import MapKit
import SwiftUI

/// Чужая тревога: показывается доверенному контакту поверх любого экрана — где человек, куда двигался и когда была связь.
struct SosAlertView: View {
    let alert: SosAlert
    let onClose: () -> Void
    @State private var track: [SosTrackPoint] = []

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
            SosTrackMap(alert: alert, track: track)
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        // Новая точка приходит событием safety.sos.location — вместе с ней перечитываем путь.
        .task(id: alert.updatedAt) {
            do {
                track = try await APIClient.shared.fetchSosTrack(alertId: alert.id)
            } catch {
                // Без пути карта всё равно показывает последнюю точку из самой тревоги.
                track = []
            }
        }
    }
}

/// Последняя точка — маркером, пройденный путь — линией. Пока человек не двигал карту сам, она охватывает весь путь.
struct SosTrackMap: View {
    let alert: SosAlert
    let track: [SosTrackPoint]
    @State private var position: MapCameraPosition = .automatic

    private var current: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: alert.latitude, longitude: alert.longitude)
    }

    private var path: [CLLocationCoordinate2D] {
        track.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Map(position: $position) {
            if path.count > 1 {
                MapPolyline(coordinates: path)
                    .stroke(.red, lineWidth: 4)
            }
            Marker(alert.displayName, systemImage: "exclamationmark.triangle.fill", coordinate: current)
                .tint(.red)
        }
        .onAppear(perform: fitAll)
        .onChange(of: track) {
            guard !position.positionedByUser else { return }
            fitAll()
        }
        .accessibilityLabel("Карта: где \(alert.displayName) и куда двигался(ась)")
    }

    private func fitAll() {
        position = .region(Self.region(covering: path + [current]))
    }

    /// Минимальный размах — чтобы одна точка или стояние на месте не давали карту «до подъезда».
    static let minimumSpanDegrees = 0.005
    private static let marginFactor = 1.4

    static func region(covering coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return MKCoordinateRegion()
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * marginFactor, minimumSpanDegrees),
            longitudeDelta: max((maxLon - minLon) * marginFactor, minimumSpanDegrees)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
