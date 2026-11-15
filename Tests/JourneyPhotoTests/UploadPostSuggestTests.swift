import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の画面の題・説明・タグの候補（札 #622・2026-11-15）を、画面の持ち主（`UploadViewModel`）で見る。
/// AI は呼ばない（`runPostSuggest` を差し替える）
@MainActor
final class UploadPostSuggestTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: OnDeviceAI.modeKey)
        super.tearDown()
    }

    private func pending(location: String = "", takenOn: String? = nil, exif: ExifFields? = nil) -> PendingPhoto {
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xff]), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: exif, coords: nil, takenOn: takenOn))
        photo.location = location
        return photo
    }

    private func model() -> UploadViewModel {
        let session = URLSession(configuration: .ephemeral)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                               photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
    }

    /// 候補は札に出すだけで、欄（題・説明・タグ）は書き換えない
    func testSuggestionsNeverWriteFields() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let model = model()
        let photo = pending(location: "兼六園", takenOn: "2026-11-03")
        model.items = [photo]
        await model.loadPostSuggestion(for: photo.id)

        XCTAssertEqual(model.items[0].title, "")
        XCTAssertEqual(model.items[0].caption, "")
        XCTAssertEqual(model.tagsText, "")
        XCTAssertEqual(model.titleSuggestions(for: model.items[0]), PostSuggest.sample.titles)
        XCTAssertEqual(model.captionSuggestion(for: model.items[0]), PostSuggest.sample.caption)
        XCTAssertEqual(model.suggestedTags, PostSuggest.sample.tags)
    }

    /// 打った題・説明の上には候補を出さない
    func testTypedFieldsHideCandidates() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let model = model()
        let photo = pending(location: "兼六園")
        model.items = [photo]
        await model.loadPostSuggestion(for: photo.id)
        model.items[0].title = "自分の題"
        model.items[0].caption = "自分の説明"
        XCTAssertEqual(model.titleSuggestions(for: model.items[0]), [])
        XCTAssertNil(model.captionSuggestion(for: model.items[0]))
    }

    /// 端末の AI が使えない機種・OS では、候補の仕組みを何も動かさない（鍵が nil・作る口も呼ばない）
    func testUnavailableDeviceDoesNothing() async {
        UserDefaults.standard.set("off", forKey: OnDeviceAI.modeKey)
        let model = model()
        let calls = Counter()
        model.runPostSuggest = { _, _ in await calls.bump(); return PostSuggest.sample }
        let photo = pending(location: "兼六園")
        model.items = [photo]
        XCTAssertNil(model.postSuggestKey(for: photo), "使えない機種では画面の作る仕組み（task）も動かない")
        await model.loadPostSuggestion(for: photo.id)
        let count = await calls.value
        XCTAssertEqual(count, 0)
        XCTAssertEqual(model.titleSuggestions(for: photo), [])
        XCTAssertNil(model.captionSuggestion(for: photo))
        XCTAssertEqual(model.suggestedTags, [])
    }

    /// 材料（撮影地）が同じなら作り直さない。変われば作り直す
    func testRegeneratesOnlyWhenMaterialChanges() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let model = model()
        let calls = Counter()
        model.runPostSuggest = { input, _ in
            await calls.bump()
            return PostSuggest.Result(titles: ["\(input.place)の朝"], caption: nil, tags: ["朝", "金沢"])
        }
        let photo = pending(location: "兼六園", takenOn: "2026-11-03",
                            exif: ExifFields(dateTimeOriginal: "2026:11:03 07:10:00"))
        model.items = [photo]
        await model.loadPostSuggestion(for: photo.id)
        await model.loadPostSuggestion(for: photo.id)
        var count = await calls.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.postSuggestInput(for: model.items[0]).takenHour, 7, "撮った時を材料に入れる")
        model.items[0].location = "金沢城"
        await model.loadPostSuggestion(for: photo.id)
        count = await calls.value
        XCTAssertEqual(count, 2)
        XCTAssertEqual(model.titleSuggestions(for: model.items[0]), ["金沢城の朝"])
        XCTAssertEqual(model.suggestedTags, ["朝"], "選択肢に無いタグ（金沢）は札に出さない")
    }

    /// 結んだ観光スポットの名前を材料に入れる
    func testPickedSpotIsMaterial() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let model = model()
        var photo = pending(location: "兼六園, 石川")
        photo.pickedSpot = UploadSpotTarget(spotId: "kenrokuen", name: "兼六園", coords: nil)
        model.items = [photo]
        XCTAssertEqual(model.postSuggestInput(for: photo).spotName, "兼六園")
    }

    /// 候補の札が出た・消えたときに打っている欄へ送るか（#607 と同じ。下の札だけなら送らない）
    func testScrollOnlyWhenCandidatesAboveFocusedFieldChange() async {
        let a = UUID(), b = UUID()
        let before = UploadDetails.suggestLayoutRows(id: a, titles: 0, caption: false)
            + UploadDetails.suggestLayoutRows(id: b, titles: 0, caption: false)
        let titlesAppear = UploadDetails.suggestLayoutRows(id: a, titles: 3, caption: false)
            + UploadDetails.suggestLayoutRows(id: b, titles: 0, caption: false)
        XCTAssertFalse(UploadDetails.suggestMovesFocusedField(old: before, new: titlesAppear, focused: .title(a)),
                       "題を打っている写真の題の候補は題の欄より下（送らない）")
        XCTAssertTrue(UploadDetails.suggestMovesFocusedField(old: before, new: titlesAppear, focused: .caption(a)),
                      "説明を打っている写真の題の候補は説明の欄より上（送る）")
        XCTAssertTrue(UploadDetails.suggestMovesFocusedField(old: before, new: titlesAppear, focused: .title(b)),
                      "前の写真の候補は次の写真の欄より上（送る）")
        let captionAppears = UploadDetails.suggestLayoutRows(id: a, titles: 0, caption: true)
            + UploadDetails.suggestLayoutRows(id: b, titles: 0, caption: false)
        XCTAssertFalse(UploadDetails.suggestMovesFocusedField(old: before, new: captionAppears, focused: .caption(a)))
        XCTAssertFalse(UploadDetails.suggestMovesFocusedField(old: before, new: before, focused: .caption(b)))
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
