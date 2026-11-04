# Host files and Windows 9x

## Shared disk

Files → **Create & open shared disk** enables a private 64 MiB FAT16 hard disk. It appears as D: on a computer with a single primary C: partition. Multiple partitions can change drive letters; adding it can also move the CD-ROM letter. It works without extra guest drivers in DOS 6.x, Windows 3.x, and Windows 9x. macOS supports folders and long names; DOS sees the corresponding short names.

The same image is owned by exactly one operating system at a time. Opening it on Mac requires a stopped guest. Before QEMU starts, DosMac inspects `hdiutil info` and detaches only the matching app-owned image. It never forces an unmount. An open host file that prevents ejection blocks guest startup rather than allowing concurrent writes. Exit Windows after saving before powering off. Open the disk in Finder again to retrieve guest files. No simultaneous host mounting of an active QEMU disk is supported.

## Live folder

Files → **Enable & open shared folder** creates the computer's own `Shared` directory. Enable it while stopped, then start the guest. Windows can map `\\10.0.2.4\DOSMAC` to a drive letter; host and guest changes are immediately available. Windows needs the AMD PCnet driver, TCP/IP, and Client for Microsoft Networks. Ordinary DOS and Windows 3.1 do not contain that client stack; use the shared FAT16 disk there.

An app-private, unprivileged Samba process serves only that directory over SMB1/NT1. It binds to 127.0.0.1 on an ephemeral port and lives only for the VM session. QEMU's restricted user network forwards guest port 139 through a fresh local relay for each connection. This does not enable macOS system File Sharing, expose a LAN listener, or give the guest general network access. Guest authentication maps to the current app user; symlinks and wide links are disabled. Do not put host files you do not want the guest to access into this directory.

The developer bundler includes Samba and its linked libraries when installed. Official redistribution must include the corresponding licenses and source obligations, just as for QEMU. The macOS system SMB daemon is not used.

## Windows 95 and 98 SE setup

Discover and Computers expose an experimental **Install Windows** sheet. Source media comes from public Internet Archive items, downloaded into a private user cache, verified against pinned sizes and SHA-1 values, and copied into a new computer. Neither Windows images nor keys belong in the repository or app distribution. The older 32 MiB generic DOS package importer remains separate from this large-media path.

The recipe uses a new 1 GiB FAT16 primary partition, an English Windows 98 SE OEM startup disk, and an installation CD containing WIN98 or WIN95. The startup disk's original boot sector, kernel layout, and unrelated files are preserved while CONFIG.SYS/AUTOEXEC.BAT and support files are patched. Only the newly created computer's C: is formatted. The CD is assigned R: so the shared disk cannot displace it. Setup files are copied to C: before installation; the assistant ejects the startup floppy before Windows Setup can reboot.

Managed Windows 9x computers use SeaBIOS 1.17.0 built with `CONFIG_PNPBIOS=n`. Stock SeaBIOS can cause Windows 98 to mistake the PCI bus for a broken Plug and Play BIOS, hiding the network card and other PCI hardware. `scripts/build-win9x-bios.py` verifies pinned upstream source, builds the compatibility firmware, and retains its configuration, license, source archive and build manifest for bundling. Generic DOS computers keep their existing firmware. Local commercial-media tests can select the firmware with `DOSMAC_WIN9X_BIOS=/absolute/path/to/bios-win9x.bin`. An already installed computer with the misdetected bus needs its Plug and Play BIOS driver changed to PCI bus once; changing firmware does not rewrite its registry. See the [SoftGPU developer’s QEMU investigation](https://github.com/JHRobotics/softgpu/blob/main/qemu.md#pci-bus-detection-fix).

MSBATCH.INF supplies the installation directory, user information and networking defaults. A key can be entered in the sheet or left for Setup. It is not logged or included in machine/library JSON; it is present in the private answer file supplied to Windows. License-page skipping is opt-in and requires the user to indicate acceptance in the sheet. Unknown prompts and product-key/license dialogs stop the assistant for direct guest control. **Continue installation** resumes the same computer rather than creating another one.

Microsoft documents an additional OEM behavior: Windows 95 may require the key to be re-entered and Windows 98 may require confirming its prefilled key, even when supplied in MSBATCH.INF. The assistant leaves those screens for review. See [Microsoft KB Q263281](https://ftp.zx.net.nz/pub/Patches/ftp.microsoft.com/MISC/KB/en-us/263/281.HTM).

The injected RunOnce batch performs first-start preparation, but Setup can run it before its final restart. The assistant releases that batch and only marks installation complete after Explorer visibly displays the desktop. Downloading the ISO, reaching Setup, or completing RunOnce does not count as installation success. The Windows 3.1 reference collection and its verified installation remain separate.

## Sources

- [QEMU virtual FAT restrictions](https://www.qemu.org/docs/master/system/images.html#virtual-fat-disk-images): modifying an exported directory during guest use is unsupported, so writable vvfat is not used for shared host storage.
- [QEMU guest forwarding](https://www.qemu.org/docs/master/system/qemu-manpage.html): restricted guest network and per-connection relay.
- [Samba configuration](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html): NT1, loopback binding, guest mapping, symlink restrictions and NBT transport.
- [Windows 98 SE OEM media](https://archive.org/details/microsoft-windows-98-second-edition-oem-x05-29232).
- [Windows 95 CD media](https://archive.org/details/win95_202004).
- [Microsoft Windows 95 Resource Kit](https://www.bitsavers.org/pdf/microsoft/resource_kits/Windows_95_Resource_Kit_1995.pdf): MSBATCH.INF and first-start custom actions.

## Validation

Default tests cover boot-disk patch preservation and answer-file injection rejection. `DOSMAC_TEST_STORAGE=1` exercises mounting, directories, a multi-megabyte file and remounting on macOS. `DOSMAC_TEST_SAMBA=1` tests real NT1/NBT reads, writes and rejection of a symlink outside the share. `DOSMAC_TEST_WIN9X_BOOT=/path/to/windows98se-boot.img` runs the real startup disk against an inert original CD fixture, checks HDD boot, and verifies host → DOS → host file transfer without executing Windows Setup. Commercial-media installation acceptance is separate and opt-in.

On November 4, 2026, these storage and NT1 tests passed locally, along with the real DOS HDD/transfer fixture and macOS/iPhone simulator builds. The native app's shared disk mounted in Finder and appeared in Word 6's Windows 3.1 drive selector. Windows 98 SE reached Explorer, shut down normally through Start, and cold-booted from its HDD back to the desktop. The revised assistant recognized that desktop and published its Library entry. D: appeared in My Computer. This existing installation required the PCI bus driver repair described above; guest-network acceptance remains separate. Windows 95 reached license review with both stock and compatibility SeaBIOS; its full desktop acceptance remains pending. The bundled QEMU smoke test also enables the shared disk, private network and compatibility firmware; the PCnet boot ROM is disabled for the data-only connection, and its firmware remains included for compatibility.

The DOS transfer fixture also copies a 3 MiB binary from the shared disk to C: and back, then compares it byte-for-byte on Mac. The shared IDE drive exposes a matching 16-head/63-sector geometry that includes its partial final cylinder, so DOS transfers are not limited to the first cylinder. The 1 GiB system partition instead ends at a whole cylinder and uses the LBA FAT16 partition type.
