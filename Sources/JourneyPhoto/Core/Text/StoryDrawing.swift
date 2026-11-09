import Foundation

/// ストーリーの描画（ペン・蛍光ペン・消しゴム・2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
///
/// **自前の線のデータで持つ**（PencilKit にしない・2026-11-09 判断）。理由:
///  1. 線のデータが**純粋な値**なので、取り消し／やり直し・下書きへの保存・上限・壊れた値の読みを
///     Linux の `swift test` で縛れる（PencilKit は UIKit だけで、Linux では型検査もできない）
///  2. 位置を**写真に対する割合**で持つ（文字の札 `TextOverlay` と同じ）。画面の大きさ・書き出しの大きさ・
///     動画の縮小のどれでも同じ所に出る。太さも写真の短い辺に対する割合（`TextOverlay.fontSize` と同じ）
///  3. 画面の描き（SwiftUI の `Canvas`）と焼き込み（Core Graphics）が**同じ経路の命令**（`StoryDrawingGeometry.ops`）
///     から描くので、見たものがそのまま焼ける
///
/// 並びは「写真 → 線 → 文字・札」の順に描く（文字・札は線の上）。
/// **線は写真の合わせ方（拡大・回し）に付いてこない**（文字の札と同じ・`TextOverlayRenderer.burn`）。

/// 筆。ペン・蛍光ペン（半透明の太い線）・消しゴム（描いた線を消す）
enum StoryPenTool: String, Codable, CaseIterable, Identifiable {
    case pen, highlighter, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: return L("ペン", "Pen")
        case .highlighter: return L("蛍光ペン", "Highlighter")
        case .eraser: return L("消しゴム", "Eraser")
        }
    }

    /// SF Symbols の名前
    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    /// 線の太さ（**写真の短い辺に対する割合**）の幅と既定
    var widthRange: ClosedRange<Double> {
        switch self {
        case .pen: return 0.004...0.040
        case .highlighter: return 0.020...0.080
        case .eraser: return 0.015...0.100
        }
    }

    var defaultWidth: Double {
        switch self {
        case .pen: return 0.010
        case .highlighter: return 0.040
        case .eraser: return 0.040
        }
    }

    /// 色の不透明度。蛍光ペンだけ半透明（1本の線の中で重なっても濃くならない・1本ずつ1色で塗る）
    var opacity: Double { self == .highlighter ? 0.45 : 1 }
}

/// 線の1点。**写真に対する割合**（左上が (0, 0)・右下が (1, 1)）。下書きには `[x, y]` の2つ組で書く（小さく保つ）
struct StoryStrokePoint: Equatable, Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }

    /// 割合の外へ出た点・壊れた値を収める（写真の外へ半分までは許す）
    var clamped: StoryStrokePoint? {
        guard x.isFinite, y.isFinite else { return nil }
        return StoryStrokePoint(x: min(max(x, -0.5), 1.5), y: min(max(y, -0.5), 1.5))
    }
}

/// 1本の線（指を置いてから離すまで）
struct StoryStroke: Equatable, Codable, Identifiable {
    let id: UUID
    var tool: StoryPenTool
    /// 色（0xRRGGBB）。消しゴムでは使わない
    var hex: UInt32
    /// 太さ（写真の短い辺に対する割合）
    var width: Double
    var points: [StoryStrokePoint]

    init(id: UUID = UUID(), tool: StoryPenTool, hex: UInt32, width: Double, points: [StoryStrokePoint]) {
        self.id = id
        self.tool = tool
        self.hex = hex & 0xFFFFFF
        self.width = Self.clampedWidth(width, tool: tool)
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case id, tool, hex, width, points }

    /// **投げない**（古い下書き・壊れた値）。知らない筆はペン・色が無ければ白・太さは幅に収め、
    /// 壊れた点は外す。点が1つも無い線は呼ぶ側（`StoryDrawing`）が捨てる
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tool = ((try? c.decodeIfPresent(String.self, forKey: .tool)) ?? nil).flatMap(StoryPenTool.init(rawValue:)) ?? .pen
        self.id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        self.tool = tool
        self.hex = (((try? c.decodeIfPresent(UInt32.self, forKey: .hex)) ?? nil) ?? 0xFFFFFF) & 0xFFFFFF
        self.width = Self.clampedWidth(((try? c.decodeIfPresent(Double.self, forKey: .width)) ?? nil) ?? tool.defaultWidth,
                                       tool: tool)
        let raw = ((try? c.decodeIfPresent([StoryStrokePoint].self, forKey: .points)) ?? nil) ?? []
        self.points = raw.compactMap { $0.clamped }
    }

    static func clampedWidth(_ value: Double, tool: StoryPenTool) -> Double {
        guard value.isFinite else { return tool.defaultWidth }
        return min(max(value, tool.widthRange.lowerBound), tool.widthRange.upperBound)
    }

    /// 点を1つだけ打った線（丸い点で描く）
    var isDot: Bool { points.count == 1 }
}

/// 写真1枚ぶんの描画。**写真ごと**に持つ（文字・フィルターと同じ）。下書きに残す形でもある（`Codable`）
struct StoryDrawing: Codable {

    /// 上限（下書きの大きさ・描き直しの重さを抑える）。1本の長さ・本数・全部の点の数
    static let maxStrokes = 200
    static let maxPointsPerStroke = 1500
    static let maxTotalPoints = 6_000
    /// **並び全体**（下書きの1件＝全部の写真）の上限。下書きは `UserDefaults` に JSON で入るので、重くしない。
    /// 最大サイズの見積もり: 1点 `[0.1234,0.5678],` ≒ 16B × 6000 点 ≒ 96KB、1本の枠（id・筆・色・太さ）≒ 110B × 300 本 ≒ 33KB
    /// ＝ **最大でおよそ 130KB**（上限を決める前は 1枚 20000 点 × 10 枚 ≒ 3.2MB になり得た）
    static let maxSequencePoints = 6_000
    static let maxSequenceStrokes = 300

    static let empty = StoryDrawing()

    /// 描いた線（古い → 新しい）。消しゴムの線も入る（あとから描く順に効く）
    private(set) var strokes: [StoryStroke] = []
    /// 取り消した線（やり直し用）。**下書きには残さない**・新しい線を描いたら空にする
    private(set) var undone: [StoryStroke] = []

    init() {}

    /// 線が無い
    var isEmpty: Bool { strokes.isEmpty }

    /// 目に見える線がある（消しゴムだけ・全部消した後は、焼き込み・書き出しで何も描かなくてよい）
    var hasInk: Bool { strokes.contains { $0.tool != .eraser && !$0.points.isEmpty } }

    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    /// 点の総数
    var totalPoints: Int { strokes.reduce(0) { $0 + $1.points.count } }

    /// この1本を足してよいか（本数・点の数の上限）
    func canAdd(_ stroke: StoryStroke) -> Bool {
        !stroke.points.isEmpty
            && stroke.points.count <= Self.maxPointsPerStroke
            && strokes.count < Self.maxStrokes
            && totalPoints + stroke.points.count <= Self.maxTotalPoints
    }

    /// 描いている線にあと何点足せるか（描き始めの手前で上限を知らせるのに使う）
    /// `others` は並びのほかの写真が持つ本数・点の数（並び全体の上限に数える）
    func remainingPoints(forStrokeWith count: Int, others: (strokes: Int, points: Int) = (0, 0)) -> Int {
        max(0, min(Self.maxPointsPerStroke - count, Self.maxTotalPoints - totalPoints - count,
                   Self.maxSequencePoints - others.points - totalPoints - count))
    }

    /// 新しい1本を始めてよいか（この写真の本数と、並び全体の本数）
    func canStartStroke(others: (strokes: Int, points: Int) = (0, 0)) -> Bool {
        strokes.count < Self.maxStrokes && strokes.count + others.strokes < Self.maxSequenceStrokes
    }

    /// 線を足す。**上限を超えるなら足さず false**。足したら「やり直し」の分は消える
    @discardableResult
    mutating func add(_ stroke: StoryStroke) -> Bool {
        guard canAdd(stroke) else { return false }
        strokes.append(stroke)
        undone.removeAll()
        return true
    }

    /// 取り消す（最後の1本を戻す）
    mutating func undo() {
        guard let last = strokes.popLast() else { return }
        undone.append(last)
    }

    /// やり直す（取り消した最後の1本を戻す）
    mutating func redo() {
        guard let next = undone.popLast() else { return }
        strokes.append(next)
    }

    /// 全部消す
    mutating func clear() {
        strokes.removeAll()
        undone.removeAll()
    }

    // MARK: - 読み書き（下書き）

    private enum CodingKeys: String, CodingKey { case strokes }

    /// **取り消した分は書かない**。幅に収めて書く
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strokes, forKey: .strokes)
    }

    /// **投げない**。壊れた線は1本ずつ外し、点の無い線は捨て、上限を超えたぶんは読まない
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let boxes = try? c.decodeIfPresent([LossyStroke].self, forKey: .strokes) else { return }
        var total = 0
        for stroke in boxes.compactMap({ $0.value }) where !stroke.points.isEmpty {
            guard strokes.count < Self.maxStrokes,
                  stroke.points.count <= Self.maxPointsPerStroke,
                  total + stroke.points.count <= Self.maxTotalPoints else { continue }
            strokes.append(stroke)
            total += stroke.points.count
        }
    }

    /// 壊れた1本で全部を読めなくしないための包み
    private struct LossyStroke: Decodable {
        let value: StoryStroke?
        init(from decoder: Decoder) throws {
            value = try? StoryStroke(from: decoder)
        }
    }
}

extension StoryDrawing: Equatable {
    /// **線だけを比べる**（やり直しの控えは「変更あり」に数えない）
    static func == (lhs: StoryDrawing, rhs: StoryDrawing) -> Bool { lhs.strokes == rhs.strokes }
}

/// いま選んでいる筆（色・筆ごとの太さ）。**画面の間だけ**持つ（端末には残さない）
struct StoryPen: Equatable {

    /// 色の見本（12色・白が先頭）。名前は読み上げと一覧の見出し用
    struct Swatch: Equatable, Identifiable {
        let hex: UInt32
        let nameJa: String
        let nameEn: String
        var id: UInt32 { hex }
        var name: String { L(nameJa, nameEn) }
    }

    static let palette: [Swatch] = [
        Swatch(hex: 0xFFFFFF, nameJa: "白", nameEn: "White"),
        Swatch(hex: 0x07090A, nameJa: "黒", nameEn: "Black"),
        Swatch(hex: 0xFF5A5F, nameJa: "赤", nameEn: "Red"),
        Swatch(hex: 0xFF9F43, nameJa: "オレンジ", nameEn: "Orange"),
        Swatch(hex: 0xFFD93D, nameJa: "黄", nameEn: "Yellow"),
        Swatch(hex: 0x9BE564, nameJa: "黄緑", nameEn: "Lime"),
        Swatch(hex: 0x2ED47A, nameJa: "緑", nameEn: "Green"),
        Swatch(hex: 0x4FD1C5, nameJa: "青緑", nameEn: "Teal"),
        Swatch(hex: 0x4DA3FF, nameJa: "青", nameEn: "Blue"),
        Swatch(hex: 0x7C6CFF, nameJa: "紫", nameEn: "Purple"),
        Swatch(hex: 0xFF6FB5, nameJa: "ピンク", nameEn: "Pink"),
        Swatch(hex: 0xC9A66B, nameJa: "真鍮", nameEn: "Brass"),
    ]

    var tool: StoryPenTool = .pen
    var colorHex: UInt32 = StoryPen.palette[0].hex
    /// 筆ごとの太さ（筆を替えても、それぞれの太さを覚えている）
    private var widths: [StoryPenTool: Double] = [:]

    /// いまの筆の太さ（写真の短い辺に対する割合）
    var width: Double { widths[tool] ?? tool.defaultWidth }

    /// いまの筆の太さを決める（筆の幅に収める）
    mutating func setWidth(_ value: Double) {
        widths[tool] = StoryStroke.clampedWidth(value, tool: tool)
    }

    /// つまみの位置（0…1）と太さの割合の変換。つまみは筆の幅いっぱいに動く
    var widthFraction: Double {
        let range = tool.widthRange
        return (width - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    mutating func setWidth(fraction: Double) {
        guard fraction.isFinite else { return }
        let range = tool.widthRange
        setWidth(range.lowerBound + min(max(fraction, 0), 1) * (range.upperBound - range.lowerBound))
    }

    /// 指を置いて始める1本（点はまだ1つ）
    func beginStroke(at point: StoryStrokePoint) -> StoryStroke {
        StoryStroke(tool: tool, hex: colorHex, width: width, points: [point])
    }
}

/// 線を描く命令と座標の変換（**画面の `Canvas` と焼き込みの Core Graphics が同じものから描く**）
enum StoryDrawingGeometry {

    /// 経路の命令
    enum Op: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(to: CGPoint, control: CGPoint)
    }

    /// 点の並び（描く先の座標）から、なめらかな経路の命令を作る。
    /// 1点だけなら空（呼ぶ側が丸い点を打つ）。2点は直線。3点以上は、各点を制御点・隣との中点を終点とする
    /// 二次の曲線でつなぎ、最後の点へ直線で終える
    static func ops(for points: [CGPoint]) -> [Op] {
        guard points.count >= 2 else { return [] }
        var result: [Op] = [.move(points[0])]
        if points.count == 2 {
            result.append(.line(points[1]))
            return result
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let next = points[index + 1]
            result.append(.quad(to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2),
                                control: control))
        }
        result.append(.line(points[points.count - 1]))
        return result
    }

    /// 写真に対する割合 → 描く先の座標（`rect` は写真が占める場所）
    static func point(_ p: StoryStrokePoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
    }

    /// 描く先の座標 → 写真に対する割合（小数4桁に丸める＝下書きを小さく・1万分の1は 0.04pt 未満）。
    /// 写真の大きさが 0 なら nil
    static func normalized(_ p: CGPoint, in rect: CGRect) -> StoryStrokePoint? {
        guard rect.width > 0, rect.height > 0, p.x.isFinite, p.y.isFinite else { return nil }
        func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        return StoryStrokePoint(x: round4(Double((p.x - rect.minX) / rect.width)),
                                y: round4(Double((p.y - rect.minY) / rect.height)))
    }

    /// 線の太さ（描く先の長さ）。写真の短い辺に対する割合（文字の大きさ `TextOverlay.fontSize` と同じ決め方）
    static func lineWidth(_ width: Double, in size: CGSize) -> CGFloat {
        CGFloat(width) * min(size.width, size.height)
    }

    /// 指の動きから点を足すか。**前の点から 1.5pt 以上動いたときだけ**（点が増えすぎない・線が震えない）
    static func shouldAppend(last: CGPoint, new: CGPoint, minimumDistance: CGFloat = 1.5) -> Bool {
        let dx = new.x - last.x, dy = new.y - last.y
        return (dx * dx + dy * dy).squareRoot() >= minimumDistance
    }
}

/// 指の動き1つぶんをどう扱うか（描く面 `StoryDrawingSurface` の判断を画面から出したもの・Linux のテストで縛る）
enum StoryStrokeInput {

    enum Step: Equatable {
        /// 新しい1本を始める（最初の点）
        case begin(StoryStrokePoint)
        /// いまの1本に点を足す
        case append(StoryStrokePoint)
        /// 何もしない（ほとんど動いていない・写真の大きさが 0）
        case ignore
        /// 上限に来た（本数・1本の長さ・全部の点の数）。呼ぶ側は一度だけ知らせる
        case limit
    }

    /// - Parameters:
    ///   - live: いま描いている1本（無ければ新しく始める）
    ///   - last: 前の点（描く先の座標）。`live` があるときだけ見る
    ///   - location: 指の位置（描く先の座標）
    ///   - photo: 写真が占める場所
    ///   - drawing: すでに持っている線（上限の判断）
    static func step(live: StoryStroke?, last: CGPoint?, location: CGPoint, photo: CGRect,
                     drawing: StoryDrawing, others: (strokes: Int, points: Int) = (0, 0)) -> Step {
        guard let point = StoryDrawingGeometry.normalized(location, in: photo) else { return .ignore }
        guard let live else {
            guard drawing.canStartStroke(others: others),
                  drawing.remainingPoints(forStrokeWith: 1, others: others) > 0 else { return .limit }
            return .begin(point)
        }
        guard let last, StoryDrawingGeometry.shouldAppend(last: last, new: location) else { return .ignore }
        guard drawing.remainingPoints(forStrokeWith: live.points.count, others: others) > 0 else { return .limit }
        return .append(point)
    }
}
