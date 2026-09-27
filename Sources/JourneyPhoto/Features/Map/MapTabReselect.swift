import Foundation

/// 地図を開いたまま下の「マップ」をもう一度押したときに、何をするか
/// （`TabRouter.mapLocateRequests`・owner の依頼 2026-09-27）。
///
/// 目的地までスクロールしたあと、現在地のボタンを探さずに戻れるように。
/// **現在地のボタンと違い、押すたびに段を進めない**——札を押すたびに
/// 地図が回ると何が起きたか分からない。何度押しても「現在地へ寄せて追う」。
enum MapTabReselect {

    enum Action: Equatable {
        /// 何もしない
        case ignore
        /// 向きに合わせるのをやめ、現在地を追うだけに戻す
        case stopHeading
        /// 現在地を取り直して寄せる（取れたら `onChange(of: location.state)` が寄せる）
        case locate
    }

    /// - Parameters:
    ///   - onScreen: 地図の画面が出ているか。**上に詳細を積んでいる間は動かさない**
    ///     ——iOS は選ばれている札を押すと一番上の画面まで戻すので、1回目は
    ///     「地図へ戻る」だけ。戻ったあとにもう一度押すと現在地へ寄る。
    ///     本命の関所は押した瞬間に見る `TabRouter.mapRootOnScreen`で、これは念のため
    ///   - isMapMode: 地図を出しているか（スポット・リストの間は動かさない）
    ///   - followsLocation: いま自分を追っているか
    ///   - followsHeading: 向いている方向に回しているか
    static func action(onScreen: Bool, isMapMode: Bool,
                       followsLocation: Bool, followsHeading: Bool) -> Action {
        guard onScreen, isMapMode else { return .ignore }
        if followsHeading { return .stopHeading }
        // 既に追っている: 地図は現在地にある（指で動かすと MapKit が追うのをやめる）
        if followsLocation { return .ignore }
        return .locate
    }
}
