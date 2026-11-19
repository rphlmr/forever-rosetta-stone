local _, Addon = ...

-- Books are identified by their owner (a bag item or a world object) and the displayed page is
-- verified against the client's own text before a translation is shown. Page order in the catalog
-- is a Vanilla reference, so the native text, not the page number alone, selects the page.

local profiles = Addon:CreateTooltipPlacementProfiles({
    name = "bookReader",
    contexts = { reading = {} },
    mouse = { sideRules = { Addon.TooltipSideRules.screen } },
    gamepad = { sideRules = { Addon.TooltipSideRules.screen } },
})

local function Readable(value, kind)
    return (not canaccessallvalues or canaccessallvalues(value)) and type(value) == kind
end

-- GameObject GUIDs share the creature layout: Type-0-server-instance-zone-entry-spawn.
function Addon:GetGameObjectID(guid)
    if not Readable(guid, "string") then return end
    local id = guid:match("^GameObject%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    return id and tonumber(id)
end

-- Comparable form of a page: placeholders resolved for the player, markup and spacing removed.
local function Comparable(text)
    if not Readable(text, "string") then return end
    text = Addon:FormatQuestText(text, nil, GetLocale()) or text
    text = text:gsub("<[^<>]*>", " "):gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return text ~= "" and text or nil
end

-- Readable text for a FontString: HTML pages keep their paragraph breaks, other tags are dropped.
local function PlainText(text)
    local html = text:find("^%s*<[Hh][Tt][Mm][Ll]>")
    if html then
        text = text:gsub("[\r\n]+", " ")
            :gsub("<[Bb][Rr]%s*/?>", "\n")
            :gsub("</?[Pp][^<>]*>", "\n")
            :gsub("</?[Hh]%d[^<>]*>", "\n")
            :gsub("<[^<>]*>", "")
            :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&nbsp;", " "):gsub("&amp;", "&")
            :gsub("[ \t]*\n[ \t]*", "\n"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    end
    return text
end

-- Remember the bag item the player last used; a book opened from it must carry its client name.
function Addon:RecordBookItem(bag, slot)
    local getID = C_Container and C_Container.GetContainerItemID
    local itemID = getID and getID(bag, slot)
    self.bookItemCandidate = Readable(itemID, "number") and itemID or nil
end

local function GetClientItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(itemID) end
    return GetItemInfo and GetItemInfo(itemID)
end

-- Match the build's object-name index using ASCII whitespace and ASCII case folding.
local function FindBookByObjectName(text, locale)
    if not Readable(text, "string") then return end
    local name = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|T.-|t", ""):gsub("|n", "\n")
        :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("[ \t\n\r\v\f]+", " "):gsub("^ +", ""):gsub(" +$", "")
        :gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
    return ForeverRosettaStoneDB:GetBookFirstPageByObjectName(name, locale)
end

-- Returns the first page ID of the open book, or nil when its owner is not a catalog book.
function Addon:ResolveBookFirstPage(guid, title)
    local objectID = self:GetGameObjectID(guid)
    local firstPage = objectID and ForeverRosettaStoneDB:GetBookFirstPage("object", objectID)
    if firstPage then return firstPage end

    local itemID = self.bookItemCandidate
    if itemID and Readable(title, "string") and GetClientItemName(itemID) == title then
        return ForeverRosettaStoneDB:GetBookFirstPage("item", itemID)
    end
    -- The interaction GUID can go away while the native book remains open.
    if not guid then return FindBookByObjectName(title, GetLocale()) end
end

-- The displayed page is the catalog page whose client-language text matches the native text,
-- trying the native page number first. Without a match the page stays native.
function Addon:ResolveBookPage(firstPage, pageNumber, nativeText)
    local rules = ForeverRosettaStoneDB:GetBookRules(firstPage)
    local pages = rules and rules.pages
    local native = Comparable(nativeText)
    if type(pages) ~= "table" or not native then return end
    local locale = GetLocale()
    local function Matches(pageID)
        return type(pageID) == "number" and Comparable(ForeverRosettaStoneDB:GetBookPage(pageID, locale)) == native
    end
    if Matches(pages[pageNumber]) then return pages[pageNumber] end
    for _, pageID in ipairs(pages) do
        if Matches(pageID) then return pageID end
    end
end

-- Title and body of the open page in the target language; either may be absent.
function Addon:GetBookTranslation(firstPage, pageID)
    local locale = self:GetTargetLocale()
    local title = ForeverRosettaStoneDB:GetBookName(firstPage, locale)
    local body = ForeverRosettaStoneDB:GetBookPage(pageID, locale)
    body = body and self:FormatQuestText(body, nil, locale)
    return title, body and PlainText(body) or nil
end

-- Resolution reads every catalog page of the book, so it is cached per displayed page.
function Addon:GetOpenBook()
    if not (ItemTextFrame and ItemTextFrame:IsVisible()) then return end
    local pageNumber = ItemTextGetPage and ItemTextGetPage()
    local nativeText = ItemTextGetText and ItemTextGetText()
    if not Readable(pageNumber, "number") or not Readable(nativeText, "string") then return end
    local ok, guid = pcall(UnitGUID, "npc")
    guid = ok and Readable(guid, "string") and guid or nil
    local title = ItemTextGetItem and ItemTextGetItem()
    local key = table.concat({ guid or "",
        tostring(self.bookItemCandidate), Readable(title, "string") and title or "", pageNumber, nativeText,
        self:GetTargetLocale() }, "\031")
    local cache = self.openBookCache
    if cache and cache.key == key then return cache.book end

    local book
    local firstPage = self:ResolveBookFirstPage(guid, title)
    local pageID = firstPage and self:ResolveBookPage(firstPage, pageNumber, nativeText)
    if pageID then
        local title, body = self:GetBookTranslation(firstPage, pageID)
        if body then
            book = { firstPage = firstPage, pageID = pageID, pageNumber = pageNumber, title = title, body = body }
        end
    end
    self.openBookCache = { key = key, book = book }
    return book
end

-- Same lifecycle as the NPC quest reader: a new book opens the reader (or offers the bookmark
-- when auto-open is off); closing it keeps the bookmark for the rest of that book.
function Addon:TransitionBookReader(current, event)
    if event.type == "reset" then
        return current.mode == "hidden" and current or { mode = "hidden" }
    end
    if event.type == "present" then
        if type(event.firstPage) ~= "number" then return current end
        if current.firstPage == event.firstPage and current.mode ~= "hidden" then return current end
        local mode = (event.autoOpen ~= false or current.mode == "visible") and "visible" or "dismissed"
        return { mode = mode, firstPage = event.firstPage }
    end
    if event.type == "dismiss" and current.mode == "visible" then
        return { mode = "dismissed", firstPage = current.firstPage }
    end
    if event.type == "open" and current.mode == "dismissed" then
        return { mode = "visible", firstPage = current.firstPage }
    end
    return current
end

function Addon:SendBookReader(event)
    self.bookReaderState = self:TransitionBookReader(self.bookReaderState or { mode = "hidden" }, event)
    if self.bookReaderState.mode ~= "visible" and self.bookReader then
        self.bookReader.frame:Hide()
        self.bookReader:ReleaseController()
        self.bookReader.contentKey = nil
    end
end

function Addon:CreateBookReader()
    local frame = self:NewFrame("Frame", "ForeverRosettaStoneBookReader", UIParent, "ForeverRosettaStoneQuestPanelTemplate")
    self:SetupQuestPanelTitle(frame)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local content = self:NewFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -68)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 26)
    local background = content:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("QuestDetailsBackgrounds", true)
    background:SetAllPoints()
    local parchments = {}
    local body = self:CreateNativeQuestBody(content, 278)
    body.frame:ClearAllPoints()
    body.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -8)
    body.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -5, 10)
    local close = self:NewFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")
    frame.CloseButton = close
    self:SetScript(close, "OnClick", function() self:SendBookReader({ type = "dismiss" }) end)

    local reader = { frame = frame, body = body, parchments = parchments }
    local footer = Addon:CreateGamepadLegend(frame, "ForeverRosettaStoneBookFooter")
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    footer:HidePrompts()

    function reader:ReleaseController()
        footer:HidePrompts()
        if not self.registered or InCombatLockdown() then return end
        self.registered = nil
        GamepadMode.FrameControlsManager:FrameHidden(frame)
        SmartNavigation:RemovePanelInfo(frame)
    end

    function reader:SyncController(focus)
        if not InputUtil.IsGamepadUIEnabled() or not frame:IsShown() then
            self:ReleaseController()
            return
        end
        close:SetShown(false)
        if not self.registered and not InCombatLockdown() then
            self.registered = true
            GamepadMode.FrameControlsManager:FrameShown(frame, false, focus == true)
        end
    end

    frame.FocusGamepad = Addon:Wrap("focus book translation", function()
        if not reader.registered or InCombatLockdown() then return end
        SmartNavigation:SetScrollFrameForFrame(frame, body.frame)
        SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(body.frame)
        Addon:ClearGamepadTarget(frame)
        footer:ShowPrompts()
    end)
    frame.UnfocusGamepad = Addon:Wrap("leave book translation", function()
        footer:HidePrompts()
        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(frame, nil) end
    end)
    frame.SmartNavigationCloseHandler = Addon:Wrap("close book translation", function()
        Addon:SendBookReader({ type = "dismiss" })
        return true
    end, true)
    Addon:HookScript(frame, "OnHide", function() reader:ReleaseController() end)

    function reader:ShowBook(book)
        local key = table.concat({ book.firstPage, book.pageID, Addon:GetTargetLocale(), book.title or "", book.body }, "\031")
        frame:SetTitle(Addon:GetTranslationLanguageLabel())
        Addon:FitQuestPanelTitle(frame)
        if self.contentKey ~= key then
            local sections = {}
            if book.title then sections[#sections + 1] = { source = QuestInfoTitleHeader, text = book.title, gap = 0 } end
            sections[#sections + 1] = { source = QuestInfoDescriptionText, text = book.body, gap = book.title and 10 or 0 }
            body:SetSections(sections)
            body:ScrollTo(0)
            self.contentKey = key
        end
        close:SetShown(not InputUtil.IsGamepadUIEnabled())
        frame:Show()
        self:SyncController()
    end

    -- Copy the material the native book draws (its textures, sizes and offsets), so the companion keeps
    -- the same parchment, stone or marble as the original. Without any, the quest parchment stays.
    function reader:SyncBackground(source)
        local used = 0
        for _, region in ipairs({ source:GetRegions() }) do
            local name = region.GetObjectType and region:GetObjectType() == "Texture" and region:GetName()
            local left, top = region:GetLeft(), region:GetTop()
            local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
            if name and name:find("Material", 1, true) and region:IsVisible() and left and top and sourceLeft and sourceTop then
                used = used + 1
                local parchment = parchments[used]
                if not parchment then
                    parchment = content:CreateTexture(nil, "BACKGROUND", nil, 1)
                    parchments[used] = parchment
                end
                local atlas = region:GetAtlas()
                if atlas then parchment:SetAtlas(atlas) else
                    parchment:SetTexture(region:GetTexture())
                    parchment:SetTexCoord(region:GetTexCoord())
                end
                local scale = region:GetEffectiveScale() / source:GetEffectiveScale()
                parchment:ClearAllPoints()
                parchment:SetPoint("TOPLEFT", frame, "TOPLEFT", (left - sourceLeft) * scale, (top - sourceTop) * scale)
                parchment:SetSize(region:GetWidth() * scale, region:GetHeight() * scale)
                parchment:Show()
            end
        end
        for index = used + 1, #parchments do parchments[index]:Hide() end
        background:SetShown(used == 0)
    end

    function reader:Layout(source, policy)
        self:SyncBackground(source)
        local scale = source:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local side = policy.GetSide(source)
        local key = table.concat({ tostring(source), policy.inputMode, scale, source:GetWidth(), source:GetHeight(),
            source:GetLeft() or 0, source:GetTop() or 0, side, source:GetFrameStrata(), source:GetFrameLevel() }, ":")
        if self.layoutKey == key then return end
        frame:SetScale(scale)
        frame:SetSize(source:GetWidth(), source:GetHeight())
        frame:SetFrameStrata(source:GetFrameStrata())
        frame:SetFrameLevel(source:GetFrameLevel() + 20)
        frame:SetFrameLevelsFromBaseLevel(frame:GetFrameLevel())
        frame:ClearAllPoints()
        frame:SetPoint(side == "left" and "TOPRIGHT" or "TOPLEFT", source, side == "left" and "TOPLEFT" or "TOPRIGHT", 0, 0)
        self.layoutKey = key
    end

    return reader
end

function Addon:GetBookBookmark()
    if self.bookBookmark then return self.bookBookmark end
    self.bookBookmark = self:CreateInteractionBookmark("ForeverRosettaStoneBookBookmark", function(focus)
        self:SendBookReader({ type = "open" })
        self:UpdateBookReader()
        local reader = self.bookReader
        if focus and reader then
            reader:ReleaseController()
            reader:SyncController(true)
        end
    end)
    return self.bookBookmark
end

function Addon:UpdateBookReader()
    local book
    if self:IsFeatureEnabled("bookPanel") and not self:IsTooltipBlocked()
        and not SettingsPanel:IsShown() and not WorldMapFrame:IsShown() then
        book = self:GetOpenBook()
    end
    if book then self:RecordDebugSurface(ItemTextFrame, "bookReader", book.firstPage, "reading", nil, book) end

    if not book then
        self:SendBookReader({ type = "reset" })
        if self.bookBookmark then self.bookBookmark:Hide() end
        return
    end

    self:SendBookReader({ type = "present", firstPage = book.firstPage, autoOpen = self:IsFeatureEnabled("bookAutoOpen") })
    local bookmark = self:GetBookBookmark()
    bookmark:Attach(ItemTextFrame, -76)
    bookmark:SetShown(self.bookReaderState.mode == "dismissed")
    bookmark:SyncController()
    if self.bookReaderState.mode ~= "visible" then return end

    if not self.bookReader then self.bookReader = self:CreateBookReader() end
    self.bookReader:Layout(ItemTextFrame, profiles.reading[self:GetTooltipInputMode()])
    self.bookReader:ShowBook(book)
end

-- Bag items do not report their ID to the reading window, so the last used bag slot is kept.
local function InstallItemTracking()
    if Addon.bookItemTracking then return end
    Addon.bookItemTracking = true
    local record = Addon:Wrap("record book item", function(bag, slot) Addon:RecordBookItem(bag, slot) end)
    if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", record) end
end

Addon:RegisterNameTooltipComponent({
    kind = "bookReader",
    defaultContext = "reading",
    placementProfiles = profiles,
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetBookName(id, locale) end,
    Install = InstallItemTracking,
    Update = function() Addon:UpdateBookReader() end,
    Hide = function() Addon:SendBookReader({ type = "reset" }) end,
})

-- World objects: an entry ID in the GUID names the book. Object tooltips usually carry no GUID, only
-- the native name, which resolves when it names exactly one catalog book.
Addon:RegisterNameTooltipComponent({
    kind = "book",
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetBookName(id, locale) end,
    ResolveData = function(_, data)
        local objectID = Addon:GetGameObjectID(data.guid)
        local firstPage = objectID and ForeverRosettaStoneDB:GetBookFirstPage("object", objectID)
        if firstPage then return firstPage end
        if not (Enum.TooltipDataType.Object and Readable(data.type, "number")
            and data.type == Enum.TooltipDataType.Object) then return end
        local line = Readable(data.lines, "table") and data.lines[1]
        local name = Readable(line, "table") and line.leftText
        return FindBookByObjectName(name, GetLocale())
    end,
})
