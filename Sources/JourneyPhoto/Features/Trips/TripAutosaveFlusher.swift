import SwiftUI

/// 自動保存の送りを**1本にまとめる**（2026-11-10 確かめ役の指摘 F・札 #521）。
///
/// 送る口（日程の画面の `flush()`）は、2秒の待ち・戻るとき・撮影スポットを開くとき・裏に回るときから呼ばれる。
/// 以前はこれが重なると2本が同時に走り、後の1本が書き込み中で断られて「まだ送れていません」になる・
/// 空の書き込みが1回増える・古い版で誤って「別の端末の変更」になる、があった。
/// いま走っている1本があれば、それが終わるのを待ってから自分の分を走らせる（自分の分は直しが残っているかを
/// 見るので、残っていなければ何も送らない）
@MainActor
final class TripAutosaveFlusher {

    private var running: Task<Bool, Never>?

    func run(_ body: @escaping @MainActor () async -> Bool) async -> Bool {
        while let current = running {
            _ = await current.value
            // 待っている間に別の呼び出しが先に走り始めたら、それも待つ
            if running == current { running = nil }
        }
        let task = Task { @MainActor in await body() }
        running = task
        let result = await task.value
        if running == task { running = nil }
        return result
    }
}

extension TripAutosave {
    /// 裏に回るときに送るか。**background のときだけ**（inactive と background の2回で2本にしない）
    static func sendsOnScenePhase(_ phase: ScenePhase) -> Bool {
        phase == .background
    }
}
