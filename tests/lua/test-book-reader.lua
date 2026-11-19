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
local pageNumber, nativeText, nativeTitle = 1, DB:GetBookPage(2097, "frFR"), "Guerre civile dans les Maleterres"
ItemTextGetPage = function() return pageNumber end
ItemTextGetText = function() return nativeText end
ItemTextGetItem = function() return nativeTitle end
ItemTextFrame = CreateFrame("Frame", nil, UIParent)
ItemTextFrame:SetSize(338, 424)
ItemTextFrame.left, ItemTextFrame.top = 20, 800
ItemTextFrame:Show()

check(DB:GetBookFirstPage("object", 175761) == 2097, "world object owners index their book")
check(DB:GetBookFirstPage("item", 5861) == 669, "bag item owners index their book")
check(DB:GetBookFirstPage("item", 175761) == nil, "item and object IDs are separate namespaces")
check(DB:GetBookFirstPage("quest", 175761) == nil, "unknown owner kinds have no book")

local book = Addon:GetOpenBook()
check(book and book.firstPage == 2097 and book.pageID == 2097, "the open object resolves its book and page")
check(book.title == "Civil War in the Plaguelands", "the reader uses the target-language title")
check(book.body == DB:GetBookPage(2097, "enUS"), "the reader uses the target-language page")
check(Addon:GetOpenBook() == book, "an unchanged page reuses its resolution")

pageNumber, nativeText = 2, DB:GetBookPage(2098, "frFR")
check(Addon:GetOpenBook().pageID == 2098, "turning the page follows the native text")
pageNumber, nativeText = 1, DB:GetBookPage(2099, "frFR")
check(Addon:GetOpenBook().pageID == 2099, "the native text, not the page number alone, selects the page")
nativeText = DB:GetBookPage(2097, "frFR"):gsub("\194\160", " ")
check(Addon:GetOpenBook().pageID == 2097, "spacing differences do not hide a matching page")
nativeText = "Une page que le catalogue ne connaît pas."
check(Addon:GetOpenBook() == nil, "unknown native text keeps the page native")
nativeText = DB:GetBookPage(2097, "frFR")
npcGUID = "GameObject-0-1-0-0-1-0000ABCD"
check(Addon:GetOpenBook() == nil, "objects that are not catalog books stay native")
npcGUID = "Creature-0-1-0-0-175761-0000ABCD"
check(Addon:GetOpenBook() == nil, "creature IDs are never read as object IDs")

-- Bag items carry no ID in the reading window: the last used slot must match the native title.
npcGUID = nil
C_Container = { GetContainerItemID = function(bag, slot) if bag == 0 and slot == 3 then return 5861 end end }
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
C_Item = ClientApi.Install(ClientApi.Client("frFR"), { target = {}, strict = false }).C_Item
Addon:RecordBookItem(0, 3)
nativeTitle, nativeText = C_Item.GetItemNameByID(5861), DB:GetBookPage(669, "frFR")
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
check(Addon:TransitionBookReader({ mode = "dismissed", firstPage = 2097 },
    { type = "present", firstPage = 2097, autoOpen = true }).mode == "dismissed", "a closed reader stays closed for that book")
check(Addon:TransitionBookReader({ mode = "dismissed", firstPage = 2097 },
    { type = "present", firstPage = 669, autoOpen = true }).mode == "visible", "another book opens again")

npcGUID, nativeTitle, nativeText, pageNumber = "GameObject-0-1-0-0-175761-0000ABCD", "Guerre civile dans les Maleterres",
    DB:GetBookPage(2097, "frFR"), 1
Addon.preferences.features.bookPanel = true
Addon.preferences.features.bookAutoOpen = true
Addon:SendBookReader({ type = "reset" })
Addon:UpdateBookReader()
local reader = Addon.bookReader
check(reader and reader.frame:IsShown(), "a translated page opens the reader")
local point, source, relative = reader.frame:GetPoint(1)
check(source == ItemTextFrame and point == "TOPLEFT" and relative == "TOPRIGHT", "the reader sits beside the native book")
local sections = reader.body.lastSections
check(sections[1].text == "Civil War in the Plaguelands" and sections[2].text == DB:GetBookPage(2097, "enUS"),
    "the reader shows the translated title and page")
check(#reader.parchments == 0, "a book without native material keeps the quest parchment")
check(not Addon.bookBookmark:IsShown(), "an open reader hides its bookmark")
Addon:UpdateBookReader()
check(reader.body.lastSections == sections, "stable polling does not rebuild the page")
local objectGUID = npcGUID
npcGUID = nil
pageNumber, nativeText = 2, DB:GetBookPage(2098, "frFR")
Addon:UpdateBookReader()
check(reader.frame:IsShown() and reader.body.lastSections[2].text == DB:GetBookPage(2098, "enUS"),
    "turning the page without an interaction GUID keeps the matching translation open")
npcGUID = objectGUID
pageNumber, nativeText = 1, DB:GetBookPage(2097, "frFR")
Addon:UpdateBookReader()
controls.setGamepad(true)
reader:SyncController(true)
check(SmartNavigation:GetActiveFrame() == reader.frame and SmartNavigation:GetCurrentButton() == nil,
    "the book reader takes window focus without selecting an action")
check(SmartNavigation.scrollFrames[reader.frame] == reader.body.frame,
    "the unselected book reader retains stick scrolling")
controls.setGamepad(false)
reader:SyncController()

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
pageNumber, nativeText = 2, DB:GetBookPage(2098, "frFR")
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and Addon.bookBookmark:IsShown(), "turning pages keeps the reader closed")
Addon.bookBookmark:Fire("OnClick")
check(reader.frame:IsShown() and reader.body.lastSections[2].text == DB:GetBookPage(2098, "enUS"),
    "the bookmark reopens the reader on the current page")

nativeText = "Une page que le catalogue ne connaît pas."
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and not Addon.bookBookmark:IsShown(), "unverified pages show neither reader nor bookmark")

nativeText = DB:GetBookPage(2097, "frFR")
Addon.preferences.features.bookAutoOpen = false
Addon:SendBookReader({ type = "reset" })
Addon:UpdateBookReader()
check(not reader.frame:IsShown() and Addon.bookBookmark:IsShown(), "without auto-open books start on the bookmark")
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
for id, value in pairs(features) do Addon.preferences.features[id] = value end
Addon:SendBookReader({ type = "reset" })
Addon.bookItemCandidate, Addon.openBookCache = nil, nil
return checks
