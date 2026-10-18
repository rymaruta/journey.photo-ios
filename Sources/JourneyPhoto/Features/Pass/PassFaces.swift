import SwiftUI

// 乗車券の特別な券面（Pro・**2026-10-17 owner が確定**）。
//
// 見本は Artifact「特別な乗車券 10案」（https://claude.ai/artifact/4LjfJ456ruQtL4S66QDtCG の `project/Main.dc.html`）の
// 「· 確定」の5つ: 01 真鍮の金属板・06 大圏航路・10 箔押しの硬券・21 漆と蒔絵・26 型押しの革。寸法はモックの
// 300×430 の座標のまま置く。
//
// 🔴 **設定した写真は一切加工しない**（owner の決まり）。写真は `PassFacePhoto` だけが描き、枠に収めて角を丸める
// だけ。光・映り込み・金粉などの層は**すべて写真より下**に重ね、写真の上には何も重ねない（モックは光が写真の上も
// 通るが、ここでは写真の窓の外だけを走る）。`PassFaceWiringTests` が書き方を見張る。
//
// 真鍮・箔は黒（暗い地）の上だけ。01 は真鍮の面に墨の字（accent-fill ＋ 墨の組み合わせ）。
// 文字と地の比は `PassFacePalette.pairs` を `PassFaceContrastTests` で測る。

/// 券面の色（`PassFacePalette` の 16 進の値から）
@MainActor
enum PassFaceColor {
    static func of(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255).opacity(opacity)
    }

    /// 箔（10・21・26）。傾けると明るい所が字の上を左右に滑る（モック `foil`・暗い所は `foilDark`）
    static func foil(_ light: PassFaceLight.Point) -> LinearGradient {
        let p = PassFaceLight.foilCenter(light)
        // モックの 100deg・p±50% の幅。0〜1 の外は端の色が伸びる
        let band = PassFaceLight.bandPoints(center: p, half: 0.5, cssDegrees: 100)
        return LinearGradient(stops: [
            Gradient.Stop(color: of(PassFacePalette.foilDark), location: 0),
            Gradient.Stop(color: of(PassFacePalette.foilMid), location: 0.3),
            Gradient.Stop(color: of(PassFacePalette.foilLight), location: 0.5),
            Gradient.Stop(color: of(PassFacePalette.foilMid), location: 0.7),
            Gradient.Stop(color: of(PassFacePalette.foilDark), location: 1),
        ], startPoint: UnitPoint(x: band.start.x, y: band.start.y), endPoint: UnitPoint(x: band.end.x, y: band.end.y))
    }
}

/// 🔴 **写真の窓**（全ての券面が使う・2026-10-17）。owner の決まり「設定した写真は一切加工しない」:
/// 枠（幅・高さ）に収めて角を丸めるだけ。**色・形・反転・映り込み・ぼかし・合成・透明度を付けない**
/// （`PassFaceWiringTests.testPhotoWindowIsUntouched` が、下の印の間の書き方を見張る）
struct PassFacePhoto: View {
    let photo: Photo?
    let width: CGFloat
    let height: CGFloat
    var corner: CGFloat = 0
    /// 写真を押した（束の画面: 全面で見る）
    var onTap: (() -> Void)? = nil

    var body: some View {
        // PHOTO-WINDOW-BEGIN
        let window = Color.clear
            .frame(width: width, height: height)
            .overlay {
                if let photo {
                    DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                           aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                           alignment: photo.gridAlignment)
                } else {
                    WebTheme.surface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
        // PHOTO-WINDOW-END
        if let onTap {
            window
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        } else {
            window
        }
    }
}

/// 特別な券面の入れ物: 傾き（`PassTiltMotion`）を**光が動く券面が出ている間だけ**読み、光の位置を決めて描く。
/// 「視差効果を減らす」・背面では読まない（光は正面のまま）。読むかどうかは裏と同じ `PassTiltHold`
struct PassSpecialFace: View {
    let face: PassTicketFace
    var onPhotoTap: (() -> Void)?
    var shine: Double?
    /// 表がいま見えているか（裏を見ている・全面の写真や Pro の案内が上にある間は false）
    var visible: Bool = true

    @ObservedObject private var tilt = PassTiltMotion.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let light = PassFaceLight.resolved(tilt: tilt.light, shine: shine, reduceMotion: reduceMotion)
        PassFaceBody(face: face, light: light, reduceMotion: reduceMotion, visible: visible, onPhotoTap: onPhotoTap)
            .modifier(PassTiltHold(style: face.style, visible: visible))
    }
}

/// 傾きを読むかを決め、読む間だけ `PassTiltMotion` を握る（表の `PassSpecialFace`・裏の `PassSpecialBack` が使う）。
/// 表と裏が同時に握っても、数えて持つ（`PassTiltMotion.hold`）ので、両方が離すまで止めない
struct PassTiltHold: ViewModifier {
    let style: PassTicketFaceStyle
    /// その面がいま見えているか
    let visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                appeared = true
                updateHold()
            }
            .onDisappear {
                appeared = false
                updateHold()
            }
            // 前面・「視差効果を減らす」・券面・見えているかが変わったら、読むかを決め直す
            .onChange(of: scenePhase) { _, _ in updateHold() }
            .onChange(of: reduceMotion) { _, _ in updateHold() }
            .onChange(of: style) { _, _ in updateHold() }
            .onChange(of: visible) { _, _ in updateHold() }
    }

    /// 傾きを読むか（`PassFaceLight.readsTilt`）
    private func updateHold() {
        let wants = PassFaceLight.readsTilt(appeared: appeared, visible: visible, foreground: scenePhase == .active,
                                            style: style, reduceMotion: reduceMotion)
        guard wants != holding else { return }
        holding = wants
        if wants { PassTiltMotion.shared.hold() } else { PassTiltMotion.shared.release() }
    }
}

/// 券面ごとに描き分ける（光の位置は渡されたものだけを使う）
struct PassFaceBody: View {
    let face: PassTicketFace
    let light: PassFaceLight.Point
    let reduceMotion: Bool
    var visible: Bool = true
    var onPhotoTap: (() -> Void)?

    var body: some View {
        switch face.style {
        case .mars:
            // マルス券は `PassCardFront` が描く（ここへは来ない）
            EmptyView()
        case .brassPlate:
            PassBrassPlateFace(face: face, light: light, onPhotoTap: onPhotoTap)
        case .greatCircle:
            PassGreatCircleFace(face: face, reduceMotion: reduceMotion, visible: visible, onPhotoTap: onPhotoTap)
        case .foilHard:
            PassFoilHardFace(face: face, light: light, onPhotoTap: onPhotoTap)
        case .urushi:
            PassUrushiFace(face: face, light: light, onPhotoTap: onPhotoTap)
        case .leather:
            PassLeatherFace(face: face, light: light, onPhotoTap: onPhotoTap)
        }
    }
}

// MARK: - 共通の部品

/// 字の影（彫り込み・箔押しの縁）。半径 0 の1本
struct PassFaceTextShadow {
    let color: Color
    let y: Double
}

/// 区間（「東京発 → フランス着」）。並べ方はマルス券と同じ `PassCardStyle.routeLayout`（矢印はいつも中央・
/// 発と着は同じ大きさ）。モックの区間の幅（260 など）と明朝 24.5 まで
struct PassFaceRoute: View {
    let face: PassTicketFace
    let width: CGFloat
    let names: AnyShapeStyle
    let marks: AnyShapeStyle
    let arrow: Color
    var shadows: [PassFaceTextShadow] = []

    static let maxSize = 24.5

    var body: some View {
        let route = PassCardStyle.routeLayout(origin: face.origin, destination: face.destination,
                                              width: Double(width), maxSize: Self.maxSize)
        return HStack(alignment: .center, spacing: 0) {
            column(face.origin, mark: PassTicket.originMark, route)
                .frame(width: CGFloat(route.columnWidth), alignment: .trailing)
            PassTicketArrow(color: arrow, lineWidth: 1.4)
                .padding(.horizontal, CGFloat(PassCardStyle.arrowGap))
            column(face.destination, mark: PassTicket.destinationMark, route)
                .frame(width: CGFloat(route.columnWidth), alignment: .leading)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
    }

    private func column(_ text: String, mark: String, _ route: PassCardStyle.RouteLayout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(PassCardStyle.markGap)) {
            if PassTicket.marksLead { markText(mark) }
            Text(text)
                .font(.custom(JPFont.displayName, fixedSize: CGFloat(route.fontSize)))
                .foregroundStyle(names)
                .lineLimit(1)
                .truncationMode(.tail)
            if !PassTicket.marksLead { markText(mark) }
        }
        .passFaceShadows(shadows)
    }

    private func markText(_ mark: String) -> some View {
        Text(mark)
            .font(.custom(JPFont.displayName, fixedSize: CGFloat(PassCardStyle.markSize)))
            .foregroundStyle(marks)
            .lineLimit(1)
            .fixedSize()
    }
}

extension View {
    /// 字の影を重ねる（彫り込み・箔の縁）。最大2本
    func passFaceShadows(_ shadows: [PassFaceTextShadow]) -> some View {
        let first = shadows.first, second = shadows.count > 1 ? shadows[1] : nil
        return self
            .shadow(color: first?.color ?? Color.clear, radius: 0, x: 0, y: first.map(\.y) ?? 0)
            .shadow(color: second?.color ?? Color.clear, radius: 0, x: 0, y: second.map(\.y) ?? 0)
    }
}

/// 「乗車券」と No. の段（明朝 15・字間 0.3em／SF 11・字間 0.12em）。読み上げでは券面の名前を添える
struct PassFaceHeadRow: View {
    let face: PassTicketFace
    let headline: String
    let head: AnyShapeStyle
    let number: AnyShapeStyle
    var numberWeight: Font.Weight = .semibold
    var shadows: [PassFaceTextShadow] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headline)
                .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.headSize))
                .tracking(PassCardStyle.headSize * PassCardStyle.headTracking)
                .foregroundStyle(head)
                .lineLimit(1)
                .passFaceShadows(shadows)
                .accessibilityLabel(face.style.spokenHeadline(headline))
            Spacer(minLength: JPSpace.xs)
            if let value = face.number {
                Text(value)
                    .font(.system(size: PassCardStyle.numberSize, weight: numberWeight).monospacedDigit())
                    .tracking(PassCardStyle.numberSize * PassCardStyle.numberTracking)
                    .foregroundStyle(number)
                    .lineLimit(1)
                    .fixedSize()
                    .passFaceShadows(shadows)
            }
        }
    }
}

/// 日付・区間・回数の3つの欄（モック: ラベル 11・値 13・上下に線・上下 7）
struct PassFaceFields: View {
    let fields: [PassTicket.Field]
    let label: Color
    let value: Color
    var valueWeight: Font.Weight = .regular
    let topLine: Color
    let bottomLine: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 1) {
                    Text(field.label)
                        .font(.system(size: PassCardStyle.fieldLabelSize))
                        .foregroundStyle(label)
                        .lineLimit(1)
                    Text(field.value)
                        .font(.system(size: PassCardStyle.fieldValueSize, weight: valueWeight).monospacedDigit())
                        .foregroundStyle(value)
                        .lineLimit(1)
                        // 欄からはみ出しそうなときだけ 12 まで（本文系の最小・マルス券と同じ）
                        .minimumScaleFactor(PassCardStyle.metaSize / PassCardStyle.fieldValueSize)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 空の欄「—」は「なし」と読む（マルス券と同じ・`PassTicket.spokenField`）
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PassTicket.spokenField(field))
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(topLine).frame(height: JPStroke.hairline).accessibilityHidden(true) }
        .overlay(alignment: .bottom) { Rectangle().fill(bottomLine).frame(height: JPStroke.hairline).accessibilityHidden(true) }
    }
}

/// 名前と「ずっと有効」の段（名前 12・ずっと有効 12 字間 0.04em・`PassCardStyle.validitySize` と同じ）
struct PassFaceFooter: View {
    let name: String
    let nameColor: Color
    var nameWeight: Font.Weight = .regular
    let validityColor: Color
    var shadows: [PassFaceTextShadow] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
            Text(name)
                .font(.system(size: PassCardStyle.metaSize, weight: nameWeight))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(PassTicket.shortValidity)
                .font(.system(size: PassCardStyle.validitySize))
                .tracking(PassCardStyle.validitySize * PassCardStyle.validityTracking)
                .foregroundStyle(validityColor)
                .lineLimit(1)
                .fixedSize()
        }
        .passFaceShadows(shadows)
    }
}

// MARK: - 動かない地紋（一度だけ作って描く。光の位置では描き直さない）

/// 地紋の形（300×430 の座標）。**一度だけ作る**——傾きで 30 回/秒描き直しても、形は作り直さない
@MainActor
enum PassFaceTextures {

    /// 決まった並びの乱数（同じ券面はいつも同じ地紋）
    struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// 01 ヘアライン（モック: 90deg に 1px 明・1px 暗の縞）
    static let hairlineLight: Path = Path { p in
        for x in stride(from: 0, to: 300, by: 2) { p.addRect(CGRect(x: x, y: 0, width: 1, height: 430)) }
    }
    static let hairlineDark: Path = Path { p in
        for x in stride(from: 1, to: 300, by: 2) { p.addRect(CGRect(x: x, y: 0, width: 1, height: 430)) }
    }

    /// 10 綿紙の細かな粒（モック: 3px おきに 1px の明るい点）
    static let paperGrain: Path = Path { p in
        for x in stride(from: 1, to: 300, by: 3) {
            for y in stride(from: 1, to: 430, by: 3) { p.addRect(CGRect(x: x, y: y, width: 1, height: 1)) }
        }
    }

    /// 21 裾の金粉（モック: 霞は裾に溜まる。細かな粒）。明るい粒と淡い粒。
    /// 2026-10-17 の Mac の画面写真で、粒が多すぎて字の上まで散っていた（モックより濃い）。
    /// 名前の行（`dustTop` より上）には置かず、裾へ向けて増やす（2026-10-17 の読み直し: 名前にかかっていた）
    static let dustTop = 350.0
    static let goldDust: (bright: Path, faint: Path) = {
        var rng = Seeded(state: 21)
        var bright = Path(), faint = Path()
        var placed = 0
        while placed < 260 {
            let x = rng.next() * 300, y = rng.next() * 430
            let t = (y - dustTop) / (430 - dustTop)
            let haze = t < 0 ? 0 : 0.2 + t * 0.8
            guard rng.next() < haze else { continue }
            let r = 0.35 + rng.next() * 0.6
            let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            if rng.next() < 0.25 { bright.addEllipse(in: dot) } else { faint.addEllipse(in: dot) }
            placed += 1
        }
        return (bright, faint)
    }()

    /// 21 の裏の平目地（金粉の散らし・2026-10-18 owner がすやり霞を外した）。`PassHirame` の 140×64 の中で、
    /// **右下の隅ほど濃く**撒く。明るい粒と淡い粒
    static let hirame: (bright: Path, faint: Path) = {
        var bright = Path(), faint = Path()
        for dot in hirameDots {
            let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
            if dot.bright { bright.addEllipse(in: rect) } else { faint.addEllipse(in: rect) }
        }
        return (bright, faint)
    }()

    /// 平目地の粒（中心・半径・明るいか）。決まった並びの乱数で、隅に近いほど置く見込みが高い（近さの3乗）
    nonisolated static let hirameDots: [(x: Double, y: Double, r: Double, bright: Bool)] = {
        var rng = Seeded(state: 5)
        var dots: [(x: Double, y: Double, r: Double, bright: Bool)] = []
        var tries = 0
        let width = 140.0, height = 64.0
        while dots.count < hirameCount, tries < 4000 {
            tries += 1
            let x = rng.next() * width, y = rng.next() * height
            let near = x / width * 0.55 + y / height * 0.45
            guard rng.next() <= near * near * near else { continue }
            let r = 0.3 + rng.next() * 0.55
            dots.append((x, y, r, rng.next() < 0.3))
        }
        return dots
    }()

    /// 平目地の粒の数
    nonisolated static let hirameCount = 90
    /// 右下の4分の1（70〜140 × 32〜64）にある粒の数（隅に寄っているかを測る）
    nonisolated static var hirameCorner: Int { hirameDots.filter { $0.x >= 70 && $0.y >= 32 }.count }

    /// 26 革のしぼ（ずらした格子に小さな粒）。光の当たる側の明るい縁と、反対の陰。
    /// 左から当てた形と右から当てた形を作り、傾きで混ぜる（`PassFaceLight.leatherFromLeft`）
    struct Grain {
        let body: Path
        let bodyAlt: Path
        let lit: Path
        let shade: Path
    }

    static let leatherFromLeft: Grain = grain(fromLeft: true)
    static let leatherFromRight: Grain = grain(fromLeft: false)

    private static func grain(fromLeft: Bool) -> Grain {
        var rng = Seeded(state: 26)
        var body = Path(), alt = Path(), lit = Path(), shade = Path()
        let step = 6.0
        let dir = fromLeft ? -1.0 : 1.0
        var row = 0
        for yy in stride(from: 0.0, through: 432, by: step) {
            let shift = row % 2 == 0 ? 0 : step / 2
            for xx in stride(from: -step, through: 304, by: step) {
                let cx = xx + shift + (rng.next() - 0.5) * 2.4
                let cy = yy + (rng.next() - 0.5) * 2.4
                let rx = 2.0 + rng.next() * 1.4, ry = 1.7 + rng.next() * 1.2
                let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
                // 光の側に 0.7 ずらした明るい縁・反対に 0.9 ずらした陰（上からも少し当てる）
                lit.addEllipse(in: rect.offsetBy(dx: dir * 0.7, dy: -0.6))
                shade.addEllipse(in: rect.offsetBy(dx: -dir * 0.9, dy: 0.8))
                if rng.next() < 0.5 { body.addEllipse(in: rect) } else { alt.addEllipse(in: rect) }
            }
            row += 1
        }
        return Grain(body: body, bodyAlt: alt, lit: lit, shade: shade)
    }
}

/// 01 のヘアライン（動かない層）
struct PassBrassHairline: View {
    var body: some View {
        ZStack {
            PassFaceTextures.hairlineLight.fill(Color.white.opacity(0.035))
            PassFaceTextures.hairlineDark.fill(Color.black.opacity(0.035))
        }
        .frame(width: 300, height: 430)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 10 綿紙の粒（動かない層）
struct PassPaperGrain: View {
    var body: some View {
        PassFaceTextures.paperGrain.fill(Color.white.opacity(0.035))
            .frame(width: 300, height: 430)
            .drawingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 21 裾の金粉（動かない層）
struct PassGoldDust: View {
    var body: some View {
        ZStack {
            PassFaceTextures.goldDust.faint.fill(PassFaceColor.of(PassFacePalette.goldDust, 0.35))
            PassFaceTextures.goldDust.bright.fill(PassFaceColor.of(PassFacePalette.goldDust, 0.8))
        }
        .frame(width: 300, height: 430)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 26 革のしぼの1枚（動かない層・左から／右から）
struct PassLeatherGrain: View {
    let fromLeft: Bool

    var body: some View {
        let grain = fromLeft ? PassFaceTextures.leatherFromLeft : PassFaceTextures.leatherFromRight
        ZStack {
            PassFaceColor.of(PassFacePalette.leatherShade)
            grain.shade.fill(Color.black.opacity(0.35))
            grain.lit.fill(PassFaceColor.of(0xFFE6C8, 0.10))
            grain.body.fill(PassFaceColor.of(PassFacePalette.leather))
            grain.bodyAlt.fill(PassFaceColor.of(0x34261B))
        }
        .frame(width: 300, height: 430)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 地（素材）。選ぶ画面の見本もこれを使う

/// 01 真鍮の板（ヘアラインと、傾けると滑る光の帯）
struct PassBrassMaterial: View {
    let light: PassFaceLight.Point

    var body: some View {
        let ends = PassFaceLight.gradientPoints(cssDegrees: PassFaceLight.brassAngle(light))
        let sheen = PassFaceLight.bandPoints(center: light.x, half: 0.25, cssDegrees: 105)
        ZStack {
            LinearGradient(stops: [
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassEdge), location: 0),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassMid), location: 0.28),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassLight), location: PassFaceLight.brassHighlight(light)),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassMid), location: 0.62),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassEdge), location: 1),
            ], startPoint: UnitPoint(x: ends.start.x, y: ends.start.y), endPoint: UnitPoint(x: ends.end.x, y: ends.end.y))
            PassBrassHairline()
            // brassSheen: 金属を滑る光の帯（写真の窓より下の層）
            LinearGradient(colors: [Color.clear, PassFaceColor.of(0xFFF1CC, 0.28), Color.clear],
                           startPoint: UnitPoint(x: sheen.start.x, y: sheen.start.y),
                           endPoint: UnitPoint(x: sheen.end.x, y: sheen.end.y))
        }
        .frame(width: 300, height: 430)
        .accessibilityHidden(true)
    }
}

/// 06 大圏航路の地（墨の紙）
struct PassRouteMaterial: View {
    var body: some View {
        PassFaceColor.of(PassFacePalette.routeGround)
            .frame(width: 300, height: 430)
            .accessibilityHidden(true)
    }
}

/// 10 墨の綿紙
struct PassPaperMaterial: View {
    var body: some View {
        ZStack {
            PassFaceColor.of(PassFacePalette.paper)
            PassPaperGrain()
        }
        .frame(width: 300, height: 430)
        .accessibilityHidden(true)
    }
}

/// 21 黒漆（奥に朱の沈む艶・裾の金粉・傾けると走る鏡面の光）。裏（`PassUrushiBack`）は裾に一行の字があるので
/// 金粉を敷かない（`dust: false`・金粉が字に掛かると #999 の比が 4.5 を割る）
struct PassLacquerMaterial: View {
    let light: PassFaceLight.Point
    var dust: Bool = true

    var body: some View {
        let glint = PassFaceLight.lacquerCenter(light)
        ZStack {
            RadialGradient(stops: [
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerTop), location: 0),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerMid), location: 0.45),
                Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerDeep), location: 1),
            ], center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 470)
            if dust { PassGoldDust() }
            // lacquerSheen: 鏡面に細く鋭く走る光（モック 34%×9% の楕円）と、広く淡い艶（70%×40%）
            Rectangle()
                .fill(RadialGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(0xFFE6D2, 0.05), location: 0),
                    Gradient.Stop(color: Color.clear, location: 0.7),
                ], center: UnitPoint(x: glint.x, y: glint.y), startRadius: 0, endRadius: 210))
                .scaleEffect(x: 1, y: 120.0 / 210.0, anchor: UnitPoint(x: glint.x, y: glint.y))
            Rectangle()
                .fill(RadialGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerGlint, PassFaceLight.lacquerPeak), location: 0),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerGlint, PassFaceLight.lacquerPeak * 0.2), location: 0.55),
                    Gradient.Stop(color: Color.clear, location: 0.75),
                ], center: UnitPoint(x: glint.x, y: glint.y), startRadius: 0, endRadius: 102))
                .scaleEffect(x: 1, y: 39.0 / 102.0, anchor: UnitPoint(x: glint.x, y: glint.y))
        }
        .frame(width: 300, height: 430)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 26 黒茶の革（光でしぼが立つ・裾の暗がり・真鍮の糸のステッチ）。**磨き込みすぎない**
/// （owner「やりすぎて本物っぽさが消えた」版がある。モックの今の版の控えめな艶に合わせる）
struct PassLeatherMaterial: View {
    let light: PassFaceLight.Point

    var body: some View {
        let fromLeft = PassFaceLight.leatherFromLeft(light)
        ZStack {
            PassLeatherGrain(fromLeft: false)
            // leatherSheen: 傾きで、左から当てたしぼを重ねる（混ぜるだけ・形は作り直さない）
            PassLeatherGrain(fromLeft: true)
                .opacity(fromLeft)
            RadialGradient(stops: [
                Gradient.Stop(color: Color.clear, location: 0.4),
                Gradient.Stop(color: Color.black.opacity(0.45), location: 1),
            ], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 400)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 2)
                .frame(width: 284, height: 414)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WebTheme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3.5]))
                .frame(width: 283.2, height: 413.2)
        }
        .frame(width: 300, height: 430)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 01 真鍮の金属板

/// 01 真鍮の金属板: 券全体が真鍮の板（ヘアライン）。字は墨で彫り込み（下に明るい縁）。写真は窓にはめ込み。
/// 傾けると光の帯が金属を滑る
struct PassBrassPlateFace: View {
    let face: PassTicketFace
    let light: PassFaceLight.Point
    var onPhotoTap: (() -> Void)?

    private var ink: Color { PassFaceColor.of(PassFacePalette.brassInk) }
    private var smallInk: Color { PassFaceColor.of(PassFacePalette.brassInk, PassFacePalette.brassSmallInkOpacity) }
    /// 彫り込み: 下に明るい縁・上に少し暗い縁
    private var engraved: [PassFaceTextShadow] {
        [PassFaceTextShadow(color: PassFaceColor.of(0xFFF4D6, 0.55), y: 1),
         PassFaceTextShadow(color: Color.black.opacity(0.25), y: -1)]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PassBrassMaterial(light: light)
            // 窓の縁（窓の外に 1px ずつ: 上は暗く・下は明るく。写真には重ねない）
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 268, height: 1).offset(x: 16, y: 13)
                .accessibilityHidden(true)
            Rectangle().fill(PassFaceColor.of(0xFFF4D6, 0.5)).frame(width: 268, height: 1).offset(x: 16, y: 210)
                .accessibilityHidden(true)
            PassFacePhoto(photo: face.photo, width: 272, height: 196, corner: 8, onTap: onPhotoTap)
                .offset(x: 14, y: 14)
            VStack(alignment: .leading, spacing: 9) {
                PassFaceHeadRow(face: face, headline: face.headline, head: AnyShapeStyle(ink), number: AnyShapeStyle(ink),
                                numberWeight: .bold, shadows: [engraved[0]])
                PassFaceRoute(face: face, width: 260, names: AnyShapeStyle(ink), marks: AnyShapeStyle(ink), arrow: ink,
                              shadows: engraved)
                PassFaceFields(fields: face.fields, label: smallInk, value: ink, valueWeight: .semibold,
                               topLine: PassFaceColor.of(PassFacePalette.brassInk, 0.35),
                               bottomLine: PassFaceColor.of(PassFacePalette.brassInk, 0.35))
                Spacer(minLength: 0)
                PassFaceFooter(name: face.name, nameColor: ink, nameWeight: .semibold, validityColor: smallInk)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .frame(width: 300, height: 208, alignment: .topLeading)
            .offset(y: 222)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 06 大圏航路

/// 06 大圏航路: 写真の下に経緯線と、発と着を結ぶ弧。小さな光が弧をたどり続ける。
/// **実際の地図や座標は描かない**（発・着は地名の札だけ・弧は形として）。距離は今の区間の値
struct PassGreatCircleFace: View {
    let face: PassTicketFace
    let reduceMotion: Bool
    /// 見えていないとき（裏・上に全面の写真）は弧の光を止める
    var visible: Bool = true
    var onPhotoTap: (() -> Void)?

    private var brass: Color { WebTheme.accent }
    private var text2: Color { PassFaceColor.of(PassFacePalette.text2) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PassRouteMaterial()
            // 経緯線と弧は写真の下（y 206〜）に置き、写真より下の層に描く
            map
                .frame(width: 300, height: 120)
                .offset(y: 206)
            PassFacePhoto(photo: face.photo, width: 300, height: 200, onTap: onPhotoTap)
            HStack(alignment: .firstTextBaseline) {
                Text(PassTicket.routeHeadline(face.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(11 * 0.12)
                    .foregroundStyle(brass)
                    .lineLimit(1)
                    .accessibilityLabel(face.style.spokenHeadline(PassTicket.routeHeadline(face.kind)))
                Spacer(minLength: JPSpace.xs)
                if let number = face.number {
                    Text(number)
                        .font(.system(size: PassCardStyle.numberSize, weight: .semibold).monospacedDigit())
                        .tracking(PassCardStyle.numberSize * PassCardStyle.numberTracking)
                        .foregroundStyle(brass)
                        .fixedSize()
                }
            }
            .frame(width: 264)
            .offset(x: 18, y: 211)
            bottom
                .frame(width: 264, height: 430 - 14, alignment: .bottomLeading)
                .offset(x: 18)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }

    /// 経緯線・弧・発と着の札・弧をたどる光
    private var map: some View {
        let start = PassGreatCircle.start, end = PassGreatCircle.end
        return ZStack(alignment: .topLeading) {
            PassGreatCircleGrid()
            PassGreatCircleArc()
            Circle().fill(brass).frame(width: 7, height: 7)
                .position(x: start.x, y: start.y)
                .accessibilityHidden(true)
            Circle().strokeBorder(brass, lineWidth: 1.4).frame(width: 8.4, height: 8.4)
                .position(x: end.x, y: end.y)
                .accessibilityHidden(true)
            mapLabel(face.origin, x: start.x, y: start.y + 20)
            mapLabel(face.destination, x: end.x, y: end.y + 20)
            // 弧をたどる光（4 秒で一周）。「視差効果を減らす」では弧の中ほどで止める
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: PassGreatCircle.paused(reduceMotion: reduceMotion, visible: visible))) { context in
                let t = PassGreatCircle.progress(at: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
                let point = PassGreatCircle.point(t)
                Circle().fill(PassFaceColor.of(PassFacePalette.routeLight)).frame(width: 6, height: 6)
                    .position(x: point.x, y: point.y)
            }
            .accessibilityHidden(true)
        }
        .frame(width: 300, height: 120, alignment: .topLeading)
    }

    /// 地名の札（12・text-2）。札の幅に収め、カードの端からはみ出さない
    private func mapLabel(_ text: String, x: Double, y: Double) -> some View {
        Text(text)
            .font(.system(size: PassCardStyle.metaSize))
            .foregroundStyle(text2)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 76)
            .position(x: min(300 - 50, max(50, x)), y: y)
            .accessibilityHidden(true)
    }

    /// 下: 区間（明朝 20）・日付と回数と「ずっと有効」・名前と大圏の距離
    private var bottom: some View {
        VStack(alignment: .leading, spacing: 6) {
            route
            HStack(alignment: .firstTextBaseline) {
                Text("\(fieldValue(0)) · \(fieldValue(2))")
                    .font(.system(size: PassCardStyle.metaSize).monospacedDigit())
                    .foregroundStyle(text2)
                    .lineLimit(1)
                    .accessibilityLabel("\(spokenField(0))、\(spokenField(2))")
                Spacer(minLength: JPSpace.xs)
                Text(PassTicket.shortValidity)
                    .font(.system(size: PassCardStyle.validitySize))
                    .tracking(PassCardStyle.validitySize * PassCardStyle.validityTracking)
                    .foregroundStyle(PassFaceColor.of(PassFacePalette.text3))
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(face.name)
                    .font(.system(size: PassCardStyle.metaSize))
                    .foregroundStyle(text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: JPSpace.xs)
                Text(L("大圏 \(fieldValue(1))", "Great circle \(fieldValue(1))"))
                    .font(.system(size: PassCardStyle.metaSize).monospacedDigit())
                    .foregroundStyle(text2)
                    .fixedSize()
                    .accessibilityLabel(spokenField(1))
            }
        }
    }

    private func fieldValue(_ index: Int) -> String {
        let fields = face.fields
        return fields.indices.contains(index) ? fields[index].value : PassTicket.blank
    }

    /// 欄の読み上げ（空は「なし」）
    private func spokenField(_ index: Int) -> String {
        let fields = face.fields
        return fields.indices.contains(index) ? PassTicket.spokenField(fields[index]) : ""
    }

    /// 「東京 発 — フランス 着」（明朝 20・発と着は 12 の text-2）。長い地名は 13 まで縮める
    /// （発・着は同じ大きさ・`PassGreatCircle.routeSize`）
    private var route: some View {
        let size = CGFloat(PassGreatCircle.routeSize(origin: face.origin, destination: face.destination))
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            routePart(face.origin, mark: PassTicket.originMark, size: size)
            Text("—")
                .font(.system(size: PassCardStyle.metaSize))
                .foregroundStyle(text2)
                .padding(.horizontal, 3)
            routePart(face.destination, mark: PassTicket.destinationMark, size: size)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
    }

    private func routePart(_ place: String, mark: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if PassTicket.marksLead { routeMark(mark) }
            Text(place)
                .font(.custom(JPFont.displayName, fixedSize: size))
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if !PassTicket.marksLead { routeMark(mark) }
        }
    }

    private func routeMark(_ mark: String) -> some View {
        Text(mark)
            .font(.custom(JPFont.displayName, fixedSize: CGFloat(PassCardStyle.markSize)))
            .foregroundStyle(text2)
            .fixedSize()
    }
}

/// 06 の経緯線（動かない層）。裏（`PassGreatCircleBack`）は同じ線を札の高さ（430）に引き伸ばし、薄く（10%）敷く。
/// 伸ばすのは座標だけで、線の太さ（0.6）は変えない（`scaleEffect` で伸ばすと横の線だけ太る）
struct PassGreatCircleGrid: View {
    var height: Double = PassGreatCircle.size.height
    var opacity: Double = 0.18

    var body: some View {
        let scale = height / PassGreatCircle.size.height
        Path { p in
            for line in PassGreatCircle.parallels + PassGreatCircle.meridians {
                p.move(to: CGPoint(x: line.from.0, y: line.from.1 * scale))
                p.addQuadCurve(to: CGPoint(x: line.to.0, y: line.to.1 * scale),
                               control: CGPoint(x: line.control.0, y: line.control.1 * scale))
            }
        }
        .stroke(WebTheme.accent.opacity(opacity), lineWidth: 0.6)
        .frame(width: 300, height: CGFloat(height))
        .accessibilityHidden(true)
    }
}

/// 06 の弧（発 → 着・破線）
struct PassGreatCircleArc: View {
    var lineWidth: CGFloat = 1.4
    var dash: CGFloat = 3

    var body: some View {
        Path { p in
            let s = PassGreatCircle.start, c1 = PassGreatCircle.control1, c2 = PassGreatCircle.control2, e = PassGreatCircle.end
            p.move(to: CGPoint(x: s.x, y: s.y))
            p.addCurve(to: CGPoint(x: e.x, y: e.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
        }
        .stroke(WebTheme.accent, style: StrokeStyle(lineWidth: lineWidth, dash: [dash, dash]))
        .frame(width: 300, height: 120)
        .accessibilityHidden(true)
    }
}

// MARK: - 10 箔押しの硬券

/// 10 箔押しの硬券: 墨の綿紙（細かな粒）。「乗車券」と区間の字そのものが真鍮の箔で、傾けると箔だけが光る。
/// 番号は色なしの空押しで大きく。写真の下端に真鍮の線
struct PassFoilHardFace: View {
    let face: PassTicketFace
    let light: PassFaceLight.Point
    var onPhotoTap: (() -> Void)?

    private var text2: Color { PassFaceColor.of(PassFacePalette.text2) }

    var body: some View {
        let foil = PassFaceColor.foil(light)
        ZStack(alignment: .topLeading) {
            PassPaperMaterial()
            // 写真の下端の真鍮の線（写真の下の黒い地に引く・写真には重ねない）
            LinearGradient(colors: [PassFaceColor.of(0x8E6F40), PassFaceColor.of(0xF3DCA6), PassFaceColor.of(0x8E6F40)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 300, height: 2)
                .offset(y: 200)
                .accessibilityHidden(true)
            if let embossed = PassTicket.embossedNumber(face.number) {
                // 空押し（色なしの型押し）: 右下に明るい縁・左上に暗い縁だけ
                ZStack {
                    Text(embossed).foregroundStyle(Color.black.opacity(0.9)).offset(x: -1, y: -1)
                    Text(embossed).foregroundStyle(Color.white.opacity(0.06)).offset(x: 1, y: 1)
                }
                .font(.custom(JPFont.displayName, fixedSize: 76))
                .lineLimit(1)
                .fixedSize()
                .frame(width: 286, alignment: .trailing)
                .offset(y: 210)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(face.number ?? embossed)
            }
            // 写真は線と空押しより上・字より下（写真より上の層は字だけ）
            PassFacePhoto(photo: face.photo, width: 300, height: 200, onTap: onPhotoTap)
            VStack(alignment: .leading, spacing: 10) {
                Text(face.headline)
                    .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.headSize))
                    .tracking(PassCardStyle.headSize * PassCardStyle.headTracking)
                    .foregroundStyle(foil)
                    .lineLimit(1)
                    .accessibilityLabel(face.style.spokenHeadline(face.headline))
                VStack(alignment: .leading, spacing: 4) {
                    routeLine(face.origin, mark: PassTicket.originMark, foil: foil)
                    routeLine(face.destination, mark: PassTicket.destinationMark, foil: foil)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(PassTicket.countTitle) \(fieldValue(2))")
                        .font(.system(size: PassCardStyle.metaSize))
                        .foregroundStyle(text2)
                        .lineLimit(1)
                        .accessibilityLabel(spokenField(2))
                    Spacer(minLength: JPSpace.xs)
                    Text(PassTicket.shortValidity)
                        .font(.system(size: PassCardStyle.validitySize))
                        .tracking(PassCardStyle.validitySize * PassCardStyle.validityTracking)
                        .foregroundStyle(PassFaceColor.of(PassFacePalette.text3))
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(face.name)
                        .font(.system(size: PassCardStyle.metaSize))
                        .foregroundStyle(text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: JPSpace.xs)
                    Text("\(fieldValue(0)) · \(fieldValue(1))")
                        .font(.system(size: PassCardStyle.metaSize).monospacedDigit())
                        .foregroundStyle(text2)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("\(spokenField(0))、\(spokenField(1))")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(width: 300, height: 430 - 220, alignment: .topLeading)
            .offset(y: 220)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }

    /// 区間の1行（明朝 26・字そのものが箔）。長い地名は 13 まで縮める
    private func routeLine(_ place: String, mark: String, foil: LinearGradient) -> some View {
        Text(PassTicket.marksLead ? "\(mark) \(place)" : "\(place) \(mark)")
            .font(.custom(JPFont.displayName, fixedSize: 26))
            .foregroundStyle(foil)
            .lineLimit(1)
            .minimumScaleFactor(PassCardStyle.routeMinSize / 26)
    }

    private func fieldValue(_ index: Int) -> String {
        let fields = face.fields
        return fields.indices.contains(index) ? fields[index].value : PassTicket.blank
    }

    private func spokenField(_ index: Int) -> String {
        let fields = face.fields
        return fields.indices.contains(index) ? PassTicket.spokenField(fields[index]) : ""
    }
}

// MARK: - 21 漆と蒔絵

/// 21 漆と蒔絵: 奥に朱の沈む黒漆の深い艶、裾に金粉の霞、写真の縁に金の覆輪。傾けると鏡面に細く鋭い光が走る
struct PassUrushiFace: View {
    let face: PassTicketFace
    let light: PassFaceLight.Point
    var onPhotoTap: (() -> Void)?

    var body: some View {
        let foil = PassFaceColor.foil(light)
        let stop = PassFaceLight.rimStop(light)
        ZStack(alignment: .topLeading) {
            PassLacquerMaterial(light: light)
            // 金の覆輪（写真の窓の外の縁 16〜19・写真には重ねない）
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(LinearGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimDark), location: 0),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimLight), location: stop),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimDark), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                .frame(width: 268, height: 184)
                .offset(x: 16, y: 16)
                .accessibilityHidden(true)
            PassFacePhoto(photo: face.photo, width: 262, height: 178, corner: 6, onTap: onPhotoTap)
                .offset(x: 19, y: 19)
            VStack(alignment: .leading, spacing: 9) {
                PassFaceHeadRow(face: face, headline: face.headline, head: AnyShapeStyle(foil), number: AnyShapeStyle(foil))
                PassFaceRoute(face: face, width: 260, names: AnyShapeStyle(Color.white),
                              marks: AnyShapeStyle(PassFaceColor.of(PassFacePalette.text2)), arrow: WebTheme.accent)
                PassFaceFields(fields: face.fields, label: PassFaceColor.of(PassFacePalette.text3),
                               value: Color.white.opacity(0.96),
                               topLine: WebTheme.accent.opacity(0.28), bottomLine: WebTheme.accent.opacity(0.28))
                PassFaceFooter(name: face.name, nameColor: PassFaceColor.of(PassFacePalette.text2),
                               validityColor: PassFaceColor.of(PassFacePalette.text3))
            }
            .frame(width: 260, alignment: .topLeading)
            .offset(x: 20, y: 214)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 26 型押しの革

/// 26 型押しの革: 光でしぼが立つ黒茶の革、真鍮の糸の破線ステッチ、写真は沈んだ窓。「乗車券」と区間は金の箔押し、
/// 小さな字は読める明るさ（モックの色）。**磨き込みすぎない**
struct PassLeatherFace: View {
    let face: PassTicketFace
    let light: PassFaceLight.Point
    var onPhotoTap: (() -> Void)?

    private var pressed: [PassFaceTextShadow] { [PassFaceTextShadow(color: Color.black.opacity(0.7), y: 1)] }

    var body: some View {
        let foil = PassFaceColor.foil(light)
        ZStack(alignment: .topLeading) {
            PassLeatherMaterial(light: light)
            // 沈んだ窓: 窓の外を黒い縁で囲み、下にかすかな明るい縁（写真の上には影を落とさない）
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
                .frame(width: 258, height: 180)
                .offset(x: 21, y: 21)
                .accessibilityHidden(true)
            Rectangle().fill(PassFaceColor.of(0xFFE6C8, 0.10)).frame(width: 244, height: 1).offset(x: 28, y: 201)
                .accessibilityHidden(true)
            PassFacePhoto(photo: face.photo, width: 256, height: 178, corner: 6, onTap: onPhotoTap)
                .offset(x: 22, y: 22)
            VStack(alignment: .leading, spacing: 9) {
                PassFaceHeadRow(face: face, headline: face.headline, head: AnyShapeStyle(foil),
                                number: AnyShapeStyle(PassFaceColor.of(PassFacePalette.leatherNumber)),
                                numberWeight: .bold, shadows: pressed)
                PassFaceRoute(face: face, width: 252, names: AnyShapeStyle(foil), marks: AnyShapeStyle(foil),
                              arrow: WebTheme.accent, shadows: [PassFaceTextShadow(color: Color.black.opacity(0.6), y: 1)])
                PassFaceFields(fields: face.fields, label: PassFaceColor.of(PassFacePalette.leatherLabel),
                               value: PassFaceColor.of(PassFacePalette.leatherValue),
                               topLine: Color.black.opacity(0.55), bottomLine: PassFaceColor.of(0xFFE6C8, 0.07))
                PassFaceFooter(name: face.name, nameColor: PassFaceColor.of(PassFacePalette.leatherName),
                               validityColor: PassFaceColor.of(PassFacePalette.leatherLabel))
            }
            .frame(width: 252, alignment: .topLeading)
            .offset(x: 24, y: 214)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 小さく描く地（選ぶ画面の見本・帳の札・ホームの束）

/// 券面の地を**小さく描くための軽い形**（300×430 の座標で描き、使う側が縮める・2026-10-17 判断）。
/// 大きい札の地（`PassBrassMaterial` など）から、小さくすると見えない細かい地紋（ヘアライン・綿紙の粒・金粉・
/// 革のしぼ）と、傾きで動く光を省き、正面の光で止めた色だけを残す。小さな札では黒に沈む漆と革は、
/// 覆輪・裾の金の霞・ステッチを太く明るく描く（見本で決めた形）。**写真の窓には何も描かない**（窓の位置は `window`）
struct PassFaceGround: View {
    let style: PassTicketFaceStyle
    /// 字の下に敷く（小さなきっぷ）。06 の弧は字と重なるので薄くし、名前の行の下へ下げる
    /// （2026-10-17 の Mac の画面写真: 弧の破線が「乗車券」と番号の間を横切っていた）
    var behindText: Bool = false

    static let size = CGSize(width: 300, height: 430)

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch style {
            case .mars:
                PassCardStyle.face
                // 写真の下端の真鍮の線（黒い地の側・窓の下）
                WebTheme.accent.opacity(PassCardStyle.photoRuleOpacity).frame(width: 300, height: 4).offset(y: 214)
            case .brassPlate:
                let ends = PassFaceLight.gradientPoints(cssDegrees: PassFaceLight.brassAngle(.center))
                LinearGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassEdge), location: 0),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassMid), location: 0.28),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassLight),
                                  location: PassFaceLight.brassHighlight(.center)),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassMid), location: 0.62),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.brassEdge), location: 1),
                ], startPoint: UnitPoint(x: ends.start.x, y: ends.start.y), endPoint: UnitPoint(x: ends.end.x, y: ends.end.y))
            case .greatCircle:
                PassRouteMaterial()
                PassGreatCircleGrid().offset(y: 206)
                PassGreatCircleArc(lineWidth: 4, dash: 9)
                    .opacity(behindText ? 0.4 : 1)
                    .offset(y: behindText ? 300 : 206)
            case .foilHard:
                PassFaceColor.of(PassFacePalette.paper)
                PassFaceColor.foil(.center).frame(width: 300, height: 6).offset(y: 200)
            case .urushi:
                RadialGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerTop), location: 0),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerMid), location: 0.45),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.lacquerDeep), location: 1),
                ], center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 470)
                LinearGradient(colors: [Color.clear, PassFaceColor.of(PassFacePalette.goldDust, 0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 300, height: 150)
                    .offset(y: 280)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LinearGradient(colors: [PassFaceColor.of(PassFacePalette.rimDark),
                                                          PassFaceColor.of(PassFacePalette.rimLight),
                                                          PassFaceColor.of(PassFacePalette.rimDark)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 10)
                    .frame(width: 282, height: 196)
                    .offset(x: 9, y: 10)
            case .leather:
                PassFaceColor.of(PassFacePalette.leather)
                PassFaceColor.of(0x8A6A4E, 0.30)
                RadialGradient(stops: [
                    Gradient.Stop(color: Color.clear, location: 0.4),
                    Gradient.Stop(color: Color.black.opacity(0.45), location: 1),
                ], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 400)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WebTheme.accent, style: StrokeStyle(lineWidth: 6, dash: [16, 11]))
                    .frame(width: 270, height: 400)
                    .offset(x: 15, y: 15)
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 写真の窓（券面ごとの位置・300×430 の座標。大きい札の窓と同じ）
    nonisolated static func window(_ style: PassTicketFaceStyle) -> CGRect {
        switch style {
        case .mars: return CGRect(x: 0, y: 0, width: 300, height: 214)
        case .brassPlate: return CGRect(x: 14, y: 14, width: 272, height: 196)
        case .greatCircle, .foilHard: return CGRect(x: 0, y: 0, width: 300, height: 200)
        case .urushi: return CGRect(x: 19, y: 19, width: 262, height: 178)
        case .leather: return CGRect(x: 22, y: 22, width: 256, height: 178)
        }
    }

    /// 窓の角（大きい札と同じ: 01 は 8・21 と 26 は 6・端まで広がる窓は 0）
    nonisolated static func windowCorner(_ style: PassTicketFaceStyle) -> CGFloat {
        switch style {
        case .brassPlate: return 8
        case .urushi, .leather: return 6
        case .mars, .greatCircle, .foilHard: return 0
        }
    }
}

// MARK: - 選ぶ画面の見本

/// 券面の見本（選ぶ画面・64×92）。地は `PassFaceGround`（写真の窓は暗い四角・字は描かない）
struct PassFaceSwatch: View {
    let style: PassTicketFaceStyle

    static let size = CGSize(width: 64, height: 92)

    var body: some View {
        let window = PassFaceGround.window(style)
        ZStack(alignment: .topLeading) {
            PassFaceGround(style: style)
            if style == .foilHard {
                // 箔の字の代わり（見本には字を描かない）
                PassFaceColor.foil(.center).frame(width: 150, height: 40).offset(x: 20, y: 240)
            }
            // 写真の窓の位置（暗い四角）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.55))
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: window.minY)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
        .scaleEffect(Self.size.width / 300, anchor: .topLeading)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
