import SwiftUI

/// アルバム。招待リンクで人を呼べる、写真のまとまり。
struct AlbumsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
    @StateObject private var model = AlbumsViewModel()
    @State private var newTitle = ""
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var inviteText = ""
    /// 開いている招待。リンクを貼った直後と、参加済みの行を押したとき
    @State private var openedToken: InviteToken?
    /// 名前を変えている最中のアルバム（Web の `/user/albums` と同じ操作）
    /// **シートの表示と、対象と、入力を別々に持つ。** ひとつの `Album?` で
    /// 兼ねると、`isPresented` の setter が閉じる合図で対象を nil にするため、
    /// 「保存」の中身が走るときには対象が消えていることがある（黙って何も起きない）
    @State private var showRename = false
    @State private var renamingId = ""
    @State private var renameTitle = ""
    /// 消す前の確認。**表示と対象を別々に持つ**（名前変更と同じ理由——
    /// ダイアログが閉じる合図で対象を nil にすると、「消す」の中身が走るときに
    /// 対象が消えていることがある）
    @State private var showDelete = false
    @State private var deleting: Album?

    var body: some View {
        Group {
            if auth.isResolving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: L("アルバムを使うにはログインしてください", "Sign in to use albums"))
            } else {
                list
            }
        }
        .navigationTitle(Labels.Navigation.albums)
        .onChange(of: auth.userId) { _, _ in model.forget() }
    }

    // **段ごとに割ってある。** 一本の長い `List { … }` にすると、Swift の
    // 型検査が現実的な時間で終わらなくなることがある
    // （"unable to type-check this expression in reasonable time"）。
    private var list: some View {
        List {
            // 板 v2 Albums: 明朝の題と一行の説明 → 作る（主ボタン）→ 招待リンクから参加の札 → 一覧
            header
                .profileListRow()
            statusRow
            if !model.albums.isEmpty || !joinedOthers.isEmpty {
                createButton
                    .profileListRow()
            }
            joinCard
                .profileListRow()
            if !model.albums.isEmpty {
                JPEyebrowLine(L("作ったアルバム", "Your albums"))
                    .padding(.top, JPSpace.xs)
                    .profileListRow()
            }
            ForEach(model.albums) { album in
                row(album)
                    .profileListRow(divider: true)
            }
            joinedSection
        }
        .listStyle(.plain)
        .webScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 題は下の明朝の見出しが受け持つ（板 v2）。中央は空けておく（戻る文字と読み上げには題を持つ）
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .toolbar { addMenu }
        .alert(L("名前を変える", "Rename"), isPresented: $showRename) {
            TextField(L("名前", "Name"), text: $renameTitle)
            Button(Labels.Common.save) {
                let id = renamingId
                let title = renameTitle
                Task { await model.rename(id, title: title, environment: environment) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        }
        .sheet(item: $openedToken) { opened in
            NavigationStack { InviteView(token: opened.token) }
        }
        // **消す前に一度聞く**（Web の `/user/albums` と同じ文言）。削除は戻せない
        .confirmationDialog(deleteTitle, isPresented: $showDelete, titleVisibility: .visible) {
            Button(Labels.Common.delete, role: .destructive) {
                guard let album = deleting else { return }
                Task {
                    // **参加の控えからも外す。** 自分のリンクを自分で開くと控えにも
                    // 入るので、消した途端に「参加しているアルバム」へ落ちてきて、
                    // 押すと「この招待リンクは使えません」になっていた
                    if await model.delete(album.id, environment: environment) {
                        joined.forget(id: album.id)
                    }
                }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("招待リンクは使えなくなり、参加者はこのアルバムを開けなくなります。写真そのものは消えません。",
                   "The invite link will stop working and members will no longer be able to open this album. The photos themselves are not deleted."))
        }
        .alert(L("招待リンクから参加", "Join with a link"), isPresented: $showJoin) {
            joinAlertButtons
        } message: {
            Text(L("受け取ったリンク（https://journey-photo.com/j?t=…）をそのまま貼れます。", "You can paste the link you received as-is."))
        }
        .alert(L("アルバムを作る", "New album"), isPresented: $showCreate) {
            createAlertButtons
        }
        .task { await model.load(environment: environment) }
        .refreshable { await model.load(environment: environment) }
    }

    private var deleteTitle: String {
        let title = deleting?.title ?? ""
        return title.isEmpty
            ? L("このアルバムを消しますか？", "Delete this album?")
            : L("「\(title)」を消しますか？", "Delete “\(title)”?")
    }

    /// **読み込みの失敗と、操作の失敗を分ける。** 操作の失敗（消せなかった・
    /// 作れなかった）は一時的な知らせ（`notice`）で、しばらくすると消える。
    /// 同じ欄に持つと、次の読み込みまで残り続け、空の案内まで隠していた
    @ViewBuilder
    private var statusRow: some View {
        if let notice = model.notice {
            Text(notice).foregroundStyle(WebTheme.danger).font(.callout)
                .profileListRow()
        }
        if let message = model.errorMessage {
            // v2 Components 06: 失敗は共通の並び（何が起きたか → もう一度）
            ErrorBanner(message: message, isBusy: model.isLoading) {
                Task { await model.load(environment: environment) }
            }
            .profileListRow()
        } else if model.albums.isEmpty && joinedOthers.isEmpty && !model.isLoading {
            // 板 v2 Albums（空）: 何が無いか → どうすれば埋まるか → 作る（写真の無い画面の主ボタン＝真鍮）
            EmptyState(title: L("まだアルバムがありません", "No albums yet"),
                       message: L("アルバムを作って招待リンクを送ると、仲間の写真がここに集まります",
                                  "Create an album and send the invite link — your companions' photos gather here."),
                       actionTitle: L("アルバムを作る", "New album")) { showCreate = true }
                // 作っている間は押せない（`create` は黙って断るので、押せる形にしない・2026-10-21）
                .disabled(model.isCreating)
                .opacity(model.isCreating ? 0.5 : 1)
                .profileListRow()
        } else if model.albums.isEmpty && model.isLoading {
            JPLoadingState(kind: .rows)
                .profileListRow()
        }
    }

    /// 自分が作ったアルバムと重ならない、参加しているアルバム（`joinedSection` と同じ絞り）
    private var joinedOthers: [JoinedAlbumsStore.Entry] {
        let mine = Set(model.albums.map { $0.id })
        return joined.entries.filter { !mine.contains($0.id) }
    }

    /// 見出し（板 v2 Albums: 明朝の題・13 の text-2 の説明）。
    /// 板の題は明朝 30 だが、字の段に 30 は無いので画面の題の 26（`JPFont.screenTitle`）
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Labels.Navigation.albums)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(L("招待リンクで、旅の仲間と写真を集めます", "Collect photos with your travel companions via an invite link"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, JPSpace.xs)
    }

    /// 「アルバムを作る」。**写真の無い画面の主ボタン＝真鍮の塗り＋墨**（`JPPillStyle.main(onPhoto: false)`・
    /// CLAUDE.md の owner の好み）。2026-10-14 判断: 板 v2 は白（アルバムの組み絵がある画面）だが、
    /// この一覧はアルバムの写真を持っていない（`GET /albums` は表紙を返さない）ので写真の無い画面
    private var createButton: some View {
        Button { showCreate = true } label: {
            Label(L("アルバムを作る", "New album"), systemImage: "plus")
                .jpPillButton(.main(onPhoto: false))
        }
        .buttonStyle(.plain)
        // 作っている間は押せない（`create` は黙って断るので、押せる形にしない・2026-10-21）
        .disabled(model.isCreating)
        .opacity(model.isCreating ? 0.5 : 1)
        .accessibilityIdentifier("albums.create")
    }

    /// 招待リンクから参加（板 v2 Albums: 黒地の札の中に欄と「開く」）。以前は右上の「＋」の中の
    /// 入力ダイアログだけで、受け取ったリンクの貼り先が見えなかった。ダイアログ（`showJoin`）も残す
    private var joinCard: some View {
        JPCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("招待リンクから参加", "Join with a link"), systemImage: "link")
                    .font(JPFont.body.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                HStack(spacing: JPSpace.xs) {
                    TextField(L("リンクか招待コード", "Link or invite code"), text: $inviteText)
                        .font(.callout)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { openInvite() }
                        .padding(.horizontal, JPSpace.s)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.s))
                        .overlay(RoundedRectangle(cornerRadius: JPRadius.s).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                        .accessibilityLabel(L("リンクか招待コード", "Link or invite code"))
                    Button { openInvite() } label: {
                        Text(L("開く", "Open"))
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.foreground)
                            .padding(.horizontal, 18)
                            .frame(minHeight: JPHeight.secondaryButton)
                            .overlay(Capsule().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                            .contentShape(Capsule())
                    }
                    // 行の中に押せるもの（欄とボタン）が2つある
                    .buttonStyle(.borderless)
                    .disabled(inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text(L("受け取ったリンク（https://journey-photo.com/j?t=…）をそのまま貼れます", "You can paste the link you received as-is."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(14)
        }
    }

    /// 貼ったリンクか招待コードを開く。**押した瞬間に参加させない**——何のアルバムか見せてから聞く
    /// （Web は `/j?t=` が中身を見せてから聞く）。ダイアログの「開く」と同じ1本
    private func openInvite() {
        let token = InviteLink.token(from: inviteText)
        inviteText = ""
        openedToken = token.isEmpty ? nil : InviteToken(id: token)
        if openedToken == nil {
            model.flash(L("招待リンクを読み取れませんでした", "Couldn't read that invite link"))
        }
    }

    /// **参加しているアルバム。** サーバーの一覧（`GET /albums`）は
    /// 自分が作ったものしか返さないので、端末が覚えている分をここに出す
    /// ——出さないと、参加した瞬間にアルバムへの入口が消える。
    @ViewBuilder
    private var joinedSection: some View {
        // **自分が作ったアルバムとは重ねない。** 自分のリンクを自分で開くと
        // サーバーは 200（`already: true`）を返すので、控えにも入る
        // ——弾かないと同じアルバムが上下に2行出る（投稿画面は弾いている）
        let others = joinedOthers
        if !others.isEmpty {
            // 板 v2 Albums: 節の見出しは眉（真鍮＋消える線）
            JPEyebrowLine(L("参加しているアルバム", "Albums you joined"))
                .padding(.top, JPSpace.xs)
                .profileListRow()
            Section {
                ForEach(others) { entry in
                    Button {
                        openedToken = InviteToken(id: entry.token)
                    } label: {
                        HStack(spacing: JPSpace.s) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title.isEmpty
                                     ? L("無題のアルバム", "Untitled album") : entry.title)
                                    .font(JPFont.rowTitle)
                                    .foregroundStyle(entry.title.isEmpty ? WebTheme.text2 : WebTheme.foreground)
                                Text(L("招待リンクから参加", "Joined with a link"))
                                    .font(JPFont.caption)
                                    .foregroundStyle(WebTheme.text3)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: JPHeight.tallRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .profileListRow(divider: true)
                    .swipeActions {
                        // **抜けるのではなく、この端末の控えを消すだけ。**
                        // サーバーに「抜ける」口は無い（Web にも無い）
                        Button(role: .destructive) {
                            joined.forget(id: entry.id)
                        } label: {
                            Label(L("一覧から消す", "Remove"), systemImage: "trash")
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    /// 1つのアルバム（板 v2 Albums: 明朝 18 の名前・人数は等幅の数字・右に「アルバムの操作」の丸）。
    /// 2026-10-14 判断: 板の左の3枚の組み絵は出さない——`GET /albums` が表紙の写真を返さない
    /// （サーバーに触らない段）。名前を変える・消すは払いと右の「…」の両方から
    private func row(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            HStack(alignment: .top, spacing: JPSpace.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title.isEmpty ? L("無題のアルバム", "Untitled album") : album.title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(album.title.isEmpty ? WebTheme.text2 : WebTheme.foreground)
                    // 英語は1人なら単数（「1 members」にしない）
                    Text(L("\(album.members) 人", album.members == 1 ? "1 member" : "\(album.members) members"))
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                }
                Spacer(minLength: 0)
                albumMenu(album)
            }
            inviteControls(album)
        }
        .padding(.vertical, JPSpace.s)
        // **払い切りで消さない**（既定の allowsFullSwipe は先頭の削除を確認なしで走らせる。
        // 戻す口は無い）。削除のボタンを押したときだけ消す
        .swipeActions(allowsFullSwipe: false) {
            // **押しただけでは消さない。** 確認を出す（消すのは確認の中）
            Button(role: .destructive) {
                deleting = album
                showDelete = true
            } label: {
                Label(Labels.Common.delete, systemImage: "trash")
            }
            Button {
                renameTitle = album.title
                renamingId = album.id
                showRename = true
            } label: {
                Label(L("名前を変える", "Rename"), systemImage: "pencil")
            }
        }
    }

    /// 行の右の「アルバムの操作」（板 v2 Albums の「…」の丸・44pt）。払いの操作と同じ2つ
    private func albumMenu(_ album: Album) -> some View {
        Menu {
            Button {
                renameTitle = album.title
                renamingId = album.id
                showRename = true
            } label: {
                Label(L("名前を変える", "Rename"), systemImage: "pencil")
            }
            // **押しただけでは消さない。** 確認を出す（消すのは確認の中）
            Button(role: .destructive) {
                deleting = album
                showDelete = true
            } label: {
                Label(Labels.Common.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("アルバムの操作", "Album actions"))
    }

    /// 🔴 **期限が切れたリンクは共有させない。** サーバーは切れた招待も一覧に
    /// 返し続けるので、以前はトークンがあるだけで「共有」を出していた——送った
    /// 相手が開くと「期限が切れています」で断られる。切れていたら同じ場所に
    /// 「招待リンクを作り直す」を出す（`InviteLink.expiry`）。使えるときは
    /// Web と同じく「〜まで」を添え、期限内でも作り直せる（owner の判断 2026-09-27）
    @ViewBuilder
    private func inviteControls(_ album: Album) -> some View {
        if let token = album.inviteToken {
            let expiry = InviteLink.expiry(album.inviteExpiresAt, now: Date())
            HStack(spacing: 12) {
                if expiry != .expired {
                    // 招待リンクはサイトの URL で共有する
                    // （アプリを入れていない人にも開ける）
                    ShareLink(item: model.inviteURL(token: token)) {
                        Label(L("招待リンクを共有", "Share invite link"), systemImage: "square.and.arrow.up")
                            .font(JPFont.footnote.weight(.semibold))
                            // 黒地の上の手がかり（リンク）は真鍮（CLAUDE.md の owner の好み）
                            .foregroundStyle(WebTheme.accent)
                            // 押す場所はラベルの内側で広げる（外側の余白は押せない）
                            .webTappable()
                    }
                    // 作り直し・取り消しの最中は配らない（失効する直前のリンクを配っていた）
                    .disabled(model.inviteWorking.contains(album.id))
                    .buttonStyle(.borderless)
                }
                // **期限内でも作り直せる**（Web の /user/albums と同じ——配ったリンクを
                // 止めて出し直したいとき）。切れていたらこれが唯一の出口
                Button {
                    Task { await model.createInvite(album.id, environment: environment) }
                } label: {
                    Text(expiry == .expired ? L("招待リンクを作り直す", "Recreate invite link")
                                            : L("作り直す", "Recreate"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        // 押す場所は 44pt（隣の「取り消す」と押し間違えない）。**ラベルの
                        // 内側で**広げる——ボタンの外側に付けた余白は押せない
                        .webTappable()
                }
                // 二度押しで2本作らない（下の「招待リンクを作る」と同じ）
                .disabled(model.inviteWorking.contains(album.id))
                .buttonStyle(.borderless)
                Button {
                    Task { await model.revokeInvite(album.id, environment: environment) }
                } label: {
                    Text(L("取り消す", "Revoke"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .webTappable()
                }
                .disabled(model.inviteWorking.contains(album.id))
                // **行に複数のボタンを置くときは borderless。**
                // 既定だと行のどこを押しても両方が反応する
                .buttonStyle(.borderless)
                // 送っている間を見せる（ボタンが薄くなるだけでは、押せたのか分からない）
                if model.inviteWorking.contains(album.id) {
                    ProgressView().controlSize(.small)
                }
            }
            // 知らせは**押したボタンのすぐ下**（下の注意書きより上）
            inviteDoneLine(album)
            switch expiry {
            case .valid(let until):
                Text(L("\(InviteLink.untilLabel(until))まで", "Valid until \(InviteLink.untilLabel(until))"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            case .expired:
                Text(L("招待リンクの期限が切れています", "This invite link has expired"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            case .unknown:
                EmptyView()
            }
            // **前のリンクが死ぬことを書く**（Web と同じ文）。書かないと、配ったリンクが黙って切れる
            Text(L("作り直すと、前のリンクは使えなくなります。", "Recreating stops the previous link from working."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        } else {
            Button {
                Task { await model.createInvite(album.id, environment: environment) }
            } label: {
                Text(L("招待リンクを作る", "Create invite link"))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    // 押す場所は 44pt（上の3つと同じ。ここだけ文字の高さしか押せなかった）
                    .webTappable()
            }
            // **二度押しで作り直さない。** サーバーは「あれば作り直す」ので、
            // 2本目で1本目が失効し、その間に共有したリンクが開けなくなる
            .disabled(model.inviteWorking.contains(album.id))
            .buttonStyle(.borderless)
            // **こちらの枝にも置く。** 取り消すとリンクが消えてこの枝に描き直されるので、
            // 上の枝にだけ置くと「取り消しました」が一度も出なかった
            inviteDoneLine(album)
        }
    }

    /// 作り直した・取り消したことを**その行で**知らせる（`InviteLink.doneMessage`）。
    /// アプリはリンクの字を出さないので、作り直しても見た目がほとんど変わらず、
    /// 押しても何も起きないように見えていた。一覧の上の知らせは、下の行からは見えない
    @ViewBuilder
    private func inviteDoneLine(_ album: Album) -> some View {
        if let done = model.inviteDone, done.albumId == album.id {
            Text(done.message)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.foreground)
        }
    }

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(L("アルバムを作る", "New album")) { showCreate = true }
                    // 作っている間は次を作らせない（二度押しで同じアルバムが2つできた）
                    .disabled(model.isCreating)
                Button(L("招待リンクから参加", "Join with a link")) { showJoin = true }
            } label: {
                // 送っている間を見せる（アラートが閉じた後、届くまで何も起きないように見えた）
                if model.isCreating {
                    ProgressView()
                        .accessibilityLabel(L("アルバムを作っています", "Creating the album"))
                } else {
                    Image(systemName: "plus")
                        .accessibilityLabel(L("アルバムの操作", "Album actions"))
                }
            }
        }
    }

    @ViewBuilder
    private var joinAlertButtons: some View {
        TextField(L("リンクか招待コード", "Link or invite code"), text: $inviteText)
        // 札の「開く」と同じ1本（押した瞬間に参加させない・`openInvite`）
        Button(L("開く", "Open")) { openInvite() }
        Button(Labels.Common.cancel, role: .cancel) { inviteText = "" }
    }

    @ViewBuilder
    private var createAlertButtons: some View {
        TextField(L("名前", "Name"), text: $newTitle)
        Button(L("作る", "Create")) {
            guard !model.isCreating else { return }
            let title = newTitle
            newTitle = ""
            Task { await model.create(title: title, environment: environment) }
        }
        Button(Labels.Common.cancel, role: .cancel) { newTitle = "" }
    }
}

@MainActor
final class AlbumsViewModel: ObservableObject {

    @Published private(set) var albums: [Album] = []
    @Published private(set) var isLoading = false
    /// 一覧を読めなかったとき（次の読み込みで消える）
    @Published var errorMessage: String?
    /// 操作の失敗の一時的な知らせ。**しばらくすると消える**（`flash`）
    @Published private(set) var notice: String?
    private var noticeTask: Task<Void, Never>?
    /// 招待リンクを作る・取り消すのを送っているアルバム
    @Published private(set) var inviteWorking: Set<String> = []
    /// アルバムを作るのを送っている間（2026-10-21）。**二度押しで同じ名前のアルバムを2つ作らない**
    /// （`createInvite` の `inviteWorking` と同じ形）。画面は「アルバムを作る」を止めて輪を出す
    @Published private(set) var isCreating = false
    /// 招待リンクの操作が通った知らせ（その行に出し、しばらくすると消える）
    @Published private(set) var inviteDone: InviteDone?
    private var inviteDoneTask: Task<Void, Never>?
    struct InviteDone: Equatable {
        let albumId: String
        let message: String
    }

    /// 何回目の読み込みか。**古い読み込みの返事が新しい返事を上書きしない**
    private var loadGeneration = 0
    /// この画面で書いた分。**読み込んだ一覧に重ねる**（`AlbumMerge`）
    /// ——書き込みの前に始めた読み込みや、結果整合で古い姿を返す読み込みで、
    /// 消したアルバムが戻る・作ったアルバムが消える・名前が巻き戻るのを防ぐ
    private var writes = AlbumMerge.Writes()
    /// 人が替わった回数（`forget`）。**走っている書き込みの答えを、次の人の一覧に書かない**
    private var era = 0

    /// 人が替わった。**前の人のアルバム（招待リンクつき）を残さない**。
    /// 画面は残ったまま中身だけログイン画面に替わるので、次の人の読み込みが
    /// 返るまで（落ちた回はずっと）前の人の一覧が出ていた
    func forget() {
        era += 1
        loadGeneration += 1
        albums = []
        writes = AlbumMerge.Writes()
        inviteWorking = []
        inviteDoneTask?.cancel()
        inviteDone = nil
        isLoading = false
        errorMessage = nil
        noticeTask?.cancel()
        notice = nil
    }

    /// 空の名前で作る・名前を変えるを押したときの知らせ
    static let nameRequired = L("名前を入れてください", "Please enter a name")

    /// 操作の失敗を一時的に知らせる（数秒で消える）
    func flash(_ message: String, seconds: Double = 4) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func inviteURL(token: String) -> URL {
        AppConfig.siteBaseURL.appendingPathComponent("j").appending(queryItems: [
            URLQueryItem(name: "t", value: token)
        ])
    }

    func load(environment: AppEnvironment) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let list = try await environment.albums.list()
            guard generation == loadGeneration else { return }
            writes = AlbumMerge.settled(writes, loaded: list)
            albums = AlbumMerge.merge(loaded: list, writes: writes)
            isLoading = false
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。失敗と言わない
            guard generation == loadGeneration else { return }
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            isLoading = false
        }
    }

    func create(title: String, environment: AppEnvironment) async {
        guard !isCreating else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // **黙って戻らない。** 空のまま「作る」を押すと、アラートが閉じて何も起きなかった
        guard !trimmed.isEmpty else { return flash(Self.nameRequired) }
        isCreating = true
        defer { isCreating = false }
        let myEra = era
        do {
            let album = try await environment.albums.create(title: trimmed)
            guard myEra == era else { return }
            writes.created.append(.init(value: album, at: Date()))
            // 🔴 **既に並んでいれば足さない。** 作っている間に始めた読み込みが先に返ると、
            // 作ったアルバムはもう一覧に居る。そこへ足すと同じ id が2つ並んでいた
            // （ForEach の id が重なる）
            albums.removeAll { $0.id == album.id }
            albums.insert(album, at: 0)
        } catch {
            guard myEra == era else { return }
            flash((error as? LocalizedError)?.errorDescription ?? L("作れませんでした", "Couldn't create"))
        }
    }

    /// 名前を変える。**画面はサーバーが受けてから直す**
    /// （先に直すと、断られたときに画面だけ新しい名前になる）。
    func rename(_ id: String, title: String, environment: AppEnvironment) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return flash(Self.nameRequired) }
        let myEra = era
        do {
            // **サーバーが直した名前を採る**（60字で切られる・制御文字が落ちる）
            let saved = try await environment.albums.rename(id: id, title: trimmed)
            guard myEra == era else { return }
            writes.renamed[id] = .init(value: saved, at: Date())
            albums = albums.map { album in
                guard album.id == id else { return album }
                return Album(id: album.id, title: saved, createdAt: album.createdAt,
                             memberCount: album.memberCount, inviteToken: album.inviteToken,
                             inviteExpiresAt: album.inviteExpiresAt)
            }
        } catch {
            guard myEra == era else { return }
            flash((error as? LocalizedError)?.errorDescription
                ?? L("名前を変えられませんでした", "Couldn't rename"))
        }
    }

    /// 消せたか（呼んだ側が参加の控えからも外す）
    func delete(_ id: String, environment: AppEnvironment) async -> Bool {
        let myEra = era
        do {
            try await environment.albums.delete(id: id)
            guard myEra == era else { return false }
            writes.deleted.insert(id)
            albums.removeAll { $0.id == id }
            return true
        } catch {
            guard myEra == era else { return false }
            flash((error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete"))
            return false
        }
    }

    private func showInviteDone(_ albumId: String, _ message: String, seconds: Double = 4) {
        inviteDone = InviteDone(albumId: albumId, message: message)
        inviteDoneTask?.cancel()
        inviteDoneTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.inviteDone = nil
        }
    }

    func createInvite(_ id: String, environment: AppEnvironment) async {
        guard !inviteWorking.contains(id) else { return }
        inviteWorking.insert(id)
        defer { inviteWorking.remove(id) }
        let myEra = era
        do {
            // **返ってきたリンクを手元にも書く。** 一覧は結果整合で読むので、
            // 読み直しが古いとリンクが出ず、もう一度押すと作り直し（前のリンクが失効）になる
            let replaced = albums.first { $0.id == id }?.inviteToken != nil
            let invite = try await environment.albums.createInvite(albumId: id)
            guard myEra == era else { return }
            writes.invites[id] = .init(value: invite, at: Date())
            albums = AlbumMerge.merge(loaded: albums, writes: writes)
            showInviteDone(id, InviteLink.doneMessage(replaced ? .recreated : .created))
            await load(environment: environment)
        } catch {
            guard myEra == era else { return }
            flash((error as? LocalizedError)?.errorDescription ?? L("招待リンクを作れませんでした", "Couldn't create the invite link"))
        }
    }

    func revokeInvite(_ id: String, environment: AppEnvironment) async {
        guard !inviteWorking.contains(id) else { return }
        inviteWorking.insert(id)
        defer { inviteWorking.remove(id) }
        let myEra = era
        do {
            try await environment.albums.revokeInvite(albumId: id)
            guard myEra == era else { return }
            writes.invites[id] = .init(value: nil, at: Date())
            albums = AlbumMerge.merge(loaded: albums, writes: writes)
            showInviteDone(id, InviteLink.doneMessage(.revoked))
            await load(environment: environment)
        } catch {
            guard myEra == era else { return }
            flash((error as? LocalizedError)?.errorDescription ?? L("取り消せませんでした", "Couldn't revoke"))
        }
    }
}

