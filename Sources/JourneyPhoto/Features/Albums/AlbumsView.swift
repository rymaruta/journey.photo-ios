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
        }
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

    @ViewBuilder
    private func inviteControls(_ album: Album) -> some View {
        if album.inviteToken != nil,
           AlbumsViewModel.isInviteExpired(album.inviteExpiresAt, now: Date()) {
            // **期限の切れたリンクは共有させない**（受け取った人が開けない）。
            // 作り直す——サーバーは作り直すと前のリンクを自動で取り消す
            HStack {
                Text(L("招待リンクの期限が切れています", "The invite link has expired"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("作り直す", "Recreate")) {
                    Task { await model.createInvite(album.id, environment: environment) }
                }
                .font(.caption)
                .disabled(model.inviteWorking.contains(album.id))
                .buttonStyle(.borderless)
            }
        } else if let token = album.inviteToken {
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
            if let expiry = AlbumsViewModel.inviteExpiry(album.inviteExpiresAt) {
                Text(L("期限 \(expiry.formatted(date: .abbreviated, time: .shortened))",
                       "Expires \(expiry.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                model.flash(L("招待リンクを読み取れませんでした", "Couldn't read that invite link"))
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
    /// 一覧を読めなかったとき（次の読み込みで消える）
    @Published var errorMessage: String?
    /// 操作の失敗の一時的な知らせ。**しばらくすると消える**（`flash`）
    @Published private(set) var notice: String?
    private var noticeTask: Task<Void, Never>?
    /// 招待リンクを作る・取り消すのを送っているアルバム
    @Published private(set) var inviteWorking: Set<String> = []

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
        isLoading = false
        errorMessage = nil
        noticeTask?.cancel()
        notice = nil
    }

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

    /// 招待リンクの期限（サーバーは `toISOString()`＝小数秒つきで返す）。読めなければ nil
    nonisolated static func inviteExpiry(_ expiresAt: String?) -> Date? {
        guard let expiresAt, !expiresAt.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: expiresAt) { return date }
        return ISO8601DateFormatter().date(from: expiresAt)
    }

    /// 招待リンクの期限が切れているか。**期限が無い・読めないときは切れていない扱い**
    /// （共有を消すと、有効なリンクまで出せなくなる。開けるかはサーバーが決める）
    nonisolated static func isInviteExpired(_ expiresAt: String?, now: Date) -> Bool {
        guard let expiry = inviteExpiry(expiresAt) else { return false }
        return expiry <= now
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
        guard !trimmed.isEmpty else { return }
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

    func createInvite(_ id: String, environment: AppEnvironment) async {
        guard !inviteWorking.contains(id) else { return }
        inviteWorking.insert(id)
        defer { inviteWorking.remove(id) }
        let myEra = era
        do {
            // **返ってきたリンクを手元にも書く。** 一覧は結果整合で読むので、
            // 読み直しが古いとリンクが出ず、もう一度押すと作り直し（前のリンクが失効）になる
            let invite = try await environment.albums.createInvite(albumId: id)
            guard myEra == era else { return }
            writes.invites[id] = .init(value: invite, at: Date())
            albums = AlbumMerge.merge(loaded: albums, writes: writes)
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
            await load(environment: environment)
        } catch {
            guard myEra == era else { return }
            flash((error as? LocalizedError)?.errorDescription ?? L("取り消せませんでした", "Couldn't revoke"))
        }
    }
}
