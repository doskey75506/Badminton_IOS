import Foundation
import Observation
import BadmintonKit

// Mirrors MainActivity.kt AppState: single observable UI state.
// After mutating storage you MUST call bump() so pages reload.
@MainActor
@Observable
final class AppState {
    let storage: Storage
    var lang: String
    var clubId: String?
    var page = 0
    var flash = ""
    var warning = ""
    var revision = 0
    /// Per-court match-type selection on the Tonight page (survives page switches,
    /// like the Android app's global mutableStateMap).
    var boardSelection: [Int: String] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dataDir = support.appendingPathComponent("data")
        storage = Storage(dataDir: dataDir)
        let saved = UserDefaults.standard.string(forKey: "lang") ?? "en"
        lang = saved == "zh" ? "zh" : "en"
        Strings.shared.lang = lang
    }

    func bump() {
        revision += 1
    }

    func switchLang(_ value: String) {
        lang = value == "zh" ? "zh" : "en"
        Strings.shared.lang = lang
        UserDefaults.standard.set(lang, forKey: "lang")
    }

    func toggleLang() {
        switchLang(lang == "zh" ? "en" : "zh")
    }

    func clubs() -> [Club] {
        storage.listClubs()
    }

    func ensureClub() {
        let list = clubs()
        if list.isEmpty {
            clubId = nil
        } else if !list.map({ $0.id }).contains(clubId ?? "") {
            clubId = list[0].id
        }
    }

    var club: String { clubId ?? "" }
}
