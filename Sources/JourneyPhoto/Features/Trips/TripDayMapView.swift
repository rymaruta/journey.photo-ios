import SwiftUI
import MapKit

/// 旅行プランの1日を地図で見る（`TripDayMap`・2026-09-30 owner の判断「次」の段）。
///
/// その日の場所を**日程の順の番号**で地図に置き、下の一覧から1か所ずつ「前の場所からの経路」を
/// Apple のマップで開く。1か所目は今いる場所から。距離・時間は出さない（計算していない）。
///
/// 見た目: 地図のピンは真鍮の塗り＋墨の番号＋黒の縁（件数バッジと同じ部品・地図の上は黒い地ではないが、
/// owner の好み「地図のピンは真鍮」に合わせる・CLAUDE.md）。一覧は黒地
struct TripDayMapView: View {

    let title: String
    let stops: [TripDayMap.Stop]

    @State private var camera: MapCameraPosition = .automatic
    /// 経路を探している場所（連打で2つ開かない）
    @State private var opening: Int?
    /// 経路を探している仕事。**画面を閉じたら取り消す**
    @State private var directionsTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                ForEach(stops.filter { $0.coords != nil }) { stop in
                    // 題はピンの下に字で出る。番号はピンにあるので題には入れない（二重に見えた・0755872 のレビュー）
                    Annotation(stop.name, coordinate: coordinate(stop.coords!)) {
                        pin(stop)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            // 地図そのものにラベルを付けない（1つの要素にまとまってピンに入れなくなりうる・`PhotoMapView` も付けていない）

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stops) { stop in
                        if stop.number > 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                        row(stop)
                    }
                    Text(L("経路は Apple のマップで開きます。座標は約1kmに丸めてあるので、場所の名前で探し直してから開きます。",
                           "Directions open in Apple Maps. Coordinates are rounded to about 1 km, so the place is looked up by name first."))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.top, 14)
                }
                .padding(16)
            }
        }
        .webScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
        }
        .onDisappear { directionsTask?.cancel() }
    }

    private func coordinate(_ coords: Photo.Coords) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
    }

    /// 番号のピン（真鍮の塗り＋墨の番号＋黒の縁）
    private func pin(_ stop: TripDayMap.Stop) -> some View {
        Text("\(stop.number)")
            .font(JPFont.mono(14, medium: true))
            .foregroundStyle(WebTheme.accentText)
            .frame(width: 30, height: 30)
            .background(WebTheme.accentFill, in: Circle())
            .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
            // 読み上げは名前と番号を1つに（題とピンに分けると、どちらかが欠けうる・86a6edb のレビュー。
            // `PhotoMapView` の撮影スポットの印と同じく、ピンに名前ごと付ける）
            .accessibilityLabel(Self.spokenLabel(stop))
    }

    /// 「清水寺、1 か所目」
    static func spokenLabel(_ stop: TripDayMap.Stop) -> String {
        L("\(stop.name)、\(stop.number) か所目", "\(stop.name), stop \(stop.number)")
    }

    private func row(_ stop: TripDayMap.Stop) -> some View {
        HStack(spacing: 12) {
            Text("\(stop.number)")
                .font(JPFont.mono(14, medium: true))
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                    // 番号の字は読み上げから外してあるので、ピンと照らし合わせられるよう名前に付ける
                    .accessibilityLabel(Self.spokenLabel(stop))
                if stop.coords == nil {
                    Text(L("地図の場所が分かりません", "No map location"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                } else if let from = stop.fromName {
                    Text(L("\(from) から", "From \(from)"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                } else {
                    Text(L("今いる場所から", "From your location"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
            }
            Spacer(minLength: 8)
            if let to = stop.coords {
                // ヘッダーの文字の合図と同じ真鍮（黒地）
                Button {
                    openDirections(stop, to: to)
                } label: {
                    Text(opening == stop.number ? L("開いています…", "Opening…") : L("経路", "Directions"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(opening != nil)
                .accessibilityLabel(L("\(stop.name)への経路", "Directions to \(stop.name)"))
            }
        }
        .accessibilityElement(children: .contain)
        .frame(minHeight: 56)
    }

    /// 前の場所（1か所目は今いる場所）から、この場所への経路。行き先・起点とも名前で探し直す
    ///
    /// 🔴 **閉じたら開かない。** 探している間（最大で数秒）に画面を閉じると、閉じたあとで
    /// Apple のマップが開いていた（押していないものが開く・eaf0c48 のレビュー）。
    /// 起点と行き先は並べて探す（待ちを1回分にする）
    private func openDirections(_ stop: TripDayMap.Stop, to: Photo.Coords) {
        guard opening == nil else { return }
        opening = stop.number
        directionsTask = Task { @MainActor in
            defer { opening = nil }
            async let destination = SpotDirections.item(name: stop.name, coords: to)
            let origin: MKMapItem
            if let from = stop.from, let fromName = stop.fromName {
                origin = await SpotDirections.item(name: fromName, coords: from)
            } else {
                origin = MKMapItem.forCurrentLocation()
            }
            let target = await destination
            guard !Task.isCancelled else { return }
            MKMapItem.openMaps(with: [origin, target], launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
            ])
        }
    }
}
