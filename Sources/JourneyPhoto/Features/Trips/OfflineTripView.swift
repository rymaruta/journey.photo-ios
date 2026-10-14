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

/// 圏外の帯（v2 の板 OfflineTrip: surface-1 の札・白 8% の縁・角 14。電波の無い印は真鍮、
/// 見出しは 14 の太字、添え書きは 12 の text-3）。v1 の真鍮の薄い地はやめた（合図は印だけで足りる）
struct OfflineBanner: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WebTheme.accent)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, JPSpace.s)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
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
            // **読むのと絵に戻すのは主スレッドの外で**（2026-10-09 判断）。作例は1枚 数百KB の JPEG で、
            // 1か所に3枚と地図が並ぶ。`.task` は主スレッドで走るので、そのままだと開いた・送ったときに画面が引っかかる
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// 番号の丸。**v2（板 OfflineTrip）: 真鍮の線と真鍮の数字**（旅行プランの日程と同じ `TripStopNumber`）。
/// 地図の画像の点と同じ番号
struct OfflineStopNumber: View {
    let number: Int
    var body: some View {
        TripStopNumber(number: number)
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
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xxs)
                .padding(.bottom, JPSpace.screenEnd)
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

            // 題（v2 の板 OfflineTrip: 明朝 26 → 13 の text-2 の等幅の1行）
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(manifest.title.isEmpty ? L("無題のプラン", "Untitled trip") : manifest.title)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text2)
            }
            .padding(.top, JPSpace.xxs)

            if let url = offline.fileURL(planId: manifest.planId, file: manifest.overviewMap) {
                VStack(alignment: .leading, spacing: 6) {
                    OfflineStoredImage(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: OfflineTripMap.overviewSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                        .accessibilityElement()
                        .accessibilityLabel(L("保存した地図の画像。場所 1 から \(manifest.stopCount) の位置",
                                              "Saved map image showing places 1 to \(manifest.stopCount)"))
                        .accessibilityAddTraits(.isImage)
                    Text(L("保存した地図の画像です。拡大や道案内はできません",
                           "This is a saved map image. You can't zoom or get directions."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }

            ForEach(manifest.days, id: \.number) { day in
                // v2 の板 OfflineTrip: 真鍮の眉「1日目 · 12月24日」と消える線 → 区切り線の行（札で囲まない）
                VStack(alignment: .leading, spacing: 0) {
                    JPEyebrowLine(Self.dayHeading(day))
                        .padding(.bottom, JPSpace.xxs)
                    ForEach(day.stops) { stop in
                        NavigationLink {
                            OfflineSpotView(manifest: manifest, stop: stop, day: day, preview: preview)
                        } label: {
                            row(stop)
                        }
                        .buttonStyle(JPRowButtonStyle())
                    }
                }
                .padding(.top, JPSpace.xxs)
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

    /// 日の眉（「1 日目 · 12月24日」）
    nonisolated static func dayHeading(_ day: OfflineTripManifest.Day) -> String {
        var head = L("\(day.number) 日目", "Day \(day.number)")
        if let label = TakenDay.label(day.date) { head += " · \(label)" }
        return head
    }

    /// 行（v2 の板 OfflineTrip の `.st`: 64・番号の丸 → 明朝の名前（撮影スポット）→ 太陽の印と光の時刻・下に区切り線）
    private func row(_ stop: OfflineTripManifest.Stop) -> some View {
        HStack(spacing: JPSpace.s) {
            OfflineStopNumber(number: stop.number)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(stop.key.hasPrefix("spot:") ? JPFont.rowTitle : JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if let line = stop.light?.line {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.horizon")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(JPFont.mono(13, relativeTo: .footnote))
                    }
                    .foregroundStyle(WebTheme.text2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: JPHeight.tallRow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
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
                VStack(alignment: .leading, spacing: JPSpace.m) {
                    // 写真の下端の上に重ねる題（写真の上なので白・灰は透過の `muted2`）
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name)
                            .font(JPFont.screenTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                            .accessibilityAddTraits(.isHeader)
                        if let address = stop.address {
                            Text(address)
                                .font(JPFont.footnote)
                                .foregroundStyle(WebTheme.muted2)
                        }
                    }

                    // 圏外の1行（v2 の板 OfflineSpot: 札にせず、真鍮の印と 12 の text-3 の1行）
                    if connectivity.isOffline || preview {
                        HStack(spacing: JPSpace.xs) {
                            Image(systemName: "wifi.slash")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(WebTheme.accent)
                                .accessibilityHidden(true)
                            Text(preview && !connectivity.isOffline
                                 ? OfflineTripText.previewBanner : OfflineTripText.offlineBanner)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    lightSection
                    samplesSection
                    placeSection
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, -58)
                .padding(.bottom, JPSpace.screenEnd)
            }
        }
        .webScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { target in
            OfflineSampleViewer(samples: stop.samples, start: target.index, url: url)
        }
    }

    /// 頭の写真（1枚目の作例）。下を黒へ溶かす（v2 の板 OfflineSpot: 250pt・溶け 140pt）
    private var hero: some View {
        ZStack(alignment: .bottom) {
            OfflineStoredImage(url: url(stop.samples.first?.file))
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(L("\(stop.name)の作例（端末に保存したもの）", "Example of \(stop.name) (saved on this iPhone)"))
        .accessibilityAddTraits(.isImage)
    }

    /// 光の時刻（v2 の板 OfflineSpot: 眉と消える線 → 4行の表。名前は 14、時刻は 17 の細い等幅の数字・行の下に区切り線）
    @ViewBuilder
    private var lightSection: some View {
        if let light = stop.light, !light.entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                JPEyebrowLine(lightHeading)
                    .padding(.bottom, JPSpace.xxs)
                ForEach(light.entries, id: \.label) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.label)
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text)
                        Spacer(minLength: JPSpace.xs)
                        Text(entry.value)
                            .font(JPFont.number(17, weight: .light, relativeTo: .body))
                            .foregroundStyle(WebTheme.text)
                    }
                    .frame(minHeight: TripStyle.lightRowMinHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
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
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                JPEyebrowLine(L("保存した作例 · \(stop.samples.count) 枚", "Saved examples · \(stop.samples.count)"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(stop.samples.enumerated()), id: \.offset) { i, sample in
                        Button {
                            viewing = SampleTarget(index: i)
                        } label: {
                            OfflineStoredImage(url: url(sample.file))
                                .frame(height: 76)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
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
    @ViewBuilder
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note = stop.note {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("メモ", "Note"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                    Text(note)
                        .font(JPFont.body)
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
            }
        }
        // v2 の板 OfflineSpot: メモと位置の札（surface-1・角 14）。「地図アプリで開く」は札の下に出す
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
        if let coords = stop.coords {
            mapsButton(coords)
        }
    }

    private func coordsRow(_ coords: Photo.Coords) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("座標", "Coordinates"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Text(OfflineTripText.coordinates(coords))
                    .font(JPFont.mono(15, relativeTo: .subheadline))
                    .foregroundStyle(WebTheme.text)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = OfflineTripText.coordinates(coords)
                copied = true
                UIAccessibility.post(notification: .announcement, argument: L("座標を写しました", "Coordinates copied"))
            } label: {
                // 板 OfflineSpot: 32 の線の小ボタン（当たりは 44）
                Label(copied ? L("写しました", "Copied") : L("写す", "Copy"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, JPSpace.s)
                    .frame(minHeight: 32)
                    .overlay(Capsule().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("座標を写す", "Copy coordinates"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minHeight: JPHeight.row)
    }

    /// 地図アプリで開く。**圏外でも押せるまま**（owner 2026-10-09: 地図アプリが端末に地図を持っていれば開ける）。
    /// 圏外のときだけ「電波が無いと開けないことがあります」を添える
    private func mapsButton(_ coords: Photo.Coords) -> some View {
        VStack(spacing: 6) {
            Button {
                // 名前で探し直さない（圏外では探せない）。丸めた座標に名前を付けて渡す
                SpotDirections.rounded(name: stop.name, coords: coords).openInMaps()
            } label: {
                // 写真のある画面の主ボタン＝白（v2 の板 OfflineSpot・`JPPillStyle.main(onPhoto: true)`）
                Label(L("地図アプリで開く", "Open in Maps"), systemImage: "map")
                    .jpPillButton(.main(onPhoto: true))
            }
            .buttonStyle(.plain)
            .accessibilityHint(connectivity.isOffline ? OfflineTripText.mapsNote : "")
            if connectivity.isOffline {
                Text(OfflineTripText.mapsNote)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, JPSpace.xxs)
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
                            .font(JPFont.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                        Text(sample.credit)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text2)
                        if samples.count > 1 {
                            Text("\(i + 1) / \(samples.count)")
                                .font(JPFont.meta)
                                .foregroundStyle(WebTheme.text3)
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
