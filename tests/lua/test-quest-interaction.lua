local Addon, controls = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
if not Addon.GetClientLabel then
    assert(loadfile("ForeverRosettaStone/tooltips/client-labels.lua"))("ForeverRosettaStone", Addon)
end
local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
end

local old = { GossipFrame = GossipFrame, C_GossipInfo = C_GossipInfo, GetQuestID = GetQuestID }
local oldActiveCount, oldAvailableCount = GetNumActiveQuests, GetNumAvailableQuests
local oldActiveID, oldAvailableInfo = GetActiveQuestID, GetAvailableQuestInfo
local getObjectives = C_QuestLog.GetQuestObjectives
local mapShown = WorldMapFrame:IsShown()
WorldMapFrame:Hide()
SettingsPanel:Hide()
GameMenuFrame:Hide()
Addon.preferences.features.questPanel = true
controls.setMouseFoci({})
controls.setGamepad(false)

GossipFrame = CreateFrame("Frame", nil, UIParent)
GossipFrame:SetSize(338, 496)
GossipFrame.left, GossipFrame.top = 20, 800
local available, active = {}, { { questID = 179 } }
C_GossipInfo = {
    GetAvailableQuests = function() return available end,
    GetActiveQuests = function() return active end,
}
QuestFrame = CreateFrame("Frame", nil, UIParent)
QuestFrame:SetSize(338, 496)
QuestFrame.left, QuestFrame.top = 20, 800
QuestFrameDetailPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameProgressPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameRewardPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameGreetingPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameDetailPanel.Bg = QuestFrameDetailPanel:CreateTexture(nil, "BACKGROUND")
QuestFrameDetailPanel.Bg:SetAtlas("QuestBG-Parchment")
QuestFrameDetailPanel.Bg:SetSize(305, 422)
QuestFrameDetailPanel.Bg.left, QuestFrameDetailPanel.Bg.top = 27, 738
QuestFrame:Hide()
GetQuestID = function() return 179 end
local original = {}
for _, name in ipairs({ "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText",
    "GetGreetingText", "GetActiveTitle", "GetAvailableTitle", "QUEST_OBJECTIVES" }) do
    original[name] = _G[name]
end
GetTitleText = function() return "Native quest" end
GetQuestText = function() return "Native offer" end
GetObjectiveText = function() return "Native objectives" end
GetProgressText = function() return "Native progress question" end
GetRewardText = function() return "Native completion speech" end
GetGreetingText = function() return "Native legacy greeting" end
GetActiveTitle = function() return "Native active title" end
GetAvailableTitle = function() return "Native available title" end
QUEST_OBJECTIVES = "Objectives"
C_GossipInfo.GetText = function() return "Hé ! Vous m'avez l'air d'être costaud." end
C_GossipInfo.GetOptions = function() return { { name = "Native gossip option" } } end
local fulfilled = 8
C_QuestLog.GetQuestObjectives = function(id)
    if id == 179 then
        return { { type = "item", text = "Viande de loup coriace: " .. fulfilled .. "/8", numFulfilled = fulfilled, numRequired = 8 } }
    end

    return getObjectives(id)
end

local hidden = { mode = "hidden" }
check(Addon:TransitionQuestInteraction(hidden, { type = "dismiss" }) == hidden, "hidden refuses dismissal")
check(Addon:TransitionQuestInteraction(hidden, { type = "present", questID = 179, context = "gossip" }) == hidden,
    "selection without a native source cannot become visible")
check(Addon:TransitionQuestInteraction(hidden, { type = "present", source = GossipFrame,
    questID = 179, context = "unknown" }) == hidden, "unknown screen cannot become visible")

local manual = Addon:TransitionQuestInteraction(hidden, { type = "present", source = QuestFrame,
    questID = 179, context = "detail", autoOpen = false })
check(manual.mode == "dismissed", "without auto-open a new NPC screen starts on the bookmark")
check(Addon:TransitionQuestInteraction(manual, { type = "present", source = QuestFrame, questID = 179,
    context = "reward", autoOpen = false }).mode == "dismissed", "without auto-open the next NPC screen stays closed")
check(Addon:TransitionQuestInteraction({ mode = "visible", source = QuestFrame, questID = 179, context = "progress" },
    { type = "present", source = QuestFrame, questID = 179, context = "detail", autoOpen = false }).mode == "visible",
    "an opened reader follows the NPC to the next screen")
Addon.preferences.features.questAutoOpen = false
check(Addon:Transition(Addon:CreateQuestState(), "quest.select", 179).mode == "collapsed",
    "without auto-open the journal starts on its bookmark")
check(Addon:Transition({ mode = "collapsed", questID = 179 }, "quest.select", 399).mode == "collapsed",
    "without auto-open another journal quest keeps the bookmark")
check(Addon:Transition({ mode = "open", questID = 179 }, "quest.select", 399).mode == "open",
    "an opened journal reader follows the selected quest")
-- NPC greeting prose and gossip options have no owned translation source, and a translated quest
-- title alone does not justify a companion: greetings show neither the reader nor its bookmark.
Addon:UpdateQuestInteraction()
check(not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown()),
    "gossip greeting never opens the reader")
check(not (Addon.questInteractionBookmark and Addon.questInteractionBookmark:IsShown()),
    "gossip greeting shows no FRS bookmark")
GossipFrame:Hide()
QuestFrame:Show()
QuestFrameDetailPanel:Hide(); QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide()
QuestFrameGreetingPanel:Show()
GetNumActiveQuests = function() return 1 end
GetNumAvailableQuests = function() return 0 end
GetActiveQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
check(not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown())
    and not (Addon.questInteractionBookmark and Addon.questInteractionBookmark:IsShown()),
    "legacy quest greeting never opens the reader or bookmark")
QuestFrameGreetingPanel:Hide()

-- A quest screen with translated text is the companion's vehicle from here on.
QuestFrameDetailPanel:Show()
Addon.preferences.features.questAutoOpen = false
Addon:UpdateQuestInteraction()
check(Addon.questInteractionState.mode == "dismissed" and Addon.questInteractionBookmark:IsShown()
    and not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown()),
    "without auto-open NPC windows only show the bookmark")
Addon.preferences.features.questAutoOpen = true
Addon:SendQuestInteraction({ type = "reset" })
check(Addon:Transition(Addon:CreateQuestState(), "quest.select", 179).mode == "open", "auto-open is the default")
Addon:UpdateQuestInteraction()
local reader = Addon.questInteractionReader
check(reader.frame:IsShown() and Addon.questInteractionState.questID == 179, "translated quest offer shows companion reader")
local point, source, relative = reader.frame:GetPoint(1)
check(source == QuestFrame and point == "TOPLEFT" and relative == "TOPRIGHT", "reader anchors beside the quest window")
check(select(4, reader.frame:GetPoint(1)) == 0, "companion touches original panel")
check(reader.frame.PortraitContainer:IsShown() == false, "companion omits NPC portrait")
check(reader.parchment:IsShown() and reader.parchment:GetAtlas() == "QuestBG-Parchment",
    "companion draws the native parchment atlas")
local _, _, _, parchmentX, parchmentY = reader.parchment:GetPoint(1)
check(parchmentX == 7 and parchmentY == -62 and reader.parchment:GetWidth() == 305
    and reader.parchment:GetHeight() == 422, "companion parchment keeps native offset and size")
local sections = reader.body.lastSections
Addon:UpdateQuestInteraction()
check(reader.body.lastSections == sections, "stable polling does not rebuild text or reset reading")
fulfilled = 7
Addon:UpdateQuestInteraction()
check(reader.body.lastSections == sections, "journal counts cannot change offer content")
Addon:SendQuestInteraction({ type = "dismiss" })
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown() and Addon.questInteractionState.mode == "dismissed", "polling respects dismissal")
check(Addon.questInteractionBookmark:IsShown(), "dismissed companion exposes bookmark on original")
Addon.questInteractionBookmark:Fire("OnClick")
check(reader.frame:IsShown() and not Addon.questInteractionBookmark:IsShown(), "bookmark reopens companion")
controls.setGamepad(true)
Addon:SendQuestInteraction({ type = "dismiss" })
Addon:UpdateQuestInteraction()
local bookmark, bookmarkManager = Addon.questInteractionBookmark, GamepadMode.FrameControlsManager
check(bookmark.registered, "a dismissed reader's bookmark joins controller navigation")
bookmarkManager:FrameHidden(bookmark.host)
bookmarkManager:FrameShown(bookmark.host, false, true)
check(SmartNavigation:GetCurrentButton() == bookmark, "focusing the bookmark frame selects the bookmark")
bookmark:Fire("OnClick")
check(reader.frame:IsShown() and not bookmark:IsShown() and not bookmark.registered
    and bookmarkManager.focusedFrame == reader.frame, "A on the bookmark opens the reader with controller focus")
controls.setGamepad(false)
Addon:UpdateQuestInteraction()
QuestFrame:Hide()
Addon:UpdateQuestInteraction()
check(Addon.questInteractionState.mode == "hidden", "closing NPC clears selection")
QuestFrame:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown(), "new NPC interaction can open again")
GetQuestID = function() return 999999999 end
Addon:SendQuestInteraction({ type = "reset" })
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown() and not Addon.questInteractionBookmark:IsShown(),
    "a quest without translated text shows neither the reader nor its bookmark")
GetQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
controls.setGamepad(true)
Addon:UpdateQuestInteraction()
local component = Addon:GetTooltipComponent("questInteraction")
check(component.SelectPlacementPolicy(QuestFrame).inputMode == "gamepad", "NPC reader selects isolated gamepad configuration")
check(reader.registered == true, "gamepad reader registers with native panel navigation")
GamepadMode.FrameControlsManager:FrameHidden(reader.frame)
GamepadMode.FrameControlsManager:FrameShown(reader.frame, false, true)
check(SmartNavigation.scrollFrames[reader.frame] == reader.body.frame, "native focus enables gamepad scrolling")
reader.frame.SmartNavigationCloseHandler()
check(not reader.frame:IsShown() and not reader.registered, "native Back dismisses and unregisters the reader")
controls.setGamepad(false)
Addon:SendQuestInteraction({ type = "reset" })
QuestFrameDetailPanel:Hide()
QuestFrameGreetingPanel:Hide()
-- Progress and completion prose have no owned source; a title alone does not justify a companion.
for _, screen in ipairs({ { QuestFrameProgressPanel, "progress" }, { QuestFrameRewardPanel, "reward" } }) do
    QuestFrameDetailPanel:Hide(); QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide()
    screen[1]:Show()
    Addon:UpdateQuestInteraction()
    check(not reader.frame:IsShown() and not Addon.questInteractionBookmark:IsShown(),
        screen[2] .. " screen shows neither the reader nor its bookmark")
end
QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide(); QuestFrameDetailPanel:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown() and Addon.questInteractionState.context == "detail", "native offer screen owns the reader")
check(reader.body.lastSections[2].text:find("What do we have here", 1, true), "offer starts with description")
check(reader.body.lastSections[3].text == (Addon:GetClientLabel("QUEST_OBJECTIVES", Addon:GetTargetLocale()) or QUEST_OBJECTIVES), "offer has native objectives header")
check(not table.concat((function()
    local text = {}; for _, section in ipairs(reader.body.lastSections) do text[#text + 1] = section.text end
    return text
end)(), " "):find("7/8", 1, true), "offer excludes accepted quest progress")
local _, anchor = reader.frame:GetPoint(1)
check(anchor == QuestFrame, "quest window owns companion placement")
check(reader.options:IsShown() and reader.frame.CloseButton:IsShown(), "quest screens offer Options beside the mouse X")
reader.options:Fire("OnClick")
local npcMenu = reader.options.contextMenu
check(npcMenu and npcMenu.entries[2].label == Addon:SettingsText("questBugged"), "NPC Options opens the journal menu")
npcMenu.entries[2].onClick()
check(Addon.questReport.state == "waiting" and Addon.questReport.record.questID == 179,
    "NPC Options reports the quest shown by the native screen")
reader.options.contextMenu = nil
reader.options:Fire("OnClick")
check(reader.options.contextMenu == nil, "Options cannot stack a menu over an open report")
Addon.questReport.frame:Hide()
check(Addon.questReport.state == "closed", "closing the report leaves the NPC reader in place")
local npcManager = GamepadMode.FrameControlsManager
controls.setGamepad(true)
Addon:UpdateQuestInteraction()
npcManager:FrameHidden(reader.frame)
npcManager:FrameShown(reader.frame, false, true)
check(SmartNavigation:GetCurrentButton() == nil, "NPC reader opens without selecting Options")
reader:SyncTarget()
check(SmartNavigation:GetCurrentButton() == nil, "NPC refresh does not restore automatic selection")
SmartNavigation:SelectButton(reader.options)
reader:SyncTarget()
check(SmartNavigation:GetCurrentButton() == reader.options, "NPC refresh preserves explicit navigation")
check(not reader.frame.CloseButton:IsShown(), "gamepad hides the X in favour of native Back")
reader.options.contextMenu = nil
reader.options:Fire("OnClick")
check(reader.options.contextMenu == nil and Addon.questReport.state == "waiting",
    "controller Options opens the report directly, without a tainting context menu")
Addon.questReport.frame:Hide()
check(npcManager.focusedFrame == reader.frame, "closing the report returns controller focus to the NPC reader")
controls.setGamepad(false)
Addon:UpdateQuestInteraction()
check(reader.frame.CloseButton:IsShown(), "mouse mode restores the X")
local originalRewards = QuestInfoRewardsFrame
local nativeRewards = CreateFrame("Frame", nil, QuestFrame)
nativeRewards.left, nativeRewards.top = 30, 550
nativeRewards:SetSize(278, 90)
local function RewardText(text, x, y)
    local region = nativeRewards:CreateFontString(nil, "ARTWORK")
    region:SetText(text)
    region.left, region.top = x, y
    region:SetSize(200, 18)
    function region:GetObjectType() return "FontString" end
    function region:GetJustifyV() return "TOP" end
    return region
end
nativeRewards.Header = RewardText("Native rewards", 30, 550)
nativeRewards.ItemReceiveText = RewardText("Native receive", 30, 525)
local xp = RewardText("40", 30, 500)
local previousExperience = EXPERIENCE_COLON
ClientApi.InstallGlobals("frFR", {"EXPERIENCE_COLON"})
local xpLabel = RewardText(EXPERIENCE_COLON, 30, 480)
local previousSpellHeader = REWARD_SPELL
ClientApi.InstallGlobals("frFR", {"REWARD_SPELL"})
local spellHeader = RewardText(REWARD_SPELL, 30, 460)
local spellReward = CreateFrame("Button", nil, nativeRewards)
spellReward.left, spellReward.top, spellReward.rewardSpellID = 30, 440, 688
spellReward:SetSize(150, 40)
spellReward.Name = RewardText("Invocation d'un diablotin", 70, 435)
function spellReward:GetRegions() return self.Name end
function spellReward:GetChildren() return end
function nativeRewards:GetRegions() return self.Header, self.ItemReceiveText, xp, xpLabel, spellHeader end
function nativeRewards:GetChildren() return spellReward end
QuestInfoRewardsFrame = nativeRewards
Addon:UpdateQuestInteraction()
local function FindRewardText(text)
    for _, region in ipairs({reader.body.child:GetChildren()}) do
        if region:IsShown() and region:GetText() == text then return region end
    end
end
local spellName = ForeverRosettaStoneDB:GetSpellName(688, Addon:GetTargetLocale())
check(spellName and FindRewardText(spellName), "NPC spell rewards show the catalog spell name")
check(FindRewardText(Addon:GetClientLabel("REWARD_SPELL", Addon:GetTargetLocale())),
    "spell reward headers translate by their GlobalString key")
local spellButton
for _, child in ipairs({reader.body.child:GetChildren()}) do
    if child.rewardSource == spellReward and child:IsShown() then spellButton = child end
end
check(spellButton ~= nil, "mirrored spell rewards get a hover target")
spellButton.left, spellButton.top = 40, 300 -- mock frames resolve only explicit screen rects
local spellSource, rewardTip = Addon.rewardSpellSource, Addon.rewardTooltips[1]
local previousCoverage = Addon.preferences.tooltipCoverage
Addon.preferences.tooltipCoverage = "name"
spellSource.SetSpellByID = function(tip, id)
    tip.processingInfo = { tooltipData = { type = Enum.TooltipDataType.Spell, id = id, lines = {} } }
    tip:Show()
end
local function RewardTitle()
    return rewardTip:IsShown() and rewardTip.TextLeft1 and rewardTip.TextLeft1:GetText()
end
spellButton:Fire("OnEnter")
check(RewardTitle() == spellName and not GameTooltip:IsOwned(spellButton),
    "hovering a mirrored spell shows only the translated reward tooltip, like the journal")
spellButton:Fire("OnLeave")
check(not rewardTip:IsShown() and not spellSource:IsShown(), "leaving a mirrored spell hides its tooltip")
local previousActive, previousCurrent = SmartNavigation.activeFrame, SmartNavigation.currentButton
controls.setGamepad(true)
SmartNavigation.activeFrame, SmartNavigation.currentButton = reader.frame, spellButton
Addon:UpdateRewardTooltips()
check(RewardTitle() == spellName, "gamepad focus on a mirrored spell shows its translated tooltip")
local _, _, _, anchorX, anchorY = rewardTip:GetPoint(1)
local tipScale = spellButton:GetEffectiveScale() / UIParent:GetEffectiveScale()
check(math.abs(anchorX - (spellButton:GetLeft() + spellButton:GetWidth()) * tipScale) < 0.01
    and math.abs(anchorY - spellButton:GetTop() * tipScale) < 0.01,
    "reward tooltips anchor like native ANCHOR_RIGHT, at the button's top-right corner")
SmartNavigation.currentButton = reader.options
Addon:UpdateRewardTooltips()
check(not rewardTip:IsShown(), "moving gamepad focus away hides the reward tooltip")
SmartNavigation.activeFrame, SmartNavigation.currentButton = previousActive, previousCurrent
controls.setGamepad(false)
Addon.preferences.tooltipCoverage = previousCoverage
check(FindRewardText(Addon:GetQuestLabel("rewards")), "NPC reward mirror translates its native header")
check(FindRewardText("40"), "NPC reward mirror preserves live XP")
check(FindRewardText(Addon:GetClientLabel("EXPERIENCE_COLON", Addon:GetTargetLocale())),
    "native reward labels translate by their GlobalString key")
check(not FindRewardText("Expérience :"), "translated reward labels replace the native wording")
xp:SetText("170")
Addon:UpdateQuestInteraction()
check(not FindRewardText("40") and FindRewardText("170"), "reward values refresh without stale XP")
check(nativeRewards.Header:GetText() == "Native rewards", "reward mirroring never overwrites native text")
QuestInfoRewardsFrame:Hide()
Addon:UpdateQuestInteraction()
check(not FindRewardText("170") and reader.body.spacerHeight == 0, "hidden native rewards clear the mirror")
QuestInfoRewardsFrame = originalRewards
EXPERIENCE_COLON = previousExperience
REWARD_SPELL = previousSpellHeader
-- Our first line starts where the native title starts, independent of native scrolling.
local previousScroll, previousTitle = QuestDetailScrollFrame, QuestInfoTitleHeader
QuestDetailScrollFrame = CreateFrame("Frame", nil, QuestFrame)
QuestDetailScrollFrame.left, QuestDetailScrollFrame.top = 25, 735
local scrollChild = CreateFrame("Frame", nil, QuestDetailScrollFrame)
scrollChild.left, scrollChild.top = 25, 755
function QuestDetailScrollFrame:GetScrollChild() return scrollChild end
QuestInfoTitleHeader = scrollChild:CreateFontString(nil, "ARTWORK")
QuestInfoTitleHeader.left, QuestInfoTitleHeader.top = 30, 745
Addon:UpdateQuestInteraction()
local _, _, _, bodyX, bodyY = reader.body.frame:GetPoint(1)
-- Native title: scroll top -65 from the window, title 10 below the scroll child top; our first
-- line sits 10 below the body top and 5 right of its left edge.
check(bodyX == 10 - 5 and bodyY == -65 - 10 + 10, "reader text starts at the native title position")
local _, barAnchor, _, _, barY = reader.body.frame.ScrollBar:GetPoint(1)
check(barAnchor ~= reader.body.frame and barY == 9,
    "without a native scroll bar ours keeps its parchment position instead of following the raised text")
QuestDetailScrollFrame.ScrollBar = CreateFrame("Frame", nil, QuestDetailScrollFrame)
QuestDetailScrollFrame.ScrollBar.left, QuestDetailScrollFrame.ScrollBar.top = 330, 732
QuestDetailScrollFrame.ScrollBar:SetSize(10, 400)
reader.body.frame.ScrollBar:ClearAllPoints()
Addon:UpdateQuestInteraction()
local _, nativeBarAnchor, _, nativeBarX, nativeBarY = reader.body.frame.ScrollBar:GetPoint(1)
check(nativeBarAnchor == reader.frame and nativeBarX == 310 and nativeBarY == -68,
    "our scroll bar sits exactly where the native one does")
QuestDetailScrollFrame, QuestInfoTitleHeader = previousScroll, previousTitle
GetQuestID = function() return 0 end
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "invalid native quest ID clears reader instead of reusing map selection")
GetQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
QuestFrame.left = UIParent:GetWidth() - 338
Addon:UpdateQuestInteraction()
local rightPoint, rightAnchor, rightRelative = reader.frame:GetPoint(1)
check(rightPoint == "TOPRIGHT" and rightAnchor == QuestFrame and rightRelative == "TOPLEFT",
    "right-side NPC windows place the reader inward without moving native frames")
SettingsPanel:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "settings block NPC reader")
SettingsPanel:Hide()
Addon:UpdateQuestInteraction()
WorldMapFrame:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "map reader and NPC reader cannot overlap")
WorldMapFrame:Hide()
Addon.preferences.features.questPanel = false
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "quest panel preference disables NPC reader without reload")

QuestFrame:Hide()
QuestFrame, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel, QuestFrameGreetingPanel = nil, nil, nil, nil, nil
GossipFrame, C_GossipInfo, GetQuestID = old.GossipFrame, old.C_GossipInfo, old.GetQuestID
GetNumActiveQuests, GetNumAvailableQuests = oldActiveCount, oldAvailableCount
GetActiveQuestID, GetAvailableQuestInfo = oldActiveID, oldAvailableInfo
C_QuestLog.GetQuestObjectives = getObjectives
for name, value in pairs(original) do _G[name] = value end
Addon.preferences.features.questPanel = true
Addon:SendQuestInteraction({ type = "reset" })
WorldMapFrame:SetShown(mapShown)

return checks
