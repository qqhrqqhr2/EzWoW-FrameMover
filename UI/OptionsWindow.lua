--===========================================================================
-- EzWoW - Frame Mover
-- UI/OptionsWindow.lua : EzWoW Style Settings Window, Scale Toast & Hover Overlay
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog

local ICON_PATH = "Interface\\AddOns\\EzWoW-FrameMover\\Media\\Icon"

local STYLE = {
    bgMain  = { 0.071, 0.094, 0.122, 0.96 }, 
    bgSub   = { 0.114, 0.157, 0.192, 0.92 }, 
    bgHover = { 0.165, 0.224, 0.275, 0.95 }, 
    border  = { 0.204, 0.298, 0.357, 1.00 }, 
    accent  = { 0.478, 0.635, 0.969, 1.00 }, 
    text    = { 0.929, 0.957, 0.969, 1.00 }, 
    textSub = { 0.655, 0.725, 0.773, 1.00 }, 
    danger  = { 0.906, 0.486, 0.439, 1.00 }, 
}

local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

function SettingsDialog.assignSolidColor(tex, r, g, b, a)
    if not tex then return end
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a or 1)
    elseif tex.SetTexture then
        tex:SetTexture(r, g, b, a or 1)
    end
end

function SettingsDialog.commitFlatBackdrop(frame, bg, border)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(FLAT_BACKDROP)
    local b = bg or STYLE.bgMain
    local recordEntry = border or STYLE.border
    frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
    frame:SetBackdropBorderColor(recordEntry[1], recordEntry[2], recordEntry[3], recordEntry[4] or 1)
end

function SettingsDialog.buildFlatButton(parent, width, height, text, onClick)
    local actionBtn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    actionBtn:SetSize(width, height)
    SettingsDialog.commitFlatBackdrop(actionBtn, STYLE.bgSub, STYLE.border)

    local formatLocalizedLabel = actionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    formatLocalizedLabel:SetPoint("CENTER", 0, 0)
    formatLocalizedLabel:SetTextColor(unpack(STYLE.text))
    formatLocalizedLabel:SetText(text or "")
    actionBtn.label = formatLocalizedLabel

    actionBtn:SetScript("OnEnter", function(self)
        SettingsDialog.commitFlatBackdrop(self, STYLE.bgHover, STYLE.accent)
    end)
    actionBtn:SetScript("OnLeave", function(self)
        SettingsDialog.commitFlatBackdrop(self, STYLE.bgSub, STYLE.border)
    end)
    if onClick then
        actionBtn:SetScript("OnClick", onClick)
    end
    return actionBtn
end

function SettingsDialog.buildSectionHeader(parent, yOffset)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, yOffset)
    holder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, yOffset)
    holder:SetHeight(20)

    local statusBar = holder:CreateTexture(nil, "ARTWORK")
    statusBar:SetSize(3, 14)
    statusBar:SetPoint("LEFT", holder, "LEFT", 0, 0)
    SettingsDialog.assignSolidColor(statusBar, unpack(STYLE.accent))

    local titleStr = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleStr:SetPoint("LEFT", statusBar, "RIGHT", 7, 0)
    titleStr:SetTextColor(unpack(STYLE.accent))
    holder.title = titleStr

    local line = holder:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", titleStr, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    SettingsDialog.assignSolidColor(line, STYLE.border[1], STYLE.border[2], STYLE.border[3], 0.65)

    return holder
end

-- Tracker sub-options only matter while the Frame Mover tracker is in use
function SettingsDialog.syncTrackerOptionRows(windowFrame)
    local enabled = ns:InitializeDatabase().enableTracker ~= false
    for _, key in ipairs({ "chkHideDefaultTracker", "chkTrackerTrackAll", "chkTrackerShowZone", "chkTrackerShowBg" }) do
        local rowWidget = windowFrame[key]
        if rowWidget and rowWidget.SetRowEnabled then rowWidget:SetRowEnabled(enabled) end
    end
end

function SettingsDialog.buildFlatCheckbox(parent, x, y, onToggle)
    local rowWidget = CreateFrame("Button", nil, parent)
    rowWidget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    rowWidget:SetSize(440, 22)

    local editBox = CreateFrame("Frame", nil, rowWidget, BackdropTemplateMixin and "BackdropTemplate" or nil)
    editBox:SetSize(18, 18)
    editBox:SetPoint("LEFT", rowWidget, "LEFT", 0, 0)
    SettingsDialog.commitFlatBackdrop(editBox, STYLE.bgSub, STYLE.border)

    local fill = editBox:CreateTexture(nil, "ARTWORK")
    fill:SetSize(10, 10)
    fill:SetPoint("CENTER", editBox, "CENTER", 0, 0)
    SettingsDialog.assignSolidColor(fill, unpack(STYLE.accent))
    fill:Hide()

    local formatLocalizedLabel = rowWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatLocalizedLabel:SetPoint("LEFT", editBox, "RIGHT", 9, 0)
    formatLocalizedLabel:SetPoint("RIGHT", rowWidget, "RIGHT", 0, 0)
    formatLocalizedLabel:SetJustifyH("LEFT")
    formatLocalizedLabel:SetTextColor(unpack(STYLE.text))

    rowWidget.box = editBox
    rowWidget.fill = fill
    rowWidget.label = formatLocalizedLabel
    rowWidget.checked = false

    function rowWidget:SetChecked(val)
        self.checked = not not val
        if self.checked then
            self.fill:Show()
            self.box:SetBackdropBorderColor(unpack(STYLE.accent))
        else
            self.fill:Hide()
            self.box:SetBackdropBorderColor(unpack(STYLE.border))
        end
    end

    rowWidget:SetScript("OnEnter", function(self)
        self.box:SetBackdropBorderColor(unpack(STYLE.accent))
        self.label:SetTextColor(1, 1, 1, 1)
        if GameTooltip and self.label and self.label:GetText() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label:GetText(), STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1, true)
            GameTooltip:Show()
        end
    end)
    function rowWidget:SetRowEnabled(enabled)
        self.rowDisabled = not enabled
        self:SetEnabled(enabled)
        self:SetAlpha(enabled and 1 or 0.45)
    end

    rowWidget:SetScript("OnLeave", function(self)
        if self.checked then
            self.box:SetBackdropBorderColor(unpack(STYLE.accent))
        else
            self.box:SetBackdropBorderColor(unpack(STYLE.border))
        end
        self.label:SetTextColor(unpack(STYLE.text))
        if GameTooltip then GameTooltip:Hide() end
    end)
    rowWidget:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onToggle then
            onToggle(self.checked)
        end
    end)

    return rowWidget
end

local toastFrame

function ns:ShowScaleToast(frameName, scalePct)
    if not toastFrame then
        toastFrame = CreateFrame("Frame", "EzWoWFrameMoverToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        toastFrame:SetSize(250, 32)
        toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
        toastFrame:SetFrameStrata("TOOLTIP")
        SettingsDialog.commitFlatBackdrop(toastFrame, STYLE.bgMain, STYLE.accent)

        local statusBar = toastFrame:CreateTexture(nil, "ARTWORK")
        statusBar:SetHeight(2)
        statusBar:SetPoint("BOTTOMLEFT", toastFrame, "BOTTOMLEFT", 1, 1)
        statusBar:SetPoint("BOTTOMRIGHT", toastFrame, "BOTTOMRIGHT", -1, 1)
        SettingsDialog.assignSolidColor(statusBar, unpack(STYLE.accent))

        local displayText = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        displayText:SetPoint("CENTER", 0, 1)
        displayText:SetTextColor(unpack(STYLE.text))
        toastFrame.txt = displayText

        toastFrame:SetScript("OnUpdate", function(self, elapsed)
            self.timer = (self.timer or 0) - elapsed
            if self.timer <= 0 then
                self:Hide()
            elseif self.timer < 0.35 then
                self:SetAlpha(self.timer / 0.35)
            else
                self:SetAlpha(1)
            end
        end)
    end

    toastFrame.txt:SetText(string.format(self:L("TOAST_SCALE"), tostring(frameName), scalePct or 100))
    local boxWidth = (toastFrame.txt:GetStringWidth() or 180) + 36
    if boxWidth < 200 then boxWidth = 200 end
    toastFrame:SetWidth(boxWidth)
    toastFrame.timer = 1.35
    toastFrame:SetAlpha(1)
    toastFrame:Show()
end

local hoverTooltip

function ns:HideHoverTooltip()
    if hoverTooltip and hoverTooltip:IsShown() then
        hoverTooltip:Hide()
    end
end

function ns:UpdateHoverTooltip()
    local savedDB = self:InitializeDatabase()
    if savedDB.showTooltip == false then
        self:HideHoverTooltip()
        return
    end

    local targetFrame = self.GetHoveredMovableFrame and self:GetHoveredMovableFrame()
    if not targetFrame then
        self:HideHoverTooltip()
        return
    end

    local fdVal = self.FrameData[targetFrame]
    local rootFrame = self:GetRootFrame(targetFrame) or targetFrame
    local frameName = self:GetFrameName(rootFrame) or self:GetFrameName(targetFrame) or (rootFrame.GetName and rootFrame:GetName()) or "Frame"
    local scalePct = (self.GetFrameScalePct and self:GetFrameScalePct(rootFrame)) or 100

    local lineList = {}
    if savedDB.enableMove ~= false then
        if savedDB.requireCtrl then
            lineList[#lineList + 1] = "• " .. self:L("TT_CTRL_DRAG_MOVE")
        else
            lineList[#lineList + 1] = "• " .. self:L("TT_DRAG_MOVE")
        end
        if fdVal and fdVal.Detachable and not (fdVal.storage and fdVal.storage.detached) then
            lineList[#lineList + 1] = "• " .. self:L("TT_ALT_DETACH")
        end
    end
    if savedDB.enableScale ~= false then
        local isCallOk, wheelLine = pcall(string.format, self:L("TT_WHEEL_SCALE"), scalePct)
        lineList[#lineList + 1] = "• " .. ((isCallOk and wheelLine) or self:L("TT_WHEEL_SCALE"))
    end
    if savedDB.quickReset ~= false then
        lineList[#lineList + 1] = "• " .. self:L("TT_SHIFT_RCLICK")
        lineList[#lineList + 1] = "• " .. self:L("TT_CTRL_RCLICK")
        lineList[#lineList + 1] = "• " .. self:L("TT_FULL_RESET")
    end

    if #lineList == 0 then
        self:HideHoverTooltip()
        return
    end

    if not hoverTooltip then
        hoverTooltip = CreateFrame("Frame", "EzWoWFrameMoverHoverTooltip", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        hoverTooltip:SetFrameStrata("TOOLTIP")
        hoverTooltip:SetFrameLevel(120)
        hoverTooltip:EnableMouse(false)
        SettingsDialog.commitFlatBackdrop(hoverTooltip, STYLE.bgMain, STYLE.border)

        local accentTop = hoverTooltip:CreateTexture(nil, "OVERLAY")
        accentTop:SetHeight(2)
        accentTop:SetPoint("TOPLEFT", hoverTooltip, "TOPLEFT", 1, -1)
        accentTop:SetPoint("TOPRIGHT", hoverTooltip, "TOPRIGHT", -1, -1)
        SettingsDialog.assignSolidColor(accentTop, unpack(STYLE.accent))

        local titleStr = hoverTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleStr:SetPoint("TOPLEFT", hoverTooltip, "TOPLEFT", 10, -9)
        titleStr:SetJustifyH("LEFT")
        titleStr:SetTextColor(unpack(STYLE.accent))
        hoverTooltip.title = titleStr

        local scaleTxt = hoverTooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scaleTxt:SetPoint("TOPRIGHT", hoverTooltip, "TOPRIGHT", -10, -9)
        scaleTxt:SetJustifyH("RIGHT")
        scaleTxt:SetTextColor(unpack(STYLE.text))
        hoverTooltip.scaleTxt = scaleTxt

        local sep = hoverTooltip:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", hoverTooltip, "TOPLEFT", 8, -26)
        sep:SetPoint("TOPRIGHT", hoverTooltip, "TOPRIGHT", -8, -26)
        SettingsDialog.assignSolidColor(sep, STYLE.border[1], STYLE.border[2], STYLE.border[3], 0.8)

        local body = hoverTooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", hoverTooltip, "TOPLEFT", 10, -32)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(3)
        body:SetTextColor(unpack(STYLE.textSub))
        hoverTooltip.body = body
    end

    local addonTitle = self:L("ADDON_TITLE") or "EzWoW FrameMover"
    local bodyStr = table.concat(lineList, "\n")
    if hoverTooltip.lastFrameName ~= addonTitle or hoverTooltip.lastScalePct ~= scalePct or hoverTooltip.lastBodyStr ~= bodyStr then
        hoverTooltip.lastFrameName = addonTitle
        hoverTooltip.lastScalePct = scalePct
        hoverTooltip.lastBodyStr = bodyStr

        hoverTooltip.title:SetText(addonTitle)
        hoverTooltip.scaleTxt:SetText(tostring(scalePct) .. "%")
        hoverTooltip.body:SetText(bodyStr)

        local headerW = (hoverTooltip.title:GetStringWidth() or 100) + (hoverTooltip.scaleTxt:GetStringWidth() or 36) + 32
        local bodyW = (hoverTooltip.body:GetStringWidth() or 180) + 22
        local boxWidth = math.max(210, headerW, bodyW)
        local headerBar = (hoverTooltip.body:GetStringHeight() or (#lineList * 14)) + 42
        hoverTooltip:SetSize(boxWidth, headerBar)
    end

    if type(GetCursorPosition) == "function" then
        local cxVal, cyVal = GetCursorPosition()
        local effScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if effScale <= 0 then effScale = 1 end
        cxVal = cxVal / effScale
        cyVal = cyVal / effScale

        local swVal = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
        local shVal = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1080
        local twVal = hoverTooltip:GetWidth() or 220
        local thVal = hoverTooltip:GetHeight() or 110

        local x = cxVal + 18
        local y = cyVal - 18
        if x + twVal > swVal - 8 then
            x = cxVal - twVal - 14
        end
        if y - thVal < 8 then
            y = cyVal + thVal + 14
        end

        hoverTooltip:ClearAllPoints()
        hoverTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end

    hoverTooltip:Show()
end

local donatePopup

function SettingsDialog.openDonateDialog()
    if not donatePopup then
        donatePopup = CreateFrame("Frame", "EzWoWFrameMoverDonatePopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        donatePopup:SetSize(380, 108)
        donatePopup:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        ns.UIKit:ElevateModal(donatePopup, 260)
        donatePopup:EnableMouse(true)
        donatePopup:SetMovable(true)
        donatePopup:RegisterForDrag("LeftButton")
        donatePopup:SetScript("OnDragStart", donatePopup.StartMoving)
        donatePopup:SetScript("OnDragStop", donatePopup.StopMovingOrSizing)
        SettingsDialog.commitFlatBackdrop(donatePopup, STYLE.bgMain, STYLE.accent)
        if UISpecialFrames then table.insert(UISpecialFrames, "EzWoWFrameMoverDonatePopup") end

        local titleStr = donatePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleStr:SetPoint("TOPLEFT", 16, -14)
        titleStr:SetTextColor(unpack(STYLE.accent))
        donatePopup.title = titleStr

        local dismissBtn = SettingsDialog.buildFlatButton(donatePopup, 22, 22, "X", function()
            donatePopup:Hide()
        end)
        dismissBtn:SetPoint("TOPRIGHT", -8, -8)
        dismissBtn:SetFrameLevel(donatePopup:GetFrameLevel() + 5)

        local inputBox = CreateFrame("EditBox", nil, donatePopup, BackdropTemplateMixin and "BackdropTemplate" or nil)
        inputBox:SetSize(348, 26)
        inputBox:SetPoint("BOTTOM", 0, 16)
        inputBox:SetFrameLevel(donatePopup:GetFrameLevel() + 5)
        inputBox:SetFontObject(ChatFontNormal)
        inputBox:SetTextInsets(8, 8, 0, 0)
        inputBox:SetAutoFocus(false)
        SettingsDialog.commitFlatBackdrop(inputBox, STYLE.bgSub, STYLE.border)
        inputBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(ns.DONATE_URL); self:HighlightText() end
        end)
        inputBox:SetScript("OnEscapePressed", function() donatePopup:Hide() end)
        inputBox:SetScript("OnEnterPressed", function() donatePopup:Hide() end)
        inputBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        inputBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        donatePopup.eb = inputBox
    end

    ns.UIKit:ElevateModal(donatePopup, 260)
    donatePopup.title:SetText(ns:L("DONATE_TITLE"))
    donatePopup.eb:SetText(ns.DONATE_URL)
    donatePopup:Show()
    if donatePopup.Raise then donatePopup:Raise() end
    donatePopup.eb:SetFocus()
    donatePopup.eb:HighlightText()
end

local settingsFrame

function ns:CreateSettingsWindow()
    if settingsFrame then return settingsFrame end

    local windowFrame = CreateFrame("Frame", "EzWoWFrameMoverSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    windowFrame:SetSize(480, 678)
    windowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    windowFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    windowFrame:SetToplevel(true)
    windowFrame:EnableMouse(true)
    windowFrame:SetMovable(true)
    windowFrame:SetClampedToScreen(true)
    windowFrame:RegisterForDrag("LeftButton")
    windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
    windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
    SettingsDialog.commitFlatBackdrop(windowFrame, STYLE.bgMain, STYLE.border)
    windowFrame:Hide()

    if type(UISpecialFrames) == "table" then
        local found = false
        for _, displayName in ipairs(UISpecialFrames) do
            if displayName == "EzWoWFrameMoverSettings" then found = true break end
        end
        if not found then
            table.insert(UISpecialFrames, "EzWoWFrameMoverSettings")
        end
    end

    local headerRegion = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    headerRegion:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 1, -1)
    headerRegion:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -1, -1)
    headerRegion:SetHeight(56)
    SettingsDialog.commitFlatBackdrop(headerRegion, STYLE.bgSub, STYLE.border)
    headerRegion:EnableMouse(true)
    headerRegion:RegisterForDrag("LeftButton")
    headerRegion:SetScript("OnDragStart", function() windowFrame:StartMoving() end)
    headerRegion:SetScript("OnDragStop", function() windowFrame:StopMovingOrSizing() end)

    local iconTex = headerRegion:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(28, 28)
    iconTex:SetPoint("LEFT", headerRegion, "LEFT", 14, 0)
    iconTex:SetTexture(ICON_PATH)

    local titleStr = headerRegion:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleStr:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 10, -1)
    titleStr:SetTextColor(unpack(STYLE.text))
    windowFrame.title = titleStr

    local verText = headerRegion:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verText:SetPoint("LEFT", titleStr, "RIGHT", 8, 0)
    verText:SetTextColor(unpack(STYLE.textSub))
    verText:SetText("v" .. tostring(self.VERSION))

    local subtitleRegion = headerRegion:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleRegion:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", 10, 1)
    subtitleRegion:SetTextColor(unpack(STYLE.textSub))
    windowFrame.subtitle = subtitleRegion

    local dismissBtn = SettingsDialog.buildFlatButton(headerRegion, 24, 24, "X", function() windowFrame:Hide() end)
    dismissBtn:SetPoint("TOPRIGHT", headerRegion, "TOPRIGHT", -12, -16)

    local accentLine = headerRegion:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT", headerRegion, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", headerRegion, "BOTTOMRIGHT", 0, 0)
    SettingsDialog.assignSolidColor(accentLine, unpack(STYLE.accent))

    local langLabel2 = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    langLabel2:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 20, -70)
    langLabel2:SetTextColor(unpack(STYLE.textSub))
    windowFrame.langLabel = langLabel2

    local langBtn = SettingsDialog.buildFlatButton(windowFrame, 160, 22, "Auto", nil)
    langBtn:SetPoint("LEFT", langLabel2, "RIGHT", 12, 0)
    windowFrame.langBtn = langBtn

    local langMenu = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    langMenu:SetWidth(160)
    langMenu:SetHeight(#self.SUPPORTED_LANGS * 22 + 6)
    langMenu:SetPoint("TOPLEFT", langBtn, "BOTTOMLEFT", 0, -2)
    langMenu:SetFrameLevel(windowFrame:GetFrameLevel() + 30)
    SettingsDialog.commitFlatBackdrop(langMenu, STYLE.bgMain, STYLE.accent)
    langMenu:Hide()
    windowFrame.langMenu = langMenu

    for entryIndex, item in ipairs(self.SUPPORTED_LANGS) do
        local itemBtn = SettingsDialog.buildFlatButton(langMenu, 154, 20, item.label, function()
            local savedDB = ns:InitializeDatabase()
            savedDB.lang = item.code
            langMenu:Hide()
            ns:RefreshSettingsUI()
        end)
        itemBtn:SetPoint("TOP", langMenu, "TOP", 0, -3 - (entryIndex - 1) * 22)
    end

    langBtn:SetScript("OnClick", function()
        if langMenu:IsShown() then
            langMenu:Hide()
        else
            langMenu:Show()
        end
    end)

    windowFrame.secGeneral = SettingsDialog.buildSectionHeader(windowFrame, -98)

    windowFrame.chkEnableMove = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -122, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.enableMove = checked
    end)
    windowFrame.chkSavePos = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -145, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.savePositions = checked
    end)
    windowFrame.chkRequireCtrl = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -168, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.requireCtrl = checked
    end)
    windowFrame.chkEnableScale = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -191, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.enableScale = checked
    end)
    windowFrame.chkClampScreen = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -214, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.clampToScreen = checked
        ns:UpdateAllClampStates()
        if ns.UpdateQuestTracker then ns:UpdateQuestTracker() end
    end)
    windowFrame.chkQuickReset = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -237, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.quickReset = checked
    end)
    windowFrame.chkShowTooltip = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -260, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.showTooltip = checked
        if not checked then
            ns:HideHoverTooltip()
        end
    end)

    windowFrame.secTracker = SettingsDialog.buildSectionHeader(windowFrame, -292)

    windowFrame.chkEnableTracker = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -316, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.enableTracker = checked
        if ns.UpdateQuestTracker then ns:UpdateQuestTracker() end
        SettingsDialog.syncTrackerOptionRows(windowFrame)
    end)
    windowFrame.chkHideDefaultTracker = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -339, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.hideDefaultTracker = checked
        if ns.ApplyDefaultTrackerVisibility then ns:ApplyDefaultTrackerVisibility() end
    end)
    windowFrame.chkTrackerTrackAll = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -362, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.trackerTrackAll = checked
        if checked then
            savedDB.trackerHiddenQuests = {}
        end
        if ns.UpdateQuestTracker then ns:UpdateQuestTracker() end
    end)
    windowFrame.chkTrackerShowZone = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -385, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.trackerShowZone = checked
        if ns.UpdateQuestTracker then ns:UpdateQuestTracker() end
    end)
    windowFrame.chkTrackerShowBg = SettingsDialog.buildFlatCheckbox(windowFrame, 20, -408, function(checked)
        local savedDB = ns:InitializeDatabase()
        savedDB.trackerShowBg = checked
        if ns.UpdateQuestTracker then ns:UpdateQuestTracker() end
    end)

    windowFrame.secStatus = SettingsDialog.buildSectionHeader(windowFrame, -440)

    local statusBox = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    statusBox:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 18, -464)
    statusBox:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -18, -464)
    statusBox:SetHeight(74)
    SettingsDialog.commitFlatBackdrop(statusBox, STYLE.bgSub, STYLE.border)

    local statusText = statusBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 12, -10)
    statusText:SetPoint("TOPRIGHT", statusBox, "TOPRIGHT", -12, -10)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(unpack(STYLE.accent))
    windowFrame.statusText = statusText

    local guideText = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guideText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
    guideText:SetPoint("BOTTOMRIGHT", statusBox, "BOTTOMRIGHT", -12, 8)
    guideText:SetJustifyH("LEFT")
    guideText:SetJustifyV("TOP")
    guideText:SetSpacing(3)
    guideText:SetTextColor(unpack(STYLE.textSub))
    windowFrame.guideText = guideText

    windowFrame.secControls = SettingsDialog.buildSectionHeader(windowFrame, -548)

    windowFrame.btnResetPos = SettingsDialog.buildFlatButton(windowFrame, 216, 26, "", function()
        ns:ResetAllPositions()
    end)
    windowFrame.btnResetPos:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 18, -572)

    windowFrame.btnResetScale = SettingsDialog.buildFlatButton(windowFrame, 216, 26, "", function()
        ns:ResetAllScales()
    end)
    windowFrame.btnResetScale:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -18, -572)

    windowFrame.btnResetOpen = SettingsDialog.buildFlatButton(windowFrame, 216, 26, "", function()
        ns:ResetOpenFrames()
    end)
    windowFrame.btnResetOpen:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 18, -602)

    windowFrame.btnRescan = SettingsDialog.buildFlatButton(windowFrame, 216, 26, "", function()
        ns:ScanAllFrames()
    end)
    windowFrame.btnRescan:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -18, -602)

    local footerRegion = CreateFrame("Frame", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    footerRegion:SetPoint("BOTTOMLEFT", windowFrame, "BOTTOMLEFT", 1, 1)
    footerRegion:SetPoint("BOTTOMRIGHT", windowFrame, "BOTTOMRIGHT", -1, 1)
    footerRegion:SetHeight(40)
    SettingsDialog.commitFlatBackdrop(footerRegion, STYLE.bgSub, STYLE.border)

    windowFrame.btnDefaults = SettingsDialog.buildFlatButton(footerRegion, 136, 24, "", function()
        ns:ResetToDefaults()
    end)
    windowFrame.btnDefaults:SetPoint("LEFT", footerRegion, "LEFT", 14, 0)

    windowFrame.btnDonate = SettingsDialog.buildFlatButton(footerRegion, 146, 24, "", function()
        SettingsDialog.openDonateDialog(windowFrame)
    end)
    windowFrame.btnDonate:SetPoint("RIGHT", footerRegion, "RIGHT", -14, 0)

    local footerHint = footerRegion:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerHint:SetPoint("LEFT", windowFrame.btnDefaults, "RIGHT", 6, 0)
    footerHint:SetPoint("RIGHT", windowFrame.btnDonate, "LEFT", -6, 0)
    footerHint:SetJustifyH("CENTER")
    if footerHint.SetWordWrap then footerHint:SetWordWrap(false) end
    footerHint:SetTextColor(unpack(STYLE.textSub))
    windowFrame.footerHint = footerHint

    windowFrame:SetScript("OnShow", function()
        ns:RefreshSettingsUI()
    end)
    windowFrame:SetScript("OnHide", function()
        if windowFrame.langMenu then windowFrame.langMenu:Hide() end
        if donatePopup then donatePopup:Hide() end
    end)

    settingsFrame = windowFrame
    self:RefreshSettingsUI()
    return windowFrame
end

function ns:RefreshSettingsUI()
    local savedDB = self:InitializeDatabase()
    if hoverTooltip then
        hoverTooltip.lastBodyStr = nil
    end
    if settingsFrame then
        local windowFrame = settingsFrame
        windowFrame.title:SetText(self:L("ADDON_TITLE"))
        windowFrame.subtitle:SetText(self:L("ADDON_SUBTITLE"))
        windowFrame.langLabel:SetText(self:L("OPT_LANGUAGE"))

        local langLabel = "Auto"
        for _, item in ipairs(self.SUPPORTED_LANGS) do
            if item.code == (savedDB.lang or "Auto") then
                langLabel = item.label
                break
            end
        end
        windowFrame.langBtn.label:SetText(langLabel .. "  ▾")

        windowFrame.secGeneral.title:SetText(self:L("SECTION_GENERAL"))
        windowFrame.chkEnableMove.label:SetText(self:L("OPT_ENABLE_MOVE"))
        windowFrame.chkEnableMove:SetChecked(savedDB.enableMove ~= false)

        windowFrame.chkSavePos.label:SetText(self:L("OPT_SAVE_POS"))
        windowFrame.chkSavePos:SetChecked(savedDB.savePositions ~= false)

        windowFrame.chkRequireCtrl.label:SetText(self:L("OPT_REQUIRE_CTRL"))
        windowFrame.chkRequireCtrl:SetChecked(savedDB.requireCtrl == true)

        windowFrame.chkEnableScale.label:SetText(self:L("OPT_ENABLE_SCALE"))
        windowFrame.chkEnableScale:SetChecked(savedDB.enableScale ~= false)

        windowFrame.chkClampScreen.label:SetText(self:L("OPT_CLAMP_SCREEN"))
        windowFrame.chkClampScreen:SetChecked(savedDB.clampToScreen ~= false)

        windowFrame.chkQuickReset.label:SetText(self:L("OPT_QUICK_RESET"))
        windowFrame.chkQuickReset:SetChecked(savedDB.quickReset ~= false)

        windowFrame.chkShowTooltip.label:SetText(self:L("OPT_SHOW_TOOLTIP"))
        windowFrame.chkShowTooltip:SetChecked(savedDB.showTooltip ~= false)

        windowFrame.secTracker.title:SetText(self:L("SECTION_TRACKER"))
        windowFrame.chkEnableTracker.label:SetText(self:L("OPT_ENABLE_TRACKER"))
        windowFrame.chkEnableTracker:SetChecked(savedDB.enableTracker ~= false)

        windowFrame.chkHideDefaultTracker.label:SetText(self:L("OPT_HIDE_DEFAULT_TRACKER"))
        windowFrame.chkHideDefaultTracker:SetChecked(savedDB.hideDefaultTracker ~= false)

        windowFrame.chkTrackerTrackAll.label:SetText(self:L("OPT_TRACKER_ALL_QUESTS"))
        windowFrame.chkTrackerTrackAll:SetChecked(savedDB.trackerTrackAll ~= false)

        windowFrame.chkTrackerShowZone.label:SetText(self:L("OPT_TRACKER_SHOW_ZONE"))
        windowFrame.chkTrackerShowZone:SetChecked(savedDB.trackerShowZone ~= false)

        windowFrame.chkTrackerShowBg.label:SetText(self:L("OPT_TRACKER_SHOW_BG"))
        windowFrame.chkTrackerShowBg:SetChecked(savedDB.trackerShowBg ~= false)
        SettingsDialog.syncTrackerOptionRows(windowFrame)

        windowFrame.secStatus.title:SetText(self:L("SECTION_STATUS"))
        local hookedCount, posCount, scaleCount = self:ComputeManagedFrameStatistics()
        windowFrame.statusText:SetText(string.format(self:L("STATUS_FORMAT"), hookedCount, posCount, scaleCount))
        windowFrame.guideText:SetText(self:L("GUIDE_TEXT"))

        windowFrame.secControls.title:SetText(self:L("SECTION_CONTROLS"))
        windowFrame.btnResetPos.label:SetText(self:L("BTN_RESET_POS"))
        windowFrame.btnResetScale.label:SetText(self:L("BTN_RESET_SCALE"))
        windowFrame.btnResetOpen.label:SetText(self:L("BTN_RESET_OPEN"))
        windowFrame.btnRescan.label:SetText(self:L("BTN_RESCAN"))

        windowFrame.btnDefaults.label:SetText(self:L("BTN_RESET_DEFAULTS"))
        windowFrame.footerHint:SetText(self:L("HINT_FOOTER"))
        windowFrame.btnDonate.label:SetText(self:L("BTN_DONATE"))
    end

    if self.UpdateQuestTracker then
        self:UpdateQuestTracker()
    end

    if self.canvasPanel and self.canvasPanel.RefreshTexts then
        self.canvasPanel:RefreshTexts()
    end
end

function ns:ToggleSettings()
    local windowFrame = self:CreateSettingsWindow()
    if windowFrame:IsShown() then
        windowFrame:Hide()
    else
        self:RefreshSettingsUI()
        windowFrame:Show()
    end
end

function ns:RegisterBlizzardCanvas()
    if self.canvasPanel then return end

    local panelFrameEntry = CreateFrame("Frame", "EzWoWFrameMoverCanvasPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Frame Mover"

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(ICON_PATH)

    local titleStr = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleStr:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    titleStr:SetTextColor(unpack(STYLE.accent))

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(4)
    desc:SetTextColor(unpack(STYLE.text))

    local launchBtn = SettingsDialog.buildFlatButton(panelFrameEntry, 220, 28, "", function()
        ns:ToggleSettings()
    end)
    launchBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

    local slashInfo = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slashInfo:SetPoint("TOPLEFT", launchBtn, "BOTTOMLEFT", 0, -14)
    slashInfo:SetTextColor(unpack(STYLE.textSub))

    function panelFrameEntry:RefreshTexts()
        titleStr:SetText(ns:L("ADDON_TITLE"))
        desc:SetText(ns:L("CANVAS_DESC"))
        launchBtn.label:SetText(ns:L("CANVAS_OPEN_BTN"))
        slashInfo:SetText(ns:L("CANVAS_SLASH_INFO"))
    end

    panelFrameEntry:SetScript("OnShow", function(self)
        self:RefreshTexts()
    end)
    panelFrameEntry:RefreshTexts()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local isCallOk, category = pcall(Settings.RegisterCanvasLayoutCategory, panelFrameEntry, panelFrameEntry.name)
        if isCallOk and category then
            pcall(Settings.RegisterAddOnCategory, category)
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panelFrameEntry)
    end

    self.canvasPanel = panelFrameEntry
end

function ns:InitUI()
    self:RegisterBlizzardCanvas()
end

SLASH_EZWOWFRAMEMOVER1 = "/ezfm"
SLASH_EZWOWFRAMEMOVER2 = "/framemover"
SLASH_EZWOWFRAMEMOVER3 = "/창이동"

SlashCmdList["EZWOWFRAMEMOVER"] = function(msg)
    local cmd = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
    if cmd == "reset" or cmd == "초기화" then
        ns:ResetAllPositions()
        ns:ResetAllScales()
    elseif cmd == "scan" or cmd == "스캔" then
        ns:ScanAllFrames()
    else
        ns:ToggleSettings()
    end
end
