import SwiftUI

/// 部品図鑑（板 CampDex「数が増えても見やすい一覧」・24 分類 96 個）。
///
/// - 見出し: 眉ラベル「部品を集める」・明朝「キャンプ場の部品」・持っている数「29 / 79」・探す
/// - 置き場所のタブ 8（選んでいるタブは真鍮の字と 2pt の下線・数は「持っている / 集められる」）
/// - 絞り込み: すべて／持っている／まだ／珍しさ ▾／新着（新しく集めた数の真鍮の件数バッジ）
/// - 分類ごとに 4 枠の行と「2/4」の進み具合（真鍮の細い棒）。まだの部品は白 10% の影絵と「？？？」
/// - **要サーバーの 17 個は「近日」と出して数から外す**（分母は 79。サーバーの口ができたら `CampUnlock.server` を
///   ほかの条件に替えるだけで数に入る）
struct CampDexView: View {

    @ObservedObject private var store = CampStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var place: CampPlace = .shelter
    @State private var filter: CampDexFilter = .all
    @State private var searching = false
    @State private var query = ""
    @State private var detail: CampPart?
    /// 開いたときの「新着」（見たことにしても、この画面の中では印を残す）
    @State private var unseenAtOpen: Set<String> = []

    var body: some View {
        let owned = store.owned
        VStack(spacing: 0) {
            header(owned)
            if searching { searchField }
            tabs(owned)
            filters
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let cats = visibleCategories(owned)
                    if cats.isEmpty {
                        Text(L("当てはまる部品はありません", "No parts match"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }
                    ForEach(cats, id: \.category.key) { item in
                        categoryRow(item.category, parts: item.parts, owned: owned)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background { RadialGradient(colors: [CampPalette.color(0x1D1B14), Color.black], center: UnitPoint(x: 0.5, y: 0.2),
                           startRadius: 0, endRadius: 520)
                .ignoresSafeArea() }
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
                .accessibilityIdentifier("camp.dex.back")
            }
        }
        .sheet(item: $detail) { part in
            CampPartDetail(part: part, owned: owned, shots: store.shots)
        }
        .onAppear { unseenAtOpen = store.unseen }
        .onDisappear { store.markSeen() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.dex")
    }

    // MARK: - 見出し

    private func header(_ owned: Set<String>) -> some View {
        let tally = CampCollection.tally(owned: owned)
        return HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("部品を集める", "Collect parts"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(CampDexText.title)
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(WebTheme.text)
            }
            .padding(.top, 8)
            .padding(.leading, 16)
            Spacer()
            HStack(spacing: 0) {
                Text("\(tally.owned)").foregroundStyle(WebTheme.text)
                Text(" / \(tally.total)").foregroundStyle(CampPalette.color(0x999999))
            }
                .font(JPFont.number(15, weight: .semibold, relativeTo: .subheadline))
                .accessibilityElement(children: .ignore)
                .padding(.top, 16)
                .accessibilityLabel(CampDexText.tally(tally.owned, tally.total))
                .accessibilityIdentifier("camp.dex.tally")
            Button { withAnimation { searching.toggle(); if !searching { query = "" } } } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WebTheme.text)
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 4)
            .padding(.trailing, 8)
            .accessibilityLabel(L("探す", "Search"))
            .accessibilityIdentifier("camp.dex.search")
        }
    }

    private var searchField: some View {
        TextField(L("名前で探す", "Search by name"), text: $query)
            .font(JPFont.body)
            .foregroundStyle(WebTheme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background { RoundedRectangle(cornerRadius: 12).fill(WebTheme.sheet) }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .accessibilityIdentifier("camp.dex.query")
    }

    // MARK: - タブと絞り込み

    private func tabs(_ owned: Set<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(CampPlace.allCases, id: \.self) { p in
                    let parts = CampCatalog.categories(in: p).flatMap(\.parts).filter { !$0.needsServer }
                    let has = parts.filter { owned.contains($0.id) }.count
                    let on = p == place
                    Button { place = p } label: {
                        HStack(spacing: 4) {
                            Text(p.name).font(.system(size: 14, weight: .semibold))
                            Text("\(has)/\(parts.count)").font(JPFont.number(12, weight: .medium))
                        }
                        .foregroundStyle(on ? WebTheme.accent : CampPalette.color(0xA3A3A3))
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? WebTheme.accent : Color.clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isHeader] : [])
                    .accessibilityIdentifier("camp.dex.tab.\(p.rawValue)")
                }
            }
            .padding(.horizontal, 12)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(WebTheme.line).frame(height: 1) }
        .padding(.top, 8)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(L("すべて", "All"), on: filter == .all) { filter = .all }
                chip(L("持っている", "Owned"), on: filter == .owned) { filter = .owned }
                chip(L("まだ", "Not yet"), on: filter == .missing) { filter = .missing }
                Menu {
                    ForEach(CampRarity.allCases, id: \.self) { r in
                        Button(r.name) { filter = .rarity(r) }
                    }
                } label: {
                    chipFace(rarityLabel + " ▾", on: isRarity)
                }
                .accessibilityIdentifier("camp.dex.filter.rarity")
                Button { filter = .new } label: {
                    HStack(spacing: 6) {
                        Text(L("新着", "New"))
                        if !unseenAtOpen.isEmpty {
                            Text("\(unseenAtOpen.count)")
                                .font(JPFont.number(11, weight: .bold))
                                .foregroundStyle(WebTheme.accentText)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 18, minHeight: 18)
                                .background { Capsule().fill(WebTheme.accent) }
                                .overlay(Capsule().strokeBorder(Color.black, lineWidth: 2))
                        }
                    }
                    .modifier(CampChipFace(on: filter == .new))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == .new ? .isSelected : [])
                .accessibilityIdentifier("camp.dex.filter.new")
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("絞り込み", "Filter"))
    }

    private var isRarity: Bool {
        if case .rarity = filter { return true }
        return false
    }

    private var rarityLabel: String {
        if case .rarity(let r) = filter { return r.name }
        return L("珍しさ", "Rarity")
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipFace(text, on: on) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chipFace(_ text: String, on: Bool) -> some View {
        Text(text).modifier(CampChipFace(on: on))
    }

    // MARK: - 一覧

    private struct Row {
        let category: CampCategory
        let parts: [CampPart]
    }

    private func visibleCategories(_ owned: Set<String>) -> [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let cats = q.isEmpty ? CampCatalog.categories(in: place) : CampCatalog.categories
        return cats.compactMap { c in
            let parts = c.parts.filter { p in
                filter.includes(p, owned: owned, unseen: unseenAtOpen)
                    && (q.isEmpty || p.name.lowercased().contains(q) || p.boardId.contains(q) || c.name.lowercased().contains(q))
            }
            return parts.isEmpty ? nil : Row(category: c, parts: filter == .all ? c.parts : parts)
        }
    }

    private func categoryRow(_ c: CampCategory, parts: [CampPart], owned: Set<String>) -> some View {
        let collectible = c.parts.filter { !$0.needsServer }
        let has = collectible.filter { owned.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(WebTheme.text)
                Text("\(has)/\(collectible.count)")
                    .font(JPFont.number(13, weight: .regular))
                    .foregroundStyle(CampPalette.color(0xA3A3A3))
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(WebTheme.accent)
                        .frame(width: collectible.isEmpty ? 0 : 64 * CGFloat(has) / CGFloat(collectible.count))
                }
                .frame(width: 64, height: 3)
                .accessibilityHidden(true)
            }
            .frame(minHeight: 28)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(parts) { part in
                    tile(part, owned: owned)
                }
            }
        }
        .padding(.top, 10).padding(.leading, 16).padding(.bottom, 6).padding(.trailing, 16)
    }

    private func tile(_ part: CampPart, owned: Set<String>) -> some View {
        let state = CampPartState.of(part, owned: owned)
        let has = state == .owned
        return Button { detail = part } label: {
            VStack(spacing: 0) {
                CampPartArtView(id: part.id, silhouette: !has)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                CampRarityMarks(rarity: part.rarity, size: 5)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 98, maxHeight: 98)
            .background { RoundedRectangle(cornerRadius: 10).fill(has ? CampStyle.tile : CampPalette.color(0x0A0A0A)) }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(has ? 0.14 : 0.07), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if has && unseenAtOpen.contains(part.id) {
                    Circle().fill(WebTheme.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                        .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                if state == .comingSoon {
                    Text(L("近日", "Soon"))
                        .font(JPFont.eyebrow)
                        .foregroundStyle(WebTheme.text3)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(has ? part.name : (state == .comingSoon ? L("近日", "Coming soon") : "？？？"))
        .accessibilityValue(part.rarity.name)
        .accessibilityIdentifier(has ? "camp.dex.part.owned" : (state == .comingSoon ? "camp.dex.part.soon" : "camp.dex.part.missing"))
    }
}

/// 絞り込みの丸い札（板: 高さ 32・左右 12・選んでいるものは白塗りに黒の字・ほかは白 22% の縁）。当たりは 44
struct CampChipFace: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Color.black : CampPalette.color(0xE5E5E5))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background { Capsule().fill(on ? Color.white : Color.clear) }
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.white.opacity(0.22), lineWidth: 1))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

/// 珍しさの印（真鍮の四角 4 つのうち、珍しさの数だけ塗る・黒地の上だけ）
struct CampRarityMarks: View {
    let rarity: CampRarity
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size < 6 ? 2 : 3) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= rarity.marks ? WebTheme.accent : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(WebTheme.accent.opacity(i <= rarity.marks ? 1 : 0.4), lineWidth: 1))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 部品 1 つの札（板 CampDex の部品の札: 絵・名前・id・珍しさ・形・集める条件・端末だけ／要サーバー）
struct CampPartDetail: View {
    let part: CampPart
    let owned: Set<String>
    let shots: [CampShot]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = CampPartState.of(part, owned: owned)
        let progress = CampCollection.progress(part.unlock, shots: shots)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RadialGradient(colors: [CampPalette.color(0x232220), CampPalette.color(0x0D0D0E)], center: UnitPoint(x: 0.5, y: 0.4),
                               startRadius: 0, endRadius: 260)
                CampPartArtView(id: part.id, silhouette: state != .owned)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            VStack(alignment: .leading, spacing: 8) {
                Text(state == .owned ? part.name : "？？？")
                    .font(JPFont.display(22, relativeTo: .title2))
                    .foregroundStyle(WebTheme.text)
                Text(part.id)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CampPalette.color(0xA3A3A3))
                HStack(spacing: 5) {
                    CampRarityMarks(rarity: part.rarity)
                    Text(part.rarity.name).font(JPFont.caption).foregroundStyle(WebTheme.accent)
                }
                Text(part.shape)
                    .font(JPFont.body)
                    .foregroundStyle(CampPalette.color(0xCFCFCF))
                JPCardDivider().padding(.vertical, 4)
                Text(L("集める", "How to collect"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(part.condition)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                switch state {
                case .owned:
                    Text(L("持っています", "You have it"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                case .missing:
                    if progress.target > 1 {
                        Text(L("いま \(progress.current) / \(progress.target)", "Now \(progress.current) / \(progress.target)"))
                            .font(JPFont.number(13, weight: .regular, relativeTo: .footnote))
                            .foregroundStyle(WebTheme.text2)
                            .accessibilityIdentifier("camp.dex.detail.progress")
                    }
                    Text(L("端末だけで集められます", "Collected on this device"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                case .comingSoon:
                    if case .server(let need) = part.unlock {
                        Text(L("近日 · 要サーバー（\(need.name)）", "Coming soon · needs our server (\(need.name))"))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
            }
            .padding(20)
            Spacer(minLength: 0)
            Button { dismiss() } label: { Text(Labels.Common.close).jpPillButton(.outline) }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .accessibilityIdentifier("camp.dex.detail.close")
        }
        .background { WebTheme.sheet.ignoresSafeArea() }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.dex.detail")
    }
}

enum CampDexText {
    static var title: String { L("キャンプ場の部品", "Campsite parts") }
    static func newCount(_ n: Int) -> String { L("新しく集めた部品が \(n) 個", "\(n) new parts") }
    static func tally(_ owned: Int, _ total: Int) -> String {
        L("\(total) 個のうち \(owned) 個を持っています（近日の 17 個は数えない）",
          "You have \(owned) of \(total) (the 17 coming-soon parts aren\u{2019}t counted)")
    }
}
