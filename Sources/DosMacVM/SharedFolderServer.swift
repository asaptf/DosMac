#if os(macOS)
  import Foundation
  import DosMacPlatform
  import Darwin

  /// App-private Samba instance: only loopback, forwarded into one isolated QEMU network.
  @MainActor
  public final class SharedFolderServer {
    public nonisolated static let guestPath = "\\\\DOSHOST\\DOSMAC"
    public nonisolated static func executable(policy: DistributionPolicy = .current) -> URL? {
      let bundled = Bundle.main.resourceURL?.appendingPathComponent("QEMU/bin/smbd")
      let override = [ProcessInfo.processInfo.environment["DOSMAC_SMBD_PATH"].map { URL(fileURLWithPath: $0) }].compactMap { $0 }
      let standard = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/smbd")
      let embedded = policy.allowsExternalEngines ? [standard] + [bundled].compactMap { $0 } : [standard]
      let system = [URL(fileURLWithPath: "/opt/homebrew/sbin/samba-dot-org-smbd"), URL(fileURLWithPath: "/usr/local/sbin/samba-dot-org-smbd")]
      return (policy.allowsExternalEngines ? override + embedded + system : embedded).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private var process: Process?
    private var log: FileHandle?
    private var input: Pipe?
    public private(set) var port: UInt16 = 0
    public init() {}
    public nonisolated static func folder(in directory: URL) throws -> URL {
      let folder = directory.appendingPathComponent("Shared", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let info = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
      guard info.isSymbolicLink != true, info.isDirectory == true else {
        throw VMError.invalid("The shared folder must stay inside this computer.")
      }
      return folder
    }
    public func start(directory: URL, runtime: URL) async throws {
      guard process == nil, let executable = Self.executable() else {
        throw VMError.invalid(
          "The embedded file-sharing engine is unavailable. Rebuild this app with Samba bundled.")
      }
      let shared = try Self.folder(in: directory)
      let user = NSUserName()
      guard user.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
        ![shared.path, runtime.path].contains(where: {
          $0.contains("%") || $0.contains("\n") || $0.contains("\r")
        })
      else { throw VMError.invalid("Unsupported shared-folder path or account name.") }
      port = try Self.availablePort()
      let config = runtime.appendingPathComponent("smb.conf")
      let text = """
        [global]
        server role = standalone server
        workgroup = WORKGROUP
        netbios name = DOSHOST
        interfaces = 127.0.0.1
        bind interfaces only = yes
        server smb transports = nbt:\(port)
        server min protocol = NT1
        server max protocol = NT1
        map to guest = Bad User
        guest account = \(user)
        security = user
        load printers = no
        printing = bsd
        printcap name = /dev/null
        disable spoolss = yes
        multicast dns register = no
        passdb backend = tdbsam
        lock directory = \(runtime.path)
        state directory = \(runtime.path)
        cache directory = \(runtime.path)
        private dir = \(runtime.path)
        pid directory = \(runtime.path)
        ncalrpc dir = \(runtime.path)/rpc
        log file = \(runtime.path)/smb.log
        [DOSMAC]
        path = \(shared.path)
        read only = no
        guest ok = yes
        guest only = yes
        oplocks = no
        level2 oplocks = no
        follow symlinks = no
        wide links = no
        """
      try Data(text.utf8).write(to: config)
      let logURL = runtime.appendingPathComponent("smb-process.log")
      FileManager.default.createFile(atPath: logURL.path, contents: nil)
      log = try FileHandle(forWritingTo: logURL)
      let child = Process()
      child.executableURL = executable
      // Foundation creates a private child process group on macOS. Samba must retain it.
      child.arguments = ["-F", "--no-process-group", "-l", runtime.path, "-s", config.path]
      // Samba watches stdin in foreground mode and exits on EOF. Keep the write end alive.
      let input = Pipe()
      self.input = input
      child.standardInput = input
      child.standardOutput = log
      child.standardError = log
      process = child
      do {
        try child.run()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
          try Task.checkCancellation()
          guard child.isRunning else {
            let diagnostic =
              (try? String(
                contentsOf: runtime.appendingPathComponent("log.samba-dot-org-smbd"),
                encoding: .utf8))
              ?? ((try? String(
                contentsOf: runtime.appendingPathComponent("smb.log"), encoding: .utf8)) ?? "")
            let processLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw VMError.invalid(
              "The private file-sharing engine could not start (\(child.terminationStatus)).\n\(diagnostic.suffix(2000))\n\(processLog.suffix(2000))"
            )
          }
          if Self.canConnect(port) { return }
          try await Task.sleep(for: .milliseconds(100))
        }
        throw VMError.timeout("Private shared folder")
      } catch {
        stop()
        throw error
      }
    }
    public func stop() {
      if let process, process.isRunning { process.terminate() }
      process = nil
      try? input?.fileHandleForWriting.close()
      input = nil
      try? log?.close()
      log = nil
    }
    private static func availablePort() throws -> UInt16 {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      guard fd >= 0 else { throw VMError.invalid("Cannot allocate the private sharing socket.") }
      defer { close(fd) }
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard result == 0 else { throw VMError.invalid("Cannot bind the private sharing socket.") }
      var size = socklen_t(MemoryLayout<sockaddr_in>.size)
      let found = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
      }
      guard found == 0 else { throw VMError.invalid("Cannot inspect the private sharing socket.") }
      return UInt16(bigEndian: address.sin_port)
    }
    private static func canConnect(_ port: UInt16) -> Bool {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      guard fd >= 0 else { return false }
      defer { close(fd) }
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = port.bigEndian
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      return withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
      }
    }
  }
#endif
