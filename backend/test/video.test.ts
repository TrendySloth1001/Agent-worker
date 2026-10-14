import { test } from "node:test";
import assert from "node:assert/strict";
import {
  baseEvidence,
  CAPTION_PROMPT,
  ensureCaptions,
  evidenceFromMeta,
  fmtTs,
  GROUNDING_NOTE,
  legacyFrameTimes,
  MAX_ANALYZE_S,
  MAX_FRAMES,
  mergeSegments,
  needsFrames,
  parseCaptions,
  pickEvenly,
  planFrames,
  renderVideoBlock,
  routeVideo,
  VIDEO_TEXT_ONLY_NOTE,
  type Evidence,
  type VideoDeps,
} from "../src/files/video.js";

const pack = (over: Partial<Parameters<typeof baseEvidence>[0]> = {}): Evidence =>
  baseEvidence({ durationS: 30, width: 1280, height: 720, hasAudio: true, frameTimes: planFrames(30), hasTranscript: true, segments: [{ start: 1, end: 4, text: "Hello there" }, { start: 12, end: 15, text: "Bye" }], ...over });

const noFrames = { sendFrames: false, frameIdx: [] as number[], notices: [] as string[] };

test("planFrames: counts and timestamps for short and long videos", () => {
  assert.deepEqual(planFrames(0), [0]);
  assert.deepEqual(planFrames(1), [0.5]);
  assert.equal(planFrames(2).length, 3); // at least 3 for anything 2 s or longer
  assert.equal(planFrames(30).length, 6);
  assert.equal(planFrames(600).length, MAX_FRAMES);
  assert.equal(planFrames(7200).length, MAX_FRAMES);
  const t = planFrames(60);
  assert.equal(t.length, 12);
  assert.equal(t[0], 2.5);
  assert.ok(t.every((x, i) => x < 60 && (i === 0 || x > t[i - 1])));
});

test("legacy frames recompute the mid-slice times", () => {
  assert.deepEqual(legacyFrameTimes(8, 80), [5, 15, 25, 35, 45, 55, 65, 75]);
  const ev = evidenceFromMeta({ durationS: 80, frameKeys: new Array(8).fill("k"), hasAudio: true, width: 640, height: 360 }, true);
  assert.equal(ev.frames[7].t, 75);
  assert.equal(ev.captionStatus, "pending");
});

test("fmtTs and pickEvenly", () => {
  assert.equal(fmtTs(42.9), "0:42");
  assert.equal(fmtTs(125), "2:05");
  assert.equal(fmtTs(3723), "1:02:03");
  assert.deepEqual(pickEvenly(3, 5), [0, 1, 2]);
  assert.equal(pickEvenly(12, 5).length, 5);
});

test("mergeSegments joins short pieces", () => {
  const m = mergeSegments([{ start: 0, end: 3, text: "a" }, { start: 3, end: 6, text: "b" }, { start: 6, end: 12, text: "c" }, { start: 12, end: 14, text: "d" }]);
  assert.deepEqual(m.map((s) => [s.start, s.end, s.text]), [[0, 12, "a b c"], [12, 14, "d"]]);
});

test("parseCaptions needs exactly one string per frame", () => {
  assert.deepEqual(parseCaptions('```json\n["a","b"]\n```', 2), ["a", "b"]);
  assert.equal(parseCaptions('["a"]', 2), null);
  assert.equal(parseCaptions("no json", 1), null);
  assert.equal(parseCaptions('["a",""]', 2), null);
  assert.ok(CAPTION_PROMPT([3, 65]).includes("[1:05]"));
});

function deps(over: Partial<VideoDeps> = {}) {
  const calls = { describe: 0, save: 0, imagesPerCall: [] as number[] };
  const d: VideoDeps = {
    frame: async (k) => `b64-${k}`,
    describe: async (m) => {
      calls.describe++;
      const n = m[0].images!.length;
      calls.imagesPerCall.push(n);
      return JSON.stringify(Array.from({ length: n }, (_, i) => `caption ${calls.describe}.${i}`));
    },
    save: async () => void calls.save++,
    ...over,
  };
  return { d, calls };
}

test("evidence pack: frames described in batches of three, saved once, then cached", async () => {
  const ev = pack({ frameTimes: planFrames(60) });
  const keys = ev.frames.map((_, i) => `f${i}`);
  const { d, calls } = deps();
  const out = await ensureCaptions("file-a", keys, ev, d);
  assert.equal(calls.describe, 4);
  assert.deepEqual(calls.imagesPerCall, [3, 3, 3, 3]);
  assert.equal(calls.save, 1);
  assert.equal(out.captionStatus, "ok");
  assert.ok(out.frames.every((f) => f.caption));
  // A follow-up question finds the described pack and makes no vision call.
  const again = await ensureCaptions("file-a", keys, out, d);
  assert.equal(calls.describe, 4);
  assert.equal(again, out);
});

test("evidence pack: a failed batch leaves those frames undescribed (partial); all failing marks it failed", async () => {
  const ev = pack({ frameTimes: planFrames(60) });
  const keys = ev.frames.map((_, i) => `f${i}`);
  let n = 0;
  const partial = deps({ describe: async (m) => (++n === 2 ? Promise.reject(new Error("busy")) : JSON.stringify(m[0].images!.map(() => "x"))) });
  const out = await ensureCaptions("file-b", keys, ev, partial.d);
  assert.equal(out.captionStatus, "partial");
  assert.equal(out.frames.filter((f) => f.caption).length, 9);
  const failing = deps({
    describe: async () => {
      throw new Error("no vision model");
    },
  });
  const none = await ensureCaptions("file-c", keys, ev, failing.d);
  assert.equal(none.captionStatus, "failed");
});

test("evidence pack: too long or frameless videos are never described", async () => {
  const { d, calls } = deps();
  const long = pack({ durationS: MAX_ANALYZE_S + 1 });
  assert.equal(long.tooLong, true);
  await ensureCaptions("file-d", long.frames.map((_, i) => `f${i}`), long, d);
  const none = pack({ frameTimes: [] });
  assert.equal(none.frameStatus, "none");
  await ensureCaptions("file-e", [], none, d);
  assert.equal(calls.describe, 0);
});

test("needsFrames: visual and unclear questions get frames, speech questions do not", () => {
  assert.equal(needsFrames(""), true);
  assert.equal(needsFrames("what is she wearing?"), true);
  assert.equal(needsFrames("describe this video"), true);
  assert.equal(needsFrames("what did he say about pricing?"), false);
  assert.equal(needsFrames("transcribe this"), false);
  assert.equal(needsFrames("what does he say and what is on screen"), true);
});

test("routing: a visual question sends up to five frames with their timestamps; a speech question sends none", () => {
  const ev = pack({ frameTimes: planFrames(60) });
  ev.frames.forEach((f, i) => (f.caption = `scene ${i}`));
  ev.captionStatus = "ok";
  const visual = routeVideo(ev, "what happens in the video?");
  assert.equal(visual.sendFrames, true);
  assert.equal(visual.frameIdx.length, 5);
  const block = renderVideoBlock("clip.mp4", ev, visual);
  for (const i of visual.frameIdx) assert.ok(block.includes(`[${fmtTs(ev.frames[i].t)}]`));
  assert.ok(block.includes("Attached images, in order"));
  const speech = routeVideo(ev, "what did they say?");
  assert.equal(speech.sendFrames, false);
  assert.deepEqual(speech.frameIdx, []);
  assert.ok(!renderVideoBlock("clip.mp4", ev, speech).includes("Attached images"));
});

test("text-only fallback gets the pack (descriptions, transcript) and the grounding note, never images", () => {
  const ev = pack();
  ev.frames.forEach((f, i) => (f.caption = `scene ${i}`));
  ev.captionStatus = "ok";
  const block = renderVideoBlock("clip.mp4", ev, noFrames);
  assert.ok(block.includes("scene 0"));
  assert.ok(block.includes("[0:01] Hello there"));
  assert.ok(block.includes("1280x720"));
  assert.ok(!block.includes("Attached images"));
  assert.match(GROUNDING_NOTE, /\[0:42\]/);
  assert.match(GROUNDING_NOTE, /Never invent/);
  assert.match(VIDEO_TEXT_ONLY_NOTE, /could not look at the video frames/);
});

test("failure messaging: plain and honest, no dev jargon", () => {
  const none = pack({ frameTimes: [] });
  const r1 = routeVideo(none, "what happens?");
  assert.equal(r1.sendFrames, false);
  assert.match(r1.notices[0], /Couldn't pull pictures/);
  assert.match(renderVideoBlock("v.mp4", none, r1), /nothing is known about what the video shows/);

  const long = pack({ durationS: 4000 });
  const r2 = routeVideo(long, "what happens?");
  assert.equal(r2.sendFrames, false);
  assert.match(r2.notices[0], /too long/);
  assert.match(renderVideoBlock("v.mp4", long, r2), /not examined/);

  const failed = pack();
  failed.captionStatus = "failed";
  assert.match(routeVideo(failed, "what is shown").notices[0], /Couldn't look closely/);
  assert.match(renderVideoBlock("v.mp4", failed, noFrames), /unavailable, so what the video shows is unknown/);

  for (const n of [r1.notices[0], r2.notices[0]]) assert.ok(!/ffmpeg|error|exception|model|api|groq/i.test(n));
});

test("transcript states: no audio, silent, failed, untimed", () => {
  assert.match(renderVideoBlock("v", pack({ hasAudio: false, hasTranscript: false, segments: [] }), noFrames), /no audio track/);
  assert.match(renderVideoBlock("v", pack({ hasTranscript: false, segments: [] }), noFrames), /no speech detected/);
  assert.match(renderVideoBlock("v", pack({ hasTranscript: false, transcriptFailed: true, segments: [] }), noFrames), /could not be made/);
  assert.match(renderVideoBlock("v", pack({ segments: [] }), noFrames, "plain words"), /no timestamps available[\s\S]*plain words/);
});
