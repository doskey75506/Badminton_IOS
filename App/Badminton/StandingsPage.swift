import SwiftUI
import BadmintonKit

// Mirrors app/.../StandingsPage.kt

private func overallStats(_ matches: [Match]) -> [String: (played: Int, wins: Int)] {
    var stats: [String: (Int, Int)] = [:]
    for m in matches {
        if m.scoreA == nil { continue }
        let winnerTeam = Set(m.winner == "A" ? m.teamA : m.teamB)
        for pid in m.teamA + m.teamB {
            let cur = stats[pid] ?? (0, 0)
            stats[pid] = (cur.0 + 1, cur.1 + (winnerTeam.contains(pid) ? 1 : 0))
        }
    }
    return stats
}

struct StandingsPage: View {
    @Bindable var state: AppState
    @State private var board = DEFAULT_BOARD

    var body: some View {
        let _ = state.revision
        let club = state.club
        let members = state.storage.loadMembers(clubId: club)
        let finished = state.storage.loadMatches(clubId: club).filter { $0.scoreA != nil && $0.board == board }
        let stats = overallStats(finished)

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("p_standings"))
                    .font(.title2)

                Menu {
                    ForEach(BOARDS, id: \.self) { b in
                        Button(T("board_\(b)")) { board = b }
                    }
                } label: {
                    Text("\(T("board")): \(T("board_\(board)"))")
                }
                .fixedSize()
                .padding(.vertical, 8)

                if members.isEmpty {
                    Text(T("no_members"))
                        .foregroundStyle(.secondary)
                } else {
                    let visible = members.filter { genderOk($0, board) }
                    HStack {
                        Text(T("col_name")).fontWeight(.bold).frame(width: 140, alignment: .leading)
                        Text(T("rating")).fontWeight(.bold).frame(width: 80, alignment: .leading)
                        Text(T("games")).fontWeight(.bold).frame(width: 60, alignment: .leading)
                        Text(T("wins")).fontWeight(.bold).frame(width: 60, alignment: .leading)
                        Text(T("losses")).fontWeight(.bold).frame(width: 60, alignment: .leading)
                        Text(T("win_rate")).fontWeight(.bold)
                    }
                    .font(.footnote)

                    let rows = visible
                        .map { m -> (Member, Int, Int) in
                            let s = stats[m.id] ?? (0, 0)
                            return (m, s.played, s.wins)
                        }
                        .sorted { ($0.0.ratings[board] ?? 1000) > ($1.0.ratings[board] ?? 1000) }

                    ForEach(rows, id: \.0.id) { row in
                        let (m, played, wins) = row
                        HStack {
                            Text(m.name).frame(width: 140, alignment: .leading)
                            Text(String(format: "%.1f", m.ratings[board] ?? 1000)).frame(width: 80, alignment: .leading)
                            Text("\(played)").frame(width: 60, alignment: .leading)
                            Text("\(wins)").frame(width: 60, alignment: .leading)
                            Text("\(played - wins)").frame(width: 60, alignment: .leading)
                            Text(played > 0 ? String(format: "%.0f%%", Double(wins) * 100.0 / Double(played)) : "-")
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }
}
