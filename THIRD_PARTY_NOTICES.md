# Third-party notices

DosMac's original project code is licensed under [Apache License 2.0](LICENSE). This does not relicense the components below; their licenses and source obligations remain applicable. See [NOTICE](NOTICE).

## QEMU machine backend

The machine manager invokes QEMU as an owned process and implements QMP/RFB protocols in Swift. No commercial OS/application image is vendored in this repository. The developer bundler can copy a locally installed QEMU. The store preparation pipeline uses a checksum-pinned, project-built minimal QEMU with a recorded build recipe and binary hashes. QEMU is GPL-2.0 licensed; SeaBIOS, VGA BIOS and every linked library retain their own terms. Source evidence and notices are collected for the exact component inventory. Signed preparation artifacts are not App Store approval; complete source delivery, applicable terms and release validation remain necessary. Sources: [QEMU](https://www.qemu.org/), [QEMU licensing](https://www.qemu.org/docs/master/about/license.html), [SeaBIOS](https://www.seabios.org/).

## SWCompression 4.9.1 and BitByteData 2.1.0

Source: [SWCompression](https://github.com/tsolomko/SWCompression) and [BitByteData](https://github.com/tsolomko/BitByteData). Versions and revisions are pinned by `Package.resolved`.

Both components carry the following MIT license:

MIT License

Copyright (c) 2026 Timofey Solomko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## DOSBox-X

DosMac's macOS adapter invokes [DOSBox-X](https://github.com/joncampbell123/dosbox-x), automatically downloaded from the official 2026.10.01 release or supplied by the user. No DOSBox-X binary is linked, bundled, or redistributed in this repository. The managed download retains the upstream app, COPYING.txt, README.txt, and other accompanying files. Its GPL license and notices apply to that installation. [Release and source](https://github.com/joncampbell123/dosbox-x/releases/tag/dosbox-x-v2026.10.01). A future bundled or embedded release must audit the selected upstream revision and linked components and ship all corresponding notices and required source.

## QEMouse v1.03

The embedded mouse driver is GPL-2.0 licensed. Its exact corresponding source, license and provenance are included in `Sources/DosMacApp/Resources/GuestTools`. See [Guest Tools](docs/guest-tools.md) and the [upstream project](https://github.com/qemus/qemouse). DosMac's display agent is an original, separate MIT-licensed component; its license is in `GuestTools/Agent/LICENSE`.

## Homebrew build recipes

Local source-evidence packages retain the exact installed Homebrew recipes, receipts, and pinned build inputs for the copied native components. Homebrew formula code retains its BSD-2-Clause license; see [the included text](Configuration/ThirdParty/Homebrew-LICENSE.txt). Source archives, recipe inputs, and source notice extraction are checksum-verified. Their collection does not establish compatibility with store terms or replace a complete corresponding-source review for the exact distributed build.

## Private file-sharing service

The embedded Samba server and its dependencies retain their upstream licenses, including Samba's GPL-3.0-or-later terms. It runs as a separate inherited-sandbox helper. Its exact component recipes, source inputs and license texts are included in the native source inventory and in-app notices. The minimal QEMU build disables the unused SSH backend; its native dependency graph is verified separately from the sharing helper's graph.
