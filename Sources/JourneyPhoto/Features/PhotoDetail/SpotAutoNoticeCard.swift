import SwiftUI

/// **自動の結びの知らせと「外す」**（撮った本人にだけ・2026-10-31 判断・journey.photo-ios#425）。
///
/// 案の板（https://claude.ai/artifact/NHrF23fezgz9sAE6qvS6xW の PhotoIOS・PhotoWeb の 4）と Web の
/// `app/photo/[id]/SpotAutoNotice.tsx` と同じ言葉・同じ動き:
///   眉「あなたにだけ表示」（真鍮・黒地の札の上）→「撮影スポット「◯◯」に結びました」→ 説明 →「違う場所なので外す」。
///   外したあとは「「◯◯」への自動の結びつけを外しています」と「元に戻す」。
/// 言葉は「結ぶ」にそろえ、「まとめ」は使わない（#425 の経過）。距離は出さない（写真の位置を細かく言わない）。
///
/// 札は v2 の `JPCard`（surface-1・白 8% の縁・角 16）。ボタンは線の副ボタン（44・白 14% の縁・幅いっぱい・
/// 板の `flex: 1`）。失敗は札の中のボタンのすぐ上に赤（13pt・丸に！）で出す（デザインシステム 06「起きた所の
/// すぐ上・トーストにしない」）。成功は知らせ（`ToastCenter`）で、サイトの更新まで時間がかかることを言う
struct SpotAutoNoticeCard: View {

    let spotName: String
    /// いま外してあるか
    let off: Bool
    /// 送っている間（二度押しを受けない）
    let saving: Bool
    /// 送れなかった知らせ（無ければ nil）
    let failure: String?
    let onToggle: () -> Void

    var body: some View {
        JPCard {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                // 黒地の札の上の眉ラベルは真鍮（デザインシステム 05）
                Text(SpotAutoNoticeText.eyebrow)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
                Text(SpotAutoNoticeText.title(spotName: spotName, off: off))
                    .jpSystemFont(16, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(WebTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(SpotAutoNoticeText.body(off: off))
                    .font(JPFont.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure {
                    Label {
                        Text(failure)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("photo.spotAuto.failure")
                }
                Button(action: onToggle) {
                    HStack(spacing: JPSpace.xs) {
                        if saving {
                            ProgressView()
                                .tint(WebTheme.foreground)
                                .accessibilityHidden(true)
                        }
                        Text(SpotAutoNoticeText.button(off: off))
                    }
                    .jpOutlineButton(.regular, fullWidth: true)
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.top, JPSpace.xxs)
                .accessibilityIdentifier("photo.spotAuto.toggle")
            }
            .padding(JPSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 眉は読み上げでは「あなたにだけ表示」と先に言う（見出しの前）
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SpotAutoNoticeText.eyebrow)
        .accessibilityIdentifier("photo.spotAuto")
    }
}
