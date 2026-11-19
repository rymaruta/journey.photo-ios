import Foundation

/// 市区町村の代表点（役所・役場のおおよその位置）。座標の無い写真の共有カードの地図のピンに使う
/// （2026-11-19 owner「金沢市, 石川県なら金沢市にピン」・`SignatureShareCardRenderer.shareMapPoint`）。
///
/// 同梱の表 `japan-municipal-offices.json`（約1,890行・約64KB。作り方は `Tools/generate-municipal-offices.py`）:
/// - 出典: 「国土数値情報（市町村役場等及び公的集会施設データ）」（国土交通省）P05 令和4年を加工して作成
///   （https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-2022.html ・CC BY 4.0）
/// - 名前と県: 「全国地方公共団体コード」（総務省・令和6年1月1日現在）を加工して作成
///   （https://www.soumu.go.jp/denshijiti/code.html ・公共データ利用規約 第1.0版）
/// - 2026-11-19 判断: アプリの中には全国の市区町村の座標の表が無かった（観光スポット・検索の索引はサーバーから読む一部だけ、
///   `PassExchange.prefectureOffices` は県だけ）ので同梱した。ネットには問い合わせない
///
/// 同じ名前の市区町村（港区・府中市・朝日町など）は県と組み合わせて引く。県が分からず名前が重なるときは引かない
enum MunicipalOffices {
    struct Entry: Equatable {
        let prefecture: String
        let name: String
        let coords: Photo.Coords
    }

    /// `[[県の番号(1-47), 名前, 緯度, 経度], …]` を読む。形の合わない行は落とす
    static func parse(_ data: Data) -> [Entry] {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
        return rows.compactMap { row in
            guard row.count == 4, let index = (row[0] as? NSNumber)?.intValue,
                  RegionList.prefectures.indices.contains(index - 1),
                  let name = row[1] as? String,
                  let lat = (row[2] as? NSNumber)?.doubleValue, let lng = (row[3] as? NSNumber)?.doubleValue
            else { return nil }
            return Entry(prefecture: RegionList.prefectures[index - 1], name: name, coords: Photo.Coords(lat: lat, lng: lng))
        }
    }

    /// アプリに同梱した表（初めて使うときに1回だけ読む）
    static let bundled: [Entry] = {
        guard let url = Bundle.main.url(forResource: "japan-municipal-offices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return parse(data)
    }()

    /// 「ヶ」「ケ」の揺れ（鎌ケ谷市・鎌ヶ谷市）をそろえる
    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "ヶ", with: "ケ").replacingOccurrences(of: "ヵ", with: "カ")
    }

    /// 市区町村の代表点。県が分かればその県の中で引く。県が分からなければ、名前が全国で1つのときだけ。
    /// 政令市の区は表では「名古屋市港区」の形なので、県が分からないときは「港区」を東京都の港区と見なさない
    /// （名古屋市・大阪市の港区と重なる名前として数える）
    static func office(named name: String, prefecture: String?, among entries: [Entry]) -> Photo.Coords? {
        let key = normalized(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let tail = key.last, "市区町村".contains(tail) else { return nil }
        if let prefecture {
            let hits = entries.filter { $0.prefecture == prefecture && normalized($0.name) == key }
            return hits.count == 1 ? hits[0].coords : nil
        }
        let hits = entries.filter { entry in
            let other = normalized(entry.name)
            return other == key || (other.hasSuffix(key) && other.dropLast(key.count).hasSuffix("市"))
        }
        return hits.count == 1 ? hits[0].coords : nil
    }
}
