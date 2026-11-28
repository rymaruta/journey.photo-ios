import Foundation

/// 重い試験の仕事（共有カードの書き出し・画素の計算）を、その台の使える CPU の数だけ同時に流す（札 #610）。
///
/// Mac の単体テストは1つのシミュレーターで1件ずつ順に流れるので、1件の中で CPU だけを使う独立した仕事を
/// 1つずつ順に回すと、その間ほかの CPU が空く。2026-11-14 に共有カードの点検（`ShareCardAuditTests`）を
/// この形にして 303.7 → 91.1秒（run 1332 → 1334）。2026-11-28 に、60枚を順に書き出していた
/// `SignatureShareCardRendererTests.testWorldwideMapExportAcrossAllRatios`（15.1〜18.6秒・run 1866〜1878）も同じ形にした。
/// 返す並びは仕事の番号の順なので、ログと失敗の一覧の順は1つずつ順に流したときと同じ
enum ConcurrentTestJobs {
    /// 同時に流す数（その台の使える CPU の数）
    static var workers: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }

    /// `0..<count` の仕事を `workers` 本まで同時に流し、番号の順に結果を返す
    static func map<T: Sendable>(_ count: Int, _ job: @escaping @Sendable (Int) async throws -> T) async throws -> [T] {
        var results = [T?](repeating: nil, count: count)
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var next = 0
            func start() {
                let index = next
                next += 1
                group.addTask { (index, try await job(index)) }
            }
            while next < min(workers, count) { start() }
            while true {
                guard let done = try await group.next() else { break }
                results[done.0] = done.1
                if next < count { start() }
            }
        }
        return results.map { $0! }
    }
}
