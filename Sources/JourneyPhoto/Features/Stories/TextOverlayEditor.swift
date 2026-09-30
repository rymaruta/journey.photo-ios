import SwiftUI
import UIKit

/// 写真と、その上の文字（作る画面の全面・板 24 / 24b）。
///
/// owner の要望:「ユーザは画面のいろんなとこにテキストを配置したい」。
///
/// **写真は画面いっぱいに埋めて敷く**（`TextOverlay.filledRect`）。文字の位置と
/// 大きさは**画像に対する割合**のままなので、焼き込み（`TextOverlayRenderer`）と
/// 同じところに出る。閲覧画面も埋めて出すので、見えている範囲もほぼ同じになる。
///
/// **置いた場所は指で決める。** 指で動かし、2本指で回す・つまむ（指の下の札に効く）。
/// 押すと打ち直す（`onTap`）。下のゴミ箱へ運ぶと消える。
/// 動かした先は見えている範囲の中へ寄せる（はみ出した端では掴み直せない）
struct StoryCanvas: View {

    let preview: Image
    /// 写真の本当の大きさ（画素）。分からないとき（nil）は枠いっぱいを写真とみなす
    let imageSize: CGSize?
    @Binding var overlays: [TextOverlay]
    /// 写真の合わせ方（拡大・位置・回し）。写真の上で動かす操作と、指の間に札の無い2本指の操作は
    /// 写真に効く（`StoryTextEditing.gestureTarget`）
    @Binding var framing: PhotoFraming
    /// 描かない札（写真の上で直接打っている札。打つ画面の真ん中に出ている）
    var hiddenId: UUID? = nil
    /// 札を押した
    var onTap: (TextOverlay) -> Void = { _ in }
    /// 写真（札の無い所）を1回押した（呼ぶ側は投票の欄を閉じる）
    var onTapPhoto: () -> Void = {}
    /// 札をゴミ箱へ運んで離した（VoiceOver の「消す」も同じ口）
    var onDelete: (UUID) -> Void = { _ in }
    /// 札を指で動かし始めた・終えた（呼ぶ側は動かしている間、周りの道具を隠してゴミ箱を見せる）
    var onDraggingChange: (Bool) -> Void = { _ in }
    /// 投票（写真1枚に1つ・焼き込まずにデータで送る）。**閲覧画面と同じ札で描く**（`StoryTextLayer`）
    var vote: Binding<StoryVoteDraft?> = .constant(nil)
    /// 投票の札を選んでいる（破線で囲む）
    var voteSelected = false
    /// 投票の札を押した
    var onTapVote: () -> Void = {}
    /// いま出している写真の印。**動かしている間に写真が替わったら、その回の移動を書かない**
    var photoId: UUID? = nil

    /// 指で動かしている最中の見た目の移動量（離したときに位置へ反映する）
    @State private var dragId: UUID?
    @State private var dragOffset: CGSize = .zero
    /// **キーボードで縮む前の枠の大きさ。** 見えている範囲はこれで決める——
    /// 縮んだ枠で決めると、キーボードを閉じたあとに画面の外へ出る札を作れた
    @State private var stableSize: CGSize = .zero
    /// 2本指で回している最中の札と、その角度（離したときに回しへ足す）
    @State private var rotateId: UUID?
    @State private var liveRotation: Double = 0
    /// 2本指でつまんでいる最中の札と、その倍率（離したときに大きさへ掛ける）
    @State private var scaleId: UUID?
    @State private var liveScale: Double = 1
    /// 指が触れている間だけ立つ印。**打ち切られても（着信・画面の切り替えで `onEnded` が
    /// 呼ばれない回も）SwiftUI が倒す**——倒れたら、途中の値を札へ入れて片付ける。
    /// 片付けないと、見た目だけ大きく（回って・ずれて）見えたまま、投稿される札は元のままだった
    /// （f17f17d のレビュー）
    @GestureState private var twisting = false
    @GestureState private var pinching = false
    @GestureState private var dragging = false
    /// 投票の札を動かし始めたときの札（動かしている間は**札の位置そのもの**を書き換える——
    /// 指の移動をそのまま見せると、札の置き方（割合の点で合わせる）と比が違い、離すと戻った）
    @State private var voteDragStart: StoryVoteDraft?
    /// 動かし始めた写真の印（`photoId`）
    @State private var voteDragPhotoId: UUID?
    /// 動かしている間に2本指の操作が入った（この回は動かさず、始めの位置に戻す）
    @State private var voteDragSpoiled = false
    @GestureState private var voteDragging = false
    /// 写真を動かしている最中の移動量（離したときに `framing` へ入れる）と、その印
    @State private var photoDrag: CGSize = .zero
    @GestureState private var photoDragging = false
    /// 写真を動かしている間に2本指の操作が入ったか（入った回の移動は入れない・札と同じ）。
    /// 動かし始めに戻す
    @State private var photoDragSpoiled = false
    @State private var photoDragStarted = false
    /// 2本指の操作がいま写真に効いているか（札に効いているときは false）。
    /// **始めたときに決めて、終わるまで変えない**（途中で札を選んでも移さない）
    @State private var twistsPhoto = false
    @State private var pinchesPhoto = false
    /// この回の2本指の操作で、写真の大きさが目に見えて変わったか（つまんでいた回）。
    /// つまんでいた回の小さなひねりは捨てる（`PhotoFraming.intendedTwist`）
    @State private var photoPinched = false
    /// 1本指で動かしている間に2本指の操作が入ったか。**入った回の移動は入れない**
    /// ——札の上でつまむと、動かす操作も片方の指を追って動き、離すとずれた所で決まった
    @State private var dragSpoiled = false
    /// 動かしている指がゴミ箱の上にあるか（離すと消す）
    @State private var trashHot = false
    /// この回、指がいったんゴミ箱の外にいたか（外にいたことが無ければ離しても消さない）
    @State private var trashArmed = false
    /// 2本指が入ったとき、はっきり運んでいた札（運んだ分を入れた札）。2本指の相手の候補。
    /// 運ぶ指を離すまで覚える（2本目の指を置き直しても同じ札に効く）
    @State private var carriedId: UUID?
    /// 真ん中の縦・横の目安に吸い付いているか（線を出す）と、吸い付けたぶんのずれ
    @State private var snapVertical = false
    @State private var snapHorizontal = false
    @State private var snapDelta: CGSize = .zero

    /// 指の位置を読む座標（写真の枠そのもの）
    static let space = "storyCanvas"

    var body: some View {
        GeometryReader { geometry in
            let photo = TextOverlay.filledRect(image: imageSize ?? geometry.size, in: geometry.size)
            ZStack(alignment: .topLeading) {
                // 写真は**写真の枠（`photo`）の大きさで描き、合わせ方を重ねる**
                // （焼き込みの `PhotoFraming.placement` と同じ順: 倍率 → 回し → ずらし）。
                // 届かない所は後ろの黒
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                let shown = liveFraming(in: photo.size)
                preview.resizable()
                    .frame(width: photo.width, height: photo.height)
                    .scaleEffect(CGFloat(shown.scale))
                    .rotationEffect(.radians(shown.rotation))
                    .offset(x: CGFloat(shown.offsetX * Double(photo.width)),
                            y: CGFloat(shown.offsetY * Double(photo.height)))
                    .position(x: photo.midX, y: photo.midY)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    // 写真の上で動かす（札の上では札が先に取る）。2回押すと合わせ方を戻す
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($photoDragging) { _, state, _ in state = true }
                            .onChanged { value in
                                if !photoDragStarted { photoDragStarted = true; photoDragSpoiled = false }
                                // 2本指の操作が入った回は、この回はもう動かさない
                                // ——片方の指を離したあとに、つまんだ間の移動がまとめて入って跳んだ
                                if twoFingerActive { photoDragSpoiled = true }
                                photoDrag = photoDragSpoiled ? .zero : value.translation
                            }
                            .onEnded { value in
                                // 入れるのは離したときの移動量から（片付けの順に頼らない）
                                if !photoDragSpoiled && !twoFingerActive {
                                    framing = framing.moved(by: value.translation, in: photo.size)
                                }
                                photoDrag = .zero
                                photoDragStarted = false
                            }
                    )
                    .onTapGesture(count: 2) { framing = .identity }
                    .onTapGesture { onTapPhoto() }
                    .accessibilityElement()
                    .accessibilityLabel(L("写真", "Photo"))
                    .accessibilityHint(L("2本指で拡大・回転、指で動かします。2回押すと元に戻します",
                                         "Pinch or twist to zoom and rotate, drag to move. Double-tap to reset"))
                ForEach(overlays.filter { $0.id != hiddenId }) { overlay in
                    text(overlay, photo: photo, canvas: geometry.size)
                }
                if let current = vote.wrappedValue {
                    // 投票の札。**置き方は閲覧画面と同じ**（絵の矩形に対する割合）。
                    // 札の上だけが指を取る（層の残りは素通り）
                    StoryTextLayer(texts: [current.asItem], imageSize: imageSize, voteState: nil,
                                   canVote: false, voting: false, highlighted: voteSelected, editable: true)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(
                            DragGesture()
                                .updating($voteDragging) { _, state, _ in state = true }
                                .onChanged { value in
                                    if voteDragStart == nil {
                                        voteDragStart = current; voteDragSpoiled = false; voteDragPhotoId = photoId
                                    }
                                    // 動かしている間に表示中の写真が替わったら、別の写真の投票を動かさない
                                    guard let start = voteDragStart, voteDragPhotoId == photoId else { return }
                                    if twoFingerActive { voteDragSpoiled = true }
                                    // 見えている範囲は**キーボードで縮む前の枠**で決める（文字の札と同じ）
                                    let full = stableSize == .zero ? geometry.size : stableSize
                                    let fullPhoto = TextOverlay.filledRect(image: imageSize ?? full, in: full)
                                    let next = voteDragSpoiled ? start : start.moved(
                                        by: value.translation, in: photo.size,
                                        visible: StoryVoteDraft.visibleRange(photo: fullPhoto, canvas: full))
                                    placeVote(x: next.x, y: next.y)
                                }
                                .onEnded { _ in
                                    if voteDragSpoiled, voteDragPhotoId == photoId, let start = voteDragStart {
                                        placeVote(x: start.x, y: start.y)
                                    }
                                    voteDragStart = nil
                                }
                        )
                        .onTapGesture { onTapVote() }
                        .accessibilityAction(named: L("投票を編集", "Edit poll")) { onTapVote() }
                }
                // 札を動かしている間だけ: 真ん中の目安の線と、下のゴミ箱（写真の上に置くのは白だけ）
                // 2本指が入って相殺された回は出さない（つまんでいる間じゅうゴミ箱が出ていた）
                if dragId != nil && !dragSpoiled {
                    guides(canvas: geometry.size)
                    trash(canvas: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .coordinateSpace(.named(Self.space))
            // ゴミ箱に入った・出たときに震わせる（離せば消えると指で分かる）
            .sensoryFeedback(.impact(weight: .medium), trigger: trashHot)
            // 2本指で札か写真を回す（相手は `StoryTextEditing.gestureTarget`）。
            // 札そのものに付けると、2本とも小さな札の中に置かないと効かないので枠全体に付ける
            .simultaneousGesture(
                RotateGesture()
                    .updating($twisting) { _, state, _ in state = true }
                    .onChanged { value in
                        // **回し始めに相手を決めて、終わるまで変えない**（順は `StoryTextEditing.gestureTarget`）。
                        // 以前は選んだ札にしか効かず、文字を押すと打つ画面が開くようになってから、
                        // 文字を回せなくなっていた（4ffb74f の制限）
                        if rotateId == nil && !twistsPhoto {
                            let other: StoryTextEditing.GestureTarget? = scaleId.map { .overlay($0) }
                                ?? (pinchesPhoto ? .photo : nil)
                            absorbDrag(photo: photo, canvas: geometry.size)
                            switch StoryTextEditing.gestureTarget(other: other,
                                                                  under: { overlayUnder(value.startLocation, photo: photo) },
                                                                  carried: carriedId) {
                            case .overlay(let id):
                                rotateId = id
                            case .photo:
                                twistsPhoto = true
                            }
                        }
                        liveRotation = value.rotation.radians
                    }
                    .onEnded { value in
                        // 打ち切りの片付けが先に済んでいたら何もしない
                        guard rotateId != nil || twistsPhoto else { return }
                        liveRotation = value.rotation.radians
                        commitRotation()
                    }
            )
            // つまんで札か写真の大きさを変える（回すのと同じ理由で枠全体に付ける）。
            // 幅はスライダーと同じ（`TextOverlay.scaled`）
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinching) { _, state, _ in state = true }
                    .onChanged { value in
                        // 回すのと同じ決め方（`StoryTextEditing.gestureTarget`）
                        if scaleId == nil && !pinchesPhoto {
                            let other: StoryTextEditing.GestureTarget? = rotateId.map { .overlay($0) }
                                ?? (twistsPhoto ? .photo : nil)
                            absorbDrag(photo: photo, canvas: geometry.size)
                            switch StoryTextEditing.gestureTarget(other: other,
                                                                  under: { overlayUnder(value.startLocation, photo: photo) },
                                                                  carried: carriedId) {
                            case .overlay(let id):
                                scaleId = id
                            case .photo:
                                pinchesPhoto = true
                            }
                        }
                        liveScale = Double(value.magnification)
                        if pinchesPhoto && abs(liveScale - 1) > 0.05 { photoPinched = true }
                    }
                    .onEnded { value in
                        guard scaleId != nil || pinchesPhoto else { return }
                        liveScale = Double(value.magnification)
                        commitScale()
                    }
            )
            // 打ち切られた回の片付け（`onEnded` と、どちらが先に来ても1回だけ入る）
            .onChange(of: twisting) { _, active in if !active { commitRotation() } }
            .onChange(of: pinching) { _, active in if !active { commitScale() } }
            .onChange(of: voteDragging) { _, active in
                // 投票の札を動かす操作の片付け。**位置は戻さない**——動かしている間の位置は毎回
                // 見えている範囲に挟んだ正しい値で、`onEnded` より先にここへ来ても離した所に残る
                // （戻すと、この順で来た回に離すたび札が元へ戻った・38685e4 のレビュー）
                if !active { voteDragStart = nil }
            }
            .onChange(of: photoDragging) { _, active in
                // 写真を動かす操作の打ち切り。**移動は入れない**（印は次に動かし始めたときに戻す）
                if !active { photoDrag = .zero; photoDragStarted = false }
            }
            .onChange(of: dragging) { _, active in
                // 動かす操作の打ち切り。**移動は入れない**（離した位置が分からない）。
                // `dragSpoiled` はここで戻さない——`onEnded` より先に来ると、2本指が入った回の
                // 移動を入れてしまう。次に動かし始めたときに戻す
                if !active {
                    dragId = nil; dragOffset = .zero; resetDragAids()
                    if !twoFingerActive { carriedId = nil }
                }
            }
            .onChange(of: dragId) { old, new in
                if (old == nil) != (new == nil) { onDraggingChange(new != nil) }
            }
            // 動かしている最中に画面ごと消えても、周りの道具を隠したままにしない
            .onDisappear { if dragId != nil { onDraggingChange(false) } }
            .onAppear { remember(geometry.size) }
            .onChange(of: geometry.size) { _, size in remember(size) }
        }
    }

    /// 投票の札の**位置だけ**を書き換える（問い・選択肢は触らない——動かしている間に表示中の
    /// 写真が替わっても、別の写真の投票の中身を上書きしない・38685e4 のレビュー）
    private func placeVote(x: Double, y: Double) {
        guard var current = vote.wrappedValue else { return }
        current.x = x
        current.y = y
        vote.wrappedValue = current
    }

    /// 回した角度を札へ入れて片付ける。**2回目は何もしない**（`onEnded` と打ち切りの片付けの両方から来る）
    private func commitRotation() {
        if let id = rotateId, let i = overlays.firstIndex(where: { $0.id == id }) {
            overlays[i].rotation += liveRotation
        } else if twistsPhoto {
            framing = framing.rotated(by: PhotoFraming.intendedTwist(liveRotation, whilePinching: photoPinched))
        }
        rotateId = nil
        twistsPhoto = false
        liveRotation = 0
        // 運ぶ指が置かれたままなら覚えておく（2本目の指を置き直して回し続けられるように）
        if scaleId == nil && !pinchesPhoto && dragId == nil { carriedId = nil }
        if !pinchesPhoto { photoPinched = false }
    }

    /// つまんだ倍率を札へ入れて片付ける（同じく2回目は何もしない）
    private func commitScale() {
        if let id = scaleId, let i = overlays.firstIndex(where: { $0.id == id }) {
            overlays[i] = overlays[i].scaled(by: liveScale)
        } else if pinchesPhoto {
            framing = framing.scaled(by: liveScale)
        }
        scaleId = nil
        pinchesPhoto = false
        liveScale = 1
        if rotateId == nil && !twistsPhoto && dragId == nil { carriedId = nil }
        // 回す方がまだ続いていれば、つまんでいた印はそちらの片付けで戻す
        if !twistsPhoto { photoPinched = false }
    }

    /// 2本指の操作（回す・つまむ）が、札か写真に効いている最中か。**指が触れている印も見る**
    /// ——札を選んでいない回は、印が立つまで `rotateId` / `scaleId` が立たない（6db29af のレビュー）
    private var twoFingerActive: Bool {
        rotateId != nil || scaleId != nil || twistsPhoto || pinchesPhoto || twisting || pinching
    }

    /// 指で操作している最中の合わせ方（**離したときと同じ幅で見せる**——幅の外で動いて見えて、
    /// 離すと戻る、にしない）
    private func liveFraming(in photo: CGSize) -> PhotoFraming {
        var live = framing
        if pinchesPhoto { live = live.scaled(by: liveScale) }
        if twistsPhoto { live = live.rotated(by: PhotoFraming.intendedTwist(liveRotation, whilePinching: photoPinched)) }
        return live.moved(by: photoDrag, in: photo)
    }

    /// 書体（`TextOverlay.Face`。同梱の字か端末の字。ゴシックは端末の太字）。**大きさは固定**——
    /// 焼き込みは画像の画素で描くので、文字の大きさの設定に追従させると割れる
    static func font(_ face: TextOverlay.Face, size: Double) -> Font {
        // **読めなかったときは焼き込みと同じ端末の太字に落とす。** `Font.custom` は
        // 黙って標準の太さに落ちるので、画面だけ細くなる
        if let name = face.fontName, UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .bold)
    }

    /// 文字に縁を付ける（焼き込みの `strokeWidth` に合わせる）。SwiftUI の文字には縁が無いので、
    /// **縁の色の文字を8方向にずらして下に敷く**。黒の見た目（白い縁・幅3%）と
    /// 縁取り（黒い縁・幅6%）。**以前は黒の見た目の縁が画面に出ず、焼き込みにだけ付いていた**
    static func edged<Label: View>(_ text: Label, overlay: TextOverlay, fontSize: Double) -> some View {
        let edge: (color: Color, width: Double)? = overlay.style.edgeOffset(fontSize: fontSize).map {
            (overlay.style == .dark ? .white : .black, $0)
        }
        return ZStack {
            if let edge {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4
                    text.foregroundStyle(edge.color)
                        .offset(x: CGFloat(cos(angle) * edge.width), y: CGFloat(sin(angle) * edge.width))
                        // 縁のための写しは読み上げない（同じ文字を9回読まれる）
                        .accessibilityHidden(true)
                }
            }
            text.foregroundStyle(color(hex: overlay.drawnHex))
        }
    }

    static func alignment(_ align: TextOverlay.Align) -> TextAlignment {
        switch align {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    static func color(_ ink: TextOverlay.Ink) -> Color {
        color(hex: ink.hex)
    }

    static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// 端末の色選びが返した色を 0xRRGGBB に。**`UIKit.` と書くのは Linux の模型のため**
    /// （模型では SwiftUI と UIKit が別々に `UIColor` を持つ。本物では同じもの）
    static func hex(of color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        _ = UIKit.UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return TextOverlay.hex(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// 幅が変わったら測り直し、同じ幅なら高い方を覚える
    private func remember(_ size: CGSize) {
        if size.width != stableSize.width || size.height > stableSize.height {
            stableSize = size
        }
    }

    private func text(_ overlay: TextOverlay, photo: CGRect, canvas: CGSize) -> some View {
        let moving = dragId == overlay.id
        // 大きさと位置は焼き込みと同じ関数（写真の短い辺に対する割合・
        // 写真に対する位置）。**下限で持ち上げない**——持ち上げると、
        // スライダーを下げても見た目が変わらないのに投稿される文字だけ
        // 小さくなる（2026-09-26 のレビュー）
        // つまんでいる最中も、離したときと同じ幅で見せる（幅の外で大きく見えて、離すと縮む、にしない）
        let size = scaleId == overlay.id ? overlay.scaled(by: liveScale).size : overlay.size
        let fontSize = TextOverlay.fontSize(size, in: photo.size)
        let center = overlay.center(in: photo)
        let rotation = overlay.rotation + (rotateId == overlay.id ? liveRotation : 0)
        return Self.edged(Text(overlay.drawnText)
            // 書体と色は焼き込みと同じもの（`TextOverlayRenderer.attributes`）
            .font(Self.font(overlay.face, size: fontSize))
            // 改行した文字の揃え（焼き込みは揃えつきの段落・`TextOverlayRenderer.draw`）
            .multilineTextAlignment(Self.alignment(overlay.align))
            // **折り返さない**（焼き込みも折り返さない。画面の幅で折り返すと行数と揃えがずれた）
            .fixedSize(), overlay: overlay, fontSize: fontSize)
            // 帯の余白も焼き込み（`TextOverlayRenderer.draw`）と同じ割合
            .padding(.horizontal, overlay.style == .banner ? CGFloat(fontSize * 0.35) : 0)
            .padding(.vertical, overlay.style == .banner ? CGFloat(fontSize * 0.175) : 0)
            .background(overlay.style == .banner ? Color.black.opacity(0.65) : Color.clear)
            .shadow(radius: overlay.style == .light ? 6 : 0)
            // 小さい文字でも指で掴めるように、**押せる範囲だけ**広げる
            // （帯の見た目は広げない＝`background` より後ろに置く）
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            // 回しは中心の周り（焼き込みも中心の周り）。**押せる範囲より後ろ**に
            // 置いて一緒に回す——前に置くと、縦に回した文字の端を押しても掴めない
            .rotationEffect(.radians(rotation))
            .position(x: center.x + (moving ? dragOffset.width : 0),
                      y: center.y + (moving ? dragOffset.height : 0))
            .gesture(
                // 指の位置は写真の枠の座標で読む（ゴミ箱の上か・`Self.space`）
                DragGesture(coordinateSpace: .named(Self.space))
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        // 動かし始め（前の回の印を戻す）
                        if dragId == nil { dragSpoiled = false; if !twoFingerActive { carriedId = nil } }
                        // 2本指の操作（回す・つまむ。**写真に効いているときも**）が入ったら、この回は動かさない。
                        // **相殺する前に、そこまで運んだ分を入れる**（2本指の判定より先にここへ来ると、
                        // 運んだ分が捨てられて札が元の位置へ戻った・4ed53ca のレビュー）。2回目は何もしない
                        if twoFingerActive && !dragSpoiled && dragId == overlay.id {
                            absorbDrag(photo: photo, canvas: canvas)
                        }
                        if twoFingerActive { dragSpoiled = true }
                        dragId = overlay.id
                        guard !dragSpoiled else {
                            dragOffset = .zero
                            resetDragAids()
                            return
                        }
                        // 真ん中の目安に吸い付ける（中心で見る）
                        let live = CGPoint(x: center.x + value.translation.width,
                                           y: center.y + value.translation.height)
                        let snapped = StoryTextEditing.snap(live, canvas: canvas)
                        snapVertical = snapped.vertical
                        snapHorizontal = snapped.horizontal
                        snapDelta = CGSize(width: snapped.point.x - live.x, height: snapped.point.y - live.y)
                        dragOffset = CGSize(width: value.translation.width + snapDelta.width,
                                            height: value.translation.height + snapDelta.height)
                        // ゴミ箱は**指の位置**で見る。指がいったん外に出るまでは効かせない
                        trashArmed = StoryTextEditing.trashArmed(wasArmed: trashArmed, finger: value.location, canvas: canvas)
                        trashHot = trashArmed && StoryTextEditing.isOverTrash(value.location, canvas: canvas)
                    }
                    .onEnded { value in
                        // **離したときに位置へ入れる。** 動かしている最中に
                        // 入れると、はみ出しの丸めが毎フレーム効いて指から離れる
                        if !dragSpoiled && !twoFingerActive {
                            if trashArmed && StoryTextEditing.isOverTrash(value.location, canvas: canvas) {
                                onDelete(overlay.id)
                            } else {
                                // 吸い付きは**離した位置で**計算し直す（最後の onChanged の値を使うと、
                                // 離す瞬間に線から離れていても最大 8pt 寄った）
                                let live = CGPoint(x: center.x + value.translation.width,
                                                   y: center.y + value.translation.height)
                                let snapped = StoryTextEditing.snap(live, canvas: canvas).point
                                move(overlay, by: CGSize(width: snapped.x - center.x, height: snapped.y - center.y),
                                     photo: photo, canvas: canvas)
                            }
                        }
                        dragId = nil
                        dragOffset = .zero
                        dragSpoiled = false
                        resetDragAids()
                        // 運ぶ指を離した。2本指も終わっていれば、運んでいた札を忘れる
                        if !twoFingerActive { carriedId = nil }
                    }
            )
            // 押すと選ぶ（直す・消すのも同じ入口）。
            // **時刻と日付も押せる**——直せないが、消す口はここにしか無い
            .onTapGesture { onTap(overlay) }
            .accessibilityLabel(overlay.text)
            // VoiceOver では指で運べないので、消す操作を別に出す
            .accessibilityAction(named: L("消す", "Delete")) { onDelete(overlay.id) }
    }

    /// 動かしている間の目安（吸い付き・ゴミ箱）を戻す
    private func resetDragAids() {
        trashHot = false
        trashArmed = false
        snapVertical = false
        snapHorizontal = false
        snapDelta = .zero
    }

    /// 1本指で運んでいる途中に2本指の操作が入ったら、**そこまで運んだ分を入れてから**2本指へ移る
    /// （入れずに相殺すると札が元の位置へ戻り、つまむ相手も元の位置で当てていた）
    private func absorbDrag(photo: CGRect, canvas: CGSize) {
        guard let id = dragId, !dragSpoiled, let overlay = overlays.first(where: { $0.id == id }) else { return }
        if dragOffset != .zero { move(overlay, by: dragOffset, photo: photo, canvas: canvas) }
        // はっきり運んでいた札だけ、2本指の相手の候補にする（どちらの処理が先に届いても同じ）
        carriedId = StoryTextEditing.isCarried(dragOffset) ? id : nil
        dragSpoiled = true
        dragOffset = .zero
        resetDragAids()
    }

    /// 2本指の操作の始めの位置の下にある札（上に重なっている方を先に）。打っている札は数えない
    private func overlayUnder(_ point: CGPoint, photo: CGRect) -> UUID? {
        let placed = overlays.filter { $0.id != hiddenId }.map { overlay -> StoryTextEditing.Placed in
            let fontSize = TextOverlay.fontSize(overlay.size, in: photo.size)
            let text = TextOverlayRenderer.naturalSize(overlay, fontSize: fontSize)
            let banner = overlay.style == .banner
            return StoryTextEditing.Placed(
                id: overlay.id, center: overlay.center(in: photo),
                size: CGSize(width: text.width + (banner ? fontSize * 0.7 : 0),
                             height: text.height + (banner ? fontSize * 0.35 : 0)),
                rotation: overlay.rotation)
        }
        return StoryTextEditing.overlay(at: point, in: placed)
    }

    /// 真ん中の目安の線（吸い付いている向きだけ）
    @ViewBuilder
    private func guides(canvas: CGSize) -> some View {
        if snapVertical {
            Rectangle().fill(Color.white.opacity(0.8))
                .frame(width: 1, height: canvas.height)
                .position(x: canvas.width / 2, y: canvas.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        if snapHorizontal {
            Rectangle().fill(Color.white.opacity(0.8))
                .frame(width: canvas.width, height: 1)
                .position(x: canvas.width / 2, y: canvas.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// ゴミ箱（下の真ん中）。**指が入ると白地に墨で大きく**（色だけで状態を言わない）
    private func trash(canvas: CGSize) -> some View {
        let c = StoryTextEditing.trashCenter(canvas: canvas)
        return Image(systemName: "trash")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(trashHot ? Color.black : Color.white)
            .frame(width: 52, height: 52)
            .background(trashHot ? Color.white : Color.black.opacity(0.45), in: Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            .scaleEffect(trashHot ? 1.25 : 1)
            .position(x: c.x, y: c.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func move(_ overlay: TextOverlay, by translation: CGSize, photo: CGRect, canvas: CGSize) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        // 見えている範囲は縮む前の枠で決める
        let full = stableSize == .zero ? canvas : stableSize
        let fullPhoto = TextOverlay.filledRect(image: imageSize ?? full, in: full)
        overlays[index] = overlays[index]
            .moved(by: translation, in: photo.size)
            .clamped(toVisible: fullPhoto, canvas: full)
    }
}

/// 写真の上の丸いチップ（選ぶと白地に墨・板 24b）
struct OverlayChip: View {
    let title: String
    var systemImage: String? = nil
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12))
                }
                Text(title)
            }
            .font(.system(size: selected ? 13 : 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? WebTheme.accentText : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? AnyShapeStyle(WebTheme.accentBackground) : AnyShapeStyle(Color.black.opacity(0.55)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.14), lineWidth: 1))
            // 見た目は 36 の札のまま、押せる所は 44（CLAUDE.md の最小）
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 書体の列（8種・横に流す）。**選んでいる書体まで流して見せる**（後ろの方の書体を選んだ札を
/// 開き直すと、列の頭が出て何を選んでいるか見えなかった・bfe5e12 のレビュー）。
/// 下の操作欄と、写真の上で打つ画面（`StoryTextTypingView`）の両方が使う
struct OverlayFaceRow: View {
    @Binding var overlay: TextOverlay

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TextOverlay.Face.allCases) { face in
                        OverlayChip(title: face.label, selected: overlay.face == face) {
                            overlay.face = face
                        }
                        .id(face)
                    }
                }
            }
            .onAppear { proxy.scrollTo(overlay.face, anchor: .center) }
            .onChange(of: overlay.id) { _, _ in proxy.scrollTo(overlay.face, anchor: .center) }
        }
    }
}

/// 色の列（12色＋好きな色）。見た目に対して読めない色は出さない（`TextOverlay.inks(for:)`）。
/// 12色あるので横に流し、**選んでいる色まで流して見せる**（書体と同じ理由）
struct OverlayInkRow: View {
    @Binding var overlay: TextOverlay

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TextOverlay.inks(for: overlay.style)) { ink in
                        let selected = overlay.customHex == nil && overlay.drawnInk == ink
                        Button {
                            overlay.ink = ink
                            overlay.customHex = nil
                        } label: {
                            Circle()
                                .fill(StoryCanvas.color(ink))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : 0.5),
                                                               lineWidth: selected ? 3 : 2))
                                .overlay(Circle().strokeBorder(Color.black, lineWidth: selected ? 1 : 0).padding(-2))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("文字の色 \(ink.label)", "Text color \(ink.label)"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .id(ink)
                    }
                    customColor
                }
            }
            .onAppear { proxy.scrollTo(colorAnchor, anchor: .center) }
            .onChange(of: overlay.id) { _, _ in proxy.scrollTo(colorAnchor, anchor: .center) }
        }
    }

    /// 色の列で流して見せる先（好きな色を選んでいればその丸）
    var colorAnchor: AnyHashable {
        overlay.customHex == nil ? AnyHashable(overlay.drawnInk) : AnyHashable("custom")
    }

    /// 12色の後ろに置く「好きな色」（端末の色選び・owner の「色が少ない」2026-09-29）。
    /// 選んだ色は**見た目に対して読めるところまで寄せて描く**（`TextOverlay.readableHex`）。
    /// 丸に出すのも寄せたあとの色——選んだままの色を出すと、写真の上と食い違う
    var customColor: some View {
        ColorPicker("", selection: Binding(
            get: { StoryCanvas.color(hex: overlay.drawnHex) },
            // 丸に出している色（寄せたあと）がそのまま返ってきたときは書かない。
            // 書くと選んだ元の色が寄せた色で上書きされ、白の見た目に戻しても元の色に戻らない
            set: { color in
                let hex = StoryCanvas.hex(of: color)
                if hex != overlay.drawnHex { overlay.customHex = hex }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Color.white, lineWidth: overlay.customHex == nil ? 0 : 3)
            .frame(width: 36, height: 36)
            .allowsHitTesting(false))
        .accessibilityLabel(L("好きな色を選ぶ", "Pick any color"))
        .accessibilityAddTraits(overlay.customHex == nil ? [] : .isSelected)
        .id("custom")
    }
}

/// 投票の札の操作欄（問い・2つの選択肢・消す）。**字数はサーバーと同じ**（40・12）
struct VotePanel: View {

    @Binding var vote: StoryVoteDraft
    var onDelete: () -> Void
    /// どの欄を打っているか（問い・選択肢1・選択肢2）。**欄ごとに値を分ける**
    /// （1つの真偽を3つの欄に付けると、どこへ移るかが決まらない）
    @FocusState private var focused: Field?

    enum Field: Hashable { case question, optionA, optionB }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                field(L("問い", "Question"), .question, text: Binding(
                    get: { vote.question },
                    set: { vote.question = StoryVoteDraft.limited(old: vote.question, new: $0, max: StoryVoteDraft.questionMax) }))
                if focused != nil {
                    Button { focused = nil } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            // `.plain` は描いた所しか押せない。枠の 44 全体を押せる所にする
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("キーボードを閉じる", "Hide keyboard"))
                }
            }
            HStack(spacing: 8) {
                field(L("選択肢1", "Option 1"), .optionA, text: Binding(
                    get: { vote.optionA },
                    set: { vote.optionA = StoryVoteDraft.limited(old: vote.optionA, new: $0, max: StoryVoteDraft.optionMax) }))
                field(L("選択肢2", "Option 2"), .optionB, text: Binding(
                    get: { vote.optionB },
                    set: { vote.optionB = StoryVoteDraft.limited(old: vote.optionB, new: $0, max: StoryVoteDraft.optionMax) }))
            }
            HStack {
                // 欠けた投票は送れない（サーバーが黙って落とす）。**どこが欠けているかを言う**
                if !vote.isComplete {
                    Text(L("問いと2つの選択肢を入れてください", "Fill in the question and both options"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                }
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Label(L("消す", "Delete"), systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.danger)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(red: 12 / 255.0, green: 12 / 255.0, blue: 13 / 255.0).opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
    }

    private func field(_ placeholder: String, _ which: Field, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .focused($focused, equals: which)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
