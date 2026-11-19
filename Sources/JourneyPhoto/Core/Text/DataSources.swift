import Foundation

/// アプリに同梱したデータの出典（設定 → 利用規約、プライバシーポリシー → データの出典・`LegalLinksView`）。
///
/// 2026-11-19 判断（担当の取りまとめ役）: 共有カードの地図に市区町村の役所の位置（国土数値情報・CC BY 4.0）と
/// 総務省の団体コードを同梱したので、それぞれの決まりが求める出典の表示をアプリの中に置く。Web の規約は変えない。
/// 地図の国と都道府県の輪郭（Natural Earth・パブリックドメイン）も、今まで出していなかったので一緒に並べる。
///
/// 書き方は各決まりの出典記載例に合わせる（「〜を加工して作成」）。中黒「・」で区切らない（owner の好み）
enum DataSources {
    struct Source: Equatable, Identifiable {
        /// 読み上げと UI テストの識別子の末尾
        let id: String
        /// 出典の名前（リンクの字・真鍮）
        let title: String
        /// 何に使っているかと、決まり
        let detail: String
        /// 出典の頁
        let url: URL
    }

    static let all: [Source] = [
        Source(id: "ksj",
               title: L("国土数値情報（国土交通省）", "National Land Numerical Information (MLIT)"),
               detail: L("市区町村役場の位置: 国土数値情報（市町村役場等及び公的集会施設データ）国土交通省、CC BY 4.0 を加工して作成",
                         "Municipal office locations: adapted from National Land Numerical Information (Municipal Offices and Public Meeting Facilities), MLIT, CC BY 4.0"),
               url: URL(string: "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-2022.html")!),
        Source(id: "soumu",
               title: L("総務省「全国地方公共団体コード」", "MIC Local Government Codes"),
               detail: L("市区町村の名前と都道府県: 総務省「全国地方公共団体コード」（令和6年1月1日現在）、公共データ利用規約（第1.0版）を加工して作成",
                         "Municipality names and prefectures: adapted from the Local Government Codes (as of January 1, 2024), Ministry of Internal Affairs and Communications, Public Data License 1.0"),
               url: URL(string: "https://www.soumu.go.jp/denshijiti/code.html")!),
        Source(id: "naturalEarth",
               title: "Natural Earth",
               detail: L("共有カードの地図の国と都道府県の輪郭: Natural Earth（パブリックドメイン）を加工して作成",
                         "Country and prefecture outlines on share card maps: adapted from Natural Earth (public domain)"),
               url: URL(string: "https://www.naturalearthdata.com/")!),
    ]
}
