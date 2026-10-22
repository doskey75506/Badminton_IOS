import Foundation

// Mirrors core/Storage.kt. JSON files under `dataDir`:
//   clubs.json
//   clubs/<id>/members.json, attendance.json, settings.json, matches.json
// Atomic writes (tmp + rename); unreadable/corrupt files fall back to defaults.

public struct StorageError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct DuplicateNameError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public final class Storage {
    public let dataDir: URL
    private let fm = FileManager.default

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    private static let jsonDecoder = JSONDecoder()

    public init(dataDir: URL) {
        self.dataDir = dataDir
    }

    // MARK: - Paths

    private var clubsFile: URL { dataDir.appendingPathComponent("clubs.json") }

    private func clubDir(_ clubId: String) -> URL {
        dataDir.appendingPathComponent("clubs").appendingPathComponent(clubId)
    }

    private func clubFile(_ clubId: String, _ name: String) -> URL {
        clubDir(clubId).appendingPathComponent("\(name).json")
    }

    private func matchesFile(_ clubId: String) -> URL {
        clubFile(clubId, "matches")
    }

    // MARK: - Low-level load/save

    private func load<T: Decodable>(_ url: URL, default defaultValue: T) -> T {
        guard fm.fileExists(atPath: url.path) else { return defaultValue }
        do {
            let data = try Data(contentsOf: url)
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            return defaultValue
        }
    }

    private func save<T: Encodable>(_ url: URL, _ data: T) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".tmp")
        let bytes = try Self.jsonEncoder.encode(data)
        try bytes.write(to: tmp, options: .atomic)
        _ = try? fm.removeItem(at: url)
        try fm.moveItem(at: tmp, to: url)
    }

    // MARK: - Clubs

    public func listClubs() -> [Club] {
        load(clubsFile, default: [Club]())
    }

    public func createClub(name: String) throws -> Club {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw StorageError("club name cannot be empty") }
        let clubs = listClubs()
        if clubs.contains(where: { $0.name == trimmed }) {
            throw DuplicateNameError("club already exists")
        }
        let club = Club(id: newId(), name: trimmed, createdAt: DateTime.now().isoString)
        try save(clubsFile, clubs + [club])
        return club
    }

    // MARK: - Settings

    public func getSettings(clubId: String) -> Settings {
        load(clubFile(clubId, "settings"), default: Settings())
    }

    public func setSettings(clubId: String, settings: Settings) throws {
        try save(clubFile(clubId, "settings"), settings)
    }

    // MARK: - Members

    public func loadMembers(clubId: String) -> [Member] {
        load(clubFile(clubId, "members"), default: [Member]())
    }

    public func saveMembers(clubId: String, members: [Member]) throws {
        try save(clubFile(clubId, "members"), members)
    }

    @discardableResult
    public func addMember(clubId: String, name: String, rating: Double? = nil, gender: String? = nil) throws -> Member {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw StorageError("member name cannot be empty") }
        var members = loadMembers(clubId: clubId)
        if members.contains(where: { $0.name == trimmed }) {
            throw DuplicateNameError("member already exists")
        }
        let r = rating ?? DEFAULT_RATING
        let member = Member(
            id: newId(),
            name: trimmed,
            gender: gender,
            ratings: Dictionary(uniqueKeysWithValues: BOARDS.map { ($0, r) }),
            createdAt: DateTime.now().isoString
        )
        members.append(member)
        try saveMembers(clubId: clubId, members: members)
        return member
    }

    public func deleteMember(clubId: String, memberId: String) throws {
        try saveMembers(clubId: clubId, members: loadMembers(clubId: clubId).filter { $0.id != memberId })
        let attendance = loadAttendance(clubId: clubId).mapValues { $0.filter { $0 != memberId } }
        try saveAttendance(clubId: clubId, attendance: attendance)
    }

    public func membersById(clubId: String) -> [String: Member] {
        Dictionary(uniqueKeysWithValues: loadMembers(clubId: clubId).map { ($0.id, $0) })
    }

    // MARK: - Matches

    public func loadMatches(clubId: String) -> [Match] {
        load(matchesFile(clubId), default: [Match]())
    }

    public func saveMatches(clubId: String, matches: [Match]) throws {
        try save(matchesFile(clubId), matches)
    }

    @discardableResult
    public func addMatch(
        clubId: String,
        date: String,
        court: Int,
        teamA: [String],
        teamB: [String],
        names: [String: String],
        ratingsBefore: [String: Double],
        board: String = DEFAULT_BOARD
    ) throws -> Match {
        let matches = loadMatches(clubId: clubId)
        let sameDay = matches.filter { $0.date == date }
        let seq = (sameDay.map { $0.seq }.max() ?? -1) + 1
        let now = DateTime.now().isoString
        var settings = getSettings(clubId: clubId)
        if settings.nightStarts[date] == nil {
            settings.nightStarts[date] = now
            try setSettings(clubId: clubId, settings: settings)
        }
        let match = Match(
            id: newId(),
            date: date,
            seq: seq,
            court: court,
            board: board,
            teamA: teamA,
            teamB: teamB,
            names: names,
            ratingsBefore: ratingsBefore,
            startedAt: now
        )
        try saveMatches(clubId: clubId, matches: matches + [match])
        return match
    }

    public func finishMatch(
        clubId: String,
        matchId: String,
        scoreA: Int,
        scoreB: Int,
        ratingsAfter: [String: Double]
    ) throws {
        var matches = loadMatches(clubId: clubId)
        for i in matches.indices where matches[i].id == matchId {
            matches[i].scoreA = scoreA
            matches[i].scoreB = scoreB
            matches[i].winner = scoreA > scoreB ? "A" : "B"
            matches[i].ratingsAfter = ratingsAfter
            matches[i].finishedAt = DateTime.now().isoString
        }
        try saveMatches(clubId: clubId, matches: matches)
    }

    @discardableResult
    public func swapMatchPlayers(
        clubId: String,
        matchId: String,
        swaps: [String: String],
        info: [String: (String, Double)]
    ) throws -> Match {
        var matches = loadMatches(clubId: clubId)
        guard let idx = matches.firstIndex(where: { $0.id == matchId }) else {
            throw StorageError("match not found")
        }
        var m = matches[idx]
        guard m.scoreA == nil else { throw StorageError("cannot swap a finished match") }
        guard !swaps.isEmpty else { throw StorageError("no players to swap") }
        for outPid in swaps.keys {
            guard m.teamA.contains(outPid) || m.teamB.contains(outPid) else {
                throw StorageError("player not in match")
            }
        }
        for inPid in swaps.values {
            guard !m.teamA.contains(inPid) && !m.teamB.contains(inPid) else {
                throw StorageError("player already in match")
            }
        }
        let leftAt = DateTime.now().isoString
        for (outPid, inPid) in swaps {
            if let pos = m.teamA.firstIndex(of: outPid) { m.teamA[pos] = inPid }
            if let pos = m.teamB.firstIndex(of: outPid) { m.teamB[pos] = inPid }
            m.names.removeValue(forKey: outPid)
            m.ratingsBefore.removeValue(forKey: outPid)
            let (name, rating) = info[inPid]!
            m.names[inPid] = name
            m.ratingsBefore[inPid] = rating
            m.departed[outPid] = leftAt
        }
        matches[idx] = m
        try saveMatches(clubId: clubId, matches: matches)
        return m
    }

    public func cancelMatch(clubId: String, matchId: String) throws {
        let matches = loadMatches(clubId: clubId)
        guard let target = matches.first(where: { $0.id == matchId }) else {
            throw StorageError("match not found")
        }
        guard target.scoreA == nil else { throw StorageError("cannot cancel a finished match") }
        try saveMatches(clubId: clubId, matches: matches.filter { $0.id != matchId })
    }

    public func activeMatches(clubId: String, date: String) -> [Match] {
        loadMatches(clubId: clubId).filter { $0.date == date && $0.scoreA == nil }
    }

    public func matchesOn(clubId: String, date: String) -> [Match] {
        loadMatches(clubId: clubId).filter { $0.date == date }
    }

    // MARK: - Attendance

    public func loadAttendance(clubId: String) -> [String: [String]] {
        load(clubFile(clubId, "attendance"), default: [String: [String]]())
    }

    public func saveAttendance(clubId: String, attendance: [String: [String]]) throws {
        try save(clubFile(clubId, "attendance"), attendance)
    }

    public func getAttendance(clubId: String, date: String) -> [String] {
        loadAttendance(clubId: clubId)[date] ?? []
    }

    public func setAttendance(clubId: String, date: String, memberIds: [String]) throws {
        var attendance = loadAttendance(clubId: clubId)
        attendance[date] = memberIds
        try saveAttendance(clubId: clubId, attendance: attendance)
    }

    // MARK: - Backup (zip of the whole data dir; import fully overwrites)

    public func exportBytes() throws -> Data {
        let base = dataDir.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: base.appendingPathComponent("clubs.json").path) else {
            throw StorageError("no data to export")
        }
        let basePrefix = base.path + "/"
        var files: [(String, URL)] = []
        if let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in en {
                let resolved = url.resolvingSymlinksInPath()
                let path = resolved.path
                guard path.hasPrefix(basePrefix) else { continue }
                let isFile = (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                guard isFile else { continue }
                if resolved.lastPathComponent.hasSuffix(".tmp") { continue }
                let rel = String(path.dropFirst(basePrefix.count))
                files.append((rel, resolved))
            }
        }
        files.sort { $0.0 < $1.0 }
        var entries: [Zip.Entry] = []
        for (rel, url) in files {
            guard let data = try? Data(contentsOf: url) else { continue }
            entries.append(Zip.Entry(name: rel, data: data))
        }
        return Zip.write(entries)
    }

    public func importBytes(_ bytes: Data) throws {
        guard let parent = dataDir.deletingLastPathComponent().path as String?,
              !parent.isEmpty else {
            throw StorageError("no data directory")
        }
        let parentURL = dataDir.deletingLastPathComponent()
        let stage = parentURL.appendingPathComponent(dataDir.lastPathComponent + ".import")
        let old = parentURL.appendingPathComponent(dataDir.lastPathComponent + ".old")
        do {
            if fm.fileExists(atPath: stage.path) { try? fm.removeItem(at: stage) }
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try extractAndValidate(bytes, stage: stage)
            if fm.fileExists(atPath: old.path) { try? fm.removeItem(at: old) }
            var movedOld = false
            if fm.fileExists(atPath: dataDir.path) {
                try fm.moveItem(at: dataDir, to: old)
                movedOld = true
            }
            if fm.fileExists(atPath: dataDir.path) {
                throw StorageError("cannot replace existing data")
            }
            do {
                try fm.moveItem(at: stage, to: dataDir)
            } catch {
                if movedOld { try? fm.moveItem(at: old, to: dataDir) }
                throw error
            }
            try? fm.removeItem(at: old)
        } catch let e as StorageError {
            try? fm.removeItem(at: stage)
            throw e
        } catch let e as DuplicateNameError {
            try? fm.removeItem(at: stage)
            throw e
        } catch {
            try? fm.removeItem(at: stage)
            throw StorageError("cannot import backup: \(error)")
        }
    }

    private func extractAndValidate(_ bytes: Data, stage: URL) throws {
        let entries: [Zip.Entry]
        do {
            entries = try Zip.read(bytes)
        } catch {
            throw StorageError("cannot import backup")
        }
        if entries.isEmpty { throw StorageError("not a backup archive") }
        let rootPath = stage.standardizedFileURL.path
        var files = 0
        for entry in entries {
            if entry.name.hasSuffix("/") { continue } // directory
            let out = stage.appendingPathComponent(entry.name)
            let outPath = out.standardizedFileURL.path
            guard outPath.hasPrefix(rootPath + "/") else {
                throw StorageError("invalid path in backup")
            }
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: out)
            files += 1
        }
        if files == 0 { throw StorageError("not a backup archive") }
        let clubsFile = stage.appendingPathComponent("clubs.json")
        guard fm.fileExists(atPath: clubsFile.path) else {
            throw StorageError("backup is missing clubs.json")
        }
        guard let data = try? Data(contentsOf: clubsFile),
              let clubs = try? Self.jsonDecoder.decode([Club].self, from: data),
              !clubs.isEmpty else {
            throw StorageError("backup contains no clubs")
        }
    }

    // MARK: - Helpers

    /// Kotlin UUID.randomUUID().toString().take(10)
    private func newId() -> String {
        String(UUID().uuidString.lowercased().prefix(10))
    }
}
