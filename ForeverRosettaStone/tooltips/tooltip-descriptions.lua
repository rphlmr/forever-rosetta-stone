local _, Addon = ...

local incompleteNotices = {
    enUS = "Some lines are not translated yet.", frFR = "Certaines lignes ne sont pas traduites.",
    deDE = "Einige Zeilen sind noch nicht übersetzt.", esES = "Algunas líneas aún no están traducidas.",
    esMX = "Algunas líneas aún no están traducidas.", itIT = "Alcune righe non sono ancora tradotte.",
    ptBR = "Algumas linhas ainda não foram traduzidas.", ruRU = "Некоторые строки ещё не переведены.",
    koKR = "일부 줄은 아직 번역되지 않았습니다.", zhCN = "部分内容尚未翻译。", zhTW = "部分內容尚未翻譯。",
}

-- Shown in the client language below a translated tooltip with unmatched lines.
function Addon:GetIncompleteTranslationNotice()
    return incompleteNotices[GetLocale()] or incompleteNotices.enUS
end

local function Readable(value, kind)
    return canaccessallvalues(value) and type(value) == kind
end

local function CanonicalFormat(text)
    -- Some sourced UI templates insert whitespace inside a positional specifier.
    -- Normalize only its explicit argument index and type, never captured values.
    return (text:gsub("%%(%d+)[ \t]*%$[ \t]*([%.%d]*[dscfFg])", function(index, kind)
        return "%" .. index .. "$" .. kind
    end))
end

-- Prefer the client's live UI label. Owned catalog text can still match a full
-- visible row when an older capture (or client surface) has no global for that key.
local function NativeFormat(key)
    local value = _G[key]
    if not canaccessallvalues(value) then return end
    if type(value) == "string" then return CanonicalFormat(value) end
    if value ~= nil then return end
    value = Addon.GetClientLabel and Addon:GetClientLabel(key, GetLocale())
    return Readable(value, "string") and CanonicalFormat(value) or nil
end

local function Normalize(text, preserveMarkup)
    if preserveMarkup then
        text = text:gsub("|C", "|c"):gsub("|R", "|r"):gsub("|T([^:|]+)[^|]*|t", "|T%1|t")
    else
        text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|T.-|t", "")
    end
    return (text:gsub("|n", "\n")
        :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("[ \t\r\n]+", " "))
end

local function Escape(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function HasTranslatableText(text)
    text = Normalize(text):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:gsub("×", ""):gsub("–", ""):gsub("—", ""):gsub("−", "")
    return text:find("[%a\128-\255]") ~= nil
end

local function Seconds(value)
    if value >= 86400 then
        local days = value / 86400
        return string.format("%g %s", days, days == 1 and "day" or "days")
    end
    if value >= 3600 then
        local hours = value / 3600
        return string.format("%g %s", hours, hours == 1 and "hour" or "hours")
    end
    if value >= 60 then return string.format("%g min", value / 60) end
    return string.format("%g sec", value)
end

local function SplitForms(forms)
    local options = {}
    for form in (forms .. ":"):gmatch("(.-):") do options[#options + 1] = form end
    return options
end

local function CanonicalNumber(text)
    local french = GetLocale() == "frFR"
    local decimalLabel, groupingLabel = NativeFormat("DECIMAL_SEPERATOR"), NativeFormat("LARGE_NUMBER_SEPERATOR")
    local decimal = Readable(decimalLabel, "string") and decimalLabel or french and "," or "."
    local grouping = Readable(groupingLabel, "string") and Normalize(groupingLabel)
        or french and " " or ","
    if grouping ~= "" and grouping ~= decimal then text = text:gsub(Escape(grouping), "") end
    if decimal ~= "." then text = text:gsub(Escape(decimal), ".") end
    if text:match("^[%+%-]?%d+%.?%d*$") then return text end
end

local function EnglishNumber(text, duration)
    text = Normalize(text):gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")
    if duration then
        if Readable(SPELL_DURATION_UNTIL_CANCELLED, "string")
            and text == Normalize(SPELL_DURATION_UNTIL_CANCELLED) then return "until canceled" end
        local function MatchDuration(format)
            if not Readable(format, "string") then return end
            local first, last, forms = format:find("|4([^;]+);")
            if first then
                for form in forms:gmatch("[^:]+") do
                    local amount = MatchDuration(format:sub(1, first - 1) .. form .. format:sub(last + 1))
                    if amount then return amount end
                end
                return
            end
            local start, finish = format:find("%%[%d%.%$]*[dfFg]")
            if not start then return end
            local pattern = "^" .. Escape(Normalize(format:sub(1, start - 1))) .. "(.-)"
                .. Escape(Normalize(format:sub(finish + 1))) .. "$"
            local captured = text:match(pattern)
            return captured and tonumber(CanonicalNumber(captured) or "")
        end
        for _, unit in ipairs({
            { 1, "SECONDS_ABBR", "SECOND_ONELETTER_ABBR", "INT_GENERAL_DURATION_SEC", "D_SECONDS" },
            { 60, "MINUTES_ABBR", "MINUTE_ONELETTER_ABBR", "INT_GENERAL_DURATION_MIN" },
            { 3600, "HOURS_ABBR", "HOUR_ONELETTER_ABBR", "INT_GENERAL_DURATION_HOURS" },
            { 86400, "DAYS_ABBR", "DAY_ONELETTER_ABBR", "INT_GENERAL_DURATION_DAYS" },
        }) do
            for index = 2, #unit do
                local amount = MatchDuration(NativeFormat(unit[index]))
                if amount then return Seconds(amount * unit[1]) end
            end
        end
        local amount, unit = text:match("^([%d%., ]+)[ \t\r\n]*([%a%.]+)$")
        local multiplier = ({ s = 1, sec = 1, ["sec."] = 1, min = 60, ["min."] = 60, h = 3600,
            hour = 3600, hours = 3600 })[unit]
        amount = amount and tonumber(CanonicalNumber((amount:gsub(" +$", ""))) or "")
        return amount and multiplier and Seconds(amount * multiplier) or nil
    end
    local minimum, maximum = text:match("^(%d[%d%., ]*)%-(%d[%d%., ]*)$")
    if minimum and CanonicalNumber(minimum) and CanonicalNumber(maximum) then
        return CanonicalNumber(minimum) .. "-" .. CanonicalNumber(maximum)
    end
    text = text:gsub(" à ", " to "):gsub(" %- ", " to "):gsub(" – ", " to ")
    local lower, upper = text:match("^(.-) to (.-)$")
    if lower and CanonicalNumber(lower) and CanonicalNumber(upper) then
        return CanonicalNumber(lower) .. " to " .. CanonicalNumber(upper)
    end
    return CanonicalNumber(text)
end

local function SelectPlural(forms, amount, locale)
    local options = type(forms) == "table" and forms or SplitForms(forms)
    local identical = true
    for index = 2, #options do
        if options[index] ~= options[1] then identical = false; break end
    end
    if identical then return options[1] end
    if not amount then return end
    local index = amount == 1 and 1 or 2
    if #options >= 3 then
        if amount ~= math.floor(amount) then return end
        local last, lastTwo = amount % 10, amount % 100
        if locale == "ruRU" or locale == "ukUA" or locale == "hrHR" then
            index = last == 1 and lastTwo ~= 11 and 1
                or last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) and 2 or 3
        elseif locale == "plPL" then
            index = amount == 1 and 1 or last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) and 2 or 3
        elseif locale == "csCZ" then
            index = amount == 1 and 1 or amount >= 2 and amount <= 4 and 2 or 3
        else
            return
        end
    elseif locale == "frFR" or locale == "ptBR" then
        index = amount == 0 and 1 or index
    end
    return options[index]
end

local function PluralAmount(value)
    local amount = tonumber((value:gsub(",", ".")))
    if amount then return amount end
    local upper = value:match("^[%+%-]?[%d%.,]+ to ([%+%-]?[%d%.,]+)$")
        or value:match("^[%d%.,]+%-([%d%.,]+)$")
    return upper and tonumber((upper:gsub(",", "."))) or nil
end

local function FormatTargetNumber(value, locale)
    if type(value) == "string" and locale ~= "enUS" then
        value = value:gsub(" to ", "-")
    end
    local decimal = Addon.GetClientLabel and Addon:GetClientLabel("DECIMAL_SEPERATOR", locale)
    if decimal ~= "." and decimal ~= "," then
        decimal = ({ frFR = true, deDE = true, esES = true, esMX = true, itIT = true, ptBR = true,
            ruRU = true, ukUA = true, plPL = true, csCZ = true, daDK = true, svSE = true,
            hrHR = true, trTR = true })[locale] and "," or "."
    end
    if type(value) == "string" and value:match("^[%d%.%-]+$") then
        return (value:gsub("%.", decimal))
    end
    return value
end

local function FormatTargetDuration(value, locale)
    local formats = Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale[locale]
    if not formats then return end
    if value == "until canceled" then return formats.SPELL_DURATION_UNTIL_CANCELLED end
    local number, unit = value:match("^([%d%.]+) (%a+)$")
    local key = ({ sec = "SECONDS_ABBR", min = "MINUTES_ABBR", hour = "HOURS_ABBR", hours = "HOURS_ABBR",
        day = "DAYS_ABBR", days = "DAYS_ABBR" })[unit]
    local format = key and formats[key]
    if not number or not format then return end
    local result = format:gsub("|4([^;]+);", function(forms)
        return SelectPlural(forms, tonumber(number), locale) or "$unsupported-plural"
    end):gsub("%%[%d%.%$]*[dfFg]", FormatTargetNumber(number, locale))
    if result:find("$unsupported-plural", 1, true) then return end
    return result
end

local TranslateCapturedEffect

local function TranslateTooltipEffect(addon, line, kind, id, locale, data)
    if (kind == "spell" or kind == "talent") and Enum.TooltipDataLineType.SpellDescription ~= nil
        and line.type == Enum.TooltipDataLineType.SpellDescription then
        local text = addon:TranslateLiveSpellDescription(id, locale, line.leftText)
        return text, true
    end
    if kind ~= "item" then return end
    local lineTypes = Enum.TooltipDataLineType
    if lineTypes.ItemSpellTriggerLearn and line.type == lineTypes.ItemSpellTriggerLearn then
        if not Readable(line.spellID, "number") then return nil, true end
        local rules = ForeverRosettaStoneDB:GetItemRules(id)
        if type(rules) ~= "table" then return nil, true end
        local binding = rules.descriptionRow
        if binding == nil then
            -- Without a captured binding, the row itself must be the client's use prefix followed by
            -- the item's own description in the client language.
            local native = ForeverRosettaStoneDB:GetItemDetails(id, GetLocale())
            local prefix = NativeFormat("ITEM_SPELL_TRIGGER_ONUSE")
            local body = type(native) == "table" and native.description
            if not Readable(prefix, "string") or not Readable(body, "string") or not Readable(line.leftText, "string")
                or Normalize(line.leftText) ~= Normalize(prefix .. " " .. body) then return nil, true end
        elseif type(binding) ~= "table" or binding.lineType ~= "ItemSpellTriggerLearn" or binding.triggerType ~= 6
            or binding.spellID ~= line.spellID then return nil, true end
        local count = 0
        if type(rules.effects) ~= "table" then return nil, true end
        for _, effect in ipairs(rules.effects) do
            if type(effect) ~= "table" then return nil, true end
            if effect.spellID == line.spellID and effect.triggerType == 6 then count = count + 1 end
        end
        if count ~= 1 then return nil, true end
        local formats = (locale == "enUS") and addon.englishTooltipFormats
            or addon.tooltipFormatsByLocale and addon.tooltipFormatsByLocale[locale]
        local prefix = formats and formats.ITEM_SPELL_TRIGGER_ONUSE
        local target = ForeverRosettaStoneDB:GetItemDetails(id, locale)
        local description = type(target) == "table" and target.description
        if not Readable(prefix, "string") or not prefix:find("%S")
            or not Readable(description, "string") or not description:find("%S") then return nil, true end
        return prefix .. " " .. description, true
    end
    local trigger
    if lineTypes.ItemSpellTriggerOnUse and line.type == lineTypes.ItemSpellTriggerOnUse then trigger = 0
    elseif lineTypes.ItemSpellTriggerOnEquip and line.type == lineTypes.ItemSpellTriggerOnEquip then trigger = 1
    elseif lineTypes.ItemSpellTriggerOnProc and line.type == lineTypes.ItemSpellTriggerOnProc then trigger = 2 end
    local details
    if trigger == nil then
        if lineTypes.None ~= nil and line.type == lineTypes.None and not Readable(line.spellID, "number") then
            -- Untyped item auras still have an owner. Accept only a full description match
            -- against one of this item's effects, never a lookup by displayed spell name.
            details = ForeverRosettaStoneDB:GetItemRules(id)
            local translated, matched
            for _, effect in ipairs(details and details.effects or {}) do
                if type(effect) == "table" and (effect.triggerType == 0 or effect.triggerType == 5)
                    and Readable(effect.spellID, "number") then
                    local candidate = addon:TranslateLiveSpellDescription(effect.spellID, locale, line.leftText)
                    if candidate then
                        if matched then return nil, true end
                        translated, matched = candidate, true
                    end
                end
            end
            if matched then return translated, true end
        end
        -- Some surfaces (toys) render the on-use row without a trigger type or spell ID.
        -- Bind it only through the item's single owned on-use effect and the native prefix.
        local native = NativeFormat("ITEM_SPELL_TRIGGER_ONUSE")
        if Readable(line.spellID, "number") or not Readable(line.leftText, "string")
            or not Readable(native, "string") then return end
        local prefix = Normalize(native):gsub("[ \t\r\n]+$", "")
        if prefix == "" or Normalize(line.leftText):sub(1, #prefix) ~= prefix then return end
        details = ForeverRosettaStoneDB:GetItemRules(id)
        local spellID
        for _, effect in ipairs(details and details.effects or {}) do
            if type(effect) == "table" and effect.triggerType == 0 then
                if spellID then return nil, true end
                spellID = effect.spellID
            end
        end
        if type(spellID) ~= "number" or spellID < 1 or spellID % 1 ~= 0 then return nil, true end
        local bound = {}
        for key, value in pairs(line) do bound[key] = value end
        bound.spellID, line, trigger = spellID, bound, 0
    end
    if not Readable(line.spellID, "number") then return nil, true end
    details = details or ForeverRosettaStoneDB:GetItemRules(id)
    local linked
    for _, effect in ipairs(details and details.effects or {}) do
        if effect.spellID == line.spellID and effect.triggerType == trigger then
            if linked then return nil, true end
            linked = effect
        end
    end
    local key = linked and ({ [0] = "ITEM_SPELL_TRIGGER_ONUSE", [1] = "ITEM_SPELL_TRIGGER_ONEQUIP",
        [2] = "ITEM_SPELL_TRIGGER_ONPROC" })[linked.triggerType]
    if not key then return nil, true end
    local formats = (locale == "enUS") and addon.englishTooltipFormats
        or addon.tooltipFormatsByLocale and addon.tooltipFormatsByLocale[locale]
    local prefix = formats and formats[key]
    local captured = prefix and TranslateCapturedEffect(addon, line, locale, key, formats)
    -- Item effects use displayed values just like spells, talents and auras.
    -- An incomplete capture must never fall back to calculated character values.
    return captured, true
end

local function TranslateLiteral(text)
    for key, english in pairs(Addon.englishTooltipFormats) do
        if Readable(NativeFormat(key), "string") and Normalize(NativeFormat(key)) == text then return english end
    end
end

local function TranslateFormat(text, source, target, translateValue, strict, locale)
    if not Readable(source, "string") then return end
    source, target = CanonicalFormat(source), CanonicalFormat(target)
    local parts, offset, count = { "^" }, 1, 0
    source = Normalize(source)
    if not source:find("%%") then return Normalize(text) == source and target or nil end
    local pluralStart, pluralEnd, forms = source:find("|4([^;]+);")
    if pluralStart and not text:find("|4", 1, true) then
        for form in forms:gmatch("[^:]+") do
            local expanded = source:sub(1, pluralStart - 1) .. form .. source:sub(pluralEnd + 1)
            local translated = TranslateFormat(text, expanded, target, translateValue, strict, locale)
            if translated then return translated end
        end
        return
    end
    local positions, argumentKinds = {}, {}
    while true do
        local first, last, format, kind = source:find("%%([%d%.%$]*)([dscfFg])", offset)
        if not first then parts[#parts + 1] = Escape((source:sub(offset):gsub("%%%%", "%%"))); break end
        parts[#parts + 1] = Escape((source:sub(offset, first - 1):gsub("%%%%", "%%")))
        parts[#parts + 1] = kind == "c" and "([%+%-])"
            or (kind == "d" or kind == "f" or kind == "F" or kind == "g") and "([%+%-]?[%d%., ]+)" or "(.-)"
        count, offset = count + 1, last + 1
        positions[count] = tonumber(format:match("^(%d+)%$")) or count
        argumentKinds[count] = kind
    end
    parts[#parts + 1] = "$"
    if count == 0 then
        return Normalize(text) == (source:gsub("%%%%", "%%")) and (target:gsub("%%%%", "%%")) or nil
    end
    local values = { Normalize(text):match(table.concat(parts)) }
    if #values == 0 then return end
    local arguments = {}
    for index, value in ipairs(values) do
        arguments[positions[index]] = translateValue and translateValue(value, argumentKinds[index])
        if not arguments[positions[index]] and not strict then
            arguments[positions[index]] = (value == "+" or value == "-") and value
                or EnglishNumber(value, false) or TranslateLiteral(value)
        end
        if not arguments[positions[index]] then return end
    end
    local index, firstValue = 0, nil
    local result = target:gsub("%%([%d%.%$]*)[dscfFg]([^%%]*)", function(format, suffix)
        index = index + 1
        local value = arguments[tonumber(format:match("^(%d+)%$")) or index] or ""
        firstValue = firstValue or value
        local expanded = suffix:gsub("|4([^;]+);", function(forms)
            return SelectPlural(forms, PluralAmount(value), locale or "enUS") or "$unsupported-plural"
        end)
        return value .. expanded
    end):gsub("%%%%", "%%")
    result = result:gsub("|4([^;]+);", function(forms)
        local amount = firstValue and PluralAmount(firstValue)
        return SelectPlural(forms, amount, locale or "enUS") or "$unsupported-plural"
    end)
    if result:find("$unsupported-plural", 1, true) then return end
    return result
end

TranslateCapturedEffect = function(addon, line, locale, key, formats)
    if not Readable(line.leftText, "string")
        or not Readable(NativeFormat(key), "string") then return end
    -- Same-language effects already contain the client's exact wording and typography.
    if GetLocale() == locale then return line.leftText end
    local native = Normalize(line.leftText)
    local prefix = Normalize(NativeFormat(key)):gsub("[ \t\r\n]+$", "")
    local targetPrefix = ""
    if native:sub(1, #prefix) == prefix then
        native = native:sub(#prefix + 1):gsub("^[ \t\r\n]+", "")
        targetPrefix = formats[key] .. " "
    end
    -- Parentheses can belong to the catalog description rather than a cooldown suffix.
    local function Description(body)
        return addon:TranslateLiveSpellDescription(line.spellID, locale, body)
            or addon:TranslateLiveSpellDescription(line.spellID, locale, body, nil, nil, nil, true)
    end
    local description = Description(native)
    if description then return targetPrefix .. description end
    -- Match the client's cooldown formats rather than assuming ASCII delimiters.
    for _, suffixKey in ipairs({"ITEM_COOLDOWN_TOTAL_SEC", "ITEM_COOLDOWN_TOTAL_MIN",
        "ITEM_COOLDOWN_TOTAL_HOURS", "ITEM_COOLDOWN_TOTAL_DAYS", "ITEM_COOLDOWN_TOTAL"}) do
        if formats[suffixKey] and Readable(NativeFormat(suffixKey), "string") then
            for start in native:gmatch("[ \t\r\n]+()") do
                local translatedSuffix = TranslateFormat(native:sub(start), NativeFormat(suffixKey), formats[suffixKey], function(value)
                            return addon:TranslateLiveTooltipValue(value, locale, false)
                        or addon:TranslateLiveTooltipValue(value, locale, true)
                end, true, locale)
                if translatedSuffix then
                    local body = native:sub(1, start - 1):gsub("[ \t\r\n]+$", "")
                    description = Description(body)
                    if description then return targetPrefix .. description .. " " .. translatedSuffix end
                end
            end
        end
    end
end

function Addon:TranslateOwnedTooltipFormat(text, key, locale, convert)
    local formats = locale == "enUS" and self.englishTooltipFormats
        or self.tooltipFormatsByLocale and self.tooltipFormatsByLocale[locale]
    local target = self.GetClientLabel and self:GetClientLabel(key, locale) or formats and formats[key]
    return Readable(target, "string") and TranslateFormat(text, NativeFormat(key), target, convert, true, locale) or nil
end

local function TranslateKnownFormats(text, formats, translateValue, strict, locale, sources)
    if Addon.GetClientLabelFormats and not sources then
        formats = Addon:GetClientLabelFormats(text, locale or "enUS", formats)
    end
    local normalized = Normalize(text)
    local exact, exactKey
    for key, target in pairs(formats) do
        local source = sources and sources[key] or NativeFormat(key)
        if Readable(source, "string") and not source:find("%%") and Normalize(source) == normalized
            and (not exactKey or key < exactKey) then exact, exactKey = target, key end
    end
    if exact then return exact end

    local best, bestKey, bestScore
    for key, target in pairs(formats) do
        local source = sources and sources[key] or NativeFormat(key)
        if Readable(source, "string") and source:find("%%") then
            local normalizedSource = Normalize(source)
            local first = normalizedSource:find("%%[%d%.%$]*[dscfFg]")
            local prefix = first and normalizedSource:sub(1, first - 1):gsub("%%%%", "%%") or ""
            -- Reject incompatible literals before building patterns or translating captures.
            -- Plural markup must still be expanded by TranslateFormat.
            if prefix:find("|4", 1, true) or normalized:sub(1, #prefix) == prefix then
                local translated = TranslateFormat(text, source, target, translateValue and function(value)
                    return translateValue(value, key)
                end, strict, locale)
                local literals = normalizedSource:gsub("%%[%d%.%$]*[dscfFg]", "")
                if translated and (not bestScore or #literals > bestScore
                    or (#literals == bestScore and key < bestKey)) then
                    best, bestKey, bestScore = translated, key, #literals
                end
            end
        end
    end
    return best
end

local function WrapSharedTranslation(text, opening, closing)
    if not opening then return text end
    if text:sub(1, #opening) == opening and text:sub(-#closing) == closing then return text end
    return opening .. text .. closing
end

local function ResolveSharedTooltipText(self, text, locale)
    if not Readable(text, "string") then return end
    if text == "" then return end
    local invariant = not HasTranslatableText(text)
    local formats = self.tooltipFormatsByLocale and self.tooltipFormatsByLocale[locale]
        or locale == "enUS" and self.englishTooltipFormats
    if not formats then return invariant and text or nil end
    local hasSourceFormat
    for key in pairs(formats) do
        if Readable(NativeFormat(key), "string") and NativeFormat(key) ~= "" then hasSourceFormat = true; break end
    end
    if not hasSourceFormat then return invariant and text or nil end
    local opening, body, closing = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    body = body or text
    if self.TranslateClientLabel then
        local label = self:TranslateClientLabel(body, locale)
        if label then return WrapSharedTranslation(label, opening, closing) end
        local quoted = body:match('^"(.-)"$')
        label = quoted and self:TranslateClientLabel(quoted, locale)
        if label then return WrapSharedTranslation('"' .. label .. '"', opening, closing) end
    end
    local function ResolveValue(value, formatKey)
        if value == "+" or value == "-" then return value end
        local number = EnglishNumber(value, false)
        if number then return FormatTargetNumber(number, locale) end
        local scalar = self.TranslateLiveTooltipValue and self:TranslateLiveTooltipValue(value, locale, false)
        if scalar then return scalar end
        if formatKey == "SPELL_RANGE_DUAL" then
            for _, key in ipairs({ "FRIENDLY", "ENEMY" }) do
                if Readable(NativeFormat(key), "string") and Normalize(value) == Normalize(NativeFormat(key)) then
                    return self.GetClientLabel and self:GetClientLabel(key, locale)
                end
            end
        end
        if self.TranslateClientLabel then
            local label = self:TranslateClientLabel(value, locale, formatKey == "ITEM_MIN_SKILL" and "profession" or nil)
            if label then return label end
        end
        for key, target in pairs(formats) do
            if Readable(NativeFormat(key), "string") and Normalize(NativeFormat(key)) == Normalize(value) then return target end
        end
        local duration = EnglishNumber(value, true)
        if duration then return FormatTargetDuration(duration, locale) end
        return self.TranslateLiveCompoundDuration and self:TranslateLiveCompoundDuration(value, locale)
    end
    -- Many shared formats capture the same value. Resolve each distinct capture once per row.
    local valueCache, professionValueCache = {}, {}
    local function TranslateValue(value, formatKey)
        local cache = formatKey == "ITEM_MIN_SKILL" and professionValueCache or valueCache
        if cache[value] == nil then cache[value] = ResolveValue(value, formatKey) or false end
        return cache[value] or nil
    end
    -- Only shared GlobalStrings formats are matched here. Entity prose remains ID-based.
    local result = TranslateKnownFormats(body, formats, TranslateValue, true, locale)
    if not result then
        local creatorFormat = self.GetClientLabel and self:GetClientLabel("ITEM_CREATED_BY", locale)
            or formats.ITEM_CREATED_BY
        if creatorFormat then
            -- The creator's name is an invariant identity, not a label to translate.
            result = TranslateFormat(body, NativeFormat("ITEM_CREATED_BY"), creatorFormat, function(value)
                return value ~= "" and value or nil
            end, true, locale)
        end
    end
    if not result then
        local normalized, bestLength = Normalize(body), 0
        for key, target in pairs(formats) do
            local source = NativeFormat(key)
            if Readable(source, "string") and not source:find("%%") then
                source = Normalize(source):gsub("[ \t\r\n]+$", "")
                if #source > bestLength and normalized:sub(1, #source) == source then
                    local suffix = normalized:sub(#source + 1)
                    local number = suffix:match("^[ \t\r\n]+([%+%-]?[%d%., ]+)$")
                    number = number and EnglishNumber(number, false)
                    if number then result, bestLength = target .. " " .. FormatTargetNumber(number, locale), #source end
                end
            end
        end
    end
    if not result and self.GetClientLabelFormats then
        result = TranslateKnownFormats(body, self:GetClientLabelFormats(body, locale) or {}, TranslateValue, true, locale)
    end
    if not result and (body:find("\n", 1, true) or body:find("|n", 1, true)) then
        local unresolved = false
        local composed = body:gsub("|n", "\n"):gsub("[^\n]+", function(part)
            local value = ResolveSharedTooltipText(self, part, locale)
            if not value then unresolved = true; return part end
            return value
        end)
        if not unresolved then result = composed end
    end
    if result and opening then return WrapSharedTranslation(result, opening, closing) end
    return result or (invariant and text or nil)
end

local function SharedCacheValues(cache, locale, field)
    local sourceLocale = GetLocale()
    if cache.sourceLocale ~= sourceLocale or cache.locale ~= locale or cache.count >= 128 then
        cache.sourceLocale, cache.locale, cache.count, cache.values, cache.stats = sourceLocale, locale, 0, {}, {}
    end
    return cache[field]
end

local function TranslateSharedTooltipText(self, text, locale, cache)
    if not cache then return ResolveSharedTooltipText(self, text, locale) end
    if not Readable(text, "string") or text == "" then return end
    local values = SharedCacheValues(cache, locale, "values")
    local value = values[text]
    if value == nil then
        value = ResolveSharedTooltipText(self, text, locale) or false
        values[text], cache.count = value, cache.count + 1
    end
    return value or nil
end

function Addon:TranslateLiveTooltipLine(text)
    if not Readable(text, "string") then return end
    for key, english in pairs(self.itemTooltipLabels) do
        if Readable(NativeFormat(key), "string") and text == NativeFormat(key) then return english end
    end
    return TranslateKnownFormats(text, self.englishTooltipFormats)
end

-- Match keyed stat templates and carry displayed values without recalculating character formulas.
function Addon:TranslateCharacterStatText(text, locale, labelKey)
    if not Readable(text, "string") then return end
    -- The pinned itIT stat sources are English fallback, so authored targets also apply within that locale.
    if (locale == GetLocale() and locale ~= "itIT") or not HasTranslatableText(text) then return text end
    local formats = self.characterStatFormats[locale]
    if not formats then return end
    local function TranslateValue(value)
        if not HasTranslatableText(value) then return value end
        -- Rendered text has the elided "de"/"d'"; raw tooltip data keeps the "|2" code.
        if GetLocale() == "frFR" then
            value = value:gsub("^|2 ?", ""):gsub("^de ", ""):gsub("^d'", ""):gsub("^d’", "")
        end
        for key, target in pairs(formats) do
            if Readable(NativeFormat(key), "string") and Normalize(value) == Normalize(NativeFormat(key)) then return target end
        end
        local shared = self.tooltipFormatsByLocale and self.tooltipFormatsByLocale[locale]
        for key, target in pairs(shared or {}) do
            if Readable(NativeFormat(key), "string") and Normalize(value) == Normalize(NativeFormat(key)) then return target end
        end
    end
    local sources = {}
    for key in pairs(formats) do
        if Readable(NativeFormat(key), "string") then sources[key] = NativeFormat(key):gsub("|2", "") end
    end
    local translated = TranslateKnownFormats(text, formats, TranslateValue, true, locale, sources)
    if translated then return translated end

    local prefix, body, suffix = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    body = body or text
    local title, titleKey, titleLength
    for key, target in pairs(formats) do
        local label = NativeFormat(key)
        if Readable(label, "string") and not label:find("%%") and body:sub(1, #label) == label then
            local value = body:sub(#label + 1)
            if not HasTranslatableText(value) and (not titleLength or #label > titleLength
                or (#label == titleLength and (key == labelKey or (titleKey ~= labelKey and key < titleKey)))) then
                title, titleKey, titleLength = target .. value, key, #label
            end
        end
    end
    if title then return (prefix or "") .. title .. (suffix or "") end

    local warning = NativeFormat("SPIRIT_STANDING_WARNING")
    if Readable(warning, "string") and text:sub(-#warning) == warning and #text > #warning then
        local body = text:sub(1, #text - #warning):gsub("[ \t\r\n]+$", "")
        local result = self:TranslateCharacterStatText(body, locale, labelKey)
        if result and formats.SPIRIT_STANDING_WARNING then
            return result .. "\n\n" .. formats.SPIRIT_STANDING_WARNING
        end
    end

    -- Some client rows concatenate independently keyed paragraphs or labels.
    for _, separator in ipairs({ "\n\n", "\n" }) do
        local first = text:find(separator, 1, true)
        if first then
            local left = self:TranslateCharacterStatText(text:sub(1, first - 1), locale, labelKey)
            local right = self:TranslateCharacterStatText(text:sub(first + #separator), locale, labelKey)
            if left and right then return left .. separator .. right end
        end
    end
end

local function Money(amount)
    return MoneyFormatterUtil.FormatMoney(amount, GameTooltipMoneyFormat)
end

local function IsLineType(line, name)
    local kind = Enum.TooltipDataLineType[name]
    return kind ~= nil and line.type == kind
end

-- Translates one native row, retaining the values and item instance chosen by the client.
local function TranslateItemStatLine(addon, text, locale, cache)
    if not Readable(text, "string") then return end
    local values = cache and SharedCacheValues(cache, locale, "stats")
    if values and values[text] ~= nil then return values[text] or nil end
    local target = locale == "enUS" and addon.englishTooltipFormats
        or addon.tooltipFormatsByLocale and addon.tooltipFormatsByLocale[locale]
    local formats = {}
    for key, value in pairs(target or {}) do
        if key:match("^TOOLTIP_ITEM_STAT_") then formats[key] = value end
    end
    for _, key in ipairs({ "ITEM_RESIST_SINGLE", "ITEM_RESIST_ALL" }) do
        formats[key] = addon.GetClientLabel and addon:GetClientLabel(key, locale)
    end
    -- These are client GlobalStrings, not spell effects or entity descriptions.
    local translated = TranslateKnownFormats(text, formats, function(value, formatKey)
        if value == "+" or value == "-" then return value end
        local number = EnglishNumber(value, false)
        if number then return FormatTargetNumber(number, locale) end
        -- Stat value slots use damage-school labels. Other UI contexts can share
        -- the same source word while having different localized names.
        if formatKey == "ITEM_RESIST_SINGLE" and addon.GetClientLabel then
            local school, matched
            for index = 2, 7 do
                local key = "DAMAGE_SCHOOL" .. index
                local source = addon:GetClientLabel(key, GetLocale())
                if Readable(source, "string") and Normalize(value) == Normalize(source) then
                    local destination = addon:GetClientLabel(key, locale)
                    if not Readable(destination, "string") or school and school ~= destination then return end
                    school, matched = destination, true
                end
            end
            if matched then return school end
        end
        if addon.TranslateClientLabel then return addon:TranslateClientLabel(value, locale) end
        for key, label in pairs(target or {}) do
            if Readable(NativeFormat(key), "string") and Normalize(value) == Normalize(NativeFormat(key)) then return label end
        end
    end, true, locale)
    if values then values[text], cache.count = translated or false, cache.count + 1 end
    return translated
end

local function TranslateItemRequirement(addon, line, id, locale)
    if not IsLineType(line, "UsageRequirement") or not Readable(line.leftText, "string") then return end
    if Readable(line.rank, "number") and line.rank > 0 and line.rank == math.floor(line.rank)
        and type(UnitFactionGroup) == "function" and type(UnitSex) == "function" then
        local ok, faction = pcall(UnitFactionGroup, "player")
        local sexOK, sex = pcall(UnitSex, "player")
        if ok and Readable(faction, "string") and sexOK and Readable(sex, "number") and (sex == 2 or sex == 3) then
            local team = faction == "Alliance" and 1 or faction == "Horde" and 0
            if team then
                local key = "PVP_RANK_" .. line.rank .. "_" .. team .. (sex == 3 and "_FEMALE" or "")
                local source = NativeFormat(key)
                local target = addon.GetClientLabel and addon:GetClientLabel(key, locale)
                if Readable(source, "string") and Readable(target, "string") then
                    local translated = addon:TranslateOwnedTooltipFormat(line.leftText, "ITEM_REQ_SKILL", locale, function(value)
                        if Normalize(value) == Normalize(source) then return target end
                    end)
                    if translated then return translated end
                end
            end
        end
    end
    local rules = ForeverRosettaStoneDB:GetItemRules(id)
    local requirements = rules and rules.requirements
    if type(requirements) ~= "table" then return end
    local function Format(key, convert)
        local formats = addon.tooltipFormatsByLocale and addon.tooltipFormatsByLocale[locale]
        local target = addon.GetClientLabel and addon:GetClientLabel(key, locale)
            or formats and formats[key]
        if not Readable(target, "string") then return end
        return TranslateFormat(line.leftText, NativeFormat(key), target, convert, true, locale)
    end
    local classes = requirements.classIDs
    if type(classes) == "table" and #classes > 0 and #classes <= 32 then
        local translated = Format("ITEM_CLASSES_ALLOWED", function(text)
            local names, used = {}, {}
            for part in (text .. ","):gmatch("(.-),") do
                part = Normalize(part):gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")
                local match, target
                for _, classID in ipairs(classes) do
                    local source = ForeverRosettaStoneDB:GetClassName(classID, GetLocale())
                    if Readable(source, "string") and Normalize(source) == part then
                        if match then return end
                        match = classID
                        target = ForeverRosettaStoneDB:GetClassName(classID, locale)
                    end
                end
                if not match or used[match] or not Readable(target, "string") then return end
                used[match], names[#names + 1] = true, target
            end
            if #names == #classes then return table.concat(names, ", ") end
        end)
        if translated then return translated end
    end
    -- Each owned ID binds one name; any other captured value must be a live number or label.
    local function Names(getName, entityID)
        if not Readable(entityID, "number") then return end
        local source = getName(ForeverRosettaStoneDB, entityID, GetLocale())
        local target = getName(ForeverRosettaStoneDB, entityID, locale)
        if Readable(source, "string") and Readable(target, "string") then return source, target end
    end
    local source, target = Names(ForeverRosettaStoneDB.GetProfessionCategoryName, requirements.skillCategoryID)
    if source then
        local translated = Format("ITEM_MIN_SKILL", function(value)
            if Normalize(value) == Normalize(source) then return target end
            local number = EnglishNumber(value, false)
            return number and FormatTargetNumber(number, locale)
        end)
        if translated then return translated end
    end
    source, target = Names(ForeverRosettaStoneDB.GetFactionName, requirements.factionID)
    if source then
        local factionSource, factionTarget = source, target
        local translated = Format("ITEM_REQ_REPUTATION", function(value)
            if Normalize(value) == Normalize(factionSource) then return factionTarget end
            -- The standing is the client's live reputation label, never a catalog constant.
            for standing = 1, 8 do
                for _, suffix in ipairs({ "", "_FEMALE" }) do
                    local key = "FACTION_STANDING_LABEL" .. standing .. suffix
                    if Readable(NativeFormat(key), "string") and Normalize(value) == Normalize(NativeFormat(key)) then
                        return addon.GetClientLabel and addon:GetClientLabel(key, locale)
                    end
                end
            end
        end)
        if translated then return translated end
    end
    source, target = Names(ForeverRosettaStoneDB.GetSpellName, requirements.abilitySpellID)
    if source then
        return Format("ITEM_REQ_SKILL", function(value)
            if Normalize(value) == Normalize(source) then return target end
        end)
    end
end

-- Set rows name the item's own set, its owned pieces and its owned bonus spells. Counts stay live.
local function TranslateItemSetLine(addon, line, id, locale)
    if Readable(line.spellID, "number") or not Readable(line.leftText, "string") then return end
    local rules = ForeverRosettaStoneDB:GetItemRules(id)
    local set = type(rules) == "table" and type(rules.set) == "table" and rules.set
    if not set then return end
    local text = line.leftText
    local function Target(key)
        local formats = locale == "enUS" and addon.englishTooltipFormats
            or addon.tooltipFormatsByLocale and addon.tooltipFormatsByLocale[locale]
        local target = addon.GetClientLabel and addon:GetClientLabel(key, locale) or formats and formats[key]
        return Readable(target, "string") and target or nil
    end
    local function Number(value)
        local number = EnglishNumber(value, false)
        return number and FormatTargetNumber(number, locale)
    end
    local source = ForeverRosettaStoneDB:GetItemDetails(id, GetLocale())
    local target = ForeverRosettaStoneDB:GetItemDetails(id, locale)
    local sourceName = type(source) == "table" and type(source.set) == "table" and source.set.name
    local targetName = type(target) == "table" and type(target.set) == "table" and target.set.name
    local nameFormat = Target("ITEM_SET_NAME")
    if Readable(sourceName, "string") and Readable(targetName, "string") and nameFormat then
        local translated = TranslateFormat(text, NativeFormat("ITEM_SET_NAME"), nameFormat, function(value)
            if Normalize(value) == Normalize(sourceName) then return targetName end
            return Number(value)
        end, true, locale)
        if translated then return translated end
    end
    local indent, body = text:match("^([ \t\r\n]+)(%S.-)$")
    if indent and type(set.items) == "table" then
        local match
        for _, pieceID in ipairs(set.items) do
            local pieceSource = ForeverRosettaStoneDB:GetItemName(pieceID, GetLocale())
            if Readable(pieceSource, "string") and Normalize(pieceSource) == Normalize(body) then
                if match and match ~= pieceID then return end
                match = pieceID
            end
        end
        local pieceTarget = match and ForeverRosettaStoneDB:GetItemName(match, locale)
        if Readable(pieceTarget, "string") then return indent .. pieceTarget end
    end
    if type(set.bonuses) ~= "table" or not addon.TranslateLiveSpellDescription then return end
    local function Bonus(value)
        -- An API tooltip can expose only the set-bonus header while its effect
        -- text is unavailable. Translate the header without fabricating an effect.
        if value == "" then return "" end
        local number = Number(value)
        if number then return number end
        local found
        for _, bonus in ipairs(set.bonuses) do
            local spellID = type(bonus) == "table" and bonus.spellID
            local translated = Readable(spellID, "number") and addon:TranslateLiveSpellDescription(spellID, locale, value)
            if translated then
                if found and found ~= translated then return end
                found = translated
            end
        end
        return found
    end
    for _, key in ipairs({ "ITEM_SET_BONUS_GRAY", "ITEM_SET_BONUS" }) do
        local bonusFormat = Target(key)
        local translated = bonusFormat and TranslateFormat(text, NativeFormat(key), bonusFormat, Bonus, true, locale)
        if translated then return translated end
    end
end

-- Rows such as ammo show the item class name on the left. Only the client-language name of the
-- item's own class is replaced, so unrelated text never gains a guessed translation.
local function TranslateItemClassName(addon, details, text, locale)
    local classes = addon.itemClassesByLocale
    local classID = details and details.classID
    if not classes or not Readable(text, "string") or not Readable(classID, "number") then return end
    local native, target = classes[GetLocale()], classes[locale]
    if native and target and native[classID] and target[classID]
        and Normalize(text) == Normalize(native[classID]) then
        return target[classID]
    end
end

local function TranslateOwnedItemText(addon, line, id, locale)
    if not IsLineType(line, "None") or not Readable(line.leftText, "string") then return end
    local source = ForeverRosettaStoneDB:GetItemDetails(id, GetLocale())
    local target = ForeverRosettaStoneDB:GetItemDetails(id, locale)
    if not source or not target then return end
    -- The client occasionally emits a malformed eight-character color header. Keep it
    -- opaque; only the exact owned text inside this wrapper is eligible for replacement.
    local opening, body, closing = line.leftText:match("^(|c[^|][^|][^|][^|][^|][^|][^|][^|])(.-)(|r)$")
    local text = body or line.leftText
    for _, field in ipairs({ "nameDescription", "description" }) do
        if Readable(source[field], "string") and Readable(target[field], "string")
            and Normalize(text) == Normalize(source[field]) then
            return WrapSharedTranslation(target[field], opening, closing)
        end
    end
end

local function TranslateItemSubclassName(addon, details, text, locale)
    if not details or not Readable(text, "string") then return end
    local names = addon.itemSubclassesByLocale
    local source = names and names[GetLocale()] and names[GetLocale()][details.classID]
    local target = names and names[locale] and names[locale][details.classID]
    source, target = source and source[details.subclassID], target and target[details.subclassID]
    if Readable(source, "string") and Readable(target, "string") and Normalize(text) == Normalize(source) then
        return target
    end
end

local function TranslateContainerLine(addon, line, id, locale)
    if not IsLineType(line, "None") or not Readable(line.leftText, "string") then return end
    local rules = ForeverRosettaStoneDB:GetItemRules(id)
    if not rules or not Readable(rules.containerSlots, "number") or rules.containerSlots <= 0 then return end
    local names = addon.itemSubclassesByLocale
    local source = names and names[GetLocale()] and names[GetLocale()][rules.classID]
    local target = names and names[locale] and names[locale][rules.classID]
    source, target = source and source[rules.subclassID], target and target[rules.subclassID]
    if not Readable(source, "string") or not Readable(target, "string") then return end
    return addon:TranslateOwnedTooltipFormat(line.leftText, "CONTAINER_SLOTS", locale, function(value)
        if Normalize(value) == Normalize(source) then return target end
        local number = EnglishNumber(value, false)
        return number and FormatTargetNumber(number, locale)
    end)
end

local function TranslateOwnedItemRestriction(addon, line, id, locale)
    if not Readable(line.leftText, "string") then return end
    local rules = ForeverRosettaStoneDB:GetItemRules(id)
    if not rules then return end
    if IsLineType(line, "None") and Readable(rules.interactionLabelID, "number")
        and ForeverRosettaStoneDB.GetGlobalString then
        -- A captured native action owns this label ID. Localized wording can
        -- collapse reading and signing into the same text without losing its owner.
        local source = ForeverRosettaStoneDB:GetGlobalString(rules.interactionLabelID, GetLocale())
        local target = ForeverRosettaStoneDB:GetGlobalString(rules.interactionLabelID, locale)
        if Readable(source, "string") and Readable(target, "string")
            and Normalize(source) == Normalize(line.leftText) then return target end
    end
    -- Armor/Cosmetic identifies an appearance requirement, rather than a
    -- learned recipe or another UI message with identical localized wording.
    if IsLineType(line, "UsageRequirement") and rules.classID == 4 and rules.subclassID == 5 then
        local known = addon:TranslateOwnedTooltipFormat(line.leftText, "ERR_COSMETIC_KNOWN", locale)
        if known then return known end
    end
    if IsLineType(line, "ErrorLine") and type(rules.requiredLockTypes) == "table" and #rules.requiredLockTypes > 0 then
        local locked = addon:TranslateOwnedTooltipFormat(line.leftText, "LOCKED", locale)
        if locked then return locked end
    end
    local function NamedFormat(key, ids, getter)
        if type(getter) ~= "function" then return end
        return addon:TranslateOwnedTooltipFormat(line.leftText, key, locale, function(value, kind)
            local number = kind ~= "s" and EnglishNumber(value, false)
            if number then return FormatTargetNumber(number, locale) end
            local translated, matched
            for _, owner in ipairs(ids or {}) do
                local source = getter(ForeverRosettaStoneDB, owner, GetLocale())
                local target = getter(ForeverRosettaStoneDB, owner, locale)
                if Readable(source, "string") and Normalize(value) == Normalize(source) then
                    if matched or not Readable(target, "string") then return end
                    translated, matched = target, true
                end
            end
            return translated
        end)
    end
    if IsLineType(line, "None") then
        if Readable(rules.limitCategoryID, "number") then
            for _, key in ipairs({ "ITEM_LIMIT_CATEGORY", "ITEM_LIMIT_CATEGORY_MULTIPLE" }) do
                local result = NamedFormat(key, {rules.limitCategoryID}, ForeverRosettaStoneDB.GetItemLimitCategoryName)
                if result then return result end
            end
        end
        local holiday = NamedFormat("ITEM_REQ_SKILL", rules.requiredHolidayNames, ForeverRosettaStoneDB.GetHolidayName)
        if holiday then return holiday end
        for _, key in ipairs({ "TRANSMOG_APPEARANCE_USABLE_HOLIDAY", "TRANSMOG_REQUIRED_HOLIDAY" }) do
            local result = NamedFormat(key, rules.requiredTransmogHolidayNames, ForeverRosettaStoneDB.GetHolidayName)
            if result then return result end
        end
        for _, area in ipairs(rules.boundAreaIDs or {}) do
            local source = ForeverRosettaStoneDB:GetAreaName(area, GetLocale())
            local target = ForeverRosettaStoneDB:GetAreaName(area, locale)
            if Readable(source, "string") and Readable(target, "string")
                and Normalize(line.leftText) == Normalize(source) then return target end
        end
    elseif IsLineType(line, "ErrorLine") then
        return NamedFormat("ITEM_MIN_SKILL", rules.requiredLockTypes, ForeverRosettaStoneDB.GetLockTypeName)
    end
end

local enchantTimeFormats = {
    "ITEM_ENCHANT_TIME_LEFT_SEC", "ITEM_ENCHANT_TIME_LEFT_MIN",
    "ITEM_ENCHANT_TIME_LEFT_HOURS", "ITEM_ENCHANT_TIME_LEFT_DAYS",
}

local function EnchantmentPattern(source)
    local parts, tokens, offset = { "^" }, {}, 1
    while true do
        local first, last, token = source:find("(%$[%a]+%d*)", offset)
        if not first then break end
        if token ~= "$i" and not token:match("^%$k[123]$") then return end
        parts[#parts + 1] = Escape(source:sub(offset, first - 1))
        parts[#parts + 1] = "([%+%-]?%d+[.,]?%d*)"
        tokens[#tokens + 1] = token
        offset = last + 1
    end
    if #tokens == 0 then return end
    parts[#parts + 1] = Escape(source:sub(offset)) .. "$"
    return table.concat(parts), tokens
end

local function MatchEnchantment(body, source, target, locale, pattern, tokens)
    if not pattern then
        if body == source then return target and not target:find("%$[%a]") and target or nil, true end
        return
    end
    local values = { body:match(pattern) }
    if #values == 0 then return end
    if not target then return nil, true end
    local captured = {}
    for index, token in ipairs(tokens) do
        local value = EnglishNumber(values[index], false)
        if not value or (captured[token] and captured[token] ~= value) then return nil, true end
        captured[token] = value
    end
    local used, unresolved = {}, false
    local translated = target:gsub("%$[%a]+%d*", function(token)
        local value = captured[token]
        if not value then unresolved = true; return end
        used[token] = true
        return FormatTargetNumber(value, locale)
    end)
    for token in pairs(captured) do
        if not used[token] then return nil, true end
    end
    if unresolved then return nil, true end
    return translated, true
end

local function MergeEnchantmentMatch(current, translated, matched)
    if not matched then return current end
    if not translated or (current and current ~= translated) then return false end
    return translated
end

local function TranslateEnchantmentByID(body, id, locale)
    local source, sourceHorde = ForeverRosettaStoneDB:GetItemEnchantmentNames(id, GetLocale())
    local target, targetHorde = ForeverRosettaStoneDB:GetItemEnchantmentNames(id, locale)
    local function Match(name, localized)
        if not name then return end
        name = Normalize(name)
        local spellID = tonumber(name:match("^%$@spelldesc(%d+)$"))
        if spellID and (not localized or localized == name) then
            local description = Addon:TranslateLiveSpellDescription(spellID, locale, body)
            return description, description ~= nil
        end
        local pattern, tokens = EnchantmentPattern(name)
        return MatchEnchantment(body, name, localized, locale, pattern, tokens)
    end
    local translated, matched = Match(source, target)
    local alternate, alternateMatched = Match(sourceHorde, targetHorde)
    local result = MergeEnchantmentMatch(nil, translated, matched)
    if result == false then return end
    return MergeEnchantmentMatch(result, alternate, alternateMatched) or nil
end

local temporaryEnchantmentIndexes = {}

local function GetTemporaryEnchantmentIndex(sourceLocale)
    local cached = temporaryEnchantmentIndexes[sourceLocale]
    if cached then return cached end
    local exact, dynamic = {}, {}
    for _, id in ipairs(ForeverRosettaStoneDB:GetTemporaryItemEnchantmentIDs() or {}) do
        local name, alternate = ForeverRosettaStoneDB:GetItemEnchantmentNames(id, sourceLocale)
        for index, source in pairs({ name, alternate }) do
            source = Normalize(source)
            local entry = { id = id, index = index, source = source }
            if source:find("%$[%a]") then
                entry.pattern, entry.tokens = EnchantmentPattern(source)
                if entry.pattern then dynamic[#dynamic + 1] = entry end
            else
                exact[source] = exact[source] or {}
                exact[source][#exact[source] + 1] = entry
            end
        end
    end
    cached = { exact = exact, dynamic = dynamic }
    temporaryEnchantmentIndexes[sourceLocale] = cached
    return cached
end

local function TranslateTemporaryEnchantment(body, locale)
    local index = GetTemporaryEnchantmentIndex(GetLocale())
    local result
    for _, entries in ipairs({ index.exact[body] or {}, index.dynamic }) do
        for _, entry in ipairs(entries) do
            if not entry.pattern or body:match(entry.pattern) then
                local name, alternate = ForeverRosettaStoneDB:GetItemEnchantmentNames(entry.id, locale)
                local target = entry.index == 1 and name or entry.index == 2 and alternate
                local translated, matched = MatchEnchantment(body, entry.source, target, locale, entry.pattern, entry.tokens)
                result = MergeEnchantmentMatch(result, translated, matched)
                if result == false then return end
            end
        end
    end
    return result
end

local function TranslateItemEnchantment(addon, line, locale)
    local text, id = line.leftText, line.enchantID
    if GetLocale() == locale or not Readable(text, "string") then return end
    local hasID = Readable(id, "number") and id > 0
    if not hasID and (not IsLineType(line, "None") or Readable(line.spellID, "number")) then return end
    local function TranslateBody(value)
        if hasID then return TranslateEnchantmentByID(value, id, locale) end
        return TranslateTemporaryEnchantment(value, locale)
    end
    if hasID then
        local translated = addon:TranslateOwnedTooltipFormat(text, "ENCHANTED_TOOLTIP_LINE", locale, TranslateBody)
            or TranslateBody(Normalize(text))
        if translated then return translated end
    end
    for _, key in ipairs(enchantTimeFormats) do
        local translated = addon:TranslateOwnedTooltipFormat(text, key, locale, function(value, kind)
            if kind == "s" then return TranslateBody(value) end
            local number = EnglishNumber(value, false)
            return number and FormatTargetNumber(number, locale)
        end)
        if translated then return translated end
    end
end

function Addon:GetEnglishTooltipLine(data, line, kind, id, sharedTextCache)
    if not canaccessallvalues(line.type, line.leftText, line.rightText) then return end
    if kind == "item" then
        local enchantment = TranslateItemEnchantment(self, line, "enUS")
        if enchantment then return enchantment end
    end
    if kind == "item" and not Readable(line.spellID, "number") then
        local owned = TranslateOwnedItemText(self, line, id, "enUS")
        if owned then return owned end
        local restriction = TranslateOwnedItemRestriction(self, line, id, "enUS")
        if restriction then return restriction end
        local container = TranslateContainerLine(self, line, id, "enUS")
        if container then return container end
        local requirement = TranslateItemRequirement(self, line, id, "enUS")
        if requirement then return requirement end
        local setLine = TranslateItemSetLine(self, line, id, "enUS")
        if setLine then return setLine end
        local stat = TranslateItemStatLine(self, line.leftText, "enUS", sharedTextCache)
        if stat then return stat end
    end
    if kind == "item" and IsLineType(line, "FlavorText") then
        local shared = TranslateSharedTooltipText(self, line.leftText, "enUS")
        if shared then return shared end
        local rules = ForeverRosettaStoneDB:GetItemRules(id)
        if type(rules) == "table" and rules.descriptionRow ~= nil then return end
        local target = ForeverRosettaStoneDB:GetItemDetails(id, "enUS")
        return target and target.description
    end
    local verified, referenced = TranslateTooltipEffect(self, line, kind, id, "enUS", data)
    if verified then return verified end
    if referenced then return self.TranslateClientLabel and self:TranslateClientLabel(line.leftText, "enUS") end
    local left, right = line.leftText, line.rightText
    if IsLineType(line, "ItemName") or IsLineType(line, "SpellName") then return end
    if IsLineType(line, "SellPrice") and Readable(line.price, "number") then
        return "Sell Price: " .. Money(line.price)
    end
    if GetLocale() == "enUS" then return left, right end
    local translatedLeft, translatedRight
    if kind == "item" then
        local details = ForeverRosettaStoneDB:GetItemRules(id)
        local subclasses = details and self.itemSubclasses[details.classID]
        local subclass = subclasses and subclasses[details.subclassID]
        if IsLineType(line, "None") then
            translatedLeft = TranslateItemSubclassName(self, details, left, "enUS")
        elseif IsLineType(line, "EquipSlot") then
            translatedRight = Readable(right, "string") and right ~= "" and subclass or translatedRight
            translatedLeft = TranslateItemClassName(self, details, left, "enUS")
                or TranslateItemSubclassName(self, details, left, "enUS")
        end
    end
    return translatedLeft or TranslateSharedTooltipText(self, left, "enUS", sharedTextCache),
        translatedRight or TranslateSharedTooltipText(self, right, "enUS", sharedTextCache)
end

function Addon:GetEnglishTooltipSubtext(line, kind, id)
    if not Readable(line.rightText, "string") then return end
    if (kind == "spell" or kind == "talent") and IsLineType(line, "SpellName") then
        local target = ForeverRosettaStoneDB:GetSpellDetails(id, "enUS")
        return target and target.rank
    end
    if GetLocale() == "enUS" then return line.rightText end
    return TranslateSharedTooltipText(self, line.rightText, "enUS")
end

local function GetTargetFormats(locale)
    return Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale[locale]
end

local function TranslateLocalizedTooltipLine(self, line, kind, id, locale, data, sharedTextCache)
    if kind == "item" then
        local enchantment = TranslateItemEnchantment(self, line, locale)
        if enchantment then return enchantment end
    end
    if kind == "item" and not Readable(line.spellID, "number") then
        local owned = TranslateOwnedItemText(self, line, id, locale)
        if owned then return owned end
        local restriction = TranslateOwnedItemRestriction(self, line, id, locale)
        if restriction then return restriction end
        local container = TranslateContainerLine(self, line, id, locale)
        if container then return container end
        local requirement = TranslateItemRequirement(self, line, id, locale)
        if requirement then return requirement end
        local setLine = TranslateItemSetLine(self, line, id, locale)
        if setLine then return setLine end
        local stat = TranslateItemStatLine(self, line.leftText, locale, sharedTextCache)
        if stat then return stat end
    end
    if kind == "item" and IsLineType(line, "FlavorText") then
        local shared = TranslateSharedTooltipText(self, line.leftText, locale)
        if shared then return shared end
        local rules = ForeverRosettaStoneDB:GetItemRules(id)
        if type(rules) == "table" and rules.descriptionRow ~= nil then return nil, nil, true end
        local target = ForeverRosettaStoneDB:GetItemDetails(id, locale)
        return target and target.description
    end
    if (kind == "spell" or kind == "talent") and IsLineType(line, "SpellName") then
        local target = ForeverRosettaStoneDB:GetSpellDetails(id, locale)
        return nil, target and target.rank
    end
    local verified, referenced = TranslateTooltipEffect(self, line, kind, id, locale, data)
    if verified then return verified end
    if referenced then
        local label = self.TranslateClientLabel and self:TranslateClientLabel(line.leftText, locale)
        return label, nil, not label
    end
    local left, right = line.leftText, line.rightText
    if IsLineType(line, "SellPrice") and Readable(line.price, "number") then
        local formats = GetTargetFormats(locale)
        local label = formats and formats.SELL_PRICE
        if label then
            label = label:gsub("[ \t\r\n]+$", "")
            local hasColon = label:sub(-1) == ":" or label:sub(-3) == "："
            return label .. (hasColon and " " or ": ") .. Money(line.price)
        end
        local native = Readable(NativeFormat("SELL_PRICE"), "string") and NativeFormat("SELL_PRICE") .. " " or ""
        return native .. Money(line.price), nil, GetLocale() ~= locale
    end
    local translatedLeft, translatedRight
    if kind == "item" then
        local details = ForeverRosettaStoneDB:GetItemRules(id)
        local subclassLocales = self.itemSubclassesByLocale and self.itemSubclassesByLocale[locale]
        local subclasses = details and subclassLocales and subclassLocales[details.classID]
        local subclass = subclasses and subclasses[details.subclassID]
        if IsLineType(line, "None") then
            translatedLeft = TranslateItemSubclassName(self, details, left, locale)
        elseif IsLineType(line, "EquipSlot") then
            if Readable(right, "string") and right ~= "" and subclass then translatedRight = subclass end
            translatedLeft = TranslateItemClassName(self, details, left, locale)
                or TranslateItemSubclassName(self, details, left, locale)
        end
    end
    return translatedLeft or TranslateSharedTooltipText(self, left, locale, sharedTextCache),
        translatedRight or TranslateSharedTooltipText(self, right, locale, sharedTextCache)
end

function Addon:GetLocalizedTooltipLine(line, kind, id, locale, data, sharedTextCache)
    if not canaccessallvalues(line.type, line.leftText, line.rightText) then return end
    local left, right, incomplete = TranslateLocalizedTooltipLine(self, line, kind, id, locale, data, sharedTextCache)
    if GetLocale() == locale and not (self.tooltipLocaleReplacements and self.tooltipLocaleReplacements[locale]) then
        left = left or (Readable(line.leftText, "string") and line.leftText)
        right = right or (Readable(line.rightText, "string") and line.rightText)
    end
    return left, right, incomplete
end

local function CopyLineFont(target, original)
    if not target or not original then return end
    local font, size, flags = original:GetFont()
    if font and size then target:SetFont(font, size, flags) end
    target:SetTextScale(original:GetTextScale())
end

local function GetColor(color, fallback)
    if fallback then return fallback:GetTextColor() end
    if color and canaccessallvalues(color) and color.GetRGB then return color:GetRGB() end
    if color and canaccessallvalues(color.r, color.g, color.b) then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function PreserveInlineLineColors(native, translated)
    if not Readable(native, "string") or not Readable(translated, "string")
        or not native:find("|[cC]") then return translated end
    local nativeLines, translatedCount = {}, 0
    for text in native:gmatch("[^\r\n]+") do nativeLines[#nativeLines + 1] = text end
    for _ in translated:gmatch("[^\r\n]+") do translatedCount = translatedCount + 1 end
    if #nativeLines ~= translatedCount then return translated end
    local index = 0
    local result = translated:gsub("[^\r\n]+", function(text)
        index = index + 1
        local color, body = nativeLines[index]:match("^(|[cC]%x%x%x%x%x%x%x%x)(.-)|[rR]$")
        if color and not body:find("|[cCrR]") and not text:find("|[cC]") then return color .. text .. "|r" end
        return text
    end)
    return result
end

local function AddSalePriceRange(tip, source, line, locale)
    local formats = Addon.tooltipFormatsByLocale[locale]
    local label = formats.SELL_PRICE:gsub("[ \t\r\n]+$", "")
    if label:sub(-1) ~= ":" and label:sub(-3) ~= "：" then label = label .. ":" end
    local rows = { label, "    " .. formats.MINIMUM .. ": " .. Money(line.price),
        "    " .. formats.MAXIMUM .. ": " .. Money(line.maxPrice) }
    for index, text in ipairs(rows) do
        tip:AddLine(text, GetColor(HIGHLIGHT_FONT_COLOR))
        local originalIndex = Readable(line.lineIndex, "number") and line.lineIndex + index
        CopyLineFont(tip:GetLeftLine(tip:NumLines()), originalIndex and source:GetLeftLine(originalIndex))
    end
end

local function GetRenderedTalentLines(source, lines)
    if not source.NumLines then return lines end
    local function Key(left, right)
        left = Readable(left, "string") and Normalize(left):match("^[ \t\r\n]*(.-)[ \t\r\n]*$") or ""
        right = Readable(right, "string") and Normalize(right):match("^[ \t\r\n]*(.-)[ \t\r\n]*$") or ""
        if left == "" and right == "" then return end
        return left .. "\0" .. right
    end
    local metadata = {}
    local display = {lineIndex=true, leftText=true, rightText=true, leftColor=true, rightColor=true}
    for _, native in ipairs(lines) do
        local key = Key(native.leftText, native.rightText)
        if key then
            if not metadata[key] then
                local fields = {}
                for field, value in pairs(native) do
                    if not display[field] and canaccessallvalues(value)
                        and (type(value) == "number" or type(value) == "string" or type(value) == "boolean") then
                        fields[field] = value
                    end
                end
                metadata[key] = fields
            else
                -- Identical text in two native rows may retain only shared metadata.
                for field, value in pairs(metadata[key]) do
                    if not canaccessallvalues(native[field]) or native[field] ~= value then metadata[key][field] = nil end
                end
            end
        end
    end
    local rendered = {}
    local stacked = Addon.stackedTooltips and Addon.stackedTooltips[source]
    local count = stacked and #stacked.rows or source:NumLines()
    for index = 1, count do
        local leftLine = source:GetLeftLine(index)
        local left = leftLine and leftLine:GetText()
        local rightLine = source.GetRightLine and source:GetRightLine(index)
        local right = rightLine and rightLine:GetText()
        local row = { lineIndex = index, leftText = left, rightText = right }
        local key = Key(left, right)
        for field, value in pairs(key and metadata[key] or {}) do row[field] = value end
        rendered[#rendered + 1] = row
    end
    return rendered
end

local function IsTalentPurchaseRequirement(line, formats)
    if not Readable(line.leftText, "string")
        or Readable(line.rightText, "string") and line.rightText:find("%S") then return false end
    for _, format in ipairs(formats or {}) do
        -- These are owned client purchase-gate formats, not descriptions or rank previews.
        -- Matching uses the whole row and the source's exact plural alternatives.
        if TranslateFormat(line.leftText, format, "", function(value) return value end, true, GetLocale()) ~= nil then
            return true
        end
    end
    return false
end

local function IsMountRidingRequirement(line)
    if not Readable(line.leftText, "string")
        or Readable(line.rightText, "string") and line.rightText:find("%S") then return false end
    local database = ForeverRosettaStoneDB
    if not database.GetGlobalStringKeysByText then return false end
    local text = Normalize(line.leftText):gsub("^ +", ""):gsub(" +$", "")
    for _, key in ipairs(database:GetGlobalStringKeysByText(text, GetLocale()) or {}) do
        if key:match("^SPELL_FAILED_.+_RIDING_REQUIREMENT$") then
            local source = Addon.GetClientLabel and Addon:GetClientLabel(key, GetLocale())
            if Readable(source, "string") and Normalize(source) == text then return true end
        end
    end
    return false
end

local function CaptureLiveDescriptionRows(addon, spec, lines, nameLine, locale, aura, spellContexts, inlineTooltips)
    local translated, skipped = {}, {}
    if spec.kind ~= "spell" and spec.kind ~= "talent" then
        return translated, skipped
    end
    local unit
    if aura and addon.GetTooltipAuraData then
        local liveAura
        liveAura, unit = addon:GetTooltipAuraData(spec.source)
        if not liveAura or liveAura.spellId ~= spec.id then return translated, skipped end
    end
    local candidates, seen = {}, {}
    for first, line in ipairs(lines) do
        local owner = spellContexts and spellContexts[line] or spec.id
        if line ~= nameLine and canaccessallvalues(line.type) and not IsLineType(line, "SpellName") then
            local text = {}
            for last = first, math.min(#lines, first + 15) do
                local row = lines[last]
                if (spellContexts and spellContexts[row] or spec.id) ~= owner then break end
                if row == nameLine or not canaccessallvalues(row.type, row.leftText)
                    or not Readable(row.leftText, "string") or IsLineType(row, "SpellName") then break end
                if not aura and spec.kind == "spell" and not IsLineType(row, "SpellDescription") then break end
                text[#text + 1] = row.leftText
                local value = addon:TranslateLiveSpellDescription(owner, locale, table.concat(text, "\n"),
                    aura and "auraDescription" or "description", unit, owner == spec.id and inlineTooltips or nil)
                if value then
                    local start, finish = first, last
                    while start < finish and Normalize(lines[start].leftText):match("^[ \t\r\n]*$") do start = start + 1 end
                    while finish > start and Normalize(lines[finish].leftText):match("^[ \t\r\n]*$") do finish = finish - 1 end
                    local key = start .. ":" .. finish
                    if not seen[key] then
                        seen[key] = true
                        candidates[#candidates + 1] = {first=start, last=finish, value=value}
                    end
                end
            end
        end
    end
    -- Independent descriptions (current and next talent ranks) can coexist. Overlapping
    -- interpretations remain ambiguous and must not consume one another's native rows.
    for _, match in ipairs(candidates) do
        local ambiguous = false
        for _, other in ipairs(candidates) do
            if other ~= match and match.first <= other.last and other.first <= match.last then
                ambiguous = true
                break
            end
        end
        if not ambiguous then
            -- Matching trims whitespace; keep the native gap before the following tooltip row.
            local ending = lines[match.last].leftText:gsub("\\r\\n", "\n"):gsub("\\n", "\n")
                :gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("|n", "\n"):match("[\n \t]*$")
            translated[lines[match.first]] = match.value:gsub("[\r\n \t]+$", "") .. ending:gsub("[^\n]", "")
            for index = match.first + 1, match.last do skipped[lines[index]] = true end
        end
    end
    return translated, skipped
end

local function EmbeddedItemContexts(spec, lines)
    local candidates, learned = {}, {}
    local function CreatedBy(spellID)
        local rules = ForeverRosettaStoneDB:GetSpellRules(spellID)
        for _, itemID in ipairs(rules and rules.createdItemIDs or {}) do candidates[itemID] = true end
    end
    if spec.kind == "spell" then CreatedBy(spec.id)
    elseif spec.kind == "item" then
        local rules = ForeverRosettaStoneDB:GetItemRules(spec.id)
        for _, effect in ipairs(rules and rules.effects or {}) do
            if effect.triggerType == 6 then learned[effect.spellID] = true; CreatedBy(effect.spellID) end
        end
    end
    local unique
    for itemID in pairs(candidates) do
        if unique then unique = nil; break end
        unique = itemID
    end
    local contexts, titles, current, nested = {}, {}, nil, nil
    for index, line in ipairs(lines) do
        if IsLineType(line, "NestedBlock") then
            current, nested = nil, false
            local types = Enum and Enum.TooltipDataType
            if types and canaccessallvalues(line.tooltipType, line.tooltipID)
                and line.tooltipType == types.Item and Readable(line.tooltipID, "number")
                and ForeverRosettaStoneDB:GetItemName(line.tooltipID, GetLocale()) then
                nested = line.tooltipID
            end
        elseif IsLineType(line, "ItemName") and (spec.kind ~= "item" or index > 1) then
            local sourceName = nested and ForeverRosettaStoneDB:GetItemName(nested, GetLocale())
            if nested ~= nil then
                current = Readable(line.leftText, "string") and Readable(sourceName, "string")
                    and Normalize(line.leftText):match("^[ \t\r\n]*(.-)[ \t\r\n]*$")
                        == Normalize(sourceName):match("^[ \t\r\n]*(.-)[ \t\r\n]*$") and nested or nil
            else
                current = Readable(line.itemID, "number") and candidates[line.itemID] and line.itemID or unique
            end
            nested = nil
            if current then titles[line] = current end
        elseif IsLineType(line, "ItemSpellTriggerLearn") and Readable(line.spellID, "number") and learned[line.spellID] then
            current = nil
        end
        if current then contexts[line] = current end
    end
    return contexts, titles
end

local function EmbeddedSpellContexts(spec, lines)
    local contexts, titles, inline = {}, {}, {}
    if spec.kind ~= "spell" and spec.kind ~= "talent" then return contexts, titles, inline end
    local details = ForeverRosettaStoneDB:GetSpellDetails(spec.id, GetLocale())
    local template = details and details.description
    if not Readable(template, "string") then return contexts, titles, inline end
    local candidates = {}
    for reference in template:gmatch("%$@spelltooltip<?(%d+)>?") do candidates[tonumber(reference)] = true end
    local current
    for index, line in ipairs(lines) do
        if index > 1 and IsLineType(line, "SpellName") then
            local found
            for id in pairs(candidates) do
                local source = ForeverRosettaStoneDB:GetSpellName(id, GetLocale())
                if Readable(source, "string") and Readable(line.leftText, "string")
                    and Normalize(source) == Normalize(line.leftText) then
                    if found then found = nil; break end
                    found = id
                end
            end
            current = found
            if found then titles[line], inline[found] = found, true end
        end
        if current then contexts[line] = current end
    end
    return contexts, titles, inline
end

function Addon:GetEquippedTransmogItemLocation(slot)
    if ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        return ItemLocation:CreateFromEquipmentSlot(slot)
    end
end

function Addon:GetCharacterSheetTransmogInfo(slot)
    local scene = CharacterModelScene
    if not scene or not scene.GetPlayerActor or not scene:IsVisible() then return end
    local actor = scene:GetPlayerActor()
    if actor and actor.GetItemTransmogInfo then return actor:GetItemTransmogInfo(slot) end
end

local function GetInspectedAppearanceSources(unit, slot)
    if not InspectFrame or not InspectFrame:IsShown() or not Readable(InspectFrame.unit, "string")
        or UnitIsUnit(unit, InspectFrame.unit) ~= true then return end
    local collection = C_TransmogCollection
    local appearances = collection and collection.GetInspectItemTransmogInfoList
        and collection.GetInspectItemTransmogInfoList()
    local appearance = Readable(appearances, "table") and appearances[slot]
    if Readable(appearance, "table") then
        return appearance.appearanceID, appearance.secondaryAppearanceID
    end
end

local function TranslateEquippedAppearance(spec, lines, locale)
    local header = NativeFormat("TRANSMOGRIFIED_HEADER")
    if not Readable(header, "string") then return end
    local appearanceLine
    for index = 2, #lines - 1 do
        local line = lines[index]
        if Readable(line.leftText, "string") and Normalize(line.leftText) == Normalize(header) then
            appearanceLine = lines[index + 1]
            break
        end
    end
    if not appearanceLine or not canaccessallvalues(appearanceLine.type)
        or not IsLineType(appearanceLine, "None") or not Readable(appearanceLine.leftText, "string") then return end

    local source = spec.source
    local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
    if canaccessallvalues(info) and info == nil and source.GetPrimaryTooltipInfo then
        info = source:GetPrimaryTooltipInfo()
    end
    if not Readable(info, "table") or not canaccessallvalues(info.getterName)
        or info.getterName ~= "GetInventoryItem" or not Readable(info.getterArgs, "table") then return end
    local unit, slot = info.getterArgs[1], info.getterArgs[2]
    if not Readable(unit, "string") or not Readable(slot, "number") then return end
    local equippedID = GetInventoryItemID(unit, slot)
    if not Readable(equippedID, "number") or equippedID ~= spec.id then return end

    local collection = C_TransmogCollection
    if not collection then return end
    local nativeName = Normalize(appearanceLine.leftText)
    local function MatchSources(primary, secondary)
        local matchedID
        for _, sourceID in pairs({ primary, secondary }) do
            if Readable(sourceID, "number") and sourceID > 0 then
                local itemID = collection.GetSourceItemID and collection.GetSourceItemID(sourceID)
                if (not Readable(itemID, "number") or itemID <= 0) and collection.GetSourceInfo then
                    local sourceInfo = collection.GetSourceInfo(sourceID)
                    itemID = Readable(sourceInfo, "table") and sourceInfo.itemID
                end
                if Readable(itemID, "number") and itemID > 0 then
                    local sourceName = ForeverRosettaStoneDB:GetItemName(itemID, GetLocale())
                    if Readable(sourceName, "string") and Normalize(sourceName) == nativeName then
                        if matchedID and matchedID ~= itemID then return false end
                        matchedID = itemID
                    end
                end
            end
        end
        return matchedID
    end
    local function MatchInfo(appearance)
        if Readable(appearance, "table") then
            return MatchSources(appearance.appearanceID, appearance.secondaryAppearanceID)
        end
    end

    local matchedID
    if unit == "player" or UnitIsUnit(unit, "player") == true then
        local location = Addon:GetEquippedTransmogItemLocation(slot)
        if Readable(location, "table") and C_Item then
            for _, getter in ipairs({ "GetAppliedItemTransmogInfo", "GetCurrentItemTransmogInfo" }) do
                local query = C_Item[getter]
                if query then
                    matchedID = MatchInfo(query(location))
                    if matchedID ~= nil then break end
                end
            end
        end
        if matchedID == nil then
            matchedID = MatchInfo(Addon:GetCharacterSheetTransmogInfo(slot))
        end
    else
        matchedID = MatchSources(GetInspectedAppearanceSources(unit, slot))
    end
    if matchedID then return appearanceLine, ForeverRosettaStoneDB:GetItemName(matchedID, locale) end
end

function Addon:FillEnglishTooltip(spec)
    if not spec or not spec.source or not spec.tip or not canaccessallvalues(spec.data)
        or type(spec.data) ~= "table" then return end
    if spec.kind == "npc" or spec.kind == "player" then return self:FillNpcTooltip(spec) end
    local mount = spec.kind == "mount"
    -- Collection summon tooltips carry spell rows but retain their own feature switches.
    local petSpellID = spec.kind == "pet" and type(spec.id) == "string" and spec.id:match("^spell:(%d+)$")
    if spec.kind == "mount" or petSpellID or spec.kind == "appearance" then
        local spellSpec = {}
        for key, value in pairs(spec) do spellSpec[key] = value end
        spellSpec.kind = spec.kind == "appearance" and "item" or "spell"
        spellSpec.id = petSpellID and tonumber(petSpellID) or spec.id
        spec = spellSpec
    end
    local tip, source = spec.tip, spec.source
    local locale = self.GetTargetLocale and self:GetTargetLocale() or "enUS"
    -- Retain only shared label translations across native item refreshes. Entity effects stay live.
    if spec.kind == "item" then spec.sharedTextCache = spec.sharedTextCache or {} end
    local english = locale == "enUS"
    local aura = spec.kind == "spell" and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura
        and spec.data.type == Enum.TooltipDataType.UnitAura
    local title = source:GetLeftLine(1)
    local titleText = spec.name
    local lines = spec.data.lines or {}
    if spec.kind == "talent" then lines = GetRenderedTalentLines(source, lines) end
    if spec.kind == "talent" and self.IsDebugPicking and self:IsDebugPicking() then
        spec.debugNativeTalentLines = lines
    end
    local purchaseFormats = spec.kind == "talent" and ForeverRosettaStoneDB.GetSharedTextsByUsage
        and ForeverRosettaStoneDB:GetSharedTextsByUsage("talentPurchaseRequirement", GetLocale())
    if spec.kind == "talent" then
        purchaseFormats = purchaseFormats or {}
        -- Talent purchase gates also use GlobalStrings for edge and tier requirements.
        for _, key in ipairs({ "GENERIC_TRAIT_FRAME_EDGE_REQUIREMENTS_BUTTON_TOOLTIP",
            "TOOLTIP_TALENT_PREREQ", "TOOLTIP_TALENT_TIER_POINTS", "TALENT_FRAME_GATE_TOOLTIP_FORMAT" }) do
            local format = self.GetClientLabel and self:GetClientLabel(key, GetLocale())
            if Readable(format, "string") then purchaseFormats[#purchaseFormats + 1] = format end
        end
    end
    local nameLine = lines[1]
    local ownedMountTitle = false
    if mount then
        -- Collection data can place an untyped title after a spacer. Bind it to
        -- this mount's owned source name instead of assuming it is the first row.
        local sourceName = ForeverRosettaStoneDB:GetSpellName(spec.id, GetLocale())
        if Readable(sourceName, "string") then
            for _, line in ipairs(lines) do
                if canaccessallvalues(line.type, line.leftText, line.rightText)
                    and not IsLineType(line, "SpellDescription") and Readable(line.leftText, "string")
                    and Normalize(line.leftText) == Normalize(sourceName) then
                    nameLine, ownedMountTitle = line, true
                    break
                end
            end
        end
    end
    local appearanceLine, appearanceName
    if spec.kind == "item" then
        local ok, line, name = pcall(TranslateEquippedAppearance, spec, lines, locale)
        if ok then appearanceLine, appearanceName = line, name end
    end
    local itemContexts, embeddedTitles = EmbeddedItemContexts(spec, lines)
    local spellContexts, embeddedSpellTitles, inlineTooltips = EmbeddedSpellContexts(spec, lines)
    if spec.kind == "talent" and title and title.GetText then
        local nativeTitle = title:GetText()
        local suffix = Readable(nativeTitle, "string") and nativeTitle:match("\n(.+)$")
        if suffix then titleText = titleText .. "\n" .. suffix end
    end
    if aura and nameLine then
        local isTitle = canaccessallvalues(nameLine.type) and IsLineType(nameLine, "SpellName")
        if not isTitle and self.GetTooltipAuraData then
            local liveAura = self:GetTooltipAuraData(source)
            -- Aura tooltips can expose their title as a generic row rather than SpellName.
            isTitle = liveAura and liveAura.spellId == spec.id and Readable(liveAura.name, "string")
                and Readable(nameLine.leftText, "string")
                and Normalize(nameLine.leftText) == Normalize(liveAura.name)
        end
        if not isTitle then nameLine = nil end
    end
    -- The rendered title replaces the native name row even when a surface leaves it
    -- untyped or uses its own type (toy boxes, collection journals).
    local nativeTitle = title and title.GetText and title:GetText()
    local nameRowIsTitle = ownedMountTitle or nameLine and not aura and canaccessallvalues(nameLine.leftText)
        and Readable(nameLine.leftText, "string") and Readable(nativeTitle, "string")
        and Normalize(nameLine.leftText) == Normalize(nativeTitle)
    local liveDescriptions, liveSkipped = CaptureLiveDescriptionRows(self, spec, lines, nameLine, locale, aura,
        spellContexts, inlineTooltips)
    local requirementIncomplete = {}
    if spec.kind == "quest" then
        for line, text in pairs(self:GetQuestLinkTranslations(spec, locale)) do liveDescriptions[line] = text end
    elseif (spec.kind == "item" or (spec.kind == "spell" or spec.kind == "talent") and not aura)
        and self.GetSpellRequirementTranslations then
        local requirements
        local requirementSpec = spec
        if lines ~= spec.data.lines then
            -- Rank previews use rendered rows. Keep their matched native metadata,
            -- and return translations keyed by those same rows without changing the capture.
            requirementSpec = {}
            for key, value in pairs(spec) do requirementSpec[key] = value end
            requirementSpec.data = {}
            for key, value in pairs(spec.data) do requirementSpec.data[key] = value end
            requirementSpec.data.lines = lines
        end
        requirements, requirementIncomplete = self:GetSpellRequirementTranslations(requirementSpec, locale)
        for line, text in pairs(requirements) do liveDescriptions[line] = text end
        requirementIncomplete = requirementIncomplete or {}
    end
    local subtext
    if nameLine and Readable(nameLine.rightText, "string") and nameLine.rightText ~= "" then
        if aura then
            local liveAura = self.GetTooltipAuraData and self:GetTooltipAuraData(source)
            local dispel = liveAura and liveAura.spellId == spec.id and liveAura.dispelName
            if Readable(dispel, "string") then
                local formats = GetTargetFormats(locale)
                subtext = formats and formats["AURA_DISPEL_" .. dispel]
            end
            subtext = subtext or TranslateSharedTooltipText(self, nameLine.rightText, locale)
        elseif spec.kind == "talent" then
            -- Talent preview ranks are not the backing spell's learned rank.
            subtext = TranslateSharedTooltipText(self, nameLine.rightText, locale)
        elseif english then subtext = self:GetEnglishTooltipSubtext(nameLine, spec.kind, spec.id)
        else
            local ignored
            ignored, subtext = self:GetLocalizedTooltipLine(nameLine, spec.kind, spec.id, locale)
        end
    end
    local incomplete = false
    if not subtext and nameLine and Readable(nameLine.rightText, "string") and nameLine.rightText ~= "" then
        subtext = nameLine.rightText
        incomplete = HasTranslatableText(subtext)
    end
    local red, green, blue = GetColor(nil, title)
    local titleRight = source.GetRightLine and source:GetRightLine(1)
    if subtext then tip:AddDoubleLine(titleText, subtext, red, green, blue, GetColor(nameLine.rightColor, titleRight))
    else tip:AddLine(titleText, red, green, blue) end
    CopyLineFont(tip:GetLeftLine(1), title)
    if subtext and tip.GetRightLine and source.GetRightLine then
        CopyLineFont(tip:GetRightLine(1), source:GetRightLine(1))
    end
    for _, line in ipairs(lines) do
        if canaccessallvalues(line.type, line.leftText, line.rightText)
            and not (spec.kind == "talent" and not liveDescriptions[line] and IsTalentPurchaseRequirement(line, purchaseFormats))
            and not (mount and not liveDescriptions[line] and IsMountRidingRequirement(line))
            and not liveSkipped[line]
            and not (IsLineType(line, "ItemName") and line == nameLine)
            and not (IsLineType(line, "SpellName") and line == nameLine)
            and not ((spec.kind == "quest" or spec.kind == "talent" or aura or nameRowIsTitle) and line == nameLine) then
            local left, right, untranslated
            local lineID = itemContexts[line] or spellContexts[line] or spec.id
            local lineKind = itemContexts[line] and "item" or spellContexts[line] and "spell" or spec.kind
            local priceRange = IsLineType(line, "SellPrice") and Readable(line.price, "number")
                and Readable(line.maxPrice, "number") and line.maxPrice > 0
            if line == appearanceLine and appearanceName then
                left = appearanceName
            elseif embeddedTitles[line] then
                left = ForeverRosettaStoneDB:GetItemName(embeddedTitles[line], locale)
                if left and Readable(line.leftText, "string") then
                    left = (line.leftText:match("^[ \t\r\n]*") or "") .. left .. (line.leftText:match("[ \t\r\n]*$") or "")
                end
                if left then left = (line.leftText:match("^[\r\n]*") or "") .. left end
            elseif embeddedSpellTitles[line] then
                left = ForeverRosettaStoneDB:GetSpellName(embeddedSpellTitles[line], locale)
            elseif priceRange then
                AddSalePriceRange(tip, source, line, locale)
            elseif liveDescriptions[line] then
                left = liveDescriptions[line]
                right = TranslateSharedTooltipText(self, line.rightText, locale)
                if requirementIncomplete[line] then incomplete = true end
            elseif aura then
                left = self:TranslateLiveAuraTime(line.leftText, locale)
                    or TranslateSharedTooltipText(self, line.leftText, locale)
                right = TranslateSharedTooltipText(self, line.rightText, locale)
            elseif spec.kind == "talent" then
                -- The talent surface owns this heading. Other UI keys can share
                -- its source wording while translating differently elsewhere.
                left = Readable(line.leftText, "string")
                    and self:TranslateOwnedTooltipFormat(line.leftText, "TALENT_BUTTON_TOOLTIP_NEXT_RANK", locale)
                    or TranslateSharedTooltipText(self, line.leftText, locale)
                right = TranslateSharedTooltipText(self, line.rightText, locale)
            elseif lineKind == "spell" and IsLineType(line, "SpellDescription") then
                -- A missing or ambiguous whole-description match must not revive the static renderer.
                left = GetLocale() == locale and line.leftText or nil
            elseif english then left, right = self:GetEnglishTooltipLine(spec.data, line, lineKind, lineID, spec.sharedTextCache)
            else left, right, untranslated = self:GetLocalizedTooltipLine(line, lineKind, lineID, locale, spec.data, spec.sharedTextCache) end
            if untranslated then incomplete = true end
            if not priceRange and not left and Readable(line.leftText, "string") then
                left = line.leftText
                if HasTranslatableText(left) then incomplete = true end
            end
            if not priceRange and not right and Readable(line.rightText, "string") and line.rightText ~= "" then
                right = line.rightText
                if HasTranslatableText(right) then incomplete = true end
            end
            if left or right then
                left = PreserveInlineLineColors(line.leftText, left)
                right = PreserveInlineLineColors(line.rightText, right)
                local sellPrice = IsLineType(line, "SellPrice")
                -- Blizzard appends the money row after assigning lineIndex to the preceding text row.
                local originalIndex = Readable(line.lineIndex, "number") and (line.lineIndex + (sellPrice and 1 or 0))
                local original = originalIndex and source:GetLeftLine(originalIndex)
                local r, g, b
                if sellPrice then r, g, b = GetColor(HIGHLIGHT_FONT_COLOR)
                else r, g, b = GetColor(line.leftColor, original) end
                if right then
                    local originalRight = originalIndex and source.GetRightLine and source:GetRightLine(originalIndex)
                    tip:AddDoubleLine(left or "", right, r, g, b, GetColor(line.rightColor, originalRight))
                else
                    tip:AddLine(left, r, g, b, true)
                end
                CopyLineFont(tip:GetLeftLine(tip:NumLines()), original)
                if right and tip.GetRightLine and source.GetRightLine and Readable(line.lineIndex, "number") then
                    CopyLineFont(tip:GetRightLine(tip:NumLines()), source:GetRightLine(line.lineIndex))
                end
            end
        end
    end
    if spec.kind == "item" and Readable(spec.data.repairCost, "number") and InRepairMode() then
        tip:AddLine(self.tooltipFormatsByLocale[locale].REPAIR_COST, GetColor(NORMAL_FONT_COLOR))
        tip:AddLine(Money(spec.data.repairCost), GetColor(HIGHLIGHT_FONT_COLOR))
    end
    if incomplete then tip:AddLine(Addon:GetIncompleteTranslationNotice(), 0.65, 0.65, 0.65, true) end
end
