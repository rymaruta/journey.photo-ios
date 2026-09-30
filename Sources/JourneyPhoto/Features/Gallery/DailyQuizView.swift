import SwiftUI

/// 今日の一問「この写真はどこ？」（Web の `/q` と同じ問題・`DailyQuiz`）。
///
/// 並び: 眉（今日の一問 · 日付）→ 写真 → 出典 → 問い → 4つの選択肢 → （答えたら）結果。
///
///  - **答える前から出典を出す**（CC の表示条件）。出典のファイル名に答えが出ることは
///    Web と同じく割り切った（`lib/utils/dailyQuiz.ts` の冒頭）
///  - **白地は「自分が選んだもの」**（板: 白＝位置と選択）。外したら自分の選択に赤の縁、
///    正解は真鍮の「✓ 正解」の字（真鍮＝合図）。真鍮の輪はフォーカスの印と紛れるので付けない
///  - 「行きたい」は結果に置かず、**ガイド（`OfficialSpotView`）で押す**——「行きたい」は
///    サーバーとの同期（未送信の控え・送信中）を持つ部品で、同じものを二度作らない
///  - 前面に戻ったときに日付が変わっていたら読み直す（夜に開いて朝に戻った）
struct DailyQuizView: View {

    /// ガイドの「この場所の写真」を引く公開写真（ホームから渡す）
    let photos: [Photo]

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    private enum Load: Equatable {
        case loading
        case none(date: String)
        case failed(date: String)
        case ready(DailyQuiz, chosen: String?)
    }

    @State private var load: Load = .loading
    /// 変わったら読み直す（再読み込み・日付が変わった）
    @State private var attempt = 0
    /// ガイドへ飛ぶための索引（答えのスポットを slug で引く）。取れなければ「ガイドを見る」を出さない
    @State private var spots: [OfficialSpot] = []

    private let answers = QuizAnswers()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityLabel(L("今日の一問", "Today's question"))
                content
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(WebTheme.background)
        .navigationTitle(L("今日の一問", "Today's question"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) { await fetch() }
        .task { await loadSpots() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if shownDate != nil, DailyQuiz.today() != shownDate { attempt &+= 1 }
        }
    }

    private var shownDate: String? {
        switch load {
        case .loading: return nil
        case .none(let date), .failed(let date): return date
        case .ready(let quiz, _): return quiz.date
        }
    }

    private var eyebrow: String {
        let head = L("今日の一問", "TODAY'S QUESTION")
        guard let date = shownDate else { return head }
        return "\(head) · \(DailyQuiz.dottedDate(date))"
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(WebTheme.surface)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                Text(L("今日の一問を読み込んでいます…", "Loading today's question…"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
        case .none:
            notice(L("今日の一問はまだありません。時間をおいて開き直してください。",
                     "There's no question for today yet. Please check back later."))
        case .failed:
            VStack(spacing: 12) {
                notice(L("今日の一問を読み込めませんでした。", "Couldn't load today's question."))
                Button {
                    load = .loading
                    attempt &+= 1
                } label: {
                    Text(L("もう一度読み込む", "Try again"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 20)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .background(WebTheme.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        case .ready(let quiz, let chosen):
            quizBody(quiz, chosen: chosen)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(WebTheme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 24)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func quizBody(_ quiz: DailyQuiz, chosen: String?) -> some View {
        let answered = chosen != nil
        let correct = chosen == quiz.answer
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: quiz.photo.url)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(L("今日の一問の写真", "Photo for today's question"))
            // 作者・ライセンス（文面へ）・出典のページ（CC BY / BY-SA の表示条件）
            SpotImageCredit(photo: quiz.photo)
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)

            Text(L("この写真はどこ？", "Where is this?"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 8) {
                ForEach(quiz.choices) { choice in
                    choiceButton(choice, quiz: quiz, chosen: chosen)
                }
            }
            .padding(.top, 12)

            if answered {
                result(quiz, correct: correct)
                    .padding(.top, 24)
            }
        }
    }

    private func choiceButton(_ choice: DailyQuiz.Choice, quiz: DailyQuiz, chosen: String?) -> some View {
        let answered = chosen != nil
        let isAnswer = choice.spotId == quiz.answer
        let isChosen = choice.spotId == chosen
        return Button {
            guard !answered else { return }
            answers.save(choice.spotId, date: quiz.date)
            load = .ready(quiz, chosen: choice.spotId)
        } label: {
            HStack(spacing: 12) {
                Text(choice.name)
                    .font(.body.weight(isChosen ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if answered && isAnswer {
                    // ✓ は飾り（読み上げは「正解」だけ）
                    Text("✓ " + L("正解", "ANSWER"))
                        .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                        .foregroundStyle(isChosen ? WebTheme.accentText : WebTheme.accent)
                        .accessibilityLabel(L("正解", "Answer"))
                }
            }
            .foregroundStyle(isChosen ? WebTheme.accentText
                             : (answered && !isAnswer ? WebTheme.faint : WebTheme.foreground))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(isChosen ? WebTheme.accentBackground : WebTheme.surface,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isChosen && !isAnswer {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.danger, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func result(_ quiz: DailyQuiz, correct: Bool) -> some View {
        let answer = quiz.answerChoice
        let guideSpot = spots.first { $0.slug == answer.slug && !$0.isDraft }
        return VStack(alignment: .leading, spacing: 4) {
            Text(correct ? L("正解", "CORRECT") : L("残念", "NOT QUITE"))
                .jpEyebrow()
                .foregroundStyle(correct ? WebTheme.accent : WebTheme.muted2)
            Text(answer.name)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.foreground)
            if let line = answer.regionLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
            HStack(spacing: 8) {
                if let guideSpot {
                    NavigationLink {
                        OfficialSpotView(spot: guideSpot, spots: spots, photos: photos)
                    } label: {
                        Text(L("ガイドを見る", "See the guide"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.accentText)
                            .padding(.horizontal, 20)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .background(WebTheme.accentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ShareLink(item: DailyQuiz.shareText(date: quiz.date, correct: correct, url: AppConfig.quizPageURL)) {
                    Text(L("結果を共有", "Share"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 20)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .overlay(Capsule().strokeBorder(WebTheme.outline, lineWidth: 1))
                }
            }
            .padding(.top, 12)
            Text(L("明日また新しい写真が出ます。", "A new photo tomorrow."))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    // MARK: - 読み込み

    private func fetch() async {
        let date = DailyQuiz.today()
        do {
            let result = try await environment.quiz.fetch(date: date)
            guard !Task.isCancelled else { return }
            switch result {
            case .none:
                load = .none(date: date)
            case .ready(let quiz):
                load = .ready(quiz, chosen: answers.chosen(for: quiz))
            }
        } catch {
            guard !Task.isCancelled else { return }
            load = .failed(date: date)
        }
    }

    private func loadSpots() async {
        guard spots.isEmpty else { return }
        let fetched = try? await environment.spots.fetchIndex()
        guard !Task.isCancelled, let fetched else { return }
        spots = fetched
    }
}
