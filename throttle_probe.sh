#!/bin/bash
# throttle_probe.sh <label> [minutes=8] — sustained R3D decode load + 1 Hz GPU clock log, to compare fan / power settings.
# Decodes the same (page-cached) 600-frame A066 range over and over with the production decoder (6 workers), so the card
# does not matter; logs thermon JSON every second and the fps of every run; prints a 30 s timeline at the end.
set -u
LABEL=${1:?label}; MIN=${2:-8}
OUT=~/Dev/thermon/probes/$(date +%Y%m%d-%H%M%S)-$LABEL; mkdir -p "$OUT"
R=/Volumes/A066_1009VI/A066_1009VI.RDM/A066_C001_1009CR.RDC/A066_C001_1009CR_001.R3D
FF=/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg
~/Dev/thermon/thermon --json > "$OUT/thermon.jsonl" & TP=$!
end=$(( $(date +%s) + MIN * 60 )); i=0
cd ~/vlog-cache/_r3dsdk
while [ $(date +%s) -lt $end ]; do
  t0=$(python3 -c 'import time;print(time.time())')
  ./r3d-decode-metal --r3d "$R" --ffmpeg "$FF" --out "$OUT/run.mp4" --encode vt --start 20500 --max-frames 600 >/dev/null 2>"$OUT/run.err"
  t1=$(python3 -c 'import time;print(time.time())')
  echo "$(date +%T) run=$i fps=$(python3 -c "print(round(600/($t1-$t0),1))") $(grep -o 'zero_output_frames=[0-9]*' "$OUT/run.err")" | tee -a "$OUT/runs.txt"
  i=$((i+1))
done
kill $TP; rm -f "$OUT/run.mp4"
python3 - "$OUT" <<'PY'
import json, sys, statistics
out = sys.argv[1]
rows = [json.loads(l) for l in open(f"{out}/thermon.jsonl") if l.strip()]
busy = [r for r in rows if r["gpu_busy"] >= 50]
print(f"\n== {out}")
for k in range(0, len(rows), 30):
    w = rows[k:k + 30]; b = [r for r in w if r["gpu_busy"] >= 50] or w
    print(f"{w[0]['t']}  clock {statistics.mean(r['gpu_clock_pct'] for r in b):5.1f}%  busy {statistics.mean(r['gpu_busy'] for r in w):5.1f}%  thermal {max(r['thermal'] for r in w)}")
if busy:
    first = next((i for i, r in enumerate(rows) if r["gpu_busy"] >= 50 and r["gpu_clock_pct"] < 90), None)
    print(f"under load: clock mean {statistics.mean(r['gpu_clock_pct'] for r in busy):.1f}%, "
          f"time at >=90% clock {100*sum(r['gpu_clock_pct']>=90 for r in busy)/len(busy):.0f}%, "
          f"first drop below 90% after {first if first is not None else 'never'} s")
runs = [float(l.split('fps=')[1].split()[0]) for l in open(f"{out}/runs.txt")]
print(f"runs {len(runs)}: first {runs[0]} fps, last {runs[-1]} fps, mean {statistics.mean(runs):.1f} fps")
PY
