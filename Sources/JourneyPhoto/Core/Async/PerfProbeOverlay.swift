import SwiftUI
#if os(iOS)
import UIKit
#endif

/// `PerfRecorder.summary()` を読み上げの値に出す見えない要素（UI テストのときだけ置く・`-JPPreviewPerfProbe YES`）。
///
/// `CamperRenderProbe` と同じ作り: 0.5 秒ごとに**自分の中だけ**描き直す（親の画面は動かさない）。
/// 見えない 1pt・押せない。識別子は `perf.probe`（UI テストは `PerfProbeSupport` で読む）
struct PerfProbeOverlay: View {
    static let identifier = "perf.probe"

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { _ in
            Text(" ")
                .font(.system(size: 1))
                .accessibilityLabel("perf probe")
                .accessibilityValue(PerfRecorder.shared.summary())
                .accessibilityIdentifier(Self.identifier)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .onAppear { PerfStallWatcher.shared.start() }
    }
}

/// 画面の表示の刻み（`CADisplayLink`）の間隔を `PerfRecorder` に渡す。メインスレッドが止まると刻みが遅れるので、
/// 間隔が 100ms を超えた回数と最大の間隔が、メインスレッドの停止の数になる（`StallMeter`）。
/// 無効のとき（本番・ふつうの起動）は始めない。iOS 以外（Linux の型検査）では何もしない
final class PerfStallWatcher: NSObject {
    static let shared = PerfStallWatcher()

    #if os(iOS)
    private var link: CADisplayLink?

    func start() {
        guard link == nil, PerfRecorder.shared.isEnabled else { return }
        // メインスレッドが止まっている間の積みを撮る見張りも始める（同じ UI テストのときだけ）
        // **Debug のビルドだけ**（Release からは `PerfMainSampler` ごと消える＝信号の受け手も見張りのスレッドも作られない）
        #if DEBUG
        PerfMainSampler.shared.start()
        #endif
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // 裏に入る間は刻みが止まる。戻った直後の長い空きを停止に数えない
        NotificationCenter.default.addObserver(self, selector: #selector(resetFrames),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func tick(_ link: CADisplayLink) {
        PerfRecorder.shared.recordFrame(at: link.timestamp)
    }

    @objc private func resetFrames() {
        PerfRecorder.shared.resetFrames()
    }
    #else
    func start() {}
    #endif
}

// **Debug のビルドだけ。** Release では丸ごと消える（`SIGUSR1` の受け手・見張りのスレッド・`backtrace` の呼び出しが
// バイナリに入らない）。有効になる条件も `-JPPreviewPerfProbe YES`（Debug のみ true）と二重（2026-11-07 owner の確認事項）
#if os(iOS) && DEBUG
import Darwin

// MARK: - メインスレッドの積み(スタック)の見本（2026-11-07・札 #435 / #429）

/// 信号の受け手が書く置き場。**信号の受け手の中では確保も鍵も使えない**ので、先に確保しておく
private let perfSampleCapacity = 48
nonisolated(unsafe) private let perfSampleBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 48)
nonisolated(unsafe) private var perfSampleDepth: Int32 = 0

/// `SIGUSR1` を受けたスレッド（メインスレッド）が、自分の積みを置き場に書く
private func perfSampleHandler(_ signal: Int32) {
    perfSampleDepth = backtrace(perfSampleBuffer, Int32(perfSampleCapacity))
}

/// Swift の名前の戻し（`swift_demangle`）。`@_silgen_name` の本体なし宣言は、構文検査（tree-sitter）が読めない
/// （`Tools/verify.sh` の NG になる）ので、実行時に `dlsym` で探す（2026-11-07）。見つからなければ nil（名前を戻さないだけ）
private typealias PerfDemangleFn = @convention(c) (UnsafePointer<CChar>?, UInt, UnsafeMutablePointer<CChar>?,
                                                    UnsafeMutablePointer<UInt>?, UInt32) -> UnsafeMutablePointer<CChar>?

private let perfDemangleFn: PerfDemangleFn? = {
    guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "swift_demangle") else { return nil }
    return unsafeBitCast(symbol, to: PerfDemangleFn.self)
}()

private func perfSwiftDemangle(_ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt,
                               _ outputBuffer: UnsafeMutablePointer<CChar>?, _ outputBufferSize: UnsafeMutablePointer<UInt>?,
                               _ flags: UInt32) -> UnsafeMutablePointer<CChar>? {
    perfDemangleFn?(mangledName, mangledNameLength, outputBuffer, outputBufferSize, flags)
}

/// メインスレッドが止まっている間（`DispatchQueue.main` に投げた合図が 150ms 戻らない間）に、別のスレッドから
/// メインスレッドへ `SIGUSR1` を送り、**止まっている最中の積み（何の処理を実行しているか）**を撮って `PerfRecorder` に渡す。
/// 1 回の停止で最大 3 枚（150ms・400ms・650ms）。**測るだけ**: UI テストのとき（`-JPPreviewPerfProbe YES`・Debug のみ）だけ始める。
/// 本番・ふつうの起動では `start()` が何もしない
final class PerfMainSampler: @unchecked Sendable {
    static let shared = PerfMainSampler()

    private let lock = NSLock()
    private var started = false
    private var mainThread: pthread_t?
    /// 投げた合図がまだ戻っていないとき、投げた時刻（`systemUptime`）
    private var pendingSince: TimeInterval?

    /// メインスレッドから呼ぶ（そのスレッドを覚える）
    func start() {
        guard PerfRecorder.shared.isEnabled, Thread.isMainThread else { return }
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        mainThread = pthread_self()
        lock.unlock()
        _ = perfSampleBuffer
        signal(SIGUSR1, perfSampleHandler)
        let thread = Thread { [self] in watch() }
        thread.name = "perf.sampler"
        thread.qualityOfService = .userInteractive
        thread.start()
        // 止まっている所を、画面の木を読まずに取り出す（`-JPMainSampleFile <path>`・2026-11-12 run 1164 の DM の会話）。
        // 主スレッドが忙しいと UI テストは画面の木を取れない（"Failed to get matching snapshots"）ので、決まった間隔で
        // 主スレッドの積みと、主スレッドに投げた合図が戻るまでの時間をファイルに書き、試験の側がファイルを読む
        if let path = UserDefaults.standard.string(forKey: Self.fileKey), !path.isEmpty {
            let fileThread = Thread { [self] in fileLoop(path: path) }
            fileThread.name = "perf.sampler.file"
            fileThread.qualityOfService = .userInteractive
            fileThread.start()
        }
    }

    /// 決まった間隔で積みを書くファイルの道（UI テストが渡す）
    static let fileKey = "JPMainSampleFile"
    /// 積みを撮る所が2つ（停止の見張り・ファイル）あるので、信号の置き場を1つずつ使う
    private let captureLock = NSLock()

    /// 0.3 秒ごとに 1 行: 起動からの ms・壁時計（UTC の `HH:mm:ss.SSS`）・主スレッドの返事の遅れ
    /// （ms。0.3 秒で戻らなければ pending）・主スレッドの積み。書くのは 1500 行まで。
    /// 壁時計は、UI テストのログ（行頭の UTC の時刻）の操作（要素を探す・押す）と突き合わせるため（2026-11-13 札 #590）
    private func fileLoop(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        let origin = ProcessInfo.processInfo.systemUptime
        let wall = DateFormatter()
        wall.locale = Locale(identifier: "en_US_POSIX")
        wall.timeZone = TimeZone(identifier: "UTC")
        wall.dateFormat = "HH:mm:ss.SSS"
        var lines = 0
        while lines < 1500 {
            let sent = ProcessInfo.processInfo.systemUptime
            let sentWall = wall.string(from: Date())
            let reply = DispatchSemaphore(value: 0)
            let box = PerfPingBox()
            DispatchQueue.main.async {
                box.set(ProcessInfo.processInfo.systemUptime)
                reply.signal()
            }
            let answered = reply.wait(timeout: .now() + 0.3) == .success
            let ping = answered ? String(Int(((box.value ?? sent) - sent) * 1000)) : "pending"
            let frames = captureFrames() ?? []
            let top = Array(frames.prefix(8))
            let app = frames.dropFirst(8).filter { $0.hasPrefix("JourneyPhoto") }.prefix(10)
            let ms = Int((sent - origin) * 1000)
            let line = "ms=\(ms) wall=\(sentWall) ping=\(ping) | " + (top + (app.isEmpty ? [] : ["…"]) + Array(app)).joined(separator: " ; ") + "\n"
            handle.write(Data(line.utf8))
            lines += 1
            if answered { Thread.sleep(forTimeInterval: 0.3) }
        }
        try? handle.close()
    }

    private func watch() {
        var samplesInEpisode = 0
        while true {
            Thread.sleep(forTimeInterval: 0.02)
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock()
            let since = pendingSince
            if since == nil { pendingSince = now }
            lock.unlock()
            guard let since else {
                samplesInEpisode = 0
                DispatchQueue.main.async { [self] in
                    lock.lock()
                    pendingSince = nil
                    lock.unlock()
                }
                continue
            }
            // 150ms・400ms・650ms 待っても戻らなければ撮る
            if samplesInEpisode < 3, now - since > 0.15 + 0.25 * Double(samplesInEpisode) {
                samplesInEpisode += 1
                capture()
            }
        }
    }

    private func capture() {
        guard let frames = captureFrames() else { return }
        // 浅い方の 7 段（いま実行中の処理）と、その先にある**このアプリの段**（`JourneyPhoto` の画像）を 6 段まで。
        // 浅い方が SwiftUI の中ばかりでも、どの画面の何が呼んだかが残る（2026-11-07）
        let top = Array(frames.prefix(7))
        let app = frames.dropFirst(7).filter { $0.hasPrefix("JourneyPhoto") }.prefix(6)
        PerfRecorder.shared.recordSample(frames: top + (app.isEmpty ? [] : ["…"]) + Array(app))
    }

    /// 主スレッドの今の積み（読めなければ nil）
    private func captureFrames() -> [String]? {
        captureLock.lock()
        defer { captureLock.unlock() }
        guard let thread = mainThread else { return nil }
        perfSampleDepth = 0
        guard pthread_kill(thread, SIGUSR1) == 0 else { return nil }
        var waited = 0
        while perfSampleDepth == 0, waited < 100 {
            Thread.sleep(forTimeInterval: 0.001)
            waited += 1
        }
        let depth = Int(perfSampleDepth)
        guard depth > 0 else { return nil }
        var frames: [String] = []
        for index in 0..<min(depth, perfSampleCapacity) {
            guard let address = perfSampleBuffer[index] else { continue }
            let text = Self.describe(address)
            // 受け手自身と信号の入口は、見たい積みではない
            if text.contains("perfSampleHandler") || text.contains("_sigtramp") { continue }
            frames.append(text)
        }
        return frames
    }

    /// 「画像`名前」。名前は Swift の綴りに戻す。長いものは切る。名前が無ければ画像と番地
    private static func describe(_ address: UnsafeMutableRawPointer) -> String {
        var info = Dl_info()
        guard dladdr(address, &info) != 0 else { return "?" }
        let image = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "?" } ?? "?"
        guard let symbol = info.dli_sname else {
            return "\(image)`+0x\(String(UInt(bitPattern: address) &- UInt(bitPattern: info.dli_fbase), radix: 16))"
        }
        var name = String(cString: symbol)
        let length = UInt(strlen(symbol))
        if let demangled = perfSwiftDemangle(symbol, length, nil, nil, 0) {
            name = String(cString: demangled)
            free(demangled)
        }
        // 見やすくするため切る（区切りの `;` `^` と空白は別の字に）
        // `protocol witness for … in conformance Foo : Bar` は型名が後ろにある。前を短くして型名を残す（どの型か分かるように）
        if let range = name.range(of: " in conformance ") {
            name = String(name.prefix(36)) + "…" + String(name[range.upperBound...].prefix(70))
        }
        let cut = String(name.prefix(110))
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "^", with: "~")
        return "\(image)`\(cut)"
    }
}
/// 主スレッドが合図を受けた時刻（ファイルの見張りが読む・鍵つき）
private final class PerfPingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TimeInterval?
    func set(_ value: TimeInterval) { lock.lock(); stored = value; lock.unlock() }
    var value: TimeInterval? { lock.lock(); defer { lock.unlock() }; return stored }
}
#endif
