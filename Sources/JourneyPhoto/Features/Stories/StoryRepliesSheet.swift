import SwiftUI

/// **自分のストーリーに届いた返信の一覧**（板「26b 返信（自分）」・v2 StoryReplies・2026-10-14）。
///
/// 以前は `StoryViewerView` の中に書いていた。v2 で札の地（surface-1 #0E0E0F）・吹き出しにしたので、
/// 写真の上の字を持つ閲覧画面のファイルから分けた（あちらは不透明の灰・札の地を置かない決まり・
/// `DesignFoundationTests.testGraysOnPhotosStayTranslucent`）。**読み込み・読み直しは閲覧画面が持つ**
/// （開いている1本の返信と、足元の件数バッジが同じ一覧を見る）——ここは描くだけ。
///
/// - 見出し: 明朝 22 の「返信」と、SF の細い数字（読めていない間は数を出さない）。右に「閉じる」
/// - 行: 顔 36（押すとその人のページ・退会した人は顔だけ）、名前 13 の太字と時刻、吹き出し（#1A1A1C・
///   左上だけ角 4）に本文 15
/// - 下: 錠の印と「返信はあなたにだけ見えています…」
struct StoryRepliesSheet: View {

    /// 文章の返信だけ（反応は「いいね」に数える）
    let items: [StoryReply]
    let loaded: Bool
    let failed: Bool
    let reloading: Bool
    /// 読めていた一覧の読み直しに失敗した（一覧はそのまま、短く知らせる）
    let notice: String?
    let onReload: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.l) {
                    heading
                    if let notice {
                        Text(notice)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                    }
                    if failed {
                        VStack(alignment: .leading, spacing: JPSpace.s) {
                            Text(Labels.Common.loadFailed)
                                .font(JPFont.body)
                                .foregroundStyle(WebTheme.text2)
                            // 引き下げを知らない人にも出口を（2026-10-02 の調査）
                            RetryButton(isBusy: reloading) { Task { await onReload() } }
                        }
                    } else if !loaded {
                        // **読み込み中に「まだ返信はありません」と言わない**（丸のバッジと同じ）
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, JPSpace.xl)
                    } else if items.isEmpty {
                        Text(L("まだ返信はありません", "No replies yet"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                    }
                    ForEach(items) { item in
                        row(item)
                    }
                    footnote
                        .padding(.top, JPSpace.s)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, JPSpace.xs)
                .padding(.bottom, JPSpace.section)
            }
            // 引き下げで読み直す（一度読めないと、その1本の間ずっと「読み込めませんでした」だった。
            // `StoryInsightsView` の引き下げと同じ）
            .refreshable { await onReload() }
            .background(WebTheme.card)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // v2: 「閉じる」は右（見出しは中身の左に明朝で置く）
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .toolbarBackground(WebTheme.card, for: .navigationBar)
        }
        .presentationBackground(WebTheme.card)
        .presentationDragIndicator(.visible)
    }

    /// 「返信 3」（明朝 22 ＋ SF 300 の数字）。読めていない間は数を出さない（`StoryInsightsView` と同じ）
    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("返信", "Replies"))
                .font(JPFont.cardTitle)
            if loaded {
                Text("\(items.count)")
                    .font(JPFont.number(JPTypeScale.title2, weight: JPFont.figureWeight, relativeTo: .title2))
            }
        }
        .foregroundStyle(WebTheme.text)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: StoryReply) -> some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            if let uid = item.profileUserId {
                NavigationLink {
                    UserProfileView(userId: uid)
                } label: {
                    // 顔は 36pt、押せるのは 44pt 四方。外へ広げて同じだけ詰めるので、並びは変わらない
                    avatar(uid)
                        .padding(4)
                        .contentShape(Rectangle())
                        .padding(-4)
                }
                .accessibilityLabel(L("\(item.displayName) のプロフィール", "\(item.displayName)'s profile"))
            } else if let uid = item.uid {
                // **退会した人はその人のページへ行かせない**（`StoryInsightsView` の行と同じ）。顔だけ出す
                avatar(uid)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.displayName)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    if let ago = StoryPlayback.ago(from: item.t) {
                        Text(ago)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
                Text(item.body)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Self.bubbleFill,
                                in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: Self.bubbleRadius,
                                                           bottomTrailingRadius: Self.bubbleRadius,
                                                           topTrailingRadius: Self.bubbleRadius))
            }
            Spacer(minLength: JPSpace.section)
        }
    }

    private func avatar(_ uid: String) -> some View {
        RemoteImage(url: UserProfile.profileAssetURL(userId: uid, suffix: nil, cacheBust: nil),
                    placeholderSymbol: "person.crop.circle.fill")
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .clipShape(Circle())
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            Image(systemName: "lock")
                .font(JPFont.caption)
                .accessibilityHidden(true)
            Text(L("返信はあなたにだけ見えています。ストーリーが消えると、返信も一緒に消えます。",
                   "Only you can see replies. They disappear with the story."))
                .font(JPFont.caption)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(WebTheme.text3)
    }

    /// 吹き出しの地（板の `#1A1A1C`）と角（板 18・左上だけ 4）
    @MainActor static var bubbleFill: Color { RaisedTile.fill }
    static let bubbleRadius: CGFloat = 18
    /// 顔（板 36）
    static let avatarSize: CGFloat = 36
}
