import SwiftUI

/// AI で組んだ結果（作る流れが日程にして保存する）
struct TripAIResult {
    let title: String
    let days: [[TripDraft.Place]]
    /// 並べた理由の1文（AI なしの組み方では空）
    let reason: String
    /// 移動が無理で外した場所（「外しました　戻す」）
    let removed: [TripAIRouteCheck.Removed]
    /// AI なしで組んだときの1行（上限・圏外・AI が答えなかった）
    let fallbackNote: String?
}

/// 「どこへ、何日？」の欄の状態と、組む手順（札 #621）。
///
/// 押す回数（5 か所・1泊2日）: 今 12 回 → 2 回（作る・送る。字を打つのは数えない）。日付は聞かない（後から入れられる）。
///
/// どの AI で組むか（設定の行は作らない・2026-11-15 判断・案の推奨）:
/// - 端末の AI が使える iPhone → 端末で組む（0円・圏外でも動く）。**無料の人はサーバーで回数を数える**
///   （組めたあとに `count`。上限なら組んだものを使わず AI なしの組み方へ。圏外で数えられなければ AI なし）
/// - 使えない iPhone → サーバーの AI（Amazon Bedrock・東京）。回数はサーバーが数える
/// - 圏外・上限・AI が答えない → AI なしの組み方（`TripAIFallback`）。行き止まりにしない
@MainActor
final class TripAIComposerModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case working
        /// 行き先が読めなかった（回数に数えない）。候補の県
        case unreadable([String])
    }

    @Published var text = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var usage: TripAIService.Usage?
    /// この iPhone で端末の AI を使うか（開いたときに1回だけ決める）
    let onDevice: Bool

    init(onDevice: Bool = TripAIDevice.isAvailable) {
        self.onDevice = onDevice
    }

    /// 残りの帯を出すか（残り5回以下。Pro・管理者の端末の回は数えないので出さない）
    var showsRemaining: Bool {
        guard let usage else { return false }
        if onDevice && !usage.countsDevice { return false }
        return usage.remaining <= TripAILimits.warnAt
    }

    /// 無料の人か（使い切ったときに Pro の案内を出す）
    var isFree: Bool { usage?.tier == "free" }

    /// 欄の下の1行（どこで組むか）
    var whereLine: String {
        onDevice ? L("この iPhone の中で組みます", "Planned on this iPhone")
            : L("打った文を、日本にある journey.photo のサーバーで読みます", "Your words are read on journey.photo's server in Japan")
    }

    func loadUsage(service: TripAIService) async {
        usage = try? await service.status()
    }

    /// 組む。行き先が読めなければ nil（`phase` が `.unreadable`）
    func send(index: [OfficialSpot], wishlist: Set<String>, offline: Bool, service: TripAIService,
              eta: @escaping TripAIRouteCheck.ETA = TripAIRouteCheck.mapsETA) async -> TripAIResult? {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, phase != .working else { return nil }
        guard let match = TripAIDestination.match(request, spots: index) else {
            phase = .unreadable(TripAIDestination.suggestions(wishlist: index.filter { wishlist.contains($0.spotId) }))
            return nil
        }
        let candidates = TripAICandidates.pick(text: request, match: match, spots: index, wishlist: wishlist)
        guard !candidates.isEmpty else {
            phase = .unreadable(match.prefectures)
            return nil
        }
        let fixedDays = TripAIDays.parse(request)
        let title0 = TripAIText.defaultTitle(prefecture: match.prefectures.first, days: fixedDays ?? 1)
        return await run(request: request, candidates: candidates, fixedDays: fixedDays, current: [],
                         title0: title0, offline: offline, service: service, eta: eta)
    }

    /// 今の日程を、頼みに合わせて直す（「直したいことを書く」）。候補は今の日程の場所＋同じ県の観光スポット（20件まで）。
    /// 日数は頼みに書いてあればそれ、無ければ今の日数
    func revise(request: String, current: [[OfficialSpot]], index: [OfficialSpot], wishlist: Set<String>, offline: Bool,
                service: TripAIService, title: String,
                eta: @escaping TripAIRouteCheck.ETA = TripAIRouteCheck.mapsETA) async -> TripAIResult? {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, phase != .working else { return nil }
        let now = current.flatMap { $0 }
        var candidates = Array(now.prefix(TripAILimits.maxCandidates))
        let prefs = Array(Set(now.compactMap { $0.region?.prefecture })).sorted()
        let match = TripAIDestination.match(request, spots: index)
            ?? TripAIDestination.Match(prefectures: prefs, cities: Set(now.compactMap { $0.region?.city }))
        for s in TripAICandidates.pick(text: request, match: match, spots: index, wishlist: wishlist)
        where candidates.count < TripAILimits.maxCandidates && !candidates.contains(where: { $0.spotId == s.spotId }) {
            candidates.append(s)
        }
        guard !candidates.isEmpty else { return nil }
        var stops: [TripAIPlan.Stop] = []
        for (d, day) in current.enumerated() {
            for s in day { if let i = candidates.firstIndex(where: { $0.spotId == s.spotId }) { stops.append(.init(n: i + 1, day: d + 1)) } }
        }
        let fixedDays = TripAIDays.parse(request) ?? max(current.count, 1)
        return await run(request: request, candidates: candidates, fixedDays: fixedDays, current: stops,
                         title0: title, offline: offline, service: service, eta: eta)
    }

    /// AI（端末かサーバー）で組み、確かめ、移動の無理を外す。AI が使えなければ AI なしの組み方
    private func run(request: String, candidates: [OfficialSpot], fixedDays: Int?, current: [TripAIPlan.Stop],
                     title0: String, offline: Bool, service: TripAIService,
                     eta: @escaping TripAIRouteCheck.ETA) async -> TripAIResult {
        phase = .working
        defer { phase = .idle }
        let usedUpNote = L("今月の AI の回数を使い切ったので、AI を使わずに組みました", "You've used this month's AI plans, so this was planned without AI")
        let offlineNote = L("電波が無いので、AI を使わずに組みました", "No signal, so this was planned without AI")
        let silentNote = L("AI が答えなかったので、AI を使わずに組みました", "AI didn't answer, so this was planned without AI")

        var plan: TripAIPlan?
        var note: String?
        if offline && !onDevice {
            note = offlineNote
        } else if onDevice {
            let message = TripAIDevice.message(request: request, days: fixedDays, candidates: candidates, current: current)
            if let made = try? await TripAIDevice.plan(message: message, days: fixedDays) {
                // 無料の人は組めた回を数える（Pro・管理者は `countsDevice == false`。サーバーも数えずに返す）
                if usage?.countsDevice == false {
                    plan = made
                } else {
                    do {
                        usage = try await service.countDeviceUse()
                        plan = made
                    } catch TripAIService.Failure.limit {
                        markUsedUp()
                        note = usedUpNote
                    } catch {
                        // 数えられない（圏外）なら、組んだものを使わない（上限はサーバーで守る）
                        note = offlineNote
                    }
                }
            } else {
                note = silentNote
            }
        } else {
            do {
                let (made, used) = try await service.plan(request: request, days: fixedDays, candidates: candidates, current: current)
                plan = made
                usage = used
            } catch TripAIService.Failure.limit {
                markUsedUp()
                note = usedUpNote
            } catch {
                note = silentNote
            }
        }

        let checked = plan?.sanitized(candidateCount: candidates.count, fixedDays: fixedDays)
        if plan != nil && checked == nil {
            note = L("AI の答えを読み取れなかったので、AI を使わずに組みました", "Couldn't read the AI's answer, so this was planned without AI")
        }
        let fallbackDays = fixedDays ?? 1
        let final: TripAIPlan
        if let checked {
            final = checked
        } else if !current.isEmpty {
            // 直すときに AI が使えなければ、今の日程のまま（壊さない）
            final = TripAIPlan(title: title0, days: fallbackDays, stops: current, reason: "")
        } else {
            final = TripAIFallback.plan(candidates: candidates, days: fallbackDays, title: title0)
        }
        let trimmed = await TripAIRouteCheck.trim(final.dayLists(candidates), eta: eta)
        let reason = checked?.reasonChecked(against: candidates) ?? ""
        return TripAIResult(title: final.title.isEmpty ? title0 : final.title,
                            days: trimmed.days.map { $0.map(TripDraft.place(spot:)) },
                            reason: reason, removed: trimmed.removed, fallbackNote: note)
    }
    private func markUsedUp() {
        if let u = usage {
            usage = .init(tier: u.tier, used: u.limit, limit: u.limit, remaining: 0, resetsOn: u.resetsOn, countsDevice: u.countsDevice)
        } else {
            usage = .init(tier: "free", used: TripAILimits.free, limit: TripAILimits.free, remaining: 0,
                          resetsOn: TripAIText.nextReset(), countsDevice: true)
        }
    }

    func clearUnreadable() { if case .unreadable = phase { phase = .idle } }
}

/// 「どこへ、何日？」の欄（作るの最初の画面の上・板 Components の入力欄 48 と案内の帯）
struct TripAIComposerView: View {
    @ObservedObject var model: TripAIComposerModel
    let send: () -> Void
    let openPro: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(L("どこへ、何日？", "Where, and how long?"))
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)

            if model.showsRemaining, let usage = model.usage { remainingBand(usage) }

            HStack(spacing: JPSpace.xs) {
                JPTextField(TripAIText.placeholder, text: $model.text)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: model.text) { _, _ in model.clearUnreadable() }
                    .accessibilityIdentifier("tripAI.field")
                Button(action: send) {
                    Group {
                        if model.phase == .working {
                            ProgressView().tint(WebTheme.accentText)
                        } else {
                            Image(systemName: "arrow.up").font(.body.weight(.semibold))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .foregroundStyle(WebTheme.accentText)
                    .background(WebTheme.accentFill, in: Circle())
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                .opacity(sendDisabled && model.phase != .working ? TripStyle.disabledOpacity : 1)
                .accessibilityLabel(model.phase == .working ? L("組んでいます", "Planning") : L("送る", "Send"))
                .accessibilityIdentifier("tripAI.send")
            }
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? WebTheme.accent : WebTheme.outline, lineWidth: 1))

            if case .unreadable(let prefs) = model.phase {
                Text(L("行き先が分かりませんでした。県か町の名前を入れてください。", "Couldn't tell where. Add a prefecture or town name."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityIdentifier("tripAI.unreadable")
                chips(prefs.map { ($0, "\($0)で" + model.text) })
            } else {
                chips(TripAIText.examples.map { ($0, $0) })
            }

            Text(model.whereLine)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
    }

    private var sendDisabled: Bool {
        model.phase == .working || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 例のチップ（押すと欄に入れてそのまま送る）
    private func chips(_ items: [(label: String, text: String)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.xs) {
                ForEach(items, id: \.label) { item in
                    Button {
                        model.text = item.text
                        send()
                    } label: {
                        Text(item.label)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text)
                            .padding(.horizontal, JPSpace.s)
                            .frame(minHeight: 32)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.phase == .working)
                }
            }
        }
    }

    /// 残りの帯（真鍮 8% の地・真鍮の字。板 Components 05「案内の帯」）。無料の人は押すと Pro の案内
    private func remainingBand(_ usage: TripAIService.Usage) -> some View {
        Button {
            if usage.tier == "free" { openPro() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TripAIText.remainingLine(remaining: usage.remaining, resetsOn: usage.resetsOn))
                        .font(JPFont.footnote.weight(.semibold))
                    if usage.tier == "free" {
                        Text(L("Pro なら月\(TripAILimits.pro)回", "Pro: \(TripAILimits.pro) a month"))
                            .font(JPFont.caption)
                            .underline()
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, JPSpace.s)
            .padding(.vertical, JPSpace.xs)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(usage.tier == "free" ? L("Pro の案内を開きます", "Opens Pro") : "")
        .accessibilityIdentifier("tripAI.remaining")
    }
}
