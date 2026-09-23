import SwiftUI

/// Чужая тревога: показывается доверенному контакту поверх любого экрана — где человек и когда была связь.
struct SosAlertView: View {
    let alert: SosAlert
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("\(alert.displayName) просит помощи")
                .font(.app(.title2, weight: .bold))
                .multilineTextAlignment(.center)
            if !alert.note.isEmpty {
                Text(alert.note)
                    .font(.app(.subheadline))
                    .multilineTextAlignment(.center)
            }
            Text("Обновлено \(alert.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
            if let accuracy = alert.accuracyM {
                Text("Точность около \(Int(accuracy)) м")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                if let url = URL(string: alert.mapsUrl) {
                    Link(destination: url) {
                        Label("Показать на карте", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .glassProminentButtonStyle()
                    .controlSize(.large)
                }
                Button("Закрыть", action: onClose)
                    .glassButtonStyle()
                    .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(24)
    }
}
