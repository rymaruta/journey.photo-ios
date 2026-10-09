import MapKit
import SwiftUI
import UIKit

// 「電波なしで使える旅」の画面（板 72c 圏外の旅行プラン・72d 圏外の場所の詳細・2026-10-09）。
// **端末に保存した中身（`OfflineTripManifest`）だけで組む**——サーバーを読まない。

// MARK: - 共通の部品

/// 板の札の絵: 電話に下向きの矢印（保存前・保存中）／チェック（保存済み）
struct OfflinePhoneIcon: View {
    var saved = false
    var side: Double = 22
    var color: Color = WebTheme.accent

    var body: some View {
        let k = side / 24
        Path { p in
            p.addRoundedRect(in: CGRect(x: 6 * k, y: 2.5 * k, width: 12 * k, height: 19 * k),
                             cornerSize: CGSize(width: 2.5 * k, height: 2.5 * k))
            if saved {
                p.move(to: CGPoint(x: 9.3 * k, y: 11.5 * k))
                p.addLine(to: CGPoint(x: 11.3 * k, y: 13.5 * k))
                p.addLine(to: CGPoint(x: 14.8 * k, y: 9.5 * k))
            } else {
                p.move(to: CGPoint(x: 12 * k, y: 7.5 * k))
                p.addLine(to: CGPoint(x: 12 * k, y: 14 * k))
                p.move(to: CGPoint(x: 9.5 * k, y: 11.5 * k))
                p.addLine(to: CGPoint(x: 12 * k, y: 14 * k))
                p.addLine(to: CGPoint(x: 14.5 * k, y: 11.5 * k))
            }
            p.move(to: CGPoint(x: 10.5 * k, y: 18.5 * k))
            p.addLine(to: CGPoint(x: 13.5 * k, y: 18.5 * k))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round, lineJoin: .round))
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// 圏外の帯（板 72c・72d: 真鍮の薄い地 #201B11・電波の無い印は真鍮）
struct OfflineBanner: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// 端末に保存した画像。**読むのは出たときに1回**（描くたびにファイルを読まない）
struct OfflineStoredImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
        }
    }
}

/// 番号の丸（板 72c: 24pt・真鍮の地に墨の数字）
struct OfflineStopNumber: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(JPFont.number(12, weight: .bold))
            .foregroundStyle(WebTheme.accentText)
            .frame(width: 24, height: 24)
            .background(WebTheme.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - 圏外の旅行プラン（板 72c）

struct OfflineTripView: View {

    let manifest: OfflineTripManifest
    /// 電波があるときに「見え方を確かめる」で開いた（帯の文を変える）
    var preview = false

    @EnvironmentObject private var offline: OfflineTripStore

    var body: some View {
        ScrollView {
            OfflineTripContent(manifest: manifest, preview: preview)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(L("旅行プラン", "Trip plans"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 72c の中身（旅行プランの画面が圏外のときにも、そのまま差し込む）
struct OfflineTripContent: View {

    let manifest: OfflineTripManifest
    var preview = false

    @EnvironmentObject private var offline: OfflineTripStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OfflineBanner(title: preview ? OfflineTripText.previewBanner : OfflineTripText.offlineBanner,
                          detail: OfflineTripText.bannerDetail(savedAt: manifest.savedAt))

            VStack(alignment: .leading, spacing: 4) {
                Text(manifest.title.isEmpty ? L("無題のプラン", "Untitled trip") : manifest.title)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.muted2)
            }
            .padding(.horizontal, 4)

            if let url = offline.fileURL(planId: manifest.planId, file: manifest.overviewMap) {
                VStack(alignment: .leading, spacing: 6) {
                    OfflineStoredImage(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: OfflineTripMap.overviewSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        .accessibilityElement()
                        .accessibilityLabel(L("保存した地図の画像。場所 1 から \(manifest.stopCount) の位置",
                                              "Saved map image showing places 1 to \(manifest.stopCount)"))
                        .accessibilityAddTraits(.isImage)
                    Text(L("保存した地図の画像です。拡大や道案内はできません",
                           "This is a saved map image. You can't zoom or get directions."))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 4)
                }
            }

            ForEach(manifest.days, id: \.number) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Text(L("\(day.number) 日目", "Day \(day.number)"))
                        if let label = TakenDay.label(day.date) {
                            Text(L("・\(label)", " · \(label)")).font(JPFont.mono(12))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 0) {
                        ForEach(Array(day.stops.enumerated()), id: \.element.number) { i, stop in
                            if i > 0 { JPCardDivider() }
                            NavigationLink {
                                OfflineSpotView(manifest: manifest, stop: stop, day: day, preview: preview)
                            } label: {
                                row(stop)
                            }
                            .buttonStyle(JPRowButtonStyle())
                        }
                    }
                    .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let range = OfflineTripText.dateRange(start: manifest.startDate, end: manifest.endDate, short: false) {
            parts.append(range)
        }
        parts.append(L("\(manifest.stopCount) か所", "\(manifest.stopCount) \(manifest.stopCount == 1 ? "place" : "places")"))
        return parts.joined(separator: " · ")
    }

    private func row(_ stop: OfflineTripManifest.Stop) -> some View {
        HStack(spacing: 12) {
            OfflineStopNumber(number: stop.number)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name)
                    .font(.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if let line = stop.light?.line {
                    Text(line)
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([String(stop.number), stop.name, stop.light?.line].compactMap { $0 }.joined(separator: " · "))
    }
}

// MARK: - 圏外の場所の詳細（板 72d）

struct OfflineSpotView: View {

    let manifest: OfflineTripManifest
    let stop: OfflineTripManifest.Stop
    let day: OfflineTripManifest.Day
    var preview = false

    @EnvironmentObject private var offline: OfflineTripStore
    @EnvironmentObject private var connectivity: Connectivity
    @State private var viewing: SampleTarget?
    @State private var copied = false

    private struct SampleTarget: Identifiable { let index: Int; var id: Int { index } }

    private func url(_ file: String?) -> URL? { offline.fileURL(planId: manifest.planId, file: file) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(JPFont.screenTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                            .accessibilityAddTraits(.isHeader)
                        if let address = stop.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(WebTheme.muted2)
                        }
                    }
                    .padding(.horizontal, 4)

                    if connectivity.isOffline || preview {
                        OfflineBanner(title: preview && !connectivity.isOffline
                                      ? OfflineTripText.previewBanner : OfflineTripText.offlineBanner)
                    }
                    lightSection
                    samplesSection
                    placeSection
                }
                .padding(.horizontal, 16)
                .padding(.top, -58)
                .padding(.bottom, 32)
            }
        }
        .webScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { target in
            OfflineSampleViewer(samples: stop.samples, start: target.index, url: url)
        }
    }

    /// 頭の写真（1枚目の作例）。下を黒へ溶かす（板: 230pt・溶け 120pt）
    private var hero: some View {
        ZStack(alignment: .bottom) {
            OfflineStoredImage(url: url(stop.samples.first?.file))
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(L("\(stop.name)の作例（端末に保存したもの）", "Example of \(stop.name) (saved on this iPhone)"))
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var lightSection: some View {
        if let light = stop.light, !light.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(lightHeading)
                    .font(JPFont.mono(12, medium: true))
                    .foregroundStyle(WebTheme.faint)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          alignment: .leading, spacing: 8) {
                    ForEach(light.entries, id: \.label) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.label)
                                .font(.caption)
                                .foregroundStyle(WebTheme.muted2)
                            Text(entry.value)
                                .font(JPFont.number(17, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(WebTheme.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    /// 「光の時刻 · 1 日目 12月24日」
    private var lightHeading: String {
        var head = L("光の時刻 · \(day.number) 日目", "Light · Day \(day.number)")
        if let date = OfflineTripText.shortDate(ymd: day.date) { head += " \(date)" }
        return head
    }

    @ViewBuilder
    private var samplesSection: some View {
        if !stop.samples.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("保存した作例 · \(stop.samples.count) 枚", "Saved examples · \(stop.samples.count)"))
                    .font(JPFont.mono(12, medium: true))
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(stop.samples.enumerated()), id: \.offset) { i, sample in
                        Button {
                            viewing = SampleTarget(index: i)
                        } label: {
                            OfflineStoredImage(url: url(sample.file))
                                .frame(height: 76)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sample.title) · \(sample.credit)")
                    }
                }
            }
        }
    }

    /// メモ・周りの地図・座標・地図アプリで開く
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note = stop.note {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("メモ", "Note"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                JPCardDivider()
            }
            // 周りの地図の画像（2026-10-09 判断: 板 72d に足した。保存した場所ごとの地図をここで見せる）
            if let mapURL = url(stop.map) {
                OfflineStoredImage(url: mapURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: OfflineTripMap.stopSize.height)
                    .clipped()
                    .accessibilityElement()
                    .accessibilityLabel(L("\(stop.name)の周りの地図の画像", "Saved map around \(stop.name)"))
                    .accessibilityAddTraits(.isImage)
                JPCardDivider()
            }
            if let coords = stop.coords {
                coordsRow(coords)
                JPCardDivider()
                mapsButton(coords)
            }
        }
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func coordsRow(_ coords: Photo.Coords) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("座標", "Coordinates"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                Text(OfflineTripText.coordinates(coords))
                    .font(JPFont.mono(14))
                    .foregroundStyle(WebTheme.text)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = OfflineTripText.coordinates(coords)
                copied = true
                UIAccessibility.post(notification: .announcement, argument: L("座標を写しました", "Coordinates copied"))
            } label: {
                Label(copied ? L("写しました", "Copied") : L("写す", "Copy"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("座標を写す", "Copy coordinates"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
    }

    /// 地図アプリで開く。**圏外でも押せるまま**（owner 2026-10-09: 地図アプリが端末に地図を持っていれば開ける）。
    /// 圏外のときだけ「電波が無いと開けないことがあります」を添える
    private func mapsButton(_ coords: Photo.Coords) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                // 名前で探し直さない（圏外では探せない）。丸めた座標に名前を付けて渡す
                SpotDirections.rounded(name: stop.name, coords: coords).openInMaps()
            } label: {
                Label(L("地図アプリで開く", "Open in Maps"), systemImage: "map")
                    .font(.footnote)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(connectivity.isOffline ? OfflineTripText.mapsNote : "")
            if connectivity.isOffline {
                Text(OfflineTripText.mapsNote)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - 作例を大きく見る

/// 作例を1枚ずつ大きく。**出典（作者・ライセンス）を必ず一緒に出す**（圏外ではリンクは開けないが文字は出す）
struct OfflineSampleViewer: View {
    let samples: [OfflineTripManifest.Sample]
    let start: Int
    let url: (String?) -> URL?

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        let i = ComposeGuide.normalized(index, count: samples.count)
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if samples.indices.contains(i) {
                let sample = samples[i]
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    OfflineStoredImage(url: url(sample.file), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel(sample.title)
                        .accessibilityAddTraits(.isImage)
                        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                            index = ComposeGuide.swiped(index: i, count: samples.count,
                                                        translationWidth: value.translation.width)
                        })
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                        Text(sample.credit)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted2)
                        if samples.count > 1 {
                            Text("\(i + 1) / \(samples.count)")
                                .font(JPFont.mono(12))
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(Labels.Common.close)
        }
        .onAppear { index = start }
    }
}
