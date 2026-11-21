import SwiftUI

/// 「AI に頼む」の画面（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」の案1）。
///
/// owner「AIに頼むは完全に独立して、提案とか、旅行プランの作成などの多岐にわたって活躍して欲しい」「AIに頼むを押して別画面になるのはどう？」
/// （2026-11-21）。探すの欄から切り離し、上の帯の「✦ AI に頼む」（`AskEntryButton`）か、探すの結果の上の1行から、全画面で開く。
///
/// - 上: 閉じる、題「✦ AI に頼む」、残りの回数（頼んで分かってから）
/// - 中: 会話（`AskThreadView` をそのまま使う。答えの案A、断り、使い切った帯、圏外）。何も頼んでいない間は例の札と、前に頼んだこと
/// - 下: 欄と送信のボタン（#662 の決まり: AI を呼ぶのは送信のボタンだけ。途中の字では送らない。キーボードのキーは「完了」）
/// - 旅行プランを作る頼み（`AskQuery.intent.plan`）は旅行プランの AI へ。回数は旅行プランの AI の枠。
///   2026-11-21 判断（版3「流れ」）: 行き先と日数が字から読めたら、確かめのシートを出さずに作り始め、答えの流れとして会話に出す。
///   読めないときだけ、旅行プランの AI のシート（`TripAIAskSheet`）で足りない札を選んでもらう
/// - 回数の上限、サーバーで数える仕組み、断り、見張りは `AskEngine` のまま（変えない）
struct AskScreen: View {
    /// 探すの結果の上の1行から来たときの字（欄に入れるだけ。送るのは送信のボタン）
    var prefill: String?
    var onClose: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore

    @StateObject private var engine = AskEngine()
    @StateObject private var location = CurrentLocation()
    /// 答えの「みんなの写真」に使う公開の写真（探すと同じ読み方を使い回す）
    @StateObject private var library = SearchViewModel()
    @State private var officialSpots: [OfficialSpot] = []
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var task: Task<Void, Never>?
    /// 旅行プランを作る頼みのとき、旅行プランの AI のシートに渡す頼み（`AskPlanFlow`）
    @State private var planAsk: TripAIAsk?
    /// 前に頼んだこと（端末の控え・`AskHistoryStore`）
    @State private var history: [AskHistoryRow] = []
    /// 会話の中で作っている旅行プラン（旅行プランの AI の仕事）と、その頼み
    @State private var planJob: TripAIJobs.Job?
    @State private var planQuestion: String?
    /// 旅行プランの AI の残りの回数（流れの答えのあと、上の1行に出す）
    @State private var planUsageLine: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let line = usageLine {
                    Text(line)
                        .font(JPFont.caption.monospacedDigit())
                        .foregroundStyle(WebTheme.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("ask.usage")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: JPSpace.m) {
                        if engine.isActive {
                            AskThreadView(engine: engine, officialSpots: officialSpots, photos: library.everything,
                                          photosKnown: library.hasLoaded,
                                          onFollowUp: { text in send(text) },
                                          onRelax: { exchange in relax(exchange) },
                                          inScreen: true,
                                          onFill: { text in
                                              // 次に頼めること: 欄に入れるだけ（送るのは送信のボタン・AI は呼ばない）
                                              draft = text
                                              focused = true
                                          })
                        } else {
                            starters
                        }
                    }
                    .padding(.top, JPSpace.xs)
                    .padding(.bottom, JPSpace.l)
                }
                .scrollDismissesKeyboard(.interactively)
                composer
            }
            .background(WebTheme.background)
            .navigationTitle(AskEntry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton(action: close)
                        .accessibilityIdentifier("ask.close")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .foregroundStyle(WebTheme.accent)
                            .accessibilityHidden(true)
                        Text(AskEntry.title)
                            .font(JPFont.headline)
                            .foregroundStyle(WebTheme.text)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .modifier(AskPlanFlow(ask: $planAsk, index: officialSpots, placeChoices: placeChoices))
            .background {
                if let planJob { AskPlanJobWatch(job: planJob) { settle(planJob, $0) } }
            }
        }
        .task { await load() }
        .onAppear {
            if let prefill, draft.isEmpty { draft = AskQuery.clipped(prefill) }
            history = AskHistoryRow.rows(AskHistoryStore().all(userId: auth.userId))
        }
        .onChange(of: auth.userId) { _, _ in
            task?.cancel()
            stopWatchingPlan()
            engine.reset()
            history = AskHistoryRow.rows(AskHistoryStore().all(userId: auth.userId))
        }
    }

    // MARK: - 何も頼んでいない間（例の札と、前に頼んだこと）

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AskEntry.startersLead)
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(AskEntry.starters(month: Calendar(identifier: .gregorian).component(.month, from: Date()))) { s in
                // 押すと欄に入るだけ（送るのは送信のボタン・押すまで AI は呼ばない）
                Button {
                    draft = s.text
                    focused = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.kind)
                            .jpEyebrow()
                            .foregroundStyle(WebTheme.accent)
                        Text(s.text)
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.starter")
            }
            if !history.isEmpty {
                JPEyebrowLine(L("前に頼んだこと", "Earlier"))
                    .padding(.top, JPSpace.s)
                VStack(spacing: 0) {
                    ForEach(history) { row in
                        Button { showSaved(row) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .foregroundStyle(WebTheme.text3)
                                    .accessibilityHidden(true)
                                Text(row.question)
                                    .font(JPFont.body)
                                    .foregroundStyle(WebTheme.text2)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ask.history")
                        JPCardDivider()
                    }
                }
            }
        }
        .padding(.horizontal, JPSpace.gutter)
    }

    // MARK: - 下の欄と送信のボタン

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                JPTextField(AskEntry.fieldPrompt, text: $draft)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    // 2026-11-21 判断（#662 の決まり）: キーボードのキーでは送らない（「完了」で閉じるだけ）
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .disabled(engine.pending != nil)
                    .accessibilityLabel(AskEntry.fieldPrompt)
                    .accessibilityIdentifier("ask.field")
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AskSendButton(enabled: AskEntry.sendEnabled(draft) && engine.pending == nil) { send(draft) }
                        .accessibilityIdentifier("ask.send")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(minHeight: 46)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            if AskEntry.showsKeepTyping(draft) {
                Text(AskQuery.keepTypingLine)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityIdentifier("ask.keepTyping")
            }
            Text(AskText.disclaimer)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(WebTheme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    // MARK: - 頼む

    /// 送信のボタン（と答えの下の言い替え）。旅行プランを作る頼みは旅行プランの AI へ、それ以外は AI に頼む
    private func send(_ raw: String) {
        let text = AskQuery.clipped(raw)
        guard AskEntry.sendEnabled(text), engine.pending == nil else { return }
        focused = false
        draft = ""
        switch AskEntry.route(text) {
        case .tripPlan:
            let ask = TripAIAsk.reading(text, spots: officialSpots)
            if ask.isComplete, let owner = auth.userId, planJob == nil {
                // 2026-11-21 判断（版3「流れ」、確かめのダイアログを足さない）: 行き先と日数が読めたら、すぐ作り始めて会話に流れの骨格を出す。
                // 回数は旅行プランの AI の枠（`TripAIRunner` が取る）。画面を閉じても作り続け、できたら上の帯で知らせる
                guard let question = engine.beginPlan(text) else { return }
                let backend = TripAIJobs.Backend.live(environment: environment, auth: auth, owner: owner, index: officialSpots,
                                                      wishlist: wishlist.spotIds, connectivity: connectivity)
                let job = TripAIJobs.shared.start(ask, owner: owner, usage: nil, backend: backend)
                TripAIJobs.shared.watching = job.id
                planQuestion = question
                planJob = job
            } else {
                // 行き先か日数が読めない: 旅行プランの AI の頼みの札（行き先、日数、好み）に読み替えて開く。回数は「この内容で作る」で
                planAsk = ask
            }
        case .ask:
            let backend = backend
            if engine.isActive {
                task = Task { await engine.followUp(text, backend: backend) }
            } else {
                task?.cancel()
                task = Task { await engine.start(text, backend: backend) }
            }
        }
    }

    private func relax(_ exchange: AskExchange) {
        let backend = backend
        task = Task { await engine.relax(exchange, backend: backend) }
    }

    /// 前に頼んだことを見せる（端末の控えから出すだけ。AI は呼ばない、回数も使わない）
    private func showSaved(_ row: AskHistoryRow) {
        let backend = backend
        task?.cancel()
        task = Task { await engine.showSaved(row.thread, backend: backend) }
    }

    private func close() {
        task?.cancel()
        stopWatchingPlan()
        onClose()
    }

    /// 上の1行（残りの回数）。旅行プランの流れの答えのあとは、旅行プランの AI の残り
    private var usageLine: String? {
        if engine.thread.last?.answer.kind == .plan || engine.pendingKind == .plan, let planUsageLine { return planUsageLine }
        return engine.usage?.remainingLine
    }

    /// 旅行プランの AI の仕事が終わった（保存まで）か、作れなかった
    private func settle(_ job: TripAIJobs.Job, _ state: TripAIJobs.State) {
        guard let question = planQuestion, planJob?.id == job.id else { return }
        switch state {
        case .building:
            return
        case .saved(let planId):
            if let result = job.result {
                engine.finishPlan(question, result: result, planId: planId, onDevice: job.runner.onDevice, userId: auth.userId)
            } else {
                engine.failPlan(question, line: TripAIJobText.failureLine(.noCandidates, title: job.title), userId: auth.userId)
            }
            TripAIJobs.shared.markSeen(planId)
        case .failed(let failure):
            engine.failPlan(question, line: TripAIJobText.failureLine(failure, title: job.title), userId: auth.userId)
        }
        if let usage = job.runner.usage {
            planUsageLine = TripAIText.remainingLine(remaining: usage.remaining, resetsOn: usage.resetsOn)
        }
        if TripAIJobs.shared.watching == job.id { TripAIJobs.shared.watching = nil }
        planJob = nil
        planQuestion = nil
    }

    /// 画面を閉じた・人が替わった: 待つのをやめる（仕事は旅行プランの AI が続け、できたら上の帯で知らせる）
    private func stopWatchingPlan() {
        if let job = planJob, TripAIJobs.shared.watching == job.id { TripAIJobs.shared.watching = nil }
        planJob = nil
        planQuestion = nil
        engine.cancelPlan()
    }

    /// 観光スポットの索引と公開の写真（探すと同じ読み方。控えがあれば通信しない）
    private func load() async {
        if officialSpots.isEmpty,
           let result = await SpotPrefectureIndex.loaded({ try await environment.spots.fetchIndex(force: false) }),
           let spots = result.spots {
            officialSpots = spots
        }
        if !library.hasLoaded {
            await library.reloadPhotos(environment: environment)
            library.applyHidden(hidden.snapshot)
        }
    }

    private var placeChoices: [(label: String, prefecture: String)] {
        AskPlanFlow.placeChoices(engine: engine)
    }

    /// 答えの外の口（台帳、公開の写真、行きたい場所、旅行プラン、現在地、回数、AI）。2026-11-21 に探すの画面から移した
    private var backend: AskEngine.Backend {
        let env = environment, conn = connectivity, authStore = auth, wish = wishlist
        let spots = officialSpots, photos = library.everything, here = location
        return AskEngine.Backend(
            signedIn: { authStore.userId != nil },
            offline: { conn.isOffline },
            deviceAI: { AskFixture.isOn ? AskFixture.deviceAI : OnDeviceAI.isAvailable },
            library: { needsLocation in
                let coords = needsLocation ? await AskScreen.locate(here) : nil
                let wished = spots.filter { wish.contains(SavedSpotKey.official($0.slug)) }
                // 旅行プランは端末の AI の道具だけが読む（サーバーの AI には送らない）。見本の口では端末の AI に問い合わせない（札 #662）
                var trips: [TripPlan] = []
                if !AskFixture.isOn, authStore.userId != nil, !conn.isOffline, OnDeviceAI.isAvailable {
                    trips = (try? await env.trips.list()) ?? []
                }
                return AskLibrary(spots: spots, photos: photos, wishlist: wished, trips: trips, here: coords)
            },
            reserve: { kind, via in try await env.ask.reserve(kind: kind, via: via) },
            serverAsk: { text, turns, sources in try await env.ask.ask(text: text, history: turns, sources: sources) },
            deviceAsk: { text, history, library in
                if AskFixture.isOn { return AskFixture.deviceResult(text, library: library) }
                return await AskDevice.live(text, history: history, library: library)
            },
            details: { needed in await env.spots.withDetails(needed, for: needed) },
            userId: { authStore.userId }
        )
    }

    /// 現在地を1回取る（許可を聞いている間は待つ。断られた・取れないときは nil で、近さでは絞らない）
    @MainActor
    static func locate(_ location: CurrentLocation) async -> Photo.Coords? {
        if case .located(let lat, let lng) = location.state { return .init(lat: lat, lng: lng) }
        location.locate(requestedByUser: true)
        for _ in 0..<75 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return nil }
            switch location.state {
            case .located(let lat, let lng): return .init(lat: lat, lng: lng)
            case .denied, .failed: return nil
            default: continue
            }
        }
        return nil
    }
}

/// 旅行プランの AI の仕事の様子を見る（できた、作れなかった）。見えない部品
struct AskPlanJobWatch: View {
    @ObservedObject var job: TripAIJobs.Job
    let onChange: (TripAIJobs.State) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: job.state, initial: true) { _, state in onChange(state) }
            .accessibilityHidden(true)
    }
}

/// 前に頼んだことの1行（`AskHistoryStore` の控え。新しい日から）
struct AskHistoryRow: Identifiable, Equatable {
    let id: String
    let question: String
    let day: String
    let thread: [AskExchange]

    /// 控えから行を作る（新しい日から、8件まで）
    static func rows(_ map: [String: AskHistoryStore.Entry], limit: Int = 8) -> [AskHistoryRow] {
        map.compactMap { key, entry -> AskHistoryRow? in
            guard let first = entry.thread.first else { return nil }
            return AskHistoryRow(id: key, question: first.question, day: entry.day, thread: entry.thread)
        }
        .sorted { $0.day == $1.day ? $0.question < $1.question : $0.day > $1.day }
        .prefix(limit)
        .map { $0 }
    }
}

/// 旅行プランを作る頼みのシートと、組み上げの画面（`AskThreadView` の「旅行プランにする」と AI の画面で使い回す・札 #675）
struct AskPlanFlow: ViewModifier {
    @Binding var ask: TripAIAsk?
    let index: [OfficialSpot]
    let placeChoices: [(label: String, prefecture: String)]

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var connectivity: Connectivity
    @State private var job: TripAIJobs.Job?
    @State private var showJob = false
    @StateObject private var plans = TripPlansModel()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })) {
                if let ask {
                    TripAIAskSheet(ask: ask, placeChoices: placeChoices, onDevice: TripAIDevice.isAvailable,
                                   start: startAfterSheet, index: index)
                }
            }
            .navigationDestination(isPresented: $showJob) {
                if let job { TripAIBuildingView(job: job, plans: plans) }
            }
    }

    /// シートが閉じ切ってから日程の画面を積む（閉じている途中に積むと捨てられる・`TripPlansView` と同じ）
    private func startAfterSheet(_ ask: TripAIAsk) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let owner = auth.userId else { return }
            let backend = TripAIJobs.Backend.live(environment: environment, auth: auth, owner: owner, index: index,
                                                  wishlist: wishlist.spotIds, connectivity: connectivity)
            job = TripAIJobs.shared.start(ask, owner: owner, usage: nil, backend: backend)
            showJob = true
        }
    }

    /// 行き先の選択肢（答えに出た観光スポットの県から6つまで）
    @MainActor
    static func placeChoices(engine: AskEngine) -> [(label: String, prefecture: String)] {
        var prefs: [String] = []
        for id in engine.thread.flatMap(\.answer.spotIds) {
            if let p = engine.spotsById[id]?.region?.prefecture, !prefs.contains(p), prefs.count < 6 { prefs.append(p) }
        }
        return prefs.map { (TripAIDestination.prefectureShort($0), $0) }
    }
}
