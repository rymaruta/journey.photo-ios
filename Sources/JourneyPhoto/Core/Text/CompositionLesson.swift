import Foundation

/// 構図の詳しい解説（設定 → 撮影ガイド → 構図一覧 → 1つの構図の画面）。
///
/// 2026-10-16 判断（owner「構図の説明が軽いので、詳しくしたい」）: 今の一言（`CompositionExample.explanation`）に
/// 加えて、6つの段を全37種類に持たせる——どういう構図か（図の線と合わせて）・なぜ効くのか・撮り方の手順
/// （3〜4 段）・合う場面（旅先の例）・よくある失敗と直し方・似た構図との違い。
///
/// - 一覧は軽いまま（名前と場面の一言だけ）。この解説は構図を開いた画面で、段の見出しを押して開く
///   （`CompositionExplanationView`）。
/// - **根拠の弱い断言は書かない**（「黄金比は人が最も美しいと感じる」「巻き貝は黄金螺旋」など）。
///   効く理由は、目の動き・重さの釣り合い・奥行きのような、見て確かめられる言い方にする。
/// - 線の説明は `CompositionGuide.rawMarks` の線（variant 0・縦 3:4）と食い違わないように書く。
/// - 日本語と英語の両方を持つ。画面は `L()` と同じく端末の言語で選ぶ（`lesson(for:)`）。
///   試験は `lesson(for:english:)` で両方を見る（`CompositionLessonTests`）
struct CompositionLesson: Equatable {
    /// どういう構図か（線や点の決まり）
    let what: String
    /// なぜ効くのか
    let why: String
    /// 撮り方の手順（3〜4 段）
    let steps: [String]
    /// 合う場面（旅先の例）
    let scenes: String
    /// よくある失敗と直し方
    let mistakes: String
    /// 似た構図との違い
    let versus: String

    /// 段の見出し（画面と読み上げで同じ語を使う）
    enum Part: CaseIterable {
        case what, why, steps, scenes, mistakes, versus

        var title: String {
            switch self {
            case .what: return L("どういう構図か", "What it is")
            case .why: return L("なぜ効くのか", "Why it works")
            case .steps: return L("撮り方の手順", "How to shoot it")
            case .scenes: return L("合う場面", "Where it fits")
            case .mistakes: return L("よくある失敗と直し方", "Common mistakes")
            case .versus: return L("似た構図との違い", "Compared with similar guides")
            }
        }
    }
}

enum CompositionLessons {

    /// 端末の言語の解説
    static func lesson(for kind: CompositionKind) -> CompositionLesson {
        lesson(for: kind, english: Locale.preferredAppLanguage == "en")
    }

    /// 言語を決めて取り出す（試験で日本語・英語の両方を見る）
    static func lesson(for kind: CompositionKind, english: Bool) -> CompositionLesson {
        let e = entry(kind)
        func pick(_ p: Pair) -> String { english ? p.1 : p.0 }
        return CompositionLesson(what: pick(e.what), why: pick(e.why), steps: e.steps.map(pick),
                                 scenes: pick(e.scenes), mistakes: pick(e.mistakes), versus: pick(e.versus))
    }

    // MARK: - 中身

    private typealias Pair = (String, String)

    private struct Entry {
        let what: Pair
        let why: Pair
        let steps: [Pair]
        let scenes: Pair
        let mistakes: Pair
        let versus: Pair
    }

    // swiftlint:disable function_body_length line_length
    private static func entry(_ kind: CompositionKind) -> Entry {
        switch kind {

        // MARK: 定番の分割

        case .thirds:
            return Entry(
                what: ("縦と横に2本ずつ線を引き、画面を9つのマスに分けます。線が交わる4つの点のどれかに主役を置き、地平線や水平線は上か下の横線に重ねます。",
                       "Two vertical and two horizontal lines split the frame into nine boxes. Put the subject on one of the four crossing points and lay the horizon along the upper or lower line."),
                why: ("主役を真ん中から少しずらすと、主役の反対側に空いた場所ができ、そこに景色や向かう先が写ります。目は主役から空いた側へ動くので、写真に流れが生まれます。",
                      "Moving the subject off-center leaves open space on the other side for the scene around it. The eye travels from the subject into that space, which gives the picture a sense of movement."),
                steps: [("まず主役（人・建物・木など）を1つ決めます。", "Pick one subject: a person, a building, a tree."),
                        ("主役を4つの交点のどれかに合わせます。人や動物は、顔が向いている側を広く空けます。", "Place it on one of the four crossing points. If it faces a direction, leave more room on that side."),
                        ("地平線があれば、空を見せたいなら下の線、地面を見せたいなら上の線に重ねます。", "If there is a horizon, put it on the lower line to show more sky or the upper line to show more ground."),
                        ("最後に四隅を見て、要らない物が入っていないか確かめてから撮ります。", "Check the corners for clutter, then shoot.")],
                scenes: ("海辺の灯台、砂浜を歩く人、田んぼの中の一本の木、展望台からの街と空。", "A lighthouse on the coast, someone walking on a beach, a lone tree in rice fields, a city skyline from a lookout."),
                mistakes: ("主役が交点の近くでも小さすぎて目に入らない → 一歩寄るか、ズームして主役を大きくします。地平線が線からずれて傾く → 横線に合わせ、傾きは水準器で確かめます。",
                           "The subject sits near a point but is too small to notice → step closer or zoom in. The horizon drifts off the line or tilts → align it with the line and check with the level."),
                versus: ("ファイグリッド（黄金比）は線が少し内側（約38%と62%）に寄ります。三分割は33%と67%で、主役を外へ大きくずらしたいときは三分割、中央寄りに落ち着かせたいときはファイグリッドが向きます。",
                         "The phi grid puts its lines a little closer to the center (about 38% and 62%) than thirds (33% and 67%). Use thirds to push the subject further out, the phi grid for a calmer, more centered feel."))

        case .iphone:
            return Entry(
                what: ("iPhone の標準カメラで「グリッド」をオンにしたときと同じ、縦横2本ずつの線（三分割）です。カメラアプリと同じ線なので、慣れた目安のまま撮れます。",
                       "The same two-by-two lines (rule of thirds) that appear when you turn on Grid in the iPhone Camera app, so you can keep the guide you already know."),
                why: ("いつもの線と同じ位置なので、構図を考える手間が減り、主役と景色の置き場所だけに集中できます。交点に主役を置くと、主役と周りの景色の両方が伝わります。",
                      "Because the lines match what you are used to, you spend less effort on layout and more on the subject. A subject on a crossing point leaves room for its surroundings."),
                steps: [("主役を1つ決めます。", "Decide on one subject."),
                        ("主役を線の交わる点のどれかに合わせます。", "Place it on one of the crossing points."),
                        ("水平線や建物の縦の線を、近くの線と平行にそろえます。", "Make horizons and building edges parallel to the nearest line."),
                        ("撮った後に切り抜く予定があるなら、端に大事な物を置かないようにします。", "If you plan to crop later, keep important things away from the edges.")],
                scenes: ("砂浜を歩く人、駅のホームの列車、カフェの窓辺の一杯、旅先の記念写真。", "A person walking on a beach, a train at a platform, a drink by a café window, a travel snapshot."),
                mistakes: ("線に合わせることに気を取られて、主役のピントが甘くなる → 先に主役を押してピントを合わせてから、置き場所を整えます。",
                           "Focusing on the lines and missing focus on the subject → tap the subject to focus first, then adjust the framing."),
                versus: ("「三分割」と線は同じです。違いは名前だけで、iPhone のカメラから移ってきた人が迷わないように分けてあります。",
                         "The lines are identical to Rule of thirds; it is listed separately so people coming from the iPhone Camera app find it easily."))

        case .halves:
            return Entry(
                what: ("画面の真ん中に縦と横の線を1本ずつ引き、上下・左右を半分ずつに分けます。",
                       "One vertical and one horizontal line through the center split the frame into equal halves."),
                why: ("半分ずつに分けると、上と下（左と右）を見比べる写真になります。空と水面、昼と夜の色、古い物と新しい物のように「対」を見せたいときにはっきり伝わります。",
                      "Equal halves invite comparison: sky against water, warm against cool, old against new. The pairing reads clearly when neither side dominates."),
                steps: [("対になる2つ（空と映り込みなど）を見つけます。", "Find a pair, such as a scene and its reflection."),
                        ("境目（水際・地平線）を真ん中の横線に重ねます。", "Put the boundary—the waterline or horizon—on the center line."),
                        ("左右の対なら、真ん中の縦線に境目を合わせます。", "For a left–right pair, use the vertical line instead."),
                        ("両側の明るさがそろう時間（風の無い朝など）を選びます。", "Choose a time when both halves are similar in brightness, such as a still morning.")],
                scenes: ("湖に映る山と島、水田に映る夕焼け、左右で色の違う街並み。", "A mountain and island mirrored in a lake, sunset reflected in flooded rice fields, a street split into two colors."),
                mistakes: ("真ん中で切ったのに、上下のどちらも主役が弱く、ぼんやりした写真になる → どちらか一方に強い形（山・建物）を入れるか、三分割に切り替えます。",
                           "The frame is split evenly but neither half has a strong shape, so the photo feels flat → include a clear form in one half or switch to thirds."),
                versus: ("シンメトリーは「鏡のように同じ形」を見せる構図で、二分割は「違う2つを並べて比べる」ときに向きます。",
                         "Symmetry shows mirrored, matching shapes; halves is better for setting two different things side by side."))

        case .symmetry:
            return Entry(
                what: ("画面の真ん中に1本の軸（縦、または向きのボタンで横）を引き、その両側が鏡に映したように同じ形になるように撮ります。",
                       "A single axis through the center—vertical, or horizontal with the orientation button—with both sides matching like a mirror."),
                why: ("左右（上下）の重さがぴったり釣り合うので、静かで落ち着いた印象になります。少しでも崩れていると目立つので、整った建物や水面の映り込みの美しさが際立ちます。",
                      "The two sides balance exactly, which feels calm and formal. Because any break in the pattern stands out, it highlights how precise a building or a reflection is."),
                steps: [("左右が同じ形の物（門・建物の正面・桟橋）を探します。", "Find something that is the same on both sides: a gate, a façade, a pier."),
                        ("その真ん中に立ち、軸の線を建物の中心に合わせます。", "Stand on its center line and align the guide with the middle."),
                        ("カメラを傾けず、上下にも向けずにまっすぐ構えます（縦の線が平行になるように）。", "Hold the camera level and straight so vertical edges stay parallel."),
                        ("人や車が片側だけに入らない瞬間を待って撮ります。", "Wait until people or cars are not on just one side, then shoot.")],
                scenes: ("寺社の正面と参道、霧の湖へ延びる桟橋、宮殿の回廊、水面に映る城。", "A shrine gate and approach, a pier into a misty lake, a palace corridor, a castle reflected in water."),
                mistakes: ("数歩だけ横にずれていて、左右がわずかに違う → 足元で中心を確かめ、軸の線と建物の中心が重なるまで横へ動きます。見上げて撮り縦の線が傾く → 少し下がって水平に構えます。",
                           "You are a step off-center and the sides differ slightly → move sideways until the guide and the center line overlap. Tilting up makes verticals lean → step back and hold the camera level."),
                versus: ("日の丸も主役を真ん中に置きますが、両側が同じ形である必要はありません。シンメトリーは両側の形まで合わせるのが決まりです。",
                         "Centered (hinomaru) also puts the subject in the middle, but the sides need not match; symmetry asks both sides to mirror each other."))

        case .hinomaru:
            return Entry(
                what: ("画面の真ん中に小さな円（短い辺の約3分の1）と十字があります。主役をこの円の中に収めます。",
                       "A small circle (about a third of the short side) and a cross mark the center. Fit the subject inside the circle."),
                why: ("主役が真ん中にあると、目は迷わずそこへ向かいます。周りを静かにしておくほど、主役だけがはっきり見えます。",
                      "With the subject in the middle, the eye goes straight to it. The quieter the surroundings, the stronger it stands out."),
                steps: [("主役を1つだけ決めます（気球・花・灯籠など）。", "Choose a single subject: a balloon, a flower, a lantern."),
                        ("背景が無地に近くなる向き（空・水面・暗い林）を探します。", "Find an angle where the background is plain: sky, water, dark woods."),
                        ("主役を円の中に収め、十字に中心を合わせます。", "Fit it in the circle and center it on the cross."),
                        ("主役の周りに余白を残す大きさまで寄ったり引いたりします。", "Zoom or move until there is breathing room around it.")],
                scenes: ("青空に浮かぶ熱気球、雪の中の赤い鳥居、水面に浮かぶ一輪の蓮。", "A hot-air balloon in a clear sky, a red torii in snow, a single lotus on a pond."),
                mistakes: ("背景がにぎやかで主役が埋もれる → 背景が単純になる位置まで動くか、主役に寄って背景を小さくします。ただ真ん中にあるだけで退屈 → 主役の形や色がはっきりした物を選びます。",
                           "A busy background swallows the subject → move until the background is simple, or get closer. It feels static → choose a subject with a strong shape or color."),
                versus: ("シンメトリーは両側の形をそろえる構図、余白は主役を小さく端に置く構図です。日の丸は主役を真ん中で大きめに見せます。",
                         "Symmetry mirrors both sides; negative space keeps the subject small and off to one side. Centered composition shows the subject in the middle at a clear size."))

        case .horizon:
            return Entry(
                what: ("横線が1本あり、地平線や水平線をそこに重ねます。向きのボタンで「空を広く」（線が下から3分の1）と「地面を広く」（上から3分の1）を切り替えます。",
                       "A single horizontal line for the horizon. The orientation button switches between More sky (line a third from the bottom) and More ground (a third from the top)."),
                why: ("空と地面のどちらを主役にするかがはっきりし、見る人がどこを見ればいいか迷いません。真ん中で切るより、広い側に目が集まります。",
                      "It makes clear whether the sky or the land is the story, so viewers know where to look. The larger area draws more attention than a split down the middle."),
                steps: [("空と地面のどちらが面白いか見比べます（雲・夕焼けなら空、花畑・砂丘なら地面）。", "Decide which is more interesting: clouds or sunset for the sky, flowers or dunes for the ground."),
                        ("向きのボタンで見せたい側を広くします。", "Use the orientation button to give that side more room."),
                        ("地平線を線にぴったり重ね、傾いていないか水準器で確かめます。", "Lay the horizon on the line and check it is level."),
                        ("広い側に雲や模様など見どころが入るように少し向きを調整します。", "Adjust the angle so the larger side has something to look at.")],
                scenes: ("白い砂丘と大きな空、夕焼けの海岸、雲海の上の山並み、草原。", "White dunes under a big sky, a coast at sunset, mountains above a sea of clouds, open grassland."),
                mistakes: ("水平線が傾いている → 線に合わせ、それでも合わないときは水準器を使います。広くした側に何も無く寂しい → 雲や模様がある側を広くします。",
                           "The horizon tilts → align it with the line or use the level. The larger side is empty → give the room to the side with clouds or texture."),
                versus: ("三分割の横線と同じ高さですが、こちらは線を1本にして地平線だけに集中できます。上下を半分に分けたいときは二分割を使います。",
                         "It sits at the same height as the thirds lines but shows only one line, so you can focus on the horizon. For an even split, use halves."))

        case .grid4:
            return Entry(
                what: ("縦横を4等分した細かい格子（線が縦3本・横3本）です。主役を置く点というより、まっすぐさと間隔を確かめる物差しです。",
                       "A fine grid that divides the frame into four in each direction (three lines each way). It is a ruler for straightness and spacing more than a set of points."),
                why: ("線が多いので、建物の縦の線の傾き、窓や柱の間隔の乱れにすぐ気づけます。整った並びが崩れずに写ると、きちんとした印象になります。",
                      "With more lines you notice leaning verticals and uneven spacing at once. When a regular pattern is kept straight, the photo feels precise."),
                steps: [("並びのある物（窓・柱・棚）を正面から見る位置に立ちます。", "Stand square to a repeating pattern: windows, columns, shelves."),
                        ("いちばん長い縦の線と横の線を、近くの格子の線と平行にします。", "Make the longest vertical and horizontal edges parallel to the grid."),
                        ("窓や柱の間隔が格子のマスと同じように並ぶ位置まで前後に動きます。", "Move closer or farther until the pattern lines up evenly with the boxes."),
                        ("すべての線に合わせる必要はなく、端の数本がそろえば撮ります。", "You do not need to match every line; once the edges agree, shoot.")],
                scenes: ("ヨーロッパの集合住宅の窓、駅の天井の格子、本屋の棚、障子。", "Rows of apartment windows, a station's ceiling grid, bookstore shelves, shoji screens."),
                mistakes: ("見上げて撮って縦の線が上ですぼまる → 少し下がるか、カメラを水平に構えます。線の多さに惑わされて主役が無い → 並びの中に1つだけ違う物（開いた窓など）を探します。",
                           "Shooting upward makes verticals converge → step back and keep the camera level. Lots of lines but no subject → look for one thing that breaks the pattern, like an open window."),
                versus: ("方眼は正方形のマス、6×4 は縦長のマスです。4×4 は縦横とも4等分なので、マスは画面と同じ縦長の形になります。",
                         "The square grid uses true squares and 6×4 uses taller boxes. The 4×4 grid splits both directions into four, so each box has the frame's shape."))

        case .squareGrid:
            return Entry(
                what: ("縦を6等分し、横の線はマスが本物の正方形になる間隔で引いた方眼です。",
                       "The width is divided into six, and the horizontal lines are spaced so every box is a true square."),
                why: ("正方形のマスは縦と横の長さが同じなので、建物や看板が縦長・横長に歪んでいないか、傾いていないかを見比べやすくなります。",
                      "Square boxes have equal sides, which makes it easy to judge whether buildings or signs look stretched or tilted."),
                steps: [("建物やタイルなど、まっすぐな線のある物を見つけます。", "Find straight lines: buildings, tiles, signs."),
                        ("縦の線をマスの縦線に重ね、傾きを直します。", "Lay vertical edges on the grid's verticals to fix tilt."),
                        ("窓や扉の大きさをマスの数で数え、並びが均等に見える位置を探します。", "Count windows or doors in boxes to find where the spacing looks even."),
                        ("正方形に切り抜く予定なら、主役がマスのまとまりの中央に来るようにします。", "If you plan a square crop, center the subject on a block of boxes.")],
                scenes: ("タイル張りの壁、駅舎の正面、商店街の看板の並び、碁盤の目の街を見下ろした景色。", "Tiled walls, a station façade, rows of shop signs, a grid-plan city seen from above."),
                mistakes: ("マスの数が多くて構図が決まらない → 主役のまとまりだけを見て、他の線は傾きの確認だけに使います。",
                           "Too many boxes to decide on a layout → frame the main group and use the rest only to check for tilt."),
                versus: ("4×4 や 6×4 はマスが縦長になります。方眼は正方形なので、形の歪みを見たいときに向きます。",
                         "4×4 and 6×4 use tall boxes; the square grid keeps true squares, so it is better for spotting distortion."))

        case .tianzige:
            return Entry(
                what: ("田の字のように、外枠と真ん中の十字で画面を4つに分けます。習字の練習用紙（田字格）と同じ形です。",
                       "An outer frame and a center cross divide the frame like the Chinese character tián (field), the same layout as Chinese calligraphy practice paper."),
                why: ("真ん中の十字と四隅の枠が見えるので、主役が中心にあるか、四隅のどこかが重すぎたり空きすぎたりしていないかを比べやすくなります。",
                      "With the cross and frame visible, you can see at once whether the subject is centered and whether any corner is too heavy or too empty."),
                steps: [("主役を十字の交点か、その近くに置きます。", "Place the subject on or near the center cross."),
                        ("4つのマスに入る物の量を見比べます。", "Compare how much is in each of the four boxes."),
                        ("一つのマスだけ重いときは、向きを少し変えて釣り合わせます。", "If one box is much heavier, shift the angle to balance them."),
                        ("外枠の内側に大事な物を収め、端で切れないようにします。", "Keep important things inside the outer frame so nothing is cut at the edge.")],
                scenes: ("水辺の建物と映り込み、庭園の東屋、正面から見た塔、花のアップ。", "A waterside building and its reflection, a garden pavilion, a tower seen head-on, a close-up of a flower."),
                mistakes: ("十字に主役を置いたのに四隅の一つに明るい物があり目がそちらへ行く → 向きを変えてその物を外すか、反対のマスにも重さを置きます。",
                           "The subject is on the cross but a bright object in one corner pulls the eye → change the angle to remove it or add weight to the opposite box."),
                versus: ("二分割・十字と線は似ていますが、田字格は外枠も見えるので、端まで含めた釣り合いを見るのに向きます。米字格は対角線も加わります。",
                         "It resembles Halves / cross, but the visible outer frame helps you balance the edges too. The mizige grid adds diagonals."))

        case .mizige:
            return Entry(
                what: ("米の字のように、真ん中の十字と2本の対角線を重ねた線です。8本の線が中心で交わります。",
                       "Like the Chinese character mǐ (rice): a center cross plus both diagonals, so eight lines meet in the middle."),
                why: ("線がすべて中心へ集まるので、回廊・トンネル・放射状の模様のように、中心へ向かう形があると、目が自然に中心へ運ばれます。",
                      "All lines converge on the center, so corridors, tunnels and radiating patterns that follow them carry the eye straight in."),
                steps: [("中心へ向かう線を持つ場所（回廊・並木・天井の梁）を探します。", "Find lines heading to a center: a corridor, an avenue of trees, ceiling beams."),
                        ("消える点（線が集まる所）を真ん中の交点に合わせます。", "Put the vanishing point on the center crossing."),
                        ("両側の線が対角線に近い角度になるよう、前後に動きます。", "Move forward or back until the side lines run close to the diagonals."),
                        ("左右の高さがそろうよう、カメラを水平に保ちます。", "Keep the camera level so both sides match.")],
                scenes: ("寺の長い回廊、トンネル状の並木道、ドームの天井を真下から、駅のホーム。", "A long temple corridor, a tree tunnel, a dome looked at from directly below, a station platform."),
                mistakes: ("消える点が中心から外れ、片側だけ線が強くなる → 横へ動いて消える点を中心へ戻します。",
                           "The vanishing point drifts off-center and one side dominates → step sideways to bring it back."),
                versus: ("放射線は中心を端寄りにも動かせます。米字格は中心が真ん中に固定で、左右の釣り合いを見るのに向きます。",
                         "Radial lets you move the center off to the side; the mizige grid keeps it fixed in the middle and helps with left–right balance."))

        // MARK: 黄金比

        case .phiGrid:
            return Entry(
                what: ("黄金比（約1:0.618）で分けた縦横2本ずつの線です。線は端から約38%と62%の所にあり、三分割より少し真ん中に寄っています。",
                       "Two lines each way placed by the golden ratio (about 1 : 0.618): at roughly 38% and 62%, a little closer to the center than thirds."),
                why: ("主役を真ん中から少しだけずらすので、日の丸ほど止まった感じにならず、三分割ほど端に寄りません。落ち着きと動きの中間の置き方になります。",
                      "The subject moves only slightly off-center: less static than a centered shot, less pushed out than thirds."),
                steps: [("主役を1つ決めます。", "Choose a single subject."),
                        ("4つの交点のうち、主役が向かう先が広く空く点を選びます。", "Pick the crossing point that leaves room in the direction the subject faces or moves."),
                        ("地平線や長い線は、近いほうの横線に重ねます。", "Lay a horizon or long edge on the nearer horizontal line."),
                        ("三分割と見比べたいときは、構図を切り替えて同じ場所で撮り比べます。", "To compare with thirds, switch guides and shoot the same scene again.")],
                scenes: ("広い草原の小さな人影、湖畔の小屋、雪原の一本の木。", "A small figure in a wide meadow, a cabin by a lake, a lone tree in a snowfield."),
                mistakes: ("交点に置いたつもりでも主役が真ん中に近すぎ、日の丸と変わらない → 交点の外側へ少しずらすか、三分割に切り替えます。",
                           "The subject ends up so close to the center that it looks centered → nudge it outward or switch to thirds."),
                versus: ("三分割より線が内側にあります。「黄金比だから必ず美しい」というわけではないので、両方で撮って好きなほうを選んで構いません。",
                         "The lines sit inside the thirds lines. The golden ratio is not a guarantee of beauty—try both and keep the one you like."))

        case .goldenSpiral:
            return Entry(
                what: ("黄金比の長方形を正方形で切り分けていき、各正方形に4分の1の円をつないだ渦巻きの線です。渦の中心（目）は、縦持ちで左下の約28%・72%の所。向きのボタンで渦の位置を4通りに変えられます。",
                       "A spiral built by cutting a golden rectangle into squares and joining a quarter circle in each. Its center (the eye) sits about 28% across and 72% down in the default orientation; the button moves it to four positions."),
                why: ("大きな弧から小さな弧へと線が巻き込むので、写真の中の曲線（階段・波・道）が渦に沿っていると、目は外側から中心へ運ばれ、最後に主役で止まります。",
                      "The curve tightens from a wide arc to a small one. When a curve in the scene—stairs, a wave, a road—follows it, the eye is carried from the edge to the center and stops on the subject."),
                steps: [("らせん階段・巻いた波・曲がる道など、だんだん小さく巻いていく形を探します。", "Look for a shape that curls tighter as it goes: a spiral staircase, a breaking wave, a winding road."),
                        ("向きのボタンで、その形の巻き込む先と渦の目が同じ側に来る向きを選びます。", "Use the orientation button so the eye is on the side where the shape curls in."),
                        ("主役（階段の中心・人・花）を渦の目に合わせます。", "Put the subject—the stairwell's center, a person, a flower—on the eye."),
                        ("外側の大きな弧に、その形の外側の曲線が沿うまで寄ったり引いたりします。", "Zoom or move until the outer curve of the shape follows the large arc.")],
                scenes: ("らせん階段を真上から、海岸線の大きな弧と岬の灯台、巻き貝のような形の庭の小道。", "A spiral staircase from above, a sweeping bay ending at a lighthouse, a garden path that curls inward."),
                mistakes: ("渦の目に主役を置いたが、周りに渦に沿う曲線が無く、ただ端に寄っただけの写真になる → 曲線のある場所を選ぶか、三分割に切り替えます。渦の向きが形と逆 → 向きのボタンで回します。",
                           "The subject is on the eye but nothing in the scene follows the curve, so it just looks off-center → choose a place with a real curve, or use thirds. The spiral turns the wrong way → change the orientation."),
                versus: ("フィボナッチ格子は同じ正方形の区切りを直線で見せ、目の位置を探しやすくします。黄金螺旋は曲線の流れを合わせたいときに使います。「自然の巻き貝はみな黄金螺旋」という話は正確ではないので、形が合うかどうかで選びます。",
                         "The Fibonacci grid shows the same squares as straight lines and makes the eye easier to find; use the spiral when you want a curve to follow it. Not every shell is a golden spiral—choose it when the shape actually fits."))

        case .fibonacciGrid:
            return Entry(
                what: ("黄金螺旋と同じ正方形の区切りを、直線だけで描いたものです。大きな正方形から小さな正方形へと区切りが続き、いちばん小さい所が渦の目になります。",
                       "The same squares as the golden spiral, drawn as straight lines. The divisions shrink from a large square to tiny ones, ending at the eye."),
                why: ("区切りが奥へ進むほど小さくなるので、手前の広い場所から奥の狭い場所へ、段を踏むように目が進みます。曲線が無い景色でも使えます。",
                      "Each division is smaller than the last, so the eye steps from the wide area to the narrow one—useful even when the scene has no curves."),
                steps: [("手前が広く、奥へ行くほど狭くなる景色（階段・路地・扉の連なり）を探します。", "Find a scene that narrows as it recedes: stairs, an alley, a row of doorways."),
                        ("向きのボタンで、いちばん小さい区画が主役の側に来るようにします。", "Use the orientation button so the smallest box is on the subject's side."),
                        ("主役（奥の扉・人）をいちばん小さい区画に入れます。", "Place the subject—a far door, a person—in the smallest box."),
                        ("大きな区画の境の線に、壁や段の縁を合わせます。", "Line up walls or step edges with the larger dividing lines.")],
                scenes: ("階段の先の扉、石畳の路地の奥の人、城の門をいくつもくぐった先。", "A door at the top of stairs, a figure at the end of a cobbled lane, a gate seen through several gates."),
                mistakes: ("線が多く、どこに合わせるか分からない → いちばん大きい区切り2本と、目の位置だけを見ます。",
                           "Too many lines to know what to match → look only at the two largest divisions and the eye."),
                versus: ("黄金螺旋は同じ区切りを曲線で見せます。ファイグリッドは黄金比の線を縦横2本ずつだけ引いた、もっと単純な版です。",
                         "The golden spiral shows the same divisions as a curve; the phi grid is a simpler version with just two golden-ratio lines each way."))

        case .goldenTriangle:
            return Entry(
                what: ("画面の対角線を1本引き、残りの2つの角からその対角線へ直角に線を下ろします。直角に交わる2つの点（足）が主役の置き場所です。向きのボタンで右上がり・右下がりを切り替えます。",
                       "One diagonal across the frame, plus a line from each of the other two corners meeting it at a right angle. The two meeting points are where subjects go. Switch between rising and falling with the button."),
                why: ("長い対角線が画面に動きをつくり、短い線が主役へ目を導きます。三角形に分かれた面のそれぞれに、空・斜面・人のような要素を分けて置けます。",
                      "The long diagonal adds movement and the short lines lead to the subject. The frame splits into triangles, each a place for sky, slope or figure."),
                steps: [("画面を斜めに横切る線（斜面・稜線・屋根）を探します。", "Find a line crossing the frame diagonally: a slope, a ridge, a roof."),
                        ("その線が対角線に重なる向きを、向きのボタンで選びます。", "Choose the orientation whose diagonal matches it."),
                        ("主役を、短い線が対角線と交わる点のどちらかに置きます。", "Place the subject at one of the right-angle points."),
                        ("残りの三角形に、空や影など大きな面が収まるか確かめます。", "Check that the remaining triangles hold large calm areas such as sky or shadow.")],
                scenes: ("斜面に立つ人、斜めに伸びる寺の屋根と塔、雪の稜線を歩く登山者。", "A person on a hillside, a slanting temple roof and pagoda, a climber on a snowy ridge."),
                mistakes: ("斜めの線が対角線より緩く、画面の途中で消える → 立つ位置を低くするか、カメラを傾けずに斜めの線が長く見える場所へ動きます。",
                           "The slope is shallower than the diagonal and fades out halfway → lower your position or move to where the line runs longer, without tilting the camera."),
                versus: ("対角線は斜めの線だけ、ダイナミックシンメトリーは対角線と直角の線を両方向に引いた4点版です。黄金三角形はその片方だけを使います。",
                         "Diagonals shows only the slanting line; dynamic symmetry draws right-angle lines from both diagonals for four points. The golden triangle uses one side of that."))

        // MARK: 対角・幾何

        case .diagonals:
            return Entry(
                what: ("画面の角から角へ引いた斜めの線です。向きのボタンで、左上→右下・左下→右上・両方を切り替えます。",
                       "A line from corner to corner. The button switches between top-left to bottom-right, bottom-left to top-right, and both."),
                why: ("水平や垂直の線は静かに見え、斜めの線は動いているように見えます。道や斜面を対角線に重ねると、写真に勢いと奥行きが出ます。",
                      "Horizontal and vertical lines feel still; diagonals feel like motion. Laying a road or slope along a diagonal adds energy and depth."),
                steps: [("道・川・稜線・手すりなど、長い直線を探します。", "Find a long straight line: a road, a river, a ridge, a railing."),
                        ("その線が角から角へ通る位置に立ちます。", "Stand where the line runs from one corner to the other."),
                        ("合わないときは、向きのボタンで反対の斜めにします。", "If it runs the other way, switch the orientation."),
                        ("線の先（奥の端）に人や建物があれば、そこが目の止まる所になります。", "If something stands at the far end, that becomes where the eye stops.")],
                scenes: ("斜めに延びるスキー場の斜面、山の稜線、港の防波堤、坂道の町並み。", "A ski slope, a mountain ridge, a harbor breakwater, a hillside street."),
                mistakes: ("カメラを傾けて斜めにしただけで、建物まで傾いて見える → カメラは水平のまま、立つ位置を変えて線を斜めにします。",
                           "Tilting the camera to fake a diagonal makes buildings lean too → keep the camera level and change your position instead."),
                versus: ("45°の対角は画面の比率に関係なく45°の線、対角線は角と角を結ぶ線です。縦長の画面ではこちらのほうが急になります。",
                         "The 45° guide is always 45°; diagonals join the corners, so in a tall frame they are steeper."))

        case .thirdsDiagonals:
            return Entry(
                what: ("三分割の線（縦横2本ずつ）に、角と角を結ぶ対角線2本を重ねたものです。主役は三分割の交点に置き、斜めの線でそこへ目を導きます。",
                       "The thirds lines plus both corner-to-corner diagonals. The subject goes on a thirds crossing, and a diagonal leads the eye to it."),
                why: ("斜めの線は目を運ぶ道になり、交点の主役はその終点になります。手前から奥へ向かう線と主役がつながるので、奥行きと見どころが一枚で伝わります。",
                      "The diagonal is a path for the eye and the subject on the crossing is where it ends, so depth and the point of interest read together."),
                steps: [("手前から奥へ斜めに延びる線（桟橋・道・手すり）を探します。", "Find a line running diagonally into the scene: a pier, a road, a railing."),
                        ("その線が画面の角から入るように立つ位置を決めます。", "Position yourself so it enters from a corner."),
                        ("線の先にいる主役（人・舟・小屋）を、三分割の交点に合わせます。", "Place the subject at the end of the line on a thirds crossing."),
                        ("主役が向いている側に空きを残して撮ります。", "Leave space on the side the subject faces.")],
                scenes: ("湖へ延びる桟橋の先に座る人、田んぼのあぜ道の先の農家、坂道の上の教会。", "Someone sitting at the end of a lake pier, a farmhouse at the end of a field path, a church at the top of a hill street."),
                mistakes: ("斜めの線と主役がつながっていない（線の先に何も無い） → 線の先に主役が来るよう、立つ位置か主役を待つ場所を変えます。",
                           "The line and the subject do not connect—the line leads nowhere → change position, or wait until someone is at its end."),
                versus: ("三分割は交点だけ、対角線は斜めの線だけです。この構図は両方を使い、「線で導いて交点で止める」形にします。",
                         "Thirds gives only the crossings and diagonals only the slant; this guide combines them: lead with the line, stop on the crossing."))

        case .diagonal45:
            return Entry(
                what: ("四隅から、画面の上でちょうど45°の角度の線を引いたものです。縦長の画面では、線は向かいの角ではなく辺の途中に届きます。",
                       "Lines from each corner at exactly 45° on screen. In a tall frame they reach the opposite side rather than the far corner."),
                why: ("45°はいちばん「斜め」に見える角度で、階段・屋根・ケーブルなど、実際に45°前後の物と重ねると、線のそろった気持ちのいい写真になります。",
                      "Forty-five degrees reads as the most decisive slant. Matching it with stairs, roofs or cables near that angle makes the lines feel tidy."),
                steps: [("階段・屋根・橋のケーブルなど、斜めの線が45°に近い物を探します。", "Look for stairs, roofs or cables close to 45°."),
                        ("その線を四隅から伸びる線のどれかに重ねます。", "Lay that line on one of the corner guides."),
                        ("交わる線がもう1本あれば、それも別の45°の線に合わせます。", "If a second line crosses it, match that to another guide."),
                        ("交わった所に主役（人・窓）を置けると、目が止まる所になります。", "A subject where the lines cross gives the eye a place to rest.")],
                scenes: ("非常階段のジグザグ、山小屋の三角屋根、斜張橋のケーブル。", "The zigzag of fire escapes, a cabin's pitched roof, the cables of a cable-stayed bridge."),
                mistakes: ("線の角度がずれていて、45°の線と合わない → 立つ位置を左右に変えると、見える角度が変わります。",
                           "The angle does not match → moving left or right changes the apparent angle."),
                versus: ("対角線は角と角を結ぶので、画面の比率で角度が変わります。45°の対角は比率にかかわらず45°です。",
                         "Diagonals join corners, so their angle depends on the frame; this guide stays at 45°."))

        case .obliqueThirds:
            return Entry(
                what: ("対角線と平行な斜めの線で、画面を斜めの帯に三等分した、このアプリ独自の補助線です（よく知られた名前のある構図ではありません）。両方の斜めの向きの線があります。",
                       "An app-made guide: slanted lines parallel to the diagonals split the frame into three diagonal bands, in both directions. It is not a traditional named composition."),
                why: ("斜めの景色（棚田・砂丘の縁・斜めの影）を三つの帯に分けて見られるので、どこに区切りを置けば釣り合うかが分かりやすくなります。",
                      "Slanting scenes—terraces, dune edges, long shadows—can be judged in three bands, which helps you place the dividing lines in balance."),
                steps: [("斜めに走る境目（影と日なた・段々の縁）を探します。", "Find a slanting boundary: shadow and light, the edge of terraces."),
                        ("いちばん目立つ境目を、斜めの線のどれかに重ねます。", "Put the strongest one on one of the slanted lines."),
                        ("3つの帯のうち、1つに主役、残りに空や影などの静かな面が入るようにします。", "Let one band hold the subject and the others hold calmer areas."),
                        ("合わないときは、構図を「対角線」に切り替えて見比べます。", "If it does not fit, compare with the diagonals guide.")],
                scenes: ("斜めに重なる棚田、砂丘の稜線、ビルの影が斜めに落ちる広場。", "Stepped rice terraces, dune crests, a plaza crossed by long shadows."),
                mistakes: ("線が4本あり、全部に合わせようとして決まらない → 1本だけに合わせ、他は目安にします。",
                           "Trying to match all four lines → match one and treat the rest as hints."),
                versus: ("三分割は縦と横の帯、こちらは斜めの帯です。対角線は1本の斜め線で、帯には分けません。",
                         "Thirds makes upright bands; this makes slanted ones. Diagonals is a single line without bands."))

        case .dynamicSymmetry:
            return Entry(
                what: ("2本の対角線と、各角から対角線へ直角に引いた4本の線（逆対角）を重ねたものです。対角線と逆対角が交わる4つの点（目）が主役の置き場所です。",
                       "Both diagonals plus four lines from the corners meeting them at right angles (reciprocals). The four crossing points—the eyes—are where subjects go."),
                why: ("いくつもの斜めの向きが整理されるので、道・屋根・影が複数の向きに走る景色でも、どの線を何にそろえるかが決めやすくなります。目の点に主役があると、斜めの線がそこへ集まって見えます。",
                      "It organizes several slanting directions, so busy scenes with roads, roofs and shadows become easier to align. With a subject on an eye, the slanting lines appear to converge on it."),
                steps: [("景色の中のいちばん長い斜めの線を対角線に重ねます。", "Lay the longest slanting line in the scene on a diagonal."),
                        ("それと直角に近い線（交わる道・影）を逆対角に合わせます。", "Match a line roughly at right angles to it with a reciprocal."),
                        ("主役を4つの目のどれかに置きます。", "Place the subject on one of the four eyes."),
                        ("線を全部使う必要はありません。2〜3本がそろえば十分です。", "You do not need every line—two or three in agreement is enough.")],
                scenes: ("交差する坂道と建物の輪郭、斜面を登る人、斜めの屋根が重なる古い町並み。", "Crossing hill streets and building edges, a person climbing a slope, layered roofs in an old town."),
                mistakes: ("6本の線に全部合わせようとして構図が窮屈になる → 対角線1本と目の点1つから始め、合う線だけを足していきます。",
                           "Forcing all six lines makes the frame cramped → start with one diagonal and one eye, then add only the lines that fit."),
                versus: ("黄金三角形はこの線の片側だけを使った形です。アーマチュアは中点への線も加えた、さらに線の多い版です。",
                         "The golden triangle is one side of this guide; the armature adds lines to the midpoints for even more options."))

        case .armature:
            return Entry(
                what: ("対角線2本、辺の真ん中を結ぶひし形の4本、各角から向かいの辺の真ん中への8本、合わせて14本の線です。昔の絵の下描きに使われた線の網です。",
                       "Fourteen lines: two diagonals, a diamond joining the midpoints of the sides, and eight lines from each corner to the middle of the opposite sides—a network once used to lay out paintings."),
                why: ("いろいろな角度の線があるので、形の多い景色でも、どれか1〜2本に重なる線が見つかります。主役や視線がその線に乗ると、まとまって見えます。",
                      "With lines at many angles, almost any busy scene has one or two that fit. When shapes or gazes rest on them, the picture holds together."),
                steps: [("景色の中のいちばん目立つ線や形を1つ選びます。", "Pick the most noticeable line or shape in the scene."),
                        ("14本の中から、それに近い線を1本探して重ねます。", "Find the guide line closest to it and align them."),
                        ("主役を、その線と別の線が交わる点に置きます。", "Put the subject where that line crosses another."),
                        ("残りの線は無視して構いません。", "Ignore the rest.")],
                scenes: ("斜張橋のケーブル、市場の屋台の屋根、人が多い広場。", "Cable-stayed bridge cables, market stall roofs, a busy square."),
                mistakes: ("線が多すぎて画面が見えにくい → 線の濃さを下げるか、シンプルな構図に切り替えます。",
                           "Too many lines to see the scene → lower the line opacity or switch to a simpler guide."),
                versus: ("ダイナミックシンメトリーより線が多く、中点への線があるぶん、画面の真ん中寄りにも置き場所が増えます。",
                         "It has more lines than dynamic symmetry; the midpoint lines add placement options nearer the center."))

        case .rootRectangle:
            return Entry(
                what: ("縦横の比が √2（約1.41）の枠を明るく見せ、その中に対角線と逆対角の線を引いたものです。後で √2 に切り抜く前提で、枠の中だけで構図を決めます。",
                       "A bright √2 (about 1.41) frame with diagonals and reciprocals drawn inside. Compose within it, planning to crop to √2 later."),
                why: ("√2 の長方形は、半分に折っても同じ形になる比率（A4 の紙と同じ）です。印刷や額装で使いやすく、枠の中の線で主役の置き場所も決めやすくなります。",
                      "A √2 rectangle keeps its shape when folded in half, like A4 paper, which makes it convenient for prints and frames; the inner lines help with placement."),
                steps: [("暗い外側は気にせず、明るい枠の中だけを見ます。", "Ignore the dim area and look only inside the bright frame."),
                        ("主役を枠の中の線が交わる点に置きます。", "Place the subject where lines cross inside the frame."),
                        ("長い斜めの線を枠の中の対角線に合わせます。", "Lay a long slanting line on the inner diagonal."),
                        ("撮った写真は切り抜かれないので、編集で √2 に切り抜きます。", "The photo is saved uncropped; crop it to √2 when editing.")],
                scenes: ("富士山と五重塔、細長い塔と山、A4 に印刷したい風景。", "Mount Fuji and a pagoda, a slim tower with mountains, a landscape you want to print on A4."),
                mistakes: ("暗い外側に大事な物を置いてしまい、切り抜くと消える → 主役は必ず明るい枠の中に収めます。",
                           "Something important sits in the dim area and disappears after cropping → keep it inside the bright frame."),
                versus: ("比率の枠（3:2・2:1など）は枠だけ、ルート長方形は枠の中にダイナミックシンメトリーの線も入ります。",
                         "The ratio frames show only the frame; the root rectangle also adds dynamic-symmetry lines inside."))

        // MARK: 配置と形

        case .triangle:
            return Entry(
                what: ("3つの点を結んだ三角形の破線です。上の頂点は真ん中の上寄り、下の2点は左右の下寄り。向きのボタンで逆さの三角形にもできます。",
                       "A dashed triangle joining three points: the apex near the top center and two base points low on each side. The button flips it upside down."),
                why: ("下が広い三角形は、山のように重さが下にあるので安定して見えます。逆さの三角形は不安定に見え、緊張感が出ます。3つの点を結ぶように目が回るので、写真の中をゆっくり見てもらえます。",
                      "A triangle with a wide base looks settled, like a mountain; inverted, it looks unstable and tense. The eye travels between the three points, so viewers linger."),
                steps: [("三角形の形をした物（山・屋根・ピラミッド）か、3つの主役（3人・3本の木）を探します。", "Find a triangular shape—a mountain, a roof, a pyramid—or three subjects such as three people or trees."),
                        ("いちばん高い所を上の頂点に合わせます。", "Put the highest point on the apex."),
                        ("下の2つの点に、形の裾か残りの2つの主役を合わせるよう前後に動きます。", "Move closer or farther until the base or the other two subjects meet the lower points."),
                        ("不安や動きを出したいときは、向きのボタンで逆さにします。", "For tension, flip to the inverted triangle.")],
                scenes: ("ピラミッドや三角屋根の山小屋、とがった山（マッターホルンなど）、記念写真の3人。", "A pyramid or A-frame hut, a sharp peak like the Matterhorn, three friends in a group photo."),
                mistakes: ("3つの点の大きさがそろいすぎて、どれが主役か分からない → 1つを手前に置くなど、大きさに差をつけます。三角形が画面からはみ出す → 一歩下がります。",
                           "All three points are the same size, so nothing leads → bring one closer to vary the sizes. The triangle spills out of the frame → step back."),
                versus: ("黄金三角形は斜めの線で画面を三角に分ける線の構図で、この三角は「形」や「3つの主役」をつなぐ構図です。",
                         "The golden triangle divides the frame with lines; this guide connects a shape or three subjects."))

        case .radial:
            return Entry(
                what: ("1つの点から8方向に伸びる破線です。中心の点は向きのボタンで、真ん中と三分割の4つの交点の、計5か所に動かせます。",
                       "Dashed lines radiating in eight directions from one point. The button moves that point to the center or any of the four thirds crossings."),
                why: ("線路・道・光の筋のように、線が1点へ集まると、目は線に沿って自然にその点へ向かいます。そこに主役を置くと、強く引きつけられます。",
                      "When tracks, roads or light rays converge, the eye follows them to the meeting point; a subject there gets strong attention."),
                steps: [("線が1点へ集まる場所（線路・並木・天井の梁・光の筋）を探します。", "Find lines that meet at a point: tracks, avenues, ceiling beams, sunbeams."),
                        ("集まる点がどこに来るとよいかを決め、向きのボタンで中心の位置を合わせます。", "Decide where the meeting point should be and set the center with the button."),
                        ("集まる点を中心の点に重ねます。", "Overlap the meeting point with the guide's center."),
                        ("その点に主役（人・塔・太陽）があると、さらに強くなります。", "A subject there—a person, a tower, the sun—makes it even stronger.")],
                scenes: ("森の中へ消える線路、桜並木の道、ドームの天井、雲間から差す光。", "Tracks disappearing into a forest, a cherry-tree avenue, a domed ceiling, sunbeams through clouds."),
                mistakes: ("線は集まっているのに、その先に何も無く物足りない → 人が来るのを待つか、集まる点に光や建物が来る位置へ動きます。",
                           "The lines converge on nothing → wait for someone to step in, or move so light or a building sits there."),
                versus: ("トンネルは周りを囲む形、放射線は線が集まる形です。米字格は中心が真ん中に固定です。",
                         "Tunnel surrounds the subject; radial converges on it. The mizige grid fixes the center in the middle."))

        case .tunnel:
            return Entry(
                what: ("画面の内側に大きな楕円（端から12%内側）と、真ん中の点があります。楕円に沿って手前の物で周りを囲み、奥の主役を真ん中に置きます。",
                       "A large oval (12% in from the edges) and a center point. Surround the frame with something in the foreground along the oval and place the far subject in the middle."),
                why: ("手前の暗い囲みと奥の明るい主役の差で、距離の違い（奥行き）がはっきりします。囲みが周りの余計な物を隠し、目は真ん中へ集まります。",
                      "The dark foreground ring against a bright far subject makes depth obvious. The ring hides clutter and steers the eye to the center."),
                steps: [("トンネル状の物（鳥居の連なり・木のアーチ・洞窟）を探します。", "Find something tunnel-like: rows of torii, arching trees, a cave mouth."),
                        ("その出口や奥の主役を真ん中の点に合わせます。", "Put the exit or far subject on the center point."),
                        ("囲みの縁が楕円に沿うまで前後に動きます。", "Move until the edges of the opening follow the oval."),
                        ("奥の明るさに合わせて明るさを下げ、外が白く飛ばないようにします。", "Lower the exposure for the bright far end so it does not blow out.")],
                scenes: ("伏見稲荷の千本鳥居、藤棚や竹林のトンネル、海岸の洞窟から見る海。", "The torii tunnel at Fushimi Inari, a wisteria or bamboo tunnel, the sea from a sea cave."),
                mistakes: ("奥が白く飛んで何があるか分からない → 奥の明るい所を押して明るさを合わせます。囲みが片側だけ → 真ん中に立ち直します。",
                           "The far end is blown out → tap it to set exposure. The ring is only on one side → re-center yourself."),
                versus: ("額縁は四角い枠（窓・門）で囲み、トンネルは丸く奥へ続く形で囲みます。放射線は囲まずに線が集まる構図です。",
                         "Frame within a frame uses a rectangular opening; tunnel uses a rounded one that recedes. Radial converges without enclosing."))

        case .frameWithin:
            return Entry(
                what: ("画面の内側に角の丸い四角（端から12%内側）があります。窓・門・アーチなど手前の物を外側の枠に使い、内側に奥の景色を収めます。",
                       "A rounded rectangle 12% in from the edges. Use a window, gate or arch in the foreground as the outer frame and place the far scene inside."),
                why: ("手前の枠が「どこから見ているか」を伝え、奥の景色との距離が見えて奥行きが出ます。枠の外の余計な物も隠せます。",
                      "The foreground frame shows where you are standing and creates depth against the scene beyond; it also hides distractions."),
                steps: [("窓・門・アーチ・木の枝など、枠になる物を探します。", "Find something to frame with: a window, gate, arch or branches."),
                        ("枠の縁が四角の線に沿う位置まで前後に動きます。", "Move until its edges follow the rectangle."),
                        ("奥の主役（海・塔・庭）を枠の内側の真ん中か三分割の交点に置きます。", "Place the far subject in the middle or on a thirds point inside."),
                        ("ピントは奥の主役に合わせ、手前の枠は少しぼけても構いません。", "Focus on the far subject; a slightly soft frame is fine.")],
                scenes: ("寺の書院の柱越しの庭、城の門越しの街、窓越しの海と舟、円窓。", "A garden seen between temple pillars, a town through a castle gate, the sea through a window, a round moon window."),
                mistakes: ("枠の内側が明るすぎて白く飛ぶ → 内側の景色を押して明るさを合わせます。枠が片側にしか無い → 一歩横へ動いて両側を入れます。",
                           "The inside is blown out → tap the view to set exposure. The frame is on one side only → step sideways to include both."),
                versus: ("トンネルは丸く奥へ続く囲み、額縁は手前の四角い開口部です。",
                         "Tunnel is a rounded enclosure that recedes; this is a rectangular opening in the foreground."))

        case .negativeSpace:
            return Entry(
                what: ("三分割の交点の1つに小さな四角（短い辺の12%）があります。主役をこの小さな四角に収め、残りを広い余白（空・海・雪原）にします。向きのボタンで四角の位置を4か所に変えられます。",
                       "A small square (12% of the short side) on one thirds crossing. Fit the subject in it and leave the rest as open space—sky, sea, snow. The button moves it to four positions."),
                why: ("主役が小さいほど、周りの広さが伝わります。何も無い場所があると目はそこで休み、最後に小さな主役へ戻ってきます。静けさや孤独を表すのにも向きます。",
                      "A small subject makes the space around it feel vast. Empty areas rest the eye and lead it back to the subject, which suits quiet or solitary moods."),
                steps: [("空・海・雪・砂など、模様の少ない広い場所を探します。", "Find a large, plain area: sky, sea, snow, sand."),
                        ("小さな主役（人・舟・灯台）を1つ決めます。", "Choose one small subject: a person, a boat, a lighthouse."),
                        ("向きのボタンで、主役が向かう先に余白が広がる位置を選びます。", "Use the button so the open space lies in the direction the subject faces."),
                        ("主役を小さな四角に収め、余白に余計な物が入らないか確かめます。", "Fit the subject in the square and check the space is clean.")],
                scenes: ("広い海の小さな灯台、雪原を歩く人、霧の中の一艘の舟、夕暮れの空と鳥。", "A small lighthouse in a wide sea, a figure crossing snow, a lone boat in fog, a bird against an evening sky."),
                mistakes: ("余白に電線や人が入って目が散る → 向きを変えて余白を本当に空にします。主役が小さすぎて見つからない → 色や明るさで目立つ主役を選びます。",
                           "Wires or people in the empty area distract → change the angle until it is truly clear. The subject is too small to find → choose one that stands out by color or brightness."),
                versus: ("三分割も交点に主役を置きますが、余白は主役を「小さく」して広さを見せるのが違いです。日の丸は主役を真ん中に大きめに置きます。",
                         "Thirds also uses a crossing, but negative space keeps the subject small to show scale. Centered places it larger in the middle."))

        case .lShape:
            return Entry(
                what: ("縦の線と横の線が直角につながったL字の破線です。縦は左寄り（22%）、横は下寄り（80%）。向きのボタンで左右・上下を反転できます。",
                       "A dashed L: a vertical line near the left (22%) joined to a horizontal line near the bottom (80%). The button mirrors it left–right or top–bottom."),
                why: ("縦の物（木・塔）と横の物（地平線・道）が角でつながると、画面の2辺に重さが寄り、残りの広い面が落ち着いた余白になります。",
                      "When something vertical meets something horizontal at a corner, the weight sits along two edges and the remaining area becomes calm space."),
                steps: [("縦に伸びる物（一本の木・塔・柱）と、横に伸びる物（地平線・道・岸）を探します。", "Find something vertical—a tree, a tower, a pillar—and something horizontal—a horizon, road or shore."),
                        ("縦の物をL字の縦の線に、横の物を横の線に重ねます。", "Lay them on the L's vertical and horizontal lines."),
                        ("向きのボタンで、空けたい側（空・海）が広くなる向きにします。", "Use the button so the side you want open—sky, sea—is large."),
                        ("2つの線が交わる角の近くに主役があると、目が止まります。", "A subject near the corner gives the eye a place to stop.")],
                scenes: ("草原の一本の木と地平線、海辺の灯台と岸、駅のホームの柱と線路。", "A lone tree and the horizon, a lighthouse and shoreline, a platform pillar and tracks."),
                mistakes: ("縦の物が画面の真ん中にあり、Lにならない → 横へ動いて端へ寄せます。",
                           "The vertical element is in the middle, so there is no L → move sideways to push it toward the edge."),
                versus: ("額縁は四辺を囲み、L字は二辺だけで支えます。三分割の線に縦横の物を置いた形と近いですが、L字は2つの線がつながっていることを大切にします。",
                         "Frame within a frame encloses all four sides; the L uses only two. It resembles placing things on thirds lines, but here the two lines must connect."))

        case .zShape:
            return Entry(
                what: ("上の横線→左下への斜め線→下の横線とつながったZ字の破線です。向きのボタンで左右を反転できます。",
                       "A dashed Z: a top line, a diagonal down to the left, and a bottom line. The button mirrors it."),
                why: ("目は左から右へ進み、斜めに折り返し、また右へ進みます。折り返しながら奥へ進むので、長い道のりや広い景色の奥行きが伝わります。",
                      "The eye moves across, doubles back on the diagonal, then across again—zigzagging deeper into the scene, which conveys distance and depth."),
                steps: [("折り返しながら奥へ続く物（つづら折りの道・川・階段）を探します。", "Find something that zigzags into the distance: a switchback road, a river, stairs."),
                        ("手前の曲がりを下の線、奥の曲がりを上の線に合わせます。", "Put the near bend on the bottom line and the far bend on the top line."),
                        ("向きのボタンで、斜めの部分が実際の道と同じ向きになるようにします。", "Use the button so the diagonal matches the real direction."),
                        ("道の上に車や人がいると、大きさの比較になり奥行きが増します。", "A car or person on the route adds scale.")],
                scenes: ("山のつづら折りの道、段々に流れる川、丘の上へ続く坂道。", "A switchback mountain road, a stepped river, a lane climbing a hill."),
                mistakes: ("道が一度しか曲がっておらず、Zにならない → 高い所から見下ろすと曲がりが増えて見えます。",
                           "The road bends only once → a higher viewpoint often reveals more bends."),
                versus: ("S字はなめらかな曲線、Z字は角のある折り返しです。",
                         "The S curve is smooth; the Z has sharp turns."))

        case .sCurve:
            return Entry(
                what: ("上から下へ、2回ゆるやかに曲がるS字の破線です。向きのボタンで左右を反転できます。",
                       "A dashed S that bends gently twice from top to bottom. The button mirrors it."),
                why: ("なめらかな曲線は、目をゆっくり手前から奥へ運びます。直線より柔らかく、川や道の流れ、ゆったりした時間を感じさせます。",
                      "A smooth curve carries the eye slowly from front to back. It feels softer than a straight line and suggests flow and an unhurried pace."),
                steps: [("2回曲がる川・道・海岸線を探します（高い所から見るとS字が見つかりやすい）。", "Look for a river, road or shoreline that bends twice—higher viewpoints help."),
                        ("手前の曲がりを画面の下、奥の曲がりを上の曲がりに合わせます。", "Match the near bend to the lower curve and the far bend to the upper one."),
                        ("向きのボタンで曲がる向きをそろえます。", "Flip the guide so it bends the same way."),
                        ("曲線の始まりが画面の下の端から入るようにします。", "Let the curve enter from the bottom edge.")],
                scenes: ("紅葉の森を抜ける道を上から、蛇行する川、海岸線の入り江。", "A road through autumn woods from above, a meandering river, a winding coastline."),
                mistakes: ("曲線が画面の途中で途切れる → 少し引いて、始まりから終わりまで入れます。",
                           "The curve is cut off midway → step back to include it from start to end."),
                versus: ("C字は1回だけ大きく曲がり、主役を包みます。S字は2回曲がって奥へ導きます。Z字は角のある折り返しです。",
                         "The C curve bends once and wraps the subject; the S bends twice and leads inward; the Z turns at sharp corners."))

        case .cCurve:
            return Entry(
                what: ("画面の片側で大きく1回曲がるC字の破線です。向きのボタンで左右を反転できます。",
                       "A dashed C that bends once along one side. The button mirrors it."),
                why: ("大きな曲線が画面の中を包むので、内側にある物（町・舟・人）に目が集まります。曲線の外側が余白になり、まとまりのある写真になります。",
                      "The broad curve wraps the frame and gathers attention on what lies inside it—a town, a boat, a person—while the outside becomes calm space."),
                steps: [("弧を描く海岸・湾・道・川の曲がりを探します。", "Find an arc: a bay, a curved road, a river bend."),
                        ("その弧をC字の線に沿わせます。", "Lay the arc along the C."),
                        ("向きのボタンで、弧のふくらむ側をそろえます。", "Flip the guide so it bulges the same way."),
                        ("弧の内側に主役（町並み・舟・灯台）を置きます。", "Place the subject inside the arc: a town, a boat, a lighthouse.")],
                scenes: ("湾曲する海岸線、川の曲がりに沿った町、円形の広場。", "A curved coastline, a town along a river bend, a round plaza."),
                mistakes: ("弧が浅く、ほとんど直線に見える → 高い所から見下ろすか、広く写せる位置へ下がります。",
                           "The arc is shallow and looks straight → find a higher viewpoint or step back."),
                versus: ("S字は2回曲がって奥へ導き、C字は1回の弧で内側を包みます。黄金螺旋は巻き込みながら1点へ向かいます。",
                         "The S bends twice to lead inward; the C wraps with a single arc; the golden spiral curls toward one point."))

        // MARK: 比率の枠

        case .square:
            return Entry(
                what: ("縦横が同じ長さ（1:1）の枠を明るく、外側を暗く見せます。枠の中には真ん中の十字があります。撮った写真は切り抜かれず、後で編集で正方形にします。",
                       "A bright 1:1 frame with a center cross; the rest is dimmed. The photo is saved uncropped—make it square when editing."),
                why: ("正方形には長い辺が無いので、目が横や縦に流れず、真ん中に集まりやすくなります。中央に置いた主役や、左右対称の形が落ち着いて見えます。",
                      "A square has no long side, so the eye does not drift sideways or up and down; it settles toward the center, which suits centered or symmetrical subjects."),
                steps: [("暗い外側を無視して、明るい正方形の中だけを見ます。", "Ignore the dim area; look only inside the square."),
                        ("主役を真ん中の十字か、その近くに置きます。", "Place the subject on or near the center cross."),
                        ("正方形の四隅に余計な物が入らないか確かめます。", "Check the four corners for clutter."),
                        ("撮った後、編集で正方形に切り抜きます。", "Crop to a square afterward.")],
                scenes: ("建物の正面、丸いステンドグラス、皿の料理を真上から、花のアップ。", "A building façade, a round stained-glass window, food from above, a flower close-up."),
                mistakes: ("暗い外側に主役の一部がはみ出して、切り抜くと欠ける → 枠の中に収めます。",
                           "Part of the subject sits in the dim area and is lost when cropped → keep it inside the frame."),
                versus: ("4:5 は少し縦長、9:16 はもっと縦長です。正方形は縦横の差が無く、中央に置く構図に向きます。",
                         "4:5 is slightly tall and 9:16 much taller; the square has no bias and suits centered layouts."))

        case .ratio4x5:
            return Entry(
                what: ("縦横の比が4:5の縦長の枠を明るく見せます。撮った写真は切り抜かれず、後で編集で 4:5 にします。",
                       "A bright 4:5 portrait frame. The photo is saved uncropped—crop to 4:5 later."),
                why: ("SNS の縦長の投稿でよく使われる比率で、画面いっぱいに大きく表示されます。3:4 より少しだけ横が広く、縦の景色に横の余裕も残せます。",
                      "It is a common portrait ratio for social posts, so the photo fills more of the screen. It is slightly wider than 3:4, keeping a little sideways room."),
                steps: [("明るい枠の中だけで構図を決めます。", "Compose inside the bright frame only."),
                        ("縦に伸びる主役（塔・人・滝）を枠の中で大きく入れます。", "Fill the frame with a vertical subject: a tower, a person, a waterfall."),
                        ("上下の端（空・足元）に余計な物が無いか確かめます。", "Check the top and bottom edges."),
                        ("編集で 4:5 に切り抜きます。", "Crop to 4:5 when editing.")],
                scenes: ("古い町並みの路地、縦長の滝、人物の全身。", "An old-town lane, a tall waterfall, a full-length portrait."),
                mistakes: ("上下を詰めすぎて塔の先や足が切れる → 少し下がって余白を残します。",
                           "Cutting off the top of a tower or someone's feet → step back to leave room."),
                versus: ("正方形より縦長、9:16 より横が広い、中間の比率です。撮る画面の 3:4 とほぼ同じ形なので、切り抜いても失う部分が少なくて済みます。",
                         "It sits between the square and 9:16. It is close to the camera's 3:4 shape, so little is lost when you crop."))

        case .ratio9x16:
            return Entry(
                what: ("縦横の比が9:16のとても縦長な枠を明るく見せます。撮った写真は切り抜かれず、後で編集で 9:16 にします。",
                       "A bright 9:16 frame, very tall. The photo is saved uncropped—crop to 9:16 later."),
                why: ("スマートフォンの画面いっぱいの比率で、ストーリーや壁紙に使えます。高さが強調され、塔や木の高さ、上から下への流れが伝わります。",
                      "It fills a phone screen, ideal for stories and wallpapers. Height is emphasized, so tall towers and top-to-bottom flows stand out."),
                steps: [("縦に長い物（塔・滝・並木）を選びます。", "Choose something tall: a tower, a waterfall, a row of trees."),
                        ("主役を明るい枠の中で、上か下の3分の1あたりに置きます。", "Place the subject around the upper or lower third inside the frame."),
                        ("ストーリーに使うなら、上下の端に文字が乗る場所を空けておきます。", "If it is for stories, leave space at the top and bottom for text."),
                        ("編集で 9:16 に切り抜きます。", "Crop to 9:16 when editing.")],
                scenes: ("見上げる塔、縦に落ちる滝、細い路地と空。", "A tower from below, a falling waterfall, a narrow alley and sky."),
                mistakes: ("横に広い景色を無理に入れて、主役が小さくなる → 縦に長い主役を選ぶか、16:9 に切り替えます。",
                           "Forcing a wide scene into it makes everything small → choose a tall subject or switch to 16:9."),
                versus: ("16:9 はこの枠を横にしたもの、4:5 はもっと横の広い縦長です。",
                         "16:9 is this frame turned sideways; 4:5 is a wider portrait."))

        case .ratio16x9:
            return Entry(
                what: ("縦横の比が16:9の横長の枠を明るく見せます。縦持ちでは枠が細い帯になるので、横持ちで撮ると画面を広く使えます。撮った写真は切り抜かれません。",
                       "A bright 16:9 landscape frame. In portrait it becomes a thin band, so turn the phone sideways to use more of the sensor. The photo is saved uncropped."),
                why: ("テレビや映画と同じ横長の比率で、横に広がる景色や、人の動く向きが伝わります。",
                      "The same wide shape as TV and film, it conveys panoramas and sideways movement."),
                steps: [("横に広がる景色（山並み・海岸・街の夜景）を選びます。", "Choose a wide scene: mountain ranges, a coastline, a city at night."),
                        ("できれば横持ちにして、明るい枠を大きくします。", "Turn the phone sideways if you can to enlarge the frame."),
                        ("地平線を枠の中の上か下の3分の1に置きます。", "Put the horizon on the upper or lower third inside the frame."),
                        ("編集で 16:9 に切り抜きます。", "Crop to 16:9 when editing.")],
                scenes: ("横に連なる山並み、長い海岸線、橋の全景、街の夜景。", "A mountain range, a long shoreline, a whole bridge, a city skyline at night."),
                mistakes: ("縦持ちのまま撮り、帯が細くて細部が小さくなる → 横持ちに変えます。",
                           "Shooting in portrait leaves a thin strip with tiny details → rotate to landscape."),
                versus: ("9:16 はこの枠を縦にしたものです。3:2・2:1 などはまとめて「3:2・2:1・XPan・√2」にあります。",
                         "9:16 is this frame turned upright; 3:2, 2:1 and others are under 3:2 · 2:1 · XPan · √2."))

        case .otherRatios:
            return Entry(
                what: ("向きのボタンで、3:2・2:1・XPan（65:24）・√2 の枠を切り替えて明るく見せます。どれも撮った写真は切り抜かれず、後で編集で切り抜きます。",
                       "Switch between 3:2, 2:1, XPan (65:24) and √2 frames with the button. The photo is saved uncropped; crop later."),
                why: ("比率が変わると、同じ景色でも伝わり方が変わります。3:2 はカメラの標準に近く自然、2:1 や XPan は横に長く映画のような広がり、√2 は印刷しやすい比率です。",
                      "The same scene reads differently at each ratio: 3:2 feels natural, 2:1 and XPan feel cinematic and wide, √2 suits printing."),
                steps: [("撮る景色の広がりに合う比率を、向きのボタンで選びます。", "Pick a ratio that suits the scene with the button."),
                        ("明るい枠の中だけで主役と地平線の位置を決めます。", "Place the subject and horizon inside the bright frame."),
                        ("横長の比率は、縦持ちだと帯が細くなるので横持ちにします。", "For wide ratios, turn the phone sideways."),
                        ("編集で同じ比率に切り抜きます。", "Crop to the same ratio when editing.")],
                scenes: ("雪の旧市街を XPan で横長に、港の夕景を 2:1 で、旅のスナップを 3:2 で。", "A snowy old town in XPan, a harbor sunset at 2:1, travel snapshots at 3:2."),
                mistakes: ("比率を変えたのに主役の位置を直さず、端で切れる → 比率を変えたら枠の中を見直します。",
                           "Changing the ratio without re-checking the subject leaves it cut at the edge → recompose after switching."),
                versus: ("1:1・4:5・9:16・16:9 はそれぞれ別の項目にあります。ルート長方形は √2 の枠に線も入った版です。",
                         "1:1, 4:5, 9:16 and 16:9 have their own entries; the root rectangle is √2 with guide lines inside."))

        // MARK: 機種の格子

        case .grid6x4:
            return Entry(
                what: ("一部のカメラにある 6×4 の格子です。縦持ちでは回して、縦4列・横6段のマスになります。",
                       "The 6×4 grid found on some cameras. In portrait it rotates to four columns and six rows."),
                why: ("三分割より細かく、方眼ほど多くない格子なので、傾きと間隔を見ながら、主役の置き場所も選べます。",
                      "Finer than thirds but lighter than the square grid, it lets you check tilt and spacing while still choosing a placement."),
                steps: [("建物や並びのある景色を選びます。", "Choose a scene with structure or repetition."),
                        ("縦の線と横の線を格子の線と平行にします。", "Make vertical and horizontal edges parallel to the grid."),
                        ("主役を格子の交わる点のどれかに置きます。", "Place the subject on one of the crossings."),
                        ("いつも使っているカメラと同じ線で撮りたいときに選びます。", "Use it when you want the same lines as your other camera.")],
                scenes: ("窓の並ぶ集合住宅、整然とした畑、駅の天井。", "An apartment block with rows of windows, orderly fields, a station ceiling."),
                mistakes: ("縦持ちで線が回ったことに気づかず、間隔が合わない → 縦持ちでは縦4列・横6段と覚えておきます。",
                           "Not noticing the grid rotated in portrait → remember it becomes four columns and six rows."),
                versus: ("4×4 は縦横とも4等分、方眼は正方形のマスです。6×4 は横長の写真で6列×4段になる格子です。",
                         "4×4 splits both ways into four; the square grid uses squares; 6×4 is six by four in landscape."))

        case .level:
            return Entry(
                what: ("端末の傾きに合わせて動く横線です。水平に近づくと線が太くなります。",
                       "A horizontal line that moves with the phone's tilt and thickens as you approach level."),
                why: ("水平線や建物がわずかに傾いているだけで、写真全体が落ち着かなく見えます。撮る前に水平を合わせると、後で切り抜いて直す手間も、そのぶん写真が小さくなることも避けられます。",
                      "Even a slight tilt makes a photo feel uneasy. Leveling before you shoot saves straightening later—and the crop that comes with it."),
                steps: [("海や湖の水平線、建物の床の線など、水平であるはずの線を見つけます。", "Find a line that should be level: a sea horizon, a floor line."),
                        ("端末をゆっくり左右に傾け、線が太くなる所で止めます。", "Tilt the phone slowly until the line thickens."),
                        ("その傾きのまま、主役の位置を決めます。", "Hold that angle and compose."),
                        ("手が揺れるなら、肘を体につけるか、物に寄りかかります。", "Brace your elbows or lean on something if your hands shake.")],
                scenes: ("海の水平線、湖の対岸、駅のホーム、建物の正面。", "A sea horizon, a far lakeshore, a station platform, a façade."),
                mistakes: ("水準器では水平なのに、斜面や坂のせいで景色が傾いて見える → 景色の中のまっすぐな線（建物の縦の線など）を優先して合わせます。",
                           "The phone is level but the scene looks tilted because of a slope → align with a reliable straight line, such as a building's vertical."),
                versus: ("水平線の構図は地平線の高さを決める線、水準器は傾きを確かめる道具です。一緒に使うと確かです。",
                         "The horizon guide sets the horizon's height; the level checks tilt. Use them together."))
        }
    }
    // swiftlint:enable function_body_length line_length
}
