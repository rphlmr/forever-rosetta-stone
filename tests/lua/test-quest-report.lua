local Addon, context = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local now, locale, behavior = 0, "frFR", "async"
local logIndex, actualID, textReads = 4, 999999999, 0
local requests = {}
GetTime = function() return now end
GetLocale = function() return locale end
GetBuildInfo = function() return "1.60.1", "70862", "date", 16001 end
GetQuestLogQuestText = function(index)
    equal(index, 4, "prose uses the log index")
    textReads = textReads + 1
    return "Description française", "English fallback as returned"
end
C_QuestLog.RequestLoadQuestByID = function(id)
    requests[#requests + 1] = id
    if behavior == "error" then error("request failed") end
    if behavior == "sync" then Addon.questReport.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", id, true) end
end
C_QuestLog.GetTitleForQuestID = function() return "Une quête 中文" end
C_QuestLog.GetQuestObjectives = function()
    return { { text = "Objectif: 0/1", type = "monster", numFulfilled = 0, numRequired = 1, finished = false } }
end
C_QuestLog.GetLogIndexForQuestID = function() return logIndex end
C_QuestLog.GetQuestIDForLogIndex = function() return actualID end
local getInfo, isComplete, isFailed = C_QuestLog.GetInfo, C_QuestLog.IsComplete, C_QuestLog.IsFailed
C_QuestLog.GetInfo = function() return { questID = actualID, level = 10 } end
C_QuestLog.IsComplete = function() return true end
C_QuestLog.IsFailed = function() return false end
C_QuestLog.SetSelectedQuest = function() error("Reports must not change the selected quest") end

context.setCombat(false)
context.setGamepad(true)
SettingsPanel:Hide()
GameMenuFrame:Hide()
WorldMapFrame:Show()
WorldMapFrame.maximized = false
QuestMapFrame.DetailsFrame:Show()
QuestMapFrame.DetailsFrame.questID = 999999999
Addon:SetFeatureEnabled("questPanel", true)
Addon:RefreshSelection()
Addon:ReleaseControllerFocus()
equal(Addon.panel:IsShown(), true, "missing quest opens the Rosetta panel")
equal(Addon.current.questID, 999999999, "missing page retains the native quest ID")
equal(Addon.page.body.sections[1]:GetText(), "Désolés pour cet oubli", "missing page follows the client locale")
equal(Addon.panel.title, "Forever Rosetta Stone", "missing page is not labeled with the translation language")
equal(Addon.panel.ReportButton:IsShown(), true, "missing quest offers the shared Options button")
equal(Addon.page.rewards:IsShown(), true, "missing page uses the same framed reward area")
equal(Addon.page.background:GetHeight(), 440, "missing page uses native parchment sizing")
equal(Addon.page.body.frame:GetHeight(), QuestMapFrame.DetailsFrame.ScrollFrame:GetHeight(),
    "missing page uses the same native quest body height")
equal(#Addon.page.body.lastSections, 5, "missing page uses the standard five quest sections")
equal(Addon.page.beerReward.Name:GetText(), "Bière", "reward name follows the client locale")
equal(Addon.page.beerReward.Count:GetText(), "100", "reward count uses the native reward slot")
equal(Addon.panel.ReportButton:GetParent(), Addon.panel.Header, "Options belongs to the quest header")
equal(Addon.panel.ReportButton.points[1][1], "TOPRIGHT", "Options aligns with the translated quest button")
equal(Addon.panel.ReportButton:GetText(), "Options", "missing quest uses the shared Options label")
Addon.page.receiveText:ClearAllPoints()
Addon.page.receiveText:SetPoint("BOTTOMLEFT", Addon.page.rewards.RewardsFrame, "BOTTOMLEFT", 12, 0)
Addon:RefreshSelection()
equal(Addon.page.receiveText.points[1][1], "TOPLEFT", "missing quest replaces a stale reward text anchor")
equal(Addon.page.receiveText.points[1][5], -58,
    "first reward label includes the native header spacer and section gap")
MapQuestInfoRewardsFrame.Header:SetHeight(3)
Addon:RefreshSelection()
equal(Addon.page.receiveText.points[1][5], -60, "reward label follows native header spacer sizing")
MapQuestInfoRewardsFrame.Header:SetHeight(1)
Addon:RefreshSelection()
equal(Addon.page.beerReward.points[1][2], Addon.page.receiveText,
    "Bière row follows the receive label")
equal(Addon.page.beerReward.points[1][3], "BOTTOMLEFT", "Bière row aligns with the receive label's left edge")
equal(Addon.page.beerReward.points[1][5], -5, "Bière row uses the native reward section spacing")
equal(Addon.reportBookmark, nil, "bug bookmark is removed")
Addon:Send("panel.close")
equal(Addon.toggle:IsVisible(), true, "missing page can be collapsed to the reopen bookmark")
Addon:OpenPanel()
equal(Addon.page.body.sections[1]:GetText(), "Désolés pour cet oubli", "reopening preserves the missing page")
SpokenPlacesPanel:Show()
Addon:RefreshSelection()
equal(Addon.panel.points[1][2], SpokenPlacesPanel, "missing page stands beside Spoken")
Addon:ReleaseControllerFocus()
Addon:SyncControllerFocus(true)
equal(SmartNavigation:GetCurrentButton(), nil,
    "opening the missing quest page does not select Options")
local beforeReportSelection = Addon.page.body.frame:GetVerticalScroll()
SmartNavigation:SelectButton(Addon.panel.ReportButton)
equal(SmartNavigation:GetCurrentButton(), Addon.panel.ReportButton, "controller reaches the report action")
equal(Addon.page.body.frame:GetVerticalScroll(), beforeReportSelection,
    "selecting the header report action preserves the reading position")
context.press("PAD1")
equal(Addon.lifecycle, "ready", "opening report succeeds")
local dialog = Addon.questReport
equal(dialog.state, "waiting", "report waits for requested data")
equal(requests[1], 999999999, "page action requests the native quest ID without translation data")
equal(dialog.copy.enabled, false, "loading report cannot be copied")
equal(context.manager.focusedFrame, dialog.frame, "native controller focuses the report")
equal(SmartNavigation.scrollFrames[dialog.frame], dialog.scroll, "native right stick uses report scroll")
equal(dialog.scroll.maintainPreviousButtonOnScroll, true, "scrolling preserves the controller button")
equal(dialog.edit.focused, nil, "opening does not force keyboard focus")
dialog.tooltip.NumLines = function() return 1 end
_G[dialog.tooltip:GetName() .. "TextLeft1"] = { GetText = function() return "Raw tooltip text" end }
dialog.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 999, true)
equal(dialog.state, "waiting", "unrelated result is ignored")
Addon:ShowQuestReport(731)
equal(#requests, 1, "open report refuses another request")
dialog.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 999999999, true)
equal(dialog.state, "ready", "matching result completes report")
equal(dialog.record.locale, "frFR", "actual locale is recorded without restrictions")
equal(dialog.record.title, "Une quête 中文", "mixed-language title remains unchanged")
equal(dialog.record.summary, "English fallback as returned", "text is not compared or rejected")
equal(dialog.record.description, "Description française", "verified quest prose is included")
equal(dialog.record.objectives[1].text, "Objectif: 0/1", "raw progress is included")
equal(dialog.record.tooltipLines[1].left, "Raw tooltip text", "tooltip lines stay raw")
equal(dialog.record.englishReference, nil, "no English reference in data")
equal(dialog.record.titleMatchesEnglish, nil, "no language comparison in data")
equal(dialog.record.build, "70862", "client build is included")
equal(dialog.record.buildDate, "date", "client build date is included")
equal(dialog.record.questLogInfo.questID, actualID, "report includes verified quest log entry")
equal(dialog.record.isComplete, true, "report includes live completion state")
equal(dialog.record.isFailed, false, "report preserves false failure state")
equal(dialog.record.translationLocale, Addon:GetTargetLocale(), "report includes selected translation language")
equal(dialog.record.catalogVersion, ForeverRosettaStoneDB.catalogVersion, "report includes catalog version")
equal(dialog.copy.enabled, true, "completed report can be copied")
equal(SmartNavigation:GetCurrentButton(), nil, "report completion does not automatically select Copy")
equal(dialog.text:find("```lua", 1, true) ~= nil, true, "issue text includes structured quest data")
local encoded = dialog.text:match("```lua\n(.-)\n```")
local decoded = assert(loadstring("return " .. encoded))()
equal(decoded.title, dialog.record.title, "copy data round-trips UTF-8")
equal(decoded.objectives[1].finished, false, "copy data preserves booleans")
SmartNavigation:SelectButton(dialog.copy)
context.press("PAD1")
equal(dialog.edit.focused, true, "controller Copy report focuses text")
equal(dialog.edit.highlighted, true, "controller Copy report selects all text")
context.press("PAD2")
equal(dialog.state, "closed", "controller B closes report")
equal(dialog.edit.focused, false, "closing releases keyboard focus")
equal(dialog.registered, nil, "closing releases native registration")
equal(Addon.lifecycle, "ready", "closing report preserves addon lifecycle")
equal(context.manager.focusedFrame, Addon.panel, "closing report returns to the missing quest page")
equal(SmartNavigation:GetCurrentButton(), nil,
    "returning from the report does not preselect Options")

SmartNavigation:SelectButton(Addon.panel.ReportButton)
equal(SmartNavigation:GetCurrentButton(), Addon.panel.ReportButton, "report action can be selected again")
QuestMapFrame.DetailsFrame.questID = 943
Addon:RefreshSelection()
equal(Addon.panel.ReportButton:IsShown(), true, "translated quest offers the header report button")
equal(Addon.page.rewards:IsShown(), true, "translated quest restores native rewards")
equal(Addon.page.beerReward:IsShown(), false, "translated quest hides the fictional reward")
equal(Addon.page.background:GetHeight(), 440, "translated quest restores native parchment sizing")
equal(SmartNavigation:GetCurrentButton(), Addon.panel.ReportButton,
    "switching quests keeps the shared Options action selected")
SmartNavigation:SelectButton(Addon.panel.ReportButton)
equal(SmartNavigation:GetCurrentButton(), Addon.panel.ReportButton,
    "controller reaches the translated quest report button")
local gamepadUI = InputUtil.IsGamepadUIEnabled
InputUtil.IsGamepadUIEnabled = function() return false end
Addon:ShowQuestOptions(Addon.panel.ReportButton)
equal(dialog.state, "closed", "mouse Options opens a menu before collecting a report")
local mouseMenu = Addon.panel.ReportButton.contextMenu
equal(mouseMenu.entries[2].label, "Cette quête est buggée", "mouse menu follows the French client locale")
for _, client in ipairs({
    { "enUS", "This quest is bugged" },
    { "deDE", "Diese Quest ist fehlerhaft" },
    { "esMX", "Esta misión tiene un error" },
    { "unknown", "This quest is bugged" },
}) do
    locale = client[1]
    Addon:ShowQuestOptions(Addon.panel.ReportButton)
    equal(Addon.panel.ReportButton.contextMenu.entries[2].label, client[2],
        "quest report label follows the client locale with aliases and fallback")
end
locale = "frFR"
InputUtil.IsGamepadUIEnabled = gamepadUI
mouseMenu.entries[2].onClick()
equal(dialog.state, "waiting", "quest menu action opens the report modal")
equal(requests[#requests], 943, "translated quest report uses the displayed quest ID")
dialog.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 943, true)
context.press("PAD2")
equal(context.manager.focusedFrame, Addon.panel, "closing report returns to the translated panel")
equal(context.press("PAD4"), true, "Rosetta leaves Y to Blizzard instead of installing a footer binding group")
Addon.panel.ReportButton.contextMenu = nil
SmartNavigation:SelectButton(Addon.panel.ReportButton)
context.press("PAD1")
equal(Addon.panel.ReportButton.contextMenu, nil,
    "controller Options never opens an addon context menu, which would taint native focus")
equal(dialog.state, "waiting", "controller Options opens the report directly")
equal(dialog.record.questID, 943, "controller Options reports the displayed quest")
equal(context.press("PAD4"), true, "quest options does not capture Y while modal has focus")
dialog.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 943, true)
context.press("PAD2")
Addon:Send("panel.close")
equal(Addon.toggle:IsVisible(), true, "reopen bookmark remains available")
equal(Addon.toggle.Icon:GetTexture(), [[Interface\AddOns\ForeverRosettaStone\media\icon]],
    "reopen bookmark uses the Rosetta icon")
Addon:OpenPanel()
SpokenPlacesPanel:Hide()
Addon:RefreshSelection()

local function open(id)
    Addon:ShowQuestReport(id or 943)
    equal(dialog.state, "waiting", "new report waits")
end
local function close() dialog.frame:Hide() end
local function result(success) dialog.frame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 943, success) end

actualID = 999
open()
result(false)
equal(dialog.record.requestOutcome, "failed", "failed load remains visible")
equal(dialog.record.summary, nil, "mismatched log entry cannot supply prose")
equal(textReads, 1, "mismatched log entry never reads text")
close()
logIndex = nil
open()
now = 5
dialog.frame:Fire("OnUpdate")
equal(dialog.record.requestOutcome, "timeout", "request times out after five seconds")
result(true)
equal(dialog.record.requestOutcome, "timeout", "late result cannot overwrite completed report")
close()
open()
close()
result(true)
equal(dialog.state, "closed", "late result after close is ignored")
behavior = "error"
Addon:ShowQuestReport(943)
equal(dialog.record.requestOutcome, "request_error", "request errors produce a report")
equal(dialog.record.requestError:find("request failed", 1, true) ~= nil, true, "request error is retained")
close()
behavior = "sync"
context.setGamepad(false)
Addon:SyncControllerFocus()
local getObjectives = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function() error("objective getter failed") end
locale = "deDE"
Addon:ShowQuestReport(943)
equal(dialog.state, "ready", "synchronous load is supported")
equal(dialog.record.locale, "deDE", "another locale is accepted")
equal(dialog.record.apiErrors[1].api, "GetQuestObjectives", "getter error is retained")
C_QuestLog.GetQuestObjectives = getObjectives
close()
context.setGamepad(true)
local count = #requests
for _, id in ipairs({ -1, 0, 1.5, 2147483648, "943" }) do Addon:ShowQuestReport(id) end
equal(#requests, count, "invalid quest IDs are refused")
context.setCombat(true)
Addon:ShowQuestReport(943)
equal(#requests, count, "report cannot open in combat")
context.setCombat(false)
behavior = "async"
open()
context.setCombat(true)
close()
equal(dialog.registered, true, "combat defers native focus cleanup")
context.setCombat(false)
dialog.frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
equal(dialog.registered, nil, "leaving combat releases the hidden report")

context.setGamepad(false)
open()
equal(dialog.registered, nil, "mouse mode does not register a controller window")
close()
context.setGamepad(true)
open()
local oldFrame = dialog.frame
Addon:Restart()
equal(Addon.lifecycle, "ready", "reset succeeds with a pending report")
equal(oldFrame:IsShown(), false, "reset hides the old report")
equal(dialog.registered, nil, "reset releases report controller focus")
equal(Addon.questReport, nil, "reset discards the pending report")
oldFrame:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 943, true)
equal(Addon.questReport, nil, "old callbacks cannot recreate report after reset")

C_QuestLog.GetInfo, C_QuestLog.IsComplete, C_QuestLog.IsFailed = getInfo, isComplete, isFailed
return checks
