import Foundation
import SwiftUI
import SayoneCore

/// Explains the app and asks for Health access (write AND read Water).
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @AppStorage("onboardingDismissed") private var onboardingDismissed: Bool = false
    @State private var isRequesting: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                features
                readHint
                if model.healthAuth == .denied {
                    deniedHint
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { buttons }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            Text(verbatim: "SayoneHealth")
                .font(.largeTitle.weight(.bold))
            Text("Every drink you log is saved to Apple Health.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingFeatureRow(symbol: "hand.tap.fill",
                                 text: "Tap a button to log water, Cola Zero or your own drink.")
            OnboardingFeatureRow(symbol: "heart.text.square.fill",
                                 text: "Water, caffeine, calories and sugar go to Health.")
            OnboardingFeatureRow(symbol: "applewatch",
                                 text: "Widgets, Apple Watch and Siri log drinks without opening the app.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readHint: some View {
        Label {
            Text("Allow both writing and reading Water. Reading lets the total include drinks logged on your other device.")
                .font(.callout)
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var deniedHint: some View {
        Label {
            Text("If access is denied, allow it in Settings → Privacy & Security → Health → SayoneHealth.")
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                allow()
            } label: {
                Text("Allow Access to Health")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRequesting)
            Button("Later") {
                close()
            }
            .disabled(isRequesting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func allow() {
        // HealthKit never shows its sheet twice: once denied, the only way back is Settings.
        if model.healthAuth == .denied, let settings = URL(string: "app-settings:") {
            openURL(settings)
            return
        }
        isRequesting = true
        Task {
            await model.requestHealthAccess()
            isRequesting = false
            close()
        }
    }

    private func close() {
        onboardingDismissed = true
        model.showHealthOnboarding = false
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
