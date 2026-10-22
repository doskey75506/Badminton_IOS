import SwiftUI

// Mirrors app/.../HelpPage.kt

private struct HelpSection {
    let title: String
    let lines: [String]
}

struct HelpPage: View {
    var state: AppState

    var body: some View {
        let _ = state.revision
        let sections: [HelpSection] = [
            HelpSection(
                title: T("help_tonight_title"),
                lines: [
                    T("help_tonight_1"),
                    T("help_tonight_2"),
                    T("help_tonight_3"),
                    T("help_tonight_4"),
                    T("help_tonight_5"),
                    T("help_tonight_note"),
                ]
            ),
            HelpSection(
                title: T("help_members_title"),
                lines: [
                    T("help_members_1"),
                    T("help_members_2"),
                ]
            ),
            HelpSection(
                title: T("help_standings_title"),
                lines: [
                    T("help_standings_1"),
                    T("help_standings_2"),
                ]
            ),
            HelpSection(
                title: T("help_history_title"),
                lines: [
                    T("help_history_1"),
                ]
            ),
            HelpSection(
                title: T("help_lang_title"),
                lines: [
                    T("help_lang_1"),
                ]
            ),
            HelpSection(
                title: T("help_data_title"),
                lines: [
                    T("help_data_1"),
                    T("help_data_2"),
                    T("help_data_3"),
                ]
            ),
        ]

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("p_help"))
                    .font(.title2)
                    .padding(.vertical, 8)
                Text(T("help_intro"))
                    .foregroundStyle(.secondary)
                ForEach(sections, id: \.title) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title)
                            .font(.headline)
                            .padding(.top, 12)
                        ForEach(Array(s.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }
}
