import XCTest
@testable import OrzuApp
import MapKit

/// JSON в тестах — ответы живого backend (GET /dating/…): модели должны разбирать именно их.
final class DatingModelsTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        ISO8601Coding.makeDecoder()
    }

    func testDecodesOwnProfile() throws {
        let json = Data("""
        {"profile":{"userId":"9ca6550c-6562-43d4-b3c5-c3102d6455a0","displayName":"Тимур","age":30,"gender":"MALE",
         "countryCode":"TJ","cityCode":"dushanbe","heightCm":180,"bio":"Люблю горы","interests":["travel","books"],
         "education":"HIGHER","profession":"Инженер","relationshipGoal":"MARRIAGE","maritalStatus":"NEVER_MARRIED",
         "children":"NONE","wantsChildren":"YES","smoking":"NEVER","alcohol":"NEVER","sport":"OFTEN",
         "cuisines":["tajik"],"hobbies":["hiking"],"photoIds":[],"videoId":null,"verified":false,
         "photos":[{"attachmentId":"p1","status":"PENDING","rejectReason":null}],"video":null,"inCouple":false,
         "birthDate":"1996-04-12","hidden":false,"visibleToOthers":false,
         "visibilityIssues":["NOT_VERIFIED","NO_APPROVED_PHOTOS"],"needsReverification":false,"hasLocation":false},
         "completeness":{"percent":87,"missing":["photos","video"]}}
        """.utf8)

        let response = try decoder().decode(MyDatingProfile.self, from: json)
        let profile = try XCTUnwrap(response.profile)

        XCTAssertEqual(profile.shared.displayName, "Тимур")
        XCTAssertEqual(profile.shared.heightCm, 180)
        XCTAssertEqual(profile.birthDate, "1996-04-12")
        XCTAssertEqual(profile.photos.first?.status, .pending)
        XCTAssertEqual(profile.visibilityIssues, [.notVerified, .noApprovedPhotos])
        XCTAssertEqual(response.completeness?.percent, 87)
    }

    func testDecodesEmptyProfile() throws {
        let json = Data(#"{"profile":null,"completeness":null}"#.utf8)

        let response = try decoder().decode(MyDatingProfile.self, from: json)

        XCTAssertNil(response.profile)
    }

    /// Карточка ленты — публичная анкета плюс совместимость, расстояние и пометки.
    func testDecodesFeedCard() throws {
        let json = Data("""
        {"cards":[{"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ",
          "cityCode":"khujand","heightCm":null,"bio":"","interests":["books"],"education":null,"profession":null,
          "relationshipGoal":"MARRIAGE","maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,
          "alcohol":null,"sport":null,"cuisines":[],"hobbies":[],"photoIds":["a1"],"videoId":null,"verified":true,
          "compatibility":{"score":72,"reasons":["Общий интерес: Книги"]},"distanceKm":12,"isNew":true,"expanded":false}],
         "limits":{"likesPerDay":7,"likesLeft":6,"introsPerDay":5,"introsLeft":5,"resetsAt":"2026-09-20T19:00:00.000Z"}}
        """.utf8)

        let feed = try decoder().decode(DatingFeed.self, from: json)
        let card = try XCTUnwrap(feed.cards.first)

        XCTAssertEqual(card.id, "u2")
        XCTAssertEqual(card.profile.photoIds, ["a1"])
        XCTAssertTrue(card.profile.verified)
        XCTAssertEqual(card.compatibility.score, 72)
        XCTAssertEqual(card.profile.distanceKm, 12)
        XCTAssertTrue(card.isNew)
        XCTAssertFalse(card.expanded)
        XCTAssertEqual(feed.limits.likesLeft, 6)
        // Старый сервер не присылает matchingCount — цифр на пустой ленте просто нет.
        XCTAssertNil(feed.matchingCount)
    }

    func testDecodesEmptyFeedMatchingCount() throws {
        let json = Data(#"{"cards":[],"matchingCount":24,"limits":{"likesPerDay":7,"likesLeft":7,"introsPerDay":5,"introsLeft":5,"resetsAt":"2026-09-20T19:00:00.000Z"}}"#.utf8)
        XCTAssertEqual(try decoder().decode(DatingFeed.self, from: json).matchingCount, 24)
    }

    /// Анкета партнёра и отправителя первого сообщения приходит с расстоянием, своя — без этого поля.
    func testPublicProfileDistance() throws {
        func profile(_ distance: String) -> Data {
            Data("""
            {"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ","cityCode":"khujand",
             "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
             "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
             "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":true\(distance)}
            """.utf8)
        }

        let near = try decoder().decode(DatingProfilePublic.self, from: profile(#","distanceKm":3"#))
        XCTAssertEqual(near.distanceText, "3 км")

        let unknown = try decoder().decode(DatingProfilePublic.self, from: profile(#","distanceKm":null"#))
        XCTAssertNil(unknown.distanceText)

        let own = try decoder().decode(DatingProfilePublic.self, from: profile(""))
        XCTAssertNil(own.distanceKm)
    }

    /// Анкета партнёра и отправителя первого сообщения приходит с расстоянием; своя — без этого поля.
    func testProfileDistanceIsOptional() throws {
        let fields = """
        "userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ","cityCode":"khujand",
        "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
        "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
        "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":true
        """
        let partner = try decoder().decode(DatingProfilePublic.self, from: Data("{\(fields),\"distanceKm\":3}".utf8))
        let own = try decoder().decode(DatingProfilePublic.self, from: Data("{\(fields)}".utf8))

        XCTAssertEqual(partner.distanceText, "3 км")
        XCTAssertNil(own.distanceKm)
        XCTAssertNil(own.distanceText)
    }

    func testDecodesMatchAndJourneyAndMeeting() throws {
        let matchJSON = Data("""
        {"id":"m1","chatId":"c1","createdAt":"2026-09-19T10:00:00.000Z","lastActivityAt":"2026-09-20T09:00:00.000Z",
         "hasMessages":true,"partner":{"userId":"u2","displayName":"Нигина","age":28,"cityCode":"khujand","photoId":"a1"}}
        """.utf8)
        let journeyJSON = Data("""
        {"matchId":"m1","stage":"ACQUAINTANCE","endedAt":null,
         "proposal":{"stage":"FIRST_MEETING","byMe":true,"at":"2026-09-20T09:30:00.000Z"},
         "history":[{"stage":"ACQUAINTANCE","reachedAt":"2026-09-19T10:00:00.000Z"}],
         "checklist":{"mine":["public_place"],"partner":[]}}
        """.utf8)
        let meetingJSON = Data("""
        {"id":"mt1","matchId":"m1","byMe":true,"startsAt":"2026-09-22T13:30:00.000Z","place":"Кафе «Рохат»",
         "note":"У входа","status":"PROPOSED","expired":false,"createdAt":"2026-09-20T09:40:00.000Z",
         "respondedAt":null,"replacedById":null,"cancelledByMe":null}
        """.utf8)

        let match = try decoder().decode(DatingMatch.self, from: matchJSON)
        let journey = try decoder().decode(JourneyView.self, from: journeyJSON)
        let meeting = try decoder().decode(DatingMeeting.self, from: meetingJSON)

        XCTAssertEqual(match.partner.displayName, "Нигина")
        XCTAssertTrue(match.hasMessages)
        XCTAssertEqual(journey.proposal?.stage, "FIRST_MEETING")
        XCTAssertEqual(journey.checklist.mine, ["public_place"])
        XCTAssertEqual(meeting.status, .proposed)
        XCTAssertNil(meeting.cancelledByMe)
    }

    func testDecodesIncomingIntro() throws {
        let json = Data("""
        {"incoming":[{"id":"i1","text":"Привет!","createdAt":"2026-09-20T09:00:00.000Z",
          "expiresAt":"2026-09-21T09:00:00.000Z","from":{"userId":"u2","displayName":"Нигина","age":28,
          "gender":"FEMALE","countryCode":"TJ","cityCode":"khujand","heightCm":null,"bio":"","interests":[],
          "education":null,"profession":null,"relationshipGoal":null,"maritalStatus":null,"children":null,
          "wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,"cuisines":[],"hobbies":[],
          "photoIds":["a1"],"videoId":null,"verified":true}}],
         "sent":[{"id":"i2","text":"Здравствуйте","createdAt":"2026-09-20T08:00:00.000Z",
          "expiresAt":"2026-09-21T08:00:00.000Z","to":{"userId":"u3","displayName":"Мадина","photoId":null}}]}
        """.utf8)

        let inbox = try decoder().decode(IntroInbox.self, from: json)

        XCTAssertEqual(inbox.incoming.first?.from.displayName, "Нигина")
        XCTAssertEqual(inbox.sent.first?.to.userId, "u3")
        XCTAssertNil(inbox.sent.first?.to.photoId)
    }

    func testDecodesCatalogAndFindsNames() throws {
        let json = Data("""
        {"journey":{"stages":[{"code":"ACQUAINTANCE","name":"Знакомство","description":"Переписываетесь","questions":["Вопрос?"]}],
          "checklist":[{"code":"public_place","name":"Встреча в людном месте"}]},
         "countries":[{"code":"TJ","name":"Таджикистан","cities":[{"code":"dushanbe","name":"Душанбе"}]}],
         "interests":[{"code":"books","name":"Книги"}],"hobbies":[],"cuisines":[],
         "genders":[{"code":"MALE","name":"Мужчина"}],"relationshipGoals":[{"code":"MARRIAGE","name":"Брак и семья"}],
         "maritalStatuses":[],"children":[],"wantsChildren":[],"education":[],"habitFrequencies":[]}
        """.utf8)

        let catalog = try decoder().decode(DatingCatalog.self, from: json)

        XCTAssertEqual(catalog.cityName(countryCode: "TJ", cityCode: "dushanbe"), "Душанбе")
        XCTAssertEqual(catalog.stage("ACQUAINTANCE")?.name, "Знакомство")
        XCTAssertEqual(catalog.relationshipGoals.name(of: "MARRIAGE"), "Брак и семья")
        // Незнакомый код не должен исчезать из интерфейса — показываем его как есть.
        XCTAssertEqual(catalog.cityName(countryCode: "TJ", cityCode: "unknown"), "unknown")
    }

    /// Незаполненное поле анкеты нельзя просто пропустить: сервер поймёт пропуск как «не менять».
    func testProfileUpdateClearsOnlyRequestedFields() throws {
        var update = DatingProfileUpdate()
        update.bio = "Обо мне"
        update.heightCm = nil
        update.education = "HIGHER"
        update.clearing = DatingProfileUpdate.allNullableKeys

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(update)) as? [String: Any])

        XCTAssertEqual(object["bio"] as? String, "Обо мне")
        XCTAssertEqual(object["education"] as? String, "HIGHER")
        XCTAssertTrue(object["heightCm"] is NSNull)
        // Пол и дата рождения задаются только при создании — иначе их вообще нет в запросе.
        XCTAssertNil(object["gender"])
        XCTAssertNil(object["birthDate"])
    }

    func testProfileUpdateSkipsUntouchedNullableFields() throws {
        var update = DatingProfileUpdate()
        update.hidden = true

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(update)) as? [String: Any])

        XCTAssertEqual(object as NSDictionary, ["hidden": true] as NSDictionary)
    }

    /// «Кого ищу» меняется частичным PATCH: сохранённые раньше поля настроек сервер должен оставить как есть.
    func testSearchSettingsSendOnlyLookingFor() throws {
        let json = Data("""
        {"lookingFor":"FEMALE","ageMin":25,"ageMax":35,"heightMin":null,"heightMax":null,"onlyMyCity":false,
         "maxDistanceKm":null,"relationshipGoals":[],"interests":[],"children":null,"wantsChildren":[],
         "habitsCompatible":false,"excludeSeen":true,"expandSearch":true}
        """.utf8)

        let settings = try decoder().decode(DatingSearchSettings.self, from: json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(settings)) as? [String: Any])

        XCTAssertEqual(settings.lookingFor, "FEMALE")
        XCTAssertEqual(object.keys.sorted(), ["lookingFor"])
    }

    func testCalendarDateRoundTrip() throws {
        let date = try XCTUnwrap(CalendarDate.date(from: "1996-04-12"))

        XCTAssertEqual(CalendarDate.string(from: date), "1996-04-12")
        XCTAssertNil(CalendarDate.date(from: "12.04.1996"))
    }

    func testDecodesVerificationStatus() throws {
        let json = Data("""
        {"verified":false,"verifiedAt":null,"reverificationRequested":false,"reverificationReason":null,
         "latest":{"id":"s1","status":"REJECTED","rejectReason":"Нужно новое селфи, а не фото из анкеты",
         "createdAt":"2026-09-20T09:00:00.000Z"}}
        """.utf8)

        let status = try decoder().decode(VerificationStatus.self, from: json)

        XCTAssertFalse(status.verified)
        XCTAssertEqual(status.latest?.status, .rejected)
        XCTAssertEqual(status.latest?.rejectReason, "Нужно новое селфи, а не фото из анкеты")
    }

    func testDecodesSelfieRequestFromModerator() throws {
        let json = Data("""
        {"verified":true,"verifiedAt":"2026-09-20T09:00:00.000Z","reverificationRequested":true,
         "reverificationReason":"Фото сильно изменились","latest":null,
         "gesture":{"code":"PEACE","emoji":"✌️","title":"Два пальца — знак V"}}
        """.utf8)

        let status = try decoder().decode(VerificationStatus.self, from: json)

        XCTAssertTrue(status.verified)
        XCTAssertTrue(status.reverificationRequested)
        XCTAssertEqual(status.reverificationReason, "Фото сильно изменились")
        XCTAssertEqual(status.gesture, SelfieGesture(code: "PEACE", emoji: "✌️", title: "Два пальца — знак V"))
    }

    func testPeopleCountDeclension() {
        XCTAssertEqual(LikedMeChip.peopleCount(1), "1 человек")
        XCTAssertEqual(LikedMeChip.peopleCount(3), "3 человека")
        XCTAssertEqual(LikedMeChip.peopleCount(5), "5 человек")
        XCTAssertEqual(LikedMeChip.peopleCount(12), "12 человек")
        XCTAssertEqual(LikedMeChip.peopleCount(22), "22 человека")
    }

    func testSingularVerbAfterCount() {
        XCTAssertEqual([1, 2, 5, 11, 21, 101, 111].map(LikedMeChip.takesSingularVerb), [true, false, false, false, true, true, false])
    }

    func testIntrosLeftDeclension() {
        func limits(_ left: Int) -> DailyLimits {
            DailyLimits(likesPerDay: 50, likesLeft: 10, introsPerDay: 5, introsLeft: left, resetsAt: Date())
        }
        XCTAssertEqual(limits(1).introsLeftText, "Сегодня можно написать ещё 1 раз. Новые — в полночь.")
        XCTAssertEqual(limits(4).introsLeftText, "Сегодня можно написать ещё 4 раза. Новые — в полночь.")
        XCTAssertEqual(limits(5).introsLeftText, "Сегодня можно написать ещё 5 раз. Новые — в полночь.")
        XCTAssertEqual(limits(12).introsLeftText, "Сегодня можно написать ещё 12 раз. Новые — в полночь.")
        XCTAssertEqual(limits(0).introsLeftText, "Сегодня сообщения закончились — новые появятся в полночь.")
    }

    // MARK: - Новые поля анкеты: старый сервер их не присылает, и разбор не должен ломаться

    private func publicProfile(_ extra: String = "") -> Data {
        Data("""
        {"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ","cityCode":"khujand",
         "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
         "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
         "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":true,"distanceKm":null\(extra)}
        """.utf8)
    }

    func testOldServerProfileHasNoNewFeatures() throws {
        let profile = try decoder().decode(DatingProfilePublic.self, from: publicProfile())

        XCTAssertNil(profile.prompts)
        XCTAssertNil(profile.voiceAttachment)
        XCTAssertNil(profile.activityStatus)
    }

    func testDecodesPromptsVoiceAndActivity() throws {
        let extra = #","prompts":[{"code":"weekend","answer":"Горы"}],"voiceId":"v1","voiceDurationSec":12,"activity":"online""#
        let profile = try decoder().decode(DatingProfilePublic.self, from: publicProfile(extra))

        XCTAssertEqual(profile.prompts?.first?.answer, "Горы")
        XCTAssertEqual(profile.voiceAttachment?.id, "v1")
        XCTAssertEqual(profile.voiceAttachment?.durationSec, 12)
        XCTAssertEqual(profile.voiceAttachment?.kind, .voice)
        XCTAssertEqual(profile.activityStatus, .online)
    }

    /// Новое значение активности на сервере не должно ломать разбор всей анкеты.
    func testUnknownActivityIsIgnored() throws {
        let profile = try decoder().decode(DatingProfilePublic.self, from: publicProfile(#","activity":"month""#))

        XCTAssertNil(profile.activityStatus)
    }

    /// Строку «Голосовое приветствие» показываем, только если сервер прислал ключ voice, пусть и null.
    func testVoiceSupportFollowsServerKey() throws {
        func mine(_ voice: String) -> Data {
            Data("""
            {"profile":{"userId":"u1","displayName":"Тимур","age":30,"gender":"MALE","countryCode":"TJ","cityCode":"dushanbe",
             "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
             "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
             "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":false,"distanceKm":null,
             "photos":[],"video":null,"inCouple":false,"birthDate":"1996-04-12","hidden":false,"visibleToOthers":false,
             "visibilityIssues":[],"needsReverification":false,"hasLocation":false\(voice)},"completeness":null}
            """.utf8)
        }

        let old = try XCTUnwrap(decoder().decode(MyDatingProfile.self, from: mine("")).profile)
        XCTAssertFalse(old.supportsVoice)

        let empty = try XCTUnwrap(decoder().decode(MyDatingProfile.self, from: mine(#","voice":null"#)).profile)
        XCTAssertTrue(empty.supportsVoice)
        XCTAssertNil(empty.voice)

        let pending = try XCTUnwrap(decoder().decode(MyDatingProfile.self, from: mine(#","voice":{"attachmentId":"v1","status":"PENDING","rejectReason":null}"#)).profile)
        XCTAssertEqual(pending.voice?.status, .pending)
    }

    /// На сервер уходят только вопрос и ответ; без prompts в обновлении ключа нет вовсе — старый сервер его бы отклонил.
    func testProfileUpdateSendsPromptsOnlyWhenSet() throws {
        var update = DatingProfileUpdate()
        update.bio = "Привет"
        let withoutPrompts = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any]
        XCTAssertNil(withoutPrompts?["prompts"])

        var answer = ProfilePromptAnswer(code: "weekend", answer: "Горы")
        answer.status = .approved
        update.prompts = [answer]
        let withPrompts = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any]
        let sent = try XCTUnwrap(withPrompts?["prompts"] as? [[String: Any]])
        XCTAssertEqual(sent.first?["code"] as? String, "weekend")
        XCTAssertEqual(sent.first?["answer"] as? String, "Горы")
        XCTAssertNil(sent.first?["status"])
    }

    /// Отмена свайпа и настройки инкогнито — только если сервер их прислал; иначе в PATCH их нет.
    func testUndoAndIncognitoAreOptional() throws {
        let limits = try decoder().decode(DailyLimits.self, from: Data(
            #"{"likesPerDay":7,"likesLeft":6,"introsPerDay":5,"introsLeft":5,"resetsAt":"2026-09-20T19:00:00.000Z"}"#.utf8
        ))
        XCTAssertNil(limits.undoLeft)

        let settings = try decoder().decode(DatingSearchSettings.self, from: Data(#"{"lookingFor":"FEMALE"}"#.utf8))
        XCTAssertNil(settings.incognito)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        XCTAssertEqual(body?.count, 1)
    }

    // MARK: - Обработка медиа на сервере

    func testAttachmentProcessingStatus() throws {
        let processing = try decoder().decode(Attachment.self, from: Data(
            #"{"id":"a1","kind":"VOICE","mimeType":"audio/mp4","fileName":"v.m4a","size":10,"durationSec":7,"status":"PROCESSING"}"#.utf8
        ))
        XCTAssertTrue(processing.isProcessing)

        let old = try decoder().decode(Attachment.self, from: Data(
            #"{"id":"a1","kind":"VOICE","mimeType":"audio/mp4","fileName":"v.m4a","size":10}"#.utf8
        ))
        XCTAssertFalse(old.isProcessing)
    }

    /// На коды медиа — свой текст на языке интерфейса, на остальные — текст сервера.
    func testMediaErrorCodesHaveOwnText() {
        XCTAssertEqual(APIError.rejected(code: "videoTooLong", message: "x").localizedDescription, "Видео слишком длинное — выберите покороче")
        XCTAssertEqual(APIError.rejected(code: "fileTooLarge", message: "x").localizedDescription, "Файл слишком большой")
        XCTAssertEqual(APIError.rejected(code: "USERNAME_TAKEN", message: "Занято").localizedDescription, "Занято")
    }
}

final class SosTrackTests: XCTestCase {
    /// Формат GET /safety/sos/:id/track: точки от старых к новым, точность может отсутствовать.
    func testDecodesTrack() throws {
        let json = #"{"alertId":"a1","points":[{"latitude":38.56,"longitude":68.78,"accuracyM":12,"recordedAt":"2026-09-28T12:00:00.000Z"},{"latitude":38.57,"longitude":68.79,"accuracyM":null,"recordedAt":"2026-09-28T12:01:00.000Z"}]}"#
        let track = try ISO8601Coding.makeDecoder().decode(SosTrack.self, from: Data(json.utf8))
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[0].accuracyM, 12)
        XCTAssertNil(track.points[1].accuracyM)
        XCTAssertLessThan(track.points[0].recordedAt, track.points[1].recordedAt)
    }

    /// Карта охватывает весь путь с запасом, а одна точка не приближается «до подъезда».
    func testRegionCoversPathWithMinimumSpan() {
        let path = [CLLocationCoordinate2D(latitude: 38.50, longitude: 68.70), CLLocationCoordinate2D(latitude: 38.60, longitude: 68.90)]
        let region = SosTrackMap.region(covering: path)
        XCTAssertEqual(region.center.latitude, 38.55, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, 68.80, accuracy: 1e-9)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0.1)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0.2)

        let single = SosTrackMap.region(covering: [CLLocationCoordinate2D(latitude: 38.5, longitude: 68.7)])
        XCTAssertEqual(single.span.latitudeDelta, SosTrackMap.minimumSpanDegrees, accuracy: 1e-12)
    }

}

/// «Кого ищу»: критерии в чужой анкете, отметки ✓/✗ и сохранение.
final class SearchCriteriaModelsTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        ISO8601Coding.makeDecoder()
    }

    /// Карточка ленты с «Кого ищу» и отметкой, подхожу ли я (ответ GET /dating/feed после ac8f9e8).
    func testDecodesSearchCriteriaOnCard() throws {
        let json = Data("""
        {"userId":"u2","displayName":"Мадина","age":26,"gender":"FEMALE","countryCode":"TJ","cityCode":"dushanbe",
         "heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,
         "maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,
         "cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":false,"distanceKm":null,
         "searchCriteria":{"lookingFor":"MALE","ageMin":27,"ageMax":35,"children":"NONE","cityCodes":["dushanbe","khujand"],"maritalStatuses":["NEVER_MARRIED"]},
         "fitsCriteria":false}
        """.utf8)
        let profile = try decoder().decode(DatingProfilePublic.self, from: json)
        let criteria = try XCTUnwrap(profile.searchCriteria)
        XCTAssertEqual(profile.fitsCriteria, false)
        XCTAssertEqual(criteria.cityCodes, ["dushanbe", "khujand"])
        XCTAssertFalse(criteria.fitsAge(26))
        XCTAssertTrue(criteria.fitsAge(27))
        XCTAssertTrue(criteria.fitsCity("khujand"))
        XCTAssertFalse(criteria.fitsCity("kulob"))
        XCTAssertTrue(criteria.fitsChildren("NONE"))
        XCTAssertFalse(criteria.fitsChildren(nil))
        // Не указанное у меня семейное положение под заданный критерий не подходит — как на сервере.
        XCTAssertFalse(criteria.fitsMaritalStatus(nil))
        XCTAssertTrue(criteria.fitsMaritalStatus("NEVER_MARRIED"))
    }

    func testCardWithoutCriteria() throws {
        let json = Data(#"{"userId":"u2","displayName":"А","age":26,"gender":"FEMALE","countryCode":"TJ","cityCode":"dushanbe","heightCm":null,"bio":"","interests":[],"education":null,"profession":null,"relationshipGoal":null,"maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,"alcohol":null,"sport":null,"cuisines":[],"hobbies":[],"photoIds":[],"videoId":null,"verified":false,"distanceKm":null,"searchCriteria":null,"fitsCriteria":null}"#.utf8)
        let profile = try decoder().decode(DatingProfilePublic.self, from: json)
        XCTAssertNil(profile.searchCriteria)
        XCTAssertNil(profile.fitsCriteria)
    }

    /// «Не важно» по детям уходит именно как null — иначе сервер оставил бы прежний выбор.
    func testCriteriaUpdateSendsNullChildren() throws {
        let update = SearchCriteriaUpdate(lookingFor: "FEMALE", ageMin: 22, ageMax: 30, children: nil, cityCodes: [], maritalStatuses: ["DIVORCED"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        XCTAssertTrue(object["children"] is NSNull)
        XCTAssertEqual(object["maritalStatuses"] as? [String], ["DIVORCED"])
    }

    func testDecodesCriteriaSettingsFromOldServer() throws {
        let json = Data(#"{"lookingFor":"FEMALE","ageMin":23,"ageMax":33,"incognito":false,"showActivity":true}"#.utf8)
        let settings = try decoder().decode(SearchCriteriaSettings.self, from: json)
        XCTAssertEqual(settings.ageMin, 23)
        XCTAssertTrue(settings.cityCodes.isEmpty)
        XCTAssertNil(settings.criteriaSetAt)
    }

    /// «Вечер рулетки» — [from, to) по часам телефона, в том числе через полночь.
    func testRouletteEveningIsLive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Dushanbe"))
        func at(_ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: 30)))
        }
        let evening = RouletteStatus.Evening(from: 20, to: 23)
        XCTAssertFalse(evening.isLive(at: try at(19), calendar: calendar))
        XCTAssertTrue(evening.isLive(at: try at(20), calendar: calendar))
        XCTAssertTrue(evening.isLive(at: try at(22), calendar: calendar))
        XCTAssertFalse(evening.isLive(at: try at(23), calendar: calendar))
        XCTAssertEqual(evening.range, "20:00–23:00")

        let overMidnight = RouletteStatus.Evening(from: 22, to: 2)
        XCTAssertTrue(overMidnight.isLive(at: try at(23), calendar: calendar))
        XCTAssertTrue(overMidnight.isLive(at: try at(1), calendar: calendar))
        XCTAssertFalse(overMidnight.isLive(at: try at(3), calendar: calendar))
        XCTAssertEqual(overMidnight.endTime, "02:00")
    }
}
