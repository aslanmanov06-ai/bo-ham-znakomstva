import XCTest
@testable import OrzuApp

final class ResponseCachePolicyTests: XCTestCase {
    func testCachesScreensButNotSearchOrOlderPages() {
        XCTAssertTrue(APIClient.isCacheable(path: "/chats"))
        XCTAssertTrue(APIClient.isCacheable(path: "/chats/c1/messages"))
        // Настройки поиска знакомств — обычный экран, а не поисковый запрос.
        XCTAssertTrue(APIClient.isCacheable(path: "/dating/search-settings"))

        XCTAssertFalse(APIClient.isCacheable(path: "/users/search?q=%D0%B0%D0%BB%D0%B8"))
        XCTAssertFalse(APIClient.isCacheable(path: "/chats/c1/messages/search?q=hi"))
        XCTAssertFalse(APIClient.isCacheable(path: "/dating/search?username=alisa"))
        XCTAssertFalse(APIClient.isCacheable(path: "/chats/c1/messages?before=2026-09-21T10:00:00.000Z"))
        // Первая страница сетки анкет (с фильтрами) — сохраняется для офлайна, следующие — нет.
        XCTAssertTrue(APIClient.isCacheable(path: "/dating/browse?cityCode=khujand"))
        XCTAssertFalse(APIClient.isCacheable(path: "/dating/browse?cityCode=khujand&cursor=2026-06-01T00:00:00.000Z_u1"))
    }
}

final class RateLimitTests: XCTestCase {
    /// Заголовок Retry-After главнее тела; без обоих — пауза по умолчанию, но никогда не ноль.
    func testRetryAfterPrefersHeaderThenBody() {
        XCTAssertEqual(APIClient.retryAfter(header: "12", bodySeconds: 40), 12)
        XCTAssertEqual(APIClient.retryAfter(header: nil, bodySeconds: 40), 40)
        XCTAssertEqual(APIClient.retryAfter(header: "Wed, 21 Oct 2026 07:28:00 GMT", bodySeconds: 7), 7)
        XCTAssertEqual(APIClient.retryAfter(header: nil, bodySeconds: nil), 30)
        XCTAssertEqual(APIClient.retryAfter(header: "0", bodySeconds: nil), 1)
    }

    /// «Код уже отправлен» сервер отдаёт как 429 с reason — экран регистрации узнаёт его по code.
    func testRateLimitedCodeIsReasonOrGeneric() {
        let codeSent = APIError.rateLimited(retryAfter: 45, reason: ServerErrorCode.codeAlreadySent, message: "Код уже отправлен")
        XCTAssertEqual(codeSent.code, ServerErrorCode.codeAlreadySent)
        XCTAssertEqual(codeSent.retryAfter, 45)
        XCTAssertFalse(codeSent.isTransient)

        let generic = APIError.rateLimited(retryAfter: 5, reason: nil, message: "Слишком часто")
        XCTAssertEqual(generic.code, ServerErrorCode.rateLimited)
        XCTAssertEqual(generic.errorDescription, "Слишком часто")
        XCTAssertNil(APIError.offline.retryAfter)
    }
}

final class UploadStatusTests: XCTestCase {
    /// 409 — файл уже принят прошлой попыткой: это успех, complete вернёт вложение.
    func testSuccessAndAlreadyReceived() {
        XCTAssertNoThrow(try APIClient.checkUploadStatus(200))
        XCTAssertNoThrow(try APIClient.checkUploadStatus(409))
    }

    /// Истёкшая ссылка и сбой сервера — повторяемые: очередь возьмёт новую ссылку, а не выбросит сообщение.
    func testExpiredLinkAndServerFailureAreTransient() {
        for status in [403, 404, 500, 503] {
            XCTAssertThrowsError(try APIClient.checkUploadStatus(status)) { error in
                XCTAssertEqual((error as? APIError)?.isTransient, true, "статус \(status)")
            }
        }
    }

    /// Отказ по существу (например, файл больше заявленного) повтором не лечится.
    func testRejectionIsFinal() {
        XCTAssertThrowsError(try APIClient.checkUploadStatus(400)) { error in
            XCTAssertEqual((error as? APIError)?.isTransient, false)
        }
    }
}
