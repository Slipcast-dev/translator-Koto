import { completionMessage, errorMessage, localizeDocument, message, uiLocale } from "./i18n.js";

// В storage остаётся только выбор языков; результат живёт в текущем popup.
// Язык интерфейса независим от исходного и целевого языков перевода.
localizeDocument(document);
const source = document.getElementById("source");
const target = document.getElementById("target");
const status = document.getElementById("status");
const result = document.getElementById("result");
const names = new Intl.DisplayNames([uiLocale], { type: "language" });
source.add(new Option(message("detect_language"), "auto"));
for (const code of [
  "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
  "nl", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh",
]) {
  source.add(new Option(names.of(code) || code, code));
  target.add(new Option(names.of(code) || code, code));
}

chrome.storage.local.get({ source: "auto", target: "ru" }).then((value) => {
  source.value = value.source;
  target.value = value.target;
});
for (const field of [source, target]) {
  field.addEventListener("change", () => chrome.storage.local.set({
    source: source.value, target: target.value,
  }));
}

for (const action of ["selection", "page", "clear", "cancel"]) {
  document.getElementById(action).addEventListener("click", async () => {
    status.textContent = message("working");
    result.textContent = "";
    try {
      const response = await chrome.runtime.sendMessage({
        action, source: source.value, target: target.value,
      });
      if (!response?.ok) throw new Error(response?.error || "bridge_error");
      status.textContent = completionMessage(response);
      // Перевод является пользовательскими данными: не локализуем его повторно
      // и не интерпретируем как HTML. Его направление независимо от оболочки.
      result.lang = target.value;
      result.textContent = response.text || "";
    } catch (error) {
      status.textContent = errorMessage(error.message);
    }
  });
}
