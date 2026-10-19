import SwiftUI

/// 友達の車を訪ねる（板 CamperVisit・2026-10-19 第2段）。人のプロフィールの「とおまわり号を訪ねる」から開く。
///
/// - 開くと `GET /users/{uid}/camper`。サーバーが友達×日で1回だけ訪ねた記録を足す。数えられた回は眉ラベルの下に
///   控えめな一行（`CamperText.visitCounted`）。訪ねて**自分に**届いた部品（はしご・同じ日の旅）は自分の控え
///   （`CamperStore.receive`）に入れ、自分の車の画面を開いたときの「届いた」で見せる（この画面では大きく出さない）
/// - 「部品を贈る」（`POST …/gift`・何を贈るかはサーバーが決める）と「焚き火に薪をくべる」（`POST …/firewood`）。
///   断りは日本語／英語の一言（`CamperText.refusal`）
/// - 車の絵: 2026-10-19 判断——飾りのサーバー保存は別の札なので、相手が集めた要サーバーの部品を付けた姿
///   （`CamperLoadout.visiting`）。段はキャンピングカー、時刻は板どおり夜
/// - 板のランタンを掛ける操作は、この回はやらない（口が無い）
struct CamperVisitView: View {
    let userId: String
    let ownerName: String?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = CamperVisitModel()
    @State private var angle = CamperFraming.overview(.camper)
    @State private var animateAngle = false
    @State private var dragStart: CamperAngle?
    @State private var readyMarker = ""

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content(width: geo.size.width)
                }
                .padding(.bottom, 32)
            }
        }
        .background { backdrop }
        .navigationTitle(CamperText.carName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(userId)|\(auth.userId ?? "")") { await load() }
    }

    private var service: CamperVisitModel.Calls {
        let camper = environment.camper
        let preview = PreviewSession.camperSample
        return CamperVisitModel.Calls(
            visit: { id in preview ? CamperServerSample.visit(userId: id) : try await camper.visit(id) },
            gift: { id in preview ? CamperGiftResult(given: true, part: "mirror.brass_oval") : try await camper.gift(id) },
            firewood: { id in preview ? CamperFirewoodResult(added: true, count: 5) : try await camper.firewood(id) })
    }

    private func load() async {
        await model.load(userId: userId, signedIn: auth.userId != nil, calls: service,
                         store: CamperStore(userId: auth.userId))
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CamperText.visitEyebrow(owner: ownerName))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .lineLimit(1)
            Text(CamperText.carName)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
            Text(CamperText.visitCaption(owner: ownerName))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted2)
            if let notice = model.visitNotice {
                // 訪ねた記録は控えめに（色は淡い字・形は小さな印。合図の真鍮は使わない）
                Label(notice, systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.text2)
                    .padding(.top, 4)
                    .accessibilityIdentifier("camper.visit.counted")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 本体

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch model.phase {
        case .idle, .loading:
            VStack(spacing: JPSpace.s) {
                ProgressView()
                Text(L("友達の車を読み込んでいます…", "Loading your friend\u{2019}s camper…"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("camper.visit.loading")
        case .failed(let message):
            ErrorBanner(message: message) { Task { await model.reload(userId: userId, signedIn: auth.userId != nil, calls: service,
                                                                      store: CamperStore(userId: auth.userId)) } }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("camper.visit.failed")
        case .loaded(let state):
            VStack(alignment: .leading, spacing: 16) {
                scene(state, width: width)
                tiles(state)
                actions
            }
        }
    }

    private func scene(_ state: CamperVisitState, width: CGFloat) -> some View {
        let config = CamperConfig(stage: .camper, mood: .night, loadout: CamperLoadout.visiting(state.parts))
        return CamperSceneView(config: config, angle: angle, animateAngle: animateAngle, doorOpen: false, reduceMotion: reduceMotion) {
            readyMarker = $0
        }
        .frame(width: width, height: min(350, max(220, width * 0.9)))
        .contentShape(Rectangle())
        .gesture(rotate)
        .onTapGesture(count: 2) {
            animateAngle = true
            angle = CamperFraming.overview(.camper)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CamperText.accessibilityLabel(stage: .camper, mood: .night, loadout: config.loadout, doorOpen: false, preview: nil))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(PreviewSession.userId != nil ? readyMarker : "")
        .accessibilityIdentifier("camper.visit.scene")
    }

    private var rotate: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? angle
                if dragStart == nil { dragStart = angle }
                animateAngle = false
                angle = CamperFraming.dragged(start, dx: Double(value.translation.width), dy: Double(value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func tiles(_ state: CamperVisitState) -> some View {
        HStack(spacing: 10) {
            tile(L("集めた部品（要サーバー）", "Server parts"), CamperText.visitParts(state.parts.count))
            tile(L("焚き火の薪", "Firewood"), model.woodCount.map { L("あなたは \($0) 回", "You: \($0)") } ?? L("まだ", "Not yet"))
        }
        .padding(.horizontal, 16)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(WebTheme.faint).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(WebTheme.foreground).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: 贈る・薪

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(message.isError ? WebTheme.text : CamperStyle.brassLight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("camper.visit.message")
            }
            HStack(spacing: 8) {
                // 写真の無い画面の主ボタン: 真鍮の塗りに墨の字（CLAUDE.md の owner の好み）
                Button { Task { await model.gift(calls: service, ownerName: ownerName) } } label: {
                    Label(model.gifted ? L("贈りました", "Given") : CamperText.giveLabel, systemImage: "gift")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(WebTheme.accentFill, in: Capsule())
                        .opacity(model.gifted || model.busy ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(model.gifted || model.busy)
                .accessibilityIdentifier("camper.visit.gift")
                Button { Task { await model.firewood(calls: service, store: CamperStore(userId: auth.userId)) } } label: {
                    // 線のボタン（板 Components の `.bo`・`jpOutlineButton` を通す）
                    Label(CamperText.firewoodLabel, systemImage: "flame")
                        .minimumScaleFactor(0.8)
                        .jpOutlineButton(.regular, fullWidth: true)
                        .frame(minHeight: 50)
                        .opacity(model.busy ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityIdentifier("camper.visit.firewood")
            }
            Text(L("贈れるのは一人に一度・1日1回。薪は同じ友達に1日1回くべられます。",
                   "One gift per friend, one a day. You can add wood to the same friend\u{2019}s fire once a day."))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.faint)
        }
        .padding(.horizontal, 16)
    }

    private var backdrop: some View {
        RadialGradient(colors: [CamperStyle.color(0x111C30), Color.black], center: UnitPoint(x: 0.5, y: 0.36),
                       startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
    }
}

/// 友達の車の読み込みと、贈る・薪の操作（`SwiftUI` を読まない部分・テストで見る）
@MainActor
final class CamperVisitModel: ObservableObject {

    /// 口（テスト・見本で差し替える）
    struct Calls {
        let visit: (String) async throws -> CamperVisitState
        let gift: (String) async throws -> CamperGiftResult
        let firewood: (String) async throws -> CamperFirewoodResult
    }

    enum Phase: Equatable {
        case idle, loading
        case loaded(CamperVisitState)
        case failed(String)
    }

    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var phase: Phase = .idle
    /// 訪ねた記録が数えられた回の一行（数えられなかった回は nil）
    @Published private(set) var visitNotice: String?
    @Published private(set) var message: Message?
    /// 贈った・もう贈ってあった（ボタンを止める）
    @Published private(set) var gifted = false
    @Published private(set) var busy = false
    /// くべた数（くべた回だけ分かる）
    @Published private(set) var woodCount: Int?

    private var userId: String?
    /// 見ている人（入り直したら読み直す）
    private var viewer: String?
    private var seq = 0

    /// 読めた相手を、同じ人が見ている間は読み直さない（画面に戻るたびに訪ねた記録の口を叩かない）
    func load(userId: String, signedIn: Bool, calls: Calls, store: CamperStore) async {
        if self.userId == userId, viewer == store.userId, case .loaded = phase { return }
        await reload(userId: userId, signedIn: signedIn, calls: calls, store: store)
    }

    func reload(userId: String, signedIn: Bool, calls: Calls, store: CamperStore) async {
        if self.userId != userId || viewer != store.userId {
            self.userId = userId
            viewer = store.userId
            visitNotice = nil
            message = nil
            gifted = false
            woodCount = nil
        }
        seq += 1
        let mine = seq
        guard signedIn else {
            phase = .failed(Labels.Common.signInRequired)
            return
        }
        phase = .loading
        do {
            let state = try await calls.visit(userId)
            guard mine == seq, self.userId == userId else { return }
            phase = .loaded(state)
            if !state.launched {
                visitNotice = nil
                message = Message(text: CamperText.refusal(code: "notLaunched", status: 409, fallback: ""), isError: true)
                return
            }
            // 訪ねて自分に届いた部品は、自分の車の画面の「届いた」で見せる
            store.receive(state.visit.added)
            visitNotice = state.visit.counted || !state.visit.added.isEmpty ? CamperText.visitCounted(added: state.visit.added.count) : nil
        } catch {
            guard mine == seq, self.userId == userId else { return }
            phase = .failed(CamperText.failure(error))
        }
    }

    func gift(calls: Calls, ownerName: String?) async {
        guard let userId, !busy, !gifted else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await calls.gift(userId)
            gifted = result.given
            message = Message(text: CamperText.gifted(part: result.part.flatMap(CamperCatalog.part), to: ownerName), isError: false)
        } catch {
            if let refused = error as? CamperService.Refused, refused.code == "already" { gifted = true }
            message = Message(text: CamperText.failure(error), isError: true)
        }
    }

    func firewood(calls: Calls, store: CamperStore) async {
        guard let userId, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await calls.firewood(userId)
            woodCount = result.count
            var text = CamperText.firewood(added: result.added, count: result.count)
            if let id = result.part, let part = CamperCatalog.part(id) {
                // 10 回で自分に届いた部品（三脚とやかん）。自分の車の画面の「届いた」で見せる
                store.receive([id])
                text += L("。あなたの車に「\(part.name)」が届きました", ". \(part.name) arrived for your camper")
            }
            message = Message(text: text, isError: false)
        } catch {
            message = Message(text: CamperText.failure(error), isError: true)
        }
    }
}

extension CamperLoadout {
    /// 友達の車の見せ方（2026-10-19 判断）: 相手が持っている要サーバーの部品を、図鑑の並びで分類ごとに付ける
    /// （同じ分類に2つあれば後の方）。オーニングの部品があれば広げる。ほかは最初の部品
    static func visiting(_ ids: [String]) -> CamperLoadout {
        var out = CamperLoadout.standard
        let have = Set(ids)
        for part in CamperCatalog.dex where have.contains(part.id) { out.pick(part) }
        if have.contains(where: { $0.hasPrefix("awning.") }) { out.awningOpen = true }
        return out
    }
}
