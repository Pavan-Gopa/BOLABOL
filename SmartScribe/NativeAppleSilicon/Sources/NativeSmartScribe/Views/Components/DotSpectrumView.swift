import Combine
import SwiftUI

struct DotSpectrumView: View {
    let bands: [Float]
    let color: Color
    let isActive: Bool
    let isProcessing: Bool
    var dotCount: Int = 30
    var noiseFloor: CGFloat = 0.14
    var amplitude: CGFloat = 0.62
    var sensitivity: CGFloat = 1
    var silenceThreshold: CGFloat = 0.16
    var processingSpeed: CGFloat = 0.72
    @State private var phase: TimeInterval = Date().timeIntervalSinceReferenceDate

    private let animationTimer = Timer.publish(
        every: 1.0 / 30.0,
        on: .main,
        in: .common
    ).autoconnect()

    private var normalizedBands: [CGFloat] {
        let sampledBands = resampledBands
        let peak = max(CGFloat(sampledBands.max() ?? 0), 0)
        if isActive, !isProcessing, peak < silenceThreshold {
            return Array(repeating: noiseFloor, count: sampledBands.count)
        }

        if !isActive {
            return sampledBands.enumerated().map { index, _ in
                noiseFloor + 0.025 * abs(sin(Double(index) * 0.74))
            }
        }

        return sampledBands.enumerated().map { index, band in
            let cleaned = max(0, (CGFloat(band) - silenceThreshold) / max(1 - silenceThreshold, 0.01))
            let relative = peak > silenceThreshold ? cleaned / max((peak - silenceThreshold) / max(1 - silenceThreshold, 0.01), 0.05) : 0
            let absolute = min(1, cleaned * 2.6 * sensitivity)
            let shaped = pow(min(1, relative), 0.74) * 0.40 + pow(absolute, 1.12) * 0.60
            let lowCut = 0.48 + 0.52 * CGFloat(index) / CGFloat(max(dotCount - 1, 1))
            let voiceWeight = lowCut * (0.86 + 0.22 * sin(CGFloat(index) / CGFloat(max(dotCount - 1, 1)) * .pi))
            return min(1, max(noiseFloor, shaped * voiceWeight))
        }
    }

    private var resampledBands: [Float] {
        guard !bands.isEmpty else { return Array(repeating: 0.08, count: dotCount) }
        if bands.count == dotCount { return bands }

        return (0..<dotCount).map { index in
            let sourceIndex = Double(index) / Double(max(dotCount - 1, 1)) * Double(max(bands.count - 1, 0))
            let lower = Int(floor(sourceIndex))
            let upper = min(lower + 1, bands.count - 1)
            let fraction = Float(sourceIndex - Double(lower))
            return bands[lower] * (1 - fraction) + bands[upper] * fraction
        }
    }

    private var shouldAnimate: Bool {
        isProcessing || !isActive
    }

    var body: some View {
        Canvas { context, size in
            drawSpectrum(
                in: &context,
                size: size,
                phase: phase
            )
        }
        .onAppear {
            phase = Date().timeIntervalSinceReferenceDate
        }
        .onReceive(animationTimer) { date in
            guard shouldAnimate else { return }
            phase = date.timeIntervalSinceReferenceDate
        }
    }

    private func drawSpectrum(
        in context: inout GraphicsContext,
        size: CGSize,
        phase: TimeInterval
    ) {
        let values = normalizedBands
        guard !values.isEmpty else { return }

        let centerY = size.height / 2
        let step = size.width / CGFloat(max(values.count - 1, 1))
        let dotRadius = max(1.9, min(3.2, size.height * 0.095))
        let strokeWidth = dotRadius * 1.55
        let maxReflection = size.height * (isProcessing ? max(amplitude, 0.86) : amplitude)
        let pulse = isProcessing ? (0.92 + 0.08 * CGFloat(sin(phase * 3.2))) : 1

        for (index, rawValue) in values.enumerated() {
            let x = CGFloat(index) * step
            let value = isProcessing
                ? processingValue(at: index, rawValue: rawValue, count: values.count, phase: phase) * pulse
                : rawValue
            let reflection = max(4, value * maxReflection)
            let dotCenter = CGPoint(x: x, y: centerY)

            var reflectionPath = Path()
            reflectionPath.move(to: CGPoint(x: x, y: centerY - dotRadius * 0.7))
            reflectionPath.addLine(to: CGPoint(x: x, y: centerY - reflection))
            reflectionPath.move(to: CGPoint(x: x, y: centerY + dotRadius * 0.7))
            reflectionPath.addLine(to: CGPoint(x: x, y: centerY + reflection))

            context.stroke(
                reflectionPath,
                with: .linearGradient(
                    Gradient(colors: [
                        color.opacity(0.02),
                        color.opacity(isActive ? 0.80 : 0.34),
                        color.opacity(0.02)
                    ]),
                    startPoint: CGPoint(x: x, y: centerY - reflection),
                    endPoint: CGPoint(x: x, y: centerY + reflection)
                ),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            let glowRect = CGRect(
                x: dotCenter.x - dotRadius * 2.4,
                y: dotCenter.y - dotRadius * 2.4,
                width: dotRadius * 4.8,
                height: dotRadius * 4.8
            )
            context.fill(
                Circle().path(in: glowRect),
                with: .radialGradient(
                    Gradient(colors: [
                        color.opacity(isActive ? 0.30 : 0.10),
                        color.opacity(0)
                    ]),
                    center: dotCenter,
                    startRadius: 0,
                    endRadius: dotRadius * 2.4
                )
            )

            let dotRect = CGRect(
                x: dotCenter.x - strokeWidth / 2,
                y: dotCenter.y - strokeWidth / 2,
                width: strokeWidth,
                height: strokeWidth
            )
            context.fill(Circle().path(in: dotRect), with: .color(color.opacity(isActive ? 0.98 : 0.46)))
            context.fill(
                Circle().path(in: dotRect.insetBy(dx: strokeWidth * 0.33, dy: strokeWidth * 0.33)),
                with: .color(.white.opacity(isActive ? 0.20 : 0.10))
            )
        }
    }

    private func processingValue(at index: Int, rawValue: CGFloat, count: Int, phase: TimeInterval) -> CGFloat {
        let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
        let travel = progress + CGFloat(phase) * processingSpeed
        let carrier = 0.5 + 0.5 * sin(travel * .pi * 2.0)
        let harmonic = 0.5 + 0.5 * sin(travel * .pi * 5.6 + 1.2)
        let fine = 0.5 + 0.5 * sin(travel * .pi * 12.0 + 0.7)
        let envelope = 0.58 + 0.42 * sin((progress * .pi))
        let synthetic = 0.30 + 0.44 * carrier + 0.20 * harmonic + 0.06 * fine
        return min(1, max(noiseFloor + 0.14, synthetic * envelope + rawValue * 0.18))
    }
}
