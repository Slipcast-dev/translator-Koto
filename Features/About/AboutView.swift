import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Отдельное окно About содержит продуктовые сведения из подписываемого bundle.
struct AboutView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 15) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)
            Text(ProductInfo.name)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(ProductInfo.versionDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(String(localized: "Developer: \(ProductInfo.developer)"))
                .font(.headline)
                .textSelection(.enabled)
            Text(ProductInfo.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "Close")) {
                dismissWindow(id: WindowID.about)
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, 5)
        }
        .padding(30)
        .frame(width: 390)
        .accessibilityIdentifier("koto.about")
    }
}
