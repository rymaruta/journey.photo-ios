import XCTest
@testable import JourneyPhoto

/// **他人の写真は、その人のもの**（CLAUDE.md・2026-11-12 owner・絶対・#577）を、機能を足しても機械で守る見張り
/// （2026-11-23 owner「守れていた、ではなく守れるように」）。
///
/// 名前ではなく**形**で探し（`OthersPhotoGuardScan`）、見つけた所を下の一覧（ファイルと理由）と突き合わせる。
/// 一覧に無い所が増えたら落ちる。一覧にあるのに見つからなくなった所も落ちる（古い許しを残さない）。
///
/// 1. 画像を外へ出す道（保存・画像の共有・ドラッグ・画像のコピー・ファイルの書き出し・元画像への直リンク）
/// 2. 画像を作る所（カード・絵・書き出し）。旅行プランの写真の札・スタンプ帳・「この色の写真」のカードのように、
///    新しい絵を作る機能は必ずここに引っかかる
/// 3. 写真を指す欄を持つ「保存・送信する型」（`Codable` / `Encodable`）。旅行プランの写真（`TripStopPhotoSlot`）・
///    スタンプ帳の札・友達の行きたい場所の札のように、写真を自分の物に入れる型は必ずここに引っかかる
/// 4. 写真の画像の中身（バイト）を通信で取る所
/// 5. 写真の画像を自分の物へ入れる入口（ストーリー・共有カード・編集・旅の一冊）は、`PhotoOwnership` を通る
///
/// **一覧に足すときは、人の写真で動かないことを確かめてから、理由を書く。** 自分の物へ入れる道なら
/// `PhotoOwnership.isMine` を通してから作る。確かめ役（`/review`）はこの一覧の増減を必ず見る。
/// リンク（ページの URL）の共有・DM で写真を引用して送るのは持ち主の写真へ連れて行くだけなので許す
final class OthersPhotoExportGuardTests: XCTestCase {

    private static let sourcesRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")

    private static var cached: [OthersPhotoGuardScan.Source]?
    private func sources() throws -> [OthersPhotoGuardScan.Source] {
        if let cached = Self.cached { return cached }
        let loaded = try OthersPhotoGuardScan.load(root: Self.sourcesRoot)
        XCTAssertGreaterThan(loaded.count, 100, "Sources を読めていない")
        Self.cached = loaded
        return loaded
    }

    // MARK: - 1. 画像を外へ出す道

    /// ファイル → 許す道と理由
    static let allowedExits: [String: (rules: Set<String>, why: String)] = [
        "Features/Common/ShareSheet.swift": (["shareSheet", "pasteboardImage"],
            "共有シートの部品そのもの。貼り付けに入れるのは文だけ"),
        "Features/Common/SignatureShareCardSheet.swift": (["shareSheet"],
            "共有カード。開くのは自分の写真だけ（`PhotoDetailRules.showsSocialCard` → `SocialShareSheet`、投稿した直後の `PostedShareCard`）"),
        "Features/Common/TravelStorySheet.swift": (["shareSheet", "pasteboardImage"],
            "旅をストーリーにの絵。自分の写真（`SocialShareSheet`）と自分の一冊（`TripBook.canShare(_:isMine:)`）からだけ開く"),
        "Features/Upload/CameraPicker.swift": (["photoLibrary"], "自分で撮った写真を端末に残す"),
        "Features/Spots/ComposeCamera.swift": (["photoLibrary"], "自分で撮った写真を端末に残す"),
        "Features/Stories/StoryCameraView.swift": (["photoLibrary"], "自分で撮った動画を端末に残す"),
        "Features/Trips/TripBookView.swift": (["shareLink"], "自分の一冊だけ（`TripBook.canShare(_:isMine:)`・`isMine` は既定なし）"),
        "Features/Trips/TripPlanDetailView.swift": (["drag"], "旅行プランの行の並べ替え（画像ではない）"),
        "Services/StoryVideoPipeline.swift": (["transferableExport"], "写真選びから動画を受け取る型（読み込みだけに使う）"),
        // ここから下はリンク（ページの URL）か文だけ。持ち主の写真・ページへ連れて行くだけ
        "Features/Albums/AlbumsView.swift": (["shareLink"], "アルバムの招待のリンク"),
        "Features/Common/SendSheet.swift": (["shareLink"], "写真のページのリンクと文（画像は渡さない）"),
        "Features/Gallery/CollectionPhotosScreen.swift": (["shareLink"], "まとめの題・件数・リンクの文"),
        "Features/Gallery/DailyQuizView.swift": (["shareLink"], "クイズの結果の文"),
        "Features/PhotoDetail/PhotoViewerView.swift": (["shareLink"], "写真のページのリンク（`shareURL`）"),
        "Features/Profile/ProfileQRView.swift": (["shareLink"], "プロフィールのリンク"),
        "Features/Profile/UserProfileView.swift": (["shareLink"], "プロフィールのリンク"),
        "Features/Spots/OfficialSpotView.swift": (["shareLink"], "観光スポットのページの文とリンク"),
        "Features/Spots/SpotDetailView.swift": (["shareLink"], "撮影地のページの文とリンク"),
        "Features/Trips/TripShareViews.swift": (["shareLink"], "旅の共有のリンク"),
        "Features/Trunk/LabelArrivedView.swift": (["shareLink"], "自分の写真のページのリンク（`PhotoLink.url`）"),
    ]

    func testImageExitsOnlyWhereAllowed() throws {
        let found = OthersPhotoGuardScan.exits(in: try sources())
        var unexpected: [String] = []
        for (path, rules) in found {
            let extra = rules.subtracting(Self.allowedExits[path]?.rules ?? [])
            if !extra.isEmpty { unexpected.append("\(path): \(extra.sorted().joined(separator: ","))") }
        }
        XCTAssertEqual(unexpected.sorted(), [],
                       "画像を外へ出す道が増えた。人の写真で出ないことを確かめてから、理由と一緒に一覧に足す（CLAUDE.md「他人の写真は、その人のもの」）")
        let stale = Self.allowedExits.compactMap { path, entry in
            entry.rules.isSubset(of: found[path] ?? []) ? nil : path
        }
        XCTAssertEqual(stale.sorted(), [], "一覧にあるのに見つからない（消したなら一覧からも消す）")
    }

    /// 元画像（`src` など）の URL を、共有・コピー・ブラウザへそのまま出す行は、どこにも置かない
    func testNoRawImageURLLeavesTheApp() throws {
        XCTAssertEqual(OthersPhotoGuardScan.rawImageURLExits(in: try sources()), [],
                       "写真の画像の URL を外へ出している。共有するのはページのリンク（`PhotoLink`）にする")
    }

    // MARK: - 2. 画像を作る所

    /// ファイル → 理由。**写真（人のものになりうる）を描くのは「自分の」と書いたものだけ**
    static let imageMakers: [String: String] = [
        // 写真を描く（自分の写真だけ。入口は 5. の見張り）
        "Services/SignatureShareCardRenderer.swift": "共有カード。自分の写真だけ（`PhotoDetailRules.showsSocialCard`・投稿直後）",
        "Services/SignatureShareCardStyles.swift": "共有カードの型（同上）",
        "Services/SignatureShareCardNewStyles.swift": "共有カードの型（同上）",
        "Services/SignatureShareCardMoreStyles.swift": "共有カードの型（同上）",
        "Services/KoyomiCardRenderer.swift": "共有の絵「暦」（共有カード・旅をストーリーにから。同上）",
        "Services/MagazineCardRenderer.swift": "共有の絵「雑誌」（同上）",
        "Services/PhotoColorCardRenderer.swift": "共有の絵「写真の色」（同上）",
        "Services/SharedPhotoStoryCard.swift": "写真を紹介するストーリーの絵。自分の写真だけ（`SendSheetLayout.canShareToStory`）",
        "Services/TravelStoryRenderer.swift": "旅をストーリーにの絵。自分の写真と自分の一冊だけ",
        "Services/TripBookCardRenderer.swift": "旅の一冊の絵。自分の一冊だけ（`TripBook.canShare(_:isMine:)`）",
        "Services/TextOverlayRenderer.swift": "ストーリーの文字を、作っている自分のストーリーに焼き込む",
        "Services/SongStickerPainter.swift": "曲の札の形（写真ではない）",
        "Services/StoryVideoPipeline.swift": "自分のストーリーの動画の書き出し",
        "Services/ImagePreparer.swift": "自分が選んだ・撮った写真を上げる形に整える（EXIF を落とす）",
        "Features/Profile/ProfileImageFromPhoto.swift": "自分の写真をアイコン・カバーにする（候補は `myPhotos`）",
        "Features/Profile/CoverCropMath.swift": "自分のカバーの切り抜き",
        "Features/Stories/StoryComposerView.swift": "作っている自分のストーリーの絵",
        "Features/Stories/YearAgoStoryView.swift": "端末の自分の写真（1年前）",
        "Features/Stories/StoryCameraView.swift": "自分で撮った写真",
        "Features/Spots/ComposeCamera.swift": "自分で撮った写真",
        "Features/Upload/CameraPicker.swift": "自分で撮った写真",
        "Features/Upload/UploadViewModel.swift": "自分が上げる写真",
        "Features/Trips/OfflineTripLive.swift": "電波なしで使う旅の材料（地図・作例）をアプリの中にだけ置く（外へは出さない）",
        // 写真を描かない（飾り・計測）
        "Features/Pro/SupporterCardTextures.swift": "サポーター証の貼り絵（写真ではない）",
        "Features/Profile/MedalTextures.swift": "硬貨の貼り絵（写真ではない）",
        "Features/Profile/MedalViewerView.swift": "硬貨の貼り絵（写真ではない）",
        "Features/Trunk/TrunkOpenView.swift": "トランクの絵（写真ではない）",
        "Features/Trunk/TrunkPerfMeter.swift": "表示の刻みの計測（写真ではない）",
        "Features/Trunk/TrunkSpinDiskCache.swift": "回すトランクの絵の置き場（写真ではない）",
        "Features/Trunk/TrunkSpinViewer.swift": "トランクの絵（写真ではない）",
        // Debug の見本（画面写真の試験だけ）
        "Features/Common/KoyomiGalleryPreview.swift": "Debug の見本",
        "Features/Common/PhotoColorGalleryPreview.swift": "Debug の見本",
        "Features/Common/ShareCardGalleryPreview.swift": "Debug の見本",
        "Features/Drafts/PreviewDraftsSample.swift": "Debug の見本",
        "Features/Stories/PreviewStorySample.swift": "Debug の見本",
        "Features/Upload/PreviewUploadSample.swift": "Debug の見本",
    ]

    func testImageMakingOnlyInRegisteredFiles() throws {
        let found = OthersPhotoGuardScan.imageMakers(in: try sources())
        XCTAssertEqual(found.subtracting(Self.imageMakers.keys).sorted(), [],
                       "画像を作る所が増えた。人の写真を描かないこと（描くなら `PhotoOwnership.isMine` を通った入口からだけ）を確かめて一覧に足す")
        XCTAssertEqual(Set(Self.imageMakers.keys).subtracting(found).sorted(), [], "一覧にあるのに見つからない")
    }

    // MARK: - 3. 写真を指す欄を持つ「保存・送信する型」

    /// `ファイル#型` → 理由
    static let photoHoldingTypes: [String: String] = [
        // 自分の写真・自分で作る物だけ
        "Core/Storage/StoryDraftStore.swift#Draft": "自分のストーリーの下書き（端末の画像ファイル）",
        "Core/Storage/StoryDraftStore.swift#Shot": "自分のストーリーの1枚。`sharedPhotoId` は自分の写真だけ（`SendSheetLayout.canShareToStory`・サーバーも 403）",
        "Core/Storage/StoryUploadCenter.swift#Entry": "同上（上げる途中の控え）",
        "Services/StoryService.swift#Body": "同上（ストーリーを上げる本文）",
        "Core/Storage/UploadDraftStore.swift#Item": "自分の投稿の下書き",
        "Services/UploadService.swift#SaveBody": "自分の写真を上げる本文",
        "Services/PhotoService.swift#Replace": "自分の写真の差し替え（サーバーが持ち主を確かめる）",
        "Services/ProfileService.swift#ProfilePatch": "自分の写真をプロフィールの先頭に留める（サーバーが持ち主を確かめる）",
        "Services/HighlightService.swift#Body": "自分のストーリーをハイライトの表紙に",
        "Core/Text/DevelopTrips.swift#DevelopProgress": "端末の自分の旅の表紙",
        "Core/Text/PassBook.swift#PassSettings": "すれちがいの札の写真。自分の公開写真だけ（`PassCardPickView.pick` が `PhotoOwnership.mine`）",
        // 人の写真を id で指すだけ（画像は持たない。持ち主が消す・非公開にすると見えなくなる）
        "Services/DMService.swift#Body": "DM で写真を引用して送る（持ち主の写真へ連れて行くだけ）",
        "Services/GroupService.swift#Body": "グループで写真を引用して送る（同上）",
        "Core/Text/PassBook.swift#PassEncounter": "すれちがった相手の札（相手が自分で選んだ公開写真の id）",
        "Models/TheirTrunk.swift#TrunkTicket": "相手のトランクの札（相手の公開写真の id）",
        "Core/AI/AskAnswer.swift#AskAnswer": "AI の答えに並べる公開写真の id（見せるだけ）",
        "Core/Text/FriendWish.swift#State": "友達が行きたい場所で撮った札の、今日出した1枚の id を端末に控えるだけ（同じ日は同じ札を出す印。画像は持たず、開くのは持ち主の写真・札 #710 の案9・2026-11-23 統合で足した）",
        "Core/Text/InspiredBy.swift#Pick": "「この写真から」の候補の縮小画像の URL（アプリの中で見せるだけ）",
        "Services/FeedbackService.swift#Body": "ご意見に、見ていた写真の公開の情報を添える（運営へ送るだけ）",
        // 写真ではない
        "Models/Photo.swift#Song": "曲のジャケット（写真ではない）",
    ]

    func testPhotoHoldingTypesAreRegistered() throws {
        let found = OthersPhotoGuardScan.photoHoldingTypes(in: try sources())
        let unexpected = found.filter { Self.photoHoldingTypes[$0.key] == nil }.map { "\($0.key) \($0.value)" }
        XCTAssertEqual(unexpected.sorted(), [],
                       "写真を指す欄を持つ保存・送信の型が増えた。人の写真の画像を自分の物に入れない（入れるのは `PhotoOwnership.isMine` を通った自分の写真だけ、"
                       + "人の写真は id で持ち主の写真へ連れて行くだけ）ことを確かめて一覧に足す")
        XCTAssertEqual(Set(Self.photoHoldingTypes.keys).subtracting(found.keys).sorted(), [], "一覧にあるのに見つからない")
    }

    /// 辞書で組む本文に、写真を指す鍵を書いているファイル → 理由
    static let photoKeysInBodies: [String: String] = [
        "Services/ProfileService.swift": "自分のアイコン・カバーを上げる",
        "Services/StoryService.swift": "自分のストーリーの画像を上げる",
        "Services/ImagePreparer.swift": "自分の写真を上げる形にする",
        "Features/Profile/ProfileImageFromPhoto.swift": "自分のカバーを上げる",
        "Core/Text/DirectMessages.swift": "サーバーの断りの種類（`photoNotFound` など・送る本文ではない）",
        "Core/Text/Labels.swift": "カテゴリの表示名（送る本文ではない）",
        "Core/Text/InspiredBy.swift": "公開写真を読む見本の行（送らない）",
        "Core/Text/FirstMoments.swift": "公開写真を読む見本の行（送らない）",
        "Features/Upload/PostPreview.swift": "投稿の見え方の見本の行（送らない）",
        "Core/Auth/PreviewSession.swift": "Debug の見本",
        "Core/Networking/PreviewBackend.swift": "Debug の見本",
        "Core/Text/PreviewSNSLoopSample.swift": "Debug の見本",
    ]

    func testPhotoKeysInRequestBodiesAreRegistered() throws {
        let found = OthersPhotoGuardScan.photoKeysInBodies(in: try sources())
        XCTAssertEqual(found.subtracting(Self.photoKeysInBodies.keys).sorted(), [],
                       "写真を指す鍵を本文に書く所が増えた。人の写真を自分の物に入れていないか確かめて一覧に足す")
        XCTAssertEqual(Set(Self.photoKeysInBodies.keys).subtracting(found).sorted(), [], "一覧にあるのに見つからない")
    }

    // MARK: - 4. 写真の画像の中身を通信で取る所

    static let imageFetchers: [String: String] = [
        "Services/TripBookCardRenderer.swift": "画像の中身を取る口（`coverData`）。呼ぶ所は 5. で見張る",
        "Features/Profile/ProfileImageFromPhoto.swift": "自分の写真の中身を取る口（`download`）",
        "Features/Profile/PhotoRecolor.swift": "自分の写真の色の編集の元（`fetchSource`）",
        "Features/PhotoDetail/PhotoDetailView.swift": "共有カード・ストーリーの絵。持ち主のときだけ（`showsSocialCard`・`canShareToStory`）",
        "Features/Gallery/PhotoLiftOverlay.swift": "手に取った写真をストーリーへ。自分の写真だけ（`PhotoOwnership.isMine`）",
        "Features/Common/SignatureShareCardSheet.swift": "持ち主の顔（アイコン）を共有カードに載せる。カードは自分の写真だけ",
        "Features/Common/TravelStorySheet.swift": "旅をストーリーにの写真。自分の写真と自分の一冊だけ",
        "Features/Trips/TripBookView.swift": "旅の一冊の絵。自分の一冊だけ（`TripBook.canShare(_:isMine:)`）",
        "Features/Profile/AvatarCropView.swift": "自分の写真をアイコンに（候補は `ProfileImageFromPhoto.myPhotos`）",
        "Features/Profile/ProfileEditView.swift": "自分の写真をカバーに（候補は `ProfileImageFromPhoto.myPhotos`）",
        "Features/Profile/EditPhotoView.swift": "自分の写真の編集（写真の詳細で `isMine` のときだけ開く）",
        "Features/Stories/StoryComposerView.swift": "自分のストーリーの絵（`StoryFilterRenderer.coverData`・名前が同じだけ）",
        "Features/Stories/StoryViewerView.swift": "次のストーリーの先読み（見せるだけ）",
        "Features/Stories/SongStickerView.swift": "曲のジャケット（写真ではない）",
        "Features/Common/DownsampledRemoteImage.swift": "一覧の縮小画像を見せるだけ（外へ出さない）",
        "Features/Trips/OfflineTripLive.swift": "電波なしで使う旅の材料をアプリの中にだけ置く",
        "Services/DailyQuizService.swift": "クイズの JSON",
        "Services/OfficialSpotService.swift": "観光スポットの JSON・本文",
        "Services/SpotWantsService.swift": "みんなの行きたいの JSON",
        "Core/Networking/PreviewBackend.swift": "Debug の見本",
    ]

    func testImageFetchOnlyInRegisteredFiles() throws {
        let found = OthersPhotoGuardScan.imageFetchers(in: try sources())
        XCTAssertEqual(found.subtracting(Self.imageFetchers.keys).sorted(), [],
                       "通信で中身を取る所が増えた。人の写真の画像を取って自分の物に入れていないか確かめて一覧に足す")
        XCTAssertEqual(Set(Self.imageFetchers.keys).subtracting(found).sorted(), [], "一覧にあるのに見つからない")
    }

    // MARK: - 5. 写真の画像を自分の物へ入れる入口は、持ち主かを確かめる

    enum Gate {
        /// このファイルに、この呼び出しが必ずある（持ち主かを確かめる所）
        case calls(String)
        /// 持ち主の確かめは呼び手が持つ（呼び手もこの一覧で見張る）。理由を書く
        case upstream(String)
    }

    /// 入口 → それを使ってよいファイル → 確かめ方
    static let ownOnlySinks: [String: [String: Gate]] = [
        "StoryComposerSeed(": [
            "Features/Gallery/PhotoLiftOverlay.swift": .calls("PhotoOwnership.isMine("),
            "Features/Stories/StoriesRow.swift": .upstream("端末の自分の写真（1年前）"),
        ],
        "StoryShareSeed(": [
            "Features/PhotoDetail/PhotoDetailView.swift": .calls("SendSheetLayout.canShareToStory("),
            "Features/Common/SignatureShareCardSheet.swift": .upstream("`SocialShareSheet(` と `PostedShareCard` からだけ開く（どちらも下で見張る）"),
        ],
        "SocialShareSheet(": [
            "Features/PhotoDetail/PhotoDetailView.swift": .calls("PhotoDetailRules.showsSocialCard("),
        ],
        "SignatureShareCardSheet(": [
            "Features/Common/SocialShareSheet.swift": .upstream("`SocialShareSheet(` の入口で見張る"),
            "Features/Upload/PostedShareCard.swift": .upstream("投稿した直後の自分の写真"),
        ],
        "PostedShareCard(": [
            "Features/Upload/UploadViewModel.swift": .upstream("投稿した直後の自分の写真"),
        ],
        "TravelStorySheet(": [
            "Features/Common/SocialShareSheet.swift": .upstream("`SocialShareSheet(` の入口で見張る"),
            "Features/Trips/TripBookView.swift": .calls("TripBook.canShare("),
        ],
        "SharedPhotoStoryCard.render(": [
            "Features/PhotoDetail/PhotoDetailView.swift": .calls("SendSheetLayout.canShareToStory("),
            "Features/Common/SignatureShareCardSheet.swift": .upstream("`SignatureShareCardSheet(` の入口で見張る"),
        ],
        "TripBookCardRenderer.coverData(": [
            "Features/PhotoDetail/PhotoDetailView.swift": .calls("PhotoDetailRules.showsSocialCard("),
            "Features/Trips/TripBookView.swift": .calls("TripBook.canShare("),
            "Features/Common/TravelStorySheet.swift": .upstream("`TravelStorySheet(` の入口で見張る"),
        ],
        "EditPhotoView(": [
            "Features/PhotoDetail/PhotoDetailView.swift": .calls("PhotoOwnership.isMine("),
            "Features/Stories/StoryViewerView.swift": .upstream("自分のストーリーから「写真にしました」で作った自分の写真"),
        ],
        "ProfileImageFromPhoto.download(": [
            "Features/Profile/AvatarCropView.swift": .upstream("候補は自分の写真（`ProfileImageFromPhoto.myPhotos`）"),
            "Features/Profile/ProfileEditView.swift": .calls("ProfileImageFromPhoto.myPhotos("),
        ],
        "PhotoRecolor.fetchSource(": [
            "Features/Profile/EditPhotoView.swift": .upstream("`EditPhotoView(` の入口で見張る"),
        ],
        // 開く側が「自分の一冊か」を必ず書く（既定の値を置かない・2026-11-23）
        "TripBookView(": [
            "Features/Gallery/HomeTopCardView.swift": .calls("isMine: true"),
            "Features/Profile/TravelRecordSection.swift": .calls("isMine: false"),
            "Features/Trips/TripShelf.swift": .calls("isMine: isMine"),
            "Features/Trips/TripPlansView.swift": .calls("isMine: true"),
        ],
    ]

    func testOwnOnlySinksAreGated() throws {
        let all = try sources()
        for (sink, allowed) in Self.ownOnlySinks {
            let users = OthersPhotoGuardScan.users(of: sink, in: all)
            XCTAssertEqual(users.subtracting(allowed.keys).sorted(), [],
                           "写真の画像を自分の物へ入れる入口 `\(sink)` を使う所が増えた。`PhotoOwnership.isMine` を通してから一覧に足す")
            XCTAssertEqual(Set(allowed.keys).subtracting(users).sorted(), [], "`\(sink)` の一覧にあるのに使っていない")
            for (path, gate) in allowed {
                guard case .calls(let token) = gate,
                      let source = all.first(where: { $0.path == path }) else { continue }
                XCTAssertTrue(source.code.contains(token), "\(path) が `\(sink)` の前に `\(token)` で持ち主を確かめていない")
            }
        }
    }

    /// 持ち主かを決める関数は、1か所（`PhotoOwnership`）を通す。どれかが自前の比べ方に戻ったら落ちる
    func testOwnershipGatesUsePhotoOwnership() throws {
        let all = try sources()
        let gates: [(path: String, signature: String)] = [
            ("Features/PhotoDetail/PhotoDetailView.swift", "static func showsSocialCard("),
            ("Features/Common/SendSheet.swift", "static func canShareToStory("),
            ("Core/Text/PhotoLift.swift", "static func allowsStory("),
            ("Features/Pass/PassCardPickView.swift", "static func pick("),
            ("Features/Profile/ProfileImageFromPhoto.swift", "static func myPhotos("),
        ]
        for gate in gates {
            let code = try XCTUnwrap(all.first { $0.path == gate.path }?.code, gate.path)
            let body = try XCTUnwrap(OthersPhotoGuardScan.functionBody(code, signature: gate.signature),
                                     "\(gate.path) に \(gate.signature) が無い")
            XCTAssertTrue(body.contains("PhotoOwnership."), "\(gate.path) の \(gate.signature) が `PhotoOwnership` を通っていない")
        }
        // 写真の詳細の「自分の写真か」も同じ所
        let detail = try XCTUnwrap(all.first { $0.path == "Features/PhotoDetail/PhotoDetailView.swift" }?.code)
        XCTAssertTrue(detail.contains("private var isMine: Bool { PhotoOwnership.isMine(photo: current, me: auth.userId) }"))
    }

    /// 写真の詳細の「SNS に載せる」（共有カード）と「ストーリーに載せる」は、持ち主かを確かめてから作る
    func testPhotoDetailChecksOwnerBeforeMakingImages() throws {
        let code = try XCTUnwrap(try sources().first { $0.path == "Features/PhotoDetail/PhotoDetailView.swift" }?.code)
        func body(of name: String) -> Substring? {
            guard let start = code.range(of: "private func \(name)() async {") else { return nil }
            return code[start.upperBound...].prefix(900)
        }
        XCTAssertTrue(body(of: "prepareThreads")?.contains("PhotoDetailRules.showsSocialCard(") == true,
                      "共有カードの画像を、持ち主かを確かめずに作っている")
        XCTAssertTrue(body(of: "prepareStory")?.contains("SendSheetLayout.canShareToStory(") == true,
                      "ストーリーの絵を、持ち主かを確かめずに作っている")
    }

    // MARK: - 見張りそのものが効いているか（わざと破った見本を当てる）

    /// 決まりを破る見本を、見張りが見つけること。見張りを緩めたら落ちる
    func testScannerCatchesPlantedViolations() {
        func src(_ path: String, _ code: String) -> OthersPhotoGuardScan.Source {
            .init(path: path, code: OthersPhotoGuardScan.stripComments(code))
        }
        let planted = [
            src("A.swift", "UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)"),
            src("B.swift", "UIPasteboard.general.image = image"),
            src("C.swift", "Image(uiImage: ui).draggable(Image(uiImage: ui))"),
            src("D.swift", "ShareLink(item: Image(uiImage: ui), preview: SharePreview(\"x\", image: Image(uiImage: ui)))"),
            src("E.swift", "let p = NSItemProvider(object: image)"),
            src("F.swift", ".contextMenu {\n Button(L(\"画像を保存\", \"Save image\")) { }\n}"),
            src("G.swift", "struct PhotoFile: Transferable {\n static var transferRepresentation: some TransferRepresentation { DataRepresentation(exportedContentType: .jpeg) { $0.data } }\n}"),
            src("H.swift", "view.fileExporter(isPresented: $x, document: doc, contentType: .jpeg) { _ in }"),
            src("I.swift", "try PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset() }"),
            src("J.swift", "UIPasteboard.general.setData(data, forPasteboardType: \"public.jpeg\")"),
        ]
        let exits = OthersPhotoGuardScan.exits(in: planted)
        XCTAssertEqual(Set(exits.keys), Set(planted.map(\.path)), "見張りが見落とした: \(Set(planted.map(\.path)).subtracting(exits.keys).sorted())")

        // 注釈の中の名前・文のコピーは引っかけない
        let quiet = [
            src("Q1.swift", "// UIActivityViewController に画像を渡す（注釈）\nUIPasteboard.general.string = url.absoluteString"),
            src("Q2.swift", ".contextMenu {\n Button(L(\"コピー\", \"Copy\")) { UIPasteboard.general.string = text }\n}"),
            src("Q3.swift", "let data = try await item.loadTransferable(type: Data.self)"),
        ]
        XCTAssertEqual(OthersPhotoGuardScan.exits(in: quiet), [:])

        // 元画像への直リンク
        XCTAssertEqual(OthersPhotoGuardScan.rawImageURLExits(in: [
            src("R.swift", "ShareLink(item: URL(string: photo.src)!)"),
            src("S.swift", "UIPasteboard.general.string = photo.detailImageURL?.absoluteString"),
            src("T.swift", "openURL(photo.gridImageURL!)"),
        ]), ["R.swift:1", "S.swift:1", "T.swift:1"])

        // 画像を作る新しい所（スタンプ帳・「この色の写真」のカードなど）
        XCTAssertEqual(OthersPhotoGuardScan.imageMakers(in: [
            src("StampCard.swift", "let renderer = UIGraphicsImageRenderer(size: size)"),
            src("ColorCard.swift", "let r = ImageRenderer(content: card)"),
            src("Plain.swift", "let x = 1"),
        ]), ["StampCard.swift", "ColorCard.swift"])

        // 写真を自分の物に入れる型（旅行プランの写真・スタンプ帳・友達の行きたい場所の札）。名前に依らず形で見つける
        let holders = OthersPhotoGuardScan.photoHoldingTypes(in: [
            src("Plan.swift", """
                struct TripStopPhotoSlot: Codable, Equatable {
                    let stopId: String
                    var photoId: String?
                    var imageURL: URL?
                    var hasPhoto: Bool { photoId != nil }
                }
                """),
            src("Stamp.swift", "struct Stamp: Identifiable, Codable { let id: String; let picture: Data }"),
            src("Wish.swift", "final class FriendWishCard: Encodable {\n let spot: String\n let cover: Photo\n}"),
            src("Read.swift", "struct OnlyRead: Decodable { let photoId: String }"),
            src("Computed.swift", "struct Other: Codable {\n let name: String\n var thumbSrc: String? { nil }\n}"),
        ])
        XCTAssertEqual(holders["Plan.swift#TripStopPhotoSlot"], ["photoId: String?", "imageURL: URL?"])
        XCTAssertEqual(holders["Stamp.swift#Stamp"], ["picture: Data"])
        XCTAssertEqual(holders["Wish.swift#FriendWishCard"], ["cover: Photo"])
        XCTAssertNil(holders["Read.swift#OnlyRead"], "読むだけの型は見ない")
        XCTAssertNil(holders["Computed.swift#Other"], "計算するだけの欄は見ない")

        // 写真の中身を通信で取る新しい口（名前に依らない）と、それを呼ぶ所
        let fetch = OthersPhotoGuardScan.imageFetchers(in: [
            src("Loader.swift", "enum StampLoader {\n static func bytes(of url: URL) async -> Data? {\n try? await URLSession.shared.data(from: url).0\n }\n}"),
            src("Caller.swift", "let d = await StampLoader.bytes(of: photo.detailImageURL!)"),
            src("Quiet.swift", "let d = try JSONSerialization.data(withJSONObject: [:])"),
        ])
        XCTAssertEqual(fetch, ["Loader.swift", "Caller.swift"])
    }
}
