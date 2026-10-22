import SwiftUI
import BadmintonKit

struct RootView: View {
    var state: AppState

    var body: some View {
        let _ = state.revision // subscribe to reloads
        Group {
            if state.clubs().isEmpty {
                WelcomeView(state: state)
            } else {
                MainScaffold(state: state)
            }
        }
        .onAppear { state.ensureClub() }
        .onChange(of: state.revision) { state.ensureClub() }
        .tint(.blue)
    }
}

struct MainScaffold: View {
    @Bindable var state: AppState
    @State private var showNewClub = false
    @State private var newClubName = ""

    var body: some View {
        let clubs = state.clubs()
        NavigationStack {
            TabView(selection: $state.page) {
                TonightPage(state: state)
                    .tabItem { Label(T("p_tonight"), systemImage: "list.clipboard") }
                    .tag(0)
                MembersPage(state: state)
                    .tabItem { Label(T("p_members"), systemImage: "person.2") }
                    .tag(1)
                StandingsPage(state: state)
                    .tabItem { Label(T("p_standings"), systemImage: "trophy") }
                    .tag(2)
                HistoryPage(state: state)
                    .tabItem { Label(T("p_history"), systemImage: "clock") }
                    .tag(3)
                DataSyncPage(state: state)
                    .tabItem { Label(T("p_sync"), systemImage: "arrow.triangle.2.circlepath") }
                    .tag(4)
                HelpPage(state: state)
                    .tabItem { Label(T("p_help"), systemImage: "questionmark.circle") }
                    .tag(5)
            }
            .navigationTitle(clubs.first(where: { $0.id == state.club })?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(clubs) { club in
                            Button {
                                state.clubId = club.id
                                state.bump()
                            } label: {
                                if club.id == state.club {
                                    Label(club.name, systemImage: "checkmark")
                                } else {
                                    Text(club.name)
                                }
                            }
                        }
                    } label: {
                        Text("\(T("club")): \(clubs.first(where: { $0.id == state.club })?.name ?? "") ▾")
                            .font(.footnote)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("new_club")) { showNewClub = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(state.lang == "zh" ? "EN" : "中文") {
                        state.toggleLang()
                        state.bump()
                    }
                }
            }
        }
        .alert(T("new_club"), isPresented: $showNewClub) {
            TextField(T("club_name"), text: $newClubName)
            Button(T("create")) {
                do {
                    let club = try state.storage.createClub(name: newClubName)
                    state.clubId = club.id
                    state.bump()
                    newClubName = ""
                    showNewClub = false
                } catch is DuplicateNameError {
                    state.warning = T("club_dup")
                    state.bump()
                } catch {
                    state.warning = T("club_name_invalid")
                    state.bump()
                }
            }
            Button(T("cancel"), role: .cancel) {
                newClubName = ""
            }
        }
        .overlay(alignment: .bottom) { ToastOverlay(state: state) }
    }
}

/// Checkbox toggle usable on iOS (ToggleStyle.checkbox is macOS-only).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

/// Snackbar equivalent: shows flash/warning messages, clears after a moment.
private struct ToastOverlay: View {
    var state: AppState

    var body: some View {
        let msg = state.warning.isEmpty ? state.flash : state.warning
        if !msg.isEmpty {
            Text(msg)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(state.warning.isEmpty ? Color.black.opacity(0.8) : Color.red.opacity(0.9))
                )
                .foregroundStyle(.white)
                .padding(.bottom, 70)
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if state.warning == msg {
                        state.warning = ""
                    } else if state.flash == msg {
                        state.flash = ""
                    }
                }
                .transition(.opacity)
        }
    }
}
