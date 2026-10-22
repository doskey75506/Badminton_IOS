import SwiftUI
import BadmintonKit

struct WelcomeView: View {
    @Bindable var state: AppState
    @State private var name = ""

    var body: some View {
        let _ = state.revision
        VStack(spacing: 16) {
            Spacer()
            Text(T("welcome"))
                .font(.title2)
            TextField(T("club_name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Button(T("create")) {
                do {
                    let club = try state.storage.createClub(name: name)
                    state.clubId = club.id
                    state.bump()
                } catch is DuplicateNameError {
                    state.warning = T("club_dup")
                    state.bump()
                } catch {
                    state.warning = T("club_name_invalid")
                    state.bump()
                }
            }
            if !state.warning.isEmpty {
                Text(state.warning)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button(state.lang == "zh" ? "EN" : "中文") {
                state.toggleLang()
                state.bump()
            }
            .padding(16)
        }
    }
}
