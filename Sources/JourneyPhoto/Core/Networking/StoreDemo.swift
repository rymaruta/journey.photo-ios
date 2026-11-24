import Foundation

// Linux では URLSession・URLProtocol が別モジュールに居る（`PreviewBackend` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UIKit)
import UIKit
#endif

/// **App Store の画面写真のための見本の表示**（Debug のみ・`-JPStoreDemo YES`・2026-11-23 札 #604）。
///
/// ストアの絵に、本番の他の利用者の写真や他の作者の作例を1枚も写さない（CLAUDE.md「他人の写真は、その人のもの」・絶対）。
/// 画面・ViewModel・Service は本物の道をそのまま通り、通信の向こう側だけを端末の中で答える（`PreviewBackend` を使い回す）:
///
/// - **画像はアプリに入っている構図の作例写真だけ**（`Assets.xcassets` の `composition-ai-*`）。出典と許諾は
///   `Tools/composition-examples/photo-sources.json`（どれも CC0。クレジット不要・商用可）。2026-11-23 owner「写真ないので見本でお願い」
///   で、運営の写真の束（非公開の S3）を取りに行く形はやめた。画像の URL は `https://store-demo.invalid/photo/<名前>.jpg`
///   （`.invalid` は外へ出ない名前）で、答え手が同梱の画像を返す
/// - **アプリの URLSession からはネットワークを読まない。** 見本の間は、アプリの全部の URLSession（`URLSession.shared` と、
///   設定から作るもの＝`guarded(_:)` を通したもの）の要求を `PreviewBackendProtocol` が引き受け、ここで答えるか断る。
///   画像の入口（`DownsampledRemoteImage`・`RemoteImage`・`AsyncImage(url:)`）でも、見本の置き場でない URL は読まない（`allowsImage`）。2段で守る。
///   **URLSession を通らない通信は止められない**: Amplify（aws-crt の自前の HTTP・ログインの設定の読み込み）、地図のタイル（MapKit）、
///   WeatherKit などの OS の部品。どれも利用者の写真は運ばない（画像はここの見張りを通る URL しか描かない）
/// - 文は作った見本（利用者名は実在の人を思わせない作った名前）。場所の名前は、写真の出典に書かれた実際の場所と合うものだけ
///   （合わない写真は場所名なしの投稿）
/// - **見た目は実機と同じ**（2026-11-23 owner「ちゃんと実機通りのスクショかも見ないといけない。イメージで作るのはダメ」）。
///   変えるのはデータだけで、画面の部品は見本の間も本物と同じに描く（作例の出典の行も、同梱の写真の本当の作者と許諾で出る）。
///   画面の側で `StoreDemo` を見てよいのは、画像を読む道（`allowsImage`・`imageURL`・`StoreDemoImages`）と見本の曲名だけ
///   （`StoreDemoTests.testScreensLookTheSameInDemo` が見張る）
///
/// 🔴 **Release には中身を入れない**（`PreviewBackend` と同じ）。見本の文・答え手は `#if DEBUG` の内側だけで、Release の
/// `isOn` はいつも false、`allowsImage` はいつも true、`guarded` は何もしない
enum StoreDemo {

    /// 起動の引数の鍵（`-JPStoreDemo YES`）
    static let key = "JPStoreDemo"
    /// 見本の画像の置き場（外へ出ない名前）
    static let host = "store-demo.invalid"
    /// 見本の間に画像を読んでよい置き場（見本の画像と、見本の通信の投稿の本体 `PreviewBackend.host`）
    static let localImageHosts: Set<String> = [host, "preview-local.invalid"]

    /// 見本の表示か（Debug のみ・Release はいつも false）
    static var isOn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }

    /// **この画像の URL を読んでよいか**（画像の入口の見張り）。見本でなければいつも true（本番の動きは変えない）。
    /// 見本の間は、見本の置き場・端末の中のファイル・data: だけ。ほかの URL（本番の写真・Commons・曲のジャケット）は読まない
    static func allowsImage(_ url: URL?) -> Bool { allowsImage(url, demo: isOn) }

    /// 見本の置き場の画像の中身（同梱の写真）。見本でない・見本の置き場でない・見本の一覧に無い名前は nil。
    /// `RemoteImage`（中身は `AsyncImage`）が使う（2026-11-23・Mac run 1736）: `AsyncImage` は `URLProtocol.registerClass` の
    /// 答え手を通らず、見本の URL（`.invalid`）を外へ読みに行って失敗し、写真の詳細・観光スポットの頁の上の絵・DM の写真が
    /// 読み込み中のままだった。見本の画像は通信せずにここから描く（見張りは変えない・外へは出さない）
    static func localImageData(for url: URL?) -> Data? {
        #if DEBUG
        guard isOn, let url, let asset = asset(in: url) else { return nil }
        return loadAsset(asset)
        #else
        return nil
        #endif
    }

    /// 見本の曲の名前（ストーリーの曲の札・見る画面の名前の下の行）。**場所を言わない名前**（どの写真に付いても食い違わない・
    /// Mac run 1736 で「夜明けの港で…」が森の線路の写真に付いていた）。見本でなければ nil（今までの曲名）
    static var songTitle: String? {
        #if DEBUG
        return isOn ? "ゆっくり遠回りして帰ろう（Long Version）" : nil
        #else
        return nil
        #endif
    }

    /// AI に頼むの絵で頼む言葉（UI テスト `testStoreDemoAsk` と単体テストが同じ言葉を使う）
    static let askQuestion = "京都で写真がきれいに撮れる所を教えて"

    /// 画像に渡す URL（`AsyncImage(url:)` に直に渡す所が使う）。見本の間に読んではいけない URL は nil（URL の無い写真と同じ姿）
    static func imageURL(_ url: URL?) -> URL? { allowsImage(url) ? url : nil }

    static func allowsImage(_ url: URL?, demo: Bool) -> Bool {
        guard demo, let url else { return true }
        if url.isFileURL || url.scheme == "data" { return true }
        guard url.scheme == "https" || url.scheme == "http", let host = url.host else { return false }
        return localImageHosts.contains(host)
    }

    /// 設定から作る URLSession を、見本の間だけ端末の中の答え手に向ける（**URLSession を作るところは必ずここを通す**。
    /// `URLProtocol.registerClass` は `URLSession.shared` にしか効かない）。見本でなければ何もしない
    @discardableResult
    static func guarded(_ config: URLSessionConfiguration) -> URLSessionConfiguration {
        #if DEBUG
        if isOn {
            config.protocolClasses = [PreviewBackendProtocol.self] + (config.protocolClasses ?? [])
        }
        #endif
        return config
    }

#if DEBUG

    /// 見本の自分（UUID の形・公開の利用者ではない）
    static let userId = "5d0e5d0e-0000-4000-8000-000000000001"

    /// 起動の最初に呼ぶ（`JourneyPhotoApp.init`）。見本の間だけ、前の回の控え（本番の一覧・画像）を消し、
    /// `URLSession.shared` にも答え手を入れる（`PreviewBackend.session` を作ると `registerClass` される）
    static func install() {
        guard isOn else { return }
        URLCache.shared.removeAllCachedResponses()
        // 一覧・索引の端末の控え（`PhotoSnapshotStore`・`SpotSnapshotStore` は Caches の下）。前の UI テストの回に
        // 本番の一覧を控えていても、見本の回には持ち込まない
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let items = try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        _ = PreviewBackend.session
        print("[storeDemo] on")
    }

    // MARK: - 見本の画像（同梱の構図の作例写真）

    /// 見本の画像の URL（`composition-ai-<asset>` を返す）
    static func photoURL(_ asset: String) -> String { "https://\(host)/photo/\(asset).jpg" }

    /// 同梱の画像を JPEG で読む口（試験で差し替える）
    nonisolated(unsafe) static var loadAsset: (String) -> Data? = { asset in
        #if canImport(UIKit)
        return UIImage(named: "composition-ai-\(asset)")?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }

    /// 使ってよい写真（`photo-sources.json` のキー）。ここに無い名前の画像は返さない
    static var assets: Set<String> { Set(photos.map(\.asset)) }

    // MARK: - 見本の人と写真

    struct Person {
        let id: String
        let name: String
        let username: String
    }

    /// 作った名前（実在の人を思わせない）。id は UUID の形
    static let people: [Person] = [
        Person(id: "5d0e5d0e-0000-4000-8000-000000000011", name: "そらいろ散歩", username: "sora_sanpo"),
        Person(id: "5d0e5d0e-0000-4000-8000-000000000012", name: "週末のカメラ", username: "weekend_cam"),
        Person(id: "5d0e5d0e-0000-4000-8000-000000000013", name: "灯台めぐり", username: "toudai_meguri"),
        Person(id: "5d0e5d0e-0000-4000-8000-000000000014", name: "朝の坂道", username: "asa_sakamichi"),
        Person(id: "5d0e5d0e-0000-4000-8000-000000000015", name: "湖のほとり", username: "kosui_hotori"),
    ]

    struct DemoPhoto {
        /// `composition-ai-<asset>`（`photo-sources.json` のキー）
        let asset: String
        let title: String
        /// 写真の出典に書かれた実際の場所。分からない写真は nil（場所名なしの投稿）
        let location: String?
        let person: Int
        let spotId: String?
        let tags: [String]
        let likes: Int
        /// 何分前の投稿か
        let minutesAgo: Int
    }

    /// 見本の写真（並びの順）。場所は `photo-sources.json` の `subject` に書かれた実際の場所だけ
    static let photos: [DemoPhoto] = [
        DemoPhoto(asset: "rootRectangle", title: "五重塔と富士山", location: "新倉山浅間公園",
                  person: 0, spotId: "store-demo-arakurayama", tags: ["富士山", "山梨"], likes: 128, minutesAgo: 35),
        DemoPhoto(asset: "tunnel", title: "朱の鳥居をくぐって", location: "伏見稲荷大社",
                  person: 1, spotId: "store-demo-fushimi-inari", tags: ["京都", "鳥居"], likes: 96, minutesAgo: 80),
        DemoPhoto(asset: "halves", title: "湖に浮かぶ島の教会", location: "ブレッド湖",
                  person: 4, spotId: nil, tags: ["スロベニア", "湖"], likes: 74, minutesAgo: 140),
        DemoPhoto(asset: "tianzige", title: "池に映る金色", location: "金閣寺",
                  person: 3, spotId: "store-demo-kinkakuji", tags: ["京都", "映り込み"], likes: 152, minutesAgo: 210),
        DemoPhoto(asset: "negativeSpace", title: "白い崖と小さな灯台", location: "ビーチーヘッド",
                  person: 2, spotId: nil, tags: ["灯台", "海"], likes: 61, minutesAgo: 300),
        DemoPhoto(asset: "ratio4x5", title: "石畳の坂の先に", location: "八坂の塔",
                  person: 3, spotId: "store-demo-yasaka", tags: ["京都", "坂道"], likes: 88, minutesAgo: 420),
        DemoPhoto(asset: "hinomaru", title: "青空に浮かぶ気球", location: "ナパバレー",
                  person: 1, spotId: nil, tags: ["気球", "空"], likes: 57, minutesAgo: 600),
        DemoPhoto(asset: "frameWithin", title: "窓の向こうの海", location: nil,
                  person: 4, spotId: nil, tags: ["海", "窓"], likes: 43, minutesAgo: 760),
        DemoPhoto(asset: "armature", title: "ケーブルの集まるところ", location: "ブルックリン橋",
                  person: 0, spotId: nil, tags: ["橋", "ニューヨーク"], likes: 69, minutesAgo: 900),
        DemoPhoto(asset: "cCurve", title: "大きく曲がる川", location: "ホースシューベンド",
                  person: 2, spotId: nil, tags: ["渓谷", "アリゾナ"], likes: 84, minutesAgo: 1100),
        DemoPhoto(asset: "symmetry", title: "霧の朝の桟橋", location: nil,
                  person: 4, spotId: nil, tags: ["霧", "湖"], likes: 52, minutesAgo: 1300),
        DemoPhoto(asset: "squareGrid", title: "青いタイルの家", location: "リスボン",
                  person: 1, spotId: nil, tags: ["街歩き", "タイル"], likes: 47, minutesAgo: 1500),
        DemoPhoto(asset: "thirds", title: "夕暮れの防波堤", location: "サンタクルーズ",
                  person: 2, spotId: nil, tags: ["灯台", "夕焼け"], likes: 66, minutesAgo: 1700),
        DemoPhoto(asset: "lShape", title: "草原の一本の木", location: nil,
                  person: 0, spotId: nil, tags: ["草原"], likes: 39, minutesAgo: 1900),
        DemoPhoto(asset: "otherRatios", title: "雪の旧市街", location: "タリン",
                  person: 3, spotId: nil, tags: ["雪", "街歩き"], likes: 58, minutesAgo: 2200),
        DemoPhoto(asset: "ratio9x16", title: "見上げた京都タワー", location: "京都タワー",
                  person: 1, spotId: nil, tags: ["京都", "タワー"], likes: 45, minutesAgo: 2500),
    ]

    static func photoId(_ asset: String) -> String { "store-demo-\(asset)" }

    /// 見本の画像の URL（`photoURL`）から写真の名前を引く。見本の置き場でない・見本の一覧に無い名前は nil
    static func asset(in url: URL) -> String? {
        let path = url.path.split(separator: "/").map(String.init)
        guard url.host == host, path.count == 2, path[0] == "photo" else { return nil }
        let name = path[1].hasSuffix(".jpg") ? String(path[1].dropLast(4)) : path[1]
        return assets.contains(name) ? name : nil
    }

    /// 公開の一覧の行（`photos.json`・`GET /feed` の `items` と同じ形）
    static func feed(now: Date = Date()) -> [[String: Any]] {
        let iso = ISO8601DateFormatter()
        return photos.map { p in
            let person = people[p.person]
            let stamp = iso.string(from: now.addingTimeInterval(-Double(p.minutesAgo) * 60))
            var row: [String: Any] = [
                "id": photoId(p.asset), "src": photoURL(p.asset), "thumbSrc": photoURL(p.asset),
                "title": p.title, "userId": person.id, "uploadedBy": person.id, "displayName": person.name,
                "published": true, "createdAt": stamp, "updatedAt": stamp, "date": String(stamp.prefix(10)),
                "tags": p.tags, "likes": p.likes, "category": "landscape",
            ]
            if let location = p.location { row["location"] = location }
            if let spotId = p.spotId { row["spotId"] = spotId }
            return row
        }
    }

    // MARK: - 見本の観光スポット（写真の出典の場所と合うものだけ）

    struct DemoSpot {
        let spotId: String
        let slug: String
        let name: String
        let nameEn: String
        let reading: String
        let prefecture: String
        let city: String
        let lat: Double
        let lng: Double
        let category: String
        let summary: String
        let description: String
        let highlights: [String]
        let seasons: [(String, String)]
        let times: [(String, String)]
        let tips: [String]
        /// 表紙と作例に使う写真（この場所の写真だけ）
        let asset: String
    }

    static let spots: [DemoSpot] = [
        DemoSpot(spotId: "store-demo-fushimi-inari", slug: "fushimi-inari-taisha", name: "伏見稲荷大社", nameEn: "Fushimi Inari Taisha",
                 reading: "ふしみいなりたいしゃ", prefecture: "京都府", city: "京都市伏見区", lat: 34.9671, lng: 135.7727,
                 category: "shrine", summary: "朱の鳥居が山の上まで続く、千本鳥居で知られる神社。",
                 description: "稲荷山のふもとから山の上まで、朱の鳥居が続く神社。千本鳥居の参道は、鳥居が連なって奥へ吸い込まれるように見えます。",
                 highlights: ["千本鳥居の参道", "稲荷山の四ツ辻からの眺め"],
                 seasons: [("autumn", "参道のまわりの木々が色づき、朱の鳥居と重なります。"), ("winter", "空気が澄み、朝の参道が静かです。")],
                 times: [("morning", "朝早くは人が少なく、鳥居の続く奥まで写せます。"), ("evening", "夕方は鳥居の朱が深く見えます。")],
                 tips: ["参道の真ん中に立ち、鳥居の奥の一点に向かって構えると奥行きが出ます。"], asset: "tunnel"),
        DemoSpot(spotId: "store-demo-kinkakuji", slug: "kinkakuji", name: "金閣寺", nameEn: "Kinkaku-ji",
                 reading: "きんかくじ", prefecture: "京都府", city: "京都市北区", lat: 35.0394, lng: 135.7292,
                 category: "temple", summary: "鏡湖池に舎利殿が映る寺。",
                 description: "金色の舎利殿が鏡湖池に映る寺。風の弱い日は、池に映った姿まで1枚に収まります。",
                 highlights: ["鏡湖池の映り込み"],
                 seasons: [("winter", "雪の積もった朝は、金と白の対比が見られます。")],
                 times: [("morning", "開門すぐは風が弱いことが多く、映り込みがきれいです。")],
                 tips: ["水際を画面の真ん中の横線に合わせると、上下の釣り合いが取れます。"], asset: "tianzige"),
        DemoSpot(spotId: "store-demo-arakurayama", slug: "arakurayama-sengen-park", name: "新倉山浅間公園", nameEn: "Arakurayama Sengen Park",
                 reading: "あらくらやませんげんこうえん", prefecture: "山梨県", city: "富士吉田市", lat: 35.5011, lng: 138.8015,
                 category: "park", summary: "五重塔の忠霊塔と富士山を一緒に望む公園。",
                 description: "階段を上った展望デッキから、忠霊塔と富士山を一緒に望める公園です。",
                 highlights: ["忠霊塔と富士山", "展望デッキ"],
                 seasons: [("spring", "桜の季節は、塔と富士山の手前に花が入ります。"), ("autumn", "紅葉と富士山が見られます。")],
                 times: [("morning", "朝は富士山がはっきり見えやすい時間帯です。")],
                 tips: ["塔を縦の線に、富士山を上の交点の近くに置くと収まりがよくなります。"], asset: "rootRectangle"),
        DemoSpot(spotId: "store-demo-yasaka", slug: "hokanji-yasaka-pagoda", name: "八坂の塔", nameEn: "Yasaka Pagoda",
                 reading: "やさかのとう", prefecture: "京都府", city: "京都市東山区", lat: 34.9986, lng: 135.7790,
                 category: "temple", summary: "東山の石畳の坂から見上げる五重塔。",
                 description: "法観寺の五重塔。二年坂や八坂通の石畳の坂から、町並みの先に塔が見えます。",
                 highlights: ["石畳の坂からの眺め"],
                 seasons: [("spring", "桜の季節は坂の町並みが華やぎます。")],
                 times: [("morning", "朝は人が少なく、坂の石畳まで写せます。")],
                 tips: ["坂の下から塔を見上げ、道を手前に入れると奥行きが出ます。"], asset: "ratio4x5"),
    ]

    /// 索引の行（`spots.json`）
    static func spotRows() -> [[String: Any]] {
        spots.map { s in
            [
                "spotId": s.spotId, "slug": s.slug, "name": s.name, "nameEn": s.nameEn, "reading": s.reading,
                "region": ["prefecture": s.prefecture, "city": s.city],  // 国内は `country` を持たない（`TripAIDestination.match`）
                "coords": ["lat": s.lat, "lng": s.lng], "category": s.category, "summary": s.summary,
                "stage": "published", "verifiedAt": "2026-11-01",
                "image": spotImage(s.asset),
                "seasonalGuide": s.seasons.map { ["season": $0.0, "text": $0.1] },
                "timeOfDayGuide": s.times.map { ["time": $0.0, "text": $0.1] },
                "seasons": s.seasons.map(\.0), "times": s.times.map(\.0),
                "timeZone": "Asia/Tokyo", "hasImage": true,
            ] as [String: Any]
        }
    }

    /// 表紙の写真（同梱の写真。どれも CC0 で、作者と許諾は `photo-sources.json` のとおり。画面には出さない）
    static func spotImage(_ asset: String) -> [String: Any] {
        ["url": photoURL(asset), "author": author(of: asset), "license": "CC0", "pageUrl": sourcePages[asset] ?? ""]
    }

    /// 写真の出典の頁（`photo-sources.json` の `sourceURL`・出典の行のリンク。画像はここから読まない）
    static let sourcePages: [String: String] = [
        "tunnel": "https://commons.wikimedia.org/wiki/File:Fushimi_Inari_Shrine_August_2019.jpg",
        "tianzige": "https://commons.wikimedia.org/wiki/File:Den_gyllene_paviljongen,_Kyoto,_Japan_(Unsplash).jpg",
        "rootRectangle": "https://commons.wikimedia.org/wiki/File:Mt_Fuji_and_Tyureito_pagoda_2.jpg",
        "ratio4x5": "https://commons.wikimedia.org/wiki/File:Kyoto,_Japan_(Unsplash_UIN-pFfJ7c).jpg",
    ]

    /// 写真の作者（`Tools/composition-examples/photo-sources.json` の `author` のまま・試験が突き合わせる）。
    /// 出典の行は見本の間は出さないが、旅のオフラインの頁などに字が残っても本当の作者になるように
    static let authors: [String: String] = [
        "tunnel": "Sizableframe",
        "tianzige": "Oskar Vertetics oskarvertetics",
        "rootRectangle": "Hrykt",
        "ratio4x5": "Sorasak boontohhgraphy",
    ]

    static func author(of asset: String) -> String { authors[asset] ?? "" }

    /// 場所ごとの本文（`spots/<slug>.json`）
    static func spotBody(_ slug: String) -> [String: Any]? {
        guard let s = spots.first(where: { $0.slug == slug }) else { return nil }
        return [
            "slug": s.slug, "description": s.description, "highlights": s.highlights,
            "seasonalGuide": s.seasons.map { ["season": $0.0, "text": $0.1] },
            "timeOfDayGuide": s.times.map { ["time": $0.0, "text": $0.1] },
            "compositionTips": s.tips,
            "check": ["kind": "human", "verifiedAt": "2026-11-01"],
            "samples": [[
                "src": photoURL(s.asset), "width": 1920, "height": 2560, "title": s.name,
                "author": author(of: s.asset), "license": "CC0", "sourceUrl": sourcePages[s.asset] ?? "",
                // 出どころは「その他」の「Commons」（名前を「Wikimedia Commons」にすると、画像の置き場が upload.wikimedia.org のものしか通さない検査に当たる。画像は同梱）。
                // 出典の行のリンクは本当の Commons の頁
                "source": ["name": "Commons", "url": sourcePages[s.asset] ?? ""],
            ] as [String: Any]],
        ]
    }

    /// DM の見本で送る観光スポットの頁（`PreviewBackend.dmReply` の札の1通）
    static var dmSpotLink: String { "https://journey-photo.com/spots/\(spots[0].slug)" }

    // MARK: - 見本の会話と旅行プラン（見本の写真と場所に合わせた文）

    /// DM の見本の会話（`PreviewBackend.dmReply` の「夕焼けの人」との会話）の文。番号は `msg` の番号。
    /// 引用のストーリー・写真の通（ホームの1枚目＝新倉山浅間公園）・スポットの札（伏見稲荷大社）と合う言葉にする
    static let dmTexts: [Int: String] = [
        1: "鳥居の写真、すごくきれい。どこですか？",
        2: "ありがとうございます。京都の伏見稲荷大社です。",
        3: "朝早くに行くと、参道に人が少なかったです",
        4: "行ってみたい",
        5: "富士山の写真もあります。送りますね",
        10: "来月、一緒に京都へ行かない？",
    ]

    /// DM の見本の1人目の名前（見本でないときの「夕焼けの人」の代わり）。会話の中身（鳥居、京都）に合う作った名前
    static let dmPeer = (name: "京めぐり", username: "kyo_meguri")

    /// 受信箱の「夕焼けの人」の行の抜き書き（会話の最初の1通と同じ）
    static var dmFirstExcerpt: String { dmTexts[1] ?? "" }

    /// 旅行プランの見本（`TripPlanFixture.initialPlans` が見本の表示のときに使う）。見本の観光スポット4か所で組む。
    /// planId は共有の見本（`TripShareFixtureStore`）と同じ `fixture-kanazawa` を使い回す（会話・仲間の見本がそのまま付く）
    static let tripPlanTitle = "京都と富士山の旅"

    static func tripPlan(start: String, end: String, shared: Bool, me: String, friend: String) -> TripPlan {
        let ids = spots.map(\.spotId)
        return TripPlan(
            planId: "fixture-kanazawa", title: tripPlanTitle, startDate: start, endDate: end,
            days: [
                TripDay(items: [.spot(spotId: ids[0], note: nil), .spot(spotId: ids[3], note: nil), .spot(spotId: ids[1], note: nil)]),
                TripDay(items: [.spot(spotId: ids[2], note: nil)]),
            ],
            createdAt: "2026-11-10T00:00:00Z", updatedAt: "2026-11-10T00:00:00Z",
            share: shared ? TripShare(ownerId: me, memberIds: [me, friend], rev: 3) : nil,
            addedBy: shared ? ["s:\(ids[0])": friend] : [:])
    }

    /// 旅行プランの会話の見本の最初の1通（`TripShareFixtureStore`）
    static let tripChatFirst = "朝の伏見稲荷大社、人が少なくて良いらしい"

    // MARK: - 答え手

    /// 答える口の置き場（試験で差し替えられるように値で持つ）
    struct Hosts {
        let site: String?
        let api: String?
        let userAPI: String?
        let userAPIPath: String

        static var current: Hosts {
            Hosts(site: AppConfig.siteBaseURL.host, api: AppConfig.livePhotosURL?.host,
                  userAPI: AppConfig.userAPIBaseURL.host, userAPIPath: AppConfig.userAPIBaseURL.path)
        }
    }

    /// 見本の間の答え。**nil なら `PreviewBackend.reply`**（ユーザー API の鍵の要る口・ストーリー・DM）へ回す。
    /// 知らない置き場は断る（403）。答え手を通る要求は、ここより先へ1本も出ない（URLSession を通らない通信は型の注記）
    static func answer(method: String, url: URL, hosts: Hosts = .current, now: Date = Date()) -> PreviewBackend.Reply? {
        let path = url.path.split(separator: "/").map(String.init)
        guard let urlHost = url.host else { return refuse(url) }
        if urlHost == host {
            guard method == "GET", let asset = asset(in: url), let data = loadAsset(asset), !data.isEmpty else { return notFound }
            return PreviewBackend.Reply(status: 200, body: data, contentType: "image/jpeg")
        }
        if urlHost == PreviewBackend.host { return nil }
        if urlHost == hosts.userAPI {
            let parts = PreviewBackend.route(url, basePath: hosts.userAPIPath)
            return userAPI(method: method, parts: parts, now: now)
        }
        if urlHost == hosts.site {
            guard method == "GET" else { return notFound }
            switch path {
            case ["app", "data", "photos.json"]: return .json(feed(now: now))
            case ["app", "data", "spots.json"]: return .json(spotRows())
            case let p where p.count == 4 && p[0] == "app" && p[1] == "data" && p[2] == "spots" && p[3].hasSuffix(".json"):
                return spotBody(String(p[3].dropLast(5))).map { .json($0) } ?? notFound
            default:
                // 分けた置き場（`spot-feed/index.json`）・今日の一問などは「無い」（古い置き場へ戻る・段が出ないだけ）
                return notFound
            }
        }
        if urlHost == hosts.api {
            // 生のいいね数（`GET /photos`）は読まない。静的な一覧（見本）のまま
            return notFound
        }
        return refuse(url)
    }

    /// ユーザー API の鍵の要らない口（見本の人・写真だけ）。ほかは nil（`PreviewBackend.reply` へ）
    static func userAPI(method: String, parts: [String], now: Date) -> PreviewBackend.Reply? {
        guard method == "GET" else { return nil }
        switch parts {
        case ["feed"]:
            return .json(["items": feed(now: now), "nextCursor": NSNull()])
        case let p where p.count == 2 && p[0] == "profile":
            if p[1] == userId {
                return .json(["userId": userId, "displayName": "わたしの旅", "username": "my_journey"])
            }
            guard let person = people.first(where: { $0.id == p[1] }) else {
                return .json(["error": "見つかりません"], status: 404)
            }
            return .json(["userId": person.id, "displayName": person.name, "username": person.username])
        case let p where p.count == 3 && p[0] == "photos" && p[2] == "like":
            let likes = photos.first(where: { photoId($0.asset) == p[1] })?.likes ?? 0
            return .json(["likes": likes])
        case let p where p.count == 3 && p[0] == "photos" && p[2] == "comments":
            return .json(["items": comments(photoId: p[1], now: now), "count": comments(photoId: p[1], now: now).count])
        case let p where p.count == 3 && p[0] == "users" && p[2] == "follow":
            return .json(["followers": 240, "following": 180])
        default:
            return nil
        }
    }

    /// 写真のコメントの見本（作った人の作った言葉）
    static func comments(photoId: String, now: Date) -> [[String: Any]] {
        guard photoId == self.photoId(photos[0].asset) else { return [] }
        let iso = ISO8601DateFormatter()
        return [
            ["id": "store-demo-c1", "uid": people[1].id, "name": people[1].name, "text": "塔と富士山が一緒に入るのいいですね",
             "t": iso.string(from: now.addingTimeInterval(-20 * 60))],
            ["id": "store-demo-c2", "uid": people[3].id, "name": people[3].name, "text": "来月行くので参考にします",
             "t": iso.string(from: now.addingTimeInterval(-10 * 60))],
        ]
    }

    static let notFound = PreviewBackend.Reply(status: 404, body: Data())

    /// 断った要求（置き場の名前だけを出す。道・問い合わせは出さない）
    static func refuse(_ url: URL) -> PreviewBackend.Reply {
        print("[storeDemo] refused \(url.host ?? "?")")
        return PreviewBackend.Reply(status: 403, body: Data())
    }
#endif
}
