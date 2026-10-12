# thermon

Apple Silicon GPU thermal-throttling monitor (no sudo). Reads IOReport "GPU Stats / GPU Performance States"
residency and the pmgr DVFS table to report the GPU's effective clock as % of max, plus busy % and
`ProcessInfo.thermalState`.

- `thermon` — CLI (`--json` for one JSON line per sample)
- `ThermonBar.app` — SwiftUI menu-bar indicator (green / yellow / red / gray, clock %, sparkline, throttled ratio)
- `throttle_probe.sh <label> [min]` — sustained R3D decode load test with a thermon log and summary (results in `probes/`, not tracked)

Build: `./build.sh [outdir]`

License: MIT (see LICENSE)
