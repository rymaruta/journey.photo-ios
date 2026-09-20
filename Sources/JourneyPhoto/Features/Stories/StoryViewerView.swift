import SwiftUI

/// ストーリーを全画面で見る。
struct StoryViewerView: View {

    let story: Story
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var reply = ""
    @State private var message: String?
    @State private var viewers: [FollowUser] = []
    @State private var showViewers = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                RemoteImage(url: story.imageURL, contentMode: .fit)
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
            }
        }
        .sheet(isPresented: $showViewers) {
            NavigationStack {
                List(viewers) { viewer in
                    Text(viewer.displayName)
                }
                .navigationTitle("見た人 \(viewers.count)")
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
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var footer: some View {
        if isMine {
            HStack(spacing: 16) {
                Button("見た人 \(viewers.count)") { showViewers = true }
                // 24時間で消える前に、自分の写真として残す
                Button("残す") { Task { await keep() } }
                Button("削除", role: .destructive) { Task { await deleteStory() } }
            }
            .font(.footnote)
            .padding(16)
        } else {
            HStack {
                TextField("返信する", text: $reply)
                    .textFieldStyle(.roundedBorder)
                Button("送信") { Task { await sendReply() } }
                    .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
    }

    private func sendReply() async {
        do {
            try await environment.stories.reply(id: story.id, text: reply)
            reply = ""
            message = "送りました"
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "送れませんでした"
        }
    }

    private func keep() async {
        do {
            try await environment.stories.keep(id: story.id)
            message = "自分の写真として残しました"
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "残せませんでした"
        }
    }

    private func deleteStory() async {
        do {
            try await environment.stories.delete(id: story.id)
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "削除できませんでした"
        }
    }
}
