import SwiftUI

/// カプセルの機械（モック Gacha.dc.html・2026-10-17 次の版）。
///
/// 硬貨を入れる → ハンドルを指で円を描いて右へ1周（押すたびに4分の1でも回る）→ カプセルが落ちる →
/// 「カプセルを開ける」（`TrunkGachaOpenView`）。**部品はハンドルが1周したときにサーバーが決める**
/// （硬貨を入れただけでは減らさない・2026-10-17 判断: 入れて閉じた人の硬貨を消さない）。
/// 触覚と音: ハンドルの1目盛り（30°）・カプセルが落ちたとき。「視差効果を減らす」の人にはカプセルの
/// 落ちる弾みとハンドルの戻りの弾みを出さない（ハンドルは指に付いて回るまま）。
struct TrunkGachaView: View {
    @ObservedObject var model: TrunkViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var toasts: ToastCenter
    @State private var phase: TrunkGachaPhase = .idle
    /// 画面に出ているか（1周したあと返事を待つ間に戻った人へ、一言で知らせる）
    @State private var visible = false
    @State private var crank = TrunkCrank()
    @State private var ticks = 0
    @State private var drops = 0
    @State private var result: TrunkGachaResult?
    @State private var showOpen = false
    /// カプセルが落ちきったか（落ちる動き）
    @State private var landed = false

    /// 機械の絵の大きさ（モック 300×540）
    private static let machine = (w: 300.0, h: 540.0)

    private var coins: Int {
        let c = model.state?.coins ?? 0
        // 入れた硬貨は、回し終えてサーバーが答えるまで手元の数から引いて見せる
        return phase == .turning || phase == .waiting ? max(0, c - 1) : c
    }

    var body: some View {
        GeometryReader { geo in
            let k = min(1, max(0.55, (Double(geo.size.height) - 190) / Self.machine.h), (Double(geo.size.width) - 40) / Self.machine.w)
            VStack(spacing: 0) {
                machine
                    .scaleEffect(k, anchor: .top)
                    .frame(width: Self.machine.w * k, height: Self.machine.h * k, alignment: .top)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                coinRow
                    .padding(.top, 2)
                Spacer(minLength: 8)
                bottom
            }
        }
        .background { TrunkStyle.stageBackground(centerY: 0.38) }
        .navigationTitle(L("カプセルの機械", "Capsule machine"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrunkGachaOddsView()
                } label: {
                    Text(L("中身と確率", "Odds"))
                        .font(.subheadline)
                        .underline()
                        .foregroundStyle(WebTheme.accent)
                        .frame(minHeight: WebTheme.minTapTarget)
                }
                .accessibilityIdentifier("trunk.gacha.odds")
            }
        }
        .sensoryFeedback(.selection, trigger: ticks)
        .sensoryFeedback(.impact(weight: .heavy), trigger: drops)
        .task { if model.state == nil { await model.load(offline: false) } }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .fullScreenCover(isPresented: $showOpen, onDismiss: reset) {
            if let result { TrunkGachaOpenView(model: model, result: result) }
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.gacha")
    }

    // MARK: 機械（モックの絵の寸法そのまま）

    private var machine: some View {
        ZStack(alignment: .topLeading) {
            // 上の真鍮の丸い蓋
            UnevenRoundedRectangle(topLeadingRadius: 38, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 38)
                .fill(RadialGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xFFF1C4)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x6E5630)), location: 1)],
                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 50))
                .frame(width: 76, height: 26)
                .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 3)
                .offset(x: 112, y: 0)
                .zIndex(2)
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 10)
                .fill(LinearGradient(colors: [Color(trunk: TrunkRGBA(0xF2DFAE)), Color(trunk: TrunkRGBA(0x8A6B39))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 12)
                .offset(x: 140, y: -8)
                .zIndex(2)
            globe.offset(x: 20, y: 12)
            // 球と胴の間の真鍮の帯
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x7E6438)), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 216, height: 22)
                .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 3)
                .offset(x: 42, y: 254)
            cabinet.offset(x: 30, y: 272)
            // 脚と足もとの光
            ForEach([40.0, 230.0], id: \.self) { x in
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(LinearGradient(colors: [WebTheme.accent, Color(trunk: TrunkRGBA(0x6E5630))], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 14)
                    .offset(x: x, y: 518)
            }
            EllipticalGradient(colors: [WebTheme.accent.opacity(0.2), Color.clear])
                .frame(width: 232, height: 14)
                .offset(x: 34, y: 528)
        }
        .frame(width: Self.machine.w, height: Self.machine.h, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("黒塗りに真鍮の金具のカプセルの機械", "A black capsule machine with brass fittings"))
    }

    /// ガラスの球（260×260）とカプセル
    private var globe: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.10), location: 0),
                                   Gradient.Stop(color: Color.white.opacity(0.02), location: 0.6),
                                   Gradient.Stop(color: Color.black.opacity(0.25), location: 1)],
                           center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 180)
            ForEach(Array(TrunkCapsules.all.enumerated()), id: \.offset) { _, c in
                capsule(top: c.top, bottom: c.bottom, size: 46)
                    .rotationEffect(.degrees(c.rot))
                    .offset(x: c.x, y: c.y)
            }
            // ガラスの光（左上の大きい光・右下の細い光）
            EllipticalGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)])
                .frame(width: 90, height: 46)
                .rotationEffect(.degrees(-28))
                .offset(x: 34, y: 22)
            EllipticalGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)])
                .frame(width: 26, height: 60)
                .rotationEffect(.degrees(-20))
                .offset(x: 204, y: 160)
            // 球の下の暗がりと、縁の白い線
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0.8),
                                   Gradient.Stop(color: Color.black.opacity(0.6), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: 260, height: 260, alignment: .topLeading)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
        .accessibilityHidden(true)
    }

    /// カプセル1つ（上の半分の色・下の半分の色・真ん中の継ぎ目）
    private func capsule(top: TrunkRGBA, bottom: TrunkRGBA, size: Double) -> some View {
        ZStack(alignment: .top) {
            Color(trunk: bottom)
            Color(trunk: top).opacity(0.9).frame(height: size / 2)
            RadialGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.4)
            Color.black.opacity(0.25).frame(height: 2).offset(y: size / 2 - 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 2)
    }

    /// 胴（240×250）: 銘・硬貨の入れ口・ハンドル・取り出し口
    private var cabinet: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 10)
                .fill(RadialGradient(colors: [Color(trunk: TrunkRGBA(0x2A2A2E)), Color(trunk: TrunkRGBA(0x0A0A0C))],
                                     center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 230))
                .overlay(TrunkStripes(angle: 90, period: 5, bands: [(0, 2, TrunkRGBA(r: 255, g: 255, b: 255, a: 0.015))])
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 16,
                                                      bottomTrailingRadius: 16, topTrailingRadius: 10)))
                .overlay(alignment: .top) { Color.white.opacity(0.15).frame(height: 1).padding(.horizontal, 8) }
                .shadow(color: Color.black.opacity(0.75), radius: 25, x: 0, y: 30)
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 8)
                .stroke(WebTheme.accent.opacity(0.45), lineWidth: 1)
                .padding(8.5)
            Text(L("旅 の 部 品", "TRAVEL PARTS"))
                .font(.custom(JPFont.displayName, fixedSize: 13))
                .tracking(13 * 0.32)
                .foregroundStyle(WebTheme.accent)
                .frame(width: 240)
                .offset(y: 18)
                .accessibilityHidden(true)
            coinSlot.offset(x: 34, y: 54)
            crankControl.offset(x: 124, y: 46)
            outlet.offset(x: 70, y: 162)
        }
        .frame(width: 240, height: 250, alignment: .topLeading)
    }

    /// 硬貨の入れ口（真鍮の板・細い口・COIN の刻印）
    private var coinSlot: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(trunk: TrunkRGBA(0x1A1206)))
                .frame(width: 8, height: 34)
                .shadow(color: Color(trunk: TrunkRGBA(r: 255, g: 240, b: 200, a: 0.6)), radius: 0, x: 0, y: 1)
            // 刻印（紙や金属に刷った字・Dynamic Type で伸ばさない）
            Text(verbatim: "COIN")
                .font(.system(size: 7, weight: .bold))
                .tracking(7 * 0.2)
                .foregroundStyle(Color(trunk: TrunkRGBA(0x3A2A12)))
        }
        .frame(width: 64, height: 84)
        .background(LinearGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                           Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                           Gradient.Stop(color: Color(trunk: TrunkRGBA(0x7E6438)), location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .top) { Color.white.opacity(0.5).frame(height: 1).padding(.horizontal, 6) }
        .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    /// ハンドル（96×96）。**回るのは中の絵だけ**——指の角度は回らない枠で測る
    private var crankControl: some View {
        let turning = phase == .turning
        return ZStack {
            Circle()
                .fill(RadialGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x6E5630)), location: 1)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 60))
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(trunk: TrunkRGBA(0x6E5630)), Color(trunk: TrunkRGBA(0xE3C98F)),
                                              Color(trunk: TrunkRGBA(0x6E5630))], startPoint: .leading, endPoint: .trailing))
                .frame(width: 16, height: 84)
                .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
            Circle()
                .fill(RadialGradient(colors: [Color(trunk: TrunkRGBA(0xFFF1C4)), Color(trunk: TrunkRGBA(0xB8955A))],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 17))
                .frame(width: 24, height: 24)
                .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
        }
        .frame(width: 96, height: 96)
        .rotationEffect(.degrees(crank.angle))
        .animation(crank.isHolding || reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.6), value: crank.angle)
        .overlay(Circle().strokeBorder(WebTheme.accent.opacity(turning ? 0.55 : 0), lineWidth: 3))
        .shadow(color: WebTheme.accent.opacity(turning ? 0.45 : 0), radius: 11)
        .shadow(color: Color.black.opacity(0.7), radius: 4, x: 0, y: 4)
        .frame(width: 96, height: 96)
        .contentShape(Circle())
        .gesture(crankGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ハンドルを右へまわす", "Turn the handle to the right"))
        .accessibilityValue("\(crank.percent)%")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { turnTap() }
        .accessibilityIdentifier("trunk.gacha.crank")
    }

    private var crankGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard phase == .turning else { return }
                let dx = Double(value.location.x) - 48, dy = Double(value.location.y) - 48
                if !crank.isHolding {
                    crank.begin(dx: dx, dy: dy)
                } else {
                    notice(crank.drag(dx: dx, dy: dy))
                }
            }
            .onEnded { _ in
                guard phase == .turning else { return }
                notice(crank.end())
            }
    }

    /// 押すたびに4分の1（読み上げの「まわす」も）
    private func turnTap() {
        guard phase == .turning else { return }
        notice(crank.tap())
    }

    /// 目盛りを越えたら触覚と音。1周したら回す
    private func notice(_ crossed: Int) {
        if crossed > 0 {
            ticks += 1
            TrunkSound.tick()
        }
        if crank.isDone, phase == .turning {
            phase = .waiting
            Task { await draw() }
        }
    }

    /// 取り出し口（100×66・真鍮の縁）と、落ちたカプセル
    private var outlet: some View {
        let mouth = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 10)
        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 10)
                .fill(RadialGradient(colors: [Color.black, Color(trunk: TrunkRGBA(0x121214))], center: .top, startRadius: 0, endRadius: 80))
            if phase == .out, let result {
                capsule(top: TrunkGachaColors.top(result.part), bottom: TrunkRGBA(0xF4F1EA), size: 40)
                    .offset(x: 30, y: landed || reduceMotion ? 22 : -38)
                    .opacity(landed || reduceMotion ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 100, height: 66, alignment: .topLeading)
        .clipShape(mouth)
        // 真鍮の縁 3（外側）と黒の 1（モックの `0 0 0 3px #C9A66B, 0 0 0 4px rgba(0,0,0,0.6)`）
        .background { mouth.stroke(Color.black.opacity(0.6), lineWidth: 8) }
        .background { mouth.stroke(WebTheme.accent, lineWidth: 6) }
    }

    // MARK: 硬貨の数と下のボタン

    private var coinRow: some View {
        HStack(spacing: 10) {
            TrunkCoinMark(size: 26)
            HStack(spacing: 4) {
                Text(L("硬貨", "Coins"))
                    .font(.subheadline)
                // 数は SF の等幅の数字（`JPFont.mono`）
                Text("\(coins)")
                    .font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
                // 英語は数のあとに字を置かない（空の字と余白を残さない）
                let unit = L("枚", "")
                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                }
            }
            .foregroundStyle(WebTheme.text)
            Text(L("· 公開の投稿1件で1枚", "· One per public post"))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.faint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trunk.gacha.coins")
    }

    private var bottom: some View {
        VStack(spacing: 8) {
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            switch phase {
            case .idle:
                Button {
                    guard coins > 0 else { return }
                    model.actionError = nil
                    crank = TrunkCrank()
                    phase = .turning
                } label: {
                    if coins > 0 {
                        TrunkButtonFace(title: TrunkGachaText.insertTitle(coins: coins))
                    } else {
                        Text(TrunkGachaText.insertTitle(coins: coins))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TrunkStyle.faint)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(TrunkStyle.line, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .buttonStyle(.plain)
                .disabled(coins == 0 || model.busy)
                .accessibilityIdentifier("trunk.gacha.insert")
            case .turning, .waiting:
                HStack(spacing: 8) {
                    Text(L("ハンドルを右へまわす", "Turn the handle right"))
                    Text("· \(crank.percent)%").font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WebTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: 1))
                .accessibilityElement(children: .combine)
            case .out:
                Button { showOpen = true } label: {
                    TrunkButtonFace(title: L("カプセルを開ける", "Open the capsule"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.gacha.openCapsule")
            }
            Text(TrunkGachaText.hint(coins: coins, phase: phase))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.faint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    /// 1周した: サーバーに回してもらう
    private func draw() async {
        guard let got = await model.gacha() else {
            phase = .idle
            crank = TrunkCrank()
            return
        }
        guard visible else {
            // 返事を待つ間に戻った: 出た部品は部品箱に入っている（硬貨はもう使った）
            toasts.show(TrunkGachaText.arrivedWhileAway(got), kind: .info)
            reset()
            return
        }
        result = got
        landed = false
        phase = .out
        drops += 1
        TrunkSound.drop()
        if reduceMotion {
            landed = true
        } else {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.55)) { landed = true }
        }
    }

    private func reset() {
        phase = .idle
        crank = TrunkCrank()
        result = nil
        landed = false
    }
}

/// カプセルの上の半分の色（部品の段で替える: ふつう＝飴色・めずらしい＝真鍮・とてもめずらしい＝金）
enum TrunkGachaColors {
    static func top(_ part: TrunkPart) -> TrunkRGBA {
        switch part.rarity {
        case .common: return TrunkRGBA(0xC98C3C)
        case .rare: return TrunkRGBA(0xC9A66B)
        case .veryRare: return TrunkRGBA(0xE3BF5E)
        }
    }
}

/// 硬貨（真鍮の平たい円盤・2026-10-18 に描き直した）。**どの画面の硬貨もこの1つ**（カプセルの機械の数の行・
/// トランクの札・部品箱・届いた画面の札・はじめての硬貨の案内）。
///
/// 縁（リム）→ 一段下がった面 → 浮き彫りの内輪 → 「COIN」の刻印（24pt 以上）。光は左上から斜め、縁の照り返しは右下。
/// `tilt` で手前へ倒すと楕円になり、下に厚みの帯が出る（重ねて奥行きを出す）。数値は `TrunkCoinGeometry`
struct TrunkCoinMark: View {
    var size: Double = 26
    /// 手前へ倒す角度（度）。0 は正面
    var tilt: Double = 0
    /// 面の中での回り（度）。刻印の向きが変わる
    var turn: Double = 0

    private var g: TrunkCoinGeometry { TrunkCoinGeometry(size: size, tilt: tilt) }

    private static let shine = Color(trunk: TrunkRGBA(0xFFF1C4))
    private static let pale = Color(trunk: TrunkRGBA(0xF2DFAE))
    private static let mid = Color(trunk: TrunkRGBA(0x8A6B39))
    private static let deep = Color(trunk: TrunkRGBA(0x7E6438))
    private static let shade = Color(trunk: TrunkRGBA(0x6E5630))
    private static let edgeDark = Color(trunk: TrunkRGBA(0x3E301A))
    private static let ink = Color(trunk: TrunkRGBA(0x3A2A12))
    private static let line = Color(trunk: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.45))

    var body: some View {
        let g = self.g
        ZStack(alignment: .top) {
            // 厚みの帯（倒したときだけ・面の下にずらして見せる）
            if g.edgeDepth > 0 {
                Circle()
                    .fill(LinearGradient(colors: [Self.deep, Self.edgeDark], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size, height: g.size)
                    .scaleEffect(x: 1, y: g.squash, anchor: .top)
                    .frame(width: g.size, height: g.size * g.squash, alignment: .top)
                    .offset(x: 0, y: g.edgeDepth)
            }
            face(g)
                .frame(width: g.size, height: g.size)
                .scaleEffect(x: 1, y: g.squash, anchor: .top)
                .frame(width: g.size, height: g.size * g.squash, alignment: .top)
        }
        .frame(width: g.size, height: g.drawnHeight, alignment: .top)
        .shadow(color: Color.black.opacity(g.shadowRadius > 0 ? 0.6 : 0), radius: g.shadowRadius, x: 0, y: g.shadowY)
        .accessibilityHidden(true)
    }

    /// 正面から見た面（真円）
    private func face(_ g: TrunkCoinGeometry) -> some View {
        ZStack {
            // 縁（リム）: 左上が照り、右下が陰
            Circle()
                .fill(LinearGradient(stops: [Gradient.Stop(color: Self.shine, location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Self.shade, location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // 一段下がった面: 光の向きを逆に（左上が陰・右下が照り＝くぼみ）
            Circle()
                .fill(LinearGradient(stops: [Gradient.Stop(color: Self.mid, location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.55),
                                             Gradient.Stop(color: Self.pale, location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(g.rimWidth)
            // 段の境の細い影
            Circle()
                .strokeBorder(Self.line, lineWidth: max(0.5, g.outlineWidth * 0.6))
                .padding(g.rimWidth)
            // 浮き彫りの内輪（左上が照り・右下が陰）
            Circle()
                .strokeBorder(LinearGradient(colors: [Self.pale, Self.shade], startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: g.ringWidth)
                .padding(g.ringInset)
            if g.showsLetters {
                // 刻印（彫った字の下の縁に照り・板の COIN の口と同じ字）
                Text(verbatim: "COIN")
                    .font(.system(size: g.letterSize, weight: .bold))
                    .tracking(g.letterSize * 0.2)
                    // 字送りは最後の字の後ろにも付くので、その半分だけ左へ寄せて真ん中に置く
                    .offset(x: g.letterSize * 0.1, y: 0)
                    .foregroundStyle(Self.ink)
                    .shadow(color: Color(trunk: TrunkRGBA(r: 255, g: 240, b: 200, a: 0.6)), radius: 0, x: 0, y: max(0.5, g.size * 0.008))
                    .rotationEffect(.degrees(turn))
            }
            // 真鍮の光: 左上から斜めに差す帯
            LinearGradient(stops: [Gradient.Stop(color: Color.white.opacity(0), location: 0.18),
                                   Gradient.Stop(color: Color.white.opacity(0.38), location: 0.32),
                                   Gradient.Stop(color: Color.white.opacity(0), location: 0.46)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(Circle())
                .allowsHitTesting(false)
            // 外の縁の暗い線（板の inset 2px）
            Circle()
                .strokeBorder(Self.line, lineWidth: g.outlineWidth)
        }
    }
}

// MARK: - カプセルを開けた

/// カプセルを開けた（モック GachaOpen.dc.html・全画面）
struct TrunkGachaOpenView: View {
    @ObservedObject var model: TrunkViewModel
    let result: TrunkGachaResult

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    private var part: TrunkPart { result.part }
    private var equippedNow: Bool { model.state?.equipped.ids(part.kind).contains(part.id) ?? false }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.36)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text(Labels.Common.close)
                            .font(.body)
                            .foregroundStyle(WebTheme.text)
                            .padding(.horizontal, 10)
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trunk.gachaOpen.close")
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        stage
                        info
                    }
                }
                actions
            }
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.gachaOpen")
    }

    private var heading: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TrunkRarityMark(rarity: part.rarity, size: 9)
                Text(TrunkGachaText.eyebrow(part))
                    .font(JPFont.eyebrow)
                    .tracking(11 * 0.12)
                    .foregroundStyle(WebTheme.accent)
            }
            .padding(.top, 8)
            Text(TrunkGachaText.title(part))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(result.duplicate
                 ? L("持っている部品でした。かけらを1つ受け取りました（\(TrunkPartsBoxText.filledFragments(result.fragments)) / 5）",
                     "You already had this. You got a fragment (\(TrunkPartsBoxText.filledFragments(result.fragments)) / 5)")
                 : L("どの型のトランクにも付けられます", "Fits every trunk style"))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    /// 開いたカプセルの半分2つと、真ん中の部品（後ろに真鍮の淡い光）
    private var stage: some View {
        ZStack(alignment: .topLeading) {
            TrunkStyle.glow(width: 330, height: 300).offset(x: 30, y: 10)
            capsuleHalf(top: true)
                .rotationEffect(.degrees(-24))
                .offset(x: 40, y: 30)
            capsuleHalf(top: false)
                .rotationEffect(.degrees(18))
                .offset(x: 226, y: 250)
            TrunkPartView(part: part, size: 160)
                .offset(x: 115, y: 80)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkPartDrawing.accessibilityLabel(part))
                .accessibilityAddTraits(.isImage)
        }
        .frame(width: 390, height: 360, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    private func capsuleHalf(top: Bool) -> some View {
        ZStack {
            if top {
                LinearGradient(colors: [Color(trunk: TrunkGachaColors.top(part)).opacity(0.95),
                                        Color(trunk: TrunkGachaColors.top(part).filtered(brightness: 0.82))],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(trunk: TrunkRGBA(0xF4F1EA)), Color(trunk: TrunkRGBA(0xCFC8B8))],
                               startPoint: .top, endPoint: .bottom)
            }
            RadialGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.38, y: top ? 0.7 : 0.3), startRadius: 0, endRadius: 40)
        }
        .frame(width: 120, height: 60)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: top ? 60 : 0, bottomLeadingRadius: top ? 0 : 60,
                                          bottomTrailingRadius: top ? 0 : 60, topTrailingRadius: top ? 60 : 0))
        .shadow(color: Color.black.opacity(0.6), radius: 9, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    private var info: some View {
        let owned = TrunkPartsBoxText.collected(model.state?.ownedParts ?? [], kind: part.kind)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("\(part.kind.title)の部品", "\(part.kind.title) part"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                Text(L("集めた\(part.kind.tabName) \(owned) / 12", "\(part.kind.tabName) collected \(owned) / 12"))
                    .font(JPFont.mono(12))
                    .foregroundStyle(TrunkStyle.faint)
            }
            Spacer()
            Text(L("古び方は\nトランクと一緒に進む", "Ages along\nwith your trunk"))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.trailing)
                .lineSpacing(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    guard let state = model.state else { return }
                    let next = TrunkEquipText.equipping(part, on: state.equipped)
                    guard !next.full else {
                        // いっぱい: 黙って外さず、付け替えの画面と同じ一言
                        model.actionError = TrunkEquipText.fullNote(part.kind)
                        return
                    }
                    if await model.equip(next.equipped) {
                        dismiss()
                        toasts.show(L("トランクに付けました", "Put on your trunk"))
                    }
                }
            } label: {
                TrunkButtonFace(title: equippedNow ? L("付けています", "Already on") : L("トランクに付ける", "Put it on my trunk"))
            }
            .buttonStyle(.plain)
            .disabled(model.busy || equippedNow)
            .accessibilityIdentifier("trunk.gachaOpen.equip")
            Button { dismiss() } label: {
                TrunkButtonFace(title: L("部品箱にしまう", "Keep in the parts box"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.gachaOpen.keep")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }
}

/// 段の印（ふつう＝灰の輪・めずらしい＝真鍮の丸・とてもめずらしい＝金のひし形に黒と真鍮の縁）。**色だけで分けない**
struct TrunkRarityMark: View {
    let rarity: TrunkPartRarity
    var size: Double = 12

    var body: some View {
        Group {
            switch rarity {
            case .common:
                Circle().strokeBorder(TrunkStyle.muted, lineWidth: 1.5)
            case .rare:
                Circle().fill(WebTheme.accent)
            case .veryRare:
                Rectangle()
                    .fill(Color(trunk: TrunkRGBA(0xE3C98F)))
                    .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2).padding(-2))
                    .overlay(Rectangle().strokeBorder(WebTheme.accent, lineWidth: 1).padding(-3))
                    .rotationEffect(.degrees(45))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 中身と確率

/// 中身と確率（モック GachaOdds.dc.html）。**確率は必ず出す**（段の確率と、1点あたりの確率）
struct TrunkGachaOddsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("出る確率", "Odds"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(Array(TrunkPartRarity.allCases.enumerated()), id: \.offset) { i, rarity in
                        HStack {
                            HStack(spacing: 10) {
                                TrunkRarityMark(rarity: rarity)
                                Text(rarity.name)
                                    .font(.subheadline)
                                    .foregroundStyle(WebTheme.text)
                            }
                            Spacer()
                            Text("\(rarity.percent)%")
                                .font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
                                .foregroundStyle(WebTheme.text)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) {
                            if i < TrunkPartRarity.allCases.count - 1 { TrunkStyle.line.frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
                // 1点あたり（段の確率 ÷ 段の点数）
                Text(L("同じ段の中は、どの部品も同じ確率です。1点あたり: ",
                       "Within a tier every part is equally likely. Per part: ")
                     + TrunkPartRarity.allCases.map { "\($0.name) \(TrunkGachaText.percentText(TrunkGachaText.perPart($0)))" }
                        .joined(separator: " · "))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .accessibilityIdentifier("trunk.odds.perPart")
                Text(L("入っている部品 · 9 種類 · 108 点", "Inside · 9 kinds · 108 parts"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array(TrunkPartKind.allCases.enumerated()), id: \.offset) { i, kind in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.subheadline)
                                    .foregroundStyle(WebTheme.text)
                                Text(kind.examples)
                                    .font(JPFont.footnote)
                                    .foregroundStyle(TrunkStyle.faint)
                            }
                            Spacer()
                            Text(L("\(TrunkPartKind.perKind) 点", "\(TrunkPartKind.perKind)"))
                                .font(JPFont.mono(13))
                                .foregroundStyle(TrunkStyle.muted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(minHeight: 48)
                        .overlay(alignment: .bottom) {
                            if i < TrunkPartKind.allCases.count - 1 { TrunkStyle.line.frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
                Text(L("硬貨は公開の投稿1件につき1枚（1日3枚まで）。お金では買えません。同じ部品が出たときは「かけら」になり、かけら5つで好きな部品と1つ交換できます。",
                       "You get one coin per public post (up to 3 a day). Coins can\u{2019}t be bought. A part you already have becomes a fragment; five fragments get you any part you choose."))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .webScreen()
        .navigationTitle(L("中身と確率", "Odds"))
        .navigationBarTitleDisplayMode(.inline)
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.odds")
    }
}
