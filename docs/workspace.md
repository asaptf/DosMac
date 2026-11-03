# Library-first workspace

The application has one sidebar and one Library. Users choose software, not an emulator tab. The shared app-level models keep native computers, imported packages, and guest shortcuts alive across navigation and multiple windows.

## Library entries and launch behavior

The verified reference computer exposes Windows 3.1 and Word 6 automatically from its completed installation record. Other installed guest apps can be registered with a title, computer and validated DOS 8.3 executable path. Editing a shortcut preserves its identity and installation-media order. Guest shortcuts live in `Application Support/DosMac/Library/apps.json`; existing packages keep their original storage and launch settings.

A stopped native computer boots its HDD before opening an app. A running session is resumed without discarding guest work. If it is already at the DOS prompt, a requested app can start there directly. Launching a different app while a Windows GUI is active currently opens that session; users can launch it from the guest desktop. The UI does not reset or power off a computer to switch apps. Imported packages retain their compatibility window and original disk/input controls.

## Discover and adding software

Search runs only on explicit submission or a source-filter change after a search. WinWorld uses its product search and public release pages. Internet Archive uses its public search and metadata APIs. Failures are isolated per provider, cancellation prevents stale results, and both source websites remain available through explicit links. External titles/descriptions are bounded plain text, not executable web content.

Supported Internet Archive files are public ZIP, 7z and DOS EXE/COM/BAT downloads within the existing 32 MiB limit. Published SHA-1 values are verified when present. Original WinWorld SHA-512/SHA-1 verification remains in place. Archive extraction and package path validation are unchanged.

A downloaded disk set is copied to an explicitly selected, stopped computer. The user chooses whether Setup runs in DOS, Windows 3.1, or boots directly from its first disk. The new Library entry is labelled **Setup ready** and remembers the source and ordered disk IDs. A new empty computer can be created without discarding the prepared download. Unknown installers remain interactive. After installing, **Add installed app** registers the actual guest executable; downloading disks never claims that application setup is complete.

Plain DOS packages use the established compatibility importer. Both paths select the added entry in Library and support **Open after adding**. Exact automatic OS/application setup remains limited to the featured reference collection.

## Session and files

The native player keeps controls above the screen and puts floppies/CD-ROM in a compact popover. Installer shortcuts scope the next-disk action to their own bank, with an option to show all computer media. Leaving the player releases captured input but keeps the VM running. Power-off remains explicit to protect guest data.

Files separates a native computer's transfer floppies from imported packages' shared D: folder. Native transfer preparation/export remains limited to a stopped computer. Imported-package files retain ordinary file import and share/export controls, including in the iPhone library preview.

## Validation

Parser fixtures cover product links, result deduplication, Archive identifiers, private/oversized/traversal file rejection, and URL query encoding. Guest-library tests cover persistence, identity-preserving edits, ordered media, and rejecting command metacharacters or path traversal. macOS and iPhone simulator builds validate the shared UI. Native PC boot/input/media/display tests remain part of CI; commercial-media installation tests stay opt-in.

References: [WinWorld search](https://winworldpc.com/search), [Internet Archive metadata API](https://archive.org/developers/md-read.html).
