import SwiftUI
import BadmintonKit

// Mirrors app/.../TonightPage.kt

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

struct TonightPage: View {
    @Bindable var state: AppState
    @State private var dateIso = DateOnly.today()
    @State private var courtsText = ""
    @State private var showDatePicker = false
    @State private var pickerDate = Date()

    var body: some View {
        let _ = state.revision
        let club = state.club
        let settings = state.storage.getSettings(clubId: club)
        let sessionStart = settings.nightStarts[dateIso].flatMap { DateTime.parse($0) }
        let nCourts = (Int(courtsText) ?? settings.courts).clamped(to: MIN_COURTS...MAX_COURTS)

        let members = state.storage.membersById(clubId: club)
        let tonight = state.storage.matchesOn(clubId: club, date: dateIso)
        let activeList = state.storage.activeMatches(clubId: club, date: dateIso)
        let activeByCourt = Dictionary(uniqueKeysWithValues: activeList.map { ($0.court, $0) })
        let onCourt = Set(activeList.flatMap { $0.teamA + $0.teamB })

        let checked = members.isEmpty ? [] : state.storage.getAttendance(clubId: club, date: dateIso)
        let available = checked.filter { !onCourt.contains($0) }
        let now = DateTime.now()
        let ordered = members.values.sorted { $0.name < $1.name }

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Date + courts
                HStack(spacing: 8) {
                    Button("\(T("date")): \(dateIso)") {
                        pickerDate = DateOnly.parse(dateIso) ?? Date()
                        showDatePicker = true
                    }
                    .buttonStyle(.bordered)
                    TextField(T("courts"), text: $courtsText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 160)
                        .onChange(of: courtsText) { _, newValue in
                            let filtered = String(newValue.filter { $0.isNumber }.prefix(2))
                            if filtered != newValue { courtsText = filtered }
                            if let n = Int(filtered), (MIN_COURTS...MAX_COURTS).contains(n), n != settings.courts {
                                var s = settings
                                s.courts = n
                                try? state.storage.setSettings(clubId: club, settings: s)
                                state.bump()
                            }
                        }
                }
                .padding(.vertical, 4)

                // Attendance
                Text(T("attendance"))
                    .font(.headline)

                if members.isEmpty {
                    Text(T("no_members_tonight"))
                        .foregroundStyle(.secondary)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 220), spacing: 4)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                        ForEach(ordered, id: \.id) { m in
                            let r = String(format: "%.0f", m.ratings[DEFAULT_BOARD] ?? 1000.0)
                            Toggle(isOn: Binding(
                                get: { checked.contains(m.id) },
                                set: { on in
                                    var ids = checked
                                    if on {
                                        if !ids.contains(m.id) { ids.append(m.id) }
                                    } else {
                                        ids.removeAll { $0 == m.id }
                                    }
                                    try? state.storage.setAttendance(clubId: club, date: dateIso, memberIds: ids)
                                    state.bump()
                                }
                            )) {
                                Text(T("member_chip", ["n": m.name, "r": r]))
                                    .font(.footnote)
                            }
                            .toggleStyle(CheckboxToggleStyle())
                        }
                    }
                }

                if !checked.isEmpty {
                    let stats = playerStats(availableIds: checked, tonightMatches: tonight, now: now, sessionStart: sessionStart)
                    let activeCourt = activeByCourt.values.reduce(into: [String: Int]()) { acc, m in
                        for pid in m.teamA + m.teamB { acc[pid] = m.court }
                    }

                    Text(T("attendance_summary", ["n": checked.count, "on": onCourt.count]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(T("col_name")).fontWeight(.bold).frame(width: 140, alignment: .leading)
                            Text(T("col_games")).fontWeight(.bold).frame(width: 80, alignment: .leading)
                            Text(T("col_rest")).fontWeight(.bold).frame(width: 110, alignment: .leading)
                            Text(T("col_court")).fontWeight(.bold)
                        }
                        .font(.footnote)
                        ForEach(checked.sorted { (stats.rest[$0] ?? 0) > (stats.rest[$1] ?? 0) }, id: \.self) { pid in
                            let name = members[pid]?.name ?? pid
                            let courtLabel = activeCourt[pid].map(String.init) ?? T("rest")
                            HStack {
                                Text(name).frame(width: 140, alignment: .leading)
                                Text("\(stats.played[pid] ?? 0)").frame(width: 80, alignment: .leading)
                                Text(String(format: "%.1f", (stats.rest[pid] ?? 0) / 60)).frame(width: 110, alignment: .leading)
                                Text(courtLabel)
                            }
                            .font(.footnote)
                        }
                    }
                }

                // Generate
                let needGen = (1...nCourts).filter { activeByCourt[$0] == nil }
                Button {
                    let boards = needGen.map { ($0, state.boardSelection[$0] ?? DEFAULT_BOARD) }
                    let sugs = suggestMatches(
                        members: members,
                        availableIds: available,
                        allMatches: state.storage.loadMatches(clubId: club),
                        tonightMatches: tonight,
                        now: now,
                        courtsBoards: boards,
                        sessionStart: sessionStart
                    )
                    if sugs.isEmpty {
                        state.warning = T("not_enough_players")
                    } else {
                        for (court, pairing) in sugs {
                            let ids = pairing.teamA + pairing.teamB
                            let names = Dictionary(uniqueKeysWithValues: ids.map { ($0, members[$0]?.name ?? $0) })
                            let before = Dictionary(uniqueKeysWithValues: ids.map { ($0, members[$0]?.ratings[pairing.board] ?? 1000.0) })
                            try? state.storage.addMatch(
                                clubId: club, date: dateIso, court: court,
                                teamA: pairing.teamA, teamB: pairing.teamB,
                                names: names, ratingsBefore: before,
                                board: pairing.board
                            )
                        }
                        state.flash = T("match_started")
                    }
                    state.bump()
                } label: {
                    Text(T("gen_all", ["n": needGen.count]))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(needGen.isEmpty)
                .padding(.vertical, 4)

                // Court cards
                let maxCourt = max(nCourts, activeByCourt.keys.max() ?? 0)
                ForEach(Array(1...maxCourt), id: \.self) { courtNo in
                    CourtCard(
                        state: state,
                        courtNo: courtNo,
                        active: activeByCourt[courtNo],
                        members: members,
                        dateIso: dateIso,
                        checked: checked,
                        onCourt: onCourt,
                        tonight: tonight,
                        sessionStart: sessionStart
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .onAppear {
            if courtsText.isEmpty {
                courtsText = String(state.storage.getSettings(clubId: club).courts)
            }
        }
        .onChange(of: settings.courts) { _, newValue in
            courtsText = String(newValue)
        }
        .sheet(isPresented: $showDatePicker) {
            VStack(spacing: 16) {
                DatePicker(
                    T("date"),
                    selection: $pickerDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                Button(T("ok")) {
                    dateIso = DateOnly.format(pickerDate)
                    showDatePicker = false
                    state.bump()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationDetents([.medium, .large])
        }
    }
}

private struct CourtCard: View {
    var state: AppState
    var courtNo: Int
    var active: Match?
    var members: [String: Member]
    var dateIso: String
    var checked: [String]
    var onCourt: Set<String>
    var tonight: [Match]
    var sessionStart: DateTime?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(T("court")) \(courtNo)")
                .fontWeight(.bold)
            if let active {
                ActiveMatch(
                    state: state,
                    active: active,
                    members: members,
                    dateIso: dateIso,
                    checked: checked,
                    onCourt: onCourt,
                    tonight: tonight,
                    sessionStart: sessionStart
                )
                .id("\(active.id)#\(state.revision)") // reset per-match UI state on changes, like Android remember(revision, id)
            } else {
                BoardPicker(state: state, courtNo: courtNo)
                Text(T("court_free"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.vertical, 4)
    }
}

private struct BoardPicker: View {
    var state: AppState
    var courtNo: Int

    var body: some View {
        let selected = state.boardSelection[courtNo] ?? DEFAULT_BOARD
        Menu {
            ForEach(BOARDS, id: \.self) { b in
                Button(T("board_\(b)")) {
                    state.boardSelection[courtNo] = b
                }
            }
        } label: {
            Text("\(T("board")): \(T("board_\(selected)"))")
                .buttonStyle(.borderless)
        }

        .fixedSize()
    }
}

private struct ActiveMatch: View {
    var state: AppState
    var active: Match
    var members: [String: Member]
    var dateIso: String
    var checked: [String]
    var onCourt: Set<String>
    var tonight: [Match]
    var sessionStart: DateTime?
    @State private var subTicked: Set<String> = []

    var body: some View {
        let club = state.club

        Text(T("board_\(active.board)"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        Text(T("running_at", ["t": fmtTime(active.startedAt)]))
            .font(.footnote)
            .foregroundStyle(.secondary)

        HStack(alignment: .top, spacing: 8) {
            teamColumn(label: T("team_a"), team: active.teamA)
            teamColumn(label: T("team_b"), team: active.teamB)
        }

        if !active.ratingsBefore.isEmpty {
            let balance = abs(
                active.teamA.reduce(0.0) { $0 + (active.ratingsBefore[$1] ?? 0) } -
                    active.teamB.reduce(0.0) { $0 + (active.ratingsBefore[$1] ?? 0) }
            )
            Text(T("balance", ["n": Int(balance)]))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        ScoreForm(state: state, active: active)

        let onCourtNow = active.teamA + active.teamB
        let othersUsed = onCourt.subtracting(Set(onCourtNow))
        let board = active.board
        let pool = checked.filter {
            !othersUsed.contains($0) && !onCourtNow.contains($0) && genderOk(members[$0], board)
        }
        let ticked = subTicked.filter { onCourtNow.contains($0) }

        if pool.count < max(ticked.count, 1) {
            Text(T("no_spare"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
            Button(T("swap")) {
                let mapping = suggestSubstitutes(
                    members: members,
                    freeIds: pool,
                    teamA: active.teamA,
                    teamB: active.teamB,
                    outgoing: Array(ticked),
                    allMatches: state.storage.loadMatches(clubId: club),
                    tonightMatches: tonight,
                    now: DateTime.now(),
                    board: board,
                    sessionStart: sessionStart
                )
                if let mapping {
                    let info = Dictionary(uniqueKeysWithValues: mapping.values.map {
                        ($0, (members[$0]?.name ?? $0, members[$0]?.ratings[board] ?? 1000.0))
                    })
                    try? state.storage.swapMatchPlayers(clubId: club, matchId: active.id, swaps: mapping, info: info)
                    let sep = Strings.shared.lang == "zh" ? "、" : ", "
                    state.flash = T("swapped", [
                        "out": mapping.keys.map { members[$0]?.name ?? $0 }.joined(separator: sep),
                        "new": mapping.values.map { members[$0]?.name ?? $0 }.joined(separator: sep),
                    ])
                    subTicked = []
                } else {
                    state.warning = T("no_spare")
                }
                state.bump()
            }
            .buttonStyle(.borderedProminent)
            .disabled(ticked.isEmpty || pool.count < ticked.count)

            Button(T("cancel_match")) {
                try? state.storage.cancelMatch(clubId: club, matchId: active.id)
                state.flash = T("match_cancelled")
                state.bump()
            }
            .buttonStyle(.bordered)
        }
    }

    private func teamColumn(label: String, team: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
            ForEach(team, id: \.self) { pid in
                let name = active.names[pid] ?? members[pid]?.name ?? pid
                let rating = active.ratingsBefore[pid]
                Toggle(isOn: Binding(
                    get: { subTicked.contains(pid) },
                    set: { on in
                        if on { subTicked.insert(pid) } else { subTicked.remove(pid) }
                    }
                )) {
                    Text(rating != nil ? "\(name) — \(Int(rating!))" : name)
                        .font(.footnote)
                }
                .toggleStyle(CheckboxToggleStyle())
            }
            if !active.ratingsBefore.isEmpty {
                let total = team.reduce(0.0) { $0 + (active.ratingsBefore[$1] ?? 0) }
                Text(T("total_rating", ["r": Int(total)]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoreForm: View {
    var state: AppState
    var active: Match
    @State private var scoreA = ""
    @State private var scoreB = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("A", text: $scoreA)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(maxWidth: 90)
                .onChange(of: scoreA) { _, v in
                    scoreA = String(v.filter { $0.isNumber }.prefix(2))
                }
            TextField("B", text: $scoreB)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(maxWidth: 90)
                .onChange(of: scoreB) { _, v in
                    scoreB = String(v.filter { $0.isNumber }.prefix(2))
                }
            Button(T("submit_score")) {
                submit()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        let club = state.club
        guard let a = Int(scoreA), let b = Int(scoreB) else {
            state.warning = T("score_invalid")
            state.bump()
            return
        }
        if a == b {
            state.warning = T("score_tie")
            state.bump()
            return
        }
        let after: [String: Double]
        do {
            after = try applyResult(
                ratingsBefore: active.ratingsBefore,
                teamA: active.teamA,
                teamB: active.teamB,
                scoreA: a,
                scoreB: b
            )
        } catch {
            state.warning = T("score_range")
            state.bump()
            return
        }
        try? state.storage.finishMatch(clubId: club, matchId: active.id, scoreA: a, scoreB: b, ratingsAfter: after)
        var allMembers = state.storage.loadMembers(clubId: club)
        for i in allMembers.indices {
            if let delta = after[allMembers[i].id], allMembers[i].ratings[active.board] != nil {
                allMembers[i].ratings[active.board] = delta
            }
        }
        try? state.storage.saveMembers(clubId: club, members: allMembers)
        let deltas = after.map { (pid, r) in
            (active.names[pid] ?? pid, r - (active.ratingsBefore[pid] ?? r))
        }.sorted { $0.1 > $1.1 }
        let winner = a > b ? T("team_a") : T("team_b")
        state.flash = T("score_saved", ["a": a, "b": b, "w": winner, "changes": joinDeltas(deltas)])
        state.bump()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
