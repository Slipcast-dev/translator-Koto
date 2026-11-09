import SwiftUI

// Сообщения разрешаются через Foundation, чтобы меню, ошибки и SwiftUI использовали один язык.

/// Панель разрешений быстрого перевода: что именно нужно, зачем, выдано ли, и что будет дальше.
/// Статусы обновляются сами; после выдачи доступа Koto продолжает исходную команду без повторного нажатия.
struct CapturePermissionView: View {
    @Bindable var coordinator: CaptureCoordinator

    private var reason: String {
        switch coordinator.pendingCapture {
        case .selection: String(localized: "To translate selected text, Koto needs the Accessibility permission.")
        case .region: String(localized: "To recognize a screen region, Koto needs the Screen & System Audio Recording permission.")
        case nil: String(localized: "Quick translation from other apps needs macOS permissions.")
        }
    }

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Access needed")).font(.headline)
                    Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                row(symbol: "text.cursor", title: String(localized: "Selected text"),
                    detail: String(localized: "System Settings → Privacy & Security → Accessibility"),
                    granted: coordinator.accessibilityGranted, needed: coordinator.pendingCapture == .selection,
                    action: { coordinator.requestAccessibility() })
                Divider().padding(.leading, 44)
                row(symbol: "viewfinder", title: String(localized: "Screen region and Live"),
                    detail: String(localized: "System Settings → Privacy & Security → Screen & System Audio Recording"),
                    granted: coordinator.screenGranted, needed: coordinator.pendingCapture == .region,
                    action: { coordinator.requestScreen() })
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if coordinator.screenAccessRequested && !coordinator.screenGranted {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "After turning on screen recording, macOS may need Koto to restart before the permission works."))
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                        Button(String(localized: "Restart Koto")) { coordinator.relaunch() }.controlSize(.small)
                    }
                }
            }
            if coordinator.runsOutsideApplications {
                note(symbol: "folder.badge.questionmark",
                     String(localized: "Koto is running from a download or disk image. macOS does not keep permissions for such a copy. Move Koto to Applications and open it from there."))
            }
            if coordinator.permissionHelpNeeded {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Koto is turned on in the list but access does not appear?"), systemImage: "questionmark.circle.fill")
                        .font(.callout.weight(.semibold))
                    Text(String(localized: "The entry in the list usually belongs to another Koto build. Click Reset and ask again, then turn Koto on once more."))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(String(localized: "Reset and ask again")) { coordinator.resetPermissions() }
                            .disabled(coordinator.resettingPermissions)
                        if coordinator.resettingPermissions { ProgressView().controlSize(.small) }
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if coordinator.pendingCapture != nil {
                Label(String(localized: "Koto continues on its own as soon as access is granted."), systemImage: "bolt.horizontal.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(String(localized: "Manual translation works without these permissions. Text and images are not saved. After a Koto update macOS may ask for access again."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(symbol: String, title: String, detail: String, granted: Bool, needed: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 24).foregroundStyle(needed && !granted ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(needed ? .semibold : .regular)
                Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label(String(localized: "Allowed"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).font(.callout).foregroundStyle(.green)
            } else {
                if needed {
                    Button(String(localized: "Allow…"), action: action).buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "Allow…"), action: action).buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
