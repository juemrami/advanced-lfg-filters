local TOC_NAME,
    ---@class Addon
    Addon = ...

---@class Addon_EventFrame: EventFrame
local EventFrame = CreateFrame("EventFrame", TOC_NAME.."EventFrame", UIParent)

local L = { -- todo: some actual translations for missing pre-localized strings
    SELECTED_CLASSES = "Selected Classes",
    SHOW_APPLICANTS = "Show Applicants",
    SHOW_PREMADE_GROUPS = "Show Premade Groups",
    TOGGLE_FILTERS_PANEL = "Toggle Filters Panel",
    FILTER_PANEL_TITLE = "Advanced Filters",
    FILTER_BY_CLASS = "Filter by Class",
}
local CLASS_FILE_BY_ID = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE",
    [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK", [10] = "MONK", [11] = "DRUID",
};
local CLASS_ID_BY_FILE = tInvert(CLASS_FILE_BY_ID)
local CHECKBOX_SIZE = 28
local CLASS_FILTER_DROPDOWN_TAG = "ADV_LFG_CLASS_FILTER"
local isPlayerHorde = UnitFactionGroup("player") == "Horde"
local isClassicEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isSeasonOfDiscovery = C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfDiscovery
local isBurningCrusade = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
local isCataclysm = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC

local ShouldFilterForResultID = function(resultID)
    local resultData = C_LFGList.GetSearchResultInfo(resultID)
    if not resultData then return false end
    if resultData.numMembers == 1 then -- applicant
        local applicants = Addon.accountDB.Applicants
        if not applicants.Enabled then return false end
        local applicant = C_LFGList.GetSearchResultLeaderInfo(resultID)
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
            if setting.Minimum and numMembers < setting.Minimum then return false end
            if setting.Maximum and numMembers > setting.Maximum then return false end
        end
        local roleCounts = C_LFGList.GetSearchResultMemberCounts(resultID)
        if premadeGroups.TankCounts.Enabled then
            local setting = premadeGroups.TankCounts
            if setting.Minimum and roleCounts.TANK < setting.Minimum then return false end
            if setting.Maximum and roleCounts.TANK > setting.Maximum then return false end
        end
        if premadeGroups.HealerCounts.Enabled then
            local setting = premadeGroups.HealerCounts
            if setting.Minimum and roleCounts.HEALER < setting.Minimum then return false end
            if setting.Maximum and roleCounts.HEALER > setting.Maximum then return false end
        end
        if premadeGroups.DamagerCounts.Enabled then
            local setting = premadeGroups.DamagerCounts
            if setting.Minimum and roleCounts.DAMAGER < setting.Minimum then return false end
            if setting.Maximum and roleCounts.DAMAGER > setting.Maximum then return false end
        end
    end
    return true
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

--- Inplace sort, Only using default blizzard one for now
local SortLFGListResults = function(results)
    local sortFunc = LFGBrowseUtil_SortSearchResults;
    sortFunc(results); return results
end

local LFGListHookModule = {}
function LFGListHookModule.Setup()
    if isClassicEra then
        --note: more accurate updates if we Hook UpdateResults instead of UpdateResultList.
        assert(LFGBrowseFrame.UpdateResults, "LFGBrowseFrame.UpdateResults not found")
        hooksecurefunc(LFGBrowseFrame, "UpdateResults", LFGListHookModule.UpdateResultList)
    end
end
function LFGListHookModule.UpdateResultList(_, abortHookCallback)
    if abortHookCallback then return end;
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
    local addCheckboxWidget = function(container, label, setting)
        local Checkbox = CreateFrame("CheckButton", nil, container, "SettingsCheckboxTemplate")
        Checkbox:SetPoint("LEFT")
        Checkbox:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
        local useSetting = setting and type(setting) == "table"
        Checkbox:RegisterCallback("OnValueChanged", function(_, value)
            if useSetting then setting.Enabled = value; end;
            LFGListHookModule.UpdateResultList()
        end)
        if useSetting then Checkbox:Init(setting and setting.Enabled or nil) end;
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
end

function Addon:ADDON_LOADED()
    self:InitSavedVars()
    self:InitUIPanel()
end
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        if addon == TOC_NAME then return Addon:ADDON_LOADED() end
        if addon == "Blizzard_GroupFinder_VanillaStyle" then
            return Addon:InitUIPanel()
        end
    end
end)

function Addon:InitSavedVars()
    ---Entries either describe the shape or are a default value
    ---@class Addon_AccountDB
    local validationTable = {
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
                    key = "number",
                    value = "boolean",
                    nullable = false,
                },
            }
        },
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
        if not validationTable[key] then accountDB[key] = nil;
        else validateSavedVar(accountDB, key, validationTable[key]) end
    end

    self.accountDB = accountDB; ---@type Addon_AccountDB
end

function Addon:InitUIPanel()
    local panelName = TOC_NAME.."Panel"
    local toggleName = panelName.."ToggleButton"
    Addon.PanelFrame = _G[panelName] or CreateFrame("Frame", panelName, UIParent, "PortraitFrameTemplate")
    Addon.PanelFrame.ToggleButton = _G[toggleName] or CreateFrame("Button", toggleName, Addon.PanelFrame);
    local panel, panelToggle = Addon.PanelFrame, Addon.PanelFrame.ToggleButton
    if not panel.initialized then
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
        ShowHideAddonButtonMixin.Setup(panelToggle)
        local updateButton = GenerateClosure(ShowHideAddonButtonMixin.OnButtonStateChanged, panelToggle)
        panel:HookScript("OnShow", updateButton); panel:HookScript("OnHide", updateButton)
        panel:Hide()
        panel.initialized = true
    end
    if LFGBrowseFrame then
        Addon.PanelFrame:SetParent(LFGBrowseFrame)
        Addon.PanelFrame:ClearAllPoints()
        Addon.PanelFrame:SetPoint("BOTTOMLEFT", LFGBrowseFrame, "BOTTOMRIGHT", -30, 76)
        Addon.PanelFrame:Show()
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
        Addon.PanelFrame.ToggleButton:Show()
        LFGListHookModule:Setup()
    end
end
Addon.EFrame = EventFrame