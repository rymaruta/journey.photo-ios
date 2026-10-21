import Foundation

/// 画面写真の見本の起動（2026-10-19・**Debug だけ**。Release では必ず無し）。`ScreenshotTests` が渡す。
/// - `-JPPreviewCamperRoomReset YES`: 覚えている部屋を読まず、最初の並びで開く（保存もしない・毎回同じ絵）
/// - `-JPPreviewCamperRoomLift YES`: 置く場面で、家具を 1 つ持ち上げてぶつかる所に動かした途中（白と赤のマス）を見せる
/// - `-JPPreviewCamperRoomContact YES`: 部屋に入ったら、板と別種の家具全部を本物の SceneKit で描いた「接写の一覧」を出す
///   （2026-10-21・ソフトラスタではなく本物の絵で全家具の出来を見るため）
enum CamperRoomPreview {
    static let resetKey = "JPPreviewCamperRoomReset"
    static let liftKey = "JPPreviewCamperRoomLift"
    static let contactKey = "JPPreviewCamperRoomContact"

    static var reset: Bool { flag(resetKey) }
    static var lift: Bool { flag(liftKey) }
    static var contact: Bool { flag(contactKey) }

    private static func flag(_ key: String) -> Bool {
        #if DEBUG
        return PreviewSession.userId != nil && UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }
}
