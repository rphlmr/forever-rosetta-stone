local _, Addon = ...

local nativeText = {
    gossip = function() return C_GossipInfo.GetText and C_GossipInfo.GetText() end,
    greeting = function() return GetGreetingText and GetGreetingText() end,
    detail = function() return GetQuestText and GetQuestText() end,
    progress = function() return GetProgressText and GetProgressText() end,
    reward = function() return GetRewardText and GetRewardText() end,
}
local stages = { gossip = "gossip", greeting = "gossip", detail = "accept", progress = "progress", reward = "complete" }

local function ReadableString(value)
    return (not issecretvalue or not issecretvalue(value))
        and (not canaccessallvalues or canaccessallvalues(value))
        and type(value) == "string"
end

local function Normalize(text)
    local normalized = text:gsub(" ", " "):gsub(" ", " "):gsub("’", "'"):gsub("…", "...")
    return normalized:gsub("[A-Z]", string.lower):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function Render(template, questID, locale, playerName, native)
    template = template:gsub("\\n", "\n"):gsub("%$[Bb]", "\n")
    -- Some client selectors include the class or race grammatical qualifier.
    template = template:gsub("(%$[Gg][^:;$\n]+:[^:;$\n]+):[cr];", "%1;")
    -- A plural suffix or the next sentence may immediately follow a player token.
    template = template:gsub("%$([CcRr])s%f[^A-Za-z]", function(token)
        return (token:lower() == "c" and "{class}" or "{race}") .. "s"
    end)
    template = template:gsub("%$[Nn](%u)", native and "{name}%1" or "{name} %1")
    if playerName then
        local function Name() return playerName end
        template = template:gsub("%$[Nn]%f[^A-Za-z]", Name):gsub("{name}", Name)
    end
    local text = Addon:FormatQuestText(template, questID, locale, true)
    if text and not text:find("%$[A-Za-z0-9]") then return text end
end

local function Applies(entry, npcID, questID, stage, sex)
    return entry.stage == stage and (not questID or entry.npcID == npcID)
        and (not entry.playerSex or entry.playerSex == sex)
end

local function AgreedDialogueText(entries, translations, npcID, questID, stage, sex)
    local candidates = {}
    for _, entry in ipairs(entries or {}) do
        if Applies(entry, npcID, questID, stage, sex) then
            candidates[entry.key] = true
        end
    end
    local text
    for _, entry in ipairs(translations) do
        if candidates[entry.key] then
            if text and text ~= entry.text then return end
            text = entry.text
            candidates[entry.key] = nil
        end
    end
    if next(candidates) == nil then return text end
end

local function UsesPlayerName(text)
    return text:find("%$[Nn]") or text:find("{name}", 1, true)
end

function Addon:MatchQuestDialogue(npcID, questID, stage, native)
    -- An NPC can have several options in a single menu. Those need an option ID
    -- or a match against the live label, even when only one is in the catalog.
    local canResolveByContext = questID or stage == "gossip"
    local readable = ReadableString(native)
    if not canResolveByContext and not readable then return end
    local db = ForeverRosettaStoneDB
    local client, target = GetLocale(), self:GetTargetLocale()
    local translations = db:GetQuestDialogue(questID, npcID, target)
    if not translations then return end
    local sex = UnitSex("player")
    local name = UnitName("player")
    local firstName = ReadableString(name) and name:match("^(%S+)%s+%S")

    if canResolveByContext and (sex == 2 or sex == 3) then
        -- English owns every variant, including variants missing in the source or target locale.
        local english = target == "enUS" and translations or db:GetQuestDialogue(questID, npcID, "enUS")
        local text = AgreedDialogueText(english, translations, npcID, questID, stage, sex)
        -- The live text can still identify the first-name form for multi-part names.
        if text and (not firstName or not UsesPlayerName(text)) then
            return Render(text, questID, target)
        end
    end

    if not readable then return end
    local source = client == target and translations or db:GetQuestDialogue(questID, npcID, client)
    if not source then return end
    local observed, matches, foreverMatches = Normalize(native), {}, {}
    for _, entry in ipairs(source) do
        if Applies(entry, npcID, questID, stage, sex) then
            local candidates = entry.scope == "forever" and foreverMatches or matches
            local text = Render(entry.text, questID, client, nil, true)
            if text and Normalize(text) == observed then
                candidates[entry.key] = {}
            elseif firstName and UsesPlayerName(entry.text) then
                text = Render(entry.text, questID, client, firstName, true)
                if text and Normalize(text) == observed then candidates[entry.key] = { firstName = firstName } end
            end
        end
    end
    -- Explicit Forever variants take precedence among exact native matches.
    if next(foreverMatches) then matches = foreverMatches end
    local result
    for _, entry in ipairs(translations) do
        local match = matches[entry.key]
        if match then
            local text = Render(entry.text, questID, target, match.firstName)
            if not text or (result and result ~= text) then return end
            matches[entry.key], result = nil, text
        end
    end
    if next(matches) == nil then return result end
end

local questIconPath = "Interface\\GossipFrame\\"

local function RowStyle(row, fallbackTexture)
    local icon = row and (row.Icon or (row:GetName() and _G[row:GetName() .. "QuestIcon"]))
    local width, height = 16, 16
    local atlas, texture
    if icon then
        width, height = icon:GetSize()
        atlas = icon:GetAtlas()
        if not ReadableString(atlas) or atlas == "" then atlas = nil end
    end
    if not atlas then
        texture = icon and icon:GetTexture()
        if not canaccessallvalues(texture) or (type(texture) ~= "number" and not ReadableString(texture)) then
            texture = fallbackTexture
        end
    end
    local art = (atlas or texture) and { atlas = atlas, texture = texture, width = width, height = height }
    return row and row:GetFontString(), art, icon
end

local function VisibleGossipRows()
    local quests, options, greeting = {}, {}
    local scroll = GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
    if scroll and scroll.ForEachFrame then
        scroll:ForEachFrame(function(row)
            local element = row.GetElementData and row:GetElementData()
            if not canaccessallvalues(element) or type(element) ~= "table" then return end
            if row.GreetingText then greeting = row.GreetingText end
            local info = element.info
            if not canaccessallvalues(info) or type(info) ~= "table" then return end
            if Addon:IsReadableEntityID(info.questID) then
                quests[info.questID] = row
            elseif canaccessallvalues(info.orderIndex) and type(info.orderIndex) == "number" then
                options[info.orderIndex] = row
            end
        end)
    end
    return quests, options, greeting
end

local function VisibleGreetingQuestRows()
    local rows = {}
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if pool then
        for row in pool:EnumerateActive() do
            local index = row:GetID()
            local id
            if row.isActive == 1 then id = GetActiveQuestID(index)
            else id = select(5, GetAvailableQuestInfo(index)) end
            if Addon:IsReadableEntityID(id) then rows[id] = row end
        end
    end
    return rows
end

local function OptionTitle(npcID, option, locale, translateOption)
    if not canaccessallvalues(option) or type(option) ~= "table" then return end
    local translated = Addon:GetGossipOptionTranslation(option, locale)
    if translated then return translated, true end
    local name = option.name
    if not ReadableString(name) or name == "" then return end
    if translateOption then
        translated = translateOption(npcID, option)
        return translated, translated ~= nil and translated ~= name
    end
    translated = Addon:MatchQuestDialogue(npcID, nil, "option", name)
    return translated or name, translated ~= nil
end

function Addon:CreateQuestDialogueSections(translated, context, questID, npcID, translateOption)
    local sections = {}
    local hasTranslatedRow = false
    local locale = Addon:GetTargetLocale()
    local greetingStyle, previousBottom, previousGroup
    local function AddRow(title, row, texture, group)
        local font, art, icon = RowStyle(row, texture)
        local top = row and row.GetTop and row:GetTop()
        local gap = previousGroup and (group == previousGroup and 0 or 15) or 20
        if previousBottom and top and top <= previousBottom then gap = previousBottom - top end
        previousBottom = row and row.GetBottom and row:GetBottom()
        previousGroup = group
        local indent = art and art.width + 4 or 0
        local introLeft = greetingStyle and greetingStyle.GetLeft and greetingStyle:GetLeft()
        if introLeft then
            local textLeft = font and font.GetLeft and font:GetLeft()
            local iconLeft = icon and icon.GetLeft and icon:GetLeft()
            if textLeft then indent = textLeft - introLeft end
            if art and iconLeft then art.x = iconLeft - introLeft end
        end
        sections[#sections + 1] = {
            text = title,
            gap = gap, source = font or QuestInfoDescriptionText, icon = art, indent = indent,
            rowHeight = math.max(row and row.GetHeight and row:GetHeight() or 0, art and art.height or 0),
        }
    end
    local function AddTitle(id, gap, row, iconName, group, header, headerKey)
        if not Addon:IsReadableEntityID(id) then return end
        local quest = Addon:GetQuest(id)
        local title = quest and Render(quest.title, id, locale)
        if title then
            hasTranslatedRow = true
            local font = context == "progress" and QuestProgressTitleText or QuestInfoTitleHeader
            if iconName then
                if headerKey and group ~= previousGroup then
                    local label = Addon:GetClientLabel(headerKey, locale) or _G[headerKey]
                    if ReadableString(label) and label ~= "" then
                        local top = header and header:GetTop()
                        local headerGap = previousBottom and top and math.max(0, previousBottom - top) or 10
                        sections[#sections + 1] = { text = label, gap = headerGap,
                            source = header or QuestInfoObjectivesHeader or QuestInfoDescriptionText }
                        previousBottom = header and header:GetBottom()
                        previousGroup = group
                    end
                end
                AddRow(title, row, questIconPath .. iconName, group)
                return
            end
            sections[#sections + 1] = { text = title, gap = gap, source = font or QuestInfoDescriptionText }
        end
    end

    if questID then AddTitle(questID, 0) end
    local textStyle = context == "progress" and QuestProgressText or QuestInfoDescriptionText
    local introduction = { text = translated or Addon:GetMissingTranslationMessage("gossip"),
        gap = questID and 5 or 0, source = textStyle }
    sections[#sections + 1] = introduction
    if context == "detail" then
        local quest = Addon:GetQuest(questID)
        local summary = quest and quest.summary and Render(quest.summary, questID, locale) or GetObjectiveText()
        if ReadableString(summary) and summary ~= "" then
            local label = Addon:GetClientLabel("QUEST_OBJECTIVES", locale) or QUEST_OBJECTIVES
            sections[#sections + 1] = { text = label, gap = 20, source = QuestInfoObjectivesHeader }
            sections[#sections + 1] = { text = summary, gap = 5, source = QuestInfoObjectivesText }
        end
    elseif context == "gossip" then
        local rows, optionRows, greeting = VisibleGossipRows()
        if greeting then introduction.source = greeting end
        greetingStyle = greeting
        previousBottom = greeting and greeting.GetBottom and greeting:GetBottom()
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            AddTitle(quest.questID, 10, rows[quest.questID], "AvailableQuestIcon", "available")
        end
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            AddTitle(quest.questID, 10, rows[quest.questID],
                quest.isComplete and "ActiveQuestIcon" or "IncompleteQuestIcon", "active")
        end
        -- The frame sorts its own options before adding them to the ScrollBox.
        local options = GossipFrame.gossipOptions
        if not canaccessallvalues(options) or type(options) ~= "table" or #options == 0 then
            options = C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
        end
        local missingOptions
        for _, option in ipairs(options) do
            local title, hasTranslation = OptionTitle(npcID, option, locale, translateOption)
            if title then
                if hasTranslation then hasTranslatedRow = true else missingOptions = true end
                local row = canaccessallvalues(option.orderIndex) and optionRows[option.orderIndex]
                local icon = option.overrideIconID or option.icon
                AddRow(title, row, canaccessallvalues(icon) and icon or nil, "option")
            end
        end
        if translated and missingOptions then
            table.insert(sections, 2, { text = Addon:GetMissingTranslationMessage("gossipOptions"),
                gap = 8, source = introduction.source })
        end
    elseif context == "greeting" then
        introduction.source = GreetingText or textStyle
        greetingStyle = GreetingText
        previousBottom = greetingStyle and greetingStyle:GetBottom()
        local rows = VisibleGreetingQuestRows()
        local activeCount = GetNumActiveQuests()
        for index = 1, activeCount do
            local id = GetActiveQuestID(index)
            AddTitle(id, 10, rows[id] or _G["QuestTitleButton" .. index], "ActiveQuestIcon", "active",
                CurrentQuestsText, "CURRENT_QUESTS")
        end
        for index = 1, GetNumAvailableQuests() do
            local id = select(5, GetAvailableQuestInfo(index))
            AddTitle(id, 10, rows[id] or _G["QuestTitleButton" .. (activeCount + index)], "AvailableQuestIcon", "available",
                AvailableQuestsText, "AVAILABLE_QUESTS")
        end
    end
    return sections, hasTranslatedRow
end


function Addon:GetInteractionNpcID()
    local guid = UnitGUID and UnitGUID("npc")
    if not ReadableString(guid) then return end
    local kind, id = guid:match("^([^-]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    local npcID = (kind == "Creature" or kind == "Vehicle") and tonumber(id)
    return npcID, guid
end

function Addon:GetCatalogDialogueSections(questID, context)
    local stage = stages[context]
    if not stage then return end
    if stage == "gossip" then questID = nil
    elseif not self:IsReadableEntityID(questID) then return end
    local npcID, guid = self:GetInteractionNpcID()
    if not npcID then return end
    local native = nativeText[context]()
    local translated = self:MatchQuestDialogue(npcID, questID, stage, native)
    if translated then
        local observed = ReadableString(native) and native or ""
        return self:CreateQuestDialogueSections(translated, context, questID, npcID), guid .. "\031" .. observed
    end
    if stage == "gossip" and ReadableString(native) then
        local sections, hasTranslatedRow = self:CreateQuestDialogueSections(nil, context, nil, npcID)
        if hasTranslatedRow or ForeverRosettaStoneDB:GetQuestDialogue(nil, npcID, "enUS") then
            return sections, guid .. "\031" .. native, true
        end
    end
end
