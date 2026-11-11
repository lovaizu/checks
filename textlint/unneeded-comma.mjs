// The textlint rule ja-no-unneeded-comma, which finds a comma (、) after the
// clause at the head of a sentence, where the clause can modify only one
// part of the rest of the sentence. A comma marks a break in the
// structure of a sentence, so there it marks nothing that the reader
// doesn't already see, as in 設定は、利用側が決めます. Issue #20 holds the
// reason.
//
// A comma stays where the word right after it could modify both a
// predicate inside the rest and the one at its end, as 急いで of
// 彼は、急いで走る犬を追った: the comma tells which one it modifies.
//
// check.mjs loads the rule with the modules of textlint: the default
// export takes the function require of those modules, and returns the rule.

// The thresholds come from Japanese that people and AI wrote, as the pull
// request of issue #20 says: up to them, nearly each sentence that the rule
// finds reads better without the comma.
const defaults = {
  // The most characters of the clause at the head, before the comma.
  maxHead: 30,
  // The most characters of the sentence, without its spaces.
  maxSentence: 60,
};

// The particles that end a clause at the head: は and も, で and に, ので
// and て. A noun or a list before a comma, such as 本日、 or A、B, isn't
// such a clause.
const headEnds = new Set(["係助詞", "格助詞", "接続助詞", "副助詞"]);

const isPredicate = (t) => ["動詞", "形容詞", "助動詞"].includes(t.pos);

// Whether token $t, of the rest of the sentence after the comma, ends a
// clause before the predicate of the sentence, by the token $u after it.
// A predicate followed by a noun is a clause that modifies the noun, and one
// followed by a particle such as ので, か or と is a clause too. A predicate
// followed by an auxiliary, or by a verb after its 連用形, as in 速くなる
// and 書き直す, is a part of the same predicate.
function endsClause(t, u) {
  if (isPredicate(t)) {
    if (u.pos === "助動詞") return false;
    if (u.pos === "動詞" && (u.pos_detail_1 === "非自立" || /^連用/.test(t.conjugated_form))) return false;
    if (u.pos === "形容詞" && u.pos_detail_1 === "非自立") return false;
    if (u.pos === "名詞" && u.pos_detail_1 === "接尾") return false;
    if (u.pos === "助詞" && (u.pos_detail_1 === "終助詞" || (u.pos_detail_1 === "接続助詞" && /^[てで]$/.test(u.surface_form)))) return false;
    return true;
  }
  if (t.pos === "助詞" && t.pos_detail_1 === "接続助詞") {
    // て before a verb that serves it, as in している and してください.
    return !(/^[てで]$/.test(t.surface_form) && u.pos === "動詞" && u.pos_detail_1 === "非自立");
  }
  return false;
}

// Whether the word right after the comma, the first of $rest, could modify
// both a predicate inside the rest of the sentence and the one at its end.
// Such a word modifies a predicate: an adverb, or a verb or an adjective
// that doesn't modify the noun after it. The predicate at the end is a
// verb or an adjective, as a noun, such as 状態 of よい状態です, takes no
// such word.
function eitherPredicate(rest) {
  const serves = (t) => ["助動詞", "助詞"].includes(t.pos) || ["非自立", "接尾"].includes(t.pos_detail_1);
  let from = 1;
  if (rest[0].pos === "動詞" || rest[0].pos === "形容詞") {
    while (from < rest.length && serves(rest[from])) from++;
    if (rest[from]?.pos === "名詞") return false;
  } else if (rest[0].pos !== "副詞") return false;
  const end = rest.findLastIndex((t) => !serves(t));
  if (end < from || !["動詞", "形容詞"].includes(rest[end].pos)) return false;
  for (let i = from; i < end; i++) {
    if (endsClause(rest[i], rest[i + 1])) return true;
  }
  return false;
}

// The heads that link the sentence to the one before it, such as 一方で,
// ほかに, その上で, まだその上に, 続けて, 最後に, 第3に and 反対に. The comma
// after them marks that link.
function isConnective(head) {
  if (head[head.length - 1].pos_detail_1 === "係助詞") return false;
  const words = head.slice(0, -1).filter((t) => !["連体詞", "接頭詞", "副詞"].includes(t.pos));
  if (words.length !== 1) return false;
  const [w] = words;
  return w.pos === "接続詞" || w.pos_detail_1 === "副詞可能" || w.pos_detail_1 === "非自立" || w.pos_detail_1 === "数" || w.pos_detail_1 === "形容動詞語幹" || ["最後", "最初"].includes(w.surface_form) || (w.pos === "動詞" && head.length === 2);
}

// The particles of a clause that a contrast or another reason follows, as
// in 速いが、高い and 速いし、安い.
const contrasts = new Set(["が", "のに", "けど", "けれど", "けれども", "ものの", "し"]);

// A topic or a subject. A head with one, and that ends in で, is a
// predicate of its own, as in 振込は自動で、通常は3営業日. A head with a
// topic, where the rest of the sentence has a topic too, sets two side by
// side, as in Aは付録Aに、Bは付録Bに and Aについては、Bでは. One that ends in
// て, where the rest has a subject too, joins two clauses, as in
// 血が流れて、彼は即死した.
const isSubject = (t) => t.pos === "助詞" && ((t.pos_detail_1 === "係助詞" && /^[はも]$/.test(t.surface_form)) || (t.pos_detail_1 === "格助詞" && t.surface_form === "が"));

// Whether the word before the comma and the word after it are the same,
// as in 事実は、事実として, or the same verb, as in 直すと、直し, where
// the comma keeps them apart.
function sameWord(head, rest) {
  const content = (t) => ["名詞", "動詞", "形容詞"].includes(t.pos);
  const a = [...head].reverse().find(content);
  const b = rest.find(content);
  if (!a || !b) return false;
  const stem = (t) => t.surface_form.match(/^\p{Script=Han}+(?=\p{Script=Hiragana})/u)?.[0];
  return (a.basic_form !== "*" && a.basic_form === b.basic_form) || (stem(a) !== undefined && stem(a) === stem(b));
}

const opens = /[「『（(［\[【〈《]/g;
const closes = /[」』）)］\]】〉》]/g;
const bare = (s) => s.replace(/[\s。．.!?！？]/g, "");

// The first comma of sentence $text, with the tokens $tokens of kuromoji:
// {comma, head, sentence, keep}, or null where the sentence has no comma.
// comma is its index, head the number of characters before it, and
// sentence that of the sentence, without spaces. keep names what makes the
// comma one that the sentence may need, if anything. Only the first comma
// of a sentence can follow the clause at its head.
export function firstComma(text, tokens) {
  const words = tokens.filter((t) => t.pos !== "記号" || t.surface_form === "、");
  const at = words.findIndex((t) => t.surface_form === "、");
  if (at < 0) return null;
  const comma = words[at].word_position - 1;
  const fact = (keep) => ({ comma, head: bare(text.slice(0, comma)).length, sentence: bare(text).length, keep });
  const head = words.slice(0, at);
  const rest = words.slice(at + 1);
  if (head.length === 0 || rest.length === 0) return fact("edge");
  if (text.slice(comma + 1).includes("、")) return fact("comma");
  // A comma inside brackets, such as 「設定は、」, isn't one of the sentence.
  const before = text.slice(0, comma);
  if ((before.match(opens) || []).length !== (before.match(closes) || []).length) return fact("bracket");
  const last = head[head.length - 1];
  if (last.pos !== "助詞" || !headEnds.has(last.pos_detail_1)) return fact("head");
  if (isConnective(head)) return fact("connective");
  if (last.pos_detail_1 === "接続助詞" && contrasts.has(last.surface_form)) return fact("contrast");
  const topic = head.slice(0, -1).some(isSubject);
  if (topic && last.surface_form === "で") return fact("predicate");
  const isTopic = (t) => t.pos === "助詞" && t.pos_detail_1 === "係助詞" && t.surface_form === "は";
  if (head.some(isTopic) && last.pos_detail_1 !== "接続助詞" && rest.some(isTopic)) return fact("parallel");
  if (topic && /^[てで]$/.test(last.surface_form) && last.pos_detail_1 === "接続助詞" && rest.some(isSubject)) return fact("clauses");
  if (sameWord(head, rest)) return fact("repeat");
  if (eitherPredicate(rest)) return fact("either");
  return fact(null);
}

// The index in $text of each comma that the sentence doesn't need, with
// the thresholds of $options.
export function unneededCommas(text, tokens, options = {}) {
  const { maxHead, maxSentence } = { ...defaults, ...options };
  const first = firstComma(text, tokens);
  return first && !first.keep && first.head <= maxHead && first.sentence <= maxSentence ? [first.comma] : [];
}

export default (require) => {
  const { tokenize } = require("kuromojin");
  const { splitAST, SentenceSplitterSyntax } = require("sentence-splitter");
  const { StringSource } = require("textlint-util-to-string");
  return (context, options = {}) => {
    const { Syntax, RuleError, report, locator } = context;
    return {
      async [Syntax.Paragraph](node) {
        const sentences = splitAST(node).children.filter((child) => child.type === SentenceSplitterSyntax.Sentence);
        for (const sentence of sentences) {
          // Code reads as a word of the sentence, by the mask of each of its
          // characters.
          const source = new StringSource(sentence, {
            replacer: ({ node: child, maskValue }) => (child.type === Syntax.Code ? maskValue("_") : undefined),
          });
          const text = source.toString();
          if (!text.includes("、")) continue;
          for (const index of unneededCommas(text, await tokenize(text), options)) {
            const at = sentence.range[0] - node.range[0] + source.originalIndexFromIndex(index);
            report(
              node,
              new RuleError("文頭の節のあとの読点です。この節がかかる先は一つしかないので、読点は文の切れ目を示していません。読点を消した文のほうが読みやすいなら、消してください。", {
                padding: locator.range([at, at + 1]),
              }),
            );
          }
        }
      },
    };
  };
};
