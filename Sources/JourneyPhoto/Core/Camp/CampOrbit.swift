import Foundation

/// 島の見せ方（板 Camp の `part`）。ふだんは `all`。ほかは部品に寄った図（12 の向き・部品の板）
enum CampFocus: String, CaseIterable, Codable, Sendable {
    case all, island, tent, fire, trees, gear, cutout

    /// 寄る先・倍率・既定の向き（板の `presets`）
    var preset: (target: CampVec3, zoom: Double, rx: Double?, ry: Double?) {
        switch self {
        case .all: return (CampVec3(0, 10, 0), 1, nil, nil)
        case .island: return (CampVec3(0, 40, 0), 1.35, -12, -30)
        case .tent: return (CampVec3(-34, -22, -26), 2.6, -18, -40)
        case .fire: return (CampVec3(38, -6, 34), 4.2, -26, -30)
        case .trees: return (CampVec3(-40, -40, -50), 1.9, -14, -30)
        case .gear: return (CampVec3(40, -8, 50), 2.6, -24, -22)
        case .cutout: return (CampVec3(-74, -30, 52), 3.0, -10, -30)
        }
    }

    /// 全体の図の倍率は育ちで変える（小さい島を寄って見せる・板 `presets.all.z`）
    func zoom(stage: CampStage) -> Double {
        guard self == .all else { return preset.zoom }
        switch stage {
        case .fire: return 1.3
        case .tent: return 1.04
        case .camp: return 0.94
        }
    }
}

/// 島を見る向き（度）。rx は縦（負で見下ろす）、ry は横の回り。板の `rX(rx, rY(ry, p))`
struct CampAngle: Equatable, Sendable {
    var rx: Double
    var ry: Double

    /// 初めの向き（実装の指定「回したときの見え方の注意」: 縦 −30°・横 −36°）
    static let resting = CampAngle(rx: -30, ry: -36)
}

/// 指で回すときの決まりと、板の投影（SceneKit のカメラに置き換える値）
enum CampOrbit {

    /// 縦の回りの範囲（実装の指定: −75°〜0°。下から見る図だけは +18° を板が直に指定する）
    static let pitchRange: ClosedRange<Double> = -75...0
    /// 指 1pt あたりの回り（板 Main: 横 0.6・縦 0.4）
    static let yawPerPoint = 0.6
    static let pitchPerPoint = 0.4
    /// 板の遠近（`persp` 900）
    static let perspective = 900.0

    /// 指で払った量から次の向き（縦は範囲に収める）
    static func dragged(from start: CampAngle, dx: Double, dy: Double) -> CampAngle {
        let rx = min(pitchRange.upperBound, max(pitchRange.lowerBound, start.rx - dy * pitchPerPoint))
        return CampAngle(rx: rx, ry: start.ry + dx * yawPerPoint)
    }

    /// 板の倍率（`zoom`）。枠の大きさで縮める（板: `min(W, H × 1.09) / 370`）
    static func scale(focus: CampFocus, stage: CampStage, zoom: Double = 1, width: Double, height: Double) -> Double {
        zoom * focus.zoom(stage: stage) * (min(width, height * 1.09) / 370)
    }

    /// カメラの距離（板の単位）。板の目は `persp / scale` 離れた所にある
    static func cameraDistance(scale: Double) -> Double { perspective / max(0.01, scale) }

    /// 縦の画角（度）。板の 1 単位が原点で `scale` px になる画角（`tan(f/2) = H / (2 × persp)`）
    static func fieldOfView(height: Double) -> Double {
        2 * atan(height / (2 * perspective)) * 180 / .pi
    }

    /// 板の点を画面の点へ（板の `proj`）。返すのは (x, y, 奥行き z, 縮み k)
    static func project(_ p: CampVec3, angle: CampAngle, target: CampVec3, scale: Double,
                        width: Double, height: Double) -> (x: Double, y: Double, z: Double, k: Double) {
        let v = toView(p - target, angle: angle)
        let z = v.z * scale
        let k = perspective / (perspective - z)
        return (width / 2 + v.x * scale * k, height / 2 + v.y * scale * k, z, k)
    }

    /// 板の座標の向きを、見る向きの座標へ（`rX(rx, rY(ry, v))`）
    static func toView(_ v: CampVec3, angle: CampAngle) -> CampVec3 {
        v.rotatedY(angle.ry).rotatedX(angle.rx)
    }

    /// 板の座標（y が下）を SceneKit の座標（y が上）へ
    static func toScene(_ p: CampVec3) -> CampVec3 { CampVec3(p.x, -p.y, p.z) }

    /// SceneKit の回し方（`eulerAngles` の pitch・yaw。ラジアン）。
    /// y を返すと縦の回りの向きが逆になる: 板の rX(rx)・rY(ry) は SceneKit の Rx(−rx)・Ry(ry)
    static func sceneEuler(_ angle: CampAngle) -> (pitch: Double, yaw: Double) {
        (-angle.rx * .pi / 180, angle.ry * .pi / 180)
    }

    /// 空の太陽（月）の画面の位置と、出すかどうか（板の `sky dressing`）
    static func sunOnScreen(light: CampVec3, angle: CampAngle, width: Double, height: Double)
        -> (x: Double, y: Double, visible: Bool) {
        let lv = toView(light.normalized, angle: angle)
        let d = max(0.25, -lv.z + 0.6)
        return (width / 2 + (lv.x / d) * width * 0.32, height * 0.42 + (lv.y / d) * height * 0.42, lv.z < 0.25)
    }
}

/// 12 の向き（板 CampViews「どこから見てもホンモノ」）。どの図も閉じた立体で、嘘にならないことを確かめる
struct CampView: Equatable, Sendable {
    let number: Int
    let title: String
    let focus: CampFocus
    let time: CampTime
    let season: CampSeason
    let stage: CampStage
    let angle: CampAngle
    /// 部品に寄った図の地の光（板の `glow`）
    let glow: UInt32

    static func all() -> [CampView] {
        func v(_ n: Int, _ title: String, focus: CampFocus = .all, time: CampTime = .evening,
               season: CampSeason = .summer, stage: CampStage = .tent, rx: Double? = nil, ry: Double? = nil,
               glow: UInt32 = 0x16140F) -> CampView {
            let p = focus.preset
            return CampView(number: n, title: title, focus: focus, time: time, season: season, stage: stage,
                            angle: CampAngle(rx: rx ?? p.rx ?? CampAngle.resting.rx, ry: ry ?? p.ry ?? CampAngle.resting.ry),
                            glow: glow)
        }
        return [
            v(1, L("いつもの向き（夕）", "Usual view (evening)")),
            v(2, L("後ろ", "Back"), rx: -14, ry: 144),
            v(3, L("横", "Side"), rx: -8, ry: -100),
            v(4, L("上", "Top"), rx: -80, ry: -20),
            v(5, L("下（岩の底）", "Below (rock base)"), focus: .island, rx: 18, ry: -30, glow: 0x101010),
            v(6, L("テントの扉", "Tent door"), focus: .tent, time: .day, glow: 0x101010),
            v(7, L("テントの裏", "Tent back"), focus: .tent, time: .day, ry: 140, glow: 0x101010),
            v(8, L("焚き火（夜）", "Fire (night)"), focus: .fire, time: .night, glow: 0x1C1206),
            v(9, L("写真の切り絵（表）", "Photo cutout (front)"), focus: .cutout, time: .morning, glow: 0x101010),
            v(10, L("写真の切り絵（裏）", "Photo cutout (back)"), focus: .cutout, time: .morning, ry: 150, glow: 0x101010),
            v(11, L("夜（キャンプ場まで育った島）", "Night (grown campsite)"), time: .night, stage: .camp),
            v(12, L("冬", "Winter"), time: .day, season: .winter, stage: .camp),
        ]
    }
}
