# thermon

> **試してみたい方へ：** このリポジトリの URL をあなたの AI（Claude Code などのコーディングエージェント）にコピペして「ビルドしてインストールして」と頼めば、Apple Silicon の Mac ならあとは AI がやってくれるはずです。
>
> **Want to try it?** Paste this repository's URL into your AI coding agent (e.g. Claude Code) and ask it to build and install it. On an Apple Silicon Mac, it should take care of the rest.

Apple Silicon GPU thermal-throttling monitor (no sudo). Reads IOReport "GPU Stats / GPU Performance States"
residency and the pmgr DVFS table to report the GPU's effective clock as % of max, plus busy % and
`ProcessInfo.thermalState`.

- `thermon` — CLI (`--json` for one JSON line per sample)
- `ThermonBar.app` — SwiftUI menu-bar indicator (green / yellow / red / gray, clock %, sparkline, throttled ratio)
- `throttle_probe.sh <label> [min]` — sustained R3D decode load test with a thermon log and summary (results in `probes/`, not tracked)

Build: `./build.sh [outdir]`

License: MIT (see LICENSE)
