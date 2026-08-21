import SwiftUI

/// Ephemeral top-center confirmations (e.g. "Project created", "Compiled to ~/Desktop/…"),
/// auto-dismissing after ~2.5s, per the handoff. Nothing like this existed before the revamp —
/// screens that used to show `.alert` for one-shot confirmations should call `ToastCenter.show`
/// instead where the spec calls for a toast.
@MainActor
@Observable
final class ToastCenter {
    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(2.5)) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

private struct NocturneToastOverlay: View {
    var center: ToastCenter

    var body: some View {
        VStack {
            if let message = center.message {
                Text(message)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.Color.neutral800)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Color.neutral700, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
            Spacer()
        }
        .animation(.easeOut(duration: 0.2), value: center.message)
        .allowsHitTesting(false)
    }
}

extension View {
    func nocturneToastOverlay(center: ToastCenter) -> some View {
        overlay(alignment: .top) { NocturneToastOverlay(center: center) }
    }
}
