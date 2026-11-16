#!/bin/sh
# Measure each SFX (EBU R128 integrated loudness), trim leading silence and
# normalise to -18 LUFS so the in-game mix (sfx.gd base_db) starts from equal files.
set -e
for f in art/kaynak/sfx/*.mp3; do
  case "$f" in *levelup*) continue;; esac
  n=$(basename "$f" .mp3)
  I=$(ffmpeg -hide_banner -nostats -threads 2 -i "$f" -af "silenceremove=start_periods=1:start_threshold=-70dB,apad=pad_dur=0.5,ebur128" -f null - 2>&1 | grep -A3 "Integrated loudness" | grep " I:" | awk '{print $2}')
  case "$I" in ''|*[!0-9.-]*) echo "skip $n: bad loudness '$I'" >&2; continue;; esac
  g=$(python3 -I -c 'import sys; print(round(-18.0 - float(sys.argv[1]), 2))' "$I") || { echo "skip $n" >&2; continue; }
  ffmpeg -hide_banner -loglevel error -y -threads 2 -i "$f" -af "silenceremove=start_periods=1:start_threshold=-70dB,volume=${g}dB,alimiter=limit=0.95" -c:a libvorbis -q:a 5 "audio/sfx/$n.ogg"
  echo "$n I=$I gain=$g"
done
