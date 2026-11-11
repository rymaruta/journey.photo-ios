import XCTest
import UIKit
@testable import JourneyPhoto

/// 回す画面の絵の使い回し（`TrunkTextures.keep` / `kept` / `forget`・2026-11-11 判断 B）を、本物の値で確かめる。
/// 2 回目に開く間の止まりを 4.3→0.8 秒にした仕組み（run 1019）。取っておいた絵が別のトランクに出ない・手放す道があることを守る
@MainActor
final class TrunkSpinCacheTests: XCTestCase {

    private func label(_ id: String) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: .place, place: .init(name: "京都", latin: "Kyoto", country: nil), seed: 1,
                   at: "2026-04-03T09:00:00Z")
    }

    private func key(model: TrunkModel = .leather, posts: Int = 12, stuck: [TrunkLabel]? = nil, ownerName: String? = "ゆき",
                     parts: TrunkEquipped = .none, wrinkles: [String: Double] = ["a": 0.2],
                     tagPicks: [TrunkTagPick] = []) -> TrunkSpinKey {
        TrunkSpinKey(model: model, posts: posts, stuck: stuck ?? [label("a")], ownerName: ownerName, parts: parts,
                     wrinkles: wrinkles, tagPicks: tagPicks)
    }

    private let faces = MedalTextures.Faces(front: nil, back: nil, edge: nil, edgeRepeat: 1)
    private let box = SpinBoxFaces(back: nil, left: nil, right: nil, top: nil, bottom: nil, handle: nil, clip: nil)

    /// 試験ごとに空から始め、終わったら空に戻す（ほかの試験に絵を残さない）
    private func fresh() {
        UserDefaults.standard.removeObject(forKey: PreviewSession.trunkDiagKey)
        TrunkTextures.forget()
        addTeardownBlock { @MainActor in TrunkTextures.forget() }
    }

    /// 取っておく → 同じ鍵で使い回す → 手放すと使い回さない
    func testKeepThenKeptThenForget() async {
        fresh()
        XCTAssertNil(TrunkTextures.kept(key()), "何も取っておいていないのに使い回した")
        TrunkTextures.keep(key(), faces: faces, box: box)
        XCTAssertNotNil(TrunkTextures.kept(key()), "取っておいた絵を同じトランクで使い回さない")
        TrunkTextures.forget()
        XCTAssertNil(TrunkTextures.kept(key()), "手放した後も使い回している")
    }

    /// 鍵の欄を 1 つずつ変えると使い回さない（別のトランクの絵を出さない）
    func testEveryFieldOfTheKeyMatters() async {
        fresh()
        TrunkTextures.keep(key(), faces: faces, box: box)
        let changed: [(String, TrunkSpinKey)] = [
            ("model", key(model: .canvas)),
            ("posts", key(posts: 13)),
            ("stuck", key(stuck: [label("a"), label("b")])),
            ("ownerName", key(ownerName: "はる")),
            ("parts", key(parts: TrunkEquipped(handle: "rope"))),
            ("wrinkles", key(wrinkles: ["a": 0.5])),
            ("tagPicks", key(tagPicks: [.removed])),
        ]
        for (field, other) in changed {
            XCTAssertNil(TrunkTextures.kept(other), "\(field) が違うのに前の絵を使い回した")
        }
        XCTAssertNotNil(TrunkTextures.kept(key()), "同じ鍵なのに使い回さない")
    }

    /// 端末に置く正面の絵の合図（`TrunkSpinDiskCache.signature`）: 同じトランクなら同じ文字、どの欄が違っても違う文字
    /// （別のトランクの絵を出さない）。手ざわりの辞書の並びには左右されない。アプリの版を含む（描き方が変わった版の絵を使わない）
    func testDiskSignatureCoversEveryField() async {
        fresh()
        let base = TrunkSpinDiskCache.signature(key())
        XCTAssertEqual(base, TrunkSpinDiskCache.signature(key()), "同じトランクで合図が変わる")
        XCTAssertEqual(TrunkSpinDiskCache.signature(key(wrinkles: ["a": 0.2, "b": 0.4])),
                       TrunkSpinDiskCache.signature(key(wrinkles: ["b": 0.4, "a": 0.2])), "手ざわりの並びで合図が変わる")
        let json = try? JSONSerialization.jsonObject(with: Data(base.utf8)) as? [String: Any]
        XCTAssertNotNil(json?["version"], "アプリの版が合図に無い")
        XCTAssertNotNil(json?["lang"], "言語が合図に無い")
        XCTAssertNotNil(json?["bold"], "文字を太くする設定が合図に無い")
        let changed: [(String, TrunkSpinKey)] = [
            ("model", key(model: .canvas)),
            ("posts", key(posts: 13)),
            ("stuck", key(stuck: [label("a"), label("b")])),
            ("ownerName", key(ownerName: "はる")),
            ("parts", key(parts: TrunkEquipped(handle: "rope"))),
            ("wrinkles", key(wrinkles: ["a": 0.5])),
            ("tagPicks", key(tagPicks: [.removed])),
        ]
        for (field, other) in changed {
            XCTAssertNotEqual(TrunkSpinDiskCache.signature(other), base, "\(field) が違うのに合図が同じ")
        }
    }

    /// 端末から読んだ絵は、側面・背面・上・底・持ち手・金具が全部そろったときだけ使う（欠けていたらその場で描く）
    func testDiskSidesNeedEveryImage() async {
        fresh()
        var images: [String: UIImage] = [:]
        for name in TrunkSpinDiskCache.names { images[name] = UIImage() }
        XCTAssertNotNil(TrunkSpinDiskCache.sides(images), "全部そろっているのに使わない")
        for name in TrunkSpinDiskCache.names where name != "front" {
            var missing = images
            missing[name] = nil
            XCTAssertNil(TrunkSpinDiskCache.sides(missing), "\(name) が欠けているのに使った")
        }
        XCTAssertEqual(TrunkSpinDiskCache.names.count, 8, "置く絵の数が変わった")
    }

    /// 同じ id のラベルでも、図柄の種・置き場・箔押しが違えば使い回さない（作り直し・動かした後に前の絵を出さない）
    func testSameLabelIdWithOtherLooksIsNotReused() async {
        fresh()
        let place = TrunkLabel.Place(name: "京都", latin: "Kyoto", country: nil)
        func one(seed: Int = 1, foil: Bool = false, pos: TrunkPos? = nil) -> [TrunkLabel] {
            [TrunkLabel(id: "a", photoId: "a", kind: .place, place: place, seed: seed, at: "2026-04-03T09:00:00Z", foil: foil, pos: pos)]
        }
        TrunkTextures.keep(key(stuck: one()), faces: faces, box: box)
        XCTAssertNotNil(TrunkTextures.kept(key(stuck: one())))
        XCTAssertNil(TrunkTextures.kept(key(stuck: one(seed: 2))), "図柄を作り直したのに前の絵を使い回した")
        XCTAssertNil(TrunkTextures.kept(key(stuck: one(foil: true))), "箔押しが違うのに前の絵を使い回した")
        XCTAssertNil(TrunkTextures.kept(key(stuck: one(pos: TrunkPos(x: 0.3, y: 0.4, rot: 8)))), "動かしたのに前の絵を使い回した")
        // 端末の合図も同じく変わる
        let base = TrunkSpinDiskCache.signature(key(stuck: one()))
        for other in [one(seed: 2), one(foil: true), one(pos: TrunkPos(x: 0.3, y: 0.4, rot: 8))] {
            XCTAssertNotEqual(TrunkSpinDiskCache.signature(key(stuck: other)), base)
        }
    }

    /// 合図は JSON で区切る: 名札の名前が無いことと "-" を分ける。文字を太くする設定も合図に入る
    func testSignatureSeparatesNilAndBold() async {
        fresh()
        XCTAssertNotEqual(TrunkSpinDiskCache.signature(key(ownerName: nil)), TrunkSpinDiskCache.signature(key(ownerName: "-")))
        XCTAssertNotEqual(TrunkSpinDiskCache.signature(key(), bold: false), TrunkSpinDiskCache.signature(key(), bold: true))
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trunk-spin-test-" + UUID().uuidString, isDirectory: true)
    }

    private let blobs: [(String, Data)] = TrunkSpinDiskCache.names.enumerated().map { ($0.element, Data(repeating: UInt8($0.offset), count: 10 + $0.offset)) }

    /// 1 つのファイルの中身（合図＋絵）: 開くと同じ絵が戻る。合図が 1 字でも違えば開かない
    func testArchiveRoundTripAndSignatureMismatch() async throws {
        fresh()
        let data = try XCTUnwrap(TrunkSpinDiskCache.archive(signature: "A", files: blobs))
        let back = try XCTUnwrap(TrunkSpinDiskCache.unarchive(data, signature: "A"))
        XCTAssertEqual(back.count, blobs.count)
        for (name, blob) in blobs { XCTAssertEqual(back[name], blob, name) }
        XCTAssertNil(TrunkSpinDiskCache.unarchive(data, signature: "B"), "合図が違うのに絵を返した")
        XCTAssertNil(TrunkSpinDiskCache.unarchive(data.prefix(data.count - 1), signature: "A"), "欠けたファイルの絵を返した")
    }

    /// 書く→読む（列に並べて書き終えた後）。別の合図では読めない。書くと前のトランクのファイルは消える
    func testWriteThenReadOnTheDisk() async {
        fresh()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = blobs
        TrunkSpinDiskCache.write(files: { first }, signature: "A", in: dir)
        TrunkSpinDiskCache.flush()
        XCTAssertEqual(TrunkSpinDiskCache.read(signature: "A", in: dir)?["front"], blobs[0].1, "書いた絵を読めない")
        XCTAssertNil(TrunkSpinDiskCache.read(signature: "B", in: dir), "別の合図で読めた")
        TrunkSpinDiskCache.write(files: { first }, signature: "B", in: dir)
        TrunkSpinDiskCache.flush()
        XCTAssertNil(TrunkSpinDiskCache.read(signature: "A", in: dir), "前のトランクのファイルが残っている")
        XCTAssertNotNil(TrunkSpinDiskCache.read(signature: "B", in: dir))
    }

    /// 消した後に、その前に頼まれた書き込み・その前に開いた画面の書き込みは書かない（退会の後に書き戻さない）
    func testRemoveAllDropsPendingWrites() async {
        fresh()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = blobs
        TrunkSpinDiskCache.write(files: { Thread.sleep(forTimeInterval: 0.05); return first }, signature: "A", in: dir)
        TrunkSpinDiskCache.removeAll(in: dir)
        TrunkSpinDiskCache.flush()
        XCTAssertNil(TrunkSpinDiskCache.read(signature: "A", in: dir), "消した後に、前に頼まれた絵を書いた")
        // 回す画面を開いた（札を取った）後に退会し、その後に描き終えて書こうとしても書かない
        let opened = TrunkSpinDiskCache.ticket()
        TrunkSpinDiskCache.removeAll(in: dir)
        TrunkSpinDiskCache.write(files: { first }, signature: "A", in: dir, ticket: opened)
        TrunkSpinDiskCache.flush()
        XCTAssertNil(TrunkSpinDiskCache.read(signature: "A", in: dir), "退会の後に、その前に開いた画面の絵を書き戻した")
        // 札を取り直せば書ける
        TrunkSpinDiskCache.write(files: { first }, signature: "A", in: dir, ticket: TrunkSpinDiskCache.ticket())
        TrunkSpinDiskCache.flush()
        XCTAssertNotNil(TrunkSpinDiskCache.read(signature: "A", in: dir))
    }

    /// 開いたときの札は、開くときの消去（測定）の後に取る＝その回の書き込みは落ちない（run 1066）
    func testOpenTicketIsTakenAfterClearing() async {
        fresh()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = blobs
        let opened = TrunkSpinDiskCache.open()
        XCTAssertEqual(opened, TrunkSpinDiskCache.ticket(), "開いた直後の札が今の札と違う（その回の絵を書かない）")
        TrunkSpinDiskCache.write(files: { first }, signature: "A", in: dir, ticket: opened)
        TrunkSpinDiskCache.flush()
        XCTAssertNotNil(TrunkSpinDiskCache.read(signature: "A", in: dir), "開いた回の絵を書かない")
    }

    /// 退会（`AccountLocalData.remove`）で端末の絵が消える
    func testAccountRemovalForgetsTheDiskImage() async throws {
        fresh()
        let dir = try XCTUnwrap(TrunkSpinDiskCache.directory)
        let first = blobs
        TrunkSpinDiskCache.write(files: { first }, signature: "A", in: dir)
        TrunkSpinDiskCache.flush()
        XCTAssertNotNil(TrunkSpinDiskCache.read(signature: "A", in: dir))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trunk-spin-removal-" + UUID().uuidString))
        let temp = tempDir()
        AccountLocalData.remove(userId: "A", username: nil, defaults: defaults, draftDirectory: temp, offlineTripsRoot: temp, passRoot: temp)
        TrunkSpinDiskCache.flush()
        XCTAssertNil(TrunkSpinDiskCache.read(signature: "A", in: dir), "退会しても回す箱の絵が端末に残る")
    }

    /// メモリが足りないと知らされたら手放す
    func testMemoryWarningForgets() async {
        fresh()
        TrunkTextures.keep(key(), faces: faces, box: box)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(TrunkTextures.kept(key()), "メモリが足りないと知らされても絵を持ち続ける")
    }
}
