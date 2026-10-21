import Foundation

/// キャンピングカーの素材の名前（網の束ごと・部品ごとに付ける）。値は `CamperMaterialSpec`
enum CamperMaterial: Hashable, Sendable {
    case paint, cap, deep, roof, under, well, reveal
    case pinstripe, pinstripeDark
    case glass, lens, lensAmber, red, amber, lamp
    /// 灯りの奥の反射板（メッキのお椀）と、消えている電球
    case reflector, bulbOff
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
    /// 住む所の窓のガラス（夜は室内の灯りでほのかに光る）。運転席のガラスは `.glass`（灯りが無いので暗い）
    case glassLit
    /// 夜は灯り（`.lamp`）、昼と雪は `base`（電球・提灯・ランプの笠）。時刻で組み直さず、材質の値だけ替えるため
    indirect case byNight(CamperMaterial)
    /// 夜、窓と扉の口から地面へこぼれる灯り（足し合わせる光の溜まり・影を落とさない）
    case glowPool
    /// 焚き火・ランタンの足元の溜まり（外の火は室内灯より赤い）
    case firePool
    /// 炎（形のある舌。下が白に近い黄、上へ橙・赤へ透ける。足し合わせる光）
    case flame
    /// ランタンの硝子（透明の円筒。中の炎が透ける）
    case lanternGlass
    /// 窓の奥の室内の明かり（カーテンのすぐ内側の面。むらのある 2700K の光を足す。ガラス越しに見える）
    case windowGlow
    /// 窓から漏れる光のにじみ（ガラスの外の、窓より一回り大きい面。縁が透ける丸いグラデーション・足す光 0.3 ほど）
    case windowHalo
    /// とおまわり号の中の家具と部屋の素材（2026-10-19・`CamperRoomMaterials`）
    case room(CamperRoomMaterial)
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
    /// 光る面の明暗の絵（反射板の輪・プリズムの筋・布の織り目）。一色の平らな光にしない（2026-10-19 owner「発光の仕方ひどい」）
    var emissionTexture: CamperTextureKind?
    var texture: CamperTextureKind?
    var doubleSided = false
    /// 不透明度が 1 未満のとき、薄い硝子として両面を描き奥行きも書く。額の表は false（奥の写真を膜で隠さない）
    var glassShell = true
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
    /// 真ん中が明るく外へ消える丸（灯りの溜まり・ガウスでなめらかに）
    case glow
    /// 点いた電球・燠・入口の灯りの覆いの光る面の明暗（真ん中の芯・輪 2・縁へ暗く。一色の平らな光にしない）
    case lampFace
    /// 尾灯・方向指示のレンズの裏のプリズムの粒（四角い角錐の並び。光の向きで面ごとに明暗が出る）
    case prism
    /// 炎の色（下は白に近い黄、上へ橙・赤、先は透ける）
    case flame
    /// 窓越しの室内の明かり（真ん中が明るく縁へ落ちる・両側のカーテンのひだ・下半分に家具の影の帯）
    case roomGlow
    // とおまわり号の中（2026-10-19・`CamperRoomTextures`）
    case planks, chevron, herringbone, checkerTiles, cork
    case boards, birchPly, darkBoards, wallpaperStripe
    case leather, linenSlub, knit, rush, wicker, rope, ovalRings, runnerWeave, enamelChip, castIron, foliage
    case clockDial, windowDay, windowNight, matBoard, photoPlaceholder, wornWood, mapPrint
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
            // 運転席・鏡・瓶のガラス。夜も光らない（run 532: フロントガラスが内から光る板に見えた）
            return CamperMaterialSpec(color: night ? 0x0A0C10 : 0x10161C, roughness: 0.05, opacity: night ? 0.7 : 0.62,
                                      doubleSided: true)
        case .glassLit:
            // 住む所の窓（2026-10-19 作り直し・owner「夜の発光の仕方ひどい」）。ガラスは**光らない**——一色の emission で塗ると
            // オレンジの平らな板になった。夜は板どおり薄い（不透明度 0.38）暗い硝子で、室内の灯りに照らされた
            // カーテン・内壁・家具が透けて見え、表には外の映り込み（月・地平線）が乗る
            // 2026-10-19（Mac night3）: 0.38 では奥の明かりが暗い四角にしか見えなかった。夜だけ薄くする
            // （昼は板どおり 0.62）。2026-10-20: 0.22 だと windowGlow が平らな黄の板に見えた → 0.32 で硝子感を残す
            return CamperMaterialSpec(color: night ? 0x2A2016 : 0x10161C, roughness: 0.04, clearCoat: night ? 1 : 0,
                                      clearCoatRoughness: 0.03, opacity: night ? 0.32 : 0.62, doubleSided: true)
        // 灯りのレンズ（2026-10-19 作り直し・2 回目）。owner「テールランプとかの灯りが不自然すぎる」:
        // 2026-10-19 判断: キャンプ場に停めて人が中にいる場面なので、前照灯・尾灯・方向指示・車幅灯は**夜も消えている**
        // （emission 無し）。夜に見えるのは、周りの灯り（焚き火・窓・ランタン・入口の灯り・月）がレンズに映る艶だけ。
        // 光らないレンズを白い平らな円盤に見せないため、レンズは**透ける硝子**（色の透け・低い粗さ・clearCoat）で、
        // 奥の反射板（`.reflector`）と電球が透けて見える。テールは濃い赤・方向指示は橙・前照灯は透明
        case .lens:
            // 前照灯・後退灯の透明の硝子（ほぼ透明。奥のメッキの反射板が見え、表に周りが映る）
            return CamperMaterialSpec(color: 0xEEF3F6, roughness: 0.02, clearCoat: 1, clearCoatRoughness: 0.02, opacity: 0.22)
        case .lensAmber:
            // 補助灯の黄色の硝子（半ば透け、奥の反射板が見える）
            return CamperMaterialSpec(color: 0xE0A63A, roughness: 0.03, clearCoat: 1, clearCoatRoughness: 0.02, opacity: 0.5)
        case .red:
            // 尾灯の濃い赤の透け。表のプリズムの粒（`.prism`）で光の当たり方にむらが出る（一色の赤い板にしない）
            return CamperMaterialSpec(color: 0x7A0F0C, roughness: 0.06, clearCoat: 1, clearCoatRoughness: 0.03, opacity: 0.84,
                                      texture: .prism)
        case .amber:
            // 方向指示・車幅灯の橙の透け（同じプリズムの粒）
            return CamperMaterialSpec(color: 0xC8641A, roughness: 0.06, clearCoat: 1, clearCoatRoughness: 0.03, opacity: 0.84,
                                      texture: .prism)
        case .reflector:
            // レンズの奥の反射板（磨いたメッキ・凹んだお椀）。周りの空と灯りを映す
            return CamperMaterialSpec(color: 0xD9DCDF, metalness: 1, roughness: 0.08)
        case .bulbOff:
            // 消えている電球（すりガラス）。真っ白にしない
            return CamperMaterialSpec(color: 0xCFCAC0, roughness: 0.3, clearCoat: 0.8, clearCoatRoughness: 0.05)
        case .lamp:
            // 電球（室内 2700K 前後）。小さいので強すぎると光の粒が散る（run 529）。芯が明るく縁へ落ちる
            return CamperMaterialSpec(color: 0xFFD890, roughness: 0.3, emission: night ? 0xFFC27A : nil,
                                      emissionIntensity: night ? 0.95 : 0, emissionTexture: night ? .lampFace : nil)
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
            // 夜は室内の灯りを受けて柔らかく光る布（透ける光は織り目の絵で、むらのある弱い光にする）
            // 2026-10-19（Mac run 547）: 外から見えるのはカーテンの裏（灯りに背を向けた面）なので、照らされても暗かった。
            // 布を透ける光をこの弱い光で出す（0.16 では窓が暗いまま。むらは織り目の絵）
            return CamperMaterialSpec(color: night ? 0xF2CC92 : 0xD8CCB4, roughness: 0.95, emission: night ? 0xFFB46B : nil,
                                      emissionIntensity: night ? 0.45 : 0, emissionTexture: night ? .weave : nil,
                                      texture: .weave, doubleSided: true)
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
            // 燠（薪の下の赤い熱）。炎は別の形（`.flame`）
            return CamperMaterialSpec(color: 0x5A1A0A, roughness: 0.8, emission: 0xFF5A1E, emissionIntensity: night ? 0.9 : 0.45,
                                      emissionTexture: .lampFace)
        case .silhouette: return CamperMaterialSpec(color: 0x050505, roughness: 1, unlit: true)
        case .byNight(let base): return spec(night ? .lamp : base, paint: paint, mood: mood)
        // 地面の溜まり（足す光）。色の明るさがそのまま足す強さ。板 pools の色と不透明度に寄せる
        // 2026-10-20 owner「光の表現が酷い」: 溜まりが硬い円・帯に見えたので暗く・芯を抑える
        case .glowPool: return CamperMaterialSpec(color: 0x2A1C10, texture: .glow, additive: true)
        case .firePool: return CamperMaterialSpec(color: 0x3A1808, texture: .glow, additive: true)
        // 炎は貼り絵そのものの色（白で掛ける）。昼は薄く
        case .flame: return CamperMaterialSpec(color: night ? 0xE6E6E6 : 0x8C8C8C, texture: .flame, additive: true)
        // 窓越しの室内の明かり（2700K）。足す光なので縁が黒く落ちる絵で板に見えない。
        // 2026-10-20 実機・網描き: 明るい一色は平らな黄の板 → 0x9A6838 でむら（roomGlow）を残す
        case .windowGlow: return CamperMaterialSpec(color: 0x9A6838, texture: .roomGlow, additive: true)
        case .windowHalo: return CamperMaterialSpec(color: 0x2A1C10, texture: .glow, additive: true)
        case .lanternGlass:
            return CamperMaterialSpec(color: 0xF1E3C4, roughness: 0.05, clearCoat: 1, clearCoatRoughness: 0.03, opacity: 0.22,
                                      doubleSided: true)
        case .room(let r): return CamperRoomMaterials.spec(r, mood: mood)
        }
    }

    /// 太陽・月（平行光）の来る向き（画面基準・上が +Y・手前が +Z）と強さと色。
    ///
    /// 2026-10-19 判断（Mac run 563 の 95k）: 夜の月は前は (0.45, 0.6, 0.55)・260 で、手前（カメラの側）から当たっていた。
    /// 車は回る台の上なので、後ろへ回すと後ろの壁が月を真正面から受け、夜なのに一面まっ白に見えた。月は上と少し奥
    /// から当て（手前を向く面には当たらない・屋根と縁に青白い光が乗るだけ）、強さも下げる。手前の面は焚き火・窓・
    /// 入口の灯りと、弱い環境光で読ませる
    static func sun(_ mood: CamperMood) -> (from: CV3, intensity: Double, color: UInt32) {
        switch mood {
        case .night: return (CV3(0.3, 0.85, -0.3), 150, 0x9FB4DC)
        case .snow: return (CV3(-0.18, 0.72, 0.62), 1000, 0xFFF4E2)
        case .day: return (CV3(-0.18, 0.72, 0.62), 1200, 0xFFF4E2)
        }
    }

    /// どの面にも一様に当たる明るさ（周りの光 `lightingEnvironment` の強さと、環境光 ambient の強さ）。
    ///
    /// 2026-10-21 判断（Mac run 577 の 95k「夜の後ろの壁がクリーム色のまま明るい」）: 画面写真の輝度を測ると、後ろの
    /// クリーム色の面は 57（昼の 95m は 236〜253）で、95b の横のクリーム色の面（50〜80）とほぼ同じだった——後ろだけに
    /// 当たる光は無い（外の灯りは届かず・月は当たらない向き・形の向きの食い違いも 0 件）。どの面も、この一様な明るさ
    /// （環境光 60・周りの光 0.14）で白に近いクリーム色が持ち上がり、暗い地の上で後ろの大きな面が目立っていた。
    /// 灯りの当たらない面がほぼ暗くなるよう、夜は半分ほどに下げる（手前の面は焚き火・窓・入口の灯りで読ませる）
    static func fill(_ mood: CamperMood) -> (environment: Double, ambient: Double) {
        switch mood {
        case .night: return (0.07, 25)
        case .snow: return (1.45, 0)
        case .day: return (1.35, 0)
        }
    }

    /// 灯りの当たらない面のおよその明るさ（0〜1・素材の色 × 一様な明るさ）。環境光は 1000 で 1、周りの光は空の平均の色
    static func unlitFaceLevel(_ m: CamperMaterial, paint: UInt32, mood: CamperMood) -> Double {
        let c = CamperTextures.rgb(spec(m, paint: paint, mood: mood).color)
        let albedo = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
        let s = sky(mood)
        let skyAvg = [s.top, s.horizon, s.groundNear, s.groundFar].map { v -> Double in
            let k = CamperTextures.rgb(v)
            return 0.2126 * k.0 + 0.7152 * k.1 + 0.0722 * k.2
        }.reduce(0, +) / 4
        let f = fill(mood)
        return albedo * (f.ambient / 1000 + f.environment * skyAvg)
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
    var fadeStart = 1.9
    var fadeEnd = 4.8

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
