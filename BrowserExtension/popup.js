// В storage только выбор языков; результат остаётся в памяти текущего popup.
const source = document.getElementById("source"), target = document.getElementById("target");
const status = document.getElementById("status"), result = document.getElementById("result");
const names = new Intl.DisplayNames(["ru"],{type:"language"});
source.add(new Option("Определить язык","auto"));
for (const code of ["ar","de","en","es","fr","hi","id","it","ja","ko","nl","pl","pt","ru","th","tr","uk","vi","zh"]) {
  source.add(new Option(names.of(code),code)); target.add(new Option(names.of(code),code));
}
chrome.storage.local.get({source:"auto",target:"ru"}).then(value=>{source.value=value.source;target.value=value.target;});
for(const field of [source,target]) field.addEventListener("change",()=>chrome.storage.local.set({source:source.value,target:target.value}));
const errors = {connection_lost:"Связь с Koto потеряна. Повторите действие.",native_host_unavailable:"Установите native host из настроек Koto.",
  unsupported_page:"На этой странице перевод недоступен.",cancelled:"Отменено.",timeout:"Перевод занял слишком много времени.",
  models_missing:"Языковые ресурсы Apple недоступны. В Koto выберите ту же пару языков и нажмите «Перевести». Если появится «Подготовить языки», выполните подготовку. Затем повторите действие здесь.",translation_failed:"Движок не выполнил перевод. Проверьте Koto.",
  invalid_or_busy:"Нет выделения, слишком длинный текст или движок занят.",cloud_not_allowed:"Разрешите облачный перевод браузера в Koto."};
for(const action of ["selection","page","clear","cancel"]) document.getElementById(action).addEventListener("click",async()=>{
  status.textContent="Выполняется…"; result.textContent="";
  try {
    const response=await chrome.runtime.sendMessage({action,source:source.value,target:target.value});
    if(!response?.ok) throw new Error(response?.error || "bridge_error");
    status.textContent=response.message || "Готово";
    result.textContent=response.text || "";
  } catch(error) { status.textContent=errors[error.message] || "Проверьте Koto и подключение браузерного моста."; }
});
