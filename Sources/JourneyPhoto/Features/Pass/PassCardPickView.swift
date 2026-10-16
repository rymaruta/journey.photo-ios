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
    @State private var showsFrom = true
    @State private var profile: UserProfile?
    @State private var didLoad = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var selectedPhoto: Photo? { photos.first { $0.id == selected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                Text(L("すれちがった人の手元に、カードになって届く一枚です。いちばん好きな写真を選んでください。いつでも変えられます。",
                       "This photo reaches the people you pass as a card. Pick your favorite — you can change it any time."))
                    .font(.subheadline)
                    .lineSpacing(5)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                PassCardFront(photo: selectedPhoto, name: profile?.name ?? L("あなた", "You"),
                              avatarURL: profile?.avatarURL(),
                              from: showsFrom ? pass.homePrefecture.map(PassExchange.fromLabel) : nil,
                              number: nil,
                              size: PassCardStyle.previewSize, corner: PassCardStyle.previewCorner,
                              footer: PassCardStyle.previewFooter)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel(L("相手に届くカードの表", "The front of the card others receive"))
                JPEyebrowLine(L("あなたの写真から選ぶ", "Choose from your photos"))
                grid
                noteField
                fromField
                Button(action: save) {
                    Text(L("この一枚をカードにする", "Use this photo as my card")).jpPillButton(.main(onPhoto: true))
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)
                .opacity(selected == nil ? 0.5 : 1)
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
            showsFrom = pass.settings.showsFrom
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
                                    Rectangle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis)
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
        JPField(L("裏に書くひとこと（\(PassExchange.noteLimit)字まで）", "A note on the back (up to \(PassExchange.noteLimit))")) {
            HStack {
                TextField(L("例：霧の朝が好きです", "e.g. I love misty mornings"), text: $note)
                    .onChange(of: note) { _, value in
                        let clean = String(value.prefix(PassExchange.noteLimit))
                        if clean != value { note = clean }
                    }
                Text("\(note.count)/\(PassExchange.noteLimit)")
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
        }
    }

    private var fromField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("どこから来た人か", "Where you\u{2019}re from"))
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
                .accessibilityHidden(true)
            Button { showsFrom.toggle() } label: {
                HStack {
                    Text(fromText)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                    Spacer()
                    Text(showsFrom ? L("出さないもできます", "You can hide this") : L("押すと載せます", "Tap to show"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("どこから来た人か", "Where you\u{2019}re from"))
            .accessibilityValue(fromText)
            .accessibilityHint(showsFrom ? L("押すとカードに載せません", "Tap to hide it from your card")
                                         : L("押すとカードに載せます", "Tap to show it on your card"))
        }
    }

    private var fromText: String {
        guard showsFrom else { return L("載せない", "Hidden") }
        guard let pref = pass.homePrefecture else { return L("居住地が未設定（載りません）", "No home set (not shown)") }
        return PassExchange.fromLabel(pref)
    }

    private func save() {
        guard let selected else { return }
        pass.update { settings in
            settings.cardPhotoId = selected
            settings.note = note
            settings.showsFrom = showsFrom
        }
        PassCoordinator.shared.refresh()
        dismiss()
    }
}
