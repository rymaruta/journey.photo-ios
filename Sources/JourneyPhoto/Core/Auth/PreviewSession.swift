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

    /// ログイン画面の Apple・Google のボタンを、通信せずに「使える」として描く（Debug のみ・UI テストの絵だけ）。
    /// `-JPPreviewExternalSignIn YES`。2026-11-23 判断: 本番・staging の口の答えに左右されずに、ボタンのある形の絵を撮るため。
    /// 覚え（`ExternalSignInMemory`）には書かない。Release では必ず false
    static let externalSignInKey = "JPPreviewExternalSignIn"

    static var forcesExternalSignIn: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: externalSignInKey)
        #else
        return false
        #endif
    }

    /// ログイン画面を、登録の確認コードの画面（6桁の箱）から開く（Debug のみ・UI テストだけ）。`-JPPreviewVerificationCode YES`。
    /// 2026-11-23 判断: 本物の Cognito に登録せずに確認コードの画面の絵を撮り、見本の認証（`-JPPreviewLocalBackend`）と
    /// 合わせて「6桁で自動で確かめてログインする」流れを確かめるため。送り先は見本のメール（`PreviewBackend.email`）。Release では必ず false
    static let verificationCodeKey = "JPPreviewVerificationCode"

    static var opensVerificationCode: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: verificationCodeKey)
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
        // App Store の見本（`StoreDemo`・札 #604）は、公開の利用者ではない見本の自分で入る
        if StoreDemo.isOn { return StoreDemo.userId }
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

    /// UI テストで、ホームの新しい投稿・はじめての投稿・今週のお題の参加を見本で出す（Debug のみ・札 #537・2026-11-11）。
    /// `-JPPreviewSNSLoop YES`。本番の公開一覧では 72 時間以内の投稿・今週のお題のタグの写真が無い日が多く、
    /// 絵が撮れない。公開一覧のいちばん新しい3枚の投稿日・お題のタグ・1枚の持ち主を**端末の中だけ**で書き替える
    /// （`PreviewSNSLoopSample`）。サーバーには何も送らない。Release では必ず false
    static let snsLoopSampleKey = "JPPreviewSNSLoop"

    static var snsLoopSample: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: snsLoopSampleKey)
        #else
        return false
        #endif
    }

    /// UI テストでホームの1本の並びの数（読んだページ・並びの数・続きの目印・新着の最初の札）を見えない要素に出す
    /// （Debug のみ・2026-10-31 #426 で札の行の位置を見るために足し、札 #595 で1本の並びの数に替えた）。
    /// `-JPPreviewFeedProbe YES`（`GalleryView` の `home.feed.probe`・`ScreenshotTests.testScrollsHomeSingleFeed`・
    /// `revealNewestFeedTile`）。Release では必ず false
    static let feedProbeKey = "JPPreviewFeedProbe"

    /// UI テストで、探すの「文で探す」の0件の外し方の動き（`SearchView.relaxProbe`）を見えない要素 `search.reading.probe` に出す
    /// （Debug のみ・2026-11-15 札 #623。回 1383 で0件のまま外さなかった理由を数で取る）
    static let searchReadingProbeKey = "JPSearchReadingProbe"

    static var searchReadingProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: searchReadingProbeKey)
        #else
        return false
        #endif
    }

    /// UI テストで、投稿の入口の切り替えの段と「一覧を見ているか」の知らせの順を見えない要素 `createflow.probe` に出す
    /// （Debug のみ・2026-11-18 確かめ役の指摘: ストーリーから投稿に替えたときに切り替えが消えるかを、推定でなく順で取る）。
    /// `-JPCreateFlowProbe YES`。Release では必ず false
    static let createFlowProbeKey = "JPCreateFlowProbe"

    static var createFlowProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: createFlowProbeKey)
        #else
        return false
        #endif
    }

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
    /// UI テストの事実取りだけ: マイページの札の行・中身の横の払いを、どの指の操作が受けたか（UIKit のパンの始まり・終わりと
    /// 移動量・速さ、留まった札の払い、横に送る札の行の送りの位置、選んだ札の替わり）を見えない要素 `mypage.tabs.probe` に出す
    /// （`-JPPreviewTabSwipeProbe YES`・Debug のみ・2026-11-13 #187 Mac run 1227・`ProfileTabSwipeLog`）。Release では必ず false
    static var tabSwipeProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewTabSwipeProbe")
        #else
        return false
        #endif
    }

    /// UI テストの事実取りだけ: 写真を大きく見る画面の上下の情報を出しているかを、見えない要素 `viewer.chrome.probe` の値
    /// （shown / hidden）に出す（`-JPPreviewViewerProbe YES`・Debug のみ）。2026-11-12 run 1193: 1回押した後の絵では ✕ と下の
    /// 情報が消えていたのに、UI テストからは `viewer.close`・`viewer.caption` が在るままに見えた（`accessibilityHidden` では
    /// UI テストの木から消えない）。消えたかを推定でなく値で見る。Release では必ず false
    static var viewerProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewViewerProbe")
        #else
        return false
        #endif
    }

    /// UI テストの事実取りだけ: 写真の詳細の「下に引いて戻る」（札 #592）で、写真を引いた量と、その間に画面の器
    /// （シートで開いたときはシートそのもの）が下がった量を、見えない要素 `detail.pull.probe` の値に出す
    /// （`-JPPreviewPullProbe YES`・Debug のみ・`DetailPullProbe`）。ストーリーの「写真を見る」のシートの根で、
    /// シートの「下へ引いて閉じる」と写真を引く動きが二重になるかを、推定でなく値で見る。Release では必ず false
    static var pullProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewPullProbe")
        #else
        return false
        #endif
    }

    /// UI テストの事実取りだけ: 並びの寸法（字の要る幅と札の幅・名前の行の張り出し・安全な範囲の上端）を、見えない要素
    /// （`LayoutProbe`）の値に出す（`-JPPreviewLayoutProbe YES`・Debug のみ・2026-11-13 デザインの点検の確かめ）。
    /// 字が切れたか・当たりが重なるかは画面の木から取れないので、推定でなく数で見る。Release では必ず false
    static var layoutProbe: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewLayoutProbe")
        #else
        return false
        #endif
    }

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

    /// UI テストで旅のスタンプ帳に見本を入れる（Debug のみ・札 #712）。`-JPPreviewStampBook empty|few|many`。
    /// 見本の利用者は鍵を持たず、自分の写真の口を叩けないので、帳面そのものを入れる（写真は持たない）。
    /// 名前は観光スポットの索引にある実在の行（案の頁の模型と同じ）。日付は例。Release では必ず nil
    static let stampBookKey = "JPPreviewStampBook"

    static var stampBookSample: StampBook? {
        #if DEBUG
        guard userId != nil, let kind = UserDefaults.standard.string(forKey: stampBookKey) else { return nil }
        return StampBookSamples.book(kind)
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

    /// 起動のときに出す説明の場面（Debug のみ）。`-JPPreviewPushPrimerMoment reachOut` で初めてのフォロー・コメント・
    /// メッセージのあとの見出しと項目（2026-11-15 札 #618）。無ければ初めての投稿のあと。Release では必ず `.firstPost`
    static let pushPrimerMomentKey = "JPPreviewPushPrimerMoment"

    static var pushPrimerMoment: PushPrimerMoment {
        #if DEBUG
        return UserDefaults.standard.string(forKey: pushPrimerMomentKey) == "reachOut" ? .reachOut : .firstPost
        #else
        return .firstPost
        #endif
    }

    /// 画面写真の試験だけ: 起動のときに「投稿しました」の1枚を見本で1回出す（札 #628・`-JPPreviewPostedSummary YES`・Debug のみ）
    static let postedSummaryKey = "JPPreviewPostedSummary"

    static var opensPostedSummary: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: postedSummaryKey)
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

    /// 旅のトランクの最初の画面を、案の状態の1つで出す（Debug のみ・札 #711）。`-JPPreviewTrunkHome coins`
    /// （手持ち0・硬貨あり）・`none`（どちらも0）・`first`（まだ何も届いていない・揺れと光を毎回）・`loading`（読み込み中のまま）・
    /// `offline`（圏外で前に読んだトランクを出す）。`-JPPreviewTrunk` と一緒のときだけ効く。Release では必ず nil
    static let trunkHomeKey = "JPPreviewTrunkHome"

    static var trunkHome: String? {
        #if DEBUG
        guard trunkSample != nil, let raw = UserDefaults.standard.string(forKey: trunkHomeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ["coins", "none", "first", "loading", "offline"].contains(raw) else { return nil }
        return raw
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

    /// 旅のトランクの見本に、貼ったあと動かした「月崎」の切符（`TrunkSample.creased`）を足し、その動かした回数にする
    /// （Debug のみ・札 #605）。`-JPPreviewTrunkWrinkles 3` でよれの強さ 1（折れ目 3 本）、`0` で同じラベルを
    /// よれなしで描く（よれの層だけを切った絵）。見本の起動のときだけ効く。Release では必ず nil
    static let trunkWrinklesKey = "JPPreviewTrunkWrinkles"

    static var trunkWrinkleMoves: Int? {
        #if DEBUG
        guard trunkSample == .sample, let raw = UserDefaults.standard.string(forKey: trunkWrinklesKey),
              let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else { return nil }
        return min(99, value)
        #else
        return nil
        #endif
    }

    /// 旅のトランクの見本を「好きなデザインで作れる」状態にする（Debug のみ・札 #706）。`-JPPreviewTrunkCustomReady YES` で
    /// 進みが 0・使える回数が 1（届いた画面の主ボタンが「好きなデザインで作る」になる絵）。見本の起動のときだけ効く。
    /// Release では必ず false
    static let trunkCustomReadyKey = "JPPreviewTrunkCustomReady"

    static var trunkCustomReady: Bool {
        #if DEBUG
        guard userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: trunkCustomReadyKey)
        #else
        return false
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

    /// 見本の届いた画面に、初めて押されたスタンプ（札 #712）も添える（`-JPPreviewTrunkArrivedStamp YES`・Debug のみ）
    static var trunkArrivedStamp: StampMoment.Pressed? {
        #if DEBUG
        guard opensTrunkArrived, UserDefaults.standard.bool(forKey: "JPPreviewTrunkArrivedStamp") else { return nil }
        return StampBookSamples.pressed
        #else
        return nil
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
        // App Store の見本（`StoreDemo`）は必ず端末の中で答える（アプリの URLSession の要求は外へ出さない。出るものは `StoreDemo` の注記）
        if StoreDemo.isOn { return true }
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

    /// 見本の通信（`localBackend`）で、**誰もフォローしていない**ことにする（`GET /user/following` は空・フォローする／
    /// 外すは受けたことにする）。ホームの「フォロー中」が空のときの「おすすめの人」（1.1.83・資料「SNS をもっと SNS に」④）を
    /// UI テストで撮る。Release では必ず false
    static let followNoneKey = "JPPreviewFollowNone"

    static var followNone: Bool {
        #if DEBUG
        guard localBackend else { return false }
        return UserDefaults.standard.bool(forKey: followNoneKey)
        #else
        return false
        #endif
    }

    /// 見本の通信（`localBackend`）で、お知らせ（`GET /user/notifications`）に**この端末で書いたコメント**を
    /// 写真へのコメントの知らせとして返す（2026-11-18 案 B4・本文の1行と、押すとそのコメントで返信の欄が開くことを
    /// UI テストで確かめる）。Release では必ず false
    static let commentNoticeKey = "JPPreviewCommentNotice"

    static var commentNotice: Bool {
        #if DEBUG
        guard localBackend else { return false }
        return UserDefaults.standard.bool(forKey: commentNoticeKey)
        #else
        return false
        #endif
    }

    /// 事実取り（2026-11-18・案 B4、Mac の回 1462）: 知らせから来たコメントへ**送るだけ**にして、返信の欄とキーボードを
    /// 出さない。回 1462 で、着いた後のコメントが送られずに写真の頭のまま（y=736・キーボードの裏）だった。
    /// 送る処理そのものが効いていないのか、キーボードを出したことで戻ったのかを分けて測るための印
    /// （`testCommentNoticeScrollProbe`）。Release では必ず false
    static let arrivalScrollOnlyKey = "JPPreviewArrivalScrollOnly"

    static var arrivalScrollOnly: Bool {
        #if DEBUG
        guard localBackend else { return false }
        return UserDefaults.standard.bool(forKey: arrivalScrollOnlyKey)
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

    /// 見本の通信（`dm`）に、グループの DM（`/groups`）の答えを足す（`PreviewBackend.groupReply`・2026-11-20 札 #582）。
    /// **これが無いと `/groups` は 503**（グループの口の無いサーバーと同じ: 入口は出ず、今の1対1のまま）。Release では必ず false
    static let groupsKey = "JPPreviewGroups"

    static var groups: Bool {
        #if DEBUG
        guard dm else { return false }
        return UserDefaults.standard.bool(forKey: groupsKey)
        #else
        return false
        #endif
    }

    /// 見本の通信に「サインインの方法」（`/user/signin-methods`・札 #601）の答えを足す。`-JPPreviewSigninMethods <形>`。
    /// 形は `linked`（メールと Apple・Apple は解除できる）か `last`（Apple で作った人・Apple は最後の1つで解除できない）。
    /// **これが無いと口は 503**（設定の行は出ない・口の無いサーバーと同じ）。Release では必ず nil
    static let signinMethodsKey = "JPPreviewSigninMethods"

    static var signinMethods: String? {
        #if DEBUG
        guard localBackend else { return nil }
        return UserDefaults.standard.string(forKey: signinMethodsKey)
        #else
        return nil
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
