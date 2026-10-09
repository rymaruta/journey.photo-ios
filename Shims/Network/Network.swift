// Network の模型（電波の有無の見張り `NWPathMonitor` に要るぶんだけ）。
// 本物と同じ名前・同じ形。中身は何もしない（Linux では知らせが来ない）
import Dispatch
import Foundation

public struct NWPath {
    public enum Status: Equatable { case satisfied, unsatisfied, requiresConnection }
    public let status: Status
    public init(status: Status) { self.status = status }
}

public final class NWPathMonitor {
    public init() {}
    public var pathUpdateHandler: ((NWPath) -> Void)?
    public var currentPath: NWPath { NWPath(status: .satisfied) }
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
}
