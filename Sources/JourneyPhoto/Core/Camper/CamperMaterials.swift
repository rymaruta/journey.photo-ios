import Foundation

/// キャンピングカーの素材の名前（網の束ごと・部品ごとに付ける）。値は `CamperMaterialSpec`
enum CamperMaterial: Hashable, Sendable {
    case paint, cap, deep, roof, under, well, reveal
    case pinstripe, pinstripeDark
    case glass, lens, lensAmber, red, amber, lamp
    case chrome, chromeDark, brass, alu, black, steel, chassis, rubber, tread, whitewall
    case wood, woodDark, fabric, fabricDark, cushion, curtain, inner, ceiling, floorIn, dash, seat, stone, mat
    case solar, solarFrame, snow, jerry, tank
    case plate(UInt32), plateInk(UInt32)
    case canvas(UInt32), canvasLight
    case roofBox
    case paper, foil
    /// ホログラムの縁（見る角度で色が変わる箔）
    case holo
    /// 壁の木（色ちがいの木目）
    case wallWood(UInt32)
    /// 燃えている薪・ストーブの窓（昼も少し光る）
    case ember
    /// 色だけ決める樹脂・紙（ステッカーの図柄・本の背・葉など）
    case tint(UInt32)
    /// まだ持っていない部品の影絵（黒・艶なし）
    case silhouette
    /// 夜、窓と扉の口から地面へこぼれる灯り（足し合わせる光の溜まり・影を落とさない）
    case glowPool
}

/// 素材の値（SceneKit の physicallyBased にそのまま渡す）。板の付箋「素材の値（実装用）」の推奨値
struct CamperMaterialSpec: Equatable, Sendable {
    var color: UInt32
    var metalness = 0.0
    var roughness = 0.6
    var clearCoat = 0.0
    var clearCoatRoughness = 0.1
    /// 1 で不透明
    var opacity = 1.0
    /// 自ら光る色と強さ（夜の灯り）
    var emission: UInt32?
    var emissionIntensity = 0.0
    var texture: CamperTextureKind?
    var doubleSided = false
    /// 光を受けない一色（影絵）
    var unlit = false
    /// 下の色に足し合わせる光（地面の灯りの溜まり）。光を受けず、影も奥行きも書かない
    var additive = false
}

/// 手で描く小さな貼り絵（`CamperTextures`）
enum CamperTextureKind: String, Sendable, CaseIterable {
    case woodGrain
    case weave
    case solarCells
    case brushed
    /// 真ん中が明るく外へ消える丸（灯りの溜まり）
    case glow
}

enum CamperMaterials {

    /// 色を混ぜる（0xRRGGBB）
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, (ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()))) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }

    /// 素材の値。塗装の色と時刻で変わる
    static func spec(_ m: CamperMaterial, paint: UInt32, mood: CamperMood) -> CamperMaterialSpec {
        let night = mood == .night, snow = mood == .snow
        switch m {
        case .paint: return CamperMaterialSpec(color: paint, roughness: 0.35, clearCoat: 1, clearCoatRoughness: 0.08)
        case .cap: return CamperMaterialSpec(color: snow ? 0xEEF1F4 : 0xEBE4D2, roughness: 0.4, clearCoat: 0.8, clearCoatRoughness: 0.08)
        case .deep: return CamperMaterialSpec(color: mix(paint, 0x0A0B0D, 0.58), roughness: 0.35, clearCoat: 1, clearCoatRoughness: 0.08)
        case .roof: return CamperMaterialSpec(color: snow ? 0xF4F7FA : 0xDDD6C4, roughness: 0.7)
        case .under: return CamperMaterialSpec(color: 0x202124, roughness: 0.8)
        case .well: return CamperMaterialSpec(color: 0x0C0C0D, roughness: 0.9)
        case .reveal: return CamperMaterialSpec(color: 0x141416, roughness: 0.8)
        case .pinstripe: return CamperMaterialSpec(color: 0xC9A66B, metalness: 0.6, roughness: 0.3, clearCoat: 1, clearCoatRoughness: 0.08)
        case .pinstripeDark: return CamperMaterialSpec(color: 0x8A6D3D, metalness: 0.5, roughness: 0.35, clearCoat: 1)
        case .glass:
            // 夜は室内の灯りでガラスがほのかに光る（窓が灯りの主役。2026-10-18 Mac の絵 run 529 のあと）
            return CamperMaterialSpec(color: night ? 0x3A2A18 : 0x10161C, roughness: 0.05, opacity: night ? 0.42 : 0.62,
                                      emission: night ? 0xFFB866 : nil, emissionIntensity: night ? 0.5 : 0, doubleSided: true)
        case .lens:
            return CamperMaterialSpec(color: 0xDFE6EC, roughness: 0.05, opacity: night ? 1 : 0.85,
                                      emission: night ? 0xFFF6E0 : nil, emissionIntensity: night ? 2.2 : 0)
        case .lensAmber:
            return CamperMaterialSpec(color: 0xE8B44A, roughness: 0.05, opacity: 0.9,
                                      emission: night ? 0xFFD27A : nil, emissionIntensity: night ? 1.8 : 0)
        case .red:
            return CamperMaterialSpec(color: night ? 0xFF4A3C : 0x8E1D1A, roughness: 0.1, clearCoat: 1,
                                      emission: night ? 0xFF4A3C : nil, emissionIntensity: night ? 1.6 : 0)
        case .amber:
            return CamperMaterialSpec(color: night ? 0xFFB347 : 0xC9772A, roughness: 0.1, clearCoat: 1,
                                      emission: night ? 0xFFB347 : nil, emissionIntensity: night ? 1.2 : 0)
        case .lamp:
            // 電球は小さいので、強すぎると光の粒が散って見える（run 529 の夜）。窓の灯りより少し上まで
            return CamperMaterialSpec(color: 0xFFD890, roughness: 0.3, emission: night ? 0xFFD890 : nil,
                                      emissionIntensity: night ? 1.1 : 0)
        case .chrome: return CamperMaterialSpec(color: 0xC9CCD0, metalness: 1, roughness: 0.12)
        case .chromeDark: return CamperMaterialSpec(color: 0x8D9196, metalness: 1, roughness: 0.18)
        case .brass: return CamperMaterialSpec(color: 0xC9A66B, metalness: 1, roughness: 0.3)
        case .alu: return CamperMaterialSpec(color: 0xB9BDC2, metalness: 1, roughness: 0.35, texture: .brushed)
        case .black: return CamperMaterialSpec(color: 0x1B1C1F, roughness: 0.45)
        case .steel: return CamperMaterialSpec(color: 0x26282C, metalness: 0.3, roughness: 0.4, clearCoat: 0.6)
        case .chassis: return CamperMaterialSpec(color: 0x1A1B1E, metalness: 0.2, roughness: 0.6)
        case .rubber: return CamperMaterialSpec(color: 0x19191B, roughness: 0.85)
        case .tread: return CamperMaterialSpec(color: 0x141416, roughness: 0.95)
        case .whitewall: return CamperMaterialSpec(color: 0xECEBE6, roughness: 0.6)
        case .wood: return CamperMaterialSpec(color: 0x9A6A3E, roughness: 0.7, texture: .woodGrain)
        case .woodDark: return CamperMaterialSpec(color: 0x6E4A2B, roughness: 0.7, texture: .woodGrain)
        case .fabric: return CamperMaterialSpec(color: 0x5D6B4A, roughness: 0.95, texture: .weave)
        case .fabricDark: return CamperMaterialSpec(color: 0x4A5639, roughness: 0.95, texture: .weave)
        case .cushion: return CamperMaterialSpec(color: 0xB7A58A, roughness: 0.9, texture: .weave)
        case .curtain:
            return CamperMaterialSpec(color: night ? 0xF2CC92 : 0xD8CCB4, roughness: 0.95, emission: night ? 0xF2CC92 : nil,
                                      emissionIntensity: night ? 0.35 : 0, texture: .weave, doubleSided: true)
        case .inner: return CamperMaterialSpec(color: 0xC9BFAE, roughness: 0.8)
        case .ceiling: return CamperMaterialSpec(color: 0xE8E0D0, roughness: 0.85)
        case .floorIn: return CamperMaterialSpec(color: 0x7A5A3C, roughness: 0.6, texture: .woodGrain)
        case .dash: return CamperMaterialSpec(color: 0x2A2B2E, roughness: 0.6)
        case .seat: return CamperMaterialSpec(color: 0x3A3530, roughness: 0.9, texture: .weave)
        case .stone: return CamperMaterialSpec(color: 0xD9D2C4, roughness: 0.3, clearCoat: 0.5)
        case .mat: return CamperMaterialSpec(color: 0x7A3A2A, roughness: 0.95, texture: .weave)
        case .solar: return CamperMaterialSpec(color: 0x16233A, metalness: 0.2, roughness: 0.1, texture: .solarCells)
        case .solarFrame: return CamperMaterialSpec(color: 0xC9CCD1, metalness: 1, roughness: 0.3)
        case .snow: return CamperMaterialSpec(color: 0xF6F9FC, roughness: 0.8)
        case .jerry: return CamperMaterialSpec(color: 0x7C2B20, roughness: 0.4, clearCoat: 0.6)
        case .tank: return CamperMaterialSpec(color: 0xCFCBC2, roughness: 0.6)
        case .plate(let c): return CamperMaterialSpec(color: c, metalness: c == 0xC9A66B ? 1 : 0, roughness: 0.35)
        case .plateInk(let c): return CamperMaterialSpec(color: c, roughness: 0.4)
        case .canvas(let c): return CamperMaterialSpec(color: c, roughness: 0.95, texture: .weave, doubleSided: true)
        case .canvasLight: return CamperMaterialSpec(color: 0xECE7DA, roughness: 0.95, texture: .weave, doubleSided: true)
        case .roofBox: return CamperMaterialSpec(color: mix(paint, 0x0A0B0D, 0.35), roughness: 0.3, clearCoat: 1)
        case .paper: return CamperMaterialSpec(color: 0xF4F1E8, roughness: 0.4, clearCoat: 0.6)
        case .foil: return CamperMaterialSpec(color: 0xD9B877, metalness: 1, roughness: 0.18)
        case .holo: return CamperMaterialSpec(color: 0xC8B8F0, metalness: 1, roughness: 0.12, clearCoat: 1, clearCoatRoughness: 0.05)
        case .tint(let c): return CamperMaterialSpec(color: c, roughness: 0.5, clearCoat: 0.3)
        case .wallWood(let c): return CamperMaterialSpec(color: c, roughness: 0.7, texture: .woodGrain)
        case .ember:
            return CamperMaterialSpec(color: 0xFF7A2E, roughness: 0.8, emission: 0xFF8A3C, emissionIntensity: night ? 2.4 : 0.8)
        case .silhouette: return CamperMaterialSpec(color: 0x050505, roughness: 1, unlit: true)
        case .glowPool: return CamperMaterialSpec(color: 0x8A5A2C, texture: .glow, additive: true)
        }
    }

    /// 周りの空（映り込みの元・板の env の色: 空の上・地平線・地面の手前・地面の奥）
    static func sky(_ mood: CamperMood) -> (top: UInt32, horizon: UInt32, groundNear: UInt32, groundFar: UInt32) {
        switch mood {
        // 地面は暗く（映り込みの地平線をくっきりさせる・車の下側が明るくなりすぎない）
        case .day: return (0x5F87B0, 0xEFE5D0, 0x2E2A23, 0x16140F)
        case .night: return (0x0B1220, 0x2A3550, 0x141A24, 0x07090C)
        case .snow: return (0x9FB0C2, 0xEEF2F6, 0xD9E1EA, 0x8D99A6)
        }
    }

    /// 床（板の付箋「接地の影と床」）。
    ///
    /// 2026-10-18 判断（Mac の絵 run 529）: 床に貼った楕円の絵が SCNFloor では引き伸ばされ、ベージュの平たい板と
    /// その奥の地平線の線に見えた（安っぽい）。床は**暗い一色**にし、透け具合は絵ではなく車からの距離で決める
    /// （`CamperFloor.shaderModifier`）。真ん中は映り込みと落ち影を受け、外へ行くほど消えて画面の黒い地に溶ける。境目の線は無い
    static func floor(_ mood: CamperMood) -> CamperFloor {
        switch mood {
        case .day: return CamperFloor(color: 0x1C1A16, reflectivity: 0.22)
        case .night: return CamperFloor(color: 0x0E121B, reflectivity: 0.2)
        case .snow: return CamperFloor(color: 0x8C99A8, reflectivity: 0.1)
        }
    }

    /// 地（画面の後ろの丸いグラデーションの真ん中の色・板 Main）
    static func backdrop(_ mood: CamperMood) -> UInt32 {
        switch mood {
        case .day: return 0x1D1B14
        case .night: return 0x101A2C
        case .snow: return 0x222A33
        }
    }
}

/// 床の値（SceneKit の `SCNFloor` に渡す。素の Swift なので試験できる）
struct CamperFloor: Equatable, Sendable {
    var color: UInt32
    var roughness = 0.85
    /// 映り込みの強さ
    var reflectivity: Double
    /// ここ（車の真ん中からの距離・SceneKit の単位）までは濃く、`fadeEnd` で消える。
    /// 車体の長さは 2.42、トレーラーつきは後ろへ 1.6 ほど伸びる
    var fadeStart = 1.5
    var fadeEnd = 4.2

    /// 床の透け具合を距離で決める（Metal の fragment の shader modifier）。
    /// `_output.color` に掛けると、色も透け具合も一緒に 0 へ向かう（地平線の線が出ない。SCNView の地は透明なので、
    /// 0 の所は後ろの画面の地がそのまま見える）。**不透明の組で描く**（`#pragma transparent` を付けない）:
    /// 透ける組は落ち影（deferred）を描いた後に描かれ、太陽の影が床に落ちなくなる
    var shaderModifier: String {
        """
        #pragma body
        float4 jpWorld = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
        float jpFade = 1.0 - smoothstep(\(fadeStart), \(fadeEnd), length(jpWorld.xz));
        _output.color *= jpFade;
        """
    }
}
