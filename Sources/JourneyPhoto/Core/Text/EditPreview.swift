import Foundation

/// 写真の編集シートの上に出す見本。
///
/// 🔴 **差し替えた後も、見本が古い写真のままだった。** 見本は開いたときの行の
/// `detailImageURL` を出していて、差し替えが済んで「差し替えました」と出ても
/// 上の写真は前のまま——差し替えたのか分からず、もう一度選び直していた。
/// サーバーの派生（小さい版）は作り直しに数分かかるので、**差し替えた回は
/// 手元で送った画像そのもの**を出す。
enum EditPreview {

    enum Source<Local> {
        /// この画面で差し替えた画像（端末にある送った本体）
        case replaced(Local)
        /// 開いたときの写真
        case original(URL?)
    }

    static func source<Local>(replaced: Local?, original: URL?) -> Source<Local> {
        if let replaced { return .replaced(replaced) }
        return .original(original)
    }
}
