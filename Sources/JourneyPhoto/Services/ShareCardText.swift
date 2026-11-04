import Foundation

/// SNS 共有カードの字の折り返し。語の途中では折らない。
///
/// 2026-11-04 owner「文章の変な改行はいやです」: 撮影地の字を 140 幅に詰めると、
/// UIKit の文字単位の折り返し（`.byCharWrapping`）では「（山中湖\n村）」のように語の途中で折れた。
/// UIKit の語の折り返しも和文では字の間で折るので使わず、折る所をここで決める:
/// - 折ってよいのは区切りの所だけ: 括弧の前（「山梨県」と「（山中湖村）」の間）、
///   読点・中黒・「,」・空白の後。括弧の中では折らない
/// - 区切りで折っても幅に収まらないときは、全体の字を 1 ずつ小さくする（撮影者名と同じ縮め方・同じ下限）
/// - 下限でも収まらなければ、収まらない行の末尾を「…」で切る（語の途中で次の行へ送らない）
/// 測る関数を外から渡すので、Linux でも折れる位置を数で試せる。
enum ShareCardText {
    struct Fitted: Equatable {
        let size: CGFloat
        let lines: [String]
        let truncated: Bool
    }

    private static let openers: Set<Character> = ["（", "(", "「", "［", "["]
    private static let closers: Set<Character> = ["）", ")", "」", "］", "]"]
    private static let breakAfter: Set<Character> = ["、", "・", "，", "/", "／"]

    /// 折ってよい所で区切った塊。塊をつなげると元の文になる
    static func segments(_ text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var current = ""
        var depth = 0
        for (index, character) in characters.enumerated() {
            if openers.contains(character) {
                if depth == 0, !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(current)
                    current = ""
                }
                depth += 1
            }
            current.append(character)
            if closers.contains(character) { depth = max(0, depth - 1) }
            guard depth == 0 else { continue }
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let isSpace = character == " " || character == "　"
            let breaks = breakAfter.contains(character)
                || (character == "," && next != " ")
                || (isSpace && next != " " && next != "　")
            if breaks, next != nil {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 塊を前から詰めて行にする（行の頭と末尾の空白は落とす）
    static func pack(_ segments: [String], maxWidth: CGFloat, size: CGFloat,
                     measure: (String, CGFloat) -> CGFloat) -> [String] {
        packGroups(segments, maxWidth: maxWidth, size: size, measure: measure)
            .map { trimmed($0.joined()) }
    }

    /// 行ごとの塊の組
    private static func packGroups(_ segments: [String], maxWidth: CGFloat, size: CGFloat,
                                   measure: (String, CGFloat) -> CGFloat) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        for segment in segments {
            let candidate = (current + [segment]).joined()
            if current.isEmpty || measure(trimmed(candidate), size) <= maxWidth {
                current.append(segment)
            } else {
                groups.append(current)
                current = [segment]
            }
        }
        if !trimmed(current.joined()).isEmpty { groups.append(current) }
        return groups
    }

    /// 幅と行数に収まる最大の大きさと、折った行。
    /// - Parameters:
    ///   - step: 縮める刻み（撮影者名・撮影地は 1）
    ///   - maxLines: その大きさで置ける行数
    static func fit(_ text: String, maxWidth: CGFloat, preferredSize: CGFloat,
                    minimumSize: CGFloat, step: CGFloat = 1,
                    maxLines: (CGFloat) -> Int,
                    measure: (String, CGFloat) -> CGFloat) -> Fitted {
        let parts = segments(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !parts.isEmpty else { return Fitted(size: preferredSize, lines: [], truncated: false) }
        var size = preferredSize
        while true {
            let lines = pack(parts, maxWidth: maxWidth, size: size, measure: measure)
            if lines.count <= max(1, maxLines(size)),
               lines.allSatisfy({ measure($0, size) <= maxWidth }) {
                return Fitted(size: size, lines: lines, truncated: false)
            }
            if size <= minimumSize { break }
            size = max(minimumSize, size - step)
        }
        // 下限でも収まらない: 置ける行数を超えた分は最後の行へ寄せ、はみ出す行は末尾を「…」で切る
        let limit = max(1, maxLines(size))
        var groups = packGroups(parts, maxWidth: maxWidth, size: size, measure: measure)
        if groups.count > limit {
            let rest = groups[(limit - 1)...].flatMap { $0 }
            groups = Array(groups[..<(limit - 1)]) + [rest]
        }
        let lines = groups.map {
            truncate(trimmed($0.joined()), maxWidth: maxWidth, size: size, measure: measure)
        }
        return Fitted(size: size, lines: lines, truncated: true)
    }

    static func truncate(_ line: String, maxWidth: CGFloat, size: CGFloat,
                         measure: (String, CGFloat) -> CGFloat) -> String {
        guard measure(line, size) > maxWidth else { return line }
        var characters = Array(line)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = trimmed(String(characters)) + "…"
            if measure(candidate, size) <= maxWidth { return candidate }
        }
        return "…"
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
