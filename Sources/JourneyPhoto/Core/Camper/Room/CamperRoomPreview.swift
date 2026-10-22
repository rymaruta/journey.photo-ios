import Foundation

/// 画面写真の見本の起動（2026-10-19・**Debug だけ**。Release では必ず無し）。`ScreenshotTests` が渡す。
/// - `-JPPreviewCamperRoomReset YES`: 覚えている部屋を読まず、最初の並びで開く（保存もしない・毎回同じ絵）
/// - `-JPPreviewCamperRoomLift YES`: 置く場面で、家具を 1 つ持ち上げてぶつかる所に動かした途中（白と赤のマス）を見せる
/// - `-JPPreviewCamperRoomContact YES`: 部屋に入ったら、板と別種の家具全部を本物の SceneKit で描いた「接写の一覧」を出す
///   （2026-10-21・ソフトラスタではなく本物の絵で全家具の出来を見るため）
/// - `-JPPreviewCamperRoomLegs YES`: 部屋に入ったら、脚のある家具を 1 つずつ 4 方向（正面・斜め・横・低い所）から本物の
///   SceneKit で描いた「脚の接写の一覧」を出す（2026-10-22 owner「椅子とかは家具によって足が壊れてたりする」）
/// - `-JPPreviewCamperRoomCoach YES`: 初めての人への手引きと、新しい家具の印を出す（覚えずに毎回）
/// - `-JPPreviewCamperRoomFrames YES`: 写真を入れられる全部の額に、自分の写真（横長と縦長）を入れた接写の一覧を出す
/// - `-JPPreviewCamperRoomCamera corner|curtain`: 部屋に入った時の向き（手前の右の角・窓の脇のカーテンへ寄る。2026-10-21
///   owner の実機の寄りの絵と同じ所を撮るため）
/// 接写の一覧の種類（`CamperRoomContactSheet`）
enum CamperRoomContactKind: Sendable {
    /// 板と別種の家具（4 点ずつ・昼と夜）
    case board
    /// 写真を入れられる額（横長・縦長の写真を入れて）
    case frames
    /// 脚のある家具（1 頁に 1 つを 4 方向から）
    case legs
}

enum CamperRoomPreview {
    static let cameraKey = "JPPreviewCamperRoomCamera"

    /// 部屋に入った時の寄り（見本の起動だけ）
    static var cameraPreset: String? {
        #if DEBUG
        guard PreviewSession.userId != nil else { return nil }
        return UserDefaults.standard.string(forKey: cameraKey)
        #else
        return nil
        #endif
    }

    static let resetKey = "JPPreviewCamperRoomReset"
    static let liftKey = "JPPreviewCamperRoomLift"
    static let contactKey = "JPPreviewCamperRoomContact"
    static let coachKey = "JPPreviewCamperRoomCoach"
    /// 部屋に入ったら家具を 1 つ選んでおく（「回す・しまう」の札を撮る・2026-10-22）。持ち上げ（`lift`）と両方立てたら持ち上げが勝つ
    static let selectKey = "JPPreviewCamperRoomSelect"
    static let legsKey = "JPPreviewCamperRoomLegs"
    /// 写真を入れられる全部の額に、本物の写真（横長・縦長）を入れた接写の一覧（2026-10-22・楕円の額で写真が筋に崩れた）
    static let framesKey = "JPPreviewCamperRoomFrames"
    static var frames: Bool { flag(framesKey) }

    /// 部屋に入ったら出す接写の一覧の種類（旗が無ければ nil）。2026-10-22 判断: 旗が 2 つ以上立っても決まった 1 つにする
    /// （脚 → 額 → 板の家具の順。画面写真の試験は 1 つの旗だけを渡す）
    static var contactKind: CamperRoomContactKind? {
        if legs { return .legs }
        if frames { return .frames }
        if contact { return .board }
        return nil
    }

    static var reset: Bool { flag(resetKey) }
    static var lift: Bool { flag(liftKey) }
    static var contact: Bool { flag(contactKey) }
    static var coach: Bool { flag(coachKey) }
    static var select: Bool { flag(selectKey) }
    static var legs: Bool { flag(legsKey) }

    private static func flag(_ key: String) -> Bool {
        #if DEBUG
        return PreviewSession.userId != nil && UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }
}
