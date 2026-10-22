import Foundation

// Mirrors core/Ratings.kt

public let K_FACTOR = 32.0

public struct RatingError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public func expectedScore(ratingA: Double, ratingB: Double) -> Double {
    1.0 / (1.0 + pow(10.0, (ratingB - ratingA) / 400.0))
}

public func marginMultiplier(scoreA: Int, scoreB: Int, ratingA: Double, ratingB: Double) -> Double {
    let pointDiff = abs(scoreA - scoreB)
    let eloDiff = abs(ratingA - ratingB)
    let mult = log(Double(pointDiff + 1)) * (2.2 / (eloDiff * 0.001 + 2.2))
    return max(1.0, min(2.0, mult))
}

public func applyResult(
    ratingsBefore: [String: Double],
    teamA: [String],
    teamB: [String],
    scoreA: Int,
    scoreB: Int
) throws -> [String: Double] {
    if scoreA == scoreB { throw RatingError("tie") }
    if min(scoreA, scoreB) < 0 || max(scoreA, scoreB) > 30 { throw RatingError("range") }
    if teamA.isEmpty || teamB.isEmpty { throw RatingError("empty") }

    let ratingA = teamA.reduce(0.0) { $0 + (ratingsBefore[$1] ?? DEFAULT_RATING) }
    let ratingB = teamB.reduce(0.0) { $0 + (ratingsBefore[$1] ?? DEFAULT_RATING) }
    let expA = expectedScore(ratingA: ratingA, ratingB: ratingB)
    let actualA: Double = scoreA > scoreB ? 1.0 : 0.0
    let mult = marginMultiplier(scoreA: scoreA, scoreB: scoreB, ratingA: ratingA, ratingB: ratingB)

    let deltaA = K_FACTOR * (actualA - expA) * mult
    var ratingsAfter: [String: Double] = [:]
    for p in teamA {
        ratingsAfter[p] = round1((ratingsBefore[p] ?? DEFAULT_RATING) + deltaA)
    }
    for p in teamB {
        ratingsAfter[p] = round1((ratingsBefore[p] ?? DEFAULT_RATING) - deltaA)
    }
    for p in ratingsAfter.keys {
        ratingsAfter[p] = max(0.0, ratingsAfter[p]!)
    }
    return ratingsAfter
}

private func round1(_ v: Double) -> Double {
    (v * 10.0).rounded() / 10.0
}
