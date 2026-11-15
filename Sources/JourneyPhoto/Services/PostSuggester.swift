import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Vision)
import Vision
#endif

/// 投稿の候補を**端末の中だけで**作る（札 #622・2026-11-15 判断。決まりは `PostSuggest` の注記）。
///
/// 1. 写真の中身: Vision の画像の分類（`VNClassifyImageRequest`・iOS 13 から。Vision の事前学習済みのモデルで、
///    端末の中で動く）。確かさ `PostSuggest.labelConfidence` 以上を `labelCount` 個まで
/// 2. 題・説明・タグ: 端末の AI（`SystemLanguageModel.default`・iOS 26 から）。答えの形は `PostSuggestDraft` で縛る。
///    タグは `@Guide(.anyOf(TagChoices.all))` で決まった選択肢の語しか作れない
///
/// どちらも失敗したら黙って nil（候補を出さないだけ。投稿は止めない）
enum PostSuggester {

    /// 候補を作る口（試験は差し替える）。nil なら出さない
    typealias Run = @Sendable (PostSuggest.Input, Data?) async -> PostSuggest.Result?

    /// 本物（`OnDeviceAI` が使えないときは何もしない）
    static let live: Run = { input, image in
        switch OnDeviceAI.mode {
        case .sample?: return PostSuggest.sample
        case .off?: return nil
        case nil: break
        }
        guard OnDeviceAI.isAvailable else { return nil }
        var filled = input
        if filled.labels.isEmpty, let image { filled.labels = await labels(for: image) }
        guard !filled.isEmpty else { return nil }
        return await generate(filled)
    }

    /// 写真に写っているもの（Vision の分類の識別子）。読めなければ空
    static func labels(for image: Data) async -> [String] {
        #if canImport(Vision) && os(iOS)
        return await Task.detached(priority: .utility) { () -> [String] in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: image, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            let observations = request.results ?? []
            return observations
                .filter { $0.confidence >= PostSuggest.labelConfidence }
                .sorted { $0.confidence > $1.confidence }
                .prefix(PostSuggest.labelCount)
                .map(\.identifier)
        }.value
        #else
        return []
        #endif
    }

    /// 端末の AI に問う。使えない OS・失敗（安全の決まりで止まった・時間切れなど）は nil
    static func generate(_ input: PostSuggest.Input) async -> PostSuggest.Result? {
        let answer = await ask(input)
        guard answer.error == nil else { return nil }
        let result = PostSuggest.result(titles: answer.titles, caption: answer.caption, tags: answer.tags)
        return result.isEmpty ? nil : result
    }

    /// AI の生の答え（整える前）。`OnDeviceAIProbeTests` が数を取るのにも使う
    struct Answer {
        var titles: [String] = []
        var caption: String?
        var tags: [String] = []
        /// 失敗の中身（画面には出さない）
        var error: String?
    }

    static func ask(_ input: PostSuggest.Input) async -> Answer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession(model: SystemLanguageModel.default, tools: [],
                                                   instructions: PostSuggest.instructions)
                let response = try await session.respond(to: PostSuggest.prompt(input),
                                                         generating: PostSuggestDraft.self,
                                                         options: GenerationOptions(temperature: 0.7))
                let draft = response.content
                return Answer(titles: draft.titles, caption: draft.caption, tags: draft.tags.map(\.name))
            } catch {
                print("[postSuggest] failed \(error)")
                return Answer(error: String(describing: error))
            }
        }
        return Answer(error: "osTooOld")
        #else
        return Answer(error: "noFramework")
        #endif
    }
}

#if canImport(FoundationModels)
/// 端末の AI の答えの形（2026-11-15 判断・札 #622）。**タグは選択肢の語だけ**（`PostSuggestTag`）
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct PostSuggestDraft {
    @Guide(description: "写真の題の候補。日本語の短い名詞句（4〜16文字）を3つ。どれも違う言い方にする", .maximumCount(3))
    var titles: [String]

    @Guide(description: "写真の説明の候補。日本語で1〜2文、60文字まで")
    var caption: String

    @Guide(description: "写真に合うタグ。選択肢の中から0〜3個", .maximumCount(3))
    var tags: [PostSuggestTag]
}

/// タグ1つ。**新しいタグを作らせない**（`TagChoices.all` のどれか）
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct PostSuggestTag {
    @Guide(description: "タグの選択肢のどれか", .anyOf(TagChoices.all))
    var name: String
}
#endif
