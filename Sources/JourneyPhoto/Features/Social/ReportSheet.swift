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
    @EnvironmentObject private var moderation: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ModerationService.ReportReason = .harassment
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("受け付けました。内容を確認します。", systemImage: "checkmark.circle")
                    } footer: {
                        // 「対応しました」とは言わない——読むのは人で、すぐには終わらない
                        Text("結果をお伝えできない場合があります。")
                    }
                } else {
                    Section("理由") {
                        Picker("理由", selection: $reason) {
                            ForEach(ModerationService.ReportReason.allCases) { reason in
                                Text(reason.label).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section("補足（任意）") {
                        TextField("状況を書いてください", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    if ownerId != nil {
                        Section {
                            Toggle("この人をブロックする", isOn: $alsoBlock)
                        } footer: {
                            Text("ブロックすると、おたがいの投稿・ストーリー・通知が見えなくなります。")
                        }
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
                    }

                    Section {
                        Button("通報する") { Task { await submit() } }
                            .disabled(isWorking)
                    }
                }
            }
            .navigationTitle("通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    /// 落とす相手を公開一覧の側へ渡し直す。
    private func applyHidden() async {
        await environment.gallery.setHidden(
            userIds: moderation.blockedUserIds,
            photoIds: moderation.reportedPhotoIds
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
            moderation.markReported(photoId)
            if alsoBlock, let ownerId {
                // **ブロックが落ちても通報は成立している。** ここで投げ直すと
                // 「通報できなかった」と誤解させるので、文言を分ける
                do {
                    try await environment.moderation.block(userId: ownerId)
                    moderation.block(ownerId)
                } catch {
                    errorMessage = "通報は受け付けました。ブロックはうまくいきませんでした。設定からもう一度お試しください。"
                }
            }
            await applyHidden()
            done = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "通報を受け付けられませんでした"
        }
    }
}
