// ThermonBar — menu bar indicator: is the Mac's GPU running at full clock or being throttled? (2026-10-11)
// Green = busy at >= 90% of top clock; yellow = busy but clock 70-90% or thermal pressure "fair";
// red = busy below 70% of top clock or thermal pressure "serious"/"critical"; gray = idle. Sudo-less (IOReport).
import SwiftUI

struct Point: Identifiable { let id: Int; let clock: Double; let busy: Double; let thermal: Int }

enum Verdict { case idle, full, mild, throttled
    var color: Color { switch self { case .idle: .gray; case .full: .green; case .mild: .yellow; case .throttled: .red } }
    var label: String { switch self { case .idle: "アイドル"; case .full: "全力（スロットリングなし）"; case .mild: "スロットリングの兆候"; case .throttled: "スロットリング中" } }
}

final class Model: ObservableObject {
    @Published var s = ThermonSample()
    @Published var history: [Point] = []
    @Published var busySeconds = 0
    @Published var throttledSeconds = 0
    private var n = 0
    private var timer: Timer?
    let ok: Bool
    init() {
        ok = thermon_init()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }
    func verdict(_ x: ThermonSample) -> Verdict {
        if x.thermalState >= 2 { return .throttled }
        if x.gpuBusyPct < 50 { return x.thermalState == 1 ? .mild : .idle }
        if x.gpuClockPct < 70 { return .throttled }
        if x.gpuClockPct < 90 || x.thermalState == 1 { return .mild }
        return .full
    }
    func tick() {
        var x = ThermonSample()
        guard thermon_sample(&x) else { return }
        s = x; n += 1
        history.append(Point(id: n, clock: x.gpuClockPct, busy: x.gpuBusyPct, thermal: Int(x.thermalState)))
        if history.count > 300 { history.removeFirst(history.count - 300) }
        if x.gpuBusyPct >= 50 { busySeconds += 1; if verdict(x) != .full { throttledSeconds += 1 } }
    }
    func reset() { busySeconds = 0; throttledSeconds = 0 }
}

let thermalNames = ["正常", "やや高い", "高い", "危険"]

struct Sparkline: View {
    let points: [Point]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, cnt = max(points.count - 1, 1)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: h * 0.1)); p.addLine(to: CGPoint(x: w, y: h * 0.1)) }
                    .stroke(Color.green.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))   // 90% line
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let q = CGPoint(x: w * CGFloat(i) / CGFloat(cnt), y: h * (1 - CGFloat(min(pt.clock, 100)) / 100))
                        i == 0 ? p.move(to: q) : p.addLine(to: q)
                    }
                }.stroke(Color.accentColor, lineWidth: 1.5)
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let q = CGPoint(x: w * CGFloat(i) / CGFloat(cnt), y: h * (1 - CGFloat(min(pt.busy, 100)) / 100))
                        i == 0 ? p.move(to: q) : p.addLine(to: q)
                    }
                }.stroke(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
    }
}

struct Panel: View {
    @ObservedObject var m: Model
    var body: some View {
        let v = m.verdict(m.s)
        VStack(alignment: .leading, spacing: 8) {
            HStack { Circle().fill(v.color).frame(width: 10, height: 10); Text(v.label).font(.headline) }
            if !m.ok { Text("IOReport を初期化できません").foregroundStyle(.red) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text("GPU クロック").foregroundStyle(.secondary); Text(String(format: "%.0f MHz（最高 %.0f の %.0f%%）", m.s.gpuMHz, m.s.gpuMaxMHz, m.s.gpuClockPct)).monospacedDigit() }
                GridRow { Text("GPU 使用率").foregroundStyle(.secondary); Text(String(format: "%.0f%%", m.s.gpuBusyPct)).monospacedDigit() }
                GridRow { Text("熱圧力（macOS）").foregroundStyle(.secondary); Text(thermalNames[max(0, min(3, Int(m.s.thermalState)))]) }
                GridRow { Text("高負荷中の絞られ率").foregroundStyle(.secondary)
                    Text(m.busySeconds > 0 ? String(format: "%.0f%%（%d / %d 秒）", 100.0 * Double(m.throttledSeconds) / Double(m.busySeconds), m.throttledSeconds, m.busySeconds) : "—").monospacedDigit() }
            }
            Text("直近 5 分：青 = クロック %、灰 = 使用率、点線 = 90%").font(.caption).foregroundStyle(.secondary)
            Sparkline(points: m.history).frame(height: 70)
            HStack { Button("集計をリセット") { m.reset() }; Spacer(); Button("終了") { NSApplication.shared.terminate(nil) } }
        }.padding(12).frame(width: 330)
    }
}

@main
struct ThermonBarApp: App {
    @StateObject var m = Model()
    var body: some Scene {
        MenuBarExtra {
            Panel(m: m)
        } label: {
            let v = m.verdict(m.s)
            HStack(spacing: 3) {
                Image(systemName: "circle.fill").foregroundStyle(v.color)
                Text(v == .idle ? "GPU" : String(format: "%.0f%%", m.s.gpuClockPct)).monospacedDigit()
            }
        }.menuBarExtraStyle(.window)
    }
}
