import SwiftUI

/// 「親しい友達」を選ぶ（モック4-7 の3つ目の宛先）。
///
/// **相手には知らせない。** 入れたことも外したことも通知しない——
/// 知らせると「外された」が分かってしまう。画面にもそう書く。
///
/// 選ぶ先は**自分がフォローしている人**。知らない人を入れる口は作らない
/// （探して入れる形にすると、覚えのない相手が並ぶ画面になる）。
///
/// ただし**既に選んでいる人は、フォロー中に居なくても並べる**
/// （`CloseFriendsRows`）。並べないと外せない。
///
/// **選んでから右上の「保存」で送る**（板 39・2026-09-26）。以前は押すたびに
/// その場で保存していた。サーバーにまとめて書く口は無いので、保存では
/// **差分だけを1件ずつ**送り、途中で失敗したら止めて「何件保存できたか」を
/// 出す（`CloseFriendsRows.save`）。全部送れたら閉じる。
///
/// 🔴 **送っていない変更があるまま黙って戻らせない。** 投稿・写真の編集の
/// 「親しい友達を選ぶ」から来た人は、以前の「押したら保存」の癖で戻る。
/// 黙って捨てると0人のまま「親しい友達」限定の写真が出て、誰にも見えない。
/// 変更がある間・送っている間は標準の戻る（と左端の払い）を隠し、自前の戻るで
/// 「保存して戻る／変更を捨てる／キャンセル」を確かめる（`CloseFriendsRows.leave`）。
///
/// 板との意図的な差: 説明文は「写真」向け（下の注記）・「フォロー中の一覧に
/// 出ない人」の段がある（上の注記）・選択の印は星（板はチェック）。
struct CloseFriendsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var following: [FollowUser] = []
    /// 選んでいるが、フォロー中の一覧に居ない人（外したい人が居る場所）
    @State private var others: [FollowUser] = []
    /// **サーバーに保存済み**の親しい友達（読んだ値と、保存で返ってきた値）
    @State private var saved: Set<String> = []
    /// 画面で選んでいる人（「保存」を押すまで送らない）
    @State private var chosen: Set<String> = []
    /// 「名前で探す」。端末の中で絞るだけ（`ListIdentity.filter`）
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 一度読めたか。**読めた後は読み直さない**——タブを替えて戻るなどで `.task` が
    /// 走り直すと、まだ保存していない選び直しがサーバーの値で上書きされていた
    @State private var loaded = false
    /// 保存を送っている間（二度押しで2回投げない・選び直させない）
    @State private var isSaving = false
    /// 保存が途中で止まった／失敗した知らせ。**アラートで出す**
    @State private var saveError: String?
    /// 「保存して戻る／変更を捨てる」の確認
    @State private var confirmLeave = false

    /// 送るもの（外す方が先・画面の並び）
    private var pending: [CloseFriendsRows.Change] {
        CloseFriendsRows.changes(saved: saved, picked: chosen,
                                 order: (others + following).map(\.id))
    }
    private var canSave: Bool {
        !pending.isEmpty && !overLimit && !isLoading && errorMessage == nil
    }
    private var overLimit: Bool { CloseFriendsRows.overLimit(chosen) }
    private var leave: CloseFriendsRows.Leave {
        CloseFriendsRows.leave(hasChanges: !pending.isEmpty, isSaving: isSaving)
    }
    private var shownOthers: [FollowUser] { ListIdentity.filter(others, query: query) }
    private var shownFollowing: [FollowUser] { ListIdentity.filter(following, query: query) }

    var body: some View {
        List {
            Section {
                // **効くのは写真だけ。** ストーリーは常にフォロワーだけに出る
                // （`api-user/src/storyVisibility.ts`・2026-09-22）。入口は写真の
                // 公開範囲（投稿・編集）と設定のプライバシー（2026-09-26）
                Text(L("公開範囲を「親しい友達」にした写真は、選んだ人だけが見られます。相手には知らせません。",
                       "Photos shared with Close friends are visible only to people you pick. They aren't told."))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                }
                .listRowBackground(Color.clear)
            } else if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
                    .listRowBackground(Color.clear)
            } else if following.isEmpty && others.isEmpty {
                Section {
                    // **「まだ誰もいない」と「読めなかった」を分ける**
                    Text(L("フォローしている人がまだいません。フォローすると、ここから選べます。",
                           "You're not following anyone yet."))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted2)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    searchField
                    if overLimit {
                        // **保存を押せない理由を出す**（黙って灰色にしない）
                        Text(L("選べるのは \(CloseFriendsRows.limit) 人までです（いま \(chosen.count) 人）。減らすと保存できます。",
                               "You can pick up to \(CloseFriendsRows.limit) people (now \(chosen.count)). Remove some to save."))
                            .font(.footnote)
                            .foregroundStyle(WebTheme.danger)
                    }
                }
                .listRowBackground(Color.clear)
                if shownOthers.isEmpty && shownFollowing.isEmpty {
                    Section {
                        Text(L("見つかりませんでした", "No matches"))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted2)
                    }
                    .listRowBackground(Color.clear)
                }
                if !shownOthers.isEmpty {
                    Section {
                        ForEach(shownOthers) { user in
                            row(user)
                        }
                    } header: {
                        Text(L("フォロー中の一覧に出ない人", "Not in your following list"))
                    } footer: {
                        Text(L("フォローを外した人などです。星を外して保存すると、「親しい友達」の写真が見えなくなります。",
                               "People you unfollowed, for example. Remove the star and tap Save to hide your Close friends photos from them."))
                    }
                    .listRowBackground(Color.clear)
                }
                // フォローが0人のときは段ごと出さない（見出しだけの段を作らない）
                // 絞った結果が0人のときも出さない（「選んだ人 N」は全体の数なので、
                // 絞っても見出しの数は変わらない）
                if !shownFollowing.isEmpty {
                    Section {
                        ForEach(shownFollowing) { user in
                            row(user)
                        }
                    } header: {
                        Text(L("選んだ人 \(chosen.count)", "\(chosen.count) picked"))
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .webScreen()
        .navigationTitle(L("親しい友達", "Close friends"))
        .navigationBarTitleDisplayMode(.inline)
        // 変更がある間・送っている間は標準の戻るを隠す（左端から払って戻るのも止まる）
        .navigationBarBackButtonHidden(leave != .now)
        .toolbar {
            if leave != .now {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if leave == .confirm { confirmLeave = true }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    // 送っている最中は戻らせない（途中の失敗が消えた画面に出る）
                    .disabled(leave == .wait)
                    .accessibilityLabel(L("戻る", "Back"))
                }
            }
            // **保存は右上**（板 39）。変えたものが無い間・上限を超えている間は押せない
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(L("保存", "Save")) {
                        Task { await save() }
                    }
                    .font(.body.weight(.semibold))
                    // 押せない間は真鍮にしない（明示した色は disabled でも薄くならない）
                    .foregroundStyle(canSave ? WebTheme.accent : WebTheme.muted2)
                    .disabled(!canSave)
                }
            }
        }
        .confirmationDialog(L("変更を保存しますか？", "Save your changes?"),
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            // 上限を超えている間は保存できないので、選択肢に出さない
            if !overLimit {
                Button(L("保存して戻る", "Save and go back")) {
                    Task { await save() }
                }
            }
            Button(L("変更を捨てる", "Discard changes"), role: .destructive) {
                dismiss()
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("保存しないで戻ると、選んだ人は「親しい友達」に入りません。",
                   "If you go back without saving, your picks won't be applied."))
        }
        .alert(L("保存できませんでした", "Couldn't save"),
               isPresented: Binding(get: { saveError != nil },
                                    set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
    }

    /// 「名前で探す」（板 39: 高さ44・角12・白8%の地）。表示名と @ユーザー名で絞る
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
            TextField(L("名前で探す", "Search by name"), text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(WebTheme.foreground)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func row(_ user: FollowUser) -> some View {
        let picked = chosen.contains(user.id)
        return Button {
            if picked { chosen.remove(user.id) } else { chosen.insert(user.id) }
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil),
                            placeholderSymbol: "person.crop.circle.fill")
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                PersonNameLines(user: user)
                    .foregroundStyle(WebTheme.foreground)
                Spacer()
                Image(systemName: picked ? "star.fill" : "star")
                    .foregroundStyle(picked ? WebTheme.accent : WebTheme.faint)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 送っている間は選び直させない（送っている差分と画面がずれる）
        .disabled(isSaving)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func load() async {
        guard !loaded else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let me = auth.userId else { return }
        let list = try? await environment.social.following(userId: me)
        let ids = try? await environment.social.closeFriendIds()
        // **フォロー中の全員の ID**（`/user/following`）。名前つきの一覧は
        // サーバーが50人で切るので、51人目以降はここからしか分からない
        let allFollowing = try? await environment.social.myFollowingIds()
        // **どちらかが引けなければ選べない。** 一覧だけ出すと、選んでいる人が
        // 「選んでいない」に見え、フォロー外の人は並ばない＝外せない
        guard let list, let ids else {
            errorMessage = Labels.Common.loadFailed
            return
        }
        let rows = Self.rows(page: list.users, allFollowing: allFollowing, chosen: ids)
        saved = Set(ids)
        chosen = Set(ids)
        // 51人目以降は名前を引いてから、フォロー中の並びの後ろに足す。
        // **全員は引かない**（500人なら450回）——選んでいる人を必ず、残りは
        // 上限（`lookupCap`）まで。引かなかった人はフォロー中の欄に出ない
        let beyond = Self.beyondToLookUp(rows.beyondPage, others: rows.others.count,
                                         chosen: Set(ids), cap: Self.lookupCap)
        following = list.users + (await names(of: beyond))
        others = await names(of: rows.others)
        // **名前を引き終えてから「読めた」にする。** 引いている途中で離れると打ち切られ、
        // 名前の無い行のまま残るので、戻ったときに読み直す
        if !Task.isCancelled { loaded = true }
    }

    /// 並べる人の振り分け。
    ///
    /// - `beyondPage`: フォロー中だが、名前つきの一覧（50人で切れる）に載らなかった人
    ///   （フォローした順）。**フォロー中の欄に足して選べるようにする**
    /// - `others`: 選んでいるが**本当にフォロー中でない**人（外した人など）
    ///
    /// 全員の ID が取れなかった（`allFollowing == nil`）ときは、一覧に居ない
    /// 選んだ人を全部 `others` に回す（外す手段だけは残す）。
    nonisolated static func rows(page: [FollowUser], allFollowing: [String]?,
                     chosen: [String]) -> (beyondPage: [String], others: [String]) {
        let split = CloseFriendsRows.split(following: page, chosen: chosen)
        guard let allFollowing else { return ([], split.others) }
        let shown = Set(page.map(\.id))
        var seen = Set<String>()
        let beyond = allFollowing.filter { !shown.contains($0) && seen.insert($0).inserted }
        let followingSet = Set(allFollowing)
        return (beyond, split.others.filter { !followingSet.contains($0) })
    }

    /// 51人目以降のうち名前を引く人。
    ///
    /// - **選んでいる人は必ず残す**（上限を超えても）。落とすと、選んでいるのに
    ///   どの欄にも出ない＝外せない（`others` には入らないので「外した人など」にも出ない）
    /// - 残りはフォローした順に、`others` と合わせて `cap` 人に収まるまで
    ///
    /// 順番はフォローした順のまま返す
    nonisolated static func beyondToLookUp(_ beyond: [String], others: Int,
                                           chosen: Set<String>, cap: Int) -> [String] {
        let chosenCount = beyond.filter { chosen.contains($0) }.count
        var room = max(0, cap - others - chosenCount)
        return beyond.filter { id in
            if chosen.contains(id) { return true }
            guard room > 0 else { return false }
            room -= 1
            return true
        }
    }

    /// 1回の読み込みで名前を引く人数の上限（「外した人など」と51人目以降の合計）。
    /// 親しい友達の上限（`CLOSE_FRIENDS_MAX` = 200）に合わせる——`lookupWidth` は
    /// この程度の人数を前提にしている
    static let lookupCap = 200

    /// 名前を引くときに同時に送る数の上限。
    ///
    /// 親しい友達は最大200人（`CLOSE_FRIENDS_MAX`）。全員を一度に引くと、
    /// アカウント全体で10本しかない Lambda の同時実行枠を埋め、
    /// 他の人の要求まで待たせる
    private static let lookupWidth = 8

    /// 引いた結果。**退会した人（404）は「取れなかった」と分ける**
    /// （`ProfileService.publicProfile` の注記）
    private enum Lookup: Sendable {
        case name(String?, username: String?)
        case deleted
    }

    /// 1人ぶん引く
    nonisolated private static func lookup(_ id: String, profiles: ProfileService) async -> (String, Lookup) {
        do {
            let profile = try await profiles.publicProfile(userId: id)
            return (id, .name(AuthorName.real(profile), username: profile.username))
        } catch APIError.server(let status, _) where status == 404 {
            return (id, .deleted)
        } catch {
            return (id, .name(nil, username: nil))
        }
    }

    /// フォロー外の人の名前。**引けなくても行は出す**（名前より外せることが先）
    private func names(of ids: [String]) async -> [FollowUser] {
        let profiles = environment.profiles
        let width = Self.lookupWidth
        let found = await withTaskGroup(of: (String, Lookup).self,
                                        returning: [String: Lookup].self) { group in
            var results: [String: Lookup] = [:]
            var next = 0
            // 最初の数本を出し、1本返るたびに次の1本を出す（同時に width 本まで）
            while next < min(width, ids.count) {
                let id = ids[next]
                group.addTask { await Self.lookup(id, profiles: profiles) }
                next += 1
            }
            while let done = await group.next() {
                results[done.0] = done.1
                if next < ids.count {
                    let id = ids[next]
                    group.addTask { await Self.lookup(id, profiles: profiles) }
                    next += 1
                }
            }
            return results
        }
        return ids.map { id in
            switch found[id] {
            case .deleted: return FollowUser(id: id, name: nil, deleted: true)
            case .name(let name, let username):
                return FollowUser(id: id, name: name, deleted: nil, username: username)
            case nil: return FollowUser(id: id, name: nil, deleted: nil)
            }
        }
    }

    /// 差分だけを1件ずつ送る（`CloseFriendsRows.save`）。**返ってきた状態を使う。**
    /// 途中で止まったら、送れたぶんは保存済みに入り、残りは選択に残る
    /// ——もう一度「保存」を押すと残りだけが送られる
    private func save() async {
        let changes = pending
        guard !isSaving, !changes.isEmpty, !overLimit else { return }
        isSaving = true
        defer { isSaving = false }
        let social = environment.social
        let outcome = await CloseFriendsRows.save(saved: saved, changes: changes) { change in
            try await social.setCloseFriend(userId: change.userId, wanted: change.wanted)
        }
        saved = outcome.saved
        // 全部送れたら閉じる（プロフィールの編集の「保存」と同じ）
        if outcome.finished {
            dismiss()
        } else {
            saveError = CloseFriendsRows.partialMessage(outcome)
        }
    }
}
