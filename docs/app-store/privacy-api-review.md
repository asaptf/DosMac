# Required-reason API review

Updated November 6, 2026. This records the intended uses and the native import inventory. It does not replace review of the exact submission candidate or App Store privacy validation.

Run `python3 scripts/audit-required-apis.py --app /path/to/DosMac.app` after packaging. The initial signed sandbox-probe bundle contained required-reason C imports in 27 native files, including `stat`, `fstat`, `lstat`, `getattrlist`, `statfs`, `fstatfs`, `statvfs`, and `mach_absolute_time`. The shipping UI additionally uses its own UserDefaults. Symbol presence alone does not prove a call's purpose or data collection.

| Category | Declared reasons | Intended use |
| --- | --- | --- |
| UserDefaults | CA92.1 | The application's own saved settings. No shared or third-party preference domain is requested by DosMac. |
| File timestamp / metadata | C617.1, 3B52.1 | Container-owned libraries, images, and documents, plus files explicitly selected for import or export. Metadata is used for file validation and local management. |
| System boot time | 35F9.1 | Elapsed-time measurement and emulator/service timing. These clock values are not used as a persistent identifier or sent to an analytics service. |
| Disk space | E174.1, 85F4.1 | Checking space for local writes and exposing local shared-volume free-space information to the guest's file-management interface. The guest sharing connection is restricted to the private loopback relay. |

The public privacy policy describes local data, sharing, external documentation links, and the developer edition's optional archive requests. The store preparation edition has no unreviewed archive downloads and no native engine downloads. There is no first-party analytics or advertising SDK.

Before submission, repeat the import inventory against the actual exported app, check that all reported categories are declared, review native call sites and SDK requirements, and generate Xcode's privacy report. No API declaration is a permission to fingerprint users or collect data under a different purpose.

Sources: [Apple required-reason API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
