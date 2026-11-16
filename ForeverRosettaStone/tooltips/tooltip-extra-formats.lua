local _, Addon = ...

-- GlobalStrings 1.60.1.70862; cs/da/hr/it/pl/sv/tr/uk targets are AI-authored.
local keys = { "REPAIR_COST", "MINIMUM", "MAXIMUM", "RETRIEVING_DATA", "MAP_TOOLTIP_TIME_LEFT",
    "ACCOUNT_QUEST_LABEL", "AVAILABLE_FOLLOWER_QUEST", "GRANTS_FOLLOWER_XP", "AVAILABLE_QUEST" }
local labels = {
    enUS = { "Repair cost:", "Minimum", "Maximum", "Retrieving data", "Time Left: %s", "Account",
        "Available ally quest", "Grants ally combat experience", "Available quest" },
    deDE = { "Reparaturkosten:", "Minimum", "Maximum", "Rufe Daten ab", "Verbleibende Zeit: %s", "Account",
        "Verfügbare Verbündetenquest", "Gewährt Verbündeten Kampferfahrung", "Verfügbare Quest" },
    esES = { "Coste de la reparación:", "Mínimo", "Máximo", "Obteniendo datos", "Tiempo restante: %s", "Cuenta",
        "Misión de aliado disponible", "Otorga experiencia de combate de aliado", "Misión disponible" },
    esMX = { "Costo de la reparación:", "Mínimo", "Máximo", "Obteniendo datos", "Tiempo restante: %s", "Cuenta",
        "Misión de aliado disponible", "Otorga experiencia en combate de aliado", "Misión disponible" },
    frFR = { "Coût de réparation :", "Minimum", "Maximum", "Récupération de données", "Temps restant : %s", "Compte",
        "Quête d’allié disponible", "Confère à l’allié de l’expérience du combat", "Quête disponible" },
    koKR = { "수리 비용:", "최소", "최대", "데이터 전송 중", "남은 시간: %s", "계정",
        "가능한 동맹 퀘스트", "동맹 전투 경험치 부여", "가능한 퀘스트" },
    ptBR = { "Valor do conserto:", "Mínimo", "Máximo", "Obtendo dados", "Tempo restante: %s", "Conta",
        "Missão de aliado disponível", "Concede experiência de combate ao aliado", "Missão disponível" },
    ruRU = { "Стоимость ремонта:", "Минимум", "Максимум", "Получение данных", "Осталось: %s", "Учетная запись",
        "Доступно задание для союзника", "Дает союзнику боевой опыт", "Доступное задание" },
    zhCN = { "修理花费：", "最小", "最大", "获取数据", "剩余时间：%s", "账号",
        "有可接的盟友任务", "可为盟友提供战斗经验值", "可接任务" },
    zhTW = { "修理花費：", "最小", "最大", "資料讀取中", "剩餘時間：%s", "帳號",
        "可以取得的盟友任務", "賦予盟友戰鬥經驗值", "可以取得的任務" },
    csCZ = { "Cena opravy:", "Minimum", "Maximum", "Načítání dat", "Zbývající čas: %s", "Účet",
        "Dostupný úkol spojence", "Poskytuje spojenci bojové zkušenosti", "Dostupný úkol" },
    daDK = { "Reparationspris:", "Minimum", "Maksimum", "Henter data", "Tid tilbage: %s", "Konto",
        "Tilgængelig allieret opgave", "Giver allierede kamperfaring", "Tilgængelig opgave" },
    hrHR = { "Cijena popravka:", "Minimum", "Maksimum", "Dohvaćanje podataka", "Preostalo vrijeme: %s", "Račun",
        "Dostupan saveznički zadatak", "Daje savezniku borbeno iskustvo", "Dostupan zadatak" },
    itIT = { "Costo di riparazione:", "Minimo", "Massimo", "Recupero dati", "Tempo rimasto: %s", "Account",
        "Missione alleato disponibile", "Fornisce esperienza di combattimento all'alleato", "Missione disponibile" },
    plPL = { "Koszt naprawy:", "Minimum", "Maksimum", "Pobieranie danych", "Pozostały czas: %s", "Konto",
        "Dostępne zadanie sojusznika", "Zapewnia sojusznikowi doświadczenie bojowe", "Dostępne zadanie" },
    svSE = { "Reparationskostnad:", "Minimum", "Maximum", "Hämtar data", "Tid kvar: %s", "Konto",
        "Tillgängligt uppdrag för allierad", "Ger allierad stridserfarenhet", "Tillgängligt uppdrag" },
    trTR = { "Onarım maliyeti:", "En az", "En fazla", "Veriler alınıyor", "Kalan süre: %s", "Hesap",
        "Alınabilir müttefik görevi", "Müttefike savaş deneyimi kazandırır", "Alınabilir görev" },
    ukUA = { "Вартість ремонту:", "Мінімум", "Максимум", "Отримання даних", "Залишилося часу: %s", "Обліковий запис",
        "Доступне завдання союзника", "Надає союзнику бойовий досвід", "Доступне завдання" },
}

for locale, values in pairs(labels) do
    for index, key in ipairs(keys) do
        Addon.tooltipFormatsByLocale[locale][key] = values[index]
        if locale == "enUS" then Addon.englishTooltipFormats[key] = values[index] end
    end
end

-- GlobalStrings 1.60.1.70862; community-only locales and Italian are AI-authored.
local auraKeys = { "STRING_SCHOOL_MAGIC", "SPELL_TIME_REMAINING_SEC", "SPELL_TIME_REMAINING_MIN",
    "SPELL_TIME_REMAINING_HOURS", "SPELL_TIME_REMAINING_DAYS" }
local auraLabels = {
    csCZ = { "Magie", "Zbývá %d |4sekunda:sekundy:sekund;", "Zbývá %d |4minuta:minuty:minut;",
        "Zbývá %d |4hodina:hodiny:hodin;", "Zbývá %d |4den:dny:dní;" },
    daDK = { "Magi", "%d |4sekund:sekunder; tilbage", "%d |4minut:minutter; tilbage",
        "%d |4time:timer; tilbage", "%d |4dag:dage; tilbage" },
    deDE = { "Magischer", "Noch %d |4Sekunde:Sekunden;", "Noch %d |4Minute:Minuten;",
        "Noch %d |4Stunde:Stunden;", "Noch %d |4Tag:Tage;" },
    enUS = { "Magic", "%d |4second:seconds; remaining", "%d |4minute:minutes; remaining",
        "%d |4hour:hours; remaining", "%d |4day:days; remaining" },
    esES = { "Mágica", "%d |4segundo restante:segundos restantes;", "%d |4minuto restante:minutos restantes;",
        "%d |4hora restante:horas restantes;", "%d |4día restante:días restantes;" },
    esMX = { "Mágica", "%d |4segundo restante:segundos restantes;", "%d |4minuto restante:minutos restantes;",
        "%d |4hora restante:horas restantes;", "%d |4día restante:días restantes;" },
    frFR = { "Magique", "%d |4seconde restante:secondes restantes;", "%d |4minute restante:minutes restantes;",
        "%d |4heure restante:heures restantes;", "%d |4jour restant:jours restants;" },
    hrHR = { "Magija", "Preostalo: %d |4sekunda:sekunde:sekundi;", "Preostalo: %d |4minuta:minute:minuta;",
        "Preostalo: %d |4sat:sata:sati;", "Preostalo: %d |4dan:dana:dana;" },
    itIT = { "Magia", "%d |4secondo rimanente:secondi rimanenti;", "%d |4minuto rimanente:minuti rimanenti;",
        "%d |4ora rimanente:ore rimanenti;", "%d |4giorno rimanente:giorni rimanenti;" },
    koKR = { "마법", "지속시간: %d초", "지속시간: %d분",
        "지속시간: %d시간", "지속시간: %d일" },
    plPL = { "Magia", "Pozostało %d |4sekunda:sekundy:sekund;", "Pozostało %d |4minuta:minuty:minut;",
        "Pozostało %d |4godzina:godziny:godzin;", "Pozostało %d |4dzień:dni:dni;" },
    ptBR = { "Magia", "%d |4segundo restante:segundos restantes;", "%d |4minuto restante:minutos restantes;",
        "%d |4hora:horas; |4restante:restantes;", "%d |4dia restante:dias restantes;" },
    ruRU = { "Магия", "Осталось %d |4секунда:секунды:секунд;", "Осталось %d |4минута:минуты:минут;",
        "Осталось %d |4час:часа:часов;", "Осталось %d |4день:дня:дней;" },
    svSE = { "Magi", "%d |4sekund:sekunder; kvar", "%d |4minut:minuter; kvar",
        "%d |4timme:timmar; kvar", "%d |4dag:dagar; kvar" },
    trTR = { "Büyü", "%d saniye kaldı", "%d dakika kaldı",
        "%d saat kaldı", "%d gün kaldı" },
    ukUA = { "Магія", "Залишилося %d |4секунда:секунди:секунд;", "Залишилося %d |4хвилина:хвилини:хвилин;",
        "Залишилося %d |4година:години:годин;", "Залишилося %d |4день:дні:днів;" },
    zhCN = { "魔法", "剩余%d秒", "剩余%d分钟",
        "剩余%d小时", "剩余%d天" },
    zhTW = { "魔法", "剩餘%d秒", "剩餘%d分鐘",
        "剩餘%d小時", "剩餘%d天" },
}

for locale, values in pairs(auraLabels) do
    for index, key in ipairs(auraKeys) do
        Addon.tooltipFormatsByLocale[locale][key] = values[index]
    end
    Addon.tooltipFormatsByLocale[locale].AURA_DISPEL_Magic = values[1]
end

-- AI-authored dispel labels, keyed by the locale-independent AuraData.dispelName enum.
local dispelTypes = { "Curse", "Disease", "Poison", "Bleed", "Enrage" }
local dispelLabels = {
    enUS = { "Curse", "Disease", "Poison", "Bleed", "Enrage" },
    csCZ = { "Kletba", "Nemoc", "Jed", "Krvácení", "Rozzuření" },
    daDK = { "Forbandelse", "Sygdom", "Gift", "Blødning", "Raseri" },
    deDE = { "Fluch", "Krankheit", "Gift", "Blutung", "Wutanfall" },
    esES = { "Maldición", "Enfermedad", "Veneno", "Sangrado", "Enfurecer" },
    esMX = { "Maldición", "Enfermedad", "Veneno", "Sangrado", "Enfurecer" },
    frFR = { "Malédiction", "Maladie", "Poison", "Saignement", "Enrager" },
    hrHR = { "Kletva", "Bolest", "Otrov", "Krvarenje", "Bijes" },
    itIT = { "Maledizione", "Malattia", "Veleno", "Sanguinamento", "Furia" },
    koKR = { "저주", "질병", "독", "출혈", "격노" },
    plPL = { "Klątwa", "Choroba", "Trucizna", "Krwawienie", "Szał" },
    ptBR = { "Maldição", "Doença", "Veneno", "Sangramento", "Enfurecer" },
    ruRU = { "Проклятие", "Болезнь", "Яд", "Кровотечение", "Исступление" },
    svSE = { "Förbannelse", "Sjukdom", "Gift", "Blödning", "Raseri" },
    trTR = { "Lanet", "Hastalık", "Zehir", "Kanama", "Öfke" },
    ukUA = { "Прокляття", "Хвороба", "Отрута", "Кровотеча", "Шаленство" },
    zhCN = { "诅咒", "疾病", "中毒", "流血", "激怒" },
    zhTW = { "詛咒", "疾病", "中毒", "流血", "狂怒" },
}

for locale, values in pairs(dispelLabels) do
    for index, dispelType in ipairs(dispelTypes) do
        Addon.tooltipFormatsByLocale[locale]["AURA_DISPEL_" .. dispelType] = values[index]
    end
end
