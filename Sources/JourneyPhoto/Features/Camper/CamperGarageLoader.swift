import SwiftUI

/// 自分の写真を自分で読んでから `CamperGarageView` を出す入れ物（2026-10-18・設定の「旅の道具」から開く口）。
///
/// 設定の画面は自分の写真を持たない。マイページと同じ口（`ProfileImageFromPhoto.myPhotos`＝`PhotoService.myPhotos()`、
/// 見本の入り方では公開一覧から自分のぶん）で読む。
///
/// **2026-10-18 見直し**: 読めるまで車の画面を出さない。読み込み中は「読み込み中」、読めなければ一言と「もう一度」。
/// 数の行（0件・飾りなし）を見せず、「届いた」の判定と保存もしない。読めてから車の画面に切り替える。
/// マイページからは今までどおり読み終えた写真を渡す（ここを通さない＝二重に読まない）
struct CamperGarageLoader: View {
    let ownerName: String?
    let userId: String?

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var loader = CamperPhotoLoader()

    var body: some View {
        Group {
            switch loader.phase {
            case .loaded:
                CamperGarageView(ownerName: ownerName, userId: userId, photos: loader.photos, photosLoaded: true)
            case .loading:
                VStack(spacing: JPSpace.s) {
                    ProgressView()
                    Text(L("写真を読み込んでいます…", "Loading your photos…"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("camper.loading")
            case .failed:
                ErrorBanner(message: L("写真を読めませんでした。つながる所で、もう一度お試しください。",
                                       "Couldn\u{2019}t load your photos. Try again when you\u{2019}re online.")) {
                    Task { await load() }
                }
                .padding(.horizontal, JPSpace.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("camper.loadFailed")
            }
        }
        .webScreen()
        .navigationTitle(CamperText.carName)
        .task(id: userId) { await load() }
    }

    private func load() async {
        await loader.load(userId: userId) { await ProfileImageFromPhoto.myPhotos(environment: environment) }
    }
}

/// 設定から開いた車の画面の写真の読み込み（`SwiftUI` を読まない部分・テストで見る）。
///
/// - 今の人の写真を読めたら、もう読まない（画面に戻るたびに読み直さない）
/// - 読んでいる最中に呼ばれても、二本目を出さない
/// - 取り消された（画面を離れた）読み込みの結果は入れない。次に開いたときに読み直す
/// - 人が替わったら、前の人の写真を捨ててから読む
@MainActor
final class CamperPhotoLoader: ObservableObject {

    enum Phase: Equatable { case loading, failed, loaded }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var photos: [Photo] = []
    /// 写真を読めた人
    private(set) var loadedFor: String?
    /// 読んでいる最中の人
    private var inFlight: String?

    func load(userId: String?, fetch: () async -> [Photo]?) async {
        guard let userId else { phase = .failed; return }
        if phase == .loaded, loadedFor == userId { return }
        guard inFlight != userId else { return }
        if loadedFor != userId {
            photos = []
            loadedFor = nil
        }
        inFlight = userId
        phase = .loading
        let fresh = await fetch()
        inFlight = nil
        guard !Task.isCancelled else { return }
        guard let fresh else { phase = .failed; return }
        photos = fresh
        loadedFor = userId
        phase = .loaded
    }
}

/// 自分の車の要サーバーの部品（`GET /user/camper`・2026-10-19 第2段）を読む（`SwiftUI` を読まない部分・テストで見る）。
///
/// - 読めて `launched: true` なら、サーバーの部品を数に入れ、分母を 131 にする（`CamperServerParts.open`）
/// - `launched: false`・通信の失敗・断り（退会など）は、端末の数え方のまま（分母 98・「近日」）。画面は止めない
/// - 写真の保存で届いた部品（`CamperStore.inbox`）は、読めなくても持っている扱い
/// - 今の人の答えを読めたら、画面に戻るたびには読まない（数え直しはサーバーが1日1回に絞る）
/// - 人が替わったら、前の人の答えを捨ててから読む。取り消された読み込みの結果は入れない
@MainActor
final class CamperServerModel: ObservableObject {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var parts = CamperServerParts.closed
    @Published private(set) var phase: Phase = .idle
    private(set) var loadedFor: String?
    private var inFlight: String?

    /// 読み終えた（読めた・読めなかった）か。「届いた」の判定はここまで待つ（後から届いた部品を次回に回さない）
    var settled: Bool { phase == .loaded || phase == .failed }

    func load(userId: String?, store: CamperStore, fetch: () async throws -> CamperServerState) async {
        guard let userId else {
            parts = .closed
            phase = .failed
            return
        }
        if phase == .loaded, loadedFor == userId { return }
        guard inFlight != userId else { return }
        if loadedFor != userId {
            parts = CamperServerParts(state: nil, inbox: store.inbox)
            loadedFor = nil
        }
        inFlight = userId
        phase = .loading
        let result: CamperServerState?
        do { result = try await fetch() } catch { result = nil }
        inFlight = nil
        guard !Task.isCancelled else { return }
        parts = CamperServerParts(state: result, inbox: store.inbox)
        if result != nil { loadedFor = userId }
        phase = result != nil ? .loaded : .failed
    }

    /// 届いた画面で見せた部品を、写真の保存の控えから外す
    func noteShown(store: CamperStore) {
        let seen = store.seen ?? []
        let left = store.inbox.filter { !seen.contains($0) }
        store.clearInbox()
        if !left.isEmpty { store.receive(left) }
    }
}
