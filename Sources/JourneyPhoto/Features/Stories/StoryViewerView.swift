import SwiftUI

/// ストーリーを全画面で見る。
struct StoryViewerView: View {

    let story: Story
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var reply = ""
    @State private var message: String?
    @State private var viewers: [StoryViewer] = []
    @State private var showViewers = false
    @State private var replies: [StoryReply] = []
    @State private var showReplies = false
    /// 返信を読めなかった。**空の一覧と区別する**（数は出ているのに
    /// 何も無い画面は「消えた」に見える）
    @State private var repliesFailed = false
    /// 送っている最中。**二度押しで2件送らない**
    @State private var isSending = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                StoryMedia(story: story)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let caption = story.caption, !caption.isEmpty {
                    Text(caption)
                        .foregroundStyle(.white)
                        .padding(12)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 4)
                }

                footer
            }
        }
        .task {
            // **見たことを伝えるのは1回。** 失敗しても画面は止めない
            await environment.stories.markViewed(id: story.id)
            if isMine {
                viewers = (try? await environment.stories.viewers(id: story.id)) ?? []
                // **返信は本人だけが読める。** 読めないと、送られた返信が
                // どこにも出ない（送る側の画面だけあった）
                do {
                    replies = try await environment.stories.replies(id: story.id)
                    repliesFailed = false
                } catch {
                    repliesFailed = true
                }
            }
        }
        .sheet(isPresented: $showReplies) {
            NavigationStack {
                List {
                    if repliesFailed {
                        Text(Labels.Common.loadFailed).foregroundStyle(.secondary)
                    } else if replies.isEmpty {
                        Text(L("まだ返信はありません", "No replies yet")).foregroundStyle(.secondary)
                    }
                    ForEach(replies) { reply in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.name ?? L("だれか", "Someone"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reply.body)
                        }
                    }
                }
                .navigationTitle(L("返信 \(replies.count)", "\(replies.count) replies"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showViewers) {
            NavigationStack {
                List(viewers) { viewer in
                    Text(viewer.name)
                }
                .navigationTitle(L("見た人 \(viewers.count)", "\(viewers.count) viewers"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(story.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .accessibilityLabel(Labels.Common.close)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var footer: some View {
        if isMine {
            HStack(spacing: 16) {
                Button(L("見た人 \(viewers.count)", "\(viewers.count) viewers")) { showViewers = true }
                // **返信の数はサーバーが持っている**（`replyCount`）。
                // 読み込み前でも数が出るよう、取れた一覧より多い方を出す
                Button(L("返信 \(replyBadge)", "\(replyBadge) replies")) { showReplies = true }
                // 24時間で消える前に、自分の写真として残す
                Button(L("残す", "Keep")) { Task { await keep() } }
                Button(Labels.Common.delete, role: .destructive) { Task { await deleteStory() } }
            }
            .font(.footnote)
            .padding(16)
        } else {
            VStack(spacing: 8) {
                // **押すだけで返せる**（Web の StoryViewer と同じ6つ）。
                // 打つより先に、これで十分な場面の方が多い
                HStack(spacing: 12) {
                    ForEach(StoryService.reactions, id: \.self) { emoji in
                        Button {
                            Task { await sendReaction(emoji) }
                        } label: {
                            Text(emoji).font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending)
                    }
                }
                HStack {
                    TextField(L("返信する", "Reply"), text: $reply)
                        .textFieldStyle(.roundedBorder)
                    Button(Labels.Common.send) { Task { await sendReply() } }
                        .disabled(isSending || reply.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
        }
    }

    /// 出す返信の数。一覧を読めていればその数、まだなら `replyCount`。
    private var replyBadge: Int { max(replies.count, story.replyCount ?? 0) }

    /// 定型の反応を送る。
    private func sendReaction(_ emoji: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.react(id: story.id, emoji: emoji)
            message = L("送りました", "Sent")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
        }
    }

    private func sendReply() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.reply(id: story.id, text: reply)
            reply = ""
            message = L("送りました", "Sent")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
        }
    }

    private func keep() async {
        do {
            try await environment.stories.keep(id: story.id)
            message = L("自分の写真として残しました", "Kept as a photo")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("残せませんでした", "Couldn't keep it")
        }
    }

    private func deleteStory() async {
        do {
            try await environment.stories.delete(id: story.id)
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
