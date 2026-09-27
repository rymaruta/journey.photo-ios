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
    }

    // **段ごとに割ってある。** 一本の長い `List { … }` にすると、Swift の
    // 型検査が現実的な時間で終わらなくなることがある
    // （"unable to type-check this expression in reasonable time"）。
    private var list: some View {
        List {
            statusRow
            ForEach(model.albums) { album in
                row(album)
            }
            joinedSection
        }
        .webScreen()
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

    @ViewBuilder
    private var statusRow: some View {
        if let message = model.errorMessage {
            Text(message).foregroundStyle(WebTheme.danger).font(.callout)
        } else if model.albums.isEmpty && !model.isLoading {
            Text(L("まだアルバムがありません", "No albums yet")).foregroundStyle(.secondary)
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
        let mine = Set(model.albums.map { $0.id })
        let others = joined.entries.filter { !mine.contains($0.id) }
        if !others.isEmpty {
            Section(L("参加しているアルバム", "Albums you joined")) {
                ForEach(others) { entry in
                    Button {
                        openedToken = InviteToken(id: entry.token)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title.isEmpty
                                 ? L("無題のアルバム", "Untitled album") : entry.title)
                            Text(L("招待リンクから参加", "Joined with a link"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
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

    private func row(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.title.isEmpty ? L("無題のアルバム", "Untitled album") : album.title)
            Text(L("\(album.members) 人", "\(album.members) members"))
                .font(.caption)
                .foregroundStyle(.secondary)
            inviteControls(album)
        }
        // **払い切りで消さない**（既定の allowsFullSwipe は先頭の削除を確認なしで走らせる。
        // 戻す口は無い）。削除のボタンを押したときだけ消す
        .swipeActions(allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    // **参加の控えからも外す。** 自分のリンクを自分で開くと控えにも
                    // 入るので、消した途端に「参加しているアルバム」へ落ちてきて、
                    // 押すと「この招待リンクは使えません」になっていた
                    if await model.delete(album.id, environment: environment) {
                        joined.forget(id: album.id)
                    }
                }
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

    @ViewBuilder
    private func inviteControls(_ album: Album) -> some View {
        if let token = album.inviteToken {
            HStack {
                // 招待リンクはサイトの URL で共有する
                // （アプリを入れていない人にも開ける）
                ShareLink(item: model.inviteURL(token: token)) {
                    Label(L("招待リンクを共有", "Share invite link"), systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                Spacer()
                Button(L("取り消す", "Revoke")) {
                    Task { await model.revokeInvite(album.id, environment: environment) }
                }
                .font(.caption)
                .disabled(model.inviteWorking.contains(album.id))
                // **行に複数のボタンを置くときは borderless。**
                // 既定だと行のどこを押しても両方が反応する
                .buttonStyle(.borderless)
            }
        } else {
            Button(L("招待リンクを作る", "Create invite link")) {
                Task { await model.createInvite(album.id, environment: environment) }
            }
            .font(.caption)
            // **二度押しで作り直さない。** サーバーは「あれば作り直す」ので、
            // 2本目で1本目が失効し、その間に共有したリンクが開けなくなる
            .disabled(model.inviteWorking.contains(album.id))
            .buttonStyle(.borderless)
        }
    }

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(L("アルバムを作る", "New album")) { showCreate = true }
                Button(L("招待リンクから参加", "Join with a link")) { showJoin = true }
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(L("アルバムの操作", "Album actions"))
            }
        }
    }

    @ViewBuilder
    private var joinAlertButtons: some View {
        TextField(L("リンクか招待コード", "Link or invite code"), text: $inviteText)
        Button(L("開く", "Open")) {
            // **押した瞬間に参加させない。** 何のアルバムか分からないまま
            // 参加することになる（Web は `/j?t=` が中身を見せてから聞く）
            let token = InviteLink.token(from: inviteText)
            inviteText = ""
            openedToken = token.isEmpty ? nil : InviteToken(id: token)
            if openedToken == nil {
                model.errorMessage = L("招待リンクを読み取れませんでした", "Couldn't read that invite link")
            }
        }
        Button(Labels.Common.cancel, role: .cancel) { inviteText = "" }
    }

    @ViewBuilder
    private var createAlertButtons: some View {
        TextField(L("名前", "Name"), text: $newTitle)
        Button(L("作る", "Create")) {
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
    @Published var errorMessage: String?
    /// 招待リンクを作る・取り消すのを送っているアルバム
    @Published private(set) var inviteWorking: Set<String> = []

    /// 何回目の読み込みか。**古い読み込みの返事が新しい返事を上書きしない**
    private var loadGeneration = 0
    /// この画面で書いた分。**読み込んだ一覧に重ねる**（`AlbumMerge`）
    /// ——書き込みの前に始めた読み込みや、結果整合で古い姿を返す読み込みで、
    /// 消したアルバムが戻る・作ったアルバムが消える・名前が巻き戻るのを防ぐ
    private var writes = AlbumMerge.Writes()

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
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            isLoading = false
        }
    }

    func create(title: String, environment: AppEnvironment) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let album = try await environment.albums.create(title: trimmed)
            writes.created.append(.init(value: album, at: Date()))
            // 🔴 **既に並んでいれば足さない。** 作っている間に始めた読み込みが先に返ると、
            // 作ったアルバムはもう一覧に居る。そこへ足すと同じ id が2つ並んでいた
            // （ForEach の id が重なる）
            albums.removeAll { $0.id == album.id }
            albums.insert(album, at: 0)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("作れませんでした", "Couldn't create")
        }
    }

    /// 名前を変える。**画面はサーバーが受けてから直す**
    /// （先に直すと、断られたときに画面だけ新しい名前になる）。
    func rename(_ id: String, title: String, environment: AppEnvironment) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            // **サーバーが直した名前を採る**（60字で切られる・制御文字が落ちる）
            let saved = try await environment.albums.rename(id: id, title: trimmed)
            writes.renamed[id] = .init(value: saved, at: Date())
            albums = albums.map { album in
                guard album.id == id else { return album }
                return Album(id: album.id, title: saved, createdAt: album.createdAt,
                             memberCount: album.memberCount, inviteToken: album.inviteToken,
                             inviteExpiresAt: album.inviteExpiresAt)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("名前を変えられませんでした", "Couldn't rename")
        }
    }

    /// 消せたか（呼んだ側が参加の控えからも外す）
    func delete(_ id: String, environment: AppEnvironment) async -> Bool {
        do {
            try await environment.albums.delete(id: id)
            writes.deleted.insert(id)
            albums.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
            return false
        }
    }

    func createInvite(_ id: String, environment: AppEnvironment) async {
        guard !inviteWorking.contains(id) else { return }
        inviteWorking.insert(id)
        defer { inviteWorking.remove(id) }
        do {
            // **返ってきたリンクを手元にも書く。** 一覧は結果整合で読むので、
            // 読み直しが古いとリンクが出ず、もう一度押すと作り直し（前のリンクが失効）になる
            let invite = try await environment.albums.createInvite(albumId: id)
            writes.invites[id] = .init(value: invite, at: Date())
            albums = AlbumMerge.merge(loaded: albums, writes: writes)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("招待リンクを作れませんでした", "Couldn't create the invite link")
        }
    }

    func revokeInvite(_ id: String, environment: AppEnvironment) async {
        guard !inviteWorking.contains(id) else { return }
        inviteWorking.insert(id)
        defer { inviteWorking.remove(id) }
        do {
            try await environment.albums.revokeInvite(albumId: id)
            writes.invites[id] = .init(value: nil, at: Date())
            albums = AlbumMerge.merge(loaded: albums, writes: writes)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("取り消せませんでした", "Couldn't revoke")
        }
    }
}
