local _, pilot = ...
local Addon = ForeverRosettaStone
local status = "Open an NPC dialogue or quest."
local enabled = true

local nativeText = {
    gossip = function() return C_GossipInfo.GetText() end,
    greeting = function() return GetGreetingText() end,
    detail = function() return GetQuestText() end,
    progress = function() return GetProgressText() end,
    reward = function() return GetRewardText() end,
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
    local kind, npcID
    if ReadableString(guid) then kind, npcID = guid:match("^([^-]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") end
    npcID = (kind == "Creature" or kind == "Vehicle") and tonumber(npcID)
    if not npcID then return Report("NPC ID unavailable.") end

    local label = ("NPC %d, %s%s"):format(npcID, stage, questID and (" quest " .. questID) or "")
    local native = nativeText[context]()
    local english = pilot.Match(npcID, stage, questID, native)
    if not english then return Report(label .. ": no matching French line.") end

    status = label .. ": English line matched."
    return Addon:CreateQuestDialogueSections(english, context, questID, npcID, OptionTitle), guid .. "\031" .. native
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
    print("FRS Quest Dialogue: " .. status)
end
