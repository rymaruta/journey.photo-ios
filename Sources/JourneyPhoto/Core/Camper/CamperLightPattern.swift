import Foundation
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

// 灯りの型（2026-10-20 owner「光のパターンは何種類か用意して使い方をわけないと」）。
// 1.1.21 で減衰を全部なだらかにしたら尾灯が真っ赤な白い球になった——用途ごとに当て方を分ける。

/// 空間を照らす灯りの型。停めた車なので前照灯・尾灯・車幅灯は点けず、ここにも入れない（2026-10-19・レンズは透ける硝子だけ）
enum CamperLightPattern: String, CaseIterable, Sendable, Equatable {
    /// 車内の天井灯: 下向き spot・影あり・急減衰（壁の外へ漏らさない）
    case ceiling
    /// とおまわり号の中の家具灯: omni・なだらか（木と布に溜まる）
    case roomLamp
    /// 焚き火: 暖かい omni・ややなだらか・足元に広い溜まり絵
    case hearth
    /// ランタン・電飾の紐: 弱い omni・急減衰・小さい溜まり絵
    case lantern
    /// 入口の灯り（扉の上の壁の灯り）: 弱い下向き spot・急減衰・影なし（2026-10-19・停めた車で点く外の灯り）
    case porch

    /// SceneKit の減衰（板の単位の range と、SceneKit へ渡す倍率 unit）
    func attenuation(range: Double, unit: Double) -> (start: CGFloat, end: CGFloat, falloff: CGFloat) {
        let r = range * unit
        switch self {
        case .ceiling, .lantern, .porch:
            // 急に落とす。なだらかにすると空間を染めすぎる
            return (0, CGFloat(r), 2)
        case .roomLamp:
            // 部屋の家具: 白い芯を避け、なだらかに回る
            return (CGFloat(r * 0.14), CGFloat(r * 1.15), 1.2)
        case .hearth:
            // 焚き火だけ少しなだらか（芝へ溜まる）
            return (CGFloat(r * 0.1), CGFloat(r * 1.1), 1.5)
        }
    }

    /// 揺らすか（焚き火・ランタン）
    var flickers: Bool {
        switch self {
        case .hearth, .lantern: return true
        case .ceiling, .roomLamp, .porch: return false
        }
    }
}

/// 地面・窓の「足す光」の溜まり絵の型（SCNLight ではない。additive の板）
enum CamperGlowPattern: String, CaseIterable, Sendable, Equatable {
    /// 窓の下・扉の前のこぼれ光
    case spillWarm
    /// 焚き火・ランタンの足元
    case fire
}

extension CamperLightSpec {
    /// 型に従って SCNLight の減衰を入れる
    func applyAttenuation(to light: SCNLight, unit: Double) {
        let a = pattern.attenuation(range: range, unit: unit)
        light.attenuationStartDistance = a.start
        light.attenuationEndDistance = a.end
        light.attenuationFalloffExponent = a.falloff
    }
}
