import Foundation
import Combine

/// 下の札を外から切り替える道（見出しの「探す」→ 探す、メニュー → 各札）。
///
/// **押した回数で伝える。** 真偽値にすると、マイページから別の札へ移って
/// もう一度押したときに「変わっていない」と見なされて効かない
/// （`NotificationRouter` / `MissionRouter` と同じ理由）。
@MainActor
final class TabRouter: ObservableObject {

    static let shared = TabRouter()

    @Published private(set) var myPageRequests = 0

    func openMyPage() { myPageRequests += 1 }

    /// 見出しの「探す」（ホームだけ・板 01c）とメニューの「撮影地マップ」から
    @Published private(set) var searchRequests = 0
    @Published private(set) var mapRequests = 0
    /// 見出しの「メニュー（≡）」（板 01d）。**シートは `RootView` が出す**
    @Published private(set) var menuRequests = 0

    func openSearch() { searchRequests += 1 }
    /// 探すの0件の出口から来たときの検索語。地図が一度だけ受け取る
    /// （`takePendingMapQuery`）。渡さないと地図が空の絞りで開き、打ち直すことになる
    private(set) var pendingMapQuery: String?

    /// - Parameter query: nil＝地図の絞りに触れない（メニュー・注目スポットから）。
    ///   空の語＝**地図の前の語を消す**（タグで探した0件から。タグの語は地図で当たらないが、
    ///   前に地図で打った語が残ると、探していたものと関係ない絞りで開く）。
    ///   語なしで呼ばれた回は、待っていた語も捨てる（古い語で絞った地図を出さない）
    func openMap(query: String? = nil) {
        pendingMapQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        mapRequests += 1
    }

    /// 地図が受け取る。受け取ったら消す（戻ってくるたびに絞り直さない）。
    ///
    /// 🔴 **地図の根（`mapRootOnScreen`）が出ていない間は渡さず残す。** 詳細を積んだまま
    /// 絞り直すと、語が見えないうえ、押した元の `NavigationLink` が消えて詳細が黙って閉じる。
    /// 根に戻った `onAppear` で受け取る
    func takePendingMapQuery(rootOnScreen: Bool) -> String? {
        guard rootOnScreen else { return nil }
        defer { pendingMapQuery = nil }
        return pendingMapQuery
    }
    func openMenu() { menuRequests += 1 }

    /// **ホームを開いたまま、下の「ホーム」をもう一度押した回数。**
    /// ホームのフィードはこれを見て一番上まで戻る（Instagram・X と同じ動き。
    /// owner の依頼・2026-09-25）。回数で伝えるのは上と同じ理由——
    /// 真偽値だと2回目以降に「変わっていない」と見なされて効かない
    @Published private(set) var homeTopRequests = 0

    /// **地図を開いたまま、下の「マップ」をもう一度押した回数。**
    /// 地図はこれを見て現在地へ戻る（ホームの一番上へ戻るのと同じ考え。
    /// owner の依頼・2026-09-27）。回数で伝えるのは上と同じ理由
    @Published private(set) var mapLocateRequests = 0

    /// 地図の一番上の画面（`PhotoMapView`）が出ているか。地図が
    /// `onAppear` / `onDisappear` で書く。
    ///
    /// 🔴 **押した瞬間にここで見る。** 詳細を積んだまま「マップ」を押すと、
    /// iOS は一番上まで戻す——その戻りで地図の `onAppear` が先に走るか、
    /// 合図を受ける `onChange` が先かは SwiftUI 次第で、地図の側で見ると
    /// 1回押しただけで「戻る」と「現在地へ」が両方起きうる。
    /// 押した時点ではまだ戻っていないので、ここで見れば順序に左右されない
    var mapRootOnScreen = false

    /// **下の「投稿」から出した写真・ストーリーの画面を閉じた回数。**
    ///
    /// 投稿の入口は下の札の「投稿」1つ（整理案 05c でマイページの
    /// 「投稿する」を外した）。そのシートは `RootView` にあり、マイページや
    /// ストーリーの行からは閉じたことが見えない——投稿しても、マイページの
    /// 格子とストーリーの行が引き下げるまで古いままだった。
    /// 回数で伝えるのは上と同じ理由
    @Published private(set) var postSheetsClosed = 0

    func postSheetClosed() { postSheetsClosed += 1 }

    /// **メニュー（≡）のシートを閉じた回数。** メニューから旅行プランを開いて
    /// 変えても、シートの下のホームは画面から消えた扱いにならないので、
    /// ホームの上段の札が古いプランのまま残った。回数で伝えるのは上と同じ理由
    @Published private(set) var menuSheetsClosed = 0

    func menuSheetClosed() { menuSheetsClosed += 1 }

    /// もう一度押したときに合図を出す札
    enum Reselectable {
        case home, map
    }

    /// 下の札が押された。**選ばれている札をもう一度押したときだけ**
    /// 合図を出す（別の札から来たときは何もしない＝開き直しで勝手に
    /// 上へ飛ばない・現在地へ引き戻さない）。受け取るのはホームと地図
    func tabTapped(_ tab: Reselectable?, alreadySelected: Bool) {
        // 人が下の札を押した＝探すの出口の続きではない。残っていた語が
        // あとで（詳細から根へ戻ったときなど）勝手に当たらないよう捨てる。
        // `openMap` の移動は札を押さない（RootView が selection を直に書く）ので、ここを通らない。
        // 🔴 **ただし詳細を積んだ地図で「マップ」を押し直した回は捨てない。** iOS が根まで戻し、
        // 待っていた語はその `onAppear` で受け取る（捨てると何も届かない）
        let returnsToMapRoot = alreadySelected && tab == .map && !mapRootOnScreen
        if !returnsToMapRoot { pendingMapQuery = nil }
        guard alreadySelected, let tab else { return }
        switch tab {
        case .home: homeTopRequests += 1
        case .map:
            // 詳細を開いていた回は「地図へ戻る」だけ（iOS がやる）。現在地へは次の1回で
            guard mapRootOnScreen else { return }
            mapLocateRequests += 1
        }
    }
}
