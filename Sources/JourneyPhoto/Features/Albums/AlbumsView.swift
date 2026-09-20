import SwiftUI

/// アルバム。招待リンクで人を呼べる、写真のまとまり。
struct AlbumsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = AlbumsViewModel()
    @State private var newTitle = ""
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var inviteText = ""

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
        }
        .toolbar { addMenu }
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
            Text(message).foregroundStyle(.red).font(.callout)
        } else if model.albums.isEmpty && !model.isLoading {
            Text(L("まだアルバムがありません", "No albums yet")).foregroundStyle(.secondary)
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
        .swipeActions {
            Button(role: .destructive) {
                Task { await model.delete(album.id, environment: environment) }
            } label: {
                Label(Labels.Common.delete, systemImage: "trash")
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
                // **行に複数のボタンを置くときは borderless。**
                // 既定だと行のどこを押しても両方が反応する
                .buttonStyle(.borderless)
            }
        } else {
            Button(L("招待リンクを作る", "Create invite link")) {
                Task { await model.createInvite(album.id, environment: environment) }
            }
            .font(.caption)
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
        Button(L("参加する", "Join")) {
            let text = inviteText
            inviteText = ""
            Task { await model.join(inviteText: text, environment: environment) }
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

    func inviteURL(token: String) -> URL {
        AppConfig.siteBaseURL.appendingPathComponent("j").appending(queryItems: [
            URLQueryItem(name: "t", value: token)
        ])
    }

    func load(environment: AppEnvironment) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            albums = try await environment.albums.list()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }

    func create(title: String, environment: AppEnvironment) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let album = try await environment.albums.create(title: trimmed)
            albums.insert(album, at: 0)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("作れませんでした", "Couldn't create")
        }
    }

    /// 招待リンクでも招待コードでも受ける。
    ///
    /// **リンクをそのまま貼れるようにする。** 受け取った人は `?t=` の後ろだけを
    /// 取り出す作業をしたくない（URL を貼って弾かれるのがいちばん多い失敗）。
    func join(inviteText: String, environment: AppEnvironment) async {
        let token = InviteLink.token(from: inviteText)
        guard !token.isEmpty else {
            errorMessage = L("招待リンクを読み取れませんでした", "Couldn't read that invite link")
            return
        }
        do {
            _ = try await environment.albums.join(token: token)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("参加できませんでした", "Couldn't join")
        }
    }

    func delete(_ id: String, environment: AppEnvironment) async {
        do {
            try await environment.albums.delete(id: id)
            albums.removeAll { $0.id == id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }

    func createInvite(_ id: String, environment: AppEnvironment) async {
        do {
            _ = try await environment.albums.createInvite(albumId: id)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("招待リンクを作れませんでした", "Couldn't create the invite link")
        }
    }

    func revokeInvite(_ id: String, environment: AppEnvironment) async {
        do {
            try await environment.albums.revokeInvite(albumId: id)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("取り消せませんでした", "Couldn't revoke")
        }
    }
}
