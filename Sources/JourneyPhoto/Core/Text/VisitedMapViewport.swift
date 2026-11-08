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
