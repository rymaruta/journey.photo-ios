import Foundation

/// 旅の写真（`LibraryTripFlowView` で選んで整えた写真）を投稿画面へ渡すかの判断（`RootView`）。
///
/// 渡すのは**整えたもの**（`ImagePreparer.Prepared`・1920px の JPEG と撮影情報）。原本は渡さない
/// ——以前は原本（1枚 数MB〜数十MB）を10枚、投稿画面を閉じるまで持ち続けていた
///
/// 🔴 **前の旅の写真を、次の投稿に混ぜない。** 読み込みの途中で流れを閉じると、
/// 読み終えた写真が控えに入ったまま投稿画面が開かず、次の「写真を投稿」や今日の
/// テーマの投稿に前の旅の写真が並んでいた（しかも非公開で始まる）。だから:
///
/// - 流れから届いた写真は、**流れが開いている間だけ**受ける
/// - 投稿画面に控えを渡すのは**旅の流れから開くときだけ**。ほかの入口は空で開く
enum TripImportHandoff {

    /// 投稿画面を開いた入口
    enum Opener: Equatable {
        /// 投稿の選択の「写真を投稿」
        case photo
        /// 今日のテーマの「参加する」
        case theme
        /// 旅の流れを閉じきったあと
        case tripFlow
    }

    /// 流れから写真が届いたときに控えるもの。閉じたあとに届いた写真は捨てる
    static func received(_ photos: [ImagePreparer.Prepared], flowOpen: Bool) -> [ImagePreparer.Prepared] {
        flowOpen ? photos : []
    }

    /// 投稿画面を開くときに渡す写真
    static func photosForUpload(opener: Opener, pending: [ImagePreparer.Prepared]) -> [ImagePreparer.Prepared] {
        opener == .tripFlow ? pending : []
    }
}
