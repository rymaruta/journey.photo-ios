import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 探すの文を、**端末の中だけで**今の絞り込みに読み替える（札 #623 の案2・2026-11-15 判断。決まりは `SearchSentence`）。
///
/// 1. 端末の AI（`OnDeviceAI` が使えるとき）: 答えの形は `SearchSentenceDraft`。季節・時間帯・欄の無い条件は
///    `@Guide(.anyOf)` で決まった選択肢しか作れない。地名と探したいものは、文に書かれた字だけを使う（`SearchSentence.normalized`）
/// 2. 使えない機種・AI が失敗した・時間切れ: 言葉の表（`SearchSentence.readByTable`）
///
/// **どちらも外へは何も送らない**（Bedrock は使わない。回数も数えない）
enum SearchSentenceReader {

    /// 読む口（試験は差し替える）
    typealias Run = @Sendable (String) async -> SearchSentence.Reading

    /// AI を待つ上限。過ぎたら表で読む（打ってから絞り込みが出るまで待たせすぎない）
    static let timeout: Duration = .seconds(4)

    /// 本物
    static let live: Run = { sentence in
        // 試験の切り替え（`-JPOnDeviceAI sample` は投稿の候補の見本のためのもの）。探すは見本を持たず、表で読む
        guard OnDeviceAI.mode == nil, OnDeviceAI.isAvailable else { return SearchSentence.readByTable(sentence) }
        if let draft = await askWithTimeout(sentence) {
            return SearchSentence.normalized(draft, sentence: sentence)
        }
        return SearchSentence.readByTable(sentence)
    }

    static func askWithTimeout(_ sentence: String) async -> SearchSentence.Draft? {
        await withTaskGroup(of: SearchSentence.Draft?.self) { group in
            group.addTask { await ask(sentence).draft }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// 端末の AI に問う。失敗（安全の決まりで止まった・使えない OS など）は `error` に理由（試験が書き出す）
    static func ask(_ sentence: String) async -> (draft: SearchSentence.Draft?, error: String?) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession(model: SystemLanguageModel.default, tools: [],
                                                   instructions: SearchSentence.instructions)
                // 読み取りは毎回同じ答えがよい（温度 0）
                let response = try await session.respond(to: SearchSentence.prompt(sentence),
                                                         generating: SearchSentenceDraft.self,
                                                         options: GenerationOptions(temperature: 0))
                let d = response.content
                return (SearchSentence.Draft(season: d.season, dayPart: d.dayPart, place: d.place,
                                             keyword: d.keyword, unsupported: d.unsupported.map(\.name)), nil)
            } catch {
                print("[searchSentence] failed \(error)")
                return (nil, String(describing: error))
            }
        }
        return (nil, "osTooOld")
        #else
        return (nil, "noFramework")
        #endif
    }
}

#if canImport(FoundationModels)
/// 端末の AI の答えの形（2026-11-15 判断・札 #623）。**季節・時間帯・欄の無い条件は選択肢の字だけ**。
/// 地名と探したいものは字のまま受け、文に無い字はアプリが落とす（`SearchSentence.normalized`）
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SearchSentenceDraft {
    @Guide(description: "文に書かれた季節、または季節の分かる言葉（紅葉なら秋）。書かれていなければ「なし」",
           .anyOf(SearchSentence.seasonChoices))
    var season: String

    @Guide(description: "文に書かれた時間帯（朝 5〜9時、日中 10〜15時、夕方 16〜18時、夜 19〜4時）。書かれていなければ「なし」",
           .anyOf(SearchSentence.dayPartChoices))
    var dayPart: String

    @Guide(description: "文の中の地名（都道府県、市町村、名所の名前）を文の字のまま1つ。無ければ「なし」")
    var place: String

    @Guide(description: "地名、季節、時間帯のほかに探したいもの（海、滝、城など）を文の字のまま1語。無ければ「なし」")
    var keyword: String

    @Guide(description: "文に書かれた、ほかの条件。選択肢の中から0〜3個", .maximumCount(3))
    var unsupported: [SearchSentenceCondition]
}

/// 欄の無い条件1つ（`SearchSentence.Unsupported` の選択肢）
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SearchSentenceCondition {
    @Guide(description: "条件の選択肢のどれか", .anyOf(SearchSentence.unsupportedChoices))
    var name: String
}
#endif
