#!/usr/bin/env python3
"""Build the README's looping screenshot tour. Requires FFmpeg on PATH."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
assets = root / 'docs/images'
ffmpeg = shutil.which('ffmpeg')
if not ffmpeg:
    raise SystemExit('Install FFmpeg, then rerun: brew install ffmpeg')
scenes = ['library.png', 'discover.png', 'windows98.png', 'start-menu.png', 'library.png']
command = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y']
for scene in scenes:
    if not (assets / scene).is_file():
        raise SystemExit(f'Missing screenshot: {scene}')
    command += ['-loop', '1', '-framerate', '12', '-t', '3', '-i', str(assets / scene)]
filters = [f'[{i}:v]scale=1008:-2:flags=lanczos,format=rgba,settb=AVTB,setpts=PTS-STARTPTS[v{i}]'
           for i in range(len(scenes))]
previous = 'v0'
for i in range(1, len(scenes)):
    name = f'fade{i}'
    filters.append(f'[{previous}][v{i}]xfade=transition=fade:duration=0.35:offset={2.65*i:.2f}[{name}]')
    previous = name
filters += [f'[{previous}]split[a][b]',
            '[a]palettegen=max_colors=192:stats_mode=diff[p]',
            '[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[out]']
command += ['-filter_complex', ';'.join(filters), '-map', '[out]', '-loop', '0',
            str(assets / 'dosmac-demo.gif')]
subprocess.run(command, check=True)
print(f'Built {assets / "dosmac-demo.gif"}')
