import Combine
import Foundation
import MapKit

/// 移動の見込みを Apple の地図に聞く（`MKDirections.calculateETA`・2026-11-10 札 #521）。
///
/// 🔴 **聞きすぎない。** Apple の文書: 短い間に多く聞くと `loadingThrottled` で断られる。だから
/// - 聞くのは**開いているプランの区間だけ**（日程の画面が頼んだ区間）
/// - **1つずつ**（前の答えが返ってから次）。間を少し空ける
/// - **同じ区間・同じ手段は控えを使う**（アプリを開いている間だけ。端末にもサーバーにも残さない）
/// - `loadingThrottled` が来たら、その回の残りは聞かずに止める（画面は「少し待ってから開き直すと出ます」）
///
/// 位置は今いる場所を取らない。送るのは日程の場所の座標だけ。料金の口は使わない（アプリの MapKit）
@MainActor
final class TravelEstimator: ObservableObject {

    static let shared = TravelEstimator()

    enum Answer: Equatable {
        case seconds(Int)
        /// 返らない（路線が無い・遠いなど）
        case unavailable
    }

    /// 区間の鍵 → 手段 → 答え
    @Published private(set) var answers: [String: [TripTravel.Mode: Answer]] = [:]
    /// 断られて止めている（`loadingThrottled`）
    @Published private(set) var throttled = false
    /// 公共交通の見込みを聞くか（`TripTravel.modes`）。
    ///
    /// **段0の Mac の試験で確かめた（2026-11-10・run 962・`MapETAProbeTests`）**: シミュレーターから日本の区間で
    /// 公共交通（`.transit`）の見込みが返った。金沢駅 → 東尋坊 車 4290 秒・歩き 76270 秒・公共交通 5324 秒、
    /// 金沢駅 → 兼六園 車 659 秒・歩き 2654 秒・公共交通 1234 秒（失敗は0件）。地方の路線バスの区間までは確かめていない
    nonisolated static let transitAvailable = true

    private var queue: [(leg: TripTravel.Leg, mode: TripTravel.Mode)] = []
    private var running = false
    private var throttledAt: Date?

    /// 間（秒）。続けて聞かない
    private static let gapNanoseconds: UInt64 = 300_000_000
    /// 断られたあと、もう一度聞いてよくなるまで（秒）
    private static let throttleCooldown: TimeInterval = 60

    /// その区間の、返った答え（聞いていない手段は入らない）
    func results(for leg: TripTravel.Leg) -> [TripTravel.Mode: Int] {
        var out: [TripTravel.Mode: Int] = [:]
        for (mode, answer) in answers[leg.key] ?? [:] {
            if case .seconds(let s) = answer { out[mode] = s }
        }
        return out
    }

    /// 聞き終えたか（返らなかった手段も含めて、頼んだ手段が全部そろった）
    func isSettled(_ leg: TripTravel.Leg, modes: [TripTravel.Mode]) -> Bool {
        let got = answers[leg.key] ?? [:]
        return modes.allSatisfy { got[$0] != nil }
    }

    /// 頼む。控えにある・もう並んでいる区間は聞かない
    func request(_ legs: [TripTravel.Leg]) {
        if throttled, let at = throttledAt, Date().timeIntervalSince(at) > Self.throttleCooldown {
            throttled = false
            throttledAt = nil
        }
        guard !throttled else { return }
        // 長い移動（国をまたぐ・国が分からないまま 500km 以上）は聞かない（返らない・意味の無い距離・2026-11-11）
        for leg in legs where !TripTravel.skipsDirections(leg) {
            for mode in TripTravel.modes(for: leg, transitAvailable: Self.transitAvailable) {
                guard answers[leg.key]?[mode] == nil,
                      !queue.contains(where: { $0.leg.key == leg.key && $0.mode == mode }) else { continue }
                queue.append((leg, mode))
            }
        }
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        defer { running = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if answers[next.leg.key]?[next.mode] != nil { continue }
            let result = await Self.ask(next.leg, mode: next.mode)
            switch result {
            case .answer(let answer):
                answers[next.leg.key, default: [:]][next.mode] = answer
            case .throttled:
                throttled = true
                throttledAt = Date()
                queue.removeAll()
                return
            case .failedNetwork:
                // 通信の失敗は「返らない」と決めない（控えに入れず、次に開いたときに聞き直す）
                continue
            }
            try? await Task.sleep(nanoseconds: Self.gapNanoseconds)
        }
    }

    private enum Outcome { case answer(Answer), throttled, failedNetwork }

    private static func ask(_ leg: TripTravel.Leg, mode: TripTravel.Mode) async -> Outcome {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(leg.from.coords)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(leg.to.coords)))
        request.transportType = transport(mode)
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            let seconds = Int(eta.expectedTravelTime)
            return .answer(seconds > 0 ? .seconds(seconds) : .unavailable)
        } catch {
            if let mk = error as? MKError, mk.code == .loadingThrottled { return .throttled }
            if (error as NSError).domain == NSURLErrorDomain { return .failedNetwork }
            return .answer(.unavailable)
        }
    }

    nonisolated static func transport(_ mode: TripTravel.Mode) -> MKDirectionsTransportType {
        switch mode {
        case .walking: return .walking
        case .automobile: return .automobile
        case .transit: return .transit
        }
    }

    /// Apple のマップを開くときの手段の鍵
    nonisolated static func launchMode(_ mode: TripTravel.Mode) -> String {
        switch mode {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .automobile: return MKLaunchOptionsDirectionsModeDriving
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        }
    }

    private nonisolated static func coordinate(_ c: Photo.Coords) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
    }
}
