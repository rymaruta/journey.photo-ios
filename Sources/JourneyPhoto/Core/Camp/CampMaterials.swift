import Foundation

/// 島の素材の名前（板 Camp の `M`・実装の指定「素材の値」の付箋）
enum CampMaterialKey: Hashable, Sendable {
    case grass, lip, soil, soilDark, rock, rockDark
    /// テントの妻壁（裏）・扉のある妻壁（表・ファスナーの点線を描く）・フライ・結んだ扉布
    case tentEnd, tentEndFront, fly, flap
    /// テントの中（光の当たり方で塗らない・板の `IN` の色をそのまま）
    case innerBack, innerSideA, innerSideB, innerFloor, bag1, bag1Top, bag2, bag2Top, pillow, quilt1, quilt2
    case groundSheet, alu, brass, chrome, rubber, rope, woodDark, wood, bark, cutEnd, char, ash, stone, stoneLight
    /// 針葉樹の段（下から 0・1・2 の 3 色）と段の裏
    case pine(Int), pineUnder
    case frame, seat, cooler, lid, enamel, enamelRim, paperMap, glassLit, water, reed, snow
    /// 写真の切り絵（表は写真・裏は無地の紙・縁）。表は切り絵ごと・層ごとの絵
    case cutoutFront(String, Int), paperBack, paperEdge, grooves
    /// 頂点の色で塗る（草むら・垂れる草・花・苔）
    case vertexColor
}

/// 素材の値。色は板と同じ、粗さ・金属は付箋の推奨値（実機で合わせる）
struct CampMaterialSpec: Equatable, Sendable {
    /// 拡散色（16 進）
    var color: UInt32
    var roughness: Double = 0.9
    var metalness: Double = 0
    /// 内から光る色（夜のテントの布・ランタンの硝子）。nil なら光らない
    var emission: UInt32? = nil
    /// 光る面の強さ（1 まで。夜のテントを平らな橙の板にしない・2026-10-19 owner）
    var emissionIntensity: Double = 0
    /// 光の当たり方で塗らない（テントの中は板の色そのまま）
    var unlit: Bool = false
    /// 両面を描く（フライ・扉布・椅子の布・草）
    var doubleSided: Bool = false
    /// 透け（水・硝子）
    var opacity: Double = 1
    /// 貼り絵（`CampTexture`）
    var texture: CampTexture? = nil
    /// 光る面だけの貼り絵（無いときは `texture`）。夜のテントはむらのある透光図を使う
    var emissionTexture: CampTexture? = nil
    /// 塗り（clearCoat 0.5 の保冷箱の蓋など）
    var clearCoat: Double = 0
}

/// 素材に貼る絵（描くのは SceneKit の側・`CampTexturePainter`）
enum CampTexture: Hashable, Sendable {
    /// 芝の目（季節で色が変わる）
    case grass
    /// 土の壁（小石と、地層の線 3 本を y 9 / 14 / 19 に）
    case soil
    case rock
    /// 帆布の織り目（フライは縫い目・裾の濃い帯つき）
    case weave
    case fly
    /// 扉のある妻壁（ファスナーの点線・縁の濃い線）
    case tentFront
    /// 夜のテントの透光（内灯のむら・縁は暗い。拡散色には使わず光る面だけ）
    case tentLit
    case bark
    case grain
    /// 机の上の地図（道の赤い点線・青い線）
    case map
    /// 撮った写真の切り絵（id と層）
    case cutout(String, Int)
}

enum CampMaterials {

    /// 時刻・季節で決まる素材の値
    static func spec(_ key: CampMaterialKey, season: CampSeason, time: CampTime) -> CampMaterialSpec {
        let winter = season == .winter, autumn = season == .autumn, spring = season == .spring
        let night = time == .night
        let grass = grassColor(season)
        switch key {
        case .grass:
            return CampMaterialSpec(color: grass, roughness: winter ? 0.6 : 0.95, texture: winter ? nil : .grass)
        case .lip:
            return CampMaterialSpec(color: winter ? 0xDFE6EC : mix(grass, 0x1D2412, 0.25), roughness: 0.95)
        case .soil: return CampMaterialSpec(color: 0x6A4A32, roughness: 0.9, texture: .soil)
        case .soilDark: return CampMaterialSpec(color: 0x4A3222, roughness: 0.9, texture: .soil)
        case .rock: return CampMaterialSpec(color: 0x6B665E, roughness: 0.85, texture: .rock)
        case .rockDark: return CampMaterialSpec(color: 0x4B4741, roughness: 0.85, texture: .rock)
        case .tentEnd:
            // 夜: 拡散は昼の帆布色のまま、光る面だけ tentLit（むらのある透光）。平らな橙にしない
            return night
                ? CampMaterialSpec(color: 0xD8C299, roughness: 0.92, emission: 0xE8B878, emissionIntensity: 0.38,
                                   texture: .weave, emissionTexture: .tentLit)
                : CampMaterialSpec(color: 0xD8C299, roughness: 0.9, texture: .weave)
        case .tentEndFront:
            return night
                ? CampMaterialSpec(color: 0xD8C299, roughness: 0.92, emission: 0xE8B878, emissionIntensity: 0.42,
                                   texture: .tentFront, emissionTexture: .tentLit)
                : CampMaterialSpec(color: 0xD8C299, roughness: 0.9, texture: .tentFront)
        case .fly:
            if night {
                // フライは厚いので妻壁より弱く・棟へ暗い tentLit
                return CampMaterialSpec(color: 0x9C6A3E, roughness: 0.92, emission: 0xC88848, emissionIntensity: 0.24,
                                        doubleSided: true, texture: .fly, emissionTexture: .tentLit)
            }
            return CampMaterialSpec(color: winter ? 0xF2F5F8 : 0x9C6A3E, roughness: 0.9, doubleSided: true,
                                    texture: winter ? nil : .fly)
        case .flap:
            return CampMaterialSpec(color: 0xC9B083, roughness: 0.9, doubleSided: true, texture: .weave)
        // 夜の内幕は扉から覗くときだけ見える。橙に飛ばさず、灯りに照らされた帆布色に寄せる
        case .innerBack: return inside(night ? 0xC9A070 : 0x5A5345, night)
        case .innerSideA: return inside(night ? 0xB89058 : 0x4A4438, night)
        case .innerSideB: return inside(night ? 0xA87848 : 0x3C372D, night)
        case .innerFloor: return inside(night ? 0x3A3220 : 0x2E3A2E, night)
        case .bag1: return inside(night ? 0x7A3A28 : 0x6E2F20, night)
        case .bag1Top: return inside(night ? 0x8A4830 : 0x8A3D2A, night)
        case .bag2: return inside(night ? 0x2E4A68 : 0x26405E, night)
        case .bag2Top: return inside(night ? 0x3E5A7A : 0x33567C, night)
        case .pillow: return inside(night ? 0xE8D8B8 : 0xD8D0BF, night)
        case .quilt1: return inside(mix(night ? 0xB9603C : 0x8A3D2A, 0x000000, 0.28), night)
        case .quilt2: return inside(mix(night ? 0x577AA2 : 0x33567C, 0x000000, 0.28), night)
        case .groundSheet: return CampMaterialSpec(color: 0x2F3D30, roughness: 0.6)
        case .alu: return CampMaterialSpec(color: 0xB9BDC2, roughness: 0.35, metalness: 1)
        case .brass: return CampMaterialSpec(color: 0xC9A66B, roughness: 0.3, metalness: 1)
        case .chrome: return CampMaterialSpec(color: 0xC9CCD0, roughness: 0.12, metalness: 1)
        case .rubber: return CampMaterialSpec(color: 0x1B1C1F, roughness: 0.8)
        case .rope:
            return CampMaterialSpec(color: 0xF5F0E4, roughness: 0.9,
                                    emission: night ? 0x6A4A2A : nil, emissionIntensity: night ? 0.25 : 0)
        case .woodDark: return CampMaterialSpec(color: 0x6E4A2B, roughness: 0.75, texture: .grain)
        case .wood: return CampMaterialSpec(color: 0x9A6A3E, roughness: 0.75, texture: .grain)
        case .bark: return CampMaterialSpec(color: 0x5A3B24, roughness: 0.9, texture: .bark)
        case .cutEnd: return CampMaterialSpec(color: 0xD9B98A, roughness: 0.8, texture: .grain)
        case .char: return CampMaterialSpec(color: 0x1A1410, roughness: 0.95)
        case .ash: return CampMaterialSpec(color: 0x1C1612, roughness: 1)
        case .stone: return CampMaterialSpec(color: 0x8D8A83, roughness: 0.7, texture: .rock)
        case .stoneLight: return CampMaterialSpec(color: 0x9A968C, roughness: 0.7, texture: .rock)
        case .pine(let tier): return CampMaterialSpec(color: pineColor(tier, season: season), roughness: 0.8)
        case .pineUnder: return CampMaterialSpec(color: winter ? 0x8E9CA6 : 0x1A2A1A, roughness: 0.9)
        case .frame: return CampMaterialSpec(color: 0x2A2C30, roughness: 0.4, metalness: 0.6)
        case .seat: return CampMaterialSpec(color: 0x55613F, roughness: 0.9, doubleSided: true, texture: .weave)
        case .cooler: return CampMaterialSpec(color: 0x3E5A5C, roughness: 0.4, clearCoat: 0.5)
        case .lid: return CampMaterialSpec(color: 0xECE7DA, roughness: 0.4, clearCoat: 0.5)
        case .enamel: return CampMaterialSpec(color: 0xF2EFE6, roughness: 0.3, clearCoat: 0.5)
        case .enamelRim: return CampMaterialSpec(color: 0x2F4F74, roughness: 0.3)
        case .paperMap: return CampMaterialSpec(color: 0xEFE6CF, roughness: 0.95, texture: .map)
        case .glassLit:
            // ランタンの硝子: 芯だけ明るく、面全体を白く飛ばさない
            return night ? CampMaterialSpec(color: 0xE8C080, roughness: 0.25, emission: 0xE8B070, emissionIntensity: 0.52)
                : CampMaterialSpec(color: 0xE9E4D6, roughness: 0.1, opacity: 0.85)
        case .water: return CampMaterialSpec(color: night ? 0x0E1A2C : 0x2C4A5A, roughness: 0.05, opacity: 0.92)
        case .reed: return CampMaterialSpec(color: autumn && !spring ? 0x9A7A3A : 0x4A6A30, roughness: 0.9, doubleSided: true)
        case .snow: return CampMaterialSpec(color: 0xF6F9FC, roughness: 0.6)
        case .cutoutFront(let id, let layer):
            return CampMaterialSpec(color: 0xFFFFFF, roughness: 0.9, texture: .cutout(id, layer))
        case .paperBack: return CampMaterialSpec(color: 0xE6E0D2, roughness: 0.9)
        case .paperEdge: return CampMaterialSpec(color: 0xEBE5D6, roughness: 0.9)
        case .grooves: return CampMaterialSpec(color: 0x2A1608, roughness: 1)
        case .vertexColor: return CampMaterialSpec(color: 0xFFFFFF, roughness: 0.95, doubleSided: true)
        }
    }

    private static func inside(_ color: UInt32, _ night: Bool) -> CampMaterialSpec {
        // unlit なので emission の強さは SceneKit では 0（色は diffuse に載る）。値だけ揃えておく
        CampMaterialSpec(color: color, roughness: 1, emission: night ? color : nil, emissionIntensity: night ? 0.5 : 0,
                         unlit: true, doubleSided: true)
    }

    /// 芝の色（付箋: 夏 #4f7233・春 #6e8f45・秋 #8a7a3a・冬 #e9eef3）
    static func grassColor(_ season: CampSeason) -> UInt32 {
        switch season {
        case .spring: return 0x6E8F45
        case .summer: return 0x4F7233
        case .autumn: return 0x8A7A3A
        case .winter: return 0xE9EEF3
        }
    }

    /// 針葉樹の段の色（下から 2・2・1 段。冬は上の段ほど白く）
    static func pineColor(_ tier: Int, season: CampSeason) -> UInt32 {
        let t = max(0, min(2, tier))
        switch season {
        case .winter: return mix(0x2F4A35, 0xEEF3F7, t == 2 ? 0.7 : 0.35)
        case .autumn: return [0x3B5233, 0x46603A, 0x55703F][t]
        case .spring: return [0x3E6234, 0x4C7340, 0x5D8A4A][t]
        case .summer: return [0x2C4A2C, 0x365A34, 0x42683C][t]
        }
    }

    /// 2 つの色を混ぜる（板の `mix`）
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ c: UInt32, _ s: UInt32) -> Double { Double((c >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, (ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()))) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }

    /// 0〜1 の RGB へ（頂点の色）
    static func rgb(_ c: UInt32) -> CampVec3 {
        CampVec3(Double((c >> 16) & 0xFF) / 255, Double((c >> 8) & 0xFF) / 255, Double(c & 0xFF) / 255)
    }
}
