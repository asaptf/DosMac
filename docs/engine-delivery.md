# Engine delivery

## Current macOS experience

The user installs a DOS program and clicks Launch. DosMac reuses an available engine or downloads the official DOSBox-X 2026.10.01 release. It automatically chooses arm64 for an Apple Silicon build and x86_64 for an Intel build. An Intel build running under Rosetta uses the Intel engine.

The initial download is approximately 90 MiB (arm64) or 98 MiB (Intel). A sidebar indicator shows download progress followed by verification and installation. The user can cancel; a later Launch retries. Engine settings also has a Prepare engine now button. After installation, launching requires no network connection.

The lookup order is an optional custom executable, the developer environment override, an optional bundled engine, a managed engine, and common system installation paths. The advanced custom path is optional.

## Integrity and storage

Download URLs and SHA-256 digests are pinned in `ManagedEngine.swift`, based on the official release asset metadata:

| Architecture | SHA-256 |
| --- | --- |
| arm64 | `8514ab856e8ac2611fbdac7adf334c34085c1e00d700a88711f842adec50240f` |
| x86_64 | `a0605348355ff4a45c781f124c44122e97156ae3f7d048637f545c9de641bedb` |

Only an archive matching its pinned digest is passed to the system ZIP extractor. The complete upstream archive, including its app, libraries, resources, license, and readme, is extracted in a staging directory. The SDL2 executable and license must be present. A receipt is written before an atomic directory rename publishes the installation. Failed or cancelled staging is removed; a prior installation is retained until a replacement has been verified. Interrupted process termination can leave an ignored `.install-*` directory; it is never treated as an installed engine.

Managed files live in Application Support under `DosMac/Engines/dosbox-x-2026.10.01-<architecture>/`. No administrator access or modifications to `/Applications` are required. Network input is capped at 128 MiB and the download timeout is ten minutes. The engine archive is independent of the smaller limits for user program imports.

The installer does not strip quarantine flags, disable Gatekeeper, or change signature enforcement. The upstream macOS release is ad-hoc signed rather than a notarized DosMac distribution. OS security restrictions may still prevent launch on some machines; a fully seamless downloadable application release requires a properly signed/notarized delivery pipeline. Only Apple Silicon execution has been verified locally; the Intel digest is pinned from official metadata but Intel execution still needs hardware validation.

## Bundled distribution and iPhone

Discovery already supports a future full app bundle at `DosMac.app/Contents/Resources/Emulator/dosbox-x.app`. No binary is currently bundled. Preparing that distribution requires reviewing the upstream GPL and all linked libraries, providing the required notices and corresponding source, and signing/notarizing the complete application.

An iPhone runtime must embed the interpreter and native display/audio/input adapter in the signed app. Downloading or bundling the macOS executable cannot provide that runtime. Automatic preparation is therefore macOS-only; the iPhone preview continues to state that DOS execution is unavailable.

## Tests

Local tests cover complete installation and license retention, digest rejection before extraction, preservation of a prior installation when a replacement is incomplete, and cancellation without publishing an engine. The opt-in `DOSMAC_TEST_ENGINE_DOWNLOAD=1 swift test` downloads the actual official archive, installs it, verifies cache reuse without a second download, launches a DOS batch program, and verifies its output through the host Exchange folder.
