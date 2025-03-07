local TOC_NAME,
    ---@class Addon
    Addon = ...

---@class Addon_EventFrame: EventFrame
local EventFrame = CreateFrame("EventFrame", TOC_NAME.."EventFrame", UIParent)
EventFrame:SetUndefinedEventsAllowed(true)
EventFrame:SetScript("OnEvent", EventFrame.TriggerEvent)
function EventFrame:RegisterEventCallback(event, callback, owner)
    EventFrame:RegisterEvent(event)
    EventFrame:RegisterCallback(event, callback, owner or EventFrame)
end

local L = { -- todo: some actual translations for missing pre-localized strings
    SELECTED_CLASSES = "Selected Classes",
    SHOW_APPLICANTS = "Show Applicants",
    SHOW_PREMADE_GROUPS = "Show Premade Groups",
    TOGGLE_FILTERS_PANEL = "Toggle Filters Panel",
    FILTER_PANEL_TITLE = "Advanced Filters",
    FILTER_BY_CLASS = "Filter by Class",
    HIDE_DELISTED = "Hide Delisted Entries",
    FILTER_BY_ROLE = "Filter Roles",
    ADDON_ACRONYM = "AGF",
}
local CLASS_FILE_BY_ID = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE",
    [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK", [10] = "MONK", [11] = "DRUID",
};
local CLASS_ID_BY_FILE = tInvert(CLASS_FILE_BY_ID)
local CHECKBOX_SIZE = 28
local CLASS_FILTER_DROPDOWN_TAG = "ADV_LFG_CLASS_FILTER"
local ACTIVITY_DROPDOWN_TAG = "ADV_LFG_ACTIVITY_FILTER"
local CATEGORY_DROPDOWN_TAG = "ADV_LFG_CATEGORY_FILTER"
local LFG_ROLE_ATLAS = {
	["GUIDE"] = "UI-LFG-RoleIcon-Leader-Micro",
	["TANK"] = "UI-LFG-RoleIcon-Tank-Micro",
	["HEALER"] = "UI-LFG-RoleIcon-Healer-Micro",
	["DPS"] = "UI-LFG-RoleIcon-DPS-Micro",
};
local LFG_ROLE_DISABLED_ATLAS = {
    ["GUIDE"] = "UI-LFG-RoleIcon-Leader-Disabled",
    ["TANK"] = "UI-LFG-RoleIcon-Tank-Disabled",
    ["HEALER"] = "UI-LFG-RoleIcon-Healer-Disabled",
    ["DPS"] = "UI-LFG-RoleIcon-DPS-Disabled",
}
local LFG_DISABLED_FONT_COLOR = CreateColor(0.3, 0.3, 0.3)
local isPlayerHorde = UnitFactionGroup("player") == "Horde"
local isClassicEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isSeasonOfDiscovery = C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfDiscovery
local isBurningCrusade = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
local isCataclysm = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC

local meetsSettingCountRequirements = function(setting, count)
    local min, max = setting.Minimum, setting.Maximum
    if not (min or max) then return true end
    -- edge case: when user has a minimum of 0, and no maximum, assume exactly 0 is expected.
    if min == 0 and not max then return count == 0 end
    if min and count < min then return false end
    if max and count > max then return false end
    return true
end
local ShouldFilterForResultID = function(resultID)
    local resultData = C_LFGList.GetSearchResultInfo(resultID)
    if not resultData then return false end
    if resultData.isDelisted and Addon.accountDB.HideDelisted then return false end
    if resultData.numMembers == 1 then -- applicant
        local applicants = Addon.accountDB.Applicants
        if not applicants.Enabled then return false end
        local applicant = C_LFGList.GetSearchResultLeaderInfo(resultID)
        if applicants.RoleFilters.Enabled then
            local appliedRoles = applicant.lfgRoles
            if not (appliedRoles.tank or appliedRoles.healer or appliedRoles.dps)
            then -- edge case: assume dps for applicants with 0 roles selected.
                appliedRoles.dps = true
            end;
            if not ((applicants.RoleFilters.DPS and appliedRoles.dps)
                or (applicants.RoleFilters.TANK and  appliedRoles.tank)
                or (applicants.RoleFilters.HEALER and appliedRoles.healer)
            ) then return false end;
        end
        if applicants.ClassFilters.Enabled then
            local classID = CLASS_ID_BY_FILE[applicant.classFilename]
            if not applicants.ClassFilters.SelectedByClassID[classID] then return false end
        end
    else -- premade group
        local premadeGroups = Addon.accountDB.PremadeGroups
        if not premadeGroups.Enabled then return false end
        local numMembers = resultData.numMembers
        if premadeGroups.MemberCounts.Enabled then
            local setting = premadeGroups.MemberCounts
            -- note: don't do the `meetsSettingCountRequirements` edge case check for member counts
            if setting.Minimum and numMembers < setting.Minimum then return false end
            if setting.Maximum and numMembers > setting.Maximum then return false end
        end
        local roleCounts = C_LFGList.GetSearchResultMemberCounts(resultID)
        if premadeGroups.TankCounts.Enabled then
            local setting = premadeGroups.TankCounts
            if not meetsSettingCountRequirements(setting, roleCounts.TANK) then return false end
        end
        if premadeGroups.HealerCounts.Enabled then
            local setting = premadeGroups.HealerCounts
            if not meetsSettingCountRequirements(setting, roleCounts.HEALER) then return false end
        end
        if premadeGroups.DamagerCounts.Enabled then
            local setting = premadeGroups.DamagerCounts
            if not meetsSettingCountRequirements(setting, roleCounts.DAMAGER) then return false end
        end
    end
    return true
end

local GetClassColor = function(classID)
    assert(classID, "usage: GetClassColor(classID) or GetClassColor(classFile)")
    if type(classID) == "string" then classID = CLASS_ID_BY_FILE[classID] end
    assert(classID, "classID not found for classFile: ", CLASS_ID_BY_FILE)
    local classInfo = C_CreatureInfo.GetClassInfo(classID)
    assert(classInfo, "classInfo not found for classID: ", classID)
    return (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classInfo.classFile])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.classFile]);
end
local GetColoredClassNameByID = function(classID, useDisabledColor)
    local classInfo = C_CreatureInfo.GetClassInfo(classID)
    assert(classInfo, "classInfo not found for classID: ", classID)
    local color =  (useDisabledColor and DISABLED_FONT_COLOR)
                or (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classInfo.classFile])
                or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.classFile]);
    local displayStr = color and color:WrapTextInColorCode(classInfo.className) or classInfo.className;
    return displayStr
end
local getDebouncedFunctionHandle = function(func, seconds)
    local debounce;
    local func = function(...) func(...); debounce = nil; end
    return function(...)
        if debounce then debounce:Cancel() end;
        if select(1, ...) then debounce = C_Timer.NewTimer(seconds, GenerateClosure(func, ...));
        else debounce = C_Timer.NewTimer(seconds, func) end;
    end;
end
--- Inplace sort, Only using default blizzard one for now
local SortLFGListResults = function(results)
    local sortFunc = LFGBrowseUtil_SortSearchResults;
    sortFunc(results); return results
end
--------------------------------------------------------------------------------
-- LFGList Hook Module
--------------------------------------------------------------------------------
-- Connects the filters to react to updates to the LFGList UI, and attaches the filters panel UI

local LFGListHookModule = { isInitialized = false }
function LFGListHookModule.AttachToGroupFinderUI()
    if not isClassicEra or LFGListHookModule.isInitialized then return end
    assert(Addon.PanelFrame and Addon.PanelFrame.ToggleButton, "Required Addon Frames not found", Addon)
    assert(LFGBrowseFrame.OptionsButton, "LFGBrowseFrame.OptionsButton not found")
    Addon.GlobalToggle:SetParent(LFGBrowseFrame)
    Addon.GlobalToggle:SetPoint("RIGHT", LFGBrowseFrame.OptionsButton, "LEFT", -5, 0)
    Addon.PanelFrame:SetParent(LFGBrowseFrame)
    Addon.PanelFrame:ClearAllPoints()
    Addon.PanelFrame:SetPoint("BOTTOMLEFT", LFGBrowseFrame, "BOTTOMRIGHT", -30, 76)
    Addon.PanelFrame:SetShown(not Addon.accountDB.GlobalDisable)
    local LFGParentFrameCloseButton do
        for _, frame in ipairs({LFGParentFrame:GetChildren()}) do
            if frame:GetObjectType() == "Button"
            and frame:GetNormalTexture() -- find close button texture
            and frame:GetNormalTexture():GetTextureFileID() == 130832 then
                LFGParentFrameCloseButton = frame
                break;
            end
        end
    end
    assert(LFGParentFrameCloseButton, "LFGParentFrameCloseButton not found")
    Addon.PanelFrame.ToggleButton:SetParent(LFGBrowseFrame)
    Addon.PanelFrame.ToggleButton:SetPoint("RIGHT", LFGParentFrameCloseButton, "LEFT", 10, 0)
    Addon.PanelFrame.ToggleButton:SetSize(LFGParentFrameCloseButton:GetSize())
    Addon.PanelFrame.ToggleButton:SetShown(not Addon.accountDB.GlobalDisable)

    -- Hook results filtering callbacks to blizzard updates to the LFGList UI
    if isClassicEra then
        --note: more accurate updates if we Hook UpdateResults instead of UpdateResultList.
        assert(LFGBrowseFrame.UpdateResults, "LFGBrowseFrame.UpdateResults not found")
        hooksecurefunc(LFGBrowseFrame, "UpdateResults", function(...)
            if Addon.accountDB.GlobalDisable then return end
            LFGListHookModule.UpdateResultList(...)
        end)
        EventFrame:RegisterEventCallback("LFG_LIST_SEARCH_RESULT_UPDATED", function(_, resultID)
            if Addon.accountDB.GlobalDisable then return end
            local result = C_LFGList.GetSearchResultInfo(resultID)
            if result and result.isDelisted and Addon.accountDB.HideDelisted then
                --note: data provider can be nil after: failed search, update during a search, empty searches.
                local dataProvider = LFGBrowseFrame.ScrollBox:GetDataProvider()
                if not dataProvider then return end;
                dataProvider:RemoveByPredicate(function(data)
                    return data.resultID == resultID
                end)
            end
        end)
        LFGListHookModule.SetupModifiedEntryFrames()
        LFGListHookModule.SetupModifiedDropdowns()
        LFGListHookModule.isInitialized = true
    end
end

function LFGListHookModule.UpdateResultList(_, abortHookCallback)
    if Addon.accountDB.GlobalDisable then return end
    if abortHookCallback then return end
    local numResults, results = C_LFGList.GetSearchResults();
    if numResults == 0 then return end; -- blizz ui takes care of this
    local numFiltered, filtered = 0, {}
    for _, resultID in ipairs(results) do
        if ShouldFilterForResultID(resultID) then
            numFiltered = numFiltered + 1
            filtered[numFiltered] = resultID
        end
    end
    LFGBrowseFrame.results = SortLFGListResults(filtered);
    LFGBrowseFrame.totalResults = numFiltered;
    abortHookCallback = true; -- hack: important not to inf loop xD
    LFGBrowseFrame:UpdateResults(abortHookCallback)
end

LFGListHookModule.RefreshScrollView = getDebouncedFunctionHandle(function()
    -- call blizzards UpdateResultList to reset dataprovider/ui.
    if not LFGListHookModule.isInitialized then return end
    if LFGBrowseFrame then LFGBrowseFrame:UpdateResultList() end;
end, 0) -- debounce calls within the same game tick

function LFGListHookModule.SetupModifiedEntryFrames()
    -- The way the addon is setup atm, we dont stop blizzard from updating the result list ui, instead we just listen for calls and do our work after.
    local CLASS_ICON_ATLASES = {}
    for _, classFile in ipairs(CLASS_FILE_BY_ID) do
        CLASS_ICON_ATLASES[classFile] = "groupfinder-icon-class-"..string.lower(classFile);
    end
    local LVL_TEXT_PATTERN = (LEVEL_ABBR.." %d") -- LFD_LEVEL_FORMAT_SINGLE or (LEVEL_ABBR.." %d")
    local ResultBGColorPresets = { blizzard = { 1, 1, 1, 0.02 }; addon = { 0.3, 0.3, 0.3, 0.275 }; }
    local EntryFrameChildRegionBlizzAnchors = { ---@type {[frame]:{region: AnchorMixin[]}}
        -- note: relativeTo can be `nil` to anchor to entry or a parentKey for a entry child region
        ActivityName = { CreateAnchor("BOTTOMLEFT", nil, "BOTTOMLEFT", 10, 2) },
        DataDisplay = { CreateAnchor("RIGHT", nil, "RIGHT", -2, -1) },
        PartyIcon = { CreateAnchor("TOPLEFT", nil, "TOPLEFT", 8, -4) },
        NewPlayerFriendlyIcon = { CreateAnchor("LEFT", "ClassIcon", "RIGHT", 8, -1) },
        ClassIcon = { CreateAnchor("BOTTOMLEFT", "Level", "BOTTOMRIGHT", 3, -1) },
        Level = { CreateAnchor("BOTTOMLEFT", "Name", "BOTTOMRIGHT", 4, -1) },
    }
    local fontStringPool = CreateUnsecuredFontStringPool(UIParent, "ARTWORK", nil, "GameFontNormalTiny")
    local partyIconOffset = 18 - 1; -- iconSize - x offset from name
    local listingNoteExactWidth = 150;
    local nameFontStringWidth = 85;
    local entryDefaultWidth = 312;
    local listingNoteRightInset = entryDefaultWidth - listingNoteExactWidth;
    local EntryNameWidthMatcher = {
        registry = {}; current = 0; max = nameFontStringWidth;
        Register = function(self, fontString)
            local incoming = min(fontString:GetUnboundedStringWidth(), self.max)
            if self.max then incoming = min(incoming, self.max) end
            if incoming > self.current then self:UpdateWidths(incoming) end
            self.registry[fontString] = true
            fontString:SetWidth(self.current)
        end,
        UpdateWidths = function(self, width)
            for frame, _ in pairs(self.registry) do frame:SetWidth(width) end
            self.current = width
        end,
        Reset = function(self)
            for frame, _ in pairs(self.registry) do self.registry[frame] = nil end
            self.current = 0
        end
    }
    local SoloPlayerLevelOffsetHandler = {
        registry = {}; shouldOffset = false;
        offset = partyIconOffset;
        Register = function(self, region)
            if not self.shouldOffset then self.registry[region] = true;
            else self:UpdateRegion(region) end
        end,
        UnRegister = function(self, region) self.registry[region] = nil end,
        EnableOffsets = function(self)
            self.shouldOffset = true;
            if not next(self.registry) then return end
            for region, _ in pairs(self.registry) do self:UpdateRegion(region) end
            self.registry = {}
        end,
        UpdateRegion = function(self, region) region:AdjustPointsOffset(self.offset, 0) end,
        Reset = function(self) self.shouldOffset = false; self.registry = {} end,
    }
    --------------------------------------------------------------------------------
    -- Entry frame modifications
    --------------------------------------------------------------------------------
    ---@class EntryModMixin: LFGBrowseSearchEntryTemplate
    local EntryModMixin = {};
    -- One time setups: anything that wont get modified by _Update (ours or blizzard). If unsure just put in Mixin.OnUpdate
    function EntryModMixin:Init()
        if Addon.accountDB.GlobalDisable then return end;
        if self.ListingNote then return end;
        self.ListingNote = fontStringPool:Acquire()
        self.ListingNote:SetParent(self)
        self.ListingNote:SetPoint("BOTTOMLEFT", 8, 1)
        self.ListingNote:SetPoint("BOTTOMRIGHT", -listingNoteRightInset, 1)
        self.ListingNote:SetAlpha(.9)
        self.ListingNote:SetHeight(self.ActivityName:GetHeight())
        self.ListingNote:SetMaxLines(1); self.ListingNote:SetJustifyH("LEFT")
        -- center the class icon for applicants
        self.ClassIcon:ClearAllPoints()
        self.ClassIcon:SetPoint("LEFT", self.Level, "RIGHT", 5, 0)
        -- make new player friendly icon less obtrusive
        self.NewPlayerFriendlyIcon:SetScale(0.8)
        -- move data display out of the middle to the topright (makes room for activityName)
        self.DataDisplay:ClearAllPoints()
        self.DataDisplay:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -2)
    end
    function EntryModMixin:OnUpdate()
        if not self.ListingNote then EntryModMixin.Init(self) end;
        if self.DataDisplay.Comment:IsShown() then
            -- use blizz-like layout for `Custom` category entries
            EntryModMixin.Reset(self)
            self.NewPlayerFriendlyIcon:SetPoint("LEFT", self.Name, "RIGHT", 2, 0)
            local r,g,b = NORMAL_FONT_COLOR:GetRGB()
            self.DataDisplay.Comment:SetTextColor(r, g, b, .9)
            return;
        end
        local resultData = C_LFGList.GetSearchResultInfo(self.resultID)
        if not resultData then return end;
        local isSolo = resultData.numMembers == 1
        local activityColor = GRAY_FONT_COLOR
        local leaderInfo = C_LFGList.GetSearchResultLeaderInfo(self.resultID)
        if leaderInfo and leaderInfo.level and leaderInfo.classFilename then
            self.Level:SetText(LVL_TEXT_PATTERN:format(leaderInfo.level));
            self.Level:Show()
            self.Level:SetPoint("BOTTOMLEFT", self.Name, "BOTTOMRIGHT", 2, 0)
            self.ClassIcon:SetAtlas(CLASS_ICON_ATLASES[leaderInfo.classFilename], false);
            self.ClassIcon:Show()
        end
        self.NewPlayerFriendlyIcon:ClearAllPoints()
        self.NewPlayerFriendlyIcon:SetPoint("RIGHT", self.DataDisplay.RoleCount.TankCount, "LEFT", 5, 0)
        self.PartyIcon:ClearAllPoints()
        self.ActivityName:ClearAllPoints()
        local listingNote = resultData.comment
        if listingNote and listingNote ~= "" then
            self.ListingNote:Show()
            self.ListingNote:SetText(listingNote)
            self.PartyIcon:SetPoint("TOPLEFT", 8, -4)
            self.ActivityName:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", -listingNoteRightInset + 4, 1)
            self.ActivityName:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -5, 1)
            self.ActivityName:SetJustifyH("RIGHT")
        else
            self.ListingNote:Hide()
            self.ListingNote:SetText("")
            self.PartyIcon:SetPoint("LEFT", 8, -1)
            self.ActivityName:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 1)
            self.ActivityName:SetJustifyH("LEFT")
        end
        EntryNameWidthMatcher:Register(self.Name)
        if isSolo then
            SoloPlayerLevelOffsetHandler:Register(self.Level)
        else
            SoloPlayerLevelOffsetHandler:UnRegister(self.Level)
            SoloPlayerLevelOffsetHandler:EnableOffsets()
        end
        if not resultData.isDelisted then -- get correct activity color
            if resultData.hasSelf then
                activityColor = LIGHTGREEN_FONT_COLOR
            elseif C_LFGList.HasActiveEntryInfo() then
                local activeEntryInfo = C_LFGList.GetActiveEntryInfo()
                for _, activityID in ipairs(activeEntryInfo.activityIDs) do
                    if activityID == resultData.activityID then
                        activityColor = BRIGHTBLUE_FONT_COLOR
                        break;
                    end
                end
            end
        end
        self.Level:SetTextColor((resultData.isDelisted
            and LFG_DISABLED_FONT_COLOR or GRAY_FONT_COLOR
        ):GetRGB())
        self.Name:SetTextColor((resultData.isDelisted
            and LFG_DISABLED_FONT_COLOR or GetClassColor(leaderInfo.classFilename)
        ):GetRGB())
        self.ActivityName:SetTextColor((resultData.isDelisted
            and LFG_DISABLED_FONT_COLOR or activityColor
        ):GetRGB())
        self.ListingNote:SetTextColor((resultData.isDelisted
            and LFG_DISABLED_FONT_COLOR or NORMAL_FONT_COLOR
        ):GetRGB())
        self.ResultBG:SetColorTexture(unpack(resultData.isDelisted
            and ResultBGColorPresets.blizzard or ResultBGColorPresets.addon
        ))
    end
    -- Called whenever a frame is released by the ScrollBoxView
    function EntryModMixin:OnRelease(...) end
    -- Reset to frame blizzard layout
    -- note: some mods may be deferred to be laid out by blizzard in their _Update
    function EntryModMixin:Reset()
        if not self.ListingNote then return end
        self.NewPlayerFriendlyIcon:ClearAllPoints()
        self.NewPlayerFriendlyIcon:SetScale(1)
        -- Restore the original texture anchors set by blizzard ui
        for regionName, anchors in pairs(EntryFrameChildRegionBlizzAnchors) do
            local region = self[regionName]
            assert(region, "Region not found: ", regionName, self)
            region:ClearAllPoints()
            for _, anchor in ipairs(anchors) do
                local relativeTo = (anchor.relativeTo and self[anchor.relativeTo]) or self
                region:SetPoint(anchor.point, relativeTo,
                    anchor.relativePoint,
                    anchor.x or 0, anchor.y or 0
                );
            end
        end
        self.ResultBG:SetColorTexture(unpack(ResultBGColorPresets.blizzard))
        self.ActivityName:SetJustifyH("LEFT")
        fontStringPool:Release(self.ListingNote)
        self.ListingNote = nil;
    end

    -- fix for `nil` resultInfo blizzard error. Occurs when event received just after `C_LFGList.Search`
    hooksecurefunc("LFGBrowseSearchEntry_Init", function(entry)
        local ModifiedEventHandler = function(self, event, resultID)
            if event ~= "LFG_LIST_SEARCH_RESULT_UPDATED"
            or self.resultID ~= resultID
            or not C_LFGList.GetSearchResultInfo(resultID) then return;
            else LFGBrowseSearchEntry_OnEvent(self, event, resultID) end;
        end
        entry:SetScript("OnEvent", ModifiedEventHandler)
    end)
    --------------------------------------------------------------------------------
    -- Entry frame data display modifications
    --------------------------------------------------------------------------------
    local SIMPLE_ROLE_ATLASES = {
        TANK = "groupfinder-icon-role-micro-tank",
        HEALER = "groupfinder-icon-role-micro-heal",
        DAMAGER = "groupfinder-icon-role-micro-dps",
    };
    local ROLE_COUNT_REGION_PARENT_KEYS = {
        "TankCount", "HealerCount", "DamagerCount", "TankIcon", "HealerIcon", "DamagerIcon"
    };
    local ROLE_DISPLAY_ORDER = {"TANK", "HEALER", "DAMAGER"}
    local CUSTOM_ICON_SIZE = 17
    local CUSTOM_ICON_ROLE_SIZE = CUSTOM_ICON_SIZE * 0.70
    local ROLE_COUNT_DEFAULT_WIDTH = 17
    local RIGHT_ICON_DEFAULT_INSET = 11
    local RIGHT_ICON_MODDED_INSET = 6
    local ROLES_TEXT_DEFAULT_INSET = 90
    local ROLE_COUNT_ICON_X_OFFSET = 3
    local ROLE_COUNT_2_DIGIT_WIDTH do
        local fs = fontStringPool:Acquire() ---@type FontString
        fs:SetFontObject("GameFontHighlightSmall"); fs:SetText("00");
        ROLE_COUNT_2_DIGIT_WIDTH = ceil(fs:GetUnboundedStringWidth());
        fontStringPool:Release(fs)
    end

    -- Reduces spacing between counts and role icons in the RoleCount data display.
    ---@param display LFGListGroupDataDisplayTemplate
    ---@param justifyH JustifyHorizontal
    local modifyRoleCountDisplay = function(display, justifyH, countWidth, iconOffset)
        for _, key in ipairs(ROLE_COUNT_REGION_PARENT_KEYS) do
            local region = display.RoleCount[key]
            -- assert(region, "RoleCount child region not found: ", key, display.RoleCount)
            if key:find("Icon") then
                if key ~= "DamagerIcon" then region:AdjustPointsOffset(iconOffset, 0) end;
            else
                region:SetWidth(countWidth)
                region:SetJustifyH(justifyH)
            end
        end
    end
    -- Set up the `CustomEnumerate` data display frame for showing class colors
    local CustomEnumeratePool = CreateFramePool("Frame", LFGBrowseFrame, nil, nil, nil,
        function(display) -- creationFunc (called when new frame created and added to pool)
            local display = display; ---@class CustomEnumerate: Frame
            display.Icons = {}
            for i = 1, 5 do
                local Icon = CreateFrame("Frame", nil, display)
                local roleTex = Icon:CreateTexture(nil, "ARTWORK")
                local classBg = Icon:CreateTexture(nil, "BACKGROUND")
                local bgMask = Icon:CreateMaskTexture(nil, "BACKGROUND")
                Icon:SetSize(CUSTOM_ICON_SIZE, CUSTOM_ICON_SIZE)
                roleTex:SetSize(CUSTOM_ICON_ROLE_SIZE, CUSTOM_ICON_ROLE_SIZE)
                roleTex:SetPoint("CENTER")
                classBg:SetAllPoints()
                bgMask:SetAllPoints(classBg)
                bgMask:SetAtlas("CircleMaskScalable", false)
                classBg:AddMaskTexture(bgMask)
                Icon.SetRole = function(_, role) roleTex:SetAtlas(SIMPLE_ROLE_ATLASES[role], false) end
                Icon.SetClassColor = function(_, classID)
                    local r, g, b = GetClassColor(classID):GetRGB()
                    classBg:SetColorTexture(r, g, b, 0.85)
                end
                Icon.SetEmptySlot = function(_)
                    roleTex:SetAtlas("groupfinder-icon-emptyslot", false)
                    classBg:SetColorTexture(0, 0, 0, 0);
                end
                Icon.SetDesaturated = function(_, desaturated)
                    roleTex:SetDesaturated(desaturated)
                    classBg:SetDesaturated(desaturated)
                end
                Icon.SetAlpha = function(_, alpha)
                    roleTex:SetAlpha(alpha)
                    classBg:SetAlpha(alpha ~= 1 and 0.2 or 1)
                end
                display.Icons[i] = Icon
                if i == 1 then display.Icons[i]:SetPoint("RIGHT", -RIGHT_ICON_MODDED_INSET, 0);
                else display.Icons[i]:SetPoint("RIGHT", display.Icons[i-1], "LEFT", -0.75, 0) end;
            end
            display:Hide()
        end
    );
    ---@class DataDisplayModMixin: LFGListGroupDataDisplayTemplate
    local DataDisplayModMixin = {};
    function DataDisplayModMixin:Init()
        local entry = self:GetParent() --[[@as LFGBrowseSearchEntryTemplate]]
        assert(entry and entry.DataDisplay == self, "Parent entry frame for data display not found", self)
        if self.CustomEnumerate then return end;
        local CustomEnumerate = CustomEnumeratePool:Acquire();
        CustomEnumerate:SetParent(entry)
        CustomEnumerate:SetAllPoints(self.Enumerate)
        modifyRoleCountDisplay(self, "RIGHT", ROLE_COUNT_2_DIGIT_WIDTH, ROLE_COUNT_ICON_X_OFFSET)
        -- line up RoleCount with CustomEnumerate
        self.RoleCount.DamagerIcon:SetPoint("RIGHT", -RIGHT_ICON_MODDED_INSET, 0)
        -- line up Solo display. 48 = 3 * (16 width icons) | + right padding
        self.Solo.RolesText:SetPoint("RIGHT", -(48 + RIGHT_ICON_MODDED_INSET + 8), 0)
        self.CustomEnumerate = CustomEnumerate
    end
    -- see: `Interface\AddOns\Blizzard_GroupFinder_VanillaStyle\Blizzard_LFGVanilla_Browse.lua:689`
    -- for args
    function DataDisplayModMixin:OnUpdate(displayType, maxNumPlayers, _, disabled, isSolo)
        if not self.CustomEnumerate then return end;
        self.CustomEnumerate:Hide()
        local entry = self:GetParent() --[[@as LFGBrowseSearchEntryTemplate]]
        if not entry.resultID then return end;
        if isSolo then return end
        if displayType == Enum.LFGListDisplayType.RoleEnumerate then
            local resultData = C_LFGList.GetSearchResultInfo(entry.resultID);
            if not resultData then return end;
            self.CustomEnumerate:Show()
            self.Enumerate:Hide() -- hide original
            -- bugfix: anchor custom display on update, instead of on init
            for i = 1, #self.CustomEnumerate.Icons do
                if i > maxNumPlayers then self.CustomEnumerate.Icons[i]:Hide()
                else
                    self.CustomEnumerate.Icons[i]:Show()
                    self.CustomEnumerate.Icons[i]:SetDesaturated(disabled)
                    self.CustomEnumerate.Icons[i]:SetAlpha(disabled and 0.5 or 1.0)
                end
            end
            local numMembers = resultData.numMembers;
            local displayData = {};--- {[lfgRole]: playerInfo[]}
            for i = 1, numMembers do
                local memberInfo = C_LFGList.GetSearchResultPlayerInfo(entry.resultID, i);
                if memberInfo then
                    local role = memberInfo.assignedRole or "DAMAGER";
                    displayData[role] = displayData[role] or {};
                    tinsert(displayData[role], memberInfo);
                end
            end
            --Note that icons are numbered from right (1) to left (5)
            local iconIndex = maxNumPlayers; -- starts at leftmost icon
            for roleIdx = 1, #ROLE_DISPLAY_ORDER do
                local role = ROLE_DISPLAY_ORDER[roleIdx];
                local numRolePlayers = displayData[role] and #displayData[role] or 0;
                for i = 1, numRolePlayers do
                    local icon =self.CustomEnumerate.Icons[iconIndex];
                    icon:Show()
                    icon:SetRole(role)
                    local class = displayData[role][i].classFilename;
                    icon:SetClassColor(CLASS_ID_BY_FILE[class])
                    iconIndex = iconIndex - 1;
                    if ( iconIndex < 1 ) then
                        return;
                    end
                end
            end
            for i = 1, iconIndex do self.CustomEnumerate.Icons[i]:SetEmptySlot() end
        end
    end
    function DataDisplayModMixin:OnRelease() end
    function DataDisplayModMixin:Reset()
        if not self.CustomEnumerate then return end;
        modifyRoleCountDisplay(self, "CENTER", ROLE_COUNT_DEFAULT_WIDTH, -ROLE_COUNT_ICON_X_OFFSET)
        self.RoleCount.DamagerIcon:SetPoint("RIGHT", -RIGHT_ICON_DEFAULT_INSET, 0)
        self.Solo.RolesText:SetPoint("RIGHT", -ROLES_TEXT_DEFAULT_INSET, 0)
        CustomEnumeratePool:Release(self.CustomEnumerate)
        self.CustomEnumerate = nil;
    end
    local scrollBox = LFGBrowseFrame.ScrollBox ---@type ScrollBoxListMixin
    local scrollView = scrollBox:GetView() ---@type ScrollBoxListViewMixin
    local modifiedFrames = {}
    -- local cbrOwner = Addon
    -- local CallbackRegistry_OnReleasedFrame = function (_, frame, elementData)
    --     if Addon.accountDB.GlobalDisable then return end;
    --     EntryModMixin.OnRelease(frame, elementData)
    -- end
    local OnDataProviderReassigned = function(_, elementData)
        -- if Addon.accountDB.GlobalDisable then return end;
        EntryNameWidthMatcher:Reset()
        SoloPlayerLevelOffsetHandler:Reset()
    end
    local OnUpdateFrame = function(frame)
        if Addon.accountDB.GlobalDisable then return end;
        if not modifiedFrames[frame] then
            EntryModMixin.Init(frame)
            modifiedFrames[frame] = true
        end
        EntryModMixin.OnUpdate(frame)
    end
    local OnUpdateFrameDataDisplay = function(display, ...)
        if Addon.accountDB.GlobalDisable then return end;
        if not display.CustomEnumerate then DataDisplayModMixin.Init(display) end;
        DataDisplayModMixin.OnUpdate(display, ...)
    end
    scrollView:RegisterCallback("OnDataProviderReassigned", OnDataProviderReassigned)
    -- scrollView:RegisterCallback("OnReleasedFrame", CallbackRegistry_OnReleasedFrame, cbrOwner)
    hooksecurefunc("LFGBrowseSearchEntry_Update", OnUpdateFrame)
    hooksecurefunc("LFGBrowseGroupDataDisplay_Update", OnUpdateFrameDataDisplay)
    local defaultElementExtent = scrollView:GetElementExtent()
    local scrollViewPadding = scrollView:GetPadding()
    local onGlobalAddonToggle = function(_, isChecked)
        local isAddonDisabled = not isChecked
        if isAddonDisabled then
            for frame, _ in pairs(modifiedFrames) do
                -- EntryModMixin.OnRelease(frame) unused atm
                EntryModMixin.Reset(frame)
                DataDisplayModMixin.Reset(frame.DataDisplay)
            end
            wipe(modifiedFrames)
            scrollView:SetElementExtent(defaultElementExtent)
            scrollViewPadding:SetSpacing(0)
            scrollViewPadding:SetTop(0)
            EntryNameWidthMatcher:Reset()
            SoloPlayerLevelOffsetHandler:Reset()
        else
            scrollView:SetElementExtent(defaultElementExtent + 2)
            scrollViewPadding:SetSpacing(1)
            scrollViewPadding:SetTop(4)
        end
        LFGListHookModule.RefreshScrollView()
    end
    Addon.GlobalToggle.Checkbox:RegisterCallback("OnValueChanged", onGlobalAddonToggle)
    onGlobalAddonToggle(nil, Addon.GlobalToggle.Checkbox:GetChecked())
end

function LFGListHookModule.SetupModifiedDropdowns()
    if not isClassicEra then return end
    local UIDropdownMenuButtonHeight = 16
    local UIDropdownButtonHeight = 24
    local BlizzardActivityDD = LFGBrowseFrame.ActivityDropDown;
    local BlizzardCategoryDD = LFGBrowseFrame.CategoryDropDown;

    local AddonCategoryDD = CreateFrame("DropdownButton",
        (TOC_NAME.."CategoryDropdown"), LFGBrowseFrame, "WowStyle1DropdownTemplate"
    );
    -- DropdownSelectionTextMixin.OnLoad(AddonCategoryDD)

    local AddonActivityDD = CreateFrame("DropdownButton",
        (TOC_NAME.."ActivityDropdown"), LFGBrowseFrame, "WowStyle1DropdownTemplate"
    );
    Mixin(AddonActivityDD, DropdownSelectionTextMixin)
    DropdownSelectionTextMixin.OnLoad(AddonActivityDD)
    AddonActivityDD.ResetButton = CreateFrame("Button", nil, AddonActivityDD)
    AddonActivityDD.ResetButton:SetNormalTexture("common-search-clearbutton")
    AddonActivityDD.ResetButton:SetSize(13, 13)
    AddonActivityDD.ResetButton:Hide();
    AddonActivityDD.ResetButton:SetPoint("CENTER", AddonActivityDD, "TOPLEFT", 3, -2)
    Mixin(AddonActivityDD, WowFilterButtonMixin)
    WowFilterButtonMixin.OnLoad(AddonActivityDD)

    ---@param dropdown DropdownButton? specifies a dropdown to refresh. If nil, refreshes both
    local refreshAddonDropdowns = function(dropdown)
        local dropdowns = dropdown and {dropdown} or {AddonCategoryDD, AddonActivityDD}
        for _, dropdown in ipairs(dropdowns) do
            -- note: i think `OnMenuResponse` might do this too
            dropdown:GenerateMenu() -- refresh menu description
            dropdown:SignalUpdate() -- update header button text
        end
    end
    local selectedCategoryID = 0; -- 0 is a placeholder ID for None or Self Listings
    -- Tracks selection state of ALL activities, regardless of availability or category
    local selectedActivitiesCache = setmetatable({}, {
        __index = function(self, key) rawset(self, key, false); return false end
    });
    -- Cached implementation of `LFGUtil_GetFilteredActivities` (avoids CVarCBR taint)
    ---@type fun(category: number, group: number?): table
    local getAvailableActivities do -- possibly called multiple times in the same frame
        local cache = {}
        getAvailableActivities = function(category, group)
            if C_CVar.GetCVarBool("disableSuggestedLevelActivityFilter")
            then return C_LFGList.GetAvailableActivities(category, group) end
            local key = ("%s_%s"):format(tostring(category), group and tostring(group) or "")
            if not cache[key] then
                local activities = C_LFGList.GetAvailableActivities(category, group);
                local activeEntryInfo = C_LFGList.GetActiveEntryInfo();
                local playerLevel = UnitLevel("player");
                local validActivities = {};
                for _, activityID in ipairs(activities) do
                    local activityInfo = C_LFGList.GetActivityInfoTable(activityID);
                    local isActiveEntryActivity = activeEntryInfo and tContains(activeEntryInfo.activityIDs, activityID)
                    local inLevelRange = (activityInfo.minLevelSuggestion > 0 and activityInfo.minLevelSuggestion <= playerLevel)
                        and (activityInfo.maxLevelSuggestion == 0 or activityInfo.maxLevelSuggestion >= playerLevel)
                    if isActiveEntryActivity or inLevelRange then
                        tinsert(validActivities, activityID)
                    end
                end
                cache[key] = validActivities
            end
            return cache[key];
        end
        local clearCache = function() _G.wipe(cache) end
        EventFrame:RegisterEventCallback("LFG_LIST_AVAILABILITY_UPDATE", clearCache)
        EventFrame:RegisterEventCallback("PLAYER_LEVEL_UP", clearCache)
    end
    -- Helper for getting the selected activities for the current selected lfg category
    local getSelectedActivitiesArray = function()
        local availableActivities = getAvailableActivities(selectedCategoryID)
        local selected = {}
        for _, activityID in ipairs(availableActivities) do
            if selectedActivitiesCache[activityID] then tinsert(selected, activityID) end
        end
        return selected
    end
    -- ActivityID custom sort function
    local Activity_SortByLevel do
        local orderRules
        if isSeasonOfDiscovery then
            orderRules = { "minLevelSuggestion", "maxLevelSuggestion", "orderIndex", "maxNumPlayers", "fullName" }
        else orderRules = { "maxNumPlayers", "minLevelSuggestion", "maxLevelSuggestion", "fullName" } end
        Activity_SortByLevel  = function(aID, bID)
            local aInfo, bInfo = C_LFGList.GetActivityInfoTable(aID), C_LFGList.GetActivityInfoTable(bID)
            -- edge case: treat LBRS (812) as a 10m
            if aID == 812 then aInfo.maxNumPlayers = 10 end; if bID == 812 then bInfo.maxNumPlayers = 10 end
            -- edge case: order Cathedral (828) before RFD (806)
            if (aID == 828 and bID == 806) or (aID == 806 and bID == 828) then return aID > bID end
            for _, ruleKey in ipairs(orderRules) do
                local aVal, bVal = aInfo[ruleKey], bInfo[ruleKey]
                if aVal ~= bVal then return aVal < bVal end
            end
            return aID < bID
        end
    end
    local LFGBrowse_DoSearch = function() -- reimplemented to avoid taint
        if (not LFGBrowseFrame.searching) then
            local categoryID = selectedCategoryID
            if (categoryID > 0) then
                local activityIDs =  getSelectedActivitiesArray()
                -- If we have no activities selected in the filter, search for everything in this category.
                if (#activityIDs == 0) then activityIDs = getAvailableActivities(categoryID) end;
                local filter = 0;
                local preferredFilters = 0;
                local languageFilter = nil;
                local searchCrossFactionListings = false;
                local advancedFilter = nil;
                C_LFGList.Search(categoryID, filter, preferredFilters, languageFilter, searchCrossFactionListings, advancedFilter, activityIDs);
                LFGBrowseFrame.searching = true;
                LFGBrowseFrame.searchFailed = false;
                LFGBrowseFrame:UpdateResults();
            end
        end
    end
    --- Reimplemented version `LFGBrowseMixin.SearchActiveEntry` to not taint blizzard DD's
    local updateToActiveEntry = function(skipSearch)
        local activeEntry = C_LFGList.GetActiveEntryInfo()
        if not activeEntry then return end
        -- blizzard resets the activity selections with only the active entry ones
        -- We will keep them instead and just add the ones for the active entry
        local bestCategory = 0
        for _, activityID in ipairs(activeEntry.activityIDs) do
            selectedActivitiesCache[activityID] = true
            if bestCategory == 0 then
                local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
                bestCategory = activityInfo and activityInfo.categoryID or 0
            end
        end
        if bestCategory > 0 then
            selectedCategoryID = bestCategory
            refreshAddonDropdowns()
        end
        if skipSearch == true then return end
        LFGBrowse_DoSearch()
    end
    local setVisibleDropdowns = function(isAddonDisabled)
        BlizzardActivityDD:SetShown(isAddonDisabled)
        BlizzardCategoryDD:SetShown(isAddonDisabled)
        AddonActivityDD:SetShown(not isAddonDisabled)
        AddonCategoryDD:SetShown(not isAddonDisabled)
    end
    --------------------------------------------------------------------------------
    -- Category Dropdown
    --------------------------------------------------------------------------------

    local isCategorySelected = function(categoryID) return selectedCategoryID == categoryID end
    local onCategorySelected = function(categoryID)
        selectedCategoryID = categoryID
        refreshAddonDropdowns(AddonActivityDD)
        LFGBrowse_DoSearch()
    end
    ---@param rootDescription RootMenuDescriptionProxy
    local categoryDropdownMenuGenerator = function(_, rootDescription)
        rootDescription:SetTag(CATEGORY_DROPDOWN_TAG)
        local playerHasActiveEntry = C_LFGList.HasActiveEntryInfo()
        local categories = C_LFGList.GetAvailableCategories()
        local numCategories = #categories
        if numCategories == 0 and not playerHasActiveEntry then
            rootDescription:CreateRadio(NONE, isCategorySelected, onCategorySelected, 0)
            return;
        end
        if playerHasActiveEntry then
            rootDescription:CreateButton(LFG_SELF_LISTING, updateToActiveEntry)
        end
        for i = 1, numCategories do
            local categoryID = categories[i]
            local activities = getAvailableActivities(categoryID)
            if #activities > 0 then
                local info = C_LFGList.GetLfgCategoryInfo(categoryID)
                rootDescription:CreateRadio(info.name, isCategorySelected, onCategorySelected, categoryID)
            end
        end
        for _, desc in rootDescription:EnumerateElementDescriptions() do
            -- reduce menu button font size and compact their size
           desc:SetFinalInitializer(function(button)
                button.fontString:SetFontObject("GameFontHighlightSmallLeft")
                local left, right = nil, button.fontString:GetRight();
                if button.leftTexture1 then
                    left = button.leftTexture1:GetLeft()
                else left = button.fontString:GetLeft() end
                button:SetSize((right-left), UIDropdownMenuButtonHeight)
            end)
        end
    end
    AddonCategoryDD:SetDefaultText(CATEGORY)
    AddonCategoryDD.Text:SetFontObject("GameFontHighlightSmallLeft")
    AddonCategoryDD:SetPoint("BOTTOMLEFT", LFGBrowseFrame.ScrollBox, "TOPLEFT", 6, 9.5)
    AddonCategoryDD:SetSize(115, UIDropdownButtonHeight)

    AddonCategoryDD:SetupMenu(categoryDropdownMenuGenerator)
    --------------------------------------------------------------------------------
    -- Activity Dropdown
    --------------------------------------------------------------------------------

    ----- Menu Selection API
    local isActivitySelected = function(activityID) return selectedActivitiesCache[activityID] end
    local onActivitySelected = function(activityID)
        selectedActivitiesCache[activityID] = not selectedActivitiesCache[activityID]
        LFGBrowse_DoSearch()
        return MenuResponse.Refresh
    end
    local isActivityGroupSelected = function(activityGroupID, override)
        --- note: calls from the dropdown menu will not use override. only from `onActivityGroupSelected`.
        local activitiesByGroup = override or LFGUtil_OrganizeActivitiesByActivityGroup(
            getAvailableActivities(selectedCategoryID, activityGroupID)
        );
        --- return true if any activityID selected
        for _, activityGroup in pairs(activitiesByGroup) do
            for _, activityID in ipairs(activityGroup) do
                if selectedActivitiesCache[activityID]
                then return true end
            end
        end
    end
    local onActivityGroupSelected = function(activityGroupID)
        local activitiesByGroup = LFGUtil_OrganizeActivitiesByActivityGroup(
            getAvailableActivities(selectedCategoryID, activityGroupID)
        );
        local isAnySelected = isActivityGroupSelected(activityGroupID, activitiesByGroup)
        for _, activityGroup in pairs(activitiesByGroup) do
            for _, activityID in ipairs(activityGroup) do
                selectedActivitiesCache[activityID] = not isAnySelected
            end
        end
        LFGBrowse_DoSearch()
        return MenuResponse.Refresh
    end
    ----- Menu Generator Setup
    local formatMenuButton = function(button)
        button.fontString:SetFontObject("GameFontHighlightSmallLeft")
        local left, right = button.leftTexture1:GetLeft(), nil;
        if button.arrow then-- button has submenu texture
            button.arrow:AdjustPointsOffset(-5, 0)
            right = button.arrow:GetRight();
        else right = button.fontString:GetRight() end;
        button:SetSize((right-left), UIDropdownMenuButtonHeight)
    end
    ---@param parentDesc ElementMenuDescriptionProxy|RootMenuDescriptionProxy
    local addActivityButton = function(activityID, parentDesc, shouldIndent)
        local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
        local activityName = LFGUtil_GetActivityInfoName(activityInfo)
        if shouldIndent then
           activityName = LFG_LIST_INDENT:format(activityName)
        end
        local description = parentDesc:CreateCheckbox(
            activityName, isActivitySelected, onActivitySelected, activityID
        );
        description:SetFinalInitializer(formatMenuButton)
        return description
    end
    local addActivityGroupButton = function(groupID, parentDesc)
        local activityGroupName = C_LFGList.GetActivityGroupInfo(groupID)
        if not activityGroupName
        -- the "Custom" activity's groupID (0) will return a `nil` value for GetActivityGroupInfo
        -- atm there is only one activityGroup for the related categoryID so we dont need to worry about-
        -- a submenu for this activity group. It also only has a single activity ("Custom") so we can skip-
        -- creating the usual "toggle all" button for single activity group categories
        then return end;
        local description = parentDesc:CreateCheckbox(
            activityGroupName, isActivityGroupSelected, onActivityGroupSelected, groupID
        );
        description:SetFinalInitializer(formatMenuButton)
        return description
    end
    ---@param rootDescription RootMenuDescriptionProxy
    local activityDropdownMenuGenerator = function(_, rootDescription)
        rootDescription:SetTag(ACTIVITY_DROPDOWN_TAG)
        AddonActivityDD:SetEnabled(selectedCategoryID > 0)
        local availableActivities = getAvailableActivities(selectedCategoryID)
        if #availableActivities < 1 then AddonActivityDD:Disable(); return end
        local activitiesByGroup = LFGUtil_OrganizeActivitiesByActivityGroup(availableActivities)
        local activityGroups, numActivityGroups = {}, 0;
        for groupID, _ in pairs(activitiesByGroup) do
            tinsert(activityGroups, groupID); numActivityGroups = numActivityGroups + 1;
        end
        if numActivityGroups > 1 then
            LFGUtil_SortActivityGroupIDs(activityGroups)
            -- each activity group has a submenu with all activities
            for _, groupID in ipairs(activityGroups) do
                local groupDescription = addActivityGroupButton(groupID, rootDescription)
                if groupDescription then -- this should always be true for this branch.
                    table.sort(activitiesByGroup[groupID], Activity_SortByLevel)
                    for _, activityID in ipairs(activitiesByGroup[groupID]) do
                        addActivityButton(activityID, groupDescription) -- buttons added as submenus
                    end
                end
            end
        else
            -- add an activityGroup "toggle all" as 1st button for non "Custom" activity groups
            if activityGroups[1] > 0 then
                addActivityGroupButton(activityGroups[1], rootDescription)
            end
            -- create activity filters (indented if a group toggle exists)
            local shouldIndent = activityGroups[1] > 0
            table.sort(availableActivities, Activity_SortByLevel)
            for _, activityID in ipairs(availableActivities) do
                addActivityButton(activityID, rootDescription, shouldIndent)
            end
        end
    end
    ----- Dropdown Button Header Text Setup
    AddonActivityDD.Text:SetFontObject("GameFontHighlightSmallLeft")
    AddonActivityDD:SetDefaultText(LFGBROWSE_ACTIVITY_HEADER_DEFAULT)
    AddonActivityDD:SetSelectionText(function()
        local selections = getSelectedActivitiesArray()
        local count = #selections
        if count > 1 then
            return string.format(LFGBROWSE_ACTIVITY_HEADER, count)
        elseif count == 1 then
            local activityInfo = C_LFGList.GetActivityInfoTable(selections[1]);
            return LFGUtil_GetActivityInfoName(activityInfo)
        else
            return LFGBROWSE_ACTIVITY_HEADER_DEFAULT
        end
    end)
    ----- Setup filters "Reset" button
    AddonActivityDD:SetDefaultCallback(function()
        local availableActivities = getAvailableActivities(selectedCategoryID)
        for _, activityID in ipairs(availableActivities) do
            selectedActivitiesCache[activityID] = false
        end
        AddonActivityDD:SignalUpdate()
    end);
    AddonActivityDD:SetIsDefaultCallback(function()
        local availableActivities = getAvailableActivities(selectedCategoryID)
        for _, activityID in ipairs(availableActivities) do
            if selectedActivitiesCache[activityID] then return false end
        end
        return true
    end);
    AddonActivityDD.ResetButton:HookScript("OnClick", LFGBrowse_DoSearch)
    --- Position
    AddonActivityDD:SetPoint("LEFT", AddonCategoryDD, "RIGHT", 5, 0)
    AddonActivityDD:SetPoint("RIGHT", LFGBrowseFrame.RefreshButton, "LEFT", -1, 0)
    AddonActivityDD:SetHeight(UIDropdownButtonHeight)

    AddonActivityDD:SetupMenu(activityDropdownMenuGenerator) -- initialize
    --------------------------------------------------------------------------------
    -- Refresh Button Glow for stale searches
    --------------------------------------------------------------------------------

    --- Adds a glow to refresh button when last searched values don't match the current dd selections
    local refreshGlowFrame = CreateFrame("Frame", nil, LFGBrowseFrame.RefreshButton)
    refreshGlowFrame:SetAllPoints()
    refreshGlowFrame:SetFrameLevel(LFGBrowseFrame.RefreshButton:GetFrameLevel())
    do -- setup glow animation/textures
        local glow = refreshGlowFrame:CreateTexture(nil, "OVERLAY") ---@type Texture
        refreshGlowFrame.glow = glow
        glow:SetDesaturated(true); glow:SetVertexColor(NORMAL_FONT_COLOR:GetRGB());
        -- glow:SetVertexColor(1, 1,1, 1);
        glow:SetAtlas("newplayertutorial-drag-slotgreen", true)
        glow:SetPoint("TOPLEFT", -6, 5); glow:SetPoint("BOTTOMRIGHT", 4,-4);
        glow:SetAlpha(0)
        local alphaFrom, alphaTo = 0.2, 0.65;
        local duration = 0.7
        local fadeAnim = glow:CreateAnimationGroup()
        fadeAnim:SetLooping("BOUNCE")
        local alphaAnim = fadeAnim:CreateAnimation("Alpha")
        alphaAnim:SetFromAlpha(alphaFrom); alphaAnim:SetToAlpha(alphaTo)
        alphaAnim:SetDuration(duration); alphaAnim:SetSmoothing("IN_OUT")
        local startAnimation = function() fadeAnim:Play() end
        local stopAnimation = function() fadeAnim:Stop(); glow:SetAlpha(0) end
        refreshGlowFrame.startAnimation = startAnimation
        refreshGlowFrame.stopAnimation = stopAnimation
        local lastSearchedActivities = {}
        hooksecurefunc(C_LFGList, "Search", function(_, _, _, _, _, _, activityIDs)
            lastSearchedActivities = activityIDs or {}
            if Addon.accountDB.GlobalDisable then return end
            stopAnimation();
        end)
        EventFrame:RegisterEventCallback("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
            if Addon.accountDB.GlobalDisable then return end
            if not next(lastSearchedActivities) then return end -- can be empty when externally updated
            local selectedActivities = getSelectedActivitiesArray()
            if not next(selectedActivities) then
                selectedActivities = getAvailableActivities(selectedCategoryID);
            end
            local didSearchMatchSelectedFilters = tCompare(lastSearchedActivities, selectedActivities, 1)
            if not didSearchMatchSelectedFilters then startAnimation() end
        end)
        EventFrame:RegisterEventCallback("LFG_LIST_SEARCH_FAILED", function()
            if not Addon.accountDB.GlobalDisable then startAnimation() end
        end)
    end
    --------------------------------------------------------------------------------
    -- Finalize Setup/Hacks and Hooks
    --------------------------------------------------------------------------------

    --- Add Hooks to refresh dropdown menu wherever blizzards dropdowns would be
    EventFrame:RegisterEventCallback("LFG_LIST_AVAILABILITY_UPDATE", function()
        if Addon.accountDB.GlobalDisable then return end
        refreshAddonDropdowns()
    end)
    EventFrame:RegisterEventCallback("CVAR_UPDATE", function(_, name)
        if Addon.accountDB.GlobalDisable then return end
        if name == "disableSuggestedLevelActivityFilter" then
            refreshAddonDropdowns(AddonActivityDD)
        end
    end)
    hooksecurefunc("LFGBrowseCategoryButton_OnClick", function()
        selectedCategoryID = BlizzardCategoryDD.selectedValue
    end)
    hooksecurefunc(LFGBrowseFrame, "SearchActiveEntry", function()
        if Addon.accountDB.GlobalDisable then
            -- just update value. menu will be refreshed on addon toggle callback
            selectedCategoryID = BlizzardCategoryDD.selectedValue
            return
        end
        updateToActiveEntry(true)
    end)
    hooksecurefunc(C_LFGList, "Search", function(categoryID, _, _, _, _, _, activityIDs)
        selectedCategoryID = categoryID
        if Addon.accountDB.GlobalDisable then return end
        refreshAddonDropdowns()
    end)
    if C_LFGList.HasActiveEntryInfo() then updateToActiveEntry(true) end

    --- Register features with the global toggle
    local LFGBrowseRefreshButton_OnClick = LFGBrowseFrame.RefreshButton:GetScript("OnClick");
    local onGlobalAddonToggle = function(_, isChecked)
        local isAddonDisabled = not isChecked
        if isAddonDisabled then
            refreshGlowFrame.stopAnimation()
            refreshGlowFrame:Hide()
            LFGBrowseFrame.RefreshButton:SetScript("OnClick", LFGBrowseRefreshButton_OnClick)
        else
            refreshGlowFrame:Show()
            LFGBrowseFrame.RefreshButton:SetScript("OnClick", LFGBrowse_DoSearch)
            refreshAddonDropdowns()
        end
        setVisibleDropdowns(isAddonDisabled)
    end
    Addon.GlobalToggle.Checkbox:RegisterCallback("OnValueChanged", onGlobalAddonToggle)
    onGlobalAddonToggle(nil, Addon.GlobalToggle.Checkbox:GetChecked())
end
--------------------------------------------------------------------------------
-- Filters Panel UI Toggle button
--------------------------------------------------------------------------------
-- Button added to the LFGList frame to allow maximizing/minimzing the filters panel

local ShowHideAddonButtonMixin = {}
function ShowHideAddonButtonMixin:Setup()
    ---@cast self Button|{LeftSeparator:Texture, RightSeparator:Texture}
    self:SetHitRectInsets(5, 5, 5, 5)
    MagicButton_OnLoad(self)
    self.LeftSeparator:ClearAllPoints()
    self.LeftSeparator:SetPoint("RIGHT", self, "LEFT", 11, 0)
    self.LeftSeparator:SetHeight(22)
    self.RightSeparator:ClearAllPoints()
    self.RightSeparator:SetPoint("LEFT", self, "RIGHT", -12, 0)
    self.RightSeparator:SetHeight(22)
    self:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:AddLine(L.TOGGLE_FILTERS_PANEL, 1, 1, 1);
        GameTooltip:Show();
    end)
    self:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:SetScript("OnClick", ShowHideAddonButtonMixin.OnClick)
    ShowHideAddonButtonMixin.OnButtonStateChanged(self);
end
function ShowHideAddonButtonMixin:OnClick(clickType, mouseDown)
    local panel = Addon.PanelFrame
    panel:SetShown(not panel:IsShown())
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end
function ShowHideAddonButtonMixin:OnButtonStateChanged()
    local isPanelShown = Addon.PanelFrame:IsShown()
    if not isPanelShown then -- BiggerButton
        self:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
        self:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
        self:SetDisabledTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Disabled")
        self:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    else -- SmallerButton
        self:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
        self:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
        self:SetDisabledTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Disabled")
        self:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    end
end
--------------------------------------------------------------------------------
-- Filters Panel UI
--------------------------------------------------------------------------------
-- Main UI panel of addon containing user facing filtering options

local FiltersPanelMixin = {}
function FiltersPanelMixin:Setup()
    local nextRelativeTop = self.Bg
    local createSettingContainer  = function(xOffset, yOffset)
        local container = CreateFrame("Frame", nil, self)
        container:SetHeight(CHECKBOX_SIZE + 4)
        container:ClearAllPoints()
        container:SetPoint("TOP", nextRelativeTop, "BOTTOM", xOffset or 0, yOffset or -5)
        container:SetPoint("LEFT", self.Bg, "LEFT", 5, 0)
        container:SetPoint("RIGHT", self.Bg, "RIGHT", -5, 0)
        return container
    end
    local addHeaderFontString = function(container, text)
        local Header = container:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
        Header:SetText(text)
        Header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        container:SetHeight(Header:GetHeight())
        return Header
    end
    local maxCheckboxLabelWith = 0;
    ---@param key string? -- defaults to `Enabled`
    local addCheckboxWidget = function(container, label, setting, key)
        local Checkbox = CreateFrame("CheckButton", nil, container, "SettingsCheckboxTemplate")
        Checkbox:SetPoint("LEFT")
        Checkbox:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
        local useSetting = setting and type(setting) == "table"
        Checkbox:RegisterCallback("OnValueChanged", function(_, value)
            if useSetting then setting[key or "Enabled"] = value; end;
            LFGListHookModule.UpdateResultList()
        end)
        if useSetting then Checkbox:Init(setting[key or "Enabled"]) end;
        Checkbox:HookScript("OnClick", GenerateClosure(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON));
        Checkbox.HoverBackground:SetAllPoints(container)
        local Label = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        Mixin(Label, CallbackRegistryMixin);
        Label:OnLoad()
        Label:GenerateCallbackEvents({"MaxLabelWidthChanged"})
        Label:SetJustifyH("LEFT")
        Label:SetText(label)
        local labelWidth = Label:GetWidth()
        Label:RegisterCallback("MaxLabelWidthChanged", function(_, newMaxWidth)
            Label:SetWidth(newMaxWidth)
        end)
        if labelWidth > maxCheckboxLabelWith then
            maxCheckboxLabelWith = labelWidth
            Label:TriggerEvent("MaxLabelWidthChanged", maxCheckboxLabelWith)
        end
        Label:SetWidth(maxCheckboxLabelWith)
        Label:SetPoint("LEFT", Checkbox, "RIGHT", 5, -1)
        Label:EnableMouse(true)
        Label:SetScript("OnMouseUp", function() if Checkbox:IsEnabled() then Checkbox:Click() end end)
        local manageHighlight = function(isMouseOver)
            if not Checkbox:IsEnabled() then return end
            Checkbox.HoverBackground:SetShown(isMouseOver)
        end
        Label:SetScript("OnEnter", GenerateClosure(manageHighlight, true))
        Label:SetScript("OnLeave", GenerateClosure(manageHighlight, false))
        Checkbox.Label = Label
        return Checkbox
    end
    local addInputRangeWidget = function(container, setting)
        ---@param settingKey "Minimum"|"Maximum"
        local createInputBox = function(settingKey)
            local input = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
            input:SetSize(CHECKBOX_SIZE + 4, CHECKBOX_SIZE)
            input:SetNumeric(true); input:SetMaxLetters(2)
            input:SetAutoFocus(false)
            input.Left:SetHeight(24);
            input.Right:SetHeight(24);
            input.Middle:SetHeight(24);
            input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            input:SetScript("OnEditFocusLost", function(self)
                local input = tonumber(self:GetText());
                if not input then setting[settingKey] = nil;
                elseif settingKey == "Minimum" then
                    setting[settingKey] = math.min(input, setting.Maximum or input)
                else
                    setting[settingKey] = math.max(input, setting.Minimum or input)
                end
                self:SetText(setting[settingKey] or "");
                if setting.Enabled then LFGListHookModule.UpdateResultList() end;
            end)
            input:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            input:SetText(setting[settingKey] or "")
            return input
        end
        local MinInput, MaxInput = createInputBox("Minimum"), createInputBox("Maximum")
        local Separator = container:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        Separator:SetText(strtrim(BATTLE_PET_VARIANCE_STR:gsub("%%s", ""))) -- "To"
        Separator:SetWidth(24)
        --- [Min] to [Max]
        -- MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", 15, 0) -- do after
        Separator:SetPoint("LEFT", MinInput, "RIGHT", 0, 0)
        MaxInput:SetPoint("LEFT", Separator, "RIGHT", MaxInput.Left:GetWidth()/2, 0)
        return MinInput, MaxInput
    end
    do -- Applicants header
        local container = createSettingContainer()
        container:SetPoint("TOP", nextRelativeTop, "TOP", 0, -12)
        addHeaderFontString(container, CLUB_FINDER_APPLICANTS)
        nextRelativeTop = container
    end
    do -- Show Applicants Toggle
        local container = createSettingContainer()
        addCheckboxWidget(container, L.SHOW_APPLICANTS, Addon.accountDB.Applicants)
        maxCheckboxLabelWith = 0; -- don't track width for this checkbox label
        nextRelativeTop = container
    end
    do -- Classes Filter
        local setting = Addon.accountDB.Applicants.ClassFilters
        local container = createSettingContainer()
        local Checkbox = addCheckboxWidget(container, L.FILTER_BY_CLASS, setting)
        Checkbox.Label:UnregisterEvents(); -- do not auto resize this label.
        local FilterDropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1FilterDropdownTemplate")
        FilterDropdown:SetPoint("LEFT", Checkbox.Label, "RIGHT", 10, 0)
        Mixin(FilterDropdown, DropdownSelectionTextMixin)
        DropdownSelectionTextMixin.OnLoad(FilterDropdown)
        FilterDropdown:SetScript("OnEnter", DropdownSelectionTextMixin.OnEnter)
        FilterDropdown:SetScript("OnLeave", DropdownSelectionTextMixin.OnLeave)
        FilterDropdown.Text:ClearAllPoints()
        FilterDropdown.Text:SetPoint("TOPLEFT", FilterDropdown, "TOPLEFT", 10, -2)
        FilterDropdown.Text:SetPoint("BOTTOMRIGHT", FilterDropdown, "BOTTOMRIGHT", -20, 2)
        FilterDropdown.Text:SetJustifyH("CENTER")
        FilterDropdown.resizeToTextMinWidth = 105;
        FilterDropdown.resizeToTextMaxWidth = 105;
        FilterDropdown.resizeToTextPadding = 0;
        Checkbox:RegisterCallback("OnValueChanged", function(_, value)
            FilterDropdown:SetEnabled(not not value);
        end)
        FilterDropdown:SetEnabled(setting.Enabled)
        local selectedIds = Addon.accountDB.Applicants.ClassFilters.SelectedByClassID
        for _, id in pairs(CLASS_ID_BY_FILE) do selectedIds[id] = selectedIds[id] or false; end;
        local setSelected = function(classID) selectedIds[classID] = not selectedIds[classID] end;
        local isSelected = function(classID) return selectedIds[classID] end
        local isAllSelected = function()
            for _, isSelected in pairs(selectedIds) do
                if not isSelected then return false end
            end
            return true
        end
        local setAllSelected = function()
            local newState = not isAllSelected();
            for classID, _ in pairs(selectedIds) do selectedIds[classID] = newState end
        end
        local hookWithUpdate = function(func)
            return function(...)
                func(...)
                LFGListHookModule.UpdateResultList()
            end
        end
        setSelected, setAllSelected = hookWithUpdate(setSelected), hookWithUpdate(setAllSelected)
        local setupClassFilter = function(rootDescription, classInfo)
            if not classInfo then return; end
            if isClassicEra
                and ((not isPlayerHorde and classInfo.classFile == "SHAMAN")
                or (isPlayerHorde and classInfo.classFile == "PALADIN"))
            then selectedIds[classInfo.classID] = nil; return; end
            local displayStr = "  " .. GetColoredClassNameByID(classInfo.classID)
            rootDescription:CreateCheckbox(displayStr, isSelected, setSelected, classInfo.classID);
        end
        FilterDropdown:SetSelectionText(function(selections)
            FilterDropdown:SetTooltip(nil)
            local count = #selections
            local isDisabled = not FilterDropdown:IsEnabled()
            local WrapOnDisabled = function(text)
                if not isDisabled then return text end
                return DISABLED_FONT_COLOR:WrapTextInColorCode(text);
            end
            if count == 0 then return WrapOnDisabled(NONE) end
            if isAllSelected() then return WrapOnDisabled(ALL_CLASSES) end
            local classID = selections[1].data
            local classStr = GetColoredClassNameByID(classID, isDisabled)
            --- only setup tooltip when more than 1 class is selected
            if count > 1 then
                FilterDropdown:SetTooltip(function(tooltip)
                    if FilterDropdown:IsMenuOpen() then return end
                    tooltip:SetOwner(FilterDropdown, "ANCHOR_BOTTOMRIGHT", 4, FilterDropdown.Background:GetHeight())
                    GameTooltip_SetTitle(tooltip, L.SELECTED_CLASSES, NORMAL_FONT_COLOR)
                    for _, selection in ipairs(selections) do
                        GameTooltip_AddNormalLine(tooltip, selection.text)
                    end
                end)
                return WrapOnDisabled(("%s +%s"):format(classStr, count - 1))
            else return classStr end
        end)
        function FilterDropdown:OnButtonStateChanged()
            WowStyle1FilterDropdownMixin.OnButtonStateChanged(self)
            FilterDropdown:SignalUpdate()
        end
        FilterDropdown:HookScript("OnMouseDown", GameTooltip_Hide)
        FilterDropdown:SetupMenu(function(_, rootDescription)
            ---@cast rootDescription RootMenuDescriptionProxy
            rootDescription:SetTag(CLASS_FILTER_DROPDOWN_TAG)
            rootDescription:CreateCheckbox(ALL_CLASSES, isAllSelected, setAllSelected)
            for classID, _ in pairs(selectedIds) do
                setupClassFilter(rootDescription, C_CreatureInfo.GetClassInfo(classID))
            end
        end)
        nextRelativeTop = container
    end
    do -- Role Filter
        local setting = Addon.accountDB.Applicants.RoleFilters
        local container = createSettingContainer()
        maxCheckboxLabelWith = 0; -- do not match to previous widths
        local Checkbox = addCheckboxWidget(container, L.FILTER_BY_ROLE, setting)
        local anchorTo = Checkbox.Label
        local createRoleWidget = function(role)
            local size = container:GetHeight() + 2
            local checkboxSize = size * 0.45
            local normalAtlas, disabledAtlas = LFG_ROLE_ATLAS[role], LFG_ROLE_DISABLED_ATLAS[role]
            local button = CreateFrame("Button", nil, container)
            local buttonTex = button:CreateTexture(nil, "ARTWORK")
            buttonTex:SetAllPoints(button)
            buttonTex:SetAtlas(normalAtlas)
            button:SetSize(size, size)
            button:SetPoint("LEFT", anchorTo, "RIGHT", role == "TANK" and 16 or 6, 0)
            local checkbox = addCheckboxWidget(button, "", setting, role)
            checkbox.Label:Hide()
            checkbox:SetSize(checkboxSize, checkboxSize)
            checkbox:ClearAllPoints()
            checkbox:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -4, 0)
            checkbox.HoverBackground:SetAlpha(0.6)
            checkbox.HoverBackground:AdjustPointsOffset(-1, 0) -- ui nit
            local setRoleAtlas = function(_, value)
                buttonTex:SetAtlas(value and normalAtlas or disabledAtlas)
                -- button:SetNormalAtlas(value and normalAtlas or disabledAtlas)
            end;
            checkbox:RegisterCallback("OnValueChanged", setRoleAtlas)
            setRoleAtlas(nil, setting[role]); -- set initial state
            button:SetScript("OnClick", function() checkbox:Click() end)
            button:SetScript("OnEnter", function() checkbox:OnEnter() end)
            button:SetScript("OnLeave", function() checkbox:OnLeave() end)
            anchorTo = button
        end
        for _, role in ipairs({"TANK", "HEALER", "DPS"}) do createRoleWidget(role) end;
        nextRelativeTop = container
    end
    do -- Premade Groups header
        local container = createSettingContainer(0, -12)
        addHeaderFontString(container, LFGLIST_NAME)
        nextRelativeTop = container
    end
    do -- Show Premade Groups Toggle
        local container = createSettingContainer()
        addCheckboxWidget(container, L.SHOW_PREMADE_GROUPS, Addon.accountDB.PremadeGroups)
        nextRelativeTop = container
    end
    maxCheckboxLabelWith = 0; -- reset. Don't match widths for previous checkbox labels
    local labelRightPadding = 20
    do -- Number of Members
        local container = createSettingContainer()
        local setting = Addon.accountDB.PremadeGroups.MemberCounts
        local Checkbox = addCheckboxWidget(container, MEMBERS, setting)
        local MinInput, MaxInput = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of tanks
        local container = createSettingContainer()
        local setting = Addon.accountDB.PremadeGroups.TankCounts
        local Checkbox = addCheckboxWidget(container, "Tanks", setting)
        local MinInput, _ = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of heals
        local container = createSettingContainer()
        local setting = Addon.accountDB.PremadeGroups.HealerCounts
        local Checkbox = addCheckboxWidget(container, "Healers", setting)
        local MinInput, _ = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of Dps
        local container = createSettingContainer()
        local setting = Addon.accountDB.PremadeGroups.DamagerCounts
        local Checkbox = addCheckboxWidget(container, "DPS", setting)
        local MinInput, _ = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Hide Delisted Entries
        local container = createSettingContainer(nil)
        container:ClearPoint("TOP") -- anchor to bottom instead
        container:SetPoint("BOTTOM", self.Bg, "BOTTOM", 0, 5)
        addCheckboxWidget(container, L.HIDE_DELISTED, Addon.accountDB, "HideDelisted")
    end
end
--------------------------------------------------------------------------------
-- Addon Main
--------------------------------------------------------------------------------

function Addon:ADDON_LOADED()
    self:InitSavedVars()
    self:InitUIPanel()
end
EventFrame:RegisterEventCallback("ADDON_LOADED", function(_, addon)
    if addon == TOC_NAME then return Addon:ADDON_LOADED() end
    if addon == "Blizzard_GroupFinder_VanillaStyle" then
        return Addon:InitUIPanel()
    end
end)

function Addon:InitSavedVars()
    ---Entries either describe the shape or are a default value
    ---@class Addon_AccountDB
    local validationTable = {
        GlobalDisable = false, -- used to completely disable any filtering
        PremadeGroups = {
            Enabled = true,
            MemberCounts = {
                Enabled = false,
                Minimum = nil, ---@type number?
                Maximum = nil, ---@type number?
            };
            TankCounts = { Enabled = false, Minimum = nil, Maximum = nil},
            HealerCounts = { Enabled = false, Minimum = nil, Maximum = nil},
            DamagerCounts = { Enabled = false, Minimum = nil, Maximum = nil},
        },
        Applicants = {
            Enabled = true,
            ClassFilters = {
                Enabled = false,
                ---@type {[number]: boolean}
                SelectedByClassID = {
                    key = "number", value = "boolean", nullable = false,
                },
            },
            RoleFilters = {
                Enabled = false,
                TANK = true, HEALER = true, DPS = true,
            },
        },
        HideDelisted = false,
    }
    local accountDB = _G[TOC_NAME.."DB"]
    if not accountDB then
        accountDB = {}
        _G[TOC_NAME.."DB"] = accountDB
    end
    local function validateSavedVar(db, dbKey, validator)
        local validatorType = type(validator)
        local dbEntry = db[dbKey]
        if validatorType == "table" then
            if not dbEntry then db[dbKey] = {}; dbEntry = db[dbKey] end
            if not validator.value then -- not a base validator table. recurse
                for key, nestedValidator in pairs(validator) do
                    validateSavedVar(dbEntry, key, nestedValidator)
                end
            else
                for key, value in pairs(dbEntry) do
                    if type(key) ~= validator.key then
                        dbEntry[key] = nil
                    elseif type(value) ~= validator.value then
                        dbEntry[key] = nil
                    end
                end
            end
        else
            --- note: also handles nil'ing deprecated keys when validator == nil
            if validatorType == "nil" then print("Removing deprecated setting "..dbKey) end
            if type(dbEntry) ~= validatorType then db[dbKey] = validator end
        end
    end
    -- Fill in missing entries
    for name, validator in pairs(validationTable) do
        validateSavedVar(accountDB, name, validator)
    end
    --- Removes deprecated entries
    for key, _ in pairs(accountDB) do
        if type(validationTable[key]) == "nil" then accountDB[key] = nil;
        else validateSavedVar(accountDB, key, validationTable[key]) end
    end

    self.accountDB = accountDB; ---@type Addon_AccountDB
end

function Addon:InitUIPanel()
    local panelName = TOC_NAME.."Panel"
    local globalToggle = TOC_NAME.."GlobalToggle"
    local frameToggle = panelName.."ToggleButton"
    Addon.GlobalToggle = _G[globalToggle] or CreateFrame("Button", globalToggle);
    Addon.PanelFrame = _G[panelName] or CreateFrame("Frame", panelName, UIParent, "PortraitFrameTemplate")
    Addon.PanelFrame.ToggleButton = _G[frameToggle] or CreateFrame("Button", frameToggle, Addon.PanelFrame);
    if not Addon.PanelFrame.initialized then
        local panel = Addon.PanelFrame
        frameToggle, globalToggle = Addon.PanelFrame.ToggleButton, Addon.GlobalToggle;
        ButtonFrameTemplate_HidePortrait(panel)
        -- ButtonFrameTemplate_HideAttic(panel)
        panel:SetWidth(250)
        panel:SetPoint("CENTER")
        -- panel:SetMovable(true)
        panel:EnableMouse(true)
        -- panel:RegisterForDrag("LeftButton")
        -- panel:SetScript("OnDragStart", panel.StartMoving)
        -- panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        -- panel:SetScript("OnHide", panel.StopMovingOrSizing)
        -- panel:SetScript("OnShow", panel.StartMoving)
        local title = panel:GetTitleText(); ---@type FontString
        title:SetText(L.FILTER_PANEL_TITLE);
        title:ClearAllPoints()
        title:SetPoint("TOP", panel.TitleContainer, "TOP", 0, -5)
        title:SetPoint("LEFT"); title:SetPoint("RIGHT");
        title:SetJustifyH("CENTER")
        panel:SetTitleOffsets(0, nil)
        panel.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble");
        panel.Bg:SetVertTile(false); panel.Bg:SetHorizTile(false);
        FiltersPanelMixin.Setup(panel)
        ShowHideAddonButtonMixin.Setup(frameToggle)
        local updateButton = GenerateClosure(ShowHideAddonButtonMixin.OnButtonStateChanged, frameToggle)
        panel:HookScript("OnShow", updateButton); panel:HookScript("OnHide", updateButton)
        panel:Hide()
        globalToggle.Checkbox = CreateFrame("CheckButton", nil, globalToggle, "SettingsCheckboxTemplate")
        globalToggle.Checkbox:HookScript("OnClick", function() PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end)
        globalToggle.Checkbox:SetPoint("LEFT", globalToggle)
        globalToggle.Checkbox:SetSize(16, 16)
        globalToggle.Label = globalToggle:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        globalToggle.Label:SetText(L.ADDON_ACRONYM)
        globalToggle.Label:SetPoint("LEFT", globalToggle.Checkbox, "RIGHT", 2, 0)
        globalToggle:SetScript("OnClick", function() globalToggle.Checkbox:Click() end)
        globalToggle:SetScript("OnEnter", function() globalToggle.Checkbox:OnEnter() end)
        globalToggle:SetScript("OnLeave", function() globalToggle.Checkbox:OnLeave() end)
        globalToggle:SetHeight(16)
        globalToggle:SetWidth(16 + globalToggle.Label:GetWidth() + 2)
        local onUpdateSetting = function(isGlobalDisabled)
            Addon.PanelFrame:SetShown(not isGlobalDisabled)
            Addon.PanelFrame.ToggleButton:SetShown(not isGlobalDisabled)
            LFGListHookModule.RefreshScrollView()
        end
        globalToggle.Checkbox:RegisterCallback("OnValueChanged", function(_, isChecked)
            Addon.accountDB.GlobalDisable = not isChecked
            onUpdateSetting(Addon.accountDB.GlobalDisable)
        end)
        globalToggle.Checkbox:Init(not Addon.accountDB.GlobalDisable)
        onUpdateSetting(Addon.accountDB.GlobalDisable) -- match initial state
        globalToggle.Checkbox.HoverBackground:SetAlpha(0)
        panel.initialized = true
    end
    if isClassicEra and LFGBrowseFrame then
        LFGListHookModule.AttachToGroupFinderUI()
    end
end
Addon.EFrame = EventFrame