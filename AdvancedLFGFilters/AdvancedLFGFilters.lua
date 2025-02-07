local TOC_NAME,
    ---@class Addon
    Addon = ...

---@class Addon_EventFrame: EventFrame
local EventFrame = CreateFrame("EventFrame", TOC_NAME.."EventFrame", UIParent)

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
    local accountDB = _G[TOC_NAME.."DB"]
    if not accountDB then
        accountDB = {}
        _G[TOC_NAME.."DB"] = accountDB
    end
    self.accountDB = accountDB
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