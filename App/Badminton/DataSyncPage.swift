import SwiftUI
import UniformTypeIdentifiers
import BadmintonKit

// Mirrors app/.../DataSyncPage.kt: export/import via the system document picker.
// Cancelling the picker (or the work) shows "Cancelled" and returns to page 0.

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DataSyncPage: View {
    @Bindable var state: AppState
    @State private var busy: String?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData: Data?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("p_sync"))
                    .font(.title2)
                    .padding(.vertical, 8)

                Text(T("sync_intro"))
                    .foregroundStyle(.secondary)

                SyncSection(
                    title: T("export_confirm_title"),
                    lines: [T("sync_export_desc")],
                    buttonLabel: T("export")
                ) {
                    do {
                        exportData = try state.storage.exportBytes()
                        showExporter = true
                    } catch {
                        state.warning = T("export_fail", ["e": "\(error)"])
                        state.bump()
                    }
                }

                SyncSection(
                    title: T("import_confirm_title"),
                    lines: [T("sync_import_desc")],
                    buttonLabel: T("import")
                ) {
                    showImporter = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: BackupDocument(data: exportData ?? Data()),
            contentType: .zip,
            defaultFilename: "badminton-backup-\(Self.stamp()).zip"
        ) { result in
            switch result {
            case .success(let url):
                state.flash = T("export_done", ["name": url.lastPathComponent])
                state.page = 0
            case .failure(let error):
                if (error as? CancellationError) != nil {
                    cancelToMainPage()
                } else {
                    state.warning = T("export_fail", ["e": "\(error)"])
                }
            }
            state.bump()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    cancelToMainPage()
                    return
                }
                runImport(url)
            case .failure(let error):
                if (error as? CancellationError) != nil {
                    cancelToMainPage()
                } else {
                    state.warning = T("import_fail", ["e": "\(error)"])
                    state.bump()
                }
            }
        }
        .overlay {
            if busy != nil {
                busyOverlay
            }
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    ProgressView()
                    Text(busy == "export" ? T("exporting") : T("importing"))
                }
                Text(T("sync_running_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(T("cancel")) {
                    importTask?.cancel()
                    busy = nil
                    cancelToMainPage()
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .frame(maxWidth: 360)
        }
    }

    private func runImport(_ url: URL) {
        busy = "import"
        importTask = Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let bytes = try Data(contentsOf: url)
                try await MainActor.run {
                    try state.storage.importBytes(bytes)
                }
                await MainActor.run {
                    state.clubId = nil
                    state.flash = T("import_done")
                    state.page = 0
                    busy = nil
                    state.bump()
                }
            } catch {
                await MainActor.run {
                    state.warning = T("import_fail", ["e": "\(error)"])
                    busy = nil
                    state.bump()
                }
            }
        }
    }

    private func cancelToMainPage() {
        state.flash = T("op_cancelled")
        state.page = 0
        state.bump()
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }
}

private struct SyncSection: View {
    var title: String
    var lines: [String]
    var buttonLabel: String
    var onClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.top, 12)
            ForEach(lines, id: \.self) { line in
                Text(line)
            }
            Button(buttonLabel, action: onClick)
                .buttonStyle(.bordered)
        }
    }
}
