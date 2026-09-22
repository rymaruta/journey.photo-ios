import SwiftUI

/// 招待リンクの中身を見て、参加する。Web の `/j?t=…`（`app/j/page.tsx`）と対。
///
/// **参加したあとの行き先まで作る。** 以前は「参加する」を押しても
/// 一覧（自分が作ったアルバムしか出ない）に戻るだけで、**アルバムを見ることも
/// そこへ投稿することもできなかった**。参加したら端末に覚え
/// （`JoinedAlbumsStore`）、この画面と投稿画面の行き先に出す。
/// シートに渡す合図。`String` は `Identifiable` ではないので包む。
struct InviteToken: Identifiable, Equatable {
    let id: String
    var token: String { id }
}

struct InviteView: View {

    let token: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var joined: JoinedAlbumsStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var preview: AlbumService.InvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var message: String?

    /// 既に参加しているか（端末が覚えている分）。
    private var alreadyJoined: Bool {
        guard let id = preview?.album.id else { return false }
        return joined.entries.contains { $0.id == id }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let preview {
                content(preview)
            } else {
                // **取り消された招待もここに来る**（30日で失効・作り直しでも失効）。
                // 参加済みなら、見られないだけで**投稿はできる**——
                // サーバーは会員かどうかで通す（`upload.ts` の `isAlbumMember`）
                VStack(spacing: 8) {
                    Text(message ?? L("この招待リンクは使えません", "This invite link isn't valid"))
                    if joined.entries.contains(where: { $0.token == token }) {
                        Text(L("参加しているアルバムは、投稿画面で行き先に選べます。",
                               "You can still choose this album when you post."))
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(L("アルバムの招待", "Album invite"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
        }
        .task { await load() }
    }

    private func content(_ preview: AlbumService.InvitePreview) -> some View {
        List {
            Section {
                Text(preview.album.title.isEmpty
                     ? L("無題のアルバム", "Untitled album") : preview.album.title)
                    .font(.headline)
                Text(L("\(preview.album.members) 人", "\(preview.album.members) members"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            if preview.photos.isEmpty {
                Section { Text(L("まだ写真がありません", "No photos yet")).foregroundStyle(.secondary) }
            } else {
                Section(L("このアルバムの写真", "Photos in this album")) {
                    ForEach(preview.photos) { photo in
                        NavigationLink {
                            // **公開の一覧から来たのではない**（個別ページは無いかもしれない）
                            PhotoDetailView(photo: photo, fromPublicFeed: false, context: preview.photos)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(photo.displayTitle)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }

            if let message {
                Section { Text(message).font(.callout).foregroundStyle(.red) }
            }

            Section {
                if auth.userId == nil {
                    Text(L("参加するにはログインしてください", "Sign in to join"))
                        .foregroundStyle(.secondary)
                } else if alreadyJoined {
                    Text(L("参加しています。投稿画面でこのアルバムを選べます。",
                           "You're in. Choose this album when you post."))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await join(preview) }
                    } label: {
                        if isJoining {
                            HStack { ProgressView(); Text(L("参加しています…", "Joining…")) }
                        } else {
                            Text(L("このアルバムに参加する", "Join this album"))
                        }
                    }
                    .disabled(isJoining)
                }
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            preview = try await environment.albums.invite(token: token)
        } catch {
            preview = nil
            message = (error as? LocalizedError)?.errorDescription
                ?? L("この招待リンクは使えません", "This invite link isn't valid")
        }
    }

    private func join(_ preview: AlbumService.InvitePreview) async {
        isJoining = true
        message = nil
        defer { isJoining = false }
        do {
            let result = try await environment.albums.join(token: token)
            // **サーバーが返した ID を使う**（プレビューと食い違ったら、そちらが正）
            joined.remember(id: result.albumId, title: preview.album.title, token: token)
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? L("参加できませんでした", "Couldn't join")
        }
    }
}
