# Managed PC architecture

## Product direction

DosMac is moving from a DOS program launcher to a native manager for complete x86 PCs. The first reference stack is **MS-DOS 6.22 → Windows 3.1 Retail → Word 6 for Windows**. DOSBox-X remains under the Legacy DOSBox tab so existing installations continue to work. Their folder-backed drives are not silently converted into bootable OS disks.

## Why QEMU

QEMU provides a real PC platform, bootable hard disks, BIOS, floppy controllers, IDE CD-ROM, and a documented machine-control API. The initial hardware is an i440FX/PIIX PC with interpreted/translated 486 or Pentium CPU, Cirrus VGA, PS/2 input, and Sound Blaster 16. CPU, RAM, and disk sizes are profile defaults, not proof that every DOS or Windows release is compatible.

86Box has a stronger focus on accurate vintage hardware and remains a possible compatibility backend. It is not selected first because the application's central requirement is reliable programmatic management and future MCP control. Apple Virtualization.framework cannot run an x86 DOS guest directly on an Apple Silicon CPU.

## Implemented boundaries

| Layer | Responsibility |
| --- | --- |
| `DosMacVM.MachineStore` | Validated machine metadata, sparse QCOW2 system disk, owned media copies |
| `QEMUArguments` | Explicit hardware, stable removable-drive IDs, TCG, firmware, BIOS boot order |
| `MachineSession` | Lifecycle, pause/resume, media insertion/ejection, keyboard, pointer and text-screen observation |
| `QMPConnection` | JSON command IDs, asynchronous replies/events, cancellation, timeouts and process-pipe transport |
| `RFBDisplay` | Native framebuffer delivery over a private UNIX socket; Raw and DesktopSize decoding |
| `MachineDisplayView` | Display rendering and focused native keyboard/relative mouse input inside DosMac |
| `ReferenceStackProvisioner` | User-requested downloads for exact DOS/Windows/Word releases and grouped disk sets |
| `DOS622Installer` | Conservative English DOS Setup rules, confirmed QMP disk changes, reboot and version verification |
| `Windows31Installer` | Retail SETUP.SHH, guest-side source staging, batch Setup and installed-file verification |
| `Word6Installer` | DISK1–DISK9 source layout, SHARE prerequisite, quiet Setup and installed-file verification |
| `GuestScreenText` | Read-only macOS Vision observation of graphical errors; no automatic dialog acceptance |

The application never needs macOS Accessibility to control a QEMU machine. Keyboard and mouse input go to the guest device model, not another application's window. QMP is carried over process pipes. The graphical connection is a UNIX-domain socket inside a mode-0700 per-session directory; no VNC or QMP TCP listener is exposed. Transport chunks pass through one ordered stream consumer: creating a separate Task per chunk can reorder actor delivery and corrupt the byte stream. A desktop resize always requests a complete framebuffer refresh.

## Machine layout

```text
Application Support/DosMac/Machines/<UUID>/
  machine.json
  disk.qcow2
  Media/<UUID>.img
  Media/<UUID>.iso
  qemu.log
```

Imported disk sets retain their labels and purpose: DOS Setup, Windows Setup, or Word Setup. Large ISO files are copied directly instead of passing through the legacy 32 MiB archive importer. The system HDD is owned exclusively by QEMU while running; QEMU's image locking rejects a second writable instance. Changing the boot-device preference is allowed only while stopped. Power-off is explicit because old guest operating systems can lose data if interrupted.

Host/guest file exchange must use a controlled transfer medium or a guest agent. The legacy folder-backed Exchange drive is not automatically exposed to real MS-DOS/Windows machines. A bounded FAT12 reader/writer supports persistent exchange floppies. The UI can create blank disks or populate them with Mac files, insert them through the ordinary drive panel, and export their root files into a fresh host folder while stopped. The first implementation is limited to 1.44 MB and strict DOS 8.3 names using letters, digits and underscores. It rejects symlink inputs and never replaces existing host files.

The current Files workspace also offers a 64 MiB FAT16 IDE disk with exclusive host/guest ownership. macOS mounting happens only while QEMU is stopped, and startup performs a non-forced detach. A separate, private Samba process exposes a machine-owned folder to Windows 9x through restricted QEMU guest forwarding. It does not use macOS system File Sharing. See [host sharing and Windows 9x](host-sharing-and-windows9x.md).

## One-click installation model

One click should start a tested, versioned recipe, not a generic sequence of blind Enter presses. A recipe must identify exact release media, group disks, create a machine, choose boot order, observe expected installer screens, mount the requested disk/CD, and verify the installed product before recording completion.

The current reference provisioner prepares all three release disk sets in a fresh machine and starts the DOS assistant. Unknown DOS prompts and license review stop automation with a visible needs-attention state. DOS is marked installed only after booting from HDD and observing version 6.22. Windows 3.1 is staged on HDD and installed with its original SETUP.SHH schema. Word 6 requires separate DISK1–DISK9 folders, matching the relative paths in WINWORD6.INF, and SHARE.EXE. Its quiet installer runs inside Windows. Each batch uses a fresh acknowledgement token, checks installed files, and flushes SMARTDrive before completion. Graphical errors are observed with macOS Vision and handed back for review. Word’s exact successful-completion notice is acknowledged once; installed files are checked afterward. The default owner is “DosMac User”; a custom identity form, recovery snapshots and resumable downloads are still pending. Downloading media alone never marks a product installed.

Windows 3.1 supports batch Setup via `/H:<answer-file>`; use the exact release's SETUP.SHH schema. The selected Word 6 release has its own recipe; this does not cover every Word/Office edition. Windows 95/98 need boot/CD variants, version-specific unattended files, driver profiles, and post-reboot verification. Some 95 CDs are not bootable and require a boot floppy. These are separate recipes, not assumptions hidden in the generic machine profile.

Windows9xRecipe now provisions pinned English CD media, patches an OEM startup floppy without moving its kernel, and stages Setup onto a new FAT16 system disk. The partition uses LBA type 0x0E and whole 64-head/63-sector BIOS cylinders; the BPB and QEMU geometry agree, including the final cluster. Original DOS helper programs acknowledge flushed staging and first-Windows-start completion. License and product-key review remains explicit. Full desktop acceptance is tracked separately from reaching Setup.

## Engine delivery

The development application supports an explicit `DOSMAC_QEMU_PATH`, a bundled QEMU tree, and existing local installations. `scripts/bundle-qemu.py` assembles a local macOS developer app with QEMU, its non-system dylib closure, BIOS/VGA firmware and VNC keymaps, rewrites library paths, and ad-hoc signs the result. It does not download or bundle DOS/Windows/Word images.

Run `scripts/build-win9x-bios.py` before bundling. It builds pinned SeaBIOS with PnP BIOS disabled so Windows 9x detects the PCI bus. The bundle retains this firmware’s exact source archive, configuration and license. Only managed Windows 9x recipes select it; a missing compatibility BIOS fails startup with a clear error and cleans up the private sharing process.

This script is not a production release pipeline. Distribution still needs complete dependency notices and corresponding source where required, versioned engine manifests, signed/notarized architecture-specific artifacts, and CI verification on Intel and Apple Silicon. The current local bundled engine has been exercised on Apple Silicon. No iPhone QEMU runtime is shipped; that requires an embedded interpreter build and platform-specific lifecycle work. UTM SE is evidence that a no-JIT route exists, not a drop-in runtime dependency.

## Future MCP boundary

Expose semantic operations through the same machine service: list/create machines, provision a validated recipe, start/pause/stop, insert an owned disk, observe a frame or text screen, send a bounded guest command, and exchange files. MCP must not expose unrestricted QMP, arbitrary host paths, or host shell execution. Installation state and checkpoints must remain in the app's machine records so automation is resumable and reviewable. No MCP server is implemented in this change.

## Verification

Local acceptance passed for the pinned reference stack: all three products installed on a new HDD, installed files survived a cold boot, and Word created a compound `.DOC` containing the test text, which was exported unchanged from its floppy. The installation took 352 seconds; the subsequent launch/save/export test took 31 seconds. Source downloads and their published checksums were verified separately; the final clean-install repeat reused private prepared media because WinWorld returned HTTP 429. Recovery snapshots, arbitrary release support and the iPhone runtime remain pending.

`DOSMAC_TEST_QEMU=1 swift test` boots an original test sector, checks guest VGA text and native framebuffer updates, pause/resume, keyboard/mouse injection, exact disk insertion, and CD eject/insert. `DOSMAC_TEST_DOS_SETUP=1 swift test` is opt-in: it downloads the selected DOS 6.22 media from WinWorld and exercises the installation recipe in a disposable machine. `DOSMAC_TEST_STACK_SETUP=1 swift test --filter actualReferenceStackInstallation` exercises all three installation stages on a fresh HDD, then restarts and checks the installed files again. `DOSMAC_TEST_KEEP_STACK=1` retains that private test machine for diagnosis; failures also retain it. Set `DOSMAC_TEST_SOURCE_MACHINE=/absolute/path/to/machine.json` to copy already prepared disk sets into a new blank machine instead of downloading them again. `DOSMAC_TEST_WORD_WORKFLOW_MACHINE=/absolute/path/to/machine.json swift test --filter launchesWordSavesDocumentAndExportsIt` exercises actual Word startup, a document save to the exchange floppy, and host export. These opt-in tests use privately downloaded media. Ordinary tests use original fixtures and do not download or redistribute third-party OS media.

References: [QMP](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html), [private VNC sockets](https://www.qemu.org/docs/master/system/vnc-security.html), [86Box](https://86box.net/), [UTM iOS engines](https://docs.getutm.app/installation/ios/), [Microsoft's archived Windows 3.1 Setup switches](https://ftp.zx.net.nz/pub/archive/ftp.microsoft.com/MISC/KB/en-us/85/125.HTM).
