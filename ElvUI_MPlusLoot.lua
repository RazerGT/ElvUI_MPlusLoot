-- ElvUI Mythic+ Loot
-- Retail ElvUI plugin: shows Mythic+ end chest loot in an ElvUI-styled movable window.

local addonName = ...
local addon = _G.ElvUIMPlusLoot or {}
local T = addon.T
local Utils = addon.Utils or {}
local TrimText = Utils.TrimText
local StripChatMarkup = Utils.StripChatMarkup
local NormalizeName = Utils.NormalizeName
local GetUnitFullName = Utils.GetUnitFullName
local ForEachKnownGroupUnit = Utils.ForEachKnownGroupUnit
local FindGroupUnitByName = Utils.FindGroupUnitByName

local E, L, V, P, G = unpack(ElvUI)
local EP = LibStub and LibStub("LibElvUIPlugin-1.0", true)

local MPL = E:NewModule("ElvUI_MythicPlusLoot", "AceEvent-3.0")

local lootEntries = {}
local collectEndChestLoot = false
local inMythicPlusDungeon = false
local pendingRefresh = false
local lootWindowOpenQueued = false

-- Developer options
-- Keep these false for public releases.
-- Set ENABLE_DEBUG_COMMAND to true locally when you need /mplootdebug for troubleshooting.
-- Set ENABLE_TEST_COMMANDS to true locally when you want /mplootitem and /mplootfake available.
local ENABLE_DEBUG_COMMAND = false
local ENABLE_TEST_COMMANDS = true
local debugMode = false
local slashCommandsRegistered = false

local WINDOW_WIDTH = 640
local WINDOW_MIN_HEIGHT = 145
local WINDOW_MAX_HEIGHT = 420
local ROW_HEIGHT = 28

local EQUIPPABLE_INVENTORY_TYPES = {
    -- Armor
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
    "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_BODY", "INVTYPE_WRIST",
    "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",

    -- Jewelry and trinkets
    "INVTYPE_FINGER", "INVTYPE_TRINKET",

    -- Weapons and off-hand items
    "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE",
}

local EQUIPPABLE_INVENTORY_TYPE_SET = {}
for _, inventoryType in ipairs(EQUIPPABLE_INVENTORY_TYPES) do
    EQUIPPABLE_INVENTORY_TYPE_SET[inventoryType] = true
end

local function Print(msg)
    print("|cff1784d1ElvUI M+ Loot:|r " .. tostring(msg))
end

local function DebugPrint(msg)
    if debugMode then
        Print("DEBUG: " .. tostring(msg))
    end
end

local function ApplyFont(fontString, size, outline)
    if not fontString then return end

    if E and E.FontTemplate then
        E:FontTemplate(fontString, nil, size or 12, outline or "")
    else
        fontString:SetFont(STANDARD_TEXT_FONT, size or 12, outline or "")
    end
end

local function StripFontMarkup(text)
    if type(text) ~= "string" then return "" end

    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local function HasCyrillicText(text)
    text = StripFontMarkup(text)
    if text == "" then return false end

    -- Cyrillic text is UTF-8 encoded. For player names this usually uses
    -- lead bytes D0-D3 followed by continuation bytes 80-BF.
    return text:find("[\208-\211][\128-\191]") ~= nil
end

local function RefreshFontStringText(fontString, text)
    if not fontString then return end

    -- Force WoW to redraw the FontString after changing the font.
    fontString:SetText("")
    fontString:SetText(text or "")
end

local function TrySetFont(fontString, fontPath, size, outline)
    if not fontString or not fontPath or fontPath == "" then return false end
    return fontString:SetFont(fontPath, size or 12, outline or "")
end

local CYRILLIC_FONT_CANDIDATES = {
    -- Blizzard's Cyrillic font files. Important: FRIZQT___CYR has three underscores.
    "Fonts\\FRIZQT___CYR.TTF",
    "Fonts\\ARIALN_CYR.TTF",
    "Fonts\\MORPHEUS_CYR.TTF",
    "Fonts\\SKURRI_CYR.TTF",

    -- Lowercase variants as a safety net for non-Windows installs.
    "Fonts\\FRIZQT___CYR.ttf",
    "Fonts\\ARIALN_CYR.ttf",
    "Fonts\\MORPHEUS_CYR.ttf",
    "Fonts\\SKURRI_CYR.ttf",
}

local function ApplyCyrillicPlayerFont(fontString, text, size, outline)
    if not fontString then return end

    if HasCyrillicText(text) then
        for _, fontPath in ipairs(CYRILLIC_FONT_CANDIDATES) do
            if TrySetFont(fontString, fontPath, size, outline) then
                RefreshFontStringText(fontString, text)
                return
            end
        end

        -- Final fallback: use Blizzard/WoW objects and constants, but only after
        -- trying the explicit Cyrillic fonts. Your ElvUI/Emblem font can otherwise
        -- slip in here and produce square boxes again.
        local chatFont = ChatFontNormal and select(1, ChatFontNormal:GetFont())

        if TrySetFont(fontString, UNIT_NAME_FONT, size, outline) then RefreshFontStringText(fontString, text); return end
        if TrySetFont(fontString, STANDARD_TEXT_FONT, size, outline) then RefreshFontStringText(fontString, text); return end
        if TrySetFont(fontString, chatFont, size, outline) then RefreshFontStringText(fontString, text); return end
    end

    ApplyFont(fontString, size, outline)
    RefreshFontStringText(fontString, text)
end

local FALLBACK_ITEM_ICON = 134400

local function GetWhisperTarget(playerName)
    local _, fullName = FindGroupUnitByName(playerName)
    if fullName then return fullName end

    return StripChatMarkup(playerName)
end

local function GetClassColoredName(fullName)
    local displayName = NormalizeName(fullName) or StripChatMarkup(fullName) or UNKNOWN or "Unknown"
    local unit = FindGroupUnitByName(fullName)

    if unit then
        local _, classFile = UnitClass(unit)
        local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if color and color.colorStr then
            return string.format("|c%s%s|r", color.colorStr, displayName)
        end
    end

    return displayName
end

local function IsMythicPlusInstance()
    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == 8
end

local function GetItemInfoSafe(itemLink)
    if C_Item and C_Item.GetItemInfo then
        local itemName, itemLink2, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc = C_Item.GetItemInfo(itemLink)
        if itemName then
            return itemName, itemLink2, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc
        end
    end

    return GetItemInfo(itemLink)
end

local function GetEquipLocation(itemLink)
    if not itemLink then return nil end

    local equipLoc

    -- GetItemInfoInstant returns itemEquipLoc as its 4th value.
    -- GetItemInfo/C_Item.GetItemInfo returns itemEquipLoc as its 9th value.
    if C_Item and C_Item.GetItemInfoInstant then
        equipLoc = select(4, C_Item.GetItemInfoInstant(itemLink))
    end

    if not equipLoc and GetItemInfoInstant then
        equipLoc = select(4, GetItemInfoInstant(itemLink))
    end

    if not equipLoc then
        equipLoc = select(9, GetItemInfoSafe(itemLink))
    end

    return equipLoc
end

local function IsEligibleItem(itemLink)
    local inventoryType = GetEquipLocation(itemLink)
    if inventoryType == nil then
        return false
    end

    return not not EQUIPPABLE_INVENTORY_TYPE_SET[inventoryType]
end

local function IsOwnLootLine(text)
    if type(text) ~= "string" then return false end

    local ownPatterns = { "^Ihr%s", "^Du%s", "^You%s" }
    for _, pattern in ipairs(ownPatterns) do
        local startsWithOwnPronoun = text:find(pattern) ~= nil
        if startsWithOwnPronoun then return startsWithOwnPronoun end
    end

    return false
end

local function ExtractPlayerFromLootText(text)
    if type(text) ~= "string" then return nil end

    local fromLink = text:match("|Hplayer:[^|]+|h%[([^%]]+)%]|h")
    if fromLink then return StripChatMarkup(fromLink) end

    if IsOwnLootLine(text) then
        return GetUnitFullName("player") or UnitName("player")
    end

    local itemStart = text:find("|Hitem:", 1, true)
    if not itemStart then return nil end

    local prefix = text:sub(1, itemStart - 1)
    prefix = StripChatMarkup(prefix)
    if not prefix then return nil end

    prefix = prefix:gsub("[:：]%s*$", "")
    prefix = prefix:gsub("%s+erhält%s+.*$", "")
    prefix = prefix:gsub("%s+bekommt%s+.*$", "")
    prefix = prefix:gsub("%s+erbeutet%s*$", "")
    prefix = prefix:gsub("%s+receives%s+.*$", "")
    prefix = prefix:gsub("%s+won%s+.*$", "")

    return StripChatMarkup(prefix:match("^([^%s:]+)") or prefix)
end

local function GetLootPlayerName(text, playerName)
    return StripChatMarkup(playerName) or ExtractPlayerFromLootText(text)
end

local function QueueOpenLootWindow()
    if lootWindowOpenQueued then return end

    lootWindowOpenQueued = true
    C_Timer.After(0.6, function()
        lootWindowOpenQueued = false
        if #lootEntries > 0 then
            MPL:OpenLootWindow()
        end
    end)
end

local function GetItemIconSafe(itemLink)
    if not itemLink then return FALLBACK_ITEM_ICON end

    local icon

    if C_Item and C_Item.GetItemInfoInstant then
        icon = select(5, C_Item.GetItemInfoInstant(itemLink))
    end

    if not icon and GetItemInfoInstant then
        icon = select(5, GetItemInfoInstant(itemLink))
    end

    if not icon and GetItemIcon then
        icon = GetItemIcon(itemLink)
    end

    return icon or FALLBACK_ITEM_ICON
end

local function GetActualItemLevel(itemLink)
    if not itemLink then return "" end

    local providers = {}
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        table.insert(providers, C_Item.GetDetailedItemLevelInfo)
    end
    if GetDetailedItemLevelInfo then
        table.insert(providers, GetDetailedItemLevelInfo)
    end

    for _, provider in ipairs(providers) do
        local ok, level = pcall(provider, itemLink)
        if ok and type(level) == "number" then
            return level
        end
    end

    local itemLevel = select(4, GetItemInfoSafe(itemLink))
    return itemLevel or ""
end

local function ReadItemVisuals(itemLink)
    local name, _, quality = GetItemInfoSafe(itemLink)
    if not name then
        return nil
    end

    local visual = {
        name = name,
        quality = tonumber(quality) or Enum.ItemQuality.Common,
    }

    if GetItemQualityColor then
        visual.r, visual.g, visual.b, visual.hex = GetItemQualityColor(visual.quality)
    end

    return visual
end

local function GetColoredItemText(itemLink)
    local visual = itemLink and ReadItemVisuals(itemLink)
    if not visual then
        return itemLink or "Unknown Item"
    end

    if visual.hex then
        return "|c" .. visual.hex .. visual.name .. "|r"
    end

    return visual.name
end

local UPGRADE_TEXT_KEYS = {
    "trackName",
    "trackString",
    "displayString",
    "itemUpgradePathDisplayString",
    "upgradeText",
}

local UPGRADE_CURRENT_KEYS = {
    "currentLevel",
    "currentRank",
    "numUpgrades",
    "upgradeLevel",
}

local UPGRADE_MAX_KEYS = {
    "maxLevel",
    "maxRank",
    "maxUpgrades",
    "upgradeMaxLevel",
}

local UPGRADE_TRACK_HINTS = {
    "explorer",
    "adventurer",
    "veteran",
    "champion",
    "hero",
    "myth",
    "forscher",
    "abenteurer",
    "held",
    "mythisch",
}

local function FirstTableValue(source, keys)
    if type(source) ~= "table" then return nil end

    for _, key in ipairs(keys) do
        local value = source[key]
        if value ~= nil and value ~= "" then
            return value
        end
    end
end

local function LooksLikeUpgradeTrack(value)
    if type(value) ~= "string" or value == "" then return false end

    local lowerValue = value:lower()
    for _, hint in ipairs(UPGRADE_TRACK_HINTS) do
        local containsKnownTrackWord = lowerValue:find(hint, 1, true) ~= nil
        if containsKnownTrackWord then return containsKnownTrackWord end
    end

    return false
end

local function GetUpgradeTrackText(itemLink)
    if not itemLink or not (C_Item and C_Item.GetItemUpgradeInfo) then
        return "-"
    end

    local ok, info1, info2, info3, info4, info5 = pcall(C_Item.GetItemUpgradeInfo, itemLink)
    if not ok then return "-" end

    local trackName, currentRank, maxRank

    if type(info1) == "table" then
        trackName = FirstTableValue(info1, UPGRADE_TEXT_KEYS)
        currentRank = FirstTableValue(info1, UPGRADE_CURRENT_KEYS)
        maxRank = FirstTableValue(info1, UPGRADE_MAX_KEYS)
    else
        local values = { info1, info2, info3, info4, info5 }
        local numbers = {}

        for _, value in ipairs(values) do
            if not trackName and LooksLikeUpgradeTrack(value) then
                trackName = value
            elseif type(value) == "number" then
                table.insert(numbers, value)
            end
        end

        currentRank = numbers[1]
        maxRank = numbers[2]
    end

    trackName = TrimText(trackName)
    if not trackName then return "-" end

    currentRank = tonumber(currentRank)
    maxRank = tonumber(maxRank)

    if currentRank and maxRank and maxRank > 0 then
        local progressText = currentRank .. "/" .. maxRank
        return trackName .. " " .. progressText
    end

    return trackName
end

local function LinkItemToChat(self, button)
    if button ~= "LeftButton" then return end
    if not self.itemLink then return end
    if not IsModifiedClick("CHATLINK") then return end

    local activeWindow = ChatEdit_GetActiveWindow()
    if activeWindow then
        ChatEdit_InsertLink(self.itemLink)
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
        ChatEdit_ActivateChat(DEFAULT_CHAT_FRAME.editBox)
        ChatEdit_InsertLink(self.itemLink)
    end
end

local function BuildSortRecord(entry, sourceIndex)
    local visual = ReadItemVisuals(entry.itemLink)
    local itemName = (visual and visual.name) or entry.itemLink or ""

    return {
        source = entry,
        index = sourceIndex,
        itemLevel = tonumber(entry.itemLevel) or tonumber(GetActualItemLevel(entry.itemLink)) or -1,
        player = string.lower(NormalizeName(entry.playerName) or ""),
        item = string.lower(itemName),
    }
end

local function SortLootEntries()
    local sortable = {}

    for index, entry in ipairs(lootEntries) do
        sortable[index] = BuildSortRecord(entry, index)
    end

    table.sort(sortable, function(left, right)
        if left.itemLevel ~= right.itemLevel then
            return left.itemLevel > right.itemLevel
        end

        if left.player ~= right.player then
            return left.player < right.player
        end

        if left.item ~= right.item then
            return left.item < right.item
        end

        return left.index < right.index
    end)

    for index, record in ipairs(sortable) do
        lootEntries[index] = record.source
    end
end

local function RefreshOpenWindow()
    pendingRefresh = false

    if not MPL or not MPL.LootWindow then return end
    if not MPL.LootWindow:IsShown() then return end

    MPL:UpdateLootWindow()
end

local function QueueWindowRefresh()
    if pendingRefresh then return end

    pendingRefresh = true
    C_Timer.After(0.30, RefreshOpenWindow)
end

local function AttachItemTooltip(widget)
    widget:SetScript("OnEnter", function(owner)
        if not owner.itemLink then return end

        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(owner.itemLink)

        if owner.keystoneLootTier then
            local tierLabel = MPL.GetKeystoneLootTierLabel and MPL:GetKeystoneLootTierLabel(owner.keystoneLootTier)
            local tooltipText = T("keystoneLootWishlistTooltip")

            if tierLabel then
                tooltipText = tooltipText .. ": " .. tierLabel
            end

            GameTooltip:AddLine(tooltipText, 1, 0.82, 0)
        end

        GameTooltip:Show()
    end)

    widget:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function MakeItemButton(parent, itemLink)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button.itemLink = itemLink
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", LinkItemToChat)
    AttachItemTooltip(button)
    return button
end

local function CreateText(parent, text, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, size or 12)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text or "")
    return fs
end

function MPL:ClearLootRows()
    if not self.rows then return end

    for index = #self.rows, 1, -1 do
        local row = self.rows[index]
        if row and row.Hide then row:Hide() end
        if row and row.SetParent then row:SetParent(nil) end
        self.rows[index] = nil
    end
end

function MPL:CreateHeaderText(parent, text, x, width)
    local fs = CreateText(parent, text, 12, "LEFT")
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(width)
    return fs
end

function MPL:CreateLootWindow()
    if self.LootWindow then return end

    local f = CreateFrame("Frame", "ElvUI_MythicPlusLoot_Window", E.UIParent, "BackdropTemplate")
    self.LootWindow = f
    self.rows = {}

    f:SetSize(WINDOW_WIDTH, WINDOW_MIN_HEIGHT)
    f:SetPoint("CENTER", E.UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(50)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
    end)
    f:SetTemplate("Transparent")
    f:CreateShadow()
    f:Hide()

    f.title = CreateText(f, T("title"), 13, "CENTER")
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local S = E:GetModule("Skins", true)
    if S and S.HandleCloseButton then
        S:HandleCloseButton(closeBtn)
    end

    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -38)
    header:SetHeight(22)
    header:SetTemplate("Default")
    f.header = header

    self:CreateHeaderText(header, T("headerItem"), 8, 260)
    self:CreateHeaderText(header, T("headerIlvl"), 286, 45)
    self:CreateHeaderText(header, T("headerTrack"), 340, 110)
    self:CreateHeaderText(header, T("headerLooter"), 455, 90)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -64)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.content = content
end

local function StartWhisperForEntry(entry)
    if InCombatLockdown and InCombatLockdown() then
        Print(T("whisperCombatBlocked"))
        return
    end

    local receiver = entry and GetWhisperTarget(entry.playerName)
    if receiver and receiver ~= "" then
        ChatFrame_SendTell(receiver)
    end
end

function MPL:CreateLootRow(parent, entry, index)
    local itemLink = entry.itemLink
    local relevance = self:GetItemRelevance(itemLink)
    local keystoneLootTier = relevance and relevance.keystoneLootTier
    local markerOffset = 5
    local itemIconOffset = 23
    local itemTextWidth = 227

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetTemplate("Default")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    if index % 2 == 0 then
        row:SetBackdropColor(0, 0, 0, 0.18)
    end

    local function AddCell(text, x, width, justify)
        local cell = CreateText(row, text, 12, justify or "LEFT")
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        cell:SetWidth(width)
        cell:SetWordWrap(false)
        return cell
    end

    if keystoneLootTier then
        row.wishlistButton = CreateFrame("Button", nil, row)
        row.wishlistButton.itemLink = itemLink
        row.wishlistButton.keystoneLootTier = keystoneLootTier
        row.wishlistButton:SetSize(14, 14)
        row.wishlistButton:SetPoint("LEFT", row, "LEFT", markerOffset, 0)
        AttachItemTooltip(row.wishlistButton)

        row.wishlistIcon = row.wishlistButton:CreateTexture(nil, "ARTWORK")
        row.wishlistIcon:SetAllPoints(row.wishlistButton)
        row.wishlistIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    end

    row.iconButton = MakeItemButton(row, itemLink)
    row.iconButton.keystoneLootTier = keystoneLootTier
    row.iconButton:SetSize(22, 22)
    row.iconButton:SetPoint("LEFT", row, "LEFT", itemIconOffset, 0)
    row.iconButton:SetTemplate("Default")

    row.icon = row.iconButton:CreateTexture(nil, "ARTWORK")
    row.icon:SetInside(row.iconButton)
    row.icon:SetTexture(GetItemIconSafe(itemLink))
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local visual = ReadItemVisuals(itemLink)
    if visual and visual.r then
        row.iconButton:SetBackdropBorderColor(visual.r, visual.g, visual.b)
    end

    row.itemButton = MakeItemButton(row, itemLink)
    row.itemButton.keystoneLootTier = keystoneLootTier
    row.itemButton:SetPoint("LEFT", row.iconButton, "RIGHT", 6, 0)
    row.itemButton:SetSize(itemTextWidth, 22)

    row.itemText = CreateText(row.itemButton, GetColoredItemText(itemLink), 12, "LEFT")
    row.itemText:SetAllPoints(row.itemButton)
    row.itemText:SetWordWrap(false)

    row.ilvl = AddCell(tostring(GetActualItemLevel(itemLink) or ""), 286, 45)
    row.track = AddCell(GetUpgradeTrackText(itemLink), 340, 110)

    local looterText = GetClassColoredName(entry.playerName)
    row.looter = AddCell("", 455, 90)
    ApplyCyrillicPlayerFont(row.looter, looterText, 12)

    row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.whisper:SetSize(58, 20)
    row.whisper:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.whisper:SetText(T("whisper"))

    local S = E:GetModule("Skins", true)
    if S and S.HandleButton then
        S:HandleButton(row.whisper)
    end

    local whisperFont = row.whisper:GetFontString()
    if whisperFont then
        ApplyFont(whisperFont, 11)
        whisperFont:SetTextColor(1, 0.82, 0)
        whisperFont:SetShadowColor(0, 0, 0, 0.9)
        whisperFont:SetShadowOffset(1, -1)
    end

    row.whisper:SetScript("OnClick", function()
        StartWhisperForEntry(entry)
    end)

    return row
end

function MPL:UpdateLootWindow()
    if not self.LootWindow then return end

    self:ClearLootRows()
    SortLootEntries()

    local itemCount = #lootEntries
    local contentTopOffset = 64
    local contentBottomPadding = 18
    local dynamicHeight

    if itemCount == 0 then
        dynamicHeight = WINDOW_MIN_HEIGHT
    else
        dynamicHeight = contentTopOffset + contentBottomPadding + (itemCount * ROW_HEIGHT)
        dynamicHeight = math.max(WINDOW_MIN_HEIGHT, dynamicHeight)
        dynamicHeight = math.min(WINDOW_MAX_HEIGHT, dynamicHeight)
    end

    self.LootWindow:SetHeight(dynamicHeight)

    if itemCount == 0 then
        local row = CreateText(self.LootWindow.content, T("noLoot"), 12, "LEFT")
        row:SetPoint("TOPLEFT", self.LootWindow.content, "TOPLEFT", 8, -8)
        row:SetTextColor(0.8, 0.8, 0.8)
        table.insert(self.rows, row)
        return
    end

    for index, entry in ipairs(lootEntries) do
        local row = self:CreateLootRow(self.LootWindow.content, entry, index)
        table.insert(self.rows, row)
    end
end

function MPL:OpenLootWindow()
    self:CreateLootWindow()

    local window = self.LootWindow
    if not window then return end

    self:UpdateLootWindow()
    window:Show()
end

function MPL:CHALLENGE_MODE_START()
    inMythicPlusDungeon = true
    collectEndChestLoot = false
    lootWindowOpenQueued = false

    if self.LootWindow then
        self.LootWindow:Hide()
        self:ClearLootRows()
    end

    wipe(lootEntries)
    DebugPrint("M+ started. Loot cleared.")
end

function MPL:CHALLENGE_MODE_COMPLETED()
    if not inMythicPlusDungeon and not IsMythicPlusInstance() then
        return
    end

    collectEndChestLoot = true
    lootWindowOpenQueued = false
    wipe(lootEntries)

    DebugPrint("M+ completed. Waiting for end chest loot. Window will open after first valid loot item.")

    -- Safety window: after this we stop listening for end chest loot.
    C_Timer.After(120, function()
        collectEndChestLoot = false
        inMythicPlusDungeon = false
        lootWindowOpenQueued = false
        DebugPrint("Loot collection window closed.")
    end)
end

function MPL:PLAYER_ENTERING_WORLD()
    if not IsMythicPlusInstance() then
        collectEndChestLoot = false
        inMythicPlusDungeon = false
    end
end

local function ExtractItemLinkFromLootMessage(text)
    if type(text) ~= "string" then return nil end
    return text:match("|Hitem:%d+.-|h%[[^%]]+%]|h")
end

local function BuildLootEntryFromEvent(text, playerName)
    local itemLink = ExtractItemLinkFromLootMessage(text)
    if not itemLink then return nil end

    local looterName = GetLootPlayerName(text, playerName)
    if not looterName then return nil end

    return {
        playerName = looterName,
        itemLink = itemLink,
        itemLevel = GetActualItemLevel(itemLink),
    }
end

function MPL:CHAT_MSG_LOOT(event, text, playerName)
    if not collectEndChestLoot then return end

    local entry = BuildLootEntryFromEvent(text, playerName)
    if not entry then
        DebugPrint("Ignored loot message without usable item/player data.")
        return
    end

    local eligible = IsEligibleItem(entry.itemLink)

    DebugPrint("CHAT_MSG_LOOT event = " .. tostring(event))
    DebugPrint("itemLink = " .. tostring(entry.itemLink))
    DebugPrint("looterName = " .. tostring(entry.playerName))
    DebugPrint("eligible = " .. tostring(eligible))

    if not eligible then return end

    table.insert(lootEntries, entry)
    QueueOpenLootWindow()
    QueueWindowRefresh()
end

function MPL:RegisterSlashCommands()
    if slashCommandsRegistered then return end
    slashCommandsRegistered = true

    -- Public commands
    SLASH_MPLUSLOOT1 = "/mploot"
    SLASH_MPLUSLOOT2 = "/mplusloot"
    SlashCmdList["MPLUSLOOT"] = function()
        if MPL.LootWindow and MPL.LootWindow:IsShown() then
            MPL.LootWindow:Hide()
        else
            MPL:OpenLootWindow()
        end
    end

    -- Test commands. Disable ENABLE_TEST_COMMANDS before release if you do not want these public.
    if ENABLE_TEST_COMMANDS then
        SLASH_MPLUSLOOTSTART1 = "/mplootstart"
        SlashCmdList["MPLUSLOOTSTART"] = function()
            inMythicPlusDungeon = true
            MPL:CHALLENGE_MODE_COMPLETED()
            Print(T("testModeActive"))
        end

        SLASH_MPLUSLOOTFAKE1 = "/mplootfake"
        SlashCmdList["MPLUSLOOTFAKE"] = function()
            collectEndChestLoot = true
            lootWindowOpenQueued = false
            wipe(lootEntries)

            local playerName = UnitName("player") or "Player"
            local testSlots = {
                16, -- Main Hand
                17, -- Off Hand
                13, -- Trinket 1
                14, -- Trinket 2
                1,  -- Head
                3,  -- Shoulder
                5,  -- Chest
                6,  -- Waist
                7,  -- Legs
                8,  -- Feet
                9,  -- Wrist
                10, -- Hands
                11, -- Finger 1
                12, -- Finger 2
                15, -- Back
            }

            local availableItems = {}
            for _, slotID in ipairs(testSlots) do
                local itemLink = GetInventoryItemLink("player", slotID)
                if itemLink then
                    table.insert(availableItems, itemLink)
                end
            end

            if #availableItems == 0 then
                Print(T("noFakeItems"))
                return
            end

            local roll = math.random(100)
            local itemAmount

            if roll <= 60 then
                itemAmount = 2
            elseif roll <= 90 then
                itemAmount = 3
            else
                itemAmount = math.random(4, 5)
            end

            itemAmount = math.min(itemAmount, #availableItems)

            for i = #availableItems, 2, -1 do
                local j = math.random(i)
                availableItems[i], availableItems[j] = availableItems[j], availableItems[i]
            end

            local fakeNames = {
                playerName,
                "Ufoklausine-Thrall",
                "Félise-Antonidas",
                "Arum-Gul'dan",
                "Sèlie-Kil'jaeden",
                "Тиной-Ясеневыйлес",
            }

            local fakePatterns = {
                "Ihr erhaltet Beute: %s",
                "%s bekommt Beute: %s",
                "%s erhält Beute: %s",
                "%s erhält Bonusbeute: %s",
                "%s bekommt Bonusbeute: %s",
                "You receive loot: %s",
                "%s receives loot: %s",
            }

            local entriesBefore = #lootEntries

            for i = 1, itemAmount do
                local itemLink = availableItems[i]
                local pattern = fakePatterns[math.random(#fakePatterns)]
                local fakeText

                if pattern:find("Ihr erhaltet") or pattern:find("You receive") then
                    fakeText = string.format(pattern, itemLink)
                else
                    local fakeName = fakeNames[math.random(#fakeNames)]
                    fakeText = string.format(pattern, fakeName, itemLink)
                end

                DebugPrint("Fake loot fired: " .. fakeText)
                MPL:CHAT_MSG_LOOT("CHAT_MSG_LOOT", fakeText, nil)
            end

            if #lootEntries > entriesBefore then
                MPL:OpenLootWindow()
                QueueWindowRefresh()
            end

            Print(string.format(T("fakeLootSimulated"), itemAmount))
        end

        SLASH_MPLUSLOOTITEM1 = "/mplootitem"
        SlashCmdList["MPLUSLOOTITEM"] = function()
            collectEndChestLoot = true
            wipe(lootEntries)

            local playerName = UnitName("player")
            local testSlots = {
                16, -- Main Hand
                17, -- Off Hand
                13, -- Trinket 1
                14, -- Trinket 2
                1,  -- Head
                3,  -- Shoulder
                5,  -- Chest
                6,  -- Waist
                7,  -- Legs
                8,  -- Feet
                9,  -- Wrist
                10, -- Hands
                11, -- Finger 1
                12, -- Finger 2
                15, -- Back
            }

            local availableItems = {}

            for _, slotID in ipairs(testSlots) do
                local itemLink = GetInventoryItemLink("player", slotID)
                if itemLink then
                    table.insert(availableItems, itemLink)
                end
            end

            if #availableItems == 0 then
                Print(T("noTestItems"))
                MPL:OpenLootWindow()
                QueueWindowRefresh()
                return
            end

            local roll = math.random(100)
            local itemAmount

            if roll <= 60 then
                itemAmount = 2
            elseif roll <= 90 then
                itemAmount = 3
            else
                itemAmount = math.random(4, 5)
            end

            itemAmount = math.min(itemAmount, #availableItems)

            for i = #availableItems, 2, -1 do
                local j = math.random(i)
                availableItems[i], availableItems[j] = availableItems[j], availableItems[i]
            end

            for i = 1, itemAmount do
                local itemLink = availableItems[i]
                table.insert(lootEntries, {
                    playerName = playerName,
                    itemLink = itemLink,
                })
            end

            MPL:OpenLootWindow()
            QueueWindowRefresh()
            Print(string.format(T("testItemsSimulated"), itemAmount))
        end
    end

    -- Developer-only debug command. Not registered in public releases.
    if ENABLE_DEBUG_COMMAND then
        SLASH_MPLUSLOOTDEBUG1 = "/mplootdebug"
        SlashCmdList["MPLUSLOOTDEBUG"] = function()
            debugMode = not debugMode
            Print(debugMode and T("debugEnabled") or T("debugDisabled"))
        end
    end
end

function MPL:Initialize()
    self:RegisterSlashCommands()

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("CHALLENGE_MODE_START")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHAT_MSG_LOOT")

    if EP and EP.RegisterPlugin then
        EP:RegisterPlugin(addonName, function()
            Print(T("loaded"))
        end)
    else
        Print(T("loaded"))
    end
end

-- Register slash commands immediately as a fallback.
-- This keeps /mploot available even if ElvUI initializes this plugin later than expected.
MPL:RegisterSlashCommands()

E:RegisterModule(MPL:GetName())
