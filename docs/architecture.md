# Architecture

## Decision: reuse a mature x86 machine emulator

DOS programs execute x86 instructions and may access PC hardware directly. Windows 3.1 also requires protected-mode CPU, memory, video, interrupt, and DOS behavior. Windows 9x adds disk boot, IDE, BIOS and driver compatibility requirements. Reimplementing all of this before delivering a usable application would be a separate multi-year emulator project.

DOSBox-X is the selected initial backend because it documents both [Windows 3.1x](https://dosbox-x.com/wiki/Guide%3AInstalling-Windows-3.1x) and [Windows 95](https://github.com/joncampbell123/dosbox-x/wiki/Guide%3AInstalling-Windows-95) installation. These upstream capabilities do not establish compatibility in DosMac; verification must use user-supplied media and the actual shipped core.

## Boundaries

| Layer | Current implementation | Next responsibility |
| --- | --- | --- |
| Native UI | Shared SwiftUI library and settings | Embedded display, keyboard, pointer, touch controls |
| Domain | Codable manifests, installed programs, machine profiles | Machine definitions and import migrations |
| Storage | Actor-owned installation, per-program drives, Exchange | Backups, recovery, uninstall and upgrade transactions |
| Session | Main-actor external process adapter on macOS | Common backend interface and embedded C ABI |
| Emulation | Automatically prepared official DOSBox-X release | Pinned interpreter core with audited build flags |

The first macOS adapter keeps upstream separate and makes the package-to-emulator-to-host-file loop testable immediately. It is not the iOS runtime architecture. iOS cannot use `Process` to launch a downloaded desktop executable.

The managed macOS installer downloads a pinned, architecture-specific upstream release, verifies a source-pinned SHA-256 before extraction, and publishes a versioned directory with a matching receipt. Launch discovers custom, bundled, managed, or existing system engines. See [engine delivery](engine-delivery.md).

## Embedded core contract to implement

Extract a small C ABI around upstream execution with opaque per-session handles. Swift owns application state; the emulation loop runs on a dedicated serial thread. The ABI must cover creation/destruction, bounded execution, cooperative stop, frame delivery, audio delivery, keyboard scancodes, relative/absolute pointer input, and approved mount descriptors. No Swift calls may directly mutate live emulated machine state from the UI thread.

Display frames should enter a bounded double/triple buffer and render through Metal, with a nearest-neighbor option and aspect-ratio correction. Audio should use a bounded ring buffer and AVAudioEngine. Define overflow/underrun behavior before connecting callbacks. Never call into Swift UI from a real-time audio callback.

For iOS, compile the interpreter only. Neither the first Mac configuration nor the planned phone core relies on JIT entitlements. Verify all executable-memory paths are disabled in the embedded build. Start with one active session per app. Backgrounding must cooperatively suspend emulation and audio; process termination must not leave writable disk images inconsistent.

## Storage and installation

Packages supply declarative metadata and payload files; they do not supply host commands or mount paths. The store validates the manifest and payload before publishing a new program via a staging-directory rename. `C:` belongs to one program; `D:` is the app's Exchange directory. Executable paths are validated before configuration generation. Host path quoting rejects control characters, quotation marks, and DOS environment expansion markers.

Packages must be stable while importing. The current local directory installer is not hardened against a malicious host process modifying files during validation and copying. The web importer stages content privately, validates ZIP/7z paths and declared sizes before extraction, and uses the same transactional local installer. Published WinWorld checksums detect mismatches but do not authenticate software or establish its license. A future curated catalog needs a trusted signed index.

SWCompression 4.9.1 supplies ZIP and 7z decoding. It has no streaming hard allocator budget; metadata preflight does not cap memory allocated while decoding compressed archive headers or malformed compressed streams. Treat hostile archive hardening, fuzzing, bounded decoding and isolation as production release work. The current importer limits network input to 32 MiB and declared expanded content to 128 MiB. BCJ/BCJ2-filtered and encrypted 7z archives are unsupported.

## Windows profiles

- DOS uses an interpreted 386, 16 MiB memory, S3 SVGA, and Sound Blaster 16.
- Windows 3.1 uses an interpreted 486 and 64 MiB. A package may start `WINDOWS/WIN.COM`; configuration changes to the executable directory first. Installation media, drivers and compatibility validation are still required.
- Windows 95/98 must get separate boot-image machine definitions. Do not offer the current folder-backed profile as Windows 9x support. A shared host folder cannot be assumed to appear in an image-booted guest; implement an offline FAT exchange path first, with exclusive ownership while images are mounted.

## Release requirements

Resolve the upstream GPL license and any linked component licenses before distributing a combined executable. Review the current [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), including emulator provisions in 4.7, against the actual product and catalog. Store acceptance and commercial application downloads are not assumed by this architecture.
