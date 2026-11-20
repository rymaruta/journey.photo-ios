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
    }

    @Published private(set) var thread: [AskExchange] = []
    /// 答えを用意している問い（読み込み中の骨格を出す）
    @Published private(set) var pending: String?
    @Published private(set) var usage: AskUsage?
    /// 札に出す観光スポット（`spotId` → 行。詳細を重ねたもの）
    @Published private(set) var spotsById: [String: OfficialSpot] = [:]
    /// みんなの写真（`Photo.id` → 写真）
    @Published private(set) var photosById: [String: Photo] = [:]

    private let history: AskHistoryStore
    /// 答えを出したあとに案内の文（詳細）を重ねる観光スポット（`fill` が積み、`loadPendingDetails` が読む）
    private var pendingDetails: [OfficialSpot] = []

    /// いまの段（UI テストのときだけ見える要素 `search.ask.stage` に出す・2026-11-20 run 1612 の帯の試験の調べ）。
    /// 段の名前と、頼んでからの経過（ms）を並べる
    @Published private(set) var stageLog: [String] = []
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
    /// 最初の問い（探すの欄に入っている文）
    var firstQuestion: String? { thread.first?.question ?? pending }

    /// 会話を閉じる。**残りの回数と札の中身も手放す**（人が替わったときに前の人の物を残さない）
    func reset() {
        thread = []
        pending = nil
        usage = nil
        pendingDetails = []
        spotsById = [:]
        photosById = [:]
    }

    /// 新しく頼む前に、**すぐに**答えの形（読み込み中）にする。前の会話は閉じる。返すのは頼んだ文（空なら nil）。
    /// 画面は欄の字をこの文にそろえてから `start` を呼ぶ（字が替わったら答えを閉じる決まりと食い違わない）
    @discardableResult
    func prepare(_ raw: String) -> String? {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty else { return nil }
        thread = []
        pending = question
        return question
    }

    /// 新しく頼む（前の会話は閉じる）。同じ日の同じ頼みは控えから出す（回数を使わない）
    func start(_ raw: String, backend: Backend) async {
        guard let question = prepare(raw) else { return }
        if let cached = history.today(question, userId: backend.userId()) {
            // 控えの札の中身（観光スポットと写真）を読み直して出す
            let library = await backend.library(false)
            guard !Task.isCancelled else { return }
            remember(library: library, thread: cached)
            thread = cached
            pending = nil
            return
        }
        await ask(question, backend: backend)
    }

    /// 今日すでに答えた控えがあるか（最近の語を押したとき、控えがあるときだけ答えを出す・AI は呼ばない・札 #662）
    func hasToday(_ raw: String, userId: String?) -> Bool {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty else { return false }
        return history.today(question, userId: userId) != nil
    }

    /// 答えの下の欄で続けて聞く（続きも1回と数える）
    func followUp(_ raw: String, backend: Backend) async {
        let question = AskQuery.clipped(raw)
        guard !question.isEmpty, !thread.isEmpty, pending == nil else { return }
        await ask(question, backend: backend)
    }

    /// 空の答えの言い替え（条件を1つ外す）。**アプリが選び直すだけで AI は呼ばない・回数を使わない**
    func relax(_ exchange: AskExchange, backend: Backend) async {
        guard let phrase = exchange.answer.relaxedQuery, pending == nil else { return }
        pending = phrase
        let library = await backend.library(false)
        let answer = await tableAnswer(phrase, library: library, backend: backend, note: nil, state: .answered)
        guard !Task.isCancelled else { return }
        append(AskExchange(question: phrase, answer: answer), library: library, backend: backend)
        await loadPendingDetails(backend: backend)
    }

    private func ask(_ question: String, backend: Backend) async {
        pending = question
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
        let detailed = await backend.details(needed)
        guard !Task.isCancelled else { return }
        for spot in detailed where spotsById[spot.spotId] != nil { spotsById[spot.spotId] = spot }
        mark("detailsDone")
    }

    private func append(_ exchange: AskExchange, library: AskLibrary?, backend: Backend) {
        if let library { remember(library: library, thread: [exchange]) }
        thread.append(exchange)
        pending = nil
        let kept = Self.keepable(thread)
        if !kept.isEmpty { history.remember(kept, userId: backend.userId()) }
    }

    /// 控えに残す往復（2026-11-20 判断）: **AI で答えた回と断った回だけ**。圏外、ログインしていない、上限、AI が答えない回の
    /// 言葉の表の答えは残さない（同じ日に開き直したとき、AI で答え直せるように）。頭から続く分だけ
    static func keepable(_ thread: [AskExchange]) -> [AskExchange] {
        Array(thread.prefix { $0.answer.usedAI || $0.answer.engine == .refused })
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
            let result = await backend.deviceAsk(question, thread, library)
            if Task.isCancelled { return AskAnswer(engine: .table) }
            guard let result else {
                return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
            }
            if let fallback = await reserveOrFallback(.device, question: question, library: library, backend: backend) {
                return fallback
            }
            return await aiAnswer(question, text: result.text, general: result.general, picks: result.picks,
                                  photoIds: result.photoIds, sources: result.sources, engine: .device,
                                  library: library, backend: backend)
        }

        // 5b. サーバーの AI（費用がかかる）。先に1回取る（取った回は次の ask が使う・二重に数えない）
        if let fallback = await reserveOrFallback(.server, question: question, library: library, backend: backend) {
            return fallback
        }
        guard let usage = self.usage else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
        }
        guard usage.serverAllowed else {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.noDeviceAILine, state: .answered)
        }
        let query = AskLibrary.query(reading: reading, intent: intent, sentence: question, spots: library.spots)
        let picks = intent.spots ? library.pickSpots(query) : []
        do {
            let turns = thread.suffix(AskService.historyTurns).map { AskService.Turn(question: $0.question, answer: $0.answer.text) }
            mark("serverAsking")
            let reply = try await backend.serverAsk(question, Array(turns), picks.map(\.spot))
            if let quota = reply.quota { self.usage = quota }
            // サーバーが断った（呼ぶ前の断り・AI の断り・答えの前の見張り）。アプリの断りの1行にそろえ、札も出さない
            if reply.refused { return .refused(care: AskGuard.needsCare(question)) }
            let sources: [AskAnswer.Source] = picks.isEmpty ? [] : [.init(kind: .spots, label: AskText.spotsSource)]
            return await aiAnswer(question, text: reply.answer, general: reply.general, picks: picks, photoIds: [],
                                  sources: sources, engine: .server, library: library, backend: backend)
        } catch AskService.Failure.limit(let reason, let quota) {
            if let quota { self.usage = quota }
            var a = await tableAnswer(question, library: library, backend: backend, note: nil, state: .answered)
            a.limit = reason
            return a
        } catch AskService.Failure.proOnly {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.noDeviceAILine, state: .answered)
        } catch {
            return await tableAnswer(question, library: library, backend: backend, note: AskText.silentLine, state: .answered)
        }
    }

    /// 回数を1回取る。取れたら nil（`usage` を更新）。取れなければ、言葉の表の答え（上限なら帯）
    private func reserveOrFallback(_ via: AskService.Via, question: String, library: AskLibrary,
                                   backend: Backend) async -> AskAnswer? {
        mark("reserving")
        do {
            usage = try await backend.reserve(.ask, via)
            return nil
        } catch AskService.Failure.limit(let reason, let quota) {
            if let quota { usage = quota }
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
                          sources: [AskAnswer.Source], engine: AskAnswer.Engine,
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
        answer.text = shaped.lead
        answer.reasons = shaped.reasons.isEmpty ? nil : shaped.reasons
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
            for id in e.answer.spotIds where spotsById[id] == nil { spotsById[id] = spots[id] }
            rememberPhotos(library: library, ids: e.answer.photoIds)
        }
    }

    private func rememberPhotos(library: AskLibrary, ids: [String]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        for p in library.photos where set.contains(p.id) { photosById[p.id] = p }
    }

    /// 最近の検索の × と「すべて消す」で、答えの控えも消す
    func forget(_ question: String, userId: String?) { history.remove(question, userId: userId) }
    func forgetAll(userId: String?) { history.removeAll(userId: userId) }
}
