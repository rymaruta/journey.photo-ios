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
