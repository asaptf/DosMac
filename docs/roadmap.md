# Roadmap and acceptance criteria

## Active QEMU roadmap

The primary direction is now [managed PC machines](machine-architecture.md). The first reference stack, selected by the user, is **MS-DOS 6.22 → Windows 3.1 Retail → Word 6**.

### PC platform foundation

- [x] Separate machine records and owned QCOW2 HDDs.
- [x] QMP lifecycle, pause/resume, reset, floppy and CD insertion/ejection.
- [x] Native in-app RFB framebuffer and direct guest keyboard/mouse input.
- [x] Private process-pipe/UNIX-socket control, with no Accessibility dependency.
- [x] Local developer engine bundling, including dylibs, BIOS and VNC keymaps.
- [x] Original boot-sector integration test against the real bundled engine.
- [x] First reference-media provisioner and grouped disk sets.
- [x] Real MS-DOS 6.22 unattended recipe test: blank HDD, disk changes, reboot and version verification.
- [x] Visual review of the native machine window, bundled BIOS display, and power controls.

### Finish the reference stack

- [x] Windows 3.1 SETUP.SHH generation, automatic source staging and installed-file verification.
- [x] Word 6 nine-disk recipe, SHARE prerequisite, recognized completion notice, and verified app launch.
- [x] A real Word document saved to the exchange floppy and exported to macOS.
- [ ] Custom owner/organization inputs and review flows for additional releases.
- [ ] Persisted recovery checkpoints before each installation stage.
- [ ] Resume prepared workflows after interruption without duplicate downloads or machines.
- [x] User-facing persistent FAT12 exchange floppies with Mac import and root-file export.

Exit: one prepared recipe installs all three products, boots from HDD, launches Word, saves a document, and exports it to macOS. Locally verified on 2026-11-03 against the selected English releases: installation on a blank HDD, cold boot, Word startup, document save, and host export. The clean installation took about six minutes. The final repeat reused privately prepared media after WinWorld returned HTTP 429.

### Guest integration

- [x] One-click Windows 98 mouse installation, restart and cold-boot acceptance.
- [x] Embedded QEMouse driver, pinned hashes, license and corresponding source.
- [x] Native absolute pointer with free host/guest crossing and relative-input fallback.
- [x] Windows 98 visual acceptance: click, double-click, drag and right-click.
- [ ] Windows 95 and Windows 3.x mouse acceptance.
- [x] Original Windows display agent, confirmed mode switching, and native resolution menu.
- [x] Windows 98 automatic fitting, normal shutdown and agent cold-boot acceptance.
- [x] Native Display menu and saved per-computer fitting preference.
- [ ] Final visual pass of the rebuilt display agent (Mac locked).
- [ ] Replacement virtual display driver and arbitrary widescreen resolutions.
- [ ] Guest control, clipboard and file-operation agent over a private host channel.

### Extend and release

- [ ] PC DOS compatibility and installation recipes.
- [x] Pinned Windows 95/98 CD and boot-floppy media, new-PC provisioning and batch answer files.
- [x] Exclusive host/guest FAT16 shared disk and app-private SMB1 folder service.
- [x] Windows 98 SE desktop, HDD cold boot, PCI/network drivers and live-folder transfer in both directions.
- [ ] Windows 95 desktop and driver acceptance, including live-folder mapping.
- [ ] Application recipes for additional Word/Office versions, tied to exact source media.
- [ ] Signed/notarized self-contained engine distributions, complete license/source packages, Intel validation.
- [ ] Embedded no-JIT iPhone runtime and physical-device performance/lifecycle testing.
- [ ] Semantic MCP service over the same machine API, after operations and recovery are stable.

## Archived DOSBox milestones

The following describes the retained Legacy DOSBox backend. It is not the primary runtime plan.

### M1 — macOS vertical slice

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
