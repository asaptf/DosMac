# Floppy disk controls

When a running program has installation media, the **Floppy drive · A:** panel appears above the library. It belongs to the running session, even if a different library card is selected. The panel shows the confirmed disk number, total disk count, and source label when available.

1. When Setup requests another disk, click **Next disk**, or choose a disk and click **Insert selected disk**.
2. Wait for the panel to confirm the inserted disk. The emulator is brought forward while the change is made.
3. Click **Show installer** if necessary, then press Enter in Setup to continue.

Any disk can be selected, including an earlier disk. Selection cycles forward through the mounted chain and confirms each step. The last disk wraps to the first. The controls do not automatically press Enter or answer installer prompts.

## macOS permission

DosMac currently runs DOSBox-X in a separate process. macOS requires Accessibility permission before DosMac can send its documented disk-switch shortcut to that process. Click **Enable disk controls…**, allow DosMac in System Settings → Privacy & Security → Accessibility, then return to DosMac. Permission is never requested simply by launching a program, and tests do not grant it automatically.

Without permission, bring DOSBox-X forward and press **F12 + O**; on some Mac keyboards, also hold **Fn**. This is the upstream default shortcut. The panel still observes manual swaps and updates the confirmed disk. A custom engine or modified mapper may use a different host key; use its own disk menu in that case.

## Confirmation and limitations

The adapter targets only the PID owned by the running session. It posts the F12/O key sequence after activating that emulator, then waits for a `Drive A: disk N of M now active` acknowledgement in the session log. The UI never advances its disk counter merely because a key event was sent. If no expected acknowledgement arrives within three seconds, the operation stops and shows a contextual error. Unexpected disk counts disable disk selection rather than associating the wrong disk labels.

Disk labels and order are stored in optional manifest metadata for new imports. Existing `MEDIA/DISKnn.IMG` imports are discovered without redownloading or modifying them. This panel controls the disk set already mounted in drive A:; it does not insert arbitrary new images or control CD-ROM drives. The installer must still perform its own disk checks and copying. iPhone execution and disk controls await the embedded emulator.

Unit tests cover fragmented log decoding, invalid mount reports, metadata validation, legacy discovery and wraparound. The opt-in real-engine test mounts three original blank FAT12 images, substitutes a guest IMGSWAP transport for the macOS key sender, verifies actual log-confirmed transitions and backward selection, and checks that a missing acknowledgement leaves the last confirmed disk unchanged. The macOS Accessibility key transport requires a separate manual check with permission enabled.
