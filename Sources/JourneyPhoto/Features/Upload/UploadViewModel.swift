import Foundation
import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

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

    /// 送る座標。空にした撮影地の座標は送らない
    var coordsToSend: Photo.Coords? {
        locationClearedByUser ? nil : (pickedCoords ?? prepared.coords)
    }
}

@MainActor
final class UploadViewModel: ObservableObject {

    /// **一度に選べる枚数。** 本当の上限はサーバーの1000枚
    /// （`api-user/src/photoLimit.ts`）だが、1枚ずつ題と説明を書く画面なので、
    /// 一度に扱う数はここで抑える（多すぎると、どれを書いているか見失う）。
    static let maxSelection = 10

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
    @Published var items: [PendingPhoto] = []

    // ここから下は、まとめて同じものが付く
    @Published var song: Photo.Song?
    @Published var tagsText = ""
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
    /// `pickerItems` を中から直している最中（`setSelectionQuietly`）
    private var isSettingSelectionQuietly = false
    /// 本体まで置けて、保存がまだ通っていない写真（`UploadService.stage` の注記）
    private let staged = StagedUploads()

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

    /// **読み込み中は押させない。** 読めたぶんだけが上がり、残りは黙って画面に残っていた
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

    /// カメラで撮った画像を受ける。
    ///
    /// **`UIImage` を経由した時点で EXIF は残っていない**（撮影地も
    /// 機材名も付かない）。それでも `ImagePreparer` を通すのは、
    /// 1920px への縮小と「残っていないことの確認」を1か所に寄せるため。
    func accept(capturedJPEG data: Data) {
        preparingCaptures += 1
        Task { [weak self] in
            let result = await Self.prepareOffMain(data)
            guard let self else { return }
            self.preparingCaptures -= 1
            switch result {
            case .success(let prepared):
                self.append(prepared)
                // **読めなかったライブラリの写真が選ばれたままなら、知らせは消さない。**
                // 消すと、その写真が抜けたまま投稿できる（写真を外しても読み直さない
                // ので、知らせは二度と出ない）
                if self.unreadable.isEmpty { self.errorMessage = nil }
            case .failure(let error):
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? L("写真を読み込めませんでした", "Couldn't load the photo")
            }
        }
    }

    /// 🔴 **画像を整えるのは画面の処理（MainActor）の外で。** 縮小・JPEG への
    /// 焼き直し・読み直しての確認・代表色で、1枚に数百ミリ秒かかる。10枚選ぶと
    /// その間ずっと画面が止まっていた
    private static func prepareOffMain(_ data: Data) async -> Result<ImagePreparer.Prepared, Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try ImagePreparer.prepare(data: data, fileName: "photo") }
        }.value
    }

    func remove(_ photoId: UUID) {
        // 送っている間は外さない（ボタンの `.disabled` は次の描画まで効かない）。
        // 保存の最中に本体を片付けると、通った行の画像が割れる
        guard !isWorking else { return }
        placeTasks[photoId]?.cancel()
        placeTasks[photoId] = nil
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
    private func loadPicked(_ picked: [PhotosPickerItem]) async {
        // 走り出す前に取り消された回は、古い選択で一覧を削らない
        guard !Task.isCancelled else { return }
        // **選び直しは差分で。** 外した分だけ落とし、足した分だけ読む。
        // 以前は丸ごと入れ替えていて、「追加」を押すと打った題やカメラで撮った
        // 分まで消えていた（2026-09-26 のレビュー）
        let diff = PickerReconcile.reconcile(existing: items.map(\.pickerItem), picked: picked)
        // 🔴 **本当に選び足したときだけ読む。** 読めなかった写真の扱いは `toLoad` の注記
        let plan = PickerReconcile.toLoad(added: diff.added, picked: picked, unreadable: unreadable)
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
        didPostAll = false
        defer { if generation == pickGeneration { isLoadingPicked = false } }

        var failedItems: [PhotosPickerItem] = []
        for item in added {
            if Task.isCancelled { return }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failedItems.append(item)
                    continue
                }
                // 読んでいる間に選び直されたら、この結果は捨てる
                guard !Task.isCancelled, generation == pickGeneration else { return }
                // **`itemIdentifier` をファイル名にしない。** スラッシュを含む
                // 端末内部の ID で、キーの組み立てを壊す。拡張子は
                // `ImagePreparer` が .jpg に付け替える。整えるのは画面の処理の外で
                let result = await Self.prepareOffMain(data)
                // 整えている間に選び直されたら、この結果は捨てる
                guard !Task.isCancelled, generation == pickGeneration else { return }
                switch result {
                case .success(let prepared):
                    append(prepared, pickerItem: item)
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

    /// 1枚を待ち行列に足し、撮影地を引き始める。
    private func append(_ prepared: ImagePreparer.Prepared, pickerItem: PhotosPickerItem? = nil) {
        var photo = PendingPhoto(prepared: prepared)
        photo.pickerItem = pickerItem
        photo.preview = Self.image(from: prepared.data)
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
        // 🔴 **送っている途中でアプリを離れても、少しのあいだ続けさせてもらう。**
        // 無いと裏に回った数秒後に止められ、戻ったときには通信が切れて失敗になる。
        // 時間切れ（30秒ほど）でも落ちた写真は画面に残り、やり直しは同じ鍵で送る
        let background = BackgroundWindow(name: "photo-upload")
        defer {
            isWorking = false
            uploadingIndex = 0
            background.end()
        }

        groupId = UploadGrouping.groupIdForSubmit(current: groupId, grouping: groupsAsOnePost,
                                        count: items.count, make: { UUID().uuidString })

        var done: [UUID] = []
        var failures: [String] = []
        /// 写真は上がったが曲を付けられなかった枚数。**成功に数えない**
        var songFailures = 0
        let queue = items.map(\.id)
        for (offset, id) in queue.enumerated() {
            // **1枚ごとに見る。** 5枚選んで2枚目でやめたとき、残りを上げ始めない
            if cancelled { break }
            uploadingIndex = offset + 1
            // **送る直前に引き直す。** 送信中も欄は生きているので、
            // 始めたときの写しで送ると、直した題が古い値で上がる
            guard let item = items.first(where: { $0.id == id }) else { continue }
            do {
                let songAttached = try await upload(item)
                if !songAttached { songFailures += 1 }
                done.append(item.id)
            } catch {
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
            // `UploadView` が即 `dismiss()` するので、警告が一度も描かれない
            if songFailures == 0 {
                didPostAll = done.count > 0
            } else {
                errorMessage = UploadSummary.message(done: done.count, failures: failures,
                                                     cancelled: cancelled, songFailures: songFailures)
            }
            // **どちらにしても選択は捨てる。** 残すと `pickerItems` に
            // 投稿済みの写真が選ばれたまま残り、次に写真を選び直した瞬間に
            // `didSet` が走って**同じ写真がもう一度上がる**
            // （`errorMessage` は `reset()` では消えないので警告は残る）
            reset()
        } else {
            errorMessage = UploadSummary.message(done: done.count, failures: failures,
                                                 cancelled: cancelled, songFailures: songFailures)
        }
    }

    /// - Returns: 曲まで含めて狙いどおりに終わったか。写真は上がったが
    ///   曲を付けられなかったときだけ `false`。**ここで `errorMessage` に
    ///   書かない**——呼び出し元が最後にまとめて出す（途中で書くと、
    ///   全部成功と見なされた `reset()` のあとに画面が閉じて消える）
    private func upload(_ item: PendingPhoto) async throws -> Bool {
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
        draft.coords = item.coordsToSend
        draft.date = item.prepared.takenOn
        draft.exif = item.prepared.exif
        // **読み込み中の地の色。** Web は前から送っていて、アプリだけ
        // 送っていなかった（同じ一覧でアプリの写真の枠だけ黒いまま残る）
        draft.dominantColor = item.prepared.dominantColor
        draft.albumId = selectedAlbumId
        draft.groupId = groupId

        // 🔴 **やり直しは前回の鍵で保存する**（`UploadService.stage` の注記）。
        // 保存が落ちた写真は本体を置き直さない——新しい鍵で送ると、前回の保存が
        // 実は通っていたときに同じ写真が2枚になる
        let presigned: UploadService.PresignResponse
        if let already = staged[item.id] {
            presigned = already
        } else {
            presigned = try await uploads.stage(
                data: item.prepared.data,
                fileName: item.prepared.fileName,
                fileType: item.prepared.contentType
            )
            staged[item.id] = presigned
        }
        let photo = try await uploads.save(draft, presigned: presigned)
        staged[item.id] = nil
        // **曲は保存のあと。** `POST /upload/save` は song を受け取らない
        // ので、`PUT /photos/{id}` で付ける。ここが落ちても写真は
        // 上がっているので、投稿そのものは失敗にしない
        if let song, let id = photo?.id {
            var patch = PhotoPatch()
            patch.song = song
            do {
                try await photoService.update(photoId: id, patch: patch)
            } catch {
                return false
            }
        }
        return true
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
        guard let presigned = staged[photoId] else { return }
        staged[photoId] = nil
        let uploads = self.uploads
        Task { await uploads.discard(key: presigned.key) }
    }

    private func reset() {
        pickerItems = []
        placeTasks.values.forEach { $0.cancel() }
        placeTasks = [:]
        items = []
        groupId = nil
        song = nil
        tagsText = ""
        category = ""
        published = true
        audience = .everyone
        selectedAlbumId = nil
    }

    private static func image(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
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
    private var byPhoto: [UUID: UploadService.PresignResponse] = [:]

    subscript(photoId: UUID) -> UploadService.PresignResponse? {
        get { byPhoto[photoId] }
        set { byPhoto[photoId] = newValue }
    }

    /// 全部を取り出して空にする。返すのは片付ける鍵
    func removeAll() -> [String] {
        let keys = byPhoto.values.map(\.key)
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
    static func toLoad<Key: Hashable>(added: [Key], picked: [Key], unreadable: Set<Key>)
        -> (load: [Key], unreadable: Set<Key>) {
        let stillPicked = unreadable.intersection(picked)
        let fresh = added.filter { !stillPicked.contains($0) }
        guard !fresh.isEmpty else { return ([], stillPicked) }
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
