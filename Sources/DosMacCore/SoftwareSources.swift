import Foundation
import DosMacPlatform
import CryptoKit
import SWCompression

public struct RemoteRelease: Identifiable, Sendable {
    public var id: String { pageURL.absoluteString }
    public let title: String
    public let pageURL: URL
    public let downloadURL: URL?
    public let sha512: String?
    public let sha1: String?

    public init(title: String, pageURL: URL, downloadURL: URL? = nil, sha512: String? = nil, sha1: String? = nil) {
        self.title = title
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.sha512 = sha512
        self.sha1 = sha1
    }
}

public struct PreparedImport: Sendable {
    public let workspace: URL
    public let package: URL
    public let title: String
    public let candidates: [String]
    public let isInstallationMedia: Bool
    public let source: URL
    public let floppyDisks: [FloppyDisk]
}

/// Fetches source metadata and prepares a private, validated local package.
/// No remote installer can execute native host commands.
public actor SoftwareSources {
    private let policy: DistributionPolicy
    private let session: URLSession
    private let fm = FileManager.default
    public static let downloadLimit = 32 * 1024 * 1024
    public static let expandedLimit = 128 * 1024 * 1024

    public init(policy: DistributionPolicy = .current) {
        self.policy = policy
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config)
    }

    public static func validateURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw DosMacError.invalidPackage("use an HTTPS source URL without embedded credentials")
        }
    }

    public static func isWinWorld(_ url: URL) -> Bool {
        ["winworldpc.com", "www.winworldpc.com"].contains(url.host?.lowercased() ?? "")
    }

    public func inspect(_ url: URL) async throws -> [RemoteRelease] {
        guard policy.allowsUnreviewedCatalogs else { throw DosMacError.invalidPackage("This edition imports your own installation images. Archive catalog downloads are unavailable.") }
        try Self.validateURL(url)
        if url.host?.lowercased() == "archive.org", url.pathComponents.count == 3, url.pathComponents[1] == "details" {
            let identifier = url.lastPathComponent
            let metadata = URL(string: "https://archive.org/metadata/")!.appendingPathComponent(identifier)
            return try Self.parseArchiveReleases(data: await fetch(metadata, limit: 2 * 1024 * 1024), page: url)
        }
        guard Self.isWinWorld(url) else {
            return [RemoteRelease(title: url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "DOS program", pageURL: url, downloadURL: url)]
        }
        let data = try await fetch(url, limit: 2 * 1024 * 1024)
        guard let html = String(data: data, encoding: .utf8) else { throw DosMacError.invalidPackage("source page is not UTF-8") }
        return try Self.parseWinWorld(html: html, page: url)
    }

    public func search(_ query: String, source: CatalogSource) async throws -> [CatalogItem] {
        guard policy.allowsUnreviewedCatalogs else { throw DosMacError.invalidPackage("This edition imports your own installation images. Archive catalog downloads are unavailable.") }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 160 else { throw DosMacError.invalidPackage("enter a search of up to 160 characters") }
        let page = source.searchURL(query)
        let data = try await fetch(page, limit: 2 * 1024 * 1024)
        if source == .internetArchive { return try Self.parseArchiveSearch(data: data) }
        guard let html = String(data: data, encoding: .utf8) else { throw DosMacError.invalidPackage("the source could not be read") }
        return Self.parseCatalogProducts(html: html, page: page)
    }

    public static func parseCatalogProducts(html: String, page: URL) -> [CatalogItem] {
        guard let expression = try? NSRegularExpression(pattern: "(?is)<dt\\b[^>]*>(.*?)</dt>\\s*<dd\\b[^>]*>(.*?)</dd>") else { return [] }
        var seen = Set<String>()
        let items: [CatalogItem] = expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let heading = Range(match.range(at: 1), in: html), let body = Range(match.range(at: 2), in: html),
                  let (url, title) = anchors(String(html[heading]), relativeTo: page).first(where: { isWinWorld($0.0) && $0.0.path.hasPrefix("/product/") }), seen.insert(url.absoluteString).inserted else { return nil }
            return CatalogItem(title: title, summary: String(plainText(String(html[body])).prefix(320)), pageURL: url, source: .winWorld)
        }
        if !items.isEmpty { return items }
        return anchors(html, relativeTo: page).compactMap { url, title in
            guard isWinWorld(url), url.path.hasPrefix("/product/"), !title.isEmpty, seen.insert(url.absoluteString).inserted else { return nil }
            return CatalogItem(title: title, summary: "Browse available releases on WinWorld.", pageURL: url, source: .winWorld)
        }
    }

    public static func parseArchiveSearch(data: Data) throws -> [CatalogItem] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let docs = (json?["response"] as? [String: Any])?["docs"] as? [[String: Any]] ?? []
        return docs.prefix(24).compactMap { item in
            guard let id = item["identifier"] as? String, id.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil, let title = item["title"] as? String else { return nil }
            return CatalogItem(title: title, summary: "Software archive · Review the release and supported platform before installing.", pageURL: URL(string: "https://archive.org/details/")!.appendingPathComponent(id), source: .internetArchive)
        }
    }

    public static func parseArchiveReleases(data: Data, page: URL) throws -> [RemoteRelease] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]] ?? []
        let releases = files.compactMap { file -> RemoteRelease? in
            guard let name = file["name"] as? String, ["zip", "7z", "exe", "com", "bat"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()),
                  file["private"] as? String != "true", file["private"] as? Bool != true, let size = file["size"] as? String, let bytes = Int(size), bytes > 0, bytes <= downloadLimit,
                  (try? validateArchivePath(name)) != nil else { return nil }
            let url = URL(string: "https://archive.org/download/")!.appendingPathComponent(page.lastPathComponent).appendingPathComponent(name)
            let hash = file["sha1"] as? String
            return RemoteRelease(title: name, pageURL: url, downloadURL: url, sha1: hash?.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil ? hash?.lowercased() : nil)
        }
        guard !releases.isEmpty else { throw DosMacError.invalidPackage("this item has no supported ZIP, 7z or DOS program download under 32 MiB; open its source page for other media") }
        return releases
    }

    public static func parseWinWorld(html: String, page: URL) throws -> [RemoteRelease] {
        let links = anchors(html, relativeTo: page)
        let title = firstMatch("(?is)<h1[^>]*>(.*?)</h1>", in: html).map(plainText) ?? "WinWorld software"
        let mirrors = links.filter { isWinWorld($0.0) && $0.0.path.contains("/from/") }
        if let mirror = mirrors.first {
            let checksum = firstMatch("(?is)<dt[^>]*>\\s*Checksum\\s*</dt>\\s*<dd[^>]*>\\s*(?:<[^>]+>)*\\s*([a-f0-9]{40,128})", in: html)?.lowercased()
            return [RemoteRelease(title: title, pageURL: page, downloadURL: mirror.0, sha512: checksum?.count == 128 ? checksum : nil, sha1: checksum?.count == 40 ? checksum : nil)]
        }
        var seen = Set<String>()
        let releases = links.filter { isWinWorld($0.0) && $0.0.path.hasPrefix("/download/") && !$0.0.path.contains("/from/") && seen.insert($0.0.absoluteString).inserted }
            .map { RemoteRelease(title: $0.1, pageURL: $0.0) }
        guard !releases.isEmpty else {
            throw DosMacError.invalidPackage("no downloads found; paste a WinWorld product or download page, or a direct HTTPS archive link")
        }
        return releases
    }

    public func prepare(_ release: RemoteRelease) async throws -> PreparedImport {
        guard policy.allowsUnreviewedCatalogs else { throw DosMacError.invalidPackage("This edition imports your own installation images. Archive catalog downloads are unavailable.") }
        let resolved: RemoteRelease
        if release.downloadURL == nil {
            guard let item = try await inspect(release.pageURL).first, item.downloadURL != nil else { throw DosMacError.invalidPackage("download mirror unavailable") }
            resolved = item
        } else { resolved = release }
        guard let download = resolved.downloadURL else { throw DosMacError.invalidPackage("missing download URL") }
        let data = try await fetch(download, limit: Self.downloadLimit)
        if let hash = resolved.sha512 {
            let actual = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == hash else { throw DosMacError.invalidPackage("source SHA-512 checksum did not match") }
        }
        if let hash = resolved.sha1 {
            let actual = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == hash else { throw DosMacError.invalidPackage("source SHA-1 checksum did not match") }
        }
        return try prepareArchive(data: data, release: resolved)
    }

    func prepareArchive(data: Data, release resolved: RemoteRelease) throws -> PreparedImport {
        guard data.count <= Self.downloadLimit else { throw DosMacError.invalidPackage("download exceeds 32 MiB") }
        let download = resolved.downloadURL ?? resolved.pageURL
        try Task.checkCancellation()
        let workspace = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("DosMac-import-\(UUID().uuidString)")
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: workspace) } }
        let package = workspace.appendingPathComponent("Import.dosmac")
        let payload = package.appendingPathComponent("payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        if data.starts(with: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) {
            do {
                let info = try SevenZipContainer.info(container: data)
                try Self.validateEntries(info.map { ($0.name, $0.size, $0.type == .regular, $0.type == .directory) })
                let entries = try SevenZipContainer.open(container: data)
                for entry in entries where entry.info.type == .regular {
                    try write(entry.data ?? Data(), name: entry.info.name, to: payload)
                }
            } catch SevenZipError.compressionNotSupported {
                throw DosMacError.invalidPackage("this 7z uses an unsupported compression filter (such as BCJ). Use ZIP or plain LZMA/LZMA2 7z in this preview")
            }
        } else if data.starts(with: [0x50, 0x4b]) {
            let info = try ZipContainer.info(container: data)
            try Self.validateEntries(info.map { ($0.name, $0.size, $0.type == .regular, $0.type == .directory) })
            let entries = try ZipContainer.open(container: data)
            for entry in entries where entry.info.type == .regular {
                try write(entry.data ?? Data(), name: entry.info.name, to: payload)
            }
        } else {
            let name = download.lastPathComponent
            guard ["exe", "com", "bat"].contains(download.pathExtension.lowercased()) else {
                throw DosMacError.invalidPackage("expected ZIP, 7z, or a direct DOS EXE/COM/BAT file; the source may require a browser or be unavailable")
            }
            if String(data: data.prefix(256), encoding: .utf8)?.lowercased().contains("<html") == true { throw DosMacError.invalidPackage("the server returned a web page instead of a DOS file") }
            try write(data, name: name, to: payload)
        }
        try Task.checkCancellation()
        // Remove wrapper directories commonly used by software archives.
        var content = payload
        while true {
            let children = try fm.contentsOfDirectory(at: content, includingPropertiesForKeys: [.isDirectoryKey])
            guard children.count == 1, let child = children.first, (try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { break }
            content = child
        }
        if content != payload {
            let flattened = workspace.appendingPathComponent("flattened")
            try fm.moveItem(at: content, to: flattened)
            try fm.removeItem(at: payload)
            try fm.moveItem(at: flattened, to: payload)
        }
        let files = try regularFiles(payload)
        let candidates = files.compactMap { file -> String? in
            let relative = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(payload.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
            let test = PackageManifest(id: "test", title: "Test", summary: "", author: "", license: "User supplied", executable: relative)
            guard (try? test.validate()) != nil else { return nil }
            // A Windows-only EXE cannot be launched by the DOS shell on its own.
            if Self.isWindowsOnlyExecutable(file) { return nil }
            return relative
        }.sorted()
        var media = false
        var floppyDisks: [FloppyDisk] = []
        var choices = candidates
        if choices.isEmpty {
            let images = files.filter { ["img", "ima", "dsk"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !images.isEmpty, images.count <= 32 else { throw DosMacError.invalidPackage("no DOS 8.3 entry points or supported floppy images found; Windows-only binaries and CD images need a machine installer") }
            let mediaFolder = payload.appendingPathComponent("MEDIA")
            // Reserve our names; never overwrite archive content.
            guard !fm.fileExists(atPath: mediaFolder.path), !fm.fileExists(atPath: payload.appendingPathComponent("INSTALL.BAT").path) else { throw DosMacError.invalidPackage("reserved media paths already exist") }
            try fm.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
            var mounts: [String] = []
            for (index, image) in images.enumerated() {
                let size = try image.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size >= 160 * 1024, size <= 2880 * 1024 else { throw DosMacError.invalidPackage("only standard floppy-size raw images are supported") }
                let name = String(format: "DISK%02d.IMG", index + 1)
                try fm.copyItem(at: image, to: mediaFolder.appendingPathComponent(name))
                mounts.append("\"C:\\MEDIA\\\(name)\"")
                floppyDisks.append(FloppyDisk(number: index + 1, imagePath: "MEDIA/\(name)", label: image.lastPathComponent))
            }
            let script = """
            @echo off
            imgmount a \(mounts.joined(separator: " ")) -t floppy
            a:
            echo Installation media mounted. Use Next disk in DosMac when requested.
            if exist SETUP.EXE goto setup
            if exist INSTALL.EXE goto install
            echo No automatic entry point found. Run the appropriate installer below.
            dir
            goto end
            :setup
            SETUP.EXE
            goto end
            :install
            INSTALL.EXE
            :end
            echo After setup, stop this session and choose the installed startup program in DosMac.

            """.replacingOccurrences(of: "\n", with: "\r\n")
            try script.write(to: payload.appendingPathComponent("INSTALL.BAT"), atomically: true, encoding: .ascii)
            choices = ["INSTALL.BAT"]
            media = true
        }
        succeeded = true
        return PreparedImport(workspace: workspace, package: package, title: resolved.title, candidates: choices, isInstallationMedia: media, source: resolved.pageURL, floppyDisks: floppyDisks)
    }

    public func finalize(_ prepared: PreparedImport, executable: String, profile: MachineProfile) throws -> URL {
        guard prepared.candidates.contains(executable) else { throw DosMacError.invalidPackage("entry point was not found in this download") }
        let digest = SHA256.hash(data: Data(prepared.source.absoluteString.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        var manifest = PackageManifest(id: "web.\(digest)", title: prepared.title + (prepared.isInstallationMedia ? " · Setup" : ""), summary: prepared.isInstallationMedia ? "Installation media from \(prepared.source.host ?? "web"). Launch to run the guest installer. Change disks in the DosMac drive panel." : "Imported from \(prepared.source.host ?? "web").", author: prepared.source.host ?? "User source", license: "User-supplied source; see original publisher terms", executable: executable, profile: profile)
        manifest.floppyDisks = prepared.floppyDisks.isEmpty ? nil : prepared.floppyDisks
        try manifest.validate()
        try JSONEncoder().encode(manifest).write(to: prepared.package.appendingPathComponent("manifest.json"), options: .atomic)
        // Preserve source provenance without overwriting any program payload file.
        try prepared.source.absoluteString.write(to: prepared.package.appendingPathComponent("source-url.txt"), atomically: true, encoding: .utf8)
        return prepared.package
    }

    public func discard(_ prepared: PreparedImport) { try? fm.removeItem(at: prepared.workspace) }

    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        try Self.validateURL(url)
        var request = URLRequest(url: url)
        request.setValue("DosMac/0.1", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let finalURL = response.url else {
            throw DosMacError.invalidPackage("source returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        try Self.validateURL(finalURL)
        guard response.expectedContentLength <= Int64(limit) else { throw DosMacError.invalidPackage("download exceeds \(limit / 1024 / 1024) MiB limit") }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < limit else { throw DosMacError.invalidPackage("download exceeds size limit") }
            data.append(byte)
        }
        return data
    }

    public static func validateArchivePath(_ name: String) throws -> String {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, !normalized.hasPrefix("/"), !normalized.contains(":"), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !parts.contains(".."), !parts.contains("."), !parts.dropLast().contains("") else {
            throw DosMacError.invalidPackage("unsafe archive path")
        }
        return normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
    }

    private static func validateEntries(_ entries: [(String, Int?, Bool, Bool)]) throws {
        guard entries.count <= 20_000 else { throw DosMacError.invalidPackage("too many archive entries") }
        var total = 0
        var names = Set<String>()
        for (name, size, regular, directory) in entries {
            let path = try validateArchivePath(name)
            guard names.insert(path.lowercased()).inserted, regular || directory else { throw DosMacError.invalidPackage("links, special files, or colliding paths in archive") }
            if regular {
                guard let size, size >= 0, size <= expandedLimit - total else { throw DosMacError.invalidPackage("expanded archive exceeds 128 MiB") }
                total += size
            }
        }
    }

    private func write(_ data: Data, name: String, to root: URL) throws {
        try Task.checkCancellation()
        guard data.count <= Self.expandedLimit else { throw DosMacError.invalidPackage("expanded file exceeds limit") }
        let path = try Self.validateArchivePath(name)
        let destination = root.appendingPathComponent(path)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .withoutOverwriting)
    }

    private func regularFiles(_ root: URL) throws -> [URL] {
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return try iterator.compactMap { item in
            guard let url = item as? URL, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return url
        }
    }

    private static func isWindowsOnlyExecutable(_ file: URL) -> Bool {
        guard file.pathExtension.lowercased() == "exe", let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 64), header.count == 64, header.starts(with: [0x4d, 0x5a]) else { return false }
        let offset = (0..<4).reduce(UInt64(0)) { $0 | UInt64(header[60 + $1]) << (8 * $1) }
        guard offset >= 64, (try? handle.seek(toOffset: offset)) != nil, let signature = try? handle.read(upToCount: 4) else { return false }
        return signature.starts(with: [0x4e, 0x45]) || signature.starts(with: [0x50, 0x45, 0, 0])
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func anchors(_ html: String, relativeTo page: URL) -> [(URL, String)] {
        guard let expression = try? NSRegularExpression(pattern: "(?is)<a\\b[^>]*?href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>") else { return [] }
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let href = Range(match.range(at: 1), in: html), let text = Range(match.range(at: 2), in: html), let url = URL(string: plainText(String(html[href])), relativeTo: page)?.absoluteURL else { return nil }
            return (url, plainText(String(html[text])))
        }
    }

    private static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
