import SwiftUI
import VaniScriptCore

public struct OnboardingFramesPreferenceKey: PreferenceKey {
    public static let defaultValue: [String: CGRect] = [:]

    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { (_, new) in new }
    }
}

public struct OnboardingTargetModifier: ViewModifier {
    let id: String

    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: OnboardingFramesPreferenceKey.self, value: [id: geo.frame(in: .named("OnboardingSpace"))])
                }
            )
    }
}

extension View {
    public func onboardingTarget(_ id: String) -> some View {
        self.modifier(OnboardingTargetModifier(id: id))
    }
}

struct OnboardingTourView: View {
    let screen: String
    @ObservedObject var store: WorkflowStore
    let frames: [String: CGRect]

    @State private var draggedPosition: CGPoint? = nil
    @GestureState private var dragOffset = CGSize.zero

    private let bubbleWidth: CGFloat = 380
    private let bubbleHeight: CGFloat = 190
    private let gap: CGFloat = 60

    var body: some View {
        let steps = TourSteps.steps(for: screen)
        guard store.isTourActive && store.activeTourScreen == screen && steps.indices.contains(store.tourStepIndex) else {
            return AnyView(EmptyView())
        }

        let activeStep = steps[store.tourStepIndex]
        let targetRect = frames[activeStep.targetSelector]

        return AnyView(
            GeometryReader { geometry in
                let size = geometry.size
                let bubblePos = calculateBubblePosition(targetRect: targetRect, size: size, placement: activeStep.bubblePlacement)
                let currentBubbleCenter = draggedPosition ?? bubblePos

                ZStack(alignment: .topLeading) {
                    // Spotlight dimming background
                    if let targetRect = targetRect {
                        SpotlightBackground(targetRect: targetRect)
                            .allowsHitTesting(false)
                    }

                    // Bezier Arrow Layer
                    if let targetRect = targetRect {
                        ArrowOverlay(
                            targetRect: targetRect,
                            bubbleRect: CGRect(
                                x: currentBubbleCenter.x + dragOffset.width,
                                y: currentBubbleCenter.y + dragOffset.height,
                                width: bubbleWidth,
                                height: bubbleHeight
                            ),
                            curveOffset: activeStep.arrowCurveOffset
                        )
                        .allowsHitTesting(false)
                    }

                    // Highlight Spotlight Border Ring
                    if let targetRect = targetRect {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VaniScriptTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                            .shadow(color: VaniScriptTheme.accent.opacity(0.6), radius: 8)
                            .frame(width: targetRect.width + 12, height: targetRect.height + 12)
                            .position(x: targetRect.midX, y: targetRect.midY)
                            .allowsHitTesting(false)
                    }

                    // Draggable Tour Bubble
                    tourBubble(activeStep: activeStep, basePos: currentBubbleCenter, stepsCount: steps.count)
                        .position(
                            x: currentBubbleCenter.x + dragOffset.width + bubbleWidth / 2,
                            y: currentBubbleCenter.y + dragOffset.height + bubbleHeight / 2
                        )
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    let newX = currentBubbleCenter.x + value.translation.width
                                    let newY = currentBubbleCenter.y + value.translation.height
                                    draggedPosition = CGPoint(
                                        x: max(20, min(size.width - bubbleWidth - 20, newX)),
                                        y: max(80, min(size.height - bubbleHeight - 20, newY))
                                    )
                                }
                        )

                    // Floating Mini-Badge (Turn Off Button)
                    miniBadge
                        .position(x: size.width / 2, y: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.tourStepIndex) { _, _ in
                    // Reset dragged position when changing steps
                    draggedPosition = nil
                }
            }
        )
    }

    private var miniBadge: some View {
        Button {
            store.skipTour()
        } label: {
            HStack(spacing: 6) {
                Text("💡")
                Text(store.tourLanguage == "ru" ? "Подсказки включены (Отключить)" : "Walkthrough Active (Turn Off)")
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(VaniScriptTheme.accent.opacity(0.12))
            .foregroundStyle(VaniScriptTheme.accent)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(VaniScriptTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private func tourBubble(activeStep: TourStep, basePos: CGPoint, stepsCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                Text(activeStep.title(for: store.tourLanguage))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .lineLimit(2)

                Spacer()

                // Language Switcher
                HStack(spacing: 0) {
                    Button("EN") {
                        store.tourLanguage = "en"
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(store.tourLanguage == "en" ? VaniScriptTheme.accent : Color.clear)
                    .foregroundStyle(store.tourLanguage == "en" ? Color.black : VaniScriptTheme.text2)
                    .cornerRadius(4)

                    Button("RU") {
                        store.tourLanguage = "ru"
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(store.tourLanguage == "ru" ? VaniScriptTheme.accent : Color.clear)
                    .foregroundStyle(store.tourLanguage == "ru" ? Color.black : VaniScriptTheme.text2)
                    .cornerRadius(4)
                }
                .padding(2)
                .background(Color.dynamic(light: Color.black.opacity(0.06), dark: Color.black.opacity(0.2)))
                .cornerRadius(6)

                // Counter
                Text(store.tourLanguage == "ru" ? "\(store.tourStepIndex + 1) из \(stepsCount)" : "\(store.tourStepIndex + 1) of \(stepsCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.dynamic(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.06)))
                    .cornerRadius(8)
            }
            .padding(.bottom, 8)

            // Description (Scrollable)
            ScrollView(.vertical, showsIndicators: true) {
                Text(activeStep.description(for: store.tourLanguage))
                    .font(.system(size: 12.5))
                    .foregroundStyle(VaniScriptTheme.text1)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 12)

            Spacer(minLength: 0)

            // Footer Action Buttons
            HStack {
                Button(store.tourLanguage == "ru" ? "Скрыть подсказки" : "Skip walkthrough") {
                    store.skipTour()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.85))
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    if store.tourStepIndex > 0 {
                        Button {
                            store.prevTourStep(for: screen)
                        } label: {
                            Text(store.tourLanguage == "ru" ? "‹ Назад" : "‹ Back")
                        }
                        .buttonStyle(TourSecondaryButtonStyle())
                    }

                    Button {
                        store.nextTourStep(for: screen)
                    } label: {
                        Text(store.tourStepIndex < stepsCount - 1
                             ? (store.tourLanguage == "ru" ? "Далее ›" : "Next ›")
                             : (store.tourLanguage == "ru" ? "Завершить" : "Finish"))
                    }
                    .buttonStyle(TourPrimaryButtonStyle())
                }
            }
        }
        .padding(18)
        .frame(width: bubbleWidth, height: bubbleHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.dynamic(
                    light: Color(red: 248/255, green: 249/255, blue: 252/255),
                    dark: Color(red: 18/255, green: 22/255, blue: 45/255)
                ).opacity(0.96))
                .shadow(color: Color.dynamic(light: .black.opacity(0.12), dark: .black.opacity(0.55)), radius: 24, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VaniScriptTheme.accent, lineWidth: 2)
        )
    }

    private func calculateBubblePosition(targetRect: CGRect?, size: CGSize, placement: BubblePlacement) -> CGPoint {
        guard let rect = targetRect else {
            // Center in screen if target element not registered/found
            return CGPoint(x: size.width / 2 - bubbleWidth / 2, y: size.height / 2 - bubbleHeight / 2)
        }

        var placement = placement
        var x = size.width / 2 - bubbleWidth / 2
        var y = size.height / 2 - bubbleHeight / 2

        // Flip collisions detection
        if placement == .bottom {
            let projectedY = rect.maxY + gap
            if projectedY + bubbleHeight > size.height - 20 {
                placement = .top
            }
        } else if placement == .top {
            let projectedY = rect.minY - bubbleHeight - gap
            if projectedY < 80 {
                placement = .bottom
            }
        } else if placement == .left {
            let projectedX = rect.minX - bubbleWidth - gap
            if projectedX < 20 {
                placement = .right
            }
        } else if placement == .right {
            let projectedX = rect.maxX + gap
            if projectedX + bubbleWidth > size.width - 20 {
                placement = .left
            }
        }

        // Final coordinate math
        switch placement {
        case .bottom:
            x = rect.midX - bubbleWidth / 2
            y = rect.maxY + gap
        case .top:
            x = rect.midX - bubbleWidth / 2
            y = rect.minY - bubbleHeight - gap
        case .left:
            x = rect.minX - bubbleWidth - gap
            y = rect.midY - bubbleHeight / 2
        case .right:
            x = rect.maxX + gap
            y = rect.midY - bubbleHeight / 2
        case .center:
            x = size.width / 2 - bubbleWidth / 2
            y = size.height / 2 - bubbleHeight / 2
        }

        // Viewport bounds clamping
        x = max(20, min(size.width - bubbleWidth - 20, x))
        y = max(80, min(size.height - bubbleHeight - 20, y))

        return CGPoint(x: x, y: y)
    }
}

private struct SpotlightBackground: View {
    let targetRect: CGRect

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.65)))

            // Cut out the spotlight target area
            let path = Path(roundedRect: targetRect.insetBy(dx: -6, dy: -6), cornerRadius: 10, style: .continuous)
            context.blendMode = .destinationOut
            context.fill(path, with: .color(Color.black))
        }
    }
}

private struct ArrowOverlay: View {
    let targetRect: CGRect
    let bubbleRect: CGRect
    let curveOffset: CGPoint

    var body: some View {
        Canvas { context, size in
            // Arrow points
            var sx = bubbleRect.midX
            var sy = bubbleRect.midY

            var tx = targetRect.midX
            var ty = targetRect.midY

            // Start arrow on closest bubble edge and end at closest target edge
            if ty < bubbleRect.minY {
                sx = bubbleRect.midX
                sy = bubbleRect.minY
                ty = targetRect.maxY
            } else if ty > bubbleRect.maxY {
                sx = bubbleRect.midX
                sy = bubbleRect.maxY
                ty = targetRect.minY
            } else if tx < bubbleRect.minX {
                sx = bubbleRect.minX
                sy = bubbleRect.midY
                tx = targetRect.maxX
            } else {
                sx = bubbleRect.maxX
                sy = bubbleRect.midY
                tx = targetRect.minX
            }

            // Control point for Bezier curve
            let mx = (sx + tx) / 2 + curveOffset.x
            let my = (sy + ty) / 2 + curveOffset.y

            // Draw path
            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy))
            path.addQuadCurve(to: CGPoint(x: tx, y: ty), control: CGPoint(x: mx, y: my))

            context.stroke(
                path,
                with: .color(VaniScriptTheme.accent),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
            )

            // Arrowhead calculations
            // Tangent vector near end (tx, ty) from control point (mx, my)
            let dx = tx - mx
            let dy = ty - my
            let len = sqrt(dx*dx + dy*dy)
            if len > 0 {
                let ux = dx / len
                let uy = dy / len

                // Head point 1 & 2 relative to tx, ty
                let angle: CGFloat = .pi / 6 // 30 degrees
                let size: CGFloat = 10

                let p1x = tx - size * (ux * cos(angle) - uy * sin(angle))
                let p1y = ty - size * (ux * sin(angle) + uy * cos(angle))

                let p2x = tx - size * (ux * cos(-angle) - uy * sin(-angle))
                let p2y = ty - size * (ux * sin(-angle) + uy * cos(-angle))

                var head = Path()
                head.move(to: CGPoint(x: tx, y: ty))
                head.addLine(to: CGPoint(x: p1x, y: p1y))
                head.addLine(to: CGPoint(x: p2x, y: p2y))
                head.closeSubpath()

                context.fill(head, with: .color(VaniScriptTheme.accent))
            }
        }
    }
}

private struct TourPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(red: 10/255, green: 10/255, blue: 18/255))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
            .cornerRadius(6)
            .shadow(color: VaniScriptTheme.accent.opacity(0.25), radius: 6)
    }
}

private struct TourSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VaniScriptTheme.text1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.dynamic(
                light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.04),
                dark: Color.white.opacity(configuration.isPressed ? 0.12 : 0.06)
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.dynamic(
                        light: Color.black.opacity(0.12),
                        dark: Color.white.opacity(0.15)
                    ), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}
