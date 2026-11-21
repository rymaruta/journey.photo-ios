import SwiftUI
import MapKit

/// 探すの「AI に頼む」の答え（札 #652・案 A「答えの下に続けて積む」・Artifact「AI に頼む」8版）。
///
/// 答えは**アプリの部品**で返す（板 Components 05 の場所の札、03 の地図のピン、みんなの写真の格子、
/// 01 の行動の札「行きたい」と副ボタン「旅行プランにする」）。文は短い1かたまり（札 #0E0E0F・縁 白 8%・角 16）。
///
/// - 答えの上に、使い切ったときの帯を1本だけ（真鍮 8% の地、真鍮の字・Components 05 の案内の帯）。確かめのダイアログは出さない
/// - 答えの下に、どこで答えたかの1行と「AI の答えは間違うことがあります」（AI を使った答えのとき）
/// - 下の欄で続けて聞ける（✦ の欄・続きも1回と数える）
/// - 4つの状態（読み込み中の骨格・空・失敗・圏外）は Components 06 の形
/// - **他人の写真は持ち主の写真の詳細へ連れて行くだけ**（保存、書き出し、作り替えの道は作らない・CLAUDE.md）
struct AskThreadView: View {

    @ObservedObject var engine: AskEngine
    /// 観光スポットの頁と写真の詳細に渡す一覧（探すの画面の控え）
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool
    var onFollowUp: (String) -> Void
    var onRelax: (AskExchange) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var followUp = ""
    @FocusState private var followFocused: Bool
    @State private var showPro = false
    /// 読み込み中の骨格は 0.3 秒より早ければ出さない（Components 06）
    @State private var showSkeleton = false
    // 旅行プランにする（札 #621 のシートへ）
    @State private var planAsk: TripAIAsk?
    @State private var showPlanSheet = false
    @State private var planJob: TripAIJobs.Job?
    @State private var showPlanJob = false
    @StateObject private var plans = TripPlansModel()

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            // UI テストのときだけ（見本の口 `-JPAskFixture`）: いまの段と経過（ms）。落ちた試験が失敗の文に出す（run 1612 の調べ）
            if AskFixture.isOn {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("search.ask.stage")
                    .accessibilityValue(engine.stageLog.joined(separator: " "))
                // 閉じる前の状態（回 1619、1626 の「Failed to terminate」の調べ・2026-11-20）: 答えの数、用意している問い、骨格、
                // 地図を出しているか、続けて聞く欄に焦点があるか
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("search.ask.probe")
                    .accessibilityValue("thread=\(engine.thread.count) pending=\(engine.pending != nil) skeleton=\(showSkeleton)"
                                        + " maps=\(engine.thread.filter { $0.answer.state != .offline && !$0.answer.spotIds.isEmpty }.count)"
                                        + " follow=\(followFocused) spotCount=\(engine.spotsById.count) photoCount=\(engine.photosById.count)")
            }
            ForEach(Array(engine.thread.enumerated()), id: \.element.id) { index, exchange in
                if index > 0 { questionBubble(exchange.question) }
                answerView(exchange, isLatest: index == engine.thread.count - 1)
            }
            if let pending = engine.pending {
                if !engine.thread.isEmpty { questionBubble(pending) }
                loading
            }
            if engine.thread.contains(where: { $0.answer.usedAI }) {
                Text(AskText.disclaimer)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityIdentifier("search.ask.disclaimer")
            }
            if !engine.thread.isEmpty { followUpField }
        }
        .padding(.horizontal, JPSpace.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.thread")
        .task(id: engine.pending) {
            showSkeleton = false
            guard engine.pending != nil else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { showSkeleton = true }
        }
        .fullScreenCover(isPresented: $showPro) { PaywallView(origin: .ask) }
        .sheet(isPresented: $showPlanSheet) {
            if let planAsk {
                TripAIAskSheet(ask: planAsk, placeChoices: placeChoices, onDevice: TripAIDevice.isAvailable,
                               start: startPlanAfterSheet, index: officialSpots)
            }
        }
        .navigationDestination(isPresented: $showPlanJob) {
            if let planJob { TripAIBuildingView(job: planJob, plans: plans) }
        }
    }

    // MARK: - 1往復

    private func questionBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WebTheme.surface8, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("search.ask.question")
        }
    }

    @ViewBuilder
    private func answerView(_ exchange: AskExchange, isLatest: Bool) -> some View {
        let a = exchange.answer
        VStack(alignment: .leading, spacing: JPSpace.s) {
            // 使い切った帯は、いちばん新しい答えにだけ1本
            if isLatest, let reason = a.limit { limitBand(reason) }
            if a.engine == .refused {
                // 案A（2026-11-20 owner 承認）: 断りは枠を外し、答えの1〜2文と同じ所に明朝 18。
                // 2026-11-20 判断（模型と違えた所）: 模型は「続けて聞く欄を選んだ状態」だが、**自動で選ばない。**
                // キーボードが上がると断りの1行と札を覆う。打ち直したい人は欄を押せばすぐ打てる（押す回数は1回増えるが、見えないより分かりやすい）
                AskLead(text: a.text, small: true)
                    .accessibilityIdentifier("search.ask.refusal")
            } else {
                if !a.chips.isEmpty { chipsRow(a.chips) }
                if isLatest, let usage = engine.usage, a.usedAI {
                    // 印は飾り。読み上げと UI テストは字だけを読む（run 1608: Label のままだと「スパークルの星」と読んだ）
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle").accessibilityHidden(true)
                        Text(usage.remainingLine)
                    }
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(usage.remainingLine)
                    .accessibilityIdentifier("search.ask.usage")
                }
                switch a.state {
                case .empty:
                    emptyState(exchange)
                case .failed:
                    ErrorBanner(title: AskText.failedTitle, message: AskText.failedDetail) {
                        onFollowUp(exchange.question)
                    }
                default:
                    // 案A（札 #663・2026-11-20 owner 承認「推奨いいね」・Artifact「AI に頼む 答えの見た目」）:
                    // 圏外は上に電波なしの帯 → はじめの1〜2文を明朝 → 「観光スポットの情報から」→ 写真の札を横に送る → 地図
                    if a.state == .offline { AskOfflineBand() }
                    if !a.spotIds.isEmpty {
                        if let lead = AskAnswerShape.leadLine(a) {
                            AskLead(text: lead.text, small: lead.small)
                                .accessibilityIdentifier("search.ask.text")
                        }
                        if !a.sources.isEmpty { sourcesLine(a.sources, count: a.spotIds.count) }
                        spotSection(a)
                    } else {
                        if !a.text.isEmpty { textCard(a.text, general: a.general) }
                        // 答えのもとは1行だけ（「観光スポットの情報から」・2026-11-20 判断 札 #663）
                        if !a.sources.isEmpty { sourcesLine(a.sources, count: nil) }
                    }
                    if !a.photoIds.isEmpty { photoGrid(a.photoIds) }
                    if a.offersPlan, !a.spotIds.isEmpty, auth.userId != nil { planButton(exchange) }
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

    /// 答えの文（札の中・一般的な答えの印）。文ははじめの1〜2文だけ（`AskAnswerShape`・札 #663）
    private func textCard(_ text: String, general: Bool) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            if general {
                Text(AskText.generalBadge)
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.text2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                    .accessibilityIdentifier("search.ask.general")
            }
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

    /// 答えのもとの1行（押しても頁は開かない。使い方の入口は設定の1か所だけ）。2026-11-20 判断（札 #663）: 「引いたもの」の見出しと
    /// 「観光スポットの台帳」の並びを「観光スポットの情報から」の1行にした（「台帳」は中の言葉）
    private func sourcesLine(_ sources: [AskAnswer.Source], count: Int?) -> some View {
        let line = AskText.sourcesLine(sources)
        let spoken = count.map { line + L("、\($0)か所", ", \($0) spots") } ?? line
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "book").accessibilityHidden(true)
            Text(line).fixedSize(horizontal: false, vertical: true)
            if let count {
                // 数字は SF の等幅数字（owner の好み）。区切りは余白（中黒を使わない）
                Text(L("\(count)か所", "\(count) spots"))
                    .font(JPFont.caption.monospacedDigit())
                    .padding(.leading, 6)
            }
        }
        .font(JPFont.caption)
        .foregroundStyle(WebTheme.text3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("search.ask.sources")
    }

    /// 読み取りの札（押せない字の札。見本の「現在地から 30km」「夕方」）
    private func chipsRow(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.chipText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(WebTheme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("こう読みました: ", "Read as: ") + chips.joined(separator: L("、", ", ")))
        .accessibilityIdentifier("search.ask.chips")
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

    // MARK: - 観光スポットの札と地図

    /// 案A: 眉「観光スポット」と「1 / 8」→ 写真の大きな札を横に送る並び → 地図（圏外では出さない）。
    /// 札を送ると地図のピンが大きくなり、ピンを押すと札がその場所へ送られる
    private func spotSection(_ a: AskAnswer) -> some View {
        let spots = a.spotIds.compactMap { engine.spotsById[$0] }
        return AskSpotCarousel(spots: spots, reasons: a.reasons ?? [:], showsMap: a.state != .offline,
                               officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
            .accessibilityIdentifier("search.ask.spots")
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

    // MARK: - 旅行プランにする（札 #621 のシート）

    private func planButton(_ exchange: AskExchange) -> some View {
        Button {
            openPlan(exchange)
        } label: {
            // 副ボタン（線・白 14% の縁・高さ 44・板 Components 01）
            Label(AskText.makePlan, systemImage: "calendar")
                .jpOutlineButton()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.ask.plan")
    }

    /// 答えの場所と頼みを、#621 の頼みの札（行き先、日数、好み）に入れて開く。答えの場所は先に入れる
    private func openPlan(_ exchange: AskExchange) {
        var ask = TripAIAsk.reading(exchange.question, spots: officialSpots)
        let spots = exchange.answer.spotIds.compactMap { engine.spotsById[$0] }
        ask.mustSpotIds = Array(spots.prefix(5).map(\.spotId))
        if !ask.hasPlace, let pref = spots.first?.region?.prefecture {
            ask.prefectures = [pref]
            ask.place = TripAIDestination.prefectureShort(pref)
        }
        planAsk = ask
        showPlanSheet = true
    }

    private var placeChoices: [(label: String, prefecture: String)] {
        var prefs: [String] = []
        for id in engine.thread.flatMap(\.answer.spotIds) {
            if let p = engine.spotsById[id]?.region?.prefecture, !prefs.contains(p), prefs.count < 6 { prefs.append(p) }
        }
        return prefs.map { (TripAIDestination.prefectureShort($0), $0) }
    }

    /// シートが閉じ切ってから日程の画面を積む（閉じている途中に積むと捨てられる・`TripPlansView` と同じ）
    private func startPlanAfterSheet(_ ask: TripAIAsk) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let owner = auth.userId else { return }
            let backend = TripAIJobs.Backend.live(environment: environment, auth: auth, owner: owner, index: officialSpots,
                                                  wishlist: wishlist.spotIds, connectivity: connectivity)
            planJob = TripAIJobs.shared.start(ask, owner: owner, usage: nil, backend: backend)
            showPlanJob = true
        }
    }

    // MARK: - 状態

    /// 読み込み中（案A: 文の2行と写真の札の形と地図の骨格。0.3 秒より早ければ出さない）
    @ViewBuilder
    private var loading: some View {
        if showSkeleton {
            AskLoadingSkeleton()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(AskText.loading)
                .accessibilityIdentifier("search.ask.loading")
        }
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

/// 答えの地図（ピンを押すと観光スポットの頁へ）。地図は答えの場所が全部入る範囲（`.automatic`）
struct AskPinsMap: View {
    let spots: [OfficialSpot]
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool
    /// 選んでいるピン（横に送った札の観光スポット・案A）。大きくする（`SpotMapMarker.selected`）
    var current: String? = nil
    /// ピンを押したとき。nil なら観光スポットの頁を開く。案A では札をその場所へ送る
    var onPick: ((OfficialSpot) -> Void)? = nil
    @State private var camera: MapCameraPosition = .automatic
    @State private var opened: OfficialSpot?
    @State private var showOpened = false

    /// ピン1つ（座標のある観光スポットだけ）
    private struct Pin: Identifiable {
        let spot: OfficialSpot
        let coordinate: CLLocationCoordinate2D
        var id: String { spot.spotId }
    }

    private var pins: [Pin] {
        spots.compactMap { s in s.coords.map { Pin(spot: s, coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) } }
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(pins) { pin in
                Annotation(pin.spot.name, coordinate: pin.coordinate) {
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
            }
        }
        .navigationDestination(isPresented: $showOpened) {
            if let opened {
                OfficialSpotView(spot: opened, spots: officialSpots, photos: photos, photosKnown: photosKnown)
            }
        }
    }
}

/// 探すの欄の見本の字（「AI に聞いてみる: …」・札 #652）。**4秒ごとに入れ替え、薄く消えて出る**。
/// 動きを減らす設定では最初の見本で止める。入れ替えで探すの画面全体を描き直さないよう、この View だけが数を持つ。
/// 字は押しても入らない（欄の見本の字と同じ）。読み上げは欄の名前「AI に聞く、または探す」だけ（ここは読まない）
struct AskRotatingPrompt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        let month = Calendar(identifier: .gregorian).component(.month, from: Date())
        Text(AskQuery.prompt(index: reduceMotion ? 0 : index, month: month))
            .font(.callout)
            .foregroundStyle(WebTheme.placeholder)
            .lineLimit(1)
            .id(reduceMotion ? 0 : index)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                // UI テストのときは入れ替えない（4秒ごとの動きが続き、アプリが静まらない・回 1619、1626 の閉じられない件の調べ）
                guard !reduceMotion, !AskFixture.isOn, !PerfRecorder.shared.isEnabled else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: AskQuery.rotateSeconds * 1_000_000_000)
                    if Task.isCancelled { return }
                    withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
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
        .accessibilityLabel(SearchSubmit.sendLabel)
    }
}
