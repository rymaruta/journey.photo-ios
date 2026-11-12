import Foundation

/// **絵を撮るためだけの、鍵を持たないログイン**（Debug のみ・owner 承認済み）。
///
/// CI の巡回は資格情報を持たないので、ログインしないと描かれない画面
/// （マイページ）の絵が1枚も撮れなかった。渡すのは**利用者 ID だけ**で、
/// トークンは1つも作らない。
///
/// **Release では必ず `nil`**（`#if DEBUG`）。TestFlight に上げるビルドは
/// Release なので、出荷物にこの口は無い。
///
/// 綴りを2か所に持たない——`AuthStore`（入るところ）と
/// `MyPageViewModel`（鍵の要らない経路へ逃がすところ）が同じここを読む。
enum PreviewSession {

    /// 起動時の引数・`UserDefaults` の鍵。`ScreenshotTests` が
    /// `-JPPreviewUserId <id>` で渡す。
    static let defaultsKey = "JPPreviewUserId"

    /// 電波が無いことにして画面を描く（Debug のみ・UI テストの絵だけ）。`-JPPreviewOffline YES`。
    ///
    /// 2026-11-12 判断（デザインの案 第2章「画面の状態とそろえ」）: 帯（電波なし）の絵を CI で撮るため。
    /// **通信は止めない**——読めた写真を「前に見た写真」として出し、上に帯が出た形を撮る。Release では必ず false
    static let offlineKey = "JPPreviewOffline"

    static var forcesOffline: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: offlineKey)
        #else
        return false
        #endif
    }

    /// 鍵を持たずに入っている利用者 ID。入っていなければ `nil`。
    static var userId: String? {
        #if DEBUG
        let raw = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return nil
        #else
        return nil
        #endif
    }

    /// UI テストで持たせるバッジ（Debug のみ）。`-JPPreviewBadges "prefectures:2,earlyUser:1"`。
    ///
    /// 鍵を持たない入り方では `GET /user/badges` が読めず、見本の利用者が持っているメダルも
    /// 決まらない。メダルを回す全画面の閉じ方（`MedalViewerTests`）を確かめるために、
    /// **入っている本人のプロフィールにだけ**この持ち物を重ねる。Release では必ず `nil`
    static let badgesKey = "JPPreviewBadges"

    static var badges: BadgeSet? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: badgesKey), !raw.isEmpty else { return nil }
        let items: [EarnedBadge] = raw.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, let tier = Int(parts[1]), tier >= 1 else { return nil }
            return EarnedBadge(key: parts[0], tier: tier, at: "2026-10-01T09:00:00Z")
        }
        return items.isEmpty ? nil : BadgeSet(items)
        #else
        return nil
        #endif
    }

    /// UI テストで名前の横に出すバッジの鍵（Debug のみ）。`-JPPreviewDisplayBadge earlyUser`。
    ///
    /// 見本の利用者は名前の横のバッジを選んでいないので、マイページの名前の横（`NameMarks`）に
    /// バッジが出ない。名前の横の絵（大きいメダルの絵を縮める・2026-10-09）を撮るために、
    /// **入っている本人のプロフィールにだけ**選んだことにする（`badges` に無い鍵は出ない）。
    /// Release では必ず `nil`
    static let displayBadgeKey = "JPPreviewDisplayBadge"

    static var displayBadge: String? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: displayBadgeKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
        #else
        return nil
        #endif
    }

    /// UI テストで本人の名前を差し替える（Debug のみ）。`-JPPreviewDisplayName <名前>`。
    ///
    /// マイページの名前の行（名前・印・点線の丸・QR・編集・2026-11-12 owner 案 A）が、長い名前でも
    /// 1行に収まるか（名前を「…」で切り、ほかは縮めない）を撮るために、**入っている本人のプロフィールにだけ**
    /// 重ねる。サーバーには送らない。Release では必ず `nil`
    static let displayNameKey = "JPPreviewDisplayName"

    static var displayName: String? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: displayNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
        #else
        return nil
        #endif
    }

    /// UI テストで Pro の人の姿にする（Debug のみ）。`-JPPreviewPro YES`。
    ///
    /// 見本の利用者は Pro を買っていないので、名前の横の画面の「PRO 限定」の段が Pro でない人の姿
    /// （鍵・「Pro で集める」）にしかならない。Pro の人の姿（説明の一行・押すと届く時期・2026-10-09）を
    /// 撮るために、**入っている本人のプロフィールにだけ** Pro を重ねる。サーバーの扱いは変わらない
    /// （Pro の口はサーバーが本当の値で断る）。Release では必ず false
    static let proKey = "JPPreviewPro"

    static var isPro: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: proKey)
        #else
        return false
        #endif
    }

    /// UI テストで、全体の再生器の後ろに見本の地（白・模様・黒の3段）を敷く（Debug のみ・2026-10-29・#402）。
    /// `-JPPreviewMiniPlayerBackdrop YES`。再生器の地を透かしたので、白い写真・模様の多い写真・黒い写真の上で
    /// 曲名が読めるかを毎回同じ絵で見る（`MiniPlayerBackdrop`）。Release では必ず false
    static let miniPlayerBackdropKey = "JPPreviewMiniPlayerBackdrop"

    static var miniPlayerBackdrop: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: miniPlayerBackdropKey)
        #else
        return false
        #endif
    }

    /// UI テストでホームの札の行の位置の数を見えない要素に出す（Debug のみ・2026-10-31 #426）。
    /// `-JPPreviewFeedProbe YES`。留まったまま替えたときに札の行が動く件を、推定でなく実際の数で見るため
    /// （`GalleryView` の `home.feed.probe`・`ScreenshotTests.testSwipesHomeFeedTabs`）。Release では必ず false
    static let feedProbeKey = "JPPreviewFeedProbe"

    static var feedProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: feedProbeKey)
        #else
        return false
        #endif
    }

    /// UI テストで、起動直後の動きの記録（`PerfRecorder`）を取り、見えない要素 `perf.probe` に出す（Debug のみ・2026-11-04・札 #435 / #429）。
    /// `-JPPreviewPerfProbe YES`。下のタブを書いた場所と時刻・起動後の `.task` の始めと終わり・メインスレッドの停止・
    /// 主要画面の body の評価回数を、推定でなく実際の数で見るため。Release では必ず false（記録も要素も出ない）
    /// UI テストの事実取りだけ: ホームの写真の札の「手に取って運ぶ」の身振りを付けない（`-JPPreviewNoLift YES`・Debug のみ・
    /// 2026-11-12 run 1171 で、ホームを払っても一覧が動かなかった件を、身振りの有り無しで比べるため）
    static var noLift: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewNoLift")
        #else
        return false
        #endif
    }

    static let perfProbeKey = "JPPreviewPerfProbe"

    static var perfProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: perfProbeKey)
        #else
        return false
        #endif
    }

    /// UI テストで、ストーリー作成の札の動き（動かす操作の回数・時刻・各札の位置・打っている最中か）を取り、
    /// 見えない要素 `story.probe` に出す（Debug のみ・2026-11-08・札 #499「場所などを入力した後、自由に動かせない」）。
    /// `-JPPreviewStoryProbe YES`。画面の絵からの推定でなく、動かない回の実際の数で原因を決めるため。
    /// Release では必ず false（記録も要素も出ない）
    static let storyProbeKey = "JPPreviewStoryProbe"

    static var storyProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: storyProbeKey)
        #else
        return false
        #endif
    }

    /// UI テストでサポーターの印を持たせる（Debug のみ・2026-10-18）。`-JPPreviewSupporter 7`（番号）。
    ///
    /// 見本の利用者の公開プロフィールは `pro: true` だが `supporter` の欄が無く、トランクの内ポケットの会員証
    /// （Pro でサポーター証の番号があるときだけ・`TrunkInsideContents.showsCard`）が出ない。会員証の絵を撮るために、
    /// **入っている本人のプロフィールにだけ**番号を重ねる（申し込んだ日は 2026-10-01・続けた月 1）。
    /// 本番の決まりは変えない。Release では必ず nil
    static let supporterKey = "JPPreviewSupporter"

    static var supporter: SupporterInfo? {
        #if DEBUG
        guard userId != nil, let raw = UserDefaults.standard.string(forKey: supporterKey),
              let number = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 1 else { return nil }
        return SupporterInfo(number: number, since: "2026-10-01T09:00:00Z", months: 1)
        #else
        return nil
        #endif
    }

    /// UI テストでメダルを回す全画面の硬貨を止める向きと強さ（Debug のみ）。
    /// `-JPPreviewMedalPoses "0:1,0.45:1,1.1:1"`（横の回り:浮き彫りの強さ）。
    ///
    /// 硬貨はふだん勝手にゆっくり回るので、画面写真の角度が毎回ちがう。浮き彫りの強さ（2026-10-14）を
    /// 決まった角度で比べるために、**最初の向きで止め、硬貨を押すと次の向きへ進める**。
    /// 入っている見本の利用者のときだけ効く。Release では必ず `nil`
    static let medalPosesKey = "JPPreviewMedalPoses"

    static var medalPoses: [MedalPose]? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: medalPosesKey), !raw.isEmpty else { return nil }
        let poses = MedalPose.parse(raw)
        return poses.isEmpty ? nil : poses
        #else
        return nil
        #endif
    }

    /// UI テストで「行った県」の画面に見本の記録を入れる（Debug のみ）。`-JPPreviewVisitedMap YES`。
    /// 回数の段（1〜4 回以上）が地図に並んだ絵を撮るための口。端末には書かない。
    /// **入っている見本の利用者のときだけ**効く。Release では必ず `nil`
    static let visitedMapKey = "JPPreviewVisitedMap"

    static var visitedMapSeed: VisitedPrefectures? {
        #if DEBUG
        guard userId != nil, UserDefaults.standard.bool(forKey: visitedMapKey) else { return nil }
        var book = VisitedPrefectures()
        let day = "2026-01-01"
        // 北から 31 県を 1 回、そのうち数県を 2・3・5 回にする
        let extra: [String: Int] = ["東京都": 5, "京都府": 3, "大阪府": 3, "神奈川県": 2, "長野県": 2, "北海道": 2]
        for name in RegionList.prefectures.prefix(31) {
            for _ in 0..<(extra[name] ?? 1) { book.add(name, day: day) }
        }
        for (name, times) in extra where book.count(name) == 0 {
            for _ in 0..<times { book.add(name, day: day) }
        }
        return book
        #else
        return nil
        #endif
    }

    /// UI テストでマイページを開いたら Pro の案内（`PaywallView`）を1度だけ出す（Debug のみ）。
    /// `-JPPreviewPaywall YES`。
    ///
    /// 見本の利用者は公開プロフィールでは Pro なので、名前の横の「Pro で集める」は出ない。
    /// 設定の Pro の行は、鍵を持たない入り方では Pro かどうか分からず「App Store で管理」を開く
    /// （`ProStatusText.settingsAction`・変えない）。審査用の画面写真「81-Pro の案内」を撮るためだけの口。
    /// **入っている見本の利用者のときだけ**効く。Release では必ず false
    static let paywallKey = "JPPreviewPaywall"

    static var opensPaywall: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: paywallKey)
        #else
        return false
        #endif
    }

    /// UI テストで通知の説明（`PushPrimerView`）を起動のときに1回出す（Debug のみ）。`-JPPreviewPushPrimer YES`。
    ///
    /// ふだんは初めての投稿が上がったときにしか出ず、鍵を持たない入り方では投稿できないので絵が撮れない。
    /// 許可の状態・前に出したかは見ない（シミュレータの状態に絵が左右されないように）。
    /// **入っている見本の利用者のときだけ**効く。Release では必ず false
    static let pushPrimerKey = "JPPreviewPushPrimer"

    /// UI テストで、すれちがいの届いた束（見本のカード7枚）を入れる（Debug のみ）。`-JPPreviewPass YES`。
    ///
    /// カードは近くの端末と Bluetooth で交換したときにしか届かず、シミュレータには電波が無いので絵が撮れない。
    /// 公開一覧の他の人の写真から見本を作る（端末の中だけ・サーバーには何も送らない）。
    /// **入っている見本の利用者のときだけ**効く。Release では必ず false
    static let passSampleKey = "JPPreviewPass"

    static var passSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: passSampleKey)
        #else
        return false
        #endif
    }

    static var opensPushPrimer: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: pushPrimerKey)
        #else
        return false
        #endif
    }

    /// UI テストで投稿画面を**見本の写真1枚を選んだ状態で**開く（Debug のみ）。`-JPPreviewUploadSample YES`。
    ///
    /// 写真を選ぶ画面（PHPicker）は別プロセスで、CI では中の写真に触れない回が続き、投稿画面の絵
    /// （42〜45c）が1枚も撮れていなかった（run 428）。ピッカーを通らず、アプリに入っている画像
    /// （`PreviewUploadSample`）をカメラで撮った1枚と同じ道で入れる。**入っている見本の利用者のときだけ**
    /// 効く。Release では必ず false
    static let uploadSampleKey = "JPPreviewUploadSample"

    /// UI テストで下書きの一覧（#400）を見本の中身で出す（Debug のみ・2026-10-29）。`-JPPreviewDrafts YES`
    /// （投稿・ストーリー・自動の書きかけ・期限が近いもの・読めない写真のあるもの）。端末の中に書くだけで、
    /// サーバーには何も送らない（下書きはもともと端末だけ・`PreviewDraftsSample`）。
    /// 入っている見本の利用者のときだけ効く。Release では必ず false
    static let draftsSampleKey = "JPPreviewDrafts"

    static var seedsDraftsSample: Bool {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: draftsSampleKey)?.lowercased() else { return false }
        return ["yes", "true", "1"].contains(raw)
        #else
        return false
        #endif
    }

    static var opensUploadSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: uploadSampleKey)
        #else
        return false
        #endif
    }

    /// UI テストで「この写真を見て撮影」の見本を出す（Debug のみ）。`-JPPreviewInspired YES`。
    ///
    /// 元の写真の付いた写真は本番にまだ無く、`GET /user/inspired` も本番に無いので、写真の詳細の行
    /// （20e/20f）と、元の写真を選んだ投稿の欄（45d）が撮れない。この鍵のときだけ:
    /// - 写真の詳細は、どの写真にも元の写真が付いているものとし、口を呼ばずに公開一覧の別の1枚を
    ///   要約にして出す（`InspiredBy.previewSource`）
    /// - 投稿画面は、公開一覧の1枚を元の写真に選んだ状態で始める
    ///
    /// **画面の状態だけ**で、サーバー・端末の控えには何も書かない。入っている見本の利用者のときだけ。
    /// Release では必ず false
    static let inspiredSampleKey = "JPPreviewInspired"

    static var showsInspiredSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: inspiredSampleKey)
        #else
        return false
        #endif
    }

    /// UI テストで「ストーリーから作った写真」の見本を出す（Debug のみ・2026-11-11）。`-JPPreviewKeptStory YES`。
    ///
    /// 写真にしたストーリーは見本の利用者に無いので、関係の札（写真の詳細の「ストーリーから作った写真 ›」・
    /// ストーリーの「写真にしました ›」）と、2つから選ぶ消す確認が撮れない。この鍵のときだけ、写真の詳細は
    /// どの写真も「本人のストーリーから作った」ものとし、口を呼ばずにその写真の絵のストーリーを1本こしらえる。
    /// **画面の状態だけ**で、サーバー・端末の控えには何も書かない。Release では必ず nil
    static let keptStorySampleKey = "JPPreviewKeptStory"

    static func keptStorySample(photoId: String, src: String) -> Story? {
        #if DEBUG
        guard let userId, UserDefaults.standard.bool(forKey: keptStorySampleKey) else { return nil }
        let row: [String: Any] = [
            "id": "preview-kept-\(photoId)", "src": src, "userId": userId, "displayName": "あなた",
            "keptAs": photoId, "archive": true,
            "createdAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
            "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(20 * 3600)),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        return try? JSONDecoder.api.decode(Story.self, from: data)
        #else
        return nil
        #endif
    }

    /// UI テストで旅のトランクを見本の中身で出す（Debug のみ・2026-10-17）。`-JPPreviewTrunk YES`（見本）・
    /// `-JPPreviewTrunk empty`（届いたラベルが1枚も無い人）。
    ///
    /// 鍵を持たない入り方では `GET /user/trunk` が読めず、ラベルも投稿しないと届かないので絵が撮れない。
    /// **サーバーには何も送らない**——貼る・削除・作り直し・型の替えは端末の中で見本を動かすだけ
    /// （`TrunkLocal`）。Pro の姿は `-JPPreviewPro`。入っている見本の利用者のときだけ効く。Release では必ず nil
    static let trunkSampleKey = "JPPreviewTrunk"

    enum TrunkPreview: Equatable { case sample, empty }

    static var trunkSample: TrunkPreview? {
        #if DEBUG
        guard userId != nil,
              let raw = UserDefaults.standard.string(forKey: trunkSampleKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        if raw == "empty" { return .empty }
        return ["yes", "true", "1", "sample"].contains(raw) ? .sample : nil
        #else
        return nil
        #endif
    }

    /// 旅のトランクの見本の硬貨の枚数（Debug のみ・2026-10-17 次の版）。`-JPPreviewTrunkCoins 0` で
    /// カプセルの機械の「硬貨がありません」を撮る。無ければ見本の 2 枚。Release では必ず nil
    static let trunkCoinsKey = "JPPreviewTrunkCoins"

    static var trunkCoins: Int? {
        #if DEBUG
        guard trunkSample != nil, let raw = UserDefaults.standard.string(forKey: trunkCoinsKey),
              let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else { return nil }
        return min(99, value)
        #else
        return nil
        #endif
    }

    /// UI テストで、起動のときに「ラベルが届きました」の画面を1回出す（Debug のみ）。`-JPPreviewTrunkArrived YES`。
    /// 投稿しないと届かないので、見本の1枚（`TrunkSample.arrived`）で出す。入っている見本の利用者のときだけ。
    /// Release では必ず false
    static let trunkArrivedKey = "JPPreviewTrunkArrived"

    static var opensTrunkArrived: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: trunkArrivedKey)
        #else
        return false
        #endif
    }

    /// 見本の届いた画面の枚数（`-JPPreviewTrunkArrived 3` で3枚・「まとめて貼る」の画面写真・2026-11-12）。`YES` は 1 枚
    static var trunkArrivedCount: Int {
        #if DEBUG
        guard opensTrunkArrived else { return 0 }
        return max(1, min(3, UserDefaults.standard.integer(forKey: trunkArrivedKey)))
        #else
        return 0
        #endif
    }

    /// UI テストで、お知らせに「はじめてのいいね」の見本の行を出す（Debug のみ・2026-11-08）。`-JPPreviewFirstReaction YES`。
    /// サーバーには何も送らず、端末の控えにも書かない。入っている見本の利用者のときだけ。Release では必ず false
    static let firstReactionKey = "JPPreviewFirstReaction"

    static var opensFirstReaction: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: firstReactionKey)
        #else
        return false
        #endif
    }

    /// UI テストで、人のプロフィールに見本の人のトランクを出す（Debug のみ・2026-10-18）。`-JPPreviewTheirTrunk YES`。
    ///
    /// 人の口（`GET /users/{uid}/trunk`）は鍵を持たない入り方では読めず、本番にもまだ無いので、人のトランクの段と
    /// 画面の絵が撮れない。**サーバーには何も送らない**——どの人のページでも見本のトランク（`TheirTrunkSample`）を
    /// 出す。ラベルの写真はその人の公開写真から引く。地名の無いラベルも混ぜる。入っている見本の利用者のときだけ効く。
    /// Release では必ず false
    static let theirTrunkKey = "JPPreviewTheirTrunk"

    static var theirTrunkSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: theirTrunkKey)
        #else
        return false
        #endif
    }

    /// UI テストで、とおまわり号の要サーバーの部品の見本を出す（Debug のみ・2026-10-19 第2段）。`-JPPreviewCamper YES`。
    ///
    /// 鍵を持たない見本の入り方では `GET /user/camper`・`GET /users/{uid}/camper` が読めないので、分母 131・届いた画面・
    /// 友達の車の絵が撮れない。**サーバーには何も送らない**——自分の車は `CamperServerSample.mine`、友達の車は
    /// `CamperServerSample.visit`、贈る・薪は見本の答え。入っている見本の利用者のときだけ。Release では必ず false
    static let camperKey = "JPPreviewCamper"

    static var camperSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: camperKey)
        #else
        return false
        #endif
    }

    /// UI テストで、とおまわり号の「中に入る」の動き（扉が開く → 口へ寄る → 部屋へ）をゆっくりにする倍率（Debug のみ・2026-10-21）。
    /// `-JPPreviewCamperEnterSlow 6`。途中の光（扉が開いた瞬間・寄っている途中・切り替わる直前）を画面写真で確かめるため。
    /// 入っている見本の利用者のときだけ。Release では必ず 1
    static let camperEnterSlowKey = "JPPreviewCamperEnterSlow"

    static var camperEnterSlow: Double {
        #if DEBUG
        guard userId != nil else { return 1 }
        let k = UserDefaults.standard.double(forKey: camperEnterSlowKey)
        return k > 1 ? min(k, 20) : 1
        #else
        return 1
        #endif
    }

    /// UI テストで、とおまわり号の描画の数（1 コマの時間・値渡しの回数）を数えて読み上げの値に出す（Debug のみ・2026-10-31・#430）。
    /// `-JPPreviewCamperPerf YES`。`CamperRenderMeter`。入っている見本の利用者のときだけ。Release では必ず false
    static let camperPerfKey = "JPPreviewCamperPerf"

    /// メモリの内訳を測るための A/B（2026-11-07・札 #430・測るだけ）。`-JPPreviewCamperAA none|2x|4x` で、とおまわり号の外観・部屋の
    /// SCNView の輪郭のなめらかさ（`antialiasingMode`）を切り替える。Debug かつ入っている見本の利用者のときだけ。指定が無い・Release では nil（本番の既定のまま）
    static let camperAAKey = "JPPreviewCamperAA"

    static var camperAA: String? {
        #if DEBUG
        guard userId != nil else { return nil }
        guard let v = UserDefaults.standard.string(forKey: camperAAKey)?.lowercased(), ["none", "2x", "4x"].contains(v) else { return nil }
        return v
        #else
        return nil
        #endif
    }

    /// 測定専用の差し替え（2026-11-07・札 #430・Debug の見本の利用者のときだけ。Release では必ず nil）。
    /// `-JPPreviewCamperDiag lightbed|lightfurniture|halftex|keepmesh`: ベッドを箱に・家具を全部箱に・貼り絵を半分の寸法に・家具の網の配列を手放さない（軽量化の前の動き）。見た目の確認は不要
    static let camperDiagKey = "JPPreviewCamperDiag"

    static var camperDiag: String? {
        #if DEBUG
        guard userId != nil else { return nil }
        guard let v = UserDefaults.standard.string(forKey: camperDiagKey)?.lowercased(),
              ["lightbed", "lightfurniture", "halftex", "keepmesh"].contains(v) else { return nil }
        return v
        #else
        return nil
        #endif
    }

    /// UI テストで、旅のトランクの重さ（1 コマの間隔・主スレッドの停止・Canvas を描いた回数と時間・回す箱の 1 コマ・
    /// 貼り絵の大きさ・メモリ）を数えて読み上げの値に出す（Debug のみ・2026-11-11「旅のトランク重すぎる」・測るだけ）。
    /// `-JPPreviewTrunkPerf YES`。`TrunkPerfMeter`。入っている見本の利用者のときだけ。Release では必ず false
    static let trunkPerfKey = "JPPreviewTrunkPerf"

    static var trunkPerf: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: trunkPerfKey)
        #else
        return false
        #endif
    }

    /// 測定専用の差し替え（2026-11-11・旅のトランクの重さ・Debug の見本の利用者のときだけ。Release では必ず空）。
    /// `-JPPreviewTrunkDiag "noshadow,nodg"` のように `,` で並べる:
    /// `noshadow` 胴の影 2 つを外す・`nodg` 胴の `drawingGroup` を外す・`spinaa0`/`spinaa2` 回す箱の輪郭のなめらかさを なし/2x に
    /// （この 3 つは見た目が変わる。比べるためだけ）。
    /// 前の作りに戻す（絵の見比べの「前」・2026-11-11 の直し）: `spincont` 回す箱を描き続ける・
    /// `spinlazy` 回す箱の絵を使い回さない・`spinlink` 止まっている箱の表示の刻みを止めない・`rastercost` 回す箱の絵を塗る時間の内訳を測る・`boldcheck` 文字を太くする設定が回す箱の正面に効くかを測る
    static let trunkDiagKey = "JPPreviewTrunkDiag"

    static var trunkDiag: Set<String> {
        #if DEBUG
        guard userId != nil, let raw = UserDefaults.standard.string(forKey: trunkDiagKey) else { return [] }
        return Set(raw.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        #else
        return []
        #endif
    }

    static var camperPerf: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: camperPerfKey)
        #else
        return false
        #endif
    }

    /// UI テストで、友達の車の画面（板 CamperVisit）へ**マイページの旅の記録から直接**入る行を出す（Debug のみ・2026-10-19）。
    /// `-JPPreviewCamperVisit YES`。
    ///
    /// 人のプロフィールの本物の入口（フォローしている人の頁だけ）は、ホームの写真の並びとフォローの関係次第で見本の
    /// 起動では出ないことがあり、画面写真（95i・95j）が撮れなかった。**本物の入口の条件は変えない**——ここは見本の友達
    /// （`CamperServerSample.friendId`）の車へ入る別の行を、見本の起動のときだけ足す。中身は見本で、サーバーには何も送らない。
    /// 入っている見本の利用者のときだけ。Release では必ず false
    static let camperVisitKey = "JPPreviewCamperVisit"

    static var camperVisitSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: camperVisitKey)
        #else
        return false
        #endif
    }

    /// UI テストで、起動のときに「はじめての硬貨」の案内を1回出す（Debug のみ・2026-10-18）。`-JPPreviewTrunkWelcome YES`
    /// で 10 枚、`-JPPreviewTrunkWelcome 3` で上限に当たって 3 枚だけ増えた姿。**サーバーには何も送らない**
    /// （`POST /user/trunk/welcome` を呼ばない）。入っている見本の利用者のときだけ。Release では必ず nil
    static let trunkWelcomeKey = "JPPreviewTrunkWelcome"

    static var trunkWelcomeAdded: Int? {
        #if DEBUG
        guard userId != nil, let raw = UserDefaults.standard.string(forKey: trunkWelcomeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        if ["yes", "true"].contains(raw) { return 10 }
        guard let n = Int(raw), n > 0 else { return nil }
        return min(10, n)
        #else
        return nil
        #endif
    }

    // MARK: アイコンとカバー（#304・2026-10-18）。どれも Debug のみ・入っている見本の利用者のときだけ・**サーバーには何も送らない**

    /// 起動のときに「この1枚をカバーに」を1回出す。`first`（初めての投稿・51）・`liked`（いいね・カバーあり・51b）・
    /// `likedNoCover`（いいね・カバーなし）。写真は見本の利用者の公開写真の1枚目
    static let coverOfferKey = "JPPreviewCoverOffer"

    enum CoverOfferPreview: String { case first, liked, likedNoCover }

    static var coverOffer: CoverOfferPreview? {
        #if DEBUG
        guard userId != nil, let raw = UserDefaults.standard.string(forKey: coverOfferKey) else { return nil }
        return CoverOfferPreview(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        return nil
        #endif
    }

    /// 起動のときにアイコン・カバーのお礼（板 53）を1回出す。`avatar`・`cover`・`both`（設定済みの人に +6）
    static let coinRewardKey = "JPPreviewCoinReward"

    static var coinReward: ProfileReward.Grant? {
        #if DEBUG
        guard userId != nil, let raw = UserDefaults.standard.string(forKey: coinRewardKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch raw {
        case "avatar": return ProfileReward.Grant(kinds: [.avatar], added: 3, coins: 5)
        case "cover": return ProfileReward.Grant(kinds: [.cover], added: 3, coins: 5)
        case "both": return ProfileReward.Grant(kinds: [.avatar, .cover], added: 6, coins: 8, existing: true)
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// UI テストで、鍵の要る口を**端末の中の見本の通信**（`PreviewBackend`）に答えさせる（Debug のみ・2026-10-22）。
    /// `-JPPreviewLocalBackend YES`。
    ///
    /// 鍵を持たない入り方では、いいね・保存・コメント・投稿が 401 の手前（鍵が無い）で止まり、
    /// 「押せる・結果が画面に出る」を UI テストで確かめられなかった。CI は資格情報を持たないので、
    /// staging の試験用の利用者でも入れない（2026-10-22 判断: 端末の中で完結させる）。
    /// **サーバーには何も書かない**——鍵の要る口はすべて端末の中で答え、読むだけの公開の口
    /// （一覧・いいね数）はこれまでどおり本物を読む。ログアウト → ログインも見本の認証
    /// （`PreviewBackend.authGateway`）で回る。入っている見本の利用者のときだけ。Release では必ず false
    static let localBackendKey = "JPPreviewLocalBackend"

    static var localBackend: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: localBackendKey)
        #else
        return false
        #endif
    }

    /// 見本の通信（`localBackend`）で、ストーリーの一覧を端末の中で答える（`PreviewBackend.previewStories`・
    /// 2026-10-22・顔の輪と返信欄を UI テストで撮る）。Release では必ず false
    static let storiesKey = "JPPreviewStories"

    static var stories: Bool {
        #if DEBUG
        guard localBackend else { return false }
        return UserDefaults.standard.bool(forKey: storiesKey)
        #else
        return false
        #endif
    }

    /// 見本のストーリー（`stories`）の1本に**紹介した写真**を付ける（札 #541 の ①・`PreviewBackend.previewStories`）。
    /// 見る画面の「写真を見る」を UI テストで撮る。Release では必ず false
    static let sharedStoryKey = "JPPreviewSharedStory"

    static var sharedStory: Bool {
        #if DEBUG
        guard stories else { return false }
        return UserDefaults.standard.bool(forKey: sharedStoryKey)
        #else
        return false
        #endif
    }

    /// 見本の通信（`localBackend`）で、メッセージ（`/dm`）を端末の中で答える（`PreviewBackend.dmReply`・
    /// 2026-11-10 札 #505・受信箱・リクエスト・会話の状態を UI テストで撮る）。Release では必ず false
    static let dmKey = "JPPreviewDM"

    static var dm: Bool {
        #if DEBUG
        guard localBackend else { return false }
        return UserDefaults.standard.bool(forKey: dmKey)
        #else
        return false
        #endif
    }

    /// UI テストでストーリー作成を**見本の写真と曲を付けた状態で**開く（Debug のみ）。`-JPPreviewStorySong YES`。
    /// 曲の札の6つの形（2026-10-28）を押して替えながら撮る。**入っている見本の利用者のときだけ**効く。
    /// Release では必ず false
    static let storySongKey = "JPPreviewStorySong"

    static var opensStorySongSample: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: storySongKey)
        #else
        return false
        #endif
    }

    /// マイページでカバーが無いことにする（額縁・板 52 を撮る。見本の利用者がカバーを持っていても）
    static let noCoverKey = "JPPreviewNoCover"

    static var forcesNoCover: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: noCoverKey)
        #else
        return false
        #endif
    }

    /// マイページでカバーも額縁も出さない（顔 72・設定の丸と数が同じ高さの姿を撮る・#415）。
    /// `-JPPreviewBareHeader YES`。Release では必ず false
    static let bareHeaderKey = "JPPreviewBareHeader"

    static var forcesBareHeader: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: bareHeaderKey)
        #else
        return false
        #endif
    }

    /// ①現像の札と画面・②「1年前」の輪と閲覧を撮る（2026-11-12 札 #543）。端末の写真の代わりに
    /// 同梱の見本の絵で旅を作る（`DevelopPreview`）。`-JPPreviewDevelop YES`。Release では必ず false
    static let developKey = "JPPreviewDevelop"

    static var develop: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: developKey)
        #else
        return false
        #endif
    }

    /// ①②の状態の絵を撮る（2026-11-12 札 #543）。`-JPPreviewDevelopState offline`（圏外）か `limited`（一部の写真だけ許可）。
    /// `develop` のときだけ効く。Release では必ず nil
    static let developStateKey = "JPPreviewDevelopState"

    static var developState: String? {
        #if DEBUG
        guard develop else { return nil }
        return UserDefaults.standard.string(forKey: developStateKey)
        #else
        return nil
        #endif
    }

    /// 圏外として撮る（`developState == "offline"`）
    static var developOffline: Bool { developState == "offline" }
    /// 一部の写真だけ許可として撮る（`developState == "limited"`）
    static var developLimited: Bool { developState == "limited" }
}
