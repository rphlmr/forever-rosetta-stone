local _, pilot = ...
local Addon = ForeverRosettaStone
local status = "Open a Northshire NPC dialogue."
local enabled = true

local nativeText = {
    gossip = function() return C_GossipInfo.GetText() end,
    greeting = function() return GetGreetingText() end,
    progress = function() return GetProgressText() end,
    reward = function() return GetRewardText() end,
}
local stages = { gossip = "gossip", greeting = "gossip", progress = "progress", reward = "complete" }

local function ReadableString(value)
    return (not issecretvalue or not issecretvalue(value))
        and (not canaccessallvalues or canaccessallvalues(value))
        and type(value) == "string"
end

local function Normalize(text)
    local normalized = text:gsub(" ", " "):gsub(" ", " "):gsub("’", "'"):gsub("…", "...")
    return normalized:gsub("[A-Z]", string.lower):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function Render(template, questID, locale, playerName)
    template = template:gsub("\\n", "\n")
    if playerName then template = template:gsub("%$[Nn]%f[^%a]", function() return playerName end) end
    local text = Addon:FormatQuestText(template, questID, locale)
    if text and not text:find("%$[%a%d]") then return text end
end

function pilot.Match(npcID, stage, questID, native)
    local matches = pilot.dialogues[npcID]
    local candidates = matches and matches[stage] and matches[stage][questID or 0]
    if not candidates or not ReadableString(native) then return nil end

    local observed = Normalize(native)
    local name = UnitName("player")
    local firstName = ReadableString(name) and name:match("^(%S+)%s+%S")
    local sex = UnitSex("player")
    local result
    for _, entry in ipairs(candidates) do
        if not entry.playerSex or entry.playerSex == sex then
            local french = Render(entry.frFR, questID, "frFR")
            local useFirstName
            if french and Normalize(french) ~= observed and firstName and entry.frFR:find("%$[Nn]%f[^%a]") then
                french = Render(entry.frFR, questID, "frFR", firstName)
                useFirstName = firstName
            end
            if french and Normalize(french) == observed then
                local english = Render(entry.enUS, questID, "enUS", useFirstName)
                if not english or (result and result ~= english) then return nil end
                result = english
            end
        end
    end
    return result
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

local function OptionTitle(npcID, option)
    if not canaccessallvalues(option) or type(option) ~= "table" then return end
    local name = option.name
    if not ReadableString(name) or name == "" then return end
    local observed, matched = Normalize(name)
    for _, candidate in ipairs((pilot.options or {})[npcID] or {}) do
        local french = Render(candidate.frFR, nil, "frFR")
        if french and Normalize(french) == observed then
            local english = Render(candidate.enUS, nil, "enUS")
            if not english or (matched and english ~= matched) then return name end
            matched = english
        end
    end
    return matched or name
end

local function Sections(english, context, questID, npcID)
    local sections = {}
    local greetingStyle, previousBottom, previousGroup
    local function AddRow(title, row, texture, group)
        local font, art, icon = RowStyle(row, texture)
        local native = row and row:GetText()
        local color = ReadableString(native) and native:match("^|c%x%x%x%x%x%x%x%x")
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
            text = color and (color .. title .. "|r") or title,
            gap = gap, source = font or QuestInfoDescriptionText, icon = art, indent = indent,
            rowHeight = math.max(row and row.GetHeight and row:GetHeight() or 0, art and art.height or 0),
        }
    end
    local function AddTitle(id, gap, row, iconName, group)
        if not Addon:IsReadableEntityID(id) then return end
        local quest = Addon:GetQuest(id)
        local title = quest and Render(quest.title, id, "enUS")
        if title then
            local font = context == "progress" and QuestProgressTitleText or QuestInfoTitleHeader
            if iconName then
                AddRow(title, row, questIconPath .. iconName, group)
                return
            end
            sections[#sections + 1] = { text = title, gap = gap, source = font or QuestInfoDescriptionText }
        end
    end

    if questID then AddTitle(questID, 0) end
    local textStyle = context == "progress" and QuestProgressText or QuestInfoDescriptionText
    local introduction = { text = english, gap = questID and 5 or 0, source = textStyle }
    sections[#sections + 1] = introduction
    if context == "gossip" then
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
        for _, option in ipairs(C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}) do
            local title = OptionTitle(npcID, option)
            if title then
                local row = canaccessallvalues(option.orderIndex) and optionRows[option.orderIndex]
                local icon = option.overrideIconID or option.icon
                AddRow(title, row, canaccessallvalues(icon) and icon or nil, "option")
            end
        end
    elseif context == "greeting" then
        introduction.source = GreetingText or textStyle
        greetingStyle = GreetingText
        previousBottom = greetingStyle and greetingStyle:GetBottom()
        local rows = VisibleGreetingQuestRows()
        local activeCount = GetNumActiveQuests()
        for index = 1, activeCount do
            local id = GetActiveQuestID(index)
            AddTitle(id, 10, rows[id] or _G["QuestTitleButton" .. index], "ActiveQuestIcon", "active")
        end
        for index = 1, GetNumAvailableQuests() do
            local id = select(5, GetAvailableQuestInfo(index))
            AddTitle(id, 10, rows[id] or _G["QuestTitleButton" .. (activeCount + index)], "AvailableQuestIcon", "available")
        end
    end
    return sections
end

local function Report(message)
    status = message
end

local function GetSections(source, questID, context)
    if not enabled then return Report("Pilot disabled.") end
    if GetLocale() ~= "frFR" or Addon:GetTargetLocale() ~= "enUS" then
        return Report("Requires a frFR client and an enUS FRS target.")
    end

    local stage = stages[context]
    if not source or not stage then return Report("No NPC dialogue, progress or reward page open.") end
    if stage == "gossip" then questID = nil
    elseif not Addon:IsReadableEntityID(questID) then return Report("Quest ID unavailable.") end

    local guid = UnitGUID("npc")
    local npcID = ReadableString(guid) and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return Report("NPC ID unavailable.") end

    local label = ("NPC %d, %s%s"):format(npcID, stage, questID and (" quest " .. questID) or "")
    local native = nativeText[context]()
    local english = pilot.Match(npcID, stage, questID, native)
    if not english then return Report(label .. ": no matching French line.") end

    status = label .. ": English line matched."
    return Sections(english, context, questID, npcID), guid .. "\031" .. native
end

Addon.questInteractionContentProvider = function(source, questID, context)
    local ok, sections, key = pcall(GetSections, source, questID, context)
    if ok then return sections, key end
    Report("Pilot could not read this screen.")
end

SLASH_FRSDIALOGUE1 = "/frsdialogue"
SlashCmdList.FRSDIALOGUE = function(command)
    if command == "off" then
        enabled = false
        Report("Pilot disabled.")
        if Addon.lifecycle == "ready" then Addon:UpdateQuestInteraction() end
    elseif command == "on" then
        enabled = true
        if Addon.lifecycle == "ready" then Addon:UpdateQuestInteraction() end
    end
    print("FRS Northshire: " .. status)
end
