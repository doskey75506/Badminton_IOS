import SwiftUI
import BadmintonKit

// Mirrors app/.../MembersPage.kt

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

struct MembersPage: View {
    @Bindable var state: AppState
    @State private var name = ""
    @State private var genderIdx = 0
    @State private var ratingText = "1000"

    private func genderLabel(_ gender: String?) -> String {
        switch gender {
        case "m": return T("gender_male")
        case "f": return T("gender_female")
        default: return T("gender_unspecified")
        }
    }

    var body: some View {
        let _ = state.revision
        let club = state.club
        let members = state.storage.loadMembers(clubId: club)
        let stats = overallStats(state.storage.loadMatches(clubId: club))

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("p_members"))
                    .font(.title2)

                VStack(spacing: 8) {
                    TextField(T("name"), text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        let genders = [
                            T("gender_male"),
                            T("gender_female"),
                            T("gender_unspecified"),
                        ]
                        ForEach(Array(genders.enumerated()), id: \.offset) { i, label in
                            Button {
                                genderIdx = i
                            } label: {
                                Text(label)
                                    .fontWeight(genderIdx == i ? .bold : .regular)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(genderIdx == i ? Color.accentColor : Color.clear)
                                    )
                                    .foregroundStyle(genderIdx == i ? .white : .primary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    TextField(T("initial_rating"), text: $ratingText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .onChange(of: ratingText) { _, v in
                            let filtered = String(v.filter { $0.isNumber || $0 == "." }.prefix(6))
                            if filtered != v { ratingText = filtered }
                        }

                    Button(T("add_member")) {
                        addMember()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)

                if members.isEmpty {
                    Text(T("no_members"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(T("member_list", ["n": members.count]))
                        .font(.headline)
                    let sorted = members.sorted { ($0.ratings[DEFAULT_BOARD] ?? 1000) > ($1.ratings[DEFAULT_BOARD] ?? 1000) }
                    ForEach(sorted, id: \.id) { m in
                        let s = stats[m.id] ?? (0, 0)
                        let gl = genderLabel(m.gender)
                        HStack {
                            Text("\(m.name)（\(gl)）")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(T("rating")) \(Int(m.ratings[DEFAULT_BOARD] ?? 1000))")
                                .font(.footnote)
                            Text("\(T("games")) \(s.played)")
                                .font(.footnote)
                            Text(T("w_l", ["w": s.wins, "l": s.played - s.wins]))
                                .font(.footnote)
                            Button(T("delete")) {
                                try? state.storage.deleteMember(clubId: club, memberId: m.id)
                                state.bump()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }

    private func addMember() {
        let club = state.club
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            state.warning = T("name_empty")
            state.bump()
            return
        }
        let gender: String?
        switch genderIdx {
        case 0: gender = "m"
        case 1: gender = "f"
        default: gender = nil
        }
        let r = Double(ratingText) ?? 1000.0
        do {
            let m = try state.storage.addMember(clubId: club, name: trimmed, rating: r, gender: gender)
            state.flash = T("member_added", [
                "n": m.name,
                "r": String(format: "%.0f", m.ratings[DEFAULT_BOARD] ?? 1000.0),
            ])
            name = ""
            state.bump()
        } catch is DuplicateNameError {
            state.warning = T("name_dup", ["n": trimmed])
            state.bump()
        } catch {
            state.warning = T("name_empty")
            state.bump()
        }
    }
}
