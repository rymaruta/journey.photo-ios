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
        XCTAssertTrue(base.contains("v="), "アプリの版が合図に無い")
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

    /// 退会したら端末の正面の絵も消す（貼ったラベルの地名が描かれている）
    func testAccountRemovalForgetsTheDiskImage() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Storage/AccountLocalData.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("TrunkSpinDiskCache.removeAll()"), "退会しても回す箱の正面の絵が端末に残る")
    }

    /// メモリが足りないと知らされたら手放す
    func testMemoryWarningForgets() async {
        fresh()
        TrunkTextures.keep(key(), faces: faces, box: box)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(TrunkTextures.kept(key()), "メモリが足りないと知らされても絵を持ち続ける")
    }
}
