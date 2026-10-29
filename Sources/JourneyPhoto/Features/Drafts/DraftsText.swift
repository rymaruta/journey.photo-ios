import Foundation

/// 下書きの一覧の文言（2026-10-29・#400・モック 9JzQWmYxF14BmUiZ9yWbe8 の文言どおり）。画面を持たない（試験で確かめる）。
///
/// **「捨てる」という言い方は使わない**（owner の好み・2026-10-09）——「削除」「変更を残さずに閉じる」と、
/// 何が起きるかで言う（`NoDiscardWordingTests`）
enum DraftsText {

    static var title: String { L("下書き", "Drafts") }

    static func kind(_ kind: DraftLibrary.Kind) -> String {
        kind == .story ? L("ストーリー", "Story") : L("投稿", "Post")
    }

    /// 絞り込みのチップ（すべて／投稿／ストーリー）
    static func filter(_ kind: DraftLibrary.Kind?) -> String {
        switch kind {
        case nil: return L("すべて", "All")
        case .post?: return L("投稿", "Posts")
        case .story?: return L("ストーリー", "Stories")
        }
    }

    /// 題（無ければ「題なし」、自動の書きかけは「書きかけ（自動で保存）」）
    static func title(_ entry: DraftLibrary.Entry) -> String {
        if !entry.title.isEmpty { return entry.title }
        return entry.isAuto ? L("書きかけ（自動で保存）", "Unsaved work (auto-saved)") : L("題なし", "Untitled")
    }

    static func photos(_ count: Int) -> String {
        L("\(count)枚", count == 1 ? "1 photo" : "\(count) photos")
    }

    /// 保存した日時（「今日 06:12」「昨日 22:40」「10月24日 19:05」）
    static func saved(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        if calendar.isDate(date, inSameDayAs: now) { return L("今日 \(time)", "Today \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return L("昨日 \(time)", "Yesterday \(time)")
        }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        return sameYear
            ? L("\(month)月\(day)日 \(time)", "\(months[month - 1]) \(day), \(time)")
            : L("\(year)年\(month)月\(day)日", "\(months[month - 1]) \(day), \(year)")
    }

    /// マスの左下（短く）
    static func daysLeftShort(_ days: Int) -> String { L("あと\(days)日", "\(days)d left") }

    /// 行・長押しの詳細（長く）
    static func daysLeftLong(_ days: Int) -> String {
        L("あと\(days)日で消えます", days == 1 ? "Deleted in 1 day" : "Deleted in \(days) days")
    }

    static func missing(_ count: Int) -> String {
        L("\(count)枚を読み込めません", count == 1 ? "1 photo can\u{2019}t load" : "\(count) photos can\u{2019}t load")
    }

    static var autoNote: String { L("アプリが途中で終了", "App closed mid-post") }

    /// 種類 · 枚数
    static func kindAndPhotos(_ entry: DraftLibrary.Entry) -> String {
        "\(kind(entry.kind)) · \(photos(entry.photoCount))"
    }

    /// 読み上げ（格子のマスは字を出さないので、題・撮影地・種類・枚数・日時・期限・読めない写真を全部読む）
    static func accessibility(_ entry: DraftLibrary.Entry, now: Date) -> String {
        var parts = [title(entry)]
        if !entry.place.isEmpty { parts.append(entry.place) }
        parts.append(kindAndPhotos(entry))
        parts.append(saved(entry.savedAt, now: now))
        let days = DraftLibrary.daysLeft(kind: entry.kind, savedAt: entry.savedAt, now: now)
        if DraftLibrary.showsDaysLeft(days), let days { parts.append(daysLeftLong(days)) }
        if entry.missingCount > 0 { parts.append(missing(entry.missingCount)) }
        return parts.joined(separator: " · ")
    }

    /// 上の帯（「12 / 20件 · 31 MB · この端末にだけ保存」）
    static func storageLine(count: Int, megabytes: Int) -> String {
        L("\(count) / \(DraftLibrary.limit)件 · \(megabytes) MB · この端末にだけ保存",
          "\(count) / \(DraftLibrary.limit) · \(megabytes) MB · Saved on this device only")
    }

    /// 明日までに消えるストーリーの帯
    static func expiringBand(_ count: Int) -> String {
        L("ストーリーの下書き\(count)件が、あした消えます。保存から\(Int(DraftLibrary.storyLifetime / 86_400))日で消えます。",
          "\(count) story draft\(count == 1 ? "" : "s") will be deleted tomorrow. Story drafts last \(Int(DraftLibrary.storyLifetime / 86_400)) days.")
    }

    static var limitBand: String {
        L("1件以上削除すると、いまの書きかけを保存できます。", "Delete at least one draft to save what you\u{2019}re writing.")
    }

    static var gridHint: String { L("長押しで題・撮影地・日時と操作", "Touch and hold for details and actions") }
    static var rowsHint: String { L("「…」で操作", "Tap \u{2022}\u{2022}\u{2022} for actions") }

    // MARK: 選ぶ・削除

    static var select: String { L("選ぶ", "Select") }
    static var selectAll: String { L("すべて", "Select all") }

    static func selectionTitle(_ count: Int) -> String {
        count == 0 ? L("選んでください", "Select drafts") : L("\(count)件を選択", "\(count) selected")
    }

    static func selectionCaption(drafts: Int, photos: Int) -> String {
        L("\(drafts)件 · 写真\(photos)枚", "\(drafts) draft\(drafts == 1 ? "" : "s") · \(photos) photo\(photos == 1 ? "" : "s")")
    }

    static func deleteButton(_ count: Int) -> String {
        count == 0 ? L("削除", "Delete") : L("\(count)件を削除", "Delete \(count)")
    }

    static func deleteConfirmTitle(_ count: Int) -> String {
        L("\(count)件の下書きを削除しますか？", count == 1 ? "Delete 1 draft?" : "Delete \(count) drafts?")
    }

    static var deleteConfirmMessage: String {
        L("写真と書いた題・説明は、この端末から消えます。すぐ後なら「元に戻す」で戻せます。",
          "The photos and text will be removed from this device. You can undo right after.")
    }

    static func deleted(_ count: Int) -> String {
        L("\(count)件を削除しました", count == 1 ? "Deleted 1 draft" : "Deleted \(count) drafts")
    }

    static var undo: String { L("元に戻す", "Undo") }

    // MARK: 長押しの操作

    static var continueEditing: String { L("続きから編集", "Continue editing") }
    static var duplicate: String { L("複製", "Duplicate") }
    static var delete: String { L("削除", "Delete") }
    static var duplicated: String { L("複製しました", "Duplicated") }
    static var duplicateFailed: String {
        L("複製できませんでした（下書きがいっぱいか、端末の空き容量が足りません）",
          "Couldn\u{2019}t duplicate (drafts are full or storage is low)")
    }

    // MARK: 状態

    static var emptyTitle: String { L("下書きはまだありません", "No drafts yet") }
    static var emptyMessage: String {
        L("投稿やストーリーを閉じるときに「下書きに保存」を選ぶと、ここに並びます。この端末にだけ残ります。",
          "Choose \u{201C}Save draft\u{201D} when you close a post or story and it\u{2019}ll show up here. Drafts stay on this device.")
    }
    static var emptyAction: String { L("写真を選ぶ", "Choose photos") }
    static var noneOfKind: String { L("この種類の下書きはありません", "No drafts of this kind") }
    static var loading: String { L("読み込み中", "Loading") }
    static var errorTitle: String { L("下書きを読めませんでした", "Couldn\u{2019}t load your drafts") }
    static var errorMessage: String {
        L("端末の空き容量が足りないと起きます。下書きは消えていません。",
          "This can happen when storage is low. Your drafts are still here.")
    }
    static var retry: String { L("もう一度試す", "Try again") }

    // MARK: 読めない写真

    static func missingTitle(_ count: Int) -> String {
        L("写真\(count)枚を読み込めませんでした", count == 1 ? "Couldn\u{2019}t load 1 photo" : "Couldn\u{2019}t load \(count) photos")
    }

    static func missingMessage(total: Int, missing: Int) -> String {
        let rest = max(0, total - missing)
        if rest == 0 {
            return L("この下書きの写真が開けません（端末の容量不足や、復元のあとに起きます）。",
                     "The photos in this draft can\u{2019}t be opened (this can happen when storage is low or after a restore).")
        }
        return L("この下書きの\(total)枚のうち\(missing)枚が開けません（端末の容量不足や、復元のあとに起きます）。残りの\(rest)枚で続けますか？",
                 "\(missing) of \(total) photo\(total == 1 ? "" : "s") in this draft can\u{2019}t be opened. Continue with the other \(rest)?")
    }

    static func continueWithRest(_ rest: Int) -> String {
        L("残りの\(rest)枚で続ける", "Continue with \(rest)")
    }

    static var deleteThisDraft: String { L("この下書きを削除", "Delete this draft") }

    // MARK: 説明のシート

    static var aboutTitle: String { L("下書きについて", "About drafts") }

    struct Fact: Equatable {
        let symbol: String
        let headline: String
        let detail: String
    }

    static func facts(count: Int, megabytes: Int) -> [Fact] {
        let days = Int(DraftLibrary.storyLifetime / 86_400)
        return [
            Fact(symbol: "iphone",
                 headline: L("この端末にだけ保存します。", "Saved on this device only."),
                 detail: L("別の iPhone や Web 版では見えません。機種を変えると引き継がれません。",
                           "They don\u{2019}t appear on other iPhones or the web, and don\u{2019}t move to a new phone.")),
            Fact(symbol: "person",
                 headline: L("ログアウトしても消えません。", "Signing out keeps them."),
                 detail: L("同じアカウントでログインし直すと戻ります。別の人がこの端末でログインしても見えません。退会すると消えます。",
                           "Sign back in to the same account to see them. Others signing in on this device can\u{2019}t see them. Deleting your account removes them.")),
            Fact(symbol: "clock",
                 headline: L("投稿の下書きは消えません。ストーリーの下書きは保存から\(days)日で消えます。",
                             "Post drafts don\u{2019}t expire. Story drafts are deleted \(days) days after saving."),
                 detail: L("消える\(DraftLibrary.warnDays)日前から、一覧でお知らせします。",
                           "We\u{2019}ll let you know in this list \(DraftLibrary.warnDays) days before.")),
            Fact(symbol: "shippingbox",
                 headline: L("\(DraftLibrary.limit)件まで · いま \(count)件・\(megabytes) MB",
                             "Up to \(DraftLibrary.limit) · now \(count), \(megabytes) MB"),
                 detail: L("写真は下書きの中に写しを持つので、写真アプリで元の写真を消しても開けます。アプリを削除すると消えます。",
                           "Drafts keep their own copy of each photo, so deleting the original from Photos is fine. Deleting the app removes them.")),
        ]
    }

    static var gotIt: String { L("わかった", "Got it") }

    // MARK: 閉じるとき（投稿・ストーリー共通）

    /// 下書きから開いて閉じるとき
    static var updateTitle: String { L("下書きを更新しますか？", "Update this draft?") }
    static var updateMessage: String { L("下書きはこの端末にだけ残ります。", "Drafts stay on this device only.") }
    static var update: String { L("この下書きを更新", "Update this draft") }
    static var saveAsNew: String { L("別の下書きとして保存", "Save as a new draft") }
    static var closeWithoutChanges: String { L("変更を残さずに閉じる", "Close without changes") }

    /// いっぱいのとき
    static var fullTitle: String { L("下書きがいっぱいです", "Your drafts are full") }
    static func fullMessage(megabytes: Int) -> String {
        L("下書きは\(DraftLibrary.limit)件までです（この端末で \(megabytes) MB）。いくつか削除すると保存できます。",
          "You can keep up to \(DraftLibrary.limit) drafts (\(megabytes) MB on this device). Delete some to save this one.")
    }
    static var tidy: String { L("下書きを整理する", "Manage drafts") }

    /// 新しい下書きの数の一言（「いま n / 20件」）
    static func countNote(_ count: Int) -> String {
        L("（いま \(count) / \(DraftLibrary.limit)件）", " (\(count) of \(DraftLibrary.limit))")
    }

    /// 保存した・更新したの知らせ
    static var savedToast: String { L("下書きに保存しました（この端末だけ）", "Saved as a draft on this device") }
    static var updatedToast: String { L("下書きを更新しました", "Draft updated") }
    static var savedAsNewToast: String { L("別の下書きとして保存しました", "Saved as a new draft") }

    /// 作る画面の上の入口（「下書き n ›」）の読み上げ
    static func entryAccessibility(_ count: Int) -> String {
        L("下書き \(count)件", count == 1 ? "Drafts, 1" : "Drafts, \(count)")
    }
}
