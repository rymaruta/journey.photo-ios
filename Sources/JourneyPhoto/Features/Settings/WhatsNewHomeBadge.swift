import SwiftUI

/// ホームの見出しのすぐ下の小さな印「● 新しくなったこと」（札 #628・2026-11-22 判断）。
///
/// 前は版が上がるたびに、開いた瞬間に「新しくなったこと」のシートが出た（11/15 は TestFlight 5版で5枚）。
/// いまは印だけにし、**押した人だけ読む**（押す回数: 今 1回 × 版の数 → 案 0回、読みたい人は1回）。
/// 読んだら消え、次の版が来るまで出ない。読まずにいた版の分は次の版とまとめて出る（`WhatsNew.pending`）。
///
/// 板の決まり: ホームの黒い地の上の合図なので真鍮（未読の点 8＋字）。縁は真鍮の細い線のカプセル。
/// 見た目は小さく、当たりは 44pt。設定の「新しくなったこと」からも今までどおり全部の版を読める
struct WhatsNewHomeBadge: View {

    @ObservedObject private var gate = WhatsNewGate.shared
    @State private var releases: [WhatsNew.Release] = []
    @State private var showSheet = false

    var body: some View {
        if gate.shouldPresent {
            Button {
                releases = gate.pending
                showSheet = !releases.isEmpty
            } label: {
                HStack(spacing: JPSpace.xs) {
                    Circle()
                        .fill(WebTheme.accent)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(WhatsNewHomeBadge.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                }
                .padding(.horizontal, JPSpace.s)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: JPStroke.hairline))
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JPSpace.m)
            .accessibilityLabel(WhatsNewHomeBadge.spokenLabel)
            .accessibilityHint(L("押すと、この版で変わったことを開きます", "Opens what changed in this version"))
            .accessibilityIdentifier("home.whatsNew")
            // 閉じたら読んだことにする（印が消える）。項目から別の画面へ移って閉じた回も同じ
            .sheet(isPresented: $showSheet, onDismiss: { gate.markSeen() }) {
                WhatsNewView(releases: releases, primaryTitle: L("閉じる", "Close"))
            }
        }
    }

    static var title: String { L("新しくなったこと", "What's new") }
    /// 色の合図（真鍮の点）を読み上げでも言う
    static var spokenLabel: String { L("新しくなったこと、未読あり", "What's new, unread") }
}
