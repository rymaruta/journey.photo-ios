import SwiftUI

/// 写真を通報する。
///
/// **審査で見られる導線。** 写真ごとに1タップで届くところに置く
/// （設定の奥に隠さない）。
struct ReportSheet: View {

    let photoId: String
    /// 通報と同時にブロックもできるようにする。相手が分からない場合は nil
    let ownerId: String?
    /// コメントの通報（2026-10-11）。写真の通報の口に、誰のどのコメントかを補足に書いて送る
    /// （`ModerationService.commentReportNote`）。ブロックの相手はコメントを書いた人
    var comment: ModerationService.ReportedComment? = nil
    /// すれちがいのカードのひとことの通報（2026-10-16）。署名が無いので、写真は隠さず・持ち主をブロックする口も
    /// 出さない。補足に印と本文を入れて送る（`ModerationService.passNoteReportNote`）
    var passNote: String? = nil
    /// 通報する写真の小さな札（v2 の板 Report・2026-10-14: 「通報する写真を上に小さく出して取り違えを防ぐ」）。
    /// 写真の詳細から開いたときだけ渡す。無ければ札を出さない（ホームの格子・ストーリーからの通報）
    var subject: Subject? = nil

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
                            Text(L("すれちがいのカードのひとこと：「\(passNote)」", "Note on a Pass card: \"\(passNote)\""))
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
                                    detail: L("ブロックすると、おたがいの投稿・ストーリー・通知が見えなくなります。", "Blocking hides each other's posts, stories and notifications."),
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
        HStack {
            // v2 の板は明朝 24。字の段（32/26/22/20/18）に無いので、画面の題の 26 にそろえた
            Text(passNote != nil ? L("ひとことを通報", "Report note")
                 : comment == nil ? L("通報", "Report") : L("コメントを通報", "Report comment"))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                // v2 の板: ガラスの丸（44pt）の ×
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .jpGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel(Labels.Common.close)
        }
        .padding(.leading, JPSpace.l)
        .padding(.trailing, JPSpace.s)
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
                let all = ModerationService.ReportReason.allCases
                ForEach(Array(all.enumerated()), id: \.element) { index, item in
                    ReportReasonRow(title: item.label, selected: reason == item,
                                    isLast: index == all.count - 1) { reason = item }
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
            let sentNote = passNote.map { ModerationService.passNoteReportNote($0, note: note) }
                ?? comment.map { ModerationService.commentReportNote($0, note: note) } ?? note
            try await environment.moderation.report(photoId: photoId, reason: reason, note: sentNote)
            // **押したあと実際に消す。** 通報が受け付けられただけで、
            // 通報した人の画面に出続けるなら意味がない。
            // コメントの通報では写真は消さない（通報したのはコメント。消すならブロックで）
            if comment == nil && passNote == nil {
                hidden.markReported(photoId, for: blocker)
            }
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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("通報を受け付けられませんでした", "Couldn't submit the report")
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
