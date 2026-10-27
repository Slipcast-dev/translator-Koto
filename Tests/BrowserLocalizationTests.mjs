import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import vm from "node:vm";

const root = new URL("../BrowserExtension/", import.meta.url);
const read = (name) => readFile(new URL(name, root), "utf8");
const catalogs = Object.fromEntries(await Promise.all(
  ["en", "ru"].map(async (locale) => [
    locale, JSON.parse(await read("_locales/" + locale + "/messages.json")),
  ]),
));
const manifest = JSON.parse(await read("manifest.json"));
const identity = JSON.parse(await read("identity.json"));
const html = await read("popup.html");
const sources = Object.fromEntries(await Promise.all(
  ["i18n.js", "popup.js", "background.js"].map(async (name) => [name, await read(name)]),
));

// Минимальный DOM-adapter проверяет действия production popup без браузера.
// Нативный chrome.i18n и реальная вёрстка отдельно проверяются в Chrome.
class Element {
  constructor() {
    this.options = [];
    this.style = {};
    this.value = "";
    this.textContent = "";
    this.dataset = {};
    this.listeners = new Map();
  }
  add(option) {
    this.options.push(option);
    if (this.options.length === 1) this.value = option.value;
  }
  addEventListener(name, listener) { this.listeners.set(name, listener); }
  async trigger(name) { return this.listeners.get(name)?.(); }
}

async function fixture(locale, preferences = { source: "en", target: "ja" }, numberRegion) {
  const language = locale.split(/[-_]/)[0] === "ru" ? "ru" : "en";
  const elements = Object.fromEntries(
    ["source", "target", "selection", "page", "clear", "cancel", "status", "result"]
      .map((id) => [id, new Element()]),
  );
  const translated = [];
  for (const match of html.matchAll(/<[^>]+data-i18n="([^"]+)"[^>]*>/g)) {
    const id = match[0].match(/\bid="([^"]+)"/)?.[1];
    const element = id ? elements[id] : new Element();
    element.dataset.i18n = match[1];
    translated.push(element);
  }
  const document = {
    documentElement: {},
    getElementById: (id) => elements[id],
    querySelectorAll: () => translated,
    createElement(tag) { assert.equal(tag, "span"); return new Element(); },
  };
  const storageWrites = [];
  const requests = [];
  const state = {
    browserResults: [], unsupported: false, nativeError: null,
    lastAction: null, workerListener: null, applyDOM: false, targets: [],
    nativeText: "<b>translated fixture</b>", inserted: [],
  };
  const nativeListeners = {};
  const chrome = {
    i18n: {
      // Здесь моделируется документированный общий/резервный lookup Chrome.
      // Это не утверждение о проверке нативной локали в настоящем браузере.
      getMessage(key, substitutions = []) {
        const entry = catalogs[language][key] || catalogs.en[key];
        if (!entry) return "";
        let value = entry.message;
        for (const [name, placeholder] of Object.entries(entry.placeholders || {})) {
          const index = Number(placeholder.content.slice(1)) - 1;
          value = value.replaceAll("$" + name.toUpperCase() + "$", substitutions[index]);
        }
        return value;
      },
    },
    storage: { local: {
      async get() { return { ...preferences }; },
      async set(value) { storageWrites.push(value); },
    } },
    tabs: { async query() {
      return [{ id: 7, url: state.unsupported ? "chrome://settings" : "https://fixture.test/" }];
    } },
    scripting: { async executeScript({ target, func, args = [] }) {
      state.targets.push(target);
      if (state.applyDOM && args.length === 2) {
        return [{ result: func(...args) }];
      }
      assert.ok(state.browserResults.length, "Unexpected browser injection");
      let result = state.browserResults.shift();
      if (typeof result === "string") result = {text:result,pageOrigin:"https://fixture.test"};
      if (Array.isArray(result)) result = {segments:result,pageOrigin:"https://fixture.test"};
      return [{ result, documentId:"fixture-document" }];
    } },
    runtime: {
      id: identity.id,
      onMessage: { addListener(listener) { state.workerListener = listener; } },
      connectNative(host) {
        assert.equal(host, "dev.slipcast.koto");
        return {
          onMessage: { addListener(listener) { nativeListeners.message = listener; } },
          onDisconnect: { addListener(listener) { nativeListeners.disconnect = listener; } },
          postMessage(frame) {
            if (frame.type !== "translate") return;
            requests.push(frame);
            queueMicrotask(() => nativeListeners.message({
              v: 1, id: frame.id,
              type: state.nativeError ? "error" : "translated",
              payload: state.nativeError
                ? { code: state.nativeError }
                : { text: state.nativeText },
            }));
          },
        };
      },
      async sendMessage(message) {
        state.lastAction = message;
        return new Promise((resolve) => {
          assert.equal(state.workerListener(message, { id: identity.id }, resolve), true);
        });
      },
    },
  };
  // Регион Intl моделируется отдельно от выбранного каталога ru/en.
  const regionalIntl = Object.create(Intl);
  regionalIntl.NumberFormat = class extends Intl.NumberFormat {
    constructor(localeArg, options) { super(localeArg ?? numberRegion, options); }
  };
  const injectedWindow = { __kotoSlipcastNodes: new Map() };
  const context = vm.createContext({
    chrome, document, Intl: regionalIntl, window: injectedWindow,
    URL, Map, Set, crypto: { randomUUID },
    setTimeout, clearTimeout, queueMicrotask,
    Option: class { constructor(text, value) { this.text = text; this.value = value; } },
  });
  new vm.Script(sources["background.js"]).runInContext(context);
  const i18n = new vm.SourceTextModule(sources["i18n.js"], { context });
  await i18n.link(() => { throw new Error("Unexpected i18n dependency"); });
  const popup = new vm.SourceTextModule(sources["popup.js"], { context });
  await popup.link((specifier) => {
    assert.equal(specifier, "./i18n.js");
    return i18n;
  });
  await popup.evaluate();
  await Promise.resolve();
  return { elements, translated, document, state, storageWrites, requests, i18n, injectedWindow };
}

test("catalogs, manifest, placeholders and extension identity", async () => {
  assert.equal(manifest.default_locale, "en");
  assert.equal(manifest.key, identity.key);
  assert.deepEqual(manifest.permissions, ["activeTab", "scripting", "nativeMessaging", "storage"]);
  assert.deepEqual(Object.keys(catalogs.en).sort(), Object.keys(catalogs.ru).sort());
  for (const [key, entry] of Object.entries(catalogs.en)) {
    assert.ok(entry.message && entry.description, key);
    assert.ok(catalogs.ru[key].message && catalogs.ru[key].description, key);
    assert.deepEqual(entry.placeholders || {}, catalogs.ru[key].placeholders || {});
  }
  for (const reference of JSON.stringify(manifest).matchAll(/__MSG_(\w+)__/g)) {
    assert.ok(catalogs.en[reference[1]], reference[1]);
  }
  assert.match(html, /script type="module" src="popup.js"/);
});

for (const locale of ["en", "ru", "en-GB", "ru-RU", "de-DE"]) {
  test("popup and worker behavior: " + locale, async () => {
    const f = await fixture(locale);
    const ru = locale.startsWith("ru");
    assert.equal(f.document.documentElement.lang, ru ? "ru" : "en");
    assert.equal(f.document.documentElement.dir, "ltr");
    assert.equal(f.elements.selection.textContent, ru ? "Перевести выделение" : "Translate selection");
    assert.equal(f.elements.source.options[0].text, ru ? "Определить язык" : "Detect language");
    assert.equal(f.elements.target.options.find((o) => o.value === "de").text, ru ? "немецкий" : "German");
    assert.equal(f.elements.source.value, "en");
    assert.equal(f.elements.target.value, "ja");
    assert.equal(f.storageWrites.length, 0, "Changing UI language must not rewrite the pair");
    assert.equal(f.elements.source.options.length, 20);
    assert.equal(f.elements.target.options.length, 19);

    f.state.browserResults = ["synthetic selection"];
    await f.elements.selection.trigger("click");
    assert.equal(f.elements.result.textContent, "<b>translated fixture</b>");
    assert.equal(f.elements.result.lang, "ja");
    assert.equal(f.elements.status.textContent, ru ? "Готово" : "Done");
    assert.equal(f.requests[0].payload.source, "en");
    assert.equal(f.requests[0].payload.target, "ja");

    f.state.browserResults = [[{ id: 0, text: "A" }, { id: 1, text: "B" }], 2];
    await f.elements.page.trigger("click");
    assert.equal(f.elements.status.textContent, ru
      ? "Переведены 2 видимых фрагмента." : "Translated 2 visible fragments.");

    f.state.browserResults = [undefined];
    await f.elements.clear.trigger("click");
    assert.equal(f.elements.status.textContent, ru ? "Перевод убран" : "Translation removed");
    await f.elements.cancel.trigger("click");
    assert.equal(f.elements.status.textContent, ru ? "Отменено" : "Cancelled");

    f.state.unsupported = true;
    await f.elements.selection.trigger("click");
    assert.equal(f.elements.status.textContent, ru
      ? "На этой странице перевод недоступен." : "Translation is unavailable on this page.");
    f.state.unsupported = false;
    f.state.nativeError = "models_missing";
    f.state.browserResults = ["synthetic selection"];
    await f.elements.selection.trigger("click");
    assert.match(f.elements.status.textContent, ru ? /Языковые ресурсы Apple/ : /Apple language resources/);

    f.elements.target.value = "de";
    await f.elements.target.trigger("change");
    assert.equal(f.storageWrites.length, 1);
    assert.equal(f.storageWrites[0].source, "en");
    assert.equal(f.storageWrites[0].target, "de");
  });
}

for (const locale of ["en", "ru"]) {
  test("error coverage, fallback and plural forms: " + locale, async () => {
    const f = await fixture(locale);
    const api = f.i18n.namespace;
    for (const key of Object.keys(catalogs.en).filter((k) => k.startsWith("error_"))) {
      const code = key.slice("error_".length);
      assert.equal(api.errorMessage(code), catalogs[locale][key].message);
    }
    assert.equal(api.errorMessage("unexpected_private_detail"), catalogs[locale].error_bridge_error.message);
    assert.equal(api.message("absent_key"), catalogs[locale].error_bridge_error.message);
    assert.equal(api.completionMessage({ status: "page_translated", count: -1 }),
      catalogs[locale].error_bridge_error.message);
    const expected = locale === "ru"
      ? ["Переведено 0 видимых фрагментов.", "Переведён 1 видимый фрагмент.",
         "Переведены 2 видимых фрагмента.", "Переведено 5 видимых фрагментов.",
         "Переведён 21 видимый фрагмент.", "Переведены 22 видимых фрагмента."]
      : ["Translated 0 visible fragments.", "Translated 1 visible fragment.",
         "Translated 2 visible fragments.", "Translated 5 visible fragments.",
         "Translated 21 visible fragments.", "Translated 22 visible fragments."];
    for (const [index, count] of [0, 1, 2, 5, 21, 22].entries()) {
      assert.equal(api.completionMessage({ status: "page_translated", count }), expected[index]);
    }
  });
}

test("initial auto→ru defaults are independent of UI language", async () => {
  for (const locale of ["en", "ru"]) {
    const f = await fixture(locale, { source: "auto", target: "ru" });
    assert.equal(f.elements.source.value, "auto");
    assert.equal(f.elements.target.value, "ru");
    assert.equal(f.storageWrites.length, 0);
  }
});

test("missing local translation uses the default English catalog", async () => {
  const original = catalogs.ru.done;
  try {
    delete catalogs.ru.done;
    const f = await fixture("ru");
    assert.equal(f.i18n.namespace.message("done"), "Done");
  } finally {
    catalogs.ru.done = original;
  }
});

test("worker rejects foreign senders and tab senders", async () => {
  const f = await fixture("en");
  let responded = false;
  const respond = () => { responded = true; };
  assert.equal(f.state.workerListener({ action: "cancel" }, { id: "foreign" }, respond), false);
  assert.equal(f.state.workerListener(
    { action: "cancel" }, { id: identity.id, tab: { id: 7 } }, respond,
  ), false);
  assert.equal(responded, false);
  assert.equal(f.requests.length, 0);
});

test("number region is independent of popup language", async () => {
  for (const [locale, region, expected] of [
    ["ru", "en-US", "12,345"], ["en", "de-DE", "12.345"],
    ["en", "ru-RU", "12 345"],
  ]) {
    const f = await fixture(locale, undefined, region);
    const text = f.i18n.namespace.completionMessage({
      status: "page_translated", count: 12345,
    }).replaceAll("\u00a0", " ").replaceAll("\u202f", " ");
    assert.ok(text.includes(expected), text);
  }
});

test("page insertion isolates RTL without changing translated text", async () => {
  const f = await fixture("en", { source: "en", target: "ar" });
  f.state.applyDOM = true;
  f.state.nativeText = "مرحبا بالعالم — Hello {name}";
  const parent = {
    insertBefore(element) { f.state.inserted.push(element); },
  };
  f.injectedWindow.__kotoSlipcastNodes.set(0, {
    node: { isConnected: true, textContent: "Hello", parentNode: parent },
    original: "Hello", output: null,
  });
  f.state.browserResults = [[{ id: 0, text: "Hello" }]];
  await f.elements.page.trigger("click");
  assert.equal(f.state.inserted.length, 1);
  const element = f.state.inserted[0];
  assert.equal(element.textContent, f.state.nativeText);
  assert.equal(element.lang, "ar");
  assert.equal(element.dir, "auto");
  assert.equal(element.style.unicodeBidi, "isolate");
  assert.equal(f.elements.status.textContent, "Translated 1 visible fragment.");
});

// tabs.query всё ещё сообщает старый URL; текст уже из нового документа.
// RPC обязан использовать origin снимка, а не исходный URL вкладки.
test("selection navigation uses origin captured with text", async () => {
  const f = await fixture("en");
  f.state.browserResults = [{text:"private mail fixture",pageOrigin:"https://mail.google.com"}];
  await f.elements.selection.trigger("click");
  assert.equal(f.requests[0].payload.pageOrigin,"https://mail.google.com");
});
test("page snapshot origin and destination document stay bound", async () => {
  const f = await fixture("en");
  f.state.browserResults = [{segments:[{id:0,text:"private fixture"}],pageOrigin:"https://mail.google.com"},1];
  await f.elements.page.trigger("click");
  assert.equal(f.requests[0].payload.pageOrigin,"https://mail.google.com");
  assert.deepEqual(Array.from(f.state.targets.at(-1).documentIds),["fixture-document"]);
});
test("unsupported snapshot origin sends no text", async () => {
  const f = await fixture("en");
  f.state.browserResults = [{text:"private fixture",pageOrigin:"null"}];
  await f.elements.selection.trigger("click");
  assert.equal(f.requests.length,0);
});
