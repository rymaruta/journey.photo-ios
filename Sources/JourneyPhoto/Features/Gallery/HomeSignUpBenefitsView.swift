import SwiftUI

/// ホームの「登録するとできること」の段（札 #618 の案1・2026-11-15 判断で案C・`SignUpBenefit`）。
///
/// ログインしていない人にだけ、並びのひと回り（と季節の段）の後ろに1回だけ出す。形は案の模型の札（`.can` の2列、
/// `.cc` の札: 地 surface-1、縁 白 8%、角 14、内側 8 / `.cp` の絵: 背 58、角 9 → 10、写真の地に白い印 26）。
/// 札を押すと今のログイン画面（`SignInSheet`）が開く。ログイン画面は変えない（owner「アカウント登録画面は何も変えたくない」）。
///
/// 色: 黒地の上なので眉ラベルは真鍮。絵は写真の地なので印は白だけ。下のボタンは線のボタン（写真の並びの中で
/// 控えめに。主ボタンにしない）。中黒で区切らない。押せるものは 44pt 以上。
///
/// 2026-11-15（札 #630）: 札と下の「新規登録」は**登録の側**で開く（「登録するとできること」なので）。下の1つだった
/// 「ログイン、新規登録」（ログインの側で開き、登録はもう1回押す）を、Web の段（`SignUpBenefits.tsx`）と同じ
/// 「新規登録」（線のボタン）と「ログイン」（文字のボタン）の2つに分けた。どちらも押す回数 1回
struct HomeSignUpBenefitsView: View {

    /// 札の絵の地に敷く写真（並びの写真。読めなければ地の色のまま）
    var photos: [Photo] = []

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var signInOpen: SignInRequest?
    @State private var signInAsk: SignInRequest?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: HomeSignUpBenefitsLayout.gap, alignment: .top),
              count: typeSize.isAccessibilitySize ? 1 : HomeSignUpBenefitsLayout.columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeSignUpBenefitsLayout.headingGap) {
            Text(SignUpBenefit.heading)
                .jpEyebrow()
                // 黒地の上なので真鍮
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: HomeSignUpBenefitsLayout.gap) {
                ForEach(Array(SignUpBenefit.allCases.enumerated()), id: \.element.id) { index, benefit in
                    Button {
                        signInOpen = SignInRequest(reason: benefit.signUpReason, entry: .signUp)
                    } label: {
                        card(benefit, photo: index < photos.count ? photos[index] : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(benefit.title)
                    .accessibilityHint(SignInPrompt.actionLabel)
                    .accessibilityIdentifier("home.signUpBenefit.\(benefit.rawValue)")
                }
            }
            HStack(spacing: JPSpace.m) {
                Button {
                    signInOpen = SignInRequest(reason: SignUpBenefit.signUpActionReason, entry: .signUp)
                } label: {
                    Text(SignInPrompt.signUpLabel).jpOutlineButton(.regular)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.signUpBenefits.action")
                Button {
                    signInOpen = SignInRequest(reason: SignUpBenefit.actionReason)
                } label: {
                    Text(SignInPrompt.loginLabel)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.signUpBenefits.signIn")
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 押した先は今のログイン画面のシート（`SignInPromptPresenter` の `open` の道。確かめは出さない）
        .signInPrompt(ask: $signInAsk, open: $signInOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.signUpBenefits")
    }

    private func card(_ benefit: SignUpBenefit, photo: Photo?) -> some View {
        VStack(alignment: .leading, spacing: HomeSignUpBenefitsLayout.innerGap) {
            picture(benefit, photo: photo)
            Text(benefit.title)
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HomeSignUpBenefitsLayout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay {
            RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
    }

    /// 札の絵: 写真の地（暗く沈めて）に白い印。写真の上なので印は白だけ
    private func picture(_ benefit: SignUpBenefit, photo: Photo?) -> some View {
        WebTheme.surface3
            .frame(maxWidth: .infinity)
            .frame(height: HomeSignUpBenefitsLayout.picture)
            .overlay {
                if let photo {
                    AsyncImage(url: photo.gridImageURL,
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: photo.gridAlignment)
                        }
                    }
                }
            }
            .overlay { Color.black.opacity(HomeSignUpBenefitsLayout.pictureScrim) }
            .overlay {
                Image(systemName: benefit.symbol)
                    .font(.system(size: HomeSignUpBenefitsLayout.symbolSize, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeSignUpBenefitsLayout.pictureRadius))
            .accessibilityHidden(true)
    }
}

/// 段の寸法（案の模型 `.can`、`.cc`、`.cp` の値。テストで見張る）
enum HomeSignUpBenefitsLayout {
    /// 列の数（模型 2。大きい文字の段では1列）
    static let columns = 2
    /// 札と札の間（模型 8）
    static let gap: CGFloat = 8
    /// 眉ラベル、札、ボタンの間（模型の `.body` の gap 12）
    static let headingGap: CGFloat = 12
    /// 札の内側（模型 8）
    static let padding: CGFloat = 8
    /// 絵と名前の間（模型 6 → 4 の倍数の 8）
    static let innerGap: CGFloat = 8
    /// 絵の背（模型 58）
    static let picture: CGFloat = 58
    /// 絵の角（模型 9 → 板の角 `JPRadius.s` の 10）
    static let pictureRadius: CGFloat = JPRadius.s
    /// 絵の印（模型の svg 26）
    static let symbolSize: CGFloat = 26
    /// 写真の地を沈める黒（白い印を読ませる）
    static let pictureScrim: Double = 0.35
    /// 札に敷く写真の数
    static var photoCount: Int { SignUpBenefit.allCases.count }
}
