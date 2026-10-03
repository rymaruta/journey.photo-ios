import Foundation

/// 写真を大きく見る画面（`PhotoViewerView`）の**拡大と移動の計算**。画面を持たない層に置いて
/// Linux の `swift test` で確かめる。
///
/// 2026-09-30 のレビュー:
///  - ピンチを離すと倍率が 1 に戻っていた（`.onEnded { scale = 1 }`）——細部を見ていられない
///  - 拡大したまま写真を動かす手段が無かった
///
/// ## 決まりごと
///
///  - 倍率は **1〜4 倍**。離しても保つ。**1.05 倍未満まで戻したら 1 倍**に揃え、位置も中央へ
///    （わずかに拡大したままだと、横に送れない・移動の対象になる、の中途半端な状態が残る）
///  - 動かせるのは**写真がはみ出している分だけ**。写真の端が画面の内側へ入り込まない
///    （横長の写真を縦の画面で見ると、上下は拡大しても黒地に収まっている間は動かない）
///  - 写真の大きさ（`content`）は**画面に収めたときの大きさ**（`.fit`）。分からなければ画面の大きさで代える
///  - 別の写真へ送ったら元に戻す（`reset`）——拡大したまま次の写真が出ない
struct ZoomPan: Equatable {
    static let minScale: Double = 1
    static let maxScale: Double = 4
    /// これ未満まで戻したら 1 倍に揃える
    static let snapBackBelow: Double = 1.05

    private(set) var scale: Double = 1
    private(set) var offset: CGSize = .zero

    /// 拡大しているか（横送りを止め、移動を受け付ける）
    var isZoomed: Bool { scale > 1 }

    /// 送り（ページ式の TabView）を止めるか。🔴 **つまんでいる最中（`pinch != 1`）も止める**
    /// （バグ探し 2026-10-03）。等倍からつまみ始めた間は `isZoomed` がまだ偽なので送りが生きていて、
    /// 2本指の重心が横へ流れると隣の写真へ送られ、離したときの倍率が隣の写真に掛かっていた
    func locksPaging(pinch: Double) -> Bool {
        isZoomed || pinch != 1
    }

    /// つまみ終えた倍率を畳むか。**つまみ始めたページと今のページが同じときだけ。**
    /// サムネイルで跳んだ等でページが替わっていたら、替わった先は等倍から始める
    /// （`reset` 済み）——前の写真でつまんだ倍率を次の写真に掛けない
    static func appliesPinchEnd(startedOn: Int, current: Int) -> Bool {
        startedOn == current
    }

    static func clampScale(_ s: Double) -> Double {
        guard s.isFinite else { return minScale }
        return min(max(s, minScale), maxScale)
    }

    /// 指でつまんでいる間の倍率（今の倍率 × つまんだ量）
    func liveScale(pinch: Double) -> Double { Self.clampScale(scale * pinch) }

    /// その倍率で動かせる範囲に収めた位置
    static func clampOffset(_ o: CGSize, scale: Double, container: CGSize, content: CGSize) -> CGSize {
        let c = content.width > 0 && content.height > 0 ? content : container
        let maxX = max(0, (c.width * scale - container.width) / 2)
        let maxY = max(0, (c.height * scale - container.height) / 2)
        func clamp(_ v: CGFloat, _ m: Double) -> CGFloat { v.isFinite ? CGFloat(min(max(Double(v), -m), m)) : 0 }
        return CGSize(width: clamp(o.width, maxX), height: clamp(o.height, maxY))
    }

    /// 指で動かしている間の位置（今の位置 ＋ 動かした量・範囲に収める）。
    /// `scale` はつまんでいる最中の倍率（省けば今の倍率）
    func liveOffset(drag: CGSize, scale live: Double? = nil, container: CGSize, content: CGSize) -> CGSize {
        Self.clampOffset(CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                         scale: live ?? scale, container: container, content: content)
    }

    /// つまみ終えた。倍率を保ち（1〜4 倍）、位置をその倍率の範囲へ収め直す
    mutating func endPinch(_ pinch: Double, container: CGSize, content: CGSize) {
        let next = Self.clampScale(scale * pinch)
        if next < Self.snapBackBelow {
            reset()
            return
        }
        scale = next
        offset = Self.clampOffset(offset, scale: scale, container: container, content: content)
    }

    /// 動かし終えた（拡大しているときだけ）。`scale` は**まだつまんでいる最中ならその倍率**
    /// ——2本指を離すと、移動とつまむの `onEnded` はどちらが先に来るか決まっていない。移動が先に
    /// 来たとき、つまむ前の狭い範囲で詰めると、見えていた位置より内側へ跳ねる
    mutating func endDrag(_ drag: CGSize, scale live: Double? = nil, container: CGSize, content: CGSize) {
        guard isZoomed || (live ?? 1) > 1 else { return }
        offset = liveOffset(drag: drag, scale: live, container: container, content: content)
    }

    /// 等倍・中央へ
    mutating func reset() {
        scale = 1
        offset = .zero
    }
}
