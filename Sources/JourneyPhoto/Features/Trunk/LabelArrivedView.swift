import SwiftUI

/// 投稿してラベルが届いた（モック LabelArrived.dc.html・全画面・2026-10-17）。
///
/// 投稿が全部上がったあと、投稿の画面と共有の画面が閉じてから `RootView` が出す（`TrunkArrivals`）。
/// 眉ラベル → 明朝の見出し「京都のラベルが届きました」→ お礼の一行 → 大きいラベル（後ろに真鍮の淡い光）→
/// どんな図柄かの札 → 手持ちの棒 → 「トランクに貼る」「あとで貼る（手持ちへ）」。
///
/// **作り直しは届いた画面のまま（札 #706・2026-11-23 owner 承認）**: 全員が1枚につき3回まで。押すたびに候補の列
/// （最初の1枚と、作り直した1回目〜3回目の4つの枠）が横に増え、新しい図柄が選ばれた状態になる。候補を押すと
/// その場でサーバーへ送る（`reroll/choose`）。**選ばずに閉じても、いま大きく見えている図柄で決まる**（決めるボタンを置かない）。
/// 何もしなければ今までどおり「トランクに貼る」の1回で貼れる。進み具合は2行（「好きなデザインで作れるまで」／点と
/// 「あと N 回の投稿」）。作れるようになった投稿では、主ボタンが「好きなデザインで作る」（`TrunkCustomView`）、副が「このまま貼る」。
/// サーバーが対応していない（`custom` の欄が無い）ときは、作り直しも進み具合も出さない。Pro の月3回の作り直しはやめた
///
/// **静かな祝い（2026-11-08・楽しさの案 A・札 #502）**: 投稿した写真が先に現れ、続いてラベルが落ちて貼りつく
/// （軽い触覚が 1 回）。最後に、言えるときだけ事実の一文（「京都、はじめての1枚です」・`ArrivalFact`）。
/// 節目と箔押しは後ろの真鍮の光を一段強くする。動きを減らす設定では、動かさずに最初から全部を出す。
/// 数を稼ぐ文・連続日数・順位・共有を促す文は出さない。共有は任意の副ボタン（公開の投稿だけ）
///
/// **1.1.83 の案（2026-11-12 判断）**: 何枚も届いたら主ボタンは「3 枚まとめて貼る」1回（今は 1 枚だけ貼れて、残りは
/// 手持ちで1枚2回ずつ＝3 枚で 5 回）。置き場は今のおまかせ（`stickPlan`）で、閉じたあとの知らせの「取り消す」で戻す。
/// 写真のある画面なので主ボタンは白、副は線 44。どんな図柄かの札は accent-soft。電波が無くて貼れなかったら、
/// ボタンのすぐ上に「ラベルは手持ちに入っています」と言う
struct LabelArrivedView: View {
    let batch: TrunkArrivals.Batch

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    /// 画面写真の見本（`-JPPreviewTrunkArrived`）ではサーバーを読まず、見本の手持ちを出す
    @StateObject private var model = TrunkViewModel(preview: PreviewSession.opensTrunkArrived ? .sample
                                                             : PreviewSession.trunkSample)
    /// 好きなデザインで作る画面（#706）
    @State private var showCustom = false
    /// 作り直しが届かなかった（ボタンを「もう一度作り直す」にする。断りでなければ「回数は減っていません」と言う）
    @State private var redoFailed = false
    /// 作り直しを頼んでいる最中（次の枠に回る印を出す）
    @State private var rolling = false
    /// いま見ている1枚の番号（何枚も届いたとき、好きなデザインで1枚貼ったら次の1枚へ進む・#706）
    @State private var current = 0
    /// 好きなデザインで作って貼った分（閉じたあとの知らせと「取り消す」に入れる）
    @State private var customStuck: [String] = []
    /// 祝いの動きの進み（写真 → ラベル → 一文）。動きを減らす設定では `shown` が最初から全部を出す
    @State private var step: ArrivalSequence.Step = .start
    /// ラベルが貼りついた瞬間に軽い触覚を 1 回鳴らすための数
    @State private var landed = 0
    /// 硬貨をもらう瞬間（札 #716）: ラベルが貼りついたあと、硬貨が回りながら札に落ちて北で止まる。落ち始めた時刻と、
    /// 札に入ったか（入るまでは札の硬貨と字を隠す）。札に入った瞬間に軽い触覚（ラベルの触覚とは別の瞬間）
    @State private var coinFallStart: Date?
    @State private var coinRested = true
    @State private var coinLanded = 0
    /// 事実の一文。**開いたときに1回だけ**決めて持つ（描き直すたびに写真の一覧を数え直さない）。nil＝言わない
    @State private var sentence: String?
    /// 写真が読み込めなかった（写真の札は出さず、ラベルだけを真ん中に出す）
    @State private var photoFailed = false
    /// 電波が無くて貼れなかった（ボタンの上の一言を、手持ちに入っていることを言う文にする）
    @State private var offlineFailed = false
    @EnvironmentObject private var connectivity: Connectivity

    /// 届いた枚数（何枚もなら「まとめて貼る」）
    private var count: Int { remaining.count }

    /// まだ貼っていない届いた分（いま見ている1枚から後ろ）
    private var remaining: [TrunkArrivals.Arrival] { Array(batch.arrivals.dropFirst(min(current, batch.arrivals.count - 1))) }

    private var arrival: TrunkArrivals.Arrival { remaining.first ?? batch.first }
    /// 届いた1枚。作り直し・候補を選ぶ・好きなデザインは手持ちの状態（サーバーの応答）にそのまま映る
    private var label: TrunkLabel {
        model.state?.pocket.first { $0.id == arrival.label.id }
            ?? model.state?.stuck.first { $0.id == arrival.label.id }
            ?? arrival.label
    }

    /// この投稿で好きなデザインで作れるようになった（主ボタンが替わる）
    private var customOffer: Bool {
        guard let progress = model.state?.custom, model.state?.supportsLabelReroll == true else { return false }
        // 使える回数があれば出す（使わずに次を投稿して進みが 1 以上になっても・確かめ役の指摘 2026-11-23）
        return progress.canMake && label.custom == nil && model.state?.pocket.contains(where: { $0.id == label.id }) == true
    }

    /// 写真があるときだけ、写真の札を出す
    private var photoURL: URL? { photoFailed ? nil : arrival.photoURL }

    /// その段まで進んだか。動きを減らす設定では最初から全部（`ArrivalSequence.isShown`）
    private func shown(_ s: ArrivalSequence.Step) -> Bool {
        ArrivalSequence.isShown(s, current: step, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.32)
            VStack(spacing: 0) {
                // 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187。前は右上の白の字だけ）
                HStack {
                    SheetCloseButton(onContent: true)
                        .accessibilityIdentifier("trunk.arrived.close")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        stage
                        TrunkCandidatesRow(model: model, label: label, rolling: rolling, idPrefix: "trunk.arrived")
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        factLine
                        chips
                        progress
                        pocket
                    }
                }
                actions
            }
        }
        .statusBarHidden(false)
        .task {
            model.bind(environment.trunk, userId: auth.userId)
            await model.load(offline: false)
        }
        // 祝いの動き（写真 → ラベルが落ちる → 一文）。動きを減らす設定では待たず、触覚だけ 1 回
        .task { await runSequence() }
        // 一文のための自分の写真の一覧（読めなければ nil＝言わない。見本の入り方では読まない）
        .task { await decideSentence() }
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .sensoryFeedback(.impact(weight: .light), trigger: coinLanded)
        .fullScreenCover(isPresented: $showCustom) {
            // 作ったらそのまま貼る（届いた画面も閉じる）。貼れなかったら届いた画面に戻る（手持ちに入っている）
            TrunkCustomView(model: model, labelId: arrival.label.id, sticks: true) { stuck in
                guard stuck else { return }
                finishCustom(arrival.label.id)
            }
        }
        // 全画面の上では `RootView` の知らせが隠れるので、ここにも置く（貼れなかったときの知らせ。`NameSideBadgeView` と同じ）
        .overlay(alignment: .top) { ToastOverlay() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.arrived")
    }

    private var heading: some View {
        VStack(spacing: 0) {
            Text("NEW LABEL\u{2002}" + L("投稿のお礼", "THANK YOU"))
                .font(JPFont.eyebrow)
                .tracking(11 * 0.12)
                .foregroundStyle(WebTheme.accent)
                .padding(.top, 18)
            Text(TrunkArrivalCopy.title(count: count, place: arrival.label.place.name))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Text(customOffer ? TrunkText.customThanks : TrunkArrivalCopy.thanks(count: count, photoTitle: arrival.photoTitle))
                .font(.subheadline)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    /// 大きいラベル（260×176 の枠に形の比で収める・後ろに 340×250 の光）。
    /// 写真があるときは、写真の札を左に置き、ラベルがその右下に貼りつく（写真 → ラベルが落ちる）。
    /// 写真が無い・読めないときは、今までどおりラベルだけを真ん中に出す（動きはラベルが落ちるだけ）
    private var stage: some View {
        let special = ArrivalFact.isSpecial(label)
        return ZStack {
            TrunkStyle.glow(width: 340, height: 250, strong: special)
            if let url = photoURL {
                photoCard(url)
                    .offset(x: -70, y: -16)
                    .opacity(shown(.photo) ? 1 : 0)
                    .scaleEffect(shown(.photo) ? 1 : 0.96)
            }
            // 何枚も届いたら、残りのラベルを後ろに重ねて見せる（2 枚まで・2026-11-12 判断・案の「3 枚届きました」）
            ForEach(Array(remaining.dropFirst().prefix(2).enumerated()), id: \.offset) { i, other in
                TrunkLabelThumb(label: other.label, maxWidth: 200, maxHeight: 136, rot: i == 0 ? 8 : -12)
                    .offset(x: (photoURL == nil ? 0 : 38) + (i == 0 ? 56 : -56), y: (photoURL == nil ? -14 : 30))
                    .opacity(shown(.label) ? 0.9 : 0)
                    .accessibilityHidden(true)
            }
            TrunkLabelThumb(label: label, maxWidth: photoURL == nil ? 260 : 236, maxHeight: photoURL == nil ? 176 : 160, rot: -4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(label))
                .accessibilityAddTraits(.isImage)
                .offset(x: photoURL == nil ? 0 : 38, y: (photoURL == nil ? 0 : 44) + (shown(.label) ? 0 : -150))
                .opacity(shown(.label) ? 1 : 0)
        }
        .frame(height: 270)
        .padding(.top, 16)
    }

    // MARK: 好きなデザインで作るまでの進み（#706）

    /// 2行（「好きなデザインで作れるまで」／点と「あと N 回の投稿」）。作れる回数を持ちきっているか、この投稿で
    /// 作れるようになったときは「好きなデザインで作れます」。サーバーが対応していなければ出さない
    @ViewBuilder
    private var progress: some View {
        if let p = model.state?.custom {
            let ready = p.canMake
            VStack(spacing: 4) {
                if !ready {
                    Text(TrunkText.customProgressTitle)
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.muted)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(0..<p.every, id: \.self) { i in
                            Circle()
                                .fill(ready || i < p.posts ? WebTheme.accent : WebTheme.hairline)
                                .frame(width: 10, height: 10)
                        }
                    }
                    if ready {
                        Text(TrunkText.customReady(tickets: p.tickets))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.accent)
                    } else {
                        Text(TrunkText.customPostsLeft(p.postsLeft))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.text)
                    }
                }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkText.customProgressAccessibility(p))
            .accessibilityIdentifier("trunk.arrived.progress")
        }
    }

    /// 投稿した写真の札（150×196・角は写真の札 14・細い縁）。読めなければ札ごと外す
    private func photoCard(_ url: URL) -> some View {
        DownsampledRemoteImage(url: url, contentMode: .fill, assumedRatioLimit: 1.6,
                               onSettled: { ok in if !ok { photoFailed = true } })
            .frame(width: 150, height: 196)
            .background(WebTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
            .rotationEffect(.degrees(-3))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(arrival.photoTitle.isEmpty ? L("投稿した写真", "The photo you posted")
                                : L("投稿した写真「\(arrival.photoTitle)」", "The photo you posted: \(arrival.photoTitle)"))
            .accessibilityAddTraits(.isImage)
    }

    /// 事実の一文（言えるときだけ・明朝・真鍮）。最後に静かに現れる。動かさない設定では最初から
    @ViewBuilder
    private var factLine: some View {
        if let sentence {
            Text(sentence)
                .font(JPFont.display(18, relativeTo: .title3))
                .foregroundStyle(WebTheme.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .opacity(shown(.sentence) ? 1 : 0)
                .accessibilityIdentifier("trunk.arrived.fact")
        }
    }

    /// 一文を1回だけ決める。節目はサーバーの事実なので一覧を待たず、そのほかは自分の写真の一覧を読んでから
    /// （読めなければ nil＝言わない）。見本の入り方（`-JPPreviewTrunkArrived`）では一覧を読まず、見本の一覧で言う
    private func decideSentence() async {
        guard sentence == nil else { return }
        #if DEBUG
        if PreviewSession.opensTrunkArrived {
            sentence = ArrivalFact.sentence(label: label, photos: ArrivalFact.previewPhotos(for: label))
            return
        }
        #endif
        sentence = ArrivalFact.sentence(label: label, photos: nil)
        if sentence != nil { return }
        let mine = await ProfileImageFromPhoto.myPhotos(environment: environment)
        sentence = ArrivalFact.sentence(label: label, photos: mine)
    }

    /// 写真 → ラベルが落ちる → 一文の順に進める。動きを減らす設定では何も動かさず、触覚を 1 回だけ
    private func runSequence() async {
        guard !reduceMotion else {
            landed += 1
            return
        }
        // 硬貨は落ちて入るまで札の中を隠す（`dropCoin` が最後に必ず出す）
        if batch.coins > 0 { coinRested = false }
        for (next, delay) in ArrivalSequence.delays(reduceMotion: false) {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            switch next {
            case .label: withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { step = next }
            default: withAnimation(.easeOut(duration: 0.4)) { step = next }
            }
            if next == .label {
                // 貼りつく頃（落ち切る少し前）に軽い触覚
                try? await Task.sleep(nanoseconds: UInt64(ArrivalSequence.landAfter * 1_000_000_000))
                if Task.isCancelled { return }
                landed += 1
                // 一文の段を待たせないよう、硬貨は別に落とす
                if batch.coins > 0 { Task { await dropCoin() } }
            }
        }
    }

    /// 硬貨が回りながら札に落ちて入る（0.62 秒）。入ったら針が揺れて北で止まり、札が少しふくらむ
    private func dropCoin() async {
        defer { coinRested = true }
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.coinAfterLabel * 1_000_000_000))
        if Task.isCancelled { return }
        let began = Date()
        coinFallStart = began
        try? await Task.sleep(nanoseconds: UInt64(TrunkMotion.coinFallSeconds * 1_000_000_000))
        coinRested = true
        coinLanded += 1
        if Task.isCancelled { return }
        // 札が少しふくらむ間だけ時計を回し、止まったら止める
        try? await Task.sleep(nanoseconds: UInt64(max(TrunkMotion.chipBumpSeconds, TrunkMotion.needleSeconds) * 1_000_000_000))
        if coinFallStart == began { coinFallStart = nil }
    }

    /// どんな図柄か（真鍮の字の札）
    /// アクセシビリティの大きさでは札を縦に積む（2026-10-21）。既定の大きさは前と同じ横並び（字は少し縮む）——
    /// `ViewThatFits` にすると、既定の大きさでも名前の長い札で縦に回ってしまう
    private var chips: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { chipItems }
            } else {
                HStack(spacing: 8) { chipItems }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var chipItems: some View {
        let items = TrunkArrivalText.chips(label)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(JPFont.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(item.text)
                    .font(JPFont.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(TrunkStyle.chip, in: Capsule())
        }
        // 一緒に届いた硬貨（公開の投稿1件で1枚・2026-10-17 次の版）。2026-11-23（札 #716）: 羅針盤の硬貨が
        // 回りながら札に落ちて入り、針が揺れて北で止まる（押す回数は 0 回のまま。動きを減らす設定では最初から札にある）
        if batch.coins > 0 {
            TimelineView(.animation(minimumInterval: nil, paused: coinFallStart == nil)) { ctx in
                let fall = coinFallStart.map { ctx.date.timeIntervalSince($0) }
                let landedFor = fall.map { $0 - TrunkMotion.coinFallSeconds } ?? -1
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 14, turn: landedFor >= 0 ? TrunkMotion.needleAngle(elapsed: landedFor) : 0)
                        .opacity(coinRested ? 1 : 0)
                        .overlay {
                            if let fall, fall < TrunkMotion.coinFallSeconds {
                                let p = fall / TrunkMotion.coinFallSeconds
                                let scale = TrunkMotion.coinFallScale.value(p)
                                TrunkCoinMark(size: TrunkMotion.coinFallSize, turn: TrunkMotion.needle.value(p))
                                    .scaleEffect(x: scale * TrunkMotion.coinFlip.value(p), y: scale)
                                    .offset(y: TrunkMotion.coinFallY.value(p))
                                    .opacity(TrunkMotion.coinFallOpacity.value(p))
                                    .allowsHitTesting(false)
                            }
                        }
                    Text(TrunkText.coinChip(batch.coins))
                        .font(JPFont.footnote.weight(.semibold))
                        .lineLimit(1)
                        .opacity(coinRested ? 1 : 0)
                }
                .foregroundStyle(WebTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(TrunkStyle.chip, in: Capsule())
                .scaleEffect(landedFor >= 0 ? TrunkMotion.chipBump.value(landedFor / TrunkMotion.chipBumpSeconds) : 1)
            }
            .zIndex(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trunk.arrived.coin")
        }
        // 一緒に届いたかけら（札 #713・サーバーが返したときだけ）。切符の切れ端の絵と「かけら +1」
        if batch.fragments > 0 {
            HStack(spacing: 6) {
                TrunkFragmentPieceView(index: 2, size: 10, shadow: false)
                    .frame(width: 10, height: 16)
                Text(TrunkFragmentText.chip(batch.fragments))
                    .font(JPFont.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(TrunkStyle.chip, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trunk.arrived.fragment")
        }
    }

    /// 手持ちの棒（読めたときだけ）
    @ViewBuilder
    private var pocket: some View {
        if let state = model.state {
            HStack(spacing: 8) {
                Text(L("手持ち", "Pocket"))
                TrunkPocketBar(count: state.pocket.count, limit: state.limit)
                    .frame(width: 120)
                Text(TrunkText.pocketCounter(count: state.pocket.count, limit: state.limit))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                Text(TrunkText.remaining(count: state.pocket.count, limit: state.limit))
            }
            .font(JPFont.footnote)
            .foregroundStyle(TrunkStyle.muted)
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if offlineFailed {
                Text(TrunkArrivalCopy.offlineNote)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("trunk.arrived.offline")
            } else if let error = model.actionError, !(redoFailed && !model.lastWriteRefused) {
                // 作り直しが届かなかったときの一言は作り直すボタンの上（`TrunkRedoButton`）
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            if customOffer {
                customActions
            } else {
                TrunkRedoButton(model: model, label: label, offline: connectivity.isOffline, rolling: $rolling,
                                failed: $redoFailed, idPrefix: "trunk.arrived")
                Button { Task { await stickAll() } } label: {
                    // 写真のある画面の主ボタンは白（板 05・2026-11-12 判断）
                    TrunkButtonFace(title: TrunkArrivalCopy.stickTitle(count: count), kind: .mainOnPhoto)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityIdentifier("trunk.arrived.stick")
                Button { dismiss() } label: {
                    TrunkButtonFace(title: TrunkArrivalCopy.laterTitle, kind: .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.arrived.keep")
            }
            HStack(spacing: 8) {
                // 共有は任意の副ボタン（公開の投稿だけ・押さなければ何も起きない・44pt）
                if arrival.shareable,
                   let url = PhotoLink.url(photoId: arrival.label.photoId, isPublished: false) {
                    ShareLink(item: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.callout)
                                .accessibilityHidden(true)
                            Text(L("共有", "Share"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(WebTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("この写真を共有", "Share this photo"))
                    .accessibilityIdentifier("trunk.arrived.share")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    /// 作れるようになった投稿の主ボタンと副（「好きなデザインで作る」「このまま貼る」・#706）
    @ViewBuilder
    private var customActions: some View {
        Button { showCustom = true } label: {
            TrunkButtonFace(title: TrunkText.customTitle, kind: .mainOnPhoto)
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityIdentifier("trunk.arrived.custom")
        Button { Task { await stickAll() } } label: {
            TrunkButtonFace(title: count > 1 ? TrunkArrivalCopy.stickTitle(count: count) : TrunkText.customKeepTitle,
                            kind: .secondary)
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .accessibilityIdentifier("trunk.arrived.stick")
        Text(TrunkText.customLaterNote)
            .font(JPFont.footnote)
            .foregroundStyle(TrunkStyle.faint)
            .multilineTextAlignment(.center)
    }

    /// 届いたラベルを全部貼る（1 枚なら今までどおり1枚）。貼れたら閉じ、閉じたあとの知らせに「取り消す」を添える。
    /// まだ読めていなければ読んでから貼る（`stickEnsuringLoaded`）。電波が無くて貼れなければ手持ちにあると言う
    private func stickAll() async {
        offlineFailed = false
        let ids = remaining.map(\.label.id)
        guard await model.stickEnsuringLoaded(ids[0], offline: connectivity.isOffline) else {
            offlineFailed = connectivity.isOffline || model.phase == .offline
            return
        }
        let rest = await model.stickAll(Array(ids.dropFirst()))
        let stuck = customStuck + [ids[0]] + rest
        // 知らせは閉じ切ってから全体で1つだけ（ここで出すと、閉じる間に届いた画面と全体で2つ見える）
        // 途中で貼れなかった分は手持ちに残る（閉じたあとの知らせで枚数を言う）。取り消しは戻せたかを返す
        TrunkArrivals.shared.noteStuckFromArrival(count: stuck.count, left: ids.count + customStuck.count - stuck.count) { [model] in
            await model.unstickAll(stuck) == stuck.count
        }
        dismiss()
    }

    /// 好きなデザインで1枚作って貼った（#706）。**残りがあれば閉じずに次の1枚へ**（2枚目から先も作り直し・好きなデザインを
    /// 使えるように・確かめ役の指摘 2026-11-23）。最後の1枚なら閉じて、貼った全部を知らせる
    private func finishCustom(_ id: String) {
        customStuck.append(id)
        let next = TrunkArrivalCursor.next(after: current, count: batch.arrivals.count)
        guard let next else {
            let stuck = customStuck
            TrunkArrivals.shared.noteStuckFromArrival(count: stuck.count, left: 0) { [model] in
                await model.unstickAll(stuck) == stuck.count
            }
            dismiss()
            return
        }
        current = next
        redoFailed = false
        rolling = false
    }
}

/// 届いた画面の「いま見ている1枚」の進め方（何枚も届いたとき・#706）。次の番号、最後なら nil
enum TrunkArrivalCursor {
    static func next(after current: Int, count: Int) -> Int? {
        current + 1 < count ? current + 1 : nil
    }
}

/// 届いた画面の札の言葉（モック: 「その場で撮った写真」「桜の時季だけの図柄」）
enum TrunkArrivalText {
    struct Chip: Equatable {
        let symbol: String
        let text: String
    }

    static func chips(_ label: TrunkLabel) -> [Chip] {
        var out: [Chip] = []
        if label.kind == .milestone, let m = label.milestone {
            out.append(Chip(symbol: "star", text: L("節目のラベル\u{2002}\(TrunkLabelDesign.milestoneWords(m).ja)",
                                                    "Milestone\u{2002}\(TrunkLabelDesign.milestoneWords(m).en.capitalized)")))
        } else if label.kind == .timeslot, let t = label.timeslot {
            out.append(Chip(symbol: "clock", text: L("\(TrunkLabelDesign.timeslotWords(t).ja)に撮った図柄",
                                                     "\(TrunkLabelDesign.timeslotWords(t).en.capitalized) design")))
        } else if let s = label.season {
            out.append(Chip(symbol: "clock", text: L("\(TrunkLabelDesign.seasonWords(s).ja)の時季だけの図柄",
                                                     "\(TrunkLabelDesign.seasonWords(s).en.capitalized)-only design")))
        }
        if !label.place.name.isEmpty {
            out.append(Chip(symbol: "mappin.and.ellipse", text: L("\(label.place.name)の図柄", "\(label.place.name) design")))
        }
        if label.foil {
            out.append(Chip(symbol: "sparkles", text: L("箔押し（まれに）", "Gold foil (rare)")))
        }
        return Array(out.prefix(2))
    }
}
