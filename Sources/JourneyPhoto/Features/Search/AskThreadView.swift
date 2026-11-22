import SwiftUI
import MapKit

/// 「AI に頼む」の答え（札 #652・#663 の案A・#675 の答えの形）。
///
/// 2026-11-21 判断（札 #675・Artifact「AI に頼む 独立の案」版3「答えの形 磨いた推奨」）: 答えの下はいつも
/// **頭の文 → 形 → 一手 → 次に頼めること → どこで答えたか** の順。形は答えの種類ごとに選ぶ（`AskAnswerLayout`）:
/// 札を横に送る（#663 の案A）、札を縦に積む（大きな字）、札1枚を広く、旅行プランの流れ、頭の文だけ。
///
/// - 使い切った帯と圏外の帯は答えの上に1本だけ。確かめのダイアログは出さない
/// - 一手（旅行プランにする、仲間に送る、旅行プランを開く）と次に頼めることは**アプリが決める**（AI は書かない・押しても AI は呼ばない）
/// - 新しく頼むと、前の答えは「質問と中身の1行」に畳む（押すと開く）
/// - いま届いた答えは少しずつ出す（頭の文が先、札と一手はあと）。読み込み中の骨格は答えの種類の形（字から分かるとき）
/// - **他人の写真は持ち主の写真の詳細へ連れて行くだけ**（保存、書き出し、作り替えの道は作らない・CLAUDE.md）。仲間に送るのはリンクだけ
struct AskThreadView: View {

    @ObservedObject var engine: AskEngine
    /// 観光スポットの頁と写真の詳細に渡す一覧（探すの画面の控え）
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool
    var onFollowUp: (String) -> Void
    var onRelax: (AskExchange) -> Void
    /// 「AI に頼む」の画面の中（札 #675）。続けて聞く欄と残りの回数は画面の下と上に出すので、ここでは出さない
    var inScreen = false
    /// 次に頼めること（チップ）を押したとき。欄に入れるだけ（送るのは送信のボタン）
    var onFill: (String) -> Void = { _ in }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType

    @State private var followUp = ""
    @FocusState private var followFocused: Bool
    @State private var showPro = false
    /// 畳んだ答えのうち、開いたもの
    @State private var expanded: Set<String> = []
    /// 一手の行き先（仲間に送るシート、旅行プランの招待）
    @State private var actRequest: AskActRequest?
    /// 開く旅行プラン（旅行プランを開く、旅行プランにするで作ったもの）
    @State private var openPlanId: String?
    /// 旅行プランにするで保存している最中
    @State private var makingPlan = false

    /// 大きな字（およそ 1.3 倍から）: 札は縦に積み、一手は縦に並べる（版3「大きな字」）
    private var largeText: Bool { dynamicType >= .xxLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            // UI テストのときだけ（見本の口 `-JPAskFixture`）: いまの段と経過（ms）。落ちた試験が失敗の文に出す（run 1612 の調べ）
            if AskFixture.isOn {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("search.ask.stage")
                    .accessibilityValue(engine.stageLog.joined(separator: " "))
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("search.ask.probe")
                    .accessibilityValue("thread=\(engine.thread.count) pending=\(engine.pending != nil) kind=\(engine.pendingKind?.rawValue ?? "-")"
                                        + " layout=\(engine.thread.last.map { "\(AskAnswerLayout.layout(for: $0.answer, largeText: largeText))" } ?? "-")"
                                        + " follow=\(followFocused) spotCount=\(engine.spotsById.count) photoCount=\(engine.photosById.count)")
            }
            ForEach(Array(engine.thread.enumerated()), id: \.element.id) { index, exchange in
                let isLatest = index == engine.thread.count - 1 && engine.pending == nil
                if inScreen, !isLatest, !expanded.contains(exchange.id) {
                    AskFoldRow(question: exchange.question,
                               summary: AskFold.summary(exchange.answer, names: names(exchange.answer)),
                               onOpen: { expanded.insert(exchange.id) })
                } else {
                    if inScreen || index > 0 { questionBubble(exchange.question) }
                    answerView(exchange, isLatest: isLatest)
                }
            }
            if let pending = engine.pending {
                if inScreen || !engine.thread.isEmpty { questionBubble(pending) }
                loading
            }
            // AI の画面の中では、下の欄の上に同じ1行がある（札 #675）
            if !inScreen, engine.thread.contains(where: { $0.answer.usedAI }) {
                Text(AskText.disclaimer)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityIdentifier("search.ask.disclaimer")
            }
            if !engine.thread.isEmpty, !inScreen { followUpField }
            if AskFixture.isOn {
                // 札の並びの調べ（回 1644）。0.5 秒ごとに自分だけ描き直す（`PerfProbeOverlay` と同じ作り）
                TimelineView(.animation(minimumInterval: 0.5)) { _ in
                    Text(".")
                        .font(.caption2)
                        .foregroundStyle(Color.clear)
                        .accessibilityIdentifier("search.ask.carouselStats")
                        .accessibilityValue(AskCarouselStats.shared.summary())
                }
                .frame(width: 1, height: 1)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        // 札の左、並びの左、頭の文の左を同じ座標で測る（原点は答えの画面の左端・回 1644 の調べ）
        .coordinateSpace(.named(AskCarouselStats.space))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.thread")
        // 出ている答えの観光スポットのうち、まだ索引だけの行の詳細（写真）を読み足す（2026-11-22 判断・owner「画像出てこないの悲しい」）。
        // 旅行プランの流れ・控えから戻した会話も含む。同じ鍵では読み直さず、圏外と答えのあとの読み込みの最中は読まない
        .task(id: SpotDetailNeeds.askTaskKey(detailNeeds, offline: connectivity.isOffline, loading: engine.detailsLoading)) {
            let needs = detailNeeds
            guard !needs.isEmpty, !connectivity.isOffline, !engine.detailsLoading else { return }
            let merged = await environment.spots.withDetails(needs, for: needs)
            guard !Task.isCancelled else { return }
            engine.overlayDetails(merged)
        }
        // 新しく頼んだら、開いていた前の答えはまた畳む
        .onChange(of: engine.pending) { _, pending in
            if pending != nil { expanded = [] }
        }
        .fullScreenCover(isPresented: $showPro) { PaywallView(origin: .ask) }
        .modifier(AskActFlow(request: $actRequest, openPlanId: $openPlanId))
    }

    /// 詳細を読み足す観光スポット: 畳んでいない答え（いちばん新しい答えと開いた答え。画面の外の帯では全部）に出ている、まだ索引だけの行
    private var detailNeeds: [OfficialSpot] {
        let thread = engine.thread
        let latestId = engine.pending == nil ? thread.last?.id : nil
        return SpotDetailNeeds.asked(thread, shown: { !inScreen || $0.id == latestId || expanded.contains($0.id) },
                                     spotsById: engine.spotsById)
    }

    /// 答えの札の観光スポットの名前（畳んだ1行の中身）
    private func names(_ a: AskAnswer) -> [String] {
        a.spotIds.compactMap { engine.spotsById[$0]?.name }
    }

    // MARK: - 1往復

    /// 頼んだ文（模型 `.bub`: 白の塗りに墨、15、角 18、幅 78% まで）
    private func questionBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 64)
            Text(text)
                // 15pt（字の大きさの設定に合わせて大きくなる）
                .font(.subheadline)
                .foregroundStyle(WebTheme.accentText)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(WebTheme.accentBackground, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("search.ask.question")
        }
    }

    @ViewBuilder
    private func answerView(_ exchange: AskExchange, isLatest: Bool) -> some View {
        let a = exchange.answer
        let fresh = engine.freshId == exchange.id
        let layout = AskAnswerLayout.layout(for: a, largeText: largeText)
        let spots = a.spotIds.compactMap { engine.spotsById[$0] }
        VStack(alignment: .leading, spacing: 12) {
            // 使い切った帯は、いちばん新しい答えにだけ1本
            if isLatest, let reason = a.limit { limitBand(reason) }
            if a.engine == .refused {
                // 断りは頭の文だけ（一手も次に頼めることも出さない・回数は使わない）。明朝 18。
                // 2026-11-20 判断: 続けて聞く欄を自動で選ばない（キーボードが断りの1行を覆う）
                AskLead(text: a.text, small: true)
                    .accessibilityIdentifier("search.ask.refusal")
            } else {
                switch a.state {
                case .empty:
                    emptyState(exchange)
                case .failed:
                    ErrorBanner(title: a.kind == .plan ? a.text : AskText.failedTitle,
                                message: a.kind == .plan ? L("もう一度押すと作り直します。", "Tap to try again.") : AskText.failedDetail) {
                        onFollowUp(exchange.question)
                    }
                default:
                    // 圏外は上に電波なしの帯（形はそのまま、頭の文は決まり文）
                    if a.state == .offline { AskOfflineBand() }
                    leadView(a, layout: layout, spots: spots)
                    Group { formView(layout, a: a, spots: spots) }
                        .modifier(AskReveal(active: fresh, delay: 0.25))
                    let acts = AskAct.acts(for: a, layout: layout, signedIn: auth.userId != nil, offline: connectivity.isOffline)
                    if !acts.isEmpty {
                        AskActsRow(acts: acts, vertical: largeText, busy: makingPlan) { act in tap(act, answer: a, spots: spots) }
                            .modifier(AskReveal(active: fresh, delay: 0.45))
                    }
                    if isLatest {
                        let next = AskNextAsks.make(for: a, layout: layout, spots: spots)
                        if !next.isEmpty {
                            AskNextChips(chips: next, onFill: onFill)
                                .modifier(AskReveal(active: fresh, delay: 0.45))
                        }
                    }
                }
                // 圏外の1行は上の帯が言う（案A）
                if let note = a.note, a.state != .offline {
                    Text(note)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("search.ask.note")
                }
                if !a.engineLine.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: a.engine == .server ? "cloud" : "iphone").accessibilityHidden(true)
                        Text(a.engineLine).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a.engineLine)
                    .accessibilityIdentifier("search.ask.engine")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.answer")
    }

    /// 頭の文（明朝 20、長いときは 18）。使い方の頁の行（AI を使わない答え）は札の中にそのまま
    @ViewBuilder
    private func leadView(_ a: AskAnswer, layout: AskAnswerLayout, spots: [OfficialSpot]) -> some View {
        if a.engine == .table, layout == .leadOnly, !a.text.isEmpty {
            textCard(a.text, general: a.general)
        } else if let lead = AskAnswerShape.leadLine(a) {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                if a.general, layout == .leadOnly { generalBadge }
                AskLead(text: lead.text, small: lead.small)
                    .accessibilityIdentifier("search.ask.text")
            }
        }
    }

    /// 答えの形（`AskAnswerLayout`）
    @ViewBuilder
    private func formView(_ layout: AskAnswerLayout, a: AskAnswer, spots: [OfficialSpot]) -> some View {
        switch layout {
        case .spotCarousel:
            AskSpotCarousel(spots: spots, reasons: a.reasons ?? [:], showsMap: a.state != .offline,
                            settled: !engine.detailsLoading,
                            officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
                // 回 1641: 名前だけを付けると中の要素の名前（`search.ask.cardProbe` など）が上書きされた。入れ物として組にする
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search.ask.spots")
        case .spotStack:
            AskSpotStack(spots: spots, reasons: a.reasons ?? [:], officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search.ask.spots")
        case .spotWide:
            if let spot = spots.first {
                AskWideSpotCard(spot: spot, reason: a.reasons?[spot.spotId], showsMap: a.state != .offline,
                                officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("search.ask.spots")
            }
        case .planFlow:
            AskPlanTimeline(days: (a.plan?.days ?? []).map { $0.compactMap { engine.spotsById[$0] } }.filter { !$0.isEmpty },
                            officialSpots: officialSpots, photos: photos, photosKnown: photosKnown,
                            offline: connectivity.isOffline)
        case .leadOnly:
            // 文だけの答えでも、AI が引いた公開の写真があれば格子で見せる（押すと持ち主の写真の詳細へ）
            if !a.photoIds.isEmpty, a.engine != .refused { photoGrid(a.photoIds) }
        }
    }

    private var generalBadge: some View {
        Text(AskText.generalBadge)
            .font(JPFont.caption.weight(.semibold))
            .foregroundStyle(WebTheme.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
            .accessibilityIdentifier("search.ask.general")
    }

    /// 使い方の頁の行（AI を使わない答え）。札 #0E0E0F、縁 白 8%、角 16
    private func textCard(_ text: String, general: Bool) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            if general { generalBadge }
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("search.ask.text")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jpCardFace()
    }

    // MARK: - 一手（押しても AI は呼ばない）

    private func tap(_ act: AskAct, answer: AskAnswer, spots: [OfficialSpot]) {
        switch act {
        case .makePlan:
            Task { await makePlan(spots) }
        case .share:
            actRequest = .share(spots: spots)
        case .sharePlan:
            if let plan = answer.plan, let planId = plan.planId { actRequest = .sharePlan(planId: planId, title: plan.title) }
        case .openPlan:
            if let planId = answer.plan?.planId { openPlanId = planId }
        }
    }

    /// 旅行プランにする（版3: 1回で旅行プランの画面へ。並べ方は座標で決め、AI を使わない・回数も使わない）。
    /// 札の観光スポットを座標で日に分けて保存し、できた旅行プランを開く
    private func makePlan(_ spots: [OfficialSpot]) async {
        guard !makingPlan, auth.userId != nil, !spots.isEmpty else { return }
        makingPlan = true
        defer { makingPlan = false }
        let days = AskQuickPlan.days(spots)
        let title = TripPlanService.titleToSend(AskQuickPlan.title(days))
        do {
            let before = Set(try await environment.trips.list().map(\.planId))
            let list = try await environment.trips.create(title: title, days: TripDraft.tripDays(days), startDate: nil, endDate: nil)
            guard let made = TripAICreated.pick(in: list.plans, before: before, title: title) else {
                toasts.show(L("旅行プランを保存できませんでした", "Couldn't save the trip"), kind: .failure)
                return
            }
            TripPlanChanges.shared.changed(made.planId)
            openPlanId = made.planId
        } catch {
            toasts.show(connectivity.isOffline ? L("電波が届かないので、旅行プランを保存できませんでした", "No signal, so the trip couldn't be saved")
                        : L("旅行プランを保存できませんでした", "Couldn't save the trip"), kind: .failure)
        }
    }

    /// 使い切った・休んでいるときの帯（答えの上に1本だけ）。Pro の案内へ連れて行けるのは無料の人の今日と今月の分だけ
    private func limitBand(_ reason: AskLimitReason) -> some View {
        let band = AskLimitText.band(reason: reason, usage: engine.usage, answeredByTable: true)
        return Button {
            if band.proLine != nil { showPro = true }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                Image(systemName: "sparkle").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(band.title)
                        .font(JPFont.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !band.detail.isEmpty {
                        Text(band.detail)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pro = band.proLine {
                        Text(pro).font(JPFont.caption.weight(.semibold)).underline()
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(band.proLine == nil)
        .accessibilityIdentifier("search.ask.band")
    }

    // MARK: - みんなの写真（持ち主の写真の詳細へ連れて行くだけ）

    private func photoGrid(_ ids: [String]) -> some View {
        let shown = ids.compactMap { engine.photosById[$0] }
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(L("みんなの写真", "Photos from everyone"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(shown) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, context: shown)
                    } label: {
                        DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                               aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                               alignment: photo.gridAlignment,
                                               assumedRatioLimit: PhotoFrame.assumedRatioLimit)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("写真の詳細を開く: ", "Open photo: ") + (photo.title?.resolved() ?? ""))
                    .accessibilityIdentifier("search.ask.photo")
                }
            }
        }
    }

    // MARK: - 状態

    /// 読み込み中（版3「待ち時間」: 押した直後から、頭の文の骨格と、字から分かる答えの種類の形の骨格）
    private var loading: some View {
        AskLoadingSkeleton(kind: engine.pendingKind)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AskText.loading)
            .accessibilityIdentifier("search.ask.loading")
    }

    /// 空（何が無いか → 理由 → 押せる言い替えを1つ）。言い替えは AI を呼ばず、回数も使わない
    private func emptyState(_ exchange: AskExchange) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text("EMPTY")
                .font(JPFont.eyebrow)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Text(AskText.emptyTitle)
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
            if !exchange.answer.text.isEmpty {
                Text(exchange.answer.text)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let relaxed = exchange.answer.relaxedQuery {
                Button { onRelax(exchange) } label: {
                    Text(relaxed)
                        .jpOutlineButton()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.ask.relax")
            }
        }
        .padding(.vertical, JPSpace.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.empty")
    }

    // MARK: - 続けて聞く

    private var followUpField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 17))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            JPTextField(AskText.followUp, text: $followUp)
                .focused($followFocused)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(WebTheme.foreground)
                // 2026-11-20 判断（札 #662）: キーボードのキーでは AI を呼ばない（変換の確定のつもりで押して送ってしまう）。
                // キーは「完了」でキーボードを閉じるだけ。送るのは右の送信のボタンだけ
                .submitLabel(.done)
                .onSubmit { followFocused = false }
                .disabled(engine.pending != nil)
                .accessibilityLabel(AskText.followUp)
                .accessibilityIdentifier("search.ask.followUp")
            if !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 続きは頼みの形でなくても聞ける（「金沢では？」の前の会話がある）。途中の字（「京都で」）だけは送らない
                AskSendButton(enabled: !AskQuery.isUnfinished(followUp)) { sendFollowUp() }
                    .accessibilityIdentifier("search.ask.send")
            }
        }
        .jpSearchBoxFace()
    }

    private func sendFollowUp() {
        let text = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, engine.pending == nil, !AskQuery.isUnfinished(text) else { return }
        followUp = ""
        followFocused = false
        onFollowUp(text)
    }
}

/// 答えの地図の範囲（純粋な計算・`AskPinsMap` が使う）。
///
/// 2026-11-22 判断（owner「AIの答えで謎の枠あった。地図のスポットかな？周り見えないから全然わからないな」）:
/// 前は `.automatic` で、ピンが1つだと MapKit が最大まで寄せ、道も街も無い一色の面にピンが1つだけになっていた。
/// - **ピンが1つ:** その場所を真ん中に、半径 `singleRadius`（1.5km）を見せる。周りの道・駅・街の名前が読める広さ
///   （台帳の座標は約1km に丸めてあるので、これ以上寄せても精度は増えない。観光スポットの頁の地図の 0.05 度より少し寄せる）
/// - **ピンが2つ以上:** 全部の座標の外枠に、上下左右へ余白を足す（`spreadPadding` 倍）。`.automatic` は座標の点で枠を決めるので、
///   端のピンが地図の縁や左下の「法律に基づく情報」にかかることがあった。枠が狭いとき（近い2か所）は1つのときの広さより寄せない
///
/// 余白の決め方（2026-11-22 確かめ役の指摘で直した）: ピン（`SpotMapMarker`）は丸なので、`AskPinsMap` は座標を丸の
/// **真ん中**に置く（`anchor: .center`。既定の `.bottom` だと絵が座標から上へ伸び、北の端のピンが上の縁で切れた）。
/// 端の座標と縁の間が、選んだピンの半径（`selectedPinRadius` 約 38pt）＋ `edgeGap` 8pt より広くなるよう、
/// 地図の高さ `mapHeight` 160 から倍率を逆に出す（約 2.36 倍）。地図は横の方が長いので、東西はさらに余裕がある
enum AskMapFrame {
    /// ピンが1つのときに見せる半径（メートル）
    nonisolated static let singleRadius: Double = 1_500
    /// 答えの地図の高さ（札の並びの地図と広い札の地図で共通・`AskSpotCarousel.mapHeight`）
    nonisolated static let mapHeight: CGFloat = 160
    /// 選んだピンの見た目の半径（写真の丸 40 の半分＋光の輪 10、それを 1.27 倍）
    nonisolated static var selectedPinRadius: CGFloat {
        (SpotMapMarker.photoSize / 2 + SpotMapMarker.haloWidth) * SpotMapMarker.selectedScale
    }
    /// ピンの絵と地図の縁の間に残す隙間
    nonisolated static let edgeGap: CGFloat = 8
    /// 端の座標と縁の間に要る長さ（pt）
    nonisolated static var edgeClearance: CGFloat { selectedPinRadius + edgeGap }
    /// ピンが2つ以上のとき、外枠を何倍に広げるか。外枠の高さ h の地図で、上下に edgeClearance ずつ空く倍率
    nonisolated static var spreadPadding: Double { Double(mapHeight / (mapHeight - edgeClearance * 2)) }
    /// 緯度1度の長さ（メートル・目安）
    nonisolated static let metersPerDegree: Double = 111_000

    /// 見せる範囲。座標が無ければ nil（呼び出し側は地図を出さない）
    nonisolated static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: ((lats.min() ?? first.latitude) + (lats.max() ?? first.latitude)) / 2,
                                            longitude: ((lngs.min() ?? first.longitude) + (lngs.max() ?? first.longitude)) / 2)
        // 1つのときの広さ（経度は緯度で縮む分を戻して、東西も同じメートルにする）
        let minLat = singleRadius * 2 / metersPerDegree
        let cosLat = max(cos(center.latitude * .pi / 180), 0.01)
        let minLng = minLat / cosLat
        let spanLat = ((lats.max() ?? 0) - (lats.min() ?? 0)) * spreadPadding
        let spanLng = ((lngs.max() ?? 0) - (lngs.min() ?? 0)) * spreadPadding
        // 上限: 範囲の上下が北緯・南緯 90 度を越えない（日本の中では着かないが、座標の誤りで地図を壊さない）
        let maxLat = max(180 - 2 * abs(center.latitude), 0.0001)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: min(max(spanLat, minLat), maxLat),
                                                         longitudeDelta: min(max(spanLng, minLng), 360)))
    }
}

/// 答えの地図（ピンを押すと観光スポットの頁へ）。範囲は `AskMapFrame`（ピンが1つでも周りの街が見える広さ）。
/// ピンの名前の字は地図の上に出さない（2026-11-22 判断: 名前は上の札にある。字が大きくピンの下に出て、左下の
/// 「法律に基づく情報」に重なっていた）。読み上げの名前はピンのボタンに残す
struct AskPinsMap: View {
    let spots: [OfficialSpot]
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool
    /// 選んでいるピン（横に送った札の観光スポット・案A）。大きくする（`SpotMapMarker.selected`）
    var current: String? = nil
    /// ピンを押したとき。nil なら観光スポットの頁を開く。案A では札をその場所へ送る
    var onPick: ((OfficialSpot) -> Void)? = nil
    /// 地図の範囲。**最初から `AskMapFrame` の範囲を入れる**（2026-11-22 確かめ役の指摘）: `onAppear` で決めると、
    /// 観光スポットの頁から戻るたびに走り、利用者が動かした地図が元に戻った（`.automatic` が一瞬出ることも無くなる）
    @State private var camera: MapCameraPosition
    @State private var opened: OfficialSpot?
    @State private var showOpened = false

    init(spots: [OfficialSpot], officialSpots: [OfficialSpot], photos: [Photo], photosKnown: Bool,
         current: String? = nil, onPick: ((OfficialSpot) -> Void)? = nil) {
        self.spots = spots
        self.officialSpots = officialSpots
        self.photos = photos
        self.photosKnown = photosKnown
        self.current = current
        self.onPick = onPick
        _camera = State(initialValue: Self.framing(Self.pins(of: spots)))
    }

    /// ピン1つ（座標のある観光スポットだけ）
    private struct Pin: Identifiable {
        let spot: OfficialSpot
        let coordinate: CLLocationCoordinate2D
        var id: String { spot.spotId }
    }

    private static func pins(of spots: [OfficialSpot]) -> [Pin] {
        spots.compactMap { s in s.coords.map { Pin(spot: s, coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) } }
    }

    private var pins: [Pin] { Self.pins(of: spots) }

    private static func framing(_ pins: [Pin]) -> MapCameraPosition {
        AskMapFrame.region(for: pins.map(\.coordinate)).map { .region($0) } ?? .automatic
    }

    /// 範囲を決め直す目印。**答えの場所が替わったときだけ**決め直す（並べ直し）。頁から戻っただけでは決め直さない
    private var pinKey: String { pins.map { "\($0.id)@\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "|") }

    var body: some View {
        Map(position: $camera) {
            ForEach(pins) { pin in
                // 丸いピンなので座標を丸の真ん中に置く（既定の .bottom だと絵が上へ伸び、北の端のピンが上の縁で切れる・`AskMapFrame`）
                Annotation(pin.spot.name, coordinate: pin.coordinate, anchor: .center) {
                    Button {
                        if let onPick {
                            onPick(pin.spot)
                        } else {
                            opened = pin.spot
                            showOpened = true
                        }
                    } label: {
                        SpotMapMarker(photoURL: pin.spot.photo?.smallURL, fallbackURL: pin.spot.photo?.smallFallbackURL)
                            .selected(current == pin.spot.spotId)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pin.spot.name)
                    .accessibilityAddTraits(current == pin.spot.spotId ? .isSelected : [])
                    .accessibilityIdentifier("search.ask.pin")
                }
                .annotationTitles(.hidden)
            }
        }
        .onChange(of: pinKey) { _, _ in camera = Self.framing(pins) }
        // 地図のカメラの動き（タイルの読み込みや動きが続いているかの目安・UI テストのときだけ数える・回 1644 の調べ）
        .onMapCameraChange(frequency: .continuous) { _ in AskCarouselStats.shared.hit(.mapCam) }
        .navigationDestination(isPresented: $showOpened) {
            if let opened {
                OfficialSpotView(spot: opened, spots: officialSpots, photos: photos, photosKnown: photosKnown)
            }
        }
    }
}

/// AI に送るボタン（札 #662・2026-11-20 判断）。板 DM の送信（真鍮の塗り #B8955A に墨の上向きの矢印・写真の無い画面の主ボタン＝送信）を
/// 欄の中に入る大きさ（見た目 36、当たり 44）にしたもの。探すの欄と、答えの下の「続けて聞く」の欄で使う。
/// 押せないとき（途中の字）は DM の送れないときと同じ白 16% の地に白 50% の矢印（色だけにしない: 押せない印と、欄の下の1行）
struct AskSendButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? WebTheme.accentText : Color.white.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(enabled ? WebTheme.accentFill : Color.white.opacity(0.16), in: Circle())
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(AskEntry.sendLabel)
    }
}
