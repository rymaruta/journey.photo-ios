import MapKit
import SwiftUI
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「電波なしで使える旅」の材料の本物の取り方（作例は台帳の本文、地図は `MKMapSnapshotter`）。
/// 置き場（`OfflineTripStore`）はこれを受け取るだけ
enum OfflineTripLive {

    /// 保存の前の下ごしらえ: 索引の行に詳細（時刻帯・写真）を重ねてから場所を並べる。
    /// **時刻帯が無いと、時刻帯が複数ある国の光の時刻を決められない**（`SunTimes.timeZone(named:country:)`）
    static func plannedStops(plan: TripPlan, environment: AppEnvironment, index: [OfficialSpot],
                             places: [DerivedSpot.Place]) async -> (stops: [OfflineTripPlan.Stop], index: [OfficialSpot]) {
        let ids = Set(plan.days.flatMap(\.items).compactMap { item -> String? in
            if case .spot(let spotId, _) = item { return spotId }
            return nil
        })
        let needed = index.filter { ids.contains($0.spotId) }
        let detailed = needed.isEmpty ? index : await environment.spots.withDetails(index, for: needed)
        return (OfflineTripPlan.stops(of: plan, index: detailed, places: places), detailed)
    }

    @MainActor
    static func sources(environment: AppEnvironment, index: [OfficialSpot],
                        places: [DerivedSpot.Place]) -> OfflineTripSources {
        let spots = environment.spots
        return OfflineTripSources(
            samples: { stop in
                await samples(for: stop, spots: spots, index: index, places: places)
            },
            download: { url in
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            },
            stopMap: { stop in
                guard let c = stop.coords else { return nil }
                return await snapshot(OfflineTripMap.around(c), size: OfflineTripMap.stopSize,
                                      dots: [(stop.number, c)])
            },
            overviewMap: { stops in
                let dots = stops.compactMap { s in s.coords.map { (s.number, $0) } }
                guard let region = OfflineTripMap.overview(dots.map(\.1)) else { return nil }
                return await snapshot(region, size: OfflineTripMap.overviewSize, dots: dots)
            })
    }

    /// 作例の候補。**撮影スポットは台帳の本文の作例**（無ければスポットの写真1枚）、
    /// **撮影地はその場所の写真**（いちばん多く押された順）
    private static func samples(for stop: OfflineTripPlan.Stop, spots: OfficialSpotService,
                                index: [OfficialSpot], places: [DerivedSpot.Place]) async -> [OfflineSampleSource] {
        switch stop.item {
        case .spot(let spotId, _):
            guard let spot = index.first(where: { $0.spotId == spotId }) else { return [] }
            let body = await spots.fetchBody(slug: spot.slug)
            let fromBody = (body?.samples ?? []).map {
                OfflineSampleSource(url: $0.src, title: $0.title, credit: $0.credit,
                                    sourceUrl: $0.sourceUrl, licenseUrl: $0.licenseUrl)
            }
            if !fromBody.isEmpty { return fromBody }
            guard let photo = spot.photo else { return [] }
            return [OfflineSampleSource(url: photo.url, title: spot.name, credit: photo.credit,
                                        sourceUrl: photo.pageUrl, licenseUrl: photo.licenseUrl)]
        case .location(let slug, _):
            guard let place = places.first(where: { $0.slug == slug }) else { return [] }
            return GallerySort.popular.apply(place.photos).compactMap { photo in
                guard let url = photo.detailImageURL else { return nil }
                let name = photo.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
                return OfflineSampleSource(url: url,
                                           title: photo.displayTitle.isEmpty ? place.label : photo.displayTitle,
                                           credit: name.isEmpty ? "journey.photo" : L("写真: \(name)", "Photo: \(name)"),
                                           sourceUrl: nil, licenseUrl: nil)
            }
        }
    }

    /// 地図を撮り、番号の点（真鍮・黒の縁・墨の数字・板 72c）を描いた JPEG。撮れなければ nil
    @MainActor
    private static func snapshot(_ region: OfflineTripMap.Region, size: (width: Double, height: Double),
                                 dots: [(Int, Photo.Coords)]) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: region.lat, longitude: region.lng),
            span: MKCoordinateSpan(latitudeDelta: region.latDelta, longitudeDelta: region.lngDelta))
        options.size = CGSize(width: size.width, height: size.height)
        // 黒い画面に合わせて暗い地図で撮る
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        guard let shot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let canvas = CGSize(width: size.width, height: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let data = renderer.jpegData(withCompressionQuality: 0.8) { _ in
            shot.image.draw(in: CGRect(origin: .zero, size: canvas))
            for (number, coords) in dots {
                let p = shot.point(for: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng))
                drawDot(number: number, at: p)
            }
        }
        return data.isEmpty ? nil : data
    }

    /// 番号の点（直径 24pt）
    private static func drawDot(number: Int, at p: CGPoint) {
        let r = 12.0
        let circle = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        // 真鍮 #C9A66B（黒い地図の上だけ・デザインシステム）
        UIColor(red: 0xC9 / 255.0, green: 0xA6 / 255.0, blue: 0x6B / 255.0, alpha: 1).setFill()
        circle.fill()
        UIColor.black.setStroke()
        circle.lineWidth = 2
        circle.stroke()
        let text = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            // 墨 #07090A
            .foregroundColor: UIColor(red: 0x07 / 255.0, green: 0x09 / 255.0, blue: 0x0A / 255.0, alpha: 1),
        ]
        let s = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: attrs)
    }
}
