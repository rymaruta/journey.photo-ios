import SwiftUI

/// カプセルの機械（モック Gacha.dc.html・2026-10-17 次の版、2026-11-23 札 #716 の案の頁で磨いた版）。
///
/// **主ボタンは「硬貨を入れて回す」1つ（2026-11-12 判断・1.1.83 の案）**: 押すと重ねた硬貨のいちばん上が入れ口へ飛び、
/// ハンドルが自分で1周してカプセルが落ちる（入れる → 回す → 開ける → 付けるの 4 回が 3 回に）。ハンドルを指で回しても出る——
/// 硬貨を入れる手順は要らず、押さえた所から回り始める。**途中で離すとハンドルは元へ戻り、硬貨は減らない**（部品と硬貨は
/// 1周したときにサーバーが決める・`TrunkGachaFlow`）。写真の無い画面なので主ボタンは真鍮の塗り。硬貨 0 のときは投稿への1手。
///
/// 2026-11-23（札 #716・owner 採用）の4つの直し（押す所、ボタンの言葉、流れは変えない）:
/// - ハンドルのまわりに 30° ごとの目盛り 12 個。回すと明るい真鍮（#F3DCA6）に点き、1周がどこまでかが絵で分かる。
///   指で回すと目盛りの間は重く、72% を越えるとカチッと次へ跳ぶ（`TrunkCrank.detent(raw:)`）。中のカプセルが揺れる
/// - 押すと、重ねた硬貨のいちばん上が羅針盤の顔を見せたまま入れ口へ飛んで沈む
/// - 取り出し口に煙ガラスのふた。1周すると溜めてから（8° 行き過ぎて戻る）カプセルが落ちて1回弾む。底に着いた瞬間に重い触覚と光の輪
/// - 圏外と分かっているときは回す前に一言出し、ボタンを押せない。0枚は入れ口が暗く、ハンドルを触ると小さく揺れる
///
/// 動かすのは位置、向き、透明度、大きさだけ（`TrunkMotion` の時間と曲線）。動かない機械の絵は1枚にまとめ（`drawingGroup`）、
/// 動く物（ハンドル、中のカプセルの3つの層、取り出し口のカプセル）は別の層。「視差効果を減らす」の人には硬貨の飛ぶ動き、
/// ふた、溜め、落ちる弾み、揺れを出さず、終わった形をすぐ出す（触覚は残す）
struct TrunkGachaView: View {
    @ObservedObject var model: TrunkViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity
    @State private var phase: TrunkGachaPhase = .idle
    /// 画面に出ているか（1周したあと返事を待つ間に戻った人へ、一言で知らせる）
    @State private var visible = false
    @State private var crank = TrunkCrank()
    @State private var ticks = 0
    @State private var drops = 0
    @State private var result: TrunkGachaResult?
    @State private var showOpen = false
    /// 開けた画面の「もう1回まわす」を押した（閉じたら続けて回す）
    @State private var againRequested = false
    /// ハンドルが自分で回っている（ボタン・ハンドルを軽く押した）。その間は指で回さない
    @State private var autoTurning = false
    /// 1周したところの溜め（度・8° 行き過ぎて戻る）
    @State private var windUp = 0.0
    /// 0枚・圏外でハンドルを触った（小さく揺れる）
    @State private var wiggleStart: Date?
    @State private var wiggledThisTouch = false
    /// 目盛りを越えた回（中のカプセルの層をずらす）
    @State private var jostleBeat = 0
    @State private var jostleOn = false
    @State private var jostleK = 0.0
    /// カプセルが落ち始めた時刻・光の輪を出した時刻
    @State private var dropStart: Date?
    @State private var ringStart: Date?
    /// 取り出し口のふた（1 は閉じている・負は上へ跳ね上がった）
    @State private var flap = 1.0
    /// 硬貨を入れる動き（重ねた硬貨のいちばん上を隠し、飛ぶ硬貨を出す）
    @State private var inserting = false
    @State private var flyAt: CGPoint?
    @State private var flyScale = 1.0
    @State private var flyOpacity = 1.0
    /// 重ねた硬貨と機械の絵の枠（飛ぶ硬貨の行き先を決める・`space` の座標）
    @State private var stackFrame = CGRect.zero
    @State private var machineFrame = CGRect.zero
    @ObservedObject private var tabRouter = TabRouter.shared

    /// 機械の絵の大きさ（モック 300×540）
    private static let machine = (w: 300.0, h: 540.0)
    /// 飛ぶ硬貨の座標の名前
    private static let space = "trunk.gacha.space"
    /// 入れ口の口の真ん中（機械の絵の座標・入れ口の板を左へ 4 寄せた所）。上は入れ口の上、下は沈んだ所
    private static let slotAbove = CGPoint(x: 92, y: 326.5)
    private static let slotInside = CGPoint(x: 92, y: 352.5)

    private var coins: Int {
        // 入れた硬貨は、入れる動きの間から、回し終えてサーバーが答えるまで手元の数から引いて見せる
        TrunkGachaFlow.shownCoins(stored: model.state?.coins ?? 0, phase: phase, inserting: inserting)
    }

    /// 待っているときの操作（0枚・圏外は回せず、ハンドルは揺れるだけ・`TrunkGachaFlow.idle`）
    private var idleControls: TrunkGachaFlow.Idle {
        TrunkGachaFlow.idle(coins: coins, offline: offline, busy: model.busy)
    }

    /// 圏外と分かっている（回す前に言い、ボタンを押せない）
    private var offline: Bool { connectivity.isOffline }
    /// 回せない（0枚・圏外）。入れ口と目盛りを暗く、ハンドルは触ると揺れるだけ
    private var cannotTurn: Bool { coins == 0 || offline }

    var body: some View {
        GeometryReader { geo in
            let k = min(1, max(0.55, (Double(geo.size.height) - 190) / Self.machine.h), (Double(geo.size.width) - 40) / Self.machine.w)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    machine
                        .scaleEffect(k, anchor: .top)
                        .frame(width: Self.machine.w * k, height: Self.machine.h * k, alignment: .top)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: { machineFrame = $0 })
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    coinRow
                        .padding(.top, 2)
                    Spacer(minLength: 8)
                    bottom
                }
                // 入れ口へ飛ぶ硬貨（顔を見せたまま・羅針盤の 26pt）
                if let flyAt {
                    TrunkCoinMark(size: 26)
                        .scaleEffect(flyScale)
                        .opacity(flyOpacity)
                        .position(x: flyAt.x, y: flyAt.y)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named(Self.space))
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
        .fullScreenCover(isPresented: $showOpen, onDismiss: closedOpen) {
            if let result {
                TrunkGachaOpenView(model: model, result: result, onAgain: { againRequested = true })
            }
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
            // 球と胴の間の真鍮の帯（上の照りと、下の影）
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x7E6438)), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Capsule().fill(Color.white.opacity(0.4)).frame(height: 4).padding(.horizontal, 4).padding(.top, 1) }
                .frame(width: 216, height: 22)
                .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 3)
                .offset(x: 42, y: 254)
            cabinet.offset(x: 30, y: 272)
            // 脚と足もとの真鍮の帯、足もとの光
            ForEach([40.0, 230.0], id: \.self) { x in
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(LinearGradient(colors: [WebTheme.accent, Color(trunk: TrunkRGBA(0x6E5630))], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 14)
                    .offset(x: x, y: 518)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x7E6438)), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Capsule().fill(Color.white.opacity(0.4)).frame(height: 2).padding(.horizontal, 4).padding(.top, 1) }
                .frame(width: 240, height: 10)
                .offset(x: 30, y: 514)
            EllipticalGradient(colors: [WebTheme.accent.opacity(0.2), Color.clear])
                .frame(width: 232, height: 14)
                .offset(x: 34, y: 528)
        }
        .frame(width: Self.machine.w, height: Self.machine.h, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("黒塗りに真鍮の金具のカプセルの機械", "A black capsule machine with brass fittings"))
    }

    /// ガラスの球（260×260）とカプセル。カプセルは3つの層に分け、目盛りを越えるたびに層ごとにずらして弾ませて戻す。
    /// ガラスの光と縁は上の層、待っているときはガラスをゆっくり光が走る
    private var globe: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.10), location: 0),
                                   Gradient.Stop(color: Color.white.opacity(0.02), location: 0.6),
                                   Gradient.Stop(color: Color.black.opacity(0.25), location: 1)],
                           center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 180)
            capsuleLayers
            TrunkGachaGlass()
            if phase == .idle && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible)) { ctx in
                    let s = TrunkMotion.sweep(elapsed: ctx.date.timeIntervalSinceReferenceDate)
                    LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.22), Color.white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 45, height: 294)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -88 + s.x, y: -18)
                        .opacity(s.opacity)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: 260, height: 260, alignment: .topLeading)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
        .accessibilityHidden(true)
    }

    /// 中のカプセルの3つの層（回している間は小さく震え、目盛りを越えるたびにずれて戻る）
    private var capsuleLayers: some View {
        let jigging = (phase == .turning || phase == .waiting) && !reduceMotion
        return TimelineView(.animation(minimumInterval: nil, paused: !jigging)) { ctx in
            let j = jigging ? TrunkMotion.jig(elapsed: ctx.date.timeIntervalSinceReferenceDate) : (dx: 0.0, dy: 0.0)
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { layer in
                    let shift = TrunkMotion.jostle(layer: layer, beat: jostleBeat, k: jostleK)
                    TrunkGachaCapsuleLayer(layer: layer)
                        .rotationEffect(.degrees(jostleOn ? shift.rotation : 0))
                        .offset(x: jostleOn ? shift.dx : 0, y: jostleOn ? shift.dy : 0)
                }
            }
            .offset(x: j.dx, y: j.dy)
        }
    }

    /// 胴（240×250）: 銘・硬貨の入れ口・ハンドル・取り出し口
    private var cabinet: some View {
        ZStack(alignment: .topLeading) {
            TrunkGachaCabinetBody()
            coinSlot.offset(x: 30, y: 54)
            crankControl.offset(x: 107, y: 42)
            outlet.offset(x: 70, y: 162)
        }
        .frame(width: 240, height: 250, alignment: .topLeading)
    }

    /// 硬貨の入れ口（真鍮の板・細い口・COIN の刻印）。硬貨があれば背が呼吸するように光り、0枚・圏外は暗い
    private var coinSlot: some View {
        ZStack {
            if !cannotTurn && phase == .idle && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible)) { ctx in
                    let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: TrunkMotion.pulseSeconds) / TrunkMotion.pulseSeconds
                    let half = p < 0.5 ? TrunkBezier.easeInOut.value(p * 2) : TrunkBezier.easeInOut.value((1 - p) * 2)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(RadialGradient(colors: [WebTheme.accent.opacity(0.2), WebTheme.accent.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 54))
                        .frame(width: 88, height: 108)
                        .opacity(0.45 + 0.55 * half)
                }
                .allowsHitTesting(false)
            }
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
            .opacity(coins == 0 ? 0.55 : 1)
        }
        .frame(width: 64, height: 84)
        .accessibilityHidden(true)
    }

    /// ハンドル（案の頁の 0.85 倍・81.6）と、まわりの黒い座と 30° ごとの目盛り 12 個。**回るのは中の絵だけ**——指の角度は
    /// 回らない枠（104×104・当たりはこの枠）で測る
    private var crankControl: some View {
        ZStack {
            TrunkGachaCrankSeat(dim: cannotTurn)
            TrunkGachaCrankTicks(lit: phase == .turning || phase == .waiting ? crank.litTicks : 0, dim: cannotTurn)
            TimelineView(.animation(minimumInterval: nil, paused: wiggleStart == nil)) { ctx in
                let wiggle = wiggleStart.map { TrunkMotion.wiggle.value(ctx.date.timeIntervalSince($0) / TrunkMotion.wiggleSeconds) } ?? 0
                TrunkGachaCrankDisc()
                    .rotationEffect(.degrees(crank.angle + windUp + wiggle))
            }
            // ハンドルの照りと細い輪（回らない）
            TrunkGachaCrankGloss()
        }
        .frame(width: 104, height: 104)
        .contentShape(Circle())
        .gesture(crankGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .idle ? TrunkGachaText.spinTitle(coins: coins) : TrunkGachaText.turningTitle)
        .accessibilityValue("\(crank.percent)%")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { turnTap() }
        .accessibilityIdentifier("trunk.gacha.crank")
    }

    /// ハンドルを指で回す（2026-11-12 判断）。硬貨があれば、入れる手順なしに押さえた所から回り始める。
    /// 目盛りの間は重く、72% を越えるとカチッと次へ跳ぶ（2026-11-23・札 #716）。
    /// 離したときの行き先は `TrunkGachaFlow.release`（1周＝回す・押しただけ＝自分で1周・途中＝元へ戻る）
    private var crankGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !autoTurning else { return }
                if phase == .idle {
                    // 0枚・圏外: 触ると小さく揺れるだけ（1回の押さえで1回）
                    guard !cannotTurn else {
                        if !wiggledThisTouch { wiggledThisTouch = true; wiggle() }
                        return
                    }
                    guard idleControls.crankTurns else { return }
                    model.actionError = nil
                    crank = TrunkCrank()
                    phase = .turning
                }
                guard phase == .turning else { return }
                let dx = Double(value.location.x) - 52, dy = Double(value.location.y) - 52
                if !crank.isHolding {
                    crank.begin(dx: dx, dy: dy)
                } else {
                    var next = crank
                    let crossed = next.drag(dx: dx, dy: dy)
                    if crossed > 0 && !reduceMotion {
                        withAnimation(.timingCurve(0.2, 0.9, 0.3, 1.35, duration: TrunkMotion.detentSnapSeconds)) { crank = next }
                        jostle(0.7)
                    } else {
                        crank = next
                    }
                    notice(crossed)
                }
            }
            .onEnded { _ in
                wiggledThisTouch = false
                guard phase == .turning, !autoTurning else { return }
                let next = TrunkGachaFlow.release(crank)
                crank.letGo()
                switch next {
                case .draw: break
                case .autoTurn:
                    // 押しただけ: ボタンと同じ道（硬貨が入れ口へ飛んでから自分で1周）。押さえた所で始めた回しは取り消す
                    crank = TrunkCrank()
                    phase = .idle
                    Task { await autoTurn() }
                case .springBack: springBack()
                }
            }
    }

    /// 押す（読み上げの「まわす」も）: 硬貨を入れて自分で1周
    private func turnTap() {
        guard phase == .idle || (phase == .turning && !autoTurning) else { return }
        guard phase != .idle || !cannotTurn else { wiggle(); return }
        Task { await autoTurn() }
    }

    /// 0枚・圏外でハンドルを触った: 小さく揺れる（動きを減らす設定では揺らさない）
    private func wiggle() {
        guard !reduceMotion else { return }
        let began = Date()
        wiggleStart = began
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.wiggleSeconds * 1_000_000_000))
            if wiggleStart == began { wiggleStart = nil }
        }
    }

    /// 硬貨を入れてハンドルが自分で1周する（目盛りごとに触覚と音）。「視差効果を減らす」の人には待たずに回し切る
    private func autoTurn() async {
        guard !autoTurning, phase == .turning || idleControls.canTurn else { return }
        autoTurning = true
        defer { autoTurning = false }
        if phase == .idle {
            model.actionError = nil
            crank = TrunkCrank()
            await insertCoin()
            guard visible else { return }
            phase = .turning
        }
        guard phase == .turning else { return }
        while !crank.isDone, phase == .turning {
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: UInt64(TrunkGachaFlow.autoStepSeconds * 1_000_000_000))
                if Task.isCancelled { return }
            }
            // 回っている途中で画面を離れた: 元へ戻して送らない（硬貨は減らない・2026-11-12 判断・確かめ役の指摘）
            guard TrunkGachaFlow.keepsAutoTurning(visible: visible) else {
                crank = TrunkCrank()
                phase = .idle
                return
            }
            var next = crank
            let crossed = next.autoAdvance()
            if reduceMotion {
                crank = next
            } else {
                withAnimation(.timingCurve(0.2, 0.9, 0.3, 1.35, duration: TrunkMotion.autoStepSnapSeconds)) { crank = next }
                jostle(0.6)
            }
            notice(crossed)
        }
    }

    /// 重ねた硬貨のいちばん上が、羅針盤の顔を見せたまま入れ口の上へ（0.26 秒）、入れ口へ沈んで消える（0.16 秒）
    private func insertCoin() async {
        guard !reduceMotion, stackFrame != .zero, machineFrame != .zero else { return }
        let k = Double(machineFrame.width) / Self.machine.w
        func onMachine(_ p: CGPoint) -> CGPoint {
            CGPoint(x: Double(machineFrame.minX) + Double(p.x) * k, y: Double(machineFrame.minY) + Double(p.y) * k)
        }
        // 入れる前の重ねた硬貨のいちばん上から（入れ始めると数の行は1枚引いて描く）
        let n = TrunkCoinStack.drawn(coins)
        let from = CGPoint(x: Double(stackFrame.minX) + TrunkCoinStack.xShift(n - 1) + 13, y: Double(stackFrame.minY) + 13 - 6)
        flyScale = 1
        flyOpacity = 1
        flyAt = from
        inserting = true
        withAnimation(.timingCurve(0.3, 0.7, 0.3, 1, duration: TrunkMotion.insertLiftSeconds)) { flyAt = onMachine(Self.slotAbove) }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.insertLiftSeconds * 1_000_000_000))
        withAnimation(.timingCurve(0.5, 0, 0.9, 0.5, duration: TrunkMotion.insertSinkSeconds)) {
            flyAt = onMachine(Self.slotInside)
            flyScale = TrunkMotion.insertSinkScale
            flyOpacity = 0
        }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.insertSinkSeconds * 1_000_000_000))
        flyAt = nil
        inserting = false
    }

    /// 中のカプセルの3つの層を少しずらして（0.07 秒）弾ませて戻す（0.32 秒）。強さ k
    private func jostle(_ k: Double) {
        guard !reduceMotion else { return }
        let beat = jostleBeat + 1
        withAnimation(.timingCurve(0, 0, 0.58, 1, duration: TrunkMotion.jostleOutSeconds)) {
            jostleBeat = beat
            jostleK = k
            jostleOn = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((TrunkMotion.jostleOutSeconds + 0.005) * 1_000_000_000))
            guard jostleBeat == beat else { return }
            withAnimation(.timingCurve(0.3, 1.5, 0.5, 1, duration: TrunkMotion.jostleBackSeconds)) { jostleOn = false }
        }
    }

    /// 途中で離した: ハンドルを元へ戻す（硬貨は減っていない・サーバーには何も送っていない）。目盛りの灯りも消える
    private func springBack() {
        if reduceMotion {
            crank = TrunkCrank()
        } else {
            withAnimation(.timingCurve(0.3, 1.35, 0.5, 1, duration: TrunkMotion.springBackSeconds)) { crank = TrunkCrank() }
            jostle(0.35)
        }
        phase = .idle
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

    /// 1周したところの溜め（0.06 秒待って 8° 行き過ぎ、戻る）。送るのはこの間
    private func windUpTurn() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.windUpPause * 1_000_000_000))
        withAnimation(.timingCurve(0, 0, 0.58, 1, duration: TrunkMotion.windUpOutSeconds)) { windUp = TrunkMotion.windUpOvershoot }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.windUpOutSeconds * 1_000_000_000))
        withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: TrunkMotion.windUpBackSeconds)) { windUp = 0 }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.windUpBackSeconds * 1_000_000_000))
    }

    /// 取り出し口（100×66・真鍮の縁）と、落ちたカプセル・煙ガラスのふた・底に着いた光の輪
    private var outlet: some View {
        let mouth = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 10)
        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 10)
                .fill(RadialGradient(colors: [Color.black, Color(trunk: TrunkRGBA(0x121214))], center: .top, startRadius: 0, endRadius: 80))
            TimelineView(.animation(minimumInterval: nil, paused: dropStart == nil && ringStart == nil)) { ctx in
                ZStack(alignment: .topLeading) {
                    if phase == .out, let result {
                        let y = dropStart.map { TrunkMotion.dropOffset(elapsed: ctx.date.timeIntervalSince($0)) } ?? 0
                        TrunkGachaCapsule(top: TrunkGachaColors.top(result.part), bottom: TrunkRGBA(0xF4F1EA), size: 40, deep: true)
                            .offset(x: 30, y: 22 + y)
                            .accessibilityHidden(true)
                    }
                    if let ringStart {
                        let r = TrunkMotion.outletRing(elapsed: ctx.date.timeIntervalSince(ringStart))
                        TrunkGachaOutletRing()
                            .frame(width: 60, height: 14)
                            .scaleEffect(r.scale)
                            .opacity(r.opacity)
                            .offset(x: 20, y: 51)
                    }
                }
            }
            // 煙ガラスのふた（上の真鍮の線から跳ね上がる）
            ZStack(alignment: .top) {
                Color.white.opacity(0.07)
                WebTheme.accent.frame(height: 2).padding(.top, 2)
            }
            .frame(width: 100, height: 66)
            .scaleEffect(x: 1, y: flap, anchor: .top)
            .allowsHitTesting(false)
        }
        .frame(width: 100, height: 66, alignment: .topLeading)
        .clipShape(mouth)
        // 真鍮の縁 3（外側）と黒の 1（モックの `0 0 0 3px #C9A66B, 0 0 0 4px rgba(0,0,0,0.6)`）、縁の照り
        .background { mouth.stroke(Color.black.opacity(0.6), lineWidth: 8) }
        .background { mouth.stroke(WebTheme.accent, lineWidth: 6) }
        .overlay { mouth.stroke(Color(trunk: TrunkRGBA(r: 255, g: 241, b: 196, a: 0.55)), lineWidth: 1.2).offset(y: -2.5) }
    }

    // MARK: 硬貨の数と下のボタン

    /// 手元の枚数だけ重ねた硬貨（5枚まで描き、数は字で）と等幅の数字。0枚は影絵
    private var coinRow: some View {
        HStack(spacing: 10) {
            TrunkCoinStackView(coins: coins, size: 26)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: { stackFrame = $0 })
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
            Text(L("公開の投稿1件で1枚", "One per public post"))
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
                if coins > 0 {
                    if idleControls.offlineNote {
                        // 圏外と分かっている: 回す前に言う（押してから1周して断らない・2026-11-23 札 #716）
                        Text(TrunkGachaText.offlineNote)
                            .font(JPFont.footnote)
                            .foregroundStyle(TrunkStyle.muted)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("trunk.gacha.offline")
                    }
                    Button { Task { await autoTurn() } } label: {
                        TrunkButtonFace(title: TrunkGachaText.spinTitle(coins: coins))
                    }
                    .buttonStyle(.plain)
                    .disabled(!idleControls.canTurn)
                    .opacity(idleControls.offlineNote ? 0.45 : 1)
                    .accessibilityIdentifier("trunk.gacha.insert")
                } else {
                    // 硬貨 0: 埋め方の一手（投稿へ1回で・2026-11-12 判断）
                    Button { tabRouter.openPost(.photo) } label: {
                        TrunkButtonFace(title: L("写真を投稿する", "Post a photo"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trunk.gacha.post")
                }
            case .turning, .waiting:
                // 回っている間（主ボタンと同じ高さ 50 で入れ替え、帯を跳ねさせない）
                HStack(spacing: 8) {
                    Text(TrunkGachaText.turningTitle)
                    Text("\(crank.percent)%").font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
                }
                .jpCapsuleFace(font: JPFont.bodyEmphasis, text: WebTheme.accent, fill: Color.clear,
                               border: WebTheme.accent.opacity(0.6), fullWidth: true,
                               minHeight: JPHeight.primaryButton, textInset: nil)
                .accessibilityElement(children: .combine)
            case .out:
                Button { showOpen = true } label: {
                    TrunkButtonFace(title: L("カプセルを開ける", "Open the capsule"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.gacha.openCapsule")
            }
            // 結果は動きで見せ、文は次にできることだけ（空の回も高さを取って帯を跳ねさせない）
            let hint = TrunkGachaText.spinHint(coins: coins, phase: phase, offline: offline)
            Text(hint.isEmpty ? " " : hint)
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.faint)
                .multilineTextAlignment(.center)
                .accessibilityHidden(hint.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    /// 1周した: 溜めの間にサーバーに回してもらう
    private func draw() async {
        let wound = Task { await windUpTurn() }
        let got = await model.gacha(offline: connectivity.isOffline)
        await wound.value
        guard let got else {
            springBack()
            return
        }
        guard visible else {
            // 返事を待つ間に戻った: 出た部品は部品箱に入っている（硬貨はもう使った）
            toasts.show(TrunkGachaText.arrivedWhileAway(got), kind: .info)
            reset()
            return
        }
        result = got
        phase = .out
        if reduceMotion {
            // 終わった形をすぐ出す（触覚と音は残す）
            drops += 1
            TrunkSound.drop()
            return
        }
        // ふたが跳ね上がり、カプセルが落ちて底に着いた瞬間に重い触覚と光の輪、1回弾む
        let began = Date()
        dropStart = began
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: TrunkMotion.flapSeconds)) { flap = TrunkMotion.flapOpen }
        try? await Task.sleep(nanoseconds: UInt64((TrunkMotion.flapSeconds + 0.02) * 1_000_000_000))
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: TrunkMotion.flapSeconds)) { flap = 1 }
        try? await Task.sleep(nanoseconds: UInt64(max(0, TrunkMotion.landsAt - TrunkMotion.flapSeconds - 0.02) * 1_000_000_000))
        drops += 1
        TrunkSound.drop()
        jostle(0.25)
        let rang = Date()
        ringStart = rang
        try? await Task.sleep(nanoseconds: UInt64(max(TrunkMotion.outletRingSeconds, TrunkMotion.dropSeconds - TrunkMotion.landsAt) * 1_000_000_000))
        if dropStart == began { dropStart = nil }
        if ringStart == rang { ringStart = nil }
    }

    /// 開けた画面を閉じた（「もう1回まわす」なら続けて回す）
    private func closedOpen() {
        reset()
        // 開けた画面を閉じて機械に戻っている（全画面の間に `onDisappear` が来ていても、続けて回せるように）
        visible = true
        let again = againRequested
        againRequested = false
        guard TrunkGachaFlow.afterOpenClosed(again: again, coins: coins, offline: offline) else { return }
        Task { await autoTurn() }
    }

    private func reset() {
        phase = .idle
        crank = TrunkCrank()
        result = nil
        dropStart = nil
        ringStart = nil
        flap = 1
        windUp = 0
    }
}

// MARK: - 機械の動かない絵（入力が変わらなければ描き直さない層）

/// カプセル1つ（上の半分の色・下の半分の色・真ん中の継ぎ目）。`deep`: 球の陰と縁の照り（案の頁の深い描き方）
struct TrunkGachaCapsule: View {
    let top: TrunkRGBA
    let bottom: TrunkRGBA
    let size: Double
    var deep = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(trunk: bottom)
            Color(trunk: top).opacity(0.9).frame(height: size / 2)
            RadialGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.4)
            Color.black.opacity(0.25).frame(height: 2).offset(y: size / 2 - 1)
            if deep {
                RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.12), location: 0),
                                       Gradient.Stop(color: Color.black.opacity(0), location: 0.45),
                                       Gradient.Stop(color: Color.black.opacity(0.6), location: 1)],
                               center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.85)
                Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1.2)
                Ellipse2D(width: size * 0.3, height: size * 0.15, opacity: 0.7)
                    .rotationEffect(.degrees(-35))
                    .offset(x: -size * 0.16, y: size * 0.29 - size * 0.075)
                Circle().fill(Color.white.opacity(0.35))
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(x: size * 0.19, y: size * 0.725 - size * 0.035)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 2)
    }
}

/// 白い楕円の照り（カプセルの左上）
private struct Ellipse2D: View {
    let width: Double
    let height: Double
    let opacity: Double

    var body: some View {
        Capsule().fill(Color.white.opacity(opacity)).frame(width: width, height: height)
    }
}

/// 球の中のカプセルの1つの層（3つに分けた i % 3 == layer の分）。1枚にまとめて描く
private struct TrunkGachaCapsuleLayer: View {
    let layer: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(TrunkCapsules.all.enumerated()).filter { $0.offset % 3 == layer }, id: \.offset) { _, c in
                TrunkGachaCapsule(top: c.top, bottom: c.bottom, size: 46, deep: true)
                    .rotationEffect(.degrees(c.rot))
                    .offset(x: c.x, y: c.y)
            }
        }
        .frame(width: 260, height: 260, alignment: .topLeading)
        .drawingGroup()
    }
}

/// ガラスの光（左上の大きい光・右下の細い光・下の暗がり・暖かい照り返し・縁の明るさ・窓の照り）
private struct TrunkGachaGlass: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            EllipticalGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)])
                .frame(width: 90, height: 46)
                .rotationEffect(.degrees(-28))
                .offset(x: 34, y: 22)
            EllipticalGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)])
                .frame(width: 26, height: 60)
                .rotationEffect(.degrees(-20))
                .offset(x: 204, y: 160)
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0.8),
                                   Gradient.Stop(color: Color.black.opacity(0.6), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [Gradient.Stop(color: WebTheme.accent.opacity(0), location: 0.6),
                                   Gradient.Stop(color: WebTheme.accent.opacity(0.32), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0), location: 0.7),
                                   Gradient.Stop(color: Color.white.opacity(0.1), location: 0.93),
                                   Gradient.Stop(color: Color.white.opacity(0.3), location: 1)],
                           center: .center, startRadius: 0, endRadius: 130)
            Canvas { ctx, _ in
                var window = Path()
                window.move(to: CGPoint(x: 42, y: 80))
                window.addQuadCurve(to: CGPoint(x: 108, y: 22), control: CGPoint(x: 56, y: 40))
                window.addLine(to: CGPoint(x: 122, y: 34))
                window.addQuadCurve(to: CGPoint(x: 64, y: 88), control: CGPoint(x: 80, y: 48))
                window.closeSubpath()
                ctx.fill(window, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)]),
                                                       startPoint: CGPoint(x: 42, y: 22), endPoint: CGPoint(x: 122, y: 88)))
            }
        }
        .frame(width: 260, height: 260, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 胴の地（黒塗り・細い縞・真鍮の内枠・銘・銘の両脇の星・四隅の留め・左右の照り）
private struct TrunkGachaCabinetBody: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 10)
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 10)
                .fill(RadialGradient(colors: [Color(trunk: TrunkRGBA(0x2A2A2E)), Color(trunk: TrunkRGBA(0x0A0A0C))],
                                     center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 230))
                .overlay(TrunkStripes(angle: 90, period: 5, bands: [(0, 2, TrunkRGBA(r: 255, g: 255, b: 255, a: 0.015))])
                    .clipShape(shape))
                .overlay(LinearGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.14), location: 0),
                                                Gradient.Stop(color: Color.white.opacity(0), location: 0.22),
                                                Gradient.Stop(color: Color.white.opacity(0), location: 0.72),
                                                Gradient.Stop(color: Color.white.opacity(0.07), location: 0.9),
                                                Gradient.Stop(color: Color.black.opacity(0.35), location: 1)],
                                         startPoint: .leading, endPoint: .trailing)
                    .clipShape(shape))
                .overlay(alignment: .top) { Color.white.opacity(0.15).frame(height: 1).padding(.horizontal, 8) }
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
            // 銘の両脇の小さな星と、四隅の留め
            Canvas { ctx, _ in
                for c in [CGPoint(x: 36, y: 26), CGPoint(x: 208, y: 26)] {
                    var star = Path()
                    let pts: [(Double, Double)] = [(0, -8), (1.8, -1.8), (8, 0), (1.8, 1.8), (0, 8), (-1.8, 1.8), (-8, 0), (-1.8, -1.8)]
                    for (i, p) in pts.enumerated() {
                        let pt = CGPoint(x: Double(c.x) + p.0, y: Double(c.y) + p.1)
                        if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                    }
                    star.closeSubpath()
                    ctx.fill(star, with: .color(WebTheme.accent))
                }
                for c in [CGPoint(x: 25, y: 19), CGPoint(x: 215, y: 19), CGPoint(x: 25, y: 231), CGPoint(x: 215, y: 231)] {
                    let rivet = Path { $0.addEllipse(in: CGRect(x: Double(c.x) - 3, y: Double(c.y) - 3, width: 6, height: 6)) }
                    ctx.fill(rivet, with: .linearGradient(Gradient(colors: [Color(trunk: TrunkRGBA(0xF2DFAE)), Color(trunk: TrunkRGBA(0x8A6B39))]),
                                                          startPoint: CGPoint(x: Double(c.x) - 3, y: Double(c.y) - 3),
                                                          endPoint: CGPoint(x: Double(c.x) + 3, y: Double(c.y) + 3)))
                    ctx.stroke(rivet, with: .color(Color.black.opacity(0.5)), lineWidth: 0.6)
                }
            }
            .frame(width: 240, height: 250)
            .accessibilityHidden(true)
        }
        .frame(width: 240, height: 250, alignment: .topLeading)
        // 1枚にまとめてから影を落とす（まとめた枠の外へ出る影を切らない）
        .drawingGroup()
        .shadow(color: Color.black.opacity(0.75), radius: 25, x: 0, y: 30)
    }
}

/// ハンドルの黒い座（案の頁の 0.85 倍・直径 102）。真鍮の輪と黒い線。0枚・圏外でも形は同じ
private struct TrunkGachaCrankSeat: View {
    let dim: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(trunk: TrunkRGBA(0x1C1C1F)), Color(trunk: TrunkRGBA(0x050506))],
                                     center: .center, startRadius: 0, endRadius: 51))
            Circle()
                .strokeBorder(LinearGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                                     Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                                     Gradient.Stop(color: Color(trunk: TrunkRGBA(0x7E6438)), location: 1)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Circle()
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 0.85)
                .padding(2.5)
        }
        .frame(width: 102, height: 102)
        .accessibilityHidden(true)
    }
}

/// ハンドルのまわりの目盛り 12 個（30° ごと・北は太い）。点いた分は明るい真鍮 #F3DCA6
struct TrunkGachaCrankTicks: View {
    /// 点いている数（0〜12）
    let lit: Int
    var dim = false

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: Double(size.width) / 2, y: Double(size.height) / 2)
            for i in 0..<12 {
                let a = (Double(i) * 30 - 90) * .pi / 180
                var tick = Path()
                tick.move(to: CGPoint(x: Double(c.x) + 44.2 * cos(a), y: Double(c.y) + 44.2 * sin(a)))
                tick.addLine(to: CGPoint(x: Double(c.x) + 48.9 * cos(a), y: Double(c.y) + 48.9 * sin(a)))
                let on = i < lit || lit >= 12
                let style = StrokeStyle(lineWidth: i == 0 ? 2.55 : 1.7, lineCap: .round)
                ctx.stroke(tick, with: .color(on ? Color(trunk: TrunkRGBA(0xF3DCA6)) : WebTheme.accent.opacity(dim ? 0.18 : 0.35)), style: style)
            }
        }
        .frame(width: 104, height: 104)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// ハンドルの回る絵（真鍮の円盤・握り棒・真ん中のつまみ）。81.6
private struct TrunkGachaCrankDisc: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF2DFAE)), location: 0),
                                             Gradient.Stop(color: WebTheme.accent, location: 0.45),
                                             Gradient.Stop(color: Color(trunk: TrunkRGBA(0x6E5630)), location: 1)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 51))
            RoundedRectangle(cornerRadius: 6.8)
                .fill(LinearGradient(colors: [Color(trunk: TrunkRGBA(0x6E5630)), Color(trunk: TrunkRGBA(0xE3C98F)),
                                              Color(trunk: TrunkRGBA(0x6E5630))], startPoint: .leading, endPoint: .trailing))
                .frame(width: 13.6, height: 71.4)
                .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
            Circle()
                .fill(RadialGradient(colors: [Color(trunk: TrunkRGBA(0xFFF1C4)), Color(trunk: TrunkRGBA(0xB8955A))],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 14.5))
                .frame(width: 20.4, height: 20.4)
                .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
        }
        .frame(width: 81.6, height: 81.6)
        .shadow(color: Color.black.opacity(0.7), radius: 4, x: 0, y: 4)
        .accessibilityHidden(true)
    }
}

/// ハンドルの照り（左上の楕円）と細い輪。回らない
private struct TrunkGachaCrankGloss: View {
    var body: some View {
        ZStack {
            EllipticalGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)])
                .frame(width: 40.8, height: 18.7)
                .rotationEffect(.degrees(-32))
                .offset(x: -11.9, y: -17)
            Circle()
                .strokeBorder(Color(trunk: TrunkRGBA(r: 255, g: 241, b: 196, a: 0.45)), lineWidth: 1)
                .frame(width: 80, height: 80)
        }
        .frame(width: 104, height: 104)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 取り出し口の底の光の輪（楕円の線）
private struct TrunkGachaOutletRing: View {
    var body: some View {
        Canvas { ctx, size in
            let ring = Path { $0.addEllipse(in: CGRect(x: 1, y: 1, width: Double(size.width) - 2, height: Double(size.height) - 2)) }
            ctx.stroke(ring, with: .color(Color(trunk: TrunkRGBA(0xF3DCA6))), lineWidth: 2)
        }
        .allowsHitTesting(false)
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

// MARK: - カプセルを開けた

/// カプセルを開けた（モック GachaOpen.dc.html・全画面。2026-11-23 札 #716 で owner の版の演出に）。
///
/// 全画面が出たあと（0.4 秒）、カプセルの半分2つが離れ（0.46 秒）、部品が 0.6 倍から出る。部品の後ろで光の筋がゆっくり回り、
/// 衝撃の輪が広がり、きらめきが瞬き、部品はゆっくり上下に揺れる。文は眉、見出し、線、一行、札、ボタンの順に少しずつ出る。
/// 持っている部品が出たら、部品が影になり、かけら（切符の切れ端・札 #713）が下の札の切符へはまる。主ボタンは
/// 硬貨があれば「もう1回まわす」（無ければ「部品箱に入れる」）。新しい部品は成功の触覚1回、かけらは軽い1回。
/// 「視差効果を減らす」の人には動かさず、終わった形をすぐ出す（触覚は残す）
struct TrunkGachaOpenView: View {
    @ObservedObject var model: TrunkViewModel
    let result: TrunkGachaResult
    /// 「もう1回まわす」（閉じたあと機械が続けて回す）
    var onAgain: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var toasts: ToastCenter
    /// 出た時刻（動きの起点）。動きを減らす設定では nil（終わった形）
    @State private var start: Date?
    /// 札の切符に見せている切れ端の数（持っている部品: はまったら1つ増える）
    @State private var shownFragments: Int?
    @State private var successes = 0
    @State private var pieces = 0
    /// 段階で出た文の数（0〜6・時計ではなく段で出す）
    @State private var texts = 0
    /// 一度きりの動きが終わった（舞台の時計を 30 コマ毎秒に落とす）
    @State private var settled = false
    /// 画面に出ている（出ていない間は時計を止める）
    @State private var visible = false
    /// かけらが飛ぶ元と行き先（`space` の座標）
    @State private var pieceFrame = CGRect.zero
    @State private var ticketFrame = CGRect.zero

    private static let space = "trunk.gachaOpen.space"

    private var part: TrunkPart { result.part }
    private var equippedNow: Bool { model.state?.equipped.ids(part.kind).contains(part.id) ?? false }
    /// はまる前の数（応答の数はもらったあと）
    private var fragmentsBefore: Int { max(0, result.fragments - 1) }
    private var ticketCount: Int { shownFragments ?? (result.duplicate ? fragmentsBefore : result.fragments) }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.36)
            VStack(spacing: 0) {
                // 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187。前は右上の白の字だけ）
                HStack {
                    SheetCloseButton(onContent: true)
                        .accessibilityIdentifier("trunk.gachaOpen.close")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        // 時計で動かすのは舞台だけ（確かめ役の指摘 2026-11-23: 画面全体と読み上げの木を毎コマ作り直していた）。
                        // 一度きりの動きの間は毎コマ、出そろったら回り続ける物だけ 30 コマ毎秒、画面に出ていない間は止める
                        TimelineView(.animation(minimumInterval: TrunkOpenClock.frameInterval(settled: settled),
                                                paused: TrunkOpenClock.paused(started: start != nil, visible: visible))) { ctx in
                            stage(start.map { ctx.date.timeIntervalSince($0) } ?? 60)
                        }
                        info
                    }
                }
                actions
            }
        }
        .coordinateSpace(.named(Self.space))
        .sensoryFeedback(.success, trigger: successes)
        .sensoryFeedback(.impact(weight: .light), trigger: pieces)
        .onAppear {
            visible = true
            begin()
        }
        .onDisappear { visible = false }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.gachaOpen")
    }

    /// 動きを始める。触覚とかけらの数は時間どおりに進める
    private func begin() {
        guard start == nil else { return }
        if reduceMotion {
            shownFragments = result.fragments
            texts = TrunkMotion.stageDelays.count
            settled = true
            if result.duplicate { pieces += 1 } else { successes += 1 }
            return
        }
        start = Date()
        let partAt = TrunkOpenClock.partAt
        // 文は段で出す（眉、見出し、線、一行、札、ボタンの順に 0.5 秒で）
        for (i, delay) in TrunkMotion.stageDelays.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: TrunkMotion.stageSeconds)) { texts = max(texts, i + 1) }
            }
        }
        // 一度きりの動きが終わったら、舞台の時計を回り続ける物の速さに落とす
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TrunkOpenClock.settleAt(duplicate: result.duplicate) * 1_000_000_000))
            settled = true
        }
        Task { @MainActor in
            if result.duplicate {
                let done = partAt + TrunkMotion.fragmentAfterOpen + TrunkMotion.fragmentLiftSeconds + TrunkMotion.fragmentFlySeconds
                try? await Task.sleep(nanoseconds: UInt64(done * 1_000_000_000))
                shownFragments = result.fragments
                pieces += 1
            } else {
                try? await Task.sleep(nanoseconds: UInt64((partAt + 0.3) * 1_000_000_000))
                successes += 1
            }
        }
    }

    /// 段階で出る文（i 番目が出たら、下から 12 上がりながら見える。動きは `begin` の `withAnimation`）
    private func stagger(_ i: Int) -> (opacity: Double, y: Double) {
        texts > i ? (1, 0) : (0, TrunkMotion.stageRise)
    }

    private var heading: some View {
        let eyebrow = stagger(0), title = stagger(1), rule = stagger(2), sub = stagger(3)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                TrunkRarityMark(rarity: part.rarity, size: 9)
                Text(TrunkGachaText.eyebrow(part))
                    .font(JPFont.eyebrow)
                    .tracking(11 * 0.12)
                    .foregroundStyle(WebTheme.accent)
            }
            .padding(.top, 8)
            .opacity(eyebrow.opacity).offset(y: eyebrow.y)
            Text(TrunkGachaText.openTitle(part))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .opacity(title.opacity).offset(y: title.y)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("trunk.gachaOpen.title")
            // 見出しの下の真鍮の細い線（右へ消える）
            LinearGradient(colors: [WebTheme.accent.opacity(0), WebTheme.accent.opacity(0.55), WebTheme.accent.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 64, height: 1)
                .padding(.top, 8)
                .opacity(rule.opacity)
                .accessibilityHidden(true)
            Text(result.duplicate ? TrunkGachaText.duplicateNote(fragments: result.fragments) : TrunkGachaText.freshNote)
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .opacity(sub.opacity).offset(y: sub.y)
                .accessibilityIdentifier("trunk.gachaOpen.note")
        }
    }

    /// 開いたカプセルの半分2つと、真ん中の部品（後ろに光の放射と真鍮の淡い光、衝撃の輪、きらめき）
    private func stage(_ e: Double) -> some View {
        let split = TrunkBezier(0.2, 0.8, 0.2, 1).value(min(1, max(0, (e - TrunkMotion.openDelay) / TrunkMotion.splitSeconds)))
        let partAt = TrunkOpenClock.partAt
        let partP = TrunkBezier(0.2, 0.8, 0.2, 1).value(min(1, max(0, (e - partAt) / TrunkMotion.splitSeconds)))
        let shown = min(1, max(0, (e - partAt) / 0.4))
        let rays = min(1, max(0, (e - TrunkMotion.openDelay) / 0.5))
        let shock = TrunkMotion.shock(elapsed: e - partAt)
        let bob = start == nil ? 0 : TrunkMotion.bob(elapsed: max(0, e - partAt))
        // 持っている部品: 部品が影になり、切れ端が浮いて札の切符へ飛ぶ
        let fragAt = partAt + TrunkMotion.fragmentAfterOpen
        let toShadow = result.duplicate ? min(1, max(0, (e - fragAt) / 0.4)) : 0
        let lift = min(1, max(0, (e - fragAt) / TrunkMotion.fragmentLiftSeconds))
        let fly = TrunkBezier(0.2, 0.8, 0.2, 1).value(min(1, max(0, (e - fragAt - TrunkMotion.fragmentLiftSeconds) / TrunkMotion.fragmentFlySeconds)))
        let flying = result.duplicate && start != nil && e >= fragAt && e < fragAt + TrunkMotion.fragmentLiftSeconds + TrunkMotion.fragmentFlySeconds
        let target = pieceTarget
        return ZStack(alignment: .topLeading) {
            TrunkGachaRays()
                .frame(width: 340, height: 340)
                .rotationEffect(.degrees(start == nil ? 0 : e / TrunkMotion.raysSeconds * 360))
                .opacity(rays)
                .offset(x: 25, y: -5)
            TrunkStyle.glow(width: 330, height: 300).offset(x: 30, y: 10)
                .opacity(shown)
            capsuleHalf(top: true)
                .rotationEffect(.degrees(-24 * split))
                .offset(x: 40 + 95 * (1 - split), y: 30 + 95 * (1 - split))
            capsuleHalf(top: false)
                .rotationEffect(.degrees(18 * split))
                .offset(x: 226 - 91 * (1 - split), y: 250 - 95 * (1 - split))
            // 部品の下の影
            EllipticalGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0)])
                .frame(width: 120, height: 16)
                .offset(x: 135, y: 250)
                .opacity(shown)
            // 衝撃の輪
            Circle()
                .strokeBorder(Color(trunk: TrunkRGBA(r: 243, g: 220, b: 166, a: 0.7)), lineWidth: 2)
                .shadow(color: Color(trunk: TrunkRGBA(r: 243, g: 220, b: 166, a: 0.5)), radius: 9)
                .frame(width: 80, height: 80)
                .scaleEffect(shock.scale)
                .opacity(start == nil ? 0 : shock.opacity)
                .offset(x: 155, y: 120)
            ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { _, s in
                let tw = start == nil ? (scale: 1.0, opacity: 0.8, rotation: 0.0)
                    : TrunkMotion.twinkle(elapsed: e - TrunkMotion.openDelay, delay: s.delay)
                TrunkSparkle()
                    .frame(width: s.size, height: s.size)
                    .scaleEffect(tw.scale)
                    .rotationEffect(.degrees(tw.rotation))
                    .opacity(tw.opacity)
                    .offset(x: s.x, y: s.y)
            }
            ZStack {
                TrunkPartView(part: part, size: 160)
                    .opacity(1 - toShadow)
                Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)
                    .frame(width: 160, height: 160)
                    .mask { TrunkPartView(part: part, size: 160, shadow: false) }
                    .opacity(toShadow)
            }
            .frame(width: 160, height: 160)
            .scaleEffect(TrunkMotion.partFrom + (1 - TrunkMotion.partFrom) * partP)
            .opacity(start == nil ? 1 : shown)
            .offset(x: 115, y: 80 + bob)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkPartDrawing.accessibilityLabel(part))
            .accessibilityAddTraits(.isImage)
            if result.duplicate {
                TrunkFragmentPieceView(index: min(4, fragmentsBefore), size: 40)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: { pieceFrame = $0 })
                    .rotationEffect(.degrees(TrunkMotion.fragmentTilt * lift))
                    .scaleEffect(1 - 0.5 * fly)
                    .offset(x: 170 + Double(target.width) * fly, y: 130 + Double(target.height) * fly)
                    .opacity(flying ? lift : 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 390, height: 360, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    /// 切れ端の行き先（札の切符の、次に埋まる切れ端の真ん中）までのずれ
    private var pieceTarget: CGSize {
        guard pieceFrame != .zero, ticketFrame != .zero else { return .zero }
        let i = Double(min(4, fragmentsBefore))
        let k = Double(ticketFrame.width) / TrunkFragmentTicket.width
        let x = Double(ticketFrame.minX) + (i * 20 + 10) * k
        let y = Double(ticketFrame.midY)
        // 測った枠は置き場のずれ（170, 130）を入れる前の形
        return CGSize(width: x - (Double(pieceFrame.midX) + 170), height: y - (Double(pieceFrame.midY) + 130))
    }

    /// きらめきの置き場（x・y・遅れ・大きさ）
    private static let sparkles: [(x: Double, y: Double, delay: Double, size: Double)] = [
        (92, 70, 0, 14), (280, 96, 0.7, 10), (262, 232, 1.3, 13), (86, 212, 1.9, 9), (190, 44, 0.4, 11), (300, 180, 2, 8),
    ]

    private func capsuleHalf(top: Bool) -> some View {
        ZStack {
            if top {
                Color(trunk: TrunkGachaColors.top(part))
                RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.4), location: 0),
                                       Gradient.Stop(color: Color.white.opacity(0), location: 0.42),
                                       Gradient.Stop(color: Color.black.opacity(0.55), location: 1)],
                               center: UnitPoint(x: 0.3, y: 0.22), startRadius: 0, endRadius: 120)
            } else {
                Color(trunk: TrunkRGBA(0xF4F1EA))
                RadialGradient(stops: [Gradient.Stop(color: Color.white.opacity(0.5), location: 0),
                                       Gradient.Stop(color: Color.white.opacity(0), location: 0.45),
                                       Gradient.Stop(color: Color.black.opacity(0.4), location: 1)],
                               center: UnitPoint(x: 0.3, y: 0.8), startRadius: 0, endRadius: 120)
            }
            // 切り口（暗い内側と白い縁）
            Capsule()
                .fill(top ? Color.black.opacity(0.55) : Color(trunk: TrunkRGBA(0x1A1A1C)).opacity(0.85))
                .overlay(Capsule().strokeBorder(Color.white.opacity(top ? 0.55 : 0.8), lineWidth: 1.6))
                .frame(width: 120, height: 20)
                .offset(y: top ? 30 : -30)
        }
        .frame(width: 120, height: 60)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: top ? 60 : 0, bottomLeadingRadius: top ? 0 : 60,
                                          bottomTrailingRadius: top ? 0 : 60, topTrailingRadius: top ? 60 : 0))
        .shadow(color: Color.black.opacity(0.6), radius: 9, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    private var info: some View {
        let s = stagger(4)
        let owned = TrunkPartsBoxText.collected(model.state?.ownedParts ?? [], kind: part.kind)
        return HStack(spacing: 12) {
            if result.duplicate {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("かけら", "Fragments"))
                            .font(.subheadline)
                        // 数は SF の等幅の数字（`JPFont.mono`）
                        Text(TrunkFragmentText.count(ticketCount))
                            .font(JPFont.mono(15, medium: true, relativeTo: .subheadline))
                    }
                    .foregroundStyle(WebTheme.text)
                    Text(L("5つで部品1つと交換できます", "Five get you one part"))
                        .font(JPFont.caption)
                        .foregroundStyle(TrunkStyle.faint)
                }
                Spacer(minLength: 8)
                TrunkFragmentTicketView(filled: ticketCount, width: 84)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: { ticketFrame = $0 })
                    .accessibilityIdentifier("trunk.gachaOpen.ticket")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(part.kind.title)の部品", "\(part.kind.title) part"))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                    Text(L("集めた\(part.kind.tabName) \(owned) / 12", "\(part.kind.tabName) collected \(owned) / 12"))
                        .font(JPFont.mono(12))
                        .foregroundStyle(TrunkStyle.faint)
                }
                Spacer()
                Text(TrunkGachaText.agingNote)
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .trunkCard(radius: 14)
        .padding(.horizontal, 20)
        .opacity(s.opacity)
        .offset(y: s.y)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        let s = stagger(5)
        let coins = model.state?.coins ?? 0
        return VStack(spacing: 8) {
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            switch TrunkGachaText.openActions(duplicate: result.duplicate, coins: coins) {
            case .equip:
                Button {
                    Task {
                        guard let state = model.state else { return }
                        let next = TrunkEquipText.equipping(part, on: state.equipped)
                        guard !next.full else {
                            // いっぱい: 黙って外さず、付け替えの画面と同じ一言
                            model.actionError = TrunkEquipText.fullNote(part.kind)
                            return
                        }
                        let before = state.equipped
                        if await model.equip(next.equipped) {
                            dismiss()
                            // 「取り消す」で付ける前に戻す（2026-11-12 判断）
                            toasts.show(TrunkGachaText.equippedNotice(part),
                                        undo: ToastCenter.Undo(title: TrunkText.undoTitle) { [model] in await model.equip(before) })
                        }
                    }
                } label: {
                    TrunkButtonFace(title: equippedNow ? L("付けています", "Already on") : L("トランクに付ける", "Put it on my trunk"))
                }
                .buttonStyle(.plain)
                .disabled(model.busy || equippedNow)
                .accessibilityIdentifier("trunk.gachaOpen.equip")
                keepButton(kind: .secondary)
            case .again:
                Button {
                    onAgain()
                    dismiss()
                } label: {
                    TrunkButtonFace(title: TrunkGachaText.againTitle)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityIdentifier("trunk.gachaOpen.again")
                keepButton(kind: .secondary)
            case .keep:
                keepButton(kind: .main)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
        .opacity(s.opacity)
        .offset(y: s.y)
    }

    private func keepButton(kind: TrunkButtonFace.Kind) -> some View {
        Button { dismiss() } label: {
            TrunkButtonFace(title: TrunkGachaText.keepTitle, kind: kind)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trunk.gachaOpen.keep")
    }
}

/// 開けた画面の光の放射（20 本の筋・中心から外へ消える）。入力が無いので描き直さず、回すだけ
private struct TrunkGachaRays: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: Double(size.width) / 2, y: Double(size.height) / 2)
            let r = Double(size.width) / 2
            var rays = Path()
            for i in 0..<20 {
                let a0 = (Double(i) * 18 - 90) * .pi / 180, a1 = (Double(i) * 18 + 6 - 90) * .pi / 180
                rays.move(to: c)
                rays.addLine(to: CGPoint(x: Double(c.x) + r * cos(a0), y: Double(c.y) + r * sin(a0)))
                rays.addLine(to: CGPoint(x: Double(c.x) + r * cos(a1), y: Double(c.y) + r * sin(a1)))
                rays.closeSubpath()
            }
            ctx.fill(rays, with: .radialGradient(Gradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 243, g: 220, b: 166, a: 0.18)), location: 0.18),
                                                                  Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 243, g: 220, b: 166, a: 0)), location: 0.72)]),
                                                 center: c, startRadius: 0, endRadius: r))
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// きらめき（4方向の細い星・明るい真鍮）
private struct TrunkSparkle: View {
    var body: some View {
        Canvas { ctx, size in
            let k = Double(size.width) / 16
            var star = Path()
            let pts: [(Double, Double)] = [(0, -8), (1.8, -1.8), (8, 0), (1.8, 1.8), (0, 8), (-1.8, 1.8), (-8, 0), (-1.8, -1.8)]
            for (i, p) in pts.enumerated() {
                let pt = CGPoint(x: (p.0 + 8) * k, y: (p.1 + 8) * k)
                if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(Color(trunk: TrunkRGBA(0xF3DCA6))))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                Text(eyebrow: L("出る確率", "Odds"))
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
                .trunkCard(radius: 14)
                .padding(.top, 8)
                // 1点あたり（段の確率 ÷ 段の点数）
                Text(L("同じ段の中は、どの部品も同じ確率です。1点あたり: ",
                       "Within a tier every part is equally likely. Per part: ")
                     + TrunkPartRarity.allCases.map { "\($0.name) \(TrunkGachaText.percentText(TrunkGachaText.perPart($0)))" }
                        .joined(separator: "\u{2002}"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .accessibilityIdentifier("trunk.odds.perPart")
                Text(eyebrow: L("入っている部品\u{2002}9 種類\u{2002}108 点", "Inside\u{2002}9 kinds\u{2002}108 parts"))
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
                .trunkCard(radius: 14)
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
