// Фоновый скрипт Safari. Отличия от Chrome: Safari не поддерживает connectNative, поэтому каждый
// запрос идёт через sendNativeMessage в обработчик расширения, а тот обращается к мосту Koto.
// documentIds в Safari недоступны: перед вставкой перевода проверяется совпадение origin страницы.
// Текст не записывается в storage или журнал.
const api = globalThis.browser ?? globalThis.chrome;
const HOST = "dev.slipcast.koto.safari";
let generation = 0;
let inflight = 0;

const knownCodes = new Set([
  "connection_lost", "native_host_unavailable", "timeout", "models_missing", "translation_failed",
  "cloud_not_allowed", "excluded_page", "busy", "duplicate_request", "invalid_request",
  "invalid_language", "bridge_error",
]);

async function translate(text, source, target, pageOrigin) {
  if (!text.trim() || text.length > 20000 || inflight >= 2) throw new Error("invalid_or_busy");
  inflight++;
  try {
    const reply = await api.runtime.sendNativeMessage(HOST, {action: "translate", text, source, target, pageOrigin});
    if (reply?.ok && typeof reply.text === "string") return reply.text;
    throw new Error(knownCodes.has(reply?.error) ? reply.error : "bridge_error");
  } catch (error) {
    // Ошибка самого sendNativeMessage означает, что обработчик расширения недоступен.
    throw new Error(knownCodes.has(error?.message) || error?.message === "invalid_or_busy"
      ? error.message : "native_host_unavailable");
  } finally {
    inflight--;
  }
}

function cancel() { generation++; }

async function execute(tabId, func, args = []) {
  const results = await api.scripting.executeScript({target: {tabId}, func, args});
  return results[0]?.result;
}
async function activeTab() {
  const [tab] = await api.tabs.query({active: true, currentWindow: true});
  if (!tab?.id || !/^https?:\/\//i.test(tab.url || "")) throw new Error("unsupported_page");
  return {tabId: tab.id};
}
// Origin и текст читаются синхронно в одном документе.
async function snapshot(tabId, func) {
  const [injection] = await api.scripting.executeScript({target: {tabId}, func});
  const value = injection?.result;
  if (!value || !/^https?:\/\//i.test(value.pageOrigin || "")) throw new Error("unsupported_page");
  return value;
}

async function act(message) {
  if (message.action === "cancel") { cancel(); return {ok: true, status: "cancelled"}; }
  const {tabId} = await activeTab();
  if (message.action === "clear") {
    await execute(tabId, () => {
      for (const record of window.__kotoSlipcastNodes?.values() || []) record.output?.remove();
      window.__kotoSlipcastNodes = undefined;
    });
    return {ok: true, status: "cleared"};
  }
  const source = message.source || "auto", target = message.target || "ru";
  if (!/^(auto|[a-z]{2,3})$/.test(source) || !/^[a-z]{2,3}$/.test(target)) throw new Error("invalid_language");
  cancel();
  const current = generation;
  if (message.action === "selection") {
    const {text, pageOrigin} = await snapshot(tabId, () => ({
      text: window.getSelection()?.toString() || "", pageOrigin: location.origin,
    }));
    if (generation !== current) throw new Error("cancelled");
    const result = await translate(text, source, target, pageOrigin);
    if (generation !== current) throw new Error("cancelled");
    return {ok: true, text: result};
  }
  if (message.action !== "page") throw new Error("invalid_action");
  const {segments, pageOrigin} = await snapshot(tabId, () => {
    // Только видимые текстовые узлы. Поля ввода и editable content исключены.
    for (const record of window.__kotoSlipcastNodes?.values() || []) record.output?.remove();
    const records = new Map();
    const output = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node, inspected = 0, characters = 0;
    while ((node = walker.nextNode()) && inspected++ < 5000 && output.length < 40) {
      const text = node.textContent;
      const parent = node.parentElement;
      if (!parent || !text.trim() || text.length > 1500 || characters + text.length > 20000 ||
          parent.closest("script,style,noscript,textarea,input,select,option,code,pre,[contenteditable]")) continue;
      const style = getComputedStyle(parent);
      if (style.visibility === "hidden" || style.display === "none") continue;
      const range = document.createRange(); range.selectNodeContents(node);
      const rect = range.getBoundingClientRect();
      if (!rect.width || !rect.height || rect.bottom <= 0 || rect.top >= innerHeight) continue;
      const id = output.length;
      records.set(id, {node, original: text, output: null});
      output.push({id, text});
      characters += text.length;
    }
    window.__kotoSlipcastNodes = records;
    return {segments: output, pageOrigin: location.origin};
  });
  let completed = 0;
  for (let index = 0; index < segments.length; index += 2) {
    if (generation !== current) throw new Error("cancelled");
    const batch = await Promise.all(segments.slice(index, index + 2).map(async segment => ({
      id: segment.id, original: segment.text, text: await translate(segment.text, source, target, pageOrigin),
    })));
    if (generation !== current) throw new Error("cancelled");
    completed += await execute(tabId, (batch, target, expectedOrigin) => {
      // Без documentId единственная защита от вставки в другую страницу — совпадение origin.
      if (location.origin !== expectedOrigin) return 0;
      let applied = 0;
      for (const item of batch) {
        const record = window.__kotoSlipcastNodes?.get(item.id);
        // Поздний ответ не заменяет динамически обновлённый текст сайта.
        if (!record?.node.isConnected || record.node.textContent !== item.original) continue;
        const translated = document.createElement("span");
        translated.textContent = item.text;
        translated.lang = target;
        translated.dir = "auto";
        Object.assign(translated.style, {display: "block", whiteSpace: "pre-wrap", padding: "4px 0", color: "#7656c9", unicodeBidi: "isolate"});
        record.output?.remove();
        record.node.parentNode.insertBefore(translated, record.node.nextSibling);
        record.output = translated;
        applied++;
      }
      return applied;
    }, [batch, target, pageOrigin]);
  }
  return {ok: true, status: "page_translated", count: completed};
}
api.runtime.onMessage.addListener((message, sender, respond) => {
  // Команды принимает только собственный popup; content scripts не получают native RPC.
  if (sender.id !== api.runtime.id || sender.tab) return false;
  act(message).then(respond).catch(error => respond({ok: false, error: String(error.message)}));
  return true;
});
