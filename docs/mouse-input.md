# Mouse input

## Windows 3.1 graphical Setup

The standard Windows 3.1 mouse driver expects relative mouse input with the pointer captured inside the emulator window. DOSBox-X defaults to `autolock=false`, so clicking an unlocked emulator window does not automatically provide this capture. DosMac now explicitly generates:

```ini
[sdl]
autolock=true
autolock_feedback=none
```

Click inside the emulated display to use the mouse. The first click may only capture it; click again to operate a Windows control. Press **Ctrl + F10** to release the mouse to macOS. If the keyboard maps F10 to media functions, also hold **Fn**. The **Main → Capture mouse** menu is an alternative.

No additional DOS mouse driver or macOS Accessibility permission is needed for ordinary mouse input inside DOSBox-X. The Accessibility permission used by DosMac's external disk-switch buttons is separate.

An existing running session retains its startup configuration. It can be fixed immediately without restarting Setup by enabling **Main → Autolock mouse**, then clicking inside the display, or by using **Main → Capture mouse / Ctrl + F10**. Subsequent DosMac launches use the corrected configuration.

The **Mouse & keyboard** panel appears for running sessions, including installed Windows programs without floppy media. It explains capture/release and provides a button to show the emulator. Keyboard navigation with Tab, arrows, Space and Enter remains available in Setup.

## Validation and scope

The current graphical Windows Setup session was manually checked on macOS: enabling click capture produced the emulator's captured-pointer window title, and guest cursor movement responded to the mouse. Ctrl + F10 released capture afterward without restarting Setup. The configuration regression check verifies that generated profiles retain `autolock=true`.

This enables relative mouse input; it does not install a seamless absolute-pointer driver in Windows. That is a separate enhancement after installation. A custom mapper can change the capture shortcut; in that case use the emulator menu.

Upstream references: [mouse support](https://dosbox-x.com/wiki/Guide%3AMouse-support-in-DOSBox%E2%80%90X), [Windows 3.1 configuration](https://dosbox-x.com/wiki/Guide%3AInstalling-Windows-3.1x).
