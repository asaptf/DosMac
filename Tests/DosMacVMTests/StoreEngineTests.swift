import Testing
import DosMacPlatform
@testable import DosMacVM

struct StoreEngineTests {
    @Test func storeCannotFallBackToDeveloperQEMUOrSamba() {
        #if os(macOS)
        // The SwiftPM test bundle has no embedded engines, even when Homebrew
        // engines are installed on the host running this test.
        #expect(QEMUInstallation.find(policy: .init(channel: .appStore)) == nil)
        #expect(SharedFolderServer.executable(policy: .init(channel: .appStore)) == nil)
        #endif
    }
}
