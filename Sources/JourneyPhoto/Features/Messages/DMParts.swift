import SwiftUI

// メッセージ（DM・第1段・札 #505）の画面の部品。見た目は画面案（Artifact「メッセージ 第1段 画面案」・owner 承認）と
// デザインの板（DesignSystem「黒塗りの真鍮」）に合わせる。数は `DMLook` に集め、試験で見張る

/// シートで開く会話（ストーリーの「メッセージを見る」・返信の一覧の行から）
struct DMSheetTarget: Identifiable, Equatable {
    let id: String
}

/// 画面の寸法（2026-11-10 の画面案の CSS から写した値に、2026-11-11 の作り直し・案C を重ねた）。
///
/// **2026-11-11 作り直し（札 #541・owner 承認「DM のデザイン」の案C「黒塗りに真鍮の縁」）**:
/// 受信箱の顔 48 → 52（未見のストーリーの輪を顔に描く・`DMStoryFace`）・会話の見出しの顔 28 → 32・
/// ストーリーへの返信の写真 40×52 → 104×138・送った写真 220×275（4:5）・吹き出しの最大幅は画面の 78%
/// （固定の 304 をやめた）・空の受信箱の顔の列 52
enum DMLook {
    /// 受信箱の顔（52）・リクエストの札の顔（44）・会話の見出しの顔（32）
    nonisolated static let rowAvatar: CGFloat = 52
    nonisolated static let requestAvatar: CGFloat = 44
    nonisolated static let headerAvatar: CGFloat = 32
    /// まだ会話が無い相手の、空の会話の上の顔（64・板の人の行の顔 44 より大きく、プロフィールの 88 より小さく・2026-11-10 判断）
    nonisolated static let newIntroAvatar: CGFloat = 64
    /// 新しいメッセージの一覧の顔（44・板 FollowList の人の行と同じ）
    nonisolated static let pickerAvatar: CGFloat = 44
    /// 空の受信箱の「フォロー中」の顔の列（52・名前は 12pt で1行・列の幅 64）
    nonisolated static let faceAvatar: CGFloat = 52
    nonisolated static let faceColumn: CGFloat = 64
    /// 送れない相手の顔の濃さ（1.1.83 観光スポット・`DMPeopleFacesRow.dimmed`）
    nonisolated static let unreachableFaceOpacity: Double = 0.4
    /// 受信箱の行の高さ（72）・リクエストの入口の行（76）
    nonisolated static let rowHeight: CGFloat = 72
    nonisolated static let requestEntryHeight: CGFloat = 76
    /// 未読の点（8・黒 2 の縁）。**真鍮**（黒地の上の合図・CLAUDE.md の owner の好み）
    nonisolated static let dot: CGFloat = 8
    /// 吹き出し: 角 20・付け根の角 6（続けて送った吹き出しは、つながる側も 6）・最大幅は画面の 78%・左右 14 上下 10
    nonisolated static let bubbleRadius: CGFloat = 20
    nonisolated static let bubbleTailRadius: CGFloat = 6
    nonisolated static let bubbleMaxWidthRatio: CGFloat = 0.78
    /// 自分の吹き出しの真鍮の縁（1pt・黒地 9.15:1・吹き出しの地 #1C170E と 7.77:1）
    nonisolated static let bubbleBorder: CGFloat = 1
    /// 入力欄の高さ（44）・送信の丸（44）。板の StoryViewerReply の返信欄と同じ
    nonisolated static let fieldHeight: CGFloat = 44
    nonisolated static let sendSize: CGFloat = 44
    /// リクエストの会話の案内の帯の地（画面案 `#1C170E`＝黒地に真鍮 8%）
    nonisolated static let requestBandAccentOpacity = 0.08
    /// ストーリーへの返信の写真（104×138・角 14）。2026-11-10 の 40×52 では写真が主役にならなかった
    nonisolated static let storyThumbWidth: CGFloat = 104
    nonisolated static let storyThumbHeight: CGFloat = 138
    /// 送った写真（幅 220・縦 4:5＝高さ 275・角 14・縁も真鍮も載せない）
    nonisolated static let photoWidth: CGFloat = 220
    nonisolated static let photoHeight: CGFloat = 275

    /// 吹き出しの最大幅（会話の幅の 78%）。幅が読めない間（0）は 390pt の画面の値
    nonisolated static func bubbleMaxWidth(container: CGFloat) -> CGFloat {
        (container > 0 ? container : 390) * bubbleMaxWidthRatio
    }
}

/// 吹き出しの色（2026-11-11・案C「黒塗りに真鍮の縁」・owner 承認）。
///
/// - 自分: accent-soft `#1C170E` の塗りに白 94% の字（15.64:1）・真鍮 1pt の縁（黒地 9.15:1）。真鍮は線だけ——
///   面に使うと、未読の点・件数・送るボタンの真鍮の合図が埋もれる（板「広い面・2つ目の塗りに真鍮を使わない」）
/// - 相手: surface-8 `#2C2C2E` に白の字（12.23:1）・縁なし
/// - 自分と相手は「右・真鍮の縁・暗い地」と「左・縁なし・灰の地」の3つで分ける（色だけにしない）
@MainActor
enum DMBubbleColors {
    static func fill(mine: Bool) -> Color { mine ? WebTheme.accentSoft : WebTheme.surface8 }
    static func text(mine: Bool) -> Color { mine ? WebTheme.text : WebTheme.foreground }
    static func border(mine: Bool) -> Color { mine ? WebTheme.accent : Color.clear }
    /// 本文の中のリンクの色（真鍮・どちらの地の上も黒地の仲間: #1C170E 7.77:1・#2C2C2E 6.07:1）
    static var link: Color { WebTheme.accent }
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
        FaceImage(url: deleted ? nil : UserProfile.profileAssetURL(userId: userId, suffix: nil, cacheBust: nil))
            .frame(width: size, height: size)
            .background(WebTheme.card)
            .clipShape(Circle())
            .opacity(deleted ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}

/// 未見のストーリーがある相手は、顔に真鍮の輪（ホームの輪と同じ・押すとその人のストーリー・`StoryAvatar`）。
/// 輪の無い人の顔は `plainTap` があればそれ（受信箱では会話を開く）、無ければ押せない顔（2026-11-11・案C）。
/// 退会した人は輪を描かない
struct DMStoryFace: View {
    let userId: String
    var deleted = false
    let name: String
    let size: CGFloat
    var plainTap: (() -> Void)?

    var body: some View {
        if deleted {
            DMAvatar(userId: userId, deleted: true, size: size)
        } else {
            StoryAvatar(userId: userId, name: name, diameter: size) {
                FaceImage(url: UserProfile.profileAssetURL(userId: userId, suffix: nil, cacheBust: nil))
                    .background(WebTheme.card)
            } plain: {
                if let plainTap {
                    Button(action: plainTap) {
                        DMAvatar(userId: userId, size: size)
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                } else {
                    DMAvatar(userId: userId, size: size)
                }
            }
        }
    }
}

/// 札の中の小さな印（「ストーリーへの返信」「2通」「リクエスト」）。線だけの丸札・12pt・text-3（押せない飾りなので白 12% の線）
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

/// 受信箱の1行の字と点（画面案「受信箱」を 2026-11-11 案C で作り直し）。**顔は行の外**（`DMStoryFace`・輪を押すと
/// ストーリー、行を押すと会話。1つのボタンの中にボタンを入れない）。
///
/// - 1行目: 名前（15・未読は太字）と「· 時刻」（12・text-3・等幅数字）。2行目: 抜粋（14・未読は白）
/// - 未読の点は行の右の真ん中（目が「名前 → 本文 → 点」の1本で済む）
/// - 未読は「点＋太字＋明るい本文」の3つ。既読の表示は出さない
struct DMThreadRow: View {
    let thread: DMThread
    var now = Date()

    var body: some View {
        HStack(spacing: JPSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DMText.name(thread.name, deleted: thread.isDeleted))
                        .font(JPFont.body.weight(unread ? .bold : .medium))
                        .foregroundStyle(thread.isDeleted ? WebTheme.text3 : WebTheme.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let time = DMText.listTime(thread.t, now: now) {
                        Text(time)
                            .font(JPFont.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(DMText.excerpt(thread))
                    .jpSystemFont(14, weight: unread ? .medium : .regular)
                    .foregroundStyle(unread ? WebTheme.text : WebTheme.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if unread {
                BrassDot()
            } else {
                Color.clear.frame(width: DMLook.dot, height: DMLook.dot)
            }
        }
        .frame(minHeight: DMLook.rowHeight)
        .contentShape(Rectangle())
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

/// 「フォロー中」の顔の列（2026-11-11・案C の空の受信箱）。顔 52・名前 12pt 1行・横に流す。押すとその人との会話
/// （最初の1通が 4 → 3 押しになる: 吹き出し → 顔 → 送信）。**写真の「送る」のシートの送る相手の列と同じ形にする**
/// （札 #541・別の担当の枝 `claude/sns-share-reply`）
struct DMPeopleFacesRow: View {
    let people: [FollowUser]
    /// 送る前に送れないと分かる相手（1.1.83 観光スポット・`DMSpotShare.unreachablePeers`）。顔を薄くする。
    /// 押せば呼ぶ側が理由を知らせる（送らない）
    var dimmed: Set<String> = []
    let onPick: (FollowUser) -> Void

    init(people: [FollowUser], dimmed: Set<String> = [], onPick: @escaping (FollowUser) -> Void) {
        self.people = people
        self.dimmed = dimmed
        self.onPick = onPick
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: JPSpace.xs) {
                ForEach(people) { user in
                    Button { onPick(user) } label: {
                        VStack(spacing: 6) {
                            DMAvatar(userId: user.id, size: DMLook.faceAvatar)
                            Text(user.displayName)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(width: DMLook.faceColumn)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                        .opacity(dimmed.contains(user.id) ? DMLook.unreachableFaceOpacity : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(user.displayName) さんにメッセージ", "Message \(user.displayName)"))
                    .accessibilityIdentifier("dm.face")
                }
            }
            .padding(.horizontal, JPSpace.gutter)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dm.faces")
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
                .jpSystemFont(14)
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(JPFont.footnote.weight(.semibold))
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
        L("おたがいの投稿、ストーリー、メッセージ、通知が見えなくなります。相手には知らされません。解除は 設定 › ブロックした人 から。",
          "You won't see each other's posts, stories, messages or notifications. They won't be told. Undo it in Settings › Blocked.")
    }
}
