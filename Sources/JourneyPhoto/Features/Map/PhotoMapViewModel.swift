import Foundation
import Combine

/// 撮影地マップの頭。絞りの条件を持ち、**地図とリストの両方が同じ `shown`
/// から描く**（ピンの数＝行の数）。
///
/// 絞るのは手元の配列だけ。打っている間に通信はしない。
@MainActor
final class PhotoMapViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case map, list
        var id: String { rawValue }
        var label: String {
            switch self {
            case .map: return L("地図", "Map")
            case .list: return L("リスト", "List")
            }
        }
    }

    @Published private(set) var photos: [Photo] = []
    /// 台帳。取れなければ空のまま（札のスポット導線が出ないだけ）
    @Published private(set) var spots: [Spot] = []
    @Published private(set) var loaded = false
    @Published var query = ""
    @Published private(set) var category: String?
    @Published var mode: Mode = .map
    /// いま地図に見えている範囲。`onMapCameraChange` が届くたびに更新する。
    /// **見えているだけでは絞らない**（`applyArea` を押したときだけ）
    @Published private(set) var visibleFrame: MapFraming.Frame?
    /// 「このエリアを検索」で固定した範囲
    @Published private(set) var areaFrame: MapFraming.Frame?

    /// 条件に合う写真。座標の無い写真は入らない（`MapSearch` の約束）
    var shown: [Photo] {
        MapSearch.photos(photos, filter: MapSearch.Filter(query: query, category: category, frame: areaFrame),
                         spots: spots)
    }

    /// ピン。**リストの行もこれ**（同じ束ね）
    var pins: [MapPin] { MapPin.group(shown) }

    /// チップに出すカテゴリ。**座標のある写真だけ**から数える——座標の無い
    /// 写真しか持たないカテゴリのチップは、押しても地図が空になる
    var categories: [String] {
        CategoryChoices.present(in: photos.filter { $0.coords != nil })
    }

    /// 何かで絞っているか（空のときの言葉を「無い」と「見つからない」で分ける）
    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category != nil || areaFrame != nil
    }

    func load(environment: AppEnvironment) async {
        photos = (try? await environment.gallery.fetchPhotos()) ?? []
        spots = await environment.spots.fetchSpots()
        loaded = true
    }

    /// チップ。**押し直すと外れる**（`CategoryChoices.toggle` と同じ約束）
    func select(category choice: String?) {
        guard let choice else {
            category = nil
            return
        }
        let next = CategoryChoices.toggle(current: category ?? "", choice: choice)
        category = next.isEmpty ? nil : next
    }

    func update(visible frame: MapFraming.Frame) {
        visibleFrame = frame
    }

    /// 「このエリアを検索」。**押したときの範囲**で固定する
    func applyArea() {
        guard let visibleFrame else { return }
        areaFrame = visibleFrame
    }

    func clearArea() {
        areaFrame = nil
    }

    /// 札に出すスポット（台帳に実在するものだけ）
    func spots(for pin: MapPin) -> [Spot] {
        MapSearch.spots(for: pin.photos, in: spots)
    }

    /// いまのピンに合わせた枠（無ければ nil＝地図の既定に任せる）
    var frame: MapFraming.Frame? {
        MapFraming.frame(for: pins.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
    }
}
