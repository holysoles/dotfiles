import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import factory from "../private-llm-gateway-helper.ts";

test("syncs matching chat models and leaves unrelated models alone", async () => {
  const dir = await mkdtemp(join(tmpdir(), "pi-cost-sync-"));
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = dir;
  try {
    const config = { providers: { enmaas: { models: [
      { id: "gpt-6-luna", cost: { input: 99 } },
      { id: "unrelated", cost: { input: 0 } },
      { id: "custom-chat", cost: { input: 99 } },
    ] } } };
    const store = { openai: { models: [
      { id: "gpt-6-luna", type: "chat", cost: { input: 0.1 } },
      { id: "gpt-6-luna", type: "classifier", cost: { input: 8 } },
      { id: "custom-chat", type: "chat", cost: { input: 2 } },
    ] } };
    await writeFile(join(dir, "models.json"), JSON.stringify(config));
    await writeFile(join(dir, "models-store.json"), JSON.stringify(store));

    let handler;
    factory({
      on: (event, fn) => { assert.equal(event, "session_start"); handler = fn; },
      registerVirtualModel: () => {},
    });
    const messages = [];
    let finish;
    const synced = new Promise((resolve) => { finish = resolve; });
    const ctx = {
      ui: { notify: (message, type) => { messages.push({ message, type }); if (type === "info") finish(); } },
      modelRegistry: { refresh: async (options) => assert.deepEqual(options, { allowNetwork: false }) },
    };
    handler({}, ctx);
    let timer;
    try {
      await Promise.race([synced, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("sync timed out")), 2000);
      })]);
    } finally {
      clearTimeout(timer);
    }
    const result = JSON.parse(await readFile(join(dir, "models.json"), "utf8"));
    assert.deepEqual(result.providers.enmaas.models.map((model) => model.cost), [
      { input: 0.1 }, { input: 0 }, { input: 2 },
    ]);
    assert.match(messages[0].message, /enmaas\/gpt-6-luna/);
    assert.match(messages[0].message, /enmaas\/custom-chat/);

    const saved = await readFile(join(dir, "models.json"), "utf8");
    handler({}, ctx);
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(await readFile(join(dir, "models.json"), "utf8"), saved);
    assert.equal(messages.length, 1);
  } finally {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
    await rm(dir, { recursive: true, force: true });
  }
});

test("fallback routes EnMaaS first, then keeps OpenAI after a failed request", () => {
  const routes = new Map();
  factory({
    on: () => {},
    registerVirtualModel: (definition) => routes.set(definition.id, definition),
  });
  assert.deepEqual([...routes.keys()], ["gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-terra"]);
  const id = "gpt-6-luna";
  const downstream = { provider: "enmaas", id };
  const upstream = { provider: "openai", id };
  let enmaasAuth = true;
  let openaiAuth = true;
  const ctx = { modelRegistry: {
    find: (provider) => provider === "enmaas" ? downstream : upstream,
    hasConfiguredAuth: (model) => model.provider === "enmaas" ? enmaasAuth : openaiAuth,
  } };
  const route = routes.get(id).route;
  const request = { reason: "user", thinkingLevel: "high" };
  assert.deepEqual(route(request, ctx), { model: downstream, thinkingLevel: "high", state: undefined });
  const retry = route({ ...request, reason: "retry", failed: { model: downstream } }, ctx);
  assert.deepEqual(retry, { model: upstream, thinkingLevel: "high", state: true });
  assert.equal(route({ ...request, reason: "continuation", state: retry.state }, ctx).model, upstream);
  assert.equal(route({ ...request, state: retry.state }, ctx).model, upstream);
  enmaasAuth = false;
  assert.equal(route(request, ctx).model, upstream);
  enmaasAuth = true;
  openaiAuth = false;
  assert.equal(route({ ...request, reason: "retry", failed: { model: downstream } }, ctx).model, downstream);
});
