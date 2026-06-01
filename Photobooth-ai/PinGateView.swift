import SwiftUI
import LocalAuthentication

/// Full-screen PIN gate that blocks access to operator settings.
/// The operator must enter the configured PIN (or use biometrics) to proceed.
struct PinGateView: View {
    let eventId: UUID
    let onUnlock: () -> Void

    @Environment(AppState.self) private var app

    // MARK: - State
    @State private var entered: [Int] = []          // digits entered so far
    @State private var shakeOffset: CGFloat = 0     // drives "wrong PIN" shake
    @State private var failCount: Int = 0
    @State private var cooldownSeconds: Int = 0
    @State private var cooldownTimer: Timer? = nil
    @State private var biometryType: LABiometryType = .none
    @State private var wrongLabel: Bool = false

    private var pin: String {
        app.settings(for: eventId).lockPin.pin
    }

    private var pinLength: Int {
        max(4, min(6, pin.isEmpty ? 4 : pin.count))
    }

    private var enteredString: String {
        entered.map(String.init).joined()
    }

    private var onCooldown: Bool { cooldownSeconds > 0 }

    // MARK: - Body

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            VStack(spacing: BoothifySpacing.xl) {
                Spacer()

                // Lock icon + title
                VStack(spacing: BoothifySpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(BoothifyTheme.textSecondary)

                    Text("Operator Settings")
                        .font(BoothifyType.title)
                        .foregroundStyle(BoothifyTheme.textPrimary)

                    if onCooldown {
                        Text("Too many attempts. Try again in \(cooldownSeconds)s")
                            .font(BoothifyType.caption)
                            .foregroundStyle(BoothifyTheme.error)
                    } else if wrongLabel {
                        Text("Wrong PIN")
                            .font(BoothifyType.caption)
                            .foregroundStyle(BoothifyTheme.error)
                    } else {
                        Text("Enter your PIN to continue")
                            .font(BoothifyType.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }

                // Dot indicators
                HStack(spacing: BoothifySpacing.md) {
                    ForEach(0..<pinLength, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? BoothifyTheme.violet : BoothifyTheme.surface2)
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: shakeOffset)
                .animation(.default, value: entered.count)

                Spacer()

                // NumPad
                numPad
                    .disabled(onCooldown)
                    .opacity(onCooldown ? 0.4 : 1)

                // Biometry button
                if biometryType != .none {
                    Button {
                        authenticateWithBiometrics()
                    } label: {
                        Image(systemName: biometryType == .faceID ? "faceid" : "touchid")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(onCooldown)
                    .opacity(onCooldown ? 0.4 : 1)
                }

                Spacer().frame(height: BoothifySpacing.lg)
            }
            .padding(.horizontal, BoothifySpacing.xl)
        }
        .onAppear {
            detectBiometryType()
        }
        .onDisappear {
            cooldownTimer?.invalidate()
        }
    }

    // MARK: - NumPad

    private var numPad: some View {
        let rows: [[Int?]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [nil, 0, -1]   // nil = blank, -1 = delete
        ]

        return VStack(spacing: BoothifySpacing.sm) {
            ForEach(rows.indices, id: \.self) { ri in
                HStack(spacing: BoothifySpacing.sm) {
                    ForEach(rows[ri].indices, id: \.self) { ci in
                        if let key = rows[ri][ci] {
                            numKey(key)
                        } else {
                            Color.clear.frame(width: 64, height: 64)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func numKey(_ key: Int) -> some View {
        Button {
            handleKey(key)
        } label: {
            Group {
                if key == -1 {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(key)")
                        .font(.title2.bold())
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 64, height: 64)
            .background(BoothifyTheme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func handleKey(_ key: Int) {
        guard !onCooldown else { return }
        Haptics.selection()

        if key == -1 {
            if !entered.isEmpty { entered.removeLast() }
            wrongLabel = false
        } else {
            guard entered.count < pinLength else { return }
            entered.append(key)

            if entered.count == pinLength {
                validate()
            }
        }
    }

    private func validate() {
        if enteredString == pin {
            Haptics.notify(.success)
            onUnlock()
        } else {
            Haptics.notify(.error)
            triggerShake()
            failCount += 1
            entered = []
            wrongLabel = true

            if failCount >= 3 {
                startCooldown()
            }
        }
    }

    private func triggerShake() {
        let total = 6
        let distance: CGFloat = 10
        for i in 0..<total {
            let delay = Double(i) * 0.06
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    shakeOffset = (i % 2 == 0) ? distance : -distance
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(total) * 0.06) {
            withAnimation(.easeOut(duration: 0.05)) {
                shakeOffset = 0
            }
        }
    }

    private func startCooldown() {
        failCount = 0
        cooldownSeconds = 30
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            cooldownSeconds -= 1
            if cooldownSeconds <= 0 {
                timer.invalidate()
                cooldownTimer = nil
                wrongLabel = false
            }
        }
    }

    private func detectBiometryType() {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometryType = ctx.biometryType
        }
    }

    private func authenticateWithBiometrics() {
        let ctx = LAContext()
        ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock operator settings"
        ) { success, _ in
            DispatchQueue.main.async {
                if success {
                    Haptics.notify(.success)
                    onUnlock()
                } else {
                    Haptics.notify(.error)
                }
            }
        }
    }
}
