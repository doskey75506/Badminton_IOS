import Foundation

// MARK: - Constants (mirrors core/Models.kt)

public let DEFAULT_RATING = 1000.0
public let DEFAULT_COURTS = 2
public let MIN_COURTS = 1
public let MAX_COURTS = 12
public let BOARDS = ["open_single", "womens_single", "open_double", "womens_double"]
public let DEFAULT_BOARD = "open_double"

// MARK: - Persisted models
//
// JSON is compatible with the Android app (kotlinx.serialization):
// club/members/settings/matches files under the data dir, same key names.
// Custom Codable uses decodeIfPresent so missing keys fall back to defaults
// (same as kotlinx properties with defaults) and explicit-nulls are tolerated.

public struct Club: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: String

    public init(id: String, name: String, createdAt: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

public struct Member: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var gender: String?
    public var ratings: [String: Double]
    public var createdAt: String

    public init(
        id: String,
        name: String,
        gender: String? = nil,
        ratings: [String: Double] = Dictionary(uniqueKeysWithValues: BOARDS.map { ($0, DEFAULT_RATING) }),
        createdAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.ratings = ratings
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, gender, ratings, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        ratings = try c.decodeIfPresent([String: Double].self, forKey: .ratings)
            ?? Dictionary(uniqueKeysWithValues: BOARDS.map { ($0, DEFAULT_RATING) })
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

public struct Match: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: String
    public var seq: Int
    public var court: Int
    public var board: String
    public var teamA: [String]
    public var teamB: [String]
    public var names: [String: String]
    public var ratingsBefore: [String: Double]
    public var ratingsAfter: [String: Double]?
    public var scoreA: Int?
    public var scoreB: Int?
    public var winner: String?
    public var startedAt: String?
    public var finishedAt: String?
    public var departed: [String: String]

    public init(
        id: String,
        date: String,
        seq: Int,
        court: Int,
        board: String = DEFAULT_BOARD,
        teamA: [String] = [],
        teamB: [String] = [],
        names: [String: String] = [:],
        ratingsBefore: [String: Double] = [:],
        ratingsAfter: [String: Double]? = nil,
        scoreA: Int? = nil,
        scoreB: Int? = nil,
        winner: String? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        departed: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.seq = seq
        self.court = court
        self.board = board
        self.teamA = teamA
        self.teamB = teamB
        self.names = names
        self.ratingsBefore = ratingsBefore
        self.ratingsAfter = ratingsAfter
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.winner = winner
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.departed = departed
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, seq, court, board, teamA, teamB, names, ratingsBefore,
             ratingsAfter, scoreA, scoreB, winner, startedAt, finishedAt, departed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        court = try c.decodeIfPresent(Int.self, forKey: .court) ?? 1
        board = try c.decodeIfPresent(String.self, forKey: .board) ?? DEFAULT_BOARD
        teamA = try c.decodeIfPresent([String].self, forKey: .teamA) ?? []
        teamB = try c.decodeIfPresent([String].self, forKey: .teamB) ?? []
        names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        ratingsBefore = try c.decodeIfPresent([String: Double].self, forKey: .ratingsBefore) ?? [:]
        ratingsAfter = try c.decodeIfPresent([String: Double].self, forKey: .ratingsAfter)
        scoreA = try c.decodeIfPresent(Int.self, forKey: .scoreA)
        scoreB = try c.decodeIfPresent(Int.self, forKey: .scoreB)
        winner = try c.decodeIfPresent(String.self, forKey: .winner)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(String.self, forKey: .finishedAt)
        departed = try c.decodeIfPresent([String: String].self, forKey: .departed) ?? [:]
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var courts: Int
    public var nightStarts: [String: String]

    public init(courts: Int = DEFAULT_COURTS, nightStarts: [String: String] = [:]) {
        self.courts = courts
        self.nightStarts = nightStarts
    }

    private enum CodingKeys: String, CodingKey {
        case courts, nightStarts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courts = try c.decodeIfPresent(Int.self, forKey: .courts) ?? DEFAULT_COURTS
        nightStarts = try c.decodeIfPresent([String: String].self, forKey: .nightStarts) ?? [:]
    }
}

// MARK: - Transient models

public struct PlayerStats: Equatable, Sendable {
    public var played: Int
    public var rest: Double

    public init(played: Int, rest: Double) {
        self.played = played
        self.rest = rest
    }
}

public struct Suggestion: Equatable, Sendable {
    public var teamA: [String]
    public var teamB: [String]
    public var balance: Double
    public var stats: [String: PlayerStats]
    public var board: String

    public init(teamA: [String], teamB: [String], balance: Double, stats: [String: PlayerStats], board: String) {
        self.teamA = teamA
        self.teamB = teamB
        self.balance = balance
        self.stats = stats
        self.board = board
    }
}
