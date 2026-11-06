import SwiftUI

struct OpenSourceNoticesView: View {
    private struct Document: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }
    private let documents: [Document] = Self.load()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Open-source software").font(.title2.bold())
                Text("DosMac is Apache-2.0 licensed. Separately licensed components retain their own terms.").foregroundStyle(.secondary)
                ForEach(documents) { document in
                    DisclosureGroup(document.title) {
                        Text(verbatim: document.text).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }
                Link("Native component source snapshot", destination: URL(string: "https://github.com/asaptf/DosMac/releases/tag/store-source-snapshot-2026-11-06-minimal")!)
                Link("Project source and notices", destination: URL(string: "https://github.com/asaptf/DosMac")!)
                Link("Privacy policy", destination: URL(string: "https://github.com/asaptf/DosMac/blob/main/docs/privacy.md")!)
                Link("Support", destination: URL(string: "https://github.com/asaptf/DosMac/blob/main/docs/support.md")!)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private static func load() -> [Document] {
        #if SWIFT_PACKAGE
        let root = Bundle.module.resourceURL?.appendingPathComponent("Resources")
        #else
        let root = Bundle.main.resourceURL
        #endif
        guard let root else { return [] }
        var files: [(String, URL)] = []
        for (title, name) in [("DosMac · Apache-2.0", "DosMac-LICENSE.txt"), ("DosMac attribution", "DosMac-NOTICE.txt"), ("Third-party notices", "THIRD-PARTY-NOTICES.md"), ("QEMouse · GPL-2.0", "QEMouse-LICENSE.txt"), ("Display agent · MIT", "Agent-LICENSE.txt")] {
            if let file = [root.appendingPathComponent(name), root.appendingPathComponent("Licenses/" + name), root.appendingPathComponent("GuestTools/" + name)].first(where: { FileManager.default.fileExists(atPath: $0.path) }) { files.append((title,file)) }
        }
        let native = root.appendingPathComponent("QEMU/Licenses")
        if let walker = FileManager.default.enumerator(at: native, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) {
            for case let file as URL in walker {
                let name = file.lastPathComponent.uppercased()
                let relative = String(file.path.dropFirst(native.path.count + 1))
                let licenseDirectory = relative.split(separator: "/").dropLast().contains { $0.uppercased() == "LICENSES" }
                if name.hasPrefix("COPYING") || name.hasPrefix("LICENSE") || name.hasPrefix("LICENCE") || name.hasPrefix("COPYRIGHT") || name.hasPrefix("NOTICE") || name == "HOMEBREW-LICENSE.TXT" || licenseDirectory {
                    files.append((relative,file))
                }
            }
        }
        return files.sorted { $0.0 < $1.0 }.compactMap { title, file in
            guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), info.isRegularFile == true, info.isSymbolicLink != true,
                  (info.fileSize ?? .max) < 1_048_576, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return Document(title: title, text: text)
        }
    }
}
