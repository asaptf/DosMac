# DosMac Guest Tools

Guest Tools integrates the Windows mouse with the Mac pointer and, when the live shared folder is enabled and mapped to H:, installs a small display agent. In **Computers → Settings → Install Guest Tools**, shut down Windows first, then press the installation button. DosMac saves a private recovery copy of the stopped QCOW2 disk, boots Windows, supplies an embedded installation floppy, stages the driver, applies its INF through Windows, verifies the installed files, and restarts Windows. The final success condition is QEMU reporting an active absolute pointing device. Downloading or copying the driver alone is not success.

The desktop and Run-dialog recognizer currently targets the English Windows 95/98 recipes. Password prompts and unfamiliar screens stop the helper for local review. Pausing the helper does not undo guest file changes. If the mouse and requested display integration are already active after boot, the helper finishes without reinstalling them. With sharing disabled, it installs the mouse component alone.

## Pointer behavior

QEMU's VMPort is enabled explicitly. DosMac monitors the current input device, rather than assuming that an available tablet is active. With absolute input active, the first click is delivered to Windows and the cursor crosses the guest boundary freely. Coordinates follow the actual image rectangle, excluding letterboxing, and normalize to QMP's 0–32767 range. Movement is coalesced; button transitions remain ordered. Leaving the guest releases held mouse buttons, and losing focus restores the host cursor.

If the guest selects relative input, DosMac retains its existing click-to-capture PS/2 behavior and Control + Option release. Real DOS games and Windows fullscreen transitions need additional acceptance testing.

## Display controls

With Guest Tools connected, **Now playing → Display** offers the modes reported by Windows and **Fit Windows to window**. Automatic fitting chooses the largest reported mode that fits the guest view in Mac logical points, waits for window resizing to settle, and asks Windows to switch modes. The preference is saved per computer. Choosing a fixed resolution turns fitting off.

This changes the actual Windows framebuffer, rather than only scaling an image. The native viewer handles the new frame size and keeps pointer coordinates aligned. Color depth is retained when possible. Resolution changes update Windows' saved display mode, as its own display settings do. This also lets the legacy shell resize its desktop and taskbar. A rejected or unconfirmed mode stops automatic fitting and retains a usable scaled display.

The first version uses the existing Cirrus driver. Accepted Windows 98 modes are 640×480, 800×600, 1024×768 and 1280×1024; exact availability comes from the installed driver. Arbitrary widescreen sizes and a replacement virtual display driver remain future work.

The original CRT-free Win32 agent is built from `GuestTools/Agent`. Its fixed, bounded request/acknowledgement protocol uses `Shared/DMTOOLS` through the already isolated SMB share. It does not execute commands or forward the clipboard. Samba oplocks are disabled so guest reads see host changes promptly. Partial, stale and oversized replies are ignored. See the [agent source and protocol](../GuestTools/Agent/README.md).

## Driver provenance and recovery

The embedded QEMouse v1.03 driver and INF are unmodified upstream release files. Their SHA-256 values are verified before installation. The app also includes the GPL-2.0 license, exact tagged source archive and provenance notice under `Sources/DosMacApp/Resources/GuestTools`. Upstream: https://github.com/qemus/qemouse, commit `fe592cba242b31a39b5f1f3c061969b813caf01a`. The release binary is upstream-built; local reproducibility is not claimed.

The recovery disk is stored under the computer's `Backups/GuestTools-<UUID>/disk.qcow2`. The original Windows SYSTEM.INI is also preserved once as `C:\DMTOOLS\SYSINI.BAK`. Full-disk recovery requires a stopped guest and replaces subsequent guest disk changes; keep the current disk as another recovery copy before restoring. The original mouse entry can instead be recovered from the INI backup inside the guest.

## Validation and remaining components

Unit tests exercise coordinate boundaries, invalid dimensions and selecting the current mouse device. An opt-in original boot-code fixture uses the VMware I/O protocol to switch a real QEMU instance between absolute and relative input, sends both button transitions, and checks host mode detection.

`DOSMAC_TEST_GUEST_TOOLS_DISK` enables installation acceptance on a private copy of an already licensed Windows 98 disk. Set `DOSMAC_TEST_GUEST_TOOLS_FILES` to the embedded GuestTools source directory and `DOSMAC_WIN9X_BIOS` to the compatibility firmware. The test requires actual driver activation and persistence through cold boot. This passed locally on 2026-11-04 on a private Windows 98 SE copy, including INF installation, a Windows restart, normal shutdown, and a fresh QEMU boot (120 seconds total). No commercial images or credentials are bundled in the test suite.

On 2026-11-06 the final display acceptance test installed the agent on a private Windows 98 SE copy with the mouse already installed, confirmed an 800×600 framebuffer and matching taskbar bounds, automatically fitted an 1100×800 view to 1024×768, restored 640×480, completed normal shutdown and checked automatic agent startup through a fresh QEMU boot (87 seconds total). The native Display menu and saved fitting preference were also checked. A final visual pass of the rebuilt agent remains pending because the Mac locked before it could be opened. A richer guest control/clipboard agent, arbitrary display modes, and installers for Windows 3.x and DOS remain upcoming components.
