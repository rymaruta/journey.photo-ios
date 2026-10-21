import SwiftUI
import UIKit

/// 家具の図鑑（2026-10-19・板「家具図鑑」CamperFurniture の右上の一覧）。
///
/// 上に置き場所のタブ 3（床・壁・天井）と「持っている / 全部」、本体は分類ごとの行（分類名・「2/4」・真鍮の細い進み具合の棒）、
/// その下に 4 つの枠を横一列。持っている＝家具の絵と珍しさの四角、まだ＝同じ絵の影絵に灰の縁（名前は「？？？」）、
/// 近日（要サーバー・形をまだ作っていない）＝分類の印と「近日」。枠を押すと、その家具を部屋の隅に置いた寄りの立体（昼・夜）
struct CamperRoomDexView: View {
    let owned: Set<String>
    let stats: CamperStats
    let roomStats: CamperRoomStats
    let paint: UInt32
    let initialMood: CamperMood
    /// 新しく届いた家具（真鍮の点・2026-10-21）と、寄りで見たら呼ぶ（見たにする）
    var news: Set<String> = []
    var onSeen: (String) -> Void = { _ in }
    let onClose: () -> Void

    @State private var tab: CamperRoomPlacement = .floor
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var detail: CamperRoomFurniture?

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabs
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(shownCategories, id: \.self) { c in
                        categoryRow(c)
                    }
                    if !needle.isEmpty, shownCategories.isEmpty {
                        Text(L("その名前の家具はありません", "No furniture with that name"))
                            .jpSystemFont(14)
                            .foregroundStyle(WebTheme.text2)
                    }
                    // 図鑑の総数・近日の数はここだけ（見出しの数は「集めた N / M」の1つ・2026-10-21）
                    Text(CamperText.roomDexFootnote(all: CamperRoomCatalog.all.count, soon: CamperRoomCatalog.soonCount))
                        .jpSystemFont(12)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background { Color.black.ignoresSafeArea() }
        .onChange(of: detail?.id) { _, id in
            if let id { onSeen(id) }
        }
        .sheet(item: $detail) { f in
            CamperRoomCloseUpView(furniture: f, have: owned.contains(f.id), stats: stats, roomStats: roomStats, paint: paint,
                                  initialMood: initialMood) { detail = nil }
        }
    }

    private var header: some View {
        let count = CamperRoomCatalog.dexCount(owned)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("家具を集める", "Collect furniture")).jpEyebrow().foregroundStyle(WebTheme.accent)
                Text(L("\(CamperText.carName)の家具", "\(CamperText.carName) furniture")).font(JPFont.screenTitle).foregroundStyle(WebTheme.foreground)
                // 一目で見る数は1つ（2026-10-21・前は「860 / 2183 · 図鑑 2194 · 近日 11」）
                Text(CamperText.collectedLine(have: count.have, total: count.total))
                    .font(JPFont.number(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityIdentifier("camper.room.dex.count")
                // 手に入れ方は影の家具の寄りに出る（2026-10-21・「？？？」だけでは集め方が分からなかった）
                Text(L("影の家具を押すと、手に入れ方が出ます", "Tap a shadow to see how to get it"))
                    .jpSystemFont(12)
                    .foregroundStyle(WebTheme.text2)
            }
            Spacer()
            Button(action: onClose) {
                Text(L("閉じる", "Close"))
                    .jpSystemFont(15, weight: .semibold)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camper.room.dex.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(CamperRoomPlacement.allCases, id: \.self) { p in
                let on = p == tab
                let items = CamperRoomCatalog.items(p).filter(\.isAvailable)
                Button { tab = p } label: {
                    HStack(spacing: 4) {
                        Text(p.name).jpSystemFont(14, weight: .semibold)
                        Text("\(items.filter { owned.contains($0.id) }.count)/\(items.count)")
                            .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                    }
                    .foregroundStyle(on ? WebTheme.accent : WebTheme.muted2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .overlay(alignment: .bottom) { Rectangle().fill(on ? WebTheme.accent : Color.clear).frame(height: 2) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("camper.room.dex.tab.\(p.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) }
    }

    /// 2,000 点を超えると、代表の家具が画面の外に出て押せない。名前か id で絞る
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(WebTheme.text3)
            TextField(L("名前で探す", "Search by name"), text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .foregroundStyle(WebTheme.foreground)
                .accessibilityIdentifier("camper.room.dex.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
                .accessibilityIdentifier("camper.room.dex.search.clear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 4)
        .frame(minHeight: WebTheme.minTapTarget)
    }

    /// 探しているときは床・壁・天井をまたぐ。空のときは今のタブだけ
    private var shownCategories: [CamperRoomCategory] {
        CamperRoomCategory.allCases.filter { c in
            (needle.isEmpty ? c.placement == tab : true) && !shownItems(c).isEmpty
        }
    }

    private func shownItems(_ c: CamperRoomCategory) -> [CamperRoomFurniture] {
        CamperRoomCatalog.items(c).filter { CamperRoomCatalog.matchesDexQuery($0, query) }
    }

    private func categoryRow(_ c: CamperRoomCategory) -> some View {
        let items = shownItems(c)
        let available = items.filter(\.isAvailable)
        let have = available.filter { owned.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(c.name).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
                Text("\(have)/\(available.count)").font(JPFont.number(12, weight: .regular, relativeTo: .caption)).foregroundStyle(WebTheme.faint)
                CamperProgressBar(fraction: available.isEmpty ? 0 : Double(have) / Double(available.count)).frame(maxWidth: 80)
            }
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(items) { f in card(f) }
            }
        }
    }

    private func card(_ f: CamperRoomFurniture) -> some View {
        let have = owned.contains(f.id)
        return Button { detail = f } label: {
            VStack(spacing: 4) {
                if f.built {
                    CamperRoomThumb(furniture: f, silhouette: !have).frame(height: 54)
                } else {
                    Image(systemName: f.category.symbol).jpSystemFont(22).foregroundStyle(WebTheme.faint).frame(height: 54)
                }
                Text(have ? f.name : L("？？？", "???"))
                    .jpSystemFont(12)
                    .foregroundStyle(have ? WebTheme.text : WebTheme.faint)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                if f.isAvailable {
                    CamperRarityDots(rarity: f.rarity)
                } else {
                    Text(L("近日", "Soon")).jpSystemFont(12, weight: .semibold).foregroundStyle(WebTheme.accent)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(have ? WebTheme.hairline : WebTheme.line,
                                                                    style: StrokeStyle(lineWidth: 1, dash: have ? [] : [3, 3])))
            // 新しく届いた家具（未読の点と同じ真鍮 8pt）
            .overlay(alignment: .topTrailing) {
                if have, news.contains(f.id) { Circle().fill(WebTheme.accent).frame(width: 8, height: 8).padding(7) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(f, have: have))
        .accessibilityIdentifier("camper.room.dex.\(f.id)")
    }

    private func label(_ f: CamperRoomFurniture, have: Bool) -> String {
        let fresh = have && news.contains(f.id) ? L("新しい家具、", "New, ") : ""
        let name = fresh + (have ? f.name : L("まだ持っていない\(f.category.name)", "A \(f.category.name) not collected yet"))
        let how = f.isAvailable ? f.unlock.condition : L("近日", "Coming soon")
        return "\(name)、\(f.rarity.name)、\(how)"
    }
}

/// 家具の寄り（部屋の隅に 1 つだけ置いた立体。昼と夜）
struct CamperRoomCloseUpView: View {
    let furniture: CamperRoomFurniture
    let have: Bool
    let stats: CamperStats
    let roomStats: CamperRoomStats
    let paint: UInt32
    let initialMood: CamperMood
    let onClose: () -> Void

    @State private var mood: CamperMood = .day
    @State private var camera = CamperRoomCamera()
    @State private var readyMarker = ""
    @State private var opened = false

    private var studio: (layout: CamperRoomLayout, doc: CamperRoomDocument) { CamperRoomStudio.make(furniture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(furniture.category.name).jpEyebrow().foregroundStyle(WebTheme.accent)
                Spacer()
                Button(action: onClose) {
                    Text(L("閉じる", "Close"))
                        .jpSystemFont(15, weight: .semibold)
                        .foregroundStyle(WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camper.room.closeup.close")
            }
            if furniture.built {
                ZStack(alignment: .bottomTrailing) {
                    CamperRoomSceneView(layout: studio.layout, doc: studio.doc, paint: paint, mood: mood, camera: camera, animateCamera: false,
                                        editing: false, photosMode: false, focusFrame: nil, previewPhotoId: nil, selected: nil, drag: nil,
                                        dragCheck: nil, photoImages: [:], studio: true) { readyMarker = $0 }
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                            camera = CamperRoomStudio.camera(furniture).dragged(dx: Double(v.translation.width), dy: Double(v.translation.height))
                        })
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("\(furniture.name)の寄り", "Close-up of \(furniture.name)"))
                        .accessibilityAddTraits(.isImage)
                        .accessibilityValue(PreviewSession.userId != nil ? readyMarker : "")
                        .accessibilityIdentifier("camper.room.closeup")
                    Button { mood = mood == .night ? .day : .night } label: {
                        Image(systemName: mood == .night ? "sun.max" : "moon")
                            .jpSystemFont(16, weight: .semibold)
                            .foregroundStyle(Color.white)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .jpGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel(mood == .night ? L("昼にする", "Make it day") : L("夜にする", "Make it night"))
                    .accessibilityIdentifier("camper.room.closeup.night")
                }
                .overlay(alignment: .top) {
                    if !have {
                        Text(L("まだ持っていない家具 · 見本", "Not yet collected · preview"))
                            .jpSystemFont(12, weight: .semibold)
                            .foregroundStyle(WebTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.8), in: Capsule())
                            .padding(.top, 8)
                    }
                }
            } else {
                Image(systemName: furniture.category.symbol)
                    .jpSystemFont(56, weight: .light)
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            Text(furniture.name).font(JPFont.screenTitle).foregroundStyle(WebTheme.foreground)
            CamperRarityDots(rarity: furniture.rarity)
            Text(furniture.look).jpSystemFont(15).foregroundStyle(WebTheme.text)
            if furniture.isAvailable {
                Text(have ? (furniture.unlock.isStarter ? L("最初から持っています", "You\u{2019}ve had it from the start")
                             : L("\(furniture.unlock.condition)で届きました", "Arrived for: \(furniture.unlock.condition)"))
                     : L("\(furniture.unlock.condition)で届きます", "Arrives with: \(furniture.unlock.condition)"))
                    .jpSystemFont(13)
                    .foregroundStyle(WebTheme.text2)
                if !have {
                    let p = furniture.unlock.progress(stats, roomStats)
                    HStack(spacing: 8) {
                        CamperProgressBar(fraction: furniture.unlock.fraction(stats, roomStats))
                        Text("\(p.have) / \(p.need)").font(JPFont.number(12, weight: .semibold, relativeTo: .caption)).foregroundStyle(WebTheme.accent)
                    }
                }
            } else {
                Text(L("近日。\(furniture.unlock.condition)で届くようになります", "Coming soon: \(furniture.unlock.condition)"))
                    .jpSystemFont(13)
                    .foregroundStyle(WebTheme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background { Color.black.ignoresSafeArea() }
        .onAppear {
            guard !opened else { return }
            opened = true
            mood = initialMood == .night ? .night : .day
            camera = CamperRoomStudio.camera(furniture)
        }
    }
}
