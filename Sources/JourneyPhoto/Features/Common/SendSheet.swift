import SwiftUI
import UIKit

/// **アプリ内の「送る」シート**（2026-11-11・札 #541・案の模型 1-C）。写真の詳細の「共有」の行き先。
///
/// 上から: 題「送る」 → **送る相手の段（顔の列・`people`）** → 線 → 行動の段（丸い印 52 と 12 の名前）。
/// 行動は「ストーリーに載せる」「リンクをコピー」「ほかのアプリ」（iPhone の共有シート）の順。
/// 「ストーリーに載せる」は自分の写真だけ（2026-11-12・#577・`SendSheetLayout.canShareToStory`）。
///
/// 🔴 **送る相手の段（`people`）は札 #541 の ③「写真を DM で送る」の部品をそのまま渡す**（`DMPeopleFacesRow`・
/// 枝 `claude/dm-redesign`。シートの側で写しを作らない）。顔が無いときは `EmptyView` の形で開き、段も線も出さない
/// （高さは段があるかで決める・`SendSheetLayout.height(hasPeople:)`）。顔を押すとその人へ1通（`DMPhotoSend`）。
///
/// 色と字（板「黒塗りの真鍮」）: 地は surface-2（`WebTheme.sheet`・シートの地）、題は Headline 17 の 600、
/// 丸は surface-3 に白 8% の縁・印は白、名前は 12 の chip-text（白 82%）。写真の無いシートなので真鍮は置かない
/// （合図ではない）。押せるのは丸と名前を合わせた 80×80（44 以上）
struct SendSheet<People: View>: View {

    /// 行動の1つ（段の型に縛られないよう外に置く）
    typealias Action = SendSheetAction

    var title: String = L("送る", "Send")
    let actions: [Action]
    let people: () -> People

    /// 送る相手の段のあるシート（段は `DMPeopleFacesRow` を渡す）
    init(title: String = L("送る", "Send"), actions: [Action], @ViewBuilder people: @escaping () -> People) {
        self.title = title
        self.actions = actions
        self.people = people
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    private var hasPeople: Bool { People.self != EmptyView.self }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(JPFont.headline)
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            if hasPeople {
                people()
                    .padding(.top, JPSpace.xs)
                Rectangle()
                    .fill(WebTheme.hairline)
                    .frame(height: JPStroke.hairline)
                    .padding(.horizontal, JPSpace.l)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(actions) { action in
                    actionButton(action)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.vertical, JPSpace.m)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.sheet)
        .presentationDetents([.height(SendSheetLayout.height(hasPeople: hasPeople))])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("sendSheet")
    }

    @ViewBuilder
    private func actionButton(_ action: Action) -> some View {
        switch action {
        case .story(let run):
            Button {
                dismiss()
                run()
            } label: {
                actionLabel(symbol: "plus.circle.dashed", text: SendSheetLayout.storyLabel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sendSheet.story")
        case .copyLink(let url):
            Button {
                UIPasteboard.general.string = url.absoluteString
                toasts.show(L("リンクをコピーしました", "Link copied"))
                dismiss()
            } label: {
                actionLabel(symbol: "link", text: L("リンクをコピー", "Copy link"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sendSheet.copyLink")
        case .otherApps(let url):
            ShareLink(item: url) {
                actionLabel(symbol: "square.and.arrow.up", text: L("ほかのアプリ", "Other apps"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sendSheet.otherApps")
        }
    }

    /// 丸い印 52（surface-3・白 8% の縁）と、その下に 12 の名前（2行まで）
    private func actionLabel(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3.weight(.light))
                .foregroundStyle(WebTheme.text)
                .frame(width: 52, height: 52)
                .background(WebTheme.surface3, in: Circle())
                .overlay(Circle().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            Text(text)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.chipText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 80)
        .frame(minHeight: 80, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }
}

/// 送る相手の顔を読んでいる間の取り置き（顔の形の影を4つ・`DMPeopleFacesRow` と同じ寸法）。押せない
struct SendSheetFacesPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(WebTheme.surface3)
                    .frame(width: DMLook.faceAvatar, height: DMLook.faceAvatar)
                    .frame(width: DMLook.faceColumn)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.gutter)
        .frame(height: SendSheetLayout.facesRowHeight, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("送る相手を読み込み中", "Loading people"))
        .accessibilityIdentifier("sendSheet.facesLoading")
    }
}

/// 送るシートの行動の1つ
enum SendSheetAction: Identifiable {
    /// ストーリーに載せる（押したらシートを閉じてから呼ぶ）
    case story(() -> Void)
    /// リンクをコピー
    case copyLink(URL)
    /// ほかのアプリ（iPhone の共有シート）
    case otherApps(URL)

    var id: String {
        switch self {
        case .story: return "story"
        case .copyLink: return "copy"
        case .otherApps: return "other"
        }
    }
}


extension SendSheet where People == EmptyView {
    /// 送る相手の段の無いシート（札 #541 の ①。③ の担当が顔の列を足すまで）
    init(title: String = L("送る", "Send"), actions: [Action]) {
        self.title = title
        self.actions = actions
        self.people = { EmptyView() }
    }
}

/// 送るシートの寸法と言葉（画面を持たない・試験で見る）
enum SendSheetLayout {
    static let storyLabel = L("ストーリーに載せる", "Add to story")
    /// シートが閉じきるまでの間（秒）。閉じる途中に次の画面を重ねると iOS が取りこぼす
    static let closeDelay: TimeInterval = 0.45

    /// シートの高さ。題 58 ＋ 行動の段 112 ＋ 下の余白。送る相手の段があれば、その段（顔 56＋名前・検索の欄）ぶん足す
    static func height(hasPeople: Bool) -> CGFloat {
        hasPeople ? 440 : 240
    }

    /// 送る相手の顔。**送れる写真（ログイン中・全体に公開）のときだけ**、多くても 12 人（DM の空の受信箱と同じ数）
    static func faces(_ people: [FollowUser], canSend: Bool) -> [FollowUser] {
        canSend ? Array(people.prefix(12)) : []
    }

    /// 送る相手の段の中身。**シートはすぐ開き、読んでいる間は段の場所を取っておく**（読めてから背が伸びない）。
    /// 読み終えて顔が無ければ（フォローしていない・読めなかった）段ごと出さない
    enum PeopleRow: Equatable {
        case none
        case placeholder
        case faces([FollowUser])
    }

    static func peopleRow(loaded: Bool, people: [FollowUser], canSend: Bool) -> PeopleRow {
        guard canSend else { return .none }
        guard loaded else { return .placeholder }
        let shown = faces(people, canSend: canSend)
        return shown.isEmpty ? .none : .faces(shown)
    }

    /// 顔の段の高さ（`DMPeopleFacesRow`: 顔 52・間 6・名前 12pt の1行）。読んでいる間の取り置きに使う
    static let facesRowHeight: CGFloat = 52 + 6 + 16

    /// 送れたときの知らせ
    static func sentLabel(_ name: String) -> String {
        L("\(name)さんに送りました", "Sent to \(name)")
    }

    /// 「ストーリーに載せる」を出すか（札 #541 の ①・#577）。**ログイン中で、自分の、全体に公開した写真だけ**。
    ///
    /// 2026-11-12 判断（owner の原則「基本的にその人のものなので、他人が自由に操作するのは絶対ダメ」）:
    /// 人の写真を自分のストーリーに載せ直す道は作らない。サーバーも人の写真は 403
    /// 「この写真はストーリーで紹介できません」で断る（`storyPhotoShare.ts`）。
    /// `canSendPhoto` は DM で送れる写真か（ログイン中・下書きでない・全体に公開）——人の写真でも送れる
    /// （持ち主の写真へ人を連れて行くだけ）ので、送る相手の段はこちらで決めない
    static func canShareToStory(ownerId: String?, me: String?, canSendPhoto: Bool) -> Bool {
        guard canSendPhoto, let ownerId, !ownerId.isEmpty, let me, !me.isEmpty else { return false }
        return ownerId == me
    }

    /// 写真の詳細から出す行動の並び。**ストーリーは自分の、全体に公開した写真だけ**（`canShareToStory`）。
    /// リンクは個別のページがある写真だけ（`shareURL`）。リンクのコピーと「ほかのアプリ」が渡すのは**ページの
    /// URL だけ**（画像のファイルは渡さない）なので、人の写真でも出す
    static func photoActions(url: URL?, canShareToStory: Bool, story: @escaping () -> Void) -> [SendSheetAction] {
        var actions: [SendSheetAction] = []
        if canShareToStory { actions.append(.story(story)) }
        if let url {
            actions.append(.copyLink(url))
            actions.append(.otherApps(url))
        }
        return actions
    }
}
