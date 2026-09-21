import Foundation

/// 撮影地を「候補から選んだ」ことの扱い。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由——テストから
/// 呼べなくなる。この轍は何度も踏んでいるので最初からこちらに置く）。
enum PlacePick {

    /// 打たれている地名に対して、手元の座標を持ち続けてよいか。
    ///
    /// **選んだ地名から1文字でも離れたら手放す。** 持ち続けると、
    /// 「パリ」を選んでから文字を「ロンドン」に直した回に
    /// **パリの座標がロンドンとして保存される**。しかもサーバーは
    /// 明示的に送られた座標を「正確」と見て `geoApprox` を外すので
    /// （`api-user/src/photoUpdate.ts`）、**間違った場所に確定で刺さる**
    /// ——地図にも JSON-LD にも、直しようのない嘘が載る。
    static func keepsCoords(typed: String, pickedLabel: String?) -> Bool {
        guard let pickedLabel else { return false }
        return typed == pickedLabel
    }
}
