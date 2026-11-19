local Addon, controls = ...
local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
end

local DB = ForeverRosettaStoneDB
local saved = { UnitGUID = UnitGUID, C_Container = C_Container, C_Item = C_Item, ItemTextFrame = ItemTextFrame,
    ItemTextGetItem = ItemTextGetItem, ItemTextGetPage = ItemTextGetPage, ItemTextGetText = ItemTextGetText }
local features = {}
for _, id in ipairs({ "bookPanel", "bookAutoOpen", "bookTooltip" }) do features[id] = Addon.preferences.features[id] end
WorldMapFrame:Hide()
SettingsPanel:Hide()
GameMenuFrame:Hide()
controls.setMouseFoci({})
controls.setGamepad(false)

-- Civil War in the Plaguelands: world object 175761, four Vanilla-reference pages from 2097.
local npcGUID = "GameObject-0-1-0-0-175761-0000ABCD"
UnitGUID = function(unit) if unit == "npc" then return npcGUID end end
local pageNumber, nativeTitle = 1, "Guerre civile dans les Maleterres"
ItemTextGetPage = function() return pageNumber end
ItemTextGetText = function() error("book translation must not read the native page body") end
ItemTextGetItem = function() return nativeTitle end
ItemTextFrame = CreateFrame("Frame", nil, UIParent)
ItemTextFrame:SetSize(338, 424)
ItemTextFrame.left, ItemTextFrame.top = 20, 800
ItemTextFrame:Show()
local nativeScroll = CreateFrame("ScrollFrame", nil, ItemTextFrame, "ScrollFrameTemplate")
ItemTextFrame.ScrollFrame = nativeScroll
nativeScroll.left, nativeScroll.top = 28, 737
nativeScroll:SetSize(296, 347)
nativeScroll.ScrollBar.left, nativeScroll.ScrollBar.top = 324, 737
nativeScroll.ScrollBar:SetSize(22, 347)
local nativeChild = CreateFrame("Frame", nil, nativeScroll)
nativeChild.top = 750
nativeScroll:SetScrollChild(nativeChild)
function nativeScroll:GetScrollChild() return nativeChild end
local nativePage = CreateFrame("SimpleHTML", nil, nativeChild)
nativePage.left, nativePage.top = 40, 735
nativePage:SetSize(270, 400)
function nativePage:GetFont(element)
    if element == "P" then return "Fonts/BookParagraph.ttf", 13, "" end
    return "Fonts/BookHeading.ttf", 16, ""
end
function nativePage:GetTextColor(element)
    assert(element == "P")
    return 0.2, 0.1, 0.05, 1
end
function nativePage:GetSpacing(element)
    assert(element == "P")
    return 2
end
ItemTextFrame.PageText = nativePage
local pageNumberLabel = ItemTextFrame:CreateFontString()
pageNumberLabel.top = 765
pageNumberLabel:SetHeight(14)
ItemTextFrame.CurrentPage = pageNumberLabel

check(DB:GetBookFirstPage("object", 175761) == 2097, "world object owners index their book")
check(DB:GetBookFirstPage("item", 5861) == 669, "bag item owners index their book")
check(DB:GetBookFirstPage("item", 175761) == nil, "item and object IDs are separate namespaces")
check(DB:GetBookFirstPage("quest", 175761) == nil, "unknown owner kinds have no book")

local book = Addon:GetOpenBook()
check(book and book.firstPage == 2097 and book.pageID == 2097, "the open object resolves its book and page")
check(book.title == "Civil War in the Plaguelands", "the reader uses the target-language title")
check(book.body == DB:GetBookPage(2097, "enUS"), "the reader uses the target-language page")
check(Addon:GetOpenBook() == book, "an unchanged page reuses its resolution")

pageNumber = 2
check(Addon:GetOpenBook().pageID == 2098, "turning the page follows the native page number")
pageNumber = 5
check(Addon:GetOpenBook() == nil, "a page number outside the catalog keeps the page native")
pageNumber = 1
npcGUID = "GameObject-0-1-0-0-1-0000ABCD"
local unknown, unknownReport = Addon:GetOpenBook()
check(unknown == nil and unknownReport.reason == "book_not_identified" and unknownReport.ownerID == 1
    and unknownReport.firstPageID == nil, "unknown books can be reported without guessing a catalog ID")
npcGUID = "Creature-0-1-0-0-175761-0000ABCD"
check(Addon:GetOpenBook() == nil, "creature IDs are never read as object IDs")

-- Bag items carry no ID in the reading window: the last used slot must match the native title.
npcGUID = nil
C_Container = { GetContainerItemID = function(bag, slot) if bag == 0 and slot == 3 then return 5861 end end }
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
C_Item = ClientApi.Install(ClientApi.Client("frFR"), { target = {}, strict = false }).C_Item
Addon:RecordBookItem(0, 3)
nativeTitle = C_Item.GetItemNameByID(5861)
check(Addon:GetOpenBook() and Addon:GetOpenBook().pageID == 669, "a book opened from a bag item resolves its page")
nativeTitle = "Lettre"
check(Addon:GetOpenBook() == nil, "a different native title is not attributed to the last used item")
Addon:RecordBookItem(0, 4)
check(Addon.bookItemCandidate == nil, "empty slots clear the item candidate")

-- HTML pages render as plain paragraphs.
local _, html = Addon:GetBookTranslation(1031, 1031)
check(html and not html:find("<") and html:find("In memory of my dear mentor", 1, true)
    and html:find("\n50 BTFT %- 25 ATFT\n"), "HTML pages keep their paragraphs without markup")

-- Reader lifecycle mirrors the NPC quest reader.
local hidden = { mode = "hidden" }
check(Addon:TransitionBookReader(hidden, { type = "dismiss" }) == hidden, "hidden refuses dismissal")
check(Addon:TransitionBookReader(hidden, { type = "present", firstPage = 2097, autoOpen = false }).mode == "dismissed",
    "without auto-open a new book starts on the bookmark")
check(Addon:TransitionBookReader({ mode = "dismissed", bookKey = 2097 },
    { type = "present", firstPage = 2097, autoOpen = true }).mode == "dismissed", "a closed reader stays closed for that book")
check(Addon:TransitionBookReader({ mode = "dismissed", bookKey = 2097 },
    { type = "present", firstPage = 669, autoOpen = true }).mode == "visible", "another book opens again")

npcGUID, nativeTitle, pageNumber = "GameObject-0-1-0-0-175761-0000ABCD", "Guerre civile dans les Maleterres", 1
Addon.preferences.features.bookPanel = true
Addon.preferences.features.bookAutoOpen = true
Addon:SendBookReader({ type = "reset" })
Addon:UpdateBookReader()
local reader = Addon.bookReader
check(reader and reader.frame:IsShown(), "a translated page opens the reader")
local point, source, relative = reader.frame:GetPoint(1)
check(source == ItemTextFrame and point == "TOPLEFT" and relative == "TOPRIGHT", "the reader sits beside the native book")
local sections = reader.body.lastSections
check(reader.title:GetText() == "Civil War in the Plaguelands" and #sections == 1
    and sections[1].text == DB:GetBookPage(2097, "enUS"), "the translated title sits outside the page body")
local _, titleParent, _, _, titleY = reader.title:GetPoint(1)
check(titleParent == reader.frame and titleY == -42, "the title uses the native pagination band's vertical center")
local _, _, _, viewportX, viewportY = reader.body.frame:GetPoint(1)
check(viewportX == 8 and viewportY == -63 and reader.body.frame:GetHeight() == 347,
    "the translated page aligns with the native viewport")
local _, _, _, barX, barY = reader.body.frame.ScrollBar:GetPoint(1)
local _, _, _, _, barBottom = reader.body.frame.ScrollBar:GetPoint(2)
check(barX == 304 and barY == -63 and barBottom == -410,
    "the book scrollbar follows the native top and bottom")
local _, _, _, textX, textY = reader.body.sections[1]:GetPoint(1)
check(textX == 12 and textY == -15 and reader.body.sections[1]:GetWidth() == 270,
    "native text margins account for the native scroll offset")
local bodyText = reader.body.sections[1]
local font, size = bodyText:GetFont()
check(font == "Fonts/BookParagraph.ttf" and size == 13 and bodyText:GetTextColor() == 0.2
    and bodyText:GetSpacing() == 2, "translated body copies the rendered paragraph style, not the heading style")
check(#reader.parchments == 0, "a book without native material keeps the quest parchment")
check(not Addon.bookBookmark:IsShown(), "an open reader hides its bookmark")
Addon:UpdateBookReader()
check(reader.body.lastSections == sections, "stable polling does not rebuild the page")
local objectGUID = npcGUID
npcGUID = nil
for number, pageID in ipairs({ 2097, 2098, 2099, 2100 }) do
    pageNumber = number
    Addon:UpdateBookReader()
    check(reader.frame:IsShown() and reader.body.lastSections[2].text == DB:GetBookPage(pageID, "enUS"),
        "turning the page without an interaction GUID keeps the matching translation open")
end
npcGUID = objectGUID
pageNumber = 1
Addon:UpdateBookReader()
controls.setGamepad(true)
reader:SyncController(true)
check(SmartNavigation:GetActiveFrame() == reader.frame and SmartNavigation:GetCurrentButton() == nil,
    "the book reader takes window focus without selecting an action")
check(SmartNavigation.scrollFrames[reader.frame] == reader.body.frame,
    "the unselected book reader retains stick scrolling")
check(not reader.footer.prompts[1].icon:IsShown() and reader.footer.prompts[2].icon:IsShown()
    and reader.footer.frame:IsShown(), "the focused reader advertises only Back")
check(reader.frame.SmartNavigationCloseHandler() and not reader.frame:IsShown() and Addon.bookBookmark:IsVisible(),
    "Back closes the translation and immediately shows the bookmark")
local bookmark, manager = Addon.bookBookmark, GamepadMode.FrameControlsManager
manager:FrameHidden(bookmark.host)
manager:FrameShown(bookmark.host, false, true)
check(bookmark.gamepadPrompt.inputKey == GAMEPAD_FACE_BOTTOM and Addon:GetWidgetTooltip():IsOwned(bookmark),
    "the focused book bookmark shows Select and the common reopen tooltip")
bookmark:Fire("OnClick")
check(reader.frame:IsShown() and manager:GetActiveFrame() == reader.frame
    and not Addon:GetWidgetTooltip():IsShown(), "the bookmark reopens the translation with reading focus")
controls.setGamepad(false)
Addon:UpdateBookReader()

-- The native material (parchment, stone, marble) is copied like the quest screens copy theirs.
local material = ItemTextFrame:CreateTexture("ItemTextMaterialTopLeft", "ARTWORK")
material:SetTexture("Interface\\ItemTextFrame\\ItemText-Stone")
material:SetSize(256, 256)
material.left, material.top = 30, 780
Addon:UpdateBookReader()
check(#reader.parchments == 1 and reader.parchments[1]:IsShown()
    and reader.parchments[1]:GetTexture() == material:GetTexture(), "the reader copies the native book material")
material:Hide()
Addon:UpdateBookReader()
check(not reader.parchments[1]:IsShown(), "a hidden native material is no longer copied")

reader.frame.CloseButton:Fire("OnClick")
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and Addon.bookBookmark:IsShown(), "closing the reader leaves the bookmark")
pageNumber = 2
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and Addon.bookBookmark:IsShown(), "turning pages keeps the reader closed")
Addon.bookBookmark:Fire("OnClick")
check(reader.frame:IsShown() and reader.body.lastSections[1].text == DB:GetBookPage(2098, "enUS"),
    "the bookmark reopens the reader on the current page")

pageNumber = 5
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and not Addon.bookBookmark:IsShown(), "unknown page numbers show neither reader nor bookmark")

pageNumber = 2
local getBookPage = DB.GetBookPage
DB.GetBookPage = function(self, pageID, locale)
    if pageID == 2098 and locale == "enUS" then return nil end
    return getBookPage(self, pageID, locale)
end
Addon.openBookCache = nil
Addon:UpdateBookReader()
check(reader.frame:IsShown() and reader.options:IsShown() and reader.missing,
    "a known page without target text shows the missing message and report action")
local nativeText = getBookPage(DB, 2098, "frFR")
local getNativeText = ItemTextGetText
ItemTextGetText = function() return nativeText end
reader.options:Fire("OnClick")
ItemTextGetText = getNativeText
local dialog = Addon.questReport
local report = dialog.record.book
check(dialog.state == "ready" and dialog.copy.enabled and report.nativeText == nativeText
    and report.nativeTitle == nativeTitle, "book reports immediately include the native readable text")
check(report.ownerKind == "object" and report.ownerID == 175761 and report.pageNumber == 2
    and report.firstPageID == 2097 and report.candidatePageID == 2098 and report.matchedPageID == 2098,
    "the book report records the owner and the page selected by the native page number")
dialog.frame:Hide()

Addon.preferences.features.bookAutoOpen = false
Addon:SendBookReader({ type = "reset" })
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and Addon.bookBookmark:IsShown(), "without auto-open missing books start on the bookmark")
Addon.bookBookmark:Fire("OnClick")
check(reader.frame:IsShown() and reader.missing and not Addon.bookBookmark:IsShown(),
    "disabling book auto-open still allows reopening the missing page from the bookmark")
DB.GetBookPage = getBookPage
pageNumber = 1
Addon:UpdateBookReader()
check(reader.frame:IsShown() and not reader.options:IsShown(), "a translated page clears the missing report action")
Addon.preferences.features.bookPanel = false
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and not Addon.bookBookmark:IsShown(), "the book panel can be turned off")
Addon.preferences.features.bookPanel = true
ItemTextFrame:Hide()
Addon:UpdateBookReader()
check(not Addon.bookBookmark:IsShown(), "closing the native book hides the bookmark")

-- Hovering a readable world object names its book.
local component = Addon:GetTooltipComponent("book")
check(component.ResolveData(GameTooltip, { guid = "GameObject-0-1-0-0-175761-0000ABCD" }) == 2097,
    "hovered book objects resolve their book")
check(component.ResolveData(GameTooltip, { guid = "GameObject-0-1-0-0-1-0000ABCD" }) == nil,
    "other objects have no book tooltip")
check(component.ResolveData(GameTooltip, { guid = "Creature-0-1-0-0-175761-0000ABCD" }) == nil,
    "creatures never resolve as book objects")
check(component.ResolveData(GameTooltip, { type = 0 }) == nil, "tooltips without a GUID have no book")

-- Live object tooltips carry only the native name (type Object, one line, no GUID or ID).
local savedGetLocale = GetLocale
GetLocale = function() return "frFR" end
local function ObjectTooltip(text)
    return { type = Enum.TooltipDataType.Object, lines = { { leftText = text, lineIndex = 1, type = 0 } } }
end
check(DB:GetBookFirstPageByObjectName("au-delà de la porte des ténèbres", "frFR") == 633,
    "an unambiguous native object title names its book")
check(DB:GetBookFirstPageByObjectName("au-delà de la porte des ténèbres", "xxXX") == nil,
    "unsupported locales have no title index")
check(component.ResolveData(GameTooltip, ObjectTooltip("Au-delà de la Porte des ténèbres")) == 633,
    "a hovered object resolves its book by native name")
check(component.ResolveData(GameTooltip, ObjectTooltip("|cffffd100Au-delà de la Porte des ténèbres|r")) == 633,
    "markup and colors do not hide the native name")
check(component.ResolveData(GameTooltip, ObjectTooltip("Au lendemain de la Deuxième Guerre")) == 627,
    "capitalization differences between client and catalog names do not hide the book")
check(component.ResolveData(GameTooltip, ObjectTooltip("Coffre inconnu")) == nil,
    "unknown object names stay native")
local itemTooltip = ObjectTooltip("Au-delà de la Porte des ténèbres")
itemTooltip.type = Enum.TooltipDataType.Item
check(component.ResolveData(GameTooltip, itemTooltip) == nil, "only object tooltips resolve by name")
GetLocale = savedGetLocale
check(component.GetName(2097, "enUS") == "Civil War in the Plaguelands", "the book tooltip names the translated title")

for key, value in pairs(saved) do _G[key] = value end
ItemTextGetText = saved.ItemTextGetText
for id, value in pairs(features) do Addon.preferences.features[id] = value end
Addon:SendBookReader({ type = "reset" })
Addon.bookItemCandidate, Addon.openBookCache = nil, nil
return checks
