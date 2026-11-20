local _, Addon = ...

local text = {
    enUS = {
        title = "Sorry we missed it", summary = "A page is missing from Forever Rosetta Stone. Help us recover it!",
        description = "We haven't translated this quest yet. Your mission: bring us its missing page."
            .. "\n\nUse the button in the quest header to prepare a report. In the report window, select Copy report,"
            .. " then press Ctrl+C / Cmd+C on your keyboard."
            .. "\n\nOpen a GitHub issue, paste the report, and describe the problem.",
        questID = "Quest ID: ", beer = "Beer",
    },
    frFR = {
        title = "Désolés pour cet oubli", summary = "Une page manque à Forever Rosetta Stone. Aidez-nous à la retrouver !",
        description = "Nous n'avons pas encore traduit cette quête. Votre mission : nous rapporter sa page manquante."
            .. "\n\nUtilisez le bouton dans l'en-tête de la quête pour préparer un rapport. Dans la fenêtre du rapport,"
            .. " sélectionnez Copy report, puis appuyez sur Ctrl+C / Cmd+C au clavier."
            .. "\n\nOuvrez un ticket GitHub, collez le rapport et décrivez le problème.",
        questID = "ID de quête : ", beer = "Bière",
    },
    deDE = {
        title = "Entschuldigt das Versehen", summary = "In Forever Rosetta Stone fehlt eine Seite. Helft uns, sie zu finden!",
        description = "Diese Quest ist noch nicht übersetzt. Eure Aufgabe: Bringt uns die fehlende Seite."
            .. "\n\nErstellt über die Schaltfläche oben im Questfenster einen Bericht. Wählt im Berichtsfenster"
            .. " Copy report und drückt Strg+C / Cmd+C auf der Tastatur."
            .. "\n\nÖffnet ein GitHub-Issue, fügt den Bericht ein und beschreibt das Problem.",
        questID = "Quest-ID: ", beer = "Bier",
    },
    esES = {
        title = "Perdón por el olvido", summary = "Falta una página en Forever Rosetta Stone. ¡Ayúdanos a recuperarla!",
        description = "Aún no hemos traducido esta misión. Tu objetivo: traernos la página que falta."
            .. "\n\nPrepara un informe con el botón de la cabecera de la misión. En la ventana del informe, selecciona"
            .. " Copy report y pulsa Ctrl+C / Cmd+C en el teclado."
            .. "\n\nAbre una incidencia en GitHub, pega el informe y describe el problema.",
        questID = "ID de misión: ", beer = "Cerveza",
    },
    itIT = {
        title = "Scusa per la dimenticanza", summary = "Manca una pagina di Forever Rosetta Stone. Aiutaci a ritrovarla!",
        description = "Non abbiamo ancora tradotto questa missione. Il tuo obiettivo: riportarci la pagina mancante."
            .. "\n\nPrepara una segnalazione con il pulsante nell'intestazione della missione. Nella finestra, seleziona"
            .. " Copy report e premi Ctrl+C / Cmd+C sulla tastiera."
            .. "\n\nApri una segnalazione su GitHub, incolla il rapporto e descrivi il problema.",
        questID = "ID missione: ", beer = "Birra",
    },
    ptBR = {
        title = "Desculpe pelo esquecimento", summary = "Falta uma página no Forever Rosetta Stone. Ajude-nos a recuperá-la!",
        description = "Ainda não traduzimos esta missão. Seu objetivo: trazer a página que falta."
            .. "\n\nPrepare um relatório pelo botão no cabeçalho da missão. Na janela, selecione Copy report"
            .. " e pressione Ctrl+C / Cmd+C no teclado."
            .. "\n\nAbra uma issue no GitHub, cole o relatório e descreva o problema.",
        questID = "ID da missão: ", beer = "Cerveja",
    },
    ruRU = {
        title = "Простите за упущение", summary = "В Forever Rosetta Stone не хватает страницы. Помогите её найти!",
        description = "Мы ещё не перевели это задание. Ваша цель: принести нам недостающую страницу."
            .. "\n\nПодготовьте отчёт кнопкой в заголовке задания. В окне отчёта выберите Copy report"
            .. " и нажмите Ctrl+C / Cmd+C на клавиатуре."
            .. "\n\nОткройте обращение на GitHub, вставьте отчёт и опишите проблему.",
        questID = "ID задания: ", beer = "Пиво",
    },
    koKR = {
        title = "놓쳐서 죄송합니다", summary = "Forever Rosetta Stone에 한 페이지가 빠져 있습니다. 함께 찾아주세요!",
        description = "아직 번역하지 못한 퀘스트입니다. 빠진 페이지를 가져오는 것이 여러분의 임무입니다."
            .. "\n\n퀘스트 상단의 버튼으로 보고서를 준비하세요. 보고서 창에서 Copy report를 선택한 다음"
            .. " 키보드에서 Ctrl+C / Cmd+C를 누르세요."
            .. "\n\nGitHub 이슈를 열어 보고서를 붙여 넣고 문제를 설명하세요.",
        questID = "퀘스트 ID: ", beer = "맥주",
    },
    zhCN = {
        title = "抱歉，我们遗漏了它", summary = "Forever Rosetta Stone缺少一页。请帮我们找回来！",
        description = "这个任务尚未翻译。你的目标是为我们带回缺失的那一页。"
            .. "\n\n使用任务顶部的按钮准备报告。在报告窗口中选择Copy report，然后按键盘上的Ctrl+C / Cmd+C。"
            .. "\n\n在GitHub上提交问题，粘贴报告并描述遇到的问题。",
        questID = "任务ID：", beer = "啤酒",
    },
    zhTW = {
        title = "抱歉，我們遺漏了它", summary = "Forever Rosetta Stone缺少一頁。請幫我們找回來！",
        description = "這個任務尚未翻譯。你的目標是為我們帶回缺失的那一頁。"
            .. "\n\n使用任務頂部的按鈕準備報告。在報告視窗中選擇Copy report，然後按鍵盤上的Ctrl+C / Cmd+C。"
            .. "\n\n在GitHub上提交問題，貼上報告並描述遇到的問題。",
        questID = "任務ID：", beer = "啤酒",
    },
}

text.esMX = text.esES

function Addon:GetMissingQuestText()
    return text[GetLocale()] or text.enUS
end

function Addon:GetMissingTranslationMessage(kind)
    local french = GetLocale() == "frFR"
    if kind == "gossipOptions" then
        return french and "Des options de dialogue sont indisponibles dans la langue choisie."
            or "Some dialogue options are unavailable in the selected language."
    end
    if kind == "gossip" then
        return french and "La traduction de ce dialogue est indisponible."
            .. "\n\nLe rapport inclut le texte original et les options du dialogue."
            or "The translation for this dialogue is unavailable."
            .. "\n\nThe report includes the original text and dialogue options."
    end
    if french then
        local missing = kind == "book" and "Cette page n’est pas disponible dans la langue choisie."
            or "La traduction de cet écran de quête est indisponible."
        return missing .. "\n\nLe rapport inclut le texte original et les informations disponibles pour identifier ce contenu."
    end
    local missing = kind == "book" and "This page is unavailable in the selected language."
        or "The translation for this quest screen is unavailable."
    return missing .. "\n\nThe report includes the original text and the available details needed to identify this content."
end
