-- Metadata chunk reassembly follows QuestieDB's src/read/baked.lua (GPLv3).
-- See notices/questiedb-license.md for the upstream licensing notice.
local addonName = ...
local Encoding = C_EncodingUtil
local profiling
local storage = {}

local function LoadStorage(name)
    if storage[name] then return storage[name] end

    local loaded, reason = C_AddOns.LoadAddOn(name)
    assert(loaded, "Cannot load Forever Rosetta Stone data addon " .. name .. ": " .. tostring(reason))
    return assert(storage[name], "Forever Rosetta Stone data addon did not register its pages: " .. name)
end

local function GetStored(key)
    local locale = key:match("^X%-Rosetta%-(%a+)%-")

    if locale then
        local name = locale == "shared" and "ForeverRosettaStone_Rules"
            or "ForeverRosettaStone_Data_" .. locale
        return LoadStorage(name)[key]
    end

    local value = C_AddOns.GetAddOnMetadata(addonName, key)

    if not value then return end

    local count = value:match("^~(%d+)~$")

    if not count then return value end

    local parts = {}

    for index = 1, tonumber(count) do
        parts[index] = assert(C_AddOns.GetAddOnMetadata(addonName, key .. "-" .. index),
            "Forever Rosetta Stone metadata is missing chunk " .. key .. "-" .. index)
    end

    return table.concat(parts)
end

local function Decode(value)
    if not profiling then
        return Encoding.DeserializeCBOR(Encoding.DecompressString(Encoding.DecodeBase64(value), 1))
    end

    local start = debugprofilestop()
    local compressed = Encoding.DecodeBase64(value)
    local decodedBase64 = debugprofilestop()
    local raw = Encoding.DecompressString(compressed, 1)
    local inflated = debugprofilestop()
    local result = Encoding.DeserializeCBOR(raw)
    local finished = debugprofilestop()
    profiling.decodes = profiling.decodes + 1
    profiling.decodedBytes = profiling.decodedBytes + #raw
    profiling.base64Ms = profiling.base64Ms + decodedBase64 - start
    profiling.inflateMs = profiling.inflateMs + inflated - decodedBase64
    profiling.cborMs = profiling.cborMs + finished - inflated

    return result
end

assert(GetStored("X-Rosetta-Format") == "8", "Unsupported Forever Rosetta Stone database format")
local locales = Decode(assert(GetStored("X-Rosetta-Locales")))
local directories, pages = {}, {}
local pageCount, access = 0, 0
local PAGE_CACHE_LIMIT = 8
local function IsSupportedLocale(locale)
    return locales[locale] ~= nil
end
local questRows = setmetatable({}, { __mode = "v" })
local detailRows = setmetatable({}, { __mode = "v" })
local questFields = { "title", "summary", "description", "eventObjectiveLabel", "objectiveLines" }
local api = {
    apiVersion = 3,
    catalogVersion = assert(GetStored("X-Rosetta-Catalog")),
}

-- Generated data addons register only against their matching catalog build.
function api:RegisterStorage(name, version, values)
    assert(version == self.catalogVersion, "Forever Rosetta Stone data addon has a different catalog version: " .. name)
    assert(not storage[name], "Forever Rosetta Stone data addon registered twice: " .. name)
    storage[name] = values
end

function api:LoadLocale(locale)
    assert(IsSupportedLocale(locale), "Unknown Forever Rosetta Stone language: " .. tostring(locale))
    LoadStorage("ForeverRosettaStone_Data_" .. locale)
end

function api:InitializeLookups()
    -- Parsing the required encoded rules pack belongs to addon initialization, not mouse hover.
    LoadStorage("ForeverRosettaStone_Rules")
end

function api:StartProfiling()
    profiling = { decodes = 0, decodedBytes = 0, base64Ms = 0, inflateMs = 0, cborMs = 0,
        pageHits = 0, pageMisses = 0 }
end

function api:StopProfiling()
    local result = profiling
    profiling = nil
    return result
end

local function FindFloor(sorted, value)
    local left, right, found = 1, #sorted, 0

    while left <= right do
        local middle = math.floor((left + right) / 2)

        if sorted[middle] <= value then
            found, left = middle, middle + 1
        else
            right = middle - 1
        end
    end

    return found
end

local function GetPage(prefix, value)
    if directories[prefix] == nil then
        local stored = GetStored(prefix .. "-INDEX")
        directories[prefix] = stored and Decode(stored) or false
    end

    local directory = directories[prefix]

    if not directory then return end

    local index = FindFloor(directory, value)

    if index == 0 then return end

    local key = prefix .. "-" .. index
    local cached = pages[key]
    access = access + 1

    if cached then
        if profiling then profiling.pageHits = profiling.pageHits + 1 end
        cached.used = access
        return cached.value
    end

    if profiling then profiling.pageMisses = profiling.pageMisses + 1 end

    if pageCount == PAGE_CACHE_LIMIT then
        local oldestKey, oldestAccess

        for candidate, entry in pairs(pages) do
            if not oldestAccess or entry.used < oldestAccess then oldestKey, oldestAccess = candidate, entry.used end
        end

        pages[oldestKey] = nil
        pageCount = pageCount - 1
    end

    local page = Decode(assert(GetStored(key), "Forever Rosetta Stone metadata is missing page " .. key))
    pages[key] = { value = page, used = access }
    pageCount = pageCount + 1

    return page
end

local function GetRecord(kind, entityID, locale, rules)
    if (not IsSupportedLocale(locale) and not rules) or type(entityID) ~= "number"
        or entityID < 1 or entityID % 1 ~= 0 then return end

    local prefix = "X-Rosetta-" .. locale .. "-" .. kind
    local page = GetPage(prefix, entityID)

    if not page then return end

    local position = FindFloor(page[1], entityID)

    if position == 0 or page[1][position] ~= entityID then return end

    return page, position
end

local function HasAITranslation(page, position)
    local byte = string.byte(page[#page], math.floor((position - 1) / 8) + 1) or 0
    return math.floor(byte / 2 ^ ((position - 1) % 8)) % 2 == 1
end

-- Shared quest records are read-only. Held records keep their identity across page eviction.
local function GetQuest(questID, locale)
    if not IsSupportedLocale(locale) or type(questID) ~= "number" then return end

    local key = locale .. ":" .. questID
    local quest = questRows[key]

    if quest then return quest end

    local page, position = GetRecord("quests", questID, locale)

    if not page then return end

    quest = { hasAITranslation = HasAITranslation(page, position) }

    for column, field in ipairs(questFields) do quest[field] = page[column + 1][position] end

    questRows[key] = quest
    return quest
end

function api:GetQuest(questID, locale)
    return GetQuest(questID, locale)
end

function api:IsQuestAITranslated(questID, locale)
    return self:IsAITranslated("quests", questID, locale)
end

local kinds = { quests = true, items = true, npcs = true, areas = true, spells = true, talents = true, maps = true,
    factions = true, creaturetypes = true, classes = true, races = true, professioncategories = true, activities = true, taxinodes = true, books = true, bookpages = true,
    totemcategories = true, shapeshiftforms = true, itemlimitcategories = true, holidaynames = true, locktypes = true,
    itemsubclasses = true, gossipoptions = true, sharedstrings = true }

function api:IsAITranslated(kind, entityID, locale)
    if not kinds[kind] then return end

    local page, position = GetRecord(kind, entityID, locale)

    if page then return HasAITranslation(page, position) end
end

local function GetName(kind, entityID, locale)
    local page, position = GetRecord(kind, entityID, locale)

    return page and page[2][position] or nil
end

function api:GetItemName(itemID, locale)
    return GetName("items", itemID, locale)
end

function api:GetAreaName(areaID, locale)
    return GetName("areas", areaID, locale)
end

-- Translate an explicitly geographical value such as GetBindLocation's label.
-- This returns wording only, never a guessed area ID or the player's current zone.
function api:TranslateLocationLabel(text, sourceLocale, targetLocale)
    if type(text) ~= "string" or text == "" or not IsSupportedLocale(sourceLocale)
        or not IsSupportedLocale(targetLocale) then return end
    local key = text:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
        :gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("[ \t\r\n\v\f]+", " "):gsub("^ +", ""):gsub(" +$", "")
    local page = GetPage("X-Rosetta-" .. sourceLocale .. "-locationlabels", key)
    if not page then return end
    local position = FindFloor(page[1], key)
    if position == 0 or page[1][position] ~= key then return end
    local result
    for _, areaID in ipairs(page[2][position]) do
        local translated = self:GetAreaName(areaID, targetLocale)
        if type(translated) ~= "string" or translated == "" or result and result ~= translated then return end
        result = translated
    end
    return result
end

-- UI map IDs are distinct from AreaTable IDs.
function api:GetMapName(mapID, locale)
    return GetName("maps", mapID, locale)
end

function api:GetSpellName(spellID, locale)
    return GetName("spells", spellID, locale)
end

function api:GetProfessionCategoryName(categoryID, locale)
    return GetName("professioncategories", categoryID, locale)
end

function api:GetTotemCategoryName(categoryID, locale)
    return GetName("totemcategories", categoryID, locale)
end

function api:GetShapeshiftFormName(formID, locale)
    return GetName("shapeshiftforms", formID, locale)
end

function api:GetItemLimitCategoryName(categoryID, locale)
    return GetName("itemlimitcategories", categoryID, locale)
end

function api:GetHolidayName(holidayNameID, locale)
    return GetName("holidaynames", holidayNameID, locale)
end

function api:GetLockTypeName(lockTypeID, locale)
    return GetName("locktypes", lockTypeID, locale)
end

function api:GetItemSubclassName(subclassRecordID, locale)
    return GetName("itemsubclasses", subclassRecordID, locale)
end

function api:GetSharedText(sharedStringID, locale)
    return GetName("sharedstrings", sharedStringID, locale)
end

function api:GetTaxiNodeName(nodeID, locale)
    return GetName("taxinodes", nodeID, locale)
end

function api:GetActivityName(activityID, locale)
    return GetName("activities", activityID, locale)
end

function api:GetGossipOptionName(optionID, locale)
    return GetName("gossipoptions", optionID, locale)
end

local function GetDetails(kind, entityID, locale)
    if not IsSupportedLocale(locale) or type(entityID) ~= "number" then return end

    local key = kind .. ":" .. locale .. ":" .. entityID
    local cached = detailRows[key]

    if cached then return cached end

    local page, position = GetRecord(kind, entityID, locale)
    local localized = page and page[3][position]

    if locale ~= "enUS" then return localized end
    if not page then return end

    local rulePage, rulePosition = GetRecord(kind, entityID, "shared", true)
    local rules = rulePage and rulePage[3][rulePosition]

    if not localized and not rules then return end

    local details = {}
    for field, value in pairs(rules or {}) do details[field] = value end
    for field, value in pairs(localized or {}) do details[field] = value end

    if rules and rules.set then
        details.set = {}
        for field, value in pairs(rules.set) do details.set[field] = value end
        for field, value in pairs(localized and localized.set or {}) do details.set[field] = value end
    end

    detailRows[key] = details
    return details
end

local function GetRules(kind, entityID)
    local page, position = GetRecord(kind, entityID, "shared", true)
    return page and page[3][position] or nil
end

local globalStringKeys, globalStringEntries, sharedTextUses

function api:GetSharedTextsByUsage(usage, locale)
    if type(usage) ~= "string" or not IsSupportedLocale(locale) then return end
    if not sharedTextUses then
        sharedTextUses = {}
        local prefix = "X-Rosetta-shared-sharedstrings"
        local encoded = GetStored(prefix .. "-INDEX")
        for _, start in ipairs(encoded and Decode(encoded) or {}) do
            local page = GetPage(prefix, start)
            for position, id in ipairs(page[1]) do
                local role = page[2][position]
                sharedTextUses[role] = sharedTextUses[role] or {}
                sharedTextUses[role][#sharedTextUses[role] + 1] = id
            end
        end
    end
    local result = {}
    for _, id in ipairs(sharedTextUses[usage] or {}) do
        local text = GetName("sharedstrings", id, locale)
        if text then result[#result + 1] = text end
    end
    return result
end

-- GlobalStrings share the same bounded pages and locale packs as other catalog text.
function api:GetGlobalStringKeys()
    if globalStringKeys then return globalStringKeys end
    globalStringKeys, globalStringEntries = {}, {}
    local prefix = "X-Rosetta-shared-globalstrings"
    local encoded = GetStored(prefix .. "-INDEX")
    if not encoded then return globalStringKeys end
    for _, start in ipairs(Decode(encoded)) do
        local page = GetPage(prefix, start)
        for position, id in ipairs(page[1]) do
            local key = page[2][position]
            globalStringKeys[key] = id
            globalStringEntries[#globalStringEntries + 1] = {id, key}
        end
    end
    return globalStringKeys
end

function api:GetGlobalString(id, locale)
    return GetName("globalstrings", id, locale)
end

function api:GetGlobalStringByKey(key, locale)
    if type(key) ~= "string" or not IsSupportedLocale(locale) then return end
    local page = GetPage("X-Rosetta-shared-globalstringkeys", key)
    if not page then return end
    local position = FindFloor(page[1], key)
    if position == 0 or page[1][position] ~= key then return end
    local id = page[2][position]
    return GetName("globalstrings", id, locale), id
end

-- Native literal lookup: one bounded page decode and a binary search, never an inventory scan.
-- Text must already be normalized like client-labels.lua; callers verify each key against _G.
function api:GetGlobalStringKeysByText(text, locale)
    if type(text) ~= "string" or text == "" or not IsSupportedLocale(locale) then return end
    local page = GetPage("X-Rosetta-" .. locale .. "-globalstringtext", text)
    if not page then return end
    local position = FindFloor(page[1], text)
    if position == 0 or page[1][position] ~= text then return end
    local keys = {}
    for _, id in ipairs(page[2][position]) do
        local rules, rulePosition = GetRecord("globalstrings", id, "shared", true)
        local key = rules and rules[2][rulePosition]
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    return keys
end

function api:GetGlobalStrings(locale)
    if not IsSupportedLocale(locale) then return end
    self:GetGlobalStringKeys()
    local values = {}
    for _, entry in ipairs(globalStringEntries) do
        local value = GetName("globalstrings", entry[1], locale)
        if value ~= nil then values[entry[2]] = value end
    end
    return values
end

-- Rule records are shared and must be treated as read-only.
function api:GetSpellRules(spellID)
    return GetRules("spells", spellID)
end

function api:GetItemRules(itemID)
    return GetRules("items", itemID)
end

-- Detail records are shared and must be treated as read-only.
function api:GetSpellDetails(spellID, locale)
    return GetDetails("spells", spellID, locale)
end

function api:GetItemDetails(itemID, locale)
    return GetDetails("items", itemID, locale)
end

-- talentID is a client DB2 Talent row ID, not a live talent API identifier.
function api:GetTalentName(talentID, locale)
    return GetName("talents", talentID, locale)
end

-- Book titles and page bodies have separate ID namespaces; records remain read-only.
function api:GetBookName(firstPageID, locale)
    return GetName("books", firstPageID, locale)
end

function api:GetBookPage(pageID, locale)
    return GetName("bookpages", pageID, locale)
end

function api:GetBookRules(firstPageID)
    return GetRules("books", firstPageID)
end

-- ownerKind is "item" or "object"; item and object IDs are separate namespaces. Owners shared by
-- several books are not indexed, so a result always names exactly one book.
local bookOwnerKinds = { item = "bookitems", object = "bookobjects" }
function api:GetBookFirstPage(ownerKind, ownerID)
    local kind = bookOwnerKinds[ownerKind]
    if not kind then return end
    local page, position = GetRecord(kind, ownerID, "shared", true)
    return page and page[2][position] or nil
end

-- World-object tooltips expose only the native name. Text must be normalized like client-labels.lua and
-- ASCII-lowercased (A-Z only), matching the build's key;
-- the result is a first page ID only when the name belongs to exactly one object-owned book.
function api:GetBookFirstPageByObjectName(text, locale)
    if type(text) ~= "string" or text == "" or not IsSupportedLocale(locale) then return end
    local page = GetPage("X-Rosetta-" .. locale .. "-bookobjectnames", text)
    if not page then return end
    local position = FindFloor(page[1], text)
    if position == 0 or page[1][position] ~= text then return end
    local found = page[2][position]
    return #found == 1 and found[1] or nil
end

function api:GetNpcName(npcID, locale)
    return GetName("npcs", npcID, locale)
end

-- NPC subnames (the "<Warlock Trainer>" tooltip line) live in the localized details column.
function api:GetNpcSubName(npcID, locale)
    local page, position = GetRecord("npcs", npcID, locale)
    local details = page and page[3][position]
    return type(details) == "table" and details.subName or nil
end

function api:GetNpcFactionID(npcID)
    local page, position = GetRecord("npcs", npcID, "shared", true)
    local details = page and page[3][position]
    return details and details.factionId
end

function api:GetFactionName(factionID, locale)
    return GetName("factions", factionID, locale)
end

function api:GetCreatureTypeName(creatureTypeID, locale)
    return GetName("creaturetypes", creatureTypeID, locale)
end

function api:GetClassName(classID, locale)
    return GetName("classes", classID, locale)
end

function api:GetRaceName(raceID, locale, sex)
    if sex ~= 3 then return GetName("races", raceID, locale) end
    local page, position = GetRecord("races", raceID, locale)
    local details = page and page[3][position]
    return details and details.nameFemale or nil
end

function api:GetLocales()
    return locales
end

local function ReadLive(callback, ...)
    local ok, value = pcall(callback, ...)
    if ok and (not canaccessallvalues or canaccessallvalues(value)) then return value end
end

local function ResolveLiveArea(api, nativeName, candidateIDs, uiMapID, mapName, names, locale)
    local result = { nativeName = nativeName, status = "unresolved" }
    if type(nativeName) ~= "string" or nativeName == "" then
        result.status = nativeName == "" and "empty" or "unavailable"
        return result
    end
    local seen = {}
    for _, areaID in ipairs(candidateIDs or {}) do
        if (not canaccessallvalues or canaccessallvalues(areaID)) and type(areaID) == "number"
            and areaID > 0 and areaID % 1 == 0 and not seen[areaID] then
            seen[areaID] = true
            if names[areaID] == nil then
                names[areaID] = ReadLive(C_Map and C_Map.GetAreaInfo, areaID) or false
            end
            if names[areaID] == nativeName then
                if result.areaID then
                    result.areaID, result.status = nil, "ambiguous"
                    return result
                end
                result.areaID = areaID
            end
        end
    end
    if result.areaID then
        result.name = api:GetAreaName(result.areaID, locale)
    elseif mapName == nativeName then
        result.uiMapID = uiMapID
        result.name = api:GetMapName(uiMapID, locale)
    else
        return result
    end
    result.status = result.name and "resolved" or "missingTranslation"
    return result
end

-- Resolve both displayed areas using names from this client, never stored matching text.
-- Records are fresh snapshots; ambiguous IDs and unavailable translations have no name.
function api:GetPlayerLocation(locale)
    if not IsSupportedLocale(locale) then return end
    local uiMapID = ReadLive(C_Map and C_Map.GetBestMapForUnit, "player")
    if type(uiMapID) ~= "number" or uiMapID < 1 or uiMapID % 1 ~= 0 then uiMapID = nil end
    local mapName, candidateIDs
    if uiMapID then
        local info = ReadLive(C_Map and C_Map.GetMapInfo, uiMapID)
        if type(info) == "table" then mapName = ReadLive(function() return info.name end) end
        local position = ReadLive(C_Map and C_Map.GetPlayerMapPosition, uiMapID, "player")
        if position then
            candidateIDs = ReadLive(C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition,
                uiMapID, position)
            if type(candidateIDs) ~= "table" then candidateIDs = nil end
        end
    end
    local names = {}
    local zone = ResolveLiveArea(self, ReadLive(GetZoneText), candidateIDs, uiMapID, mapName, names, locale)
    local subzone = ResolveLiveArea(self, ReadLive(GetSubZoneText), candidateIDs, uiMapID, mapName, names, locale)
    return { uiMapID = uiMapID, zone = zone, subzone = subzone }
end

_G.ForeverRosettaStoneDB = api
