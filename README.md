# DosMac

A native manager for complete retro PCs on Mac, with a future iPhone runtime.

**Status: developer preview.** Library is the app's home: installed Word/Windows shortcuts, your own guest apps, and existing imported packages share the same searchable collection. Complete PCs run through the included QEMU engine. iPhone execution is not implemented yet; its library and source UI build remains available.

## Your workspace

- **Library** — open Word or Windows directly, search installed apps, import a `.dosmac` package, or add/edit a shortcut to an app already installed inside a computer. Existing imported packages remain available through classic DOS compatibility.
- **Discover** — search WinWorld and Internet Archive, choose a release, or paste a direct HTTPS link. Downloads can be added to Library and optionally opened immediately. Source availability and rate limits are shown without hiding results from the other provider.
- **Now playing** — the guest screen and playback controls stay together. Use **Disks** to insert, eject or advance installation media. An installer's own disk order is remembered. Browsing Library or Discover keeps the session alive; click its sidebar card to return.
- **Files** — open a 64 MB shared FAT16 disk in Finder while the computer is stopped, or enable a live Windows network folder at `\\10.0.2.4\DOSMAC`. DosMac ejects the shared disk from macOS before guest startup. Exchange floppies and imported packages' shared D: folder remain available.
- **Computers** — create a blank PC or change its hardware/boot/media settings. These controls are secondary to the app library.

Use **⌘F** to focus search, and **⌘1–⌘4** for Library, Discover, Files and Computers. Click the guest screen to capture input; **Control + Option** releases it.

The featured **Windows 3.1 + Word 6** collection installs pinned English releases of MS-DOS 6.22, Windows 3.1 Retail and Word 6 in a private computer. Its default installation identity is “DosMac User”. The recipe has been verified on an empty HDD, through cold boot, actual Word startup, document save and host export. Other releases can be added as setup disks and opened from Library; their guest installers may require manual interaction. Preparing media is labelled **Setup ready**, not installed software. Password-protected archives and catalog CD downloads are not supported; local ISO files can be imported in computer settings.

The current PCs have BIOS boot, owned QCOW2 disks, floppy/IDE CD-ROM, native display and direct input. **Discover → Install Windows 98 SE / Windows 95** prepares a new computer with verified source media and experimental batch Setup. Enter your own product key, or supply it in Setup; unfamiliar dialogs pause for guest control. Windows 98 SE has reached its desktop and passed HDD cold boot; Windows 95 desktop and Windows guest-network acceptance remain pending. See [host sharing and Windows 9x](docs/host-sharing-and-windows9x.md), [workspace behavior](docs/workspace.md) and [managed PC architecture](docs/machine-architecture.md).

The developer build can use a local QEMU 9.2 or newer installation, or an explicit `DOSMAC_QEMU_PATH=/absolute/path/to/qemu-system-i386`. To assemble a self-contained local macOS build after building the app:

```sh
brew install i686-elf-gcc i686-elf-binutils
python3 scripts/build-win9x-bios.py
python3 scripts/bundle-qemu.py --app build/macOS/Build/Products/Debug/DosMac.app
```

The resulting app carries its engine, dylibs, firmware and keymaps. This is a local development bundle; public binary distribution still needs the license/source and notarization work documented in the architecture. No commercial OS or application image is bundled.

## Build on Mac

Requires Xcode 16 or newer and macOS 14 or newer.

```sh
swift run DosMac
```

For a development-only engine location, use `DOSMAC_ENGINE_PATH=/absolute/path/to/dosbox-x swift run DosMac`. This does not install or bundle the engine.

For a normal application bundle, install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then:

```sh
xcodegen generate
xcodebuild -project DosMac.xcodeproj -scheme DosMac-macOS \
  -configuration Debug -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
open build/macOS/Build/Products/Debug/DosMac.app
```

The following is a compatibility reference for existing **imported packages**:

1. Click **Install Hello, DOS**. This installs an original, redistributable batch demo with one click.
2. Select the program and click **Launch**. On the first launch, DosMac downloads the official DOSBox-X release for your Mac, verifies its pinned SHA-256, and installs it privately. Progress and cancellation appear in the sidebar. The program then opens in the emulator's own window.
3. Open **Files → Imported packages · D:**. The demo creates `HELLO.TXT` through guest drive `D:`.

No separate DOSBox-X installation, Homebrew, administrator password, or executable-path selection is needed. The initial download is approximately 90 MiB on Apple Silicon or 98 MiB on Intel. Later launches use the cached engine offline. **Engine settings → Prepare engine now** can prepare it ahead of time. If downloading fails, retry **Launch**. Existing system engines and optional custom paths remain supported. See [engine delivery](docs/engine-delivery.md).

Use **Import package** to select a `.dosmac` directory. The example at `Examples/HelloDOS.dosmac` is also importable. Packages are copied to application storage; originals are not modified. Duplicate installs are rejected rather than overwriting user data.

Use **Add from web** to paste a WinWorld product/download page or a direct HTTPS ZIP/7z/DOS-file URL. Select a release and click **Install**. Single-entry archives install directly; multiple entry points prompt for selection. Enable **Launch after installation** to start the program immediately. Floppy archives prepare a guest installer rather than pretending the program is already installed. See [software sources](docs/software-sources.md).

When Setup requests another disk, use the **Floppy drive · A:** panel above the library. Click **Next disk**, or choose a disk and click **Insert selected disk**. Return to the installer and press Enter after the panel confirms the inserted disk. On macOS, disk buttons require Accessibility permission for DosMac; click **Enable disk controls…** to open the system prompt. Without permission, use **F12 + O** in DOSBox-X (possibly **Fn + F12 + O** on a Mac keyboard). See [disk controls](docs/disk-controls.md).

In graphical Windows Setup, click inside the DOSBox-X screen to capture the mouse. DosMac enables click-to-capture automatically; the standard Windows 3.1 driver requires captured relative input. Press **Ctrl + F10** to release it (**Ctrl + Fn + F10** on some Mac keyboards), or use **Main → Capture mouse** in DOSBox-X. The running-session panel includes these instructions. See [mouse input](docs/mouse-input.md).

## After installing Windows

Stop the current session, select the same library item, and choose **Startup settings** from its context menu. Set **Start in → DOS prompt on C:** and save to open the built-in DOS shell at `C:\>` without running the floppy installer. To start the installed Windows directly, click **Use installed Windows**, then **Save**. DosMac detects `WINDOWS/WIN.COM` and other installed `WIN.COM` entry points. Your installed files stay on the same private C: drive; no reinstallation is needed.

From the DOS prompt, type `CD \WINDOWS` and then `WIN` to start an installation in the default directory. The floppy images remain available if you later choose the installer entry point again, but DOS/installed-Windows startup does not mount them. See [startup modes](docs/startup.md).

## Build for iPhone

```sh
xcodegen generate
xcodebuild -project DosMac.xcodeproj -scheme DosMac-iOS \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
```

Open `DosMac.xcodeproj`, choose `DosMac-iOS`, select a simulator or configure your signing team for a physical device. The preview supports package import and Exchange import/export via the share sheet. The embedded CPU, display, audio, and input adapter remains future work; the UI reports this explicitly.

## What works

- Shared Swift 6 core and SwiftUI application for macOS and iOS.
- Persistent library, search, selection, installation date and launch timestamps.
- Transactional local package installation with versioned manifests.
- Relative DOS 8.3 entry points, symlink rejection, size limits, and duplicate protection.
- Private `C:` per program and app-owned shared `D:` Exchange folder.
- Import/export of Exchange files; Finder access on Mac.
- WinWorld page and mirror resolution, optional published SHA-512 validation, and direct HTTPS file imports.
- ZIP and supported 7z archive extraction with path/type/count/declared-size validation.
- Floppy-media preparation and editable startup programs after guest installation.
- Live floppy drive panel with disk selection, next-disk control, and mount confirmation from DOSBox-X. Previously imported disk sets are detected automatically.
- macOS DOSBox-X process lifecycle, stop control, generated configuration, and session logs.
- Automatic, checksum-verified engine preparation, cancellation/retry, offline reuse, and bundled-engine discovery.
- DOS/386 and Windows 3.1/486 configuration profiles using `core=normal` (interpreter).

## Verification

```sh
swift test
# Optional real-engine integration test; opens and closes an emulator window:
DOSMAC_TEST_ENGINE=/absolute/path/to/dosbox-x swift test
# Optional full engine download/install/offline-cache/DOS execution test (~90–98 MiB):
DOSMAC_TEST_ENGINE_DOWNLOAD=1 swift test
# Optional live WinWorld metadata test (does not download software):
DOSMAC_TEST_WINWORLD=1 swift test
# Optional download/checksum/extraction test of the Windows 3.1 floppy archive:
DOSMAC_TEST_WINWORLD_DOWNLOAD=1 swift test
```

The integration test installs a temporary package, runs a DOS batch program, waits for clean process exit, and verifies the file written to the host through `D:`. Without the environment variable, this test is explicitly skipped. Unit tests exercise installation persistence, launch configuration, failed installs, duplicate installs, symbolic links, and command/path injection.

## Architecture and next milestones

See [architecture](docs/architecture.md), [package format](docs/packages.md), and [roadmap](docs/roadmap.md).

The design uses instruction and hardware emulation, with an integrated DOS environment initially and a future disk-image boot path for Windows 9x. A DOS API compatibility layer alone would not cover 386 protected mode, device drivers, or Windows 9x boot requirements.

## Data and trust

Data lives under the app's Application Support `DosMac` directory. Each program has `DriveC`, `installed.json`, `session.conf`, and `session.log`. `Exchange` is shared by all programs and should contain only files intended for guests.

The current external macOS emulator runs with the user's permissions. Private drive layout and package validation are **not a security sandbox**; run trusted DOS software. Web imports are user-initiated and stored privately; they do not execute native host installers. There is no curated catalog, telemetry, DosMac clipboard bridge, JIT, or bundled OS image in this preview. DOSBox-X may expose its own integration features in its separate window.

DOSBox-X is a separate GPL-licensed dependency, not vendored or included in this repository. Before an embedded-core release, choose the project's distribution license and satisfy all upstream license and source obligations. Windows and commercial DOS software must be supplied from sources the user is entitled to use. No OS image or third-party software archive ships with the app. SWCompression and BitByteData are MIT-licensed Swift Package Manager dependencies; see [third-party notices](THIRD_PARTY_NOTICES.md).
