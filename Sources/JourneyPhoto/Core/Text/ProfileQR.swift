import Foundation

/// プロフィールの QR（札 #545・段1・2026-11-11）。
///
/// **QR の中身は Web の人の頁 `https://journey-photo.com/users/<id>`。** アプリが無い人もカメラで読めば
/// Web で開ける（本番で 200 を確かめた・2026-11-11）。リンクでアプリが開く（Associated Domains）のは段2。
///
/// **2026-11-11 判断（owner「QR を読む所と出す所を分けると『どこだっけ？』となる」）: 出す・読むを1つの画面にする。**
/// 画面（`ProfileQRView`）は上に自分の QR、下に相手の QR を読むカメラの小窓。会った2人が同じ画面を開けば、
/// 見せる・読むのどちらでもつながる。入口も1つ（設定の「公開範囲とプライバシー」の札の「プロフィールの QR」）。
///
/// **`@MainActor` の型に置かない**（`InviteLink` と同じ理由。テストから呼べなくなる）。
enum ProfileQR {

    /// 自分の頁の URL。`base` はサイトの根（`AppConfig.siteBaseURL`。本番は journey-photo.com・staging は staging のサイト）
    static func url(userId: String, base: URL) -> URL? {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUserId(trimmed) else { return nil }
        return base.appendingPathComponent("users").appendingPathComponent(trimmed)
    }

    /// 画面に出す短い形（`journey-photo.com/users/…`）。全部の ID は長いので頭だけ見せる
    static func shortLabel(_ url: URL) -> String {
        let host = url.host ?? ""
        return "\(host)/users/…"
    }

    /// 読んだ QR の中身から、開く人の ID を取り出した結果
    enum Read: Equatable {
        /// この人のプロフィールを開く
        case profile(userId: String)
        /// 自分の QR（開かずに「あなたの QR です」と言う）
        case mine
        /// Journey Photo の人の頁ではない（ほかのサイト・文字だけ・招待のリンクなど）
        case other
    }

    /// 読める人の頁の名前（サイト）。本番の2つと、いまの接続先のサイト（staging で試すとき）
    static func acceptedHosts(base: URL) -> Set<String> {
        var hosts: Set<String> = ["journey-photo.com", "www.journey-photo.com"]
        if let host = base.host?.lowercased() { hosts.insert(host) }
        return hosts
    }

    /// QR の中身を読む。**`https://<サイト>/users/<id>` だけ**を人の頁とみなす（末尾の `/`・`?…`・`#…` は無視）。
    /// 写真の頁・招待のリンク・ほかのサイトは `.other`（勝手に開かない）
    static func read(_ text: String, base: URL, viewerId: String?) -> Read {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), acceptedHosts(base: base).contains(host) else { return .other }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "users" else { return .other }
        let id = parts[1].removingPercentEncoding ?? parts[1]
        guard isUserId(id) else { return .other }
        if let viewerId, viewerId == id { return .mine }
        return .profile(userId: id)
    }

    /// 利用者 ID の形（Cognito の sub・英数字とハイフン・下線）。**URL に混ぜても壊れない字だけ**
    static func isUserId(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 128 else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A) || scalar == "-" || scalar == "_"
        }
    }

    /// 読んだ結果の一言（小窓の下に出す）。人の頁なら言わずに開く
    static func message(for read: Read) -> String? {
        switch read {
        case .profile: return nil
        case .mine: return L("これはあなたの QR です", "This is your QR code")
        case .other: return L("Journey Photo のプロフィールの QR ではありません",
                              "This isn't a Journey Photo profile QR code")
        }
    }

    // MARK: - カメラの小窓

    /// カメラの許可（`AVAuthorizationStatus` を写した形。テストから組めるように AVFoundation に寄らない）
    enum Permission: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    /// 小窓に出すもの。**開いただけでは許可を聞かない**（2026-11-11 owner）——まだ聞いていなければ
    /// 「カメラを使うと相手の QR を読めます」と許可のボタン。押したときに初めて聞く
    enum CameraState: Equatable {
        /// まだ聞いていない（許可のボタン）
        case needsPermission
        /// 映像を流している（相手の QR を映せば読む）
        case scanning
        /// 断られた・制限されている（設定アプリへのボタン）
        case denied
        /// 端末にカメラが無い・組み立てられない（シミュレータ）
        case unavailable
    }

    /// 開いたときの小窓。許可済みならそのまま流す（聞かない）
    static func cameraState(hasCamera: Bool, permission: Permission) -> CameraState {
        guard hasCamera else { return .unavailable }
        switch permission {
        case .notDetermined: return .needsPermission
        case .authorized: return .scanning
        case .denied, .restricted: return .denied
        }
    }

    /// 小窓の案内の文（流している間は出さない）
    static func cameraNote(_ state: CameraState) -> String? {
        switch state {
        case .needsPermission: return L("カメラを使うと相手の QR を読めます", "Use the camera to scan someone's QR code")
        case .scanning: return nil
        case .denied: return L("カメラが許可されていません。設定アプリで許可すると相手の QR を読めます",
                               "Camera access is off. Allow it in Settings to scan someone's QR code")
        case .unavailable: return L("この端末ではカメラを使えません", "The camera isn't available on this device")
        }
    }

    /// 小窓のボタンの文（無ければボタンを出さない）
    static func cameraAction(_ state: CameraState) -> String? {
        switch state {
        case .needsPermission: return L("カメラを使う", "Use camera")
        case .denied: return L("設定を開く", "Open Settings")
        case .scanning, .unavailable: return nil
        }
    }
}

/// QR を見せている間だけ画面を明るくする（2026-11-11 判断: 押さなくても上がる＝既定で正しく動く。
/// 相手のカメラが暗い画面の QR を読み損ねないように。Wallet の券と同じ）。
///
/// 上げる前の明るさを覚え、画面を離れた・裏に回ったときに**1度だけ**戻す。もともと最大なら何もしない
struct ProfileQRBrightness: Equatable {

    /// 上げる先（最大）
    static let raised: Double = 1.0

    /// 上げる前の明るさ（上げていなければ nil）
    private(set) var original: Double?

    /// いまの明るさを受けて、上げるなら上げる先を返す（もう上げてある・もともと最大なら nil）
    mutating func raise(current: Double) -> Double? {
        guard original == nil, current < Self.raised else { return nil }
        original = current
        return Self.raised
    }

    /// 戻す明るさ（上げていなければ nil）。戻したら忘れる（2度戻さない）
    mutating func restore() -> Double? {
        defer { original = nil }
        return original
    }
}

/// 人のプロフィールの右上の「…」（札 #545・2026-11-11 に「プロフィールを共有」を足した）
enum UserProfileMenu {

    /// 「…」を出すか。**自分の頁・ブロックしている人には出さない**（自分はマイページの側・ブロック中は通報も共有もしない）。
    /// 未ログインでも出す（中は共有だけ）
    static func showsMenu(viewerId: String?, userId: String, blocked: Bool) -> Bool {
        guard !blocked else { return false }
        return viewerId != userId
    }
}
