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
}
