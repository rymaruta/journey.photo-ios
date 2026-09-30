import Foundation
import Combine
// 背面に回っても送り終えるまで少し待ってもらう（`beginBackgroundTask`）
import UIKit

/// **ストーリーを裏で送る係**（板 27「投稿した直後——上がるまで自分の輪が進み具合を示す」）。
///
/// 以前は投稿画面の中で送り終えるまで待ち、その間は画面を閉じられなかった
/// （`interactiveDismissDisabled`）。いまは「ストーリーに投稿」で画面を閉じ、
/// ここが順に送る。ホームの自分の輪は `phase` を見て進み具合と「送信中…」を出す。
///
/// 🔴 **途中で失敗したら、そこで止める**（投稿画面にあった決まりをそのまま移した）。
/// 残りを出し続けると「何本出たのか」が誰にも分からなくなる。出たぶんは残し、
/// **送れなかった残りは捨てずに持つ**——輪から「もう一度送る」か「やめる」を選ぶ。
///
/// 🔴 **送り終えていない並びは端末にも書く**（`directory`）。以前はメモリだけで、
/// 送っている途中にアプリを強制終了すると投稿が黙って消えた。起動し直したら
/// 「送れませんでした」として戻し、輪から送り直すかやめるかを選ばせる
/// （黙って送り直さない——閉じた人が「出したつもりか」は分からない）。
@MainActor
final class StoryUploadCenter: ObservableObject {

    static let shared = StoryUploadCenter(directory: defaultDirectory, keepsAliveInBackground: true)

    /// 1本ぶん。**焼き込み済みの画像**を持つ（文字の配置は投稿画面の中の話）
    struct Job: Identifiable {
        let id: UUID
        let imageData: Data
        let caption: String
        let location: String
        let coords: Photo.Coords?
        let song: Photo.Song?
        let durationSec: Int
        let archive: Bool
        /// 返信を受けるか（切ったときだけサーバーへ `false` を送る）
        let allowReplies: Bool
        /// 写真の上にデータで置くもの（投票と、そのときのひとこと・`StoryPostText.list`）。
        /// 無ければ送らない
        let texts: [StoryPostText]?
        /// 曲の札をこの写真に焼き込んだか（見る画面の ♪ の行を出さない）
        let songOnPhoto: Bool
        /// 上げ終えた画像（送り直しで二重に出さないための目印・`StoryService.post`）
        var uploaded: StoryService.UploadedMedia?

        init(id: UUID = UUID(), imageData: Data, caption: String, location: String,
             coords: Photo.Coords?, song: Photo.Song?, durationSec: Int, archive: Bool,
             allowReplies: Bool = true, texts: [StoryPostText]? = nil,
             songOnPhoto: Bool = false,
             uploaded: StoryService.UploadedMedia? = nil) {
            self.id = id
            self.imageData = imageData
            self.caption = caption
            self.location = location
            self.coords = coords
            self.song = song
            self.durationSec = durationSec
            self.archive = archive
            self.allowReplies = allowReplies
            self.texts = texts
            self.songOnPhoto = songOnPhoto
            self.uploaded = uploaded
        }
    }

    /// 1本を送る手順。2つ目の引数で「上げ終えた画像」を係に覚えさせる（nil で忘れる）
    typealias Send = (Job, @escaping @MainActor (StoryService.UploadedMedia?) -> Void) async throws -> Void

    enum Phase: Equatable {
        case idle
        /// `done` 本出して、全部で `total` 本
        case sending(done: Int, total: Int)
        /// 止まった。`remaining` 本が手元に残っている
        case failed(message: String, remaining: Int)
    }

    @Published private(set) var phase: Phase = .idle
    /// **全部送り終えた回数。** 輪はこれを見て一覧を読み直す
    /// （回数で伝えるのは `TabRouter` と同じ理由——真偽値だと2回目が効かない）
    @Published private(set) var finished = 0

    private var pending: [Job] = []
    private var total = 0
    private var send: Send?
    private var onAllSent: (() -> Void)?
    private var onFailed: ((String) -> Void)?
    /// 🔴 **誰の投稿か。** 係はアプリに1つなので、ログインし直した別の人の
    /// トークンで前の人の写真を出してしまわないよう、送る前に毎回照らす
    private var ownerId: String?
    private var currentUserId: (() -> String?)?
    /// 🔴 **捨てた並びの送信を続けさせない番号。** 送信の返事を待つ間に捨てる
    /// （ログアウト・やめる）と、戻ってきた `run` が空の並びから取り出して落ちる
    private var generation = 0

    /// 起動し直して戻した並びを送るための手順（`configure`）。
    /// 戻した並びには投稿画面が渡した手順が無いので、アプリが起動時に渡す
    private var defaultSend: Send?
    private var defaultCurrentUserId: (() -> String?)?
    /// 捨てた並びの、上げ終えていた画像を片づける
    private var discardUpload: ((String) async -> Void)?
    /// 戻した並びを送り終えたときに下書きを片づける（`draftToClear` を渡す）。
    /// 戻した並びには投稿画面の `onAllSent` が無いので、アプリが起動時に渡す
    private var clearDraft: ((String) -> Void)?
    /// 送り終えたら片づける下書きの印（`StoryDraftStore.Draft.savedAt`）。
    /// 端末にも書く——書かないと、起動し直して送った回に下書きが残り、
    /// 「続きから」で同じ投稿をもう1本出しやすい
    private var draftToClear: String?

    /// 送り終えていない並びを書く場所。nil ならメモリだけ（試験）
    private let directory: URL?
    private let keepsAliveInBackground: Bool

    /// 送っている最中か、失敗した残りを持っているか（新しい投稿を受けない）
    var isBusy: Bool { phase != .idle }

    /// いま送っている（送れずに持っている）並びの元の下書きの印。投稿画面はこの下書きに
    /// 「続きから」を出さない——送っている最中の下書きを戻すと、同じ投稿を二重に出しやすい
    var pendingDraftStamp: String? { draftToClear }

    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("story-uploads", isDirectory: true)
    }

    init(directory: URL? = nil, keepsAliveInBackground: Bool = false) {
        self.directory = directory
        self.keepsAliveInBackground = keepsAliveInBackground
        restore()
    }

    /// 起動し直して戻した並びを送る手順を渡す（アプリの起動時に1回）
    func configure(currentUserId: @escaping () -> String?,
                   send: @escaping Send,
                   discardUpload: @escaping (String) async -> Void,
                   clearDraft: @escaping (String) -> Void = { _ in }) {
        defaultCurrentUserId = currentUserId
        defaultSend = send
        self.discardUpload = discardUpload
        self.clearDraft = clearDraft
    }

    /// 送り始める。**前の投稿が片付いていなければ受けない**（false）——
    /// 2つの並びが混ざると、どれが出たのか分からなくなる
    @discardableResult
    func start(_ jobs: [Job],
               ownerId: String,
               currentUserId: @escaping () -> String?,
               draftToClear: String? = nil,
               send: @escaping Send,
               onAllSent: @escaping () -> Void = {},
               onFailed: @escaping (String) -> Void = { _ in }) -> Bool {
        guard !isBusy, !jobs.isEmpty, !ownerId.isEmpty else { return false }
        pending = jobs
        self.draftToClear = draftToClear
        total = jobs.count
        self.ownerId = ownerId
        self.currentUserId = currentUserId
        self.send = send
        self.onAllSent = onAllSent
        self.onFailed = onFailed
        // 🔴 **その場で「送信中」にする。** 裏の `Task` が動き出すまで `.idle` のままだと、
        // その隙の二度押しをもう1本として受けてしまう（テストで捕まえた）。
        // 輪もこの瞬間から「送信中…」を出せる
        phase = .sending(done: 0, total: total)
        persist(writingImages: true)
        Task { await run() }
        return true
    }

    /// 失敗した残りをもう一度送る
    func retry() {
        guard case .failed = phase, !pending.isEmpty else { return }
        phase = .sending(done: total - pending.count, total: total)
        Task { await run() }
    }

    /// 失敗した残りを捨てる（出せたぶんはそのまま）。
    /// **上げ終えていた画像も片づける**（使われている鍵はサーバーが消さない）
    func discard() {
        guard case .failed = phase else { return }
        let keys = pending.compactMap { $0.uploaded?.key }
        if let discardUpload, !keys.isEmpty {
            Task {
                for key in keys { await discardUpload(key) }
            }
        }
        reset()
    }

    /// ログインしている人が変わった（ログアウト・別の人でログイン・退会）。
    /// **投稿した本人でなくなったら、送っている最中でも残りを捨てる**
    func userChanged(to userId: String?) {
        guard isBusy, userId != ownerId else { return }
        reset()
    }

    private func run() async {
        guard let send = send ?? defaultSend else { return }
        let currentUserId = currentUserId ?? defaultCurrentUserId
        let myGeneration = generation
        phase = .sending(done: total - pending.count, total: total)
        // **背面に回っても、送り終えるまで少し待ってもらう。** 待ってもらわないと、
        // 送っている途中にホームへ戻っただけで通信が止まり、失敗になりやすかった
        let background = beginBackground()
        defer { endBackground(background) }
        while let job = pending.first {
            // **本人のままか、送る前に毎回照らす**（別の人のトークンで出さない）
            let current = currentUserId?()
            // **誰か分からない（ログインしていない・圏外で起動して確かめられない）
            // ときは捨てない。** 残したまま止める——捨てると、圏外で起動して
            // 「もう一度送る」を押しただけで、送信待ちが知らせも無く消えていた。
            // 本人に戻れば送り直せ、別の人が入れば `userChanged` が捨てる
            guard let current else {
                // 何本出たかは残す（輪の「もう一度送る」の文言に出る）。
                // **知らせ（トースト）は出さない**——本当のログアウトでは直後に
                // `userChanged(nil)` が残りを捨てるので、「送り直して」と言うと嘘になる
                let message = StoryQueue.partialFailure(
                    posted: total - pending.count, total: total,
                    reason: L("ログインしてから、もう一度送ってください",
                              "Sign in, then try sending again"))
                phase = .failed(message: message, remaining: pending.count)
                return
            }
            guard current == ownerId else {
                reset()
                return
            }
            do {
                let jobId = job.id
                try await send(job) { [weak self] media in
                    // 捨てた並び・別の1本には書かない
                    guard let self, myGeneration == self.generation,
                          let i = self.pending.firstIndex(where: { $0.id == jobId }) else { return }
                    self.pending[i].uploaded = media
                    self.persist(writingImages: false)
                }
                // 待っている間に捨てられた並びなら、ここで手を引く
                guard myGeneration == generation else { return }
                pending.removeFirst()
                phase = .sending(done: total - pending.count, total: total)
                removeImage(of: job)
                persist(writingImages: false)
            } catch {
                guard myGeneration == generation else { return }
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? L("投稿できませんでした", "Couldn't post")
                let message = StoryQueue.partialFailure(posted: total - pending.count,
                                                        total: total, reason: reason)
                phase = .failed(message: message, remaining: pending.count)
                // **失敗は知らせる。** ホームの輪が見えない画面にいる人にも届くように
                onFailed?(message)
                return
            }
        }
        if let onAllSent {
            onAllSent()
        } else if let draftToClear {
            // 起動し直して戻した並び（投稿画面の片づけが無い）
            clearDraft?(draftToClear)
        }
        reset()
        finished += 1
    }

    private func reset() {
        generation += 1
        pending = []
        total = 0
        send = nil
        onAllSent = nil
        onFailed = nil
        ownerId = nil
        currentUserId = nil
        draftToClear = nil
        phase = .idle
        clearStorage()
    }

    // MARK: - 背面

    /// 背面での猶予（`beginBackgroundTask`）。送る回ごとに札を分ける
    /// ——捨てた回の片づけが、次の回の猶予を返してしまわないように
    private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]

    /// 背面での猶予をもらう。返すのは札（要らなくなったら `endBackground` に渡す）
    private func beginBackground() -> UUID? {
        guard keepsAliveInBackground else { return nil }
        let token = UUID()
        // 猶予が切れたら返す（返さないとアプリごと止められる）。送っている1本は
        // 失敗として戻り、並びは端末に残っているので次に送り直せる
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "story-upload") { [weak self] in
            MainActor.assumeIsolated { self?.endBackground(token) }
        }
        guard identifier != .invalid else { return nil }
        backgroundTasks[token] = identifier
        return token
    }

    private func endBackground(_ token: UUID?) {
        guard let token, let identifier = backgroundTasks.removeValue(forKey: token) else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }

    // MARK: - 端末に書く

    /// 並びの記録（画像は別のファイル）
    private struct Manifest: Codable {
        struct Entry: Codable {
            let id: UUID
            let caption: String
            let location: String
            let latitude: Double?
            let longitude: Double?
            let song: Photo.Song?
            let durationSec: Int
            let archive: Bool
            /// 前の版の並びには無い（nil＝返信を受ける。切ったときだけ `false` を書く）
            let allowReplies: Bool?
            let uploaded: StoryService.UploadedMedia?
            /// 写真の上にデータで置くもの（投票など）。**書かないと、途中で落ちて戻したときに
            /// 投票の無いストーリーとして出た**（274951f のレビュー）。前の版には無い
            let texts: [StoryPostText]?
        }
        let ownerId: String
        let total: Int
        let jobs: [Entry]
        /// 前の版には無い（nil＝片づける下書きなし）
        let draftToClear: String?
    }

    private var manifestURL: URL? { directory?.appendingPathComponent("queue.json") }

    private func imageURL(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// いまの並びを書く。画像は並びを受けたときに1回だけ書く（`writingImages`）
    private func persist(writingImages: Bool) {
        guard let directory, let manifestURL, let ownerId, !pending.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if writingImages {
                for job in pending {
                    guard let url = imageURL(job.id) else { continue }
                    try job.imageData.write(to: url, options: .atomic)
                }
            }
            let manifest = Manifest(ownerId: ownerId, total: total, jobs: pending.map { job in
                Manifest.Entry(id: job.id, caption: job.caption, location: job.location,
                               latitude: job.coords?.lat, longitude: job.coords?.lng,
                               song: job.song, durationSec: job.durationSec,
                               archive: job.archive, allowReplies: job.allowReplies ? nil : false,
                               uploaded: job.uploaded, texts: job.texts)
            }, draftToClear: draftToClear)
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            // 書けなくても送信は続ける（メモリの並びは生きている）。強制終了に
            // 備えられないだけ
        }
    }

    private func removeImage(of job: Job) {
        guard let url = imageURL(job.id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func clearStorage() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// 前の起動で送り終えていなかった並びを戻す。**画像が1本でも読めなければ、
    /// 読めたぶんだけを戻す**（読めないものは送りようがない）
    private func restore() {
        guard let manifestURL,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            clearStorage()
            return
        }
        let jobs: [Job] = manifest.jobs.compactMap { entry in
            guard let url = imageURL(entry.id), let image = try? Data(contentsOf: url) else { return nil }
            let coords: Photo.Coords? = {
                guard let lat = entry.latitude, let lng = entry.longitude else { return nil }
                return Photo.Coords(lat: lat, lng: lng)
            }()
            return Job(id: entry.id, imageData: image, caption: entry.caption, location: entry.location,
                       coords: coords, song: entry.song, durationSec: entry.durationSec,
                       archive: entry.archive, allowReplies: entry.allowReplies != false,
                       texts: entry.texts, uploaded: entry.uploaded)
        }
        guard !jobs.isEmpty, !manifest.ownerId.isEmpty else {
            clearStorage()
            return
        }
        // 出せた数は「記録の全部 − 記録に残っていた本数」。**画像を読めずに落とした
        // ぶんを「出せた」に数えない**（全部の数から一緒に引く）
        let posted = max(0, manifest.total - manifest.jobs.count)
        pending = jobs
        total = posted + jobs.count
        ownerId = manifest.ownerId
        draftToClear = manifest.draftToClear
        let reason = L("アプリが閉じられたため、送信が途中で止まりました",
                       "Sending stopped because the app was closed")
        phase = .failed(message: StoryQueue.partialFailure(posted: posted,
                                                           total: total, reason: reason),
                        remaining: jobs.count)
    }
}
