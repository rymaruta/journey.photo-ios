import Foundation

/// 写真の編集で、座標を**消すか**・差し替えで**書くか**の決まり。
///
/// **保存済みの値ではなく、この画面での操作で決める。** 判定を画面の外に
/// 置くのは、Linux の模型では画面を動かせず試験できないため。
enum EditPlaceRules {

    /// 開いたときは撮影地が入っていて、いま空（＝本人が消した）
    static func clearedByUser(openedLocation: String?, currentLocation: String) -> Bool {
        !trim(openedLocation ?? "").isEmpty && trim(currentLocation).isEmpty
    }

    /// 保存で `coords: null` を送るか。**本人が撮影地を消したときだけ。**
    /// 開いたときから撮影地が空で座標だけある写真（圏外で投稿した等）は、
    /// 題を直しただけで座標を消さない
    static func clearsCoords(openedLocation: String?, currentLocation: String,
                             pickedCoords: Bool) -> Bool {
        !pickedCoords && clearedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
    }

    /// 差し替えで新しい写真の位置を書くか。**元からピンがあった写真だけ**、
    /// ピンを新しい写真の位置へ動かす。ピンの無い写真（Web の「地図に出さない」で
    /// 外した・撮影地も無い）に位置を戻さない。この画面で撮影地を消したときも書かない
    static func keepsCoordsOnReplace(openedLocation: String?, openedHasCoords: Bool,
                                     currentLocation: String) -> Bool {
        openedHasCoords && !clearedByUser(openedLocation: openedLocation, currentLocation: currentLocation)
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
