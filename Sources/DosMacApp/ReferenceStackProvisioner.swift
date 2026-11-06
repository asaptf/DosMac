import Foundation
import DosMacPlatform
import DosMacCore
import DosMacVM

/// Downloads user-requested source media into a new, isolated machine; never publishes OS images.
enum ReferenceStackProvisioner {
    static let recipeID = "dos622-win31-word6-en-v1"
    static let sources: [(MediaPurpose, String, String, String)] = [
        (.dosSetup, "MS-DOS 6.22", "https://winworldpc.com/download/c38fc38d-68c2-bbe2-80a6-4b11c3a4c2ac", "54de77786837e152a8211dd20308cddfe4ff9ed4ba5f0d151f58e588b32eaa7e26cb470157859441c3a1d7f29755055673dc4a6c2b1279afb0fdc2cd09940d04"),
        (.windowsSetup, "Windows 3.1 Retail", "https://winworldpc.com/download/41574932-18c3-9a11-c3a4-e284a2c3a570", "5ecc69587430a2921a8e3607396ab0a89036abc810a839a8cf0457ece98c28c0b363775e8b1e1cffe26f475f53856e2a6d223e5c95b097b6ffddaf277042a203"),
        (.wordSetup, "Word 6.0 for Windows", "https://winworldpc.com/download/57ce7cd2-479c-11ee-b57b-0200008a0da4", "85a48cacdbc20ba5ffd373144d821824afcaee50")
    ]

    #if os(macOS)
    @MainActor static func prepare(store: MachineStore, onCreate: (Machine) async -> Void, progress: @escaping (String) -> Void) async throws -> Machine {
        guard DistributionPolicy.current.allowsUnreviewedCatalogs else { throw VMError.invalid("Import your own installation media in this edition.") }
        var machine = try await store.create(name: "DOS 6.22 · Windows 3.1 · Word 6", guest: .windows31)
        machine.installation = InstallationRecord(recipeID: recipeID, message: "Preparing installation media…")
        try await store.save(machine)
        await onCreate(machine)
        let service = SoftwareSources()
        do {
            for (purpose, title, address, checksum) in sources {
                try Task.checkCancellation(); progress("Downloading and verifying \(title)…")
                guard let release = try await service.inspect(URL(string: address)!).first else { throw VMError.invalid("The \(title) release is unavailable.") }
                guard (release.sha512 ?? release.sha1) == checksum else { throw VMError.invalid("The \(title) source has changed. This recipe needs review before downloading replacement media.") }
                let prepared = try await service.prepare(release)
                do {
                    guard !prepared.floppyDisks.isEmpty else { throw VMError.invalid("The \(title) source did not contain the expected raw floppy images.") }
                    let urls = prepared.floppyDisks.map { prepared.package.appendingPathComponent("payload").appendingPathComponent($0.imagePath) }
                    machine = try await store.importMedia(urls, into: machine, cdrom: false, purpose: purpose, names: prepared.floppyDisks.map(\.label))
                } catch { await service.discard(prepared); throw error }
                await service.discard(prepared)
            }
            machine.installation?.message = "All three disk sets are ready. The DOS installation assistant can start."
            try await store.save(machine)
            return machine
        } catch {
            machine.installation?.message = "Media preparation stopped: \(error.localizedDescription)"
            machine.installation?.needsAttention = true
            try? await store.save(machine)
            throw error
        }
    }
    #endif
}
