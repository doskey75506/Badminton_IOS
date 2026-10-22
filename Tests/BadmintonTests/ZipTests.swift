import XCTest
@testable import BadmintonKit

/// Zip compatibility tests: the Android app writes DEFLATE zips via
/// java.util.zip; our export writes STORED. Both must be readable.
final class ZipTests: XCTestCase {
    func testStoredRoundtrip() throws {
        let payload = Data("hello badminton".utf8)
        let out = Zip.write([
            Zip.Entry(name: "clubs.json", data: payload),
            Zip.Entry(name: "clubs/abc/members.json", data: Data("[]".utf8)),
        ])
        let entries = try Zip.read(out)
        XCTAssertEqual(2, entries.count)
        XCTAssertEqual("clubs.json", entries[0].name)
        XCTAssertEqual(payload, entries[0].data)
        XCTAssertEqual("clubs/abc/members.json", entries[1].name)
    }

    func testGarbageRejected() {
        XCTAssertThrowsError(try Zip.read(Data()))
        XCTAssertThrowsError(try Zip.read(Data("not a zip at all".utf8)))
    }

    #if os(macOS)
    func testReadsDeflateZipFromSystemZip() throws {
        // /usr/bin/zip compresses with DEFLATE — same method java.util.zip uses,
        // so this covers reading Android-created backups.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("badminton-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let clubsJSON = """
        [
          {"id": "abc1234567", "name": "测试俱乐部", "createdAt": "2026-10-09T21:00:00"}
        ]
        """
        try clubsJSON.write(to: dir.appendingPathComponent("clubs.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("clubs/abc1234567"),
            withIntermediateDirectories: true
        )
        try "[{\"long repeated payload\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]"
            .write(to: dir.appendingPathComponent("clubs/abc1234567/members.json"), atomically: true, encoding: .utf8)

        let zipURL = dir.appendingPathComponent("backup.zip")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = dir
        proc.arguments = ["-q", "-r", zipURL.path, "clubs.json", "clubs"]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(0, proc.terminationStatus)

        let bytes = try Data(contentsOf: zipURL)
        let entries = try Zip.read(bytes)
        let names = Set(entries.map { $0.name })
        XCTAssertEqual(Set(["clubs.json", "clubs/abc1234567/members.json"]), names)
        let clubsEntry = entries.first { $0.name == "clubs.json" }!
        XCTAssertEqual(clubsJSON, String(data: clubsEntry.data, encoding: .utf8))

        // End-to-end: a DEFLATE backup imports fully.
        let target = Storage(dataDir: dir.appendingPathComponent("imported"))
        try target.importBytes(bytes)
        XCTAssertEqual(["测试俱乐部"], target.listClubs().map { $0.name })
    }
    #endif
}
