#!/usr/bin/env node
/**
 * Swift の**構文**だけを機械で検査する。
 *
 * この作業環境には Swift ツールチェーンが無い（`download.swift.org` も
 * GitHub のリリース資産も、ネットワークポリシーで遮断されている）。
 * 型検査はできないが、**構文の壊れ**は tree-sitter で見つけられる。
 * 手で書いて一度もコンパイルしていないコードでは、ここが唯一の自動検査。
 *
 * **これが緑でも「ビルドが通る」とは言えない。** 見ているのは括弧の対応や
 * 宣言の形までで、型・名前解決・SwiftUI の ViewBuilder の制約は見ていない。
 *
 *     cd Tools && npm install     # tree-sitter と tree-sitter-swift
 *     node check-swift-syntax.js ../Sources ../Tests
 */
const fs = require("fs");
const path = require("path");

let Parser, Swift;
try {
    Parser = require("tree-sitter");
    Swift = require("tree-sitter-swift");
} catch (e) {
    console.error("tree-sitter が入っていません。Tools/ で `npm install` してください。");
    process.exit(2);
}

const roots = process.argv.slice(2);
if (roots.length === 0) {
    console.error("使い方: node check-swift-syntax.js <ディレクトリ...>");
    process.exit(2);
}

function walkFiles(dir, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walkFiles(full, out);
        else if (entry.name.endsWith(".swift")) out.push(full);
    }
    return out;
}

/** ERROR ノードと「足りない」ノードを集める */
function findProblems(node, out = []) {
    if (node.type === "ERROR" || node.isMissing) {
        out.push({
            kind: node.isMissing ? "MISSING" : "ERROR",
            line: node.startPosition.row + 1,
            column: node.startPosition.column + 1,
            text: node.text.split("\n")[0].slice(0, 80),
        });
        // ERROR の下は当てにならないので降りない
        return out;
    }
    for (let i = 0; i < node.childCount; i++) findProblems(node.child(i), out);
    return out;
}

const parser = new Parser();
parser.setLanguage(Swift);

let files = 0;
let broken = 0;
for (const root of roots) {
    for (const file of walkFiles(root)) {
        files++;
        // **解析器がまだ読めない書き方を先に外す。** `nonisolated(unsafe)` は
        // Swift 5.10 で入った指定で、tree-sitter-swift 0.7 は解析に失敗する
        // （本物のコンパイラは通る）。誤報で緑が濁ると検査を見なくなるので、
        // 意味を変えない範囲で落としてから読む
        const source = fs.readFileSync(file, "utf8")
            .replace(/\bnonisolated\(unsafe\)\s+/g, "")
            // **条件付きコンパイルの行を落としてから読む。** `#if` で属性だけを
            // 囲む書き方（`#if !SWIFT_PACKAGE` + `@main`）を解析器が読めない。
            // 両方の枝を残すと意味は重複するが、見ているのは構文だけなので困らない
            .replace(/^[ \t]*#(if|elseif|else|endif)\b.*$/gm, "");
        const tree = parser.parse(source);
        if (!tree.rootNode.hasError) continue;
        broken++;
        console.log(`\n${path.relative(process.cwd(), file)}`);
        for (const problem of findProblems(tree.rootNode)) {
            console.log(`  ${problem.line}:${problem.column} ${problem.kind}  ${problem.text}`);
        }
    }
}

console.log(`\n${files} ファイル / 構文が壊れている ${broken} ファイル`);
process.exit(broken === 0 ? 0 : 1);
