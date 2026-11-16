local _, Addon = ...

-- Client tooltip formats from build 1.60.1.70862; additional-language labels are AI-authored.
Addon.npcTooltipData = {
    enUS = { formats = { "Level %d", "Level %d Elite", "Level ??", "Level %d %s", "Level %d Elite %s", "Level ?? %s", "Level %d Corpse", "Level ?? Corpse" }, pvp = "PvP" },
    frFR = { formats = { "Niveau %d", "Niveau %d élite", "Niveau ??", "%2$s niveau %1$d", "%2$s élite niveau %1$d", "%s niveau ??", "Cadavre de niveau %d", "Cadavre de niveau ??" }, pvp = "JcJ" },
    deDE = { formats = { "Stufe %d", "Stufe %d Elite", "Stufe ?", "Stufe %1$d %2$s", "Stufe %1$d Elite %2$s", "Stufe ? %s", "Leichnam der Stufe %d", "Stufe ? Leichnam" }, pvp = "PvP" },
    esES = { formats = { "Nivel %d", "Nivel %d Élite", "Nivel ?", "Nivel %d %s", "Nivel %d Élite %s", "Nivel ? %s", "Cadáver de nivel %d", "Cadáver nivel ??" }, pvp = "JcJ" },
    esMX = { formats = { "Nivel %d", "Nivel %d Élite", "Nivel ?", "Nivel %d %s", "Nivel %d Élite %s", "Nivel ? %s", "Cadáver de nivel %d", "Cadáver nivel ?" }, pvp = "JcJ" },
    ptBR = { formats = { "Nível %d", "Nível %d Elite", "Nível ??", "%2$s Nível %1$d", "%2$s Nível %1$d Elite", "%s Nível ??", "Cadáver Nível %d", "Cadáver Nível ??" }, pvp = "JxJ" },
    ruRU = { formats = { "%d-й уровень", "%d-й уровень (элита)", "Уровень ??", "%2$s %1$d-го уровня", "%2$s %1$d-го уровня (элита)", "%s уровня ??", "Труп %d-го уровня", "Труп, уровень ??" }, pvp = "PvP" },
    koKR = { formats = { "레벨 %d", "레벨 %d 정예", "레벨 ??", "레벨 %d %s", "레벨 %d 정예 %s", "레벨 ?? %s", "%d 레벨 시체", "레벨 ?? 시체" }, pvp = "전쟁 참여 중" },
    zhCN = { formats = { "等级 %d", "等级%d 精英", "等级未知", "等级%d %s", "等级%d 精英%s", "等级未知 %s", "等级%d 尸体", "等级未知 尸体" }, pvp = "PvP" },
    zhTW = { formats = { "等級 %d", "等級%d精英", "等級未知", "等級%d%s", "等級%d精英%s", "等級未知%s", "等級%d 屍體", "等級未知的屍體" }, pvp = "PvP" },
    itIT = { formats = { "Livello %d", "Livello %d élite", "Livello ??", "Livello %d %s", "Livello %d élite %s", "Livello ?? %s", "Cadavere di livello %d", "Cadavere di livello ??" }, pvp = "PvP" },
    csCZ = { formats = { "Úroveň %d", "Úroveň %d elita", "Úroveň ??", "Úroveň %d %s", "Úroveň %d elita %s", "Úroveň ?? %s", "Mrtvola úrovně %d", "Mrtvola úrovně ??" }, pvp = "PvP" },
    daDK = { formats = { "Niveau %d", "Niveau %d elite", "Niveau ??", "Niveau %d %s", "Niveau %d elite %s", "Niveau ?? %s", "Lig niveau %d", "Lig niveau ??" }, pvp = "PvP" },
    hrHR = { formats = { "Razina %d", "Razina %d elita", "Razina ??", "Razina %d %s", "Razina %d elita %s", "Razina ?? %s", "Leš razine %d", "Leš razine ??" }, pvp = "PvP" },
    plPL = { formats = { "Poziom %d", "Poziom %d elita", "Poziom ??", "Poziom %d %s", "Poziom %d elita %s", "Poziom ?? %s", "Zwłoki poziomu %d", "Zwłoki poziomu ??" }, pvp = "PvP" },
    svSE = { formats = { "Nivå %d", "Nivå %d elit", "Nivå ??", "Nivå %d %s", "Nivå %d elit %s", "Nivå ?? %s", "Lik på nivå %d", "Lik på nivå ??" }, pvp = "PvP" },
    trTR = { formats = { "Seviye %d", "Seviye %d elit", "Seviye ??", "Seviye %d %s", "Seviye %d elit %s", "Seviye ?? %s", "Seviye %d ceset", "Seviye ?? ceset" }, pvp = "PvP" },
    ukUA = { formats = { "Рівень %d", "Рівень %d еліта", "Рівень ??", "Рівень %d %s", "Рівень %d еліта %s", "Рівень ?? %s", "Труп %d-го рівня", "Труп рівня ??" }, pvp = "PvP" },
}
Addon.npcTooltipSourceLocales = { itIT = "enUS" }
Addon.npcTooltipClassifications = {
    enUS = { "Elite", "Boss" }, frFR = { "Élite", "Boss" },
    deDE = { "Elite", "Boss" }, esES = { "Élite", "Jefe" }, esMX = { "Élite", "Jefe" },
    ptBR = { "Elite", "Chefe" }, ruRU = { "элита", "босс" }, koKR = { "정예", "우두머리" },
    zhCN = { "精英", "首领" }, zhTW = { "精英", "首領" }, itIT = { "Élite", "Capo" },
    csCZ = { "Elita", "Boss" }, daDK = { "Elite", "Boss" }, hrHR = { "Elita", "Vođa" },
    plPL = { "Elita", "Boss" }, svSE = { "Elit", "Boss" }, trTR = { "Elit", "Patron" },
    ukUA = { "Еліта", "Бос" },
}
