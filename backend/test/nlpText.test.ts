import { test } from "node:test";
import assert from "node:assert/strict";
import { damerau, escapeLike, expandQuery, fuzzyScore, fuzzyTerms, needsFuzzy, normalize, snippetAround, stem, stemTokens, synonymsOf, tokenize, tsQueryText } from "../src/nlp/text.js";
import { keywordQuery } from "../src/retrieval/search.js";

test("normalize: NFKC, lowercase, diacritics", () => {
  assert.equal(normalize("  Café   Münster "), "cafe munster");
  assert.equal(normalize("ＦＵＬＬ　ｗｉｄｔｈ"), "full width");
  assert.equal(normalize("ﬁne"), "fine"); // ligature
  assert.equal(normalize("Ünïcödé"), "unicode");
});

test("tokenize is code-aware", () => {
  assert.deepEqual(tokenize("getUserByID"), ["get", "user", "by", "id"]);
  assert.deepEqual(tokenize("HTTPServerError"), ["http", "server", "error"]);
  assert.deepEqual(tokenize("snake_case_name"), ["snake", "case", "name"]);
  assert.deepEqual(tokenize("kebab-case-name"), ["kebab", "case", "name"]);
  assert.deepEqual(tokenize("src/utils/text.test.ts"), ["src", "utils", "text", "test", "ts"]);
  assert.deepEqual(tokenize("utf8Decoder2"), ["utf", "8", "decoder", "2"]);
  assert.deepEqual(tokenize("Crème Brûlée!"), ["creme", "brulee"]);
  assert.deepEqual(tokenize(""), []);
});

test("Porter stemmer", () => {
  const cases: Record<string, string> = {
    running: "run",
    runs: "run",
    caresses: "caress",
    ponies: "poni",
    relational: "relat",
    connected: "connect",
    connecting: "connect",
    connection: "connect",
    generalization: "gener",
    hopping: "hop",
    happy: "happi",
    configuration: "configur",
    configured: "configur",
    configuring: "configur",
    deployments: "deploy",
    searches: "search",
    databases: "databas",
    authenticated: "authent",
  };
  for (const [w, s] of Object.entries(cases)) assert.equal(stem(w), s, w);
  // short words, numbers and non-ASCII pass through
  assert.equal(stem("is"), "is");
  assert.equal(stem("k8s"), "k8s");
  assert.equal(stem("42"), "42");
  assert.equal(stem("日本語"), "日本語");
  assert.equal(stem("connect"), stem("connected"));
  assert.deepEqual(stemTokens("Running tests"), ["run", "test"]);
});

test("synonym and abbreviation expansion", () => {
  assert.deepEqual(synonymsOf("k8s"), ["kubernetes"]);
  assert.ok(synonymsOf("kubernetes").includes("k8s"));
  assert.ok(synonymsOf("JS").includes("javascript"));
  assert.ok(synonymsOf("db").includes("database"));
  assert.ok(synonymsOf("auth").includes("authentication"));
  assert.deepEqual(synonymsOf("banana"), []);
  assert.deepEqual(expandQuery("k8s db"), ["k8s", "kubernetes", "db", "database"]);
  assert.deepEqual(expandQuery("k8s k8s"), ["k8s", "kubernetes"]); // unique
  assert.ok(expandQuery("a b c d e f g h", 3).length <= 3);
});

test("tsQueryText builds an OR query with synonyms", () => {
  assert.equal(tsQueryText("k8s auth"), "k8s or kubernetes or auth or authentication or authorization");
  assert.equal(tsQueryText("ml pipeline"), 'ml or pipeline or "machine learning"');
  assert.equal(tsQueryText("c++ useState"), "c++ or usestate");
  assert.equal(tsQueryText("  "), "");
});

test("keywordQuery (RAG) adds synonyms but keeps identifiers", () => {
  const q = keywordQuery("how to deploy to k8s with useState");
  assert.match(q, /\bk8s\b/);
  assert.match(q, /\bkubernetes\b/);
  assert.match(q, /\busestate\b/);
  assert.match(q, / or /);
  assert.equal(keywordQuery("a b"), "");
});

test("typo fallback query builder", () => {
  assert.deepEqual(fuzzyTerms("kuberentes deploy"), ["kuberentes", "deploy"]);
  assert.deepEqual(fuzzyTerms("the a of 42 db"), []); // too short / numeric terms are dropped
  assert.deepEqual(fuzzyTerms("getUserName"), ["user", "name"]);
  assert.deepEqual(fuzzyTerms("deploy deploy"), ["deploy"]);
  assert.equal(fuzzyTerms("one two three four five six seven", 4).length, 4);
  assert.ok(needsFuzzy(0) && needsFuzzy(2));
  assert.ok(!needsFuzzy(3));
  assert.equal(escapeLike("50%_off\\"), "50\\%\\_off\\\\");
});

test("Damerau-Levenshtein (reused from repoSearch)", () => {
  assert.equal(damerau("kitten", "sitting"), 3);
  assert.equal(damerau("ab", "ba"), 1); // transposition
  assert.equal(damerau("same", "same"), 0);
});

test("fuzzyScore: typos, stems, synonyms", () => {
  assert.ok(fuzzyScore("kuberentes", "Kubernetes deployment guide") > 0); // transposition
  assert.ok(fuzzyScore("configuring", "how to configure nginx") > 0); // stem
  assert.ok(fuzzyScore("k8s", "Kubernetes cluster") > 0); // synonym
  assert.ok(fuzzyScore("getUser", "get_user_by_id") >= 0.9);
  assert.equal(fuzzyScore("postgres", "kubernetes cluster"), 0);
  assert.equal(fuzzyScore("cat dog", "cat only"), 0); // every token must match
  assert.equal(fuzzyScore("", "x"), 0);
  assert.ok(fuzzyScore("react", "react") > fuzzyScore("reakt", "react"));
});

test("snippetAround returns an excerpt with match offsets", () => {
  const text = "Lorem ipsum ".repeat(20) + "how to configure kubernetes autoscaling " + "dolor sit ".repeat(20);
  const s = snippetAround(text, "kubernetes", 80)!;
  assert.ok(s.snippet.length <= 82);
  assert.equal(s.snippet.slice(s.start, s.start + s.length).toLowerCase(), "kubernetes");
  assert.ok(s.snippet.startsWith("…") && s.snippet.endsWith("…"));
  const syn = snippetAround("we run on k8s in prod", "kubernetes")!;
  assert.equal(syn.snippet.slice(syn.start, syn.start + syn.length), "k8s");
  const typo = snippetAround("the autoscaling setup", "autoscalng")!;
  assert.equal(typo.snippet.slice(typo.start, typo.start + typo.length), "autoscaling");
  assert.equal(snippetAround("nothing relevant", "zebra"), null);
});
