import XCTest
@testable import JourneyPhoto

/// 「自然な文で探す」（札 #623）を作り込む前の数え（2026-11-15）。**端末の AI で文の例 20件を読み、合った数を書く。**
///
/// 書き出す行（Mac の `xcodebuild-full.log`）:
/// - `measured [search-sentence] engine=ai status=…` 端末の AI が使えるか（使えない理由・`OnDeviceAI.systemStatus`）
/// - `measured [search-sentence] engine=ai case=… raw=… ai=… merged=… ms=…` 1件ずつ（AI だけ・表と合わせた形）
/// - `measured [search-sentence] summary engine=ai aiOnly=…/20 merged=…/20 failures=… medianMs=…`
///
/// **端末の AI が使えない環境（Apple Intelligence の無い Mac のシミュレーター）では、理由を書いて抜ける。**
/// 失敗にはしない——使えないことが答え（「確かめられない」と報告する）。表の側は `SearchSentenceTests` が毎回数える
final class SearchSentenceDeviceEvalTests: XCTestCase {

    func testOnDeviceAIReadsTheTwentyExamples() async {
        let status = OnDeviceAI.systemStatus
        print("measured [search-sentence] engine=ai status=\(status)")
        guard status.isAvailable else { return }

        var aiOnly = 0, merged = 0, failures = 0
        var times: [Int] = []
        for (index, c) in SearchSentenceFixture.cases.enumerated() {
            let started = Date()
            let answer = await SearchSentenceReader.ask(c.sentence)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            times.append(ms)
            guard let draft = answer.draft else {
                failures += 1
                print("measured [search-sentence] engine=ai case=\(index + 1) sentence=\(c.sentence) error=\(answer.error ?? "-") ms=\(ms)")
                continue
            }
            // AI だけ（表を混ぜない）: 選択肢の値と、文の中の字だけを使う
            let alone = Self.aiAlone(draft, sentence: c.sentence)
            let both = SearchSentence.normalized(draft, sentence: c.sentence)
            if c.matches(alone) { aiOnly += 1 }
            if c.matches(both) { merged += 1 }
            print("measured [search-sentence] engine=ai case=\(index + 1) sentence=\(c.sentence) ms=\(ms)"
                  + " raw=season:\(draft.season),dayPart:\(draft.dayPart),place:\(draft.place),keyword:\(draft.keyword),unsupported:\(draft.unsupported)"
                  + " aiOnly=\(c.matches(alone)) merged=\(c.matches(both))"
                  + " mergedText=\(both.text ?? "-") mergedSeason=\(both.season?.rawValue ?? "-") mergedDayPart=\(both.dayPart?.rawValue ?? "-")")
        }
        let sorted = times.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let n = SearchSentenceFixture.cases.count
        print("measured [search-sentence] summary engine=ai aiOnly=\(aiOnly)/\(n) merged=\(merged)/\(n)"
              + " failures=\(failures) medianMs=\(median) maxMs=\(sorted.last ?? 0)")
    }

    /// 表を混ぜずに、AI の答えだけを型に入れる（数えるためだけ。アプリは `normalized` で表と合わせる）
    static func aiAlone(_ draft: SearchSentence.Draft, sentence: String) -> SearchSentence.Reading {
        var r = SearchSentence.Reading(sentence: sentence)
        r.season = SearchSentence.season(choice: draft.season)
        r.dayPart = SearchSentence.dayPart(choice: draft.dayPart)
        r.unsupported = SearchSentence.unique(draft.unsupported.compactMap(SearchSentence.Unsupported.of(choice:)))
        let haystack = SearchSentence.fold(sentence)
        let words = [draft.place, draft.keyword]
            .map { SearchSentence.fold($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "なし" && haystack.contains($0) && SearchSentence.isKeyword($0) }
        let (text, unused) = SearchSentence.pickText(SearchSentence.unique(words))
        r.text = text
        r.unused = unused
        return r
    }
}
