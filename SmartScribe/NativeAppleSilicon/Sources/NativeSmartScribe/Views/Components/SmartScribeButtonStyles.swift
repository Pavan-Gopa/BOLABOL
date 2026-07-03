import SwiftUI

// MARK: - Toolbar Icon Button Style

/// Unified button style for all toolbar icon buttons throughout the app.
/// Provides consistent sizing, hover feedback, and press animation.
struct SmartScribeToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? .white.opacity(0.10) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Modern Record Button

/// A stylish record button that transforms from a circle to a rounded square when active.
struct ModernRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                
                RoundedRectangle(cornerRadius: isRecording ? 6 : 16, style: .continuous)
                    .strokeBorder(Color.red, lineWidth: isRecording ? 9 : 2.5)
                    .frame(width: isRecording ? 18 : 32, height: isRecording ? 18 : 32)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isRecording)
    }
}

// MARK: - Surface Container

/// A reusable glass-morphism container used to group related controls.
struct ControlSurface<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}
