local _, Addon = ...

local keys = { "title", "inspect", "addon", "help", "clear", "save", "copy", "run", "home", "captures",
    "empty", "inspectHint", "addonHint", "shareHint", "pickHint", "stop", "count", "command", "saved",
    "reportHint", "steps", "expected", "actual", "details", "limit", "noCapture", "commands", "recovery",
    "performance", "developer", "languages", "item", "spell", "npc", "quest", "map", "area", "other" }
local translations = {
    enUS = {
        "Debug & reports", "Inspect something", "Addon report", "How to report", "Clear captures", "Save report",
        "Select output", "Run", "Start", "Captures", "Nothing captured yet. Choose Inspect something.",
        "Pick, explore the game, then stop and choose a capture.",
        "Version, languages, settings, and errors for an addon problem.",
        "Copy a report into a GitHub issue. Describe what happened and what you expected.",
        "Explore tooltips, quests, maps, and panels. The console is click-through.", "Stop picking",
        "%d / %d captures", "Command (optional)",
        "Saved. Log out, copy WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua as FRS-debug.txt, and attach the copy to your issue. Keep the original file.",
        "Select output and copy with Ctrl+C / Cmd+C, or Save report without a keyboard. Report at:",
        "Steps to reproduce", "Expected behavior", "Actual behavior", "Diagnostics", "Capture limit reached.",
        "No live capture. Choose Inspect something first.", "Commands and examples", "Settings and recovery",
        "Performance", "Developer tools", "Language codes", "Item", "Spell", "NPC", "Quest", "Map", "Area", "UI" },
    frFR = {
        "Diagnostic et signalement", "Inspecter un élément", "Rapport de l’addon", "Comment signaler", "Effacer les captures", "Enregistrer",
        "Sélectionner le texte", "Exécuter", "Accueil", "Captures", "Aucune capture. Choisissez Inspecter un élément.",
        "Explorez le jeu, arrêtez la capture, puis sélectionnez un élément.",
        "Version, langues, réglages et erreurs pour signaler un problème.",
        "Collez un rapport dans un ticket GitHub. Décrivez le résultat et le comportement attendu.",
        "Explorez les infobulles, quêtes, cartes et fenêtres. La console laisse passer les interactions.", "Arrêter la capture",
        "%d / %d captures", "Commande (facultative)",
        "Enregistré. Déconnectez-vous, copiez WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua sous FRS-debug.txt et joignez la copie au ticket. Gardez l’original.",
        "Sélectionnez le texte puis Ctrl+C / Cmd+C, ou enregistrez sans clavier. Signalez le problème ici :",
        "Étapes pour reproduire", "Comportement attendu", "Comportement observé", "Diagnostic", "Limite de captures atteinte.",
        "Aucune capture. Choisissez d’abord Inspecter un élément.", "Commandes et exemples", "Réglages et récupération",
        "Performances", "Outils de développement", "Codes de langue", "Objet", "Sort", "PNJ", "Quête", "Carte", "Zone", "Interface" },
    deDE = {
        "Diagnose und Berichte", "Element untersuchen", "Addon-Bericht", "Problem melden", "Aufnahmen löschen", "Bericht speichern",
        "Text auswählen", "Ausführen", "Start", "Aufnahmen", "Keine Aufnahmen. Wählt Element untersuchen.",
        "Erkundet das Spiel, beendet die Aufnahme und wählt einen Eintrag.", "Version, Sprachen, Einstellungen und Fehler des Addons.",
        "Fügt den Bericht in ein GitHub-Issue ein. Beschreibt das Ergebnis und eure Erwartung.",
        "Erkundet Tooltips, Quests, Karten und Fenster. Eingaben gehen durch die Konsole hindurch.", "Aufnahme beenden",
        "%d / %d Aufnahmen", "Befehl (optional)",
        "Gespeichert. Ausloggen, WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua als FRS-debug.txt kopieren und die Kopie anhängen. Original behalten.",
        "Text mit Strg+C / Cmd+C kopieren oder ohne Tastatur speichern. Problem melden:",
        "Schritte zum Reproduzieren", "Erwartetes Verhalten", "Tatsächliches Verhalten", "Diagnose", "Aufnahmelimit erreicht.",
        "Keine Aufnahme. Zuerst Element untersuchen wählen.", "Befehle und Beispiele", "Einstellungen und Wiederherstellung",
        "Leistung", "Entwicklerwerkzeuge", "Sprachcodes", "Gegenstand", "Zauber", "NSC", "Quest", "Karte", "Gebiet", "Oberfläche" },
    esES = {
        "Diagnóstico e informes", "Inspeccionar elemento", "Informe del addon", "Cómo informar", "Borrar capturas", "Guardar informe",
        "Seleccionar texto", "Ejecutar", "Inicio", "Capturas", "Sin capturas. Elige Inspeccionar elemento.",
        "Explora el juego, detén la captura y elige una entrada.", "Versión, idiomas, ajustes y errores del addon.",
        "Pega el informe en una incidencia de GitHub. Explica lo ocurrido y lo esperado.",
        "Explora ayudas, misiones, mapas y paneles. La consola permite interactuar a través de ella.", "Detener captura",
        "%d / %d capturas", "Comando (opcional)",
        "Guardado. Cierra sesión, copia WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua como FRS-debug.txt y adjunta la copia. Conserva el original.",
        "Selecciona y copia con Ctrl+C / Cmd+C, o guarda sin teclado. Informa aquí:",
        "Pasos para reproducir", "Comportamiento esperado", "Comportamiento observado", "Diagnóstico", "Límite de capturas alcanzado.",
        "Sin captura. Elige primero Inspeccionar elemento.", "Comandos y ejemplos", "Ajustes y recuperación",
        "Rendimiento", "Herramientas de desarrollo", "Códigos de idioma", "Objeto", "Hechizo", "PNJ", "Misión", "Mapa", "Zona", "Interfaz" },
    itIT = {
        "Diagnostica e segnalazioni", "Ispeziona elemento", "Rapporto dell’addon", "Come segnalare", "Cancella acquisizioni", "Salva rapporto",
        "Seleziona testo", "Esegui", "Inizio", "Acquisizioni", "Nessuna acquisizione. Scegli Ispeziona elemento.",
        "Esplora il gioco, termina l’acquisizione e scegli una voce.", "Versione, lingue, impostazioni ed errori dell’addon.",
        "Incolla il rapporto in una segnalazione GitHub. Descrivi il risultato e cosa ti aspettavi.",
        "Esplora descrizioni, missioni, mappe e pannelli. La console lascia passare le interazioni.", "Termina acquisizione",
        "%d / %d acquisizioni", "Comando (facoltativo)",
        "Salvato. Disconnettiti, copia WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua come FRS-debug.txt e allega la copia. Conserva l’originale.",
        "Seleziona e copia con Ctrl+C / Cmd+C, oppure salva senza tastiera. Segnala qui:",
        "Passaggi per riprodurre", "Comportamento previsto", "Comportamento effettivo", "Diagnostica", "Limite di acquisizioni raggiunto.",
        "Nessuna acquisizione. Scegli prima Ispeziona elemento.", "Comandi ed esempi", "Impostazioni e ripristino",
        "Prestazioni", "Strumenti per sviluppatori", "Codici lingua", "Oggetto", "Incantesimo", "PNG", "Missione", "Mappa", "Zona", "Interfaccia" },
    ptBR = {
        "Diagnóstico e relatos", "Inspecionar elemento", "Relatório do addon", "Como relatar", "Limpar capturas", "Salvar relatório",
        "Selecionar texto", "Executar", "Início", "Capturas", "Nenhuma captura. Escolha Inspecionar elemento.",
        "Explore o jogo, pare a captura e escolha uma entrada.", "Versão, idiomas, configurações e erros do addon.",
        "Cole o relatório em uma issue do GitHub. Descreva o ocorrido e o resultado esperado.",
        "Explore dicas, missões, mapas e painéis. O console deixa as interações passarem.", "Parar captura",
        "%d / %d capturas", "Comando (opcional)",
        "Salvo. Desconecte-se, copie WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua como FRS-debug.txt e anexe a cópia. Mantenha o original.",
        "Selecione e copie com Ctrl+C / Cmd+C, ou salve sem teclado. Relate aqui:",
        "Passos para reproduzir", "Comportamento esperado", "Comportamento observado", "Diagnóstico", "Limite de capturas atingido.",
        "Sem captura. Escolha primeiro Inspecionar elemento.", "Comandos e exemplos", "Configurações e recuperação",
        "Desempenho", "Ferramentas de desenvolvimento", "Códigos de idioma", "Item", "Feitiço", "PNJ", "Missão", "Mapa", "Área", "Interface" },
    ruRU = {
        "Диагностика и отчёты", "Исследовать элемент", "Отчёт об аддоне", "Как сообщить", "Очистить записи", "Сохранить отчёт",
        "Выделить текст", "Выполнить", "Начало", "Записи", "Записей нет. Выберите исследование элемента.",
        "Исследуйте игру, остановите запись и выберите элемент.", "Версия, языки, настройки и ошибки аддона.",
        "Вставьте отчёт в обращение на GitHub. Опишите результат и ожидаемое поведение.",
        "Открывайте подсказки, задания, карты и окна. Консоль пропускает нажатия.", "Остановить запись",
        "%d / %d записей", "Команда (необязательно)",
        "Сохранено. Выйдите из игры, скопируйте WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua как FRS-debug.txt и приложите копию. Сохраните оригинал.",
        "Выделите текст и нажмите Ctrl+C / Cmd+C или сохраните без клавиатуры. Сообщить:",
        "Шаги воспроизведения", "Ожидаемое поведение", "Фактическое поведение", "Диагностика", "Достигнут предел записей.",
        "Нет записи. Сначала выберите исследование элемента.", "Команды и примеры", "Настройки и восстановление",
        "Производительность", "Инструменты разработчика", "Коды языков", "Предмет", "Заклинание", "НИП", "Задание", "Карта", "Область", "Интерфейс" },
    koKR = {
        "진단 및 문제 보고", "대상 살펴보기", "애드온 보고서", "문제 보고 방법", "기록 지우기", "보고서 저장",
        "텍스트 선택", "실행", "시작", "기록", "기록이 없습니다. 대상 살펴보기를 선택하세요.",
        "게임을 살펴본 뒤 기록을 중지하고 항목을 선택하세요.", "애드온 버전, 언어, 설정 및 오류를 확인합니다.",
        "GitHub 이슈에 보고서를 붙여넣고 실제 결과와 예상 결과를 설명하세요.",
        "툴팁, 퀘스트, 지도 및 창을 살펴보세요. 콘솔을 통해 뒤쪽 화면을 조작할 수 있습니다.", "기록 중지",
        "%d / %d개 기록", "명령어 (선택 사항)",
        "저장되었습니다. 로그아웃 후 WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua를 FRS-debug.txt로 복사하여 이슈에 첨부하세요. 원본은 유지하세요.",
        "텍스트 선택 후 Ctrl+C / Cmd+C로 복사하거나 키보드 없이 저장하세요. 문제 보고:",
        "재현 단계", "예상 동작", "실제 동작", "진단 정보", "기록 한도에 도달했습니다.",
        "기록이 없습니다. 먼저 대상 살펴보기를 선택하세요.", "명령어 및 예시", "설정 및 복구",
        "성능", "개발자 도구", "언어 코드", "아이템", "주문", "NPC", "퀘스트", "지도", "지역", "인터페이스" },
    zhCN = {
        "诊断与问题报告", "检查目标", "插件报告", "如何报告", "清除记录", "保存报告",
        "选择文本", "运行", "开始", "记录", "暂无记录。请选择检查目标。",
        "浏览游戏内容，停止记录后选择一个条目。", "查看插件版本、语言、设置和错误。",
        "将报告粘贴到 GitHub 问题中，说明实际结果和预期结果。",
        "浏览提示、任务、地图和面板。操作可穿过控制台。", "停止记录",
        "%d / %d 条记录", "命令（可选）",
        "已保存。登出后，将 WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua 复制为 FRS-debug.txt 并附加到问题中。请保留原文件。",
        "选择文本后按 Ctrl+C / Cmd+C 复制，或无需键盘保存。报告地址：",
        "重现步骤", "预期行为", "实际行为", "诊断信息", "已达到记录上限。",
        "暂无记录。请先选择检查目标。", "命令与示例", "设置与恢复",
        "性能", "开发者工具", "语言代码", "物品", "法术", "NPC", "任务", "地图", "区域", "界面" },
    zhTW = {
        "診斷與問題回報", "檢查目標", "插件報告", "如何回報", "清除記錄", "儲存報告",
        "選取文字", "執行", "開始", "記錄", "暫無記錄。請選擇檢查目標。",
        "瀏覽遊戲內容，停止記錄後選擇一個項目。", "查看插件版本、語言、設定和錯誤。",
        "將報告貼到 GitHub 問題中，說明實際結果和預期結果。",
        "瀏覽提示、任務、地圖和面板。操作可穿過主控台。", "停止記錄",
        "%d / %d 筆記錄", "指令（選用）",
        "已儲存。登出後，將 WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua 複製為 FRS-debug.txt 並附加到問題中。請保留原始檔案。",
        "選取文字後按 Ctrl+C / Cmd+C 複製，或無需鍵盤儲存。回報網址：",
        "重現步驟", "預期行為", "實際行為", "診斷資訊", "已達記錄上限。",
        "暫無記錄。請先選擇檢查目標。", "指令與範例", "設定與復原",
        "效能", "開發者工具", "語言代碼", "物品", "法術", "NPC", "任務", "地圖", "區域", "介面" },
}
translations.esMX = translations.esES
Addon.debugTranslations = translations
local invalid = {
    enUS = "Unknown command or invalid ID", frFR = "Commande inconnue ou identifiant invalide",
    deDE = "Unbekannter Befehl oder ungültige ID", esES = "Comando desconocido o ID no válido",
    esMX = "Comando desconocido o ID no válido", itIT = "Comando sconosciuto o ID non valido",
    ptBR = "Comando desconhecido ou ID inválido", ruRU = "Неизвестная команда или неверный ID",
    koKR = "알 수 없는 명령어 또는 잘못된 ID", zhCN = "未知命令或无效 ID", zhTW = "未知指令或無效 ID",
}
local helpButton = { enUS = "Help", frFR = "Aide", deDE = "Hilfe", esES = "Ayuda", esMX = "Ayuda",
    itIT = "Aiuto", ptBR = "Ajuda", ruRU = "Помощь", koKR = "도움말", zhCN = "帮助", zhTW = "說明" }
local surfaceKeys = { "mount", "pet", "talent", "stat", "mapMenu", "tracking", "playerLocation" }
local surfaces = {
    enUS = { "Mount", "Pet", "Talent", "Stat", "Map menu", "Tracking", "Player location" },
    frFR = { "Monture", "Mascotte", "Talent", "Caractéristique", "Menu de carte", "Suivi", "Position du joueur" },
    deDE = { "Reittier", "Haustier", "Talent", "Attribut", "Kartenmenü", "Aufspüren", "Spielerposition" },
    esES = { "Montura", "Mascota", "Talento", "Estadística", "Menú del mapa", "Rastreo", "Ubicación del jugador" },
    itIT = { "Cavalcatura", "Mascotte", "Talento", "Statistica", "Menu mappa", "Ricerca", "Posizione giocatore" },
    ptBR = { "Montaria", "Mascote", "Talento", "Atributo", "Menu do mapa", "Rastreamento", "Localização do jogador" },
    ruRU = { "Транспорт", "Питомец", "Талант", "Характеристика", "Меню карты", "Поиск", "Положение игрока" },
    koKR = { "탈것", "애완동물", "특성", "능력치", "지도 메뉴", "추적", "플레이어 위치" },
    zhCN = { "坐骑", "宠物", "天赋", "属性", "地图菜单", "追踪", "玩家位置" },
    zhTW = { "坐騎", "寵物", "天賦", "屬性", "地圖選單", "追蹤", "玩家位置" },
}
surfaces.esMX = surfaces.esES

local displayKeys = { "display", "recipe", "displayInput", "displayShow", "displayPin", "displayTarget",
    "displayHide", "displayHint", "displayInvalid", "displayNoTarget", "displayCombat", "displayPaused" }
local displayTexts = {
    enUS = { "Display", "Craft recipe", "Selected type: ID or matching link", "Show tooltip", "Pin tooltip", "Show target",
        "Hide tooltips", "Choose a type for an example, or enter an ID/link. Showing closes the console. Recipes use crafting spell IDs; scrolls and crafted results use Item. Client data must be available.",
        "Enter a positive ID or a link matching the selected type.", "Select a target first.", "Leave combat first.", "Reset the addon before displaying tooltips." },
    frFR = { "Afficher", "Recette", "Type choisi : identifiant ou lien correspondant", "Voir l’infobulle", "Épingler", "Voir la cible",
        "Masquer les bulles", "Choisissez un type pour un exemple, ou entrez un identifiant/lien. L’affichage ferme la console. Recettes : identifiant du sort de fabrication. Parchemins et objets fabriqués : Objet. Les données doivent être disponibles dans le client.",
        "Entrez un identifiant positif ou un lien du type sélectionné.", "Sélectionnez d’abord une cible.", "Quittez d’abord le combat.", "Réinitialisez l’addon avant d’afficher des infobulles." },
    deDE = { "Anzeigen", "Rezept", "Gewählter Typ: ID oder passender Link", "Tooltip zeigen", "Anheften", "Ziel zeigen",
        "Tooltips ausblenden", "Typ für ein Beispiel wählen oder ID/Link eingeben. Die Anzeige schließt die Konsole. Rezepte verwenden Herstellungszauber-IDs; Schriftrollen und Ergebnisse verwenden Gegenstand. Clientdaten müssen verfügbar sein.",
        "Positive ID oder Link des gewählten Typs eingeben.", "Zuerst ein Ziel wählen.", "Zuerst den Kampf verlassen.", "Addon vor der Anzeige zurücksetzen." },
    esES = { "Mostrar", "Receta", "Tipo elegido: ID o enlace correspondiente", "Ver descripción", "Fijar", "Ver objetivo",
        "Ocultar ayudas", "Elige un tipo para un ejemplo o introduce un ID/enlace. Mostrar cierra la consola. Las recetas usan IDs de hechizos de fabricación; pergaminos y resultados usan Objeto. Los datos deben estar disponibles en el cliente.",
        "Introduce un ID positivo o un enlace del tipo seleccionado.", "Selecciona un objetivo primero.", "Sal del combate primero.", "Reinicia el addon antes de mostrar ayudas." },
    itIT = { "Mostra", "Ricetta", "Tipo scelto: ID o collegamento corrispondente", "Mostra tooltip", "Fissa", "Mostra bersaglio",
        "Nascondi tooltip", "Scegli un tipo per un esempio o inserisci ID/link. La visualizzazione chiude la console. Le ricette usano ID di incantesimi di creazione; pergamene e risultati usano Oggetto. I dati devono essere disponibili nel client.",
        "Inserisci un ID positivo o un link del tipo selezionato.", "Seleziona prima un bersaglio.", "Esci prima dal combattimento.", "Reimposta l’addon prima di mostrare tooltip." },
    ptBR = { "Exibir", "Receita", "Tipo escolhido: ID ou link correspondente", "Exibir dica", "Fixar", "Exibir alvo",
        "Ocultar dicas", "Escolha um tipo para um exemplo ou insira ID/link. Exibir fecha o console. Receitas usam IDs de feitiços de fabricação; pergaminhos e resultados usam Item. Os dados precisam estar disponíveis no cliente.",
        "Insira um ID positivo ou link do tipo selecionado.", "Selecione um alvo primeiro.", "Saia do combate primeiro.", "Reinicie o addon antes de exibir dicas." },
    ruRU = { "Показать", "Рецепт", "Выбранный тип: ID или соответствующая ссылка", "Подсказка", "Закрепить", "Показать цель",
        "Скрыть подсказки", "Выберите тип для примера или введите ID/ссылку. Показ закрывает консоль. Рецепты используют ID заклинаний создания; свитки и результаты — Предмет. Данные должны быть доступны клиенту.",
        "Введите положительный ID или ссылку выбранного типа.", "Сначала выберите цель.", "Сначала выйдите из боя.", "Сначала сбросьте аддон." },
    koKR = { "표시", "제작법", "선택한 유형: ID 또는 해당 링크", "툴팁 표시", "고정", "대상 표시",
        "툴팁 숨기기", "유형을 선택해 예시를 보거나 ID/링크를 입력하세요. 표시하면 콘솔이 닫힙니다. 제작법은 제작 주문 ID를 사용합니다. 두루마리와 제작 결과는 아이템을 선택하세요. 클라이언트 데이터가 필요합니다.",
        "양수 ID 또는 선택한 유형의 링크를 입력하세요.", "먼저 대상을 선택하세요.", "먼저 전투를 종료하세요.", "먼저 애드온을 초기화하세요." },
    zhCN = { "显示", "制作配方", "所选类型：ID 或对应链接", "显示提示", "固定提示", "显示目标",
        "隐藏提示", "选择类型查看示例，或输入 ID/链接。显示时关闭控制台。配方使用制作法术 ID；卷轴和成品请选择物品。需要客户端中可用的数据。",
        "请输入正数 ID 或所选类型的链接。", "请先选择目标。", "请先脱离战斗。", "请先重置插件。" },
    zhTW = { "顯示", "製作配方", "所選類型：ID 或對應連結", "顯示提示", "固定提示", "顯示目標",
        "隱藏提示", "選擇類型查看範例，或輸入 ID/連結。顯示時關閉主控台。配方使用製作法術 ID；卷軸和成品請選擇物品。需要用戶端中可用的資料。",
        "請輸入正數 ID 或所選類型的連結。", "請先選擇目標。", "請先脫離戰鬥。", "請先重設插件。" },
}
displayTexts.esMX = displayTexts.esES
local componentTabs = { enUS = "UI components", frFR = "Composants d’interface",
    deDE = "UI-Komponenten", esES = "Componentes de IU", esMX = "Componentes de IU", itIT = "Componenti UI",
    ptBR = "Componentes da IU", ruRU = "Компоненты интерфейса", koKR = "UI 구성 요소", zhCN = "界面组件", zhTW = "介面元件" }
local consoleTabs = { enUS = "Console", frFR = "Console", deDE = "Konsole", esES = "Consola",
    esMX = "Consola", itIT = "Console", ptBR = "Console", ruRU = "Консоль", koKR = "콘솔", zhCN = "控制台", zhTW = "主控台" }
local optionalInputs = { enUS = "Optional ID or link", frFR = "Identifiant ou lien facultatif",
    deDE = "Optionale ID oder Link", esES = "ID o enlace opcional", esMX = "ID o enlace opcional", itIT = "ID o link facoltativo",
    ptBR = "ID ou link opcional", ruRU = "ID или ссылка (необязательно)", koKR = "ID 또는 링크 (선택)", zhCN = "ID 或链接（可选）", zhTW = "ID 或連結（選填）" }

local gossipTexts = {
    enUS = "Dialogue", frFR = "Dialogue",
    deDE = "Dialog", esES = "Diálogo",
    esMX = "Diálogo", itIT = "Dialogo",
    ptBR = "Diálogo", ruRU = "Диалог",
    koKR = "대화", zhCN = "对话", zhTW = "對話",
}

function Addon:DebugText(key, ...)
    if key == "gossip" then
        return gossipTexts[GetLocale()] or gossipTexts.enUS
    end
    if key == "clearErrorLog" then
        local labels = { enUS = "Clear error log", frFR = "Effacer les erreurs", deDE = "Fehlerlog löschen",
            esES = "Borrar errores", esMX = "Borrar errores", itIT = "Cancella errori", ptBR = "Limpar erros",
            ruRU = "Очистить ошибки", koKR = "오류 기록 지우기", zhCN = "清除错误记录", zhTW = "清除錯誤記錄" }
        return labels[GetLocale()] or labels.enUS
    end
    if key == "errorLog" then
        local labels = { enUS = "Error log", frFR = "Journal d’erreurs", deDE = "Fehlerprotokoll",
            esES = "Registro de errores", esMX = "Registro de errores", itIT = "Registro errori",
            ptBR = "Registro de erros", ruRU = "Журнал ошибок", koKR = "오류 기록",
            zhCN = "错误日志", zhTW = "錯誤記錄" }
        return labels[GetLocale()] or labels.enUS
    end
    local previewKeys = { comparison = 1, previewSeparate = 2, previewStacked = 3, previewLayout = 4 }
    if previewKeys[key] then
        local labels = {
            enUS = { "Compare equipped", "Side by side", "Stacked", "Translation layout" },
            frFR = { "Comparer l’équipement", "Côte à côte", "Empilé", "Affichage de la traduction" },
            deDE = { "Ausrüstung vergleichen", "Nebeneinander", "Gestapelt", "Übersetzungslayout" },
            esES = { "Comparar equipo", "Lado a lado", "Apilado", "Diseño de traducción" },
            esMX = { "Comparar equipo", "Lado a lado", "Apilado", "Diseño de traducción" },
            itIT = { "Confronta equipaggiato", "Affiancato", "Impilato", "Layout traduzione" },
            ptBR = { "Comparar equipado", "Lado a lado", "Empilhado", "Layout da tradução" },
            ruRU = { "Сравнить экипировку", "Рядом", "Вместе", "Вид перевода" },
            koKR = { "착용 장비 비교", "나란히", "통합", "번역 표시 방식" },
            zhCN = { "对比已装备", "并排", "堆叠", "翻译布局" },
            zhTW = { "比較已裝備", "並排", "堆疊", "翻譯版面" },
        }
        return (labels[GetLocale()] or labels.enUS)[previewKeys[key]]
    end
    if key == "previewReturn" then
        local labels = { enUS = "Back to debug tools", frFR = "Retour aux outils de diagnostic",
            deDE = "Zurück zur Diagnose", esES = "Volver al diagnóstico", esMX = "Volver al diagnóstico",
            itIT = "Torna alla diagnostica", ptBR = "Voltar ao diagnóstico", ruRU = "Назад к диагностике",
            koKR = "진단 도구로 돌아가기", zhCN = "返回调试工具", zhTW = "返回偵錯工具" }
        return labels[GetLocale()] or labels.enUS
    end
    if key == "display" then return componentTabs[GetLocale()] or componentTabs.enUS end
    if key == "consoleTab" then return consoleTabs[GetLocale()] or consoleTabs.enUS end
    if key == "displayInput" then return optionalInputs[GetLocale()] or optionalInputs.enUS end
    for index, name in ipairs(displayKeys) do
        if name == key then return (displayTexts[GetLocale()] or displayTexts.enUS)[index] end
    end
    if key == "invalid" then return invalid[GetLocale()] or invalid.enUS end
    if key == "helpButton" then return helpButton[GetLocale()] or helpButton.enUS end
    for index, name in ipairs(surfaceKeys) do
        if name == key then return (surfaces[GetLocale()] or surfaces.enUS)[index] end
    end
    local locale = translations[GetLocale()] or translations.enUS
    for index, name in ipairs(keys) do
        if name == key then
            local text = locale[index]
            return select("#", ...) > 0 and string.format(text, ...) or text
        end
    end
    error("Unknown debug text: " .. tostring(key))
end

function Addon:GetDebugKindLabel(kind)
    local labels = { item = "item", spell = "spell", talent = "talent", mount = "mount", npc = "npc", pet = "pet",
        quest = "quest", questOffer = "quest", questTracker = "quest", questInteraction = "quest", minimapQuest = "quest",
        map = "map", playerLocation = "playerLocation", area = "area", minimapLocation = "area",
        mapDropdown = "mapMenu", trackingMenu = "tracking", characterStat = "stat", gossip = "gossip" }
    return self:DebugText(labels[kind] or "other")
end
