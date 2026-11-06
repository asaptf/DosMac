import Foundation
import DosMacPlatform

/// A partitioned FAT16 disk, understood by DOS 6.x and Windows 3.x/9x without drivers.
public enum SharedDiskImage {
  public static let filename = "SharedDisk.img"
  public static func make() -> Data {
    let sectors = 131072
    let start = 63
    let volumeSectors = sectors - start
    var disk = Data(repeating: 0, count: sectors * 512)
    // Single non-bootable 64 MiB FAT16 primary partition, with standard CHS geometry.
    disk[447] = 1
    disk[448] = 1
    disk[450] = 0x06
    disk[451] = 0
    disk[452] = 32
    disk[453] = 130
    disk.putLE32(UInt32(start), at: 454)
    disk.putLE32(UInt32(volumeSectors), at: 458)
    disk[510] = 0x55
    disk[511] = 0xaa
    let b = start * 512
    disk.replaceSubrange(b..<(b + 3), with: [0xeb, 0x3c, 0x90])
    disk.replaceSubrange((b + 3)..<(b + 11), with: Data("DOSMAC  ".utf8))
    disk.putLE16(512, at: b + 11)
    disk[b + 13] = 4
    disk.putLE16(1, at: b + 14)
    disk[b + 16] = 2
    disk.putLE16(512, at: b + 17)
    disk[b + 21] = 0xf8
    disk.putLE16(128, at: b + 22)
    disk.putLE16(63, at: b + 24)
    disk.putLE16(16, at: b + 26)
    disk.putLE32(UInt32(start), at: b + 28)
    disk.putLE32(UInt32(volumeSectors), at: b + 32)
    disk[b + 36] = 0x80
    disk[b + 38] = 0x29
    disk.putLE32(UInt32.random(in: 1...UInt32.max), at: b + 39)
    disk.replaceSubrange((b + 43)..<(b + 54), with: Data("DOSMAC     ".utf8))
    disk.replaceSubrange((b + 54)..<(b + 62), with: Data("FAT16   ".utf8))
    disk[b + 510] = 0x55
    disk[b + 511] = 0xaa
    for fat in [b + 512, b + 129 * 512] {
      disk.replaceSubrange(fat..<(fat + 4), with: [0xf8, 0xff, 0xff, 0xff])
    }
    let label = b + 257 * 512
    disk.replaceSubrange(label..<(label + 11), with: Data("DOSMAC     ".utf8))
    disk[label + 11] = 0x08
    disk.putLE16(0x0021, at: label + 24)
    return disk
  }
}

#if os(macOS)
  extension SharedDiskImage {
    /// Sparse 1 GiB FAT16 partition for a newly created Windows 9x machine only.
    static func createSystemImage(at file: URL) throws {
      let sectors = 2_097_152
      let usableSectors = 520 * 64 * 63
      let start = 63
      let b = start * 512
      var header = Data(repeating: 0, count: (start + 1 + 512 + 32) * 512)
      header[446] = 0x80
      header[447] = 1
      header[448] = 1
      header[450] = 0x0e
      // Whole BIOS cylinders only: ScanDisk must be able to read the last FAT16 cluster.
      header[451] = 63
      header[452] = 0xbf
      header[453] = 7
      header.putLE32(UInt32(start), at: 454)
      header.putLE32(UInt32(usableSectors - start), at: 458)
      header[510] = 0x55
      header[511] = 0xaa
      header.replaceSubrange(b..<(b + 3), with: [0xeb, 0x3c, 0x90])
      header.replaceSubrange((b + 3)..<(b + 11), with: Data("DOSMAC  ".utf8))
      header.putLE16(512, at: b + 11)
      header[b + 13] = 32
      header.putLE16(1, at: b + 14)
      header[b + 16] = 2
      header.putLE16(512, at: b + 17)
      header[b + 21] = 0xf8
      header.putLE16(256, at: b + 22)
      header.putLE16(63, at: b + 24)
      header.putLE16(64, at: b + 26)
      header.putLE32(UInt32(start), at: b + 28)
      header.putLE32(UInt32(usableSectors - start), at: b + 32)
      header[b + 36] = 0x80
      header[b + 38] = 0x29
      header.putLE32(UInt32.random(in: 1...UInt32.max), at: b + 39)
      header.replaceSubrange((b + 43)..<(b + 54), with: Data("DOSMAC     ".utf8))
      header.replaceSubrange((b + 54)..<(b + 62), with: Data("FAT16   ".utf8))
      header[b + 510] = 0x55
      header[b + 511] = 0xaa
      for offset in [b + 512, b + 257 * 512] {
        header.replaceSubrange(offset..<(offset + 4), with: [0xf8, 0xff, 0xff, 0xff])
      }
      guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
        throw VMError.invalid("Cannot create the new system disk.")
      }
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.truncate(atOffset: UInt64(sectors * 512))
      try handle.seek(toOffset: 0)
      try handle.write(contentsOf: header)
    }
  }
#endif

#if os(macOS)
  public enum SharedStorage {
    public static func image(in directory: URL) -> URL {
      directory.appendingPathComponent(SharedDiskImage.filename)
    }
    public static func ensureDisk(in directory: URL) throws {
      let image = image(in: directory)
      if FileManager.default.fileExists(atPath: image.path) {
        let values = try image.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
          throw VMError.invalid("The shared disk must be an app-owned regular image.")
        }
      } else {
        try SharedDiskImage.make().write(to: image, options: .withoutOverwriting)
      }
    }
    private static func attachment(in directory: URL) async throws -> (
      device: String, volume: URL?
    )? {
      let data = try await ChildProcess.output(
        URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["info", "-plist"])
      guard
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any],
        let images = plist["images"] as? [[String: Any]]
      else { throw VMError.invalid("Cannot inspect mounted disk images.") }
      let expected = image(in: directory).standardizedFileURL.resolvingSymlinksInPath()
      for entry in images {
        guard let path = entry["image-path"] as? String,
          URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() == expected,
          let entities = entry["system-entities"] as? [[String: Any]],
          let device = entities.first?["dev-entry"] as? String,
          device.range(of: "^/dev/disk[0-9]+$", options: .regularExpression) != nil
        else { continue }
        let mount = entities.compactMap { $0["mount-point"] as? String }.first
        return (device, mount.map { URL(fileURLWithPath: $0, isDirectory: true) })
      }
      return nil
    }
    /// Never force-detach: a host app keeping a file open must prevent guest startup.
    public static func prepareForGuest(in directory: URL) async throws {
      try ensureDisk(in: directory)
      guard DistributionPolicy.current.allowsHostDiskMounts else { return }
      if let mounted = try await attachment(in: directory) {
        try await ChildProcess.run(
          URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", mounted.device])
      }
    }
    /// Call only when QEMU has closed this machine's disks.
    public static func mountForHost(in directory: URL) async throws -> URL {
      guard DistributionPolicy.current.allowsHostDiskMounts else { throw VMError.invalid("Use the live shared folder or exchange floppy in this edition.") }
      try ensureDisk(in: directory)
      if let mounted = try await attachment(in: directory) {
        guard let volume = mounted.volume else {
          throw VMError.invalid(
            "The shared disk is attached but not mounted. Eject it in Disk Utility and try again.")
        }
        return volume
      }
      _ = try await ChildProcess.output(
        URL(fileURLWithPath: "/usr/bin/hdiutil"),
        arguments: ["attach", "-nobrowse", "-plist", image(in: directory).path])
      guard let volume = try await attachment(in: directory)?.volume else {
        throw VMError.invalid("The shared disk did not mount.")
      }
      return volume
    }
  }
#endif
