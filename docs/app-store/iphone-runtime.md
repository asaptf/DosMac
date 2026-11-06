# iPhone execution work

Status: the current iPhone target builds its UI but does not execute PC guests. A macOS signed helper and its JIT entitlement cannot be reused as an iOS runtime.

The preferred investigation is a bundled QEMU interpreter library, retaining the existing machine format, QCOW2 disks and firmware where compatible. UTM's maintained fork demonstrates a JIT-free interpreter and shared-library entry point. Its documentation also identifies lifecycle constraints when QEMU runs in an iOS app thread. This is an architectural reference, not a dependency already integrated into DosMac.

Before calling the iPhone release functional:

1. Pin the runtime fork, patches, exact dependencies and their licenses/source delivery.
2. Build device and simulator interpreter libraries without a JIT entitlement or downloaded native code.
3. Implement and verify the runtime lifecycle, including a second start after stopping a guest.
4. Connect framebuffer, keyboard, touch/pointer and removable media to the existing workspace.
5. Verify private disk creation/import/export and a supported file-exchange mechanism.
6. Boot the original diagnostic, DOS and licensed Windows fixtures on a physical iPhone; record performance and memory limits.
7. Archive, export and test the exact iPhone release through TestFlight.

References checked November 6, 2026:

- [UTM architecture](https://github.com/utmapp/UTM/blob/main/Documentation/Architecture.md)
- [UTM iOS development](https://github.com/utmapp/UTM/blob/main/Documentation/iOSDevelopment.md)
- [UTM iOS editions](https://docs.getutm.app/installation/ios/)

The UI build and Mac acceptance results do not satisfy these steps.
