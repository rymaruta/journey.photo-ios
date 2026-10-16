import SwiftUI

/// 名刺の一枚を選ぶ（板 PassCardPick）。すれちがった人の手元に、カードになって届く一枚。
///
/// - 選べるのは**全体に公開している自分の写真だけ**（公開範囲を絞った写真は相手の端末で引けない・
///   `PassExchange.isPublicCard`）。公開一覧（`photos.json`）に載っているものから選ぶ
/// - 上の見本は、相手に届くカードの表と同じ部品（`PassCardFront`）。**番号は出さない**
///   （番号は受け取った側の帳の順で決まり、自分の側では決まらない・2026-10-16 判断）
/// - 主ボタンは白（写真のある画面の主ボタン・CLAUDE.md の owner の好み。板は真鍮の塗りだが owner の決まりを取った）
struct PassCardPickView: View {

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var selected: String?
    @State private var note = ""
    /// 乗車券の区間（2026-10-16 判断・owner「発・着を自分で決めたい」）
    @State private var originChoice: PassSettings.Origin = .home
    @State private var originText = ""
    @State private var destinationCustom = false
    @State private var destinationText = ""
    @State private var profile: UserProfile?
    @State private var didLoad = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var selectedPhoto: Photo? { photos.first { $0.id == selected } }

    private var previewFace: PassTicketFace {
        PassTicketFace(photo: selectedPhoto, kind: .plain, number: nil,
                       origin: PassTicket.previewOrigin(originChoice, text: originText, homePrefecture: pass.homePrefecture),
                       destination: PassTicket.previewDestination(custom: destinationCustom, text: destinationText),
                       name: profile?.name ?? L("あなた", "You"), distance: nil, date: nil,
                       alighting: L("旅先のあたり 下車", "Got off around your trip"))
    }

    /// ひとことが長すぎる（字数か、電波に載る大きさ）
    private var noteTooLong: Bool {
        PassExchange.noteProblem(note) != nil
            || (originChoice == .custom && PassExchange.labelProblem(originText) != nil)
            || (destinationCustom && PassExchange.labelProblem(destinationText) != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                Text(L("すれちがった人の手元に、カードになって届く一枚です。いちばん好きな写真を選んでください。いつでも変えられます。",
                       "This photo reaches the people you pass as a card. Pick your favorite — you can change it any time."))
                    .font(.subheadline)
                    .lineSpacing(5)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                // 相手に届くきっぷの表（束の画面と同じ部品）。区間の右・日時・下車は会ってから決まるので、
                // 見本では「旅先」とする。番号は受け取った側の帳の順なので出さない
                // **縮めない**（縮めると字が 12pt を割る・2026-10-16 の読み直し）。束の画面と同じ 300 幅で出す
                PassCardFront(face: previewFace)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("相手に届くカードの表", "The front of the card others receive"))
                JPEyebrowLine(L("あなたの写真から選ぶ", "Choose from your photos"))
                grid
                noteField
                routeSection
                Button(action: save) {
                    Text(L("この一枚をカードにする", "Use this photo as my card")).jpPillButton(.main(onPhoto: true))
                }
                .buttonStyle(.plain)
                .disabled(selected == nil || noteTooLong)
                .opacity(selected == nil || noteTooLong ? 0.5 : 1)
                .padding(.top, JPSpace.xxs)
                .accessibilityIdentifier("pass.pick.save")
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.emptyTop)
        }
        .scrollDismissesKeyboard(.interactively)
        .webScreen()
        .navigationTitle(L("名刺の一枚", "Your card"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            selected = pass.settings.cardPhotoId
            note = pass.settings.note
            originChoice = pass.settings.origin
            originText = pass.settings.originLabel ?? ""
            destinationCustom = pass.settings.destinationLabel != nil
            destinationText = pass.settings.destinationLabel ?? ""
            await load()
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard let me = auth.userId else { return }
        let mine = try? await environment.profiles.myProfile()
        if let mine {
            profile = mine
            pass.noteHome(mine.homeLocation)
        }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        photos = all.filter { ($0.userId ?? $0.uploadedBy) == me && PassExchange.isPublicCard($0) }
        // 前に選んだ写真が公開一覧から消えていたら（非公開にした・消した）選び直してもらう
        if let selected, !photos.contains(where: { $0.id == selected }) { self.selected = nil }
        if selected == nil { selected = photos.first?.id }
    }

    @ViewBuilder
    private var grid: some View {
        if isLoading {
            JPLoadingState(kind: .grid)
        } else if photos.isEmpty {
            EmptyState(title: L("全体に公開している写真がありません", "No public photos yet"),
                       message: L("名刺にできるのは、全体に公開している写真だけです。投稿してからもう一度開いてください。",
                                  "Only photos shared with everyone can be your card. Post one, then come back."))
        } else {
            LazyVGrid(columns: Self.columns, spacing: 3) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    let on = photo.id == selected
                    Button { selected = photo.id } label: {
                        Color.clear
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)
                            .overlay { RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment) }
                            .clipped()
                            .overlay {
                                if on {
                                    // 写真の上の真鍮は読めないので、**内側に黒の縁**を足して写真から切り離す
                                    // （2026-10-16 の読み直し・件数バッジの黒い縁と同じ考え方）
                                    ZStack {
                                        Rectangle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis)
                                        Rectangle().strokeBorder(Color.black, lineWidth: JPStroke.hairline)
                                            .padding(JPStroke.emphasis)
                                    }
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    // 選んだ印（真鍮の丸に墨のチェック・黒 2 の縁）。写真の上だが黒い縁で地から切り離す
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(WebTheme.accentText)
                                        .frame(width: 22, height: 22)
                                        .background(WebTheme.accent, in: Circle())
                                        .overlay(Circle().strokeBorder(Color.black, lineWidth: JPStroke.emphasis))
                                        .padding(6)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("写真 \(index + 1) · \(photo.displayTitle)", "Photo \(index + 1) · \(photo.displayTitle)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
        JPField(L("裏に書くひとこと（\(PassExchange.noteLimit)字まで）", "A note on the back (up to \(PassExchange.noteLimit))")) {
            HStack {
                // 打っている途中では切らない（かな漢字の変換中に字数で切ると、変換が壊れる）。
                // 超えたら数を危険の色にして、主ボタンを押せなくする
                TextField(L("例：霧の朝が好きです", "e.g. I love misty mornings"), text: $note)
                Text("\(note.count)/\(PassExchange.noteLimit)")
                    .font(JPFont.meta)
                    .foregroundStyle(noteTooLong ? WebTheme.danger : WebTheme.text3)
                    .accessibilityHidden(true)
            }
        }
            // 押せない訳を言う（字数の内でも、絵文字が多いと電波に載る大きさを超える）
            if let problem = PassExchange.noteProblem(note) {
                Text(problem)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pass.pick.noteProblem")
            }
        }
    }

    /// 乗車券の区間（発・着）。**自分で書いた字は署名が無い**ので、受け取った側では「相手の端末から届いた文」の扱い
    /// （通報・伏せる）になる。下車の行は書いた字に関わらず、受け取った側の位置で自動
    private var routeSection: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            JPEyebrowLine(L("乗車券の区間", "Ticket route"))
            Text(L("発（どこから）", "From"))
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
                .accessibilityAddTraits(.isHeader)
            JPCard {
                JPRadioRow(title: homeTitle, selected: originChoice == .home) { originChoice = .home }
                    .accessibilityIdentifier("pass.pick.origin.home")
                JPCardDivider()
                JPRadioRow(title: L("自分で書く", "Write my own"), selected: originChoice == .custom) { originChoice = .custom }
                    .accessibilityIdentifier("pass.pick.origin.custom")
                JPCardDivider()
                JPRadioRow(title: L("出さない（どこかから）", "Don\u{2019}t show (somewhere)"), selected: originChoice == .hidden) {
                    originChoice = .hidden
                }
                .accessibilityIdentifier("pass.pick.origin.hidden")
            }
            if originChoice == .custom {
                labelField(L("発に書く字（\(PassExchange.labelLimit)字まで）", "From (up to \(PassExchange.labelLimit))"),
                           placeholder: L("例：雪国", "e.g. Snow country"), text: $originText, id: "pass.pick.origin.text")
            }
            Text(L("着（旅先）", "To"))
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
                .padding(.top, JPSpace.xxs)
                .accessibilityAddTraits(.isHeader)
            JPCard {
                JPRadioRow(title: L("すれちがった所（自動）", "Where we pass (automatic)"), selected: !destinationCustom) {
                    destinationCustom = false
                }
                .accessibilityIdentifier("pass.pick.destination.auto")
                JPCardDivider()
                JPRadioRow(title: L("自分で書く（旅先）", "Write my own (trip)"), selected: destinationCustom) { destinationCustom = true }
                    .accessibilityIdentifier("pass.pick.destination.custom")
            }
            if destinationCustom {
                labelField(L("着に書く字（\(PassExchange.labelLimit)字まで）", "To (up to \(PassExchange.labelLimit))"),
                           placeholder: L("例：北陸ひとり旅・金沢", "e.g. Solo trip, Kanazawa"), text: $destinationText,
                           id: "pass.pick.destination.text")
            }
            Text(L("書いた字は相手の端末にそのまま届きます（署名はありません）。「〇〇のあたり 下車」の行は、受け取った人の位置で自動です。",
                   "What you write reaches the other device as is (unsigned). The \u{201C}got off around …\u{201D} line always uses where they were."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「居住地から（自動）」の行の名前（居住地が無ければそう言う）
    private var homeTitle: String {
        guard let pref = pass.homePrefecture else {
            return L("居住地から（自動・居住地が未設定）", "From where I live (automatic \u{00B7} not set)")
        }
        return L("居住地から（自動・\(PassTicket.shortPlace(pref))）", "From where I live (automatic \u{00B7} \(pref))")
    }

    private func labelField(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            JPField(title) {
                HStack {
                    // 打っている途中では切らない（ひとことと同じ）。超えたら数を危険の色にして訳を出す
                    TextField(placeholder, text: text)
                        .accessibilityIdentifier(id)
                    Text("\(text.wrappedValue.count)/\(PassExchange.labelLimit)")
                        .font(JPFont.meta)
                        .foregroundStyle(PassExchange.labelProblem(text.wrappedValue) == nil ? WebTheme.text3 : WebTheme.danger)
                        .accessibilityHidden(true)
                }
            }
            if let problem = PassExchange.labelProblem(text.wrappedValue) {
                Text(problem)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        guard let selected else { return }
        pass.update { settings in
            settings.cardPhotoId = selected
            settings.note = note
            settings.setOrigin(originChoice, text: originText)
            settings.destinationLabel = destinationCustom ? PassExchange.cleanLabel(destinationText) : nil
        }
        PassCoordinator.shared.refresh()
        dismiss()
    }
}
