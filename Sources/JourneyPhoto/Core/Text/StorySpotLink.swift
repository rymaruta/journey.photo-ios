import Foundation

/// ストーリーの撮影地から、**撮影スポットのガイド**（`OfficialSpotView`）へつなぐ
/// （2026-09-30・owner「iOS のストーリー機能大好きだからもっと作り込みたい」）。
///
/// 友達の旅先のストーリーから「ここに行きたい」へ一直線につなぐ——インスタに無い、
/// 写真の旅のアプリならではの作り込み。サーバーは変えない（撮影地の文字と約1kmの座標は
/// ストーリーが既に持ち、索引は端末にある）。
///
/// 🔴 **取り違えるくらいなら結ばない。** 結ぶのは次のときだけ:
///  - 撮影地の文字に、**スポットの名前がそのまま入っている**（「高屋神社」「高屋神社（天空の鳥居）」）。
///    市区町村だけの撮影地（「観音寺市, 香川県」）は結ばない——町の真ん中の別の場所を名乗る
///  - 座標があれば **`maxKm` 以内**、いちばん近いもの（同じ名前の別の神社を避ける）
///  - 座標が無ければ、**名前で当たるのが1件だけ**のとき
///  - 下書き（運営未確認）は結ばない
enum StorySpotLink {

    /// 名前が当たっても、これより離れていれば別の場所とみなす（座標はどちらも約1km に丸めてある）
    static let maxKm: Double = 5

    /// 名前として当てる最短の文字数（1文字の名前で何にでも当たらないように）
    static let minNameLength = 2

    static func spot(for story: Story, in spots: [OfficialSpot]) -> OfficialSpot? {
        guard let raw = story.location else { return nil }
        let place = MapSearch.fold(raw)
        guard !place.isEmpty else { return nil }
        let named = spots.filter { spot in
            !spot.isDraft && names(of: spot).contains { place.contains($0) }
        }
        guard !named.isEmpty else { return nil }
        guard let here = story.coords else {
            // 座標が無い: 名前だけでは同じ名前の別の場所を区別できない。1件だけなら結ぶ
            return named.count == 1 ? named[0] : nil
        }
        return named
            .compactMap { spot -> (OfficialSpot, Double)? in
                guard let there = spot.coords else { return nil }
                let km = TravelDistance.kilometers(from: here, to: there)
                return km <= maxKm ? (spot, km) : nil
            }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.slug < $1.0.slug }?
            .0
    }

    /// 当てる名前: 名前・括弧を除いた名前・括弧の中（旧称）・英語名。全角半角・大小は畳む
    static func names(of spot: OfficialSpot) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let s else { return }
            let folded = MapSearch.fold(s)
            if folded.count >= minNameLength { out.append(folded) }
        }
        add(spot.name)
        let (outer, inner) = splitParentheses(spot.name)
        add(outer)
        // 「旧・大石林山」のような括弧の中は、頭の「旧・」を落として当てる
        inner.forEach { add($0.replacingOccurrences(of: "旧・", with: "")) }
        add(spot.nameEn)
        return out
    }

    /// 「A（B）」→ ("A", ["B"])。全角・半角の括弧の両方
    static func splitParentheses(_ name: String) -> (outer: String, inner: [String]) {
        var outer = ""
        var inner: [String] = []
        var current = ""
        var depth = 0
        for ch in name {
            if ch == "（" || ch == "(" {
                depth += 1
                if depth == 1 { current = ""; continue }
            } else if ch == "）" || ch == ")" {
                if depth == 1 { inner.append(current.trimmingCharacters(in: .whitespaces)) }
                depth = max(0, depth - 1)
                continue
            }
            if depth == 0 { outer.append(ch) } else { current.append(ch) }
        }
        return (outer.trimmingCharacters(in: .whitespaces), inner.filter { !$0.isEmpty })
    }
}
