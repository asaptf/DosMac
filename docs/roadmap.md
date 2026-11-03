# Roadmap and acceptance criteria

## M1 — macOS vertical slice (current)

- [x] Native library, package installation, search and persisted state.
- [x] Real DOSBox-X launch with interpreted 386/486 profiles.
- [x] Automatic engine download, pinned checksum verification, private installation and offline cache.
- [x] Private program drive and shared Exchange directory.
- [x] Native iOS library and Exchange import/export build.
- [x] WinWorld metadata/mirror import and direct HTTPS ZIP/7z/DOS-file import.
- [x] Floppy-media setup launcher and startup-program selection.
- [x] Live disk panel with next/selected disk controls, legacy-media discovery, and emulator log acknowledgement.
- [x] Automated storage/configuration tests and an opt-in real-engine smoke test.
- [ ] Manual library, import and launch checks on both platform UIs.

## M2 — embedded emulator on both platforms

- Pin an upstream revision and produce reproducible interpreter-only builds.
- Implement and test a minimal C ABI, including stop and error propagation.
- Embed display and audio; support physical keyboard, touch keyboard and trackpad gestures.
- Test DOS real mode, 386 protected mode and a DOS extender with redistributable fixtures.
- Run on a physical iPhone without JIT or executable-memory entitlement.
- Verify pause/resume, interruption, audio route changes and application termination.

Exit: the same package runs on Mac and iPhone, renders correctly, plays audio, accepts input, and writes a file to Exchange. Battery, thermals and frame pacing are measured on named hardware.

## M3 — Windows 3.1

- Guided import from user-supplied installation media.
- Validated 386 Enhanced Mode, video, mouse, audio, and working-directory settings.
- File exchange round trip between a guest application and host.
- Compatibility matrix with actual versions and reproducible tests.

Exit: Windows 3.1 boots on both platforms; a user edits a document in Windows, exports it, and reopens it on the host.

## M4 — one-click catalog and library management

- Curated redistributable packages with explicit provenance and licenses.
- Trusted index, content digests, bounded downloads and validated archive extraction.
- Download/install progress, cancellation, retry and offline installed library.
- Backups, uninstall and upgrades preserving saves and user documents.
- Settings for per-program controls, memory and display.
- App icons, accessibility, localization and polished onboarding.

Exit: a fresh installation installs and runs a catalog title with one action, survives interrupted downloads, and preserves user data during an upgrade.

## M5 — Windows 95/98 research track

- Image creation, bootable installation and safe writable-disk ownership.
- Tested BIOS/IDE/PCI/CPU configurations and required drivers.
- Offline FAT exchange with image locking; avoid simultaneous guest/host writes.
- Benchmark boot time, memory and responsiveness on physical iPhone hardware.

Exit: documented reproducible boot and a file exchange round trip. Ship as experimental until tested; do not promise Windows 9x compatibility based solely on upstream capability.
