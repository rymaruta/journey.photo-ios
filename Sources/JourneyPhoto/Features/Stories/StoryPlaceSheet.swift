import SwiftUI

/// ストーリーの「場所」のシート（2026-11-14 判断・人間工学の点検）。
///
/// 前は字を打つだけの小さな窓（`alert` の `TextField`）で、地名を最後まで打って「決める」を押していた。
/// 投稿の撮影地の欄と**同じ部品**（`PlaceSearchField`）を使い、打った数文字から候補（撮影スポット・地名）を出す。
/// 押す回数: 前「場所」→ 全部打つ →「決める」、今「場所」→ 数文字 → 候補を押す（押したら決めて閉じる）。
/// 写真の位置があれば、打つ前から近くの撮影スポットが並ぶ（`PlaceSpotSuggestions` の空の語）。
///
/// - 候補に無い名前は、打って右下のキー（完了）か右上の「決める」で決める（前と同じことができる）
/// - 座標は欄からは受け取らない。送る座標は今までどおり作る画面が決める（`StorySpotSuggestion.Place.coordsToSend`）
/// - 写真の位置は**近くの候補を先に出すためだけ**に使う（「撮影地の位置を付ける」がオフなら渡さない）
/// - 形は板の決まり: 閉じるは左上（`SheetCloseButton(onContent:)`）、右上は決める操作だけ（黒地なので真鍮の字）
struct StoryPlaceSheet: View {

    /// 開いたときの撮影地（空＝まだ付けていない）
    let initial: String
    /// 写真の位置（近くの候補を先に出す）。送らない
    let near: Photo.Coords?
    /// 欄の下の説明（位置を送るかどうか・`StoryLocationText.placeEditorNote`）
    let note: String
    /// 決めた撮影地（空＝外す）
    var onSet: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    /// 欄が候補の座標を書く先。**使わない**（送る座標は作る画面が決める）
    @State private var pickedCoords: Photo.Coords?

    init(initial: String, near: Photo.Coords?, note: String, onSet: @escaping (String) -> Void) {
        self.initial = initial
        self.near = near
        self.note = note
        self.onSet = onSet
        _draft = State(initialValue: initial)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            header
            VStack(alignment: .leading, spacing: 6) {
                // サーバーが 200 で切る（`sanitizeText(location, 200)`）。欄で止める（前の窓と同じ）
                PlaceSearchField(location: Binding(
                                    get: { draft },
                                    set: { draft = PostLimits.limited(old: draft, new: $0, limit: PostLimits.location) }),
                                 coords: $pickedCoords,
                                 near: near,
                                 offersSpots: true,
                                 boxed: true,
                                 fieldIdentifier: "story.place.field",
                                 autoFocus: true,
                                 onPick: { name in finish(name) })
                    .submitLabel(.done)
                    .onSubmit { finish(trimmed) }
            }
            Text(note)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if !initial.isEmpty {
                Button {
                    finish("")
                } label: {
                    Text(L("撮影地を外す", "Remove place"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("story.place.remove")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.l)
        .padding(.top, JPSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: JPSpace.s) {
            SheetCloseButton(onContent: true)
            Text(L("撮影地", "Place"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            // 右上は決める操作だけ（板 03「戻る、閉じるは 3 型だけ」）。黒地のヘッダーの文字の操作は真鍮
            Button {
                finish(trimmed)
            } label: {
                Text(L("決める", "Set"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(trimmed.isEmpty ? WebTheme.text3 : WebTheme.accent)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .accessibilityIdentifier("story.place.set")
        }
    }

    private func finish(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空のまま「完了」を押しただけ（まだ付けていない）なら何も変えずに閉じる
        if !(text.isEmpty && initial.isEmpty) { onSet(text) }
        dismiss()
    }
}
