import Foundation

/// 部屋の初めの向きを、画面の絵の縦横に合わせる（2026-10-22 owner の実機 1.1.37: 部屋の絵が上へ押し出されて切れ、
/// 下に大きな黒い空きがあった）。
///
/// `overview(_:)` は部屋の真ん中（高さ 18）を画面の真ん中に置き、部屋の対角から距離を決めるだけだった。
/// 奥の壁は天井まであるのに手前の壁は高さ 9 で切るので、見える部屋は上へ寄り（上 5%・下 16% の空き）、
/// 縦長の絵では横がはみ出し、張り出し・トレーラーの部屋は奥の壁の天端が上へ切れた。
/// ここでは見える部屋の 8 つの角（奥と横の壁は天井まで・手前の切った壁は切った高さ）を画面へ映し、
/// その外接の四角が絵の真ん中に来て、縁に `margin` を残して収まるよう、狙う点と倍率を数回詰める
extension CamperRoomCamera {
    /// 絵の縁に残す割合（上下左右）
    static let fitMargin = 0.06

    /// 画面の絵（`viewport`）に合わせた初めの向き。絵の大きさが無い時は `overview(_:)` のまま
    static func overview(_ layout: CamperRoomLayout, viewport: CGSize) -> CamperRoomCamera {
        var c = overview(layout)
        let w = Double(viewport.width), h = Double(viewport.height)
        guard w > 40, h > 40 else { return c }
        let forward = c.orientation.rotate(CV3(0, 0, -1)).normalized
        for _ in 0..<6 {
            guard let box = c.shellBox(layout, viewport: viewport) else { break }
            // 外接の四角の真ん中を絵の真ん中へ（狙う点を、視線に直交する面の上で動かす）
            let center = CGPoint(x: (box.minX + box.maxX) / 2, y: (box.minY + box.maxY) / 2)
            let ray = c.ray(center, viewport: viewport, layout: layout)
            let denom = ray.direction.dot(forward)
            if abs(denom) > 1e-6 {
                let t = (c.target - ray.origin).dot(forward) / denom
                c.target = ray.origin + ray.direction * t
            }
            // 縁に margin を残して収まる倍率（遠近があるので数回詰める）
            let room = 1 - 2 * fitMargin
            let scale = max(Double(box.width) / (w * room), Double(box.height) / (h * room))
            guard scale > 0 else { break }
            c.zoom = min(zoomRange.upperBound, max(zoomRange.lowerBound, c.zoom / scale))
        }
        return c
    }

    /// 見える部屋の角を画面へ映した外接の四角（点）。カメラの後ろの角があれば nil
    func shellBox(_ layout: CamperRoomLayout, viewport: CGSize) -> CGRect? {
        let s = layout.size
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for x in [0, s.x] {
            for z in [0, s.z] {
                // 手前（扉の壁 z = 奥行き）と、カメラの側の端の壁は切った高さまで
                let cutEnd = cutsFrontEnd ? x == s.x : x == 0
                let top = z == s.z || cutEnd ? CamperRoomBuilder.cutHeight : layout.ceilingHeight
                for y in [0, top] {
                    guard let p = project(CV3(x, y, z), viewport: viewport, layout: layout) else { return nil }
                    minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                    minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
