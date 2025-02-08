local TOC_NAME,
    ---@class Addon
    Addon = ...

---@class Addon_EventFrame: EventFrame
local EventFrame = CreateFrame("EventFrame", TOC_NAME.."EventFrame", UIParent)

local CHECKBOX_SIZE = 28
local isPlayerHorde = UnitFactionGroup("player") == "Horde"
local isClassicEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local isSeasonOfDiscovery = C_Seasons.GetActiveSeason() == Enum.SeasonID.SeasonOfDiscovery
local isBurningCrusade = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
local isCataclysm = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC

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
        GameTooltip:AddLine("Toggle Filters Panel", 1, 1, 1);
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
        Checkbox:RegisterCallback("OnValueChanged", function(_, value)
            setting.Enabled = value;
        end)
        Checkbox:Init(setting.Enabled)
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
                if not input then setting[settingKey] = nil; self:SetText(""); return; end
                if settingKey == "Minimum" then
                    setting[settingKey] = math.min(input, setting.Maximum or input)
                else
                    setting[settingKey] = math.max(input, setting.Minimum or input)
                end
                self:SetText(setting[settingKey]);
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
    do -- Classes Filter
        local setting = Addon.accountDB.ClassFilters
        local container = createSettingContainer()
        local Checkbox = addCheckboxWidget(container, "Filter by Class", setting)
        Checkbox.Label:UnregisterEvents(); -- do not auto resize this label.
        local FilterDropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1FilterDropdownTemplate")
        FilterDropdown:SetPoint("LEFT", Checkbox.Label, "RIGHT", 15, 0)
        FilterDropdown.text = CLASS; FilterDropdown.resizeToText = true;
        local selectedIds = Addon.accountDB.ClassFilters.SelectedByClassID
        for classID = 1, GetNumClasses() do
            if (classID == 10) and (GetClassicExpansionLevel() <= LE_EXPANSION_CATACLYSM) then
				classID = 11; -- fix gap between warlock and druid in pre mop xpacs
			end
            selectedIds[classID] = selectedIds[classID] or false
        end
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
        local setupClassFilter = function(rootDescription, classInfo)
            if not classInfo then return; end
            if isClassicEra
                and ((not isPlayerHorde and classInfo.classFile == "SHAMAN")
                or (isPlayerHorde and classInfo.classFile == "PALADIN"))
            then selectedIds[classInfo.classID] = nil; return; end
            local displayStr = classInfo.className
            local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classInfo.classFile])
                        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.classFile]);
            local displayStr = color and color:WrapTextInColorCode(displayStr) or displayStr;
            displayStr = "  "..displayStr
            rootDescription:CreateCheckbox(displayStr, isSelected, setSelected, classInfo.classID);
        end
        FilterDropdown:SetupMenu(function(_, rootDescription)
            ---@cast rootDescription RootMenuDescriptionProxy
            rootDescription:SetTag("ADV_LFG_CLASS_FILTER")
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
    maxCheckboxLabelWith = 0; -- reset max for the next set of filter labels
    local labelRightPadding = 20
    do -- Number of Members
        local container = createSettingContainer()
        local setting = Addon.accountDB.MemberCounts
        local Checkbox = addCheckboxWidget(container, MEMBERS, setting)
        local MinInput, MaxInput = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of tanks
        local container = createSettingContainer()
        local setting = Addon.accountDB.TankCounts
        local Checkbox = addCheckboxWidget(container, "Tanks", setting)
        local MinInput, _ = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of heals
        local container = createSettingContainer()
        local setting = Addon.accountDB.HealerCounts
        local Checkbox = addCheckboxWidget(container, "Healers", setting)
        local MinInput, _ = addInputRangeWidget(container, setting)
        MinInput:SetPoint("LEFT", Checkbox.Label, "RIGHT", labelRightPadding, 0)
        nextRelativeTop = container
    end
    do -- Number of Dps
        local container = createSettingContainer()
        local setting = Addon.accountDB.DamagerCounts
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
        MemberCounts = {
            Enabled = false,
            Minimum = nil, ---@type number?
            Maximum = nil, ---@type number?
        };
        TankCounts = { Enabled = false, Minimum = nil, Maximum = nil},
        HealerCounts = { Enabled = false, Minimum = nil, Maximum = nil},
        DamagerCounts = { Enabled = false, Minimum = nil, Maximum = nil},
        ClassFilters = {
            Enabled = false,
            ---@type {[number]: boolean}
            SelectedByClassID = {
                key = "number",
                value = "boolean",
                nullable = false,
            },
        }
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
        title:SetText("Advanced Filters");
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
    end
end
Addon.EFrame = EventFrame