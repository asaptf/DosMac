# Software sources

The first provider supports WinWorld product pages and individual download pages. The generic provider supports direct HTTPS links to ZIP, supported 7z archives, and DOS EXE/COM/BAT files. No API keys or site account are required. Authentication walls, CAPTCHA, quotas and HTTP failures are reported; they are not bypassed. The app does not crawl the catalog or automatically retry downloads against every mirror.

## User flow

1. Open **Add from web** and paste a source URL.
2. Click **Find downloads** and choose the exact release/language.
3. Choose the hardware profile and optionally enable **Launch after installation**.
4. Click **Install**. An archive with one DOS entry point installs automatically. Multiple entry points prompt for a selection.
5. For floppy archives, launch the prepared **Setup** item, complete the guest installer, then stop the session and use the gear beside **Launch** to choose the installed program's entry point.

This is one-action installation after a release is selected for ready-to-run packages. It is not a universal unattended installer. Future curated recipes can preselect entry points, disk ordering and validated unattended setup steps for specific releases.

## Source validation

- HTTPS links without embedded credentials. Ephemeral network session with no shared cookie or credential store.
- WinWorld links are resolved relative to the original page and restricted to the WinWorld domain during metadata parsing.
- Site-provided SHA-512 is checked when present. Mirrors may redirect to the site's download hosts.
- Requests respect ordinary server responses and download limits. No scraper bypass, quota reset or authentication workaround.
- Raw archive paths, entry types, case collisions, entry count and declared expanded size are checked before extraction.
- Archive paths cannot be absolute, contain a drive prefix, traverse parents, or include control characters. Links and special files are rejected.
- Sources may change HTML or mirrors; parser fixtures and opt-in live metadata tests make breakage visible.

## Preview limits

Downloads are limited to 32 MiB and declared expanded data to 128 MiB/20,000 entries. ZIP and 7z using supported codecs such as LZMA/LZMA2 are accepted. BCJ/BCJ2-filtered, encrypted and split archives are unsupported. SWCompression is not an isolated, memory-budgeted decoder; malicious-input hardening remains release work.

EXE files identified as Windows NE/PE are not offered as standalone DOS startup programs. A working Windows installation is required to run Windows applications. Windows 3.1 installation from disks remains an interactive, unverified compatibility workflow; Windows 9x bootable HDD/CD images are not supported yet.

Recognized raw floppy extensions are `.img`, `.ima` and `.dsk`, limited to standard floppy sizes and at most 32 disks. Files are renamed to safe `MEDIA/DISKnn.IMG` paths and passed to DOSBox-X `imgmount`. The initial disk order follows natural filename order; release-specific recipes are needed where labels differ. Setup runs from `A:` and writes to the program's private `C:`. Use DOSBox-X's disk-swap controls when prompted. A prepared installer is distinct from an installed application.

Each installed import records its original source URL as `source-url.txt` beside `installed.json`, not inside the writable DOS drive. Source availability does not establish a redistribution license; no third-party software is bundled or republished by DosMac.
