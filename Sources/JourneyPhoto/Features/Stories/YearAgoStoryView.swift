import SwiftUI
import UIKit

/// **②「1年前」の閲覧**（2026-11-12・札 #543・資料第6章 段2 ②）。
///
/// ストーリーの列の「1年前」の輪から全画面で開く。見方は人のストーリーと同じ:
/// 1枚 4秒で進む・右 2/3 を叩く＝次・左 1/3＝前・押さえる＝止まる・下へ払う・×＝閉じる。最後の1枚の後は閉じる。
/// 1枚目は「ほこり」をかぶって出て 0.6秒で自然に晴れる（飾り・なでると早く晴れる。なでないと見られない形にはしない）。
///
/// **人のストーリーの閲覧（`StoryViewerView`）は使わない**——あちらは「見た」をサーバーへ知らせる作り。
/// ここは端末の写真だけで、何も送らない（`YearAgoTrips` の注記）。
///
/// 寸法（章）: 自分のストーリーの板と同じ（写真の面・角は下だけ 24・進みの棒 3）。下の2つは 50 の高さで並べ、
/// 写真の下の黒地に白の塗り1つ（ストーリーに出す）＋ガラス1つ（投稿にする）
struct YearAgoStoryView: View {

    let pick: YearAgoTrips.Pick
    /// 端末の一冊の地名（無ければ nil・題は日付だけ）
    let name: String?
    /// 「ストーリーに出す」: 今見ている1枚の本体を渡す（呼び手が作る画面を開く）
    let onShare: (Data) -> Void
    /// 「投稿にする」: ①の現像の画面を、この旅で開く
    let onPost: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity

    @State private var index = 0
    /// 今の1枚の進み（0〜1）
    @State private var progress: Double = 0
    /// 押さえて止めている
    @State private var held = false
    /// 押し始め（叩いたか・払ったかを見る）
    @State private var pressStart: Date?
    /// 読めなかった写真（飛ばす）
    @State private var skipped: Set<String> = []
    /// ほこりの濃さ（1 → 0 で晴れる）
    @State private var dust: Double = 1
    /// 「ストーリーに出す」で本体を読んでいる
    @State private var loadingShare = false
    /// 読めた写真（iCloud の本体を落としている間は進まない・`YearAgoTrips.canAdvance`）
    @State private var loaded: Set<String> = []

    /// 圏外（見るのは端末の中だけでできる。送るのはあとで）
    private var offline: Bool { connectivity.isOffline || PreviewSession.developOffline }

    private var ids: [String] { pick.photoIds.filter { !skipped.contains($0) } }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: JPSpace.m) {
                photoArea(width: geometry.size.width)
                buttons
                    .padding(.horizontal, JPSpace.s)
                    .padding(.bottom, JPSpace.xs)
            }
        }
        .background { WebTheme.background.ignoresSafeArea() }
        .statusBarHidden()
        .task(id: index) { await play() }
        .onChange(of: ids.isEmpty) { _, empty in if empty { dismiss() } }
        .accessibilityIdentifier("yearAgo.viewer")
    }

    // MARK: - 写真の面

    private func photoArea(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if ids.indices.contains(index) {
                let id = ids[index]
                LibraryShotImage(id: id, side: 440, onFailed: { skip(id) }, onLoaded: { loaded.insert(id) },
                                 loadingText: YearAgoTrips.loadingText)
                    .id(id)
                    .accessibilityHidden(true)
                // ほこりは読めてからかぶせる（読み込み中の字を隠さない）
                if loaded.contains(id) { dustLayer }
            }
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(YearAgoTrips.title(name: name, day: pick.day, year: YearAgoTrips.year(of: pick.day)))
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(WebTheme.foreground)
                Text(YearAgoTrips.subtitle(trip: pick.trip, day: pick.day, count: ids.count))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.muted2)
            }
            .jpPhotoTextShadow()
            .padding(JPSpace.l)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: JPRadius.xl, bottomTrailingRadius: JPRadius.xl))
        .contentShape(Rectangle())
        .gesture(press(width: width))
        .overlay(alignment: .top) { head }
        .overlay { offlineNotice }
        .ignoresSafeArea(edges: .top)
        .accessibilityAction(named: L("次の写真", "Next photo")) { advance() }
        .accessibilityAction(named: L("前の写真", "Previous photo")) { goBack() }
    }

    /// 上: 進みの棒（3）と、「1年前の今日」「あなたにだけ見えています」・閉じる
    private var head: some View {
        VStack(spacing: JPSpace.xs) {
            HStack(spacing: JPSpace.xxs) {
                ForEach(Array(ids.enumerated()), id: \.element) { offset, _ in
                    GeometryReader { bar in
                        Capsule().fill(Color.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.white)
                                    .frame(width: bar.size.width * fill(of: offset))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: JPSpace.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(YearAgoTrips.headline(pick.yearsAgo))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.foreground)
                    HStack(spacing: JPSpace.xxs) {
                        Image(systemName: "lock.fill").font(.caption2).accessibilityHidden(true)
                        Text(L("あなたにだけ見えています", "Only you can see this"))
                            .font(JPFont.caption)
                    }
                    .foregroundStyle(WebTheme.muted2)
                }
                .jpPhotoTextShadow()
                .accessibilityElement(children: .combine)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .jpPhotoTextShadow()
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
                .accessibilityIdentifier("yearAgo.close")
            }
        }
        .padding(.horizontal, JPSpace.xs)
        .safeAreaPadding(.top)
        .padding(.top, JPSpace.xs)
    }

    /// 圏外の一言（章「圏外」・写真の上なのでガラスに白）。題の上に置く
    @ViewBuilder
    private var offlineNotice: some View {
        if let notice = YearAgoTrips.offlineNotice(offline: offline) {
            VStack {
                Spacer()
                Text(notice)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, JPSpace.s)
                    .jpGlass(in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, JPSpace.l)
                    .padding(.bottom, 120)
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("yearAgo.offline")
        }
    }

    /// ほこり（飾り）。色をかぶせた地と、点の散らし。0.6秒で晴れる
    private var dustLayer: some View {
        ZStack {
            Color(red: 0.59, green: 0.55, blue: 0.47).opacity(0.72)
            GeometryReader { g in
                ForEach(0..<60, id: \.self) { k in
                    Circle()
                        .fill(Color.white.opacity(k % 3 == 0 ? 0.35 : 0.22))
                        .frame(width: 2, height: 2)
                        .position(x: g.size.width * Self.scatter(k, 0.37),
                                  y: g.size.height * Self.scatter(k, 0.61))
                }
            }
        }
        .opacity(dust)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 点の散らし（決まった並び。開くたびに変わらない）
    private static func scatter(_ k: Int, _ salt: Double) -> Double {
        let v = sin(Double(k) * 12.9898 + salt * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    private func fill(of offset: Int) -> Double {
        if offset < index { return 1 }
        if offset == index { return progress }
        return 0
    }

    // MARK: - 下の2つ

    private var buttons: some View {
        HStack(spacing: JPSpace.xs) {
            Button(action: share) {
                Group {
                    if loadingShare {
                        ProgressView().tint(WebTheme.accentText)
                    } else {
                        Text(L("ストーリーに出す", "Share to story"))
                    }
                }
                .jpPillButton(.primary)
            }
            .buttonStyle(.plain)
            .disabled(loadingShare)
            .accessibilityIdentifier("yearAgo.share")
            Button {
                dismiss()
                onPost()
            } label: {
                Text(L("投稿にする", "Make a post"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, minHeight: JPHeight.primaryButton)
                    .jpGlass(in: Capsule(), border: 0.14)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yearAgo.post")
        }
    }

    // MARK: - 動き

    /// 押さえる＝止まる・叩く＝次／前・下へ払う＝閉じる。なでるとほこりが早く晴れる
    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil { pressStart = Date() }
                held = true
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if moved > 20, dust > 0 { withAnimation(.easeOut(duration: 0.15)) { dust = 0 } }
            }
            .onEnded { value in
                let started = pressStart ?? Date()
                pressStart = nil
                held = false
                let dx = value.translation.width, dy = value.translation.height
                if YearAgoTrips.swipeCloses(dx: dx, dy: dy) {
                    dismiss()
                    return
                }
                let short = Date().timeIntervalSince(started) < 0.25 && abs(dx) + abs(dy) < 12
                guard short else { return }
                if YearAgoTrips.tapGoesNext(x: value.location.x, width: width) { advance() } else { goBack() }
            }
    }

    /// 1枚を流す（4秒・止めている間と読み込み中は進めない）。ほこりは**読めてから**出して晴らす
    /// （iCloud から落としている間に晴れてしまうと、ほこりが見えない）
    private func play() async {
        progress = 0
        dust = reduceMotion ? 0 : 1
        var dustCleared = reduceMotion
        let step = 1.0 / 30
        while !Task.isCancelled {
            let current = ids.indices.contains(index) ? ids[index] : ""
            if !dustCleared, loaded.contains(current) {
                dustCleared = true
                withAnimation(.easeOut(duration: YearAgoTrips.dustSeconds)) { dust = 0 }
            }
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            if Task.isCancelled { return }
            guard YearAgoTrips.canAdvance(held: held, sharing: loadingShare,
                                          loaded: loaded.contains(current)) else { continue }
            progress += step / YearAgoTrips.secondsPerPhoto
            if progress >= 1 {
                advance()
                return
            }
        }
    }

    private func advance() {
        if index + 1 < ids.count { index += 1 } else { dismiss() }
    }

    private func goBack() {
        if index > 0 { index -= 1 } else { progress = 0 }
    }

    /// 読めなかった写真は飛ばす（章: iCloud から落とせなかった写真）
    private func skip(_ id: String) {
        skipped.insert(id)
        if index >= ids.count { index = max(0, ids.count - 1) }
    }

    private func share() {
        guard ids.indices.contains(index), !loadingShare else { return }
        let id = ids[index]
        loadingShare = true
        Task {
            let data: Data?
            if let sample = DevelopPreview.image(for: id) {
                data = sample.jpegData(compressionQuality: 0.9)
            } else {
                data = await PhotoLibrary.imageData(for: id)
            }
            loadingShare = false
            guard let data else {
                toasts.show(L("写真を読み込めませんでした。通信できる場所でもう一度お試しください",
                              "Couldn't load the photo. Try again with a connection."), kind: .failure)
                return
            }
            dismiss()
            onShare(data)
        }
    }
}
