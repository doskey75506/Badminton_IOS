import XCTest
@testable import BadmintonKit

final class RatingsTests: XCTestCase {
    func testWinnerGainsAndDeltasSumToZero() {
        let before = ["A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0]
        let after = try! applyResult(ratingsBefore: before, teamA: ["A", "B"], teamB: ["C", "D"], scoreA: 21, scoreB: 15)
        for p in ["A", "B"] {
            XCTAssertGreaterThan(after[p]!, before[p]!)
        }
        for p in ["C", "D"] {
            XCTAssertLessThan(after[p]!, before[p]!)
        }
        let totalBefore = before.values.reduce(0, +)
        let totalAfter = after.values.reduce(0, +)
        XCTAssertEqual(0.0, ((totalAfter - totalBefore) * 1e6).rounded() / 1e6, accuracy: 0.0)
    }

    func testExpectedScoreSymmetry() {
        XCTAssertEqual(
            1 - expectedScore(ratingA: 1200.0, ratingB: 1000.0),
            expectedScore(ratingA: 1000.0, ratingB: 1200.0),
            accuracy: 1e-9
        )
    }

    func testTieRejected() {
        XCTAssertThrowsError(
            try applyResult(ratingsBefore: ["A": 1000.0, "B": 1000.0], teamA: ["A"], teamB: ["B"], scoreA: 21, scoreB: 21)
        )
    }

    func testScoreOutOfRangeRejected() {
        XCTAssertThrowsError(
            try applyResult(ratingsBefore: ["A": 1000.0, "B": 1000.0], teamA: ["A"], teamB: ["B"], scoreA: 31, scoreB: 20)
        )
    }

    func testBiggerMarginBiggerChange() {
        let before = ["A": 1000.0, "B": 1000.0]
        let close = try! applyResult(ratingsBefore: before, teamA: ["A"], teamB: ["B"], scoreA: 21, scoreB: 20)
        let blowout = try! applyResult(ratingsBefore: before, teamA: ["A"], teamB: ["B"], scoreA: 21, scoreB: 5)
        XCTAssertGreaterThan(blowout["A"]! - before["A"]!, close["A"]! - before["A"]!)
    }

    func testUpsetWinAwardsMore() {
        let before = ["A": 900.0, "B": 1100.0]
        let after = try! applyResult(ratingsBefore: before, teamA: ["A"], teamB: ["B"], scoreA: 21, scoreB: 18)
        XCTAssertGreaterThan(after["A"]! - before["A"]!, 0)
    }
}
