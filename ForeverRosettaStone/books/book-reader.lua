local _, Addon = ...

-- Books are identified by their owner, and the native page number indexes the catalog's page list.

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
    if firstPage then return firstPage, "object", objectID end

    local itemID = self.bookItemCandidate
    if itemID and Readable(title, "string") and GetClientItemName(itemID) == title then
        return ForeverRosettaStoneDB:GetBookFirstPage("item", itemID), "item", itemID
    end
    -- The interaction GUID can go away while the native book remains open.
    if not guid then return FindBookByObjectName(title, GetLocale()) end
    if objectID then return nil, "object", objectID end
end

function Addon:ResolveBookPage(firstPage, pageNumber)
    local rules = ForeverRosettaStoneDB:GetBookRules(firstPage)
    local pages = rules and rules.pages
    local pageID = type(pages) == "table" and pages[pageNumber]
    if type(pageID) == "number" then return pageID end
end

-- Title and body of the open page in the target language; either may be absent.
function Addon:GetBookTranslation(firstPage, pageID)
    local locale = self:GetTargetLocale()
    local title = ForeverRosettaStoneDB:GetBookName(firstPage, locale)
    local body = ForeverRosettaStoneDB:GetBookPage(pageID, locale)
    body = body and self:FormatQuestText(body, nil, locale)
    return title, body and PlainText(body) or nil
end

-- Cache the resolved translation for the displayed page and target language.
function Addon:GetOpenBook()
    if not (ItemTextFrame and ItemTextFrame:IsVisible()) then return end
    local pageNumber = ItemTextGetPage and ItemTextGetPage()
    if not Readable(pageNumber, "number") or pageNumber < 1 then return end
    local ok, guid = pcall(UnitGUID, "npc")
    guid = ok and Readable(guid, "string") and guid or nil
    local title = ItemTextGetItem and ItemTextGetItem()
    local key = table.concat({ guid or "",
        tostring(self.bookItemCandidate), Readable(title, "string") and title or "", pageNumber,
        self:GetTargetLocale() }, "\031")
    local cache = self.openBookCache
    if cache and cache.key == key then return cache.book, cache.missing end

    local book, missing
    local firstPage, ownerKind, ownerID = self:ResolveBookFirstPage(guid, title)
    local pageID = firstPage and self:ResolveBookPage(firstPage, pageNumber)
    if firstPage and not pageID then return end
    if pageID then
        local title, body = self:GetBookTranslation(firstPage, pageID)
        if body then
            book = { firstPage = firstPage, pageID = pageID, pageNumber = pageNumber, title = title, body = body,
                ownerKind = ownerKind, ownerID = ownerID }
        end
    end
    if not book then
        missing = { ownerKind = ownerKind, ownerID = ownerID, firstPageID = firstPage,
            matchedPageID = pageID, candidatePageID = pageID,
            pageNumber = pageNumber, nativeTitle = Readable(title, "string") and title or nil,
            reason = pageID and "missing_translation" or "book_not_identified" }
    end
    self.openBookCache = { key = key, book = book, missing = missing }
    return book, missing
end

-- Same lifecycle as the NPC quest reader: a new book opens the reader (or offers the bookmark
-- when auto-open is off); closing it keeps the bookmark for the rest of that book.
function Addon:TransitionBookReader(current, event)
    if event.type == "reset" then
        return current.mode == "hidden" and current or { mode = "hidden" }
    end
    if event.type == "present" then
        local key = event.bookKey or event.firstPage
        if key == nil then return current end
        if current.bookKey == key and current.mode ~= "hidden" then return current end
        local mode = (event.autoOpen ~= false or current.mode == "visible") and "visible" or "dismissed"
        return { mode = mode, bookKey = key }
    end
    if event.type == "dismiss" and current.mode == "visible" then
        return { mode = "dismissed", bookKey = current.bookKey }
    end
    if event.type == "open" and current.mode == "dismissed" then
        return { mode = "visible", bookKey = current.bookKey }
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
    local function Dismiss()
        self:SendBookReader({ type = "dismiss" })
        self:UpdateBookReader()
    end
    local reader = self:CreateSideReader("ForeverRosettaStoneBookReader", Dismiss)
    local frame, body, content, background = reader.frame, reader.body, reader.content, reader.background
    local parchments = {}
    reader.parchments = parchments
    background:SetAtlas("QuestBG-Parchment")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    reader.title = title
    local scrollBackground = content:CreateTexture(nil, "BACKGROUND")
    scrollBackground:SetColorTexture(0, 0, 0, 0.8)
    scrollBackground:SetPoint("TOPLEFT", body.frame, "TOPRIGHT")
    scrollBackground:SetPoint("BOTTOMRIGHT", body.frame.ScrollBar, "BOTTOMRIGHT")
    scrollBackground:Hide()
    local report = self:NewFrame("Button", nil, frame, "UIPanelButtonTemplate")
    report:SetSize(110, 22)
    report:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -32)
    report:SetText("Options")
    reader.options = report
    self:SetScript(report, "OnClick", function(owner)
        self:ShowTranslationOptions(owner, self:SettingsText("reportTranslation"), function()
            local book, missing = self:GetOpenBook()
            if not (book or missing) then return end
            local reportData = {}
            if missing then
                for key, value in pairs(missing) do reportData[key] = value end
            else
                reportData = { firstPageID = book.firstPage, matchedPageID = book.pageID, pageNumber = book.pageNumber,
                    ownerKind = book.ownerKind, ownerID = book.ownerID }
                local title = ItemTextGetItem and ItemTextGetItem()
                if Readable(title, "string") then reportData.nativeTitle = title end
            end
            local ok, nativeText
            if ItemTextGetText then ok, nativeText = pcall(ItemTextGetText) end
            if ok and Readable(nativeText, "string") then reportData.nativeText = nativeText end
            reader.reportOwner = true
            self:ShowBookReport(reportData)
        end)
    end)
    self:SetupSideReaderController(reader, "ForeverRosettaStoneBookFooter", Dismiss)

    function reader:ShowBook(book)
        local key = table.concat({ book.firstPage or "", book.pageID or "", book.pageNumber,
            Addon:GetTargetLocale(), book.title or "", book.body }, "\031")
        self.missing = book.missing
        frame:SetTitle(self.missing and "Forever Rosetta Stone" or Addon:GetTranslationLanguageLabel())
        Addon:FitQuestPanelTitle(frame)
        title:SetText(book.title)
        title:SetShown(book.title ~= nil)
        local pageChanged = self.contentKey ~= key
        if pageChanged or self.textLayoutChanged then
            local native = self.nativePage
            local kind = native and native:GetObjectType()
            local textType
            if not self.missing and kind == "SimpleHTML" and native:GetFont("P") then
                textType = "P"
            elseif kind ~= "FontString" then
                native = QuestInfoDescriptionText
            end
            body:SetSections({ { source = native, textType = textType,
                text = book.body, gap = 0 } })
            if pageChanged then body:ScrollTo(0) end
            self.contentKey = key
        end
        frame:Show()
        self:SyncController()
        self:SyncTarget()
    end

    -- Copy the material the native book draws (its textures, sizes and offsets), so the companion keeps
    -- the same parchment, stone or marble as the original. Without any, the quest parchment stays.
    function reader:SyncBackground(source)
        local used = 0
        for _, region in ipairs({ source:GetRegions() }) do
            local isTexture = region:GetObjectType() == "Texture"
            local name = isTexture and region:GetName()
            local isMaterial = isTexture and (region == source.Material
                or (name and name:find("Material", 1, true))
                or region:GetAtlas() == "QuestBG-Parchment")
            local left, top = region:GetLeft(), region:GetTop()
            local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
            if isMaterial and region:IsVisible() and left and top and sourceLeft and sourceTop then
                used = used + 1
                local parchment = parchments[used]
                if not parchment then
                    parchment = content:CreateTexture(nil, "BACKGROUND", nil, 1)
                    parchments[used] = parchment
                end
                local atlas = region:GetAtlas()
                if atlas then parchment:SetAtlas(atlas) else parchment:SetTexture(region:GetTexture()) end
                parchment:SetTexCoord(region:GetTexCoord())
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
        local scale = source:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local side = policy.GetSide(source)
        local key = table.concat({ tostring(source), policy.inputMode, scale, source:GetWidth(), source:GetHeight(),
            source:GetLeft() or 0, source:GetTop() or 0, side, source:GetFrameStrata(), source:GetFrameLevel() }, ":")
        if self.layoutKey ~= key then
            frame:SetScale(scale)
            frame:SetSize(source:GetWidth(), source:GetHeight())
            frame:SetFrameStrata(source:GetFrameStrata())
            frame:SetFrameLevel(source:GetFrameLevel() + 20)
            frame:SetFrameLevelsFromBaseLevel(frame:GetFrameLevel())
            frame:ClearAllPoints()
            frame:SetPoint(side == "left" and "TOPRIGHT" or "TOPLEFT", source,
                side == "left" and "TOPLEFT" or "TOPRIGHT", 0, 0)
            self.layoutKey = key
        end

        Addon:SyncQuestInset(frame, source)
        local viewport = source.ScrollFrame or ItemTextScrollFrame
        local viewportScale = Addon:AlignQuestViewport(body.frame, viewport, frame, source)
        local bar = viewport and (viewport.ScrollBar or ItemTextScrollFrameScrollBar)
        local alignedBar = Addon:AlignQuestScrollBar(body.frame.ScrollBar, bar, frame, source)
        scrollBackground:SetShown(alignedBar and not (frame.questInset and frame.questInset:IsShown()))

        local page = source.PageText or ItemTextPageText
        local leftInset, topInset, width
        if viewportScale then
            local child = viewport.GetScrollChild and viewport:GetScrollChild()
            local pageLeft, pageTop = page and page:GetLeft(), page and page:GetTop()
            local childTop = child and child:GetTop()
            leftInset = pageLeft and math.max(0, (pageLeft - viewport:GetLeft()) * viewportScale) or 5
            topInset = pageTop and childTop and math.max(0, (childTop - pageTop) * viewportScale) or 10
            local available = viewport:GetWidth() * viewportScale - leftInset
            width = math.max(1, page and math.min(page:GetWidth() * viewportScale, available) or (available - 5))
            background:ClearAllPoints()
            background:SetAllPoints(body.frame)
        end
        self.textLayoutChanged = self.nativePage ~= page or body.textInsetX ~= leftInset or body.textInsetY ~= topInset
            or body.contentWidth ~= width
        self.nativePage = page
        body.textInsetX, body.textInsetY, body.contentWidth = leftInset, topInset, width
        self:SyncBackground(source)

        local nativePageNumber = source.CurrentPage or ItemTextCurrentPage
        local nativeTop, sourceTop = nativePageNumber and nativePageNumber:GetTop(), source:GetTop()
        local titleY = -41
        if nativeTop and sourceTop then
            titleY = (nativeTop - sourceTop - nativePageNumber:GetHeight() / 2)
                * nativePageNumber:GetEffectiveScale() / source:GetEffectiveScale()
        end
        title:ClearAllPoints()
        title:SetPoint("LEFT", frame, "TOPLEFT", 16, titleY)
        title:SetPoint("RIGHT", frame, "TOPRIGHT", -report:GetWidth() - 18, titleY)
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
    local book, missing
    if self:IsFeatureEnabled("bookPanel") and not self:IsTooltipBlocked()
        and not SettingsPanel:IsShown() and not WorldMapFrame:IsShown() then
        book, missing = self:GetOpenBook()
    end
    if book then self:RecordDebugSurface(ItemTextFrame, "bookReader", book.firstPage, "reading", nil, book) end

    if not book and not missing then
        self:SendBookReader({ type = "reset" })
        if self.bookBookmark then self.bookBookmark:Hide() end
        return
    end

    local bookKey = book and book.firstPage or missing.firstPageID
        or table.concat({ missing.ownerKind or "", missing.ownerID or "", missing.nativeTitle or "" }, ":")
    if missing then
        book = { firstPage = missing.firstPageID, pageNumber = missing.pageNumber, missing = missing,
            body = self:GetMissingTranslationMessage("book") }
    end
    self:SendBookReader({ type = "present", bookKey = bookKey, autoOpen = self:IsFeatureEnabled("bookAutoOpen") })
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
    local function record(bag, slot)
        if Addon.lifecycle == "ready" then Addon:Run("record book item", Addon.RecordBookItem, Addon, bag, slot) end
    end
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
