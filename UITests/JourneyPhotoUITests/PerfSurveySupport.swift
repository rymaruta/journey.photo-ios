import XCTest

/// 札 #594「アプリ全体を軽くする」の下調べ（`PerformanceTests.testUsageSurveyProbe`）で、アプリの通しの記録
/// （`PerfTimeline`・見えない要素 `perf.timeline`）を読んで、**段ごとの数**にする道具（2026-11-13）。
///
/// 値の形（アプリの `PerfTimeline.summary()` と同じ。変えるときは両方と `PerfTimelineTests`）:
///
///     t=12345 | st=[2604:424,5434:227] | mem=[1000:85,2000:120] | cnt=[body.home:14,body.map:3] | rs=[+18322 A`a^B`b;+19022 …]
struct PerfTimelineReading {
    static let identifier = "perf.timeline"

    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    func section(_ key: String) -> String {
        for part in raw.components(separatedBy: " | ") where part.hasPrefix(key + "=") {
            var value = String(part.dropFirst(key.count + 1))
            if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
            return value
        }
        return ""
    }

    /// アプリの時計（起動からの ms）。値は 0.5 秒ごとに更新されるので、読んだ時刻より最大 0.5 秒古い
    var nowMs: Int { Int(section("t")) ?? 0 }

    /// 停止の全部（始め ms, 長さ ms）
    var stalls: [(startMs: Int, gapMs: Int)] {
        pairs(section("st"))
    }

    /// 溢れて残らなかった停止の数
    var droppedStalls: Int {
        section("st").split(separator: ",").compactMap { part -> Int? in
            guard part.hasPrefix("+"), part.hasSuffix("dropped") else { return nil }
            return Int(part.dropFirst().dropLast("dropped".count))
        }.first ?? 0
    }

    /// メモリ（時刻 ms, MB）
    var memory: [(ms: Int, mb: Int)] {
        pairs(section("mem")).map { ($0.0, $0.1) }
    }

    /// body の評価回数（通しの累計）
    var counts: [String: Int] {
        var out: [String: Int] = [:]
        for part in section("cnt").split(separator: ",") {
            guard let colon = part.lastIndex(of: ":"), let n = Int(part[part.index(after: colon)...]) else { continue }
            out[String(part[..<colon])] = n
        }
        return out
    }

    /// 積みの見本（撮った ms, 段を `^` でつないだもの）
    var samples: [(ms: Int, stack: String)] {
        section("rs").split(separator: ";").compactMap { entry in
            let text = String(entry)
            guard text.hasPrefix("+"), let space = text.firstIndex(of: " "),
                  let ms = Int(text[text.index(after: text.startIndex)..<space]) else { return nil }
            return (ms, String(text[text.index(after: space)...]))
        }
    }

    private func pairs(_ text: String) -> [(Int, Int)] {
        text.split(separator: ",").compactMap { part in
            let kv = part.split(separator: ":")
            guard kv.count == 2, let a = Int(kv[0]), let b = Int(kv[1]) else { return nil }
            return (a, b)
        }
    }
}

/// 1 段の数（始めと終わりの読み取りの差）
struct PerfSurveyStage {
    let name: String
    let startMs: Int
    let endMs: Int
    /// 試験の側で測った段の壁時計（ms・読み取りの待ちを除く）
    let wallMs: Int
    let stallCount: Int
    let stallMaxMs: Int
    let stallTotalMs: Int
    let memPeakMB: Int
    let memEndMB: Int
    /// 段の間に増えた body の評価回数（名前ごと・0 は除く）
    let bodies: [(String, Int)]
    /// 段の間に撮った積みの見本（浅い方の段と、このアプリの段）
    let samples: [String]

    var bodyTotal: Int { bodies.reduce(0) { $0 + $1.1 } }

    /// 段の始めと終わりの読み取り（時刻と body の累計）と、**全部の段を流し終えた後の読み取り**（停止とメモリ）から作る。
    /// 停止は「始めが段の中」のものを数える（段の境目をまたぐ停止は、始まった段の分にする。段の終わりの読み取りの時点で
    /// まだ止まっていた分も、後の読み取りには入っている）。積みの見本は、どの読み取りで見えたものも集めた `samplePool` から
    /// （アプリは新しい方の 12 件しか出さないので、段ごとに読んで溜める）
    init(name: String, from start: PerfTimelineReading, to end: PerfTimelineReading, final: PerfTimelineReading,
         samplePool: [(ms: Int, stack: String)], wallMs: Int) {
        self.name = name
        self.wallMs = wallMs
        startMs = start.nowMs
        endMs = end.nowMs
        let inside = final.stalls.filter { $0.startMs >= start.nowMs && $0.startMs < end.nowMs }
        stallCount = inside.count
        stallMaxMs = inside.map(\.gapMs).max() ?? 0
        stallTotalMs = inside.reduce(0) { $0 + $1.gapMs }
        let mem = final.memory.filter { $0.ms > start.nowMs && $0.ms <= end.nowMs }
        memPeakMB = mem.map(\.mb).max() ?? 0
        memEndMB = mem.last?.mb ?? 0
        let before = start.counts
        bodies = end.counts.compactMap { key, value -> (String, Int)? in
            let delta = value - (before[key] ?? 0)
            return delta > 0 ? (key, delta) : nil
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        samples = samplePool.filter { $0.ms > start.nowMs && $0.ms <= end.nowMs }.map { "+\($0.ms) \($0.stack)" }
    }
}

/// 段ごとの数を XCTest の `measured [...]` の行に出す（`Tools/perf-collect.py` が拾う）。
/// 中身は試験の本体が段を流し終えてから入れる。`measure` の何回目でも同じ値を返す（平均がそのまま段の値になる）
final class PerfSurveyMetric: NSObject, XCTMetric, @unchecked Sendable {
    let stages: [PerfSurveyStage]

    init(stages: [PerfSurveyStage]) {
        self.stages = stages
    }

    func copy(with zone: NSZone? = nil) -> Any {
        PerfSurveyMetric(stages: stages)
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp,
                            to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        var out: [XCTPerformanceMeasurement] = []
        for (i, s) in stages.enumerated() {
            let id = "com.journeyphoto.survey.s\(i + 1)"
            let label = "Survey \(i + 1) \(s.name)"
            func add(_ key: String, _ title: String, _ value: Int, _ unit: String) {
                out.append(XCTPerformanceMeasurement(identifier: "\(id).\(key)", displayName: "\(label) \(title)",
                                                     doubleValue: Double(value), unitSymbol: unit))
            }
            add("stallTotal", "stall total", s.stallTotalMs, "ms")
            add("stallMax", "stall max", s.stallMaxMs, "ms")
            add("stalls", "stalls", s.stallCount, "count")
            add("body", "body", s.bodyTotal, "count")
            add("memPeak", "memory peak", s.memPeakMB, "MB")
            add("wall", "wall", s.wallMs, "ms")
        }
        return out
    }
}
