import XCTest
@testable import BadmintonKit

final class MatchmakingTests: XCTestCase {
    let now = DateTime(year: 2026, month: 10, day: 9, hour: 21, minute: 0, second: 0)

    private func makeMembers(ratings: [String: Double], gender: String? = nil) -> [String: Member] {
        var out: [String: Member] = [:]
        for (pid, r) in ratings {
            out[pid] = Member(
                id: pid,
                name: pid,
                gender: gender,
                ratings: Dictionary(uniqueKeysWithValues: BOARDS.map { ($0, r) })
            )
        }
        return out
    }

    private var equal: [String: Member] {
        makeMembers(ratings: ["A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0, "E": 1000.0, "F": 1000.0])
    }

    private func match(
        _ seq: Int,
        _ teamA: [String],
        _ teamB: [String],
        started: DateTime? = nil,
        finished: DateTime? = nil,
        score: (Int, Int) = (21, 15)
    ) -> Match {
        Match(
            id: "m\(seq)",
            date: "2026-10-09",
            seq: seq,
            court: 1,
            teamA: teamA,
            teamB: teamB,
            scoreA: score.0,
            scoreB: score.1,
            winner: score.0 > score.1 ? "A" : "B",
            startedAt: started?.isoString,
            finishedAt: finished?.isoString
        )
    }

    func testRequiresFourPlayers() {
        XCTAssertNil(suggestMatch(members: equal, availableIds: ["A", "B", "C"], allMatches: [], tonightMatches: [], now: now))
    }

    func testPicksLongestRestedPlayers() {
        let tonight = [
            match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: -10), finished: now.adding(minutes: -1)),
        ]
        let result = suggestMatch(
            members: equal, availableIds: ["A", "B", "C", "D", "E", "F"],
            allMatches: [], tonightMatches: tonight, now: now
        )!
        let quad = result.teamA + result.teamB
        XCTAssertTrue(quad.contains("E") && quad.contains("F"))
        XCTAssertEqual(600.0, result.stats["E"]!.rest, accuracy: 0.001)
        XCTAssertEqual(60.0, result.stats["A"]!.rest, accuracy: 0.001)
    }

    func testPlayerStatsCountsAndRest() {
        let tonight = [
            match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: -30), finished: now.adding(minutes: -20)),
            match(1, ["A", "B"], ["E", "F"], started: now.adding(minutes: -10), finished: now.adding(minutes: -2)),
        ]
        let stats = playerStats(availableIds: ["A", "B", "C", "D", "E", "F"], tonightMatches: tonight, now: now)
        XCTAssertEqual(2, stats.played["A"]!)
        XCTAssertEqual(1, stats.played["C"]!)
        XCTAssertEqual(1, stats.played["E"]!)
        XCTAssertEqual(120.0, stats.rest["A"]!, accuracy: 0.001)
        XCTAssertEqual(1200.0, stats.rest["C"]!, accuracy: 0.001)
        XCTAssertEqual(120.0, stats.rest["E"]!, accuracy: 0.001)
    }

    func testFreshNightPrefersBalance() {
        let members = makeMembers(ratings: ["A": 800.0, "B": 820.0, "C": 1200.0, "D": 1180.0])
        let result = suggestMatch(
            members: members, availableIds: ["A", "B", "C", "D"],
            allMatches: [], tonightMatches: [], now: now
        )!
        for team in [result.teamA, result.teamB] {
            let ratings = team.map { members[$0]!.ratings["open_double"]! }.sorted()
            XCTAssertTrue(ratings[0] < 1000 && ratings[1] > 1000)
        }
        XCTAssertLessThanOrEqual(result.balance, 20.0)
    }

    func testAvoidsRepeatedPartner() {
        let history = [
            match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: -60 * 24), finished: now.adding(minutes: -60 * 24 + 20)),
        ]
        let result = suggestMatch(
            members: equal, availableIds: ["A", "B", "C", "D", "E", "F"],
            allMatches: history, tonightMatches: [], now: now
        )!
        let counts = pairCounts(history)
        for team in [result.teamA, result.teamB] {
            XCTAssertEqual(0, counts.partners[team.sorted()] ?? 0)
        }
    }

    func testExcludedQuadsAreSkipped() {
        let ids = ["A", "B", "C", "D", "E", "F"]
        let first = suggestMatch(members: equal, availableIds: ids, allMatches: [], tonightMatches: [], now: now)!
        let excluded = [Set(first.teamA + first.teamB)]
        let second = suggestMatch(
            members: equal, availableIds: ids, allMatches: [], tonightMatches: [], now: now, exclude: excluded
        )
        XCTAssertNotNil(second)
        XCTAssertFalse(excluded.contains(Set(second!.teamA + second!.teamB)))
    }

    func testMultiCourtSuggestionsAreDisjoint() {
        let eight = makeMembers(ratings: [
            "A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0,
            "E": 1000.0, "F": 1000.0, "G": 1000.0, "H": 1000.0,
        ])
        let out = suggestMatches(
            members: eight, availableIds: ["A", "B", "C", "D", "E", "F", "G", "H"],
            allMatches: [], tonightMatches: [], now: now,
            courtsBoards: [(1, "open_double"), (2, "open_double")]
        )
        XCTAssertEqual(Set([1, 2]), Set(out.keys))
        let quad1 = Set(out[1]!.teamA + out[1]!.teamB)
        let quad2 = Set(out[2]!.teamA + out[2]!.teamB)
        XCTAssertTrue(quad1.intersection(quad2).isEmpty)
        XCTAssertEqual(4, quad1.count)
        XCTAssertEqual(4, quad2.count)
    }

    func testMultiCourtStopsWhenPoolExhausted() {
        let six = makeMembers(ratings: [
            "A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0, "E": 1000.0, "F": 1000.0,
        ])
        let out = suggestMatches(
            members: six, availableIds: ["A", "B", "C", "D", "E", "F"],
            allMatches: [], tonightMatches: [], now: now,
            courtsBoards: [(1, "open_double"), (2, "open_double")]
        )
        XCTAssertEqual(Set([1]), Set(out.keys))
    }

    func testSinglesPicksTwoPlayers() {
        let members = makeMembers(ratings: ["A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0])
        let result = suggestMatch(
            members: members, availableIds: ["A", "B", "C", "D"],
            allMatches: [], tonightMatches: [], now: now, board: "open_single"
        )!
        XCTAssertEqual(1, result.teamA.count)
        XCTAssertEqual(1, result.teamB.count)
        XCTAssertEqual("open_single", result.board)
    }

    func testSinglesRequiresTwoPlayers() {
        let members = makeMembers(ratings: ["A": 1000.0])
        XCTAssertNil(suggestMatch(
            members: members, availableIds: ["A"],
            allMatches: [], tonightMatches: [], now: now, board: "open_single"
        ))
    }

    func testWomensBoardFiltersGender() {
        var members = makeMembers(ratings: [
            "A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0, "E": 1000.0, "F": 1000.0,
        ])
        for pid in ["A", "B", "C", "D"] {
            members[pid]!.gender = "f"
        }
        for pid in ["E", "F"] {
            members[pid]!.gender = "m"
        }
        let out = suggestMatches(
            members: members, availableIds: ["A", "B", "C", "D", "E", "F"],
            allMatches: [], tonightMatches: [], now: now,
            courtsBoards: [(1, "womens_double")]
        )
        XCTAssertTrue(out.keys.contains(1))
        let picked = Set(out[1]!.teamA + out[1]!.teamB)
        XCTAssertTrue(picked.isSubset(of: ["A", "B", "C", "D"]))
    }

    func testMixedBoardsSharePool() {
        var members = makeMembers(ratings: [
            "A": 1000.0, "B": 1000.0, "C": 1000.0, "D": 1000.0,
            "E": 1000.0, "F": 1000.0, "G": 1000.0, "H": 1000.0,
        ])
        for pid in ["A", "B", "C", "D"] {
            members[pid]!.gender = "f"
        }
        let out = suggestMatches(
            members: members, availableIds: ["A", "B", "C", "D", "E", "F", "G", "H"],
            allMatches: [], tonightMatches: [], now: now,
            courtsBoards: [(1, "womens_double"), (2, "open_double")]
        )
        XCTAssertEqual(Set([1, 2]), Set(out.keys))
        let q1 = Set(out[1]!.teamA + out[1]!.teamB)
        let q2 = Set(out[2]!.teamA + out[2]!.teamB)
        XCTAssertTrue(q1.isSubset(of: ["A", "B", "C", "D"]))
        XCTAssertTrue(q1.intersection(q2).isEmpty)
        XCTAssertEqual(4, q2.count)
    }

    func testSubstitutesInsufficientPool() {
        XCTAssertNil(suggestSubstitutes(
            members: equal, freeIds: ["E"],
            teamA: ["A", "B"], teamB: ["C", "D"], outgoing: ["A", "B"],
            allMatches: [], tonightMatches: [], now: now, board: "open_double"
        ))
    }

    func testSubstitutesFillsOnlyOutgoingSlots() {
        let result = suggestSubstitutes(
            members: equal, freeIds: ["E", "F"],
            teamA: ["A", "B"], teamB: ["C", "D"], outgoing: ["B"],
            allMatches: [], tonightMatches: [], now: now, board: "open_double"
        )!
        XCTAssertEqual(Set(["B"]), Set(result.keys))
        XCTAssertTrue(Set(["E", "F"]).contains(result["B"]!))
    }

    func testSubstitutesMultipleSlots() {
        let result = suggestSubstitutes(
            members: equal, freeIds: ["E", "F"],
            teamA: ["A", "B"], teamB: ["C", "D"], outgoing: ["A", "C"],
            allMatches: [], tonightMatches: [], now: now, board: "open_double"
        )!
        XCTAssertEqual(Set(["A", "C"]), Set(result.keys))
        XCTAssertEqual(Set(["E", "F"]), Set(result.values))
        XCTAssertNotEqual(result["A"]!, result["C"]!)
    }

    func testSubstitutesPicksLongestRested() {
        let tonight = [
            match(0, ["E", "F"], ["A", "B"], started: now.adding(minutes: -10), finished: now.adding(minutes: -5)),
            match(1, ["E", "C"], ["A", "D"], started: now.adding(minutes: -4), finished: now.adding(minutes: -1)),
        ]
        let result = suggestSubstitutes(
            members: equal, freeIds: ["E", "F"],
            teamA: ["A", "B"], teamB: ["C", "D"], outgoing: ["A"],
            allMatches: [], tonightMatches: tonight, now: now, board: "open_double"
        )!
        XCTAssertEqual(["A": "F"], result)
    }

    func testSubstitutesPrefersBalance() {
        let members = makeMembers(ratings: [
            "A": 800.0, "B": 800.0, "C": 1200.0,
            "D": 1200.0, "E": 1050.0, "F": 950.0,
        ])
        let result = suggestSubstitutes(
            members: members, freeIds: ["E", "F"],
            teamA: ["A", "B"], teamB: ["C", "D"], outgoing: ["A"],
            allMatches: [], tonightMatches: [], now: now, board: "open_double"
        )!
        XCTAssertEqual(["A": "E"], result)
    }

    func testCombinationsAndPermutationsBasics() {
        XCTAssertEqual(
            [["A", "B"], ["A", "C"], ["B", "C"]],
            combinations(["A", "B", "C"], 2)
        )
        XCTAssertEqual(6, permutations(["A", "B", "C"], 2).count)
        XCTAssertEqual(
            [["A", "B"], ["A", "C"], ["B", "A"]],
            Array(permutations(["A", "B", "C"], 2).prefix(3))
        )
    }

    func testRestNeverNegative() {
        let future = match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: 5), finished: now.adding(minutes: 10))
        let stats = playerStats(availableIds: ["A"], tonightMatches: [future], now: now)
        XCTAssertEqual(0.0, stats.rest["A"]!, accuracy: 0.001)
    }

    func testRestAnchorsToSessionStartWhenMatchesDeleted() {
        let session = now.adding(minutes: -5)
        let stats = playerStats(availableIds: ["A", "B"], tonightMatches: [], now: now, sessionStart: session)
        XCTAssertEqual(300.0, stats.rest["A"]!, accuracy: 0.001)
        XCTAssertEqual(300.0, stats.rest["B"]!, accuracy: 0.001)
    }

    func testSessionStartBeatsFirstStart() {
        let session = now.adding(minutes: -10)
        let active = Match(
            id: "m0", date: "2026-10-09", seq: 0, court: 1,
            teamA: ["E"], teamB: ["F"],
            startedAt: now.adding(minutes: -2).isoString
        )
        let stats = playerStats(availableIds: ["A", "B"], tonightMatches: [active], now: now, sessionStart: session)
        XCTAssertEqual(600.0, stats.rest["A"]!, accuracy: 0.001)
    }

    func testLastFinishStillWinsOverSessionStart() {
        let session = now.adding(minutes: -30)
        let finishedMatch = match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: -10), finished: now.adding(minutes: -3))
        let stats = playerStats(availableIds: ["A"], tonightMatches: [finishedMatch], now: now, sessionStart: session)
        XCTAssertEqual(180.0, stats.rest["A"]!, accuracy: 0.001)
    }

    func testDepartedPlayersRestFromSubOutTime() {
        let active = Match(
            id: "m0", date: "2026-10-09", seq: 0, court: 1,
            teamA: ["E", "B"], teamB: ["C", "D"],
            startedAt: now.adding(minutes: -20).isoString,
            departed: ["A": now.adding(minutes: -4).isoString]
        )
        let stats = playerStats(availableIds: ["A"], tonightMatches: [active], now: now)
        XCTAssertEqual(240.0, stats.rest["A"]!, accuracy: 0.001)
    }

    func testDepartedBeatsEarlierFinish() {
        let earlier = match(0, ["A", "B"], ["C", "D"], started: now.adding(minutes: -30), finished: now.adding(minutes: -25))
        let active = Match(
            id: "m1", date: "2026-10-09", seq: 1, court: 1,
            teamA: ["E", "F"], teamB: ["C", "D"],
            startedAt: now.adding(minutes: -10).isoString,
            departed: ["A": now.adding(minutes: -1).isoString]
        )
        let stats = playerStats(availableIds: ["A"], tonightMatches: [earlier, active], now: now)
        XCTAssertEqual(60.0, stats.rest["A"]!, accuracy: 0.001)
    }
}
