# DosMac Guest Tools

The first component integrates the Windows mouse with the Mac pointer. In **Computers → Settings → Install Guest Tools**, shut down Windows first, then press the installation button. DosMac saves a private recovery copy of the stopped QCOW2 disk, boots Windows, supplies an embedded installation floppy, stages the driver, applies its INF through Windows, verifies the installed files, and restarts Windows. The final success condition is QEMU reporting an active absolute pointing device. Downloading or copying the driver alone is not success.

The desktop and Run-dialog recognizer currently targets the English Windows 95/98 recipes. Password prompts and unfamiliar screens stop the helper for local review. Pausing the helper does not undo guest file changes. If the driver is already active after boot, the helper finishes without reinstalling it.

## Pointer behavior

QEMU's VMPort is enabled explicitly. DosMac monitors the current input device, rather than assuming that an available tablet is active. With absolute input active, the first click is delivered to Windows and the cursor crosses the guest boundary freely. Coordinates follow the actual image rectangle, excluding letterboxing, and normalize to QMP's 0–32767 range. Movement is coalesced; button transitions remain ordered. Leaving the guest releases held mouse buttons, and losing focus restores the host cursor.

If the guest selects relative input, DosMac retains its existing click-to-capture PS/2 behavior and Control + Option release. Real DOS games and Windows fullscreen transitions need additional acceptance testing.

## Driver provenance and recovery

The embedded QEMouse v1.03 driver and INF are unmodified upstream release files. Their SHA-256 values are verified before installation. The app also includes the GPL-2.0 license, exact tagged source archive and provenance notice under `Sources/DosMacApp/Resources/GuestTools`. Upstream: https://github.com/qemus/qemouse, commit `fe592cba242b31a39b5f1f3c061969b813caf01a`. The release binary is upstream-built; local reproducibility is not claimed.

The recovery disk is stored under the computer's `Backups/GuestTools-<UUID>/disk.qcow2`. The original Windows SYSTEM.INI is also preserved once as `C:\DMTOOLS\SYSINI.BAK`. Full-disk recovery requires a stopped guest and replaces subsequent guest disk changes; keep the current disk as another recovery copy before restoring. The original mouse entry can instead be recovered from the INI backup inside the guest.

## Validation and remaining components

Unit tests exercise coordinate boundaries, invalid dimensions and selecting the current mouse device. An opt-in original boot-code fixture uses the VMware I/O protocol to switch a real QEMU instance between absolute and relative input, sends both button transitions, and checks host mode detection.

`DOSMAC_TEST_GUEST_TOOLS_DISK` enables installation acceptance on a private copy of an already licensed Windows 98 disk. Set `DOSMAC_TEST_GUEST_TOOLS_FILES` to the embedded GuestTools source directory and `DOSMAC_WIN9X_BIOS` to the compatibility firmware. The test requires actual driver activation and persistence through cold boot. This passed locally on 2026-11-04 on a private Windows 98 SE copy, including INF installation, a Windows restart, normal shutdown, and a fresh QEMU boot (120 seconds total). No commercial images or credentials are bundled in the test suite.

Adaptive guest display resolution, a guest control/clipboard agent, and installers for Windows 3.x and DOS are separate upcoming components. Window resizing currently scales the existing framebuffer; it does not change Windows' resolution.
