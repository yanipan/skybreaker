#!/bin/bash
# Convert a generated clip (mp4) to the Ogg Theora file Godot can play.
#   scripts/tools/clip_to_ogv.sh clip.mp4 assets/cutscenes/<beat image_file>.ogv [quality 0-10, default 7]
# Godot's VideoStreamPlayer only plays Theora (.ogv), not MP4. Audio is
# dropped: cutscenes have their own narration and music. Homebrew ffmpeg on
# this Mac has no libtheora, so this uses the copy at ~/.claude/tools/bin/ffmpeg-theora
# (an ffmpeg-static build); set FFMPEG_THEORA to point elsewhere.
set -euo pipefail
FF="${FFMPEG_THEORA:-$HOME/.claude/tools/bin/ffmpeg-theora}"
"$FF" -y -loglevel error -i "$1" -an -vf "scale=720:-2,fps=24" -pix_fmt yuv420p -c:v libtheora -q:v "${3:-7}" "$2"
ls -la "$2"
