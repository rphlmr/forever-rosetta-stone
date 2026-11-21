local Addon, tooltipData, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local previousLocale = Addon:GetTargetLocale()
Addon:SetTargetLocale("frFR")
Addon.errorDialog.frame:Hide()
SlashCmdList.FOREVERROSETTASTONE("")
equal(Addon.errorDialog.frame:IsShown(), false, "console waits for the chat handler")
flushTimers()
local dialog = Addon.errorDialog
equal(dialog.console, true, "bare /frs opens the debug console")
equal(dialog.window.template, "PortraitFrameTemplateNoCloseButton", "console uses the native portrait window shell")
equal(dialog.window.movable, true, "console can be moved")
equal(dialog.dragHandle.dragButtons[1], "LeftButton", "title bar accepts left-button dragging")
dialog.dragHandle:Fire("OnDragStart")
equal(dialog.window.moving, true, "dragging the title bar moves the console")
dialog.dragHandle:Fire("OnDragStop")
equal(dialog.window.moving, false, "releasing the title bar stops moving")
equal(dialog.window:GetPortrait().texture, [[Interface\AddOns\ForeverRosettaStone\media\icon]],
    "native top-left portrait displays the Forever Rosetta Stone logo")
equal(dialog.window.PortraitContainer:GetFrameLevel() > dialog.window:GetFrameLevel(), true,
    "portrait circle stays above the native window background")
equal(dialog.window:GetPortrait().width, 54, "logo fills the native portrait without crossing its rim")
equal(dialog.window:GetPortrait().mask, dialog.window.PortraitContainer.CircleMask,
    "logo uses the native circular clipping mask")
equal(dialog.background.atlas, "Profession-Background-Template2", "console reuses the native profession background")
equal(dialog.listTitle:GetText(), Addon:DebugText("captures") .. " · " .. #Addon.debugPicker.entries .. "/30",
    "capture count lives in the list header")
equal(dialog.frame.strata, "TOOLTIP", "console uses the highest addon UI strata")
equal(dialog.frame.level, 9000, "console leaves headroom below the engine's frame-level ceiling")
equal(dialog.window:GetFrameLevel() > dialog.frame:GetFrameLevel(), true, "window layers above the mouse-catching overlay")
equal(dialog.run:GetFrameLevel() > dialog.window:GetFrameLevel(), true, "native buttons layer above the window")
local reopenedView = dialog.view
equal(dialog[reopenedView == "report" and "capturesTab" or reopenedView == "display" and "displayToggle" or "consoleTab"]:GetChecked(),
    true, "bare /frs reopens the last tab")
dialog.capturesTab:Fire("OnClick")
equal(dialog.view, "report", "report tab opens the report screen")
equal(dialog.capturesTab:GetChecked(), true, "report tab becomes selected")
equal(dialog.sidebar:IsShown(), true, "report screen shows the capture list")
equal(dialog.pick:IsShown(), true, "report screen offers inspection")
equal(dialog.commandBox:IsShown(), false, "report screen hides advanced commands")
equal(dialog.report, Addon:GetDebugWelcome(), "an empty report screen shows the step-by-step guide")
equal(dialog.saveReport.enabled, false, "the guide has nothing to save")
equal(dialog.editBox.highlighted, false, "welcome text is readable without a selection overlay")
dialog.consoleTab:Fire("OnClick")
equal(dialog.view, "console", "console tab opens the command screen")
equal(dialog.commandBox:IsShown(), true, "console shows the command field")
equal(dialog.sidebar:IsShown(), false, "console hides the capture list")
equal(dialog.consoleTab:GetChecked(), true, "console tab becomes selected")
dialog.addonReport:Fire("OnClick")
equal(dialog.view, "console", "addon report stays on the console screen")
equal(dialog.report:find(Addon:DebugText("addon"), 1, true) ~= nil, true, "Addon report button reopens environment details")
equal(dialog.report:find("addonVersion", 1, true) ~= nil, true, "addon report contains diagnostic evidence")
for _, text in ipairs({ "https://github.com/rphlmr/forever-rosetta-stone/issues/new",
    Addon:DebugText("steps"), Addon:DebugText("expected"), Addon:DebugText("actual"), "```text" }) do
    equal(dialog.report:find(text, 1, true) ~= nil, true, "copied report includes reporting guidance: " .. text)
end
SlashCmdList.FOREVERROSETTASTONE("help")
flushTimers()
local help = dialog.report
for _, example in ipairs({ "/frs help", "/frs status", "/frs settings", "/frs language frFR",
    "/frs quest", "/frs reset", "/frs item 25", "/frs spell 133", "/frs pick", "/frs stop",
    "/frs list", "/frs clear", "/frs error", "/frs gossip",
    "/frs debug item 25", "/frs questdata 783 7" }) do
    equal(help:find(example, 1, true) ~= nil, true, "help includes a runnable example: " .. example)
end
equal(help:find(Addon:DebugText("recovery"), 1, true) ~= nil, true, "help groups commands by purpose")
equal(help:find("gallery", 1, true), nil, "normal help hides developer-only commands")
equal(help:find("/frs dump", 1, true), nil, "release help omits API execution")
equal(help:find("/frs bench", 1, true), nil, "release help omits profiling")
local oldGossipFrame, oldGossipInfo, oldUnitName, oldUnitGUID = GossipFrame, C_GossipInfo, UnitName, UnitGUID
GossipFrame = CreateFrame("Frame", nil, UIParent)
local gossipOptions = {
    { gossipOptionID = 12345, name = "Hôtel des ventes", orderIndex = 0, flags = 0,
        selectOptionWhenOnlyOption = false, rewards = {{ id = 456, quantity = 2 }} },
    { gossipOptionID = 12346, name = "Banque de Stormwind", orderIndex = 1 },
}
local optionReads = 0
C_GossipInfo = {
    GetOptions = function() optionReads = optionReads + 1; return gossipOptions end,
    GetText = function() return "Où voulez-vous aller ?" end,
    SelectOption = function() error("capture must never select an option") end,
}
UnitName = function(unit) equal(unit, "npc", "capture reads the interacting NPC"); return "Guet de Hurlevent" end
UnitGUID = function(unit) equal(unit, "npc", "capture reads the interacting NPC GUID"); return "Creature-0-1-2-3-68-0001" end
dialog.frame:Hide()
SlashCmdList.FOREVERROSETTASTONE("gossip")
equal(dialog.frame:IsShown(), false, "gossip capture waits for native chat to finish")
flushTimers()
local gossipReport = dialog.report
for _, evidence in ipairs({ "Gossip menu capture", "optionCount = 2", "gossipOptionID = 12345",
    "gossipOptionID = 12346", "Hôtel des ventes", "Banque de Stormwind", "Où voulez-vous aller ?",
    "Guet de Hurlevent", "Creature-0-1-2-3-68-0001", "selectOptionWhenOnlyOption = false",
    "quantity = 2", "clientLocale", "capturedAt" }) do
    equal(gossipReport:find(evidence, 1, true) ~= nil, true, "gossip report preserves " .. evidence)
end
dialog.selectOutput:Fire("OnClick")
equal(dialog.editBox.focused, true, "gossip report can be copied through Select output")
gossipOptions[1].name = "Changed menu"
GossipFrame:Hide()
equal(dialog.report, gossipReport, "copied gossip snapshot survives menu changes and closure")
Addon:RunDebugCommand("gossip")
equal(optionReads, 1, "closed menu does not capture stale gossip options")
equal(dialog.report:find("Open an NPC dialogue", 1, true) ~= nil, true, "closed menu explains how to capture")
GossipFrame:Show()
gossipOptions = {}
Addon:RunDebugCommand("gossip")
equal(dialog.report:find("optionCount = 0", 1, true) ~= nil, true, "empty open menus are reported explicitly")
C_GossipInfo.GetOptions = function() error("gossip API unavailable") end
Addon:RunDebugCommand("gossip")
equal(dialog.report:find("gossip API unavailable", 1, true) ~= nil, true, "API failures remain copyable evidence")
C_GossipInfo.GetOptions = function() return { { gossipOptionID = 1, name = "Banque" } } end
Addon:RunDebugCommand("capture gossip")
equal(Addon.debugPicker.byID["gossip:68"] ~= nil, true, "Capture dialogue adds the open NPC dialogue to the list")
equal(dialog.view, "report", "Capture dialogue shows the report screen")
equal(dialog.selectedEntry, Addon.debugPicker.byID["gossip:68"], "the captured dialogue is selected")
equal(dialog.report:find("gossipOptionID = 1", 1, true) ~= nil, true, "the dialogue capture keeps its options")
Addon:RunDebugCommand("capture gossip")
equal(#Addon.debugPicker.entries, 1, "capturing the same dialogue twice keeps one entry")
Addon:MoveDebugPicker("clear")
Addon:MoveDebugPicker("start")
Addon.debugPicker.unitEvents:Fire("OnEvent", "GOSSIP_SHOW")
flushTimers()
equal(Addon.debugPicker.byID["gossip:68"] ~= nil, true, "inspection captures dialogues as they open")
C_GossipInfo.GetOptions = function() return { { gossipOptionID = 2, name = "Sous-menu" } } end
Addon.debugPicker.unitEvents:Fire("OnEvent", "GOSSIP_SHOW")
flushTimers()
equal(#Addon.debugPicker.byID["gossip:68"].menus, 2, "a sub-menu is kept beside the root menu")
GossipFrame:Hide()
Addon.debugPicker.unitEvents:Fire("OnEvent", "GOSSIP_SHOW")
flushTimers()
equal(Addon:IsDebugPicking(), true, "a dialogue that closed at once does not end the inspection")
Addon:MoveDebugPicker("stop")
Addon:SelectDebugCapture(Addon.debugPicker.byID["gossip:68"])
equal(dialog.report:find("gossipOptionID = 2", 1, true) ~= nil, true, "the dialogue report lists every menu")
Addon:MoveDebugPicker("clear")
GossipFrame:Show()
Addon:MoveDebugPicker("start")
equal(Addon.debugPicker.byID["gossip:68"] ~= nil, true, "a dialogue already open is captured when inspection starts")
Addon:MoveDebugPicker("stop")
Addon:MoveDebugPicker("clear")
GossipFrame:Hide()
Addon:RunDebugCommand("capture gossip")
equal(#Addon.debugPicker.entries, 0, "a closed dialogue adds nothing")
equal(dialog.report:find("Open an NPC dialogue", 1, true) ~= nil, true, "a closed dialogue explains what to do")
GossipFrame, C_GossipInfo, UnitName, UnitGUID = oldGossipFrame, oldGossipInfo, oldUnitName, oldUnitGUID
dialog.editBox:ClearFocus()
Addon:RunDebugCommand("item 25")
dialog.help:Fire("OnClick")
equal(dialog.report, help, "native Help button uses the same catalog as /frs help")
equal(select(1, dialog.editBox:GetTextColor()), 1, "report text is white rather than inheriting dark edit-box text")
Addon:RunDebugCommand("/frs language deDE")
equal(Addon:GetTargetLocale(), "deDE", "console accepts full slash examples and language commands")
Addon:RunDebugCommand("language frFR")
local oldDev = Addon.devDebug
Addon.devDebug = true
Addon:RunDebugCommand("help")
equal(dialog.report:find("gallery", 1, true), nil, "developer help also removes the obsolete gallery")
Addon:RunDebugCommand("gallery links")
equal(dialog.report:find(Addon:DebugText("invalid"), 1, true) ~= nil, true, "removed gallery is an unknown command")
Addon.devDebug = oldDev
Addon:RunDebugCommand("help")
equal(dialog.commandBox.maxLetters, 0, "console API input has no chat-length limit")
assert(loadfile("ForeverRosettaStone/diagnostics/dev-api-probe.lua"))("ForeverRosettaStone", Addon)
equal(Addon:GetCommandHelp():find("/frs dump", 1, true) ~= nil, true, "local development help exposes API execution")
dialog.commandBox:SetText('dump (function() return nil, false, 430 end)()')
dialog.run:Fire("OnClick")
equal(dialog.report:find("returnCount = 3", 1, true) ~= nil, true, "Run displays every API return in the console")
equal(dialog.report:find("value = false", 1, true) ~= nil, true, "console API report preserves false results")
equal(dialog.report:find("<nil>", 1, true) ~= nil, true, "console API report preserves nil results")
Addon.RunAPIProbe = nil
Addon:RunDebugCommand("help")

tooltipData(GameTooltip, Enum.TooltipDataType.Item, 25)
equal(#Addon.debugPicker.entries, 0, "hovering outside Pick mode records nothing")
dialog.pick:Fire("OnClick")
equal(Addon:IsDebugPicking(), true, "Pick starts capture")
equal(Addon:MoveDebugPicker("start"), false, "repeated start does not clear an active capture")
equal(dialog.frame:IsShown(), not InputUtil.IsGamepadUIEnabled(), "only mouse inspection keeps the console visible")
equal(dialog.frame.alpha, 0.15, "console is translucent while picking")
for _, frame in ipairs({dialog.frame, dialog.window, dialog.scroll, dialog.editBox, dialog.commandBox,
    dialog.run, dialog.pick, dialog.help, dialog.addonReport, dialog.clearCaptures, dialog.saveReport,
    dialog.close, dialog.list, dialog.selectOutput}) do
    equal(frame:IsMouseEnabled(), false, "every console region is click-through")
    equal(frame:IsMouseWheelEnabled(), false, "scroll regions do not block the native UI")
end
equal(dialog.stopPicking:IsShown(), true, "Stop remains available outside the faded console")
equal(dialog.stopPicking:IsMouseEnabled(), true, "Stop is clickable")
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 25, nil, {{type=0, leftText="Native instance amount 42"}})
local afterItem = #Addon.debugPicker.entries
do
    local previousInspect, previousUnitIsUnit, previousCollection = InspectFrame, UnitIsUnit, C_TransmogCollection
    local previousProcessing = GameTooltip.processingInfo
    InspectFrame = { unit = "target", IsShown = function() return true end }
    UnitIsUnit = function(left, right) return left == right end
    local calls = 0
    C_TransmogCollection = { GetInspectItemTransmogInfoList = function()
        calls = calls + 1
        return { [1] = { appearanceID = 456 } }
    end }
    local function inspectCapture(unit)
        GameTooltip.processingInfo = { getterName = "GetInventoryItem", getterArgs = { unit, 1, n = 2 } }
        Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Item, id = 25, lines = {} })
        return Addon.debugPicker.byID["item:25"].tooltipEvidence.replayContext.item.transmog
    end
    local captured = inspectCapture("target")
    equal(captured.slot, 1, "inspect capture keeps the live inventory slot")
    equal(captured.inspectAppearances.values[1][1].appearanceID, 456, "inspect capture keeps the raw appearance cache")
    equal(inspectCapture("player").inspectAppearances, nil, "another unit cannot inherit the inspect cache")
    equal(calls, 1, "capture only reads appearances for the matching inspect unit")
    local priorLocation, priorApplied = ItemLocation, C_Item.GetAppliedItemTransmogInfo
    ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
    C_Item.GetAppliedItemTransmogInfo = function(location)
        equal(location.slot, 1, "capture uses the player's equipped item location")
        return { appearanceID = 789 }
    end
    equal(inspectCapture("player").equippedAppearance.values[1].appearanceID, 789,
        "picker records the equipped item's applied appearance")
    equal(calls, 1, "player capture does not use the inspect cache")
    local priorModel = CharacterModelScene
    C_Item.GetAppliedItemTransmogInfo = function() return { appearanceID = 0, secondaryAppearanceID = 0 } end
    CharacterModelScene = {
        IsVisible = function() return true end,
        GetPlayerActor = function()
            return { GetItemTransmogInfo = function() return { appearanceID = 789 } end }
        end,
    }
    local fallback = inspectCapture("player")
    equal(fallback.equippedAppearance.values[1].appearanceID, 0, "picker preserves the raw zero from the item")
    equal(fallback.characterSheetAppearance.values[1].appearanceID, 789, "picker captures the model fallback")
    equal(fallback.status, "captured", "a readable model appearance supplies the missing identity")
    local priorCurrent = C_Item.GetCurrentItemTransmogInfo
    C_Item.GetCurrentItemTransmogInfo = function(location)
        equal(location.slot, 1, "current equipment capture uses the same item location")
        return { appearanceID = 456 }
    end
    equal(inspectCapture("player").currentAppearance.values[1].appearanceID, 456,
        "picker records the current appearance when applied IDs are zero")
    C_Item.GetCurrentItemTransmogInfo = priorCurrent
    CharacterModelScene = priorModel
    ItemLocation, C_Item.GetAppliedItemTransmogInfo = priorLocation, priorApplied
    GameTooltip.processingInfo = previousProcessing
    InspectFrame, UnitIsUnit, C_TransmogCollection = previousInspect, previousUnitIsUnit, previousCollection
end
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 25)
equal(#Addon.debugPicker.entries, afterItem, "repeated item hovers do not duplicate a capture")
tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 133)
local capturedTip = CreateFrame("GameTooltip", nil, UIParent)
capturedTip:AddLine("Translated spell")
local sourceRight = GameTooltip.GetRightLine
GameTooltip.GetRightLine = function() return nil end
capturedTip.GetRightLine = function() return nil end
Addon:RecordDebugTooltip(GameTooltip, {type = Enum.TooltipDataType.Spell, id = 133, lines = {}})
Addon:RecordDebugRenderedTooltip({kind = "spell", id = 133, tip = capturedTip})
GameTooltip.GetRightLine = sourceRight
equal(Addon.debugPicker.captureError, nil, "tooltip capture completes without diagnostic errors")
local capturedCount = #Addon.debugPicker.entries
equal(capturedCount, afterItem + 1, "a different spell adds a distinct capture")
equal(dialog.pickedButtons[1]:IsMouseEnabled(), false, "new picker rows remain click-through")
equal(dialog.pickedButtons[1]:GetFontString():GetWidth(), 228, "capture labels leave space inside their buttons")
equal(dialog.pickedButtons[1]:GetFontString().wordWrap, false, "long capture names stay on one clipped line")
equal(dialog.pickedButtons[1]:GetText():sub(1, 3), "1. ", "captures are numbered in capture order")
equal(dialog.pickedButtons[capturedCount]:GetText():sub(1, #tostring(capturedCount) + 2), capturedCount .. ". ",
    "the latest capture carries the highest number")
dialog.stopPicking:Fire("OnClick")
equal(dialog.view, "report", "stopping returns to the report screen")
equal(dialog.selectedEntry, Addon.debugPicker.entries[capturedCount], "stopping selects the latest capture")
equal(dialog.pickedButtons[capturedCount].highlightLocked, true, "the selected capture is highlighted")
equal(dialog.guide:IsShown(), true, "the reporting guide is always reachable on the report screen")
dialog.guide:Fire("OnClick")
equal(dialog.report, Addon:GetDebugWelcome(), "the guide button shows the reporting steps")
equal(dialog.report:find("issues/new", 1, true) ~= nil, true, "the guide includes the GitHub link")
equal(dialog.selectedEntry, Addon.debugPicker.entries[capturedCount], "opening the guide keeps the selected capture")
equal(dialog.pickedButtons[capturedCount].highlightLocked, true, "the selected capture stays highlighted")
equal(Addon:IsDebugPicking(), false, "Stop ends capture")
equal(dialog.frame.alpha, 1, "Stop restores opacity")
equal(dialog.frame:IsMouseEnabled(), true, "Stop restores console interaction")
equal(dialog.stopPicking:IsShown(), false, "Stop control is hidden outside capture")
equal(#Addon.debugPicker.entries, capturedCount, "Stop retains the hovered list")
for index, entry in ipairs(Addon.debugPicker.entries) do
    if entry.kind == "item" and entry.id == 25 then dialog.pickedButtons[index]:Fire("OnClick"); break end
end
equal(dialog.report:find(Addon:GetDebugKindLabel("item") .. " 25", 1, true) ~= nil, true, "selecting a hovered item opens its report")
equal(dialog.report:find("capturedTooltip", 1, true) ~= nil, true, "report includes raw tooltip evidence")
equal(dialog.report:find(Addon:DebugText("reportHint"), 1, true) ~= nil, true,
    "picked entity reports explain what to paste on GitHub")
equal(dialog.report:find("targetDetails", 1, true) ~= nil, true, "report includes catalog details")
equal(dialog.report:find("nativeTemplates", 1, true), nil, "catalog diagnostics do not claim native-source templates")
equal(dialog.report:find("hasAITranslation = false", 1, true) ~= nil, true, "false flags are not reported as unavailable")
dialog.selectOutput:Fire("OnClick")
equal(dialog.editBox.focused, true, "Select output gives keyboard focus to the copy field")
equal(dialog.editBox.highlighted, true, "Select output highlights the complete report")
dialog.saveReport:Fire("OnClick")
equal(Addon.preferences.debugReport, dialog.report, "Save report persists the exact selected report for controller users")
Addon:RunDebugCommand("status")
equal(dialog.report:find("debugReport", 1, true), nil, "new reports do not embed the previous saved report")
dialog.commandBox:SetText("spell 133")
dialog.commandBox:Fire("OnEnterPressed")
equal(dialog.report:find(Addon:GetDebugKindLabel("spell") .. " 133", 1, true) ~= nil, true, "command entry can query spells")
Addon:RunDebugCommand("item 999999999")
equal(dialog.report:find(Addon:DebugText("noCapture"), 1, true) ~= nil, true, "uncaptured IDs are identified honestly")
Addon:RunDebugCommand("item 0")
equal(dialog.report:find(Addon:DebugText("invalid"), 1, true) ~= nil, true, "invalid IDs stay in the console")
Addon:RunDebugCommand("print('arbitrary Lua')")
equal(dialog.report:find(Addon:DebugText("invalid"), 1, true) ~= nil, true, "console does not evaluate Lua")

local oldLoad, oldTitle = C_QuestLog.RequestLoadQuestByID, C_QuestLog.GetTitleForQuestID
local oldLogIndex, oldLogID = C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetQuestIDForLogIndex
local oldQuestText, oldTooltipInfo = GetQuestLogQuestText, C_TooltipInfo
local requested = {}
C_QuestLog.RequestLoadQuestByID = function(id) requested[#requested + 1] = id end
C_QuestLog.GetTitleForQuestID = function(id)
    if id == 98914 then return "Theramore Standard Care Package" end
end
C_QuestLog.GetLogIndexForQuestID = function(id) if id == 98914 then return 1 end end
C_QuestLog.GetQuestIDForLogIndex = function() return 98914 end
GetQuestLogQuestText = function() return "Native journal description", "Native journal summary" end
C_TooltipInfo = {
    GetHyperlink = function(link) return { lines = {{ leftText = link }} } end,
}
dialog.commandBox:SetText("questdata 98914 98915 98914")
dialog.run:Fire("OnClick")
local questEvents = Addon.debugQuestDataEvents
equal(table.concat(requested, ","), "98914,98915", "quest titles request each native quest once")
equal(dialog.report:find("Loading 2 quest(s)", 1, true) ~= nil, true, "console waits for both load results")
questEvents:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 98915, false)
questEvents:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 98914, true)
for _, evidence in ipairs({ "build = ", "locale = ", "98914", "98915", "Theramore Standard Care Package",
    "objectives", "Native journal description", "Native journal summary", "quest:98915",
    'status = "load failed"', 'titleStatus = "unavailable"' }) do
    equal(dialog.report:find(evidence, 1, true) ~= nil, true, "quest title report includes " .. evidence)
end
dialog.selectOutput:Fire("OnClick")
equal(dialog.editBox.highlighted, true, "quest titles are copyable from the console")
Addon:RunDebugCommand("questtitle 98915")
flushTimers()
equal(dialog.report:find('status = "timed out"', 1, true) ~= nil, true, "missing load events time out")
Addon:RunDebugCommand("questdata 98914")
Addon:RunDebugCommand("help")
questEvents:Fire("OnEvent", "QUEST_DATA_LOAD_RESULT", 98914, true)
equal(dialog.report, help, "late native results do not replace the current console output")
Addon:RunDebugCommand("questdata 98914 invalid")
equal(#requested, 4, "invalid quest-title commands do not load any quests")
C_QuestLog.RequestLoadQuestByID, C_QuestLog.GetTitleForQuestID = oldLoad, oldTitle
C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetQuestIDForLogIndex = oldLogIndex, oldLogID
GetQuestLogQuestText, C_TooltipInfo = oldQuestText, oldTooltipInfo

Addon:MoveDebugPicker("start")
for id = 1, 31 do
    Addon:RecordDebugTooltip(GameTooltip, {type=Enum.TooltipDataType.Item, id=id, lines={{leftText="Item "..id}}})
end
equal(#Addon.debugPicker.entries, 30, "picker memory is bounded")
equal(Addon.debugPicker.full, true, "capture truncation is explicit")
Addon:ToggleDebugInspection()
equal(Addon:IsDebugPicking(), false, "the inspection shortcut stops capture")
equal(dialog.stopPicking:IsShown(), false, "closing does not leave an invisible picker active")
Addon:RunDebugCommand("pick")
Addon:RecordDebugTooltip(GameTooltip, {type=Enum.TooltipDataType.Spell, id=133,
    lines={{leftText="Spell"}}, restricted={secret=true}})
Addon:MoveDebugPicker("stop")
Addon:RunDebugCommand("spell 133")
equal(dialog.report:find("<restricted>", 1, true) ~= nil, true, "restricted values are marked")
local errors, blockedActions = Addon.errors, Addon.blockedActions
dialog.clearCaptures:Fire("OnClick")
equal(#Addon.debugPicker.entries, 0, "Clear captures removes the hovered list")
equal(dialog.listTitle:GetText(), Addon:DebugText("captures") .. " · 0/30", "cleared list shows zero captures")
equal(dialog.view, "report", "Clear captures stays on the report screen")
equal(dialog.capturesTab:GetChecked(), true, "Clear captures keeps the report tab selected")
equal(dialog.clearCaptures:IsShown(), true, "Clear stays in place for controller focus")
equal(dialog.clearCaptures.enabled, false, "Clear is disabled once the list is empty")
equal(next(Addon.debugPicker.byID), nil, "Clear captures removes tooltip evidence by ID")
equal(dialog.pickedButtons[1]:IsShown(), false, "Clear captures hides old picker rows")
equal(dialog.report, Addon:GetDebugWelcome(), "Clear captures replaces the report with instructions")
equal(dialog.commandBox:GetText(), "", "Clear captures clears the command field")
equal(Addon.preferences.debugReport, nil, "Clear captures also removes the saved report")
equal(Addon:GetTargetLocale(), "frFR", "Clear captures preserves preferences")
equal(Addon.errors, errors, "Clear captures preserves addon errors")
equal(Addon.blockedActions, blockedActions, "Clear captures preserves protected-action evidence")
local runMouseEnabled = dialog.run:IsMouseEnabled()
Addon:RunDebugCommand("pick")
Addon:RecordDebugTooltip(GameTooltip, {type=Enum.TooltipDataType.Item, id=25, lines={{leftText="Item"}}})
Addon:RunDebugCommand("clear")
equal(Addon:IsDebugPicking(), false, "clear command stops an active picker")
equal(dialog.frame.alpha, 1, "clearing an active picker restores opacity")
equal(dialog.run:IsMouseEnabled(), runMouseEnabled, "clearing an active picker restores previous control input")
equal(dialog.stopPicking:IsShown(), false, "clearing an active picker removes Stop toolbar")
equal(#Addon.debugPicker.entries, 0, "clearing an active picker discards captures")
Addon:RunDebugCommand("clear")
equal(dialog.report, Addon:GetDebugWelcome(), "repeated clear remains on welcome view")
dialog.close:Fire("OnClick")
Addon:OpenSettings()
equal(GetUIPanel("center"), SettingsPanel, "settings owns the native center panel before opening diagnostics")
equal(CanOpenPanels(), false, "settings blocks bags and other native panels while open")
Settings.FindButton(Addon.settingsCategory, Addon:DebugText("title")).callback()
equal(GetUIPanel("center"), nil, "opening diagnostics releases the native settings panel slot")
dialog.pick:Fire("OnClick")
equal(Addon:IsDebugPicking(), true, "inspection starts after leaving settings")
equal(CanOpenPanels(), true, "native bags and windows can open while inspecting from settings")
dialog.stopPicking:Fire("OnClick")
dialog.close:Fire("OnClick")
equal(dialog.frame:IsShown(), false, "one close dismisses the console")
equal(CanOpenPanels(), true, "closing the console needs no second Escape to release native panels")
Addon:ShowDebugConsole(Addon:GetDebugWelcome())
equal(SettingsPanel:IsShown(), false, "Settings help opens the console without covering native hovers")
equal(Addon.errorDialog.console, true, "Settings exposes the same debug tool")
equal(dialog.report, Addon:GetDebugWelcome(), "Settings opens instructions rather than a raw report")
local previousGamepad = InputUtil.IsGamepadUIEnabled
InputUtil.IsGamepadUIEnabled = function() return true end
Addon:SyncDebugController()
equal(SmartNavigation:GetActiveFrame(), dialog.window, "gamepad opening focuses the console through the native manager")
equal(SmartNavigation:GetCurrentButton(), nil, "debug opens without selecting an action")
Addon:SyncDebugController()
equal(SmartNavigation:GetCurrentButton(), nil, "debug refresh preserves the unselected state")
equal(dialog.commandBox.smartNavigationIgnored, true, "gamepad does not require entering a command")
equal(dialog.gamepadFooter.frame:IsShown(), true, "Select and Back legend is visible")
equal(dialog.focusIndicator:IsShown(), false, "console hides its focus arrow until explicit navigation")
dialog.window:SmartNavigationOnSelect(dialog.capturesTab)
equal(dialog.focusIndicator.points[1][2], dialog.capturesTab, "focus arrow follows native tab selection")
equal(dialog.view, "report", "settings reopens the report screen")
equal(dialog.pick.navigationOverrides.right, dialog.capturesTab, "Right moves from Inspect to the selected tab")
equal(dialog.capturesTab.navigationOverrides.down, dialog.displayToggle, "Down moves to the tooltip tester tab")
equal(dialog.displayToggle.navigationOverrides.down, dialog.consoleTab, "Down reaches the console tab")
equal(dialog.consoleTab.navigationOverrides.up, dialog.displayToggle, "Up moves back through side tabs")
equal(dialog.capturesTab.navigationOverrides.left, dialog.pick, "Left returns to the page")
local captureCount = #Addon.debugPicker.entries
equal(dialog.pick.navigationOverrides.down, captureCount > 0 and dialog.pickedButtons[1] or dialog.clearCaptures,
    "Down reaches the first numbered capture")
if captureCount > 0 then
    equal(dialog.pickedButtons[captureCount].navigationOverrides.down, dialog.clearCaptures, "Down reaches Clear after the list")
end
equal(dialog.clearCaptures.navigationOverrides.down, dialog.guide, "Down reaches the reporting guide")
equal(dialog.guide.navigationOverrides.right, dialog.saveReport, "Right moves from the guide to Save report")
equal(dialog.saveReport.navigationOverrides.left, dialog.guide, "Left returns to the guide")
equal(dialog.saveReport.navigationOverrides.right, dialog.selectOutput, "Right moves along the report footer")
equal(dialog.selectOutput.navigationOverrides.right, dialog.capturesTab, "Right reaches tabs at the end of the row")
dialog.consoleTab:OnSmartNavClick()
equal(dialog.view, "console", "gamepad Select opens the console tab")
dialog.addonReport:OnSmartNavClick()
equal(dialog.report:find(Addon:DebugText("addon"), 1, true) ~= nil, true, "gamepad Select opens the addon report")
equal(dialog.addonReport.navigationOverrides.right, dialog.errorLog, "Right reaches Error log within the footer row")
equal(dialog.errorLog.navigationOverrides.right, dialog.saveReport, "Right reaches Save report within the footer row")
equal(dialog.saveReport.navigationOverrides.right, dialog.selectOutput, "Right reaches Select output within the footer row")
equal(dialog.selectOutput.navigationOverrides.right, dialog.consoleTab, "Right reaches tabs at the end of the row")
equal(dialog.errorLog.navigationOverrides.left, dialog.addonReport, "Left returns through the footer row")
equal(dialog.run.navigationOverrides.right, dialog.help, "command actions follow their horizontal row")
equal(dialog.help.navigationOverrides.left, dialog.run, "Left reaches Run from Help")
equal(dialog.pick.navigationOverrides.right, dialog.capturesTab, "Inspect retains its report tab target")
dialog.saveReport:OnSmartNavClick()
equal(Addon.preferences.debugReport, dialog.report, "gamepad saves a report without keyboard copying")
dialog.capturesTab:OnSmartNavClick()
equal(dialog.view, "report", "gamepad Select returns to the report tab")
local following = dialog.pick
following:OnSmartNavClick()
equal(Addon:IsDebugPicking(), true, "gamepad Select starts Pick")
equal(SmartNavigation:GetActiveFrame() == dialog.window, false, "Pick releases console focus to native panels")
equal(dialog.controllerRegistered, nil, "inspection does not register a passive popup in the native focus stack")
equal(dialog.frame:IsShown(), false, "gamepad inspection hides the console while navigating")
equal(dialog.stopFooter.frame:IsShown(), true, "inspection immediately displays the Back prompt")
equal(dialog.stopPanel:IsGamePadButtonEnabled(), false, "inspection does not intercept native gamepad bindings")
equal(dialog.stopPanel:GetScript("OnGamePadButtonDown"), nil, "inspection leaves bag and menu input to the game")
local previousIsKeyDown, backDown = IsKeyDown, false
IsKeyDown = function(key) return key == GAMEPAD_FACE_RIGHT and backDown end
GamepadMode.FrameControlsManager.isUIFocused = false
dialog.stopPanel:Fire("OnUpdate", 0.016)
equal(Addon:IsDebugPicking(), true, "ordinary controller input keeps inspection running")
equal(dialog.focusIndicator:IsShown(), false, "Pick hides the console focus arrow")
local previousTooltipInfo = C_TooltipInfo
C_TooltipInfo = { GetUnit = function(unit)
    if unit == "softinteract" then
        return { type = Enum.TooltipDataType.Unit, guid = "Creature-0-0-0-0-853-00000000",
            lines = { { leftText = "Coldridge Mountaineer" } } }
    end
end }
Addon.debugPicker.unitEvents:Fire("OnEvent", "PLAYER_SOFT_INTERACT_CHANGED")
equal(Addon.debugPicker.byID["npc:853"].name, "Coldridge Mountaineer", "controller soft targets are captured without mouse hover")
C_TooltipInfo = previousTooltipInfo
backDown = true
dialog.stopPanel:Fire("OnUpdate", 0.016)
equal(Addon:IsDebugPicking(), true, "a short Back press leaves inspection active")
CloseSpecialWindows()
flushTimers()
equal(Addon:IsDebugPicking(), true, "closing native windows keeps the capture session active")
dialog.stopPanel:Fire("OnUpdate", 0.85)
equal(Addon:IsDebugPicking(), false, "holding Back stops inspection")
equal(dialog.frame:IsShown(), true, "stopping returns to the reports window")
equal(dialog.stopFooter.frame:IsShown(), false, "stopping hides the Back prompt")
equal(next(Addon.debugPicker.unitEvents.events), nil, "stopping unregisters controller unit capture events")
IsKeyDown = previousIsKeyDown
dialog.clearCaptures:OnSmartNavClick()
equal(Addon.preferences.debugReport, nil, "gamepad Clear captures removes the saved report")
dialog.selectOutput:OnSmartNavClick()
dialog.editBox:Fire("OnEditFocusGained")
equal(dialog.editBox.gamepadEnabled, true, "the focused copy field listens to the controller")
dialog.editBox:Fire("OnGamePadButtonDown", "PAD1")
dialog.editBox:Fire("OnEditFocusLost")
equal(dialog.editBox.focused == false and dialog.editBox.gamepadEnabled == false and dialog.frame:IsShown(), true,
    "a controller button leaves the copy field and gives navigation back")
dialog.selectOutput:OnSmartNavClick()
dialog.editBox:Fire("OnEditFocusGained")
dialog.editBox:Fire("OnGamePadButtonDown", "PAD2")
equal(dialog.frame:IsShown(), false, "B closes the console from the copy field like Escape")
Addon:ShowDebugConsole("Debug report after copying")
equal(dialog.window:SmartNavigationCloseHandler(), true, "gamepad Back is handled by the console")
equal(dialog.frame:IsShown(), false, "gamepad Back closes the console")
equal(dialog.controllerRegistered, nil, "closing releases the native controller registration")
local registrationsBeforePick = GamepadMode.FrameControlsManager.registrations
local focusBeforePick = SmartNavigation:GetActiveFrame()
Addon:RunDebugCommand("pick")
equal(GamepadMode.FrameControlsManager.registrations, registrationsBeforePick,
    "direct Pick never focuses the console before inspecting native windows")
equal(SmartNavigation:GetActiveFrame(), focusBeforePick, "direct Pick preserves native navigation")
dialog.stopPicking:Fire("OnClick")
dialog.close:Fire("OnClick")
local nativePanel = CreateFrame("Frame", nil, UIParent)
GamepadMode.FrameControlsManager:FrameShown(nativePanel)
Addon:ShowDebugConsole(Addon:GetDebugWelcome())
dialog.pick:OnSmartNavClick()
equal(nativePanel:IsShown(), true, "Pick keeps the inspected native window open")
equal(SmartNavigation:GetActiveFrame(), nativePanel, "Pick restores navigation to the previous native window")
dialog.stopPicking:Fire("OnClick")
dialog.close:Fire("OnClick")
GamepadMode.FrameControlsManager:FrameHidden(nativePanel)
nativePanel:Hide()
InputUtil.IsGamepadUIEnabled = previousGamepad
Addon:ShowDebugConsole("Debug report before opening the error log", nil, "console")
local previousDebugReport = dialog.report
dialog.errorLog:Fire("OnClick")
equal(dialog.console, nil, "error log replaces the debug view")
dialog.close:Fire("OnClick")
flushTimers()
equal(dialog.frame:IsShown(), true, "closing the error log returns to the debug tool")
equal(dialog.console, true, "return restores console mode")
equal(dialog.report, previousDebugReport, "return preserves the previous debug report")
equal(dialog.view, "console", "return restores the tab the error log was opened from")
dialog.errorLog:Fire("OnClick")
equal(CloseSpecialWindows(), true, "Escape dismisses the error-log view")
flushTimers()
equal(dialog.console, true, "Escape returns to the debug tool")
dialog.errorLog:Fire("OnClick")
InputUtil.IsGamepadUIEnabled = function() return true end
Addon:SyncDebugController()
dialog.window:SmartNavigationCloseHandler()
SmartNavigation:RemovePanelInfo(dialog.window)
equal(dialog.frame:IsShown(), false, "error-log return waits for native hide cleanup")
flushTimers()
equal(dialog.console, true, "controller Back returns to the debug tool")
equal(SmartNavigation:GetActiveFrame(), dialog.window, "return restores native navigation after hide cleanup")
equal(SmartNavigation:GetCurrentButton(), nil, "return restores navigation without preselecting an action")
InputUtil.IsGamepadUIEnabled = previousGamepad
dialog.close:Fire("OnClick")
equal(dialog.frame:IsShown(), false, "closing the returned debug tool does not reopen it")
Addon:ShowErrorDialog()
dialog.close:Fire("OnClick")
equal(dialog.frame:IsShown(), false, "standalone error log closes without opening the debug tool")
Addon:ShowDebugDisplay()
Addon:ShowErrorDialog(true)
dialog.close:Fire("OnClick")
flushTimers()
equal(dialog.display:IsShown(), true, "error log returns to the previous component tab")
dialog.errorLog:Fire("OnClick")
Addon:ShowDebugConsole("Explicit navigation replaces the return destination")
dialog.close:Fire("OnClick")
equal(dialog.frame:IsShown(), false, "explicit navigation clears the old error-log return")

local previousErrorLog = Addon.errorLog
Addon.errorLog, Addon.preferences.errorLog = {}, nil
Addon:LoadErrorLog()
for index = 1, 12 do Addon:RecordError("test", "failure " .. index) end
equal(#Addon.errorLog, 10, "persistent log retains the ten most recent failures")
equal(Addon.errorLog[1]:find("failure 3", 1, true) ~= nil, true, "persistent log drops oldest failures")
Addon.errorLog = {}
Addon:LoadErrorLog()
equal(#Addon.errorLog, 10, "saved failures load into a fresh session log")
Addon:RecordError("oversized", string.rep("x", 13000))
equal(#Addon.errorLog[10] <= 12000 and #Addon.errorLog[10] > 11000, true, "saved stack traces have a bounded size")
Addon:ShowErrorDialog()
equal(dialog.report:find("failure 12", 1, true) ~= nil, true, "error report includes saved history")
equal(dialog.saveReport:IsShown(), true, "error log can be saved without a keyboard")
local originalHide = dialog.frame.Hide
dialog.frame.Hide = function() error("close callback failed") end
dialog.window:SmartNavigationCloseHandler()
dialog.frame.Hide = originalHide
equal(Addon.errorLog[10]:find("close callback failed", 1, true) ~= nil, true,
    "debug Back callback failures are retained for reports")
Addon.preferences.errorLog, Addon.errorLog = { false, 42, "saved failure" }, {}
Addon:LoadErrorLog()
equal(#Addon.errorLog, 1, "saved error history ignores malformed entries")
equal(Addon.errorLog[1], "saved failure", "valid saved errors survive normalization")
local previousErrors, previousBlocked = Addon.errors, Addon.blockedActions
local lifecycle, captures = Addon.lifecycle, Addon.debugPicker.entries
Addon.errors, Addon.blockedActions = { "session failure" }, { "blocked action" }
Addon:ShowDebugConsole("Keep the debug view after clearing errors", nil, "console")
equal(dialog.clearErrorLog:IsShown(), false, "clear errors is confined to the error-log screen")
dialog.errorLog:OnSmartNavClick()
equal(dialog.clearErrorLog:IsShown(), true, "error log exposes a clear-all action")
equal(dialog.saveReport.navigationOverrides.right, dialog.clearErrorLog, "controller navigation reaches Clear error log")
equal(#Addon.errorLog, 1, "opening the log keeps existing history")
dialog.clearErrorLog:OnSmartNavClick()
equal(#Addon.errorLog, 0, "clear removes persistent error history")
equal(#Addon.errors, 0, "clear removes current-session errors")
equal(#Addon.blockedActions, 0, "clear removes current-session protected-action errors")
equal(Addon.preferences.errorLog, Addon.errorLog, "cleared history remains connected to SavedVariables")
equal(Addon.lifecycle, lifecycle, "clearing errors preserves addon state")
equal(Addon.debugPicker.entries, captures, "clearing errors preserves UI captures")
equal(dialog.report:find("saved failure", 1, true), nil, "cleared errors disappear from the report")
Addon.errorLog = {}
Addon:LoadErrorLog()
equal(#Addon.errorLog, 0, "cleared history stays empty in a fresh session")
Addon:RecordError("test", "new failure after clear")
equal(#Addon.errorLog, 1, "new errors continue to be recorded after clearing")
Addon:RecordError("test", "repeated failure")
Addon:RecordError("test", "repeated failure")
equal(#Addon.errorLog, 2, "identical consecutive errors collapse into one entry")
equal(Addon.errorLog[2]:find(" · ×2\n", 1, true) ~= nil, true, "collapsed errors show their repeat count")
local formattedLog = Addon:FormatErrorLog()
equal(formattedLog:find("repeated failure", 1, true) < formattedLog:find("new failure after clear", 1, true), true,
    "error log lists the newest entry first")
dialog.close:Fire("OnClick")
flushTimers()
equal(dialog.report, "Keep the debug view after clearing errors", "clear preserves the return to the debug tool")
Addon.errors, Addon.blockedActions = previousErrors, previousBlocked
Addon.errorLog, Addon.preferences.errorLog = previousErrorLog, previousErrorLog
equal(Settings.FindButton(Addon.settingsCategory, Addon:DebugText("title")).tooltip:find("Ctrl+C / Cmd+C", 1, true) ~= nil, true,
    "Settings explains how to copy a contribution report")
dialog.close:Fire("OnClick")
Addon:SetTargetLocale(previousLocale)
local savedCombat, savedJumpOverride = InCombatLockdown, SmartNavigation_AddJumpNavigationOverride
InCombatLockdown = function() return true end
SmartNavigation_AddJumpNavigationOverride = function() error("protected navigation must wait until combat ends") end
Addon:RefreshDebugPickedList()
equal(dialog.listTitle:GetText(), Addon:DebugText("captures") .. " · " .. #Addon.debugPicker.entries .. "/30", "capture refresh remains available without protected navigation in combat")
InCombatLockdown, SmartNavigation_AddJumpNavigationOverride = savedCombat, savedJumpOverride
return checks
