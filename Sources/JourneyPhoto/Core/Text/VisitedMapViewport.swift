import Foundation

/// 行った県マップの**拡大と移動**の計算（札 #503）。画面（ピンチ・ドラッグ）は結果を受け取るだけにして、
/// 数は Linux の `swift test` で確かめる。
///
/// 地図は「単位の空間」（幅 1000・`PrefectureMapGeometry`）の絵で、画面の枠（`container`）の真ん中に
/// 収まる大きさ（`fit`）で置く。画面の点 = 枠の中心 + (単位の点 − 絵の中心) × fit × zoom + pan
///
/// 2026-11-08 判断: 拡大は 1〜6 倍（3 倍でも埼玉・神奈川・滋賀・大阪などの小さな県は 44pt に届かない
/// ——提案書の計算——ので、押した点の近くの県を `PrefectureMapGeometry.prefecture(at:tolerance:)` で拾う）。
/// 絵が枠から出ないよう移動を止める。ピンチは指の下の点を動かさない
struct VisitedMapViewport: Equatable {

    nonisolated static let minZoom: CGFloat = 1
    nonisolated static let maxZoom: CGFloat = 6
    /// 拡大ボタン（＋−）の1回ぶんの倍率
    nonisolated static let step: CGFloat = 1.6
    /// 小さな県を押しやすくするために許す距離（画面の pt）。押した点からこの距離までの県を拾う
    nonisolated static let tapSlack: CGFloat = 16

    var zoom: CGFloat = 1
    /// 画面の点での移動
    var pan: CGSize = .zero

    static func fit(content: CGSize, container: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return 1 }
        return min(container.width / content.width, container.height / content.height)
    }

    func scale(content: CGSize, container: CGSize) -> CGFloat {
        Self.fit(content: content, container: container) * zoom
    }

    func screenPoint(forUnit u: CGPoint, content: CGSize, container: CGSize) -> CGPoint {
        let s = scale(content: content, container: container)
        return CGPoint(x: container.width / 2 + (u.x - content.width / 2) * s + pan.width,
                       y: container.height / 2 + (u.y - content.height / 2) * s + pan.height)
    }

    func unitPoint(forScreen p: CGPoint, content: CGSize, container: CGSize) -> CGPoint {
        let s = max(scale(content: content, container: container), 0.0001)
        return CGPoint(x: content.width / 2 + (p.x - container.width / 2 - pan.width) / s,
                       y: content.height / 2 + (p.y - container.height / 2 - pan.height) / s)
    }

    /// 押した点で許す距離を、単位の空間の長さにしたもの
    func tolerance(content: CGSize, container: CGSize) -> CGFloat {
        Self.tapSlack / max(scale(content: content, container: container), 0.0001)
    }

    /// 絵が枠から出ないよう、拡大の範囲と移動を収める
    func clamped(content: CGSize, container: CGSize) -> VisitedMapViewport {
        var v = self
        v.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
        let s = v.scale(content: content, container: container)
        let limitX = max(0, (content.width * s - container.width) / 2)
        let limitY = max(0, (content.height * s - container.height) / 2)
        v.pan = CGSize(width: min(max(pan.width, -limitX), limitX), height: min(max(pan.height, -limitY), limitY))
        return v
    }

    /// 倍率を変える。`focal`（画面の点）の下の絵の点を動かさない
    func zoomed(to newZoom: CGFloat, around focal: CGPoint, content: CGSize, container: CGSize) -> VisitedMapViewport {
        let target = min(max(newZoom, Self.minZoom), Self.maxZoom)
        guard zoom > 0 else { return clamped(content: content, container: container) }
        let ratio = target / zoom
        let cx = container.width / 2, cy = container.height / 2
        var v = self
        v.zoom = target
        v.pan = CGSize(width: (focal.x - cx) - (focal.x - cx - pan.width) * ratio,
                       height: (focal.y - cy) - (focal.y - cy - pan.height) * ratio)
        return v.clamped(content: content, container: container)
    }

    /// 指で動かす（動かし始めの値 `self` から `translation` だけ）
    func panned(by translation: CGSize, content: CGSize, container: CGSize) -> VisitedMapViewport {
        var v = self
        v.pan = CGSize(width: pan.width + translation.width, height: pan.height + translation.height)
        return v.clamped(content: content, container: container)
    }

    /// 拡大ボタン（＋）・縮小ボタン（−）。枠の真ん中を中心にする
    func stepped(_ direction: Int, content: CGSize, container: CGSize) -> VisitedMapViewport {
        let factor = direction >= 0 ? Self.step : 1 / Self.step
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        return zoomed(to: zoom * factor, around: center, content: content, container: container)
    }

    var canZoomIn: Bool { zoom < Self.maxZoom - 0.001 }
    var canZoomOut: Bool { zoom > Self.minZoom + 0.001 }
    var isZoomed: Bool { zoom > Self.minZoom + 0.001 }

    /// 県の名前を地図に出す倍率（これ以上拡大すると、県名と回数を県の上に出す）
    nonisolated static let namesFromZoom: CGFloat = 2.4
    /// 回数の数字だけを出す倍率（1 回以上の県）
    nonisolated static let countsFromZoom: CGFloat = 1.6
}

/// 地図の指の判定（札 #510・案 A）。画面（`VisitedMapCanvasView`）の指の状態から「足す・帯だけ・何もしない」を
/// 決める所だけを切り出し、Linux の `swift test` で縛る（押し間違い・長押しで足さないことを本物の動きの手前で守る）
enum VisitedMapTouch {

    enum Outcome: Equatable {
        /// 押した: 1 回足す
        case add
        /// 長押し（0.5 秒）: 足さずに帯だけ
        case peek
        /// 何もしない（動かした・ピンチした・長押しで帯を出し終えた）
        case none
    }

    /// 長押しの長さ（今までの判定のまま。モックは 0.45 秒・触覚の合図と同じ長さにそろえた）
    nonisolated static let longPressSeconds: Double = 0.5
    /// これより動いたら移動・スクロール（足さない）
    nonisolated static let moveTolerance: Double = 10

    /// 0.5 秒たったときに長押しを出すか。同じ指で、**まだ指が地図に乗っていて**（ScrollView に指を取られて
    /// 取り消されていない）、動かしてもピンチしてもいないときだけ
    /// （2026-11-10 レビュー: 地図の上から縦にスクロールした指で、0.5 秒後に帯と触覚が出ないように）
    static func firesLongPress(sameTouch: Bool, fingerDown: Bool, moved: Bool, pinched: Bool) -> Bool {
        sameTouch && fingerDown && !moved && !pinched
    }

    /// 長押しで帯を出した行（一覧）。離したときに来る押下を飲み込むのに使う。
    /// `releasedAt` は**その指が離れた・取り消された時刻**（行の Button の押している間が終わった時刻）
    struct LongPress: Equatable {
        let prefecture: String
        let at: Date
        var releasedAt: Date? = nil
    }

    /// 指が離れてから、この秒数のうちに来た押下だけを、その指の押下として飲み込む
    /// （Button の押下と「押している間」の終わりは同じ指の離れで、どちらが先に来るかは決まっていない）
    nonisolated static let releaseSwallowSeconds: Double = 0.5

    /// 指が離れた・取り消された（行の外へずらして離した・スクロールに取られた）。印の寿命をここで切る
    static func released(_ longPress: LongPress?, at now: Date) -> LongPress? {
        guard var longPress, longPress.releasedAt == nil else { return longPress }
        longPress.releasedAt = now
        return longPress
    }

    /// 一覧の行の押下を飲み込むか（長押しで帯を出したあと、同じ指を離したときの押下だけ）。
    /// 別の行・指が離れてから 0.5 秒より後の押下（次の本当の押下）は飲み込まない。
    /// 2026-11-10 再確認: 前は長押しから 10 秒の間ずっと飲み込み、押下が来ないまま離れた指の印が残ると、
    /// 次の本当の押下を黙って飲み込んでいた（押した数だけ数える決まりに反する）
    static func swallowsTap(on prefecture: String, after longPress: LongPress?, now: Date) -> Bool {
        guard let longPress, longPress.prefecture == prefecture, now >= longPress.at else { return false }
        // 指がまだ乗っている間に来た押下は、その指の押下
        guard let releasedAt = longPress.releasedAt else { return true }
        let elapsed = now.timeIntervalSince(releasedAt)
        return elapsed >= 0 && elapsed < releaseSwallowSeconds
    }

    /// 指を離したとき
    /// - heldSeconds: 指を置いていた長さ。押し始めが分からない（指の途中状態が片付いたあと）なら nil で、
    ///   何もしない（2026-11-10 再確認: 前は nil を短い押下と見て 1 回足していた）
    static func onRelease(moved: Bool, pinched: Bool, longPressFired: Bool, heldSeconds: Double?) -> Outcome {
        guard !moved, !pinched, !longPressFired, let heldSeconds else { return .none }
        return heldSeconds >= longPressSeconds ? .peek : .add
    }
}
