# Local package format v1

A package is a directory with the `.dosmac` extension:

```text
HelloDOS.dosmac/
  manifest.json
  payload/
    HELLO.BAT
```

```json
{
  "formatVersion": 1,
  "id": "org.dosmac.hello",
  "title": "Hello, DOS",
  "summary": "Your first DOS program.",
  "version": "1.0",
  "author": "DosMac",
  "license": "CC0-1.0",
  "executable": "HELLO.BAT",
  "profile": "dos"
}
```

Identifiers contain lowercase alphanumerics separated by dots or hyphens, up to 80 characters. Entry points use relative DOS 8.3 paths and end in `.EXE`, `.COM`, or `.BAT`. Either slash direction is accepted. Use the same letter case in the manifest and the actual payload for compatibility with case-sensitive host filesystems. Spaces, drive prefixes, parent traversal, arguments, environment expansion and batch command metacharacters are rejected.

Profiles are `dos` and `windows31`. A profile chooses emulator hardware settings; it is not proof that a program or Windows installation works.

The manifest limit is 64 KiB. The payload limit is 512 MiB and 20,000 entries. Symbolic links, special files and case-colliding paths are rejected. Duplicate IDs are rejected. Unsuccessful installs never appear in the library. Imports copy data; DOS may subsequently modify its private copy.

The format does not yet support archives, remote URLs, install scripts, launch arguments, dependencies, updates, or disk-image boot. Only add these through a new validated schema, preserving version-1 behavior.

To package a user-owned Windows 3.1 installation, use a `windows31` profile and an entry point such as `WINDOWS/WIN.COM`, placing all installed files under `payload`. This is an unverified workflow, not a Windows installer. Do not redistribute Windows files without rights.
