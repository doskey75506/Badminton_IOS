import XCTest
@testable import BadmintonKit

final class StorageTests: XCTestCase {
    var tmpRoot: URL!
    var storage: Storage!

    override func setUpWithError() throws {
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("badminton-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        storage = Storage(dataDir: tmpRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    private func newSubdir(_ name: String) throws -> URL {
        let url = tmpRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testClubLifecycle() throws {
        let club = try storage.createClub(name: "测试俱乐部")
        XCTAssertEqual(["测试俱乐部"], storage.listClubs().map { $0.name })
        XCTAssertThrowsError(try storage.createClub(name: "测试俱乐部")) { error in
            XCTAssertTrue(error is DuplicateNameError)
        }
        XCTAssertThrowsError(try storage.createClub(name: "   "))
        XCTAssertEqual(DEFAULT_COURTS, storage.getSettings(clubId: club.id).courts)
        try storage.setSettings(clubId: club.id, settings: Settings(courts: 5))
        XCTAssertEqual(5, storage.getSettings(clubId: club.id).courts)
    }

    func testMemberLifecycle() throws {
        let club = try storage.createClub(name: "c")
        let m = try storage.addMember(clubId: club.id, name: "张三", rating: 1200.0, gender: "f")
        XCTAssertEqual(1200.0, m.ratings["open_double"]!, accuracy: 0.0)
        XCTAssertEqual(4, m.ratings.count)
        XCTAssertThrowsError(try storage.addMember(clubId: club.id, name: "张三")) { error in
            XCTAssertTrue(error is DuplicateNameError)
        }
        XCTAssertEqual(m, storage.membersById(clubId: club.id)[m.id]!)
        try storage.deleteMember(clubId: club.id, memberId: m.id)
        XCTAssertTrue(storage.loadMembers(clubId: club.id).isEmpty)
    }

    func testMatchRoundtrip() throws {
        let club = try storage.createClub(name: "c")
        let match = try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 1,
            teamA: ["a", "b"], teamB: ["c", "d"],
            names: ["a": "甲", "b": "乙", "c": "丙", "d": "丁"],
            ratingsBefore: ["a": 1000.0, "b": 1000.0, "c": 1000.0, "d": 1000.0],
            board: "womens_double"
        )
        XCTAssertEqual(0, match.seq)
        let second = try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 2,
            teamA: ["e"], teamB: ["f"], names: [:], ratingsBefore: [:]
        )
        XCTAssertEqual(1, second.seq)
        XCTAssertEqual(2, storage.matchesOn(clubId: club.id, date: "2026-10-09").count)
        XCTAssertEqual(2, storage.activeMatches(clubId: club.id, date: "2026-10-09").count)

        try storage.finishMatch(
            clubId: club.id, matchId: match.id, scoreA: 21, scoreB: 15,
            ratingsAfter: ["a": 1010.0, "b": 1010.0, "c": 990.0, "d": 990.0]
        )
        XCTAssertEqual(1, storage.activeMatches(clubId: club.id, date: "2026-10-09").count)
        let finished = storage.matchesOn(clubId: club.id, date: "2026-10-09").first { $0.id == match.id }!
        XCTAssertEqual(21, finished.scoreA)
        XCTAssertEqual("A", finished.winner)
        XCTAssertEqual(1010.0, finished.ratingsAfter!["a"]!, accuracy: 0.0)

        XCTAssertThrowsError(try storage.cancelMatch(clubId: club.id, matchId: match.id))
        try storage.cancelMatch(clubId: club.id, matchId: second.id)
        XCTAssertEqual(1, storage.matchesOn(clubId: club.id, date: "2026-10-09").count)
    }

    func testSwapPlayers() throws {
        let club = try storage.createClub(name: "c")
        let match = try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 1,
            teamA: ["a", "b"], teamB: ["c", "d"],
            names: ["a": "甲", "b": "乙", "c": "丙", "d": "丁"],
            ratingsBefore: ["a": 1000.0, "b": 1000.0, "c": 1000.0, "d": 1000.0]
        )
        let updated = try storage.swapMatchPlayers(
            clubId: club.id, matchId: match.id,
            swaps: ["a": "e"],
            info: ["e": ("戊", 1050.0)]
        )
        XCTAssertEqual(["e", "b"], updated.teamA)
        XCTAssertEqual("戊", updated.names["e"]!)
        XCTAssertNil(updated.names["a"])
        XCTAssertEqual(1050.0, updated.ratingsBefore["e"]!, accuracy: 0.0)
        XCTAssertEqual(match.id, updated.id)
        XCTAssertEqual(match.startedAt, updated.startedAt)
        XCTAssertTrue(updated.departed.keys.contains("a"))
    }

    func testAddMatchRecordsNightStartOnce() throws {
        let club = try storage.createClub(name: "c")
        XCTAssertTrue(storage.getSettings(clubId: club.id).nightStarts.isEmpty)
        try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 1,
            teamA: ["a", "b"], teamB: ["c", "d"], names: [:], ratingsBefore: [:]
        )
        let first = storage.getSettings(clubId: club.id).nightStarts["2026-10-09"]!
        try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 2,
            teamA: ["e"], teamB: ["f"], names: [:], ratingsBefore: [:]
        )
        XCTAssertEqual(first, storage.getSettings(clubId: club.id).nightStarts["2026-10-09"]!)
        try storage.addMatch(
            clubId: club.id, date: "2026-10-10", court: 1,
            teamA: ["e"], teamB: ["f"], names: [:], ratingsBefore: [:]
        )
        XCTAssertTrue(storage.getSettings(clubId: club.id).nightStarts.keys.contains("2026-10-10"))
    }

    func testAttendanceRoundtrip() throws {
        let club = try storage.createClub(name: "c")
        let m1 = try storage.addMember(clubId: club.id, name: "甲")
        let m2 = try storage.addMember(clubId: club.id, name: "乙")
        try storage.setAttendance(clubId: club.id, date: "2026-10-09", memberIds: [m1.id, m2.id])
        XCTAssertEqual([m1.id, m2.id], storage.getAttendance(clubId: club.id, date: "2026-10-09"))
        try storage.deleteMember(clubId: club.id, memberId: m1.id)
        XCTAssertEqual([m2.id], storage.getAttendance(clubId: club.id, date: "2026-10-09"))
    }

    func testExportImportRoundtrip() throws {
        let club = try storage.createClub(name: "测试俱乐部")
        let m = try storage.addMember(clubId: club.id, name: "张三", rating: 1200.0, gender: "f")
        try storage.setSettings(clubId: club.id, settings: Settings(courts: 5))
        try storage.setAttendance(clubId: club.id, date: "2026-10-09", memberIds: [m.id])
        try storage.addMatch(
            clubId: club.id, date: "2026-10-09", court: 1,
            teamA: ["a"], teamB: ["b"], names: [:], ratingsBefore: [:]
        )

        let bytes = try storage.exportBytes()
        let fresh = Storage(dataDir: try newSubdir("fresh"))
        try fresh.importBytes(bytes)

        XCTAssertEqual(["测试俱乐部"], fresh.listClubs().map { $0.name })
        XCTAssertEqual(5, fresh.getSettings(clubId: club.id).courts)
        XCTAssertEqual(["张三"], fresh.loadMembers(clubId: club.id).map { $0.name })
        XCTAssertEqual(
            1200.0,
            fresh.membersById(clubId: club.id)[m.id]!.ratings["open_double"]!,
            accuracy: 0.0
        )
        XCTAssertEqual([m.id], fresh.getAttendance(clubId: club.id, date: "2026-10-09"))
        XCTAssertEqual(1, fresh.loadMatches(clubId: club.id).count)
        XCTAssertEqual(["测试俱乐部"], storage.listClubs().map { $0.name })
    }

    func testImportFullyOverwritesExistingData() throws {
        let src = Storage(dataDir: try newSubdir("src"))
        let club = try src.createClub(name: "来源")
        try src.addMember(clubId: club.id, name: "甲")

        let dstDir = try newSubdir("dst")
        let dst = Storage(dataDir: dstDir)
        let stale = try dst.createClub(name: "本机旧数据")
        try dst.addMember(clubId: stale.id, name: "路人")

        try dst.importBytes(try src.exportBytes())

        XCTAssertEqual(["来源"], dst.listClubs().map { $0.name })
        XCTAssertEqual(["甲"], dst.loadMembers(clubId: club.id).map { $0.name })
        XCTAssertTrue(dst.loadMembers(clubId: stale.id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("clubs/\(stale.id)").path))
    }

    func testImportRejectsInvalidBackupAndKeepsData() throws {
        let keeper = try storage.createClub(name: "keep")

        let badZip = Zip.write([Zip.Entry(name: "foo.txt", data: Data("hello".utf8))])

        let target = Storage(dataDir: try newSubdir("target"))
        _ = try target.createClub(name: "mine")
        let badInputs: [Data] = [Data(), Data("not a zip".utf8), badZip]
        for bad in badInputs {
            XCTAssertThrowsError(try target.importBytes(bad))
        }
        XCTAssertEqual(["mine"], target.listClubs().map { $0.name })

        try target.importBytes(try storage.exportBytes())
        XCTAssertEqual(["keep"], target.listClubs().map { $0.name })
        XCTAssertEqual([keeper.id], target.listClubs().map { $0.id })
    }

    func testExportWithoutDataFails() {
        XCTAssertThrowsError(try storage.exportBytes())
    }
}
