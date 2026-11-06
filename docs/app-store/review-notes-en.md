# App Review notes draft

Use only after the exact uploaded build has passed the acceptance checklist. Replace build-specific details before submission.

## Reviewer access

No DosMac account, subscription, login or activation is required. No external native engine download is required. QEMU, its required libraries and firmware are embedded and signed in the application.

## Test without commercial software

1. Open Discover.
2. Select **Open PC hardware check**.
3. Click the guest screen and press Enter to display the color bars.
4. Press Enter again to return to the original diagnostic text.
5. Press Control + Option to release captured input.
6. Use Pause/Resume or power off the diagnostic computer.
7. Open Library to launch the saved diagnostic again.

This is original redistributable diagnostic code. It does not contain a commercial operating system, product key, installer or personal document.

## User-supplied software

Users create private computers and import their own local installation media. The store edition does not offer the developer edition's archive catalogs or native engine downloader. It does not bundle DOS, Windows or commercial application media. Guided setup is experimental and users may need to control guest installation prompts themselves.

## Sandbox and embedded helpers

The app uses App Sandbox. Embedded native executable helpers inherit that sandbox. The macOS QEMU helper uses the hardened-runtime JIT exception for CPU emulation; the main app, image tool and sharing server do not request that exception. Imported images are copied from user-selected files into the app's private library. Live guest sharing exposes only the selected computer's designated Shared folder through an app-private loopback relay.

The application does not require administrative access or an external package manager. It does not use host disk mounting in this edition.

## Licensing and privacy

Settings → Licenses contains project and dependency notices. Public privacy and support URLs are linked in the app. Corresponding-source delivery, native privacy review, final signing and acceptance must be completed for the exact submitted build before this note is used.

## Submission details still required

- Actual version/build number and supported macOS versions/architectures.
- Tested signing/export/upload results and source-delivery URL.
- Any final known guest compatibility limitations.
- Owner's App Review contact details, entered privately in App Store Connect.
