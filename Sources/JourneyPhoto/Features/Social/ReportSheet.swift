import SwiftUI

/// 写真を通報する。
///
/// **審査で見られる導線。** 写真ごとに1タップで届くところに置く
/// （設定の奥に隠さない）。
struct ReportSheet: View {

    let photoId: String
    /// 通報と同時にブロックもできるようにする。相手が分からない場合は nil
    let ownerId: String?

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
                        reasons
                        JPField(L("補足（任意）", "Details (optional)"), multiline: true) {
                            TextField(L("状況を書いてください", "Tell us what happened"), text: $note, axis: .vertical)
                                .lineLimit(3...6)
                        }
                        if ownerId != nil {
                            JPCard {
                                JPToggleRow(
                                    title: L("この人をブロックする", "Also block this person"),
                                    detail: L("ブロックすると、おたがいの投稿・ストーリー・通知が見えなくなります。", "Blocking hides each other's posts, stories and notifications."),
                                    isOn: $alsoBlock)
                            }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(WebTheme.danger).font(.callout)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .background(Self.sheetBackground)
        .presentationBackground(Self.sheetBackground)
        .preferredColorScheme(.dark)
    }

    /// シートの地（板: #0d0d0e。画面の黒より一段浮かせる）
    private static let sheetBackground = Color(red: 13 / 255, green: 13 / 255, blue: 14 / 255)

    private var header: some View {
        HStack {
            Text(L("通報", "Report"))
                .font(JPFont.display(24, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 10)
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 10) {
            JPSectionTitle(L("理由", "Reason"))
            JPCard {
                ForEach(Array(ModerationService.ReportReason.allCases.enumerated()), id: \.element) { index, item in
                    if index > 0 { JPCardDivider() }
                    JPRadioRow(title: item.label, selected: reason == item) { reason = item }
                }
            }
        }
    }

    /// 受け付けたあと、ブロックだけ落ちたとき（閉じずに理由を読ませる）
    private var receipt: some View {
        Label(L("受け付けました。内容を確認します。", "Received. We'll review it."), systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(WebTheme.text)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                if done { dismiss() } else { Task { await submit() } }
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(done ? Labels.Common.close : L("通報する", "Report"))
                    }
                }
                .jpPillButton()
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            // 「対応しました」とは言わない——読むのは人で、すぐには終わらない
            Text(L("結果をお伝えできない場合があります。", "We may not be able to tell you the outcome."))
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)
        }
        .jpBottomBar()
    }

    /// 落とす相手を公開一覧の側へ渡し直す。
    private func applyHidden() async {
        await environment.gallery.setHidden(
            userIds: hidden.blockedUserIds,
            photoIds: hidden.reportedPhotoIds
        )
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await environment.moderation.report(photoId: photoId, reason: reason, note: note)
            // **押したあと実際に消す。** 通報が受け付けられただけで、
            // 通報した人の画面に出続けるなら意味がない
            hidden.markReported(photoId)
            if alsoBlock, let ownerId {
                // **ブロックが落ちても通報は成立している。** ここで投げ直すと
                // 「通報できなかった」と誤解させるので、文言を分ける
                do {
                    try await environment.moderation.block(userId: ownerId)
                    hidden.block(ownerId)
                } catch {
                    errorMessage = L("通報は受け付けました。ブロックはうまくいきませんでした。設定からもう一度お試しください。", "Your report was received, but blocking failed. Try again from Settings.")
                }
            }
            await applyHidden()
            // **受け付けたことを伝える。** それまでは黙って閉じるだけで、
            // 押した人には届いたのか分からなかった
            toasts.show(L("通報を受け付けました。ありがとうございます。",
                          "Thanks — your report was received."))
            // **知らせは1つ。** 全部うまくいけば閉じてトーストで伝える
            // （以前はシートの完了画面とトーストの二重だった）。ブロックだけ
            // 落ちたときは閉じずに、その旨を読ませる
            if errorMessage == nil {
                dismiss()
            } else {
                done = true
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("通報を受け付けられませんでした", "Couldn't submit the report")
        }
    }
}
