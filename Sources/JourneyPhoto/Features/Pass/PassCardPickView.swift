import SwiftUI

/// 乗車券（旧: 名刺の一枚。2026-10-17 owner が呼び名を「わたしの乗車券」に替えた）を選ぶ（板 PassCardPick）。すれちがった人の手元に、カードになって届く一枚。
///
/// - 選べるのは**全体に公開している自分の写真だけ**（公開範囲を絞った写真は相手の端末で引けない・
///   `PassExchange.isPublicCard`）。公開一覧（`photos.json`）に載っているものから選ぶ
/// - 上の見本は、相手に届くカードと同じ回る部品（`PassSpinCard` → `PassSpinTicket`）。指で回して裏も見られる。**番号は出さない**
///   （番号は受け取った側の帳の順で決まり、自分の側では決まらない・2026-10-16 判断）
/// - 主ボタンは白（写真のある画面の主ボタン・CLAUDE.md の owner の好み。板は真鍮の塗りだが owner の決まりを取った）
/// - **券面**（2026-10-17・Pro）: 見本の下に券面を選ぶ欄。Pro でない人にも見本は見せ、押すと Pro の案内（`PaywallView`）。
///   選んだ券面は設定（`PassSettings.faceStyle`）に保存し、電波で相手に届く。Pro をやめたら見本はマルス券に戻る
///   （選んだ値は残す・`PassTicketFaceStyle.own`）
struct PassCardPickView: View {

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: StoreService
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
    /// 選んだ券面（Pro をやめても残す値・2026-10-17）
    @State private var faceChoice: PassTicketFaceStyle = .mars
    @State private var showPaywall = false
    @State private var deliveredAtPaywall = 0

    /// いま見本に出す券面（**Pro のときだけ**選んだ券面・ほかはマルス券）
    private var shownFace: PassTicketFaceStyle {
        PassTicketFaceStyle.own(chosen: faceChoice.rawValue, isPro: profile?.isPro)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var selectedPhoto: Photo? { photos.first { $0.id == selected } }

    private var previewFace: PassTicketFace {
        PassTicketFace(photo: selectedPhoto, kind: .plain, number: nil,
                       origin: PassTicket.previewOrigin(originChoice, text: originText, homePrefecture: pass.homePrefecture),
                       destination: PassTicket.previewDestination(custom: destinationCustom, text: destinationText),
                       name: profile?.name ?? L("あなた", "You"), distance: nil, date: nil,
                       count: PassTicket.countLabel(.plain, meetingCount: nil),
                       via: PassTicket.via(L("旅先", "your trip")), style: shownFace)
    }

    /// 見本の裏（相手に届く形・会ってから決まる区間と回数は「—」・`PassTicketBackFace.preview`）
    private var previewBack: PassTicketBackFace {
        PassTicketBackFace.preview(photoTitle: selectedPhoto?.displayTitle, note: note,
                                   name: profile?.name ?? L("あなた", "You"),
                                   origin: originChoice, homePrefecture: pass.homePrefecture)
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
                // 相手に届くきっぷ（束の画面と同じ回る部品 `PassSpinTicket`・同じ手つき・2026-10-16 owner の頼み）。
                // 区間の右・経由は会ってから決まるので、見本では「旅先」とする。番号は受け取った側の帳の順
                // なので出さない。日付・区間（km）・回数も会ってから決まるので、表・裏とも「—」（2026-10-17 マルス券）
                // **縮めない**（縮めると字が 12pt を割る・2026-10-16 の読み直し）。束の画面と同じ 300 幅で出す
                PassSpinCard(front: previewFace, back: previewBack,
                             spokenName: L("相手に届くカード", "the card others receive"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                faceSection
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
        .navigationTitle(L("わたしの乗車券", "My ticket"))
        .navigationBarTitleDisplayMode(.inline)
        // 買えたら（サーバーが受け取ったら）プロフィールを読み直して、選んだ券面を使えるようにする
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            if store.deliveredRevision != deliveredAtPaywall { Task { await reloadProfile() } }
        }) {
            PaywallView()
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            selected = pass.settings.cardPhotoId
            note = pass.settings.note
            originChoice = pass.settings.origin
            originText = pass.settings.originLabel ?? ""
            destinationCustom = pass.settings.destinationLabel != nil
            destinationText = pass.settings.destinationLabel ?? ""
            faceChoice = PassTicketFaceStyle.fromWire(pass.settings.faceStyle)
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
                       message: L("乗車券にできるのは、全体に公開している写真だけです。投稿してからもう一度開いてください。",
                                  "Only photos shared with everyone can go on your ticket. Post one, then come back."))
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
                    .foregroundStyle(PassExchange.noteProblem(note) == nil ? WebTheme.text3 : WebTheme.danger)
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
    /// （通報・伏せる）になる。「経由」の行は書いた字に関わらず、受け取った側の位置で自動
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
                JPRadioRow(title: L("出さない（どこか発）", "Don\u{2019}t show (somewhere)"), selected: originChoice == .hidden) {
                    originChoice = .hidden
                }
                .accessibilityIdentifier("pass.pick.origin.hidden")
            }
            if originChoice == .custom {
                labelField(L("発に書く字（\(PassExchange.labelLimit)字まで）", "From (up to \(PassExchange.labelLimit))"),
                           placeholder: L("例：雪国", "e.g. Snow"), text: $originText, id: "pass.pick.origin.text")
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
                           placeholder: L("例：北陸ひとり旅", "e.g. Hokuriku"), text: $destinationText,
                           id: "pass.pick.destination.text")
            }
            Text(L("書いた字は相手の端末にそのまま届きます（署名はありません）。「経由 〇〇のあたり」の行は、受け取った人の位置で自動です。",
                   "What you write reaches the other device as is (unsigned). The \u{201C}via …\u{201D} line always uses where they were."))
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

    // MARK: - 券面（Pro・2026-10-17）

    /// 券面を選ぶ欄（見本の下・横に並べる）。Pro でない人には見本を見せ、押すと Pro の案内
    private var faceSection: some View {
        let isPro = profile?.isPro == true
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(L("券面", "Ticket design"))
            Text(isPro
                 ? L("選んだ券面で、すれちがった人の手元に届きます。", "Your ticket reaches people you pass in this design.")
                 : L("特別な券面は Pro で選べます。選ぶと、すれちがった人の手元にもその券面で届きます。",
                     "Special designs come with Pro. People you pass receive your ticket in that design."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: JPSpace.s) {
                    ForEach(PassTicketFaceStyle.pickerOrder) { style in
                        faceOption(style, isPro: isPro)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    private func faceOption(_ style: PassTicketFaceStyle, isPro: Bool) -> some View {
        let locked = style.needsPro && !isPro
        let on = style == shownFace
        return Button {
            if locked {
                deliveredAtPaywall = store.deliveredRevision
                showPaywall = true
            } else {
                faceChoice = style
            }
        } label: {
            VStack(spacing: 6) {
                PassFaceSwatch(style: style)
                    .padding(3)
                    // 選んだ券面: 真鍮の 2pt の縁（黒い地の上）とチェック（色だけで伝えない）
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(on ? WebTheme.accent : WebTheme.border, lineWidth: on ? JPStroke.emphasis : JPStroke.hairline)
                    }
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WebTheme.accentText)
                                .frame(width: 20, height: 20)
                                .background(WebTheme.accent, in: Circle())
                                .overlay(Circle().strokeBorder(Color.black, lineWidth: JPStroke.emphasis))
                                .offset(x: 6, y: -6)
                                .accessibilityHidden(true)
                        } else if locked {
                            // 「PRO」の合図（真鍮・黒い地の上）
                            HStack(spacing: 2) {
                                Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                                Text("PRO").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(WebTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black, in: Capsule())
                            .offset(x: -6, y: 6)
                            .accessibilityHidden(true)
                        }
                    }
                Text(style.name)
                    .font(.system(size: 12))
                    .foregroundStyle(on ? WebTheme.text : WebTheme.text2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: PassFaceSwatch.size.width + 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("券面 \(style.name)", "\(style.name) design"))
        .accessibilityValue(locked ? L("Pro で選べます", "Available with Pro") : "")
        .accessibilityHint(locked ? L("押すと Pro の案内を開きます", "Opens the Pro details") : "")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pass.pick.face.\(style.rawValue)")
    }

    /// Pro を買った後に、自分のプロフィール（Pro の印）を読み直す
    private func reloadProfile() async {
        let mine = try? await environment.profiles.myProfile()
        if let mine { profile = mine }
    }

    private func save() {
        guard let selected else { return }
        let isPro = profile?.isPro == true
        let face = faceChoice
        pass.update { settings in
            // 券面は Pro のときだけ変える（Pro でないときは前に選んだ値を残す・2026-10-17）
            if isPro { settings.faceStyle = face == .mars ? nil : face.rawValue }
            settings.cardPhotoId = selected
            settings.note = note
            // 「自分で書く」を空のまま保存したら、発は「出さない」・着は「すれちがった所」に戻す（`setOrigin`・`setDestination`）
            settings.setOrigin(originChoice, text: originText)
            settings.setDestination(custom: destinationCustom, text: destinationText)
        }
        PassCoordinator.shared.refresh()
        dismiss()
    }
}
