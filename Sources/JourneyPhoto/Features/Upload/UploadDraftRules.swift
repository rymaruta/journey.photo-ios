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
}
