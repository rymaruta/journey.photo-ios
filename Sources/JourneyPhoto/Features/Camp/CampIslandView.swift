import SwiftUI
import UIKit

/// 切り絵の紙の表の絵を渡す口（切り絵の id・層 → 画像）
typealias CampCutoutImages = (String, Int) -> UIImage?

/// 16 進の色（板の値をそのまま使う）
enum CampPalette {
    static func color(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255).opacity(alpha)
    }
}

/// キャンプ場の島の 1 枚（板 Camp の部品）。空（撮った写真の色・太陽・星・雲・島の下の霧）は SwiftUI で描き、
/// 島は SceneKit（`CampSceneView`）で描いて重ねる。舞う花びら・雪・落ち葉は島の上に重ねる（板の `fall`）。
///
/// - 全体の図（`focus == .all`）だけ空を出す。部品に寄った図は板の部品の板と同じ、黒地に淡い光の丸
/// - 読み上げは板の `aria`（「キャンプ場の島（夏・夕）。浮かぶ島に…」）。「増やす・減らす」で 30° ずつ回せる
struct CampIslandView: View {
    let options: CampSceneOptions
    var angle: CampAngle
    var zoom: Double = 1
    var interactive = true
    /// 写真から取った空の色（上・中・下）。無ければ板の空
    var skyColors: [UInt32]? = nil
    /// 部品に寄った図の地の光の色
    var glow: UInt32 = 0x16140F
    var cornerRadius: Double = 18
    var justPlaced: String? = nil
    var images: CampCutoutImages = { _, _ in nil }
    var onAngle: (CampAngle) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width), h = Double(geo.size.height)
            ZStack {
                if options.focus == .all {
                    CampSkyView(lighting: CampLighting.of(time: options.time, season: options.season), angle: angle,
                                skyColors: skyColors, stage: options.stage, zoom: zoom, width: w, height: h)
                } else {
                    RadialGradient(colors: [CampPalette.color(glow), Color.black], center: UnitPoint(x: 0.5, y: 0.4),
                                   startRadius: 0, endRadius: CGFloat(max(w, h) * 0.72))
                }
                scene
                if options.focus == .all {
                    CampFallView(season: options.season, width: w, height: h)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: options.focus == .all ? cornerRadius : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CampIslandText.description(options))
        .accessibilityHint(interactive ? CampIslandText.rotateHint : "")
        .accessibilityAdjustableAction { direction in
            guard interactive else { return }
            switch direction {
            case .increment: onAngle(CampAngle(rx: angle.rx, ry: angle.ry + 30))
            case .decrement: onAngle(CampAngle(rx: angle.rx, ry: angle.ry - 30))
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var scene: some View {
        #if canImport(SceneKit)
        CampSceneView(options: options, angle: angle, zoom: zoom, interactive: interactive, reduceMotion: reduceMotion,
                      justPlaced: justPlaced, images: images, onAngle: onAngle)
            // 回せない島（育ちの札の中の小さな島）は指を外へ通す（札のボタンが押せるように）
            .allowsHitTesting(interactive)
        #else
        Color.clear
        #endif
    }
}

/// 島の読み上げの文
enum CampIslandText {
    static func description(_ o: CampSceneOptions) -> String {
        let name: String
        switch o.focus {
        case .all: name = L("キャンプ場の島", "Campsite island")
        case .island: name = L("島（芝・土の層・岩の底）", "Island (grass, soil layers, rock base)")
        case .tent: name = L("テント", "Tent")
        case .fire: name = L("焚き火", "Campfire")
        case .trees: name = L("木", "Trees")
        case .gear: name = L("道具", "Gear")
        case .cutout: name = L("写真の切り絵の箱庭", "Photo cutout diorama")
        }
        let when = L("（\(o.season.name)・\(o.time.name)）", " (\(o.season.name), \(o.time.name))")
        return name + when + L("。浮かぶ島に芝と土の層、テント、焚き火、針葉樹、撮った写真を 3 枚に切った紙の箱庭、椅子や保冷箱",
                               ". A floating island with grass and soil layers, a tent, a campfire, conifers, a paper diorama cut from your photo into three layers, a chair and a cooler")
    }

    static var rotateHint: String { L("指で回すと、島の裏の岩と、焚き火の向こうが見えます", "Drag to see the rock below and the far side of the fire") }
}

/// 空（板 Camp の `sky dressing`）: 3 色の空・太陽（月）・星・雲・島の下の霧
struct CampSkyView: View {
    let lighting: CampLighting
    let angle: CampAngle
    var skyColors: [UInt32]?
    let stage: CampStage
    let zoom: Double
    let width: Double
    let height: Double

    /// 写真の空は 70% だけ混ぜる（暗い写真でも島が沈まない・2026-10-18 判断）
    private var sky: [UInt32] {
        guard let photo = skyColors, photo.count == 3 else { return lighting.sky }
        return zip(lighting.sky, photo).map { CampMaterials.mix($0, $1, 0.7) }
    }

    var body: some View {
        let s = sky
        let sun = CampOrbit.sunOnScreen(light: lighting.sun, angle: angle, width: width, height: height)
        let sunR = lighting.stars ? 30.0 : 90.0
        let scale = CampOrbit.scale(focus: .all, stage: stage, zoom: zoom, width: width, height: height)
        let mistY = CampOrbit.project(CampVec3(0, 120, 0), angle: angle, target: CampFocus.all.preset.target, scale: scale,
                                      width: width, height: height).y
        ZStack {
            LinearGradient(stops: [Gradient.Stop(color: CampPalette.color(s[0]), location: 0),
                                   Gradient.Stop(color: CampPalette.color(s[1]), location: 0.55),
                                   Gradient.Stop(color: CampPalette.color(s[2]), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            if lighting.stars {
                ForEach(CampSkyDressing.stars(width: width, height: height), id: \.id) { star in
                    Circle()
                        .fill(Color.white.opacity(star.opacity))
                        .frame(width: CGFloat(star.r * 2), height: CGFloat(star.r * 2))
                        .position(x: CGFloat(star.x), y: CGFloat(star.y))
                }
            }
            if sun.visible {
                Circle()
                    .fill(RadialGradient(stops: [Gradient.Stop(color: CampPalette.color(lighting.sunCore), location: 0),
                                                 Gradient.Stop(color: CampPalette.color(lighting.sunCore, 0.9), location: 0.12),
                                                 Gradient.Stop(color: CampPalette.color(lighting.sunHalo, 0.35), location: 0.3),
                                                 Gradient.Stop(color: CampPalette.color(lighting.sunHalo, 0), location: 1)],
                                         center: .center, startRadius: 0, endRadius: CGFloat(sunR)))
                    .frame(width: CGFloat(sunR * 2), height: CGFloat(sunR * 2))
                    .position(x: CGFloat(sun.x), y: CGFloat(sun.y))
            }
            ForEach(CampSkyDressing.clouds(width: width, height: height), id: \.id) { cloud in
                Capsule()
                    .fill(CampPalette.color(lighting.stars ? 0x1A2638 : (lighting.mist == 0xF0B07A ? 0xF2B27A : 0xFFFFFF)))
                    .frame(width: CGFloat(cloud.rx * 2), height: CGFloat(cloud.ry * 2))
                    .blur(radius: 6)
                    .position(x: CGFloat(cloud.x), y: CGFloat(cloud.y))
            }
            .opacity(lighting.stars ? 0.5 : 0.7)
            Rectangle()
                .fill(EllipticalGradient(colors: [CampPalette.color(lighting.mist, 0.75), CampPalette.color(lighting.mist, 0)]))
                .frame(width: CGFloat(width * 0.84), height: 68)
                .position(x: CGFloat(width / 2), y: CGFloat(mistY))
        }
        .accessibilityHidden(true)
    }
}

/// 空の飾り（星 46・雲 5・舞うもの 30）。板と同じ乱数（seed × 16807）で、何度描いても同じ所
enum CampSkyDressing {
    struct Star { let id: Int; let x: Double; let y: Double; let r: Double; let opacity: Double }
    struct Cloud { let id: Int; let x: Double; let y: Double; let rx: Double; let ry: Double }
    struct Flake { let id: Int; let x: Double; let y: Double; let rx: Double; let ry: Double; let angle: Double; let opacity: Double; let color: UInt32 }

    static func stars(width: Double, height: Double) -> [Star] {
        var r = CampRandom(29)
        return (0..<46).map { i in
            Star(id: i, x: r.next() * width, y: r.next() * height * 0.7, r: 0.4 + r.next() * 0.9, opacity: 0.4 + r.next() * 0.6)
        }
    }

    static func clouds(width: Double, height: Double) -> [Cloud] {
        var r = CampRandom(31)
        return (0..<5).map { i in
            Cloud(id: i, x: r.next() * width, y: height * (0.12 + r.next() * 0.3), rx: 40 + r.next() * 60, ry: 5 + r.next() * 6)
        }
    }

    static func fall(season: CampSeason, width: Double, height: Double) -> [Flake] {
        guard season != .summer else { return [] }
        var r = CampRandom(37)
        return (0..<30).map { i in
            let color: UInt32 = season == .winter ? 0xFFFFFF : (season == .spring ? 0xF6C8D6 : [0xD9772E, 0xB9452A, 0xE6A63A][i % 3])
            return Flake(id: i, x: r.next() * width, y: r.next() * height, rx: season == .winter ? 1.3 : 2,
                         ry: season == .winter ? 1.3 : 1, angle: r.next() * 180, opacity: 0.5 + r.next() * 0.5, color: color)
        }
    }
}

/// 舞う花びら（春）・落ち葉（秋）・雪（冬）
struct CampFallView: View {
    let season: CampSeason
    let width: Double
    let height: Double

    var body: some View {
        ZStack {
            ForEach(CampSkyDressing.fall(season: season, width: width, height: height), id: \.id) { f in
                Capsule()
                    .fill(CampPalette.color(f.color, f.opacity))
                    .frame(width: CGFloat(f.rx * 2), height: CGFloat(f.ry * 2))
                    .rotationEffect(.degrees(f.angle))
                    .position(x: CGFloat(f.x), y: CGFloat(f.y))
            }
        }
        .accessibilityHidden(true)
    }
}
