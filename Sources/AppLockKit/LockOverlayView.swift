import AppKit
import SwiftUI

/// The lock screen shown over a protected app's window: the app icon with a lock
/// badge, a passcode field of dots driven by the keyboard, and a biometric
/// button.
struct LockOverlayView: View {

    @ObservedObject var model: LockOverlayModel

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { geometry in
            // Windows come in all shapes; scale the layout down so it still fits
            // in a small one rather than clipping.
            let scale = min(1, max(0.58, geometry.size.height / 400))

            ZStack {
                background
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
            }
            .clipShape(shape)
        }
        .modifier(ShakeEffect(animatableData: model.shakeTrigger))
        .animation(.default, value: model.shakeTrigger)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            shape.fill(Color.black.opacity(model.scrimOpacity))
            RadialGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.0)],
                center: .center,
                startRadius: 8,
                endRadius: 380
            )
            .clipShape(shape)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            iconBadge
            Spacer().frame(height: 24)
            title
            Spacer().frame(height: 28)
            passcodeField
            Spacer().frame(height: 16)
            hintRow
            if model.showBiometricButton {
                Spacer().frame(height: 22)
                biometricButton
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 440)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.0)],
                        center: .center,
                        startRadius: 24,
                        endRadius: 130
                    )
                )
                .frame(width: 250, height: 250)

            ZStack(alignment: .bottomTrailing) {
                appIcon
                    .frame(width: 106, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 22, y: 10)

                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .offset(x: 9, y: 9)
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let appIcon = model.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .padding(20)
                .foregroundStyle(.white.opacity(0.75))
                .background(Color.white.opacity(0.12))
        }
    }

    private var title: some View {
        VStack(spacing: 5) {
            Text("App is Locked")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.appName)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }

    private var passcodeField: some View {
        HStack(spacing: 20) {
            ForEach(0..<max(model.passcodeLength, 1), id: \.self) { index in
                ZStack {
                    Circle().fill(index < model.enteredCount ? Color.white : Color.clear)
                    Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                }
                .frame(width: 15, height: 15)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.enteredCount)
    }

    private var hintRow: some View {
        Group {
            if let message = model.message {
                Text(message)
                    .foregroundStyle(Color.red.opacity(0.95))
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "keyboard")
                    Text(
                        model.showBiometricButton
                            ? "Type your passcode, or use \(model.biometryLabel)"
                            : "Type your passcode"
                    )
                }
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .frame(height: 20)
    }

    private var biometricButton: some View {
        Button {
            model.onBiometricTap?()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "touchid")
                    .font(.system(size: 16, weight: .medium))
                Text("Unlock with \(model.biometryLabel)")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.13)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
