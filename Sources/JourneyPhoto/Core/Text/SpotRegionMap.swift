import Foundation

/// 探すの「撮影スポット」の段の**地図**（札 #524 の続き・2026-11-11 owner「iOS 側にもこの機能欲しい」）。
///
/// Web のホームの日本地図（`HomeJapanMap`）と同じ考え: 地方を押す（長押しでなぞる・ひと押しでも選べる）と、
/// その地方が真鍮で塗られ、札に「撮影スポット N件」「上位の名前 ほか」「すべて見る」が出る。
/// 形と当たり判定は「行った県」の地図と同じ `PrefectureMapGeometry`（県の形・沖縄の挿入図）を使い回し、
/// 県から地方へは `PrefectureRegions` で引く（写しを作らない）。
///
/// 2026-11-11 判断: Web は「地方 → 拡大して県」の2段だが、探すの段は高さを決めた1段（212pt）の中に置くので
/// **地方だけ**を選ぶ。県はその先の一覧（県ごとの見出し）と、写真の札の列で選べる。
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum SpotRegionMap {

    /// 地図の上の点（画面の pt・地図の枠の左上が原点）にある地方。**撮影スポットのある地方だけ**
    /// （無い地方を選ぶと段が別の地方へ落ちるので、押しても何もしない）。
    /// 当たりは「行った県」の地図と同じ（線の内側・近い県・沖縄の挿入図）
    static func region(at point: CGPoint, container: CGSize, geometry: PrefectureMapGeometry,
                       groups: [SpotPrefectureIndex.Group]) -> String? {
        let viewport = VisitedMapViewport()
        let unit = viewport.unitPoint(forScreen: point, content: geometry.size, container: container)
        let tolerance = viewport.tolerance(content: geometry.size, container: container)
        guard let prefecture = geometry.prefecture(at: unit, tolerance: tolerance),
              let region = PrefectureRegions.region(of: prefecture),
              groups.contains(where: { $0.region.name == region.name }) else { return nil }
        return region.name
    }

    /// 地図で塗る県（選んでいる・なぞっている地方の県）
    static func highlighted(_ regionName: String?) -> Set<String> {
        guard let regionName, let region = PrefectureRegions.all.first(where: { $0.name == regionName }) else { return [] }
        return Set(region.prefectures)
    }

    /// 撮影スポットのある県（無い県は地を沈める）
    static func covered(_ groups: [SpotPrefectureIndex.Group]) -> Set<String> {
        Set(groups.flatMap { $0.cards.map(\.prefecture) })
    }

    /// なぞるのを始める長押しの長さ（Web の `traceGesture` と同じ 250ms）
    nonisolated static let traceDelay: Double = 0.25

    /// 札の「すべて見る」の字（「北海道の撮影スポットをすべて見る」）
    static func seeAll(_ group: SpotPrefectureIndex.Group) -> String {
        L("\(group.region.name)の撮影スポットをすべて見る",
          "See all photo spots in \(PrefectureRegions.englishName(group.region))")
    }
}
