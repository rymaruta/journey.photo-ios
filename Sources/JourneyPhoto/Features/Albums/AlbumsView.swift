import SwiftUI

/// アルバム。招待リンクで人を呼べる、写真のまとまり。
struct AlbumsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = AlbumsViewModel()
    @State private var newTitle = ""
    @State private var showCreate = false

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
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
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
