# DosMac display agent

An original, MIT-licensed Win32 x86 program for Windows 95/98. The currently accepted guest is English Windows 98 SE with its installed Cirrus display driver. Windows 95 remains unverified.

Build on a Mac with `brew install llvm lld`, then run `python3 scripts/build-guest-agent.py` from the repository root. The developer tools are not needed by DosMac users. LLVM/LLD produce a CRT-free PE32 executable targeting subsystem 4.0 and i386 instructions, with deterministic timestamps. The adjacent `dmagent.json` records binary/source hashes and compiler version. The app pins the executable's SHA-256; update that value in `MachineLibraryView.swift` after an intentional rebuild.

The process runs without a window, holds a singleton mutex, and polls `H:\DMTOOLS\REQUEST.TXT` every 500 ms. The existing managed live share must be mapped to H:. It reports enumerated modes through `STATUS.TXT`, tests a requested mode with `ChangeDisplaySettingsA`, then applies it as the saved Windows display mode. Color depth is preserved when supported. The agent checks the shell taskbar bounds and rolls back an unusable mode. Its own startup entry is installed by DosMac's INF helper. The Win32 message queue stays active, and successful mode changes require matching taskbar bounds including Win9x non-client borders. `DISPLAY.LOG` records only the last mode-change result and geometry.

Protocol:

```
DMAC1 HELLO <32-lowercase-hex-session-token>
DMAC1 RESIZE <token> <uint32-request-id> <width> <height>

DMAC1 READY <token> <width> <height>
MODE <width> <height>
...
END

DMAC1 RESULT <token> <id> <OK|FAILED> <width> <height>
END
```

Each request ends in LF. Responses end in `\nEND\n`. The parser accepts only bounded numbers, dimensions and enumerated modes. Unknown commands do nothing. The host rejects replies from earlier sessions, incomplete files, oversized messages and out-of-order acknowledgements. Session tokens correlate replies; they are not credentials or a security boundary against the guest.

The process has no host command execution, clipboard forwarding, Internet access or arbitrary file-operation protocol. Clipboard and a richer guest-control service are future components. The fixed H: transport can later be replaced without changing the display policy.
