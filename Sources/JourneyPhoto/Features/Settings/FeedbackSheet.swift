import PhotosUI
import SwiftUI
import UIKit

/// 意見を送る（札 #546・2026-11-11 owner 承認「フォームまかせる」「形式は自由記述」）。
///
/// **書いて送るだけ**: 開く → 書く → 送る（押す回数 3）。自由に書く欄1つが主で、👍／👎・種類の選択は置かない。
/// 「写真を添える」「返事が欲しい」は任意で、欄の下に小さな文字のボタンとして控えめに置く（押さなくても送れる）。
///
/// 形は通報のシート（板 v2 Report・`ReportSheet`）にそろえた: 左寄せの明朝の題と右の ×、
/// 欄は `JPField`、下に固定した主ボタン（写真の無い画面＝真鍮の塗りに墨・`JPPillStyle.main(onPhoto: false)`）。
///
/// 送ったら閉じて「届きました」。**圏外なら下書きに残して閉じ、つながったら送る**（`FeedbackOutbox`）——
/// 書いたものを失わせない・送れるまで待たせない。送り直しても届かない理由（その日の上限など）だけはシートに残して読ませる。
struct FeedbackSheet: View {

    /// どの画面から開いたか（英数字の短い名前。サーバーの `screen`）
    let screen: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var wantsReply = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var preview: UIImage?
    @State private var isPreparingPhoto = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !isSending && !isPreparingPhoto }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    JPField(L("ひとこと", "Your feedback"), multiline: true) {
                        TextField(L("使ってみて思ったこと・困ったこと・欲しい機能など、自由に書いてください",
                                    "Anything you noticed, got stuck on, or would like to see"),
                                  text: $text, axis: .vertical)
                            .lineLimit(5...12)
                            .focused($focused)
                            // サーバーと同じ上限で止める（黙って切らない・数え方は UTF-16）
                            .onChange(of: text) { old, new in
                                let kept = PostLimits.limited(old: old, new: new, limit: FeedbackService.textMax)
                                if kept != new { text = kept }
                            }
                            .accessibilityIdentifier("feedback.text")
                    }
                    extras
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xs)
                .padding(.bottom, JPSpace.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .interactiveDismissDisabled(isSending)
        .safeAreaInset(edge: .bottom) { footer }
        .background(WebTheme.sheet)
        .presentationBackground(WebTheme.sheet)
        .preferredColorScheme(.dark)
        // 開いたらすぐ書ける（押す回数を増やさない）
        .onAppear { focused = true }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private var header: some View {
        HStack {
            Text(L("意見を送る", "Send feedback"))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .jpGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel(Labels.Common.close)
        }
        .padding(.leading, JPSpace.l)
        .padding(.trailing, JPSpace.s)
        .padding(.top, JPSpace.s)
    }

    /// 任意の2つ（写真を添える・返事が欲しい）。**控えめな文字のボタン**（13・text-2・当たり 44）。
    /// 返事が欲しいは**ログインしている人だけ**（宛先の無い人に返事を約束しない）
    private var extras: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview {
                HStack(spacing: JPSpace.s) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                        .accessibilityLabel(L("添えた写真", "Attached photo"))
                    Button {
                        photo = nil
                        self.preview = nil
                        photoItem = nil
                    } label: {
                        Text(L("写真を外す", "Remove photo"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text2)
                            .frame(minHeight: WebTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityIdentifier("feedback.removePhoto")
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(isPreparingPhoto ? L("写真を準備しています…", "Preparing photo…") : L("写真を添える（任意）", "Attach a photo (optional)"),
                          systemImage: "photo")
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                        .frame(minHeight: WebTheme.minTapTarget)
                }
                .disabled(isSending || isPreparingPhoto)
                .accessibilityIdentifier("feedback.attachPhoto")
            }
            if auth.userId != nil {
                Button { wantsReply.toggle() } label: {
                    Label(L("返事が欲しい（任意）", "I'd like a reply (optional)"),
                          // 選んだら真鍮の印（黒地の上の合図・形でも伝える）
                          systemImage: wantsReply ? "checkmark.circle.fill" : "circle")
                        .font(JPFont.caption)
                        .foregroundStyle(wantsReply ? WebTheme.accent : WebTheme.text2)
                        .frame(minHeight: WebTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityAddTraits(wantsReply ? .isSelected : [])
                .accessibilityIdentifier("feedback.wantsReply")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(WebTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("feedback.error")
            }
            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView().tint(WebTheme.accentText)
                            Text(L("送っています…", "Sending…"))
                        }
                    } else {
                        Text(L("送る", "Send"))
                    }
                }
                .jpPillButton(JPPillStyle.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityIdentifier("feedback.send")
        }
        .jpBottomBar()
    }

    /// 写真は `ImagePreparer` を通した JPEG だけを送る（位置・撮影情報を落とし、長辺 1920 に縮めたもの）
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = L("写真を読み込めませんでした", "Couldn't load the photo")
                return
            }
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "feedback")
            }.value
            guard prepared.data.count <= FeedbackService.photoMaxBytes else {
                errorMessage = L("写真が大きすぎます", "The photo is too large")
                return
            }
            errorMessage = nil
            photo = prepared.data
            preview = UIImage(data: prepared.data)
        } catch {
            errorMessage = L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    private func submit() async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let draft = FeedbackDraft(text: trimmed, screen: screen, wantsReply: wantsReply, userId: auth.userId)
        let outbox = FeedbackOutbox()
        // **先に下書きとして残してから送る**（送っている間に閉じても書いたものが消えない）
        try? outbox.save(draft, photo: photo)
        let service = environment.feedback
        let outcome = await outbox.deliver(draft, currentUserId: auth.userId) { draft, photo, signedIn in
            try await service.send(draft, photo: photo, signedIn: signedIn)
        }
        switch outcome {
        case .sent:
            toasts.show(L("届きました。ありがとうございます", "Received — thank you!"))
            dismiss()
        case .unreachable where connectivity.isOffline:
            toasts.show(L("つながったら送ります", "We'll send it when you're back online"))
            dismiss()
        case .unreachable, .serverBusy:
            // 電波はあるのに届かなかった（サーバーが遠い・混んでいる）。「つながったら」とは言わない
            toasts.show(L("いまは送れませんでした。あとで自動でもう一度送ります",
                          "Couldn't send right now. We'll try again automatically."))
            dismiss()
        case .tomorrow:
            // その日の上限。消さずに残し、次の日に自動で送る
            toasts.show(L("今日はこれ以上送れません。明日、自動で送ります",
                          "You've reached today's limit. We'll send it tomorrow."))
            dismiss()
        case .dropped(let message):
            errorMessage = message
        }
    }
}
