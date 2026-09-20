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
 *  3. **`@MainActor` の型の静的メンバを、テストから呼んでいる**
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

// 3. @MainActor の型の静的メンバをテストから呼んでいないか
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
