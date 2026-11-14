import SwiftUI

/// 写真を通報する。
///
/// **審査で見られる導線。** 写真ごとに1タップで届くところに置く
/// （設定の奥に隠さない）。
struct ReportSheet: View {

    let photoId: String
    /// 通報と同時にブロックもできるようにする。相手が分からない場合は nil
    let ownerId: String?
    /// メッセージの会話の通報（2026-11-10・札 #505 の画面案「通報」）。写真の通報と同じ型で、理由に
    /// 「未成年へのいやな接触・誘い出し」「なりすまし」を並べ、送られる範囲（直近の抜粋）と相手に知らされないことを書く。
    /// 送る口は `POST /dm/{id}/report`（`photoId` は使わない）。ブロックの相手は `ownerId`（会話の相手）
    var conversation: Conversation? = nil
    /// コメントの通報（2026-10-11）。写真の通報の口に、誰のどのコメントかを補足に書いて送る
    /// （`ModerationService.commentReportNote`）。ブロックの相手はコメントを書いた人
    var comment: ModerationService.ReportedComment? = nil
    /// すれちがいのカードのひとことの通報（2026-10-16）。署名が無いので、写真は隠さず・持ち主をブロックする口も
    /// 出さない。補足に印と本文を入れて送る（`ModerationService.passNoteReportNote`）
    var passNote: String? = nil
    /// 写真の通報で、同じカードのひとことを前に通報していたら、その本文（上書きで消えないよう補足に一緒に入れる）
    var carriedPassNote: String? = nil
    /// 受け付けた（閉じる前に呼ぶ）。すれちがいのひとことの通報の後に、そのひとことを伏せるのに使う
    var onReported: (() -> Void)? = nil
    /// 通報する写真の小さな札（v2 の板 Report・2026-10-14: 「通報する写真を上に小さく出して取り違えを防ぐ」）。
    /// 写真の詳細から開いたときだけ渡す。無ければ札を出さない（ホームの格子・ストーリーからの通報）
    var subject: Subject? = nil

    /// 通報する会話
    struct Conversation: Equatable {
        let id: String
        /// 相手の名前（見出しに出す）
        let name: String
    }

    /// 通報する写真の札の中身
    struct Subject: Equatable {
        let title: String
        let imageURL: URL?
        /// 「霧の人 · @kiri_photo」。分からなければ nil
        let byline: String?
    }

    /// 「この人をブロックする」の相手（コメントの通報ならコメントを書いた人）
    private var blockTarget: String? { passNote != nil ? nil : (comment?.authorId ?? ownerId) }
    /// 補足の上限（コメントの通報は本文を入れる分だけ短い）
    private var noteLimit: Int {
        comment == nil && passNote == nil ? ModerationService.reportNoteMax : ModerationService.commentReportUserNoteMax
    }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ModerationService.ReportReason = .harassment
    @State private var dmReason: DMReportReason = .harassment
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var done = false

    var body: some View {
        // 板 47: 左寄せの明朝の見出しと右の ×、理由は丸の選択の札、
        // 下に固定した白いカプセル。**ナビバーは使わない**
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if done {
                        receipt
                    } else {
                        if let passNote {
                            Text(L("乗車券に書かれた言葉：\(passNote)", "Text on a Pass ticket: \(passNote)"))
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.muted2)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if comment == nil, let subject {
                            subjectCard(subject)
                        }
                        if let comment {
                            // どのコメントを通報するか（押し間違いに気づけるように）
                            Text(L("\(comment.authorName)さんのコメント：「\(comment.text)」",
                                   "Comment by \(comment.authorName): \"\(comment.text)\""))
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.muted2)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if passNote != nil || carriedPassNote != nil {
                            // サーバーの通報は「1人1写真に1件」で上書きされる。黙って消えないよう言う
                            Text(passNote != nil
                                 ? L("同じ写真を前に通報していれば、その通報はこの通報で置き換わります（1つの写真につき1件）。",
                                     "If you reported this photo before, that report will be replaced by this one (one per photo).")
                                 : L("前に送ったひとことの通報は置き換わるため、この通報の補足に一緒に入れて送ります。",
                                     "Your earlier report about the note will be replaced, so it\u{2019}s included in this report."))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("report.replaceNotice")
                        }
                        reasons
                        JPField(L("補足（任意）", "Details (optional)"), multiline: true) {
                            TextField(L("状況を書いてください", "Tell us what happened"), text: $note, axis: .vertical)
                                .lineLimit(3...6)
                                // **500 で止める。** 送る前に黙って切っていたので、書いた末尾が
                                // 届いていないことに気づけなかった（数え方はサーバーと同じ UTF-16）
                                .onChange(of: note) { old, new in
                                    let kept = PostLimits.limited(old: old, new: new, limit: noteLimit)
                                    if kept != new { note = kept }
                                }
                        }
                        if blockTarget != nil {
                            JPCard(fill: WebTheme.surface) {
                                JPToggleRow(
                                    title: L("この人をブロックする", "Also block this person"),
                                    detail: conversation != nil
                                        ? L("ブロックすると、おたがいの投稿、ストーリー、メッセージ、通知が見えなくなります。",
                                            "Blocking hides each other's posts, stories, messages and notifications.")
                                        : L("ブロックすると、おたがいの投稿、ストーリー、通知が見えなくなります。", "Blocking hides each other's posts, stories and notifications."),
                                    isOn: $alsoBlock)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            // 複数行の欄は Return が改行なので、払って下げる口を残す
            .scrollDismissesKeyboard(.interactively)
        }
        // **送っている間は閉じさせない。** 閉じた瞬間に呼び出し側の後始末
        // （ストーリーの `afterReport`）が走り、まだ記録されていない通報を
        // 見落とす。そのあと送信が成立しても後始末は二度と呼ばれない
        .interactiveDismissDisabled(isWorking)
        .safeAreaInset(edge: .bottom) { footer }
        .background(Self.sheetBackground)
        .presentationBackground(Self.sheetBackground)
        .preferredColorScheme(.dark)
    }

    /// シートの地（v2 の板: surface-2 #161617。画面の黒より一段浮かせる）。
    /// 札は `JPCard(fill: WebTheme.surface)`——既定の札の地（#0E0E0F）はシートより暗く、札に見えない
    private static let sheetBackground = WebTheme.sheet

    private var header: some View {
        // 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187。前は v2 の板どおり右上のガラスの ×）
        HStack(spacing: JPSpace.s) {
            SheetCloseButton(onContent: true)
                .disabled(isWorking)
            // v2 の板は明朝 24。字の段（32/26/22/20/18）に無いので、画面の題の 26 にそろえた
            Text(passNote != nil ? L("書かれた言葉を通報", "Report text")
                 : comment == nil || conversation != nil ? L("通報", "Report") : L("コメントを通報", "Report comment"))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.leading, JPSpace.s)
        .padding(.trailing, JPSpace.l)
        .padding(.top, JPSpace.s)
    }

    /// 理由（v2 の板 Report: 「理由（1つ）」の見出しの下に、左に丸の行を白 8% の線で区切って並べる。札にしない）。
    /// 選んだ丸は**真鍮の太い輪**（黒地の上の合図・形でも伝える）。読み上げは「選択中」
    private var reasons: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(L("理由（1つ）", "Reason (choose one)"))
                .font(JPFont.caption.weight(.medium))
                .foregroundStyle(WebTheme.text2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if conversation != nil {
                    let all = DMReportReason.allCases
                    ForEach(Array(all.enumerated()), id: \.element) { index, item in
                        ReportReasonRow(title: item.label, selected: dmReason == item,
                                        isLast: index == all.count - 1) { dmReason = item }
                    }
                } else {
                    let all = ModerationService.ReportReason.allCases
                    ForEach(Array(all.enumerated()), id: \.element) { index, item in
                        ReportReasonRow(title: item.label, selected: reason == item,
                                        isLast: index == all.count - 1) { reason = item }
                    }
                }
            }
        }
    }

    /// 通報する写真の小さな札（v2 の板: 44 の写真・題 14 の太字・作者 12 の text-3）
    private func subjectCard(_ subject: Subject) -> some View {
        JPCard(fill: WebTheme.surface) {
            HStack(spacing: JPSpace.s) {
                RemoteImage(url: subject.imageURL)
                    .frame(width: Self.subjectThumb, height: Self.subjectThumb)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if !subject.title.isEmpty {
                        Text(subject.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(1)
                    }
                    if let byline = subject.byline {
                        Text(byline)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("通報する写真: ", "Reporting: ") + [subject.title, subject.byline ?? ""]
            .filter { !$0.isEmpty }.joined(separator: PhotoMetaLine.separator))
        .accessibilityIdentifier("report.subject")
    }

    /// 札の写真の大きさ（v2 の板の 44）
    nonisolated static let subjectThumb: CGFloat = 44

    /// 受け付けたあと、ブロックだけ落ちたとき（閉じずに理由を読ませる）
    private var receipt: some View {
        Label(L("受け付けました。内容を確認します。", "Received. We'll review it."), systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(WebTheme.text)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // **赤字はボタンのすぐ上。** 札の末尾に置くと、理由7行の下で
            // スクロールしないと見えず、押しても何も起きないように見える
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(WebTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                if done { dismiss() } else { Task { await submit() } }
            } label: {
                Group {
                    if isWorking {
                        // 白いカプセルの上なので回転は墨で。文字も添える（読み上げが空にならない）
                        HStack(spacing: 8) {
                            ProgressView().tint(WebTheme.accentText)
                            Text(L("送っています…", "Sending…"))
                        }
                    } else {
                        Text(done ? Labels.Common.close : L("通報する", "Report"))
                    }
                }
                // 写真の無い画面の主ボタンは真鍮の塗り（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29）・
                // v2 の板も真鍮の塗り）。決まりは `JPPillStyle.main(onPhoto:)` で引く
                .jpPillButton(JPPillStyle.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            if conversation != nil {
                // 送られる範囲と、相手に知らされないこと（画面案「通報」）
                Text(L("この会話の直近のやりとりが運営に届きます。相手には知らされません。",
                       "The latest messages in this conversation are sent to our team. They won't be told."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("report.dmScope")
            }
            // 「対応しました」とは言わない——読むのは人で、すぐには終わらない
            Text(L("結果をお伝えできない場合があります。", "We may not be able to tell you the outcome."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.center)
        }
        .jpBottomBar()
    }

    /// 落とす相手を公開一覧の側へ渡し直す。
    private func applyHidden() async {
        await environment.gallery.setHidden(hidden.snapshot)
    }

    private func submit() async {
        // **送っている間・受け付けた後は送らない。** ボタンの `disabled` は描き直しの後にしか
        // 効かないので、同じフレームで2回押すと通報が2回送られていた
        guard !isWorking, !done else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        // ブロックを控えるのは押した人の控えだけ（待っている間に人が替わったら書かない）
        let blocker = hidden.owner
        do {
            if let conversation {
                // 会話の通報（2026-11-10 札 #505）。写真の印は付けない（会話の写しはサーバーが取る）
                try await environment.dm.report(conversation.id, reason: dmReason.serverReason,
                                                 note: dmReason.note(adding: note))
                await finishReport(blocker: blocker)
                return
            }
            let sentNote = passNote.map { ModerationService.passNoteReportNote($0, note: note) }
                ?? carriedPassNote.map { ModerationService.photoReportWithPassNote(note, passNote: $0) }
                ?? comment.map { ModerationService.commentReportNote($0, note: note) } ?? note
            try await environment.moderation.report(photoId: photoId, reason: reason, note: sentNote)
            // **押したあと実際に消す。** 通報が受け付けられただけで、
            // 通報した人の画面に出続けるなら意味がない。
            // コメントの通報では写真は消さない（通報したのはコメント。消すならブロックで）
            if comment == nil && passNote == nil {
                hidden.markReported(photoId, for: blocker)
            }
            await finishReport(blocker: blocker)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("通報を受け付けられませんでした", "Couldn't submit the report")
        }
    }

    /// 受け付けたあと（写真・会話の通報で同じ）: 一緒にブロック → 公開一覧へ渡し直す → 知らせる
    private func finishReport(blocker: String?) async {
        if alsoBlock, let blockTarget {
            // **ブロックが落ちても通報は成立している。** ここで投げ直すと
            // 「通報できなかった」と誤解させるので、文言を分ける
            do {
                try await environment.moderation.block(userId: blockTarget)
                hidden.block(blockTarget, for: blocker)
            } catch {
                errorMessage = L("通報は受け付けました。ブロックはうまくいきませんでした。相手のプロフィールからもう一度お試しください。", "Your report was received, but blocking failed. Try again from their profile.")
            }
        }
        await applyHidden()
        onReported?()
        // **受け付けたことを伝える。** それまでは黙って閉じるだけで、
        // 押した人には届いたのか分からなかった
        // **知らせは1つ。** 全部うまくいけば閉じてトーストで伝える
        // （以前はシートの完了画面とトーストの二重だった）。ブロックだけ
        // 落ちたときは閉じずに、その旨を読ませる。
        // ストーリーの全画面（`StoryReelView`）にも同じ知らせを重ねてある
        if errorMessage == nil {
            toasts.show(L("通報を受け付けました。ありがとうございます。",
                          "Thanks — your report was received."))
            dismiss()
        } else {
            done = true
        }
    }
}

/// 通報の理由の1行（v2 の板 Report・2026-10-14）。**左に丸**、選ぶと真鍮の太い輪（輪の幅 6 で中が小さく残る）。
/// 行の高さは 48（押せる 44 より大きい）、行の間は白 8% の線（最後の行は引かない）。
///
/// 共通の `JPRadioRow`（右に白い丸・札の中の行）は設定などが使っているので変えない——v2 の通報の板だけの形
private struct ReportReasonRow: View {

    let title: String
    let selected: Bool
    let isLast: Bool
    let action: () -> Void

    /// 行の高さ（v2 の板の 48）
    static let height: CGFloat = JPHeight.field
    /// 丸の大きさと、選んだときの輪の幅（v2 の板: 20・6）
    static let ring: CGFloat = 20
    static let selectedRingWidth: CGFloat = 6

    var body: some View {
        Button(action: action) {
            HStack(spacing: JPSpace.s) {
                Circle()
                    .strokeBorder(selected ? WebTheme.accent : Color.white.opacity(0.35),
                                  lineWidth: selected ? Self.selectedRingWidth : 1.5)
                    .frame(width: Self.ring, height: Self.ring)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 会話の通報の理由（画面案「通報」の並び・2026-11-10 札 #505）。
///
/// サーバーが受ける理由は写真の通報と同じ許可リスト（`REPORT_REASONS`）。画面案の「なりすまし」はリストに無いので、
/// **2026-11-10 判断: 「その他」で送り、補足の頭に「なりすまし」と書く**（サーバーを変えずに運営が読める）
enum DMReportReason: String, CaseIterable, Identifiable {
    case harassment, sexual, minor, spam, impersonation, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: return L("いやがらせ、攻撃", "Harassment or attacks")
        case .sexual: return L("性的な内容、つきまとい", "Sexual content or stalking")
        case .minor: return L("未成年へのいやな接触、誘い出し", "Inappropriate contact with a minor")
        case .spam: return L("広告、勧誘、スパム", "Spam or advertising")
        case .impersonation: return L("なりすまし", "Impersonation")
        case .other: return L("その他", "Something else")
        }
    }

    /// サーバーへ送る理由
    var serverReason: ModerationService.ReportReason {
        switch self {
        case .harassment: return .harassment
        case .sexual: return .sexual
        case .minor: return .minor
        case .spam: return .spam
        case .impersonation, .other: return .other
        }
    }

    /// 送る補足。なりすましは頭に印を付ける（運営が読む・日本語で固定）
    func note(adding userNote: String) -> String {
        let trimmed = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self == .impersonation else { return trimmed }
        return trimmed.isEmpty ? "なりすまし" : "なりすまし：" + trimmed
    }
}
