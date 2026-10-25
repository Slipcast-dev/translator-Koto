// Chrome сам выбирает региональный/общий каталог и резервный default_locale.
// Маркер берётся из выбранного каталога: неподдерживаемый язык Chrome получает
// английские подписи языков вместе с английским интерфейсом.
export const uiLocale = chrome.i18n.getMessage("ui_language") === "ru" ? "ru" : "en";

export function message(key, substitutions = []) {
  const value = chrome.i18n.getMessage(key, substitutions);
  // Отсутствующий ключ не должен показывать пустую строку или внутренний код.
  return value || chrome.i18n.getMessage("error_bridge_error") ||
    "Check Koto and the browser bridge connection.";
}

const errorCodes = new Set([
  "connection_lost", "native_host_unavailable", "unsupported_page", "cancelled",
  "timeout", "models_missing", "translation_failed", "invalid_or_busy",
  "cloud_not_allowed", "excluded_page", "busy", "duplicate_request",
  "invalid_request", "invalid_language", "invalid_action", "bridge_error",
]);

export function errorMessage(code) {
  // Сообщение внешнего RPC не используется как имя произвольной UI-команды.
  return message(errorCodes.has(code) ? "error_" + code : "error_bridge_error");
}

export function completionMessage(response) {
  switch (response.status) {
    case "cancelled": return message("result_cancelled");
    case "cleared": return message("result_cleared");
    case "page_translated": {
      if (!Number.isSafeInteger(response.count) || response.count < 0) {
        return message("error_bridge_error");
      }
      const form = new Intl.PluralRules(uiLocale).select(response.count);
      const count = new Intl.NumberFormat().format(response.count);
      return message("page_translated_" + form, [count]);
    }
    default: return message("done");
  }
}

export function localizeDocument(document) {
  document.documentElement.lang = uiLocale;
  document.documentElement.dir = "ltr"; // В первой версии поддерживаются ru/en.
  for (const element of document.querySelectorAll("[data-i18n]")) {
    // В каталоге хранится текст, а не HTML: перевод не создаёт DOM-разметку.
    element.textContent = message(element.dataset.i18n);
  }
}
