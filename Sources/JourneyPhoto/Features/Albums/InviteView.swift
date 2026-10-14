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
    /// 戻るスワイプ途中の `onAppear` で行を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

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
                // v2: 読み込みは骨格（0.3 秒より早ければ出さない）
                JPLoadingState(kind: .grid)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if let preview {
                content(preview)
            } else {
                // **取り消された招待もここに来る**（30日で失効・作り直しでも失効）。
                // 参加済みなら、見られないだけで**投稿はできる**——
                // サーバーは会員かどうかで通す（`upload.ts` の `isAlbumMember`）
                // v2 Components 06: 失敗は共通の並び（何が起きたか → どうなっているか → もう一度）。
                // 「もう一度」は押し直せば直りうるときだけ（失効した招待には出さない）
                VStack(spacing: JPSpace.xs) {
                    ErrorBanner(message: message ?? L("この招待リンクは使えません", "This invite link isn't valid"),
                                retry: canRetry ? { Task { await load() } } : nil)
                    if joined.entries.contains(where: { $0.token == token }) {
                        // **言い切らない。** 招待の取り消しと、アルバムそのものの削除は同じ 410 で
                        // 返り、見分けられない。消されていたら投稿は「見つかりません」で断られる
                        Text(L("アルバムが残っていれば、投稿画面で行き先に選べます。",
                               "If the album still exists, you can choose it when you post."))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, JPSpace.xl)
                    }
                }
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
        .onAppear {
            switch front.appear() {
            case .first:
                dropped = hidden.snapshot
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    dropped = hidden.snapshot
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
        // **読めていれば読み直さない。** 写真の詳細から戻るたびに走り、
        // 一覧がくるくるに置き換わって見ていた位置を失っていた
        .task { if preview == nil { await load() } }
    }

    /// 招待の中身（板 v2 Invite）: 上半分に写真の組み絵（大1・小2）、黒地に眉「SHARED ALBUM · 招待されています」と
    /// 明朝 32 の題・人数と枚数（等幅）、「このアルバムの写真」の4列の格子、下に固定の主ボタン
    /// （写真のある画面なので白・CLAUDE.md）。
    ///
    /// 2026-10-14 判断: 板は格子を4枚目で「＋83」に畳むが、**全部の写真を4列で並べる**——畳むと
    /// 5枚目からを開く口が無くなる（以前の一覧は全部の行を開けた）。参加している人の顔の重ねは
    /// 招待の応答に人の一覧が無いので出さない（サーバーに触らない段）
    private func content(_ preview: AlbumService.InvitePreview) -> some View {
        // 通報した写真・ブロックした人の写真は落とす（招待の中身はサーバーが絞らない）。
        // 持ち主はサーバー（`GET /invites/{token}`）が写真ごとに `userId` で返す
        // （2026-10-07・既知 H-1。それより前のサーバーは返さず、ブロックの分は落とせなかった）
        let photos = dropped.visible(preview.photos)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mosaic(photos)
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    Text(L("SHARED ALBUM · 招待されています", "SHARED ALBUM · YOU'RE INVITED"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                    Text(preview.album.title.isEmpty
                         ? L("無題のアルバム", "Untitled album") : preview.album.title)
                        .font(JPFont.photoTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    // 英語は1人なら単数（「1 members」にしない）
                    Text(L("\(preview.album.members) 人", preview.album.members == 1 ? "1 member" : "\(preview.album.members) members")
                         + " · " + L("\(photos.count)枚", photos.count == 1 ? "1 photo" : "\(photos.count) photos"))
                        .font(JPFont.number(JPTypeScale.footnote, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text2)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, photos.isEmpty ? JPSpace.m : -JPSpace.xs)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("このアルバムの写真", "Photos in this album"))
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text2)
                        .accessibilityAddTraits(.isHeader)
                    if photos.isEmpty {
                        Text(L("まだ写真がありません", "No photos yet"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ProfileV2.gridSpacing), count: 4),
                                  spacing: ProfileV2.gridSpacing) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                                NavigationLink {
                                    // **公開の一覧から来たのではない**（個別ページは無いかもしれない）
                                    PhotoDetailView(photo: photo, fromPublicFeed: false, context: photos)
                                } label: {
                                    PhotoFrame(photo: photo, corner: 0)
                                        .background(WebTheme.card)
                                }
                                .buttonStyle(.plain)
                                // 招待の応答は題を返さないので、何枚目かを読む
                                .accessibilityLabel(photo.displayTitle.isEmpty
                                                    ? L("\(index + 1)枚目", "Photo \(index + 1)") : photo.displayTitle)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.field))
                    }
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, 22)

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, JPSpace.l)
                        .padding(.top, JPSpace.m)
                }
            }
            .padding(.bottom, JPSpace.screenEnd)
        }
        .safeAreaInset(edge: .bottom) { joinBar(preview) }
        .webScreen()
    }

    /// 上半分の組み絵（板 v2 Invite: 高さ 380・左に大きい1枚、右に2枚・すき間 2・下 140pt を黒へ）。
    /// 写真が無ければ置かない（灰色の空き地を作らない）
    @ViewBuilder
    private func mosaic(_ photos: [Photo]) -> some View {
        if let first = photos.first {
            HStack(spacing: ProfileV2.gridSpacing) {
                mosaicTile(first)
                if photos.count > 1 {
                    VStack(spacing: ProfileV2.gridSpacing) {
                        mosaicTile(photos[1])
                        if photos.count > 2 { mosaicTile(photos[2]) }
                    }
                    .frame(width: Self.mosaicSideWidth)
                }
            }
            .frame(height: Self.mosaicHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [WebTheme.background.opacity(0), WebTheme.background],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                    .allowsHitTesting(false)
            }
            .clipped()
            // 飾り。写真は下の格子から開く
            .accessibilityHidden(true)
        }
    }

    private func mosaicTile(_ photo: Photo) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment) }
            .background(WebTheme.card)
            .clipped()
    }

    /// 板 v2 Invite: 組み絵の高さ 380・右の列の幅（2fr:1fr の 1fr ≒ 390 の 1/3）
    nonisolated static let mosaicHeight: CGFloat = 380
    nonisolated static let mosaicSideWidth: CGFloat = 128

    /// 下に固定の参加の帯（`jpBottomBar`）。主ボタンは写真のある画面なので白
    /// （`JPPillStyle.main(onPhoto: true)`）。参加済み・未ログインはボタンの代わりに一行
    @ViewBuilder
    private func joinBar(_ preview: AlbumService.InvitePreview) -> some View {
        VStack(spacing: 10) {
            if auth.userId == nil {
                Text(L("参加するにはログインしてください", "Sign in to join"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
            } else if alreadyJoined {
                Text(L("参加しています。投稿画面でこのアルバムを選べます。",
                       "You're in. Choose this album when you post."))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    Task { await join(preview) }
                } label: {
                    Group {
                        if isJoining {
                            HStack { ProgressView().tint(WebTheme.accentText); Text(L("参加しています…", "Joining…")) }
                        } else {
                            Text(L("このアルバムに参加する", "Join this album"))
                        }
                    }
                    .jpPillButton(.main(onPhoto: true))
                }
                .buttonStyle(.plain)
                .disabled(isJoining)
                Text(L("参加しているアルバムは、投稿画面で行き先に選べます", "Albums you've joined can be chosen when you post"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
            }
        }
        .jpBottomBar()
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
        // 送る前の人を取る。**答えを待つ間にアカウントを替えても、参加した人の控えに書く**
        // （替わった後の人の一覧に、前の人が参加したアルバムを入れない）
        let owner = joined.owner
        do {
            let result = try await environment.albums.join(token: token)
            // **サーバーが返した ID を使う**（プレビューと食い違ったら、そちらが正）
            joined.remember(id: result.albumId, title: preview.album.title, token: token, for: owner)
            // 人数を取り直す（参加しても「N 人」のままだった）。取れなければ前のまま
            let refreshed = try? await environment.albums.invite(token: token)
            if let refreshed { self.preview = refreshed }
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? L("参加できませんでした", "Couldn't join")
        }
    }
}
