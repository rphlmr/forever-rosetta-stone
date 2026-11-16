local _, Addon = ...

local statNames = { "Armor", "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Health", "Mana",
    "Attack Power", "Spell Power", "Critical Strike", "Haste", "Hit", "Dodge", "Parry", "Block", "Defense" }
local translations = {
    enUS = { "Equipped", "Equipped With",
        "If you replace this item, the following stat changes will occur:",
        "If you replace these items, the following stat changes will occur:", statNames },
    frFR = { "Équipé", "Équipé avec",
        "Si vous remplacez cet objet, les caractéristiques suivantes seront modifiées :",
        "Si vous remplacez ces objets, les caractéristiques suivantes seront modifiées :",
        { "Armure", "Force", "Agilité", "Endurance", "Intelligence", "Esprit", "Vie", "Mana",
            "Puissance d’attaque", "Puissance des sorts", "Coup critique", "Hâte", "Toucher", "Esquive", "Parade", "Blocage", "Défense" } },
    deDE = { "Angelegt", "Angelegt mit", "Wenn Ihr diesen Gegenstand ersetzt, ändern sich folgende Werte:",
        "Wenn Ihr diese Gegenstände ersetzt, ändern sich folgende Werte:",
        { "Rüstung", "Stärke", "Beweglichkeit", "Ausdauer", "Intelligenz", "Willenskraft", "Gesundheit", "Mana",
            "Angriffskraft", "Zaubermacht", "Kritischer Trefferwert", "Tempo", "Trefferwert", "Ausweichen", "Parieren", "Blocken", "Verteidigung" } },
    esES = { "Equipado", "Equipado con", "Si reemplazas este objeto, se producirán los siguientes cambios en las estadísticas:",
        "Si reemplazas estos objetos, se producirán los siguientes cambios en las estadísticas:",
        { "Armadura", "Fuerza", "Agilidad", "Aguante", "Intelecto", "Espíritu", "Salud", "Maná",
            "Poder de ataque", "Poder con hechizos", "Golpe crítico", "Celeridad", "Golpe", "Esquivar", "Parar", "Bloquear", "Defensa" } },
    itIT = { "Equipaggiato", "Equipaggiato con", "Sostituendo questo oggetto, le statistiche cambieranno come segue:",
        "Sostituendo questi oggetti, le statistiche cambieranno come segue:",
        { "Armatura", "Forza", "Agilità", "Tempra", "Intelletto", "Spirito", "Salute", "Mana",
            "Potenza d'attacco", "Potenza magica", "Colpo critico", "Celerità", "Impatto", "Schivata", "Parata", "Blocco", "Difesa" } },
    ptBR = { "Equipado", "Equipado com", "Se você substituir este item, ocorrerão as seguintes mudanças nos atributos:",
        "Se você substituir estes itens, ocorrerão as seguintes mudanças nos atributos:",
        { "Armadura", "Força", "Agilidade", "Vigor", "Intelecto", "Espírito", "Vida", "Mana",
            "Poder de Ataque", "Poder Mágico", "Acerto Crítico", "Aceleração", "Acerto", "Esquiva", "Aparo", "Bloqueio", "Defesa" } },
    ruRU = { "Надето", "Надето вместе с", "При замене этого предмета характеристики изменятся следующим образом:",
        "При замене этих предметов характеристики изменятся следующим образом:",
        { "Броня", "Сила", "Ловкость", "Выносливость", "Интеллект", "Дух", "Здоровье", "Мана",
            "Сила атаки", "Сила заклинаний", "Критический удар", "Скорость", "Меткость", "Уклонение", "Парирование", "Блокирование", "Защита" } },
    ukUA = { "Споряджено", "Споряджено разом із", "Якщо замінити цей предмет, характеристики зміняться так:",
        "Якщо замінити ці предмети, характеристики зміняться так:",
        { "Броня", "Сила", "Спритність", "Витривалість", "Інтелект", "Дух", "Здоров’я", "Мана",
            "Сила атаки", "Сила заклять", "Критичний удар", "Швидкість", "Влучність", "Ухилення", "Парирування", "Блокування", "Захист" } },
    plPL = { "Założono", "Założono razem z", "Po zastąpieniu tego przedmiotu statystyki zmienią się następująco:",
        "Po zastąpieniu tych przedmiotów statystyki zmienią się następująco:",
        { "Pancerz", "Siła", "Zręczność", "Wytrzymałość", "Intelekt", "Duch", "Zdrowie", "Mana",
            "Siła ataku", "Moc zaklęć", "Trafienie krytyczne", "Pośpiech", "Trafienie", "Unik", "Parowanie", "Blok", "Obrona" } },
    csCZ = { "Vybaveno", "Vybaveno společně s", "Pokud nahradíte tento předmět, vlastnosti se změní následovně:",
        "Pokud nahradíte tyto předměty, vlastnosti se změní následovně:",
        { "Zbroj", "Síla", "Obratnost", "Výdrž", "Intelekt", "Duch", "Zdraví", "Mana",
            "Síla útoku", "Síla kouzel", "Kritický zásah", "Zrychlení", "Zásah", "Úhyb", "Odražení", "Blokování", "Obrana" } },
    daDK = { "Udstyret", "Udstyret sammen med", "Hvis du erstatter denne genstand, ændres følgende egenskaber:",
        "Hvis du erstatter disse genstande, ændres følgende egenskaber:",
        { "Rustning", "Styrke", "Smidighed", "Udholdenhed", "Intellekt", "Ånd", "Helbred", "Mana",
            "Angrebskraft", "Tryllekraft", "Kritisk træffer", "Hastighed", "Træffer", "Undvigelse", "Parering", "Blokering", "Forsvar" } },
    svSE = { "Utrustad", "Utrustad med", "Om du ersätter detta föremål ändras följande egenskaper:",
        "Om du ersätter dessa föremål ändras följande egenskaper:",
        { "Rustning", "Styrka", "Smidighet", "Uthållighet", "Intellekt", "Ande", "Hälsa", "Mana",
            "Attackkraft", "Trollformelskraft", "Kritisk träff", "Snabbhet", "Träff", "Undvikande", "Parering", "Blockering", "Försvar" } },
    hrHR = { "Opremljeno", "Opremljeno s", "Ako zamijenite ovaj predmet, svojstva će se promijeniti ovako:",
        "Ako zamijenite ove predmete, svojstva će se promijeniti ovako:",
        { "Oklop", "Snaga", "Okretnost", "Izdržljivost", "Intelekt", "Duh", "Zdravlje", "Mana",
            "Snaga napada", "Moć čarolija", "Kritični pogodak", "Brzina", "Pogodak", "Izmicanje", "Pariranje", "Blokiranje", "Obrana" } },
    trTR = { "Kuşanıldı", "Birlikte kuşanıldı", "Bu eşyayı değiştirirseniz özellikler şöyle değişir:",
        "Bu eşyaları değiştirirseniz özellikler şöyle değişir:",
        { "Zırh", "Güç", "Çeviklik", "Dayanıklılık", "Zekâ", "Ruh", "Sağlık", "Mana",
            "Saldırı Gücü", "Büyü Gücü", "Kritik Vuruş", "Hız", "İsabet", "Sıyrılma", "Savuşturma", "Blok", "Savunma" } },
    koKR = { "착용 중", "함께 착용 시", "이 아이템으로 교체하면 능력치가 다음과 같이 변경됩니다:",
        "이 아이템들로 교체하면 능력치가 다음과 같이 변경됩니다:",
        { "방어도", "힘", "민첩성", "체력", "지능", "정신력", "생명력", "마나",
            "전투력", "주문력", "치명타", "가속", "적중", "회피", "무기 막기", "방패 막기", "방어 숙련" } },
    zhCN = { "已装备", "同时装备", "如果替换此物品，下列属性将发生变化：", "如果替换这些物品，下列属性将发生变化：",
        { "护甲", "力量", "敏捷", "耐力", "智力", "精神", "生命值", "法力值",
            "攻击强度", "法术强度", "爆击", "急速", "命中", "躲闪", "招架", "格挡", "防御" } },
    zhTW = { "已裝備", "同時裝備", "如果替換此物品，下列屬性將會改變：", "如果替換這些物品，下列屬性將會改變：",
        { "護甲", "力量", "敏捷", "耐力", "智力", "精神", "生命力", "法力",
            "攻擊強度", "法術能量", "致命一擊", "加速", "命中", "閃躲", "招架", "格擋", "防禦" } },
}
translations.esMX = translations.esES
local textKeys = { EQUIPPED = 1, IF_EQUIPPED_TOGETHER = 2,
    ITEM_DELTA_DESCRIPTION = 3, ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION = 4 }

local function ReadText(text)
    return canaccessallvalues(text) and type(text) == "string"
end

local function GetSummaryLines(source)
    local rows, summary = {}, false
    for index = 1, source:NumLines() do
        local line = source:GetLeftLine(index)
        local text = line and line:GetText()
        if ReadText(text) then
            if text == ITEM_DELTA_DESCRIPTION or text == ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION then summary = true end
            if summary then rows[#rows + 1] = { line = line, text = text } end
        end
    end
    return rows
end

function Addon:TranslateComparisonText(text)
    if not ReadText(text) then return end
    local target = translations[self:GetTargetLocale()]
    if not target then return end
    for key, index in pairs(textKeys) do
        if ReadText(_G[key]) and text == _G[key] then return target[index] end
    end
    -- Delta strings already contain the client-computed signed value and color escapes.
    local labelKeys = { ARMOR = "Armor", STAT_ARMOR = "Armor", HEALTH = "Health", MANA = "Mana",
        DEFENSE = "Defense", DAMAGE_PER_SECOND = "Damage per Second" }
    for index = 1, 6 do
        local key = "RESISTANCE" .. index .. "_NAME"
        labelKeys[key] = self.englishTooltipFormats[key]
    end
    for key, english in pairs(self.englishTooltipFormats) do
        if key:match("^ITEM_MOD_.+_SHORT$") then labelKeys[key] = english end
    end
    local bestNative, bestEnglish, bestKey
    for key, english in pairs(labelKeys) do
        local native = _G[key]
        if ReadText(native) and native ~= "" and text:sub(-#native) == native
            and (not bestNative or #native > #bestNative) then
            bestNative, bestEnglish, bestKey = native, english, key
        end
    end
    if bestNative then
        local translated = self:GetTargetLocale() == "enUS"
        translated = translated and bestEnglish or nil
        for index, name in ipairs(statNames) do
            if name == bestEnglish then translated = target[5][index]; break end
        end
        if not translated and (bestKey == "DAMAGE_PER_SECOND" or bestKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
            or bestKey:match("^RESISTANCE[1-6]_NAME$")) then
            local formats = self.tooltipFormatsByLocale and self.tooltipFormatsByLocale[self:GetTargetLocale()]
            translated = formats and formats[bestKey]
        end
        if translated then return text:sub(1, #text - #bestNative) .. translated end
    end
    local database = ForeverRosettaStoneDB
    if self.GetClientLabel and database and database.GetGlobalStringKeysByText then
        -- Comparison rows retain the client's signed value and markup. Resolve
        -- only an exact owned stat-label suffix, including newly added stats.
        for start in text:gmatch("()%S+") do
            local suffix, translated, ambiguous = text:sub(start), nil, false
            for _, key in ipairs(database:GetGlobalStringKeysByText(suffix, GetLocale()) or {}) do
                if key:match("^ITEM_MOD_.+_SHORT$") then
                    local source = self:GetClientLabel(key, GetLocale())
                    local targetLabel = self:GetClientLabel(key, self:GetTargetLocale())
                    if source == suffix and ReadText(targetLabel) then
                        if translated and translated ~= targetLabel then ambiguous = true end
                        translated = targetLabel
                    end
                end
            end
            if translated and not ambiguous then return text:sub(1, start - 1) .. translated end
        end
    end
    if GetLocale() == self:GetTargetLocale() then return text end
end

function Addon:FillTooltipComparison(spec)
    local source, tip = spec.source, spec.tip
    if tip.CompareHeader then
        local header = source.CompareHeader
        local shown = header and header:IsShown()
        tip.CompareHeader:SetShown(shown and self:GetTooltipDisplayMode(source) == "separate")
        if shown and header.Label and tip.CompareHeader.Label then
            local text = header.Label:GetText()
            tip.CompareHeader.Label:SetText(self:TranslateComparisonText(text) or text)
            self:CopyQuestTextStyle(tip.CompareHeader.Label, header.Label)
            tip.CompareHeader.Label:SetTextScale(header.Label:GetTextScale())
            tip.CompareHeader:SetWidth(tip.CompareHeader.Label:GetWidth() + 30)
        end
    end
    if spec.kind ~= "item" or self.preferences.tooltipCoverage == "name" then return end
    for index, row in ipairs(GetSummaryLines(source)) do
        if index == 1 then tip:AddLine(" ") end
        local red, green, blue = row.line:GetTextColor()
        tip:AddLine(self:TranslateComparisonText(row.text) or row.text, red, green, blue, true)
        local translated = tip:GetLeftLine(tip:NumLines())
        self:CopyQuestTextStyle(translated, row.line)
        if translated then
            translated:SetTextScale(row.line:GetTextScale())
            translated:SetWordWrap(true)
        end
    end
end
