import SwiftUI
import UIKit

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
    /// どのストーリーへの返信か（通報のメールに書く）。分からなければ nil
    var storyId: String? = nil

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.openURL) private var openURL

    /// ブロックの確認を出している返信（押した時点の相手を持つ・`blockConfirmation(presenting:)`）
    @State private var pendingBlock: StoryReply?
    /// **このシートの「…」からブロックした人**。その人の返信はその場で外す。
    /// `hidden.blockedUserIds` で毎回絞らない——行の顔から開いた人のページでブロックすると、
    /// 行が消えて開いている画面が閉じる（`ModerationSnapshot.users` の注記と同じ理由）。
    /// 人のページでブロックした分は、閉じたときに閲覧画面が外す（`StoryViewerView` の `onDismiss`）
    @State private var blockedHere: Set<String> = []
    /// メールを開けなかった（宛先を知らせる確認を出す）
    @State private var mailUnavailable = false

    /// 出す返信（このシートでブロックした人の分を外す）
    private var shown: [StoryReply] { StoryReplyActions.visible(items, blockedHere: blockedHere) }

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
                    } else if shown.isEmpty {
                        Text(L("まだ返信はありません", "No replies yet"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                    }
                    ForEach(shown) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, JPSpace.xs)
                .padding(.bottom, JPSpace.section)
            }
            // 引き下げで読み直す（一度読めないと、その1本の間ずっと「読み込めませんでした」だった。
            // `StoryInsightsView` の引き下げと同じ）
            .refreshable { await onReload() }
            // 錠の注記は**シートの下端**（板 `margin: auto 20px 40px`）。一覧の終わりに続けて置くと、
            // 返信が少ないときにシートの真ん中に浮いていた（2026-10-16 判断）
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footnote
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, JPSpace.l)
                    .padding(.top, JPSpace.s)
                    .padding(.bottom, JPSpace.l)
                    .background(WebTheme.card)
            }
            .background(WebTheme.card)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // v2: 「閉じる」は右（見出しは中身の左に明朝で置く）
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .toolbarBackground(WebTheme.card, for: .navigationBar)
            .blockConfirmation(presenting: $pendingBlock) { reply in
                Task { await block(reply) }
            }
            // メールを開けない端末: 宛先は**トーストではなく確認で出す**（トーストは短く消え、
            // 長い宛先が途中で切れる）。写して別のメールから送れるよう「宛先をコピー」を置く
            .alert(StoryReplyActions.mailUnavailableTitle, isPresented: $mailUnavailable) {
                Button(StoryReplyActions.copyAddress) {
                    UIPasteboard.general.string = LegalConsent.contactEmail
                    toasts.show(L("宛先をコピーしました", "Address copied"))
                }
                Button(Labels.Common.close, role: .cancel) {}
            } message: {
                Text(StoryReplyActions.mailUnavailable)
            }
        }
        // **このシートの上にもトーストを重ねる**（シートの上には根のトーストが出ず、ブロックの結果・
        // 失敗が裏に隠れていた・`PassViewerView` と同じ形）
        .overlay(alignment: .top) { ToastOverlay() }
        .presentationBackground(WebTheme.card)
        // 板 v2 StoryReplies: シートは**上から約 160 で止まる**（後ろにストーリーの写真が覗く）。
        // 画面の高さは機種で違うので、板の画面（844）に対する割合で持つ（2026-10-16 判断）
        .presentationDetents([.fraction(Self.detentFraction)])
        .presentationDragIndicator(.visible)
    }

    /// 「返信 3」（明朝 22 ＋ SF 300 の数字）。読めていない間は数を出さない（`StoryInsightsView` と同じ）
    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("返信", "Replies"))
                .font(JPFont.cardTitle)
            if loaded {
                Text("\(shown.count)")
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
            let actions = StoryReplyActions(item, me: hidden.owner)
            // 「…」の無い行（自分の返信）は前のとおり右に 32 空ける——吹き出しが右端まで伸びない
            Spacer(minLength: actions.trailingSpace)
            if actions.hasMenu {
                replyMenu(item, actions: actions)
            }
        }
    }

    /// 返信の「…」（通報・この人をブロック・審査 1.2・2026-10-16）。形はコメントの「…」と同じ
    /// （`PhotoDetailView.commentMenu`: 系統のメニュー・ブロックは `role: .destructive`・印は小さく当たりは 44pt）。
    /// 板（StoryReplies）に「…」は無いが、審査で要る口なので行の右上に足した
    private func replyMenu(_ item: StoryReply, actions: StoryReplyActions) -> some View {
        Menu {
            if actions.report {
                Button { report(item) } label: {
                    Label(L("通報", "Report"), systemImage: "flag")
                }
            }
            if actions.block {
                Button(role: .destructive) { pendingBlock = item } label: {
                    Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("\(item.displayName)さんの返信の操作", "More actions for reply from \(item.displayName)"))
        .accessibilityIdentifier("storyReplies.menu")
    }

    /// 通報（問い合わせの宛先へのメール・`ModerationService.storyReplyReportURL` の注記）。
    /// メールを開けない端末では、宛先を知らせる（黙って何も起きないようにしない）
    private func report(_ item: StoryReply) {
        let target = ModerationService.ReportedComment(id: item.id, authorId: item.uid ?? "",
                                                       authorName: item.displayName, text: item.body)
        guard let url = ModerationService.storyReplyReportURL(target, storyId: storyId) else { return }
        openURL(url) { accepted in
            if !accepted { mailUnavailable = true }
        }
    }

    /// ブロック（確認の後）。**サーバーに送り、その場で一覧から外す**
    private func block(_ item: StoryReply) async {
        guard let uid = item.uid else { return }
        do {
            try await hidden.blockAndHide(uid, environment: environment)
            blockedHere.insert(uid)
            toasts.show(L("ブロックしました。設定から解除できます。", "Blocked. You can undo this in Settings."))
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block"),
                        kind: .failure)
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
    /// シートの上端（板の画面 844 のうち上から 160）と、それをシートの高さの割合にしたもの
    static let boardTop: CGFloat = 160
    static let boardScreenHeight: CGFloat = 844
    static let detentFraction: CGFloat = 1 - boardTop / boardScreenHeight
}

/// 返信の「…」に何を出すか（画面を持たない決まり・テストで見張る）。2026-10-16
struct StoryReplyActions: Equatable {
    /// 通報（本文がある返信だけ・自分の返信には出さない）
    let report: Bool
    /// ブロック（相手が分かり・自分でなく・退会していない人だけ）
    let block: Bool

    init(_ reply: StoryReply, me: String?) {
        let mine = reply.uid != nil && reply.uid == me
        report = !mine && !reply.body.isEmpty
        block = !mine && reply.uid?.isEmpty == false && reply.deleted != true
    }

    init(report: Bool, block: Bool) {
        self.report = report
        self.block = block
    }

    /// 「…」を出すか
    var hasMenu: Bool { report || block }

    /// 吹き出しの右に必ず空ける幅。「…」がある行は「…」（44pt）が幅を取るので詰め、
    /// 無い行（自分の返信）は v2 の板どおり節の間（32）を空ける
    var trailingSpace: CGFloat { hasMenu ? JPSpace.s : JPSpace.section }

    /// このシートでブロックした人の返信を外す
    static func visible(_ items: [StoryReply], blockedHere: Set<String>) -> [StoryReply] {
        guard !blockedHere.isEmpty else { return items }
        return items.filter { reply in reply.uid.map { !blockedHere.contains($0) } ?? true }
    }

    /// メールを開けない端末で出す確認の題・本文・ボタン（宛先は本文に**全部**出す。トーストでは切れた）
    static var mailUnavailableTitle: String { L("メールを開けませんでした", "Couldn\u{2019}t open Mail") }

    static var mailUnavailable: String {
        L("\(LegalConsent.contactEmail) へ、返信の内容を添えてお知らせください。",
          "Please email \(LegalConsent.contactEmail) with the reply.")
    }

    static var copyAddress: String { L("宛先をコピー", "Copy address") }
}

/// お知らせから開く返信の一覧の行き先（`NotificationsView`・2026-10-16）
struct StoryRepliesTarget: Identifiable, Equatable {
    let storyId: String
    var id: String { storyId }
}

/// **お知らせの「ストーリーへの返信」から開く返信の一覧**（2026-10-16・行き止まりの直し）。
///
/// 中身は見る画面の返信の一覧と同じ `StoryRepliesSheet`。読み込み・ブロックの絞り・読み直しの失敗の
/// 出し方も見る画面（`StoryViewerView.reloadReplies`）と同じ決まり（`StoryInsightsView.failureOutcome`）
struct StoryRepliesLoader: View {

    let storyId: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @State private var replies: [StoryReply] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var reloading = false
    @State private var notice: String?

    var body: some View {
        StoryRepliesSheet(items: replies.textReplies, loaded: loaded, failed: failed,
                          reloading: reloading, notice: notice,
                          onReload: { await load(pulled: true) },
                          storyId: storyId)
            .task(id: storyId) { await load(pulled: false) }
    }

    private func load(pulled: Bool) async {
        guard !reloading else { return }
        reloading = true
        defer { reloading = false }
        do {
            let fetched = try await environment.stories.replies(id: storyId)
            replies = BlockFilter.replies(fetched, blocked: hidden.blockedUserIds)
            failed = false
            loaded = true
            notice = nil
        } catch {
            switch StoryInsightsView.failureOutcome(error, firstLoad: !loaded, pulled: pulled) {
            case .silent: break
            case .errorMessage: failed = true
            case .refreshNotice: notice = L("読み直せませんでした", "Couldn't refresh")
            }
        }
    }
}
