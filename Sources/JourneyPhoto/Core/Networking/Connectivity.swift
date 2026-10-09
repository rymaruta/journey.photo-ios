import Combine
import Foundation
import Network

/// 電波があるか（「電波なしで使える旅」・板 72c・72d・2026-10-09）。
///
/// `NWPathMonitor` の知らせをそのまま映す。**分からないうちは「ある」**として扱う
/// （起動直後に一瞬だけ圏外の画面を出さない）。圏外の判定は「つながる道が無い」だけ——
/// つながっていてもサーバーが遠いときは、ふつうの画面の「読み込めませんでした」になる
@MainActor
final class Connectivity: ObservableObject {

    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private var started = false

    init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOffline != offline else { return }
                self.isOffline = offline
            }
        }
        monitor.start(queue: DispatchQueue(label: "photo.journey.connectivity"))
    }

    deinit { monitor.cancel() }
}
