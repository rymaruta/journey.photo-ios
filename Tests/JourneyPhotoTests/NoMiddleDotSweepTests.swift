import XCTest
@testable import JourneyPhoto

/// 画面の文で「・」「·」を区切りに使わない（2026-11-12 owner・1.1.84 で既存の約 560 か所を一度に直した）。
///
/// 直し方:
/// - 文の中で並べるとき（「人・建物・木など」）は「、」。英語は「, 」
/// - 名前と時刻・件数・場所などの欠片の間（「わたしの車 · キャンピングカー」）は余白（en space・字の大きさの半分＝12〜16pt の字で 6〜8pt）
/// - 二つの名詞の名前（「国・地域」「空・海」）は「と」
///
/// コードの中の文字列（注記を除く）を全部読み、許した所のほかに中黒が残っていないことを見る。
/// 新しい文に中黒を書くとここで落ちる
final class NoMiddleDotSweepTests: XCTestCase {

    /// 区切りではない・画面に出ない中黒（ファイル名と、文字列の中身）
    static let allowed: Set<String> = [
        "CamperCatalog.swift|・",                       // 番号の桁の埋め（記号の並び）
        "ContactText.swift|・",                         // 電話番号を読むときに読み飛ばす字
        "DailyQuiz.swift|Journey Photo · Where is this? \\(shortDate(date)) ✓",  // ほかの SNS に貼る共有の文
        "DailyQuiz.swift|Journey Photo · Where is this? \\(shortDate(date)) ✗",
        "PrefectureMapGeometry.swift|九州・沖縄",          // 地方の名前（索引・地図の鍵と同じ）
        "SpotRegionMap.swift|九州・沖縄",
        "StorySpotLink.swift|旧・",                      // 撮影スポットの旧名を読むための目印
        "SunTimes.swift|ボスニア・ヘルツェゴビナ",          // 国の名前
        "OfficialSpotView.swift|・",                    // 箇条書きの頭の印（区切りではない）
        "ModerationService.swift|理由・補足（任意）:",      // 運営に届く通報の本文（画面に出ない）
        "ModerationService.swift|\\(passNoteMarker) 署名なし（写真の持ち主が書いたとは限らない・写真の通報ではない）",
        "OfficialSpotService.swift|[spots] 読めなかった・重複した索引の行を \\(list.dropped) 件落としました",  // ログ
        "OfficialSpotService.swift|[spots] 読めなかった・重複した索引の行・区分を \\(parsed.dropped) 件落としました",
        "OfficialSpotService.swift|[spots] 読めなかった・重複した区分の行を \\(list.dropped) 件落としました",
        "ShareCardMap.swift|（）()、，,・ 　/",            // 利用者の書いた地名を切る字
        "ShareCardText.swift|・",                       // 利用者の書いた題を折り返す字
        "TripPlanFixture.swift|金沢・福井の旅",            // 見本の利用者の題（利用者の書いた文の見本）
        "TripShareService.swift|金沢・福井の旅",
    ]

    private var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    func testNoMiddleDotSeparatorsInScreenText() throws {
        var found: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100)
        for file in files {
            // 写真の内側の開発用の一覧（Mac の画面写真で家具を並べて見るだけ・利用者には出ない）
            if file.lastPathComponent == "CamperRoomContactSheet.swift" { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.literals(text) where literal.contains("・") || literal.contains("·") {
                let key = "\(file.lastPathComponent)|\(literal)"
                if !Self.allowed.contains(key) { found.append(key) }
            }
        }
        XCTAssertEqual(found, [], "画面の文に中黒の区切りがある（「、」か余白か「と」で分ける）")
    }

    /// 見張りそのもの: 注記は読まず、文字列だけを拾う
    func testLiteralReaderSkipsComments() {
        let q = Self.quote
        let code = "// 区切り · 注記\n"
            + "let a = L(" + q + "名前 · 時刻" + q + ", " + q + "x" + q + ") " + "/" + "* 中黒・注記 *" + "/" + "\n"
        let bs = String(Unicode.Scalar(0x5C))
        let inner = bs + "(f(" + q + "・" + q + ")) と"
        let code2 = code + "let b = " + q + inner + q + "\n"
        XCTAssertEqual(Self.literals(code2), ["名前 · 時刻", "x", inner])
    }

    /// Swift の文字列リテラルの中身（注記を飛ばす・補間の中の文字列は外側の中身に含める）
    /// 引用符（構文の検査 `check-swift-syntax.js` が引用符の字の書き方で迷うので、字の番号で持つ）
    static let quote = String(Unicode.Scalar(0x22))
    private static let quoteScalar = Unicode.Scalar(0x22)
    private static let backslash = Unicode.Scalar(0x5C)
    private static let open = Unicode.Scalar(0x28)
    private static let close = Unicode.Scalar(0x29)
    private static let newline = Unicode.Scalar(0x0A)

    static func literals(_ text: String) -> [String] {
        let s = Array(text.unicodeScalars)
        let q = quote
        let triple = q + q + q
        var out: [String] = []
        var i = 0
        func starts(_ p: String, _ at: Int) -> Bool {
            let ps = Array(p.unicodeScalars)
            guard at + ps.count <= s.count else { return false }
            return Array(s[at..<at + ps.count]) == ps
        }
        func str(_ a: Int, _ b: Int) -> String {
            var v = String.UnicodeScalarView()
            v.append(contentsOf: s[a..<max(a, b)])
            return String(v)
        }
        while i < s.count {
            if starts("//", i) {
                while i < s.count, s[i] != newline { i += 1 }
                continue
            }
            if starts("/" + "*", i) {
                i += 2
                while i < s.count, !starts("*" + "/", i) { i += 1 }
                i += 2
                continue
            }
            if starts(triple, i) {
                var j = i + 3
                while j < s.count, !starts(triple, j) { j += 1 }
                out.append(str(i + 3, j))
                i = j + 3
                continue
            }
            if starts("#" + q, i) {
                var j = i + 2
                while j < s.count, !starts(q + "#", j) { j += 1 }
                out.append(str(i + 2, j))
                i = j + 2
                continue
            }
            if s[i] == quoteScalar {
                var j = i + 1
                while j < s.count, s[j] != quoteScalar, s[j] != newline {
                    if s[j] == backslash {
                        if j + 1 < s.count, s[j + 1] == open {
                            var k = j + 2
                            var depth = 1
                            while k < s.count, depth > 0 {
                                if s[k] == open { depth += 1 } else if s[k] == close { depth -= 1 } else if s[k] == quoteScalar {
                                    k += 1
                                    while k < s.count, s[k] != quoteScalar {
                                        if s[k] == backslash { k += 1 }
                                        k += 1
                                    }
                                }
                                k += 1
                            }
                            j = k
                            continue
                        }
                        j += 2
                        continue
                    }
                    j += 1
                }
                out.append(str(i + 1, j))
                i = j + 1
                continue
            }
            i += 1
        }
        return out
    }
}
