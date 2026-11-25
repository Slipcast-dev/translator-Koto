// Фоновый скрипт Safari. Отличия от Chrome: Safari не поддерживает connectNative, поэтому каждый
// запрос идёт через sendNativeMessage в обработчик расширения, а тот обращается к мосту Koto.
// documentIds в Safari недоступны: перед вставкой перевода проверяется совпадение origin страницы.
// Текст не записывается в storage или журнал.
const api = globalThis.browser ?? globalThis.chrome;
const HOST = "dev.slipcast.koto.safari";
let generation = 0;
// Учитываются только запросы текущего поколения: отменённые не должны занимать лимит.
const inflight = new Set();

const knownCodes = new Set([
  "connection_lost", "native_host_unavailable", "timeout", "models_missing", "translation_failed",
  "cloud_not_allowed", "excluded_page", "busy", "duplicate_request", "invalid_request",
  "invalid_language", "bridge_error", "rate_limited",
]);

async function translate(text, source, target, pageOrigin) {
  if (!text.trim() || text.length > 20000 || inflight.size >= 2) throw new Error("invalid_or_busy");
  const ticket = {};
  inflight.add(ticket);
  try {
    const reply = await api.runtime.sendNativeMessage(HOST, {action: "translate", text, source, target, pageOrigin});
    if (reply?.ok && typeof reply.text === "string") return reply.text;
    throw new Error(knownCodes.has(reply?.error) ? reply.error : "bridge_error");
  } catch (error) {
    // Ошибка самого sendNativeMessage означает, что обработчик расширения недоступен.
    throw new Error(knownCodes.has(error?.message) || error?.message === "invalid_or_busy"
      ? error.message : "native_host_unavailable");
  } finally {
    inflight.delete(ticket);
  }
}

function cancelRequests() {
  if (!inflight.size) return;
  inflight.clear();
  // Обработчик закрывает соединения с мостом, и приложение прекращает начатые переводы.
  api.runtime.sendNativeMessage(HOST, {action: "cancel"})?.catch?.(() => {});
}
function cancel() { generation++; cancelRequests(); }

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
async function snapshot(tabId, func, args = []) {
  const [injection] = await api.scripting.executeScript({target: {tabId}, func, args});
  const value = injection?.result;
  if (!value || !/^https?:\/\//i.test(value.pageOrigin || "")) throw new Error("unsupported_page");
  return value;
}

// Выполняется внутри страницы. Только видимые текстовые узлы; поля ввода и editable content исключены.
// reset начинает новый перевод; без reset возвращаются лишь ещё не переведённые узлы (прокрутка).
function collectVisible(reset) {
  if (reset) {
    for (const record of window.__kotoSlipcastNodes?.values() || []) record.output?.remove();
    window.__kotoSlipcastNodes = new Map();
    window.__kotoSlipcastSeen = new WeakMap();
    window.__kotoSlipcastNext = 0;
  }
  const records = window.__kotoSlipcastNodes;
  const seen = window.__kotoSlipcastSeen;
  // Состояние исчезает при переходе на другую страницу или после «Убрать перевод».
  if (!records || !seen) return {segments:[], pageOrigin:location.origin, gone:true};
  const output = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let node, inspected = 0, characters = 0;
  while ((node = walker.nextNode()) && inspected++ < 20000 && output.length < 40) {
    const text = node.textContent;
    const known = seen.get(node);
    if (known?.text === text) continue;
    const parent = node.parentElement;
    if (!parent || !text.trim() || text.length > 1500 || characters + text.length > 20000 ||
        parent.closest("script,style,noscript,textarea,input,select,option,code,pre,[contenteditable],[data-koto-translation]")) continue;
    const range = document.createRange(); range.selectNodeContents(node);
    const rect = range.getBoundingClientRect();
    if (!rect.width || !rect.height || rect.bottom <= 0 || rect.top >= innerHeight) continue;
    const style = getComputedStyle(parent);
    if (style.visibility === "hidden" || style.display === "none") continue;
    // Сайт изменил уже переведённый узел: прежняя подпись относится к старому тексту.
    if (known) { records.get(known.id)?.output?.remove(); records.delete(known.id); }
    const id = window.__kotoSlipcastNext++;
    records.set(id, {node, original:text, output:null});
    seen.set(node, {text, id});
    output.push({id, text});
    characters += text.length;
  }
  return {segments:output, pageOrigin:location.origin};
}
function removeTranslations() {
  for (const record of window.__kotoSlipcastNodes?.values() || []) record.output?.remove();
  window.__kotoSlipcastNodes = undefined;
  window.__kotoSlipcastSeen = undefined;
}
// Перевод при прокрутке ограничен: забытая вкладка с бегущей строкой не должна бесконечно
// загружать модель или расходовать облачную квоту.
const FOLLOW = {interval: 1200, segments: 400, characters: 100000, duration: 10 * 60 * 1000};

// При явно выбранном языке короткие соседние фрагменты уходят одним запросом. При автоопределении
// пакет не объединяется: на странице с несколькими языками весь пакет получил бы один исходный язык.
function groupSegments(segments, source) {
  const groups = [];
  let group = [], size = 0;
  for (const segment of segments) {
    if (group.length && (source === "auto" || group.length >= 8 || size + segment.text.length > 1500)) {
      groups.push(group); group = []; size = 0;
    }
    group.push(segment); size += segment.text.length;
  }
  if (group.length) groups.push(group);
  return groups;
}
async function translateGroup(group, source, target, pageOrigin, current) {
  const item = (segment, text) => ({id:segment.id, original:segment.text, text});
  if (group.length > 1) {
    const joined = group.map(segment => segment.text.replace(/\s+/g, " ").trim()).join("\n");
    const lines = (await translate(joined, source, target, pageOrigin)).split("\n");
    if (lines.length === group.length && lines.every(line => line.trim())) {
      return group.map((segment, index) => item(segment, lines[index]));
    }
  }
  // Один фрагмент или ответ с другим числом строк: переводим по одному.
  const results = [];
  for (const segment of group) {
    if (generation !== current) throw new Error("cancelled");
    results.push(item(segment, await translate(segment.text, source, target, pageOrigin)));
  }
  return results;
}
async function translatePage(segments, session) {
  let completed = 0;
  const groups = groupSegments(segments, session.source);
  for (let index = 0; index < groups.length; index += 2) {
    if (generation !== session.generation) throw new Error("cancelled");
    let batch;
    try {
      batch = (await Promise.all(groups.slice(index, index + 2).map(group =>
        translateGroup(group, session.source, session.target, session.pageOrigin, session.generation)))).flat();
    } catch (error) {
      if (generation === session.generation) cancelRequests();
      throw error;
    }
    if (generation !== session.generation) throw new Error("cancelled");
    completed += await execute(session.tabId, (batch, target, expectedOrigin) => {
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
        // Текст перевода определяет направление независимо от языка сайта.
        translated.dir = "auto";
        // Метка не даёт принять собственный перевод за новый текст страницы при прокрутке.
        translated.dataset.kotoTranslation = "1";
        Object.assign(translated.style, {display:"block",whiteSpace:"pre-wrap",padding:"4px 0",color:"#7656c9",unicodeBidi:"isolate"});
        record.output?.remove();
        record.node.parentNode.insertBefore(translated, record.node.nextSibling);
        record.output = translated;
        applied++;
      }
      return applied;
    }, [batch, session.target, session.pageOrigin]);
  }
  return completed;
}
// Переход на другую страницу уничтожает состояние collectVisible (gone), и наблюдение заканчивается.
async function followScroll(session, used) {
  const deadline = Date.now() + FOLLOW.duration;
  let {segments, characters} = used;
  while (generation === session.generation && Date.now() < deadline &&
         segments < FOLLOW.segments && characters < FOLLOW.characters) {
    await new Promise(resolve => setTimeout(resolve, FOLLOW.interval));
    if (generation !== session.generation) return;
    try {
      const found = await execute(session.tabId, collectVisible, [false]);
      if (!found || found.gone || found.pageOrigin !== session.pageOrigin) return;
      const next = found.segments.slice(0, FOLLOW.segments - segments);
      if (!next.length) continue;
      segments += next.length;
      characters += next.reduce((sum, segment) => sum + segment.text.length, 0);
      await translatePage(next, session);
    } catch { return; }
  }
}
async function act(message) {
  if (message.action === "cancel") { cancel(); return {ok: true, status: "cancelled"}; }
  const {tabId} = await activeTab();
  if (message.action === "clear") {
    cancel();
    await execute(tabId, removeTranslations);
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
  const {segments, pageOrigin} = await snapshot(tabId, collectVisible, [true]);
  const session = {tabId, source, target, pageOrigin, generation: current};
  const count = await translatePage(segments, session);
  const following = message.follow === true;
  if (following) {
    void followScroll(session, {
      segments: segments.length,
      characters: segments.reduce((sum, segment) => sum + segment.text.length, 0),
    });
  }
  return {ok: true, status: "page_translated", count, following};
}
api.runtime.onMessage.addListener((message, sender, respond) => {
  // Команды принимает только собственный popup; content scripts не получают native RPC.
  if (sender.id !== api.runtime.id || sender.tab) return false;
  act(message).then(respond).catch(error => respond({ok: false, error: String(error.message)}));
  return true;
});
