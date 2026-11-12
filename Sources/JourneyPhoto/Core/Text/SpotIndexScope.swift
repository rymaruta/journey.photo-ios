import Foundation

/// 撮影スポットの一覧の範囲（`OfficialSpotIndexView` の `Scope`・札 #524）。
///
/// 2026-11-11（確かめ役の指摘）: 地図の区分（`SpotMapArea.scope`）が「すべて見る」の行き先として持つので、
/// 画面の型の中ではなく、画面を持たない層に置く（画面の側は `typealias`）
enum SpotIndexScope: Hashable {
    /// 県（探すの段の写真の札から）
    case prefecture(String)
    /// 地方（`PrefectureRegions.Region.name`）。探すの段の地図の札の「すべて見る」から
    case region(String)
    /// 全国（段の見出しの「すべて見る」から）
    case all
}
