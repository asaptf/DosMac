# Startup after installation

Each library item has its own private C: drive. The initial floppy import starts `INSTALL.BAT`, which mounts the disk set and runs Setup. Finishing Setup does not automatically replace that entry point or assume that the user wants Windows to start on every launch.

## DOS on C:

1. End the current emulator session normally.
2. Select the existing library item and click the gear beside Launch.
3. Set **Start in → DOS prompt on C:** and click **Save**.
4. Click **Launch**. The built-in DOS environment opens at `C:\>` without running the floppy batch file or mounting its images.

This is DOSBox-X's integrated DOS shell over the folder-backed C: drive, not BIOS boot from a disk image. Windows files remain in that drive. For an installation in the standard directory, type:

```dos
C:
CD \WINDOWS
WIN
```

## Start installed Windows directly

Open the same startup settings and click **Use installed Windows**, then **Save**. The picker detects `WINDOWS/WIN.COM`, or another `WIN.COM` in a valid DOS 8.3 directory, and selects the Windows 3.1 hardware profile. Launch then starts that executable, rather than `INSTALL.BAT`.

The generated environment adds the selected Windows directory to PATH and prepares `C:\TEMP` for TEMP/TMP. Windows starts with its directory as the working directory. The floppy-drive panel is hidden because this entry point does not mount the installation media. A generated title ending in “ · Setup” is cleaned up when switching to the installed Windows launcher.

The images and installer remain stored for later use; switching startup mode does not delete or rewrite the Windows installation. If necessary, choose `INSTALL.BAT` again in Program mode. Settings are disabled while a session is running to keep the next-launch preference separate from the active session.

Old manifests with no `startupMode` continue launching their declared program. The DOS preference is persistent and does not require the previous installer executable to remain present. Tests cover default compatibility, DOS startup without the installer command, persistence, and switching from DOS to an installed Windows entry point.
