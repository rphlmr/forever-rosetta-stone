local _, Addon = ...

local decoded = {}
local sourceIndex, sourceLocale
local labelCache, cacheOrder, cacheCursor = {}, {}, 1
local LABEL_CACHE_LIMIT = 512

local function CanonicalFormat(text)
    return (text:gsub("%%(%d+)[ \t]*%$[ \t]*([%.%d]*[dscfFg])", function(index, kind)
        return "%" .. index .. "$" .. kind
    end))
end

local function Normalize(text)
    return (text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("|T.-|t", ""):gsub("|n", "\n"):gsub("\194\160", " ")
        :gsub("\226\128\175", " "):gsub("[ \t\r\n]+", " "):gsub("^ +", ""):gsub(" +$", ""))
end

local function Adapt(key, locale, value)
    local adapters = {Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale[locale],
        Addon.characterStatFormats and Addon.characterStatFormats[locale],
        locale == "enUS" and Addon.englishTooltipFormats or nil}
    for _, adapter in pairs(adapters) do
        if adapter[key] ~= nil then adapter[key] = value end
    end
end

local function Label(key, locale)
    if decoded[locale] then return decoded[locale][key] end
    local database = ForeverRosettaStoneDB
    if not database or not database.GetGlobalStringByKey then return end
    local cacheKey = locale .. ":" .. key
    local value = labelCache[cacheKey]
    if value ~= nil then return value or nil end
    value = database:GetGlobalStringByKey(key, locale)
    if value then Adapt(key, locale, value) end
    local previous = cacheOrder[cacheCursor]
    if previous then labelCache[previous] = nil end
    cacheOrder[cacheCursor], labelCache[cacheKey] = cacheKey, value or false
    cacheCursor = cacheCursor % LABEL_CACHE_LIMIT + 1
    return value
end

local function Shape(source)
    source = CanonicalFormat(source)
    local parts, offset = {"^"}, 1
    while true do
        local first, last, kind = source:find("%%[%d%.%$]*([dscfFg])", offset)
        local literal = source:sub(offset, first and first - 1 or #source):gsub("%%%%", "%%")
        parts[#parts + 1] = literal:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        if not first then break end
        parts[#parts + 1] = kind == "c" and "[%+%-]"
            or kind ~= "s" and "[%+%-]?[%d%., ]+" or ".-"
        offset = last + 1
    end
    parts[#parts + 1] = "$"
    return table.concat(parts)
end

local function Shapes(source)
    local shapes, pending = {Shape(source)}, {source}
    local position = 1
    while pending[position] do
        local text = pending[position]
        local first, last, forms = text:find("|4([^;]+);")
        if first then
            for form in forms:gmatch("[^:]+") do
                local expanded = text:sub(1, first - 1) .. form .. text:sub(last + 1)
                if expanded:find("|4", 1, true) then pending[#pending + 1] = expanded
                else shapes[#shapes + 1] = Shape(expanded) end
            end
        end
        position = position + 1
    end
    return shapes
end

-- Only keys used by the tooltip adapters participate in native-line matching.
-- Catalog text is fetched by key/ID after a candidate has matched, never as a full locale scan.
local function Index()
    local locale = GetLocale()
    if sourceIndex and sourceLocale == locale then return sourceIndex end
    local known = {}
    local function Include(values)
        for key in pairs(values or {}) do known[key] = true end
    end
    Include(Addon.englishTooltipFormats)
    Include(Addon.itemTooltipLabels)
    Include(Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale.enUS)
    Include(Addon.characterStatFormats and Addon.characterStatFormats.enUS)
    -- These labels fill value slots in shared tooltip formats rather than complete rows.
    Include({ BAG_NAME_BAG_REAGENT = true, ITEM_TOY_ONUSE = true, ITEM_COSMETIC_LEARN = true,
        FOCUS_COST = true, FOCUS_COST_PER_TIME = true, FOCUS_COST_PER_TIME_NO_BASE = true,
        ITEM_DURATION_SEC = true, ITEM_DURATION_MIN = true, ITEM_DURATION_HOURS = true, ITEM_DURATION_DAYS = true,
        ITEM_PET_KNOWN = true, TOKEN_CONSUMABLE_DESCRIPTION_30_DAYS = true,
        TOKEN_AUCTIONABLE_DESCRIPTION_30_DAYS = true, LOCKED = true, COMBO_POINTS_COST = true, HP_TEMPLATE = true })
    local aliases = {}
    for key in pairs(known) do
        for _, prefix in ipairs({"PROFESSIONS_", "CHARACTER_PROFESSION_"}) do
            local alias = prefix .. key
            local value = _G[alias]
            if canaccessallvalues(value) and type(value) == "string" then aliases[alias] = true end
        end
    end
    Include(aliases)
    local exact, formats, deferred = {}, {}, {}
    local sourceAdapter = locale == "enUS" and Addon.englishTooltipFormats
        or Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale[locale]
    for key in pairs(known) do
        local value = _G[key]
        -- Existing adapters index candidate shapes only. The selected candidate
        -- is checked against its owned catalog text before it can translate a row.
        if canaccessallvalues(value) and value == nil then
            value = sourceAdapter and sourceAdapter[key]
        end
        if canaccessallvalues(value) and value == nil then deferred[key] = true end
        if canaccessallvalues(value) and type(value) == "string" and value ~= "" then
            local text = CanonicalFormat(Normalize(value))
            local first = text:find("%%[%d%.%$]*[dscfFg]")
            if first then
                local prefix = text:sub(1, first - 1)
                local bucket = prefix:match("^([^ \t\r\n]+)[ \t\r\n]") or ""
                formats[bucket] = formats[bucket] or {}
                formats[bucket][#formats[bucket] + 1] = {key = key, shapes = Shapes(text)}
            else
                exact[text] = exact[text] or {}
                exact[text][#exact[text] + 1] = key
                local literal = text:gsub("%%%%", "%%")
                if literal ~= text then
                    exact[literal] = exact[literal] or {}
                    exact[literal][#exact[literal] + 1] = key
                end
            end
        end
    end
    sourceIndex, sourceLocale = {exact = exact, formats = formats, known = known, deferred = deferred}, locale
    return sourceIndex
end

function Addon:GetClientLabel(key, locale)
    return Label(key, locale)
end

function Addon:InitializeTooltipLabels()
    Index()
end

-- Explicit bulk export for inventory/diagnostic callers. Tooltip rendering must not call this.
function Addon:GetClientLabels(locale)
    if decoded[locale] then return decoded[locale] end
    local database = ForeverRosettaStoneDB
    local values = database and database.GetGlobalStrings and database:GetGlobalStrings(locale)
    if not values then return end
    for key, value in pairs(values) do Adapt(key, locale, value) end
    decoded[locale] = values
    return values
end

function Addon:TranslateClientLabel(text, locale, context)
    local index = Index()
    local normalized, result = Normalize(text), nil
    local keys = index.exact[normalized]
    if not keys then
        -- Any other catalog-owned literal: one bounded page lookup in the client-locale pack.
        -- Format strings stay limited to the adapter keys, so "%s"-like shapes never claim lines.
        local database = ForeverRosettaStoneDB
        local found = database and database.GetGlobalStringKeysByText
            and database:GetGlobalStringKeysByText(normalized, GetLocale())
        keys = found or {}
    end
    if context == "profession" then
        local professionKeys, characterKeys = {}, {}
        for _, key in ipairs(keys) do
            if key:match("^PROFESSIONS_") then professionKeys[#professionKeys + 1] = key
            elseif key:match("^CHARACTER_PROFESSION_") then characterKeys[#characterKeys + 1] = key end
        end
        if #professionKeys > 0 then keys = professionKeys
        elseif #characterKeys > 0 then keys = characterKeys end
    end
    for _, key in ipairs(keys) do
        local value = _G[key]
        if canaccessallvalues(value) and value == nil then value = Label(key, GetLocale()) end
        if canaccessallvalues(value) and type(value) == "string" and Normalize(value) == normalized then
            local translated = Label(key, locale)
            if translated then
                translated = translated:gsub("|n", "\n"):gsub("[ \t\r\n]+$", "")
                if result and result ~= translated then return end
                result = translated
            end
        end
    end
    return result
end

function Addon:GetClientLabelFormats(text, locale, allowed)
    local index, normalized = Index(), Normalize(text)
    local keys, formats = {}, {}
    for _, key in ipairs(index.exact[normalized] or {}) do keys[key] = true end
    local word = normalized:match("^([^ \t\r\n]+)") or ""
    for _, bucket in ipairs({word, ""}) do
        for _, entry in ipairs(index.formats[bucket] or {}) do
            for _, shape in ipairs(entry.shapes) do
                if normalized:match(shape) then keys[entry.key] = true; break end
            end
        end
    end
    -- Load missing adapter shapes only after the normal formats failed. This
    -- keeps ordinary cold hovers from decoding unrelated catalog label pages.
    for key, shapes in pairs(index.deferred) do
        if shapes == true and not allowed then
            local source = Label(key, GetLocale())
            shapes = source and source ~= "" and Shapes(Normalize(source)) or false
            index.deferred[key] = shapes
        end
        if type(shapes) == "table" and (not allowed or allowed[key] ~= nil) then
            for _, shape in ipairs(shapes) do
                if normalized:match(shape) then keys[key] = true; break end
            end
        end
    end
    for key in pairs(keys) do
        if not allowed or allowed[key] ~= nil then
            formats[key] = Label(key, locale) or (allowed and allowed[key])
        end
    end
    -- Retain specialized fixture/adaptor keys outside the shared registry.
    if allowed then
        for key, value in pairs(allowed) do
            if not index.known[key] then formats[key] = value end
        end
    end
    return formats
end
