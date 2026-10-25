// MV3 worker хранит только текущие запросы. Текст не записывается в storage или журнал.
const HOST = "dev.slipcast.koto";
let nativePort = null;
let generation = 0;
const pending = new Map();

function connection() {
  if (nativePort) return nativePort;
  const port = chrome.runtime.connectNative(HOST);
  nativePort = port;
  port.onMessage.addListener((frame) => {
    if (!frame || frame.v !== 1 || typeof frame.id !== "string") return;
    const job = pending.get(frame.id);
    if (!job) return;
    pending.delete(frame.id);
    clearTimeout(job.timer);
    if (frame.type === "translated" && typeof frame.payload?.text === "string") job.resolve(frame.payload.text);
    else job.reject(new Error(frame.payload?.code || "bridge_error"));
  });
  port.onDisconnect.addListener(() => {
    // Читаем lastError, но не выводим потенциально содержащую пути строку в console.
    void chrome.runtime.lastError;
    if (nativePort === port) nativePort = null;
    for (const job of pending.values()) { clearTimeout(job.timer); job.reject(new Error("connection_lost")); }
    pending.clear();
  });
  return port;
}
function translate(text, source, target, pageOrigin) {
  if (!text.trim() || text.length > 20000 || pending.size >= 4) return Promise.reject(new Error("invalid_or_busy"));
  const id = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      try { nativePort?.postMessage({v:1,id:crypto.randomUUID(),type:"cancel",payload:{requestID:id}}); } catch {}
      reject(new Error("timeout"));
    }, 250000);
    pending.set(id, {resolve,reject,timer});
    try { connection().postMessage({v:1,id,type:"translate",payload:{text,source,target,pageOrigin}}); }
    catch { clearTimeout(timer); pending.delete(id); reject(new Error("native_host_unavailable")); }
  });
}
function cancel() {
  generation++;
  for (const [id, job] of pending) {
    try { nativePort?.postMessage({v:1,id:crypto.randomUUID(),type:"cancel",payload:{requestID:id}}); } catch {}
    clearTimeout(job.timer);
    job.reject(new Error("cancelled"));
  }
  pending.clear();
}

async function execute(tabId, func, args=[]) {
  const results = await chrome.scripting.executeScript({target:{tabId},func,args});
  return results[0]?.result;
}
async function activeTab() {
  const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
  if (!tab?.id || !/^https?:\/\//i.test(tab.url || "")) throw new Error("unsupported_page");
  return {tabId:tab.id,pageOrigin:new URL(tab.url).origin};
}
// Внутренний ответ popup содержит код и параметры; язык текста выбирается только в UI.
async function act(message) {
  if (message.action === "cancel") { cancel(); return {ok:true,status:"cancelled"}; }
  const {tabId,pageOrigin} = await activeTab();
  if (message.action === "clear") {
    await execute(tabId, () => {
      for (const record of window.__kotoSlipcastNodes?.values() || []) record.output?.remove();
      window.__kotoSlipcastNodes = undefined;
    });
    return {ok:true,status:"cleared"};
  }
  const source = message.source || "auto", target = message.target || "ru";
  if (!/^(auto|[a-z]{2,3})$/.test(source) || !/^[a-z]{2,3}$/.test(target)) throw new Error("invalid_language");
  cancel();
  const current = generation;
  if (message.action === "selection") {
    const text = await execute(tabId, () => window.getSelection()?.toString() || "");
    const result = await translate(text, source, target, pageOrigin);
    if (generation !== current) throw new Error("cancelled");
    return {ok:true,text:result};
  }
  if (message.action !== "page") throw new Error("invalid_action");
  const segments = await execute(tabId, () => {
    // Только видимые текстовые узлы main frame. Поля ввода и editable content исключены.
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
      records.set(id, {node,original:text,output:null});
      output.push({id,text});
      characters += text.length;
    }
    window.__kotoSlipcastNodes = records;
    return output;
  });
  let completed = 0;
  for (let index=0; index<segments.length; index+=2) {
    if (generation !== current) throw new Error("cancelled");
    const batch = await Promise.all(segments.slice(index,index+2).map(async segment => ({
      id:segment.id,original:segment.text,text:await translate(segment.text,source,target,pageOrigin)
    })));
    if (generation !== current) throw new Error("cancelled");
    completed += await execute(tabId, (batch,target) => {
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
        Object.assign(translated.style,{display:"block",whiteSpace:"pre-wrap",padding:"4px 0",color:"#7656c9",unicodeBidi:"isolate"});
        record.output?.remove();
        record.node.parentNode.insertBefore(translated,record.node.nextSibling);
        record.output = translated;
        applied++;
      }
      return applied;
    }, [batch,target]);
  }
  return {ok:true,status:"page_translated",count:completed};
}
chrome.runtime.onMessage.addListener((message,sender,respond) => {
  // Команды принимает только собственный popup; content scripts не получают native RPC.
  if (sender.id !== chrome.runtime.id || sender.tab) return false;
  act(message).then(respond).catch(error => respond({ok:false,error:String(error.message)}));
  return true;
});
