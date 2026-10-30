import Foundation
import Combine

/// 下書きの一覧（投稿とストーリー・2026-10-29・#400「下書きを複数持つ」）。
///
/// 下書きそのものは前からの置き場（投稿 `UploadDraftStore`・ストーリー `StoryDraftStore`）の
/// `Slot.entry(ID)` に1件ずつ置く。ここは**その人の下書きを並べ・数え・まとめて扱う**だけ
/// （新しい置き場を作らない）。owner が決めたこと（Issue #400・モック 9JzQWmYxF14BmUiZ9yWbe8）:
///
/// 1. **投稿＋ストーリー合わせて `limit`（20）件。** 投稿の下書きは期限なし、ストーリーは保存から
///    `storyLifetime`（7日）で消える（2日前から一覧で「あと n 日」・通知は送らない）。いっぱいのときは
///    保存を出さず「下書きを整理する」へ——**黙って古いものを消して保存しない**
/// 2. 「下書き」は端末の書きかけだけを呼ぶ（マイページの非公開の写真の札は「非公開」）
/// 3. ログアウトでは消さない（人ごとの鍵で残る）。退会では消す（`AccountLocalData`）
///
/// 自動の書きかけ（`Slot.auto`・アプリが途中で終了した回）も一覧の先頭に出すが、**件数の上限には
/// 数えない**（本人が保存したものではない・モックの注記「別の枠なので件数の上限に数えない」）。
///
/// 削除は「元に戻す」が効くよう、**押した時点では記録も画像も消さない**——一覧から隠すだけ
/// （`hide`）。約6秒たつか一覧を閉じたら本当に消す（`finalize`）。途中でアプリが終了したら
/// 下書きは残る（消えるより安全な側に倒す）
@MainActor
final class DraftLibrary: ObservableObject {

    static let shared = DraftLibrary()

    /// 投稿＋ストーリー合わせて持てる件数（2026-10-29 owner 決定・#400）
    nonisolated static let limit = 20
    /// ストーリーの下書きが残る長さ（保存から7日・インスタのストーリーの下書きと同じ）
    nonisolated static let storyLifetime: TimeInterval = 7 * 24 * 60 * 60
    /// 「あと n 日」を出し始める残りの日数（2日前から）
    nonisolated static let warnDays = 2
    /// 削除のあと「元に戻す」を出しておく秒数（モックの約6秒）
    nonisolated static let undoSeconds: Double = 6

    enum Kind: String, Equatable, CaseIterable {
        case post, story
    }

    /// 一覧の1件（画面に出すものだけ）
    struct Entry: Identifiable, Equatable {
        /// 下書きの ID（`Slot.entry` の UUID）。自動の書きかけは `autoPostId`・`autoStoryId`
        let id: String
        let kind: Kind
        /// アプリが途中で終了した自動の書きかけ（件数に数えない・先頭に固定）
        let isAuto: Bool
        let savedAt: Date
        /// 保存した時刻の元の字（ストーリーの送信の印 `pendingDraftStamp` と比べる）
        let stamp: String
        /// 題（投稿は1枚目の題、ストーリーは写真の上の文字かひとこと）。無ければ空
        let title: String
        /// 撮影地（無ければ空）
        let place: String
        /// 写真の枚数（届いたか分からない写真は数えない——開き直しても戻さない）
        let photoCount: Int
        /// 読めない写真の枚数（画像のファイルが無い）
        let missingCount: Int
        /// 縮図に使う画像（読める最初の1枚）。無ければ nil（全部読めない）
        let cover: URL?
        /// 画像の大きさの合計（バイト）
        let bytes: Int64

        /// 読める写真の枚数（「残りの n 枚で続ける」）
        var readableCount: Int { max(0, photoCount - missingCount) }
    }

    nonisolated static let autoPostId = "auto-post"
    nonisolated static let autoStoryId = "auto-story"

    /// 一覧が描き直す合図（保存・削除・元に戻す）。押した回数で伝える（`TabRouter` と同じ理由）
    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    private let directory: URL?
    /// 削除を押して「元に戻す」を待っている下書き（一覧と件数から隠す）
    private(set) var hidden: Set<String> = []
    /// 今の時刻（試験で差し替える）
    var now: () -> Date = { Date() }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory
    }

    /// 置き場の入れ物（同じ defaults・directory を使う）
    private func uploadStore(_ slot: UploadDraftStore.Slot) -> UploadDraftStore {
        UploadDraftStore(defaults: defaults, directory: directory, slot: slot)
    }

    private func storyStore(_ slot: StoryDraftStore.Slot, userId: String) -> StoryDraftStore {
        let store = StoryDraftStore(defaults: defaults, directory: directory, slot: slot)
        store.bind(userId: userId)
        return store
    }

    /// 保存・削除のあとに呼ぶ（一覧と件数のバッジを描き直す）
    func noteChanged() { revision += 1 }

    /// 画像の置き場を読めるか（読めなければ一覧は「読めなかった」を出し、「0件」にしない・板 06）。
    /// まだ無い（一度も保存していない）のは読めることにする
    func storageReadable() -> Bool {
        let path = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).path
        guard FileManager.default.fileExists(atPath: path) else { return true }
        return FileManager.default.isReadableFile(atPath: path)
    }

    // MARK: 移す・期限

    /// 🔴 **前の版の「人ごとに1件」の下書きを新しい形に移し、期限の過ぎたストーリーの下書きを消す。**
    /// 一覧・件数を読む前に毎回呼ぶ（何度呼んでも同じ）。起動のときにも呼ぶ（`JourneyPhotoApp`）
    func prepare(for userId: String) {
        guard !userId.isEmpty else { return }
        uploadStore(.saved).migrateLegacySaved(for: userId, newId: Self.legacyEntryId(userId: userId, kind: .post))
        StoryDraftStore.migrateLegacySaved(for: userId, defaults: defaults,
                                           newId: Self.legacyEntryId(userId: userId, kind: .story))
        purgeExpiredStories(for: userId)
    }

    /// 保存から `storyLifetime` を過ぎたストーリーの下書き（自動の書きかけも）を消す。**知らせない**
    /// （owner 決定: 2日前から一覧で知らせるだけ・通知は送らない）。
    ///
    /// 2026-10-29 判断（見直し）: 端末の時計を先へ進めると、何件かが一度に消えうる。それでも今の仕様で足りるとした——
    /// ストーリーの下書きは一過性のもので、消える2日前から一覧の帯とマスで知らせており、時計を進めるのは本人の操作。
    /// 消すのは一覧・件数を読んだときと起動のときだけで、通知も送らない（owner 決定どおり）
    func purgeExpiredStories(for userId: String) {
        let current = now()
        for id in StoryDraftStore.entryIds(for: userId, defaults: defaults) {
            let store = storyStore(.entry(id), userId: userId)
            if let draft = store.draft, Self.isExpired(stamp: draft.savedAt, now: current) { store.clear() }
        }
        let auto = storyStore(.auto, userId: userId)
        if let draft = auto.draft, Self.isExpired(stamp: draft.savedAt, now: current) { auto.clear() }
    }

    /// ストーリーの下書きの保存の時刻の書き方（**ミリ秒まで**・2026-10-29 の見直し）。時刻は送り終えた下書きを
    /// 片づける印（`clearStory(stamp:)`・`StoryUploadCenter.pendingDraftStamp`）にもなるので、秒までだと
    /// 同じ秒に保存した別の下書き（複製・別の下書きとして保存）を巻き込んで消した。読む側は両方読める（`storyDate`）
    nonisolated static func storyStamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// 前の版の1件を移すときの ID（**利用者 ID から決まる**・2026-10-29 の見直し）。移す処理が二つ同時に
    /// 走っても（起動と画面）同じ鍵に書くので、1件が2件にならない
    nonisolated static func legacyEntryId(userId: String, kind: Kind) -> String {
        // FNV-1a（64bit）を種を替えて2回 → 16バイト → UUID の形
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash: UInt64 = 0xcbf29ce484222325 ^ seed
            for byte in "\(kind.rawValue):\(userId)".utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let a = fnv(0), b = fnv(0x9e3779b97f4a7c15)
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: a >> (8 * UInt64($0))) }
            + (0..<8).map { UInt8(truncatingIfNeeded: b >> (8 * UInt64($0))) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50   // 版（名前から作った印）
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return uuid.uuidString
    }

    /// ストーリーの下書きの保存の時刻（秒まで・ミリ秒あり・なしの両方）
    nonisolated static func storyDate(_ stamp: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: stamp) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: stamp)
    }

    /// 期限を過ぎたか。読めない時刻は過ぎていないことにする（黙って消さない）
    nonisolated static func isExpired(stamp: String, now: Date) -> Bool {
        guard let saved = storyDate(stamp) else { return false }
        return now.timeIntervalSince(saved) >= storyLifetime
    }

    /// 消えるまでの日数（切り上げ・「あと n 日」）。投稿・読めない時刻は nil
    nonisolated static func daysLeft(kind: Kind, savedAt: Date, now: Date) -> Int? {
        guard kind == .story else { return nil }
        let remaining = savedAt.addingTimeInterval(storyLifetime).timeIntervalSince(now)
        return max(1, Int((remaining / 86_400).rounded(.up)))
    }

    /// 「あと n 日」を出すか（2日前から）
    nonisolated static func showsDaysLeft(_ days: Int?) -> Bool {
        guard let days else { return false }
        return days <= warnDays
    }

    // MARK: 並べる・数える

    /// その人の下書き。**自動の書きかけを先頭、あとは保存の新しい順**。隠している（削除を待つ）もの・
    /// 送っている最中のストーリーの下書き（`sendingStoryStamp`）は出さない——送っている下書きを
    /// 開き直すと同じ投稿を二重に出しやすい（`StoryComposerView.asksRestore` と同じ理由）
    func entries(for userId: String, sendingStoryStamp: String? = nil) -> [Entry] {
        guard !userId.isEmpty else { return [] }
        prepare(for: userId)
        var result: [Entry] = []
        let uploads = uploadStore(.saved)
        for id in uploads.entryIds(for: userId) where !hidden.contains(id) {
            let store = uploads.sibling(.entry(id))
            if let draft = store.draft(for: userId) { result.append(postEntry(id: id, draft: draft, store: store)) }
        }
        if !hidden.contains(Self.autoPostId) {
            let auto = uploads.sibling(.auto)
            if let draft = auto.draft(for: userId), !UploadDraftStore.restorable(draft).items.isEmpty {
                result.append(postEntry(id: Self.autoPostId, draft: draft, store: auto, isAuto: true))
            }
        }
        for id in StoryDraftStore.entryIds(for: userId, defaults: defaults) where !hidden.contains(id) {
            let store = storyStore(.entry(id), userId: userId)
            if let draft = store.draft, draft.savedAt != sendingStoryStamp {
                result.append(storyEntry(id: id, draft: draft, store: store))
            }
        }
        if !hidden.contains(Self.autoStoryId) {
            let auto = storyStore(.auto, userId: userId)
            if let draft = auto.draft { result.append(storyEntry(id: Self.autoStoryId, draft: draft, store: auto, isAuto: true)) }
        }
        return Self.sorted(result)
    }

    /// 並べ方（自動の書きかけを先頭・あとは保存の新しい順・同じ時刻は ID の順）
    nonisolated static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            if a.isAuto != b.isAuto { return a.isAuto }
            if a.savedAt != b.savedAt { return a.savedAt > b.savedAt }
            return a.id < b.id
        }
    }

    /// 上限に数える件数（自動の書きかけは数えない）。
    ///
    /// 🔴 **削除の「元に戻す」を待っている下書きも数える**（2026-10-29 の見直し）。数えないと、待っている間に
    /// 新しく保存してから「元に戻す」を押して 21 件になった。空くのは本当に消したとき（約6秒後か一覧を閉じたとき）
    func count(for userId: String) -> Int {
        guard !userId.isEmpty else { return 0 }
        prepare(for: userId)
        let posts = uploadStore(.saved).entryIds(for: userId).count
        let stories = StoryDraftStore.entryIds(for: userId, defaults: defaults).count
        return posts + stories
    }

    /// 種類ごとの件数（「投稿する」のシートのバッジ）
    func count(for userId: String, kind: Kind) -> Int {
        guard !userId.isEmpty else { return 0 }
        prepare(for: userId)
        switch kind {
        case .post: return uploadStore(.saved).entryIds(for: userId).filter { !hidden.contains($0) }.count
        case .story:
            return StoryDraftStore.entryIds(for: userId, defaults: defaults).filter { !hidden.contains($0) }.count
        }
    }

    /// 画面に出す件数（マイページの「下書き」の枠のバッジ・枠を出すか）。自動の書きかけと、削除の「元に戻す」を
    /// 待っているものは数えない（2026-10-30 判断 #408: 枠の長押しで消したら、バッジと枠をすぐ減らす。
    /// 上限の数え方 `count(for:)` は待っているものも数えたまま）
    func shownCount(for userId: String) -> Int {
        count(for: userId, kind: .post) + count(for: userId, kind: .story)
    }

    /// いっぱいか（新しい下書きを保存できない）
    func isFull(for userId: String) -> Bool { count(for: userId) >= Self.limit }

    nonisolated static func isFull(count: Int) -> Bool { count >= limit }

    private func postEntry(id: String, draft: UploadDraftStore.Draft, store: UploadDraftStore,
                           isAuto: Bool = false) -> Entry {
        let items = UploadDraftStore.restorable(draft).items
        let present = store.presentItems(items)
        let title = items.lazy.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        let place = items.lazy.map { $0.location.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? draft.spot?.name ?? ""
        return Entry(id: id, kind: .post, isAuto: isAuto,
                     savedAt: UploadDraftStore.savedDate(draft.savedAt) ?? .distantPast, stamp: draft.savedAt,
                     title: title, place: place, photoCount: items.count,
                     missingCount: items.count - present.count,
                     cover: present.first.map(store.imageURL),
                     bytes: present.reduce(0) { $0 + Self.fileSize(store.imageURL($1)) })
    }

    private func storyEntry(id: String, draft: StoryDraftStore.Draft, store: StoryDraftStore,
                            isAuto: Bool = false) -> Entry {
        let shots = draft.shots
        let present = shots.filter { FileManager.default.fileExists(atPath: store.imageURL($0).path) }
        return Entry(id: id, kind: .story, isAuto: isAuto,
                     savedAt: Self.storyDate(draft.savedAt) ?? .distantPast, stamp: draft.savedAt,
                     title: Self.storyTitle(draft), place: draft.location.trimmingCharacters(in: .whitespacesAndNewlines),
                     photoCount: shots.count, missingCount: shots.count - present.count,
                     cover: present.first.map(store.imageURL),
                     bytes: present.reduce(0) { $0 + Self.fileSize(store.imageURL($1)) })
    }

    /// ストーリーの下書きの題: 1枚目に置いた文字、無ければひとこと（1行目）
    nonisolated static func storyTitle(_ draft: StoryDraftStore.Draft) -> String {
        let overlay = draft.shots.lazy.flatMap(\.overlays).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let text = overlay ?? draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.split(separator: "\n", omittingEmptySubsequences: true).first ?? "")
    }

    /// ファイルの大きさ（大きさだけを読む——時刻は読まない。プライバシーの申告の要る口を使わない）
    nonisolated static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    // MARK: 消す・元に戻す・複製

    /// 削除を押した（**一覧から隠すだけ**・`finalize` まで記録も画像も残す）
    func hide(_ ids: [String]) {
        hidden.formUnion(ids)
        noteChanged()
    }

    /// 「元に戻す」（隠していたものを一覧に戻す。消していないので元の位置に戻る）
    func undo(_ ids: [String]) {
        hidden.subtract(ids)
        noteChanged()
    }

    /// 隠していた下書きを本当に消す（記録と画像）。「元に戻す」の時間が過ぎた・一覧を閉じた
    func finalize(_ ids: [String], for userId: String) {
        let pending = ids.filter { hidden.contains($0) }
        guard !pending.isEmpty else { return }
        for id in pending { remove(id, for: userId) }
        hidden.subtract(pending)
        noteChanged()
    }

    /// 1件を消す（記録と画像）。投稿でもストーリーでも、ID から置き場を決める
    func remove(_ id: String, for userId: String) {
        guard !userId.isEmpty else { return }
        switch id {
        case Self.autoPostId: uploadStore(.auto).clear(for: userId)
        case Self.autoStoryId: storyStore(.auto, userId: userId).clear()
        default:
            let upload = uploadStore(.entry(id))
            if upload.draft(for: userId) != nil {
                upload.clear(for: userId)
            } else {
                storyStore(.entry(id), userId: userId).clear()
            }
        }
    }

    /// 送り終えたストーリーの元の下書きを片づける（`StoryUploadCenter` の `clearDraft`・起動し直して
    /// 送り終えたとき）。印（保存した時刻）が同じ下書きだけ——送っている間に保存し直したものは消さない
    func clearStory(stamp: String, for userId: String) {
        guard !userId.isEmpty else { return }
        for id in StoryDraftStore.entryIds(for: userId, defaults: defaults) {
            let store = storyStore(.entry(id), userId: userId)
            if store.draft?.savedAt == stamp { store.clear() }
        }
        noteChanged()
    }

    /// その印（保存した時刻）のストーリーの下書きの ID（自動の書きかけが開いていた下書きを探す・`basedOn`）
    func storyEntryId(stamp: String, for userId: String) -> String? {
        StoryDraftStore.entryIds(for: userId, defaults: defaults).first { id in
            storyStore(.entry(id), userId: userId).draft?.savedAt == stamp
        }
    }

    /// 複製（同じ写真・同じ欄の新しい1件）。**画像も写しを作る**——片方を消しても、もう片方は開ける。
    /// いっぱいなら作らない。読めない写真・届いたか分からない写真は写さない
    /// - Returns: 新しい下書きの ID（作れなかったら nil）
    @discardableResult
    func duplicate(_ id: String, kind: Kind, for userId: String, newId: String = UUID().uuidString) -> String? {
        guard !userId.isEmpty, !isFull(for: userId) else { return nil }
        let ok: Bool
        switch kind {
        case .post:
            let source = id == Self.autoPostId ? uploadStore(.auto) : uploadStore(.entry(id))
            guard var draft = source.draft(for: userId) else { return nil }
            let items = source.presentItems(UploadDraftStore.restorable(draft).items)
            let inputs: [UploadDraftStore.ItemInput] = items.compactMap { item in
                guard let data = try? Data(contentsOf: source.imageURL(item)) else { return nil }
                var copy = item
                copy.key = nil
                copy.inFlight = nil
                copy.savedKey = nil
                return UploadDraftStore.ItemInput(imageData: data, item: copy)
            }
            guard !inputs.isEmpty else { return nil }
            draft.savedAt = UploadDraftStore.savedAtString(now())
            draft.entryId = nil
            ok = uploadStore(.entry(newId)).save(inputs, fields: draft, for: userId)
        case .story:
            let source = id == Self.autoStoryId ? storyStore(.auto, userId: userId) : storyStore(.entry(id), userId: userId)
            guard let draft = source.draft else { return nil }
            let inputs: [StoryDraftStore.ShotInput] = draft.shots.compactMap { shot in
                guard let data = try? Data(contentsOf: source.imageURL(shot)) else { return nil }
                return StoryDraftStore.ShotInput(imageData: data, fileName: shot.fileName, contentType: shot.contentType,
                                                 coords: shot.coords, overlays: shot.overlays,
                                                 framing: shot.framing, vote: shot.vote)
            }
            guard !inputs.isEmpty else { return nil }
            ok = storyStore(.entry(newId), userId: userId).save(
                shots: inputs, caption: draft.caption, location: draft.location, song: draft.song,
                durationSec: draft.durationSec, archive: draft.archive == true,
                allowReplies: draft.allowReplies != false,
                savedAt: Self.storyStamp(now()))
        }
        guard ok else { return nil }
        noteChanged()
        return newId
    }

    /// 合計の大きさ（一覧の上の帯「n MB」）。四捨五入した MB（1 MB 未満でも画像があれば 1）
    nonisolated static func megabytes(_ entries: [Entry]) -> Int {
        let bytes = entries.reduce(Int64(0)) { $0 + $1.bytes }
        guard bytes > 0 else { return 0 }
        return max(1, Int((Double(bytes) / 1_000_000).rounded()))
    }
}

/// 下書きの一覧の表示（格子／行）を覚える（2026-10-29・#400 の「選んだほうを覚える」）。
/// 人ごと・端末だけ。退会で消す（`AccountLocalData`）
struct DraftViewPreference {
    enum Layout: String, Equatable { case grid, rows }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static let keyPrefix = "journey-photo-drafts-layout"

    private func key(_ userId: String?) -> String { "\(Self.keyPrefix):\(userId ?? "")" }

    /// 覚えている表示（既定は格子・owner「インスタみたいに3かける3で」）
    func layout(for userId: String?) -> Layout {
        defaults.string(forKey: key(userId)).flatMap(Layout.init(rawValue:)) ?? .grid
    }

    func set(_ layout: Layout, for userId: String?) {
        defaults.set(layout.rawValue, forKey: key(userId))
    }

    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(userId))
    }
}
