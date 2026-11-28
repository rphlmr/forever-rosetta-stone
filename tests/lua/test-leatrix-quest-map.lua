local addon, equal, near = ...
local map, details = WorldMapFrame, QuestMapFrame.DetailsFrame
local canvas = map:GetCanvasContainer()
local footer = map.overlayFrames[1]
local border = CreateFrame("Frame", nil, map)
local title = CreateFrame("Frame", nil, map)
local close = CreateFrame("Button", nil, border)
border.CloseButton = close
map.BorderFrame, map.ScrollContainer = border, canvas
map.NavBar:Hide()
title:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", 0, 0)
title:SetPoint("BOTTOMRIGHT", canvas, "TOPRIGHT", 308, 0)
close:SetPoint("RIGHT", title, "RIGHT", -2, 0)
title.left, title.top, title.right = 20, 785, 1020
title:SetHeight(22)
canvas.bottom = 250
footer:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, 0)
footer.bottom = 230
local previousBackground = details.Bg
details.Bg = details:CreateTexture(nil, "BACKGROUND")
details.Bg.left, details.Bg.top = details:GetLeft(), details:GetTop()
details.Bg:SetSize(details:GetSize())

addon:Layout()
local _, anchor, _, x, y = addon.panel:GetPoint(1)
equal(anchor, title, "simple map anchors the reader to the visible title bar")
near(x, 8, "reader border meets the right edge of the simple map")
near(title.top + y + 16, title.top, "reader border aligns with the simple map title")
local rim = details.BorderFrame
local rimBottom = rim:GetBottom()
near(title.top + y - addon.panel:GetHeight() - 3, rimBottom - 6, "reader ends at the quest border and its inset")
local parchment = addon.page.background
near(details:GetTop() + select(5, parchment:GetPoint(1)) - parchment:GetHeight(), rimBottom,
    "parchment ends above the native action row")
near(title.top + y + select(5, addon.panel.Content:GetPoint(1)), details:GetTop(), "quest text stays aligned")
local scrollHeight = details.ScrollFrame:GetHeight()
details.ScrollFrame:SetHeight(800)
MapQuestInfoRewardsFrame:Hide()
addon:Layout()
local translatedScroll = addon.page.body.frame
near(select(5, translatedScroll:GetPoint(1)) - translatedScroll:GetHeight(), addon.page.bottomLimit,
    "a quest without visible rewards still scrolls inside the reader")
equal(details.ScrollFrame:GetHeight(), 800, "the native scroll frame stays under the map addon's control")
MapQuestInfoRewardsFrame:Show()
details.ScrollFrame:SetHeight(scrollHeight)
footer:Hide()
addon:Layout()
near(title.top + y - addon.panel:GetHeight() - 3, rimBottom - 6, "hiding coordinates adds no empty row")
local rimHeight = rim:GetHeight()
rim:SetHeight(rimHeight + 100)
addon:Layout()
near(title.top + y - addon.panel:GetHeight() - 3, canvas.bottom, "without coordinates the reader ends at the map")
footer:Show()
addon:Layout()
near(title.top + y - addon.panel:GetHeight() - 3, footer.bottom, "an overflowing quest still fits the map")
rim:SetHeight(rimHeight)

title.right = UIParent:GetWidth() / title:GetEffectiveScale()
addon:Layout()
local point, relative, corner = addon.panel:GetPoint(1)
equal(point, "TOPRIGHT", "right screen edge puts the reader to the left of quest details")
equal(relative, details, "reader clears the native action row")
equal(corner, "TOPLEFT", "reader stays over the map canvas when right space is limited")
title.right = 1020

local share, abandon = CreateFrame("Button", nil, details), CreateFrame("Button", nil, details)
details.ShareButton, details.AbandonButton = share, abandon
share:SetText("Share")
abandon:SetText("Abandon")
abandon:SetHeight(22)
local gamepad = InputUtil.IsGamepadUIEnabled
InputUtil.IsGamepadUIEnabled = function() return false end
local shared, abandoned
QuestMapQuestOptions_ShareQuest = function(id) shared = id end
QuestMapQuestOptions_AbandonQuest = function(id) abandoned = id end
local function OpenOptions()
    addon:ShowQuestOptions(addon.panel.ReportButton)
    return addon.panel.ReportButton.contextMenu.entries
end
abandon.bottom = canvas.bottom + 2
equal(#OpenOptions(), 2, "visible native actions need no fallback")
abandon.bottom = canvas.bottom - 100
share:SetEnabled(false)
local entries = OpenOptions()
equal(entries[3].enabled, false, "ineligible share stays disabled")
entries[3].onClick()
equal(shared, nil, "disabled share cannot run")
share:SetEnabled(true)
entries = OpenOptions()
entries[3].onClick()
equal(shared, details.questID, "share uses the native action on the displayed quest")
entries[4].onClick()
equal(abandoned, details.questID, "abandon uses the native confirmation flow")
local id = details.questID
details.questID = id + 1
shared = nil
entries[3].onClick()
equal(shared, nil, "an open menu cannot act on a different quest")
details.questID = id

QuestMapQuestOptions_ShareQuest, QuestMapQuestOptions_AbandonQuest = nil, nil
InputUtil.IsGamepadUIEnabled = gamepad
details.ShareButton, details.AbandonButton = nil, nil
details.Bg = previousBackground
map.BorderFrame, map.ScrollContainer = nil, nil
canvas.bottom = 0
footer:ClearAllPoints()
footer.bottom = nil
map.NavBar:Show()
addon:Layout()
