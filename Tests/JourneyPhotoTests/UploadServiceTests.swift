import XCTest
@testable import JourneyPhoto
// `PhotosPickerItem` は PhotosUI と SwiftUI の重なりにある。**両方要る**
// （片方だと Xcode でだけ落ちる・`Tools/check-cross-imports.py`）
import SwiftUI
import PhotosUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の3手（presign → S3 に PUT → save）。
///
/// **2手目と3手目の間で落ちたら S3 に迷子が残る。** そこを実際に走らせて見る。
final class UploadServiceTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func service() -> UploadService {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        return UploadService(api: api, session: session)
    }

    private let presignBody = """
    {"presignedUrl":"https://s3.example.test/put?sig=1",
     "key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg",
     "photoId":"p1","contentType":"image/jpeg"}
    """

    /// 3手が順番どおり呼ばれ、**PUT の Content-Type は presign が返した値**。
    /// presigner が content-type を署名対象に入れているので、違う値で送ると
    /// 署名が合わない（`api-user/src/uploadPolicy.ts` の経緯）。
    func testHappyPathSendsSignedContentType() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let presigned = try await service().stage(
            data: Data(repeating: 0xFF, count: 16),
            fileName: "photo.jpg", fileType: "image/jpeg"
        )
        let photo = try await service().save(PhotoDraft(), presigned: presigned)
        XCTAssertEqual(photo?.id, "p1")
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path),
                       ["/upload/presigned-url", "/put", "/upload/save"])
        let put = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/put" })
        XCTAssertEqual(put.contentType, "image/jpeg")
        XCTAssertEqual(put.method, "PUT")
    }

    /// **PUT で落ちたら、S3 の迷子を片付ける。** 行はまだ無いので消してよい
    func testDiscardsUploadWhenPutFails() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 500, body: ""),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        do {
            _ = try await service().stage(
                data: Data(repeating: 0xFF, count: 16),
                fileName: "photo.jpg", fileType: "image/jpeg"
            )
            XCTFail("投げるはず")
        } catch {
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 500)
        }
        XCTAssertTrue(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" },
                      "S3 に迷子が残ったまま")
    }

    /// スポットの画面から開いた投稿は、**保存の本文に `spotId` が入る**（配線まで見る）。
    /// スポットを外したら入らない
    @MainActor
    func testSpotUploadSendsSpotIdInTheSaveBody() async throws {
        for removed in [false, true] {
            ScriptedProtocol.reset()
            ScriptedProtocol.script = [
                .init(match: "/upload/presigned-url", status: 200, body: presignBody),
                .init(match: "/put", status: 200, body: ""),
                .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
            ]
            let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                                tokenProvider: StubTokenProvider(token: "t"), session: session)
            let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                        photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
            model.spot = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社", coords: nil)
            var item = PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
                exif: nil, coords: nil, takenOn: nil))
            item.location = "高屋神社"
            model.items = [item]
            if removed { model.removeSpot() }

            await model.submit()

            let save = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/upload/save" })
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(save.body)) as? [String: Any])
            if removed {
                XCTAssertNil(json["spotId"], "外したのに送った")
                XCTAssertEqual(model.postedToSpot, 0, "並ばない投稿で「投稿しました」を出す")
            } else {
                XCTAssertEqual(json["spotId"] as? String, "sp_0123456789ab")
                XCTAssertEqual(model.postedToSpot, 1)
            }
        }
    }

    /// 🔴 **今日のテーマのタグは一度だけ入れる。** 画面の `onAppear` は選択画面などから
    /// 戻るたびに呼ばれる——印が無いと、利用者が空にしたタグがまた入っていた
    @MainActor
    func testThemeTagIsAppliedOnlyOnce() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.initialTag = "夕焼け"
        model.applyInitialTag()
        XCTAssertEqual(model.tagsText, "夕焼け")
        model.tagsText = ""
        model.applyInitialTag()  // カテゴリの選択画面から戻った
        XCTAssertEqual(model.tagsText, "", "空にしたタグを戻ってきたときに入れ直している")
    }

    /// 束の印の頭（2026-10-02 判断）: 旅の写真の流れから来た投稿は必ず `trip-` で始まり、
    /// ふだんのまとめ投稿には付かない（旅の記録の一冊になるのは前者だけ）
    @MainActor
    func testTripGroupIdOnlyFromTheTripFlow() async throws {
        for fromTrip in [true, false] {
            ScriptedProtocol.reset()
            ScriptedProtocol.script = [
                .init(match: "/upload/presigned-url", status: 200, body: presignBody),
                .init(match: "/put", status: 200, body: ""),
                .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
            ]
            let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                                tokenProvider: StubTokenProvider(token: "t"), session: session)
            let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                        photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
            if fromTrip {
                // 旅の写真の流れ（RootView → UploadView の initialPhotos）。模型では整えられないので
                // 失敗を言い終えるまで待ってから、整った写真を置く
                model.applyInitialPhotos([Data([1])], startPrivate: true)
                for _ in 0..<300 where model.errorMessage == nil {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                XCTAssertTrue(model.fromTripImport)
            }
            // 旅の流れでは「それぞれ別の投稿」にしても束ねる（ふだんの投稿はまとめるときだけ）
            model.groupsAsOnePost = !fromTrip
            model.items = (0..<2).map { _ in PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
                exif: nil, coords: nil, takenOn: nil)) }

            await model.submit()

            let saves = ScriptedProtocol.calls.filter { $0.path == "/upload/save" }
            XCTAssertEqual(saves.count, 2)
            for save in saves {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(save.body)) as? [String: Any])
                let groupId = try XCTUnwrap(json["groupId"] as? String)
                XCTAssertEqual(groupId.hasPrefix("trip-"), fromTrip,
                               fromTrip ? "旅の写真の流れの束に trip- が付いていない" : "ふだんのまとめ投稿に trip- が付いた")
                XCTAssertLessThanOrEqual(groupId.count, 64)
            }
        }
    }

    /// 旅の写真から来た投稿は**非公開で送る**。上げ終えて片付けたあとも非公開のまま
    /// （初期値に戻す）で、片付いた画面は書きかけではない（閉じるときに聞かない）
    @MainActor
    func testPrivateStartIsSentAndKeptAfterReset() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.applyInitialPhotos([], startPrivate: true)
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        await model.submit()

        let save = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/upload/save" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(save.body)) as? [String: Any])
        XCTAssertEqual(json["published"] as? Bool, false, "非公開で始めたのに公開で送った")
        XCTAssertTrue(model.didPostAll)
        XCTAssertFalse(model.published, "片付けで公開に戻った")
        XCTAssertFalse(model.hasDraft, "片付いた画面を書きかけにした")
    }

    /// 🔴 **曲だけ付かなかった回は画面が閉じずに入力を片付ける。** そのときテーマの
    /// タグは入れ直す——印を下ろさないと、次の投稿でタグが空のまま残った
    @MainActor
    func testThemeTagComesBackAfterAPostWhoseSongFailed() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
            // 曲を付ける `PUT /photos/p1` は台本に無い＝404 で落ちる
        ]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.initialTag = "夕焼け"
        model.applyInitialTag()
        model.song = Photo.Song(title: "曲", artist: nil, artwork: nil,
                                previewUrl: "https://example.test/p.m4a", trackUrl: nil)
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        await model.submit()

        XCTAssertFalse(model.didPostAll, "前提: 曲が付かなかった回は閉じない")
        XCTAssertNotNil(model.errorMessage, "前提: 曲が付かなかったと知らせている")
        XCTAssertTrue(model.items.isEmpty, "前提: 入力は片付いている")
        XCTAssertEqual(model.tagsText, "夕焼け", "片付けたあとテーマのタグが空のまま")
    }

    /// 🔴 **持ち主が消したアルバムは、行き先から外して止める。** 保存は「見つかりません」
    /// （会員でない＝`isAlbumMember`）で断られる。止めずに続けると残りも全部同じ理由で落ち、
    /// 行き先に残るので押し直しても直らなかった
    @MainActor
    func testGoneAlbumIsDroppedAndTheRestIsNotSent() async throws {
        ScriptedProtocol.script = [
            .init(match: "/albums", status: 200, body: #"{"albums":[]}"#),
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 404, body: #"{"error":"アルバムが見つかりません"}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        await model.loadAlbums(joined: [JoinedAlbumsStore.Entry(id: "gone", title: "消されたアルバム", token: "t1")])
        XCTAssertEqual(model.albums.map(\.id), ["gone"], "下ごしらえ: 参加したアルバムが行き先に出る")
        var forgotten: [String] = []
        model.onAlbumGone = { forgotten.append($0) }
        model.selectedAlbumId = "gone"
        let photo = { PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil)) }
        model.items = [photo(), photo(), photo()]

        await model.submit()

        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1,
                       "アルバムが無いと分かったあとも残りを送った")
        XCTAssertEqual(model.items.count, 3, "写真は残る（行き先を選び直して送れる）")
        XCTAssertNil(model.selectedAlbumId)
        XCTAssertFalse(model.albums.contains { $0.id == "gone" }, "行き先に残った")
        XCTAssertEqual(forgotten, ["gone"], "端末の控えから外さない")
        XCTAssertTrue(model.errorMessage?.contains(L("選んだアルバムが見つかりませんでした", "The album you chose wasn't found")) == true,
                      "理由が伝わらない: \(model.errorMessage ?? "nil")")
        try await discardLeftovers(model, staged: 1)
    }

    /// 🔴 **外すのは送った宛先。** 送信中も行き先は選び直せる。消されたアルバム宛ての保存が
    /// 返る前に生きているアルバムへ選び直すと、生きている方を行き先と端末の控えから外していた
    @MainActor
    func testGoneAlbumIsTheOneSentNotTheOneChosenSince() async throws {
        ScriptedProtocol.script = [
            .init(match: "/albums", status: 200, body: #"{"albums":[]}"#),
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 404, body: #"{"error":"アルバムが見つかりません"}"#),
        ]
        let gate = Gate()
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session,
            beforeRequest: { request in
                if request.url?.path == "/upload/save" { await gate.wait() }
            }
        )
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        await model.loadAlbums(joined: [JoinedAlbumsStore.Entry(id: "gone", title: "消されたアルバム", token: "t1"),
                                        JoinedAlbumsStore.Entry(id: "live", title: "生きているアルバム", token: "t2")])
        var forgotten: [String] = []
        model.onAlbumGone = { forgotten.append($0) }
        model.selectedAlbumId = "gone"
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        let sending = Task { await model.submit() }
        await gate.untilWaiting()
        model.selectedAlbumId = "live"
        await gate.open()
        await sending.value

        XCTAssertEqual(forgotten, ["gone"], "選び直した方を端末の控えから外した")
        XCTAssertEqual(model.albums.map(\.id), ["live"], "選び直した方を行き先から外した")
        XCTAssertEqual(model.selectedAlbumId, "live", "選び直した行き先が消えた")
        try await discardLeftovers(model, staged: 1)
    }

    /// S3 への PUT の 404 は「アルバムが無い」ではない（保存の 404 だけがそれ）
    @MainActor
    func testStorageNotFoundIsNotAGoneAlbum() async throws {
        ScriptedProtocol.script = [
            .init(match: "/albums", status: 200, body: #"{"albums":[]}"#),
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 404, body: ""),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        await model.loadAlbums(joined: [JoinedAlbumsStore.Entry(id: "alb", title: "旅", token: "t1")])
        var forgotten: [String] = []
        model.onAlbumGone = { forgotten.append($0) }
        model.selectedAlbumId = "alb"
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        await model.submit()

        XCTAssertEqual(forgotten, [], "置き場所の失敗でアルバムを忘れた")
        XCTAssertEqual(model.selectedAlbumId, "alb")
        XCTAssertEqual(model.albums.map(\.id), ["alb"])
    }

    /// 置いたまま保存の通らなかった写真（`staged` 枚）の鍵を、**この試験の中で**片付ける。
    /// 残すと、モデルが消えるとき（`deinit`）の片付けが後から走り、次の試験の呼び出し記録に
    /// 紛れ込む（`testHappyPathSendsSignedContentType` が約4回に1回落ちた）
    @MainActor
    private func discardLeftovers(_ model: UploadViewModel, staged: Int) async throws {
        let before = ScriptedProtocol.calls.filter { $0.path == "/upload/discard" }.count
        model.items.map(\.id).forEach { model.remove($0) }
        let done = { ScriptedProtocol.calls.filter { $0.path == "/upload/discard" }.count >= before + staged }
        try await waitUntil(done)
        // 届かないまま進むと、片付けが次の試験の記録に紛れる（前に不定期に落ちた原因）
        XCTAssertTrue(done(), "置き場所の鍵を片付けられなかった")
    }

    /// 🔴 **保存のやり直しは同じ鍵で送る。** 保存が「落ちた」ときも、サーバーには
    /// 行ができていることがある（応答だけ失われた）。やり直しで presign から
    /// 通すと新しい鍵になり、サーバーの「鍵から ID を導く」重複よけが効かず、
    /// 同じ写真が2枚になっていた。片付け（discard）もしない——やり直す鍵の本体が消える
    @MainActor
    func testRetryAfterFailedSaveReusesTheSameKey() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        await model.submit()
        XCTAssertEqual(model.items.count, 1, "落ちた写真は残る")
        XCTAssertNotNil(model.errorMessage)

        ScriptedProtocol.script = [
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        await model.submit()
        XCTAssertTrue(model.items.isEmpty)

        let paths = ScriptedProtocol.calls.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/upload/presigned-url" }.count, 1, "やり直しで新しい鍵をもらっている")
        XCTAssertEqual(paths.filter { $0 == "/put" }.count, 1, "本体を置き直している")
        XCTAssertEqual(paths.filter { $0 == "/upload/save" }.count, 2)
        XCTAssertFalse(paths.contains("/upload/discard"), "やり直す鍵の本体を消している")
    }

    /// 保存が落ちた写真を**本人が外したら**、置いたままの本体を片付ける
    /// （保存の失敗では片付けないので、ここで消さないと S3 に残る）
    @MainActor
    func testRemovingAPhotoWhoseSaveFailedDiscardsItsUpload() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 500, body: #"{"error":"保存に失敗しました"}"#),
            .init(match: "/upload/discard", status: 200, body: #"{"success":true}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]
        await model.submit()
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" })

        model.remove(model.items[0].id)
        try await waitUntil { ScriptedProtocol.calls.contains { $0.path == "/upload/discard" } }
        XCTAssertTrue(ScriptedProtocol.calls.contains { $0.path == "/upload/discard" },
                      "外した写真の本体が S3 に残ったまま")
    }

    /// カメラの1枚は**画面の処理の外で整える**。整えている間は投稿させない
    /// （押すと、その1枚が待ち行列に入る前に送信が始まる）。整えられなければ知らせる
    @MainActor
    func testCapturedPhotoIsPreparedInTheBackgroundAndBlocksSubmitMeanwhile() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]
        XCTAssertTrue(model.canSubmit)

        // 模型の ImageIO は読めないので、整えるのは失敗で終わる
        model.accept(capturedJPEG: Data([0x00]))
        XCTAssertFalse(model.canSubmit, "整えている間に投稿できる")
        try await waitUntil { model.canSubmit }
        XCTAssertTrue(model.canSubmit)
        XCTAssertNotNil(model.errorMessage, "整えられなかったことを知らせていない")
        XCTAssertEqual(model.items.count, 1)
    }

    /// **カメラの写真だけの回でも、最後の1枚を外したら束の印を捨てる。**
    /// 残すと、次に撮った写真が前の（一部だけ上がった）投稿の束に入る
    @MainActor
    func testRemovingTheLastCameraPhotoDropsTheGroup() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        // どちらも手前で弾かれる形（通信しない）。印は送り始めに作られる
        func camera() -> PendingPhoto {
            PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data([0xFF]), fileName: "photo.jpg", contentType: "image/svg+xml",
                exif: nil, coords: nil, takenOn: nil))
        }
        model.items = [camera(), camera()]
        model.groupsAsOnePost = true
        await model.submit()
        XCTAssertNotNil(model.groupId)

        model.remove(model.items[0].id)
        XCTAssertNotNil(model.groupId, "まだ1枚残っている")
        model.remove(model.items[0].id)
        XCTAssertNil(model.groupId, "前の投稿の束の印が残っている")
    }

    /// **選び足したときは、前に読めなかった写真も読み直す。** 読み直さないと、
    /// 一時的な失敗が直らないまま知らせが消え、1枚少ないまま投稿できる
    @MainActor
    func testAddingPhotosRetriesThoseThatCouldNotBeLoaded() async throws {
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        // 読めない写真を決まった形で作る（シミュレータの本物の写真ライブラリに問い合わせない）
        model.loadPickedData = { _ in nil }
        let a = PhotosPickerItem(itemIdentifier: "a")
        let c = PhotosPickerItem(itemIdentifier: "c")
        let d = PhotosPickerItem(itemIdentifier: "d")
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xFF]), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))
        photo.pickerItem = a
        model.items = [photo]
        model.pickerItems = [a, c]
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil }
        let once = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(once.contains("1"), once)

        model.pickerItems = [a, c, d]
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil && model.errorMessage != once }
        let twice = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(twice.contains("2"), "読めなかった c を読み直していない: \(twice)")
    }

    /// 条件が立つまで待つ（既定は最長5秒）。切り離した仕事の終わりを時間で当てない
    @MainActor
    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        for _ in 0..<Int(seconds * 100) where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// 🔴 **一部だけ上がった回に、投稿済みの写真を選択から外す**——そして
    /// **その直しで読み直しを起こさない。**
    ///
    /// 外さないと、残った1枚を外す・「追加」で選び足すたびに、投稿済みの写真が
    /// 新しく選ばれた分として読み直され、もう一度上がる。外すときに読み直しを
    /// 起こすと、前に読めなかった写真を読み直して「残りは投稿できていません」を消す
    @MainActor
    func testPartialPostDropsPostedItemsFromTheSelectionAndKeepsTheError() async throws {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presignBody),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        let api = APIClient(
            baseURL: URL(string: "https://api.example.test")!,
            tokenProvider: StubTokenProvider(token: "t"),
            session: session
        )
        let model = UploadViewModel(uploads: service(), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        // 読めない写真を決まった形で作る（シミュレータの本物の写真ライブラリに問い合わせない）
        model.loadPickedData = { _ in nil }
        let a = PhotosPickerItem(itemIdentifier: "a")
        let b = PhotosPickerItem(itemIdentifier: "b")
        // c は読めなかった写真（選択には残り、待ち行列には居ない）
        let c = PhotosPickerItem(itemIdentifier: "c")
        func pending(_ key: PhotosPickerItem, type: String) -> PendingPhoto {
            var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: type,
                exif: nil, coords: nil, takenOn: nil))
            photo.pickerItem = key
            return photo
        }
        // b は手前で弾かれる形にして、a だけが上がる回を作る
        model.items = [pending(a, type: "image/jpeg"), pending(b, type: "image/svg+xml")]
        model.pickerItems = [a, b, c]
        // c の読み込み（読めずに終わる）を待つ。**時間で待たない**——本物の
        // PhotosUI では 100ms で返る保証が無い
        try await waitUntil { !model.isLoadingPicked && model.errorMessage != nil }

        await model.submit()
        let summary = model.errorMessage
        XCTAssertNotNil(summary)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.pickerItems, [b, c], "投稿済みの写真が選ばれたまま")
        XCTAssertEqual(model.errorMessage, summary, "送れなかった知らせが消えている")

        // 残った1枚を外しても、読めなかった c を読み直して知らせを上書きしない
        model.remove(model.items[0].id)
        // 読み直しが起きないことを見るので、短く待てば足りる
        try await waitUntil(seconds: 0.5) { model.isLoadingPicked || model.errorMessage != summary }
        XCTAssertEqual(model.pickerItems, [c])
        XCTAssertEqual(model.errorMessage, summary, "写真を外したら送れなかった知らせが消えた")
    }

    /// 上限と形は**手前で弾く**（50MB 上げてから 400 を食わない）。
    func testRejectsTooLargeFileWithoutCallingServer() async {
        do {
            _ = try await service().stage(
                data: Data(count: UploadService.maxFileSize + 1),
                fileName: "big.jpg", fileType: "image/jpeg"
            )
            XCTFail("投げるはず")
        } catch {
            // **文言で確かめない。** 表示は端末の言語で変わる。見るのは形
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 400)
        }
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "手前で弾かずに投げている")
    }

    /// **SVG は通さない。** スクリプトを書ける文書で、同じオリジンから返る。
    func testRejectsSVG() async {
        do {
            _ = try await service().stage(
                data: Data("<svg/>".utf8),
                fileName: "a.svg", fileType: "image/svg+xml"
            )
            XCTFail("投げるはず")
        } catch {
            guard case .server(let status, _)? = error as? APIError else {
                return XCTFail("形が違う: \(error)")
            }
            XCTAssertEqual(status, 400)
        }
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty)
    }

    /// 🔴 **差し替えで撮影日を載せなかった回は、そうと返す**（画面が「撮影日は前のまま」と知らせる）。
    /// 載せた回・元から撮影日の無い写真は false
    func testReplaceTellsWhenTheDateWasLeftOut() async throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let photos = PhotoService(api: api)
        for (takenOn, keptOld) in [("1980-01-01", true), ("2024-11-01", false), (nil, false)] as [(String?, Bool)] {
            ScriptedProtocol.reset()
            ScriptedProtocol.script = [
                .init(match: "/upload/presigned-url", status: 200, body: presignBody),
                .init(match: "/put", status: 200, body: ""),
                .init(match: "/photos/p1", status: 200, body: "{}"),
            ]
            let prepared = ImagePreparer.Prepared(data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg",
                                                  contentType: "image/jpeg", exif: nil, coords: nil, takenOn: takenOn)
            let result = try await photos.replace(photoId: "p1", prepared: prepared, uploads: service())
            XCTAssertEqual(result, keptOld, "\(takenOn ?? "nil")")
            let put = try XCTUnwrap(ScriptedProtocol.calls.first { $0.path == "/photos/p1" })
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(put.body)) as? [String: Any])
            let replace = try XCTUnwrap(json["replace"] as? [String: Any])
            XCTAssertEqual(replace["date"] as? String, keptOld ? nil : takenOn)
        }
    }
}

/// 順番に応答を返す `URLProtocol`。パスの一部で引き当てる。
final class ScriptedProtocol: URLProtocol {

    struct Step {
        let match: String
        let status: Int
        let body: String
        /// 1回使ったら外す。**同じ口に1回目・2回目で別の答え**を返すのに使う
        /// （本体とサムネイルの presign に別の鍵を返し、取り違えを捕まえる）
        var once = false
    }

    struct Call {
        let path: String
        let method: String
        let contentType: String?
        /// 送った本文（読めたときだけ）。URLProtocol には `httpBody` ではなく流れで届く
        var body: Data? = nil
    }

    nonisolated(unsafe) static var script: [Step] = []
    nonisolated(unsafe) static var calls: [Call] = []

    static func reset() {
        script = []
        calls = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        ScriptedProtocol.calls.append(.init(
            path: path,
            method: request.httpMethod ?? "",
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: request.httpBody ?? Self.read(request.httpBodyStream)
        ))
        let index = ScriptedProtocol.script.firstIndex { path.contains($0.match) }
        let step = index.map { ScriptedProtocol.script[$0] }
        if let index, step?.once == true { ScriptedProtocol.script.remove(at: index) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: step?.status ?? 404,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((step?.body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
