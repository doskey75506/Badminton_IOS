import Foundation

// Mirrors core/Matchmaking.kt

public let BALANCE_TOLERANCE = 100.0
public let REST_TOLERANCE = 60.0

public func restSeconds(
    availableIds: [String],
    tonightMatches: [Match],
    now: DateTime,
    sessionStart: DateTime? = nil
) -> [String: Double] {
    var firstStart: DateTime?
    var leftCourt: [String: DateTime] = [:]
    func markLeft(_ pid: String, _ at: DateTime) {
        if let cur = leftCourt[pid], cur >= at { return }
        leftCourt[pid] = at
    }
    for m in tonightMatches.sorted(by: { $0.seq < $1.seq }) {
        let started = DateTime.parse(m.startedAt)
        if let started, let fs = firstStart, started < fs {
            firstStart = started
        } else if let started, firstStart == nil {
            firstStart = started
        }
        if let finished = DateTime.parse(m.finishedAt) {
            for pid in m.teamA + m.teamB { markLeft(pid, finished) }
        }
        for (pid, ts) in m.departed {
            guard let t = DateTime.parse(ts) else { continue }
            markLeft(pid, t)
        }
    }
    var rest: [String: Double] = [:]
    for pid in availableIds {
        let t0 = leftCourt[pid] ?? sessionStart ?? firstStart ?? now
        rest[pid] = max(0.0, now.secondsSince(t0))
    }
    return rest
}

public func playerStats(
    availableIds: [String],
    tonightMatches: [Match],
    now: DateTime,
    sessionStart: DateTime? = nil
) -> (played: [String: Int], rest: [String: Double]) {
    var played: [String: Int] = [:]
    for pid in availableIds { played[pid] = 0 }
    for m in tonightMatches {
        for pid in m.teamA + m.teamB {
            if played[pid] != nil { played[pid] = played[pid]! + 1 }
        }
    }
    return (played, restSeconds(availableIds: availableIds, tonightMatches: tonightMatches, now: now, sessionStart: sessionStart))
}

/// Keys are sorted player-id pairs, matching Kotlin's sorted List<String> map keys.
public func pairCounts(_ allMatches: [Match]) -> (partners: [[String]: Int], opponents: [[String]: Int]) {
    var partners: [[String]: Int] = [:]
    var opponents: [[String]: Int] = [:]
    for m in allMatches {
        for team in [m.teamA, m.teamB] {
            let sorted = team.sorted()
            for i in sorted.indices {
                for j in (i + 1)..<sorted.count {
                    let key = [sorted[i], sorted[j]]
                    partners[key, default: 0] += 1
                }
            }
        }
        for a in m.teamA {
            for b in m.teamB {
                let key = [a, b].sorted()
                opponents[key, default: 0] += 1
            }
        }
    }
    return (partners, opponents)
}

public func genderOk(_ member: Member?, _ board: String) -> Bool {
    if !board.hasPrefix("womens") { return true }
    return member?.gender == "f"
}

private func teamRating(_ members: [String: Member], _ team: [String], _ board: String) -> Double {
    team.reduce(0.0) { $0 + (members[$1]?.ratings[board] ?? DEFAULT_RATING) }
}

private func pairingsOf(_ quad: [String]) -> [([String], [String])] {
    let a = quad[0], b = quad[1], c = quad[2], d = quad[3]
    return [
        ([a, b], [c, d]),
        ([a, c], [b, d]),
        ([a, d], [b, c]),
    ]
}

/// Lexicographic comparison over heterogeneous keys (Int or [String] elements),
/// ported from Kotlin's compareKeys/compareValues.
private func compareValuesAny(_ a: Any, _ b: Any) -> Int {
    if let la = a as? [String], let lb = b as? [String] {
        for i in la.indices {
            if i >= lb.count { return 1 }
            if la[i] != lb[i] { return la[i] < lb[i] ? -1 : 1 }
        }
        if la.count == lb.count { return 0 }
        return la.count > lb.count ? 1 : -1
    }
    if let ia = a as? Int, let ib = b as? Int {
        if ia == ib { return 0 }
        return ia < ib ? -1 : 1
    }
    if let da = a as? Double, let ib = b as? Double {
        if da == ib { return 0 }
        return da < ib ? -1 : 1
    }
    return 0
}

private func compareKeys(_ a: [Any], _ b: [Any]) -> Int {
    for i in a.indices {
        let cmp = compareValuesAny(a[i], b[i])
        if cmp != 0 { return cmp }
    }
    return 0
}

public func suggestMatch(
    members: [String: Member],
    availableIds: [String],
    allMatches: [Match],
    tonightMatches: [Match],
    now: DateTime,
    exclude: [Set<String>] = [],
    board: String = DEFAULT_BOARD,
    sessionStart: DateTime? = nil
) -> Suggestion? {
    let isSingle = board.hasSuffix("single")
    let need = isSingle ? 2 : 4
    if availableIds.count < need { return nil }

    let stats = playerStats(availableIds: availableIds, tonightMatches: tonightMatches, now: now, sessionStart: sessionStart)
    let played = stats.played
    let rest = stats.rest
    let counts = pairCounts(allMatches)
    let partners = counts.partners
    let opponents = counts.opponents
    let topSum = rest.values.sorted(by: >).prefix(need).reduce(0.0, +)
    let restSpan = REST_TOLERANCE * Double(need)

    var best: [Any]?
    var bestTeamA: [String] = []
    var bestTeamB: [String] = []
    var bestBalance = 0.0

    for group in combinations(availableIds.sorted(), need) {
        if exclude.contains(Set(group)) { continue }
        let groupRest = group.reduce(0.0) { $0 + (rest[$1] ?? 0.0) }
        let restBucket = Int((topSum - groupRest) / restSpan) // truncates toward zero, like Kotlin toInt()

        var bestPairingKey: [Any]?
        var pairTeamA: [String] = []
        var pairTeamB: [String] = []
        var pairBalance = 0.0

        let pairings: [([String], [String])] = isSingle
            ? [([group[0]], [group[1]])]
            : pairingsOf(group)

        for (teamA, teamB) in pairings {
            let balance = abs(teamRating(members, teamA, board) - teamRating(members, teamB, board))
            let balanceBucket = Int(ceil(balance / BALANCE_TOLERANCE))
            let pairRep = (partners[teamA.sorted()] ?? 0) + (partners[teamB.sorted()] ?? 0)
            var oppRep = 0
            for a in teamA {
                for b in teamB {
                    oppRep += opponents[[a, b].sorted()] ?? 0
                }
            }
            let key: [Any] = [balanceBucket, pairRep, oppRep, teamA, teamB]
            if let bpk = bestPairingKey, compareValuesArray(key, bpk) >= 0 { continue }
            bestPairingKey = key
            pairTeamA = teamA
            pairTeamB = teamB
            pairBalance = balance
        }

        guard let bestPairingKey else { continue }
        let fullKey: [Any] = [restBucket] + bestPairingKey
        if let b = best, compareValuesArray(fullKey, b) >= 0 { continue }
        best = fullKey
        bestTeamA = pairTeamA
        bestTeamB = pairTeamB
        bestBalance = pairBalance
    }

    guard best != nil else { return nil }
    var statsOut: [String: PlayerStats] = [:]
    for it in availableIds {
        statsOut[it] = PlayerStats(played: played[it] ?? 0, rest: rest[it] ?? 0.0)
    }
    return Suggestion(teamA: bestTeamA, teamB: bestTeamB, balance: bestBalance, stats: statsOut, board: board)
}

public func suggestMatches(
    members: [String: Member],
    availableIds: [String],
    allMatches: [Match],
    tonightMatches: [Match],
    now: DateTime,
    courtsBoards: [(Int, String)],
    sessionStart: DateTime? = nil
) -> [Int: Suggestion] {
    var out: [Int: Suggestion] = [:]
    var pool = availableIds
    for (court, board) in courtsBoards {
        let genderPool = pool.filter { genderOk(members[$0], board) }
        guard let suggestion = suggestMatch(
            members: members,
            availableIds: genderPool,
            allMatches: allMatches,
            tonightMatches: tonightMatches,
            now: now,
            board: board,
            sessionStart: sessionStart
        ) else { continue }
        out[court] = suggestion
        let used = Set(suggestion.teamA + suggestion.teamB)
        pool = pool.filter { !used.contains($0) }
    }
    return out
}

public func suggestSubstitutes(
    members: [String: Member],
    freeIds: [String],
    teamA: [String],
    teamB: [String],
    outgoing: [String],
    allMatches: [Match],
    tonightMatches: [Match],
    now: DateTime,
    board: String,
    sessionStart: DateTime? = nil
) -> [String: String]? {
    let outgoingSet = Set(outgoing)
    var slots: [(String, Int)] = []
    for (i, p) in teamA.enumerated() where outgoingSet.contains(p) {
        slots.append(("a", i))
    }
    for (i, p) in teamB.enumerated() where outgoingSet.contains(p) {
        slots.append(("b", i))
    }
    let slotPids = (teamA + teamB).filter { outgoingSet.contains($0) }
    let free = freeIds
    let need = slots.count
    if need == 0 || free.count < need { return nil }

    let stats = playerStats(availableIds: free, tonightMatches: tonightMatches, now: now, sessionStart: sessionStart)
    let rest = stats.rest
    let counts = pairCounts(allMatches)
    let partners = counts.partners
    let opponents = counts.opponents
    let topSum = free.map { rest[$0] ?? 0.0 }.sorted(by: >).prefix(need).reduce(0.0, +)
    let restSpan = REST_TOLERANCE * Double(need)
    let rating = free.reduce(into: [String: Double]()) { $0[$1] = members[$1]?.ratings[board] ?? DEFAULT_RATING }
    let keptA = teamA.filter { !outgoingSet.contains($0) }.reduce(0.0) { $0 + (members[$1]?.ratings[board] ?? DEFAULT_RATING) }
    let keptB = teamB.filter { !outgoingSet.contains($0) }.reduce(0.0) { $0 + (members[$1]?.ratings[board] ?? DEFAULT_RATING) }

    var best: [Any]?
    var bestCombo: [String] = []

    for combo in permutations(free, need) {
        var newA = teamA
        var newB = teamB
        for (k, slot) in slots.enumerated() {
            if slot.0 == "a" { newA[slot.1] = combo[k] }
            else { newB[slot.1] = combo[k] }
        }
        let addA = slots.enumerated().filter { $0.element.0 == "a" }.map { combo[$0.offset] }
        let addB = slots.enumerated().filter { $0.element.0 == "b" }.map { combo[$0.offset] }
        let comboRest = combo.reduce(0.0) { $0 + (rest[$1] ?? 0.0) }
        let restBucket = Int((topSum - comboRest) / restSpan)
        let balance = abs(keptA + addA.reduce(0.0) { $0 + rating[$1]! } - keptB - addB.reduce(0.0) { $0 + rating[$1]! })
        let balanceBucket = Int(ceil(balance / BALANCE_TOLERANCE))
        let pairRep = (partners[newA.sorted()] ?? 0) + (partners[newB.sorted()] ?? 0)
        var oppRep = 0
        for a in newA {
            for b in newB {
                oppRep += opponents[[a, b].sorted()] ?? 0
            }
        }
        let key: [Any] = [restBucket, balanceBucket, pairRep, oppRep, combo]
        if let b = best, compareValuesArray(key, b) >= 0 { continue }
        best = key
        bestCombo = combo
    }

    guard best != nil else { return nil }
    var result: [String: String] = [:]
    for (k, pid) in slotPids.enumerated() {
        result[pid] = bestCombo[k]
    }
    return result
}

private func compareValuesArray(_ a: [Any], _ b: [Any]) -> Int {
    for i in a.indices {
        let cmp = compareValuesAny(a[i], b[i])
        if cmp != 0 { return cmp }
    }
    return 0
}

public func combinations<T>(_ items: [T], _ k: Int) -> [[T]] {
    if k == 0 { return [[]] }
    if items.count < k { return [] }
    var result: [[T]] = []
    func rec(_ start: Int, _ acc: [T]) {
        if acc.count == k {
            result.append(acc)
            return
        }
        if start >= items.count { return }
        for i in start..<items.count {
            rec(i + 1, acc + [items[i]])
        }
    }
    rec(0, [])
    return result
}

public func permutations<T>(_ items: [T], _ k: Int) -> [[T]] {
    var result: [[T]] = []
    func rec(_ used: inout [Bool], _ acc: [T]) {
        if acc.count == k {
            result.append(acc)
            return
        }
        for i in items.indices {
            if used[i] { continue }
            used[i] = true
            rec(&used, acc + [items[i]])
            used[i] = false
        }
    }
    var used = [Bool](repeating: false, count: items.count)
    rec(&used, [])
    return result
}
