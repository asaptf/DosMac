# DosMac

A native home for DOS software on Mac and iPhone.

**Status: 0.1 developer preview.** macOS automatically prepares DOSBox-X on first launch and runs it in its own window. The iOS app builds and manages the library and Exchange files, but **does not run DOS yet**. No Windows installation has been tested in DosMac. This is the first working product slice, not a complete emulator release.

## Run on Mac

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

1. Click **Install Hello, DOS**. This installs an original, redistributable batch demo with one click.
2. Select the program and click **Launch**. On the first launch, DosMac downloads the official DOSBox-X release for your Mac, verifies its pinned SHA-256, and installs it privately. Progress and cancellation appear in the sidebar. The program then opens in the emulator's own window.
3. Open **Exchange**. The demo creates `HELLO.TXT` through guest drive `D:`.

No separate DOSBox-X installation, Homebrew, administrator password, or executable-path selection is needed. The initial download is approximately 90 MiB on Apple Silicon or 98 MiB on Intel. Later launches use the cached engine offline. **Engine settings → Prepare engine now** can prepare it ahead of time. If downloading fails, retry **Launch**. Existing system engines and optional custom paths remain supported. See [engine delivery](docs/engine-delivery.md).

Use **Import package** to select a `.dosmac` directory. The example at `Examples/HelloDOS.dosmac` is also importable. Packages are copied to application storage; originals are not modified. Duplicate installs are rejected rather than overwriting user data.

Use **Add from web** to paste a WinWorld product/download page or a direct HTTPS ZIP/7z/DOS-file URL. Select a release and click **Install**. Single-entry archives install directly; multiple entry points prompt for selection. Enable **Launch after installation** to start the program immediately. Floppy archives prepare a guest installer rather than pretending the program is already installed. See [software sources](docs/software-sources.md).

When Setup requests another disk, use the **Floppy drive · A:** panel above the library. Click **Next disk**, or choose a disk and click **Insert selected disk**. Return to the installer and press Enter after the panel confirms the inserted disk. On macOS, disk buttons require Accessibility permission for DosMac; click **Enable disk controls…** to open the system prompt. Without permission, use **F12 + O** in DOSBox-X (possibly **Fn + F12 + O** on a Mac keyboard). See [disk controls](docs/disk-controls.md).

In graphical Windows Setup, click inside the DOSBox-X screen to capture the mouse. DosMac enables click-to-capture automatically; the standard Windows 3.1 driver requires captured relative input. Press **Ctrl + F10** to release it (**Ctrl + Fn + F10** on some Mac keyboards), or use **Main → Capture mouse** in DOSBox-X. The running-session panel includes these instructions. See [mouse input](docs/mouse-input.md).

## After installing Windows

Stop the current session, select the same library item, and click its gear button. Set **Start in → DOS prompt on C:** and save to open the built-in DOS shell at `C:\>` without running the floppy installer. To start the installed Windows directly, click **Use installed Windows**, then **Save**. DosMac detects `WINDOWS/WIN.COM` and other installed `WIN.COM` entry points. Your installed files stay on the same private C: drive; no reinstallation is needed.

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
