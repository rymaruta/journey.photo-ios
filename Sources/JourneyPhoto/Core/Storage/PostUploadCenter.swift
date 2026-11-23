import Foundation
import Combine

/// **投稿（写真）を裏で送る係**（2026-11-18 owner 採用・案 B2「投稿を送る」）。
///
/// 前は「投稿する」を押すと、送り終えるまで投稿の画面で待ち、送ったあと共有カードが毎回画面いっぱいに出た
/// （1.1.83 の owner の決め）。いまはストーリー（`StoryUploadCenter`・板 27）と同じ形:
/// 「投稿する」で画面を閉じ、ここが送る。ホームの自分の輪が真鍮で満ちていく「送信中…」。
/// 終わったら知らせ「投稿しました　カードにする」（`PostedCardHabit.quietText`）、
/// 失敗したら「送れませんでした　もう一度」。共有カードは知らせから開く（今回の採用で 1.1.83 の決めを置き換えた）。
///
/// 送る中身と手順は前のまま、**画面のモデル（`UploadViewModel`）をそのまま持って送る**——写しを作らない。
/// - 写真の本体は背景の転送（`BackgroundTransfer`）、保存の前後は裏の猶予（`BackgroundWindow`）。アプリを離れても送り終える
/// - 送る前に送信の控え（`UploadDraftStore` の `send`）を書く。強制終了されても、次の起動で「送れなかった投稿があります」
/// - 🔴 **失敗したら、写真と文はここに残す**（画面のモデルごと）。「もう一度」で同じ鍵で送り直す（二重にならない・
///   `UploadService.stage`）。輪を押せば投稿の画面で開き直して直せる。強制終了しても控えから戻せる
@MainActor
final class PostUploadCenter: ObservableObject {

    static let shared = PostUploadCenter()

    /// 1件の投稿（1回の「投稿する」）
    @MainActor
    final class Job: Identifiable {
        let id = UUID()
        let model: UploadViewModel
        /// 送り始めたときの枚数
        fileprivate(set) var total: Int
        /// 送り終えた枚数（`uploadingIndex` から）
        fileprivate(set) var done = 0
        /// 送っている最中か
        fileprivate(set) var sending = false
        /// 送れなかった理由（送れなかったときだけ）
        fileprivate(set) var failure: String?
        /// 観光スポットの頁へ「並んだ枚数」を知らせる（スポットから開いた投稿だけ）
        fileprivate let onPosted: ((Int) -> Void)?
        /// 誰の投稿か（人が替わったら持たない）。**持ち主の分からない投稿は受けない**（`start`）
        let ownerId: String?
        /// 送っている途中で持ち主でなくなった（終わったら黙って手放す・控えは持ち主の枠に残る）
        fileprivate(set) var abandoned = false
        /// 本人が「送信をやめる」を押した（終わったら失敗ではなく「送信をやめました」にする）
        fileprivate(set) var cancelledByUser = false

        fileprivate init(model: UploadViewModel, onPosted: ((Int) -> Void)?) {
            self.model = model
            self.total = model.items.count
            self.onPosted = onPosted
            self.ownerId = model.draftOwner
        }
    }

    /// 輪と知らせが見る段
    enum Phase: Equatable {
        case idle
        /// 写真 `done` 枚を出して、全部で `total` 枚
        case sending(done: Int, total: Int)
        /// 止まった（写真と文は持っている）
        case failed(message: String)
    }

    /// 知らせ（`ToastCenter` へ）。試験はここを差し替えて受け取る
    enum Notice: Equatable {
        /// 全部上がった。カードを作れる投稿（全体に公開）なら `card` が true
        case posted(card: Bool)
        /// 上がったが一言ある（曲が付かなかった・前に投稿済みだった など）
        case postedWithNote(String)
        /// 送れなかった（「もう一度」で送り直す）
        case failed(String)
        /// 送れなかった。「もう一度」では直らない（選んだアルバムが消えた）ので、投稿の画面で直すよう案内する
        case failedNeedsEditing(String)
        /// 本人が「送信をやめる」でやめた（失敗ではない。触覚は鳴らさない・写真と文は持ったまま）
        case cancelled
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var phase: Phase = .idle
    /// **全部送り終えた回数。** ホームの輪・マイページはこれを見て読み直す（真偽値だと2回目が効かない）
    @Published private(set) var finished = 0
    /// **送れなかった回数**（失敗の触覚を1回鳴らす合図・前の投稿画面の `postFailedTicks` の役）
    @Published private(set) var failures = 0
    /// 知らせの「直す」で、投稿の画面で開き直してほしい投稿（ホームの輪 `StoriesRow` が受けて開く）
    @Published private(set) var editRequest: UUID?

    /// 知らせを出す口（アプリが起動時に渡す・`configure`）
    private weak var toasts: ToastCenter?
    /// 試験で知らせを受ける口（渡されていれば `toasts` より先に呼ぶ）
    var onNotice: ((Notice, UUID) -> Void)?
    /// 🔴 **いまログインしている人**（アプリが起動時に渡す・試験は差し替える）。送る前・1枚ごと・「もう一度」で持ち主と比べる
    var currentUserId: (() -> String?)?
    /// 投稿の知らせの言い方を場所で変える口（札 #710 の案1「行きたい場所に行けました」・案7「最初の1枚になりました」）。
    /// 起動のときに渡す（行きたい場所の控えと観光スポットの索引を読む）。nil なら通常の「投稿しました」
    var placeNotice: (@MainActor (_ posted: [Photo], _ spot: UploadSpotTarget?, _ postedToSpot: Int, _ ownerId: String?) async -> PostedPlaceNotice?)?

    /// 送っている・送れずに持っている投稿があるか（輪が「送信中…」「送れませんでした」を出す）
    var isBusy: Bool { !jobs.isEmpty }

    /// 送れずに持っている投稿（いちばん古いもの）
    var failedJob: Job? { jobs.first { $0.failure != nil && !$0.sending } }

    /// 🔴 **この係が持っている投稿の送信の控え。** 投稿の画面を開いたときの「送れなかった投稿があります」から外す——
    /// 裏で送っている最中・送れずに持っている投稿を「続きから」で戻すと、同じ写真が2つの画面で二重に送られる
    var heldJournalIds: Set<String> { Set(jobs.compactMap { $0.model.journalId }) }

    /// 尋ねてよい送信の控え（係が持っていないもの）
    static func askable(_ journalIds: [String], held: Set<String>) -> [String] {
        journalIds.filter { !held.contains($0) }
    }

    init() {}

    /// 起動時に知らせの口と、いまログインしている人を読む口を渡す
    func configure(toasts: ToastCenter, currentUserId: @escaping () -> String?) {
        self.toasts = toasts
        self.currentUserId = currentUserId
    }

    /// 持ち主がいまログインしている人か。**持ち主の分からない投稿は送らない**（別の人の「もう一度」で上がらないように）
    private func ownedByCurrentUser(_ ownerId: String?) -> Bool {
        guard let ownerId, !ownerId.isEmpty else { return false }
        guard let currentUserId else { return true }
        return currentUserId() == ownerId
    }

    /// 送り始める。**画面はこれが true を返したら閉じる**（返さなければ閉じない・送れる形でない）。
    /// 共有カードは画面いっぱいに出さず、知らせの「カードにする」から開く（`showsCardSheet` を切る）
    @discardableResult
    func start(_ model: UploadViewModel, onPosted: ((Int) -> Void)? = nil) -> Bool {
        guard model.canSubmit, !jobs.contains(where: { $0.model === model }),
              ownedByCurrentUser(model.draftOwner) else { return false }
        model.showsCardSheet = { false }
        let job = Job(model: model, onPosted: onPosted)
        // 🔴 1枚ごとに持ち主のままかを見る（途中で人が替わったら、残りを別の人の名前で上げない）
        let owner = job.ownerId
        model.ownerStillSignedIn = { [weak self] in self?.ownedByCurrentUser(owner) ?? false }
        model.onProgress = { [weak self, weak job] index in
            guard let self, let job else { return }
            job.done = PostUploadProgress.done(uploadingIndex: index, total: job.total)
            self.recompute()
        }
        // 🔴 **その場で「送信中」にする**（裏の Task が動き出すまでの隙に、輪が出ない・二度押しを受けない）
        job.sending = true
        jobs.append(job)
        recompute()
        Task { await run(job) }
        return true
    }

    /// 送れなかった投稿をもう一度送る（知らせの「もう一度」・輪の「もう一度送る」）。同じ鍵で送り直す
    func retry(_ jobId: UUID? = nil) {
        guard let job = jobs.first(where: { jobId == nil ? ($0.failure != nil && !$0.sending) : $0.id == jobId }),
              job.failure != nil, !job.sending, job.model.canSubmit,
              // 🔴 持ち主でない人の「もう一度」では送らない（持ち主の分からない投稿も）
              ownedByCurrentUser(job.ownerId) else { return }
        job.failure = nil
        job.cancelledByUser = false
        job.total = job.model.items.count
        job.done = 0
        job.sending = true
        recompute()
        Task { await run(job) }
    }

    /// 送れなかった投稿を、投稿の画面で開き直して直す（輪の「投稿の画面で直す」）。
    /// **係から外して画面に渡す**（写真と文は画面のモデルごと。画面の「投稿する」でまたここへ戻る）
    func takeForEditing(_ jobId: UUID? = nil) -> UploadViewModel? {
        guard let index = jobs.firstIndex(where: { jobId == nil ? ($0.failure != nil && !$0.sending) : $0.id == jobId }),
              !jobs[index].sending else { return nil }
        let job = jobs.remove(at: index)
        job.model.onProgress = nil
        recompute()
        return job.model
    }

    /// ログインしている人が変わった。**投稿した本人でなくなったら、持っている投稿を手放す**
    /// （送信の控えは本人の端末の枠に残る——同じ人が入り直せば「送れなかった投稿があります」から戻せる）。
    /// 🔴 **送っている最中の投稿も止める**（いま送っている1枚のあと、残りを上げ始めない・2026-11-18 確かめ役の指摘）。
    /// 止まったら黙って手放す（`run`）
    func userChanged(to userId: String?) {
        let before = jobs.count
        for job in jobs where job.sending && job.ownerId != userId {
            job.abandoned = true
            job.model.cancel()
        }
        jobs.removeAll { !$0.sending && $0.ownerId != userId }
        if jobs.count != before { recompute() }
        PostedCardOffer.shared.userChanged(to: userId)
    }

    /// 送っている投稿をやめる（輪の「送信をやめる」）。いま送っている1枚は最後まで通し、残りは上げ始めない。
    /// 写真と文は持ったまま（送れなかった投稿として残り、「もう一度送る」「投稿の画面で直す」を選べる）
    func cancelSending() {
        for job in jobs where job.sending {
            job.cancelledByUser = true
            job.model.cancel()
        }
    }

    /// 知らせの「直す」: 投稿の画面で開き直す（ホームの輪が受けて開く）
    func requestEditing(_ jobId: UUID) {
        editRequest = jobId
    }

    /// 受けた「直す」を片づける
    func clearEditRequest() {
        editRequest = nil
    }

    /// 送れずに持っている投稿が「もう一度」で直るか（アルバムが消えた回は直らない）
    func canRetry(_ job: Job?) -> Bool {
        guard let job else { return false }
        return !job.model.failureNeedsEditing
    }

    private func run(_ job: Job) async {
        await job.model.submit()
        job.sending = false
        let model = job.model
        // 人が替わったと知らされた（`userChanged`）投稿は手放す（控えは持ち主の枠に残る）
        if job.abandoned {
            model.onProgress = nil
            jobs.removeAll { $0 === job }
            recompute()
            return
        }
        // 🔴 送っている途中で持ち主でなくなって止めた（`ownerStillSignedIn`）: **写真と文を持ったまま、送れなかった投稿にする**。
        // 別の人には知らせない（「もう一度」も持ち主でなければ送らない・`retry`）
        if model.stoppedForOwner {
            job.failure = model.errorMessage ?? PostUploadOutcome.failedText
            job.done = 0
            recompute()
            return
        }
        // 観光スポットの頁へ「並んだ枚数」（一部だけ上がった回も知らせる・前の画面の `postedToSpot` と同じ）
        if model.postedToSpot > 0 { job.onPosted?(model.postedToSpot) }
        // 🔴 本人が「送信をやめる」でやめた（2026-11-18 確かめ役の指摘）: 失敗の知らせと触覚を出さない（`failures` を増やさない）。
        // 知らせは「送信をやめました」。輪は送れなかった投稿として残す（写真と文は持ったまま。「もう一度送る」「投稿の画面で直す」）。
        // やめる前に全部上がっていた回は、ふつうに「投稿しました」
        let cancelledByUser = job.cancelledByUser
        job.cancelledByUser = false
        if cancelledByUser, !model.items.isEmpty {
            job.failure = PostUploadOutcome.cancelledText
            job.done = 0
            recompute()
            notice(.cancelled, job: job)
            return
        }
        switch PostUploadOutcome.of(didPostAll: model.didPostAll, remaining: model.items.count,
                                    message: model.errorMessage, needsEditing: model.failureNeedsEditing) {
        case .posted:
            finish(job)
            if let card = model.quietPostedCard { PostedCardOffer.shared.offer(card, ownerId: job.ownerId) }
            let place = await placeNotice?(model.savedPhotos, model.spot, model.postedToSpot, job.ownerId)
            notice(.posted(card: model.quietPostedCard != nil), job: job, card: model.quietPostedCard, place: place)
        case .postedWithNote(let note):
            finish(job)
            notice(.postedWithNote(note), job: job)
        case .failed(let message):
            job.failure = message
            job.done = 0
            failures += 1
            recompute()
            notice(.failed(message), job: job)
        case .failedNeedsEditing(let message):
            job.failure = message
            job.done = 0
            failures += 1
            recompute()
            notice(.failedNeedsEditing(message), job: job)
        }
    }

    /// 送り終えた（写真が無くなった）投稿を外し、マイページ・ホームに上がった写真を並べさせる
    private func finish(_ job: Job) {
        job.model.onProgress = nil
        jobs.removeAll { $0 === job }
        finished += 1
        recompute()
        // 画面を閉じたあとに上がった写真を、マイページ・ホームへ渡す（`TabRouter.notePosted` で控えた分）
        TabRouter.shared.postSheetClosed()
    }

    private func notice(_ notice: Notice, job: Job, card shareCard: PostedShareCard? = nil,
                        place: PostedPlaceNotice? = nil) {
        if let onNotice {
            onNotice(notice, job.id)
            return
        }
        guard let toasts else { return }
        switch notice {
        case .posted:
            // 場所の知らせ（札 #710）は1行目と2行目を替えるだけ。「カードにする」はそのまま
            let title = place?.title ?? PostedCardHabit.quietText
            if let card = shareCard {
                // その知らせのカードを、持ち主がいまの人のときだけ開く（札 #688）
                toasts.show(title, detail: place?.detail, kind: .success, actionTitle: PostedCardHabit.quietAction) { [weak self] in
                    PostedCardOffer.shared.present(card, currentUserId: self?.currentUserId?())
                }
            } else {
                toasts.show(title, detail: place?.detail, kind: .success)
            }
        case .postedWithNote(let note):
            toasts.show(note, kind: .info)
        case .failed:
            let id = job.id
            toasts.show(PostUploadOutcome.failedText, kind: .failure, actionTitle: PostUploadOutcome.retryAction) { [weak self] in
                self?.retry(id)
            }
        case .cancelled:
            toasts.show(PostUploadOutcome.cancelledText, kind: .info)
        case .failedNeedsEditing(let message):
            // 「もう一度」は出さない（同じ理由でまた落ちる）。投稿の画面で行き先を選び直す
            let id = job.id
            toasts.show(message, kind: .failure, actionTitle: PostUploadOutcome.editAction) { [weak self] in
                self?.requestEditing(id)
            }
        }
    }

    private func recompute() {
        let next = PostUploadProgress.phase(jobs.map { (sending: $0.sending, done: $0.done, total: $0.total, failure: $0.failure) })
        if next != phase { phase = next }
    }
}

/// 送り終えたあとの分かれ道（`PostUploadCenter.run`）。画面の外に出して試す
enum PostUploadOutcome: Equatable {
    case posted
    case postedWithNote(String)
    case failed(String)
    /// 「もう一度」では直らない失敗（選んだアルバムが消えた）。投稿の画面で直す
    case failedNeedsEditing(String)

    /// 失敗の知らせの言葉（案 B2「送れませんでした　もう一度」）
    static var failedText: String { L("送れませんでした", "Couldn\u{2019}t post") }
    static var retryAction: String { L("もう一度", "Try again") }
    /// 投稿の画面で直す一手（輪の「投稿の画面で直す」と同じ行き先・知らせは短く）
    static var editAction: String { L("直す", "Fix") }
    /// 本人が「送信をやめる」でやめたときの知らせ（失敗の言葉にしない）
    static var cancelledText: String { L("送信をやめました", "Stopped sending") }

    /// - `didPostAll`: 全部上がり、言うことも無い
    /// - 写真が残っていない（`remaining == 0`）が一言ある: 上がったが知らせる（曲が付かなかった・前に投稿済み）
    /// - 写真が残っている: 送れなかった（写真と文は持ったまま）
    static func of(didPostAll: Bool, remaining: Int, message: String?, needsEditing: Bool = false) -> PostUploadOutcome {
        if didPostAll { return .posted }
        if remaining == 0 {
            if let message, !message.isEmpty { return .postedWithNote(message) }
            return .posted
        }
        let text = message ?? L("投稿できませんでした", "Couldn\u{2019}t post")
        return needsEditing ? .failedNeedsEditing(text) : .failed(text)
    }
}

/// 輪の進み具合（ホームの自分の輪・案 B2「真鍮で満ちていく」）
enum PostUploadProgress {

    /// 送り終えた枚数。`uploadingIndex` は「何枚目を送っているか」（1から・0 は送っていない）
    static func done(uploadingIndex: Int, total: Int) -> Int {
        min(max(0, uploadingIndex - 1), total)
    }

    /// 持っている投稿から輪の段を決める。**送っている投稿があれば送信中**（失敗した残りより先に見せる）
    static func phase(_ jobs: [(sending: Bool, done: Int, total: Int, failure: String?)]) -> PostUploadCenter.Phase {
        let sending = jobs.filter(\.sending)
        if !sending.isEmpty {
            return .sending(done: sending.map(\.done).reduce(0, +), total: sending.map(\.total).reduce(0, +))
        }
        if let failure = jobs.first(where: { $0.failure != nil })?.failure { return .failed(message: failure) }
        return .idle
    }

    /// 輪の満ち具合（0〜1）。0枚目でも少しだけ点ける（止まって見えない・ストーリーと同じ 0.08）
    static func fraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return max(0.08, Double(done) / Double(total))
    }
}

/// ホームの自分の輪（`StoriesRow.uploadRing`）が出す段。**ストーリーと投稿のどちらを送っていても、同じ1つの輪**
/// （板 27「上がるまで、自分の輪の真鍮が時計回りに満ちていく」・案 B2）。送っている方を先に見せ、
/// 止まったら赤い輪と「送れませんでした」（押すと、止まった方の「もう一度送る」）
enum UploadRing {

    enum Failed: Equatable {
        case story
        case post
    }

    struct State: Equatable {
        /// 満ち具合（0〜1）
        let progress: Double
        /// 止まった方（送っている間は nil）
        let failed: Failed?
    }

    static func of(story: StoryUploadCenter.Phase, post: PostUploadCenter.Phase) -> State {
        var done = 0
        var total = 0
        var sending = false
        if case .sending(let d, let t) = story { done += d; total += t; sending = true }
        if case .sending(let d, let t) = post { done += d; total += t; sending = true }
        if sending {
            return State(progress: PostUploadProgress.fraction(done: done, total: total), failed: nil)
        }
        if case .failed = story { return State(progress: 1, failed: .story) }
        if case .failed = post { return State(progress: 1, failed: .post) }
        return State(progress: 1, failed: nil)
    }

    /// 輪の下の名前（案 B2「送信中…」）
    static func name(_ state: State) -> String {
        state.failed == nil ? L("送信中…", "Sending…") : L("送れませんでした", "Failed")
    }
}

/// 投稿の知らせの、場所で変える言い方（札 #710）。1行目（太い字）と2行目（小さな字）
struct PostedPlaceNotice: Equatable {
    let title: String
    let detail: String?

    /// 言い方を決める。どれにも当たらなければ nil（通常の「投稿しました」）
    ///
    /// - 行きたい場所に入れた場所で、**まだ知らせていない**場所の写真が上がった: 「行きたい場所に行けました」と場所の名前
    ///   （同じ場所の2枚目からは通常の知らせ・`WishVisitMemory`）
    /// - 写真の無い観光スポット（開いたときに0枚と読めていた・`UploadSpotTarget.announcesFirst`）に、その観光スポットの写真として
    ///   上がった: 「〇〇の最初の1枚になりました」（札 #710 の案7。行きたい場所より先に言う）
    static func make(posted: [Photo], wishKeys: Set<String>, spots: [OfficialSpot],
                     announced: Set<String>, spot: UploadSpotTarget? = nil,
                     postedToSpot: Int = 0) -> (notice: PostedPlaceNotice, wishKey: String?)? {
        let hit = WishVisit.notice(posted: posted, keys: wishKeys, spots: spots, announced: announced)
        if let spot, spot.announcesFirst, postedToSpot > 0 {
            return (PostedPlaceNotice(title: FirstPhoto.postedTitle(spot.name), detail: FirstPhoto.postedDetail), hit?.key)
        }
        if let hit {
            return (PostedPlaceNotice(title: WishVisit.noticeTitle, detail: hit.name), hit.key)
        }
        return nil
    }
}
