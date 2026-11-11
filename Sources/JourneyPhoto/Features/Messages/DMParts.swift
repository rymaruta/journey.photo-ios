import SwiftUI

// メッセージ（DM・第1段・札 #505）の画面の部品。見た目は画面案（Artifact「メッセージ 第1段 画面案」・owner 承認）と
// デザインの板（DesignSystem「黒塗りの真鍮」）に合わせる。数は `DMLook` に集め、試験で見張る

/// シートで開く会話（ストーリーの「メッセージを見る」・返信の一覧の行から）
struct DMSheetTarget: Identifiable, Equatable {
    let id: String
}

/// 画面案の寸法（2026-11-10・画面案のモックの CSS から写した値）
enum DMLook {
    /// 受信箱の顔（48）・リクエストの札の顔（44）・会話の見出しの顔（28）
    nonisolated static let rowAvatar: CGFloat = 48
    nonisolated static let requestAvatar: CGFloat = 44
    nonisolated static let headerAvatar: CGFloat = 28
    /// まだ会話が無い相手の、空の会話の上の顔（64・板の人の行の顔 44 より大きく、プロフィールの 88 より小さく・2026-11-10 判断）
    nonisolated static let newIntroAvatar: CGFloat = 64
    /// 新しいメッセージの一覧の顔（44・板 FollowList の人の行と同じ）
    nonisolated static let pickerAvatar: CGFloat = 44
    /// 受信箱の行の高さ（72）・リクエストの入口の行（76）
    nonisolated static let rowHeight: CGFloat = 72
    nonisolated static let requestEntryHeight: CGFloat = 76
    /// 未読の点（8・黒 2 の縁）。**真鍮**（黒地の上の合図・CLAUDE.md の owner の好み）
    nonisolated static let dot: CGFloat = 8
    /// 吹き出し: 角 20・付け根の角 6・最大幅は画面の 78%・左右 14 上下 10
    nonisolated static let bubbleRadius: CGFloat = 20
    nonisolated static let bubbleTailRadius: CGFloat = 6
    nonisolated static let bubbleMaxWidthRatio: CGFloat = 0.78
    /// 入力欄の高さ（44）・送信の丸（44）
    nonisolated static let fieldHeight: CGFloat = 44
    nonisolated static let sendSize: CGFloat = 44
    /// リクエストの会話の案内の帯の地（画面案 `#1C170E`＝黒地に真鍮 8%）
    nonisolated static let requestBandAccentOpacity = 0.08
}

/// 未読の点（8pt の真鍮・黒 2pt の縁）。**色だけで伝えない**——行は字を太く・本文を明るくし、読み上げに「未読」
struct BrassDot: View {
    var body: some View {
        Circle().fill(WebTheme.accent).frame(width: DMLook.dot, height: DMLook.dot)
            .overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 2).padding(-2))
    }
}

/// 相手の顔。退会した人は顔を出さない（灰の人型）
struct DMAvatar: View {
    let userId: String
    var deleted = false
    let size: CGFloat

    var body: some View {
        RemoteImage(url: deleted ? nil : UserProfile.profileAssetURL(userId: userId, suffix: nil, cacheBust: nil),
                    placeholderSymbol: "person.fill")
            .frame(width: size, height: size)
            .background(WebTheme.card)
            .clipShape(Circle())
            .opacity(deleted ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}

/// 札の中の小さな印（「ストーリーへの返信」「2通」「リクエスト」）。線だけの丸札・12pt・text-3
struct DMChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
    }
}

/// 受信箱の1行（画面案「受信箱（通常）」）。未読は「点＋太字＋明るい本文」の3つ。既読の表示は出さない
struct DMThreadRow: View {
    let thread: DMThread
    var now = Date()

    var body: some View {
        HStack(spacing: JPSpace.s) {
            DMAvatar(userId: thread.peerId, deleted: thread.isDeleted, size: DMLook.rowAvatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(DMText.name(thread.name, deleted: thread.isDeleted))
                    .font(.system(size: 15, weight: unread ? .bold : .medium))
                    .foregroundStyle(thread.isDeleted ? WebTheme.text3 : WebTheme.text)
                    .lineLimit(1)
                Text(DMText.excerpt(thread))
                    .font(.system(size: 14, weight: unread ? .medium : .regular))
                    .foregroundStyle(unread ? WebTheme.text : WebTheme.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let time = DMText.listTime(thread.t, now: now) {
                    Text(time)
                        .font(JPFont.caption.monospacedDigit())
                        .foregroundStyle(WebTheme.text3)
                }
                if unread {
                    BrassDot()
                } else {
                    Color.clear.frame(width: DMLook.dot, height: DMLook.dot)
                }
            }
        }
        .frame(minHeight: DMLook.rowHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DMThreadRow.spoken(thread, now: now))
    }

    private var unread: Bool { thread.showsUnread }

    /// 読み上げの文（「未読、名前、本文、12分前」）
    nonisolated static func spoken(_ thread: DMThread, now: Date) -> String {
        let parts = [thread.showsUnread ? L("未読", "Unread") : nil,
                     DMText.name(thread.name, deleted: thread.isDeleted),
                     DMText.excerpt(thread),
                     DMText.listTime(thread.t, now: now)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: "、")
    }
}

/// 圏外の帯（画面案「圏外」・共通の `OfflineBanner` の形で、左右 16 の余白を付けて置く）
struct DMOfflineStrip: View {
    let text: String

    var body: some View {
        OfflineBanner(title: text)
            .padding(.horizontal, JPSpace.gutter)
            .padding(.bottom, JPSpace.xs)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// 画面の下に出す短い知らせ（承認しました ›メッセージを見る・画面案「承認した直後」）。
/// 共通の `ToastCenter` は押せる一手を持たないので、この画面の中に置く。4秒で消える
struct DMActionToast: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WebTheme.success)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.toast.action")
            }
        }
        .padding(.leading, JPSpace.m)
        .padding(.trailing, JPSpace.xs)
        .padding(.vertical, JPSpace.xs)
        .frame(minHeight: 52)
        .background(WebTheme.surface4, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
        .shadow(color: Color.black.opacity(0.45), radius: 12, y: 8)
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.xs)
        .accessibilityElement(children: .contain)
    }

    /// 出している時間（画面案「4 秒」）
    nonisolated static let duration: Duration = .seconds(4)
}

/// ブロックの確認（画面案「ブロックの確認」: 「ブロックした人」の板の文に、メッセージを足した）
enum DMBlockText {
    static func title(_ name: String) -> String {
        L("\(name) さんをブロックしますか？", "Block \(name)?")
    }
    static var message: String {
        L("おたがいの投稿・ストーリー・メッセージ・通知が見えなくなります。相手には知らされません。解除は 設定 › ブロックした人 から。",
          "You won't see each other's posts, stories, messages or notifications. They won't be told. Undo it in Settings › Blocked.")
    }
}
