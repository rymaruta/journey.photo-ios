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

    /// メモリが足りないと知らされたら手放す
    func testMemoryWarningForgets() async {
        fresh()
        TrunkTextures.keep(key(), faces: faces, box: box)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(TrunkTextures.kept(key()), "メモリが足りないと知らされても絵を持ち続ける")
    }
}
