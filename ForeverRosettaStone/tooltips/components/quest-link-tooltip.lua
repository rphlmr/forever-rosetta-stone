local _, Addon = ...

local function Normalize(text)
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("[ \t\r\n]+", " "):gsub("[ \t\r\n]*:[ \t\r\n]*", ": "):gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")
end

local function Escape(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function TranslateObjective(text, source, target)
    local pattern, fields, offset = { "^" }, {}, 1
    source = Normalize(source)
    for first, field, last in source:gmatch("(){([%a]+)}()") do
        if field ~= "current" and field ~= "required" and field ~= "standing" then return end
        pattern[#pattern + 1] = Escape(source:sub(offset, first - 1))
        pattern[#pattern + 1] = field == "standing" and "(.+)" or "(%d+)"
        fields[#fields + 1], offset = field, last
    end
    pattern[#pattern + 1] = Escape(source:sub(offset)) .. "$"
    if #fields == 0 then return text == source and target or nil end
    local captures = { text:match(table.concat(pattern)) }
    if #captures ~= #fields then return end
    local values = {}
    for index, field in ipairs(fields) do values[field] = captures[index] end
    -- Standing labels require structured faction data; never copy a native label
    -- into a translated template as if it had been translated.
    if values.standing then return end
    local missing = false
    local result = target:gsub("{([%a]+)}", function(field)
        if not values[field] then missing = true end
        return values[field]
    end)
    return not missing and result or nil, values
end

-- Unit tooltips carry an explicit quest title ID followed by typed objectives.
-- Match only templates owned by that quest; objective positions are never inferred.
function Addon:GetUnitQuestTranslations(lines, locale)
    local result, questID = {}, nil
    local types = Enum.TooltipDataLineType
    for _, line in ipairs(lines or {}) do
        if canaccessallvalues(line.type) then
            if types.QuestTitle ~= nil and line.type == types.QuestTitle then
                questID = canaccessallvalues(line.id) and type(line.id) == "number" and line.id > 0 and line.id or nil
                local target = questID and ForeverRosettaStoneDB:GetQuest(questID, locale)
                local text = target and target.title
                if text and self.FormatQuestText then text = self:FormatQuestText(text, questID, locale) end
                result[line] = {text = text, incomplete = not text, questID = questID}
            elseif types.QuestObjective ~= nil and line.type == types.QuestObjective then
                local source = questID and ForeverRosettaStoneDB:GetQuest(questID, GetLocale())
                local target = questID and ForeverRosettaStoneDB:GetQuest(questID, locale)
                local selected, ambiguous
                if source and target and canaccessallvalues(line.leftText) and type(line.leftText) == "string" then
                    local targets = {}
                    for _, objective in ipairs(target.objectiveLines or {}) do targets[objective.index] = objective end
                    for _, objective in ipairs(source.objectiveLines or {}) do
                        local destination = targets[objective.index]
                        if destination and destination.type == objective.type then
                            local candidate, values = TranslateObjective(Normalize(line.leftText), objective.text, destination.text)
                            if candidate and values then
                                for field, key in pairs({current = "numFulfilled", required = "numRequired"}) do
                                    local value = line[key]
                                    if value ~= nil and (not canaccessallvalues(value) or type(value) ~= "number"
                                        or values[field] and tonumber(values[field]) ~= value) then candidate = nil end
                                end
                            end
                            if candidate then
                                if selected and selected ~= candidate then ambiguous = true end
                                selected = candidate
                            end
                        end
                    end
                end
                result[line] = {text = not ambiguous and selected or nil,
                    incomplete = ambiguous or not selected, questID = questID}
            end
        end
    end
    return result
end

-- Quest links have untyped prose and requirement rows, unlike the quest log.
-- Resolve them only within the supplied quest ID and its owned catalog fields.
function Addon:GetQuestLinkTranslations(spec, locale)
    local translated = {}
    local native = ForeverRosettaStoneDB:GetQuest(spec.id, GetLocale())
    local target = ForeverRosettaStoneDB:GetQuest(spec.id, locale)
    if not native or not target then return translated end
    local requirements, inRequirements = {}, false
    for _, line in ipairs(spec.data.lines or {}) do
        if canaccessallvalues(line.leftText) and type(line.leftText) == "string" then
            local text = Normalize(line.leftText)
            if type(QUEST_TOOLTIP_REQUIREMENTS) == "string" and text == Normalize(QUEST_TOOLTIP_REQUIREMENTS) then
                inRequirements = true
            elseif inRequirements and text:match("^%- ") then
                requirements[#requirements + 1] = line
            else
                for _, field in ipairs({ "summary", "description" }) do
                    local source = self:FormatQuestText(native[field], spec.id, GetLocale())
                    local value = self:FormatQuestText(target[field], spec.id, locale)
                    if source and value and text == Normalize(source) then translated[line] = value end
                end
            end
        end
    end
    local targets = {}
    for _, line in ipairs(target.objectiveLines or {}) do targets[line.index] = line end
    for _, row in ipairs(requirements) do
        local text = Normalize(row.leftText):gsub("^%- ", "")
        local value
        for _, source in ipairs(native.objectiveLines or {}) do
            local destination = targets[source.index]
            if destination and destination.type == source.type then
                local candidate = TranslateObjective(text, source.text, destination.text)
                if source.type == "item" or source.type == "monster" then
                    -- The compiler owns this item-name template; link quantities stay live.
                    local name = source.text:match("^(.-): {current}/{required}$")
                    local targetName = destination.text:match("^(.-): {current}/{required}$")
                    local count = name and text:match("^(%d+ [x×] )" .. Escape(Normalize(name)) .. "$")
                    if count and targetName then candidate = count .. targetName end
                end
                candidate = self:FormatQuestText(candidate, spec.id, locale)
                if candidate then
                    if value and value ~= candidate then value = nil; break end
                    value = candidate
                end
            end
        end
        -- A single event requirement is identified by the quest's event field, even
        -- when the native catalog lacks the client's localized event wording.
        if not value and #requirements == 1 and #(native.objectiveLines or {}) == 0 then
            value = self:FormatQuestText(target.eventObjectiveLabel, spec.id, locale)
        end
        if value then
            local prefix = row.leftText:match("^([ \t\r\n]*%-[ \t\r\n]*)") or "- "
            translated[row] = prefix .. value
        end
    end
    return translated
end

Addon:RegisterNameTooltipComponent({
    kind = "quest",
    defaultContext = "chatLink",
    supportsFullText = true,
    GetName = function(id, locale)
        local quest = ForeverRosettaStoneDB:GetQuest(id, locale)
        return quest and quest.title
    end,
    ResolveData = function(source, data)
        if (source == ItemRefTooltip or source == Addon.debugPreviewSource) and data.type == Enum.TooltipDataType.Quest
            and Addon:IsReadableEntityID(data.id) then return data.id end
    end,
})
