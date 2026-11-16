local _, Addon = ...

-- enUS: FACTION_STANDING_LABEL1..8, client capture build 70938,
-- SHA-256 005570d28807adbe4ab3b3dc22011c4885dd179df1b568a55fe172252ffd6ac8.
-- Target tables combine AI translations with verified rank terms reused where available.
local labels = {
    enUS = {"Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"},
    csCZ = {"Nenáviděný", "Nepřátelský", "Nepřívětivý", "Neutrální", "Přátelský", "Uznávaný", "Uctívaný", "Velebený"},
    daDK = {"Hadet", "Fjendtlig", "Uvenlig", "Neutral", "Venlig", "Æret", "Højt æret", "Ophøjet"},
    deDE = {"Hasserfüllt", "Feindselig", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll", "Ehrfürchtig"},
    esES = {"Odiado", "Hostil", "Antipático", "Neutral", "Amistoso", "Honorable", "Venerado", "Exaltado"},
    esMX = {"Odiado", "Hostil", "Antipático", "Neutral", "Amistoso", "Honorable", "Venerado", "Exaltado"},
    frFR = {"Haï", "Hostile", "Inamical", "Neutre", "Amical", "Honoré", "Révéré", "Exalté"},
    hrHR = {"Omražen", "Neprijateljski", "Nesklon", "Neutralan", "Prijateljski", "Poštovan", "Uvažavan", "Uzvišen"},
    itIT = {"Odiato", "Ostile", "Sfavorevole", "Neutrale", "Amichevole", "Onorato", "Riverito", "Osannato"},
    koKR = {"증오", "적대적", "약간 적대적", "중립", "약간 우호적", "우호적", "매우 우호적", "확고한 동맹"},
    plPL = {"Znienawidzony", "Wrogi", "Nieprzychylny", "Neutralny", "Przyjazny", "Szanowany", "Czczony", "Wywyższony"},
    ptBR = {"Odiado", "Hostil", "Desfavorável", "Tolerado", "Respeitado", "Honrado", "Reverenciado", "Exaltado"},
    ruRU = {"Ненависть", "Враждебность", "Неприязнь", "Равнодушие", "Дружелюбие", "Уважение", "Почтение", "Превознесение"},
    svSE = {"Hatad", "Fientlig", "Ovänlig", "Neutral", "Vänlig", "Ärad", "Vördad", "Upphöjd"},
    trTR = {"Nefret Edilen", "Düşmanca", "Soğuk", "Tarafsız", "Dostane", "Saygın", "Hürmet Edilen", "Yüceltilmiş"},
    ukUA = {"Ненависть", "Ворожість", "Неприязнь", "Байдужість", "Приязнь", "Повага", "Шана", "Звеличення"},
    zhCN = {"仇恨", "敌对", "冷淡", "中立", "友善", "尊敬", "崇敬", "崇拜"},
    zhTW = {"仇恨", "敵對", "冷淡", "中立", "友善", "尊敬", "崇敬", "崇拜"},
}

function Addon:GetFactionStandingLabel(reaction, locale)
    if type(reaction) ~= "number" or reaction % 1 ~= 0 or type(locale) ~= "string" then return nil end
    local localeLabels = labels[locale]
    return localeLabels and localeLabels[reaction] or nil
end
