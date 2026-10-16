import Foundation

/// 投稿の下書き（`UploadDraftStore`）の決まり。画面を持たない（試験で確かめる・2026-10-11）。
///
/// - 閉じる確認（×）に「下書きに保存」を足す。出せないときは理由を言う
/// - 開いたときに「下書きを続けますか？」を尋ねる
/// - 投稿が上がった写真は1枚ずつ下書きから外す（`UploadViewModel.draftKeys` の注記）
///
/// **「捨てる」という言い方は使わない**（owner の好み・2026-10-09。ストーリーの下書きと同じ）。
/// 開いたときの問いの答えは「続ける」と「下書きを削除」
enum UploadDraftRules {

    /// 下書きに保存できない理由
    enum SaveBlock: Equatable {
        /// 写真が無い（下書きは写真ごとの題・説明を残すもの。写真の無い下書きは作らない）
        case noPhotos
        /// 写真を読み込んでいる・カメラの1枚を整えている（読みかけの写真が落ちた下書きを作らない）
        case loading
        /// 送っている・送りかけの写真がある（`visibilityLocked`）。下書きから送り直すと鍵が変わり、
        /// 前の送信が届いていたら同じ写真が2枚になる
        case sending
        /// ログインしていない（人ごとの下書きなので持ち主が要る）
        case signedOut
    }

    /// 保存できない理由。保存できるなら nil（先に当たったものを返す）
    static func saveBlock(hasPhotos: Bool, loading: Bool, sending: Bool, signedIn: Bool) -> SaveBlock? {
        if !signedIn { return .signedOut }
        if !hasPhotos { return .noPhotos }
        if loading { return .loading }
        if sending { return .sending }
        return nil
    }

    /// 閉じる確認の中身
    struct CloseDialog: Equatable {
        let title: String
        /// 「下書きに保存」を出すか
        let canSave: Bool
        let message: String
    }

    /// 閉じる確認の題・「下書きに保存」を出すか・説明。
    /// - Parameters:
    ///   - block: 保存できない理由（`saveBlock`）
    ///   - replacesOther: **開き直していない**前の下書きがある（保存すると置き換わる）
    ///   - restored: この画面で下書きを開き直した（「投稿をやめる」でも前の下書きは残る）
    ///   - unsure: 開き直した写真に、届いたか分からないものがある（下書きから外れる）
    static func closeDialog(block: SaveBlock?, replacesOther: Bool, restored: Bool,
                            unsure: Bool = false) -> CloseDialog {
        let unsureNote = unsure
            ? L("届いたか分からない写真は、二重に投稿しないよう下書きから外します。",
                "Photos that may have already been sent are taken out of the draft so they aren't posted twice. ")
            : ""
        let keeps = restored
            ? unsureNote + L("投稿をやめても、前に保存した下書きの残りは残ります。",
                             "If you stop, the rest of the draft you saved earlier stays.")
            : L("投稿をやめると、選んだ写真と書いた題・説明は残りません。",
                "If you stop, the photos you picked and what you wrote won't be kept.")
        guard let block else {
            let replace = replacesOther
                ? L("前の下書きは置き換わります（下書きは1件だけです）。", "This replaces your earlier draft (only one is kept). ")
                : ""
            return CloseDialog(
                title: L("下書きに保存しますか？", "Save as a draft?"), canSave: true,
                message: replace + L("下書きはこの端末にだけ残ります。", "Drafts stay on this device only. ") + keeps)
        }
        let reason: String
        switch block {
        case .noPhotos, .signedOut:
            reason = ""
        case .loading:
            reason = L("写真を読み込んでいる間は下書きに保存できません。保存するなら「書き続ける」を押して、読み込み終わるまでお待ちください。",
                       "You can't save a draft while photos are loading. To save, tap Keep editing and wait for them to finish. ")
        case .sending:
            reason = L("送りかけの写真があるため、下書きに保存できません。",
                       "Some photos are partway sent, so this can't be saved as a draft. ")
        }
        return CloseDialog(title: L("投稿をやめて閉じますか？", "Stop this post?"), canSave: false,
                           message: reason + keeps)
    }

    /// 開いたときに「下書きを続けますか？」を尋ねるか。**何かを持って開いた回は尋ねない**
    /// （旅の写真・構図を重ねて撮った1枚・今日のテーマのタグ・撮影スポット——それを投稿しに来た人に、
    /// 前の写真や欄を混ぜない。戻すとテーマのタグやスポットの紐付けを下書きの値で上書きする・2026-10-11）
    static func asksRestore(hasStoredDraft: Bool, opensWithContent: Bool, alreadyAsked: Bool) -> Bool {
        hasStoredDraft && !opensWithContent && !alreadyAsked
    }

    /// 投稿の画面を開いたときにすること（2026-10-16）
    enum OpenAction: Equatable {
        /// 尋ねずにその控えから戻す（起動のときの「送れなかった投稿があります」で「続きから」を押して来た）
        case resumeJournal(String)
        /// 「送れなかった投稿があります」をその控え1件について尋ねる（古い順・1件ずつ）
        case askJournal(String)
        /// 「書きかけの続きがあります」を尋ねる
        case askAuto
        /// 「下書きを続けますか？」を尋ねる（本人の下書き）
        case askSaved
        case none
    }

    /// 開いたときの問い。送れなかった投稿（控え・古い順に1件）→ アプリが途中で終了した書きかけ → 本人の下書き
    /// - Parameters:
    ///   - journalIds: その人の送信の控え（**古い順**）
    ///   - resumeJournal: 起動のときの知らせで「続きから」を押して来た控え
    static func openAction(journalIds: [String], hasAutoDraft: Bool, hasSavedDraft: Bool,
                           opensWithContent: Bool, alreadyAsked: Bool, resumeJournal: String? = nil) -> OpenAction {
        guard !alreadyAsked else { return .none }
        if let resumeJournal, journalIds.contains(resumeJournal) { return .resumeJournal(resumeJournal) }
        if !opensWithContent, let oldest = journalIds.first { return .askJournal(oldest) }
        if asksRestore(hasStoredDraft: hasAutoDraft, opensWithContent: opensWithContent, alreadyAsked: false) {
            return .askAuto
        }
        if asksRestore(hasStoredDraft: hasSavedDraft, opensWithContent: opensWithContent, alreadyAsked: false) {
            return .askSaved
        }
        return .none
    }

    /// この画面が書きかけの枠（`Slot.auto`）に触って（書いて・消して）よいか。
    ///
    /// 🔴 **尋ねていない書きかけを黙って上書き・削除しない**（2026-10-16 の読み直し）。開いたとき空だった・
    /// この画面で尋ねたときだけ触る。**送信の控えはこれと関係なく必ず書く**（投稿ごとの別の枠・`Slot.send`）
    static func ownsAutoSlot(hasAutoDraft: Bool, action: OpenAction) -> Bool {
        !hasAutoDraft || action == .askAuto
    }

    // MARK: - 送れなかった投稿（送信の控え）

    /// 控えが溜まったら片づけを勧める件数（2026-10-16 判断: 写真の本体を持つので容量を食い続けない）
    static let journalLimit = 3
    /// 控えが古くなったら片づけを勧める長さ（7日）
    static let journalMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// 片づけを勧める控え: **7日を過ぎたもの**と、新しい順に `journalLimit` 件を超えた古いもの
    /// - Parameter journals: 古い順（ID と保存した時刻）
    @MainActor
    static func journalsToClean(_ journals: [(id: String, savedAt: String)], now: Date) -> [String] {
        let overflow = Set(journals.dropLast(journalLimit).map(\.id))
        return journals.filter { entry in
            if overflow.contains(entry.id) { return true }
            guard let at = UploadDraftStore.savedDate(entry.savedAt) else { return false }
            return now.timeIntervalSince(at) > journalMaxAge
        }.map(\.id)
    }

    /// 次の起動で出す「送れなかった投稿があります」（2026-10-16）
    struct InterruptedNotice: Equatable {
        let message: String
        /// 「続きから」で戻す控え（**古い順に1件**）。戻せる写真のある控えが無ければ nil
        let resumeId: String?
        /// 届いたか分からない写真だけの控え（戻せない）。知らせたら片づける
        let unsureOnlyIds: [String]
        /// 片づけを勧める控え（`journalsToClean`）。空なら勧めない
        let cleanupIds: [String]
    }

    /// 次の起動で知らせるか。出さないなら nil
    /// - Parameter journals: その人の送信の控え（古い順・`UploadDraftStore.journals`）
    @MainActor
    static func interruptedNotice(_ journals: [(id: String, draft: UploadDraftStore.Draft)],
                                  now: Date = Date()) -> InterruptedNotice? {
        guard !journals.isEmpty else { return nil }
        var resumable: [String] = []
        var unsureOnly: [String] = []
        var dropped = 0
        for entry in journals {
            let (restorable, unsure) = UploadDraftStore.restorable(entry.draft)
            dropped += unsure
            if restorable.isEmpty { unsureOnly.append(entry.id) } else { resumable.append(entry.id) }
        }
        let unsureNote = dropped > 0
            ? L("送っている途中だった \(dropped) 枚は投稿済みの可能性があるため、プロフィールで確かめてください。",
                "\(dropped) photo(s) were partway sent and may already be posted \u{2014} check your profile. ")
            : ""
        let cleanup = journalsToClean(journals.filter { resumable.contains($0.id) }
                                        .map { (id: $0.id, savedAt: $0.draft.savedAt) }, now: now)
        let cleanupNote = cleanup.isEmpty ? ""
            : L("古いものは端末の容量を使い続けるので、片づけるのがおすすめです。",
                "Older ones keep using storage on this device, so consider clearing them.")
        let head = resumable.isEmpty
            ? L("投稿を送り終える前にアプリが終了しました。", "The app closed before your post finished sending. ")
            : L("送れなかった投稿が \(resumable.count) 件あります。「続きから」で古いものから1件ずつ戻せます。",
                "\(resumable.count) post(s) didn\u{2019}t finish sending. Tap Continue to pick them up one at a time, oldest first. ")
        return InterruptedNotice(message: head + unsureNote + cleanupNote, resumeId: resumable.first,
                                 unsureOnlyIds: unsureOnly, cleanupIds: cleanup)
    }
}
