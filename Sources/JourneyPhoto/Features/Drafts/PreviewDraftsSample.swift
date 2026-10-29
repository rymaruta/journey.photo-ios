import UIKit

/// 画面写真の試験で下書きの一覧（#400）に並べる見本（`PreviewSession.seedsDraftsSample`・Debug のみ）。
///
/// **アプリに入っている画像を使う**（構図の見本・`Assets.xcassets`）。写真のライブラリにも通信にも頼らない。
/// 端末の下書きの置き場（`UploadDraftStore` / `StoryDraftStore` の `Slot.entry`）にふだんと同じ道で書く。
/// その人の下書きがもう在れば何もしない（試験の中で消した後、次の起動でまた並ぶ）
@MainActor
enum PreviewDraftsSample {

    static let assetNames = ["composition-ai-radial", "composition-ai-goldenSpiral", "composition-ai-horizon",
                             "composition-ai-diagonals", "composition-ai-frameWithin", "composition-ai-halves"]

    static func seedIfNeeded(for userId: String, now: Date = Date()) {
        guard PreviewSession.seedsDraftsSample, !userId.isEmpty,
              DraftLibrary.shared.count(for: userId) == 0 else { return }
        let images = assetNames.compactMap { UIImage(named: $0)?.jpegData(compressionQuality: 0.8) }
        guard images.count == assetNames.count else { return }
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        // 投稿（題・撮影地・枚数）。日時はモックの並び（今日・昨日・数日前）
        let posts: [(title: String, place: String, shots: [Int], ago: TimeInterval)] = [
            (L("朝霧の河童橋", "Kappa Bridge in morning mist"), L("長野県松本市", "Matsumoto, Nagano"), [0, 4, 2], 6 * hour),
            ("", "", [5], 5 * day),
            (L("千本鳥居の夕方", "Torii gates at dusk"), L("京都市伏見区", "Fushimi, Kyoto"), [1, 2, 3, 4, 0], 9 * day),
            (L("棚田の夕暮れ", "Rice terraces at sunset"), L("石川県輪島市", "Wajima, Ishikawa"), [3, 1], 11 * day),
            (L("紅葉の渓谷", "Autumn gorge"), L("青森県十和田市", "Towada, Aomori"), [2], 15 * day),
        ]
        for post in posts {
            let inputs = post.shots.enumerated().map { index, shot in
                UploadDraftStore.ItemInput(imageData: images[shot], item: UploadDraftStore.Item(
                    imageFile: "", fileName: "sample-\(shot).jpg", contentType: "image/jpeg", exif: nil,
                    latitude: nil, longitude: nil, takenOn: nil, dominantColor: nil,
                    title: index == 0 ? post.title : "", caption: "", location: post.place,
                    photoPlaceName: nil, locationClearedByUser: false,
                    pickedLatitude: nil, pickedLongitude: nil, recipe: nil))
            }
            let fields = UploadDraftStore.Draft(
                items: [], tagsText: "", category: "", published: true, audience: "everyone", song: nil,
                selectedAlbumId: nil, groupsAsOnePost: true,
                savedAt: UploadDraftStore.savedAtString(now.addingTimeInterval(-post.ago)))
            UploadDraftStore(slot: .entry(UUID().uuidString)).save(inputs, fields: fields, for: userId)
        }
        // 読めない写真のある下書き（2枚のうち1枚の画像を消す）
        let brokenId = UUID().uuidString
        let broken = UploadDraftStore(slot: .entry(brokenId))
        let brokenInputs = [3, 5].map { shot in
            UploadDraftStore.ItemInput(imageData: images[shot], item: UploadDraftStore.Item(
                imageFile: "", fileName: "sample-\(shot).jpg", contentType: "image/jpeg", exif: nil,
                latitude: nil, longitude: nil, takenOn: nil, dominantColor: nil,
                title: shot == 3 ? L("雲海の城跡", "Castle ruins above the clouds") : "", caption: "",
                location: L("兵庫県朝来市", "Asago, Hyogo"), photoPlaceName: nil, locationClearedByUser: false,
                pickedLatitude: nil, pickedLongitude: nil, recipe: nil))
        }
        let brokenFields = UploadDraftStore.Draft(
            items: [], tagsText: "", category: "", published: true, audience: "everyone", song: nil,
            selectedAlbumId: nil, groupsAsOnePost: true,
            savedAt: UploadDraftStore.savedAtString(now.addingTimeInterval(-17 * day)))
        if broken.save(brokenInputs, fields: brokenFields, for: userId),
           let last = broken.draft(for: userId)?.items.last {
            try? FileManager.default.removeItem(at: broken.imageURL(last))
        }
        // ストーリー（1件は期限が近い——あと1日）
        let stories: [(text: String, shots: [Int], ago: TimeInterval)] = [
            (L("夜の運河", "Canal at night"), [2, 4], 6 * day + 2 * hour),
            (L("海まで歩く", "Walk to the sea"), [5], 2 * day),
        ]
        for story in stories {
            let inputs = story.shots.enumerated().map { index, shot in
                StoryDraftStore.ShotInput(
                    imageData: images[shot], fileName: "sample-\(shot).jpg", contentType: "image/jpeg", coords: nil,
                    overlays: index == 0 ? [TextOverlay(text: story.text)] : [])
            }
            let store = StoryDraftStore(slot: .entry(UUID().uuidString))
            store.bind(userId: userId)
            store.save(shots: inputs, caption: "", location: "", song: nil, durationSec: 5,
                       savedAt: DraftLibrary.storyStamp(now.addingTimeInterval(-story.ago)))
        }
        DraftLibrary.shared.noteChanged()
    }
}
