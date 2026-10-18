import SwiftUI

// 乗車券の裏の特別な券面（Pro・**2026-10-18 札 #306**・owner「裏面デザイン変わってなくて悲しいね」→「まかせる」）。
//
// 見本は Artifact「すれちがい乗車券の裏面」（https://claude.ai/artifact/BgPadmCAZRPVjoicuTWyJ7）。
// - **並び・寸法・字の大きさはマルス券の裏（`PassCardBack`）と同じ**: 帯 44（「ご案内」と No.）・作品名（明朝 18）・
//   ひとこと（15）と届いた文の注記（12）・欄4つ（ラベル 12・値 14 の等幅数字）・破線・裾の一行（12）
// - 変えるのは地・字の色・飾りだけで、どれも**表の券面と同じ素材の View と色**を使う（`PassBrassMaterial` など）。
//   画像は使わない
// - 飾り（06 の弧・10 の空押しの番号・21 の平目地）は、作品名・ひとことと欄の間の**空いた所にだけ**描く
//   （`PassBackOrnamentSpace`）。狭ければ出さない＝字の下には決して敷かない
// - 裏には写真が無いので、写真を加工する層はどこにも無い
// - 文字と地の比は `PassFacePalette.pairs`（裏で新しく出る地は「裏 …」の組）を `PassFaceContrastTests` で測る

/// 特別な券面の裏の入れ物: 表と同じく、裏が見えている間だけ傾き（`PassTiltMotion`）を読み、光の位置を決めて描く
struct PassSpecialBack: View {
    let face: PassTicketBackFace
    var shine: Double?
    /// 裏がいま見えているか（表を見ている・全面の写真や Pro の案内が上にある間は false）
    var visible: Bool = true

    var body: some View {
        PassTiltLight(visible: visible, shine: shine) { light in
            PassBackBody(face: face, light: light, shine: shine)
        }
        .modifier(PassTiltHold(style: face.style, visible: visible))
    }
}

/// 券面ごとに裏を描き分ける（光の位置は渡されたものだけを使う）
struct PassBackBody: View {
    let face: PassTicketBackFace
    let light: PassFaceLight.Point
    var shine: Double?

    var body: some View {
        switch face.style {
        case .mars:
            // マルス券の裏は `PassCardBack` が描く（ここへは来ない）
            EmptyView()
        case .brassPlate:
            PassBrassPlateBack(face: face, light: light)
        case .greatCircle:
            PassGreatCircleBack(face: face, shine: shine)
        case .foilHard:
            PassFoilHardBack(face: face, light: light)
        case .urushi:
            PassUrushiBack(face: face, light: light)
        case .leather:
            PassLeatherBack(face: face, light: light)
        }
    }
}

// MARK: - 共通の部品

/// 裏の字の色（券面ごと）
struct PassBackInk {
    /// 帯の「ご案内」と No.
    let head: AnyShapeStyle
    let number: AnyShapeStyle
    var numberWeight: Font.Weight = .semibold
    /// 06 だけ、帯の字を表の眉ラベル（「航路乗車券」）と同じ SF 11・字間 0.12em にする
    var eyebrowHead = false
    var headShadows: [PassFaceTextShadow] = []
    /// 作品名（明朝 18）
    let title: AnyShapeStyle
    var titleShadows: [PassFaceTextShadow] = []
    /// ひとこと（15）
    let note: Color
    var noteWeight: Font.Weight = .regular
    var noteShadows: [PassFaceTextShadow] = []
    /// 小さな字（欄のラベル・届いた文の注記・伏せている一行・裾の一行）
    let small: Color
    /// 欄の値（14・等幅数字）
    let value: Color
    var valueWeight: Font.Weight = .regular
    var valueShadows: [PassFaceTextShadow] = []
}

/// 帯の字（「ご案内」と No.）。読み上げでは表と同じく券面の名前を添える
struct PassBackBand: View {
    let face: PassTicketBackFace
    let ink: PassBackInk

    static var title: String { L("ご案内", "NOTICE") }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            head
                .foregroundStyle(ink.head)
                .lineLimit(1)
                .passFaceShadows(ink.headShadows)
                .accessibilityLabel(face.style.spokenHeadline(Self.title))
            Spacer(minLength: JPSpace.xs)
            if let number = face.number {
                Text(number)
                    .font(.system(size: PassCardStyle.numberSize, weight: ink.numberWeight).monospacedDigit())
                    .tracking(PassCardStyle.numberSize * PassCardStyle.numberTracking)
                    .foregroundStyle(ink.number)
                    .lineLimit(1)
                    .fixedSize()
                    .passFaceShadows(ink.headShadows)
            }
        }
    }

    @ViewBuilder private var head: some View {
        if ink.eyebrowHead {
            Text(Self.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(11 * 0.12)
        } else {
            Text(Self.title)
                .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.headSize))
                .tracking(PassCardStyle.headSize * PassCardStyle.headTracking)
        }
    }
}

/// 作品名とひとこと（マルス券の裏と同じ字組・同じ注記）
struct PassBackText: View {
    let face: PassTicketBackFace
    let ink: PassBackInk

    var body: some View {
        VStack(alignment: .leading, spacing: PassCardStyle.backSpacing) {
            Text(face.title)
                .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.backTitleSize))
                .foregroundStyle(ink.title)
                .lineLimit(2)
                .passFaceShadows(ink.titleShadows)
            if !face.note.isEmpty {
                // 🔴 **ひとことには署名が無い**（電波の中身は誰でも書ける）。届いた文だと分かる書き方にする
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(L("「\(face.note)」", "\u{201C}\(face.note)\u{201D}"))
                        .font(.system(size: PassCardStyle.noteSize, weight: ink.noteWeight))
                        .lineSpacing(5)
                        .foregroundStyle(ink.note)
                        .lineLimit(3)
                        .passFaceShadows(ink.noteShadows)
                    Text(PassPrivacyText.noteSource)
                        .font(.system(size: PassCardStyle.backLabelSize))
                        .foregroundStyle(ink.small)
                        .lineLimit(2)
                }
            } else if face.noteHidden {
                Text(L("ひとことは伏せています", "Note hidden"))
                    .font(.system(size: PassCardStyle.backLabelSize))
                    .foregroundStyle(ink.small)
            }
        }
    }
}

/// 作品名・ひとことと欄の間の空き（マルス券の裏の `Spacer`）。**飾りはこの中にだけ**描き、空きが `minHeight` より
/// 低ければ出さない（ひとことが3行・作品名が2行のときは空きが狭くなる）。読み上げには出さない
struct PassBackOrnamentSpace<Content: View>: View {
    let minHeight: CGFloat
    let content: Content

    init(minHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                GeometryReader { proxy in
                    if Self.shows(height: Double(proxy.size.height), minHeight: Double(minHeight)) {
                        content.frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 飾りを出すか（空きが飾りの高さ以上のときだけ）
    nonisolated static func shows(height: Double, minHeight: Double) -> Bool { height >= minHeight }
}

/// 発行・有効・区間・回数の 2×2。値は 14 の等幅数字、「有効」だけ2行まで（`PassCardStyle.backValueLines`）。
/// 行は上でそろえ、増えた1行は上の空きが受け持つので、格子は崩れない
struct PassBackFields: View {
    enum Style {
        /// 上に1本の細い線（06・21）
        case hairline(Color)
        /// 彫り線（01: 上が暗い1本・下が明るい1本。たての真ん中にも同じ2本）
        case engraved
        /// 箔の罫（10: 上・行の間・たての真ん中）
        case foilRules
        /// 型押しの欄（26: 欄ごとに革を沈めた箱）
        case debossed
    }

    let fields: [PassTicket.Field]
    let ink: PassBackInk
    let style: Style
    /// 縦の寸法（欄の上の余白・箱の上下）。`PassCardStyle.backMetrics`
    var metrics = PassCardStyle.BackMetrics()

    /// 罫で区切る券面（01・10）の右の欄の字下げ（罫から字を離す）
    nonisolated static let ruleIndent: CGFloat = 5
    /// 型押しの欄の箱の左右の内側（板どおり 8・欄は左右に張り出さない＝値の幅 110）
    nonisolated static let debossPadding: CGFloat = 8

    private var isDebossed: Bool {
        if case .debossed = style { return true }
        return false
    }

    private var isRuled: Bool {
        switch style {
        case .engraved, .foilRules: return true
        case .hairline, .debossed: return false
        }
    }

    private var gap: CGFloat { PassCardStyle.backFieldGap }

    /// 行の間の罫の上下（罫の太さを引いた残りを半分ずつ）
    private static func separatorPadding(gap: CGFloat) -> CGFloat {
        let line: CGFloat = JPStroke.hairline
        return (gap - line) / 2
    }

    var body: some View {
        let rows = Array(stride(from: 0, to: fields.count, by: 2))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { rowSeparator }
                HStack(alignment: .top, spacing: gap) {
                    cell(fields[row], indent: 0)
                    if row + 1 < fields.count { cell(fields[row + 1], indent: isRuled ? Self.ruleIndent : 0) }
                }
                // 型押しの箱は、2行の欄に合わせて隣の箱も同じ高さにする
                .fixedSize(horizontal: false, vertical: isDebossed)
            }
        }
        .overlay { columnRule }
        .padding(.top, metrics.fieldTop)
        .overlay(alignment: .top) { topRule }
    }

    private func cell(_ field: PassTicket.Field, indent: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label)
                .font(.system(size: PassCardStyle.backLabelSize))
                .foregroundStyle(ink.small)
                .lineLimit(1)
            Text(field.value)
                .font(.system(size: PassCardStyle.backValueSize, weight: ink.valueWeight).monospacedDigit())
                .foregroundStyle(ink.value)
                // 「有効」だけ2行まで（字は縮めない）
                .lineLimit(PassCardStyle.backValueLines(field))
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .passFaceShadows(ink.valueShadows)
        }
        .padding(.leading, indent)
        .padding(.horizontal, isDebossed ? Self.debossPadding : 0)
        .padding(.vertical, metrics.cellVertical)
        .frame(maxWidth: .infinity, maxHeight: isDebossed ? .infinity : nil, alignment: .topLeading)
        .background {
            if isDebossed { PassDeboss(corner: 5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenField(field))
    }

    /// 行の間（欄の間と同じ高さ。10 は真ん中に箔の罫）
    @ViewBuilder private var rowSeparator: some View {
        switch style {
        case .foilRules:
            PassFoilRule(vertical: false)
                .opacity(0.7)
                .frame(height: JPStroke.hairline)
                .padding(.vertical, Self.separatorPadding(gap: gap))
        case .hairline, .engraved, .debossed:
            Color.clear.frame(height: gap)
        }
    }

    /// 上の線
    @ViewBuilder private var topRule: some View {
        switch style {
        case .hairline(let color):
            Rectangle().fill(color).frame(height: JPStroke.hairline).accessibilityHidden(true)
        case .engraved:
            PassEngravedRule(vertical: false)
        case .foilRules:
            PassFoilRule(vertical: false).frame(height: JPStroke.hairline)
        case .debossed:
            EmptyView()
        }
    }

    /// たての真ん中の線（01・10）
    @ViewBuilder private var columnRule: some View {
        switch style {
        case .engraved:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PassEngravedRule(vertical: true)
                Spacer(minLength: 0)
            }
        case .foilRules:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PassFoilRule(vertical: true).frame(width: JPStroke.hairline)
                Spacer(minLength: 0)
            }
        case .hairline, .debossed:
            EmptyView()
        }
    }
}

/// 01 の彫り線（暗い1本と明るい1本を並べる。表の写真の窓の縁と同じ色）
struct PassEngravedRule: View {
    let vertical: Bool

    var body: some View {
        let dark = Color.black.opacity(0.35), lit = PassFaceColor.of(0xFFF4D6, 0.5)
        Group {
            if vertical {
                HStack(spacing: 0) {
                    Rectangle().fill(dark).frame(width: 1)
                    Rectangle().fill(lit).frame(width: 1)
                }
            } else {
                VStack(spacing: 0) {
                    Rectangle().fill(dark).frame(height: 1)
                    Rectangle().fill(lit).frame(height: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 10 の箔の罫（表の写真の下端の線と同じ色の並び）
struct PassFoilRule: View {
    let vertical: Bool

    var body: some View {
        LinearGradient(colors: [PassFaceColor.of(0x8E6F40), PassFaceColor.of(0xF3DCA6), PassFaceColor.of(0x8E6F40)],
                       startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 26 の型押し（革を沈めた面: 黒 22%・上に陰の1本・下に明るい縁の1本。表の沈んだ写真の窓と同じ陰）
struct PassDeboss: View {
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.black.opacity(PassFacePalette.debossShade))
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(PassFaceColor.of(0xFFE6C8, 0.07)).frame(height: 1) }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 裏の破線（券面ごとの色と刻み）。回しているときは縁と同じ光が流れる
struct PassBackDash: View {
    let color: Color
    var dash: CGFloat = 4
    var gap: CGFloat? = nil
    var lineWidth: CGFloat = 1
    var shine: Double? = nil

    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, dash: [dash, gap ?? dash])
        Rectangle()
            .stroke(color, style: style)
            .overlay {
                if let light = PassTicketShine.style(at: shine) { Rectangle().stroke(light, style: style) }
            }
            .frame(height: lineWidth)
            .accessibilityHidden(true)
    }
}

/// 裏の並び（どの券面も同じ）。帯の地・帯の下の線・空きの飾り・破線・欄の区切り方だけを券面が決める。
/// 縦の寸法は `PassCardStyle.backMetrics`（いちばん長い中身でも切れない配分を `worstBackHeight` で見張る）
struct PassBackLayout<BandGround: View, Rule: View, Ornament: View, Dash: View>: View {
    let face: PassTicketBackFace
    let ink: PassBackInk
    let fields: PassBackFields.Style
    let metrics: PassCardStyle.BackMetrics
    /// 帯を札の左右の縁から離す（26: ステッチの内側に入れる）。帯の高さは 44 のまま
    let bandSide: CGFloat
    /// 飾りを出す空きの高さの下限
    let ornamentMinHeight: CGFloat
    let bandGround: BandGround
    let rule: Rule
    let ornament: Ornament
    let dash: Dash

    init(face: PassTicketBackFace, ink: PassBackInk, fields: PassBackFields.Style,
         bandSide: CGFloat = 0, ornamentMinHeight: CGFloat = 0,
         @ViewBuilder bandGround: () -> BandGround, @ViewBuilder rule: () -> Rule,
         @ViewBuilder ornament: () -> Ornament, @ViewBuilder dash: () -> Dash) {
        self.face = face
        self.ink = ink
        self.fields = fields
        self.metrics = PassCardStyle.backMetrics(face.style)
        self.bandSide = bandSide
        self.ornamentMinHeight = ornamentMinHeight
        self.bandGround = bandGround()
        self.rule = rule()
        self.ornament = ornament()
        self.dash = dash()
    }

    var body: some View {
        VStack(spacing: 0) {
            PassBackBand(face: face, ink: ink)
                .padding(.horizontal, PassCardStyle.inset - bandSide)
                .padding(.top, metrics.bandInnerTop)
                .frame(maxWidth: .infinity)
                .frame(height: PassCardStyle.bandHeight)
                .background { bandGround }
                .padding(.horizontal, bandSide)
                .padding(.top, metrics.bandTop)
            rule
                .frame(height: metrics.rule)
            VStack(alignment: .leading, spacing: metrics.spacing) {
                PassBackText(face: face, ink: ink)
                PassBackOrnamentSpace(minHeight: ornamentMinHeight) { ornament }
                PassBackFields(fields: face.fields, ink: ink, style: fields, metrics: metrics)
                dash
                Text(face.footnote)
                    .font(.system(size: PassCardStyle.footnoteSize))
                    .tracking(PassCardStyle.footnoteSize * PassCardStyle.footnoteTracking)
                    .lineSpacing(4)
                    .foregroundStyle(ink.small)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PassCardStyle.backPadding)
            .padding(.top, metrics.bodyTop)
            .padding(.bottom, PassCardStyle.backPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 01 真鍮の金属板

/// 01 の裏: 表と同じ真鍮の板（ヘアライン・傾けると滑る光の帯）。字はすべて墨の彫り込み。帯の下・欄の上・欄の間・
/// 破線は彫り線（色の面は置かない）
struct PassBrassPlateBack: View {
    let face: PassTicketBackFace
    let light: PassFaceLight.Point

    /// 彫り込み（表の `PassBrassPlateFace.engraved` と同じ値）
    private var engraved: [PassFaceTextShadow] {
        [PassFaceTextShadow(color: PassFaceColor.of(0xFFF4D6, 0.55), y: 1),
         PassFaceTextShadow(color: Color.black.opacity(0.25), y: -1)]
    }

    var body: some View {
        let ink = PassFaceColor.of(PassFacePalette.brassInk)
        let small = PassFaceColor.of(PassFacePalette.brassInk, PassFacePalette.brassSmallInkOpacity)
        let style = PassBackInk(head: AnyShapeStyle(ink), number: AnyShapeStyle(ink), numberWeight: .bold,
                                headShadows: [engraved[0]], title: AnyShapeStyle(ink), titleShadows: engraved,
                                note: ink, noteWeight: .medium, noteShadows: [engraved[0]], small: small,
                                value: ink, valueWeight: .semibold, valueShadows: [engraved[0]])
        ZStack(alignment: .topLeading) {
            PassBrassMaterial(light: light)
            PassBackLayout(face: face, ink: style, fields: .engraved) {
                Color.clear
            } rule: {
                PassEngravedRule(vertical: false).padding(.horizontal, 14)
            } ornament: {
                EmptyView()
            } dash: {
                VStack(spacing: 0) {
                    PassBackDash(color: PassFaceColor.of(PassFacePalette.brassInk, 0.4))
                    PassBackDash(color: PassFaceColor.of(0xFFF4D6, 0.45))
                }
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 06 大圏航路

/// 06 の裏: 墨の紙一面に表の経緯線を薄く引き伸ばし、帯は表の眉ラベルと同じ字組。空きに表と同じ弧（発の点・着の輪）。
/// 弧をたどる光は裏では出さない（読む面なので動くものを置かない）
struct PassGreatCircleBack: View {
    let face: PassTicketBackFace
    var shine: Double?

    var body: some View {
        let brass = AnyShapeStyle(WebTheme.accent)
        let ink = PassBackInk(head: brass, number: brass, eyebrowHead: true, title: AnyShapeStyle(WebTheme.text),
                              note: WebTheme.text, small: PassFaceColor.of(PassFacePalette.text3), value: WebTheme.text)
        ZStack(alignment: .topLeading) {
            PassRouteMaterial()
            PassGreatCircleGrid(height: 430, opacity: PassFacePalette.routeBackGridOpacity)
            PassBackLayout(face: face, ink: ink, fields: .hairline(WebTheme.accent.opacity(0.28)),
                           ornamentMinHeight: PassGreatCircleBackArc.height) {
                Color.clear
            } rule: {
                PassTicketRule(opacity: PassCardStyle.bandRuleOpacity, shine: shine)
            } ornament: {
                PassGreatCircleBackArc()
            } dash: {
                PassBackDash(color: WebTheme.accent.opacity(PassCardStyle.dashOpacity), dash: 3, shine: shine)
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

/// 06 の裏の弧（板どおり**弧の所だけを切り出して** 220×66 に描く）。表の地図（300×120）の x 30〜270・y 10〜82 を
/// 切り出し、220/240 倍に置き直す。**線の太さは縮めない**（座標だけ置き直し、線は 1.3・点と輪は表と同じ大きさ）
struct PassGreatCircleBackArc: View {
    nonisolated static let size = CGSize(width: 220, height: 66)
    /// 表の地図から切り出す所
    nonisolated static let crop = CGRect(x: 30, y: 10, width: 240, height: 72)
    nonisolated static var scale: CGFloat { size.width / crop.width }
    nonisolated static let lineWidth: CGFloat = 1.3
    /// 弧が収まる高さ
    nonisolated static var height: CGFloat { size.height }

    /// 表の地図の座標を、切り出した 220×66 の座標に
    nonisolated static func place(_ p: (x: Double, y: Double)) -> CGPoint {
        CGPoint(x: (CGFloat(p.x) - crop.minX) * scale, y: (CGFloat(p.y) - crop.minY) * scale)
    }

    var body: some View {
        let start = Self.place(PassGreatCircle.start), end = Self.place(PassGreatCircle.end)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: start)
                p.addCurve(to: end, control1: Self.place(PassGreatCircle.control1), control2: Self.place(PassGreatCircle.control2))
            }
            .stroke(WebTheme.accent.opacity(0.7), style: StrokeStyle(lineWidth: Self.lineWidth, dash: [3, 3]))
            Circle().fill(WebTheme.accent.opacity(0.85)).frame(width: 7, height: 7)
                .position(x: start.x, y: start.y)
            Circle().strokeBorder(WebTheme.accent.opacity(0.85), lineWidth: 1.4).frame(width: 8.4, height: 8.4)
                .position(x: end.x, y: end.y)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - 10 箔押しの硬券

/// 10 の裏: 墨の綿紙。「ご案内」・No.・作品名は字そのものが箔（傾けると箔が光る）。帯の下は表の写真の下と同じ箔の線、
/// 欄は箔の罫の升目。空きに表と同じ空押しの番号
struct PassFoilHardBack: View {
    let face: PassTicketBackFace
    let light: PassFaceLight.Point

    /// 空押しの番号の大きさ（表は 76。裏は空きに収まる大きさ）
    static let embossSize: CGFloat = 64

    var body: some View {
        let foil = AnyShapeStyle(PassFaceColor.foil(light))
        let ink = PassBackInk(head: foil, number: foil, title: foil, note: WebTheme.text,
                              small: PassFaceColor.of(PassFacePalette.text3), value: WebTheme.text)
        ZStack(alignment: .topLeading) {
            PassPaperMaterial()
            PassBackLayout(face: face, ink: ink, fields: .foilRules, ornamentMinHeight: Self.embossSize) {
                Color.clear
            } rule: {
                PassFoilRule(vertical: false)
            } ornament: {
                if let embossed = PassTicket.embossedNumber(face.number) {
                    // 空押し（色なしの型押し）: 表と同じ（右下に明るい縁・左上に暗い縁だけ）
                    ZStack {
                        Text(embossed).foregroundStyle(Color.black.opacity(0.9)).offset(x: -1, y: -1)
                        Text(embossed).foregroundStyle(Color.white.opacity(0.06)).offset(x: 1, y: 1)
                    }
                    .font(.custom(JPFont.displayName, fixedSize: Self.embossSize))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            } dash: {
                PassBackDash(color: WebTheme.accent.opacity(0.6))
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

// MARK: - 21 漆と蒔絵

/// 21 の裏: 表と同じ黒漆（裾の金粉は敷かない）。表で写真を囲んでいた金の覆輪を札の縁いっぱいに回し、帯の下も同じ金。
/// 空きの右下の隅に金粉の散らし（平目地・`PassHirame`）。
/// 2026-10-18 owner: 前の案のすやり霞（2筋）は「好きではない」、その次のすすきは「余計」→ 平目地だけ
struct PassUrushiBack: View {
    let face: PassTicketBackFace
    let light: PassFaceLight.Point

    /// 覆輪の内側（札の縁から）
    static let rimInset: CGFloat = 8
    static let rimSize = CGSize(width: 284, height: 414)

    var body: some View {
        let foil = AnyShapeStyle(PassFaceColor.foil(light))
        let stop = PassFaceLight.rimStop(light)
        let ink = PassBackInk(head: foil, number: foil, title: AnyShapeStyle(Color.white), note: Color.white.opacity(0.96),
                              small: PassFaceColor.of(PassFacePalette.text3), value: Color.white.opacity(0.96))
        ZStack(alignment: .topLeading) {
            PassLacquerMaterial(light: light, dust: false)
            // 金の覆輪（表と同じ金・同じ太さ 3。傾けると光る所が動く）
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(LinearGradient(stops: [
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimDark), location: 0),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimLight), location: stop),
                    Gradient.Stop(color: PassFaceColor.of(PassFacePalette.rimDark), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                .frame(width: Self.rimSize.width, height: Self.rimSize.height)
                .offset(x: Self.rimInset, y: Self.rimInset)
                .accessibilityHidden(true)
            PassBackLayout(face: face, ink: ink, fields: .hairline(WebTheme.accent.opacity(0.28)),
                           ornamentMinHeight: PassHirame.size.height) {
                Color.clear
            } rule: {
                LinearGradient(colors: [PassFaceColor.of(PassFacePalette.rimDark), PassFaceColor.of(PassFacePalette.rimLight),
                                        PassFaceColor.of(PassFacePalette.rimDark)],
                               startPoint: .leading, endPoint: .trailing)
                    .padding(.horizontal, Self.rimInset + 3)
                    .accessibilityHidden(true)
            } ornament: {
                PassHirame()
            } dash: {
                PassTicketDash()
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}

/// 21 の裏の蒔絵: 右下の隅に金粉の散らし（平目地・`PassFaceTextures.hirame`・隅ほど濃い）だけ。
/// 2026-10-18 owner: すやり霞（横に長い2筋）は「好きではない」、金のすすきは「余計」→ 平目地だけを残した。
/// 空きの右下に寄せて置く（`PassBackOrnamentSpace`・空きが 64 より低ければ出さない）
struct PassHirame: View {
    nonisolated static let size = CGSize(width: 140, height: 64)

    var body: some View {
        ZStack(alignment: .topLeading) {
            PassFaceTextures.hirame.faint.fill(PassFaceColor.of(PassFacePalette.goldDust, 0.4))
            PassFaceTextures.hirame.bright.fill(PassFaceColor.of(PassFacePalette.goldDust, 0.85))
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .drawingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityHidden(true)
    }
}

// MARK: - 26 型押しの革

/// 26 の裏: 表と同じ黒茶の革とステッチ。帯と4つの欄は革を押し下げた型押し。見出しは金の箔押し、小さな字は表と同じ色
struct PassLeatherBack: View {
    let face: PassTicketBackFace
    let light: PassFaceLight.Point

    var body: some View {
        let foil = AnyShapeStyle(PassFaceColor.foil(light))
        let pressed = [PassFaceTextShadow(color: Color.black.opacity(0.7), y: 1)]
        let ink = PassBackInk(head: foil, number: AnyShapeStyle(PassFaceColor.of(PassFacePalette.leatherNumber)),
                              numberWeight: .bold, headShadows: pressed, title: foil,
                              titleShadows: [PassFaceTextShadow(color: Color.black.opacity(0.6), y: 1)],
                              note: PassFaceColor.of(PassFacePalette.leatherValue),
                              small: PassFaceColor.of(PassFacePalette.leatherLabel),
                              value: PassFaceColor.of(PassFacePalette.leatherValue))
        ZStack(alignment: .topLeading) {
            PassLeatherMaterial(light: light)
            PassBackLayout(face: face, ink: ink, fields: .debossed, bandSide: 12) {
                PassDeboss(corner: 6)
            } rule: {
                EmptyView()
            } ornament: {
                EmptyView()
            } dash: {
                // ステッチと同じ刻みの真鍮の糸
                PassBackDash(color: WebTheme.accent.opacity(0.75), dash: 5, gap: 3.5, lineWidth: 1.2)
            }
        }
        .frame(width: 300, height: 430, alignment: .topLeading)
    }
}
