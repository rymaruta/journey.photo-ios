import SwiftUI
import MapKit

/// 「行きたい場所」を地図で見る（3か月の計画の7の第一歩・2026-10-03）。
///
/// マイページの「行きたい場所」のタブの「地図で見る」から積む。並べるのは一覧と同じ行
/// （撮影地と台帳の撮影スポット）で、分け方・枠の計算は `SavedSpotsMap`（Linux で試験）。
///
///  - 地図の枠は**保存した場所が全部入る範囲**（`SavedSpotsMap.frame`。地図のタブのように
///    「いちばん重い塊」には寄せない）
///  - ピンは撮影スポットと同じ印（`SpotMapMarker`・真鍮）。押すと撮影スポットの画面へ
///  - 座標の無いものは地図の下に一覧で残す（黙って消さない）
///  - 0件のときは「撮影スポットを探す」（地図のタブ）への出口
///
/// 🔴 **行は積んだときの写しを受け取る**（`MyPageView.wishIds` と同じ理由）。開いた
/// スポットで♥を外した瞬間に行が消えると、開いている画面が閉じる。戻れば一覧が取り直す
struct SavedSpotsMapView: View {

    let split: SavedSpotsMap.Split
    /// 撮影スポットの画面に渡す索引（近くのスポットを出すのに使う）
    let officialSpots: [OfficialSpot]
    /// 撮影地・撮影スポットの画面に渡す写真の集まり（マイページの `pool`）
    let photos: [Photo]
    /// 写真の一覧が読めているか（`OfficialSpotView.photosKnown`）
    let photosKnown: Bool

    @State private var camera: MapCameraPosition = .automatic
    /// 押したピン・行の鍵。開く先は `navigationDestination(item:)`
    @State private var opened: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if split.isEmpty {
                    emptyArea
                } else {
                    Text(SavedSpotsMap.summary(split))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 16)
                    if !split.pinned.isEmpty {
                        map
                    }
                    if !split.unplaced.isEmpty {
                        unplacedList
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .webScreen()
        .navigationTitle(L("行きたい場所の地図", "Want-to-go map"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { key in
            destination(for: key)
        }
        .onAppear { frame() }
    }

    // MARK: - 地図

    private var map: some View {
        Map(position: $camera) {
            ForEach(split.pinned) { item in
                // 題は MapKit がピンの下に字で描く（地図のタブの撮影スポットと同じ）
                Annotation(item.name, coordinate: coordinate(item)) {
                    Button {
                        open(item)
                    } label: {
                        // 印は 32〜40pt のまま、押せる範囲だけ 44pt に広げる（中心は変わらない）
                        SpotMapMarker(photoURL: item.imageURL)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // 地図に置けるものは必ず開ける（座標を持つスポットは索引の行がある）
                    .accessibilityLabel(SavedSpotsMap.spokenLabel(item))
                    .accessibilityHint(L("撮影スポットの画面を開きます", "Opens the spot"))
                    .accessibilityIdentifier("savedMap.pin")
                }
            }
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        // 地図そのものにラベルを付けない（1つの要素にまとまってピンに入れなくなりうる・`TripDayMapView` と同じ）
    }

    private func coordinate(_ item: SavedSpotsMap.Item) -> CLLocationCoordinate2D {
        let coords = item.coords ?? Photo.Coords(lat: 0, lng: 0)
        return CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
    }

    /// 枠は全部が入る範囲（`SavedSpotsMap.frame`）。点が無ければ地図の既定のまま
    private func frame() {
        guard let frame = SavedSpotsMap.frame(for: split.pinned.compactMap(\.coords)) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
            span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                   longitudeDelta: frame.longitudeSpan)
        ))
    }

    // MARK: - 座標の無いもの

    private var unplacedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("地図に置けない場所", "Not on the map"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(L("場所（座標）が分からないため、地図には出していません。",
                   "These don't have a known location, so they aren't on the map."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .padding(.top, 4)
                .padding(.bottom, 6)
            ForEach(split.unplaced) { item in
                if item.canOpen {
                    Button { open(item) } label: { unplacedRow(item) }
                        .buttonStyle(.plain)
                        .accessibilityHint(L("撮影スポットの画面を開きます", "Opens the spot"))
                } else {
                    unplacedRow(item)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func unplacedRow(_ item: SavedSpotsMap.Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.canOpen {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(WebTheme.faint)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SavedSpotsMap.spokenLabel(item))
        .accessibilityIdentifier("savedMap.unplaced")
    }

    // MARK: - 0件

    /// 板 WishlistTab の B1（空）と同じ言い方。開いている間に全部外した回にここへ来る
    /// （ふだんは一覧が空なら「地図で見る」は出ない）
    private var emptyArea: some View {
        VStack(spacing: 4) {
            EmptyState(message: L("行きたい場所はまだありません。撮影スポットで「行きたい」を押すと、ここの地図に並びます。",
                                  "No places yet. Tap “Want to go” on a photo spot to see it on this map."))
            FindSpotsButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - 開く先

    private func open(_ item: SavedSpotsMap.Item) {
        guard item.canOpen else { return }
        opened = item.key
    }

    @ViewBuilder
    private func destination(for key: String) -> some View {
        let item = split.pinned.first { $0.key == key } ?? split.unplaced.first { $0.key == key }
        switch item?.target {
        case .place(let place):
            SpotDetailView(spot: place, photos: photos)
        case .official(let row):
            if let spot = row.spot {
                OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
            } else {
                EmptyState(message: L("この撮影スポットは開けません", "This spot can't be opened"))
            }
        case nil:
            EmptyState(message: L("この場所は開けません", "This place can't be opened"))
        }
    }
}

/// 「行きたい場所」が0件のときの出口（板 WishlistTab の B1「撮影スポットを探す」）。
/// 撮影スポットを名前・近い順で探せるのは地図のタブ（`OfficialPins` の注記——検索の画面には節を足さない）。
/// **写真の無い画面の主ボタン1つ＝真鍮の塗り＋墨の字**（デザインシステム・CLAUDE.md）
struct FindSpotsButton: View {
    var body: some View {
        Button {
            TabRouter.shared.openMap()
        } label: {
            Text(L("撮影スポットを探す", "Find photo spots"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .padding(.horizontal, 24)
                .frame(minHeight: 48)
                .background(WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("マップのタブを開きます", "Opens the Map tab"))
        .accessibilityIdentifier("wishlist.findSpots")
    }
}
