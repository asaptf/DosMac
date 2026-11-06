# README media

Captured from the native macOS developer build on November 6, 2026:

- `library.png` — installed app and desktop shortcuts.
- `discover.png` — source search and guided installation entry points. Windows installation buttons are disabled while another computer is running.
- `windows98.png` — a separately installed Windows 98 SE desktop in the native viewer.
- `start-menu.png` — the same guest with its Start menu open.

`dosmac-demo.gif` is a looping animated tour of these real screenshots with short crossfades. It is not a real-time installation recording, and its timing does not represent installation or startup speed. It contains no product keys or personal documents. Guest product names, marks, and artwork retain their respective ownership; no guest installation media is included.

To regenerate the GIF, install FFmpeg and run this from the repository root:

```sh
python3 scripts/build-readme-demo.py
```

The output is 1008 pixels wide at 12 frames per second. The full-size PNGs remain available for reading UI details. Temporary capture files stay under the ignored `build/` directory.
