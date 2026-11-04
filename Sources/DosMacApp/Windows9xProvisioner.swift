import CryptoKit
import DosMacVM
import Foundation

private final class WindowsMediaProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable
{
  let maximum: Int64
  let update: @Sendable (Int64) -> Void
  private let lock = NSLock()
  private var last = Date.distantPast
  init(maximum: Int64, update: @escaping @Sendable (Int64) -> Void) {
    self.maximum = maximum
    self.update = update
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesWritten > maximum {
      downloadTask.cancel()
      return
    }
    lock.lock()
    let notify = Date().timeIntervalSince(last) >= 1
    if notify { last = Date() }
    lock.unlock()
    if notify { update(totalBytesWritten) }
  }
}

/// Pinned media stays in the user's private cache; no OS binaries or keys ship with the app.
actor Windows9xProvisioner {
  struct Source: Sendable {
    let item: String, filename: String, cachedName: String, sha1: String
    let bytes: Int
    var url: URL {
      URL(string: "https://archive.org/download/\(item)/")!.appendingPathComponent(filename)
    }
  }
  static let boot = Source(
    item: "microsoft-windows-98-second-edition-oem-x05-29232",
    filename: "Microsoft Windows 98 Second Edition Boot Disk [X04-80322].img",
    cachedName: "windows98se-boot.img", sha1: "825b1181fa4d7711d33802f7c3c011b8816f52ab",
    bytes: 1_474_560)
  static func source(for guest: GuestSystem) -> Source {
    guest == .windows98
      ? Source(
        item: "microsoft-windows-98-second-edition-oem-x05-29232",
        filename: "Microsoft Windows 98 Second Edition OEM [X05-29232].iso",
        cachedName: "windows98se.iso", sha1: "fa040cd3f7fd472e9612b1721bc72d7b82538450",
        bytes: 655_591_424)
      : Source(
        item: "win95_202004", filename: "Win95.iso", cachedName: "windows95.iso",
        sha1: "30bcb51d56f63a3ae8946075adbc4270352d0f52", bytes: 632_123_392)
  }
  private var cache: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "DosMac/Windows9x", isDirectory: true)
  }
  private func media(_ source: Source, progress: @escaping @Sendable (String) async -> Void)
    async throws -> URL
  {
    try FileManager.default.createDirectory(
      at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let destination = cache.appendingPathComponent(source.cachedName)
    if FileManager.default.fileExists(atPath: destination.path),
      try valid(destination, source: source)
    {
      return destination
    }
    await progress("Downloading \(source.cachedName) (\(source.bytes / 1024 / 1024) MB)…")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 3600
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let delegate = WindowsMediaProgress(maximum: Int64(source.bytes)) { count in
      Task {
        await progress(
          "Downloading \(source.cachedName) · \(count * 100 / Int64(source.bytes))% (\(count / 1024 / 1024) / \(source.bytes / 1024 / 1024) MB)…"
        )
      }
    }
    let (temporary, response) = try await session.download(from: source.url, delegate: delegate)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      response.url?.scheme == "https"
    else { throw VMError.invalid("The Windows source did not return the expected HTTPS download.") }
    await progress("Verifying \(source.cachedName)…")
    guard try valid(temporary, source: source) else {
      throw VMError.invalid(
        "The Windows download failed its pinned size or SHA-1 check. No machine was changed.")
    }
    try Task.checkCancellation()
    // A failed/cancelled download never replaces a previously verified cache entry.
    let staging = cache.appendingPathComponent(".download-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: temporary, to: staging)
    defer { try? FileManager.default.removeItem(at: staging) }
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
    } else {
      try FileManager.default.moveItem(at: staging, to: destination)
    }
    return destination
  }
  private func valid(_ url: URL, source: Source) throws -> Bool {
    let info = try url.resourceValues(forKeys: [
      .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
    ])
    guard info.isSymbolicLink != true, info.isRegularFile == true, info.fileSize == source.bytes
    else { return false }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = Insecure.SHA1()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined() == source.sha1
  }
  #if os(macOS)
    func prepare(
      guest: GuestSystem, productKey: String, acceptedLicense: Bool, store: MachineStore,
      progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Machine {
      _ = try Windows9xRecipe.answerFile(
        guest: guest, productKey: productKey, acceptedLicense: acceptedLicense)
      let bootDisk = try await media(Self.boot, progress: progress)
      let iso = try await media(Self.source(for: guest), progress: progress)
      await progress("Creating a private Windows computer and preparing Setup…")
      return try await store.createWindows9x(
        guest: guest, iso: iso, bootDisk: bootDisk, productKey: productKey,
        acceptedLicense: acceptedLicense)
    }
  #endif
}
