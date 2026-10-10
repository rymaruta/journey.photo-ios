import Foundation

/// 「作例を重ねて撮る」（Pro・板 ComposeGuide・2026-10-09）の、画面を持たない決まり。
///
/// 画面は `Features/Spots/ComposeGuideView.swift`。ここは Linux でも試験で見張れる計算だけを置く:
/// 作例の濃さの範囲・作例の順（切り替え）・上の札の文・案内の札の文・距離と方角。
///
/// 🔴 **ありもしない数を出さない。** 板の案内の札は「あと [3] m 北へ。地平線を下の線に合わせる」だが、
/// 距離が出せるのは**作例に撮った位置があり、いまの位置も分かるとき**だけ。どちらかが無ければ
/// 距離の文は出さず「地平線を下の線に合わせる」だけにする。
/// 2026-10-09 時点で作例（`SpotSample`・サーバーの `SpotSample`）は撮った位置を持っていない
/// （本文 JSON の `samples` に緯度経度が無い）ので、画面はいつも後者になる。
/// 撮影地（スポット）の座標は「作例を撮った位置」ではないので代わりに使わない。
enum ComposeGuide {

    // MARK: - 作例の濃さ

    /// スライダーの範囲（板の `overlay`: 0〜0.8）。1 にすると映像が見えなくなるので上は 0.8
    static let opacityRange: ClosedRange<Double> = 0...0.8
    /// 開いたときの濃さ（板: 0.35〜0.45 の間）
    static let defaultOpacity = 0.4

    /// 範囲の内側に収める。数でない値（NaN）は既定に戻す
    static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    /// 読み上げで1回に動かす幅（スライダーを指で動かせない人の「上げる・下げる」）
    static let opacityStep = 0.05

    /// 濃さの読み上げの値（「40%」）。0〜0.8 を百分率で
    static func opacityPercent(_ value: Double) -> String {
        "\(Int((clampedOpacity(value) * 100).rounded()))%"
    }

    // MARK: - 作例の順

    /// 次の作例（最後の次は最初へ戻る）。作例が無ければ 0
    static func next(after index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (normalized(index, count: count) + 1) % count
    }

    /// 前の作例（最初の前は最後へ）
    static func previous(before index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (normalized(index, count: count) + count - 1) % count
    }

    /// 範囲の外の番号（作例が減った・壊れて隠れた）を内側へ戻す
    static func normalized(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// 左右に払ったときの行き先。**左へ払う＝次・右へ払う＝前**（写真の送りと同じ向き）。
    /// 短い払いは切り替えない（濃さのスライダーや撮影の指と紛れないように）
    static func swiped(index: Int, count: Int, translationWidth: Double) -> Int {
        guard count > 1, abs(translationWidth) >= swipeThreshold else { return normalized(index, count: count) }
        return translationWidth < 0 ? next(after: index, count: count) : previous(before: index, count: count)
    }

    /// 払いとみなす横の長さ（pt）
    static let swipeThreshold = 60.0

    // MARK: - 上の札

    /// 板: 「[撮影地の名前] · 作例 [2] / [6]」。番号は 1 から
    static func counter(spotName: String, index: Int, count: Int) -> String {
        let shown = count > 0 ? normalized(index, count: count) + 1 : 0
        return L("\(spotName) · 作例 \(shown) / \(count)", "\(spotName) · Example \(shown) / \(count)")
    }

    /// 上の札の読み上げ（「鍋ヶ滝、作例 2 枚目、全 6 枚」）
    static func counterAccessibility(spotName: String, index: Int, count: Int) -> String {
        let shown = count > 0 ? normalized(index, count: count) + 1 : 0
        return L("\(spotName)、作例 \(shown) 枚目、全 \(count) 枚",
                 "\(spotName), example \(shown) of \(count)")
    }

    // MARK: - 案内の札

    /// 着いたとみなす距離（m）。これより近ければ「あと何 m」は言わない（GPS の揺れの内側）
    static let arrivedMeters = 2.0
    /// 案内する距離の上限（m）。これより遠ければ現地に居ないので、歩く案内はしない
    static let guidedMaxMeters = 1_000.0

    /// 構図の一言（板の後半）。距離が出せないときはこれだけを出す
    static var horizonTip: String {
        L("地平線を下の線に合わせる", "Line up the horizon with the lower line")
    }

    /// 案内の札の文。
    ///
    /// - 撮った位置（`target`）・いまの位置（`current`）のどちらかが無い → 「地平線を下の線に合わせる」
    /// - 着いている（2 m 未満）・遠すぎる（1 km 超）→ 同じく一言だけ
    /// - それ以外 → 「あと 3 m 北へ。地平線を下の線に合わせる」
    static func hint(current: Photo.Coords?, target: Photo.Coords?) -> String {
        guard let move = movement(current: current, target: target) else { return horizonTip }
        return L("あと \(move.distance) \(move.direction.ja)へ。\(horizonTip)",
                 "\(move.distance) to the \(move.direction.en). \(horizonTip)")
    }

    /// 歩く案内（距離の文と方角）。出せないときは nil
    struct Movement: Equatable {
        /// 「3 m」「1.2 km」
        let distance: String
        let direction: Compass
        /// 北から時計回りの角度（矢印を回すのに使う）
        let bearing: Double
    }

    static func movement(current: Photo.Coords?, target: Photo.Coords?) -> Movement? {
        guard let current, let target, valid(current), valid(target) else { return nil }
        let meters = distanceMeters(from: current, to: target)
        guard meters.isFinite, meters >= arrivedMeters, meters <= guidedMaxMeters else { return nil }
        let bearing = bearingDegrees(from: current, to: target)
        return Movement(distance: distanceLabel(meters: meters), direction: Compass(bearing: bearing), bearing: bearing)
    }

    /// 距離の書き方: 1 km 未満は 1 m 単位（「3 m」）、それ以上は 0.1 km 単位（「1.2 km」）
    static func distanceLabel(meters: Double) -> String {
        if meters < 999.5 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    /// 2点間の距離（m）。式は `TravelDistance.kilometers`（Web の `haversineKm`）と同じ
    static func distanceMeters(from: Photo.Coords, to: Photo.Coords) -> Double {
        TravelDistance.kilometers(from: from, to: to) * 1000
    }

    /// `from` から見た `to` の方角（北から時計回り・0〜360）
    static func bearingDegrees(from: Photo.Coords, to: Photo.Coords) -> Double {
        let lat1 = from.lat * .pi / 180, lat2 = to.lat * .pi / 180
        let dLng = (to.lng - from.lng) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 8方位
    enum Compass: Int, CaseIterable, Equatable {
        case north, northEast, east, southEast, south, southWest, west, northWest

        /// 角度から（各方位の両側 22.5° ずつ）
        init(bearing: Double) {
            let b = bearing.isFinite ? (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) : 0
            self = Compass(rawValue: Int((b + 22.5) / 45) % 8) ?? .north
        }

        var ja: String { ["北", "北東", "東", "南東", "南", "南西", "西", "北西"][rawValue] }
        var en: String {
            ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][rawValue]
        }
    }

    private static func valid(_ c: Photo.Coords) -> Bool {
        c.lat.isFinite && c.lng.isFinite && abs(c.lat) <= 90 && abs(c.lng) <= 180
    }

    // MARK: - 入口

    /// 入口を出すか。**作例が1枚も無いスポットでは出さない**
    static func showsEntry(sampleCount: Int) -> Bool { sampleCount > 0 }

    /// 撮る画面を開いたときの作例（2026-10-10）。**作例の帯で押した1枚から始める**
    /// （owner の報告「1枚目しか重ねられない」・TestFlight 1.0.84）。入口のボタンは `nil`＝1枚目。
    ///
    /// 押した1枚は**出典のページ（`sourceUrl`）で探す**——番号で渡すと、案内の画面（Pro でない人）を
    /// 経るあいだに読めなかった作例が帯から隠れて、別の1枚から始まる。見つからなければ 1枚目
    static func startIndex(of sourceUrl: URL?, in samples: [SpotSample]) -> Int {
        guard let sourceUrl, let i = samples.firstIndex(where: { $0.sourceUrl == sourceUrl }) else { return 0 }
        return i
    }

    /// 撮る画面を開く頼み（`fullScreenCover(item:)` に渡す）。開くたびに別の頼みにする
    /// （同じ1枚を続けて開いても作り直す）。
    ///
    /// 2026-10-10 判断: **開いた時点の作例の並びを持つ。** 撮る画面を開いている間も裏の帯は読み込みを
    /// 続け、読めなかった1枚は帯から隠れる（`OfficialSpotView.brokenSamples`）。今の並びをそのまま
    /// 渡すと、撮る画面の番号はそのままで並びだけ縮み、見ている作例が別の1枚にずれる
    struct Launch: Identifiable, Equatable {
        let id = UUID()
        /// 撮る画面に渡す作例（開いた時点で固定）
        let samples: [SpotSample]
        /// 始める作例の番号（`samples` の中）
        let start: Int

        /// - Parameters:
        ///   - sample: 始める作例の出典のページ（帯で押した1枚）。入口のボタンは nil＝1枚目
        ///   - samples: いま帯に出している作例
        init(sample: URL?, samples: [SpotSample]) {
            self.samples = samples
            self.start = ComposeGuide.startIndex(of: sample, in: samples)
        }
    }

    /// 入口を押したときの行き先
    enum Destination: Equatable {
        /// 撮る画面（Pro）
        case camera
        /// Pro の案内（Pro でない・ログインしていない。案内の画面がログインを求める）
        case paywall
        /// Pro かどうかを確かめられなかった（圏外など）。**Pro の人に案内を出さない**——知らせだけ
        case unreachable
    }

    /// - Parameters:
    ///   - signedIn: ログインしているか
    ///   - isPro: サーバーのプロフィールの `pro`。読めなかったら nil（権利を決めるのはサーバー）
    static func destination(signedIn: Bool, isPro: Bool?) -> Destination {
        guard signedIn else { return .paywall }
        guard let isPro else { return .unreachable }
        return isPro ? .camera : .paywall
    }

    // MARK: - 撮ったあと

    /// 写真の保存の結果（知らせの文）
    enum SaveOutcome: Equatable {
        case saved
        /// 写真への追加が許可されていない
        case denied
        case failed
    }

    static func message(for outcome: SaveOutcome) -> String {
        switch outcome {
        case .saved: return L("保存しました", "Saved to Photos")
        case .denied: return L("写真への保存が許可されていません。設定アプリで許可してください",
                               "Saving to Photos isn't allowed. Turn it on in Settings.")
        case .failed: return L("保存できませんでした", "Couldn't save the photo")
        }
    }

    // MARK: - カメラが使えないとき

    /// カメラの使える・使えないの段（`AVAuthorizationStatus` と、端末にカメラがあるか から決める）
    enum CameraState: Equatable {
        /// まだ確かめている（許可を尋ねている）
        case preparing
        case ready
        /// 許可されていない（設定アプリへ誘導する）
        case denied
        /// 保護者の設定などで使えない（設定アプリでは変えられないことがある）
        case restricted
        /// この端末にカメラが無い（シミュレータ）・開けなかった
        case unavailable
    }

    /// カメラが使えないときの見出しと説明。使えるときは nil
    static func blockedText(_ state: CameraState) -> (title: String, detail: String)? {
        switch state {
        case .preparing, .ready:
            return nil
        case .denied:
            return (L("カメラの使用が許可されていません", "Camera access is off"),
                    L("作例を重ねて撮るには、設定アプリでカメラを許可してください。",
                      "To shoot with an example overlay, allow camera access in Settings."))
        case .restricted:
            return (L("カメラを使えません", "Camera unavailable"),
                    L("この端末の設定（スクリーンタイムなど）でカメラが制限されています。",
                      "The camera is restricted on this device (for example, by Screen Time)."))
        case .unavailable:
            return (L("カメラを使えません", "Camera unavailable"),
                    L("この端末ではカメラを開けませんでした。", "Couldn't open the camera on this device."))
        }
    }

    /// 設定アプリへの誘導を出すか（許可を断ったときだけ。制限・カメラ無しは設定で直らない）
    static func offersSettings(_ state: CameraState) -> Bool { state == .denied }
}

/// 画面写真の試験（`ScreenshotTests`）だけが、Pro でなくても撮る画面を開くための鍵（2026-10-09）。
///
/// **Release では必ず false**（`#if DEBUG`・`PreviewSession` と同じ決まり）。TestFlight・App Store の
/// ビルドでは、この鍵で Pro の確かめを飛ばせない。`-JPComposeGuidePreview YES` で渡す
enum ComposeGuideAccess {
    static let defaultsKey = "JPComposeGuidePreview"

    static var previewUnlocked: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: defaultsKey)
        #else
        return false
        #endif
    }
}
