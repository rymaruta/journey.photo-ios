import SwiftUI

/// キャンプ場が育つ（板 CampGrow: 焚き火 → テント場 → キャンプ場）。
///
/// - 大きい島はいまの段（まだ先の段を選ぶと 60% の濃さ・灰色 60% に「まだ先 · 見本」）
/// - 3 つの札（いまの段は真鍮 16% の地・選んでいる札は真鍮の縁・まだ先は破線の縁）。小さな島は夕方
/// - 名前を変えられる（板に無い・2026-10-18 判断。題の右の鉛筆）
struct CampGrowView: View {
    var ownerName: String?

    @ObservedObject private var store = CampStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked: CampStage?
    @State private var capturing = false
    @State private var renaming = false
    @State private var draftName = ""

    private var now: CampStage { store.stage }
    private var shown: CampStage { picked ?? now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("キャンプ場が育つ", "Your campsite grows"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("\(store.displayName(owner: ownerName))は、いま「\(now.name)」",
                           "\(store.displayName(owner: ownerName)) is now a \u{201C}\(now.name)\u{201D}"))
                        .font(JPFont.display(24, relativeTo: .title2))
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button {
                    draftName = store.snapshot.name ?? ""
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WebTheme.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("名前を変える", "Rename"))
                .accessibilityIdentifier("camp.grow.rename")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            ZStack(alignment: .top) {
                CampIslandView(options: CampSceneOptions(stage: shown, season: .summer, time: .day,
                                                         cutouts: placed),
                               angle: .resting, interactive: false, images: CampStoreImages.loader(store))
                    .opacity(locked(shown) ? 0.6 : 1)
                    .grayscale(locked(shown) ? 0.6 : 0)
                if locked(shown) {
                    Text(L("まだ先 · 見本", "Later · preview"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background { Capsule().fill(CampStyle.cardSelected) }
                        .padding(.top, 14)
                }
            }
            .frame(height: 330)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .accessibilityIdentifier("camp.grow.island")
            HStack(spacing: 8) {
                ForEach(CampStage.allCases, id: \.self) { stage in card(stage) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("焚き火・テント場・キャンプ場", "Campfire, tent site, campsite"))
            Text(L("続けて撮るほど島が広がり、テント・椅子・机・池・ランタンの柱が増えます",
                   "The more you shoot, the bigger the island grows, with a tent, chairs, a table, a pond and a lantern post"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            Spacer(minLength: 12)
            Button { capturing = true } label: {
                Text(L("撮って加える", "Shoot and add"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background { Capsule().fill(WebTheme.accentFill) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 38)
            .accessibilityIdentifier("camp.grow.capture")
        }
        .background { WebTheme.background.ignoresSafeArea() }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                }
                .accessibilityLabel(L("戻る", "Back"))
                .accessibilityIdentifier("camp.grow.back")
            }
        }
        .fullScreenCover(isPresented: $capturing) {
            CampCaptureView(ownerName: ownerName) { _ in capturing = false }
        }
        .sheet(isPresented: $renaming) { renameSheet }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.grow")
    }

    private var placed: [CampPlacedCutout] {
        store.placed.compactMap { c in c.spot.map { CampPlacedCutout(id: c.id, layers: c.layers, spot: $0) } }
    }

    private func locked(_ stage: CampStage) -> Bool { stage.threshold > now.threshold }

    private func card(_ stage: CampStage) -> some View {
        let on = stage == shown, isNow = stage == now, lock = locked(stage)
        let sub: String
        if isNow {
            sub = L("いま", "Now")
        } else if lock {
            let left = max(1, stage.threshold - store.placedCount)
            sub = L("あと \(left) 枚", "\(left) more")
        } else {
            sub = L("通ってきた", "Passed")
        }
        return Button { picked = stage } label: {
            VStack(spacing: 2) {
                CampIslandView(options: CampSceneOptions(stage: stage, season: .summer, time: .evening), angle: .resting,
                               zoom: stage == .fire ? 1.1 : 1, interactive: false, cornerRadius: 8)
                    .frame(width: 104, height: 84)
                    .opacity(lock ? 0.55 : 1)
                    .grayscale(lock ? 0.8 : 0)
                Text(stage.name)
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(isNow ? CampStyle.highlight : (lock ? WebTheme.text2 : WebTheme.text))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(JPFont.number(12, weight: .regular))
                    .foregroundStyle(isNow ? WebTheme.accent : CampPalette.color(0x999999))
            }
            .padding(.top, 6).padding(.leading, 4).padding(.bottom, 10).padding(.trailing, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { RoundedRectangle(cornerRadius: 12).fill(isNow ? CampStyle.cardSelected : CampStyle.card) }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                on ? WebTheme.accent : Color.white.opacity(lock ? 0.22 : 0.08),
                style: StrokeStyle(lineWidth: 1, dash: lock && !on ? [4, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(sub)
        .accessibilityIdentifier("camp.grow.stage.\(stage.rawValue)")
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("キャンプ場の名前", "Campsite name"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.text)
            TextField(L("とおまわり野営地", "Detour Camp"), text: $draftName)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background { RoundedRectangle(cornerRadius: 12).fill(WebTheme.surface) }
                .accessibilityIdentifier("camp.grow.name")
            Text(L("20 字まで。空にすると「とおまわり野営地」", "Up to 20 characters. Leave empty for \u{201C}Detour Camp\u{201D}"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            HStack(spacing: 8) {
                Button { renaming = false } label: { Text(Labels.Common.cancel).jpPillButton(.outline) }
                Button {
                    store.rename(draftName)
                    renaming = false
                } label: { Text(Labels.Common.save).jpPillButton(.accent) }
                    .accessibilityIdentifier("camp.grow.saveName")
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(WebTheme.sheet)
    }
}

/// まだ立てていない切り絵を立てる（板 3 置く。置く場所の名前は CampCapture の 3 つにそろえる）
struct CampPlaceView: View {
    let cutout: CampCutoutRecord
    let onFinish: (String?) -> Void

    @ObservedObject private var store = CampStore.shared
    @State private var spot = 0
    @State private var angle = CampAngle.resting

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Button { onFinish(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Labels.Common.close)
                .accessibilityIdentifier("camp.place.close")
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("置く場所を選ぶ", "Choose where"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("\(cutout.title)の箱庭をどこに立てる？", "Where should the \(cutout.title) diorama stand?"))
                        .font(JPFont.display(24, relativeTo: .title2))
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            CampIslandView(options: options, angle: angle, images: CampStoreImages.loader(store), onAngle: { angle = $0 })
                .frame(height: 360)
                .padding(.horizontal, 10)
                .padding(.top, 12)
            Text(L("切り絵の箱庭が少し浮いて、点線の輪が立てる場所です。指で島を回して確かめられます",
                   "The diorama floats a little and the dotted ring shows where it will stand. Turn the island to check"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            CampSpotPicker(spot: $spot)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { onFinish(nil) } label: { Text(L("あとで置く", "Place later")).jpPillButton(.outline) }
                    .frame(maxWidth: .infinity)
                Button {
                    store.place(cutout.id, spot: spot)
                    onFinish(cutout.id)
                } label: {
                    Text(L("ここに立てる", "Stand it here"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background { Capsule().fill(WebTheme.accent) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .accessibilityIdentifier("camp.place.done")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 38)
        }
        .padding(.top, 50)
        .background { WebTheme.background.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.place")
    }

    private var options: CampSceneOptions {
        let placed = store.placed.compactMap { c in c.spot.map { CampPlacedCutout(id: c.id, layers: c.layers, spot: $0) } }
        return CampSceneOptions(stage: CampStage.stage(cutouts: store.placedCount + 1), season: CampClock.season(of: Date()),
                                time: CampTime(slot: CampClock.slot(of: Date())), cutouts: placed,
                                placing: CampPlacedCutout(id: cutout.id, layers: cutout.layers, spot: spot))
    }
}
