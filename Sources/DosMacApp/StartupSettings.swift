import SwiftUI
import DosMacCore

struct StartupSettings: View {
    @ObservedObject var model: LibraryModel
    let program: InstalledProgram
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var executable = ""
    @State private var profile = MachineProfile.dos
    @State private var mode = StartupMode.program
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Text(verbatim: "Open DOS at C:\\> or start an installed program. Choosing DOS or Windows skips the floppy installer.").foregroundStyle(.secondary)
                Picker("Start in", selection: $mode) { ForEach(StartupMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                if let windows = detectedWindows {
                    Text(verbatim: "Installed Windows found: C:\\\(windows.replacingOccurrences(of: "/", with: "\\"))").font(.callout).foregroundStyle(.secondary)
                    Button("Use installed Windows") { executable = windows; profile = .windows31; mode = .program }
                }
                if mode == .program {
                    Picker("Startup program", selection: $executable) { ForEach(entries, id: \.self) { Text($0).tag($0) } }
                }
                Picker("Machine profile", selection: $profile) { ForEach(MachineProfile.allCases, id: \.self) { Text($0.title).tag($0) } }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Startup program")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await model.library?.updateStartup(program, executable: executable, profile: profile, mode: mode)
                                await model.refresh()
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled((mode == .program && executable.isEmpty) || model.running)
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 400)
        #endif
        .task {
            executable = program.manifest.executable
            profile = program.manifest.profile
            mode = program.manifest.effectiveStartupMode
            do { entries = try await model.library?.entryPoints(for: program) ?? [] }
            catch { self.error = error.localizedDescription }
        }
    }

    private var detectedWindows: String? {
        entries.first { $0.uppercased() == "WINDOWS/WIN.COM" }
            ?? entries.first { $0.split(separator: "/").last?.uppercased() == "WIN.COM" }
    }
}
