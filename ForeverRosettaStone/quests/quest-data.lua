local _, Addon = ...

function Addon:GetQuest(questID)
    local started = self:BeginBenchmarkSample()
    local quest = ForeverRosettaStoneDB:GetQuest(questID, self:GetTargetLocale())
    self:EndBenchmarkSample("quest.lookup", questID, started, quest ~= nil)
    return quest and quest.title and quest or nil
end

local function MatchesLocationHeader(title, nativeName, kind, id)
    if not nativeName then return false end
    if title == nativeName then return true end
    if title:sub(1, #nativeName + 2) ~= nativeName .. " (" then return false end
    local english = kind == "area" and ForeverRosettaStoneDB:GetAreaName(id, "enUS")
        or kind == "map" and ForeverRosettaStoneDB:GetMapName(id, "enUS")
    return english and title == nativeName .. " (" .. english .. ")"
end

local QUEST_HEADER_AREA_TAG = 0x40000000

function Addon:GetQuestHeaderAreaID(header)
    if not header or not header.isHeader or type(header.title) ~= "string" then return end
    local areaID = header.headerSortKey
    if not self:IsReadableEntityID(areaID) then return end
    -- Forever's captured area headers carry bit 30; older headers expose the raw ID.
    -- Only decode this tag, and verify the identity against the live client name.
    if areaID >= QUEST_HEADER_AREA_TAG and areaID < QUEST_HEADER_AREA_TAG * 2 then
        areaID = areaID - QUEST_HEADER_AREA_TAG
    end
    if areaID > 0 and areaID < QUEST_HEADER_AREA_TAG and C_Map.GetAreaInfo
        and MatchesLocationHeader(header.title, C_Map.GetAreaInfo(areaID), "area", areaID) then
        return areaID
    end
end

function Addon:GetQuestHeaderLocationName(header)
    if not header or not header.isHeader or type(header.title) ~= "string" then return end

    local areaID = self:GetQuestHeaderAreaID(header)
    if areaID then
        return ForeverRosettaStoneDB:GetAreaName(areaID, self:GetTargetLocale())
    end
    return self:GetClientMapLocationName(header.title)
end

-- Resolve names only against the live client's structured map tree, never catalog text.
function Addon:GetClientMapLocationName(title)
    if not canaccessallvalues(title) or type(title) ~= "string" or title == "" then return end
    if not C_Map.GetMapChildrenInfo then return end

    local mapID = C_Map.GetBestMapForUnit("player") or WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local seen = {}
    while info and info.parentMapID and info.parentMapID > 0 do
        if seen[info.mapID] then return end
        seen[info.mapID] = true
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if not info then return end

    local matchID
    for _, candidate in ipairs(C_Map.GetMapChildrenInfo(info.mapID, nil, true) or {}) do
        local matches = MatchesLocationHeader(title, candidate.name, "map", candidate.mapID)
        if matches then
            if matchID and matchID ~= candidate.mapID then return end
            matchID = candidate.mapID
        end
    end
    return matchID and ForeverRosettaStoneDB:GetMapName(matchID, self:GetTargetLocale())
end

function Addon:GetHoveredMapLocationName(nativeName)
    local map = WorldMapFrame
    if not canaccessallvalues(nativeName) or type(nativeName) ~= "string" or nativeName == ""
        or not map.IsCanvasMouseFocus or not map:IsCanvasMouseFocus()
        or not map.GetNormalizedCursorPosition then return end

    local mapID = map:GetMapID()
    if not self:IsReadableEntityID(mapID) then return end
    local x, y = map:GetNormalizedCursorPosition()
    if not canaccessallvalues(x, y) or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return end

    -- Verify the displayed label still belongs to this map, rather than a POI.
    local plainName = nativeName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    plainName = plainName:gsub(" %(%d+%-%d+%)$", ""):gsub(" %(%d+%)$", "")
    -- Subzones do not have their own UiMapID. Bind only to area IDs returned for
    -- this cursor position and verify their names against the current client.
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
        and C_Map.GetAreaInfo and type(CreateVector2D) == "function" then
        local ok, areas = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapID, CreateVector2D(x, y))
        if ok and canaccessallvalues(areas) and type(areas) == "table" then
            local found, seen = nil, {}
            for _, areaID in ipairs(areas) do
                if self:IsReadableEntityID(areaID) and not seen[areaID] then
                    seen[areaID] = true
                    local readable, name = pcall(C_Map.GetAreaInfo, areaID)
                    if readable and canaccessallvalues(name) and name == plainName then
                        if found then return end
                        found = areaID
                    end
                end
            end
            if found then return ForeverRosettaStoneDB:GetAreaName(found, self:GetTargetLocale()) end
        end
    end
    if not C_Map.GetMapInfoAtPosition then return end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if not ok or not canaccessallvalues(info) or type(info) ~= "table"
        or not self:IsReadableEntityID(info.mapID) or info.mapID == mapID
        or not canaccessallvalues(info.name) then return end
    if plainName ~= info.name then return end
    return ForeverRosettaStoneDB:GetMapName(info.mapID, self:GetTargetLocale())
end

-- Target-language labels authored for the nine playable classes and eight races.
-- Female forms are supplied where they differ; linguistic review is pending.
local playerLabels = {
    enUS = { "Warrior|Paladin|Hunter|Rogue|Priest|Shaman|Mage|Warlock|Druid", "Human|Orc|Dwarf|Night Elf|Undead|Tauren|Gnome|Troll" },
    deDE = { "Krieger|Paladin|Jäger|Schurke|Priester|Schamane|Magier|Hexenmeister|Druide", "Mensch|Orc|Zwerg|Nachtelf|Untoter|Tauren|Gnom|Troll", "Kriegerin|Paladin|Jägerin|Schurkin|Priesterin|Schamanin|Magierin|Hexenmeisterin|Druidin", "Mensch|Orcin|Zwergin|Nachtelfe|Untote|Tauren|Gnomin|Trollin" },
    esES = { "Guerrero|Paladín|Cazador|Pícaro|Sacerdote|Chamán|Mago|Brujo|Druida", "Humano|Orco|Enano|Elfo de la noche|No-muerto|Tauren|Gnomo|Trol", "Guerrera|Paladina|Cazadora|Pícara|Sacerdotisa|Chamana|Maga|Bruja|Druida", "Humana|Orca|Enana|Elfa de la noche|No-muerta|Tauren|Gnoma|Trol" },
    esMX = { "Guerrero|Paladín|Cazador|Pícaro|Sacerdote|Chamán|Mago|Brujo|Druida", "Humano|Orco|Enano|Elfo de la noche|No-muerto|Tauren|Gnomo|Trol", "Guerrera|Paladina|Cazadora|Pícara|Sacerdotisa|Chamana|Maga|Bruja|Druida", "Humana|Orca|Enana|Elfa de la noche|No-muerta|Tauren|Gnoma|Trol" },
    frFR = { "Guerrier|Paladin|Chasseur|Voleur|Prêtre|Chaman|Mage|Démoniste|Druide", "Humain|Orc|Nain|Elfe de la nuit|Mort-vivant|Tauren|Gnome|Troll", "Guerrière|Paladine|Chasseresse|Voleuse|Prêtresse|Chamane|Mage|Démoniste|Druidesse", "Humaine|Orque|Naine|Elfe de la nuit|Morte-vivante|Tauren|Gnome|Troll" },
    itIT = { "Guerriero|Paladino|Cacciatore|Ladro|Sacerdote|Sciamano|Mago|Stregone|Druido", "Umano|Orco|Nano|Elfo della notte|Non morto|Tauren|Gnomo|Troll", "Guerriera|Paladina|Cacciatrice|Ladra|Sacerdotessa|Sciamana|Maga|Strega|Druida", "Umana|Orca|Nana|Elfa della notte|Non morta|Tauren|Gnoma|Troll" },
    ptBR = { "Guerreiro|Paladino|Caçador|Ladino|Sacerdote|Xamã|Mago|Bruxo|Druida", "Humano|Orc|Anão|Elfo noturno|Morto-vivo|Tauren|Gnomo|Troll", "Guerreira|Paladina|Caçadora|Ladina|Sacerdotisa|Xamã|Maga|Bruxa|Druida", "Humana|Orc|Anã|Elfa noturna|Morta-viva|Tauren|Gnoma|Troll" },
    ruRU = { "Воин|Паладин|Охотник|Разбойник|Жрец|Шаман|Маг|Чернокнижник|Друид", "Человек|Орк|Дворф|Ночной эльф|Нежить|Таурен|Гном|Тролль", "Воительница|Паладин|Охотница|Разбойница|Жрица|Шаманка|Маг|Чернокнижница|Друид", "Человек|Орк|Дворф|Ночная эльфийка|Нежить|Таурен|Гном|Тролль" },
    koKR = { "전사|성기사|사냥꾼|도적|사제|주술사|마법사|흑마법사|드루이드", "인간|오크|드워프|나이트 엘프|언데드|타우렌|노움|트롤" },
    zhCN = { "战士|圣骑士|猎人|潜行者|牧师|萨满祭司|法师|术士|德鲁伊", "人类|兽人|矮人|暗夜精灵|亡灵|牛头人|侏儒|巨魔" },
    zhTW = { "戰士|聖騎士|獵人|盜賊|牧師|薩滿|法師|術士|德魯伊", "人類|獸人|矮人|夜精靈|不死族|牛頭人|地精|食人妖" },
    csCZ = { "Válečník|Paladin|Lovec|Tulák|Kněz|Šaman|Mág|Černokněžník|Druid", "Člověk|Ork|Trpaslík|Noční elf|Nemrtvý|Tauren|Gnóm|Troll", "Válečnice|Paladinka|Lovkyně|Tulačka|Kněžka|Šamanka|Mágyně|Černokněžnice|Druidka", "Člověk|Orkyně|Trpaslice|Noční elfka|Nemrtvá|Taurenka|Gnómka|Trollka" },
    daDK = { "Kriger|Paladin|Jæger|Slyngel|Præst|Shaman|Magiker|Troldmand|Druide", "Menneske|Ork|Dværg|Natelver|Udød|Tauren|Gnom|Trold" },
    hrHR = { "Ratnik|Paladin|Lovac|Lupež|Svećenik|Šaman|Mag|Vještac|Druid", "Čovjek|Ork|Patuljak|Noćni vilenjak|Nemrtvi|Tauren|Gnom|Trol", "Ratnica|Paladinka|Lovkinja|Lupež|Svećenica|Šamanka|Maga|Vještica|Druidkinja", "Čovjek|Orkinja|Patuljica|Noćna vilenjakinja|Nemrtva|Taurenka|Gnomkinja|Trolkinja" },
    ltLT = {
        "Karys|Paladinas|Medžiotojas|Sukčius|Kunigas|Šamanas|Magas|Kerėtojas|Druidas",
        "Žmogus|Orkas|Nykštukas|Nakties elfas|Nemirėlis|Taurenas|Gnomas|Trolis",
        "Karė|Paladinė|Medžiotoja|Sukčiuvė|Kunigė|Šamanė|Magė|Kerėtoja|Druidė",
        "Žmogus|Orkė|Nykštukė|Nakties elfė|Nemirėlė|Taurenė|Gnomė|Trolė",
    },
    plPL = { "Wojownik|Paladyn|Łowca|Łotrzyk|Kapłan|Szaman|Mag|Czarnoksiężnik|Druid", "Człowiek|Ork|Krasnolud|Nocny elf|Nieumarły|Tauren|Gnom|Troll", "Wojowniczka|Paladynka|Łowczyni|Łotrzyca|Kapłanka|Szamanka|Magini|Czarnoksiężniczka|Druidka", "Człowiek|Orczyca|Krasnoludka|Nocna elfka|Nieumarła|Taurenka|Gnomka|Trollka" },
    svSE = { "Krigare|Paladin|Jägare|Skurk|Präst|Schaman|Magiker|Svartkonstnär|Druid", "Människa|Orc|Dvärg|Nattalv|Odöd|Tauren|Gnom|Troll" },
    trTR = { "Savaşçı|Paladin|Avcı|Haydut|Rahip|Şaman|Büyücü|Falcı|Druid", "İnsan|Ork|Cüce|Gece Elfi|Ölümsüz|Tauren|Cücecik|Trol" },
    ukUA = { "Воїн|Паладин|Мисливець|Розбійник|Жрець|Шаман|Маг|Чорнокнижник|Друїд", "Людина|Орк|Дворф|Нічний ельф|Нежить|Таурен|Гном|Троль", "Воїтелька|Паладин|Мисливиця|Розбійниця|Жриця|Шаманка|Магиня|Чорнокнижниця|Друїдка", "Людина|Оркиня|Дворфійка|Нічна ельфійка|Нежить|Тауренка|Гномка|Тролиха" },
}

local classIndexes = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9 }
local raceIndexes = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }
local playerPlaceholderAliases = {
    nom = "name", nombre = "name", ["имя"] = "name",
    klasse = "class", classe = "class", clase = "class",
    volk = "race", raza = "race",
}

local function GetPlayerLabel(locale, kind, token, sex)
    local labels = playerLabels[locale]
    local index = (kind == 1 and classIndexes or raceIndexes)[token or ""]
    if not labels or not index then return nil end
    local list = labels[sex == 3 and kind + 2] or labels[kind]
    local position = 0
    for label in list:gmatch("[^|]+") do
        position = position + 1
        if position == index then return label end
    end
end

function Addon:FormatQuestText(text, questID, targetLocale, allowSentenceSelectors)
    if type(text) ~= "string" or not text:find("%S") then return nil end

    local nativeRace, raceToken = UnitRace("player")
    local nativeClass, classToken = UnitClass("player")
    local locale = targetLocale or self:GetTargetLocale()
    local sex = UnitSex and UnitSex("player")
    local replacements = {
        name = UnitName("player"),
        race = GetPlayerLabel(locale, 2, raceToken, sex),
        class = GetPlayerLabel(locale, 1, classToken, sex),
    }

    if locale == GetLocale() then
        replacements.race = nativeRace or replacements.race
        replacements.class = nativeClass or replacements.class
    end

    local objectives = text:find("%$%d+oa") and questID and C_QuestLog and C_QuestLog.GetQuestObjectives
        and C_QuestLog.GetQuestObjectives(questID)
    local incomplete = false
    local function replace(value)
        if value == nil then incomplete = true end
        return value
    end

    local genderSelector = allowSentenceSelectors and "%$[Gg]([^:;$\n]+):([^:;$\n]+);"
        or "%$[Gg]([^:;$\n%.!?]+):([^:;$\n%.!?]+);"
    -- Client token names are ASCII. The next byte may begin a localized character.
    local formatted = text:gsub("%$[Nn]%f[^A-Za-z]", function() return replace(replacements.name) end)
        :gsub("%$[Rr]%f[^A-Za-z]", function() return replace(replacements.race) end)
        :gsub("%$[Cc]%f[^A-Za-z]", function() return replace(replacements.class) end)
        :gsub(genderSelector, function(male, female)
            if sex == 2 then return male end
            if sex == 3 then return female end
            incomplete = true
        end)
        :gsub("%$B", "\n"):gsub("%$b%f[^A-Za-z]", "\n")
        :gsub("<([^<>]+)>", function(token)
            -- Lua's locale-sensitive lower() can corrupt UTF-8 bytes.
            local key = token:gsub("[A-Z]", string.lower)
            key = playerPlaceholderAliases[key] or key
            if key == "name" or key == "race" or key == "class" then return replace(replacements[key]) end
        end)
        :gsub("{([A-Za-z]+)}", function(token)
            local key = token:lower()
            if key == "name" or key == "race" or key == "class" then return replace(replacements[key]) end
        end)
        :gsub("%$(%d+)oa", function(index)
            local objective = objectives and objectives[tonumber(index)]
            if objective and objective.numRequired then return tostring(objective.numRequired) end
            incomplete = true
        end)

    -- Slash-separated forms may depend on grammatical context, not player sex.
    if formatted:find("<[^<>%s/]+/[^<>%s/]+>") then return nil end
    if incomplete then return nil end
    return formatted
end


local function GetStructuredStanding(addon, factionID)
    local ok, value = pcall(function()
        local function readable(v)
            return (not issecretvalue or not issecretvalue(v))
                and (not canaccessallvalues or canaccessallvalues(v))
        end
        if not readable(factionID) or type(factionID) ~= "number" or factionID <= 0
            or factionID == math.huge or factionID ~= math.floor(factionID) or not C_Reputation
            or type(C_Reputation.GetFactionDataByID) ~= "function" then return end
        local data = C_Reputation.GetFactionDataByID(factionID)
        if not readable(data) or type(data) ~= "table" then return end
        local id, reaction = data.factionID, data.reaction
        if not readable(id) or not readable(reaction) or id ~= factionID
            or type(reaction) ~= "number" or reaction ~= math.floor(reaction)
            or reaction < 1 or reaction > 8 or type(addon.GetFactionStandingLabel) ~= "function" then return end
        local label = addon:GetFactionStandingLabel(reaction, addon:GetTargetLocale())
        if not readable(label) or type(label) ~= "string" or not label:find("%S") then return end
        return label
    end)
    if ok then return value end
end

function Addon:GetProgressLines(questID)
    local quest = self:GetQuest(questID)

    if not quest then return {} end

    local live = C_QuestLog.GetQuestObjectives(questID) or {}
    local templates = {}

    for _, line in ipairs(quest.objectiveLines or {}) do templates[line.index] = line end

    local lines = {}

    for index, objective in ipairs(live) do
        local template = templates[index]
        local text

        if template and template.type == objective.type then
            text = template.text
            local standing
            if text:find("{standing}", 1, true) and objective.type == "reputation" then
                standing = GetStructuredStanding(self, template.factionID)
            end
            if (text:find("{standing}", 1, true) and not standing)
                or (text:find("{current}", 1, true) and objective.numFulfilled == nil)
                or (text:find("{required}", 1, true) and objective.numRequired == nil) then
                text = nil
            else
                if text:find("|4", 1, true) then
                    local locale, required = self:GetTargetLocale(), objective.numRequired
                    -- The selector immediately after the required count is controlled by that count.
                    local singular = required == 1 or required == 0 and (locale == "frFR" or locale == "ptBR")
                    text = text:gsub("({required}%s+)|4([^:;]+):([^:;]+);", function(prefix, one, many)
                        return prefix .. (singular and one or many)
                    end)
                    if text:find("|4", 1, true) then text = nil end
                end
                text = text and text:gsub("{current}", tostring(objective.numFulfilled or 0))
                    :gsub("{required}", tostring(objective.numRequired or 0))
                    :gsub("{standing}", function() return standing end)
            end
        elseif #live == 1 and objective.type == "event" and quest.eventObjectiveLabel then
            text = quest.eventObjectiveLabel .. (objective.finished and " (" .. self:GetQuestLabel("complete") .. ")" or "")
        end

        if text then text = self:FormatQuestText(text, questID) end
        text = text or objective.text

        if text and text ~= "" then
            lines[#lines + 1] = { native = objective.text, translated = text }
        end
    end

    return lines
end

function Addon:GetProgressText(questID)
    local lines = {}
    for _, objective in ipairs(self:GetProgressLines(questID)) do lines[#lines + 1] = objective.translated end
    return table.concat(lines, "\n")
end

local questLabels = {
    enUS = { description = "Description", rewards = "Rewards", complete = "Complete", receive = "You will receive:" },
    frFR = { description = "Description", rewards = "Récompenses", complete = "Terminé", receive = "Vous recevrez :" },
    deDE = { description = "Beschreibung", rewards = "Belohnungen", complete = "Abgeschlossen", receive = "Ihr erhaltet:" },
    esES = { description = "Descripción", rewards = "Recompensas", complete = "Completada", receive = "Recibirás:" },
    esMX = { description = "Descripción", rewards = "Recompensas", complete = "Completada", receive = "Recibirás:" },
    itIT = { description = "Descrizione", rewards = "Ricompense", complete = "Completata", receive = "Riceverai:" },
    ptBR = { description = "Descrição", rewards = "Recompensas", complete = "Concluída", receive = "Você receberá:" },
    ruRU = { description = "Описание", rewards = "Награды", complete = "Выполнено", receive = "Вы получите:" },
    ukUA = { description = "Опис", rewards = "Нагороди", complete = "Виконано", receive = "Ви отримаєте:" },
    csCZ = { description = "Popis", rewards = "Odměny", complete = "Dokončeno", receive = "Obdržíš:" },
    plPL = { description = "Opis", rewards = "Nagrody", complete = "Ukończono", receive = "Otrzymasz:" },
    trTR = { description = "Açıklama", rewards = "Ödüller", complete = "Tamamlandı", receive = "Alacağın ödüller:" },
    svSE = { description = "Beskrivning", rewards = "Belöningar", complete = "Slutfört", receive = "Du får:" },
    daDK = { description = "Beskrivelse", rewards = "Belønninger", complete = "Fuldført", receive = "Du modtager:" },
    hrHR = { description = "Opis", rewards = "Nagrade", complete = "Dovršeno", receive = "Dobit ćeš:" },
    ltLT = { description = "Aprašymas", rewards = "Atlygiai", complete = "Atlikta", receive = "Gausi:" },
    koKR = { description = "설명", rewards = "보상", complete = "완료", receive = "받을 보상:" },
    zhCN = { description = "描述", rewards = "奖励", complete = "完成", receive = "你将获得：" },
    zhTW = { description = "描述", rewards = "獎勵", complete = "完成", receive = "你將獲得：" },
}

function Addon:GetQuestLabel(key)
    return questLabels[self:GetTargetLocale()][key]
end

local function NormalizeQuestLine(text)
    return (text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("\194\160", " ")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Mirrors the native tracker for a completed quest: the client's completion text when it has one,
-- otherwise the QUEST_WATCH_QUEST_READY GlobalString. Completion text has no owned catalog field,
-- so it translates only when it is exactly this quest's summary in the client language; any other
-- completion text returns nil rather than a guessed label.
function Addon:GetQuestTurnInText(questID)
    local locale = self:GetTargetLocale()
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    local completion = index and GetQuestLogCompletionText and GetQuestLogCompletionText(index)
    if type(completion) ~= "string" or completion == "" then
        return self:GetClientLabel("QUEST_WATCH_QUEST_READY", locale)
    end
    local native = ForeverRosettaStoneDB:GetQuest(questID, GetLocale())
    local target = ForeverRosettaStoneDB:GetQuest(questID, locale)
    local source = native and self:FormatQuestText(native.summary, questID, GetLocale())
    if source and target and NormalizeQuestLine(source) == NormalizeQuestLine(completion) then
        return self:FormatQuestText(target.summary, questID, locale)
    end
end
