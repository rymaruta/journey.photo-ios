import Foundation
import Combine

/// 「AI に頼む」の手順（札 #652・案 A）。画面は持たない（答えの画面は `AskThreadView`）。
///
/// 1問の流れ（Artifact「AI に頼む」8版、2026-11-20 owner 承認）:
/// 1. **先に断る**（`AskGuard.declinesBeforeAsking`）。AI を呼ばず、回数も使わない
/// 2. 同じ日の同じ頼みは、端末の控え（`AskHistoryStore`）の答えを出す。回数を使わない
/// 3. 言葉の表で読み（`SearchSentence.readByTable`）、頼みの中身（`AskQuery.intent`）と選ぶ条件を作る
/// 4. **サーバーで1回取る**（`AskService.reserve`）。端末の AI は答えを出す直前に取る（答えなかった回は数えない・2026-11-20 判断）。
///    サーバーの AI は呼ぶ前に取る。ログインしていない、圏外、取れない（429）ときは AI の答えを出さない
/// 5. 端末の AI が使える iPhone → 端末の AI（道具で台帳などを引く・`AskDevice`）。
///    使えない iPhone → `serverAllowed`（Pro で止めに達していない）ならサーバーの AI、それ以外は言葉の表
/// 6. 答えは見張り（`AskGuard.screened`）を通してから出す
///
/// どの道で失敗しても、言葉の表と台帳で答えを出す（行き止まりにしない）。
@MainActor
final class AskEngine: ObservableObject {

    /// 外の口（試験は差し替える）
    struct Backend {
        var signedIn: () -> Bool
        var offline: () -> Bool
        /// この iPhone で端末の AI が使えるか（`OnDeviceAI.isAvailable`）
        var deviceAI: () -> Bool
        /// 引いてよいものの棚を作る（`needsLocation` なら現在地も取る）
        var library: (_ needsLocation: Bool) async -> AskLibrary
        var reserve: (AskService.Kind, AskService.Via) async throws -> AskUsage
        var serverAsk: (String, [AskService.Turn], [OfficialSpot]) async throws -> AskService.ServerAnswer
        /// 端末の AI で答える。失敗、時間切れ、使えないときは nil
        var deviceAsk: (String, [AskExchange], AskLibrary) async -> AskDevice.Result?
        /// 札に出す観光スポットに、案内の文（詳細）を重ねる
        var details: ([OfficialSpot]) async -> [OfficialSpot]
        var userId: () -> String?
        /// サーバーの AI に送ってよいか（同意のシート・`AIServerConsent.request`。2026-11-22 判断・審査 5.1.2(i)）。
        /// 画面は `AIServerConsent.shared.request` を渡す。試験の既定は同意済み（送る口 `AskService.ask` も別に見張る）
        var serverConsent: () async -> Bool = { true }
        /// サーバーへ送りそうか（`AskServerNotice.shows` と同じ見立て）。無料と分かっている人には、回数を取る前に聞かない
        /// （サーバーが Pro だけと答えて送らないのに、同意を聞くことになる）
        var serverLikely: () -> Bool = { true }
        /// いま同意済みか（聞かずに読む・`AIServerConsent.acceptedNow`）。会話の中で「やめる」のあと設定でオンにした人に送るため
        var consentAccepted: () -> Bool = { false }
    }

    @Published private(set) var thread: [AskExchange] = []
    /// 答えを用意している問い（読み込み中の骨格を出す）
    @Published private(set) var pending: String?
    /// 用意している答えの種類（字から分かるとき。押した瞬間から形の骨格を出す・2026-11-21 判断 札 #675）。分からなければ nil
    @Published private(set) var pendingKind: AskAnswerKind?
    /// いま届いた答え（少しずつ出す: 頭の文が先、札と一手はあと）。控えから出した答えは入れない
    @Published private(set) var freshId: String?
    @Published private(set) var usage: AskUsage?
    /// 札に出す観光スポット（`spotId` → 行。詳細を重ねたもの）
    @Published private(set) var spotsById: [String: OfficialSpot] = [:]
    /// みんなの写真（`Photo.id` → 写真）
    @Published private(set) var photosById: [String: Photo] = [:]

    private let history: AskHistoryStore
    /// いまの会話の控えの鍵（`AskHistoryStore.Conversation.id`）。最初の答えを出したときに作る（札 #678）
    private(set) var conversationId: String?
    /// 控えから戻した会話の札の中身（観光スポットと写真）を、索引を読んでから重ねる必要があるか（`refill`）
    private(set) var needsRefill = false
    /// 閉じたときに欄に残っていた字か、答えを待っている途中で取り消した頼み（開き直したら欄に戻す・札 #678）
    var carriedDraft: String?
    /// 利用者が打った頼みで、いま答えを用意しているもの（取り消したら欄に戻す。言い替え・控えから出す回は入れない）
    private var askingQuestion: String?
    /// 頼み始めたときの人と、そのときの控えを消した回の数（札 #678 の確かめ役の指摘）。答えが届いたとき、人が替わっていたり
    /// 待っている間にログアウト・退会で控えを消していたら、端末の控えに書かない（前の人の会話を別の鍵や消したあとに残さない）
    private var askOwner: String?
    private var ownerGeneration = 0
    /// 答えを出したあとに案内の文（詳細）を重ねる観光スポット（`fill` が積み、`loadPendingDetails` が読む）
    private var pendingDetails: [OfficialSpot] = []
    /// この会話でサーバーの AI への送信を「やめる」と答えた（2026-11-22 判断）。会話の間は聞き直さず、言葉の表で答える。
    /// 新しい会話（`clearThread`）で忘れる。同意は設定からもできる
    private(set) var consentDeclined = false

    /// いまの段（UI テストのときだけ見える要素 `search.ask.stage` に出す・2026-11-20 run 1612 の帯の試験の調べ）。
    /// 段の名前と、頼んでからの経過（ms）を並べる
    @Published private(set) var stageLog: [String] = []
    /// 札に出す観光スポットの案内の文（詳細）を読んでいる最中か（札の並びは、読み終えてから1枚目の位置をそろえる・回 1641 の調べ）
    @Published private(set) var detailsLoading = false
    private var stageStarted = Date()

    func mark(_ stage: String) {
        if stage == "start" { stageStarted = Date(); stageLog = [] }
        let ms = Int(Date().timeIntervalSince(stageStarted) * 1000)
        stageLog.append("\(stage)@\(ms)")
        if stageLog.count > 24 { stageLog.removeFirst(stageLog.count - 24) }
    }

    init(history: AskHistoryStore = AskHistoryStore()) {
        self.history = history
    }

    var isActive: Bool { !thread.isEmpty || pending != nil }

    /// 会話を閉じる。**残りの回数と札の中身も手放す**（人が替わったときに前の人の物を残さない）
    func reset() {
        clearThread()
        usage = nil
        pendingDetails = []
        spotsById = [:]
        photosById = [:]
        carriedDraft = nil
    }

    /// 会話を画面から外す（残りの回数は持ったまま）
    private func clearThread() {
        thread = []
        pending = nil
        pendingKind = nil
        freshId = nil
        conversationId = nil
        needsRefill = false
        askingQuestion = nil
        askOwner = nil
        consentDeclined = false
    }

    // MARK: - 会話を残す（札 #678・2026-11-21 判断）

    /// この人の頼みとして控えに書いてよいかを覚える（頼み始めたとき）
    private func claimOwner(_ userId: String?) {
        askOwner = userId
        ownerGeneration = AskHistoryStore.generation(userId)
    }

    /// 端末の控えに書いてよいか: ログインしていて、頼み始めたときと同じ人で、その間に控えを消していない
    private func mayPersist(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty, userId == askOwner else { return false }
        return AskHistoryStore.generation(userId) == ownerGeneration
    }

    /// AI に渡す直前のやりとり: **今日のものだけ**（数日前の会話の続きを AI に渡さない。画面には残す）
    var contextThread: [AskExchange] {
        let today = AskHistoryStore.day(Date())
        return thread.filter { $0.askedAt.map { AskHistoryStore.day($0) == today } ?? false }
    }

    /// 画面を開いた: 端末の控えとそろえる。**AI は呼ばない、回数も使わない。**
    /// - 持っている会話が控えから消えていたら（「前の会話」の一覧で消した、ログアウト・退会）、画面からも外す
    /// - 何も出していなければ、控えの今の会話を戻す（アプリを落として開き直したとき）
    /// - ログインしていない間は控えに何も無い（画面の中だけで持つ）
    func resume(userId: String?) {
        guard userId?.isEmpty == false else { return }
        let list = history.conversations(userId: userId)
        if let id = conversationId, pending == nil, !list.items.contains(where: { $0.id == id }) {
            clearThread()
        }
        guard !isActive, let current = list.current else { return }
        restore(current, userId: userId)
    }

    /// 控えの会話を出す（札の中身は `refill` で重ねる）
    func restore(_ conversation: AskHistoryStore.Conversation, userId: String?) {
        clearThread()
        thread = conversation.thread
        conversationId = conversation.id
        needsRefill = true
        claimOwner(userId)
    }

    /// 戻した会話の札の中身（観光スポットと写真）を、索引と公開の写真から重ねる（通信は `backend.library` の控えだけ）
    func refill(backend: Backend) async {
        guard needsRefill else { return }
        let library = await backend.library(false)
        guard !Task.isCancelled else { return }
        remember(library: library, thread: thread)
        needsRefill = false
    }

    /// 前の会話を開いて、続きから話せるようにする（Pro・`AskConversationRule`）
    func open(_ conversation: AskHistoryStore.Conversation, backend: Backend) async {
        restore(conversation, userId: backend.userId())
        history.setCurrentConversation(conversation.id, userId: backend.userId())
        await refill(backend: backend)
    }

    /// 「新しく頼む」: 何も頼んでいない画面に戻す。`keep` が false（無料）なら今の会話を控えから消す
    func startNew(keep: Bool, userId: String?) {
        if let id = conversationId {
            if keep { history.setCurrentConversation(nil, userId: userId) } else { history.removeConversation(id, userId: userId) }
        } else {
            history.setCurrentConversation(nil, userId: userId)
        }
        clearThread()
    }

    /// 答えを待っている途中で閉じた: 待つのをやめる。利用者が打った頼みなら返す（開き直したら欄に戻す）。
    /// 2026-11-21 判断: 閉じたら取り消す（今までどおり）。端末の AI は答えを出す直前に数えるので、取り消した回は数えない
    func interrupt() -> String? {
        guard let question = pending else { return nil }
        let typed = question == askingQuestion ? question : nil
        pending = nil
        pendingKind = nil
        askingQuestion = nil
        return typed
    }

    /// 欄に戻す字を受け取る（受け取ったら消す）
    func takeCarriedDraft() -> String? {
        defer { carriedDraft = nil }
        return carriedDraft
    }

    private func keepConversation(userId: String?) {
        guard !thread.isEmpty, mayPersist(userId) else { return }
        let id = conversationId ?? UUID().uuidString
        conversationId = id
        history.saveConversation(id: id, thread: thread, userId: userId)
    }

    /// 新しく頼む前に、**すぐに**答えの形（読み込み中）にする。前の会話は閉じる。返すのは頼んだ文（空なら nil）。
    /// 画面は欄の字をこの文にそろえてから `start` を呼ぶ（字が替わったら答えを閉じる決まりと食い違わない）
    @discardableResult
    func prepare(_ raw: String) -> String? {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty else { return nil }
        thread = []
        conversationId = nil
        needsRefill = false
        pending = question
        askingQuestion = question
        pendingKind = AskAnswerKind.byWords(question)
        return question
    }

    /// 新しく頼む（前の会話は閉じる）。同じ日の同じ頼みは控えから出す（回数を使わない）
    func start(_ raw: String, backend: Backend) async {
        guard let question = prepare(raw) else { return }
        claimOwner(backend.userId())
        if let cached = history.today(question, userId: backend.userId()) {
            // 控えの札の中身（観光スポットと写真）を読み直して出す
            let library = await backend.library(false)
            guard !Task.isCancelled else { return }
            // 2026-11-22 判断（札 #684）: 今日同じ頼みで始めた会話が残っていれば（Pro が「新しく頼む」のあと同じ頼みをした）、
            // 新しい会話を作らずにそれを開く。前は毎回新しい id の会話を作り、「前の会話」に同じ会話が2つ並んだ
            let existing = Self.todaysConversation(startingWith: question,
                                                   in: history.conversations(userId: backend.userId()).items)
            let shown = existing?.thread ?? cached.map { var e = $0; e.askedAt = Date(); return e }
            remember(library: library, thread: shown)
            freshId = nil
            thread = shown
            if let existing { conversationId = existing.id }
            pending = nil
            askingQuestion = nil
            keepConversation(userId: backend.userId())
            return
        }
        await ask(question, backend: backend)
    }

    /// 答えの下の欄で続けて聞く（続きも1回と数える）
    func followUp(_ raw: String, backend: Backend) async {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty, !thread.isEmpty, pending == nil else { return }
        // 2026-11-21 判断（札 #678 の確かめ役の指摘）: 戻した会話から続けて聞くときも、同じ日の同じ頼みは控えの答えを出す
        // （回数を使わない。閉じて開き直すと会話の続きになるので、新しく頼む道を通らなくなった）
        if let cached = history.today(question, userId: backend.userId())?.first,
           RecentSearchesStore.normalized(cached.question) == RecentSearchesStore.normalized(question) {
            pending = question
            claimOwner(backend.userId())
            let library = await backend.library(false)
            guard !Task.isCancelled else { return }
            append(AskExchange(question: question, answer: cached.answer), library: library, backend: backend)
            freshId = nil
            return
        }
        await ask(question, backend: backend)
    }

    /// 空の答えの言い替え（条件を1つ外す）。**アプリが選び直すだけで AI は呼ばない・回数を使わない**
    func relax(_ exchange: AskExchange, backend: Backend) async {
        guard let phrase = exchange.answer.relaxedQuery, pending == nil else { return }
        pending = phrase
        pendingKind = .cards
        claimOwner(backend.userId())
        let library = await backend.library(false)
        let answer = await tableAnswer(phrase, library: library, backend: backend, note: nil, state: .answered)
        guard !Task.isCancelled else { return }
        append(AskExchange(question: phrase, answer: answer), library: library, backend: backend)
        await loadPendingDetails(backend: backend)
    }

    // MARK: - 旅行プランの流れ（札 #675 の答えの形・版3「流れ（今の旅行プランの AI の答えをこの形に）」）

    /// 旅行プランを作る頼みを、答えの流れとして待つ（流れの骨格を出す）。作るのは旅行プランの AI（`TripAIJobs`）で、
    /// **回数は旅行プランの AI の枠**（`TripAIRunner` が取る。ここでは数えない）。返すのは頼んだ文（待てないときは nil）
    @discardableResult
    func beginPlan(_ raw: String, userId: String? = nil) -> String? {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty, pending == nil else { return nil }
        claimOwner(userId)
        pending = question
        pendingKind = .plan
        mark("start")
        return question
    }

    /// 旅行プランの AI ができた（保存まで終わった）。頭の文、日ごとの観光スポット、保存したプランを答えにする。
    /// 理由の文は見張り（`AskGuard.screened`）を通し、台帳に無い場所らしい名前があれば決まり文に替える
    func finishPlan(_ question: String, result: TripAIResult, planId: String?, onDevice: Bool, userId: String?,
                    askedServer: Bool = false) {
        guard pending == question else { return }
        // 2026-11-22 判断: サーバーへ送った回は、断りや AI なしの答えでも「送った」を残す（下の欄の知らせを出し続ける）
        var refusal = AskAnswer.refused(care: false)
        if askedServer { refusal.serverSent = true }
        if result.refused {
            appendPlain(AskExchange(question: question, answer: refusal), userId: userId)
            return
        }
        let screened = AskGuard.screened(result.reason)
        if screened.refused {
            appendPlain(AskExchange(question: question, answer: refusal), userId: userId)
            return
        }
        let usedAI = result.mode == .ai
        let days = result.days.filter { !$0.isEmpty }
        let spots = days.flatMap { $0 }
        for s in spots where spotsById[s.spotId] == nil { spotsById[s.spotId] = s }
        var answer = AskAnswer(engine: usedAI ? (onDevice ? .device : .server) : .table)
        answer.kind = .plan
        let lead = AskPlanFlowText.lead(reason: screened.text, usedAI: usedAI, days: days.count)
        answer.text = AskLeadCheck.hasUnknownPlace(lead, shown: spots, ledger: spots)
            ? AskPlanFlowText.lead(reason: "", usedAI: false, days: days.count) : lead
        answer.spotIds = spots.map(\.spotId)
        answer.plan = AskPlanAnswer(title: result.title, planId: planId, days: days.map { $0.map(\.spotId) })
        answer.note = AskPlanFlowText.modeNote(result.mode)
        if askedServer { answer.serverSent = true }
        appendPlain(AskExchange(question: question, answer: answer), userId: userId)
    }

    /// 旅行プランを作れなかった（圏外、候補が無い、保存できない）。やり直しは答えの「もう一度」から
    func failPlan(_ question: String, line: String, userId: String?, askedServer: Bool = false) {
        guard pending == question else { return }
        var answer = AskAnswer(engine: .table, state: .failed, text: line)
        answer.kind = .plan
        if askedServer { answer.serverSent = true }
        appendPlain(AskExchange(question: question, answer: answer), userId: userId)
    }

    /// 旅行プランを待つのをやめる（画面を閉じた・人が替わった。作る仕事は旅行プランの AI が続け、できたら帯で知らせる）
    func cancelPlan() {
        guard pendingKind == .plan else { return }
        pending = nil
        pendingKind = nil
    }

    private func appendPlain(_ exchange: AskExchange, userId: String?) {
        push(exchange)
        pending = nil
        pendingKind = nil
        persist(userId: userId)
    }

    /// 会話に1往復足す（頼んだ時刻を付ける。残すのは新しい `AskHistoryStore.turnLimit` 往復まで）
    private func push(_ exchange: AskExchange) {
        var e = exchange
        if e.askedAt == nil { e.askedAt = Date() }
        thread.append(e)
        if thread.count > AskHistoryStore.turnLimit { thread.removeFirst(thread.count - AskHistoryStore.turnLimit) }
        freshId = e.id
    }

    /// 端末の控えに書く（同じ日の同じ頼みの控えと、会話）。ログインしていない、人が替わった、控えを消した間の答えは書かない
    private func persist(userId: String?) {
        guard mayPersist(userId) else { return }
        let kept = Self.keepable(Self.todaysHead(thread))
        if !kept.isEmpty { history.remember(kept, userId: userId) }
        keepConversation(userId: userId)
    }

    private func ask(_ question: String, backend: Backend) async {
        pending = question
        askingQuestion = question
        claimOwner(backend.userId())
        pendingKind = AskAnswerKind.byWords(question)
        mark("start")
        let answer = await answer(question, backend: backend)
        // 欄を打ち替えて閉じた回（取り消し）は出さない
        guard !Task.isCancelled else { return }
        // 札の中身は `answer` の中で覚えた
        append(AskExchange(question: question, answer: answer), library: nil, backend: backend)
        mark(answer.limit != nil ? "band" : "answered")
        await loadPendingDetails(backend: backend)
    }

    /// 2026-11-20 判断（run 1612 の帯の試験）: **答えと「使い切った」帯は、観光スポットの案内の文（詳細・通信）を待たずに先に出す。**
    /// 案内の文はあとから札に差し込む（利用者を通信待ちで待たせない）。前は答えを作る中で詳細を待っていて、遅い回線や
    /// 遅い模擬機では答えも帯も出るまで 30 秒を超えた
    private func loadPendingDetails(backend: Backend) async {
        let needed = pendingDetails
        pendingDetails = []
        guard !needed.isEmpty else { return }
        mark("detailsLoading")
        detailsLoading = true
        defer { detailsLoading = false }
        let detailed = await backend.details(needed)
        guard !Task.isCancelled else { return }
        // 索引だけの行にだけ差し込む（写真つきの行を索引の行で上書きしない・2026-11-22 確かめ役の指摘）
        overlayDetails(detailed)
        mark("detailsDone")
    }

    /// 画面が読み足した観光スポットの詳細を札に重ねる（`AskThreadView` の `.task(id:)`・`SpotDetailNeeds.asked`）。
    /// まだ索引だけの行にだけ差し込む（`SpotDetailNeeds.overlay`）。控えから戻した会話・旅行プランの流れの札もこれで写真が出る
    func overlayDetails(_ merged: [OfficialSpot]) {
        var next = spotsById
        for row in SpotDetailNeeds.overlay(Array(spotsById.values), with: merged) { next[row.spotId] = row }
        guard next != spotsById else { return }
        spotsById = next
    }

    private func append(_ exchange: AskExchange, library: AskLibrary?, backend: Backend) {
        if let library { remember(library: library, thread: [exchange]) }
        push(exchange)
        pending = nil
        pendingKind = nil
        askingQuestion = nil
        persist(userId: backend.userId())
    }

    /// 控えに残す往復（2026-11-20 判断）: **AI で答えた回と断った回だけ**。圏外、ログインしていない、上限、AI が答えない回の
    /// 言葉の表の答えは残さない（同じ日に開き直したとき、AI で答え直せるように）。頭から続く分だけ
    static func keepable(_ thread: [AskExchange]) -> [AskExchange] {
        Array(thread.prefix { $0.answer.usedAI || $0.answer.engine == .refused })
    }

    /// 会話の頭から、今日（日本時間）頼んだ往復が続く分だけ。
    /// 2026-11-22 判断（札 #684）: 前の日の会話を開いて今日続けて聞くと、その会話を丸ごと今日の答えとして控えに書き直し、
    /// 翌日からも同じ頼みに古い答え（見頃など）を回数を使わずに出していた。前の日の頼みで始まる会話は控えに書かない
    static func todaysHead(_ thread: [AskExchange], now: Date = Date()) -> [AskExchange] {
        let today = AskHistoryStore.day(now)
        return Array(thread.prefix { $0.askedAt.map { AskHistoryStore.day($0) == today } ?? false })
    }

    /// 今日、同じ頼みで始めた会話（控えから答えを出すとき、新しい会話を作らずにそれを開く・札 #684）
    static func todaysConversation(startingWith question: String, in items: [AskHistoryStore.Conversation],
                                   now: Date = Date()) -> AskHistoryStore.Conversation? {
        let key = RecentSearchesStore.normalized(question)
        let today = AskHistoryStore.day(now)
        return items.first { item in
            guard let first = item.thread.first, RecentSearchesStore.normalized(first.question) == key,
                  let at = first.askedAt else { return false }
            return AskHistoryStore.day(at) == today
        }
    }

    // MARK: - 1問に答える

    func answer(_ question: String, backend: Backend) async -> AskAnswer {
        // 1. 先に断る（AI を呼ばない・回数も使わない・何も引かない）
        if AskGuard.declinesBeforeAsking(question) || AskGuard.needsCare(question) {
            return .refused(care: AskGuard.needsCare(question))
        }
        let reading = SearchSentence.readByTable(question)
        let intent = AskQuery.intent(question, reading: reading)
        let library = await backend.library(intent.near)

        // 4. 回数を取る
        guard backend.signedIn() else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.signedOutLine, state: .answered)
        }
        guard !backend.offline() else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.offlineLine, state: .offline)
        }
        let onDevice = backend.deviceAI()

        // 5a. 端末の AI（0円）。2026-11-20 判断: **答えを画面に出す直前に1回取る**（reserve via device）。
        // AI が答えなかった、時間切れ、欄を打ち替えて取り消した回は数えない（Artifact「数えない回」）。取れなければ答えを出さない
        if onDevice {
            mark("deviceAsking")
            let result = await backend.deviceAsk(question, contextThread, library)
            if Task.isCancelled { return AskAnswer(engine: .table) }
            guard let result else {
                return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
            }
            if let fallback = await reserveOrFallback(.device, question: question, library: library, backend: backend) {
                return fallback
            }
            return await aiAnswer(question, text: result.text, general: result.general, picks: result.picks,
                                  photoIds: result.photoIds, sources: result.sources, engine: .device,
                                  aiKind: result.kind, library: library, backend: backend)
        }

        // 5b. サーバーの AI（費用がかかる）。先に1回取る（取った回は次の ask が使う・二重に数えない）
        // 2026-11-22 判断（審査 5.1.2(i)）: 送る前に同意を取る。送りそうな人（Pro、管理者、まだ分からない）には回数を取る前に聞く
        // （「やめる」で回数を無駄にしない）。無料と分かっている人には聞かず、回数を取ってサーバーが許したときだけ、送る直前に聞く
        if backend.serverLikely(), self.usage?.serverAllowed != false, !(await serverConsented(backend)) {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.consentDeclinedLine, state: .answered)
        }
        if let fallback = await reserveOrFallback(.server, question: question, library: library, backend: backend) {
            return fallback
        }
        guard let usage = self.usage else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
        }
        guard usage.serverAllowed else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.noDeviceAILine, state: .answered)
        }
        // 2026-11-22 判断（確かめ役の指摘）: ここで「やめる」と答えると、上で取った1回は戻らない（回数を戻す口がサーバーに無い。
        // 作らない）。ここで聞くのは、無料と見立てたのにサーバーが送ってよいと答えた稀な回だけ（ふつうは回数を取る前に聞く）
        guard await serverConsented(backend) else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.consentDeclinedLine, state: .answered)
        }
        let query = AskLibrary.query(reading: reading, intent: intent, sentence: question, spots: library.spots)
        let picks = intent.spots ? library.pickSpots(query) : []
        do {
            let turns = contextThread.suffix(AskService.historyTurns).map { AskService.Turn(question: $0.question, answer: $0.answer.text) }
            mark("serverAsking")
            let reply = try await backend.serverAsk(question, Array(turns), picks.map(\.spot))
            if Task.isCancelled { return AskAnswer(engine: .table) }
            if let quota = reply.quota { self.usage = quota }
            // サーバーが断った（呼ぶ前の断り・AI の断り・答えの前の見張り）。アプリの断りの1行にそろえ、札も出さない
            if reply.refused { return .refused(care: AskGuard.needsCare(question)) }
            let sources: [AskAnswer.Source] = picks.isEmpty ? [] : [.init(kind: .spots, label: AskText.spotsSource)]
            // 2026-11-21 判断: サーバーが種類と頭の文を返したら使う（今のサーバーは返さない。返す形はサーバーの担当に頼む）
            let text = reply.lead.map { $0.isEmpty ? reply.answer : $0 + "\n" + reply.answer } ?? reply.answer
            return await aiAnswer(question, text: text, general: reply.general, picks: picks, photoIds: [],
                                  sources: sources, engine: .server, aiKind: reply.kind, library: library, backend: backend)
        } catch AskService.Failure.limit(let reason, let quota) {
            if let quota, !Task.isCancelled { self.usage = quota }
            var a = await tableAnswer(question, library: library, backend: backend, note: nil, state: .answered)
            a.limit = reason
            return a
        } catch AskService.Failure.proOnly {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.noDeviceAILine, state: .answered)
        } catch {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
        }
    }

    /// サーバーの AI に送ってよいか。この会話で「やめる」と答えていたら聞かずに false（同意済みなら聞かずに true）
    private func serverConsented(_ backend: Backend) async -> Bool {
        // 同意済みを先に見る（2026-11-22 確かめ役の指摘: 「やめる」のあと設定でオンにしても、この会話では送らなかった）
        if backend.consentAccepted() {
            consentDeclined = false
            return true
        }
        if consentDeclined { return false }
        let ok = await backend.serverConsent()
        if !ok { consentDeclined = true }
        return ok
    }

    /// 回数を1回取る。取れたら nil（`usage` を更新）。取れなければ、言葉の表の答え（上限なら帯）
    private func reserveOrFallback(_ via: AskService.Via, question: String, library: AskLibrary,
                                   backend: Backend) async -> AskAnswer? {
        mark("reserving")
        do {
            let reserved = try await backend.reserve(.ask, via)
            // 2026-11-21 判断（バグ調べ）: 待っている間に取り消された（ログアウトして `reset` した・画面を閉じた）回は、
            // 前の人の残りの回数を置き直さない（上の1行に前の人の回数が残っていた）。答えも出さない
            guard !Task.isCancelled else { return AskAnswer(engine: .table) }
            usage = reserved
            return nil
        } catch AskService.Failure.limit(let reason, let quota) {
            if let quota, !Task.isCancelled { usage = quota }
            var a = await tableAnswer(question, library: library, backend: backend, note: nil, state: .answered)
            a.limit = reason
            return a
        } catch AskService.Failure.signedOut {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.signedOutLine, state: .answered)
        } catch AskService.Failure.proOnly {
            // 端末の AI が無い iPhone の無料の人（サーバーの 403 `proOnly`）。回数は使っていない
            return await tableAnswer(question, library: library, backend: backend, note: AskText.noDeviceAILine, state: .answered)
        } catch {
            let offline = backend.offline()
            return await tableAnswer(question, library: library, backend: backend,
                                     note: offline ? AskText.offlineLine : AskText.silentLine, state: offline ? .offline : .answered)
        }
    }

    /// AI の答えを部品にする。**文は見張りを通す**（漏れの形が混じれば断りの1行に替え、札も出さない）
    private func aiAnswer(_ question: String, text: String, general: Bool, picks: [AskLibrary.Pick], photoIds: [String],
                          sources: [AskAnswer.Source], engine: AskAnswer.Engine, aiKind: String? = nil,
                          library: AskLibrary, backend: Backend) async -> AskAnswer {
        let screened = AskGuard.screened(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if screened.refused { return .refused(care: false) }
        let reading = SearchSentence.readByTable(question)
        let intent = AskQuery.intent(question, reading: reading)
        let query = AskLibrary.query(reading: reading, intent: intent, sentence: question, spots: library.spots)
        // AI が台帳を引かなかったときも、観光スポットを探す頼みなら、アプリが選んだ札を出す
        let shown = !picks.isEmpty ? picks : (intent.spots ? library.pickSpots(query) : [])
        var answer = AskAnswer(engine: engine)
        // 2026-11-20 判断（札 #663）: 文ははじめの1〜2文だけ。「- 名前: 説明」の行は札の理由に振り分け、札に無い名前の行は出さない
        let shaped = AskAnswerShape.shape(screened.text, spots: shown.map(\.spot))
        // 2026-11-21 判断（札 #675 の答えの形・版3）: 頭の文に台帳に無い場所らしい名前があれば決まり文に替える。
        // 種類は AI が返したもの → 字から分かるもの → 札の有無。AI が札と言ったのに札が無ければ「形が読めなかった」（頭の文だけ）
        answer.text = AskLeadCheck.safeLead(shaped.lead, shown: shown.map(\.spot), ledger: library.spots, season: query.season?.label)
        answer.reasons = shaped.reasons.isEmpty ? nil : shaped.reasons
        let declared = AskAnswerKind.parse(aiKind)
        answer.kind = AskFormCheck.kind(ai: declared, words: AskAnswerKind.byWords(question), spotCount: shown.count)
        if AskFormCheck.unreadable(ai: declared, spotCount: shown.count) { answer.unreadable = true }
        answer.general = general && shown.isEmpty && photoIds.isEmpty
        answer.sources = sources
        await fill(&answer, picks: shown, query: query, intent: intent, question: question,
                   extraPhotoIds: photoIds, library: library, backend: backend)
        return answer
    }

    /// AI を使わない答え（言葉の表と台帳。使い方の質問は使い方の頁の3行）
    func tableAnswer(_ question: String, library: AskLibrary, backend: Backend, note: String?,
                     state: AskAnswer.State) async -> AskAnswer {
        let reading = SearchSentence.readByTable(question)
        let intent = AskQuery.intent(question, reading: reading)
        let query = AskLibrary.query(reading: reading, intent: intent, sentence: question, spots: library.spots)
        var answer = AskAnswer(engine: .table, state: state)
        answer.note = note
        answer.kind = intent.spots ? .cards : .text
        if !intent.spots {
            let pages = AskHelpPages.matching(question)
            if let page = pages.first {
                answer.text = page.lines.joined(separator: "\n")
                answer.sources = pages.map { .init(kind: .help, label: L("使い方の頁「\($0.title)」", "Help: \($0.title)")) }
            } else {
                answer.text = AskText.unansweredLine
            }
            return answer
        }
        let picks = library.pickSpots(query)
        if picks.isEmpty {
            if state != .offline { answer.state = .empty }
            answer.relaxedQuery = AskLibrary.relaxed(query).map(AskLibrary.phrase)
            answer.chips = chips(query: query, library: library)
            answer.text = emptyReason(query)
            return answer
        }
        await fill(&answer, picks: picks, query: query, intent: intent, question: question,
                   extraPhotoIds: [], library: library, backend: backend)
        return answer
    }

    /// 札（観光スポット、地図のピン、みんなの写真、旅行プランにする）と、読み取りの札と見出しを入れる
    private func fill(_ answer: inout AskAnswer, picks: [AskLibrary.Pick], query: AskLibrary.Query, intent: AskQuery.Intent,
                      question: String, extraPhotoIds: [String], library: AskLibrary, backend: Backend) async {
        answer.chips = chips(query: query, library: library)
        if intent.near, library.here == nil { answer.note = answer.note ?? AskText.noLocationLine }
        if query.season != nil, Self.asksWeekly(question) { answer.note = answer.note ?? AskText.weeklyLine }
        guard !picks.isEmpty else {
            answer.photoIds = extraPhotoIds
            rememberPhotos(library: library, ids: extraPhotoIds)
            return
        }
        // 札は索引の行で先に出し、案内の文（詳細）は答えを出したあとに重ねる（`loadPendingDetails`・2026-11-20 判断）
        for p in picks where spotsById[p.spot.spotId] == nil { spotsById[p.spot.spotId] = p.spot }
        pendingDetails += picks.map(\.spot)
        answer.spotIds = picks.map(\.spot.spotId)
        for p in picks { if let km = p.distanceKm, query.near { answer.distances[p.spot.spotId] = km } }
        answer.heading = query.filter.spotsHeading(count: picks.count)
        let photos = library.pickPhotos(near: picks, keyword: query.keyword ?? query.place)
        let ids = extraPhotoIds + photos.map(\.id).filter { !extraPhotoIds.contains($0) }
        answer.photoIds = Array(ids.prefix(AskLibrary.maxPhotos))
        rememberPhotos(library: library, ids: answer.photoIds)
        answer.offersPlan = true
    }

    /// 読み取りの札（「現在地から 30km」「香川」「夕方」）
    private func chips(query: AskLibrary.Query, library: AskLibrary) -> [String] {
        var out: [String] = []
        if query.near, library.here != nil { out.append(AskText.nearChip(km: AskLibrary.nearKm)) }
        if let place = query.place { out.append(place) }
        if let s = query.season { out.append(s.label) }
        if let d = query.dayPart { out.append(d.phrase) }
        if let k = query.keyword { out.append(k) }
        return out
    }

    /// 空のときの理由の1行（「沖縄県で冬の案内に雪とある所はありませんでした。」）
    private func emptyReason(_ q: AskLibrary.Query) -> String {
        let place = q.place.map { L("\($0)で", "in \($0) ") } ?? (q.near ? L("近くで", "nearby ") : "")
        let cond = [q.season?.label, q.dayPart?.phrase].compactMap { $0 }.joined(separator: L("、", " "))
        let guide = cond.isEmpty ? "" : L("\(cond)の案内に", "with \(cond) notes ")
        let word = q.keyword.map { L("\($0)とある", "mentioning \($0) ") } ?? (cond.isEmpty ? L("合う", "matching ") : L("ある", ""))
        return L("\(place)\(guide)\(word)所はありませんでした。", "No spots \(place)\(guide)\(word)were found.")
    }

    /// 「今週末」「来週」「見頃」（台帳に週ごとの見頃は無い）
    static func asksWeekly(_ text: String) -> Bool {
        ["今週", "週末", "来週", "見頃", "今が", "this weekend", "next week"].contains { text.contains($0) }
    }

    private func remember(library: AskLibrary, thread: [AskExchange]) {
        let spots = Dictionary(library.spots.map { ($0.spotId, $0) }, uniquingKeysWith: { a, _ in a })
        for e in thread {
            // 古い形の旅行プランの答え（`spotIds` が空で日ごとの場所だけ）も、開き直したときに場所を出す（2026-11-22 確かめ役の指摘）
            let ids = e.answer.spotIds + (e.answer.plan?.days.flatMap { $0 } ?? [])
            for id in ids where spotsById[id] == nil { spotsById[id] = spots[id] }
            rememberPhotos(library: library, ids: e.answer.photoIds)
        }
    }

    private func rememberPhotos(library: AskLibrary, ids: [String]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        for p in library.photos where set.contains(p.id) { photosById[p.id] = p }
    }

}
