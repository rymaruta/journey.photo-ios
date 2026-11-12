import Foundation

/// 地図を**なぞる**操作の状態（探すの撮影スポットの段の地図・札 #524 の続き・2026-11-11）。
///
/// 長押し（0.25 秒）に届いたら始まり、指の下の区分を `area` に持つ。離したら、離した点の区分を選ぶ
/// （地図の外で離したら選ばない）。**取り消し（スクロール・電話・タブの切り替え）では必ず空に戻る**——
/// 塗りと札がなぞった区分のまま残らない（確かめ役の指摘）。
///
/// 指の出来事は UIKit の長押しの認識（`SpotMapTraceCatcher`）が届ける。2026-11-11 判断（run 1022 の数）:
/// SwiftUI の「長押し → 引く」（`LongPressGesture.sequenced(before: DragGesture)`）は、`.gesture` でも
/// `.simultaneousGesture` でも地図の上から払った指を取り、画面が流れなかった（地図の y 680.7 → 680.7。
/// その操作を外すと 680.7 → 322.7 と流れた）。UIKit の長押しは 0.25 秒より前に 10pt 動くと失敗し、指は画面のスクロールへ渡る。
/// UIKit は取り消しを `.cancelled` で必ず届けるので、`@GestureState` の代わりにここで空に戻す
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
struct SpotMapTrace: Equatable {

    /// 指の下の区分（なぞっている間だけ）
    private(set) var area: String?

    enum Event: Equatable {
        /// 長押しに届いた・指が動いた（指の下の区分。区分の外なら nil で、前の区分のまま）
        case began(String?)
        case changed(String?)
        /// 離した（離した点の区分。地図の外なら nil）
        case ended(String?)
        /// 取り消された
        case cancelled
    }

    /// 出来事を当てる。**選ぶ区分**（離した点の区分）を返す。ほかは nil
    mutating func handle(_ event: Event) -> String? {
        switch event {
        case .began(let next), .changed(let next):
            if let next { area = next }
            return nil
        case .ended(let picked):
            area = nil
            return picked
        case .cancelled:
            area = nil
            return nil
        }
    }
}
