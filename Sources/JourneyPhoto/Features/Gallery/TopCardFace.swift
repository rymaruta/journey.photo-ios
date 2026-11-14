import SwiftUI

/// ホームの上の札の面（写真つきの横長カード・v2 Main の板）。2026-11-12 に `HomeTopCardView` から切り出した——
/// 探すの「今日の一問」の段（`SearchView`）も同じ面を使う（今日の一問をホームの札から探すへ移した・案 第10章）。
/// 寸法の値は今までどおり `HomeTopCardView`（`cardHeight`・`lineLimit`・`photoWidth`）が持つ
struct TopCardFace: View {
    let eyebrow: String
    let eyebrowLabel: String
    let title: String
    let line: String
    let detail: String?
    /// 写真の出典の行（撮影スポット・今日の一問の写真）。あれば `detail` の代わりに出す（`TopCardCredit`・2026-11-14 判断）
    var credit: TopCardCredit? = nil
    let backdrop: Photo?
    var backdropURL: URL? = nil
    /// ①現像前の旅の札（2026-11-12 札 #543）: 左の写真の代わりに置く、色を抜いたフィルムの3コマ（端末の写真の id）。
    /// 空なら写真（`backdrop`・`backdropURL`）を置く
    var film: [String] = []
    var trailingSymbol: String = "chevron.right"
    var detailTruncation: Text.TruncationMode = .middle
    /// 旅行プランの札（右上に「⋯」を重ねる・`tripCardMenu`）。眉と題をその下に潜らせない（`HomeTopCardView.menuReserve`）
    var reservesMenu: Bool = false
    /// 横にめくる並びの中か（外の余白を持たず、並びの高さいっぱいに伸びる）
    var inCarousel: Bool = false

    var body: some View {
        // **v2（2026-10-14・Main の板「上の札を写真つきの横長カードに」）**:
        // 左に写真（幅 112・札の高さいっぱい・薄めない）、右に 眉（真鍮＋消える線）→ 明朝の題 →
        // 12 の text-2 の一行 → 出典。地は札の面（#0E0E0F）に白 8% の縁・角 16。
        // 以前は写真を右に 35% の薄さで敷き、題は明朝 26 だった。写真を薄めずに置けるので、
        // 字を写真の上に重ねない（真鍮の眉を黒地の上に置ける・CLAUDE.md）
        HStack(alignment: .center, spacing: 0) {
            if film.isEmpty {
                cardPhoto(backdrop: backdrop, backdropURL: backdropURL)
            } else {
                cardFilm(film)
            }
            HStack(alignment: .center, spacing: JPSpace.xs) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    // 英字の眉は読み上げでは日本語で（今日のテーマの札と同じ）
                    JPEyebrowLine(eyebrow, spoken: eyebrowLabel)
                        .padding(.trailing, reservesMenu ? HomeTopCardView.menuReserve : 0)
                    // **#417 ③（2026-10-30 owner 採用）: 題・一行・出典は1行ずつ**（背を板の 116 に）。
                    // 2行まで許していた間は、並びの背が一番高い札（出典の2行）に揃って 156 になり、
                    // 下の写真の一覧が押し下がっていた。切れた全文は読み上げで読める（札は1つの要素）
                    Text(title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(HomeTopCardView.lineLimit)
                        .padding(.trailing, reservesMenu ? HomeTopCardView.menuReserve : 0)
                    Text(line)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(HomeTopCardView.lineLimit)
                    if let credit {
                        creditLine(credit)
                    } else if let detail {
                        // **1行。** 並びは背を揃えるので、1枚が高くなると全部の札が高くなり、
                        // 下の写真の一覧が押し下がる。写真の出典はここを通らない（上の `creditLine`・2026-11-14）
                        Text(detail)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(HomeTopCardView.lineLimit)
                            // 既定は真ん中で切る。当日モードは末尾で切る
                            // （名前が長くても、先頭の「明日 · 名前 · ゴールデンアワー」を残す）
                            .truncationMode(detailTruncation)
                            // UI テストのときだけ: 渡された幅と要る幅を値に出す（`TopCardProbe`・2026-11-14）
                            .modifier(TopCardDetailProbe(title: title, detail: detail))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: trailingSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityHidden(true)
            }
            .padding(.leading, JPSpace.m)
            .padding(.trailing, JPSpace.s)
            .padding(.vertical, JPSpace.s)
            // 並びの中では高さいっぱい（隣の札と背を揃える）・文字は上に寄せる
            .frame(maxWidth: .infinity, maxHeight: inCarousel ? .infinity : nil,
                   alignment: inCarousel ? .topLeading : .leading)
        }
        .frame(maxWidth: .infinity, minHeight: HomeTopCardView.cardHeight,
               maxHeight: inCarousel ? .infinity : nil, alignment: .leading)
        // UI テストのときだけ: 札の背を値に出す（`TopCardProbe`・2026-11-14）
        .modifier(TopCardHeightProbe(title: title))
        .jpCardFace()
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .accessibilityElement(children: .combine)
        .padding(.horizontal, inCarousel ? 0 : JPSpace.gutter)
    }

    /// 写真の出典の1行（**2026-11-14 判断**・`TopCardCredit`）。札の背も行の数も変えず、出典の頭を必ず見せる。
    /// 入る最初の形を出す: 地域＋出典 → 県＋出典 → 出典だけ → 作者の後ろだけを切る（ライセンス名は先に幅を取って残す）。
    /// 前は1本の字を真ん中で切り、ちょうど「写真: 作者」が消えていた。
    /// 読み上げは形にかかわらず全文（地域と出典）。全文は札を押した先（`SpotImageCredit`）にリンクつきで出ている
    private func creditLine(_ credit: TopCardCredit) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(credit.wholeLines, id: \.self) { line in
                Text(line)
                    .lineLimit(HomeTopCardView.lineLimit)
            }
            HStack(spacing: 0) {
                Text(credit.author)
                    .lineLimit(HomeTopCardView.lineLimit)
                    .truncationMode(.tail)
                Text(credit.licenseTail)
                    .lineLimit(HomeTopCardView.lineLimit)
                    .layoutPriority(1)
            }
        }
        .font(JPFont.caption)
        .foregroundStyle(WebTheme.text3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(credit.spoken)
        // UI テストのときだけ: 行の幅と各形の要る幅・残った頭を値に出す（`TopCardProbe`・2026-11-14）
        .modifier(TopCardCreditProbe(title: title, credit: credit))
    }

    /// 札の左の写真。**写真の無い札（旅行プラン・旅の最中）は置かない**——空の枠を作らない
    @ViewBuilder
    private func cardPhoto(backdrop: Photo?, backdropURL: URL?) -> some View {
        if let backdrop {
            RemoteImage(url: backdrop.gridImageURL, alignment: backdrop.gridAlignment)
                .frame(width: HomeTopCardView.photoWidth)
                .frame(maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        } else if let backdropURL {
            // 撮影スポット・今日の一問の写真（`Photo` ではない）。出典は右の字に出す
            RemoteImage(url: backdropURL)
                .frame(width: HomeTopCardView.photoWidth)
                .frame(maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        }
    }

    /// ①現像前の旅の札の左: 色を抜いた3コマ（章「帯の3コマは色を抜いた表紙」）。幅は写真と同じ 112
    private func cardFilm(_ ids: [String]) -> some View {
        VStack(spacing: 2) {
            ForEach(ids, id: \.self) { id in
                LibraryShotImage(id: id, side: 112)
                    .saturation(0.35)
                    .brightness(-0.22)
                    .colorMultiply(Color(red: 1, green: 0.9, blue: 0.74))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(width: HomeTopCardView.photoWidth)
        .frame(maxHeight: .infinity)
        .background(Color.black)
        .clipped()
        .accessibilityHidden(true)
    }
}
