import Foundation

/// 持ち主が選んだ並び（ピン留め）。
///
/// **`@MainActor` の型に置かない。** 置くと静的メソッドまで MainActor に
/// 縛られ、テスト（`XCTestCase` のメソッドは isolation を持たない）から
/// 呼べなくなる——`TagInput` / `PhotoQuery` と同じ理由。
enum PhotoPinning {

    /// ピン留めされた写真を先頭に出す。
    ///
    /// **持ち主が選んだ並び**（Web の「先頭にピン留め」・最大3枚）。
    /// `pinnedPhotoIds` は復号していたのにどこでも見ておらず、
    /// **Web で留めた写真がアプリでは普通の位置に沈んでいた**。
    /// 留めた順に前へ、残りは今までどおりの並びのまま。
    static func pinnedFirst(_ photos: [Photo], pinned: [String]) -> [Photo] {
        guard !pinned.isEmpty else { return photos }
        let byId = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // **消された写真の ID が残っていても落ちない**（引けたものだけ前へ）
        let head = pinned.compactMap { byId[$0] }
        let headIds = Set(head.map { $0.id })
        return head + photos.filter { !headIds.contains($0.id) }
    }
}
