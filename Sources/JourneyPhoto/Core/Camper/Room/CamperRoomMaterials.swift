import Foundation

// とおまわり号の中の素材（2026-10-19）。外まわりと同じ physicallyBased の値（`CamperMaterialSpec`）で、貼り絵は
// `CamperRoomTextures`。owner「アーティファクトの家具はホンモノ感が足りない」: 単色の平らな面にしない——
// 木は木目と使い込んだ艶のむら、布は織り目とよれ、革は粒としわ、金属は粗さの違い、陶器と琺瑯は艶と欠け。
//
// 夜の光の決まり（外まわりと同じ・docs/CAMPER.md）: 光る面の emission は 1 まで、にじみ（bloom）は使わない。
// 灯りの笠・電球・ストーブの窓は、光る面に明暗の絵を貼る（一色の平らな光にしない）。

/// 木の種類（色）
enum CamperRoomWood: String, CaseIterable, Hashable, Sendable {
    case oak, walnut, pine, teak, birch, cedar, darkOak

    var color: UInt32 {
        switch self {
        case .oak: return 0xB08A5E
        case .walnut: return 0x5E3F2A
        case .pine: return 0xC9A57A
        case .teak: return 0x8A5A36
        case .birch: return 0xD8C4A2
        case .cedar: return 0xA0603E
        case .darkOak: return 0x6E4A2B
        }
    }
}

/// 室内の素材
enum CamperRoomMaterial: Hashable, Sendable {
    /// 木（木目・艶のむら）
    case wood(CamperRoomWood)
    /// 手の触れる所が擦れて明るくなった木（取っ手のまわり・縁）
    case wornWood(CamperRoomWood)
    /// 塗った木・鉄（色）
    case painted(UInt32)
    /// 布: 麻（節のある織り）・編み物・帆布・別珍
    case linen(UInt32)
    case knit(UInt32)
    case canvas(UInt32)
    case velvet(UInt32)
    case leather(UInt32)
    /// 布団・マットレス（綿の生地）
    case cotton(UInt32)
    /// 金属: 磨いた真鍮・くすんだ真鍮・黒い鉄・鋳物・琺瑯（色）・クローム
    case brass, agedBrass, iron, castIron, chrome
    case enamel(UInt32)
    /// 陶器（色）・素焼き
    case ceramic(UInt32)
    case terracotta
    /// 透明の硝子・額の表の薄い硝子・乳白の硝子（夜は灯る）
    case glass, frameGlass, milkGlass
    /// 灯りの笠の布（色。夜は内からの光が透ける）
    case shade(UInt32)
    /// 電球（夜は灯る）
    case bulb
    /// 炎・燠（ストーブの窓の奥）
    case fire
    /// ストーブの窓の雲母（夜は奥の火で明るむ）
    case mica
    /// 畳の目・畳の黒い縁・籐・麻紐
    case rush, rushEdge, wicker, rope
    /// 葉・土
    case leaf, soil
    /// 紙・額のマット・時計の文字盤
    case paper, mat, dial
    /// 飾った写真（家具の名前 `u` ごと。絵は画面の側が写真で差し替える）
    case photo(String)
    /// 敷物の柄（細長い敷物・楕円の輪）
    case runner, ovalRug
    // 部屋
    /// 床（外まわりの図鑑の床の key）・壁（壁の木の key）
    case floorFinish(String)
    case wallFinish(String)
    /// カーテン（色）
    case curtain(UInt32)
    /// 台所の天板（石）・扉（色）・流し（ステンレス）
    case countertop, cabinet(UInt32), sinkSteel
    /// 壁の断面: 外板（車の塗装）・断熱材
    case skin(UInt32), insulation
    /// 幅木・窓枠（木）・窓のゴム
    case trim, windowRubber
    /// 窓の外の景色（昼・夜で絵が替わる。光を受けない）
    case windowView
    /// 色紙（折り鶴・紙の玉。薄く、両面）
    case paperColor(UInt32)
    /// 色硝子（色硝子の天窓・小瓶。透ける）
    case tintedGlass(UInt32)
    /// 旅の地図の印刷（紙に道と点）
    case mapPrint
    /// 鏡（2026-10-21）: クロームの板だと周りの光の絵だけを映して真鍮の円盤・黒い板に見えた。映る部屋の絵に硝子の照り
    case mirror
    /// 部屋の中の物の硝子（瓶・器・戸・球）。窓の硝子は夜に外の暗さで黒く曇らせるが、物の硝子は夜も透ける（2026-10-21）
    case clearGlass
    /// 中に物を入れた透明の球（硝子の球の吊り鉢・2026-10-21）。光を受けない足す光で、中身と奥の壁を隠さない
    case globeGlass
    /// 硝子の球の映りの筋（窓の明かりが映った細い弧・足す光）
    case globeGlint
    /// まだ持っていない家具の影絵
    case silhouette
}

enum CamperRoomMaterials {

    /// 家具の網から分けて、壁・中身を描いた後に重ねる透明の硝子（硝子の球・瓶・ポット・戸棚の戸）。
    /// 2026-10-21（Mac run 625・632）: 家具 1 つの網の中に混ぜたままだと、硝子が壁や中身より先に描かれ、昼は灰色、
    /// 夜は灯りに照らされた不透明な玉（拡散の色を黒にすると黒い玉）に見えた。外の車の硝子・炎（`CamperScene`）と同じく後に足す
    static func drawnAfterOpaque(_ m: CamperMaterial) -> Bool {
        m == .room(.clearGlass) || m == .room(.globeGlass) || m == .room(.globeGlint)
    }

    /// カーテンの色（板 CamperRoomMain: 麻・藍・森の緑・赤茶）
    static let curtainColors: [(key: String, ja: String, en: String, color: UInt32)] = [
        ("linen", "麻", "Linen", 0xD9CCB2), ("indigo", "藍", "Indigo", 0x2F4F74),
        ("forest", "森の緑", "Forest", 0x4A5A46), ("rust", "赤茶", "Rust", 0x8A3A26),
    ]

    /// 灯りの色（暖かい白 2700K・昼の白 4000K・琥珀 2200K）
    static let lightColors: [(key: String, ja: String, en: String, color: UInt32)] = [
        ("warm", "暖かい白", "Warm white", 0xFFC98A), ("white", "昼の白", "Daylight", 0xFFE9CF), ("amber", "琥珀", "Amber", 0xFFA650),
    ]

    static func curtainColor(_ key: String) -> UInt32 { curtainColors.first { $0.key == key }?.color ?? 0xD9CCB2 }
    static func lightColor(_ key: String) -> UInt32 { lightColors.first { $0.key == key }?.color ?? 0xFFC98A }

    /// 床の仕上げ（外まわりの図鑑の床: ナラの板・コルク・矢筈の寄木・市松のタイル）
    static func floorSpec(_ key: String) -> CamperMaterialSpec {
        switch key {
        case "cork": return CamperMaterialSpec(color: 0xB8875A, roughness: 0.85, texture: .cork)
        case "chevron": return CamperMaterialSpec(color: 0xB58D60, roughness: 0.5, clearCoat: 0.35, clearCoatRoughness: 0.3, texture: .chevron)
        case "checker_tiles": return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.25, clearCoat: 0.6, clearCoatRoughness: 0.15, texture: .checkerTiles)
        default: return CamperMaterialSpec(color: 0xA87A4A, roughness: 0.55, clearCoat: 0.3, clearCoatRoughness: 0.35, texture: .planks)
        }
    }

    /// 壁の仕上げ（外まわりの図鑑の壁の木: 松の板・樺の合板・胡桃・矢筈）
    static func wallSpec(_ key: String) -> CamperMaterialSpec {
        switch key {
        case "plywood_birch": return CamperMaterialSpec(color: 0xE4D6BC, roughness: 0.7, texture: .birchPly)
        case "dark_walnut": return CamperMaterialSpec(color: 0x7A5232, roughness: 0.65, texture: .darkBoards)
        case "herringbone": return CamperMaterialSpec(color: 0xC9A57A, roughness: 0.65, texture: .herringbone)
        default: return CamperMaterialSpec(color: 0xD9B98A, roughness: 0.72, texture: .boards)
        }
    }

    static func spec(_ m: CamperRoomMaterial, mood: CamperMood) -> CamperMaterialSpec {
        let night = mood == .night
        switch m {
        case .wood(let w):
            return CamperMaterialSpec(color: w.color, roughness: 0.62, clearCoat: 0.25, clearCoatRoughness: 0.4, texture: .furnitureGrain)
        case .wornWood(let w):
            return CamperMaterialSpec(color: CamperMaterials.mix(w.color, 0xFFFFFF, 0.08), roughness: 0.48, clearCoat: 0.4, clearCoatRoughness: 0.3,
                                      texture: .wornWood)
        case .painted(let c): return CamperMaterialSpec(color: c, roughness: 0.55, clearCoat: 0.3, clearCoatRoughness: 0.35, texture: .enamelChip)
        case .linen(let c): return CamperMaterialSpec(color: c, roughness: 0.95, texture: .linenSlub)
        case .knit(let c): return CamperMaterialSpec(color: c, roughness: 1, texture: .knit)
        case .canvas(let c): return CamperMaterialSpec(color: c, roughness: 0.93, texture: .weave)
        case .velvet(let c): return CamperMaterialSpec(color: c, roughness: 0.78, clearCoat: 0.1, clearCoatRoughness: 0.8, texture: .linenSlub)
        case .leather(let c): return CamperMaterialSpec(color: c, roughness: 0.5, clearCoat: 0.25, clearCoatRoughness: 0.4, texture: .leather)
        case .cotton(let c): return CamperMaterialSpec(color: c, roughness: 0.96, texture: .weave)
        case .brass: return CamperMaterialSpec(color: 0xC9A66B, metalness: 1, roughness: 0.28)
        case .agedBrass: return CamperMaterialSpec(color: 0xA88A55, metalness: 0.9, roughness: 0.45, texture: .castIron)
        case .iron: return CamperMaterialSpec(color: 0x2A2B2D, metalness: 0.7, roughness: 0.5)
        case .castIron: return CamperMaterialSpec(color: 0x1E1F21, metalness: 0.55, roughness: 0.7, texture: .castIron)
        case .chrome: return CamperMaterialSpec(color: 0xC9CCD0, metalness: 1, roughness: 0.12)
        case .enamel(let c): return CamperMaterialSpec(color: c, roughness: 0.22, clearCoat: 0.8, clearCoatRoughness: 0.12, texture: .enamelChip)
        case .ceramic(let c): return CamperMaterialSpec(color: c, roughness: 0.3, clearCoat: 0.7, clearCoatRoughness: 0.15)
        case .terracotta: return CamperMaterialSpec(color: 0xA8573A, roughness: 0.9, texture: .castIron)
        case .glass:
            // 昼は薄い硝子で外の景色が見える。夜は暗い硝子（外の車の運転席ガラスと同じ考え方）——
            // 明るい色のまま clearCoat を残すと、窓が白い板に見えて夜が壊れる（2026-10-19 owner）
            return CamperMaterialSpec(color: night ? 0x0A0C10 : 0xDDE6EA, roughness: night ? 0.12 : 0.04,
                                      clearCoat: night ? 0.35 : 1, clearCoatRoughness: night ? 0.2 : 0.02,
                                      opacity: night ? 0.55 : 0.25, doubleSided: true)
        case .frameGlass:
            // 額の表。窓の硝子を使うと、夜は暗い膜・昼は白い板になって、飾った写真が見えない（2026-10-19 owner）。
            // 両面の硝子として描くと膜になって奥の印画が消えるので、薄い膜のまま奥行きは書かない
            // 2026-10-21（Mac run 605）: 粗さ 0.4 だと、透かしても周りの光の映りがぼけて面全体に白い膜が掛かり、
            // 額の中の写真・駅の時計の文字盤が白い板に見えた（物理の映りは透明度で薄まらない）。映りは鋭く、照りの層は無し
            // 2026-10-21（owner の実機: 写真を飾っても額の中が真っ白）: 物理の光の透明は SceneKit では効かず（硝子の球と同じ・
            // run 625〜636）、明るい硝子の板が印画の手前を不透明に覆っていた。光を受けない「足す光」のごく暗い膜にする
            return CamperMaterialSpec(color: 0x0E0F10, roughness: 1, additive: true)
        case .milkGlass:
            // 夜の乳白硝子は抑えめ（0.5→0.28）。白く飛ぶと天井の板が昼の蛍光灯に見える
            return CamperMaterialSpec(color: 0xF2EEE6, roughness: 0.28, clearCoat: 0.45, opacity: night ? 1 : 0.92,
                                      emission: night ? 0xE8C090 : nil, emissionIntensity: night ? 0.28 : 0,
                                      emissionTexture: night ? .lampFace : nil)
        case .shade(let c):
            // 布の笠: 夜は内の電球の光が布を透ける（織り目のむら）。面全体を飛ばさない
            return CamperMaterialSpec(color: c, roughness: 0.9, emission: night ? CamperMaterials.mix(c, 0xE8A868, 0.4) : nil,
                                      emissionIntensity: night ? 0.26 : 0, emissionTexture: night ? .linenSlub : nil,
                                      texture: .linenSlub, doubleSided: true)
        case .bulb:
            return CamperMaterialSpec(color: 0xF6EBD6, roughness: 0.18, clearCoat: 0.8, opacity: night ? 1 : 0.7,
                                      emission: night ? 0xE8B070 : nil, emissionIntensity: night ? 0.42 : 0,
                                      emissionTexture: night ? .lampFace : nil)
        case .fire:
            return CamperMaterialSpec(color: 0x5A1A0A, roughness: 0.8, emission: 0xFF7A2E, emissionIntensity: night ? 1.0 : 0.6,
                                      emissionTexture: .flame)
        case .mica:
            return CamperMaterialSpec(color: 0x2A1A10, roughness: 0.1, clearCoat: 1, clearCoatRoughness: 0.05,
                                      emission: 0xFF8A3C, emissionIntensity: night ? 0.7 : 0.35, emissionTexture: .flame)
        case .rush: return CamperMaterialSpec(color: 0xC9C08A, roughness: 0.8, texture: .rush)
        case .rushEdge: return CamperMaterialSpec(color: 0x1E1E20, roughness: 0.85, texture: .weave)
        case .wicker: return CamperMaterialSpec(color: 0xB8925E, roughness: 0.8, texture: .wicker)
        case .rope: return CamperMaterialSpec(color: 0xD8C8A6, roughness: 0.95, texture: .rope)
        case .leaf: return CamperMaterialSpec(color: 0x4E7A3A, roughness: 0.55, clearCoat: 0.3, texture: .foliage, doubleSided: true)
        case .soil: return CamperMaterialSpec(color: 0x3A2A1E, roughness: 1)
        case .paper: return CamperMaterialSpec(color: 0xF2EEE4, roughness: 0.8)
        case .mat: return CamperMaterialSpec(color: 0xF6F3EC, roughness: 0.85, texture: .matBoard)
        case .dial: return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.4, clearCoat: 0.5, texture: .clockDial)
        case .photo: return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.35, clearCoat: 0.4, clearCoatRoughness: 0.2, texture: .photoPlaceholder)
        case .runner: return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.97, texture: .runnerWeave)
        case .ovalRug: return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.97, texture: .ovalRings)
        case .floorFinish(let k): return floorSpec(k)
        case .wallFinish(let k): return wallSpec(k)
        case .curtain(let c):
            // 昼は窓の光が布を透ける（明るい側だけ少し）、夜は室内の灯りを受ける布
            return CamperMaterialSpec(color: c, roughness: 0.95, emission: night ? nil : CamperMaterials.mix(c, 0xFFFFFF, 0.5),
                                      emissionIntensity: night ? 0 : 0.12, emissionTexture: night ? nil : .linenSlub,
                                      texture: .linenSlub, doubleSided: true)
        case .countertop: return CamperMaterialSpec(color: 0xD9D2C4, roughness: 0.28, clearCoat: 0.6, clearCoatRoughness: 0.15, texture: .cork)
        case .cabinet(let c): return CamperMaterialSpec(color: c, roughness: 0.6, clearCoat: 0.3, texture: .furnitureGrain)
        case .sinkSteel: return CamperMaterialSpec(color: 0xB9BDC2, metalness: 1, roughness: 0.3, texture: .brushed)
        case .skin(let c): return CamperMaterialSpec(color: c, roughness: 0.35, clearCoat: 1, clearCoatRoughness: 0.08)
        case .insulation: return CamperMaterialSpec(color: 0xD8C69A, roughness: 1, texture: .cork)
        case .trim: return CamperMaterialSpec(color: CamperRoomWood.oak.color, roughness: 0.55, clearCoat: 0.3, texture: .furnitureGrain)
        case .windowRubber: return CamperMaterialSpec(color: 0x18181A, roughness: 0.8)
        case .windowView:
            // 光を受けない景色（窓の外）。夜は夜の絵
            return CamperMaterialSpec(color: 0xFFFFFF, texture: night ? .windowNight : .windowDay, unlit: true)
        case .paperColor(let c): return CamperMaterialSpec(color: c, roughness: 0.85, texture: .linenSlub, doubleSided: true)
        case .tintedGlass(let c):
            return CamperMaterialSpec(color: c, roughness: 0.05, clearCoat: 1, clearCoatRoughness: 0.03, opacity: 0.55, doubleSided: true)
        case .mapPrint: return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.8, texture: .mapPrint)
        case .mirror:
            return CamperMaterialSpec(color: 0xFFFFFF, roughness: 0.18, clearCoat: 1, clearCoatRoughness: 0.03,
                                      texture: night ? .mirrorNight : .mirrorDay)
        case .clearGlass:
            // 透明の硝子は拡散の色をほとんど持たない（白い拡散だと run 605 で硝子の球・瓶が白い陶器に見えた）。映りの照りで硝子に見せる
            // 2026-10-21（owner「家具ぶっ壊れてる」・Mac run 622 の 96e）: 硝子の球の吊り鉢が中の地形も植物も見えない灰色の玉
            // （夜は半分黒い玉）に描かれた。既定の「硝子の殻」（両面・奥行きを書く）だと、手前の面が奥行きを書いて中身を隠し、
            // 照りの層（clearCoat）の映りは透明度で薄まらないので面全体が膜になる。額の硝子（`.frameGlass`）と同じく、
            // 奥行きは書かず照りの層も無しで、鋭い映りだけで硝子に見せる
            return CamperMaterialSpec(color: 0x8C969A, roughness: 0.03, opacity: night ? 0.16 : 0.12, doubleSided: true,
                                      glassShell: false)
        case .globeGlass:
            // 2026-10-21: 物理の光の透明（`opacity`）では、どの値でも球が不透明な玉に描かれた（Mac run 625: 灰色の玉・夜はクリーム色に
            // 黒い三日月、run 632: 拡散を黒にすると黒い玉、run 636: 壁・中身の後に描いても黒い玉＝順番ではない）。平らな戸の硝子は透けるのに、
            // 丸く閉じた硝子だけ奥が消える——SceneKit の物理の光は透明度で映りを薄めず、球では映りが面全体に出る。
            // 球は光を受けない「足す光」にする（灯りの溜まり・炎と同じ。下の色を隠さず、少し明るくするだけ）。映りは別の筋（`.globeGlint`）
            return CamperMaterialSpec(color: night ? 0x0B0C0D : 0x15191C, roughness: 1, additive: true)
        case .globeGlint:
            return CamperMaterialSpec(color: night ? 0x3A3228 : 0x6A757C, roughness: 1, additive: true)
        case .silhouette: return CamperMaterialSpec(color: 0x050505, roughness: 1, unlit: true)
        }
    }
}
