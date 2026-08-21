import SwiftUI

/// Common chrome for every modal sheet, per the handoff: header row with title + close (×),
/// scrollable body with 18/20px padding and 14px gap between fields, footer row with
/// right-aligned actions. Wrap a sheet's content in this rather than hand-rolling headers.
struct NocturneSheet<Content: View, Footer: View>: View {
    var title: String
    var width: CGFloat = 460
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(18)
            }
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                footer()
            }
            .padding(16)
        }
        .frame(width: width)
        .background(Theme.Color.surface)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(Theme.Font.heading(17))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.nocturneIcon)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

extension View {
    /// Applies Nocturne's sheet chrome (12px radius, 1px `neutral-700` border) to native
    /// `.sheet(...)` presentation content.
    func nocturneSheetPresentation() -> some View {
        presentationBackground {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.Color.neutral700, lineWidth: 1)
                )
        }
        .presentationCornerRadius(12)
    }
}
