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
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss

    /// 🔴 ブロック・通報した写真を落とすための控え。**画面に戻ったときに取り直す**
    /// ——その場で絞ると、詳細でブロックした瞬間に押した元の行が消えて詳細が閉じる
    @State private var dropped = ModerationSnapshot()

    @State private var preview: AlbumService.InvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var message: String?
    /// 読み込みの失敗が**押し直せば直りうる**ものか（圏外・5xx）。
    /// 失効した招待（4xx）に「もう一度試す」を出しても何も変わらない
    @State private var canRetry = false

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
                        // **言い切らない。** 招待の取り消しと、アルバムそのものの削除は同じ 410 で
                        // 返り、見分けられない。消されていたら投稿は「見つかりません」で断られる
                        Text(L("アルバムが残っていれば、投稿画面で行き先に選べます。",
                               "If the album still exists, you can choose it when you post."))
                            .font(.footnote)
                    }
                    if canRetry {
                        Button(Labels.Common.retry) { Task { await load() } }
                            .buttonStyle(.bordered)
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
        .onAppear { dropped = hidden.snapshot }
        // **読めていれば読み直さない。** 写真の詳細から戻るたびに走り、
        // 一覧がくるくるに置き換わって見ていた位置を失っていた
        .task { if preview == nil { await load() } }
    }

    private func content(_ preview: AlbumService.InvitePreview) -> some View {
        // 🔴 ブロックした人・通報した写真を出さない（招待の中身はサーバーが絞らない）
        let photos = dropped.visible(preview.photos)
        return List {
            Section {
                Text(preview.album.title.isEmpty
                     ? L("無題のアルバム", "Untitled album") : preview.album.title)
                    .font(.headline)
                Text(L("\(preview.album.members) 人", "\(preview.album.members) members"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            if photos.isEmpty {
                Section { Text(L("まだ写真がありません", "No photos yet")).foregroundStyle(.secondary) }
            } else {
                Section(L("このアルバムの写真", "Photos in this album")) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        NavigationLink {
                            // **公開の一覧から来たのではない**（個別ページは無いかもしれない）
                            PhotoDetailView(photo: photo, fromPublicFeed: false, context: photos)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                // 招待の応答は題を返さないので、空の行にせず何枚目かを出す
                                Text(photo.displayTitle.isEmpty
                                     ? L("\(index + 1)枚目", "Photo \(index + 1)") : photo.displayTitle)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }

            if let message {
                Section { Text(message).font(.callout).foregroundStyle(WebTheme.danger) }
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
        canRetry = false
        // 前の回の失敗の文を残さない（再試行で開けたのに赤い文が並ぶ）
        message = nil
        defer { isLoading = false }
        do {
            preview = try await environment.albums.invite(token: token)
        } catch {
            preview = nil
            // 押し直して直りうるのは圏外・読めない応答（キャプティブポータルの HTML など）・
            // サーバーの一時的な失敗だけ。失効した招待（404・410）には出さない
            switch error as? APIError {
            case .unreachable?, .decoding?: canRetry = true
            case .server(let status, _)?: canRetry = status >= 500 || status == 429
            default: canRetry = false
            }
            message = (error as? LocalizedError)?.errorDescription
                ?? L("この招待リンクは使えません", "This invite link isn't valid")
        }
    }

    private func join(_ preview: AlbumService.InvitePreview) async {
        // 素早く2回押すと、`.disabled` が効く前に2本目の Task が走る
        guard !isJoining else { return }
        isJoining = true
        message = nil
        defer { isJoining = false }
        do {
            let result = try await environment.albums.join(token: token)
            // **サーバーが返した ID を使う**（プレビューと食い違ったら、そちらが正）
            joined.remember(id: result.albumId, title: preview.album.title, token: token)
            // 人数を取り直す（参加しても「N 人」のままだった）。取れなければ前のまま
            let refreshed = try? await environment.albums.invite(token: token)
            if let refreshed { self.preview = refreshed }
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? L("参加できませんでした", "Couldn't join")
        }
    }
}
