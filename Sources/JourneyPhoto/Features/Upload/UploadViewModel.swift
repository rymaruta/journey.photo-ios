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
            if location.isEmpty, !oldValue.isEmpty { locationClearedByUser = true }
            else if !location.isEmpty { locationClearedByUser = false }
        }
    }
    /// 撮影地を候補から選んだときに入る座標（写真の EXIF より優先）
    var pickedCoords: Photo.Coords?
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
    private var groupId: String?
    /// 何回目の選択か。選び直した後に、前の読み込みの結果を混ぜないための目印
    private var pickGeneration = 0

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumId: String?
    /// 送信中。**読み込み中とは分ける**——一緒にすると、写真を選んでいる
    /// 間に「送信中… 0 / 2 枚目」と「残りをやめる」が出る
    @Published private(set) var isWorking = false
    @Published private(set) var isLoadingPicked = false
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

    init(uploads: UploadService, albums: AlbumService, photos: PhotoService, discovery: DiscoveryService) {
        self.uploads = uploads
        self.albumService = albums
        self.photoService = photos
        self.discovery = discovery
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
    var canSubmit: Bool { !items.isEmpty && !isWorking && !isLoadingPicked }

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
        do {
            let prepared = try ImagePreparer.prepare(data: data, fileName: "photo")
            append(prepared)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    func remove(_ photoId: UUID) {
        placeTasks[photoId]?.cancel()
        placeTasks[photoId] = nil
        items.removeAll { $0.id == photoId }
    }

    /// 選ばれた写真を読み、**その場で EXIF を落とす**。
    /// 落とせなかったら受け付けない（`ImagePreparer` の関所）。
    ///
    /// **1枚でも読めたら、読めたぶんは受ける。** 全部捨てると、
    /// 1枚の壊れた写真のために選び直しになる（Web も落ちた枚数だけ伝える）。
    private func loadPicked(_ picked: [PhotosPickerItem]) async {
        guard !picked.isEmpty else { return }
        // 🔴 **選び直しの競合。** 前の読み込みは取り消されても `await` から戻ってくる。
        // 戻った先で確かめずに足すと、選び直した一覧に外したはずの写真が混ざり、
        // 前の読み込みの後片付けが「読み込み中」を早く消していた
        pickGeneration += 1
        let generation = pickGeneration
        isLoadingPicked = true
        errorMessage = nil
        didPostAll = false
        // 選び直したら、前の選択で作った束の印は使わない
        groupId = nil
        defer { if generation == pickGeneration { isLoadingPicked = false } }

        // 選び直しは**入れ替え**（前の選択が残ると、何が上がるのか読めない）
        placeTasks.values.forEach { $0.cancel() }
        placeTasks = [:]
        items = []

        var failed = 0
        for item in picked {
            if Task.isCancelled { return }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failed += 1
                    continue
                }
                // 読んでいる間に選び直されたら、この結果は捨てる
                guard !Task.isCancelled, generation == pickGeneration else { return }
                // **`itemIdentifier` をファイル名にしない。** スラッシュを含む
                // 端末内部の ID で、キーの組み立てを壊す。拡張子は
                // `ImagePreparer` が .jpg に付け替える
                append(try ImagePreparer.prepare(data: data, fileName: "photo"))
            } catch {
                failed += 1
            }
        }

        if failed > 0 {
            // **黙って減らさない。** 「なぜか1枚少ない」まま公開させない
            errorMessage = items.isEmpty
                ? L("写真を読み込めませんでした", "Couldn't load the photos")
                : L("\(failed) 枚は読み込めませんでした", "\(failed) photo(s) couldn't be loaded")
        }
    }

    /// 1枚を待ち行列に足し、撮影地を引き始める。
    private func append(_ prepared: ImagePreparer.Prepared) {
        var photo = PendingPhoto(prepared: prepared)
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
        guard !isWorking, !items.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        cancelled = false
        defer {
            isWorking = false
            uploadingIndex = 0
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
        items.removeAll { done.contains($0.id) }
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

        let photo = try await uploads.upload(
            data: item.prepared.data,
            fileName: item.prepared.fileName,
            fileType: item.prepared.contentType,
            draft: draft
        )
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
