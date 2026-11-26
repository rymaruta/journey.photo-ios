import SwiftUI
import UIKit

/// 初めての投稿のあとの「投稿しました」1枚（札 #628・`PostedSummaryCenter`・2026-11-22 判断）。
///
/// 板の決まり: シートの面（`WebTheme.sheet`）、見出しは明朝、左上の「閉じる」（`SheetCloseButton`・2026-11-13 owner 承認）。
/// 写真のある画面なので主ボタン「カードを共有」は白（`jpPillButton(.primary)`）。行は白 7% の札に字、右の操作は真鍮の字
/// （黒に近い面の上の合図・リンクと同じ扱い）。押せる所は 44pt 以上。
///
/// 閉じるまでの押す回数: 今 5〜7回（カード、カバー、通知の説明、iPhone の許可、届いたラベル、お礼）→ 案 1回（閉じる）。
/// 行は押した人だけが進む
struct PostedSummarySheet: View {

    let summary: PostedSummaryCenter.Summary

    @ObservedObject private var center = PostedSummaryCenter.shared
    @ObservedObject private var pushPrimer = PushPrimerStore.shared
    @EnvironmentObject private var push: PushCenter
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    /// 開いている間に届いた行（ラベル）も描くため、店の中身を優先する
    private var shown: PostedSummaryCenter.Summary { center.presented ?? summary }

    @State private var pushAsking = false
    @State private var cover: CoverState = .idle

    enum CoverState: Equatable { case idle, applying, done, failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JPSpace.l) {
                    Text(PostedSummaryText.title)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("postedSummary.title")
                    if let card = shown.card {
                        thumbnail(card)
                        Button { center.close(then: .shareCard) } label: {
                            Text(PostedSummaryText.shareCard).jpPillButton(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("postedSummary.shareCard")
                    }
                    VStack(spacing: JPSpace.xs) {
                        ForEach(rowsShown, id: \.self) { row in rowView(row) }
                    }
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, JPSpace.m)
                .padding(.bottom, JPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(WebTheme.sheet, ignoresSafeAreaEdges: .all)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: { center.close(then: nil) })
                        .accessibilityIdentifier("postedSummary.close")
                }
            }
        }
        .presentationBackground(WebTheme.sheet)
        .presentationDetents([.large])
        .accessibilityIdentifier("postedSummary")
    }

    /// 描く行（カバーにした後も「カバーにしました」を残し、押した結果が見えるようにする）
    private var rowsShown: [RowKey] {
        var keys: [RowKey] = []
        for row in PostedSummaryCenter.rows(shown) {
            switch row {
            case .push: keys.append(.push)
            case .cover: keys.append(.cover)
            case .labels(let count): keys.append(.labels(count))
            }
        }
        if cover == .done, !keys.contains(.cover) {
            keys.insert(.cover, at: keys.firstIndex(where: { if case .labels = $0 { return true }; return false }) ?? keys.count)
        }
        return keys
    }

    enum RowKey: Hashable {
        case push, cover
        case labels(Int)
    }

    @ViewBuilder
    private func rowView(_ key: RowKey) -> some View {
        switch key {
        case .push:
            row(text: PostedSummaryText.pushRow, action: PostedSummaryText.pushAction, busy: pushAsking,
                id: "postedSummary.push") { turnOnPush() }
        case .cover:
            switch cover {
            case .done:
                row(text: PostedSummaryText.coverDone, action: nil, busy: false, id: "postedSummary.cover") {}
            case .failed:
                row(text: PostedSummaryText.coverFailed, action: PostedSummaryText.retry, busy: false,
                    id: "postedSummary.cover") { applyCover() }
            case .idle, .applying:
                row(text: PostedSummaryText.coverRow(showsCoins: shown.cover?.showsCoins ?? false),
                    action: PostedSummaryText.coverAction, busy: cover == .applying,
                    id: "postedSummary.cover") { applyCover() }
            }
        case .labels(let count):
            row(text: PostedSummaryText.labelsRow(count), action: PostedSummaryText.labelsAction, busy: false,
                id: "postedSummary.labels") { center.close(then: .labels) }
        }
    }

    /// 1行: 左に字、右に真鍮の操作。行ぜんたいが当たり（44pt 以上）
    private func row(text: String, action: String?, busy: Bool, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: JPSpace.s) {
                Text(text)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if busy {
                    ProgressView().tint(WebTheme.accent)
                } else if let action {
                    Text(action)
                        .font(JPFont.body.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, JPSpace.m)
            .frame(maxWidth: .infinity, minHeight: JPHeight.secondaryButton + JPSpace.xs)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.field))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.field))
        }
        .buttonStyle(.plain)
        .disabled(busy || action == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// 投稿に使った絵（位置などを落とした絵・`PostedShareCard.photoData`）
    @ViewBuilder
    private func thumbnail(_ card: PostedShareCard) -> some View {
        if let image = UIImage(data: card.photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                .accessibilityHidden(true)
        }
    }

    /// 「続ける」: 説明の画面を挟まず、iPhone の許可へ（理由は行の字で言っている）。端末で1回だけ聞く
    private func turnOnPush() {
        guard !pushAsking else { return }
        pushAsking = true
        Task {
            await push.refreshAuthorization()
            if pushPrimer.consume(signedIn: auth.userId != nil, permission: push.permission) {
                _ = await push.enable()
            }
            pushAsking = false
            center.clearPush()
        }
    }

    /// 「する」: この写真をカバーに（`CoverOfferView` と同じ口・`ProfileImageFromPhoto.applyCover`）
    private func applyCover() {
        guard cover != .applying, let offer = shown.cover else { return }
        guard let url = offer.imageURL else { cover = .failed; return }
        cover = .applying
        Task {
            let ok = await ProfileImageFromPhoto.applyCover(photoId: offer.photoId, url: url,
                                                            environment: environment, auth: auth)
            cover = ok ? .done : .failed
            if ok { center.clearCover() }
        }
    }
}

/// 「投稿しました」の言葉（札 #628）
enum PostedSummaryText {
    static var title: String { L("投稿しました", "Posted") }
    static var shareCard: String { L("カードを共有", "Share card") }
    static var pushRow: String { L("いいねや返事が来たら知らせる", "Get notified about likes and replies") }
    /// 2026-11-26 判断（審査 5.1.1(iv)）: 押すと iOS の確認が出るので、通知の説明（`PushPrimerText.proceed`）と同じ「続ける」。
    /// 「オンにする」「許可」とは呼ばない
    static var pushAction: String { PushPrimerText.proceed }
    /// カバーの行。初めてのカバーで硬貨が届くとき（`Offer.showsCoins`）は枚数も言う（前の `CoverOfferView` と同じ約束）
    static func coverRow(showsCoins: Bool) -> String {
        guard showsCoins else { return L("この写真をカバーに", "Use this photo as your cover") }
        let n = ProfileRewardText.coinsPerKind
        return L("この写真をカバーに（硬貨 \(n) 枚）", "Use this photo as your cover (\(n) coins)")
    }
    static var coverAction: String { L("する", "Use") }
    static var coverDone: String { L("カバーにしました", "Cover updated") }
    static var coverFailed: String { L("カバーにできませんでした", "Couldn't set the cover") }
    static var retry: String { L("もう一度", "Retry") }
    static func labelsRow(_ count: Int) -> String {
        L("ラベルが\(count)枚届きました", count == 1 ? "A label arrived" : "\(count) labels arrived")
    }
    static var labelsAction: String { L("見る", "View") }
}
