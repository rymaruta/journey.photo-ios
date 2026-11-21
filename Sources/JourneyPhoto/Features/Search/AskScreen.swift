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
/// - 2026-11-21 判断（札 #678）: 会話は画面の外（`RootView`・アプリが動いている間）の `AskEngine` が持ち、端末の控え
///   （`AskHistoryStore` の会話）にも残す。閉じて開き直しても、アプリを落としても、最後の会話の続きが出る（AI は呼ばない）。
///   上の帯の「新しく頼む」で何も頼んでいない画面へ（無料は今の会話を消す・Pro は残して「前の会話」から選べる・`AskConversationRule`）
struct AskScreen: View {
    /// 会話（`RootView` が持つ。閉じても手放さない）
    @ObservedObject var engine: AskEngine
    /// 探すの結果の上の1行から来たときの字（欄に入れるだけ。送るのは送信のボタン）
    var prefill: String?
    var onClose: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var hidden: ModerationStore

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
    @State private var conversations = AskHistoryStore.Conversations()
    /// 自分のプロフィールの Pro（読めていなければ nil・`AskConversationRule.plan`）
    @State private var profilePro: Bool?
    @State private var confirmNew = false
    @State private var showConversations = false
    @State private var showPaywall = false
    @State private var confirmClearConversations = false
    /// 会話の中で作っている旅行プラン（旅行プランの AI の仕事）と、その頼み
    @State private var planJob: TripAIJobs.Job?
    @State private var planQuestion: String?
    /// 旅行プランの AI の残りの回数（流れの答えのあと、上の1行に出す）
    @State private var planUsageLine: String?
    /// ログインしていないときの旅行プランの頼み（今のログインの画面で案内する）
    @State private var signIn: SignInRequest?

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
                // 2026-11-21 判断（回 1675 の絵）: 会話が無いときは置かない（空の項目でもガラスの丸が残った）
                if engine.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            if !listed.isEmpty {
                                Button { showConversations = true } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(WebTheme.text)
                                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(AskEntry.conversationsTitle)
                                .accessibilityIdentifier("ask.conversations")
                            }
                            Button(action: newConversation) {
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(engine.pending == nil ? WebTheme.text : WebTheme.text3)
                                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(engine.pending != nil)
                            .accessibilityLabel(AskEntry.newLabel)
                            .accessibilityIdentifier("ask.new")
                        }
                    }
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
            .sheet(item: $signIn) { request in
                SignInSheet(reason: request.reason, entry: request.entry)
            }
            // 無料の「新しく頼む」: 今の会話が消える（取り消せない）ので1回だけ聞く。Pro の案内を並べる（値段は書かない）
            .confirmationDialog(AskEntry.freeNewConfirm, isPresented: $confirmNew, titleVisibility: .visible) {
                Button(AskEntry.newLabel, role: .destructive) { beginNew() }
                Button(AskEntry.proKeepsConversations) { showPaywall = true }
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showConversations) { conversationsSheet }
            // 何も頼んでいない画面の「すべて消す」（一覧のシートの中は、シートの上で聞く）
            .confirmationDialog(clearConfirmTitle, isPresented: Binding(get: { confirmClearConversations && !showConversations },
                                                                        set: { confirmClearConversations = $0 }),
                                titleVisibility: .visible) {
                Button(L("すべて消す", "Clear all"), role: .destructive) { clearConversations() }
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showPaywall, onDismiss: { Task { await loadPro() } }) {
                PaywallView()
            }
        }
        // 2026-11-21 判断（確かめ役の指摘）: 全画面の AI の画面の上では、アプリの下の知らせ（`RootView`）が裏に隠れる。
        // ここにも置く（`TripCreateView` と同じ）。下の欄と「AI の答えは間違うことがあります」の上に出す
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, AskScreen.toastBottomPadding)
        }
        .task {
            await load()
            // 控えから戻した会話の札の中身（観光スポットと写真）を、索引を読んでから重ねる（AI は呼ばない）
            let backend = backend
            await engine.refill(backend: backend)
        }
        .task(id: auth.userId) { await loadPro() }
        .onAppear {
            AskScreen.freshFixtureConversations(engine: engine, userId: auth.userId)
            // 最後の会話の続き（札 #678）。控えから消えていたら外し、何も出していなければ控えの今の会話を戻す
            engine.resume(userId: auth.userId)
            // 探すの1行から来た字（回 1658: 渡した字が古い値で届かなかったので、道しるべ（`TabRouter`）からも受け取る）
            let carried = TabRouter.shared.takePendingAskText()
            let left = engine.takeCarriedDraft()
            if let text = prefill ?? carried ?? left, draft.isEmpty { draft = AskQuery.clipped(text) }
            reloadConversations()
        }
        .onChange(of: engine.thread.count) { _, _ in reloadConversations() }
        .onChange(of: auth.userId) { _, _ in
            task?.cancel()
            stopWatchingPlan()
            engine.reset()
            profilePro = nil
            reloadConversations()
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
            if !listed.isEmpty {
                conversationsHeader
                    .padding(.top, JPSpace.s)
                conversationRows
            } else if knownFree, auth.userId != nil {
                // 無料: 一覧は出さず、Pro で分けて残せることを1行だけ（しつこくしない・値段は書かない）
                Button { showPaywall = true } label: {
                    Text(AskEntry.proConversationsLine)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.accent)
                        .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, JPSpace.xs)
                .accessibilityIdentifier("ask.proConversations")
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
        // 2026-11-21 判断（確かめ役の指摘）: 旅行プランは保存するのでログインが要る。ログインしていなければ、シートを開いて
        // 「この内容で作る」で黙って止まる前に、今のログインの画面で案内する（字は欄に残す）
        if AskEntry.route(text) == .tripPlan,
           let request = SignInPrompt.request(AskEntry.planSignIn, signUpReason: AskEntry.planSignUp,
                                              userId: auth.userId, isResolving: auth.isResolving) {
            focused = false
            signIn = request
            return
        }
        focused = false
        draft = ""
        switch AskEntry.route(text) {
        case .tripPlan:
            let ask = TripAIAsk.reading(text, spots: officialSpots)
            if ask.isComplete, let owner = auth.userId, planJob == nil {
                // 2026-11-21 判断（版3「流れ」、確かめのダイアログを足さない）: 行き先と日数が読めたら、すぐ作り始めて会話に流れの骨格を出す。
                // 回数は旅行プランの AI の枠（`TripAIRunner` が取る）。画面を閉じても作り続け、できたら上の帯で知らせる
                guard let question = engine.beginPlan(text, userId: owner) else { return }
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

    // MARK: - 会話（札 #678）

    /// 前の会話の行（何も頼んでいない画面と、上の帯の一覧で使い回す）
    private var conversationRows: some View {
        VStack(spacing: 0) {
            ForEach(listed) { conversation in
                Button { openConversation(conversation) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .foregroundStyle(WebTheme.text3)
                            .accessibilityHidden(true)
                        Text(conversation.question)
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.conversation")
                // 長押しで1つ消す（Pro の前の会話・札 #678。探すの「すべて消す」では消えない）
                .contextMenu {
                    Button(role: .destructive) { deleteConversation(conversation) } label: {
                        Label(L("削除", "Delete"), systemImage: "trash")
                    }
                }
                JPCardDivider()
            }
        }
    }

    /// 前の会話の見出し（眉ラベルと「すべて消す」）
    private var conversationsHeader: some View {
        HStack(alignment: .center) {
            JPEyebrowLine(AskEntry.conversationsTitle)
            clearConversationsButton
        }
    }

    private var clearConversationsButton: some View {
        Button { confirmClearConversations = true } label: {
            Text(L("すべて消す", "Clear all"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text3)
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("前の会話をすべて消す", "Clear all earlier conversations"))
        .accessibilityIdentifier("ask.conversations.clearAll")
    }

    private func deleteConversation(_ conversation: AskHistoryStore.Conversation) {
        AskHistoryStore().removeConversation(conversation.id, userId: auth.userId)
        reloadConversations()
    }

    private func clearConversations() {
        AskHistoryStore().removeConversations(keeping: engine.conversationId, userId: auth.userId)
        reloadConversations()
        showConversations = false
    }

    private var conversationsSheet: some View {
        NavigationStack {
            // 左へ払って1つ消せるよう List にする（行の形は `conversationRows` と同じ）
            List {
                ForEach(listed) { conversation in
                    Button { openConversation(conversation) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundStyle(WebTheme.text3)
                                .accessibilityHidden(true)
                            Text(conversation.question)
                                .font(JPFont.body)
                                .foregroundStyle(WebTheme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ask.conversation")
                    .listRowBackground(WebTheme.background)
                    .listRowSeparatorTint(WebTheme.hairline)
                    .swipeActions(allowsFullSwipe: true) {
                        Button(role: .destructive) { deleteConversation(conversation) } label: {
                            Label(L("削除", "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .webScreen()
            .navigationTitle(AskEntry.conversationsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton()
                }
                ToolbarItem(placement: .topBarTrailing) { clearConversationsButton }
            }
            .confirmationDialog(clearConfirmTitle, isPresented: $confirmClearConversations, titleVisibility: .visible) {
                Button(L("すべて消す", "Clear all"), role: .destructive) { clearConversations() }
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var clearConfirmTitle: String { L("前の会話をすべて消しますか", "Clear all earlier conversations?") }

    private var plan: AskConversationRule.Plan { AskConversationRule.plan(usage: engine.usage, profile: profilePro) }
    /// 無料と分かっているとき（読めていない間は Pro の案内を出さない）
    private var knownFree: Bool { plan == .free }

    private var listed: [AskHistoryStore.Conversation] { AskConversationRule.listed(conversations, plan: plan) }

    private func reloadConversations() {
        conversations = AskHistoryStore().conversations(userId: auth.userId)
    }

    /// 前の会話を開く（端末の控えから出すだけ。AI は呼ばない、回数も使わない）。続けて聞くと、その会話の続きになる
    private func openConversation(_ conversation: AskHistoryStore.Conversation) {
        let backend = backend
        task?.cancel()
        stopWatchingPlan()
        showConversations = false
        draft = ""
        task = Task {
            await engine.open(conversation, backend: backend)
            reloadConversations()
        }
    }

    /// 上の帯の「新しく頼む」。無料で会話があるときだけ確かめる
    private func newConversation() {
        if AskConversationRule.confirmsNew(plan: plan, hasConversation: engine.conversationId != nil) {
            confirmNew = true
        } else {
            beginNew()
        }
    }

    private func beginNew() {
        task?.cancel()
        stopWatchingPlan()
        engine.startNew(keep: AskConversationRule.keepsOnNew(plan: plan), userId: auth.userId)
        draft = ""
        reloadConversations()
    }

    /// 自分のプロフィールの Pro を読む（手元の控えを先に。読めなければ nil のまま）
    private func loadPro() async {
        if let cached = MyProfileCache.shared.profile(for: auth.userId) { profilePro = cached.isPro }
        #if DEBUG
        // UI テストの見本の Pro（`-JPPreviewPro`・入っている本人だけ。プロフィールの読み込みを待たない）
        if PreviewSession.isPro, auth.userId == PreviewSession.userId { profilePro = true }
        #endif
        guard auth.userId != nil else { profilePro = nil; return }
        let profile = try? await environment.profiles.myProfile()
        if let profile { profilePro = profile.isPro }
    }

    /// UI テストの見本（`-JPAskFixture`）では、起動して最初に開いたとき前の試験の会話を持ち越さない
    @MainActor private static var fixtureConversationsCleared = false
    @MainActor
    static func freshFixtureConversations(engine: AskEngine, userId: String?) {
        guard AskFixture.isOn, !fixtureConversationsCleared else { return }
        fixtureConversationsCleared = true
        AskHistoryStore().forgetConversations(userId: userId)
        engine.reset()
    }

    /// 閉じる。答えを待っている途中なら取り消し、頼みの字は開き直したとき欄に戻す（打ちかけの字も）。会話は残す
    private func close() {
        let interrupted = engine.interrupt()
        task?.cancel()
        stopWatchingPlan()
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 打ち始めていた字があればそれを優先して残す。無ければ取り消した頼み
        engine.carriedDraft = typed.isEmpty ? interrupted : draft
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

    /// 知らせを下の欄（高さ 46、上下の余白、断りの1行）の上に出す
    static let toastBottomPadding: CGFloat = 96

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

/// 会話の残し方の決まり（札 #678・2026-11-21 owner「AI との会話で別スレッドにするには月額500円の有料プラン（Pro）なら使えるようにしたい」）
///
/// - 無料: 会話は1本。閉じて開き直すと続きが出る。「新しく頼む」は確かめてから今の会話を消す。前の会話の一覧は出さない
/// - Pro: 「新しく頼む」で今の会話は残り、別の会話を始める。前の会話（`AskHistoryStore.limit` 件まで）から続きを選べる
/// - Pro が切れたら、一覧は出さず今の会話だけを見せる（控えは消さない。また Pro になれば戻る）
enum AskConversationRule {

    /// Pro か、無料か、まだ分からないか
    enum Plan: Equatable { case pro, free, unknown }

    /// サーバーが数えた回数の返事（`AskUsage.tier`）と、自分のプロフィール（`UserProfile.isPro`）。**どちらかが Pro なら Pro**
    /// （2026-11-21 確かめ役の指摘: Pro を買って戻っても、前に読んだ無料の回数の返事が勝って無料の扱いになっていた）。
    /// どちらも読めていなければ「分からない」
    static func plan(usage: AskUsage?, profile: Bool?) -> Plan {
        if usage?.isPro == true || profile == true { return .pro }
        if usage != nil || profile == false { return .free }
        return .unknown
    }

    /// 一覧に出す前の会話（Pro だけ。今の会話は除く）
    static func listed(_ list: AskHistoryStore.Conversations, plan: Plan) -> [AskHistoryStore.Conversation] {
        guard plan == .pro else { return [] }
        return list.items.filter { $0.id != list.currentId }
    }

    /// 「新しく頼む」で今の会話を残すか。**分からない間は残す**（Pro の人の会話を消さない側に倒す）
    static func keepsOnNew(plan: Plan) -> Bool { plan != .free }

    /// 「新しく頼む」の前に確かめるか（無料と分かっていて、消える会話があるときだけ）
    static func confirmsNew(plan: Plan, hasConversation: Bool) -> Bool { plan == .free && hasConversation }
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
