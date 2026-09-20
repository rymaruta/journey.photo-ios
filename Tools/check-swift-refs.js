#!/usr/bin/env node
/**
 * 型検査の代わりに、**落ちる原因が決まっているもの**だけを見る。
 *
 * コンパイラが無いので型は見られない。ただし SwiftUI で実行時に落ちる形は
 * 種類が限られていて、そのうち2つは構文木から機械で見つけられる:
 *
 *  1. **配られていない `@EnvironmentObject`**
 *     画面が要求する型が、どこからも `.environmentObject(...)` で
 *     配られていないと、その画面を開いた瞬間に落ちる。コンパイルは通る。
 *  2. **同じ型を2か所で宣言している**
 *     これはコンパイルエラーだが、ファイルをまたぐと目で気づけない。
 *  3. **画面に出る文字が日本語だけになっている**
 *     Web 版は ja / en の2つを持つ。片方だけの文字列を足すと、英語の端末で
 *     そこだけ日本語が残る。`L("ja", "en")` か `Labels.*` を通すこと。
 *  4. **`Text` に渡す実行時の文字列に Markdown を書いている**
 *     `Text("**太字**")` が太字になるのは**文字列リテラル**のときだけ。
 *     `L(…)` の戻り値（ただの String）では記号がそのまま見える。
 *  5. **`@MainActor` の型の静的メンバを、テストから呼んでいる**
 *     `XCTestCase` のメソッドは isolation を持たないので
 *     "Call to main actor-isolated static method in a synchronous
 *     nonisolated context" でコンパイルが落ちる。実際に2回踏んだ。
 *
 *     node Tools/check-swift-refs.js Sources
 */
const fs = require("fs");
const path = require("path");
const Parser = require("tree-sitter");
const Swift = require("tree-sitter-swift");

const roots = process.argv.slice(2);
if (roots.length === 0) {
    console.error("使い方: node check-swift-refs.js <Sources> [Tests]");
    process.exit(2);
}
const [sourceRoot, testRoot] = roots;

function walkFiles(dir, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walkFiles(full, out);
        else if (entry.name.endsWith(".swift")) out.push(full);
    }
    return out;
}

const parser = new Parser();
parser.setLanguage(Swift);

const files = walkFiles(sourceRoot);

/** 宣言された型 → 宣言したファイル（複数なら重複） */
const declaredIn = new Map();
/** `@EnvironmentObject var x: T` の T → 使っているファイル */
const required = new Map();
/** `.environmentObject(expr)` の expr（識別子） */
const injectedExpressions = new Set();
/** `let/var name = Type(` の name → Type（同じファイル内で解決するため） */
const bindings = new Map();

const problems = [];

for (const file of files) {
    const source = fs.readFileSync(file, "utf8");
    const tree = parser.parse(source);

    // 宣言（ネストした型は `A.B` ではなく素の名前で見る。重複の見落としより
    // 誤検知の方が困るので、ネストは名前に親を付けて区別する）
    (function collect(node, prefix) {
        for (let i = 0; i < node.childCount; i++) {
            const child = node.child(i);
            const kind = child.type;
            // **関数の中の型は数えない。** `func f() { struct Body: Encodable {...} }`
            // は関数ごとに別物で、同じ名前が何度あってもよい（実際、送信する
            // 本文の型を各メソッドに置いている）
            if (kind === "function_declaration" || kind === "init_declaration"
                || kind === "deinit_declaration" || kind === "subscript_declaration") {
                continue;
            }
            if (kind === "class_declaration" || kind === "protocol_declaration") {
                // **`extension` は数えない。** 解析器は `extension` も
                // `class_declaration` として返すので、そのままだと
                // 「同じ型を2回宣言している」と誤報になる
                if (child.text.startsWith("extension")) { collect(child, prefix); continue; }
                const nameNode = child.childForFieldName("name");
                if (nameNode) {
                    const full = prefix ? `${prefix}.${nameNode.text}` : nameNode.text;
                    const list = declaredIn.get(full) ?? [];
                    list.push(file);
                    declaredIn.set(full, list);
                    collect(child, full);
                    continue;
                }
            }
            collect(child, prefix);
        }
    })(tree.rootNode, "");

    // 正規表現で足りるところは正規表現で見る（構文木の型名がバージョンで変わる）
    for (const match of source.matchAll(/@EnvironmentObject\s+(?:private\s+)?var\s+\w+\s*:\s*([A-Za-z_][\w.]*)/g)) {
        const list = required.get(match[1]) ?? [];
        list.push(path.relative(process.cwd(), file));
        required.set(match[1], list);
    }
    for (const match of source.matchAll(/\.environmentObject\(\s*([A-Za-z_]\w*)\s*\)/g)) {
        injectedExpressions.add(match[1]);
    }
    for (const match of source.matchAll(/(?:@StateObject|@State|let|var)\s+(?:private\s+)?var?\s*([a-z]\w*)\s*(?::\s*[\w<>\[\], ?]+)?\s*=\s*([A-Z]\w*)\s*\(/g)) {
        bindings.set(match[1], match[2]);
    }
}

// 3. 画面に出る文字が二言語になっているか
{
    // 文字を受け取る口。ここに日本語の直書きがあれば、英語の端末で日本語が残る
    const uiCall = /\b(Text|Button|Label|TextField|SecureField|Toggle|Section|Picker|Link|navigationTitle|alert)\(\s*"([^"]*[\u3040-\u30ff\u4e00-\u9faf][^"]*)"/g;
    for (const file of files) {
        // 模型と、値だけを持つ層は対象外（画面に出ない）
        if (!file.includes("/Features/") && !file.includes("/App/")) continue;
        const source = fs.readFileSync(file, "utf8");
        for (const match of source.matchAll(uiCall)) {
            problems.push(
                `${path.relative(process.cwd(), file)}: 「${match[2]}」が日本語だけです` +
                `（L("…", "…") か Labels.* を通してください）`
            );
        }
    }
}

// 4. 実行時の文字列に Markdown を書いていないか
{
    const markdownInRuntimeText = /Text\(\s*(?:L\(|Labels\.)[^)]*\*\*/g;
    for (const file of files) {
        const source = fs.readFileSync(file, "utf8");
        for (const match of source.matchAll(markdownInRuntimeText)) {
            problems.push(
                `${path.relative(process.cwd(), file)}: Text に渡す実行時の文字列に ` +
                `Markdown（**）があります（リテラルでないので記号がそのまま見えます）`
            );
        }
    }
}

// 4.5 UIKit の記号を、import 無しで使っていないか
//
// **他のフレームワークから透けて見えることに頼らない。** `import SwiftUI` や
// `import PhotosUI` だけでも UIKit の型が見えることがある（ObjC のモジュールが
// 再輸出するため）が、それは保証ではない。手元（Linux）は Shims/SwiftUI が
// `UIImage` の別名を持っているので必ず通り、**Xcode で初めて
// "cannot find 'UIImage' in scope" になる**種類の間違い。
{
    const uikitSymbols = /\b(UIImage|UIApplication|UIScreen|UIPasteboard|UIDevice|UIColor|UIViewController|UIView|UIFont)\b/;
    for (const file of files) {
        const source = fs.readFileSync(file, "utf8");
        const code = source.split("\n").filter((line) => !line.trim().startsWith("//")).join("\n");
        const found = code.match(uikitSymbols);
        if (found && !/^import UIKit$/m.test(source)) {
            problems.push(
                `${path.relative(process.cwd(), file)}: ${found[1]} を使っていますが ` +
                `import UIKit がありません（手元では Shims が肩代わりするので通り、Xcode で落ちます）`
            );
        }
    }
}

// 4.6 ストーリーを「必ず画像」として描いていないか
//
// **ストーリーは写真とは限らない**（Web は mp4 を受ける）。
// `RemoteImage` に動画の URL を渡すと、読み込みに失敗して**真っ黒のまま**
// になる——落ちないので気づけない。動画かどうかを見る場所は
// `StoryMedia.swift` の1か所に寄せてある。
{
    for (const file of files) {
        if (!file.includes("/Features/Stories/")) continue;
        if (file.endsWith("StoryMedia.swift")) continue;
        const source = fs.readFileSync(file, "utf8");
        if (/RemoteImage\(\s*url:\s*story\./.test(source)) {
            problems.push(
                `${path.relative(process.cwd(), file)}: ストーリーを RemoteImage で直接描いています` +
                `（動画のストーリーが真っ黒になります。StoryMedia / StoryThumb を使ってください）`
            );
        }
    }
}

// 4.7 入力と突き合わせる語を、日本語に固定していないか
//
// **その人の言葉で打たせる。** 退会の確認は「削除」と打たせていたので、
// 英語の端末には「Type “削除” to confirm」と出ていた——日本語入力を
// 持たない人は**アプリから退会できない**（審査 5.1.1(v) を見るのは
// たいてい英語の審査官）。比べる語は `L(…)` を通す。
{
    const japaneseLiteral = /(==|!=)\s*"[^"]*[\u3040-\u30ff\u4e00-\u9faf][^"]*"/;
    for (const file of files) {
        if (!file.includes("/Features/") && !file.includes("/App/")) continue;
        const source = fs.readFileSync(file, "utf8");
        const found = source.match(japaneseLiteral);
        if (found) {
            problems.push(
                `${path.relative(process.cwd(), file)}: 入力と ${found[0].trim()} を直接比べています` +
                `（日本語を打てない端末で詰みます。L("…", "…") を通してください）`
            );
        }
    }
}

// 5. @MainActor の型の静的メンバをテストから呼んでいないか
if (testRoot) {
    const mainActorTypes = new Set();
    for (const file of files) {
        const source = fs.readFileSync(file, "utf8");
        for (const match of source.matchAll(
            /@MainActor\s*(?:\n\s*)?(?:public\s+|internal\s+|private\s+|final\s+)*(?:class|struct|enum|actor)\s+([A-Z]\w*)/g
        )) {
            mainActorTypes.add(match[1]);
        }
    }
    for (const file of walkFiles(testRoot)) {
        const source = fs.readFileSync(file, "utf8");
        const isMainActorTest = /@MainActor\s*(?:final\s+)?class/.test(source);
        if (isMainActorTest) continue;
        for (const match of source.matchAll(/\b([A-Z]\w*)\.[a-z]\w*\s*\(/g)) {
            if (mainActorTypes.has(match[1])) {
                problems.push(
                    `${path.relative(process.cwd(), file)} が @MainActor の ` +
                    `${match[1]} の静的メンバを呼んでいます` +
                    `（XCTestCase は isolation を持たないのでコンパイルが落ちます）`
                );
            }
        }
    }
}

// 1. 配られていない EnvironmentObject
const injectedTypes = new Set();
for (const name of injectedExpressions) {
    const type = bindings.get(name);
    if (type) injectedTypes.add(type);
}
for (const [type, users] of required) {
    if (!injectedTypes.has(type)) {
        problems.push(
            `@EnvironmentObject の ${type} がどこからも配られていません` +
            `（開いた瞬間に落ちます）: ${[...new Set(users)].join(", ")}`
        );
    }
}

// 2. 同じ型を2か所で宣言していないか
for (const [name, where] of declaredIn) {
    if (where.length > 1) {
        problems.push(`${name} が複数のファイルで宣言されています: ${where.map((f) => path.relative(process.cwd(), f)).join(", ")}`);
    }
}

if (problems.length > 0) {
    for (const problem of problems) console.log(`NG  ${problem}`);
    process.exit(1);
}
console.log(`参照の検査: 問題なし（${files.length} ファイル / 配られている型 ${injectedTypes.size} / 要求している型 ${required.size}）`);
