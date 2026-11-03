import SwiftUI
import DosMacCore

struct StartupSettings: View {
    @ObservedObject var model: LibraryModel
    let program: InstalledProgram
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var executable = ""
    @State private var profile = MachineProfile.dos
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Text("After a guest installer finishes, choose the installed program on its C: drive here.").foregroundStyle(.secondary)
                Picker("Startup program", selection: $executable) { ForEach(entries, id: \.self) { Text($0).tag($0) } }
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
                                try await model.library?.updateStartup(program, executable: executable, profile: profile)
                                await model.refresh()
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(executable.isEmpty || model.running)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 300)
        #endif
        .task {
            executable = program.manifest.executable
            profile = program.manifest.profile
            do { entries = try await model.library?.entryPoints(for: program) ?? [] }
            catch { self.error = error.localizedDescription }
        }
    }
}
