import SwiftUI

/// ブロックした人の一覧と解除。
///
/// **解除できる場所が要る。** ブロックだけできて外せないと、
/// 誤って押した人が戻せない。
///
/// **v2（2026-10-14・板 BlockedUsers）**: 左寄せの明朝 30 の大見出しと説明（13・text-2）、人の行は 64 で
/// 下に白 8% の区切り線、アイコンは少し灰色に（見えなくなった人だと分かる・`BlockedUsersLayout.avatarGrayscale`）、
/// 「解除」は線のボタン（白 14%）
struct BlockedUsersView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var auth: AuthStore
    @State private var users: [FollowUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 一度でも読み終えたか。**「ブロックしている人はいません」は読み終えてから**
    /// ——最初の読み込みが取り消されると、空の一覧のまま「いません」と出ていた
    @State private var hasLoaded = false
    /// いま解除を送っている相手（二度押しで2回投げない）
    @State private var working: Set<String> = []
    /// 何回目の読み込みか。**解除より前に始めた読み込みの返事は捨てる**
    /// ——引き下げ更新の返事が解除の後に届くと、解除した人が一覧と
    /// 端末の控え（`replaceBlocked`）の両方に戻っていた
    @State private var loadGeneration = 0

    var body: some View {
        List {
            Text(L("ブロックした人", "Blocked people"))
                .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                .foregroundStyle(WebTheme.text)
                .padding(.horizontal, JPSpace.xxs)
                .accessibilityAddTraits(.isHeader)
                .plainRow(top: JPSpace.xs, bottom: 0)
            // 板の説明。**同じ言い方をアプリの他の入口（通報・プロフィール）でも使っている**
            // 板 v2: 13・text-2
            Text(L("ブロックすると、おたがいの投稿・ストーリー・通知が見えなくなります。",
                   "Blocking hides each other's posts, stories and notifications."))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .padding(.horizontal, JPSpace.xxs)
                .plainRow(top: 6, bottom: JPSpace.s)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(WebTheme.danger).font(.callout)
                    .padding(.horizontal, 4)
                    .plainRow()
            } else if users.isEmpty && !isLoading && hasLoaded {
                Text(L("ブロックしている人はいません", "No one is blocked"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, JPSpace.xxs)
                    .plainRow()
            }
            ForEach(users) { user in
                HStack(spacing: 12) {
                    // **プロフィールへは飛ばさない**（板はリンク）。プロフィール画面は
                    // ブロック中を見ておらず、「フォローする」が出て押すとサーバーに断られる
                    person(user)
                    Button {
                        Task { await unblock(user.id) }
                    } label: {
                        // 余白と枠は**中身の側**に置く。外に付けると押せるのは文字だけで、
                        // 枠の縁を押すと行の方が反応していた
                        Text(L("解除", "Unblock"))
                            .font(JPFont.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                            .padding(.horizontal, JPSpace.m)
                            .frame(minWidth: 44, minHeight: JPHeight.inlineButton)
                            // 板 v2: 線のボタンの縁（白 14%）
                            .overlay(Capsule().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                            // 見た目は 36pt、押せる高さは 44pt（`FollowPill` と同じ）
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    // 行の中のボタンは borderless にしないと、行のどこを
                    // 押しても反応する
                    .buttonStyle(.borderless)
                    .disabled(working.contains(user.id))
                }
                // 板 v2: 人の行は 64、下に白 8% の区切り線
                .frame(minHeight: JPHeight.tallRow)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
                .plainRow(top: 0, bottom: 0)
            }
        }
        .listStyle(.plain)
        .webScreen()
        // 戻るボタンの文言のために題は持つが、バーの中央には出さない（板は左寄せの大見出しだけ・設定と同じ）
        .navigationTitle(L("ブロックした人", "Blocked people"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading { ProgressView() } }
    }

    /// アイコンと名前・@ユーザー名（板 45）。@ユーザー名は一覧の応答が各行に持つ
    /// （2026-09-26 から）。無い人・退会した人・101人目以降は名前だけ
    private func person(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil))
                .frame(width: 44, height: 44)
                .background(WebTheme.surface)
                .clipShape(Circle())
                // 板 v2: 少し灰色に（見えなくなった人だと分かる）。名前は白のまま
                .grayscale(BlockedUsersLayout.avatarGrayscale)
            PersonNameLines(user: user, lineLimit: 1)
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        let owner = auth.userId
        // 取りに行く前に札を取る（起動時の同期と、どちらが後に始まったかを見分ける）
        let fetch = hidden.beginBlockFetch()
        do {
            let list = try await environment.moderation.blocks()
            // 返ってくる間に人が替わっていたら、一覧にも書かない
            guard generation == loadGeneration, auth.userId == owner else { return }
            users = list.users
            hasLoaded = true
            // **サーバーの一覧で上書きする。** 端末のぶんを足し合わせると、
            // 別の端末で解除したのに「見えないまま」になる
            // 返ってくる間に人が替わっていたら書かない
            hidden.replaceBlocked(with: list.blockedIds, for: owner, fetch: fetch)
            await apply()
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。失敗と言わない
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }

    /// 「見せない」を公開一覧の側へ渡し直す。
    private func apply() async {
        await environment.gallery.setHidden(hidden.snapshot)
    }

    private func unblock(_ userId: String) async {
        guard !working.contains(userId) else { return }
        working.insert(userId)
        defer { working.remove(userId) }
        errorMessage = nil
        let owner = hidden.owner
        do {
            try await environment.moderation.unblock(userId: userId)
            loadGeneration += 1
            isLoading = false
            hidden.unblock(userId, for: owner)
            await apply()
            users.removeAll { $0.id == userId }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("解除できませんでした", "Couldn't unblock")
        }
    }
}

/// ブロックした人の画面の決まり（v2 の板 BlockedUsers）。テストで見張る
enum BlockedUsersLayout {
    /// アイコンの灰色の度合い（板: grayscale(.6)）
    static let avatarGrayscale: Double = 0.6
}

private extension View {
    /// 板 45 の素の行: 地も区切り線も無く、左右は画面の 16
    func plainRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
