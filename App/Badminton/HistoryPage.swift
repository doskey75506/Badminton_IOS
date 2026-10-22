import SwiftUI
import BadmintonKit

// Mirrors app/.../HistoryPage.kt

private func fmtTime(_ iso: String?) -> String {
    guard let iso, let dt = DateTime.parse(iso) else { return "-" }
    return dt.timeString
}

private func fmtDuration(_ m: Match) -> String {
    guard let s = DateTime.parse(m.startedAt), let f = DateTime.parse(m.finishedAt) else { return "-" }
    let seconds = Int(f.secondsSince(s))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private func joinDeltas(_ deltas: [(String, Double)]) -> String {
    let sep = Strings.shared.lang == "zh" ? "，" : ", "
    return deltas.map { "\($0.0) " + String(format: "%+.1f", $0.1) }.joined(separator: sep)
}

private enum RangeOpt: String, CaseIterable {
    case all, today, d7, d30, custom

    var label: String {
        switch self {
        case .all: T("h_all")
        case .today: T("h_today")
        case .d7: T("h_7")
        case .d30: T("h_30")
        case .custom: T("h_custom")
        }
    }
}

struct HistoryPage: View {
    @Bindable var state: AppState
    @State private var range: RangeOpt = .all
    @State private var player = ""
    @State private var dateFrom = ""
    @State private var dateTo = ""
    @State private var showFrom = false
    @State private var showTo = false
    @State private var pickerDate = Date()

    var body: some View {
        let _ = state.revision
        let club = state.club
        let allMatches = state.storage.loadMatches(clubId: club)

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("p_history"))
                    .font(.title2)

                if allMatches.isEmpty {
                    Text(T("h_no_data"))
                        .foregroundStyle(.secondary)
                } else {
                    let namePool = Array(Set(allMatches.flatMap { $0.names.values })).sorted()

                    HStack {
                        Menu {
                            ForEach(RangeOpt.allCases, id: \.self) { opt in
                                Button(opt.label) { range = opt }
                            }
                        } label: {
                            Text("\(T("h_range")): \(range.label)")
                        }
                        .fixedSize()
                    }

                    if range == .custom {
                        HStack(spacing: 8) {
                            Button("\(T("h_from")): \(dateFrom.isEmpty ? "-" : dateFrom)") {
                                pickerDate = dateFrom.isEmpty
                                    ? (DateOnly.parse(DateOnly.adding(days: -30, to: DateOnly.today())) ?? Date())
                                    : (DateOnly.parse(dateFrom) ?? Date())
                                showFrom = true
                            }
                            .buttonStyle(.bordered)
                            Button("\(T("h_to")): \(dateTo.isEmpty ? "-" : dateTo)") {
                                pickerDate = dateTo.isEmpty ? (DateOnly.parse(DateOnly.today()) ?? Date()) : (DateOnly.parse(dateTo) ?? Date())
                                showTo = true
                            }
                            .buttonStyle(.bordered)
                        }
                        if !dateFrom.isEmpty && !dateTo.isEmpty && dateFrom > dateTo {
                            Text(T("h_range_invalid"))
                                .foregroundStyle(.red)
                        }
                    }

                    Menu {
                        Button(T("h_all_players")) { player = "" }
                        ForEach(namePool, id: \.self) { name in
                            Button(name) { player = name }
                        }
                    } label: {
                        Text("\(T("h_player")): \(player.isEmpty ? T("h_all_players") : player)")
                    }
                    .fixedSize()

                    let today = DateOnly.today()
                    let fromIso: String? = {
                        switch range {
                        case .all: return nil
                        case .today: return today
                        case .d7: return DateOnly.adding(days: -7, to: today)
                        case .d30: return DateOnly.adding(days: -30, to: today)
                        case .custom: return dateFrom.isEmpty ? nil : dateFrom
                        }
                    }()
                    let toIso: String? = {
                        switch range {
                        case .all: return nil
                        case .today: return today
                        case .d7: return nil
                        case .d30: return nil
                        case .custom: return dateTo.isEmpty ? nil : dateTo
                        }
                    }()

                    let rows = allMatches
                        .sorted { lhs, rhs in
                            if lhs.date != rhs.date { return lhs.date > rhs.date }
                            return lhs.seq > rhs.seq
                        }
                        .filter { m in
                            if let fromIso, m.date < fromIso { return false }
                            if let toIso, m.date > toIso { return false }
                            if !player.isEmpty && !m.names.values.contains(player) { return false }
                            return true
                        }

                    Text(T("h_count", ["n": rows.count]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if rows.isEmpty {
                        Text(T("h_no_data"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows, id: \.id) { m in
                            HistoryRow(m: m)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showFrom) {
            dateSheet(title: T("h_from"), isPresented: $showFrom) { dateFrom = $0 }
        }
        .sheet(isPresented: $showTo) {
            dateSheet(title: T("h_to"), isPresented: $showTo) { dateTo = $0 }
        }
    }

    @ViewBuilder
    private func dateSheet(title: String, isPresented: Binding<Bool>, onPick: @escaping (String) -> Void) -> some View {
        VStack(spacing: 16) {
            DatePicker(title, selection: $pickerDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
            Button(T("ok")) {
                onPick(DateOnly.format(pickerDate))
                isPresented.wrappedValue = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}

private func winnerLabel(_ winner: String?) -> String {
    switch winner {
    case "A": return T("team_a")
    case "B": return T("team_b")
    default: return "-"
    }
}

private struct HistoryRow: View {
    var m: Match

    var body: some View {
        let teamA = m.teamA.map { m.names[$0] ?? $0 }.joined(separator: " / ")
        let teamB = m.teamB.map { m.names[$0] ?? $0 }.joined(separator: " / ")
        let winner = winnerLabel(m.winner)
        let chg: String? = {
            let before = m.ratingsBefore
            guard !before.isEmpty, let after = m.ratingsAfter, !after.isEmpty else { return nil }
            let deltas = before.map { (pid, r) in
                (m.names[pid] ?? pid, (after[pid] ?? r) - r)
            }.sorted { $0.1 > $1.1 }
            return joinDeltas(deltas)
        }()

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(m.date) \(fmtTime(m.startedAt))–\(fmtTime(m.finishedAt))")
                    .fontWeight(.bold)
                    .font(.footnote)
                Spacer()
                Text("\(T("h_court")) \(m.court) · \(T("board_\(m.board)"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(T("team_a")): \(teamA)")
                .font(.footnote)
            Text(m.scoreA != nil ? "\(m.scoreA!) : \(m.scoreB!)" : T("ongoing"))
                .font(.headline)
                .padding(.vertical, 2)
            Text("\(T("team_b")): \(teamB)")
                .font(.footnote)
            Text("\(T("h_winner")): \(winner) · \(T("h_duration")): \(fmtDuration(m))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let chg {
                Text("\(T("h_rating_chg")): \(chg)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.vertical, 4)
    }
}
