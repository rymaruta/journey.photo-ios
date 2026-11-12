import Foundation

/// ホームの上の札（旅行プランの「出発が近い」「旅の最中」）の「⋯」と長押しのメニューの中身（2026-11-12）。
///
/// owner「旅行プラン当日のやつはホームに出てくると思うけど、削除するときは旅行プランのページに行かないと
/// いけないのめんどくさい」。札から直に、ホームに出さない・消すを選べるようにする。
///
/// 2026-11-12 判断（CLAUDE.md「直感的で簡単に」）:
/// - 「⋯」と長押しは**同じ中身**（見て分かる入口と、慣れた人の近道）
/// - 自分だけのプランの削除は**聞かずにすぐ消し、「元に戻す」を6秒出す**（取り消せる操作は聞かない）。
///   サーバーへ送るのは6秒たってから（`TripPlanRemovalQueue`）
/// - 仲間と共有したプラン（札 #553・枝 `claude/183-trip-share`）は、持ち主でない人には「削除」ではなく
///   「この旅から抜ける」。持ち主の削除は**仲間全員から消える**ので、そのことが分かる言葉にして、
///   **これだけは確かめを出す**（他人に影響する操作）
enum HomeTripCardMenu {

    /// 札のプランに対する自分の立場
    enum Role: Equatable {
        /// 自分だけのプラン
        case mine
        /// 仲間と共有したプランの持ち主（消すと仲間全員から消える）
        case sharedOwner
        /// 仲間と共有したプランの仲間（持ち主でない）
        case sharedMember
    }

    enum Item: String, Equatable, CaseIterable {
        /// この旅をホームに出さない（端末の中だけ・プランは消さない）
        case hideFromHome
        /// 旅行プランを削除（自分だけのプラン）
        case delete
        /// 仲間全員から削除（共有したプランの持ち主）
        case deleteForEveryone
        /// この旅から抜ける（共有したプランの仲間）
        case leave

        var title: String {
            switch self {
            case .hideFromHome: return L("この旅をホームに出さない", "Hide this trip from Home")
            case .delete: return L("旅行プランを削除", "Delete trip plan")
            case .deleteForEveryone: return L("仲間全員から削除", "Delete for everyone")
            case .leave: return L("この旅から抜ける", "Leave this trip")
            }
        }

        var systemImage: String {
            switch self {
            case .hideFromHome: return "eye.slash"
            case .delete, .deleteForEveryone: return "trash"
            case .leave: return "rectangle.portrait.and.arrow.right"
            }
        }

        /// 系統のメニューで危険の形（赤）にするか。出さないはプランを消さないので普通の行
        var isDestructive: Bool { self != .hideFromHome }

        /// 押したあとに確かめを出すか。**他人に影響する操作だけ**（仲間全員から消える）
        var needsConfirm: Bool { self == .deleteForEveryone }

        /// 識別子（UI テスト）
        var identifier: String { "home.tripMenu.\(rawValue)" }
    }

    /// メニューに並べるもの（上から）
    static func items(for role: Role) -> [Item] {
        switch role {
        case .mine: return [.hideFromHome, .delete]
        case .sharedOwner: return [.hideFromHome, .deleteForEveryone]
        case .sharedMember: return [.hideFromHome, .leave]
        }
    }

    /// プランに対する自分の立場。
    ///
    /// 🔴 **main にはまだ共有の仕組み（`TripPlan.share`）が無いので、いまは必ず `.mine`。**
    /// 共有の枝（`claude/183-trip-share`）と合わせるときは、ここを
    /// `plan.share == nil ? .mine : (plan.share!.isOwner(me) ? .sharedOwner : .sharedMember)` にする
    /// （サーバーの `DELETE /user/trips/<id>` は、持ち主なら仲間全員から消し、仲間なら抜けるに分ける）
    static func role(of plan: TripPlan, me: String?) -> Role {
        .mine
    }

    // MARK: - 確かめ（仲間全員から削除だけ）

    static func confirmTitle(_ planTitle: String) -> String {
        L("「\(planTitle)」を仲間全員から削除しますか？", "Delete \"\(planTitle)\" for everyone?")
    }

    static var confirmMessage: String {
        L("仲間のプランと会話も消えます。", "It will also be removed for everyone in the trip, along with the chat.")
    }

    static var confirmButton: String { L("仲間全員から削除", "Delete for everyone") }

    // MARK: - 知らせ（元に戻す）

    /// 押したあとの知らせの文
    static func doneText(_ item: Item, planTitle: String) -> String {
        switch item {
        case .hideFromHome:
            return L("「\(planTitle)」をホームに出しません", "\"\(planTitle)\" won't show on Home")
        case .delete, .deleteForEveryone:
            return L("「\(planTitle)」を削除しました", "Deleted \"\(planTitle)\"")
        case .leave:
            return L("「\(planTitle)」から抜けました", "Left \"\(planTitle)\"")
        }
    }

    /// 消せなかった知らせ（札は戻る）
    static func failedText(_ item: Item, planTitle: String) -> String {
        switch item {
        case .leave:
            return L("「\(planTitle)」から抜けられませんでした", "Couldn't leave \"\(planTitle)\"")
        default:
            return L("「\(planTitle)」を削除できませんでした", "Couldn't delete \"\(planTitle)\"")
        }
    }

    static var undo: String { L("元に戻す", "Undo") }

    /// 札の「⋯」の読み上げ
    static var menuLabel: String { L("この旅行プランの操作", "Trip plan actions") }
}
