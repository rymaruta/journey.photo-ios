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
        // **消された写真の ID が残っていても落ちない**（引けたものだけ前へ）。
        // 🔴 **同じ ID が2つあっても1枚だけ前へ。** 2枚並べると格子の ForEach の id が
        // 重なる（LazyVGrid では落ちる例がある）
        var seen = Set<String>()
        let head = pinned.filter { seen.insert($0).inserted }.compactMap { byId[$0] }
        let headIds = Set(head.map { $0.id })
        return head + photos.filter { !headIds.contains($0.id) }
    }
}

/// 写真の詳細の ⋯ の「プロフィールの先頭にピン留め」（資料「説明なしで分かるアプリ」項目9・1.1.85 束H・2026-11-12）。
/// マイページの写真の長押しだけでは、見せたい1枚を先頭に置けると分からなかった。長押しは近道として残す。
/// 押す回数: 長押し → 選ぶ の2回（見えない）→ 写真 → ⋯ → ピン留め の3回（見える）
enum ProfilePinMenu {
    static func title(pinned: Bool) -> String {
        pinned ? L("ピン留めを解除", "Unpin from profile")
               : L("プロフィールの先頭にピン留め", "Pin to top of profile")
    }

    /// 変えたあとの一言
    static func done(pinned: Bool) -> String {
        pinned ? L("プロフィールの先頭にピン留めしました", "Pinned to the top of your profile")
               : L("ピン留めを解除しました", "Unpinned")
    }
}
