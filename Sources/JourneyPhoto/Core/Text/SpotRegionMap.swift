import Foundation

/// 探すの「撮影スポット」の段の**地図の型**（札 #524 の続き・2026-11-11 owner「iOS 側にもこの機能欲しい」
/// 「いずれは日本地図以外も選べるようにしたい」）。
///
/// Web のホームの日本地図（`HomeJapanMap`）と同じ考え: 区分を押す（長押しでなぞる・ひと押しでも選べる）と、
/// その区分が真鍮で塗られ、札に「撮影スポット N件」「上位の名前 ほか」「すべて見る」が出る。
///
/// 2026-11-11 判断（後で地図を足せる作り）:
/// - 地図を**型**として持つ: 名前・形（`SpotMapShapes`＝塗る片と当たり判定）・区分の作り方（台帳 → 区分ごとの束ね・
///   `SpotMapArea`）。日本（`.japan`）はその1つ目。地図の画面（`SpotRegionMapView`）・選ぶ操作・右の札・「すべて見る」は
///   **型に依らない**（区分の id・名前・件数・名前の行・行き先の `Scope` だけを読む）
/// - 2つ目（例: 世界を国・地域で塗る。台帳の海外は国の区分つきで 1,719 件）を足すときは、型を1つ作って
///   `SpotRegionMap.available` に足すだけ。地図が2つ以上になったら、地図の右上に小さな切り替え（「日本｜世界」）を
///   **地図の枠の中に重ねて**出す（段の高さは変えない・`showsSwitcher`）。今は1つなので出さない
/// - 日本の区分は地方（`PrefectureRegions`）。Web は「地方 → 拡大して県」の2段だが、段は高さを決めた1段（212pt）
///   なので地方だけを選ぶ。県はその先の一覧（県の見出し）と、写真の札の列で選べる。
///   日本の地方は上の地方のチップ・写真の札の列と**同じ選択**（`sharesRegionChips`）
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
struct SpotRegionMap: Identifiable {

    /// 地図の id（切り替え・選択の覚え先）
    let id: String
    /// 切り替えに出す名前（「日本」「世界」）
    let title: String
    /// 塗る形と当たり判定
    let shapes: SpotMapShapes
    /// 区分を作る（台帳 → 区分ごとの束ね）
    let areas: (SpotMapSource) -> [SpotMapArea]
    /// 上の地方のチップ・写真の札の列と選択を分け合うか（日本だけ）
    var sharesRegionChips = false

    /// 地図の上の点（画面の pt・地図の枠の左上が原点）にある区分の id。**撮影スポットのある区分だけ**
    /// （無い区分を押しても何もしない）。当たりは片の線の内側・近い片（`SpotMapShapes.piece(at:tolerance:)`）
    func area(at point: CGPoint, container: CGSize, in areas: [SpotMapArea]) -> String? {
        let viewport = VisitedMapViewport()
        let unit = viewport.unitPoint(forScreen: point, content: shapes.size, container: container)
        let tolerance = viewport.tolerance(content: shapes.size, container: container)
        guard let piece = shapes.piece(at: unit, tolerance: tolerance) else { return nil }
        return areas.first { $0.pieces.contains(piece) }?.id
    }

    /// 地図の切り替えを出すか（**地図が2つ以上のときだけ**。1つの間は出さない）
    static func showsSwitcher(_ maps: [SpotRegionMap]) -> Bool { maps.count > 1 }

    /// 塗る片（選んでいる・なぞっている区分の片）
    static func highlighted(_ areaId: String?, in areas: [SpotMapArea]) -> Set<String> {
        guard let areaId, let area = areas.first(where: { $0.id == areaId }) else { return [] }
        return area.pieces
    }

    /// 撮影スポットのある片（無い片は地を沈める）
    static func covered(_ areas: [SpotMapArea]) -> Set<String> {
        areas.reduce(into: Set<String>()) { $0.formUnion($1.coveredPieces) }
    }

    /// なぞるのを始める長押しの長さ（Web の `traceGesture` と同じ 250ms）
    nonisolated static let traceDelay: Double = 0.25

    // MARK: - 日本

    /// 日本地図（地方で塗る）。形は「行った県」の地図と同じ `PrefectureMapGeometry`
    static func japan(_ geometry: PrefectureMapGeometry) -> SpotRegionMap {
        SpotRegionMap(id: "japan", title: L("日本", "Japan"), shapes: geometry,
                      areas: { japanAreas($0.japanGroups) }, sharesRegionChips: true)
    }

    /// 日本の区分（地方）。束ね方は写真の札の列・地方のチップと同じ `SpotPrefectureIndex.groups`
    static func japanAreas(_ groups: [SpotPrefectureIndex.Group]) -> [SpotMapArea] {
        groups.map { group in
            SpotMapArea(id: group.region.name, title: group.title, count: group.count, names: group.names,
                        pieces: Set(group.region.prefectures),
                        coveredPieces: Set(group.cards.map(\.prefecture)),
                        scope: .region(group.region.name),
                        seeAll: L("\(group.region.name)の撮影スポットをすべて見る",
                                  "See all photo spots in \(PrefectureRegions.englishName(group.region))"))
        }
    }

    /// 出せる地図（今は日本だけ）。**地図を足すときはここに足す**
    static func available(japan geometry: PrefectureMapGeometry?) -> [SpotRegionMap] {
        [geometry.map(japan)].compactMap { $0 }
    }
}

/// 地図の形（塗る片・大きさ・当たり判定）。日本は `PrefectureMapGeometry`（片＝県）。
/// 世界の地図を足すときは、国の輪郭（`country-outlines.json`）から作る型がこれに従う
protocol SpotMapShapes {
    /// 単位の空間の大きさ
    var size: CGSize { get }
    /// 挿入図の枠（日本の沖縄）。無ければ nil
    var inset: CGRect? { get }
    /// 塗る片（名前と輪）
    var mapPieces: [(name: String, polygons: [[CGPoint]])] { get }
    /// 押した点（単位の空間）の片
    func piece(at unit: CGPoint, tolerance: CGFloat) -> String?
}

extension PrefectureMapGeometry: SpotMapShapes {
    var mapPieces: [(name: String, polygons: [[CGPoint]])] { pieces.map { ($0.prefecture, $0.polygons) } }
    func piece(at unit: CGPoint, tolerance: CGFloat) -> String? { prefecture(at: unit, tolerance: tolerance) }
}

/// 地図の区分（日本なら地方）と、その中の撮影スポットの束ね（型に依らない・右の札と「すべて見る」が読む）
struct SpotMapArea: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    /// 札の上位の名前（4 件まで）
    let names: [String]
    /// 塗る片（区分の全部の片）
    let pieces: Set<String>
    /// 撮影スポットのある片（無い片は地を沈める）
    let coveredPieces: Set<String>
    /// 「すべて見る」の行き先
    let scope: OfficialSpotIndexView.Scope
    /// 「すべて見る」の読み上げ（「北海道の撮影スポットをすべて見る」）
    let seeAll: String

    /// 札の名前の行（「阿寒湖・大雪山 旭岳・ファーム富田・五稜郭 ほか」）。全部出せたら「ほか」を付けない
    var namesLine: String {
        let joined = names.joined(separator: L("・", ", "))
        return count > names.count ? L("\(joined) ほか", "\(joined), and more") : joined
    }
}

/// 区分を作る材料（台帳と、日本の地方の束ね）。地図ごとに要るものだけ読む
struct SpotMapSource {
    let spots: [OfficialSpot]
    let japanGroups: [SpotPrefectureIndex.Group]
}
