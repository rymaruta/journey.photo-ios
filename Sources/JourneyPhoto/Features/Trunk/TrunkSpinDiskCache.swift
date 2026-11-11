import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 回す箱の絵（正面・側面・背面・上・底・持ち手・付け根の金具）の、端末の置き場（2026-11-11 判断・1 回目に開く間の止まりを縮める）。
///
/// run 1041 / 1047 / 1050: 1 回目に開く間の止まりのほとんどは、SceneKit が絵を読むときに主スレッドで塗る時間だった。
/// 塗った絵を PNG（色を変えない形）で端末に置き、同じトランクなら読み込んで渡す（塗らない）。
///
/// - **1 つのファイル**に、合図（絵に効く全部の欄・アプリの版・言語・文字を太くする設定）と 8 枚の絵を一緒に入れる。
///   ファイルの名前は合図の指紋。読むときは中の合図の文字が**全部同じときだけ**使う（合図と絵が食い違う隙間を作らない）
/// - 書くのは**1 本の列**（`writer`）で順に。退会で消した（`removeAll`）後は、その前に開いた回す画面が描き終えても書かない（`ticket`）
/// - 置くのは最後に開いたトランクの 1 ファイルだけ（書くときに前のものを消す）
/// - 測定用の差し替え（`PreviewSession.trunkDiag`）のうち絵が変わりうるものが付いているときは、読まない・書かない
enum TrunkSpinDiskCache {

    /// 置く絵の名前（正面と、側面・背面・上・底・持ち手・付け根の金具）
    static let names = ["front", "back", "left", "right", "top", "bottom", "handle", "clip"]

    /// 絵を変えない測定用の差し替え（これだけなら読む・書く）。`spindiskfront` は正面だけ読む・書かない比べ
    static let neutralDiag: Set<String> = ["spindiskclear", "spindiskfront", "spinlink", "spincont"]

    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("trunk-spin", isDirectory: true)
    }

    // MARK: 合図

    /// 絵に効くものを全部並べた合図（JSON・鍵の順。名札の名前が無いことと "-" を分ける）
    static func signature(_ key: TrunkSpinKey, bold: Bool = boldText) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "-")(\(info?["CFBundleVersion"] ?? "-"))"
        let wrinkles = key.wrinkles.keys.sorted().map { [$0, String(key.wrinkles[$0]!)] }
        let object: [String: Any] = [
            "version": version,
            "lang": Locale.current.identifier,
            "bold": bold,
            "model": key.model.rawValue,
            "posts": key.posts,
            "owner": key.ownerName.map { $0 as Any } ?? NSNull(),
            "stuck": String(describing: key.stuck),
            "parts": String(describing: key.parts),
            "wrinkles": wrinkles,
            "tags": String(describing: key.tagPicks),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// 文字を太くする設定（アクセシビリティ）。絵に効くかは `TrunkBoldProbe` で測った（合図に入れておく）
    static var boldText: Bool {
        #if os(iOS)
        return UIAccessibility.isBoldTextEnabled
        #else
        return false
        #endif
    }

    /// 合図の指紋（ファイルの名前・FNV-1a 64 ビット）
    static func fingerprint(_ signature: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in signature.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    // MARK: 1 つのファイル（合図＋絵）

    /// ファイルの中身: 頭の長さ（4 バイト・大きい方から）→ 頭（JSON: 合図と各絵の名前・長さ）→ 絵を順に
    static func archive(signature: String, files: [(String, Data)]) -> Data? {
        let header: [String: Any] = ["signature": signature, "files": files.map { ["name": $0.0, "length": $0.1.count] }]
        guard let head = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]) else { return nil }
        var out = Data()
        let length = UInt32(head.count)
        out.append(contentsOf: [UInt8(length >> 24 & 0xff), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
        out.append(head)
        for (_, data) in files { out.append(data) }
        return out
    }

    /// ファイルの中身を開く。合図が `signature` と全部同じときだけ絵を返す
    static func unarchive(_ data: Data, signature: String) -> [String: Data]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard bytes.count >= 4 + length,
              let header = try? JSONSerialization.jsonObject(with: Data(bytes[4..<(4 + length)])) as? [String: Any],
              header["signature"] as? String == signature,
              let files = header["files"] as? [[String: Any]] else { return nil }
        var offset = 4 + length
        var out: [String: Data] = [:]
        for file in files {
            guard let name = file["name"] as? String, let size = file["length"] as? Int, size >= 0,
                  offset + size <= bytes.count else { return nil }
            out[name] = Data(bytes[offset..<(offset + size)])
            offset += size
        }
        return offset == bytes.count ? out : nil
    }

    // MARK: 書く列

    private static let writer = DispatchQueue(label: "trunk-spin-disk", qos: .utility)
    private static let lock = NSLock()
    private static var generationValue = 0

    private static var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return generationValue
    }

    /// 今の札（`removeAll` のたびに変わる）。回す画面を開いたときに取り、書くときに渡す
    static func ticket() -> Int {
        generation
    }

    /// 書く（列に並べる）。札（`ticket`・省けば今）を取った後に `removeAll` されていたら書かない
    /// （開いている間に退会しても、描き終えた後に書き戻さない）
    static func write(files: @escaping @Sendable () -> [(String, Data)]?, signature: String, in dir: URL, ticket: Int? = nil) {
        let asked = ticket ?? generation
        writer.async {
            guard asked == generation, let files = files(), files.count > 0,
                  let data = archive(signature: signature, files: files) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // 1 ファイルだけ残す（前のトランクのものを消してから書く）
            for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: old) }
            try? data.write(to: dir.appendingPathComponent(fingerprint(signature) + ".trunkspin"), options: .atomic)
            TrunkPerfMeter.shared.note("SpinDiskBytes", String(format: "files=%d mb=%.2f", files.count, Double(data.count) / 1_048_576))
            TrunkPerfMeter.shared.hit("SpinDiskSaved")
        }
    }

    /// 読む（合図が全部同じときだけ）
    static func read(signature: String, in dir: URL) -> [String: Data]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(fingerprint(signature) + ".trunkspin")) else { return nil }
        return unarchive(data, signature: signature)
    }

    /// 全部消す（退会・測定）。これより前に頼まれた書き込みは書かない
    static func removeAll(in dir: URL? = directory) {
        lock.lock()
        generationValue += 1
        lock.unlock()
        guard let dir else { return }
        writer.async { try? FileManager.default.removeItem(at: dir) }
    }

    /// 列が空になるまで待つ（試験）
    static func flush() {
        writer.sync {}
    }

    // MARK: 回す画面から使う

    /// 読んでよいか（絵を変える測定用の差し替えが付いていない）
    static var usable: Bool {
        PreviewSession.trunkDiag.subtracting(neutralDiag).isEmpty
    }

    /// 置いた絵を読む（全部そろっていなくても正面があれば返す。測定専用の `spindiskfront` では正面だけ）
    static func load(for key: TrunkSpinKey) -> [String: UIImage]? {
        let diag = PreviewSession.trunkDiag
        if diag.contains("spindiskclear") {
            removeAll()
            flush()
        }
        guard usable, let dir = directory, let files = read(signature: signature(key), in: dir) else { return nil }
        #if os(iOS)
        var out: [String: UIImage] = [:]
        for name in diag.contains("spindiskfront") ? ["front"] : names {
            if let data = files[name], let image = UIImage(data: data, scale: 3) { out[name] = image }
        }
        return out["front"] == nil ? nil : out
        #else
        return nil
        #endif
    }

    /// 読んだ絵から側面などを組む（全部そろっていなければ nil＝その場で描く）
    static func sides(_ images: [String: UIImage]) -> SpinBoxFaces? {
        guard let back = images["back"], let left = images["left"], let right = images["right"], let top = images["top"],
              let bottom = images["bottom"], let handle = images["handle"], let clip = images["clip"] else { return nil }
        return SpinBoxFaces(back: back, left: left, right: right, top: top, bottom: bottom, handle: handle, clip: clip)
    }

    /// 塗った絵を書く（PNG にするのも列の中＝主スレッドの外）
    static func save(front: UIImage?, sides: SpinBoxFaces, for key: TrunkSpinKey, ticket: Int) {
        guard usable, !PreviewSession.trunkDiag.contains("spindiskfront"), let dir = directory else { return }
        let images: [(String, UIImage?)] = [("front", front), ("back", sides.back), ("left", sides.left), ("right", sides.right),
                                            ("top", sides.top), ("bottom", sides.bottom), ("handle", sides.handle), ("clip", sides.clip)]
        let box = DiskImageBox(images: images.compactMap { name, image in image.map { (name, $0) } })
        guard box.images.count == names.count else { return }
        #if os(iOS)
        write(files: {
            let files = TrunkPerfMeter.measure("SpinDiskSave") { box.images.compactMap { name, image in image.pngData().map { (name, $0) } } }
            return files.count == names.count ? files : nil
        }, signature: signature(key), in: dir, ticket: ticket)
        #else
        _ = box
        #endif
    }
}

/// 糸をまたいで絵を渡す入れ物（作った後は読むだけ）
private struct DiskImageBox: @unchecked Sendable {
    let images: [(String, UIImage)]
}
