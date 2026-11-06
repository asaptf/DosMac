# App Store preparation

Status: active work, not a submission-ready release. Updated November 6, 2026.

## Editions

`DosMac-macOS` remains the developer edition. `DosMac-AppStore` is a separate, sandboxed preparation target, currently Apple Silicon only, with bundle identifier `org.dosmac.store`. Its private container does not migrate or alter the existing developer library. The final App ID and store metadata must be checked in the owner's account before submission.

The preparation target imports user-supplied images and includes an original PC hardware diagnostic. Discover has no unreviewed archive catalog. Local Windows 95/98 media can enter the existing guided installer. Native engine downloads and external engine overrides are rejected in the backends, not merely hidden in the UI. Classic DOSBox-X packages remain in the developer edition. Host disk mounting is developer-only; the store preparation target uses its live folder and exchange images for host transfers.

## Evidence recorded locally

- Placed native helpers in `Contents/Helpers` and libraries in `Contents/Frameworks`, independently of firmware and license resources. The signed package passed the standard-location and nested-signature checks.
- Signed QEMU and helpers with the same Apple Development identity, with sandbox inheritance and hardened runtime. QEMU alone has the macOS JIT exception; this does not establish an iOS runtime or iOS entitlement.
- Ran `DosMac-SandboxProbe` in its actual app container. It could not read an existing disposable marker outside the container, booted original PC code, rendered the framebuffer, accepted keyboard input, rendered the 16-color pattern, returned to text mode, and passed pause/resume.
- Repeated the probe with the embedded private Samba service enabled. This proves server startup, not yet a full guest SMB round trip inside the sandbox.
- Visually ran the store target's original diagnostic through text and graphics modes, without a commercial OS image or native engine download.
- Distribution policy tests reject a custom native executable and stop native engine installation and unreviewed source inspection before downloading.

The exact later repeat results and release validation must accompany the candidate; these observations do not imply Apple approval.

## Remaining gates

| Gate | State |
| --- | --- |
| Developer and store UI builds and original-fixture regressions | Developer, store, and iOS UI builds passed; 28 VM and 38 Core tests passed. Final packaged acceptance remains open |
| Original diagnostic color pattern and saved Library shortcut | Original diagnostic renders; final return-to-text and Library shortcut repeat in progress |
| User-selected file imports/exports inside sandbox | End-to-end panel tests pending |
| Windows 98 startup, Guest Tools, live file exchange inside sandbox | Startup, mouse integration and actual 800 × 600 mode passed on a private fixture; guest C: file-copy round trip is being diagnosed |
| Windows 95 full desktop acceptance | Pending |
| Complete native dependency license and source inventory | 32 primary archives and 6 additional recipe inputs verified; GLib local patch pinned against the installed recipe. 222 source notice texts collected. Complete-source and store-term review remain open |
| Distribution of GPL and other dependencies under store terms | Requires review for the exact binary and distribution terms; Apache-2.0 does not remove upstream obligations |
| Required-reason API audit of native dependencies | Native symbol inventory and four categories declared with [purpose notes](app-store/privacy-api-review.md); exact exported-app and call-site review pending |
| About/open-source notices accessible in the app | Settings license view implemented; final visual check pending |
| Final icon, store-sized screenshots, preview video and metadata | In progress |
| Release archive, App Store provisioning and upload validation | Apple Development-signed Release archive built; self-contained packaging, export and upload validation pending |
| TestFlight, real clean-Mac acceptance, reviewer demonstration | Pending |
| App Store account agreements and final legal acceptance | Owner action if prompted |
| iPhone guest execution and device acceptance | Not implemented; a separate runtime effort, not covered by the Mac probe |

## Local sandbox probe

The probe is a test-only app, not a shipping product. Build it, bundle the engine with sandbox signatures, and run its executable:

```sh
xcodegen generate
xcodebuild -project DosMac.xcodeproj -scheme DosMac-SandboxProbe \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/store-probe CODE_SIGNING_ALLOWED=NO build
python3 scripts/bundle-qemu.py \
  --app build/store-probe/Build/Products/Debug/DosMacProbe.app \
  --sandbox --sign-identity 'YOUR APPLE DEVELOPMENT IDENTITY'
```

Run the host-side harness, which creates an existing disposable marker outside the sandbox, invokes both modes, checks their reports, and removes only that marker:

```sh
python3 scripts/check-sandbox.py --app build/store-probe/Build/Products/Debug/DosMacProbe.app
```

Successful runs remove only their own temporary machine. Failed copies remain in the probe's container for diagnosis. Never use commercial disk images as committed fixtures.

A helper signed for sandbox inheritance must be launched by its sandboxed parent; invoking that QEMU executable directly is not a valid standalone smoke test. The bundler queries the original developer engine for version metadata before using its signed copy.

## References

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): self-contained apps, Mac sandboxing, downloadable software, emulators, content rights, and privacy.
- [Sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).
- [macOS JIT runtime exception](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit).
- [Required-reason API declarations](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
- [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).

Native placement follows [Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/). App Store upload and acceptance remain separate checks.
