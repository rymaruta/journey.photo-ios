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
            if auth.userId == nil {
                SignInView(reason: "アルバムを使うにはログインしてください")
            } else {
                list
            }
        }
        .navigationTitle("アルバム")
    }

    private var list: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            } else if model.albums.isEmpty && !model.isLoading {
                Text("まだアルバムがありません").foregroundStyle(.secondary)
            }

            ForEach(model.albums) { album in
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title.isEmpty ? "無題のアルバム" : album.title)
                    Text("\(album.members) 人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let token = album.inviteToken {
                        HStack {
                            // 招待リンクはサイトの URL で共有する
                            // （アプリを入れていない人にも開ける）
                            ShareLink(item: model.inviteURL(token: token)) {
                                Label("招待リンクを共有", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                            }
                            Spacer()
                            Button("取り消す") {
                                Task { await model.revokeInvite(album.id, environment: environment) }
                            }
                            .font(.caption)
                        }
                    } else {
                        Button("招待リンクを作る") {
                            Task { await model.createInvite(album.id, environment: environment) }
                        }
                        .font(.caption)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await model.delete(album.id, environment: environment) }
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("アルバムを作る") { showCreate = true }
                    Button("招待リンクから参加") { showJoin = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("招待リンクから参加", isPresented: $showJoin) {
            TextField("リンクか招待コード", text: $inviteText)
            Button("参加する") {
                let text = inviteText
                inviteText = ""
                Task { await model.join(inviteText: text, environment: environment) }
            }
            Button("やめる", role: .cancel) { inviteText = "" }
        } message: {
            Text("受け取ったリンク（https://journey-photo.com/j?t=…）をそのまま貼れます。")
        }
        .alert("アルバムを作る", isPresented: $showCreate) {
            TextField("名前", text: $newTitle)
            Button("作る") {
                let title = newTitle
                newTitle = ""
                Task { await model.create(title: title, environment: environment) }
            }
            Button("やめる", role: .cancel) { newTitle = "" }
        }
        .task { await model.load(environment: environment) }
        .refreshable { await model.load(environment: environment) }
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "読み込めませんでした"
        }
    }

    func create(title: String, environment: AppEnvironment) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let album = try await environment.albums.create(title: trimmed)
            albums.insert(album, at: 0)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "作れませんでした"
        }
    }

    /// 招待リンクでも招待コードでも受ける。
    ///
    /// **リンクをそのまま貼れるようにする。** 受け取った人は `?t=` の後ろだけを
    /// 取り出す作業をしたくない（URL を貼って弾かれるのがいちばん多い失敗）。
    func join(inviteText: String, environment: AppEnvironment) async {
        let token = Self.token(from: inviteText)
        guard !token.isEmpty else {
            errorMessage = "招待リンクを読み取れませんでした"
            return
        }
        do {
            _ = try await environment.albums.join(token: token)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "参加できませんでした"
        }
    }

    /// `https://…/j?t=<トークン>` からトークンを取り出す。
    /// URL でなければ、打たれた文字列そのものをトークンとみなす。
    static func token(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return trimmed }
        if let value = components.queryItems?.first(where: { $0.name == "t" })?.value {
            return value
        }
        return components.scheme == nil ? trimmed : ""
    }

    func delete(_ id: String, environment: AppEnvironment) async {
        do {
            try await environment.albums.delete(id: id)
            albums.removeAll { $0.id == id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "削除できませんでした"
        }
    }

    func createInvite(_ id: String, environment: AppEnvironment) async {
        do {
            _ = try await environment.albums.createInvite(albumId: id)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "招待リンクを作れませんでした"
        }
    }

    func revokeInvite(_ id: String, environment: AppEnvironment) async {
        do {
            try await environment.albums.revokeInvite(albumId: id)
            await load(environment: environment)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "取り消せませんでした"
        }
    }
}
