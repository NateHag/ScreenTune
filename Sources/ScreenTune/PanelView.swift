import SwiftUI

struct PanelView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ScreenTune").font(.headline)
                Spacer()
                Toggle("On", isOn: $model.tune.enabled).toggleStyle(.switch).labelsHidden()
            }

            GroupBox("Color") {
                VStack(spacing: 6) {
                    row("Saturation", $model.tune.saturation, 0.3...2.0, percent)
                    row("Warmth", $model.tune.kelvin, 2700...6500, { "\(Int($0)) K" }, reversed: true)
                    row("Contrast", $model.tune.contrast, 0.5...1.5, percent)
                    row("Mid tones", $model.tune.gamma, 0.5...2.0, { String(format: "%.2f", $0) })
                    row("Extra dim", $model.tune.dim, 0.2...1.0, percent)
                    DisclosureGroup("Red / Green / Blue") {
                        row("Red", $model.tune.red, 0.5...1.0, percent)
                        row("Green", $model.tune.green, 0.5...1.0, percent)
                        row("Blue", $model.tune.blue, 0.5...1.0, percent)
                    }
                    .font(.callout)
                }
                .padding(4)
            }

            GroupBox("Auto-brightness") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use my curve", isOn: $model.tune.autoBrightness)
                    CurveEditor(curve: $model.tune.curve, lux: model.currentLux, offset: model.tune.offset)
                        .frame(height: 120)
                    HStack {
                        Text(luxText)
                        Spacer()
                        Text("Screen \(model.currentBrightness.map(percent) ?? "–")")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    row("Reaction", $model.tune.reaction, 0.5...15, { String(format: "%.1f s", $0) })
                    HStack {
                        Text("Your key changes: \(signedPercent(model.tune.offset))").font(.caption)
                        Spacer()
                        Button("Reset") { model.tune.offset = 0 }.controlSize(.small)
                        Button("Default curve") { model.tune.curve = AutoBrightness.defaultCurve }.controlSize(.small)
                    }
                    if !model.auto.sensorAvailable {
                        Text("No light sensor found.").font(.caption).foregroundStyle(.red)
                    }
                    Text("Drag the dots. Left = dark room, right = bright light. Turn off \"Automatically adjust brightness\" in System Settings > Displays.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                Spacer()
                Button("Reset color") { model.resetColor() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var luxText: String {
        guard let lux = model.currentLux else { return "Light: –" }
        return "Light: \(lux < 10 ? String(format: "%.1f", lux) : String(Int(lux))) lux"
    }

    private func row(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                     _ format: @escaping (Double) -> String, reversed: Bool = false) -> some View {
        HStack {
            Text(label).frame(width: 74, alignment: .leading)
            if reversed {
                // Warmth: right = warmer, which is a lower Kelvin number.
                Slider(value: Binding(
                    get: { range.upperBound + range.lowerBound - value.wrappedValue },
                    set: { value.wrappedValue = range.upperBound + range.lowerBound - $0 }), in: range)
            } else {
                Slider(value: value, in: range)
            }
            Text(format(value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .font(.callout)
        .contextMenu { Button("Reset \(label)") { value.wrappedValue = Tune.defaultValue(label) ?? value.wrappedValue } }
    }
}

private func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
private func signedPercent(_ x: Double) -> String { (x >= 0 ? "+" : "") + percent(x) }

extension Tune {
    static func defaultValue(_ label: String) -> Double? {
        let d = Tune()
        return ["Saturation": d.saturation, "Warmth": d.kelvin, "Contrast": d.contrast, "Mid tones": d.gamma,
                "Extra dim": d.dim, "Red": d.red, "Green": d.green, "Blue": d.blue, "Reaction": d.reaction][label]
    }
}

/// Brightness (up) against light level (right). Each dot can be dragged up and down.
struct CurveEditor: View {
    @Binding var curve: [Double]
    var lux: Double?
    var offset: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, pad = 8.0
            let n = curve.count
            let px = { (i: Double) in pad + i / Double(n - 1) * (w - 2 * pad) }
            let py = { (v: Double) in pad + (1 - v) * (h - 2 * pad) }

            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                Path { p in
                    for (i, v) in curve.enumerated() {
                        let pt = CGPoint(x: px(Double(i)), y: py(v))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(.tint, lineWidth: 2)
                if offset != 0 {
                    Path { p in
                        for (i, v) in curve.enumerated() {
                            let pt = CGPoint(x: px(Double(i)), y: py(clamp(v + offset)))
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let lux {
                    let x = px(AutoBrightness.position(lux: lux))
                    Path { p in p.move(to: CGPoint(x: x, y: pad)); p.addLine(to: CGPoint(x: x, y: h - pad)) }
                        .stroke(.orange, lineWidth: 1)
                }
                ForEach(curve.indices, id: \.self) { i in
                    Circle().fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .position(x: px(Double(i)), y: py(curve[i]))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    // The dot nearest to where the drag started.
                    let i = Int(clamp(((g.startLocation.x - pad) / (w - 2 * pad) * Double(n - 1)).rounded(), 0, Double(n - 1)))
                    curve[i] = clamp(1 - (g.location.y - pad) / (h - 2 * pad), 0.01, 1)
                })
        }
    }
}
