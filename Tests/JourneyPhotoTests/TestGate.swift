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
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrived = 0

    init(holds: Int = .max) {
        self.holds = holds
    }

    func wait() async {
        arrived += 1
        if opened || arrived > holds { return }
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
/// `beforeRequest` に渡す）。登録の無い道は止めずに通す
struct PathGates: Sendable {
    private let gates: [(path: String, gate: Gate)]

    init(_ gates: [String: Gate]) {
        self.gates = gates.map { ($0.key, $0.value) }
    }

    func wait(for request: URLRequest) async {
        let path = request.url?.path ?? ""
        guard let hit = gates.first(where: { path.contains($0.path) }) else { return }
        await hit.gate.wait()
    }
}
