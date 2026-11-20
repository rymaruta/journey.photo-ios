import SwiftUI

// グループの DM（2026-11-20・札 #582・案「グループチャットを簡単に」の推奨 C）の画面の部品。
// 色・字・吹き出し・入力欄は 1対1 の部品（`DMParts.swift`）をそのまま使い、ここにはグループにしか無いものだけを置く

/// グループの寸法（案の模型は 390pt を 300 に縮めて描いた。ここは 390pt の値に戻し、1対1の寸法 `DMLook` にそろえた）
enum GroupLook {
    /// 重ねた顔の枠: 受信箱の行（1対1の顔と同じ 52）・会話の見出し（34）・詳しい画面と空の会話と招待の札（72）
    nonisolated static let rowFaces: CGFloat = DMLook.rowAvatar
    nonisolated static let headerFaces: CGFloat = 34
    nonisolated static let largeFaces: CGFloat = 72
    /// 枠に対する1つの顔の大きさ（模型 30/44・24/34・50/72 ≒ 0.69）と、重なりの黒い縁
    nonisolated static let faceRatio: CGFloat = 0.69
    nonisolated static let faceRing: CGFloat = 2
    /// 相手の吹き出しの横の小さな顔（28）と、続きの吹き出しの左の空き（顔 28＋間 6）
    nonisolated static let senderAvatar: CGFloat = 28
    nonisolated static let senderGap: CGFloat = 6
    nonisolated static var senderIndent: CGFloat { senderAvatar + senderGap }
    /// 会話の真ん中の1行の最大幅（模型 240 を 390pt に戻した値）
    nonisolated static let eventMaxWidth: CGFloat = 300
    /// 選ぶ画面の印（丸 24・縁 2）と、選んだ人の札（高さ 32）
    nonisolated static let checkSize: CGFloat = 24
    nonisolated static let pickedChipHeight: CGFloat = 32
    /// 選ぶ画面の主ボタン（高さ 48）
    nonisolated static let mainButtonHeight: CGFloat = 48
    /// 詳しい画面の行（48）と、人を足すの点線の丸（32）
    nonisolated static let infoRowHeight: CGFloat = 48
    nonisolated static let addCircle: CGFloat = 32
}

/// 重ねた顔（グループのアイコン）。**写真にしない**——他人の写真をアイコンにされる道を作らない（案「安全と決まり」）。
/// 見る人を除いた2人の顔を、左上と右下に黒 2pt の縁で重ねる。顔が1人なら真ん中に1つ・0人なら人の印
struct GroupFaces: View {
    let faces: [GroupFace]
    let size: CGFloat

    var body: some View {
        let face = (size * GroupLook.faceRatio).rounded()
        ZStack {
            if faces.count >= 2 {
                DMAvatar(userId: faces[0].id, size: face)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                DMAvatar(userId: faces[1].id, size: face)
                    .padding(GroupLook.faceRing)
                    .background(WebTheme.background, in: Circle())
                    .padding(-GroupLook.faceRing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else if let only = faces.first {
                DMAvatar(userId: only.id, size: size)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: size, height: size)
                    .background(WebTheme.surface3, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 受信箱のグループの1行（1対1の行 `DMThreadRow` と同じ形: 名前と時刻・抜粋・未読の点）
struct GroupThreadRow: View {
    let thread: GroupThread
    var now = Date()

    var body: some View {
        HStack(spacing: JPSpace.s) {
            GroupFaces(faces: thread.info.faces, size: GroupLook.rowFaces)
                .opacity(thread.isRemoved ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(GroupText.title(thread.info))
                        .font(JPFont.body.weight(unread ? .bold : .medium))
                        .foregroundStyle(thread.isRemoved ? WebTheme.text3 : WebTheme.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let time = DMText.listTime(thread.updatedAt, now: now) {
                        Text(time)
                            .font(JPFont.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(GroupText.excerpt(thread))
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
        .accessibilityLabel([unread ? L("未読", "Unread") : nil, GroupText.title(thread.info),
                             // 外された人の行には人数が来ない（サーバー ed0e0dc70: 外された時の名前だけ）
                             thread.info.memberCount > 0 ? GroupText.memberCount(thread.info.memberCount) : nil,
                             GroupText.excerpt(thread),
                             DMText.listTime(thread.updatedAt, now: now)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "、"))
    }

    private var unread: Bool { thread.showsUnread }
}

/// 会話の真ん中の短い1行（作った・足した・参加した・抜けた・外した・名前を変えた）。12pt・text-3・真ん中寄せ
struct GroupEventLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: GroupLook.eventMaxWidth)
            .padding(.horizontal, JPSpace.xs)
            .padding(.vertical, JPSpace.xxs)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("group.event")
    }
}

/// 選ぶ画面の印（丸 24・outline の縁。選ぶと真鍮の塗りに墨のチェック・黒地の上の合図）。**形でも伝える**（チェックの有無）
struct GroupCheckMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(WebTheme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WebTheme.accentText)
            } else {
                Circle().strokeBorder(WebTheme.outline, lineWidth: 2)
            }
        }
        .frame(width: GroupLook.checkSize, height: GroupLook.checkSize)
        .accessibilityHidden(true)
    }
}

/// 選んだ人の札（顔 26・名前 13・× で外す。地は surface-8・高さ 32）。× の当たりは 44
struct GroupPickedChip: View {
    let user: FollowUser
    var locked = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            DMAvatar(userId: user.id, size: 26)
            Text(user.displayName)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
            if !locked {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WebTheme.text2)
                        .frame(width: 26, height: 26)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -(WebTheme.minTapTarget - GroupLook.pickedChipHeight) / 2)
                .padding(.horizontal, -9)
                .accessibilityLabel(L("\(user.displayName) を外す", "Remove \(user.displayName)"))
                .accessibilityIdentifier("group.pick.remove")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, locked ? 10 : 4)
        .frame(height: GroupLook.pickedChipHeight)
        .background(WebTheme.surface8, in: Capsule())
    }
}
