import XCTest
@testable import OrzuApp

/// Решение по жесту в ленте: что засчитывается как лайк или пропуск, а что возвращает карточку на место.
final class SwipeDirectionTests: XCTestCase {
    private let threshold: CGFloat = 110

    func testCardReleasedPastThresholdCounts() {
        XCTAssertEqual(SwipeDirection.decide(predictedEndX: 180, threshold: threshold), .like)
        XCTAssertEqual(SwipeDirection.decide(predictedEndX: -180, threshold: threshold), .skip)
    }

    func testExactThresholdCounts() {
        XCTAssertEqual(SwipeDirection.decide(predictedEndX: threshold, threshold: threshold), .like)
        XCTAssertEqual(SwipeDirection.decide(predictedEndX: -threshold, threshold: threshold), .skip)
    }

    func testShortDragReturnsCard() {
        XCTAssertNil(SwipeDirection.decide(predictedEndX: 0, threshold: threshold))
        XCTAssertNil(SwipeDirection.decide(predictedEndX: 60, threshold: threshold))
        XCTAssertNil(SwipeDirection.decide(predictedEndX: -109, threshold: threshold))
    }

    /// Палец увёл карточку за порог и резко отдёрнул назад — по инерции она окажется у центра, свайп отменяется.
    func testFlickBackCancelsSwipe() {
        XCTAssertNil(SwipeDirection.decide(predictedEndX: 20, threshold: threshold))
    }
}
