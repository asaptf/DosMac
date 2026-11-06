import Foundation

/// One release policy shared by the UI and both execution backends.
public struct DistributionPolicy: Sendable, Equatable {
    public enum Channel: String, Sendable { case developer, appStore = "app-store" }
    public let channel: Channel
    public init(channel: Channel) { self.channel = channel }
    public static var current: Self {
        Self(channel: Bundle.main.object(forInfoDictionaryKey: "DosMacDistribution") as? String == Channel.appStore.rawValue ? .appStore : .developer)
    }
    public var allowsExternalEngines: Bool { channel == .developer }
    public var allowsNativeEngineDownloads: Bool { channel == .developer }
    public var allowsUnreviewedCatalogs: Bool { channel == .developer }
    public var allowsHostDiskMounts: Bool { channel == .developer }
}
