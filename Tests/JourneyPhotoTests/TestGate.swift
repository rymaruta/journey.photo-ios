import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 待たせておいて、合図で先へ進める。**「取得の途中」「遅い口」を作る**ための道具。
///
/// 🔴 **遅さを `URLProtocol` の応答で作らない。** 別のスレッドから
/// `URLProtocol` の `client` を叩くと、Linux の swift-corelibs-foundation では
/// まれに（約1%）落ちる（segfault）。応答を作業列に戻す形はデッドロックした
/// （前の作業の記録。ここでは再現を確かめていない）。
/// だから `StubProtocol` は即座に答え、待たせるのは要求を出す**手前**
/// （トークンの提供者・サービスの `beforeRequest`）に置く。
///
/// `holds` は**先頭から何回ぶんを止めるか**。それより後に着いた呼び出しは
/// 止めずに通す——「2回目は止まらずに進むこと」を見る試験で、壊れたときに
/// 待ち続けて試験ごと固まらないように。
actor Gate {
    private let holds: Int
    private let skip: Int
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrived = 0

    /// - Parameter skip: 先頭から何回ぶんを**止めずに通すか**（「1回目は通し、2回目を止める」用）
    init(holds: Int = .max, skip: Int = 0) {
        self.holds = holds
        self.skip = skip
    }

    func wait() async {
        arrived += 1
        if opened || arrived <= skip || arrived - skip > holds { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// `count` 回ぶん `wait()` に着くまで待つ。**上限（既定2秒）で試験を落とす**
    /// ——壊れて誰も着かない回に、Linux の XCTest は1件ごとの時間切れが無いので
    /// 全体の実行ごと止まる
    func untilWaiting(_ count: Int = 1, timeout: TimeInterval = 2,
                      file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while arrived < count {
            if Date() > deadline {
                XCTFail("Gate に \(count) 回着かなかった（\(arrived) 回）", file: file, line: line)
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// トークンを渡す前に `gate` で待つ提供者。**API の要求を「飛んでいる途中」にする**
struct GatedTokenProvider: TokenProviding {
    let token: String?
    let gate: Gate
    func idToken() async throws -> String? {
        await gate.wait()
        return token
    }
}

/// 道（URL のパス）ごとの `Gate`。**「この口だけ遅い」を作る**（`APIClient` の
/// `beforeRequest` に渡す）。登録の無い道は止めずに通す。
///
/// 鍵は道の一部（`"/user/profile"`）か、メソッドつき（`"POST /photos/p1/comments"`
/// ——一覧の読み込みと送信が同じ道の口を分ける）。**いちばん長く当たる鍵を使う**
/// （辞書の並びは実行ごとに変わるので、先に当たった方を使うと回ごとに揺れる）
struct PathGates: Sendable {
    private let gates: [(method: String?, path: String, gate: Gate)]

    init(_ gates: [String: Gate]) {
        self.gates = gates.map { key, gate in
            let parts = key.split(separator: " ", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1], gate) : (nil, key, gate)
        }
    }

    func wait(for request: URLRequest) async {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let hit = gates
            .filter { path.contains($0.path) && ($0.method == nil || $0.method == method) }
            .max { $0.path.count < $1.path.count }
        guard let hit else { return }
        await hit.gate.wait()
    }
}
