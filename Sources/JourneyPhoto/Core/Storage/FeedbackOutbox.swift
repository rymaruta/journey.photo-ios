import Foundation

/// 意見箱の1件（書いたもの）。**id は端末が作る UUID**——圏外で下書きに残して後で送っても、
/// 押し直しても、サーバーでは1件のまま（`feedback.ts` の冪等の鍵）
struct FeedbackDraft: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    /// どの画面から（英数字の短い名前。例 `settings`・`photo-detail`）
    let screen: String
    /// 返事が欲しいか（**ログインしている人だけ**意味を持つ。サーバーも宛先の無い人には約束しない）
    let wantsReply: Bool
    /// 書いた人（ログインしていなければ nil）。送るときにいまの人と比べる（`FeedbackOutbox.flush`）
    let userId: String?
    let createdAt: Date
    /// この時刻までは送らない（その日の上限に当たった下書き・次の JST の0時）。無ければいつでも送る
    var notBefore: Date?
    /// 利用者が欄に書いた字そのもの（添えた記録を含まない）。**端末の中だけ**で、送る本文（`text`）には入れない。
    /// 断られた下書きをシートに戻すときに使う（`FeedbackSheet`）
    var typed: String?
    /// 送り直しても届かない理由で断られたときの、画面に出した理由（2026-11-14 判断・1.1.91）。
    /// これがある下書きは**自動の送り直しに乗せない**（同じ理由で断られ続ける）。次にシートを開いたら欄に戻し、
    /// 利用者が「もう一度送る」を押したときだけ送る
    var rejectedReason: String?

    init(id: String = UUID().uuidString.lowercased(), text: String, screen: String,
         wantsReply: Bool, userId: String?, createdAt: Date = Date(), notBefore: Date? = nil,
         typed: String? = nil, rejectedReason: String? = nil) {
        self.id = id
        self.text = text
        self.screen = screen
        self.wantsReply = wantsReply
        self.userId = userId
        self.createdAt = createdAt
        self.notBefore = notBefore
        self.typed = typed
        self.rejectedReason = rejectedReason
    }
}

/// 意見箱の**送れていない下書き**（圏外で送れなかった分を、つながったら送る）。
///
/// 2026-11-11 判断（札 #546）: 置き場は Application Support の `feedback-outbox/`（`<id>.json` と添えた写真の
/// `<id>.jpg`）。UserDefaults に写真を入れない。送る前に**必ず先に書いてから**送る——送っている間に
/// アプリが閉じても書いたものが消えない。
///
/// 送り直すのは「起動してログインの確かめが済んだとき」「前面に戻ったとき」「電波が戻ったとき」（`JourneyPhotoApp`）。
/// 古すぎる・多すぎる下書きは送らずに捨てる（`maxAge`・`maxCount`）。
///
/// 2026-11-14 判断（1.1.91）: **断られた下書きも消さない。** 前は送り直しても届かない理由で断られたら消していて、
/// 書いた本文が端末のどこにも残らなかった。いまは理由（`rejectedReason`）を付けて残し、自動の送り直しには乗せず、
/// 次にシートを開いたら欄に戻す（`held(for:)`）。要らなければ利用者が欄を空にして閉じれば消える
struct FeedbackOutbox {

    /// 下書きを持っておく長さ（これより古いものは送らずに捨てる）
    static let maxAge: TimeInterval = 30 * 24 * 3600
    /// 持っておく件数（あふれたら古い順に捨てる）
    static let maxCount = 20

    let root: URL
    private let fileManager = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("feedback-outbox", isDirectory: true)
    }

    private func jsonURL(_ id: String) -> URL { root.appendingPathComponent("\(id).json") }
    private func photoURL(_ id: String) -> URL { root.appendingPathComponent("\(id).jpg") }

    /// id はファイル名になるので、UUID の形だけを通す（任意の文字列で外の場所を指させない）
    static func isValidId(_ id: String) -> Bool {
        id.count == 36 && id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    /// 書いて残す（送る前に呼ぶ）。写真は `ImagePreparer` を通した JPEG
    func save(_ draft: FeedbackDraft, photo: Data?) throws {
        guard Self.isValidId(draft.id) else { return }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        if let photo {
            try photo.write(to: photoURL(draft.id), options: .atomic)
        }
        try writeJSON(draft)
        trim()
    }

    private func writeJSON(_ draft: FeedbackDraft) throws {
        try JSONEncoder().encode(draft).write(to: jsonURL(draft.id), options: .atomic)
    }

    /// 残っている下書き（古い順）
    func all() -> [FeedbackDraft] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        let decoder = JSONDecoder()
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name in
                guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
                return try? decoder.decode(FeedbackDraft.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func photo(for id: String) -> Data? {
        guard Self.isValidId(id) else { return nil }
        return try? Data(contentsOf: photoURL(id))
    }

    func remove(_ id: String) {
        guard Self.isValidId(id) else { return }
        try? fileManager.removeItem(at: jsonURL(id))
        try? fileManager.removeItem(at: photoURL(id))
    }

    /// 断られて残っている下書きのうち、この人が書いたいちばん新しいもの（シートの欄に戻す）。
    /// **書いた人が違えば戻さない**（別の人の本文を見せない。ログインしていない回どうしは nil どうしで合わせる）
    func held(for userId: String?) -> FeedbackDraft? {
        all().last { $0.rejectedReason != nil && $0.userId == userId }
    }

    /// 断られて残っている下書きを、シートで書き直した中身に合わせる（閉じたとき）。写真を外していたら写真も消す
    func updateHeld(_ id: String, typed: String, wantsReply: Bool, photo: Data?) {
        guard Self.isValidId(id),
              let data = try? Data(contentsOf: jsonURL(id)),
              let old = try? JSONDecoder().decode(FeedbackDraft.self, from: data) else { return }
        let draft = FeedbackDraft(id: old.id, text: old.text, screen: old.screen, wantsReply: wantsReply,
                                  userId: old.userId, createdAt: old.createdAt, notBefore: old.notBefore,
                                  typed: typed, rejectedReason: old.rejectedReason)
        try? writeJSON(draft)
        if let photo {
            try? photo.write(to: photoURL(id), options: .atomic)
        } else {
            try? fileManager.removeItem(at: photoURL(id))
        }
    }

    /// 退会した人の下書きを消す（`AccountLocalData.remove`）
    func removeData(for userId: String) {
        for draft in all() where draft.userId == userId { remove(draft.id) }
    }

    /// 古すぎる・多すぎる下書きを捨てる
    func trim(now: Date = Date()) {
        let drafts = all()
        var kept: [FeedbackDraft] = []
        for draft in drafts {
            if now.timeIntervalSince(draft.createdAt) > Self.maxAge { remove(draft.id) } else { kept.append(draft) }
        }
        if kept.count > Self.maxCount {
            for draft in kept.prefix(kept.count - Self.maxCount) { remove(draft.id) }
        }
    }

    /// 送るときの口。**書いた人がいまもログインしているときだけ**ログインした人の口で送る。
    /// 人が替わった・ログアウトした回は、ログインしていない人の口で送る（返事は約束しない。
    /// 別の人のアカウントで前の人の意見を送らない）
    static func signedIn(_ draft: FeedbackDraft, currentUserId: String?) -> Bool {
        guard let author = draft.userId, let current = currentUserId else { return false }
        return author == current
    }

    /// 1件送った結果
    enum Outcome: Equatable {
        /// 届いた（下書きを消した）
        case sent
        /// 届いた。ただし**ログインが切れていたので、ログインしていない人の口で送った**＝返事は約束できない
        /// （返事が欲しいを選んでいた下書きだけ。シートでそう添える）
        case sentWithoutReply
        /// 本文は届いた。写真だけ送れなかった（下書きを消した。送り直すと本文が二重になる）
        case sentWithoutPhoto
        /// 届かなかった（圏外・時間切れ）。下書きに残した。電波が戻ったら送る
        case unreachable
        /// サーバーの一時的な不調。下書きに残した。次の機会に送る
        case serverBusy
        /// その日の上限。下書きに残し、次の JST の0時まで送らない
        case tomorrow
        /// 送り直しても届かない理由で断られた。**下書きは理由を付けて残した**（自動では送り直さない。
        /// シートに理由を出し、利用者が「もう一度送る」を押したときだけ送る・2026-11-14 判断）
        case held(String)

        /// 下書きに残し、**残りの送り直しもここで止める**か（圏外・混雑・その日の上限）。
        /// 断られた回（`held`）は残すが、その1件の事情なので後ろの分は続けて送る
        var isKept: Bool { self == .unreachable || self == .serverBusy || self == .tomorrow }
        /// 本文が届いたか
        var isDelivered: Bool { self == .sent || self == .sentWithoutReply || self == .sentWithoutPhoto }
    }

    /// 1件送る。送れたら消し、圏外・混雑・その日の上限なら残す。送り直しても届かない理由で断られたら、
    /// 理由を付けて残し（`held`）、失敗の種類・HTTP の状態・時刻だけを端末の記録に1行残す（`ExitTrail.keepFeedbackFailure`。
    /// 本文・利用者の情報は入れない。次の意見に添えられる）
    ///
    /// **ログインが切れていたら（トークンが無い・401）、その場でログインしていない人の口で送り直す**——
    /// 下書きの先頭に残したままにすると、ログインし直すまで後ろの分も全部詰まる
    func deliver(_ draft: FeedbackDraft, currentUserId: String?, now: Date = Date(),
                 trailDefaults: UserDefaults = .standard,
                 send: (FeedbackDraft, Data?, Bool) async throws -> Void) async -> Outcome {
        let photo = photo(for: draft.id)
        let signedIn = Self.signedIn(draft, currentUserId: currentUserId)
        var fellBack = false
        do {
            do {
                try await send(draft, photo, signedIn)
            } catch where signedIn && FeedbackService.failure(error) == .signedOut {
                fellBack = true
                try await send(draft, photo, false)
            }
            remove(draft.id)
            return fellBack && draft.wantsReply ? .sentWithoutReply : .sent
        } catch {
            if error is CancellationError { return .unreachable }
            switch FeedbackService.failure(error) {
            case .photoFailed:
                remove(draft.id)
                return .sentWithoutPhoto
            case .unreachable, .signedOut:
                return .unreachable
            case .serverBusy:
                return .serverBusy
            case .dailyLimit:
                var later = draft
                later.notBefore = FeedbackService.nextJSTMidnight(after: now)
                try? writeJSON(later)
                return .tomorrow
            case .rejected:
                let reason = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
                var held = draft
                held.rejectedReason = reason
                held.notBefore = nil
                try? writeJSON(held)
                let note = FeedbackService.failureNote(error)
                ExitTrail.keepFeedbackFailure(kind: note.kind, status: note.status, defaults: trailDefaults, now: now)
                return .held(reason)
            }
        }
    }

    /// 残っている下書きを古い順に送る。
    /// - 圏外・混雑ならそこで止める（全部を順に叩かない）
    /// - その日の上限の下書きは、待つ時刻（`notBefore`）まで飛ばす。上限に当たったら、その日はもう送らない
    /// - **断られた下書き（`rejectedReason`）は送らない**（同じ理由で断られ続ける。シートで利用者が送り直す）
    @discardableResult
    func flush(currentUserId: String?, now: Date = Date(), trailDefaults: UserDefaults = .standard,
               send: (FeedbackDraft, Data?, Bool) async throws -> Void) async -> Int {
        trim(now: now)
        var sent = 0
        for draft in all() {
            if draft.rejectedReason != nil { continue }
            if let notBefore = draft.notBefore, notBefore > now { continue }
            let outcome = await deliver(draft, currentUserId: currentUserId, now: now,
                                        trailDefaults: trailDefaults, send: send)
            if outcome.isKept { break }
            if outcome.isDelivered { sent += 1 }
        }
        return sent
    }
}

/// 送り直しを重ねて走らせない見張り（起動・前面に戻る・電波が戻るが同時に来る）
@MainActor
enum FeedbackOutboxRunner {
    private static var running = false

    static func flush(environment: AppEnvironment, userId: String?, outbox: FeedbackOutbox = FeedbackOutbox()) {
        // 断られた下書きだけなら走らせない（自動では送り直さない）
        guard !running, outbox.all().contains(where: { $0.rejectedReason == nil }) else { return }
        running = true
        let service = environment.feedback
        Task { @MainActor in
            defer { running = false }
            await outbox.flush(currentUserId: userId) { draft, photo, signedIn in
                try await service.send(draft, photo: photo, signedIn: signedIn)
            }
        }
    }
}
