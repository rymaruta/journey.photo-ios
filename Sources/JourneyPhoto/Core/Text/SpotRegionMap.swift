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
    /// 片の外を押したとき、区分へ寄せる強さ（画面の pt・区分の id → 足す近さ）。**小さな区分ほど大きくする**——
    /// 境までの距離だけで分けると、周りを囲まれた小さな区分（四国・近畿）が 44×44 に届かない
    var hitBonus: [String: CGFloat] = [:]
    /// 地図の上に置く区分の名前の札（`SpotMapLabel`）。無ければ札を置かない
    var labels: [SpotMapLabel] = []

    /// 地図の上の点（画面の pt・地図の枠の左上が原点）の区分の id。**撮影スポットのある区分だけ**。
    ///
    /// 2026-11-11（確かめ役の指摘・陣地分け）: 段の中の地図は小さく、線の内側だけでは四国（648pt²）・近畿（882）・
    /// 中国（1135）・中部（1551）の当たりが 44×44（1936pt²）に届かなかった。そこで
    ///   1. 片の**内側**を押したら、その片の区分（撮影スポットの無い区分の片なら何もしない）
    ///   2. どの片の内側でもない点（海・境の隙間）は、**いちばん近い区分**に寄せる（地図の枠の中だけ）
    /// とし、地図の枠ぜんたいを区分で分け合う。押せる広さは `SpotRegionMapTests` が 1pt ごとに数えて縛る
    func area(at point: CGPoint, container: CGSize, in areas: [SpotMapArea]) -> String? {
        guard CGRect(origin: .zero, size: container).contains(point) else { return nil }
        // 名前の札の上は、その札の区分（2026-11-12 判断: 札が隣の地方の陸に掛かっていても、見えている札の地方を選ぶ）
        if let label = labelFrames(container: container, in: areas).first(where: { $0.frame.contains(point) }) {
            return label.label.area
        }
        let unit = VisitedMapViewport().unitPoint(forScreen: point, content: shapes.size, container: container)
        if let inside = shapes.piece(at: unit, tolerance: 0) {
            return areas.first { $0.pieces.contains(inside) }?.id
        }
        // 片の外: 区分までの距離（画面の pt）
        let scale = VisitedMapViewport().scale(content: shapes.size, container: container)
        let distances = areas.map { (id: $0.id, raw: shapes.distance(from: unit, toPieces: $0.pieces) * scale) }
        guard let nearest = distances.min(by: { $0.raw < $1.raw }) else { return nil }
        // 🔴 **海岸のすぐ外（`coastSlack` 以内）は、いちばん近い区分が必ず勝つ**（2026-11-11 確かめ役の指摘: 寄せだけで
        // 分けると、九州の海岸のすぐ外（長崎の西・鹿児島の南・宮崎の東）が四国になった）。寄せはそれより遠い点だけ
        if nearest.raw <= Self.coastSlack { return nearest.id }
        return distances.min { a, b in
            a.raw - (hitBonus[a.id] ?? 0) < b.raw - (hitBonus[b.id] ?? 0)
        }?.id
    }

    /// 海岸から何 pt までは、いちばん近い区分が必ず勝つか（寄せを使わない）
    nonisolated static let coastSlack: CGFloat = 8

    /// 名前の札の枠（画面の pt・地図の枠の左上が原点）。**撮影スポットのある区分の札だけ**。札は地図の枠の中に収める
    func labelFrames(container: CGSize, in areas: [SpotMapArea]) -> [SpotMapLabelFrame] {
        let present = Set(areas.map(\.id))
        let viewport = VisitedMapViewport()
        return labels.filter { present.contains($0.area) }.map { label in
            let center = viewport.screenPoint(forUnit: label.center, content: shapes.size, container: container)
            let size = CGSize(width: Self.labelWidth(label.text), height: Self.labelHeight)
            let x = min(max(center.x - size.width / 2, 0), max(container.width - size.width, 0))
            let y = min(max(center.y - size.height / 2, 0), max(container.height - size.height, 0))
            return SpotMapLabelFrame(label: label, frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
        }
    }

    /// 名前の札の高さ（見た目）。当たりは札の上と、その区分の陣地（`area(at:)`・どの地方も 44×44 以上）
    nonisolated static let labelHeight: CGFloat = 22
    /// 名前の札の字の大きさ（地図の絵の一部なので文字サイズの設定に追従させない・札の幅をこの大きさで決めるため）
    nonisolated static let labelFontSize: CGFloat = 12
    /// 名前の札の左右の余白と「›」の分（左 7・字と › の間 2・› 6・右 5）
    nonisolated static let labelChrome: CGFloat = 20

    /// 名前の札の幅。字の幅を見積もる（漢字・かなは字の大きさ、英数字はその 0.62 倍）＋余白。最小 44
    static func labelWidth(_ text: String) -> CGFloat {
        let glyphs = text.reduce(CGFloat(0)) { sum, ch in
            sum + (ch.isASCII ? labelFontSize * 0.62 : labelFontSize)
        }
        return max(44, (glyphs + labelChrome).rounded(.up))
    }

    /// 区分を順に替える（読み上げの上下の払い・`accessibilityAdjustableAction`）。端で止まる
    static func step(_ current: String?, in areas: [SpotMapArea], forward: Bool) -> String? {
        guard !areas.isEmpty else { return nil }
        guard let current, let index = areas.firstIndex(where: { $0.id == current }) else { return areas.first?.id }
        let next = forward ? min(index + 1, areas.count - 1) : max(index - 1, 0)
        return areas[next].id
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
                      areas: { japanAreas($0.japanGroups) }, sharesRegionChips: true, hitBonus: japanHitBonus,
                      labels: japanLabels)
    }

    /// 日本の地方の名前の札（2026-11-12 owner「なんも押してないのに県を選ぶというのわかりづらいな。ガイドもないし」。
    /// Web の #625 と同じ考え: 地方の名前を**押せる札**にして、地図が押せることを見て分かるようにする）。
    ///
    /// 2026-11-12 判断:
    /// - 置き場は段の地図（幅 189・高さ 212）で、札（高さ 22）どうしが重ならず、地方の上かすぐ隣の海に来る点。
    ///   単位の空間の点で持つ（地図の大きさが変わっても同じ所に来る）。重ならないことは `SpotRegionMapTests` が縛る
    /// - 九州・沖縄は「九州」と「沖縄」（左上の挿入図）の2枚。どちらも九州・沖縄を選ぶ（Web も沖縄県に別の札がある）
    /// - 中部と関東、中国と四国は近いので、関東は太平洋側、中国は日本海側へずらした
    static var japanLabels: [SpotMapLabel] { [
        SpotMapLabel(area: "北海道", text: L("北海道", "Hokkaido"), center: CGPoint(x: 805, y: 175)),
        SpotMapLabel(area: "東北", text: L("東北", "Tohoku"), center: CGPoint(x: 794, y: 483)),
        SpotMapLabel(area: "関東", text: L("関東", "Kanto"), center: CGPoint(x: 847, y: 737)),
        SpotMapLabel(area: "中部", text: L("中部", "Chubu"), center: CGPoint(x: 534, y: 663)),
        SpotMapLabel(area: "近畿", text: L("近畿", "Kinki"), center: CGPoint(x: 412, y: 801)),
        SpotMapLabel(area: "中国", text: L("中国", "Chugoku"), center: CGPoint(x: 200, y: 642)),
        SpotMapLabel(area: "四国", text: L("四国", "Shikoku"), center: CGPoint(x: 328, y: 939)),
        SpotMapLabel(area: "九州・沖縄", text: L("九州", "Kyushu"), center: CGPoint(x: 115, y: 1066)),
        SpotMapLabel(area: "九州・沖縄", text: L("沖縄", "Okinawa"), center: CGPoint(x: 158, y: 101)),
    ] }

    /// 日本の地方の寄せ（画面の pt）。段の中の地図（決めたときは幅 143・高さ 160。2026-11-12 に地図を段の高さ 212 へ
    /// 広げた後もこの値のまま。広くなったので、どの地方の押せる広さも増える）で、どの地方も 44×44（1936pt²）以上
    /// 押せるように決めた値（2026-11-11: 1pt ごとに押した広さを数え、いちばん狭い地方（沖縄の挿入図を除いた九州本土も含む）が
    /// 広くなる値を探した。海岸から `coastSlack`（8pt）より遠い点だけに効く。いちばん狭いのは 2150pt²。
    /// `SpotRegionMapTests.testEveryRegionIsAtLeast44x44` が縛り、前後の広さはログに出す）
    nonisolated static let japanHitBonus: [String: CGFloat] = [
        "東北": 3, "関東": 3, "中部": 16, "近畿": 34, "中国": 31, "四国": 44, "九州・沖縄": 9,
    ]

    /// 日本の区分（地方）。束ね方は写真の札の列・地方のチップと同じ `SpotPrefectureIndex.groups`
    static func japanAreas(_ groups: [SpotPrefectureIndex.Group]) -> [SpotMapArea] {
        groups.map { group in
            SpotMapArea(id: group.region.name, title: group.title, count: group.count, names: group.names,
                        pieces: Set(group.region.prefectures),
                        coveredPieces: Set(group.cards.map(\.prefecture)),
                        scope: .region(group.region.name),
                        seeAll: L("\(group.region.name)の観光スポットをすべて見る",
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
    /// `names` の片までの距離（単位の空間・内側なら 0）。陣地分け（`SpotRegionMap.area(at:)`）に使う
    func distance(from unit: CGPoint, toPieces names: Set<String>) -> CGFloat
}

extension PrefectureMapGeometry: SpotMapShapes {
    var mapPieces: [(name: String, polygons: [[CGPoint]])] { pieces.map { ($0.prefecture, $0.polygons) } }
    func piece(at unit: CGPoint, tolerance: CGFloat) -> String? { prefecture(at: unit, tolerance: tolerance) }

    /// 沖縄の挿入図の枠の中は、沖縄県の片まで 0。ほかは片の箱までの距離で順に見て、近い順に本当の距離を測る（箱が遠ければ打ち切る）
    func distance(from unit: CGPoint, toPieces names: Set<String>) -> CGFloat {
        if let inset, inset.contains(unit), names.contains(Self.insetPrefecture), piece(Self.insetPrefecture) != nil {
            return 0
        }
        func boxDistance(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - unit.x, 0, unit.x - r.maxX), dy = max(r.minY - unit.y, 0, unit.y - r.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        let candidates = pieces.filter { names.contains($0.prefecture) }
            .map { (piece: $0, lower: boxDistance($0.bounds)) }
            .sorted { $0.lower < $1.lower }
        var best = CGFloat.infinity
        for candidate in candidates {
            if candidate.lower >= best { break }
            best = min(best, distance(from: unit, to: candidate.piece))
        }
        return best
    }

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
    let scope: SpotIndexScope
    /// 「すべて見る」の読み上げ（「北海道の撮影スポットをすべて見る」）
    let seeAll: String

    /// 札の「すべて見る」の字（「北海道をすべて見る」）。見出しの全国の「すべて見る」と分ける（確かめ役の指摘・2026-11-11）
    var seeAllLabel: String { L("\(title)をすべて見る", "See all in \(title)") }

    /// 札の名前の行（「阿寒湖・大雪山 旭岳・ファーム富田・五稜郭 ほか」）。全部出せたら「ほか」を付けない
    var namesLine: String {
        let joined = names.joined(separator: L("、", ", "))
        return count > names.count ? L("\(joined) ほか", "\(joined), and more") : joined
    }
}

/// 地図の上の区分の名前の札（「近畿 ›」・2026-11-12）。押すとその区分を選ぶ（地図を押したのと同じ）。
/// 見た目は Web の地方名の札（黒の地・真鍮の細い縁・白い名前・真鍮の「›」）
struct SpotMapLabel: Equatable, Identifiable {
    /// 区分の id（押したら選ぶ区分）
    let area: String
    /// 札の字（区分の名前。九州・沖縄は「九州」「沖縄」の2枚）
    let text: String
    /// 札の真ん中（単位の空間）
    let center: CGPoint

    var id: String { text }
}

/// 名前の札と、地図の枠の中の置き場（画面の pt）
struct SpotMapLabelFrame: Identifiable {
    let label: SpotMapLabel
    let frame: CGRect

    var id: String { label.id }
}

/// 区分を作る材料（台帳と、日本の地方の束ね）。地図ごとに要るものだけ読む
struct SpotMapSource {
    let spots: [OfficialSpot]
    let japanGroups: [SpotPrefectureIndex.Group]
}
