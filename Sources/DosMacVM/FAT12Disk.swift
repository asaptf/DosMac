import Foundation

/// Bounded FAT12 support for raw installation floppies and app-owned guest-transfer disks.
public struct FAT12Disk {
    private let image: Data
    private let sectorSize: Int, clusterSectors: Int, reserved: Int, fatCount: Int, fatSectors: Int, rootEntries: Int
    private var rootOffset: Int { (reserved + fatCount * fatSectors) * sectorSize }
    private var dataOffset: Int { rootOffset + ((rootEntries * 32 + sectorSize - 1) / sectorSize) * sectorSize }

    public init(data: Data) throws {
        guard data.count >= 512, data.count <= 3 * 1024 * 1024 else { throw VMError.invalid("Invalid floppy image size.") }
        image = data
        sectorSize = Int(data.le16(11)); clusterSectors = Int(data[13]); reserved = Int(data.le16(14)); fatCount = Int(data[16]); fatSectors = Int(data.le16(22)); rootEntries = Int(data.le16(17))
        guard [512,1024].contains(sectorSize), clusterSectors > 0, clusterSectors <= 8, reserved > 0, fatCount > 0, fatCount <= 2, fatSectors > 0, rootEntries <= 512, dataOffset <= data.count else { throw VMError.invalid("Unsupported FAT12 floppy geometry.") }
    }

    public var fileNames: [String] {
        stride(from: rootOffset, to: min(rootOffset + rootEntries * 32, image.count), by: 32).compactMap { offset in
            guard image[offset] != 0, image[offset] != 0xe5, image[offset + 11] & 0x18 == 0, image[offset + 11] != 0x0f else { return nil }
            let name = String(decoding: image[offset..<(offset+8)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            let ext = String(decoding: image[(offset+8)..<(offset+11)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return ext.isEmpty ? name : name + "." + ext
        }
    }

    public func file(_ requested: String) throws -> Data? {
        for offset in stride(from: rootOffset, to: min(rootOffset + rootEntries * 32, image.count), by: 32) {
            guard image[offset] != 0, image[offset] != 0xe5, image[offset + 11] & 0x18 == 0, image[offset + 11] != 0x0f else { continue }
            let name = String(decoding: image[offset..<(offset+8)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            let ext = String(decoding: image[(offset+8)..<(offset+11)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            guard (ext.isEmpty ? name : name + "." + ext).uppercased() == requested.uppercased() else { continue }
            let size = Int(image.le32(offset + 28))
            guard size <= image.count else { throw VMError.invalid("Invalid FAT file size.") }
            var cluster = Int(image.le16(offset + 26)), result = Data(), seen = Set<Int>()
            while result.count < size {
                guard cluster >= 2, cluster < 0xff0, seen.insert(cluster).inserted else { throw VMError.invalid("Invalid or cyclic FAT cluster chain.") }
                let start = dataOffset + (cluster - 2) * clusterSectors * sectorSize
                let bytes = min(clusterSectors * sectorSize, size - result.count)
                guard start >= dataOffset, start + bytes <= image.count else { throw VMError.invalid("FAT cluster exceeds its image.") }
                result.append(image[start..<(start + bytes)])
                let fatOffset = reserved * sectorSize + cluster + cluster / 2
                guard fatOffset + 1 < rootOffset else { throw VMError.invalid("Invalid FAT entry.") }
                let entry = Int(image.le16(fatOffset))
                cluster = cluster & 1 == 0 ? entry & 0xfff : entry >> 4
            }
            return result
        }
        return nil
    }

    public static func make(files: [String: Data]) throws -> Data {
        guard files.count <= 100 else { throw VMError.invalid("Too many support files.") }
        var disk = Data(repeating: 0, count: 1440 * 1024)
        disk.replaceSubrange(0..<3, with: [0xeb,0x3c,0x90]); disk.replaceSubrange(3..<11, with: Data("DOSMAC  ".utf8))
        disk.putLE16(512, at: 11); disk[13] = 1; disk.putLE16(1, at: 14); disk[16] = 2
        disk.putLE16(224, at: 17); disk.putLE16(2880, at: 19); disk[21] = 0xf0; disk.putLE16(9, at: 22); disk.putLE16(18, at: 24); disk.putLE16(2, at: 26)
        disk[38] = 0x29
        disk.putLE32(UInt32.random(in: 1...UInt32.max), at: 39)
        disk.replaceSubrange(43..<54, with: Data("DOSMAC     ".utf8))
        disk.replaceSubrange(54..<62, with: Data("FAT12   ".utf8))
        disk[510] = 0x55; disk[511] = 0xaa
        var fat = Data(repeating: 0, count: 9 * 512); fat.replaceSubrange(0..<3, with: [0xf0,0xff,0xff])
        var cluster = 2, entryIndex = 0
        let dataOffset = 33 * 512
        for name in files.keys.sorted() {
            guard name.range(of: "^[A-Z0-9_]{1,8}(\\.[A-Z0-9_]{1,3})?$", options: .regularExpression) != nil, let bytes = files[name] else { throw VMError.invalid("Support filenames must use uppercase DOS 8.3 names.") }
            let count = (bytes.count + 511) / 512
            guard cluster + count <= 2849 else { throw VMError.invalid("Support files do not fit on a floppy.") }
            let offset = 19 * 512 + entryIndex * 32
            let parts = name.split(separator: ".")
            let short = String(parts[0]).padding(toLength: 8, withPad: " ", startingAt: 0) + (parts.count > 1 ? String(parts[1]) : "").padding(toLength: 3, withPad: " ", startingAt: 0)
            disk.replaceSubrange(offset..<(offset+11), with: Data(short.utf8)); disk[offset+11] = 0x20
            disk.putLE16(0x0021, at: offset + 16); disk.putLE16(0x0021, at: offset + 18); disk.putLE16(0x0021, at: offset + 24) // 1980-01-01
            disk.putLE16(UInt16(bytes.isEmpty ? 0 : cluster), at: offset + 26); disk.putLE32(UInt32(bytes.count), at: offset+28)
            let target = dataOffset + (cluster-2)*512
            disk.replaceSubrange(target..<(target+bytes.count), with: bytes)
            for i in 0..<count {
                let c = cluster + i, value = i == count-1 ? 0xfff : c+1, at = c+c/2
                let old = Int(fat.le16(at))
                let updated = c & 1 == 0 ? (old & 0xf000) | value : (old & 0x000f) | (value << 4)
                fat.putLE16(UInt16(updated), at: at)
            }
            cluster += count; entryIndex += 1
        }
        disk.replaceSubrange(512..<(10*512), with: fat); disk.replaceSubrange((10*512)..<(19*512), with: fat)
        return disk
    }

    /// Patch support files without moving IO.SYS, its directory entry, or the original boot sector.
    public func replacing(files: [String: Data]) throws -> Data {
        guard sectorSize == 512, rootEntries > 0 else { throw VMError.invalid("Use a standard FAT12 startup disk.") }
        var result = image
        let fatStart = reserved * sectorSize, fatEnd = fatStart + fatSectors * sectorSize
        let clusterBytes = clusterSectors * sectorSize
        let clusterLimit = min(0xff0, (image.count - dataOffset) / clusterBytes + 2)
        guard fatEnd <= rootOffset, fatEnd - fatStart >= (clusterLimit * 3 + 1) / 2 else { throw VMError.invalid("Invalid startup disk FAT.") }
        func value(_ cluster: Int) -> Int {
            let at = fatStart + cluster + cluster / 2
            let word = Int(result.le16(at))
            return cluster & 1 == 0 ? word & 0xfff : word >> 4
        }
        func set(_ cluster: Int, _ next: Int) {
            let at = fatStart + cluster + cluster / 2, old = Int(result.le16(at))
            result.putLE16(UInt16(cluster & 1 == 0 ? (old & 0xf000) | next : (old & 0x000f) | (next << 4)), at: at)
        }
        for (name, bytes) in files.sorted(by: { $0.key < $1.key }) {
            guard name.range(of: "^[A-Z0-9_]{1,8}(\\.[A-Z0-9_]{1,3})?$", options: .regularExpression) != nil else { throw VMError.invalid("Invalid startup support filename.") }
            let parts = name.split(separator: ".")
            let short = Data((String(parts[0]).padding(toLength: 8, withPad: " ", startingAt: 0) + (parts.count > 1 ? String(parts[1]) : "").padding(toLength: 3, withPad: " ", startingAt: 0)).utf8)
            let offsets = stride(from: rootOffset, to: rootOffset + rootEntries * 32, by: 32)
            let existing = offsets.first { result[$0] != 0xe5 && Data(result[$0..<($0 + 11)]) == short }
            guard let entry = existing ?? offsets.first(where: { result[$0] == 0 || result[$0] == 0xe5 }) else { throw VMError.invalid("The startup disk directory is full.") }
            if existing != nil {
                guard result[entry + 11] & 0x18 == 0 else { throw VMError.invalid("Cannot replace a startup directory.") }
                var cluster = Int(result.le16(entry + 26)), seen = Set<Int>()
                while cluster >= 2 && cluster < 0xff0 {
                    guard cluster < clusterLimit, seen.insert(cluster).inserted else { throw VMError.invalid("Invalid startup file chain.") }
                    let next = value(cluster); set(cluster, 0); cluster = next
                }
            }
            let count = (bytes.count + clusterBytes - 1) / clusterBytes
            let free = Array((2..<clusterLimit).lazy.filter { value($0) == 0 }.prefix(count))
            guard free.count == count else { throw VMError.invalid("Startup support files do not fit on the boot disk.") }
            result.replaceSubrange(entry..<(entry + 32), with: Data(repeating: 0, count: 32))
            result.replaceSubrange(entry..<(entry + 11), with: short); result[entry + 11] = 0x20
            for field in [16, 18, 24] { result.putLE16(0x0021, at: entry + field) }
            result.putLE16(UInt16(free.first ?? 0), at: entry + 26)
            result.putLE32(UInt32(bytes.count), at: entry + 28)
            for (index, cluster) in free.enumerated() {
                set(cluster, index + 1 < free.count ? free[index + 1] : 0xfff)
                let offset = dataOffset + (cluster - 2) * clusterBytes
                result.replaceSubrange(offset..<(offset + clusterBytes), with: Data(repeating: 0, count: clusterBytes))
                let lower = index * clusterBytes, upper = min(bytes.count, lower + clusterBytes)
                result.replaceSubrange(offset..<(offset + upper - lower), with: bytes[lower..<upper])
            }
        }
        let fat = Data(result[fatStart..<fatEnd])
        for copy in 1..<fatCount {
            let start = fatStart + copy * fatSectors * sectorSize
            result.replaceSubrange(start..<(start + fat.count), with: fat)
        }
        return result
    }
}

extension Data {
    func le16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i+1]) << 8 }
    func le32(_ i: Int) -> UInt32 { UInt32(le16(i)) | UInt32(le16(i+2)) << 16 }
    mutating func putLE16(_ v: UInt16, at i: Int) { self[i] = UInt8(v & 255); self[i+1] = UInt8(v >> 8) }
    mutating func putLE32(_ v: UInt32, at i: Int) { putLE16(UInt16(v & 65535), at: i); putLE16(UInt16(v >> 16), at: i+2) }
}
