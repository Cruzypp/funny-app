import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct SafetyHeatmapMap: View {
    var zones: [SafetyZonePrediction]
    var night: Bool

    @State private var position: MapCameraPosition

    init(zones: [SafetyZonePrediction], night: Bool) {
        self.zones = zones
        self.night = night
        _position = State(initialValue: .region(Self.region(for: zones)))
    }

    var body: some View {
        Map(position: $position) {
            ForEach(zones) { zone in
                MapCircle(center: zone.coordinate, radius: zone.radiusMeters)
                    .foregroundStyle(zone.level.heatColor.opacity(zone.opacity))

                Annotation("", coordinate: zone.coordinate) {
                    Circle()
                        .fill(zone.level.heatColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: zone.level.heatColor.opacity(0.35), radius: 8)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .preferredColorScheme(night ? .dark : .light)
        .frame(maxWidth: .infinity)
        .frame(height: 460)
        .onChange(of: zoneSignature) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                position = .region(Self.region(for: zones))
            }
        }
    }

    private var zoneSignature: String {
        zones
            .map { "\($0.id):\(Int(($0.riskScore * 100).rounded()))" }
            .joined(separator: "|")
    }

    private static func region(for zones: [SafetyZonePrediction]) -> MKCoordinateRegion {
        let coordinates = zones.map(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? 19.4326
        let maxLat = latitudes.max() ?? 19.4326
        let minLng = longitudes.min() ?? -99.1332
        let maxLng = longitudes.max() ?? -99.1332

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.025, (maxLat - minLat) * 1.7),
            longitudeDelta: max(0.025, (maxLng - minLng) * 1.7)
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
