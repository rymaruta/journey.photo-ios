import Foundation

/// 「他人の写真は、その人のもの」（CLAUDE.md・2026-11-12 owner・絶対）の見張りが使う、ソースの読み方。
///
/// 名前に頼らず「形」で探す: 画像を外へ出す API・画像を作る API・写真を指す欄を持つ保存／送信の型・
/// 画像の中身を通信で取る所。見つけた所は `OthersPhotoExportGuardTests` の一覧（理由つき）と突き合わせる。
/// 試験の中で、わざと破った見本（`OthersPhotoExportGuardTests.testScannerCatchesPlantedViolations`）にも当てて、
/// 見張りそのものが効いていることを毎回確かめる（2026-11-23 owner「守れていた、ではなく守れるように」）
enum OthersPhotoGuardScan {

    struct Source {
        let path: String
        /// 注釈（`//` から行末）を落とした本文。注釈に API の名前を書いても引っかからない
        let code: String
        let lines: [String]

        init(path: String, code: String) {
            self.path = path
            self.code = code
            self.lines = code.components(separatedBy: "\n")
        }
    }

    static func load(root: URL) throws -> [Source] {
        var out: [Source] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            out.append(Source(path: String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)),
                              code: stripComments(text)))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// 行の注釈を落とす。`"https://…"` の `://` は注釈ではないので、`//` の前が `:` のときは残す
    static func stripComments(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            var previous: Character = " "
            var index = line.startIndex
            var inString = false
            while index < line.endIndex {
                let c = line[index]
                if c == "\"" && previous != "\\" { inString.toggle() }
                if !inString, c == "/", previous == "/" {
                    let start = line.index(before: index)
                    let before = start > line.startIndex ? line[line.index(before: start)] : " "
                    if before != ":" { return String(line[..<start]) }
                }
                previous = c
                index = line.index(after: index)
            }
            return line
        }.joined(separator: "\n")
    }

    /// 作った正規表現を使い回す（ファイル×行×決まりの数だけ作り直すと遅い）
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]
    private static let compiledLock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression? {
        compiledLock.lock()
        defer { compiledLock.unlock() }
        if let re = compiled[pattern] { return re }
        let re = try? NSRegularExpression(pattern: pattern)
        compiled[pattern] = re
        return re
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let re = regex(pattern) else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    // MARK: - ① 画像を外へ出す道（保存・画像の共有・ドラッグ・画像のコピー・ファイルの書き出し）

    /// 名前 → 1行に当てる正規表現。**画像そのものを手にできる道**だけ。リンクや文の共有（`.string =`）は入れない
    static let exitRules: [(name: String, pattern: String)] = [
        ("photoLibrary", #"UIImageWriteToSavedPhotosAlbum|UISaveVideoAtPathToSavedPhotosAlbum|PHAssetCreationRequest|PHAssetChangeRequest|creationRequestForAsset|performChanges\s*[({]"#),
        ("shareSheet", #"UIActivityViewController\s*\(|\bShareSheet\s*\("#),
        ("shareLink", #"\bShareLink\s*\("#),
        ("pasteboardImage", #"UIPasteboard\b[^\n]*\.(image|images|setData|setItems|addItems|itemProviders|setItemProviders|items|setImage|setValue)\b"#),
        ("drag", #"\.draggable\s*\(|\.onDrag\b|UIDragInteraction|NSItemProvider|\.itemProvider\b|UIDragItem"#),
        ("transferableExport", #":\s*[\w\s,&]*\bTransferable\b|\bDataRepresentation\s*\(|\bFileRepresentation\s*\(|\bProxyRepresentation\s*\(|exportedContentType"#),
        ("fileExport", #"\.fileExporter\s*\(|UIDocumentInteractionController|forExporting|QLPreviewController|\.fileMover\s*\(|FileDocument\b"#),
    ]

    /// 写真の画像の URL をそのまま外（共有・コピー・ブラウザ）へ渡す行。**どこにも許さない**（元画像への直リンク）
    static let rawImageURLOut =
        #"(ShareLink|UIPasteboard|openURL|\.open\s*\(|\bLink\s*\(|SFSafariViewController|SafariView)[^\n]*(\.(src|thumbSrc|srcAvif|src256|thumbAvif|thumbSm|thumbSmAvif|srcOriginal|detailImageURL|gridImageURL|pinImageURL)\b)"#

    /// 長押しのメニュー（`.contextMenu`）の中の「保存」「ダウンロード」「画像のコピー」
    static let contextMenuSaveWords = #"保存|ダウンロード|画像をコピー|写真をコピー|\"Save|\"Download|Copy (image|photo)|square\.and\.arrow\.down"#

    /// ファイル → 見つかった道の名前
    static func exits(in sources: [Source]) -> [String: Set<String>] {
        var found: [String: Set<String>] = [:]
        for source in sources {
            for rule in exitRules where matches(rule.pattern, source.code) {
                // ファイル全体で当たった決まりだけ、行ごとに確かめる（行をまたぐ当たりを数えない）
                if source.lines.contains(where: { matches(rule.pattern, $0) }) {
                    found[source.path, default: []].insert(rule.name)
                }
            }
            for block in contextMenuBlocks(source.code) where matches(contextMenuSaveWords, block) {
                found[source.path, default: []].insert("contextMenuSave")
            }
        }
        return found
    }

    /// 元画像への直リンクを外へ出す行（ファイル:行）
    static func rawImageURLExits(in sources: [Source]) -> [String] {
        sources.flatMap { source in
            guard matches(rawImageURLOut, source.code) else { return [String]() }
            return source.lines.enumerated().compactMap { index, line in
                matches(rawImageURLOut, line) ? "\(source.path):\(index + 1)" : nil
            }
        }
    }

    /// `.contextMenu { … }` の中身（波かっこの対応で切り出す）
    static func contextMenuBlocks(_ code: String) -> [String] {
        var blocks: [String] = []
        var search = code.startIndex
        while let hit = code.range(of: ".contextMenu", range: search..<code.endIndex) {
            search = hit.upperBound
            guard let open = code[hit.upperBound...].firstIndex(where: { $0 == "{" || $0 == "(" }) else { break }
            if let body = balanced(code, from: open) { blocks.append(body) }
        }
        return blocks
    }

    /// `from` の開きかっこから、対応する閉じかっこまで（開きと閉じを含む）
    static func balanced(_ code: String, from open: String.Index) -> String? {
        let opener = code[open]
        let closer: Character = opener == "{" ? "}" : ")"
        var depth = 0
        var index = open
        while index < code.endIndex {
            let c = code[index]
            if c == opener { depth += 1 }
            if c == closer {
                depth -= 1
                if depth == 0 { return String(code[open...index]) }
            }
            index = code.index(after: index)
        }
        return nil
    }

    // MARK: - ② 画像を作る所（書き出し・描き直し）。カードや絵を作る新しい道は、ここに必ず引っかかる

    static let imageMaking =
        #"jpegData\s*\(|pngData\s*\(|heicData|CGImageDestination|\bImageRenderer\b|UIGraphicsImageRenderer|fileDataRepresentation|CIContext\b[^\n]*(jpegRepresentation|pngRepresentation|heifRepresentation|writeJPEG|writePNG|writeHEIF)"#

    static func imageMakers(in sources: [Source]) -> Set<String> {
        Set(sources.filter { matches(imageMaking, $0.code) }.map(\.path))
    }

    // MARK: - ③ 写真を指す欄を持つ「保存・送信する型」（自分の物に写真を入れる型）

    /// 欄の名前（写真・画像・表紙・縮小・src・絵）
    static let photoFieldName = #"(?i)(photo|image|cover|thumb|src|picture|artwork)"#
    /// 欄の型（文字列・URL・写真・画像のデータ）
    static let photoFieldType = #"^\[?\s*(String|URL|Photo|Data|UIImage|CGImage)\s*\]?\??$"#

    /// `ファイル#型` → 写真を指す欄。`Codable` / `Encodable` の struct・class だけ（サーバーから読むだけの型は見ない）
    static func photoHoldingTypes(in sources: [Source]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        let decl = #"\b(?:struct|class|actor)\s+(\w+)(?:<[^>{]*>)?\s*:([^{]*)\{"#
        for source in sources {
            let code = source.code
            guard let re = regex(decl) else { continue }
            for m in re.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let nameRange = Range(m.range(at: 1), in: code),
                      let inheritRange = Range(m.range(at: 2), in: code),
                      let whole = Range(m.range, in: code) else { continue }
                let inherits = String(code[inheritRange])
                guard matches(#"\b(Codable|Encodable)\b"#, inherits) else { continue }
                let open = code.index(before: whole.upperBound)
                guard let body = balanced(code, from: open) else { continue }
                let fields = storedFields(topLevelOf: body).filter { name, type in
                    let t = type.trimmingCharacters(in: .whitespaces)
                    if matches(#"^\[?\s*Photo\s*\]?\??$"#, t) { return true }
                    return matches(photoFieldName, name) && matches(photoFieldType, t)
                }.map { "\($0.0): \($0.1)" }
                if !fields.isEmpty { out["\(source.path)#\(code[nameRange])"] = fields }
            }
        }
        return out
    }

    /// 型の本体の一番外の段にある、値を持つ欄（名前・型）。計算するだけの欄（`{ … }` が続く）は数えない
    static func storedFields(topLevelOf body: String) -> [(String, String)] {
        // 一番外の段だけを残す（入れ子の型・関数の中身は「{」1字に縮める。計算するだけの欄は「{」で終わる）
        var flat = ""
        var depth = 0
        for c in body {
            if c == "{" { depth += 1; if depth == 2 { flat.append("{") }; continue }
            if c == "}" { depth -= 1; continue }
            if depth == 1 { flat.append(c) }
        }
        let segments = flat.components(separatedBy: CharacterSet(charactersIn: "\n;"))
        let field = #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|nonisolated|static|lazy|weak|private\(set\)|fileprivate\(set\))\s+)*(let|var)\s+(\w+)\s*:\s*([^={]+?)\s*(=[^{]*)?(\{)?\s*$"#
        return segments.compactMap { segment in
            guard let c = captures(field, segment).first, c.count >= 6 else { return nil }
            if segment.contains("static ") { return nil }
            if !c[5].isEmpty, c[1] == "var" { return nil }  // 計算するだけの欄
            return (c[2], c[3])
        }
    }

    /// 送る本文の辞書に、写真を指す鍵（`"photoId":` `"cover":` など）を書いている所（ファイル）
    static func photoKeysInBodies(in sources: [Source]) -> Set<String> {
        let key = #""\w*([Pp]hoto|[Ii]mage|[Cc]over|[Tt]humb|[Ss]rc)\w*"\s*:"#
        return Set(sources.filter { source in
            matches(key, source.code)
        }.map(\.path))
    }

    // MARK: - ④ 画像の中身（バイト）を通信で取る所

    /// 通信の口（`URLSession` の data / download / bytes・dataTask）
    static let rawFetch = #"\.(data|download|bytes)\s*\(\s*(from|for)\s*:|\.dataTask\s*\(\s*with\s*:|\.downloadTask\s*\(\s*with\s*:"#

    /// URL を受けて Data / UIImage を返し、**中で通信する**、外から呼べる関数（取り手）。名前に頼らず形で探す。
    /// 取り手を呼ぶだけの包みも取り手として数える（増えなくなるまで回す）
    static func fetchers(in sources: [Source]) -> Set<String> {
        let pattern = #"(?m)^[^\n]*\bfunc\s+(\w+)\s*\(([^)]*)\)[^{\n]*->\s*(Data|UIImage)\??\s*\{"#
        var candidates: [(name: String, body: String)] = []
        for source in sources {
            let code = source.code
            guard let re = regex(pattern) else { continue }
            for m in re.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let whole = Range(m.range, in: code), let name = Range(m.range(at: 1), in: code),
                      let params = Range(m.range(at: 2), in: code) else { continue }
                if matches(#"\b(private|fileprivate)\b"#, String(code[whole])) { continue }
                guard matches(#":\s*URL\??\s*(,|=|$)"#, String(code[params])),
                      let body = balanced(code, from: code.index(before: whole.upperBound)) else { continue }
                candidates.append((String(code[name]), body))
            }
        }
        var names: Set<String> = []
        while true {
            let next = Set(candidates.filter { candidate in
                matches(rawFetch, candidate.body) || names.contains { calls($0, in: candidate.body) }
            }.map(\.name))
            if next == names { return names }
            names = next
        }
    }

    /// `name` の取り手を呼んでいるか
    static func calls(_ name: String, in code: String) -> Bool {
        commonNames.contains(name)
            ? matches(#"\b(?!JSONSerialization\b|PropertyListSerialization\b)[A-Z]\w*\.\#(name)\s*\("#, code)
            : matches(#"\.\#(name)\s*\("#, code)
    }

    /// ありふれた名前（`data` `download` など）は、型の名前から呼ぶ形（`ProfileImageFromPhoto.download(`）だけを数える
    /// ——`URLSession.shared.download(` は通信の口として別に数える
    static let commonNames: Set<String> = ["data", "download", "image", "load", "fetch", "get"]

    static func imageFetchers(in sources: [Source]) -> Set<String> {
        let names = fetchers(in: sources)
        return Set(sources.filter { source in
            matches(rawFetch, source.code) || names.contains { calls($0, in: source.code) }
        }.map(\.path))
    }

    // MARK: - ⑤ 自分の物へ入れる入口（closed set）

    /// その入口を使っているファイル
    static func users(of sink: String, in sources: [Source]) -> Set<String> {
        let escaped = NSRegularExpression.escapedPattern(for: sink)
        return Set(sources.filter { source in
            // 型の宣言そのもの（`struct X` `enum X`）と、名前の一部が同じ別の型（`DeviceTripBookView(`）は数えない
            matches("(?<![\\w.])(?<!struct |enum |class |func )\(escaped)", source.code)
        }.map(\.path))
    }

    /// `static func name(` から始まる関数の本体
    static func functionBody(_ code: String, signature: String) -> String? {
        guard let start = code.range(of: signature),
              let open = code[start.upperBound...].firstIndex(of: "{") else { return nil }
        return balanced(code, from: open)
    }
}
