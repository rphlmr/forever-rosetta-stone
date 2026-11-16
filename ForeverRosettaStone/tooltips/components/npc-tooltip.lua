local _, Addon = ...

local function Readable(value, kind)
    return canaccessallvalues(value) and type(value) == kind
end

local function Normalize(text)
    return (text:gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("[ \t\r\n]+", " ")
        :gsub("^ ", ""):gsub(" $", ""))
end

local function Escape(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function MatchFormat(text, format)
    local pattern, positions, offset = { "^" }, {}, 1
    format = Normalize(format)
    while true do
        local start, finish, position, kind = format:find("%%(%d*%$?)([ds])", offset)
        if not start then pattern[#pattern + 1] = Escape(format:sub(offset)); break end
        pattern[#pattern + 1] = Escape(format:sub(offset, start - 1))
        pattern[#pattern + 1] = kind == "d" and "(%d+)" or "(.-)"
        positions[#positions + 1] = tonumber(position:match("^(%d+)%$")) or #positions + 1
        offset = finish + 1
    end
    pattern[#pattern + 1] = "$"
    if #positions == 0 then
        if Normalize(text) == format then return {} end
        return
    end
    local captures = { Normalize(text):match(table.concat(pattern)) }
    if #captures ~= #positions then return end
    local arguments = {}
    for index, value in ipairs(captures) do arguments[positions[index]] = value end
    return arguments
end

local function RenderFormat(format, arguments)
    local index = 0
    return (format:gsub("%%(%d*%$?)([ds])", function(position)
        index = index + 1
        return arguments[tonumber(position:match("^(%d+)%$")) or index] or ""
    end))
end

-- Owner title lines ("%s's Pet", "%s's Totem"...) come from client GlobalStrings; the owner name stays verbatim.
local OWNER_TITLE_KEYS = {
    "UNITNAME_TITLE_PET", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_COMPANION",
    "UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_SQUIRE", "UNITNAME_TITLE_OPPONENT",
    "UNITNAME_TITLE_WAR_BANNER",
}
local OWNER_SUMMON_TITLE_LIMIT = 100
local ownerTitleKeys, ownerSourceFormats, ownerTargetFormats = nil, {}, {}

local function GetOwnerTitleKeys()
    if ownerTitleKeys then return ownerTitleKeys end
    ownerTitleKeys = {}
    for _, key in ipairs(OWNER_TITLE_KEYS) do ownerTitleKeys[#ownerTitleKeys + 1] = key end
    for index = 1, OWNER_SUMMON_TITLE_LIMIT do
        ownerTitleKeys[#ownerTitleKeys + 1] = "UNITNAME_SUMMON_TITLE" .. index
    end
    return ownerTitleKeys
end

local function GetGlobalFormat(key, locale)
    local db = ForeverRosettaStoneDB
    if type(db.GetGlobalStringByKey) ~= "function" then return end
    local ok, value = pcall(db.GetGlobalStringByKey, db, key, locale)
    if ok and Readable(value, "string") and value ~= "" then return value end
end

-- A format that is only "%s" would match any line; a usable owner title needs literal text.
local function IsOwnerFormat(format)
    return Readable(format, "string") and Normalize((format:gsub("%%%d*%$?s", ""))) ~= ""
end

-- Client grammar codes: "|3-n(name)" declines a Russian name, "|2 name" elides French "de"/"d'".
local function SourceVariants(format)
    format = format:gsub("|3%-%d+%((.-)%)", "%1")
    if not format:find("|2", 1, true) then return { format } end
    return { (format:gsub("|2 ?", "de ")), (format:gsub("|2 ?", "d'")), (format:gsub("|2 ?", "d\226\128\153")) }
end

local function StartsWithVowel(text)
    return text:find("^[AEIOUYaeiouy]") ~= nil
        or text:find("^\195[\128-\134\136-\143\146-\150\152-\156\160-\166\168-\175\178-\182\184-\188]") ~= nil
end

local function ResolveGrammar(text)
    text = text:gsub("|3%-%d+%((.-)%)", "%1")
    return (text:gsub("|2 ?([^|]*)", function(rest)
        return (StartsWithVowel(rest) and "d'" or "de ") .. rest
    end))
end

local function GetOwnerSourceFormats(sourceLocale)
    local cached = ownerSourceFormats[sourceLocale]
    if cached then return cached end
    cached = {}
    for _, key in ipairs(GetOwnerTitleKeys()) do
        -- The live client string is the exact native text; the catalog covers clients without it.
        local format = Readable(_G[key], "string") and _G[key] or GetGlobalFormat(key, sourceLocale)
        if IsOwnerFormat(format) then cached[#cached + 1] = { key = key, variants = SourceVariants(format) } end
    end
    ownerSourceFormats[sourceLocale] = cached
    return cached
end

local function GetOwnerTargetFormat(key, locale)
    local formats = ownerTargetFormats[locale]
    if not formats then formats = {}; ownerTargetFormats[locale] = formats end
    if formats[key] == nil then formats[key] = GetGlobalFormat(key, locale) or false end
    return formats[key] or nil
end

local function TranslateOwnerTitle(text, sourceLocale, locale)
    -- Tooltip data keeps the raw grammar codes ("Familier |2 Dane"); only the rendered
    -- font string resolves them. Match the resolved form against the resolved variants.
    text = ResolveGrammar(text)
    local result
    for _, entry in ipairs(GetOwnerSourceFormats(sourceLocale)) do
        for _, variant in ipairs(entry.variants) do
            local arguments = MatchFormat(text, variant)
            if arguments then
                local target = GetOwnerTargetFormat(entry.key, locale)
                if not IsOwnerFormat(target) then return end
                local rendered = ResolveGrammar(RenderFormat(target, arguments))
                -- Identical native titles with different targets (koKR pet/minion/companion) stay native.
                if result and result ~= rendered then return end
                result = rendered
                break
            end
        end
    end
    return result
end

local function GetUnitToken(source, data)
    if not source or not data then return end
    if not Readable(data.guid, "string") or not UnitGUID then return end
    local unit
    if source.GetUnit then
        local ok, _, value = pcall(source.GetUnit, source)
        if ok and Readable(value, "string") then unit = value end
    end
    if not unit then
        local title = data.lines and data.lines[1]
        unit = title and Readable(title.unitToken, "string") and title.unitToken or nil
    end
    if not unit then return end
    local guidOK, guid = pcall(UnitGUID, unit)
    if not guidOK or not Readable(guid, "string") or guid ~= data.guid then return end
    return unit
end

local function GetUnitLabels(spec, locale)
    local unit = GetUnitToken(spec.source, spec.data)
    if not unit then return end

    local labels = {}
    if UnitCreatureType then
        local typeOK, native, id = pcall(UnitCreatureType, unit)
        if typeOK and Readable(id, "number") then
            labels.creatureType = ForeverRosettaStoneDB:GetCreatureTypeName(id, locale)
            if Readable(native, "string") then labels.nativeCreatureType = native end
        end
    end
    if UnitClass then
        local classOK, native, _, id = pcall(UnitClass, unit)
        if classOK and Readable(id, "number") then
            labels.class = ForeverRosettaStoneDB:GetClassName(id, locale)
            if Readable(native, "string") then labels.nativeClass = native end
        end
    end
    if UnitIsDead then
        local deadOK, isDead = pcall(UnitIsDead, unit)
        if deadOK and Readable(isDead, "boolean") then labels.isDead = isDead end
    end
    if UnitIsPlayer then
        local playerOK, isPlayer = pcall(UnitIsPlayer, unit)
        if playerOK and Readable(isPlayer, "boolean") then labels.isPlayer = isPlayer end
    end
    if labels.isPlayer then
        if GetGuildInfo then
            local guildOK, name = pcall(GetGuildInfo, unit)
            if guildOK and Readable(name, "string") and name ~= "" then labels.nativeGuild = name end
        end
        if UnitFactionGroup then
            local factionOK, _, native = pcall(UnitFactionGroup, unit)
            if factionOK and Readable(native, "string") and native ~= "" then labels.nativeFaction = native end
        end
        if UnitRace then
            local raceOK, native, _, id = pcall(UnitRace, unit)
            if raceOK and Readable(id, "number") and Readable(native, "string") then
                labels.raceID, labels.nativeRace = id, native
            end
        end
        if UnitSex then
            local sexOK, sex = pcall(UnitSex, unit)
            if sexOK and Readable(sex, "number") then labels.sex = sex end
        end
        if UnitLevel then
            local levelOK, level = pcall(UnitLevel, unit)
            if levelOK and Readable(level, "number") then labels.level = level end
        end
    end
    return labels
end

local function IsNativePlayerFaction(text, labels)
    -- Player allegiance is intentionally kept native; only exempt the same live unit's label.
    return labels and labels.isPlayer and labels.nativeFaction
        and Normalize(text) == Normalize(labels.nativeFaction)
end

local function IsNativePlayerGuild(text, labels, index)
    -- The guild row follows the player name. Do not confuse a guild named like a class with the class row.
    if index ~= 2 or not labels or not labels.isPlayer or not labels.nativeGuild then return false end
    local native = Normalize(text)
    local guild = Normalize(labels.nativeGuild)
    return native == guild or native == "<" .. guild .. ">"
end

function Addon:TranslateUnitRaceName(raceID, nativeRace, sourceLocale, locale, sex)
    local db = ForeverRosettaStoneDB
    if type(db.GetRaceName) ~= "function" then return end
    if sex == 2 or sex == 3 then return db:GetRaceName(raceID, locale, sex) end
    -- UnitRace already supplies the race ID and its native wording. Without
    -- UnitSex, translate only when all matching sourced variants agree; do not
    -- invent a player-sex response or choose between different target labels.
    local result
    for _, variant in ipairs({2, 3}) do
        local source = db:GetRaceName(raceID, sourceLocale, variant)
        if Readable(source, "string") and Normalize(source) == Normalize(nativeRace) then
            local target = db:GetRaceName(raceID, locale, variant)
            if not Readable(target, "string") or target == "" or result and result ~= target then return end
            result = target
        end
    end
    return result
end

local function TranslatePlayerLevel(line, labels, sourceLocale, locale)
    if not labels or not labels.isPlayer or not labels.nativeRace or not labels.level
        or not Readable(line.leftText, "string") then return end
    local key = "TOOLTIP_UNIT_LEVEL_RACE"
    local native = Readable(_G[key], "string") and _G[key] or GetGlobalFormat(key, sourceLocale)
    local target = GetGlobalFormat(key, locale)
    if not native or not target then return end
    -- Both arguments are already captured APIs. Match the whole formatted row:
    -- a string-first positional format cannot be split at spaces inside a race label.
    local level, suffix = tostring(labels.level), ""
    local expected = RenderFormat(native, { level, labels.nativeRace })
    if Normalize(line.leftText) ~= Normalize(expected) then
        local player = Readable(_G.PLAYER, "string") and _G.PLAYER or GetGlobalFormat("PLAYER", sourceLocale)
        if not player then return end
        expected = RenderFormat(native, { level, labels.nativeRace .. " (" .. player .. ")" })
        if Normalize(line.leftText) ~= Normalize(expected) then return end
        local translatedPlayer = GetGlobalFormat("PLAYER", locale)
        if not translatedPlayer then return end
        suffix = " (" .. translatedPlayer .. ")"
    end
    local db = ForeverRosettaStoneDB
    if type(db.GetRaceName) ~= "function" then return end
    local translatedRace = Addon:TranslateUnitRaceName(labels.raceID, labels.nativeRace, sourceLocale, locale, labels.sex)
    if not Readable(translatedRace, "string") or translatedRace == "" then return end
    return RenderFormat(target, { level, translatedRace .. suffix })
end

-- A dead unit's type row shows the client's CORPSE GlobalString instead of its creature type.
-- Require both the live death state and the client's own CORPSE text before using the key.
local function TranslateCorpse(line, sourceLocale, locale)
    local native = Readable(_G.CORPSE, "string") and _G.CORPSE or GetGlobalFormat("CORPSE", sourceLocale)
    if not native or not Readable(line.leftText, "string") then return end
    if Normalize(line.leftText) ~= Normalize(native) then return end
    return GetGlobalFormat("CORPSE", locale)
end

local function IsTypedUnitRow(line)
    local types = Enum.TooltipDataLineType
    return types.UnitType ~= nil and line.type == types.UnitType
end

-- Some clients leave the type row untyped (type 0). The row is then identified only when its text
-- is exactly the native value the same live unit API returned with the ID; never by label lookup.
local function TranslateUnitType(line, labels, sourceLocale, locale)
    local typed = IsTypedUnitRow(line)
    if not labels then return end
    if labels.isDead then
        local corpse = TranslateCorpse(line, sourceLocale, locale)
        if corpse then return corpse end
    end
    if labels.isPlayer == nil then return end
    local translated = labels.isPlayer and labels.class or not labels.isPlayer and labels.creatureType or nil
    local native = labels.isPlayer and labels.nativeClass or not labels.isPlayer and labels.nativeCreatureType or nil
    if typed then return translated end
    if native and Readable(line.leftText, "string") and Normalize(line.leftText) == Normalize(native) then
        return translated
    end
end

function Addon:TranslateNpcTooltipText(text, locale, npcID)
    if not Readable(text, "string") then return end
    if GetLocale() == locale and locale ~= "itIT" then return text end
    local sourceLocale = GetLocale()
    sourceLocale = self.npcTooltipSourceLocales[sourceLocale] or sourceLocale
    local source, target = self.npcTooltipData[sourceLocale], self.npcTooltipData[locale]
    if not source or not target then return end
    if Normalize(text) == Normalize(source.pvp) then return target.pvp end
    local classifications = self.npcTooltipClassifications[sourceLocale]
    local targetClassifications = self.npcTooltipClassifications[locale]
    if classifications and targetClassifications then
        for index, value in ipairs(classifications) do
            if Normalize(text) == Normalize(value) then return targetClassifications[index] end
        end
    end
    -- Newer clients append the classification to the level row: "Level 61 (Elite)". Translate the level
    -- part with the format pass below and re-attach the classification from the owned label lists.
    local levelPart, classification = Normalize(text):match("^(.-) %((.-)%)$")
    if levelPart and classifications and targetClassifications then
        for index, value in ipairs(classifications) do
            if classification == Normalize(value) and targetClassifications[index] then
                local translatedLevel = self:TranslateNpcTooltipText(levelPart, locale)
                if translatedLevel then return translatedLevel .. " (" .. targetClassifications[index] .. ")" end
            end
        end
    end
    for index, format in ipairs(source.formats) do
        local arguments = not format:find("%%[%d%$]*s") and MatchFormat(text, format)
        if arguments then
            return RenderFormat(target.formats[index], arguments)
        end
    end
    local ownerTitle = TranslateOwnerTitle(text, sourceLocale, locale)
    if ownerTitle then return ownerTitle end
    local db = ForeverRosettaStoneDB
    if not Readable(npcID, "number") or npcID <= 0 then return end
    -- The NPC's owned faction ID disambiguates the visible name; never search factions by text.
    -- Client faction text comes first: a subname can repeat the faction name with only an English fallback.
    if type(db.GetNpcFactionID) == "function" and type(db.GetFactionName) == "function" then
        local ok, factionID = pcall(db.GetNpcFactionID, db, npcID)
        if ok and Readable(factionID, "number") and factionID > 0 then
            local sourceOK, nativeName = pcall(db.GetFactionName, db, factionID, sourceLocale)
            if sourceOK and Readable(nativeName, "string") and nativeName ~= ""
                and Normalize(text) == Normalize(nativeName) then
                local targetOK, translated = pcall(db.GetFactionName, db, factionID, locale)
                if targetOK and Readable(translated, "string") and translated ~= "" then return translated end
            end
        end
    end
    -- Subnames come from the NPC's own record in the client language; never search other NPCs by text.
    if type(db.GetNpcSubName) == "function" then
        local sourceOK, nativeSubName = pcall(db.GetNpcSubName, db, npcID, sourceLocale)
        if sourceOK and Readable(nativeSubName, "string") and nativeSubName ~= ""
            and Normalize(text) == Normalize(nativeSubName) then
            local targetOK, translated = pcall(db.GetNpcSubName, db, npcID, locale)
            if targetOK and Readable(translated, "string") and translated ~= "" then return translated end
        end
    end
end

local function CopyFont(target, source)
    if target and source then
        local font, size, flags = source:GetFont()
        if font and size then target:SetFont(font, size, flags) end
        target:SetTextScale(source:GetTextScale())
    end
end

local function Color(color, source)
    if color and not canaccessallvalues(color) then color = nil end
    if color and color.GetRGB then return color:GetRGB() end
    if color and canaccessallvalues(color.r, color.g, color.b) then return color.r, color.g, color.b end
    if source then return source:GetTextColor() end
    return 1, 1, 1
end

local function IsOwnedUnitText(addon, text, npcID)
    if not Readable(text, "string") then return false end
    local locale = addon.npcTooltipSourceLocales[GetLocale()] or GetLocale()
    local native = addon.npcTooltipData[locale]
    local value = Normalize(text)
    if native and value == Normalize(native.pvp) then return true end
    for _, label in ipairs(addon.npcTooltipClassifications[locale] or {}) do
        if value == Normalize(label) then return true end
        local level = value:match("^(.-) %(" .. Escape(Normalize(label)) .. "%)$")
        if level and IsOwnedUnitText(addon, level, npcID) then return true end
    end
    for _, format in ipairs(native and native.formats or {}) do
        if not format:find("%%[%d%$]*s") and MatchFormat(value, format) then return true end
    end
    for _, entry in ipairs(GetOwnerSourceFormats(locale)) do
        for _, format in ipairs(entry.variants) do
            if MatchFormat(value, format) then return true end
        end
    end
    local db = ForeverRosettaStoneDB
    if not Readable(npcID, "number") or npcID <= 0 then return false end
    if type(db.GetNpcFactionID) == "function" and type(db.GetFactionName) == "function" then
        local factionOK, faction = pcall(db.GetNpcFactionID, db, npcID)
        local nameOK, name
        if factionOK and faction then nameOK, name = pcall(db.GetFactionName, db, faction, locale) end
        if nameOK and Readable(name, "string") and value == Normalize(name) then return true end
    end
    local subnameOK, subname
    if type(db.GetNpcSubName) == "function" then subnameOK, subname = pcall(db.GetNpcSubName, db, npcID, locale) end
    return subnameOK and Readable(subname, "string") and value == Normalize(subname) or false
end

local function IsPickedUnitLine(addon, line, npcID, labels, index)
    local types = Enum.TooltipDataLineType
    for _, key in ipairs({"UnitLevel", "UnitType", "UnitOwner", "UnitDead"}) do
        if types[key] ~= nil and line.type == types[key] then return true end
    end
    if line.type ~= nil and line.type ~= (types.None or 0) then return false end
    if not Readable(line.leftText, "string") then return false end
    if IsNativePlayerGuild(line.leftText, labels, index) or IsNativePlayerFaction(line.leftText, labels) then return true end
    if labels then
        local sourceLocale = addon.npcTooltipSourceLocales[GetLocale()] or GetLocale()
        local corpse = Readable(_G.CORPSE, "string") and _G.CORPSE or GetGlobalFormat("CORPSE", sourceLocale)
        if labels.isDead and corpse and Normalize(line.leftText) == Normalize(corpse) then return true end
        local native = labels.isPlayer and labels.nativeClass or labels.nativeCreatureType
        if native and Normalize(line.leftText) == Normalize(native) then return true end
        if labels.isPlayer then
            local locale = addon.npcTooltipSourceLocales[GetLocale()] or GetLocale()
            local format = Readable(_G.TOOLTIP_UNIT_LEVEL_RACE, "string") and _G.TOOLTIP_UNIT_LEVEL_RACE
                or GetGlobalFormat("TOOLTIP_UNIT_LEVEL_RACE", locale)
            if format and MatchFormat(line.leftText, format) then return true end
        end
    end
    return IsOwnedUnitText(addon, line.leftText, npcID)
end

function Addon:GetUnitTooltipSelection(spec, locale)
    local labels = GetUnitLabels(spec, locale)
    local quests = self.GetUnitQuestTranslations and self:GetUnitQuestTranslations(spec.data.lines, locale) or {}
    local selected, rows = {}, {}
    for index, line in ipairs(spec.data.lines or {}) do
        if index == 1 or quests[line] or canaccessallvalues(line.type)
            and IsPickedUnitLine(self, line, spec.id, labels, index) then
            selected[line], rows[#rows + 1] = true, line
        end
    end
    return selected, labels, quests, rows
end

function Addon:FillNpcTooltip(spec)
    if not spec or not spec.source or not spec.tip or not canaccessallvalues(spec.data)
        or type(spec.data) ~= "table" then return end
    local tip, source = spec.tip, spec.source
    local title = source:GetLeftLine(1)
    local locale = self:GetTargetLocale()
    local selected, unitLabels, questRows = self:GetUnitTooltipSelection(spec, locale)
    local nameLine = spec.data.lines and spec.data.lines[1]
    local incomplete, subtext = false, nil
    if nameLine and Readable(nameLine.rightText, "string") and nameLine.rightText ~= ""
        and IsOwnedUnitText(self, nameLine.rightText, spec.id) then
        subtext = self:TranslateNpcTooltipText(nameLine.rightText, locale, spec.id)
        if not subtext then subtext, incomplete = nameLine.rightText, true end
    end
    local red, green, blue = Color(nil, title)
    if subtext then tip:AddDoubleLine(spec.name, subtext, red, green, blue, Color(nameLine.rightColor))
    else tip:AddLine(spec.name, red, green, blue) end
    CopyFont(tip:GetLeftLine(1), title)
    if subtext and tip.GetRightLine and source.GetRightLine then
        CopyFont(tip:GetRightLine(1), source:GetRightLine(1))
    end
    for index, line in ipairs(spec.data.lines or {}) do
        if index ~= 1 and selected[line] then
            if canaccessallvalues(line.type, line.leftText, line.rightText) then
                local sourceLocale = self.npcTooltipSourceLocales[GetLocale()] or GetLocale()
                local guild = Readable(line.leftText, "string") and IsNativePlayerGuild(line.leftText, unitLabels, index)
                local quest = questRows[line]
                local left
                if quest then left = quest.text
                else left = guild and line.leftText or TranslatePlayerLevel(line, unitLabels, sourceLocale, locale)
                    or TranslateUnitType(line, unitLabels, sourceLocale, locale) end
                if quest and quest.incomplete then incomplete = true end
                if not left and not quest and not IsTypedUnitRow(line) then
                    left = self:TranslateNpcTooltipText(line.leftText, locale, spec.id)
                end
                local right = self:TranslateNpcTooltipText(line.rightText, locale, spec.id)
                if not left and Readable(line.leftText, "string") then
                    left = line.leftText
                    if Normalize(left):match("%S") and not IsNativePlayerFaction(left, unitLabels) then
                        incomplete = true
                    end
                end
                if not right and Readable(line.rightText, "string") and line.rightText ~= "" then
                    right, incomplete = line.rightText, true
                end
                if left or right then
                    local lineIndex = Readable(line.lineIndex, "number") and line.lineIndex or index
                    local original = source:GetLeftLine(lineIndex)
                    local red, green, blue = Color(line.leftColor, original)
                    if right then tip:AddDoubleLine(left or "", right, red, green, blue, Color(line.rightColor))
                    else tip:AddLine(left, red, green, blue, true) end
                    CopyFont(tip:GetLeftLine(tip:NumLines()), original)
                    if right and tip.GetRightLine and source.GetRightLine then
                        CopyFont(tip:GetRightLine(tip:NumLines()), source:GetRightLine(lineIndex))
                    end
                end
            else
                incomplete = true
            end
        end
    end
    if incomplete then tip:AddLine(Addon:GetIncompleteTranslationNotice(), 0.65, 0.65, 0.65, true) end
end

Addon:RegisterNameTooltipComponent({
    kind = "npc",
    supportsFullText = true,
    defaultContext = "unit",
    placementProfiles = Addon.npcTooltipPlacements,
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetNpcName(id, locale) end,
    ResolveData = function(_, data)
        if data.type ~= Enum.TooltipDataType.Unit or not canaccessallvalues(data.guid)
            or type(data.guid) ~= "string" then return end
        local kind, id = data.guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
        if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    end,
})
