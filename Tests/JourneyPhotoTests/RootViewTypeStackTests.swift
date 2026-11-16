import XCTest
@testable import JourneyPhoto
#if canImport(Darwin)
import Darwin
#endif

/// **起動の画面（`RootView`）の型の入れ子の深さと、型を組み立てるときのスタックの量**（1.1.99 の起動で落ちた件・2026-11-16）。
///
/// TestFlight 1.1.99 の実機（iOS 27.2.1）の落ちた記録は `EXC_BAD_ACCESS (SIGSEGV)`・「Thread stack size exceeded」。
/// メインスレッド（1008K）を使い切った所は、`RootView.tabsBase.getter` の
/// `__swift_instantiateConcreteTypeFromMangledNameV2` から上の 85 段がすべて、型の名前から型を組み立て直す
/// 再帰（`decodeMangledType`・`_checkGenericRequirements`）だった（札 #596 のストーリーの画面と同じ形）。
/// 1.1.99 は `tabsBase` に `.overlay`（AI の旅行プランの帯）と `.sheet`（その日程）を足していた。
///
/// 直しは、段（`tabBar` → `tabsUnread` → `tabsBase` → … → `tabsWithFoundingGift`）の頭を型の境目
/// （`viewTypeBoundary`・`AnyView`）で切ったこと。ここでは段ごとの具体的な型（`RootView.typeSegments`）の
/// 入れ子の深さを測り、上限を超えたら落とす。測った数は `measured rootTypeStack` の行に出す（Mac の `xcodebuild-full.log`）。
/// 名前は本物の SwiftUI でないと意味が無い（Linux の模型の修飾子は素通し）ので、上限は iOS（Mac の模擬機）だけで見る
@MainActor
final class RootViewTypeStackTests: XCTestCase {

    /// 段を全部並べている（名前が重ならない）
    func testSegmentsAreListed() async {
        let segments = RootView.typeSegments()
        XCTAssertEqual(segments.count, 15)
        XCTAssertEqual(Set(segments.map(\.name)).count, segments.count)
    }

    #if os(iOS)
    /// 1つの型の深さの上限（ストーリーの画面の `StoryViewTypeDepthTests.depthLimit` と同じ）。Mac の模擬機で測った数:
    /// - 直す前（1.1.99 の main cb03fdd・回 1407）: `body` 157・`tabsWithFoundingGift` 146 … `tabsBase` 46
    ///   （名前から組み立て直すスタックは `body` 211136 バイト・`tabsBase` 76160 バイト。基準の `Int` は 66480）
    /// - 境目を入れた後（回 1410）: いちばん深いのは `tabsBase` 35 → 前半を `tabsUnread` に分けた
    static let depthLimit = 24

    /// **どの段も上限以下**。超えたら、その段の中に境目（`viewTypeBoundary`）を足す
    func testRootViewSegmentsStayShallow() async {
        let baseline = TypeStackProbe.decodeBytes(Int.self)
        print("measured rootTypeStack part=baseline(Int) bytes=\(baseline)")
        var worst: (name: String, depth: Int) = ("", 0)
        for segment in RootView.typeSegments() {
            let name = String(reflecting: segment.type)
            let depth = ViewTypeDepth.depth(of: name)
            let bytes = TypeStackProbe.decodeBytes(segment.type)
            print("measured rootTypeStack part=\(segment.name) depth=\(depth) bytes=\(bytes) length=\(name.count)")
            if depth > worst.depth { worst = (segment.name, depth) }
            XCTAssertLessThanOrEqual(depth, Self.depthLimit, "\(segment.name): \(name)")
        }
        print("measured rootTypeStack worst=\(worst.name) depth=\(worst.depth) limit=\(Self.depthLimit)")
    }
    #endif
}

#if canImport(Darwin)
/// 型を名前から組み立て直すときに使うスタックの量を測る（`RootViewTypeStackTests`）。
///
/// 大きいスタックの別のスレッドで、使っていない所に印（0xA5）を塗ってから組み立て直し、
/// 印が消えたいちばん深い所までの長さを数える（スレッドの頭からのバイト数。測る段のすぐ下 8KB は塗らないので、それより浅い分は見えない）
enum TypeStackProbe {
    private final class Box: @unchecked Sendable { var bytes = 0 }

    /// `type` の名前（`_mangledTypeName`）を `_typeByName` で組み立て直すのに使ったスタックのバイト数。2回測って大きい方
    static func decodeBytes(_ type: Any.Type) -> Int {
        guard let mangled = _mangledTypeName(type) else { return -1 }
        return max(measure { _ = _typeByName(mangled) }, measure { _ = _typeByName(mangled) })
    }

    /// `body` を 16MB のスタックのスレッドで走らせ、スレッドの頭から一番深く使った所までのバイト数を返す
    static func measure(_ body: @escaping () -> Void) -> Int {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.bytes = paintRunScan(body)
            done.signal()
        }
        thread.stackSize = 16 << 20
        thread.start()
        done.wait()
        return box.bytes
    }

    @inline(never)
    private static func paintRunScan(_ body: () -> Void) -> Int {
        let me = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(me))
        let bottom = top - UInt(pthread_get_stacksize_np(me))
        var anchor = 0
        let here = withUnsafeMutablePointer(to: &anchor) { UInt(bitPattern: $0) }
        // ガードの近くと、自分の段のすぐ下（塗る処理の段）は塗らない
        let lo = (bottom + 64 * 1024) & ~UInt(7)
        let hi = (here - 8 * 1024) & ~UInt(7)
        let words = Int(hi - lo) / 8
        guard words > 0, let base = UnsafeMutablePointer<UInt64>(bitPattern: lo) else { return -1 }
        let mark: UInt64 = 0xA5A5_A5A5_A5A5_A5A5
        base.initialize(repeating: mark, count: words)
        body()
        var i = 0
        while i < words && base[i] == mark { i += 1 }
        withExtendedLifetime(anchor) {}
        return Int(top - (lo + UInt(i * 8)))
    }
}
#endif
