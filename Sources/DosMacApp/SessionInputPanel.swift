import SwiftUI

struct SessionInputPanel: View {
    let showEmulator: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mouse & keyboard", systemImage: "computermouse").font(.headline)
                Spacer()
                Button("Show emulator", action: showEmulator)
            }
            Text("Click inside the DOSBox-X screen to capture the mouse. This is required by the standard Windows 3.1 mouse driver, including graphical Setup.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Release the mouse: Ctrl + F10 (Ctrl + Fn + F10 on some Mac keyboards). You can also use Main → Capture mouse in DOSBox-X. Tab, arrow keys, Space, and Enter remain available in Setup.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}
