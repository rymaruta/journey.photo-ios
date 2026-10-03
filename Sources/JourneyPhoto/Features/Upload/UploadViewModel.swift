import Foundation
import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit
// 帯のサムネを縮めて読む（`StripThumb`）
import ImageIO

/// スポットの画面から開いた投稿の行き先。撮影地の名前と座標を先に入れ、
/// 保存で `spotId` を付ける（スポットのページの「この場所の写真」に並ぶ）
struct UploadSpotTarget: Equatable {
    let spotId: String
    let name: String
    /// 公開してよい座標（約1km）。無いスポットは写真の位置のまま
    let coords: Photo.Coords?

    init(spotId: String, name: String, coords: Photo.Coords?) {
        self.spotId = spotId
        self.name = name
        self.coords = coords
    }

    init(_ spot: OfficialSpot) {
        self.init(spotId: spot.spotId, name: spot.name, coords: spot.coords)
    }

    /// 写真の位置がスポットからこれより離れていたら、そのスポットの写真とみなさない
    /// （別の旅の写真を混ぜて選んだとき）。スポットの座標は約1kmに丸めてあり、
    /// 遠くから撮る景色（富士山・雲海）もあるので広めに取る
    static let nearbyKm = 10.0

    /// この写真をスポットの写真として扱うか。**位置の無い写真は扱う**（本人がスポットの
    /// 画面から選んだ）。位置があってスポットから遠い写真は普通の投稿として扱う
    func covers(_ prepared: ImagePreparer.Prepared) -> Bool {
        guard let taken = prepared.coords, let coords else { return true }
        return TravelDistance.kilometers(from: taken, to: coords) <= Self.nearbyKm
    }

    /// 送る `spotId`。次のどれかなら付けない:
    /// - 本人が撮影地を空にした（場所を伏せたのに、紐付けで分かってしまう）
    /// - 撮影地からスポットの名前が消えた（別の場所に書き換えた＝このスポットで撮っていない）
    ///
    /// **名前を含んでいればよい**——「高屋神社, 香川」のように県を足しただけで外すと、
    /// 帯は出たままなのに黙って紐付けが消える
    static func spotIdToSend(_ target: UploadSpotTarget?, for item: PendingPhoto) -> String? {
        guard let target, !item.locationClearedByUser, item.location.contains(target.name) else { return nil }
        return target.spotId
    }
}

/// 投稿画面の帯のサムネ（無編集の絵・2026-10-03）。
///
/// 帯は 96×120pt。3倍の画面で長い辺 360px あれば足りる——編集後のサムネ
/// （`UploadViewModel.renderStripPreview`）と同じ大きさにそろえる
enum StripThumb {
    static let maxPixelSize = 360

    /// どのデータから作るか。**一覧用のサムネ（512px）があればそれ**——1920px の本体を読まずに済む。
    /// 無ければ（カメラ・旅の写真で作れなかった）本体から
    static func source(for prepared: ImagePreparer.Prepared) -> Data {
        prepared.thumbnail ?? prepared.data
    }

    /// ImageIO の縮小（`ImagePreparer.downsampledImage`）で長い辺 `maxPixelSize` に作る。
    /// 全部を読み込んでから縮めない。**画面の処理の外で呼ぶ**。読めなければ nil
    static func make(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return ImagePreparer.downsampledImage(source: source, maxPixelSize: maxPixelSize)
    }
}

/// 投稿を待っている1枚。
///
/// **題・説明・撮影地は写真ごと**（Web の投稿画面と同じ）。タグ・カテゴリ・
/// 公開／下書き・アルバム・曲は**まとめて同じもの**を付ける——まとめて上げる
/// のは「同じ旅の写真」なので、そこが割れると選び直す手間の方が大きい。
struct PendingPhoto: Identifiable {
    let id = UUID()
    let prepared: ImagePreparer.Prepared
    var preview: Image?
    var title = ""
    var caption = ""
    /// 🔴 **入っていた撮影地を本人が空にしたら、座標も送らない。** 撮影地は写真の
    /// 位置から自動で入るので、自宅の地名を知られたくなくて消しても、座標（約1km）は
    /// 送られて地図に出ていた。**空にした操作だけを見る**——自動入力が間に合わない
    /// （選んですぐ投稿・圏外・候補なし）ときは Web と同じく座標を送る
    var location = "" {
        didSet {
            // 空白だけは空と同じに見る（送るときは trim で空になるのに、
            // 印だけ解けて座標が送られていた）
            let now = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let before = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if now.isEmpty, !before.isEmpty { locationClearedByUser = true }
            else if !now.isEmpty { locationClearedByUser = false }
        }
    }
    /// 撮影地を候補から選んだときに入る座標（写真の EXIF より優先）
    var pickedCoords: Photo.Coords?
    /// ライブラリから選んだ写真の印（カメラで撮った分は nil）。
    /// 選び直しのときに「まだ選ばれているか」を見るのに使う
    var pickerItem: PhotosPickerItem?

    /// 入っていた撮影地を空にしたか（`location` の didSet だけが書く）
    private(set) var locationClearedByUser = false

    // MARK: 写真の編集（Phase 2・2026-10-02）

    /// 編集のレシピ。**写真ごと**（別の写真には効かない）。無編集なら `prepared` をそのまま送る
    var recipe: PhotoRecipe = .identity
    /// 編集の元（選んだときの原本の一時ファイル・`PhotoEditSources`）。
    /// 無ければ整えた本体（`prepared.data`）を元にする——旅の写真から来た分（選ぶ画面が整えてから
    /// 渡す）と、一時ファイルを書けなかった分
    var editSource: URL?
    /// 編集後の見本（帯のサムネ）。無編集・まだ描けていなければ nil（元の `preview` を出す）
    var editedPreview: Image?

    /// 帯に出す絵。編集してあれば編集後
    var stripPreview: Image? {
        recipe.isIdentity ? preview : (editedPreview ?? preview)
    }

    /// 帯のサムネに付ける札（プリセット名か「調整」）。無編集なら nil
    var editBadge: String? { PhotoEditBadge.text(for: recipe) }

    /// 編集の元の中身を読む口。**画面の処理の外で呼ぶ**（数 MB）。一時ファイルが読めなければ整えた本体。
    /// 読むものだけを持つ（写真の行そのもの＝画面の絵を抱えたまま処理の外へ渡さない）
    var editSourceReader: @Sendable () -> Data {
        let url = editSource
        let fallback = prepared.data
        return { url.flatMap { try? Data(contentsOf: $0) } ?? fallback }
    }

    /// 送る座標。空にした撮影地の座標は送らない
    var coordsToSend: Photo.Coords? {
        locationClearedByUser ? nil : (pickedCoords ?? prepared.coords)
    }

    /// スポットから開いた投稿で送る座標。**位置の無い写真は、スポットに紐付くあいだ
    /// スポットの座標を送る。**
    ///
    /// 以前は `pickedCoords` に入れていたが、撮影地の欄は文字が変わると
    /// `pickedCoords` を捨てる（`PlaceSearchField`）ので、「高屋神社, 香川」と足しただけで
    /// `spotId` は付いたままピンだけ消えていた。紐付けと同じ条件（`spotIdToSend`）で決める
    func coordsToSend(spot: UploadSpotTarget?) -> Photo.Coords? {
        if let coords = coordsToSend { return coords }
        guard prepared.coords == nil, UploadSpotTarget.spotIdToSend(spot, for: self) != nil else { return nil }
        return spot?.coords
    }
}

@MainActor
final class UploadViewModel: ObservableObject {

    /// **一度に選べる枚数。** 本当の上限はサーバーの1000枚
    /// （`api-user/src/photoLimit.ts`）だが、1枚ずつ題と説明を書く画面なので、
    /// 一度に扱う数はここで抑える（多すぎると、どれを書いているか見失う）。
    /// 画面の外（旅の写真を選ぶ画面の init）からも読むので MainActor に縛らない
    nonisolated static let maxSelection = 10

    /// スポットの画面から開いたときの行き先（`UploadSpotTarget`）。外すと普通の投稿に戻る
    @Published var spot: UploadSpotTarget?

    /// スポットを外す。スポットの座標は外した時点で送らなくなる（`coordsToSend(spot:)`）。
    /// 撮影地の名前は残す（本人が直せる。空にすると座標まで送らなくなる）
    func removeSpot() {
        spot = nil
    }

    @Published var pickerItems: [PhotosPickerItem] = [] {
        didSet {
            // 送信の後始末で選択を直しただけ（`setSelectionQuietly`）なら読み直さない
            guard !isSettingSelectionQuietly else { return }
            // **前の読み込みを捨ててから始める。** 重ねると、外したはずの
            // 写真まで待ち行列に残って一緒に投稿される
            loadTask?.cancel()
            let picked = pickerItems
            loadTask = Task { [weak self] in await self?.loadPicked(picked) }
        }
    }
    /// 投稿を待っている写真。**画面から直接書き換える**ので `var`
    @Published var items: [PendingPhoto] = [] {
        didSet {
            // 編集の元（一時ファイル）は、並びから居なくなった写真の分を消す
            // （外した・選び直した・投稿した・`reset()`。どの道でもここを通る）
            let inUse = Set(items.compactMap(\.editSource))
            if inUse != editSources.urls { editSources.keep(only: inUse) }
        }
    }
    /// 編集の元の一時ファイル。画面を閉じたら（`deinit`）全部消す
    let editSources = PhotoEditSources()

    // ここから下は、まとめて同じものが付く
    @Published var song: Photo.Song?
    @Published var tagsText = ""
    /// 最初から入れておくタグ（今日のテーマの「参加する」から来たとき・`UploadView`）。
    /// **入れるだけで、消せる**——決めつけない
    var initialTag: String?
    /// `initialTag` をもう入れたか。**一度だけ入れる**——`onAppear` は選択画面などから
    /// 戻るたびに呼ばれるので、印が無いと利用者が空にしたタグがまた入る
    private var appliedInitialTag = false

    /// 今日のテーマのタグを入れる（画面が出たとき）。既に何か打っていれば触らない
    func applyInitialTag() {
        guard let initialTag, !appliedInitialTag else { return }
        appliedInitialTag = true
        // 入れたタグは「最初から入っていたもの」として控える（書きかけ扱いにしない・main #86）
        if tagsText.isEmpty {
            tagsText = initialTag
            initialTagsText = initialTag
        }
    }
    /// **非公開で始める**（旅の写真からまとめて来たとき・`UploadView` の `startPrivate`）。
    /// 何年も前の旅を一度に出すので、まず自分だけに見える形で入れる。
    /// `reset()` はこの初期値に戻し、`hasDraft` はこれと同じ間は書きかけに数えない
    private(set) var startsPrivate = false
    /// 最初の写真（旅の写真）をもう入れたか。**一度だけ入れる**——`onAppear` は戻るたびに
    /// 呼ばれるので、印が無いと同じ写真が足される。`reset()` でも下ろさない
    /// （入れ直すと、上げたばかりの写真がもう一度並ぶ）
    private var appliedInitialPhotos = false
    /// 旅の写真の流れから来た投稿か（最初の写真を受けた）。束の印に `UploadGrouping.tripPrefix`
    /// を付ける——旅の記録の一冊になるのはこの束だけ。`reset()` でも下ろさない（同じ画面の続き）。
    /// **いつも1つの投稿にまとめる**（`groupsForSubmit`）。
    /// 写真を全部入れ替えても `trip-` が付くのは、画面が旅の流れのままなので意図どおり（2026-10-02 判断）
    private(set) var fromTripImport = false

    /// 送るときに束ねるか。**旅の流れではいつも束ねる**（「それぞれ別の投稿」にすると groupId が
    /// 付かず、非公開で始まった写真がどこの棚にも出なかった）
    var groupsForSubmit: Bool { fromTripImport || groupsAsOnePost }

    /// 公開範囲の初期値（`startsPrivate` の裏返し）
    var initialPublished: Bool { !startsPrivate }

    /// 旅の写真からまとめて来たときの初期値を入れる（画面が出たとき・一度だけ）。
    /// 2枚以上なら「1つの投稿にまとめる」にする（同じ旅の写真なので）。
    ///
    /// 写真は**整えてあるもの**（`LibraryTripPickView` が読みながら1枚ずつ `ImagePreparer` に通した。
    /// EXIF・GPS は落ちていて、撮影日と約1kmに丸めた座標を持つ）。**並びは渡した順のまま**
    func applyInitialPhotos(_ photos: [ImagePreparer.Prepared], startPrivate: Bool) {
        guard !appliedInitialPhotos else { return }
        appliedInitialPhotos = true
        startsPrivate = startPrivate
        if startPrivate { published = false }
        guard !photos.isEmpty else { return }
        fromTripImport = true
        if photos.count > 1 { groupsAsOnePost = true }
        for prepared in photos { append(prepared) }
    }

    /// カテゴリ。**決まった選択肢から選ぶ**（`CategoryChoices`）
    @Published var category = ""
    @Published var published = true
    /// 公開範囲。**`published` が false のときは意味を持たない**
    /// （非公開は誰にも見えないので、絞りようが無い）。
    /// 送るのは `audienceToSend` 経由——画面が「公開」に戻すのを忘れても、
    /// 非公開の行に絞りの印が付かないようにする。
    @Published var audience: Audience = .everyone

    /// サーバーへ送る公開範囲。**非公開なら送らない。**
    var audienceToSend: Audience { published ? audience : .everyone }

    /// 🔴 **鍵を控えている写真（本体は置けたが保存が通ったか分からない）が1枚でもある間は、
    /// 公開範囲を変えさせない。**
    ///
    /// やり直しは前回の鍵で保存する（`UploadService.stage` の注記）。前回の保存が実は通っていて
    /// （応答だけ失われた）、今回の公開範囲が違うと、サーバーは画像の置き場が食い違うので
    /// 「保存済み」の 409 で断る（`upload.ts`）。以前はそこで行き詰まり、押し直しても 409 が続いた。
    /// 下書き↔公開も同じ行で選ぶので、まとめて止める（非公開にすると送る公開範囲も変わる）。
    /// その写真を外せば（`remove`）鍵も片付くが、**外すことは勧めない**——前の保存が通っていたら、
    /// 選び直して上げると同じ写真が2枚になる。勧めるのは「もう一度投稿する」
    /// （届いていれば同じ鍵の保存が通るか、「保存済み」の 409 で投稿済みとして外れる）
    var visibilityLocked: Bool { items.contains { staged[$0.id] != nil } }

    /// 公開範囲を変えられない理由（短い一言）。変えられるときは nil
    var visibilityLockReason: String? {
        visibilityLocked
            ? L("前の送信が届いている可能性があるため、公開範囲は変えられません。まず「投稿する」をもう一度押してください（届いていれば投稿済みになります）。何度押しても投稿できないときは、その写真を外してください",
                "Your last attempt may have gone through, so visibility can't be changed. Tap Post again first (if it went through, it will show as posted). If it keeps failing, remove that photo.")
            : nil
    }

    /// 公開範囲を選ぶ（画面の行から）。**錠が掛かっている・送っている間は何もしない**——ボタンの
    /// `.disabled` は次の描画まで効かない。送信は1枚ごとにその時点の値を読むので、送っている間に
    /// 変わると同じ束で割れる。`audience` が nil なら公開範囲は今のまま（非公開を選んだ）
    func chooseVisibility(published: Bool, audience: Audience?) {
        guard !visibilityLocked, !isWorking else { return }
        self.published = published
        if let audience { self.audience = audience }
    }
    /// 選んだ写真を**1つの投稿としてまとめる**か（モック8）。
    ///
    /// **行は1枚ずつのまま。** まとめても個別ページとサイトマップは
    /// 変わらない——写真1枚＝1ページがこのサイトの検索での面積なので、
    /// 1行にまとめると出せるページが減る。束ねるのは見せ方だけ。
    ///
    /// 既定は**まとめない**（今までと同じ）。2枚以上選んだときだけ選べる
    @Published var groupsAsOnePost = false

    /// この回の束の印。**送り始めるときに1つだけ作る**
    private(set) var groupId: String?
    /// 何回目の選択か。選び直した後に、前の読み込みの結果を混ぜないための目印
    private var pickGeneration = 0

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumId: String?
    /// 選んだアルバムに入れなくなった（持ち主が消した・外された）。画面が端末の控え
    /// （`JoinedAlbumsStore`）から外す。外さないと行き先に残り続け、選ぶたびに全部落ちる
    var onAlbumGone: ((String) -> Void)?
    /// 保存が通った1枚（保存の応答の行）。下の「投稿」から開いた画面が `TabRouter` に渡し、
    /// マイページ・ホームが読み直しを待たずに先に並べる（`PostedPhotos`・2026-10-03）
    var onSaved: ((Photo) -> Void)?
    /// 送信中。**読み込み中とは分ける**——一緒にすると、写真を選んでいる
    /// 間に「送信中… 0 / 2 枚目」と「残りをやめる」が出る
    @Published private(set) var isWorking = false
    @Published private(set) var isLoadingPicked = false
    /// カメラで撮った写真を整えている枚数。**整え終わるまで投稿させない**
    /// （押すと、撮った1枚だけが待ち行列に入る前に送信が始まり、画面に残る）
    @Published private(set) var preparingCaptures = 0
    /// 一度でも投稿できたか。**閉じる合図に使う**（待ち行列が空になった
    /// だけでは閉じない——選び直しの読み込み中も空になる）
    @Published private(set) var didPostAll = false
    /// 投稿したら SNS にも載せるか（`ThreadsShare`）。**端末に覚える**——毎回入れ直させない
    @Published var shareToThreads = UserDefaults.standard.bool(forKey: ThreadsShare.defaultsKey) {
        didSet { UserDefaults.standard.set(shareToThreads, forKey: ThreadsShare.defaultsKey) }
    }
    /// 共有の画面に渡すもの。**全部上がった回だけ**、`didPostAll` より先に立てる
    /// （画面は立っていれば閉じる代わりに共有の画面を出し、それを閉じてから閉じる）
    @Published var threadsBundle: ThreadsShare.Bundle?
    /// 上がった写真のうち外へ渡してよいもの（公開・全体に公開）。やり直しをまたいで貯め、
    /// 全部上がったときに `threadsBundle` にする
    private var sharable: [(data: Data, photoId: String, title: String, description: String, location: String)] = []

    /// スポットのページに並ぶ形で上がった枚数（`spotId` 付き・公開・全体に公開）。
    /// スポットの画面が「投稿しました」を出すかを決める（並ばない投稿で言い切らない）
    @Published private(set) var postedToSpot = 0
    /// 編集した写真を書き出している間の進み（送り始める前・`exportAllEdited`）。書き出していなければ nil
    @Published private(set) var exportProgress: UploadEditRules.ExportProgress?
    /// 何枚目を上げているか（`0` は上げていない）。画面の「3 / 5 枚目」に使う
    @Published private(set) var uploadingIndex = 0
    @Published var errorMessage: String?

    private let uploads: UploadService
    private let albumService: AlbumService
    private let photoService: PhotoService
    private let discovery: DiscoveryService
    /// 引いている最中の地名の問い合わせ。写真を選び直したら捨てる
    private var placeTasks: [UUID: Task<Void, Never>] = [:]
    /// 途中でやめた。**残りを上げ始めない**
    private var cancelled = false
    /// 読み込み中の仕事。**選び直しが重ならないように、前のを捨てる**
    private var loadTask: Task<Void, Never>?
    /// 読めなかったライブラリの写真の印。**それだけでは読み直さない**——
    /// 新しく選び足したときに一緒に読み直す（`loadPicked` の注記）
    private var unreadable: Set<PhotosPickerItem> = []
    /// 前の送信で曲を付けられなかった枚数で、**まだ知らせに出ているもの**。
    /// 撮った写真が整って知らせを言い直すときに引き継ぐ（`UploadSummary.afterCapture`）
    /// ——その写真はもう並びに居ないので、消すと二度と伝わらない
    private var songFailuresShown = 0
    /// `pickerItems` を中から直している最中（`setSelectionQuietly`）
    private var isSettingSelectionQuietly = false
    /// 本体まで置けて、保存がまだ通っていない写真（`UploadService.stage` の注記）
    private let staged = StagedUploads()
    /// 控えた鍵を置いたときの編集と、置いた絵の代表色（`UploadEditRules.reusesStaged`）。
    /// 鍵と同じ時に書き、同じ時に消す。やり直しは書き出し直さないので、代表色もここから送る
    private var stagedEdits: [UUID: (recipe: PhotoRecipe, dominantColor: String?)] = [:]
    /// 帯のサムネの編集後を描いている仕事（写真ごと。編集し直したら前のを捨てる）
    private var stripRenders: [UUID: Task<Void, Never>] = [:]
    /// ライブラリの写真を読む口。**試験でだけ差し替える**——シミュレータでは
    /// 本物の写真ライブラリに問い合わせるので、「読めなかった」回を決まった形で作れない
    var loadPickedData: (PhotosPickerItem) async throws -> Data? = { item in
        try await item.loadTransferable(type: Data.self)
    }

    /// ライブラリの写真1枚を読むのを待つ上限（秒）。過ぎたら「読めなかった」に回す（`AsyncTimeout.firstWithin`）。
    ///
    /// 🔴 **2026-10-03 判断: 60秒。** iCloud にしか無い写真は落としてくるので数十秒かかることがあり、
    /// 短いと読める写真まで落とす。いっぽう上限が無いと、返らない1枚のために「読み込み中」が解けず、
    /// 読めた写真まで投稿できないままだった（`canSubmit` は読み込み中は押させない）。
    /// 過ぎた写真は「もう一度読み込む」（`retryUnreadable`）で読み直せる。試験でだけ短くする
    var pickedLoadTimeout: TimeInterval = 60

    /// 画像を整える口（`ImagePreparer.prepare`）。**試験でだけ差し替える**——模型の ImageIO は
    /// 画像を読めないので、整った1枚を決まった形で作る。**画面の処理の外から呼ばれる**
    ///
    /// 既定は**一覧用の 512px も作る**（`withThumbnail: true`・保存の `thumbUrl` になる）
    var prepareData: @Sendable (Data) throws -> ImagePreparer.Prepared = { data in
        try ImagePreparer.prepare(data: data, fileName: "photo", withThumbnail: true)
    }

    /// 編集の元（原本）を一時ファイルに残す口（`PhotoEditSources.write`）。**画面の処理の外から呼ばれる。**
    /// 試験でだけ差し替える
    var keepEditSource: @Sendable (Data) -> URL? = { data in PhotoEditSources.write(data) }

    /// 編集した写真を、送る本体に書き出す口（`PhotoRenderer.exportPrepared`）。**画面の処理の外から呼ばれる。**
    /// 試験でだけ差し替える（模型の Core Image は描けない）
    var exportEdited: @Sendable (Data, PhotoRecipe, ImagePreparer.Prepared) throws -> ImagePreparer.Prepared = {
        source, recipe, base in
        try PhotoRenderer.shared.exportPrepared(source: source, recipe: recipe, base: base)
    }

    /// SNS に渡す絵に透かしを入れる口（`WatermarkRenderer.apply`）。**画面の処理の外から呼ばれる。**
    /// 試験でだけ差し替える（模型では描けない）
    var watermark: @Sendable (Data) -> Data? = { WatermarkRenderer.apply($0) }

    /// 帯のサムネの編集後を描く口。**画面の処理の外から呼ばれる。** 試験でだけ差し替える
    var renderStripPreview: @Sendable (Data, PhotoRecipe) -> UIImage? = { data, recipe in
        PhotoRenderer.shared.render(data: data, recipe: recipe, maxPixelSize: StripThumb.maxPixelSize)
            .map { UIImage(cgImage: $0) }
    }

    /// 帯のサムネ（無編集の絵）を作る口（`StripThumb.make`）。**画面の処理の外から呼ばれる。**
    /// 受け取るのは `StripThumb.source` が選んだデータ。試験でだけ差し替える
    var makeStripThumb: @Sendable (Data) -> UIImage? = { data in
        StripThumb.make(from: data).map { UIImage(cgImage: $0) }
    }

    init(uploads: UploadService, albums: AlbumService, photos: PhotoService, discovery: DiscoveryService) {
        self.uploads = uploads
        self.albumService = albums
        self.photoService = photos
        self.discovery = discovery
    }

    /// **閉じたら、保存しなかった本体を片付ける。** 保存の失敗では片付けない
    /// （やり直しで同じ鍵を使う）ので、諦めて閉じた分はここで消す。
    /// 保存が実は通っていた鍵は、ふつうはサーバーが消さない（`discardUpload`）。
    /// ただし行の書き込みが遅れている間（API Gateway の 29 秒で切れたあとも
    /// Lambda は続く・利用者の索引は結果整合）は消えうる——窓は、保存の失敗の
    /// たびに消していた以前より狭い。塞ぐならサーバー側（確かめていない）
    deinit {
        editSources.removeAll()
        let keys = staged.removeAll()
        guard !keys.isEmpty else { return }
        let uploads = self.uploads
        Task {
            for key in keys { await uploads.discard(key: key) }
        }
    }

    /// アルバムは無いことの方が多い。**取れなくても投稿は止めない。**
    ///
    /// **参加しているアルバムも行き先に出す。** `GET /albums` は自分が
    /// 作ったものしか返さない（`albums.ts`）ので、端末が覚えている分
    /// （`JoinedAlbumsStore`）を足す。足さないと、招待された人は
    /// **そのアルバムに1枚も投稿できない**——サーバーは会員なら受け付ける
    /// （`upload.ts` の `isAlbumMember`）のに、選ぶ口が無いだけだった。
    func loadAlbums(joined: [JoinedAlbumsStore.Entry] = []) async {
        let mine = (try? await albumService.list()) ?? []
        let mineIds = Set(mine.map(\.id))
        let extra = joined
            .filter { !mineIds.contains($0.id) }
            .map { Album(id: $0.id, title: $0.title, createdAt: nil,
                         memberCount: nil, inviteToken: nil, inviteExpiresAt: nil) }
        albums = mine + extra
    }

    /// 最初から入れたタグ（今日のテーマの「参加する」）。**本人が書いたものではない**ので、
    /// これと同じ間は書きかけに数えない（`hasDraft`）
    var initialTagsText = ""

    /// 閉じると消える書きかけがあるか。
    ///
    /// - **写真を選び始めたら**（読み込み中・カメラの準備中を含む。題・説明・撮影地は写真ごと）
    /// - 写真の前でも入れられる欄（タグ・曲・アルバム・公開範囲・カテゴリ）を**変えたら**。
    ///   写真ばかり見ていたので、写真を選ぶ前に入れたこれらが確認なしで消えていた（48b2481 のレビュー）
    /// 最初から入っているタグ・スポットの紐付けは本人が書いたものではないので数えない
    var hasDraft: Bool {
        !items.isEmpty || isLoadingPicked || preparingCaptures > 0
            // 公開範囲は初期値と比べる（旅の写真から来たときは非公開で始まる。
            // 投稿し終えて片付けた画面を「書きかけ」にしない）
            || song != nil || selectedAlbumId != nil || published != initialPublished || audience != .everyone
            || !category.isEmpty
            // タグは**中身で**比べる（候補を足して外すと末尾に「, 」が残り、同じ中身が書きかけに見えた）
            || TagInput.parse(tagsText) != TagInput.parse(initialTagsText)
    }

    /// **読み込み中は押させない。** 読めたぶんだけが上がり、残りは黙って画面に残っていた
    ///
    /// 2026-10-03 判断: 読み込みの上限時間（`pickedLoadTimeout`）が過ぎた写真は「読めなかった」に回し、
    /// **読めた分だけで押せる**ようにする（ここは変えない）。この注記が防いでいるのは「読み込みの最中に
    /// 押して、残りが黙って画面に残る」ことで、時間切れの後は読み込みは終わっている。読めなかった枚数は
    /// 知らせ（`errorMessage`）に出し、「もう一度読み込む」（`retryUnreadable`）を添えるので黙って減らない。
    /// `loadPicked` の「1枚でも読めたら、読めたぶんは受ける」とも同じ考え
    var canSubmit: Bool { !items.isEmpty && !isWorking && !isLoadingPicked && preparingCaptures == 0 }

    /// 写真の座標から撮影地を引いて、**空のときだけ**入れる。
    ///
    /// **なぜ埋めるか。** 撮影地 → 地図 → `/location/<スラッグ>` → 検索流入 が
    /// このサイトの価値で（CLAUDE.md）、実データでは 30枚中13枚が空だった。
    /// 手で打つ人は少ない。Web は 2026-08 からこれを埋めている。
    ///
    /// **5秒で諦める。** Web 側の `REVERSE_GEOCODE_TIMEOUT_MS` と同じ。
    /// 遅れて届いた地名が**打っている最中に割り込む**のを止める。
    func fillPlaceName(for photoId: UUID, lat: Double, lng: Double) async {
        // 引く前に一度（打ってあるなら、そもそも引かない）
        guard let start = items.firstIndex(where: { $0.id == photoId }),
              PlaceFill.value(current: items[start].location, found: "-") != nil else { return }
        let found = await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask { [discovery] in try? await discovery.placeName(lat: lat, lng: lng) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard !Task.isCancelled else { return }
        // **待っている間に打ち始めていたら、入れない。** 書きかけを奪わない。
        // 並びが変わっていることもあるので、番号ではなく id で引き直す
        guard let index = items.firstIndex(where: { $0.id == photoId }),
              let next = PlaceFill.value(current: items[index].location, found: found) else { return }
        items[index].location = next
    }

    /// カメラで撮った1枚を受ける。
    ///
    /// **`UIImage` を経由した時点で EXIF は残っていない**（撮影地も
    /// 機材名も付かない）。それでも `ImagePreparer` を通すのは、
    /// 1920px への縮小と「残っていないことの確認」を1か所に寄せるため。
    ///
    /// 🔴 **JPEG にするのも画面の処理の外で**（`CameraCapture` の注記）。撮影日・機種は
    /// カメラが付けた撮影情報から付け直す（無ければ撮った時刻・`ImagePreparer.applyingCaptureInfo`）
    func accept(capture: CameraCapture) {
        preparingCaptures += 1
        let prepare = prepareData
        Task { [weak self] in
            let keep = self?.keepEditSource
            let result: Result<(ImagePreparer.Prepared, URL?), Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    guard let data = capture.jpegData() else { throw ImagePreparer.PrepareError.unreadable }
                    let prepared = try prepare(data)
                    // 編集の元は撮った JPEG（撮影情報は持たない。`prepared` は付け直したもの）
                    return (ImagePreparer.applyingCaptureInfo(prepared, metadata: capture.metadata,
                                                              capturedAt: capture.capturedAt),
                            keep?(data))
                }
            }.value
            guard let self else {
                // 画面が先に閉じた。残した元は誰も消さないので、ここで消す
                if case .success(let (_, url)) = result, let url { try? FileManager.default.removeItem(at: url) }
                return
            }
            self.preparingCaptures -= 1
            switch result {
            case .success(let (prepared, source)):
                self.append(prepared, editSource: source)
                // **読めなかったライブラリの写真が選ばれたままなら、それを言い直す。**
                // ただ消すと、その写真が抜けていることが二度と出ない（写真を外しても
                // 読み直さない）。前の知らせを残すと、撮り直しで直ったカメラの失敗や
                // 「全部読めなかった」の文言が、今の状態と合わないまま残る
                self.errorMessage = UploadSummary.afterCapture(unreadable: self.unreadable.count,
                                                               songFailures: self.songFailuresShown)
            case .failure(let error):
                self.songFailuresShown = 0
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? L("写真を読み込めませんでした", "Couldn't load the photo")
            }
        }
    }

    /// 🔴 **画像を整えるのは画面の処理（MainActor）の外で。** 縮小・JPEG への
    /// 焼き直し・読み直しての確認・代表色で、1枚に数百ミリ秒かかる。10枚選ぶと
    /// その間ずっと画面が止まっていた
    ///
    /// 編集の元（原本）の一時ファイルも同じ所で書く（`keepEditSource`）。整えられなかった写真は残さない
    private static func prepareOffMain(
        _ data: Data, with prepare: @escaping @Sendable (Data) throws -> ImagePreparer.Prepared,
        keep: @escaping @Sendable (Data) -> URL?
    ) async -> Result<(ImagePreparer.Prepared, URL?), Error> {
        await Task.detached(priority: .userInitiated) {
            Result { (try prepare(data), keep(data)) }
        }.value
    }

    // MARK: - 写真の編集（Phase 2・2026-10-02）

    /// この写真の編集画面を開けない理由。開けるなら nil（`UploadEditRules.canEdit`）
    func editLockReason(for photoId: UUID) -> String? {
        UploadEditRules.canEdit(isStaged: staged[photoId] != nil, isWorking: isWorking)
            ? nil : UploadEditRules.editLockMessage
    }

    /// 編集画面の「完了」。**その写真だけ**にレシピを入れ、帯のサムネの編集後を描き直す。
    /// 開けない写真（`editLockReason`）・もう並びに居ない写真には何もしない（false）。
    /// 画面の `.disabled` は次の描画まで効かないので、ここでも確かめる
    @discardableResult
    func applyEdit(_ photoId: UUID, recipe: PhotoRecipe) -> Bool {
        guard editLockReason(for: photoId) == nil,
              let index = items.firstIndex(where: { $0.id == photoId }) else { return false }
        let next = recipe.sanitized
        guard items[index].recipe != next else { return true }
        items[index].recipe = next
        items[index].editedPreview = nil
        stripRenders[photoId]?.cancel()
        stripRenders[photoId] = nil
        // 無編集に戻した写真は元の `preview` を出す（描かない）
        guard !next.isIdentity else { return true }
        let read = items[index].editSourceReader
        let render = renderStripPreview
        stripRenders[photoId] = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                render(read(), next)
            }.value
            guard !Task.isCancelled, let self,
                  let i = self.items.firstIndex(where: { $0.id == photoId }),
                  // 描いている間に編集し直されたら、この絵は捨てる
                  self.items[i].recipe == next else { return }
            self.items[i].editedPreview = image.map { Image(uiImage: $0) }
            self.stripRenders[photoId] = nil
        }
        return true
    }

    /// 送る1枚。**編集してあれば元から書き出したもの**（`UploadEditRules.needsExport`）、
    /// 無編集なら整えた `prepared` のまま。書き出しは画面の処理の外で
    private func preparedToSend(_ item: PendingPhoto) async throws -> ImagePreparer.Prepared {
        guard UploadEditRules.needsExport(item.recipe) else { return item.prepared }
        let export = exportEdited
        let read = item.editSourceReader
        let recipe = item.recipe
        let base = item.prepared
        do {
            return try await Task.detached(priority: .userInitiated) {
                try export(read(), recipe, base)
            }.value
        } catch {
            // 書き出しが毎回落ちる写真もありうる。抜け道（編集をやめれば元の写真で送れる）を添える
            throw EditExportFailed(message: UploadEditRules.exportFailureMessage(
                (error as? LocalizedError)?.errorDescription))
        }
    }

    /// 送る前に書き出した1枚（写真ごと）。書き出したときのレシピを添える（送るときに違えば使わない）
    private struct Exported {
        let recipe: PhotoRecipe
        let result: Result<ImagePreparer.Prepared, Error>
    }

    /// 🔴 **編集した写真を、送り始める前（まだ前面にいるうち）に全部書き出す**（2026-10-03）。
    ///
    /// 以前は1枚ごとに「書き出す → 置く → 保存」を繰り返していた。投稿を押してすぐ裏に回ると、
    /// 2枚目以降の書き出し（Core Image・GPU）が裏で走り、裏では GPU を使えない・編集の元の一時ファイルが
    /// ロックで読めない（`PhotoEditSources.fileProtection`）で落ちていた。書き出しは前面にいるうちに済ませ、
    /// 裏に回ってからは通信だけにする（`BackgroundWindow` の窓は通信の分）。
    ///
    /// - **1枚ずつ順に**書き出す（並べるとメモリが原本の数だけ膨らむ）。持つのは結果だけ
    ///   （1枚 1920px の JPEG・数百 KB〜1MB 程度。10枚まで）
    /// - 書き出せなかった写真は結果に失敗を持たせ、**その写真だけ**送らずに残す（今までと同じ）
    /// - 控えた鍵を使い回す写真（`reusesStaged`）は置く絵が要らない。SNS に載せる回だけ共有の絵として書き出す
    ///
    /// 書き出しの間は「書き出し中 n/N」を出す（`exportProgress`。「0/N」のまま止まって見えた）。
    /// 失うもの: 最初の1枚が上がり始めるまでの時間が、編集した枚数ぶんの書き出しだけ延びる（2026-10-03 判断）
    private func exportAllEdited(_ queue: [UUID]) async -> [UUID: Exported] {
        var out: [UUID: Exported] = [:]
        let sharing = shareToThreads && ThreadsShare.isEligible(published: published, audience: audienceToSend)
        // 書き出す写真を先に決める（「n/N」の N）
        let targets = items.filter { item in
            guard queue.contains(item.id), UploadEditRules.needsExport(item.recipe) else { return false }
            let reuses = staged[item.id] != nil
                && UploadEditRules.reusesStaged(stagedWith: stagedEdits[item.id]?.recipe, current: item.recipe)
            return !reuses || sharing
        }.map(\.id)
        defer { exportProgress = nil }
        for (offset, id) in targets.enumerated() {
            if cancelled { break }
            guard let item = items.first(where: { $0.id == id }) else { continue }
            exportProgress = UploadEditRules.ExportProgress(index: offset + 1, total: targets.count)
            do {
                out[id] = Exported(recipe: item.recipe, result: .success(try await preparedToSend(item)))
            } catch {
                out[id] = Exported(recipe: item.recipe, result: .failure(error))
            }
        }
        return out
    }

    /// 置く本体。先に書き出した結果を使う（レシピが同じとき）。無ければここで書き出す
    /// （書き出してから送るまでに編集が変わった。編集の錠があるのでふつうは起きない）
    private func bodyToSend(_ item: PendingPhoto, exported: Exported?) async throws -> ImagePreparer.Prepared {
        guard UploadEditRules.needsExport(item.recipe) else { return item.prepared }
        if let exported, exported.recipe == item.recipe { return try exported.result.get() }
        return try await preparedToSend(item)
    }

    /// 編集した写真を書き出せなかった（知らせの文は `UploadEditRules.exportFailureMessage`）
    private struct EditExportFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func remove(_ photoId: UUID) {
        // 送っている間は外さない（ボタンの `.disabled` は次の描画まで効かない）。
        // 保存の最中に本体を片付けると、通った行の画像が割れる
        guard !isWorking else { return }
        placeTasks[photoId]?.cancel()
        placeTasks[photoId] = nil
        stripRenders[photoId]?.cancel()
        stripRenders[photoId] = nil
        discardStaged(photoId)
        let removed = items.first { $0.id == photoId }
        items.removeAll { $0.id == photoId }
        // **ライブラリの選択からも外す。** 残すと、次に「追加」を開いたときに
        // 選ばれたままで、閉じると外したはずの写真が戻ってくる
        if let key = removed?.pickerItem {
            // **ここは読み直しを通す**（`setSelectionQuietly` にしない）。
            // 走り出す前の読み込みの取り消しを didSet に任せている。読めなかった
            // 写真は読み直さない（`unreadable`）ので、知らせは消えない
            pickerItems.removeAll { $0 == key }
        }
        // **最後の1枚を外したら束の印も捨てる。** カメラの分（印なし）は上の
        // 読み直しを通らないので、ここで捨てないと次に撮った写真が前の投稿の束に入る
        if items.isEmpty { groupId = nil }
    }

    /// 選ばれた写真を読み、**その場で EXIF を落とす**。
    /// 落とせなかったら受け付けない（`ImagePreparer` の関所）。
    ///
    /// **1枚でも読めたら、読めたぶんは受ける。** 全部捨てると、
    /// 1枚の壊れた写真のために選び直しになる（Web も落ちた枚数だけ伝える）。
    ///
    /// `retryingUnreadable`: 「もう一度読み込む」（`retryUnreadable`）から。選び足していなくても
    /// 読めなかった写真を読み直す
    private func loadPicked(_ picked: [PhotosPickerItem], retryingUnreadable: Bool = false) async {
        // 走り出す前に取り消された回は、古い選択で一覧を削らない
        guard !Task.isCancelled else { return }
        // **選び直しは差分で。** 外した分だけ落とし、足した分だけ読む。
        // 以前は丸ごと入れ替えていて、「追加」を押すと打った題やカメラで撮った
        // 分まで消えていた（2026-09-26 のレビュー）
        let diff = PickerReconcile.reconcile(existing: items.map(\.pickerItem), picked: picked)
        // 🔴 **本当に選び足したときだけ読む。** 読めなかった写真の扱いは `toLoad` の注記
        let plan = PickerReconcile.toLoad(added: diff.added, picked: picked, unreadable: unreadable,
                                          retry: retryingUnreadable)
        unreadable = plan.unreadable
        let added = plan.load
        let dropped = zip(items, diff.keep).filter { !$0.1 }.map { $0.0.id }
        for id in dropped {
            placeTasks[id]?.cancel()
            placeTasks[id] = nil
            discardStaged(id)
        }
        items.removeAll { dropped.contains($0.id) }
        // **束の印を捨てるのは、前の写真が1枚も残らないときだけ。** 「追加」は
        // 前の写真を残すので、押し直しで公開済みの分と同じ投稿に入るべき
        // （印を捨てると、途中まで上がった投稿が2つに割れる）
        if items.isEmpty { groupId = nil }
        guard !added.isEmpty else { return }

        // 🔴 **選び直しの競合。** 前の読み込みは取り消されても `await` から戻ってくる。
        // 戻った先で確かめずに足すと、選び直した一覧に外したはずの写真が混ざり、
        // 前の読み込みの後片付けが「読み込み中」を早く消していた
        pickGeneration += 1
        let generation = pickGeneration
        isLoadingPicked = true
        errorMessage = nil
        songFailuresShown = 0
        didPostAll = false
        defer { if generation == pickGeneration { isLoadingPicked = false } }

        var failedItems: [PhotosPickerItem] = []
        let load = loadPickedData
        for item in added {
            if Task.isCancelled { return }
            do {
                // **1枚ごとに上限時間を設ける**（`pickedLoadTimeout` の注記）。過ぎた・読めなかった写真は
                // 「読めなかった」に回し、読めた写真だけで投稿できるようにする
                // 待つのは `firstWithin`（取り消しに応えない読み込みでも時間切れが効く）
                let outcome = await AsyncTimeout.firstWithin(seconds: pickedLoadTimeout) {
                    () async -> Result<Data?, Error>? in
                    do { return .success(try await load(item)) } catch { return .failure(error) }
                }
                // 選び直し・画面を閉じた
                if Task.isCancelled { return }
                // nil は時間切れ
                guard let data = try outcome?.get() else {
                    failedItems.append(item)
                    continue
                }
                // 読んでいる間に選び直されたら、この結果は捨てる
                guard !Task.isCancelled, generation == pickGeneration else { return }
                // **`itemIdentifier` をファイル名にしない。** スラッシュを含む
                // 端末内部の ID で、キーの組み立てを壊す。拡張子は
                // `ImagePreparer` が .jpg に付け替える。整えるのは画面の処理の外で
                let result = await Self.prepareOffMain(data, with: prepareData, keep: keepEditSource)
                // 整えている間に選び直されたら、この結果は捨てる（残した元の一時ファイルも）
                guard !Task.isCancelled, generation == pickGeneration else {
                    if case .success(let (_, url)) = result, let url { try? FileManager.default.removeItem(at: url) }
                    return
                }
                switch result {
                case .success(let (prepared, source)):
                    append(prepared, pickerItem: item, editSource: source)
                case .failure:
                    failedItems.append(item)
                }
            } catch {
                failedItems.append(item)
            }
        }

        // 取り消された回の「読めなかった」は嘘になる（新しい回が読み直している）
        guard !Task.isCancelled, generation == pickGeneration else { return }
        // 覚えるのは最後まで走った回の失敗だけ（取り消しで落ちた分は読めないのではない）
        unreadable.formUnion(failedItems)
        let failed = failedItems.count
        if failed > 0 {
            // **黙って減らさない。** 「なぜか1枚少ない」まま公開させない
            errorMessage = items.isEmpty
                ? L("写真を読み込めませんでした", "Couldn't load the photos")
                : L("\(failed) 枚は読み込めませんでした", "\(failed) photo(s) couldn't be loaded")
        }
    }

    /// 読めなかったライブラリの写真があるか（画面が「もう一度読み込む」を出す）。
    /// 読み込み中・送信中は出さない
    var canRetryUnreadable: Bool { !unreadable.isEmpty && !isLoadingPicked && !isWorking }

    /// 読めなかった写真（時間切れ・iCloud から落とせなかった）を**もう一度読む**（2026-10-03）。
    ///
    /// 今までは選び足したときに一緒に読み直すだけで（`PickerReconcile.toLoad` の注記）、
    /// 読めなかった写真を読み直す口が画面に無かった。読めた写真・打った題はそのまま残る
    func retryUnreadable() {
        guard canRetryUnreadable else { return }
        loadTask?.cancel()
        let picked = pickerItems
        loadTask = Task { [weak self] in await self?.loadPicked(picked, retryingUnreadable: true) }
    }

    /// 1枚を待ち行列に足し、撮影地を引き始める。試験から呼ぶので private にしない
    func append(_ prepared: ImagePreparer.Prepared, pickerItem: PhotosPickerItem? = nil, editSource: URL? = nil) {
        var photo = PendingPhoto(prepared: prepared)
        photo.pickerItem = pickerItem
        photo.editSource = editSource
        // 帯のサムネは**画面の処理の外で小さく作る**（`StripThumb`）。届くまでは地の色
        startStripThumb(for: photo.id, prepared: prepared)
        // **スポットから開いたときは、撮影地をそのスポットにする**（座標から引き直さない）。
        // ただし**写真の位置がスポットから遠い写真は普通の投稿**（別の旅の写真を混ぜて選んだ）。
        // 位置のある写真は写真の座標をそのまま送る（撮った場所の方が正しい）。
        // スポットの座標を使うのは位置の無い写真だけ
        if let spot, spot.covers(prepared) {
            // 位置の無い写真の座標は送るときに決める（`coordsToSend(spot:)`）
            photo.location = spot.name
            items.append(photo)
            return
        }
        items.append(photo)
        // **撮影地を、写真の座標から先に埋めておく**（Web と同じ）。
        // **待たない**——待つと、引き終わるまで投稿ボタンが押せない
        guard let coords = prepared.coords else { return }
        let id = photo.id
        placeTasks[id] = Task { [weak self] in
            await self?.fillPlaceName(for: id, lat: coords.lat, lng: coords.lng)
        }
    }

    /// 上げるのをやめる。**いま上げている1枚は最後まで通す**
    /// （途中で切ると S3 に迷子が残る）。残りは始めない。
    func cancel() {
        cancelled = true
    }

    func submit() async {
        // 🔴 **二度押しで二重に出さない**（`StoryComposerView.post` と同じ穴）。
        // ボタンの `.disabled` は次の描画まで効かず、素早い2回押しで
        // `submit()` が2本走る
        // 読み込み中・整え中も止める（`canSubmit`）——ボタンの `.disabled` だけに頼らない
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        cancelled = false
        songFailuresShown = 0
        // 🔴 **送っている途中でアプリを離れても、少しのあいだ続けさせてもらう。**
        // 無いと裏に回った数秒後に止められ、戻ったときには通信が切れて失敗になる。
        // 時間切れ（30秒ほど）でも落ちた写真は画面に残り、やり直しは同じ鍵で送る
        let background = BackgroundWindow(name: "photo-upload")
        defer {
            isWorking = false
            uploadingIndex = 0
            background.end()
        }

        groupId = UploadGrouping.groupIdForSubmit(current: groupId, grouping: groupsForSubmit,
                                        count: items.count,
                                        make: { UploadGrouping.newGroupId(fromTrip: fromTripImport) })

        var done: [UUID] = []
        var failures: [String] = []
        /// 写真は上がったが曲を付けられなかった枚数。**成功に数えない**
        var songFailures = 0
        /// 前の送信の保存が通っていた（「保存済み」の 409）枚数。上がったものとして外し、知らせる
        var savedEarlier = 0
        /// 編集した写真を共有用に書き出せず、共有から外した枚数（`UploadOutcome.shareSkipped`）
        var shareSkipped = 0
        let queue = items.map(\.id)
        // 🔴 **編集した写真の書き出しは、最初の1枚を置く前に全部済ませる**（`exportAllEdited` の注記）
        let exported = await exportAllEdited(queue)
        for (offset, id) in queue.enumerated() {
            // **1枚ごとに見る。** 5枚選んで2枚目でやめたとき、残りを上げ始めない
            if cancelled { break }
            uploadingIndex = offset + 1
            // **送る直前に引き直す。** 送信中も欄は生きているので、
            // 始めたときの写しで送ると、直した題が古い値で上がる
            guard let item = items.first(where: { $0.id == id }) else { continue }
            do {
                let outcome = try await upload(item, exported: exported[item.id])
                if !outcome.songAttached { songFailures += 1 }
                if outcome.savedEarlier { savedEarlier += 1 }
                if outcome.shareSkipped { shareSkipped += 1 }
                done.append(item.id)
            } catch {
                // 🔴 **アルバムが無くなっていたら、そこで止めて行き先から外す。** 保存の 404 は
                // 会員でないとき（`upload.ts` の `isAlbumMember`）だけで、持ち主がアルバムを
                // 消すと会員の印も消える。残すと残りも同じ理由で全部落ち、押し直しても直らない
                // **外すのは送った宛先**（`AlbumGone` が持つ）。送信中も行き先は選び直せるので、
                // 今の `selectedAlbumId` を読むと、選び直した生きているアルバムを外していた
                if let gone = error as? AlbumGone {
                    albumGone(gone.albumId)
                    failures.append(L("選んだアルバムが見つかりませんでした。消された可能性があります。行き先を選び直してください",
                                      "The album you chose wasn't found. It may have been deleted. Choose another destination."))
                    break
                }
                failures.append((error as? LocalizedError)?.errorDescription
                                ?? L("投稿できませんでした", "Couldn't post"))
            }
        }

        // **上がったぶんだけ待ち行列から外す。** 残したままだと、やり直しで
        // 同じ写真をもう一度上げる（枚数の枠を食う）
        let postedKeys = items.filter { done.contains($0.id) }.map(\.pickerItem)
        items.removeAll { done.contains($0.id) }
        // 🔴 **ライブラリの選択からも外す。** 残すと、残った1枚を外す・「追加」で
        // 選び足す、のどちらでも選び直しの差分が投稿済みの写真を「新しく選ばれた」
        // と読み、**同じ写真をもう一度読み込んで上げる**（`remove` と同じ理由）
        let remaining = PickerReconcile.dropPosted(picked: pickerItems, posted: postedKeys)
        if remaining.count != pickerItems.count { setSelectionQuietly(remaining) }
        // **曲が付かなかった回は閉じない。** `didPostAll` を立てると
        // `UploadView` が即 `dismiss()` するので、警告が一度も描かれない
        if items.isEmpty && failures.isEmpty {
            // **曲が付かなかった回は閉じない。** `didPostAll` を立てると
            // `UploadView` が即 `dismiss()` するので、警告が一度も描かれない。
            // 前の公開範囲で投稿済みだった回も閉じない（その知らせを見せる）
            // 共有から外した写真がある回も閉じない（共有の画面は出さず、そのことを知らせる）
            if songFailures == 0 && savedEarlier == 0 && shareSkipped == 0 {
                // **いまの欄でも入切が見えているときだけ**（失敗のあと公開範囲を絞ってやり直すと、
                // 行が消えて入切が見えないまま共有の画面が開いた・6c6c42a7 のレビュー）。
                // 曲が付かなかった回は出さない（警告を共有の画面で覆い隠す）
                if shareToThreads, ThreadsShare.isEligible(published: published, audience: audience),
                   let lead = sharable.first {
                    // 透かしを入れる（`WatermarkRenderer`・重いので画面の処理の外で）。
                    // 束は `didPostAll` より先に立てる（画面は立っていれば閉じずに共有の画面を出す）
                    let raw = Array(sharable.prefix(ThreadsShare.maxImages).map(\.data))
                    let mark = watermark
                    let marked = await Task.detached(priority: .userInitiated) {
                        raw.compactMap { mark($0) }
                    }.value
                    // 1枚も用意できなければ共有の画面は出さず、投稿画面はそのまま閉じる（投稿自体は済んでいる）。
                    // 渡すのは `ImagePreparer` が作った JPEG なので、ここで全部失敗することは実際にはまず無い
                    if !marked.isEmpty { threadsBundle = ThreadsShare.Bundle(
                        images: marked,
                        // 最後に「Journey Photo」とその下に1枚目の写真の**短縮リンク**（owner 2026-10-02）。
                        // `/?p=<先頭8文字>` はトップが `/?photo=<id>` に置き換える。`/photo/<id>` は
                        // 再ビルドのあと（数分）まで無く、すぐ載せると Threads が 404 を読む（`PhotoLink`）
                        text: ThreadsShare.text(title: lead.title, description: lead.description,
                                                location: lead.location,
                                                url: PhotoLink.shortURL(photoId: lead.photoId)
                                                    ?? PhotoLink.url(photoId: lead.photoId, isPublished: false))) }
                }
                didPostAll = done.count > 0
            } else {
                errorMessage = UploadEditRules.withShareSkipped(UploadSummary.withSavedEarlier(
                    UploadSummary.message(done: done.count, failures: failures,
                                          cancelled: cancelled, songFailures: songFailures),
                    savedEarlier: savedEarlier), skipped: shareSkipped)
                songFailuresShown = songFailures
            }
            // **どちらにしても選択は捨てる。** 残すと `pickerItems` に
            // 投稿済みの写真が選ばれたまま残り、次に写真を選び直した瞬間に
            // `didSet` が走って**同じ写真がもう一度上がる**
            // （`errorMessage` は `reset()` では消えないので警告は残る）
            reset()
        } else {
            errorMessage = UploadEditRules.withShareSkipped(UploadSummary.withSavedEarlier(
                UploadSummary.message(done: done.count, failures: failures,
                                      cancelled: cancelled, songFailures: songFailures),
                savedEarlier: savedEarlier), skipped: shareSkipped)
            songFailuresShown = songFailures
        }
    }

    /// 送る下書き（題・説明・撮影地・タグ・行き先ほか）。**画面のいまの値から作る**——
    /// 送信中も欄は生きているので、保存の直前に呼び直す（`upload` の注記）
    private func makeDraft(for item: PendingPhoto) -> PhotoDraft {
        var draft = PhotoDraft()
        draft.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = item.caption
        draft.location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tags = TagInput.parse(tagsText)
        // **空なら送らない**（空文字は「カテゴリ無し」ではなく空の属性になる）
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        draft.published = published
        draft.audience = audienceToSend
        // **選んだ撮影地の座標を優先する。** 写真に残っていた位置より、
        // 本人が選んだ地名の方が正しい（丸めはどちらも約1km）
        draft.coords = item.coordsToSend(spot: spot)
        draft.date = item.prepared.takenOn
        draft.exif = item.prepared.exif
        // **読み込み中の地の色。** Web は前から送っていて、アプリだけ
        // 送っていなかった（同じ一覧でアプリの写真の枠だけ黒いまま残る）
        draft.dominantColor = item.prepared.dominantColor
        draft.albumId = selectedAlbumId
        draft.groupId = groupId
        draft.spotId = UploadSpotTarget.spotIdToSend(spot, for: item)
        return draft
    }

    /// 1枚の結末（写真は上がっている）
    private struct UploadOutcome {
        /// 曲まで含めて狙いどおりに終わったか。曲を付けられなかったときだけ `false`
        var songAttached = true
        /// 前の送信の保存が通っていた（「保存済み」の 409）。公開範囲は前に選んだもの
        var savedEarlier = false
        /// 編集した写真を共有用に書き出せず、共有に回さなかった（元の絵を黙って渡さない）
        var shareSkipped = false
    }

    /// - Returns: 写真は上がっている。曲・前の保存のことは `UploadOutcome`。
    ///   **ここで `errorMessage` に書かない**——呼び出し元が最後にまとめて出す
    ///   （途中で書くと、全部成功と見なされた `reset()` のあとに画面が閉じて消える）
    private func upload(_ item: PendingPhoto, exported: Exported? = nil) async throws -> UploadOutcome {
        var draft = makeDraft(for: item)

        // 🔴 **やり直しは前回の鍵で保存する**（`UploadService.stage` の注記）。
        // 保存が落ちた写真は本体を置き直さない——新しい鍵で送ると、前回の保存が
        // 実は通っていたときに同じ写真が2枚になる
        // 一覧用の 512px も同じ回で置く（`UploadService.stagePhoto`）。やり直しは前回のサムネも使い回す
        //
        // **編集した写真は、元から書き出した1枚を置く**（`preparedToSend`）。控えた鍵が別の編集の
        // 画像なら使わない（`UploadEditRules.reusesStaged`。編集の錠があるのでふつうは起きない）
        let placed: UploadService.Staged
        // 置いた本体。やり直し（前の鍵を使う）では書き出し直さない（共有に要るときだけ下で作る）
        var body: ImagePreparer.Prepared?
        if let already = staged[item.id],
           UploadEditRules.reusesStaged(stagedWith: stagedEdits[item.id]?.recipe, current: item.recipe) {
            placed = already
            if let edit = stagedEdits[item.id] { draft.dominantColor = edit.dominantColor }
        } else {
            discardStaged(item.id)
            // 編集した写真は送り始める前に書き出してある（`exportAllEdited`）
            let toSend = try await bodyToSend(item, exported: exported)
            body = toSend
            // 代表色は**置く絵から**（編集後。無編集なら整えたときの色のまま）。撮影情報は原本のまま
            draft.dominantColor = toSend.dominantColor
            placed = try await uploads.stagePhoto(toSend)
            staged[item.id] = placed
            stagedEdits[item.id] = (item.recipe, toSend.dominantColor)
        }
        // 🔴 **保存の直前に、いまの行から下書きを作り直す**（2026-10-03）。下書きは送り始めに
        // 作っていたので、画像を書き出して置くまで（数秒）の間に直した題・説明・撮影地は
        // **古い値のまま保存され、保存のあと行ごと消えて黙って失われた**。
        // 画像から決まる値（代表色）だけは置いた絵のものを引き継ぐ
        let placedColor = draft.dominantColor
        draft = makeDraft(for: items.first(where: { $0.id == item.id }) ?? item)
        draft.dominantColor = placedColor
        let photo: Photo?
        var outcome = UploadOutcome()
        do {
            photo = try await uploads.save(draft, presigned: placed.main, thumbUrl: placed.thumb?.publicUrl)
        } catch let error as APIError {
            // **保存の 404 だけ**が「アルバムが無い」。S3 への PUT の 404 は別の失敗
            if let albumId = draft.albumId, case .server(404, _) = error { throw AlbumGone(albumId: albumId) }
            // 🔴 **「保存済み」の 409 は、前の送信の保存が通っていた印。** 上がったものとして外す
            // （残すと押し直しても同じ鍵・同じ 409 で抜けられない・`visibilityLocked` の注記）。
            // 公開範囲は前に選んだもの——今回の値では無いので、共有・スポットの数には入れない
            guard case .server(409, let message) = error, UploadSummary.isSavedAlready(message) else { throw error }
            staged[item.id] = nil
            stagedEdits[item.id] = nil
            outcome.savedEarlier = true
            if let song {
                // 写真の ID が分からなければ曲は付けられない——付いたことにしない（知らせる側に倒す）
                if let id = placed.main.photoId {
                    var patch = PhotoPatch()
                    patch.song = song
                    do { try await photoService.update(photoId: id, patch: patch) } catch { outcome.songAttached = false }
                } else {
                    outcome.songAttached = false
                }
            }
            return outcome
        }
        staged[item.id] = nil
        stagedEdits[item.id] = nil
        if let photo { onSaved?(photo) }
        if let id = photo?.id, ThreadsShare.isEligible(published: draft.published, audience: draft.audience) {
            // 共有に渡すのも**置いた絵**（編集後）。やり直しで書き出していなければ、載せる設定のときだけ
            // ここで作る。🔴 **作れなければ共有に回さず知らせる**——編集前の絵を黙って渡さない
            // （投稿したのは編集後なので、SNS と見た目が割れる）
            if !UploadEditRules.needsExport(item.recipe) {
                sharable.append((item.prepared.data, id, draft.title, draft.description, draft.location))
            } else if let data = body?.data {
                sharable.append((data, id, draft.title, draft.description, draft.location))
            } else if shareToThreads {
                // やり直し（前の鍵を使う）でも、共有の絵は送り始める前に書き出してある（`exportAllEdited`）
                // （`if let … = try? await` を1行に書くと構文の検査の tree-sitter が読めない）
                let rebuilt = try? await bodyToSend(item, exported: exported)
                if let data = rebuilt?.data {
                    sharable.append((data, id, draft.title, draft.description, draft.location))
                } else {
                    outcome.shareSkipped = true
                }
            }
        }
        if photo != nil, draft.spotId != nil, draft.published, draft.audience == .everyone {
            postedToSpot += 1
        }
        // **曲は保存のあと。** `POST /upload/save` は song を受け取らない
        // ので、`PUT /photos/{id}` で付ける。ここが落ちても写真は
        // 上がっているので、投稿そのものは失敗にしない
        if let song, let id = photo?.id {
            var patch = PhotoPatch()
            patch.song = song
            do {
                try await photoService.update(photoId: id, patch: patch)
            } catch {
                outcome.songAttached = false
            }
        }
        return outcome
    }

    /// 保存がアルバムの 404 で断られた。`albumId` は**その保存で送った宛先**
    private struct AlbumGone: Error { let albumId: String }

    private func albumGone(_ albumId: String) {
        albums.removeAll { $0.id == albumId }
        if selectedAlbumId == albumId { selectedAlbumId = nil }
        onAlbumGone?(albumId)
    }

    /// 選択から印を外すだけで、**読み直しを起こさない。**
    ///
    /// didSet を通しても、今は読めなかった写真を読み直さない（`unreadable`）が、
    /// 送信の後始末で走らせる理由も無い（一部だけ上がった回の「残りは投稿できて
    /// いません」を、読み込みの知らせで消しかけた経緯がある）。
    /// **送信の後始末専用。** 送信中は選び直せないので、走っている読み込みは無い
    private func setSelectionQuietly(_ selection: [PhotosPickerItem]) {
        isSettingSelectionQuietly = true
        defer { isSettingSelectionQuietly = false }
        pickerItems = selection
    }

    /// 置いたまま保存していない本体を片付ける（本人がその写真を外した）
    private func discardStaged(_ photoId: UUID) {
        stagedEdits[photoId] = nil
        guard let placed = staged[photoId] else { return }
        staged[photoId] = nil
        let uploads = self.uploads
        Task { for key in placed.keys { await uploads.discard(key: key) } }
    }

    private func reset() {
        pickerItems = []
        placeTasks.values.forEach { $0.cancel() }
        placeTasks = [:]
        stripRenders.values.forEach { $0.cancel() }
        stripRenders = [:]
        items = []
        groupId = nil
        song = nil
        tagsText = ""
        // 最初のタグも忘れる（残すと、空に戻した画面が「書きかけ」になり、閉じられなかった）
        initialTagsText = ""
        // **印も下ろして入れ直す。** 曲だけ付かなかった回は画面が閉じずにここへ来るので、
        // 下ろさないと次の投稿でテーマのタグが空のまま残る
        appliedInitialTag = false
        applyInitialTag()
        category = ""
        // 初期値に戻す（旅の写真から来た画面は非公開のまま。`hasDraft` もこれと比べる）
        published = initialPublished
        audience = .everyone
        selectedAlbumId = nil
        sharable = []
    }

    /// 帯のサムネを作って入れる（2026-10-03）。以前は 1920px の本体をそのまま `UIImage(data:)` にして
    /// 画面の処理の上で持っていた（10枚で 1 枚 約 15MB の画素 × 10。帯は 96×120pt）
    private func startStripThumb(for photoId: UUID, prepared: ImagePreparer.Prepared) {
        let source = StripThumb.source(for: prepared)
        let make = makeStripThumb
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { make(source) }.value
            guard let self, let image,
                  let i = self.items.firstIndex(where: { $0.id == photoId }) else { return }
            self.items[i].preview = Image(uiImage: image)
        }
    }
}

/// 裏に回っても続けさせてもらう窓（`beginBackgroundTask`）。
/// **必ず閉じる**——閉じ忘れると、時間切れで OS にアプリごと止められる
@MainActor
final class BackgroundWindow {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // 時間切れ。送信は止まるが、ここで閉じないと OS に止められる。
            // 呼ばれるのは主スレッド（SDK の版によって型に書いていないので明示する）
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// 置いたが保存していない本体の控え（写真ごと）。
///
/// **MainActor に縛らない箱に入れる**のは、画面のモデルが消えるとき（`deinit`）
/// にも読むため。触るのは MainActor の上だけ
final class StagedUploads: @unchecked Sendable {
    private var byPhoto: [UUID: UploadService.Staged] = [:]

    subscript(photoId: UUID) -> UploadService.Staged? {
        get { byPhoto[photoId] }
        set { byPhoto[photoId] = newValue }
    }

    /// 全部を取り出して空にする。返すのは片付ける鍵
    func removeAll() -> [String] {
        let keys = byPhoto.values.flatMap(\.keys)
        byPhoto = [:]
        return keys
    }
}

/// 新規投稿の「追加」（ライブラリの選び直し）の差分。画面の状態を持たない計算だけ
enum PickerReconcile {

    /// 選び直しで**読む写真**と、読んでいる間の「読めなかった」控え。
    ///
    /// **本当に選び足したときだけ読む**（読めなかった分だけなら読まない）。
    /// 読めなかった写真は選択に残り待ち行列には居ないので、差分では毎回
    /// 「新しく選ばれた分」に見える。それだけで読むと、写真を外すたびに読み直して
    /// `errorMessage` を消し、「送れなかった」の知らせを読み込みの失敗で上書きしていた。
    ///
    /// **選び足したときは、読めなかった分も一緒に読み直す**——外すと、一時的な
    /// 失敗（iCloud・圏外）が直らないまま知らせも消え、1枚少ないまま投稿できる。
    ///
    /// **読む分は控えから外して返す。** 失敗は最後まで走った回だけが戻す——途中で
    /// 取り消された回の分は、次の回で新しい写真として読み直される（控えに残すと、
    /// 次の回が「新しい写真なし」で帰り、知らせも無いまま落ちる）。読めた写真も残らない
    ///
    /// `retry`: 「もう一度読み込む」を押した（`UploadViewModel.retryUnreadable`）。選び足していなくても、
    /// 読めなかった分を読み直す
    static func toLoad<Key: Hashable>(added: [Key], picked: [Key], unreadable: Set<Key>, retry: Bool = false)
        -> (load: [Key], unreadable: Set<Key>) {
        let stillPicked = unreadable.intersection(picked)
        let fresh = added.filter { !stillPicked.contains($0) }
        guard retry || !fresh.isEmpty else { return ([], stillPicked) }
        return (added, stillPicked.subtracting(added))
    }

    /// 投稿済みの写真の印を選択から外す。カメラの分（nil）は選択に居ないので関係ない
    static func dropPosted<Key: Hashable>(picked: [Key], posted: [Key?]) -> [Key] {
        let gone = Set(posted.compactMap { $0 })
        return picked.filter { !gone.contains($0) }
    }

    /// 選び直しの差分。**残す印と、新しく読む印**を返す。
    ///
    /// ライブラリは前の選択に印を付けて開く（`photoLibrary: .shared()`）ので、
    /// 返ってくる選択は「前の分＋足した分−外した分」。前の分を読み直さずに
    /// 残せば、1枚ずつ打った題・説明・撮影地が消えない。カメラの分（nil）は常に残す
    static func reconcile<Key: Hashable>(existing: [Key?], picked: [Key]) -> (keep: [Bool], added: [Key]) {
        let chosen = Set(picked)
        let keep = existing.map { key in key.map { chosen.contains($0) } ?? true }
        let known = Set(existing.compactMap { $0 })
        var seen = Set<Key>()
        let added = picked.filter { !known.contains($0) && seen.insert($0).inserted }
        return (keep, added)
    }
}
