--===========================================================================
-- EzWoW - Frame Mover
-- Modules/MoverEngine.lua : Universal Blizzard Frame Dragging, Wheel Scaling & Combat Queue
--===========================================================================
local ADDON_NAME, ns = ...

local FrameDragController = ns.FrameDragController or {}
ns.FrameDragController = FrameDragController
local hasInCombat = ns.IsInCombatLockdownState
local hasFrameObject = ns.IsValidUIFrameObject
local runNext = ns.RunOnNextFrameTick
local resolveMouseFocusList = ns.CollectHoveredFrameStack
local untaintedSetNil = ns.ClearTableKeyUntainted
local returnFalse = ns.AlwaysReturnFalse

local ADDON_NAME, ns = ...

ns.VERSION = "1.1.0"
ns.DONATE_URL = "https://www.paypal.com/ncp/payment/5KM693JWNN65C"

ns.DEFAULTS = {
    lang = "Auto",
    enableMove = true,
    savePositions = true,
    requireCtrl = false,
    enableScale = true,
    clampToScreen = true,
    quickReset = true,
    showTooltip = true,
    enableTracker = true,
    hideDefaultTracker = true,
    trackerTrackAll = true,
    trackerShowZone = true,
    trackerShowBg = true,
    trackerExpanded = true,
    trackerWidth = 270,
    trackerHeight = 360,
    trackerCollapsedZones = {},
    trackerCollapsedQuests = {},
    trackerHiddenQuests = {},
    trackerWatchedQuests = {},
    positions = {},
    scales = {},
}

ns.FrameData = {}
ns.FrameRegistry = {}
ns.MoveHandles = {}
ns.CurrentMouseoverFrames = {}
ns.CombatQueue = {}
ns.SetPointsQueue = {}
ns.SessionScales = {}
ns.hookedFrames = {}

local MIN_SCALE = 0.50
local MAX_SCALE = 1.50
local SCALE_STEP = 0.05

local ignoreSetPointHook = false

local okFake, secureRootParent = pcall(CreateFrame, "Frame", "EzWoW_FrameMover_FakeUIParent", nil, "SecureFrameTemplate")
if not okFake or not secureRootParent then
    secureRootParent = CreateFrame("Frame", "EzWoW_FrameMover_FakeUIParent", UIParent)
end
secureRootParent:SetAllPoints(UIParent)
ns.FakeUIParent = secureRootParent

local okSec, secureFrame = pcall(CreateFrame, "Frame", nil, nil, "SecureHandlerBaseTemplate")
if not okSec then
    secureFrame = nil
end

function FrameDragController.readCurrentFrameAnchors(frame)
    if not frame or not frame.GetNumPoints then return nil end
    local numPoints = frame:GetNumPoints()
    if not numPoints or numPoints == 0 then return nil end

    local pts = {}
    for index = 1, numPoints do
        local anchorPoint, relativeFrame, relativePoint, offX, offY = frame:GetPoint(index)
        if anchorPoint then
            local anchorTarget = {
                anchorPoint = anchorPoint,
                relativeFrame = relativeFrame,
                relativePoint = relativePoint or anchorPoint,
                offX = offX or 0,
                offY = offY or 0,
            }
            if ns:GetFrameName(relativeFrame) then
                anchorTarget.relativeFrameName = ns:GetFrameName(relativeFrame)
            elseif type(relativeFrame) == "table" and relativeFrame.GetName and relativeFrame:GetName() then
                anchorTarget.relativeFrameName = relativeFrame:GetName()
            end
            pts[#pts + 1] = anchorTarget
        end
    end
    return pts
end

function FrameDragController.computeAbsoluteScreenAnchor(frame)
    if not frame then return nil end
    local calculateCanvasScale = frame:GetScale()
    if not calculateCanvasScale or calculateCanvasScale <= 0 then return nil end
    if not frame:GetLeft() or not frame:GetTop() or not frame:GetRight() or not frame:GetBottom() then
        return nil
    end

    local left, top = frame:GetLeft() * calculateCanvasScale, frame:GetTop() * calculateCanvasScale
    local right, bottom = frame:GetRight() * calculateCanvasScale, frame:GetBottom() * calculateCanvasScale
    local parentWidth = GetScreenWidth and GetScreenWidth() or UIParent:GetWidth()
    local parentHeight = GetScreenHeight and GetScreenHeight() or UIParent:GetHeight()

    local hOffsetCenter = (left + right) / 2 - parentWidth / 2
    local vOffsetCenter = (top + bottom) / 2 - parentHeight / 2

    local coordX, coordY, point = 0, 0, ""
    if left < (parentWidth - right) and left < math.abs(hOffsetCenter) then
        coordX = left
        point = "LEFT"
    elseif (parentWidth - right) < math.abs(hOffsetCenter) then
        coordX = right - parentWidth
        point = "RIGHT"
    else
        coordX = hOffsetCenter
    end

    if bottom < (parentHeight - top) and bottom < math.abs(vOffsetCenter) then
        coordY = bottom
        point = "BOTTOM" .. point
    elseif (parentHeight - top) < math.abs(vOffsetCenter) then
        coordY = top - parentHeight
        point = "TOP" .. point
    else
        coordY = vOffsetCenter
    end

    if point == "" then
        point = "CENTER"
    end

    return {
        {
            anchorPoint = point,
            relativeFrame = "EzWoW_FrameMover_FakeUIParent",
            relativePoint = point,
            offX = coordX,
            offY = coordY,
        },
    }
end

function FrameDragController.applySavedFrameAnchors(frame, framePoints, raw, skipUI)
    if not frame then return false end
    if hasInCombat() and frame:IsProtected() then return false end

    if framePoints and framePoints[1] then
        local fdVal = ns.FrameData[frame]
        local useSecure = secureFrame and secureFrame.Execute and not hasInCombat() and (fdVal and fdVal.UseSecureCursorDrag)
        local assignPoint = frame.SetPointBase or frame.SetPoint
        local calculateCanvasScale = (raw and 1) or frame:GetScale() or 1
        if calculateCanvasScale <= 0 then calculateCanvasScale = 1 end

        ignoreSetPointHook = true
        if useSecure then
            local clearedOk = pcall(function()
                secureFrame:SetFrameRef("frame", frame)
                secureFrame:Execute([[ self:GetFrameRef('frame'):ClearAllPoints(); ]])
            end)
            if not clearedOk then
                pcall(frame.ClearAllPoints, frame)
            end
        else
            pcall(frame.ClearAllPoints, frame)
        end
        ignoreSetPointHook = false

        for _, anchorPointEntry in ipairs(framePoints) do
            ignoreSetPointHook = true
            local relativeFrame = anchorPointEntry.relativeFrame
            if type(relativeFrame) == "string" then
                if relativeFrame == "EzWoW_FrameMover_FakeUIParent" then
                    relativeFrame = secureRootParent
                else
                    relativeFrame = _G[relativeFrame] or ns:GetFrameFromName(relativeFrame)
                end
            end
            if relativeFrame == UIParent then
                relativeFrame = secureRootParent
            end

            local hasRelExplicitProtected = false
            if relativeFrame and relativeFrame.IsProtected then
                local isCallOk, _, explicit = pcall(relativeFrame.IsProtected, relativeFrame)
                hasRelExplicitProtected = isCallOk and explicit or false
            end

            local executedSecure = false
            if secureFrame and secureFrame.Execute and not hasInCombat() and (useSecure or not relativeFrame or hasRelExplicitProtected) then
                executedSecure = pcall(function()
                    secureFrame:SetFrameRef("frame", frame)
                    if relativeFrame then
                        secureFrame:SetFrameRef("relativeFrame", relativeFrame)
                    end
                    secureFrame:SetAttribute("hasRelativeFrame", relativeFrame and true or false)
                    secureFrame:SetAttribute("anchorPoint", anchorPointEntry.anchorPoint)
                    secureFrame:SetAttribute("relativePoint", anchorPointEntry.relativePoint or anchorPointEntry.anchorPoint)
                    secureFrame:SetAttribute("offX", (anchorPointEntry.offX or 0) / calculateCanvasScale)
                    secureFrame:SetAttribute("offY", (anchorPointEntry.offY or 0) / calculateCanvasScale)
                    secureFrame:Execute([[
                        local frame = self:GetFrameRef('frame');
                        local relativeFrame;
                        if self:GetAttribute('hasRelativeFrame') then
                            relativeFrame = self:GetFrameRef('relativeFrame');
                        end
                        local anchorPoint = self:GetAttribute('anchorPoint');
                        local relativePoint = self:GetAttribute('relativePoint');
                        local offX = self:GetAttribute('offX');
                        local offY = self:GetAttribute('offY');
                        frame:SetPoint(anchorPoint, relativeFrame, relativePoint, offX, offY);
                    ]])
                end)
            end
            if not executedSecure then
                pcall(assignPoint, frame, anchorPointEntry.anchorPoint, relativeFrame, anchorPointEntry.relativePoint or anchorPointEntry.anchorPoint, (anchorPointEntry.offX or 0) / calculateCanvasScale, (anchorPointEntry.offY or 0) / calculateCanvasScale)
            end
            ignoreSetPointHook = false
        end
    end

    if not skipUI and ns.RefreshSettingsUI then
        ns:RefreshSettingsUI()
    end
    return true
end

function FrameDragController.resolveFrameScale(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage then return (frame and frame:GetScale()) or 1 end
    local parentScale = (fdVal.storage.frameParent and not fdVal.ManuallyScaleWithParent and FrameDragController.resolveFrameScale(fdVal.storage.frameParent)) or 1
    return (frame:GetScale() or 1) * parentScale
end

function ns:GetFrameScalePct(frame)
    return math.floor((FrameDragController.resolveFrameScale(frame) or 1) * 100 + 0.5)
end

function FrameDragController.assignFrameScaleSubs(frame, oldScale, newScale)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.SubFrames then return end
    for _, subData in pairs(fdVal.SubFrames) do
        if subData.storage then
            local subFrame = subData.storage.frame
            if subFrame then
                if subData.ManuallyScaleWithParent and not subData.storage.detached then
                    pcall(subFrame.SetScale, subFrame, (subFrame:GetScale() / oldScale) * newScale)
                elseif not subData.ManuallyScaleWithParent and subData.storage.detached then
                    pcall(subFrame.SetScale, subFrame, (oldScale * subFrame:GetScale()) / newScale)
                else
                    FrameDragController.assignFrameScaleSubs(subFrame, oldScale, newScale)
                end
            end
        end
    end
end

function FrameDragController.applyClampedFrameScale(frame, frameScale, showToast)
    if not frame then return false end
    if hasInCombat() and frame:IsProtected() then return true end
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage then return false end

    local oldScale = FrameDragController.resolveFrameScale(frame)
    local newScale = math.floor(frameScale * 100 + 0.5) / 100
    if newScale < MIN_SCALE then newScale = MIN_SCALE end
    if newScale > MAX_SCALE then newScale = MAX_SCALE end

    if fdVal.storage.detached and fdVal.storage.frameParent then
        local parentScale = FrameDragController.resolveFrameScale(fdVal.storage.frameParent)
        newScale = fdVal.ManuallyScaleWithParent and newScale or (newScale / parentScale)
    elseif fdVal.ManuallyScaleWithParent and fdVal.storage.frameParent then
        newScale = FrameDragController.resolveFrameScale(fdVal.storage.frameParent)
    end

    local savedDB = ns:InitializeDatabase()
    local frameName = fdVal.storage.frameName
    if math.abs(newScale - 1.0) < 0.005 then
        savedDB.scales[frameName] = nil
        ns.SessionScales[frameName] = nil
    else
        savedDB.scales[frameName] = newScale
        ns.SessionScales[frameName] = newScale
    end

    local scaledSecure = false
    if secureFrame and secureFrame.Execute and not hasInCombat() and (fdVal.UseSecureCursorDrag or frame:IsProtected()) then
        scaledSecure = pcall(function()
            secureFrame:SetFrameRef("frame", frame)
            secureFrame:SetAttribute("newScale", newScale)
            secureFrame:Execute([[
                local frame = self:GetFrameRef('frame');
                if frame and frame.SetScale then
                    frame:SetScale(self:GetAttribute('newScale'));
                end
            ]])
        end)
    end
    if not scaledSecure or math.abs((frame:GetScale() or 1) - newScale) > 0.01 then
        pcall(frame.SetScale, frame, newScale)
    end
    FrameDragController.assignFrameScaleSubs(frame, oldScale, newScale)

    if showToast and ns.ShowScaleToast then
        ns:ShowScaleToast(frameName, math.floor(newScale * 100 + 0.5))
    end
    if ns.RefreshSettingsUI then
        ns:RefreshSettingsUI()
    end
    return true
end

function FrameDragController.assignFrameParentSubs(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.SubFrames then return true end
    local returnValue = true
    for subName, subData in pairs(fdVal.SubFrames) do
        local subFrame = ns:GetFrameFromName(subName)
        if subFrame then
            if subData.ForceParentage and subFrame.GetParent and subFrame.SetParent and subFrame:GetParent() ~= frame then
                pcall(subFrame.SetParent, subFrame, frame)
            elseif subData.ForceParentage then
                returnValue = false
            end
            returnValue = FrameDragController.assignFrameParentSubs(subFrame) and returnValue
        end
    end
    return returnValue
end

function FrameDragController.assignFrameParent(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage then return true end
    return (fdVal.storage.frameParent and FrameDragController.assignFrameParent(fdVal.storage.frameParent)) or FrameDragController.assignFrameParentSubs(frame)
end

local secureDragUpdater = CreateFrame("Frame")
local secureDragState = nil

function FrameDragController.stopSecureDrag()
    secureDragUpdater:SetScript("OnUpdate", nil)
    secureDragState = nil
end

function FrameDragController.startSecureDrag(frame)
    if not frame or type(GetCursorPosition) ~= "function" then return false end
    if hasInCombat() and frame:IsProtected() then return false end
    local startPos = FrameDragController.computeAbsoluteScreenAnchor(frame)
    if not startPos or not startPos[1] then return false end
    local startX, startY = GetCursorPosition()
    if not startX or not startY then return false end

    secureDragState = {
        frame = frame,
        startPt = startPos[1],
        startX = startX,
        startY = startY,
    }

    secureDragUpdater:SetScript("OnUpdate", function()
        if not secureDragState or not secureDragState.frame then
            FrameDragController.stopSecureDrag()
            return
        end
        local windowFrame = secureDragState.frame
        if (hasInCombat() and windowFrame:IsProtected()) or (windowFrame.IsShown and not windowFrame:IsShown()) then
            FrameDragController.stopSecureDrag()
            return
        end
        local posX, posY = GetCursorPosition()
        if not posX or not posY then return end
        local uiEffScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if uiEffScale <= 0 then uiEffScale = 1 end
        local dxVal = (posX - secureDragState.startX) / uiEffScale
        local dyVal = (posY - secureDragState.startY) / uiEffScale
        local spawnCoord = secureDragState.startPt
        FrameDragController.applySavedFrameAnchors(windowFrame, {
            {
                anchorPoint = spawnCoord.anchorPoint,
                relativeFrame = spawnCoord.relativeFrame,
                relativePoint = spawnCoord.relativePoint,
                offX = (spawnCoord.offX or 0) + dxVal,
                offY = (spawnCoord.offY or 0) + dyVal,
            },
        }, false, true)
    end)
    return true
end

function FrameDragController.startMoving(frameOrHandle)
    if ns.MoveHandles[frameOrHandle] then
        untaintedSetNil(frameOrHandle, "onDragStartCallback")
        return
    end
    local fdVal = ns.FrameData[frameOrHandle]
    if fdVal and fdVal.UseSecureCursorDrag then
        FrameDragController.startSecureDrag(frameOrHandle)
        return
    end
    pcall(frameOrHandle.StartMoving, frameOrHandle)
end

function FrameDragController.stopMoving(frameOrHandle)
    if ns.MoveHandles[frameOrHandle] then
        frameOrHandle.onDragStartCallback = returnFalse
        return
    end
    local fdVal = ns.FrameData[frameOrHandle]
    if fdVal and fdVal.UseSecureCursorDrag then
        FrameDragController.stopSecureDrag()
        return
    end
    pcall(frameOrHandle.StopMovingOrSizing, frameOrHandle)
end

function ns:EnqueuePostCombatCallback(func, ...)
    self.CombatQueue[#self.CombatQueue + 1] = { func = func, args = { ... } }
end

function ns:FlushPostCombatCallbackQueue()
    if hasInCombat() or #self.CombatQueue == 0 then return end
    for index = 1, #self.CombatQueue do
        local item = self.CombatQueue[index]
        if item and item.func then
            item.func(unpack(item.args))
        end
    end
    wipe(self.CombatQueue)
end

function ns:EnqueueDeferredAnchorRestore(frame, framePoints)
    if self.SetPointsQueue[frame] then return end
    self.SetPointsQueue[frame] = framePoints
    runNext(function()
        self:FlushDeferredAnchorRestoreQueue()
    end)
end

function ns:FlushDeferredAnchorRestoreQueue()
    for frame, framePoints in pairs(self.SetPointsQueue) do
        if hasInCombat() and frame:IsProtected() then
            self:EnqueuePostCombatCallback(FrameDragController.applySavedFrameAnchors, frame, framePoints)
        else
            FrameDragController.applySavedFrameAnchors(frame, framePoints)
        end
    end
    wipe(self.SetPointsQueue)
end

local doOnMouseDown, doOnMouseUp, onMouseDown, onMouseUp, onMouseWheel, handleFrameShowEvent, onSubFrameHide, handleFrameMouseEnter, handleFrameMouseLeave, onSetPoint, onSizeUpdate

function onMouseDown(frame, button)
    local moveHandle = ns.MoveHandles[frame] and frame or nil
    if moveHandle then
        frame = moveHandle:GetParent()
    end
    return doOnMouseDown(frame, button, moveHandle)
end

function doOnMouseDown(frame, button, moveHandle)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return false end

    local savedDB = ns:InitializeDatabase()
    if not savedDB.enableMove then return false end

    local returnValue = false
    local parentReturnValue = false
    ns:SetupPointStorage(frame)

    if button == "LeftButton" then
        if not moveHandle and IsAltKeyDown and IsAltKeyDown() and fdVal.Detachable and not fdVal.storage.detached then
            fdVal.storage.points.detachPoints = FrameDragController.readCurrentFrameAnchors(frame)
            fdVal.storage.detached = true
            returnValue = true
            if PlaySound then
                pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN) or 839)
            end
        end

        if not fdVal.storage.detached then
            parentReturnValue = (fdVal.storage.frameParent and doOnMouseDown(fdVal.storage.frameParent, button, moveHandle)) or false
        end

        if (fdVal.storage.detached or not parentReturnValue) and (not savedDB.requireCtrl or (IsControlKeyDown and IsControlKeyDown())) then
            if fdVal.UseSecureCursorDrag then
                if hasInCombat() and frame:IsProtected() then return false end
                fdVal.storage.points.startPoints = fdVal.storage.points.startPoints or FrameDragController.computeAbsoluteScreenAnchor(frame)
                if FrameDragController.startSecureDrag(frame) then
                    fdVal.storage.isMoving = true
                    returnValue = true
                end
            else
                local userPlaced = frame.IsUserPlaced and frame:IsUserPlaced()
                pcall(frame.SetMovable, frame, true)
                FrameDragController.startMoving(moveHandle or frame)
                if frame.SetUserPlaced then
                    pcall(frame.SetUserPlaced, frame, userPlaced)
                end
                fdVal.storage.points.startPoints = fdVal.storage.points.startPoints or FrameDragController.computeAbsoluteScreenAnchor(frame)
                fdVal.storage.isMoving = true
                returnValue = true
            end
        end
    end

    if (returnValue or parentReturnValue) and ns.HideHoverTooltip then
        ns:HideHoverTooltip()
    end

    return returnValue or parentReturnValue
end

function onMouseUp(frame, button)
    local moveHandle = ns.MoveHandles[frame] and frame or nil
    if moveHandle then
        frame = moveHandle:GetParent()
    end
    return doOnMouseUp(frame, button, moveHandle)
end

function doOnMouseUp(frame, button, moveHandle)
    if moveHandle then FrameDragController.stopMoving(moveHandle) end
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return false end

    local returnValue = false
    local parentReturnValue = false

    if not fdVal.storage.detached then
        parentReturnValue = (fdVal.storage.frameParent and doOnMouseUp(fdVal.storage.frameParent, button, moveHandle)) or false
    end

    if fdVal.storage.detached or not parentReturnValue then
        if button == "LeftButton" and fdVal.storage.isMoving then
            FrameDragController.stopMoving(moveHandle or frame)

            ns:SetupPointStorage(frame)
            fdVal.storage.points.dragPoints = FrameDragController.computeAbsoluteScreenAnchor(frame)
            fdVal.storage.points.dragged = true
            fdVal.storage.isMoving = nil
            local savedDB = ns:InitializeDatabase()
            if savedDB.savePositions ~= false and fdVal.storage.frameName then
                savedDB.positions[fdVal.storage.frameName] = fdVal.storage.points
            end
            returnValue = true

            if fdVal.storage.points.dragPoints then
                FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.dragPoints)
            end
        elseif button == "RightButton" then
            local savedDB = ns:InitializeDatabase()
            if savedDB.quickReset ~= false then
                local hasCtrl = IsControlKeyDown and IsControlKeyDown()
                local hasAlt = IsAltKeyDown and IsAltKeyDown()
                local hasShift = IsShiftKeyDown and IsShiftKeyDown()

                if hasCtrl and hasAlt then
                    ns:ResetFrame(fdVal.storage.frameName)
                    return true
                end

                local fullReset = false
                if hasAlt and fdVal.storage.detached then
                    if FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.detachPoints, true) then
                        fdVal.storage.points.detachPoints = nil
                        fdVal.storage.detached = nil
                        returnValue = true
                        fullReset = true
                        if PlaySound then
                            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE) or 840)
                        end
                    end
                end

                if hasCtrl or fullReset then
                    returnValue = FrameDragController.applyClampedFrameScale(frame, 1.0, true) or returnValue
                end

                if hasShift or fullReset then
                    if fdVal.storage.points then
                        if not fullReset and fdVal.storage.points.startPoints then
                            FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.startPoints)
                            fdVal.storage.points.startPoints = nil
                        end
                        fdVal.storage.points.dragPoints = nil
                        fdVal.storage.points.dragged = nil
                    end
                    returnValue = true
                    if type(UpdateUIPanelPositions) == "function" then
                        pcall(UpdateUIPanelPositions, frame)
                    end
                end
            end
            returnValue = true
        end
    end

    return returnValue or parentReturnValue
end

function onMouseWheel(frame, delta, ...)
    local savedDB = ns:InitializeDatabase()
    if savedDB.enableScale == false or not (IsControlKeyDown and IsControlKeyDown()) then return false end
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return false end

    local returnValue = false
    local parentReturnValue = false

    if not fdVal.storage.detached then
        parentReturnValue = (fdVal.storage.frameParent and onMouseWheel(fdVal.storage.frameParent, delta, ...)) or false
    end

    if fdVal.storage.detached or not parentReturnValue then
        local oldScale = FrameDragController.resolveFrameScale(frame) or 1.0
        local newScale = oldScale + SCALE_STEP * (delta > 0 and 1 or -1)
        returnValue = FrameDragController.applyClampedFrameScale(frame, newScale, true) or returnValue
    end

    return returnValue or parentReturnValue
end

function handleFrameShowEvent(frame, skipNextFrame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return end

    if hasInCombat() and frame:IsProtected() then
        ns:EnqueuePostCombatCallback(handleFrameShowEvent, frame)
        return
    end

    FrameDragController.assignFrameParent(frame)

    if type(fdVal.SubFrames) == "table" then
        for subFrameName, subFrameData in pairs(fdVal.SubFrames) do
            if type(subFrameData) == "table" and not (subFrameData.storage and subFrameData.storage.hooked) then
                if ns:GetFrameFromName(subFrameName) then
                    ns:ProcessFrameTree(subFrameName, subFrameData, frame, true)
                end
            end
        end
    end

    local savedDB = ns:InitializeDatabase()
    local frameName = ns:GetFrameName(frame)
    if frameName and savedDB.scales[frameName] then
        FrameDragController.applyClampedFrameScale(frame, savedDB.scales[frameName], false)
    elseif frameName and ns.SessionScales[frameName] then
        FrameDragController.applyClampedFrameScale(frame, ns.SessionScales[frameName], false)
    end

    onSetPoint(frame)

    if not skipNextFrame then
        runNext(function() handleFrameShowEvent(frame, true) end)
    end
end

function onSubFrameHide(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return end
    local parentFrame = fdVal.storage.frameParent
    if parentFrame then return onSubFrameHide(parentFrame) end
    if fdVal.storage.isMoving then
        if fdVal.UseSecureCursorDrag then
            doOnMouseUp(frame, "LeftButton")
        else
            ns:WaitForGlobalMouseUp(frame)
        end
    end
end

function handleFrameMouseEnter(frame)
    local moveHandle = ns.MoveHandles[frame] and frame or nil
    if moveHandle then
        frame = moveHandle:GetParent()
    end
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled then return end
    ns.CurrentMouseoverFrames[frame] = true
    ns:CheckMouseWheelCapture()
end

function handleFrameMouseLeave(frame)
    local moveHandle = ns.MoveHandles[frame] and frame or nil
    if moveHandle then
        frame = moveHandle:GetParent()
    end
    if not ns.CurrentMouseoverFrames[frame] then return end
    if frame and frame.IsMouseOver and frame:IsMouseOver() then
        ns:CheckMouseWheelCapture()
        return
    end
    ns.CurrentMouseoverFrames[frame] = nil
    ns:CheckMouseWheelCapture()
end

function onSetPoint(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled or ignoreSetPointHook then return end
    local savedDB = ns:InitializeDatabase()
    if not savedDB.enableMove then return end

    if fdVal.IgnoreSavedPositionWhenMaximized and frame.IsMaximized and frame:IsMaximized() then
        return
    end

    ns:SetupPointStorage(frame)

    if fdVal.storage.points and fdVal.storage.points.dragged and fdVal.storage.points.dragPoints and (not fdVal.storage.frameParent or fdVal.storage.detached) then
        if hasInCombat() and frame:IsProtected() then
            ns:EnqueuePostCombatCallback(FrameDragController.applySavedFrameAnchors, frame, fdVal.storage.points.dragPoints)
        else
            FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.dragPoints)
        end
    end
end

function onSizeUpdate(frame)
    local fdVal = ns.FrameData[frame]
    if not fdVal or not fdVal.storage or fdVal.storage.disabled or fdVal.UseSecureCursorDrag then return end
    if frame:IsProtected() and hasInCombat() then
        ns:EnqueuePostCombatCallback(onSizeUpdate, frame)
        return
    end
    local clampDistance = 40
    local clampWidth = (frame:GetWidth() - clampDistance) or 0
    local clampHeight = (frame:GetHeight() - clampDistance) or 0
    if frame.SetClampRectInsets then
        pcall(frame.SetClampRectInsets, frame, clampWidth, -clampWidth, -clampHeight, clampHeight)
    end
end

local wheelCaptureFrame
local mouseUpListenerFrame

function ns:GetHoveredMovableFrame()
    if secureDragState ~= nil then return nil end
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
        return nil
    end

    local foci = resolveMouseFocusList()
    local top = foci[1]
    if not top or top == _G.WorldFrame or top == UIParent then
        return nil
    end

    if not self.MoveHandles[top] and not self.FrameData[top] then
        if top.IsObjectType and (top:IsObjectType("Button") or top:IsObjectType("EditBox") or top:IsObjectType("Slider") or top:IsObjectType("ScrollFrame")) then
            return nil
        end
    end

    for _, windowFrame in ipairs(foci) do
        if self.MoveHandles[windowFrame] then
            windowFrame = windowFrame:GetParent()
        end
        local fdVal = windowFrame and self.FrameData[windowFrame]
        if fdVal and not fdVal.IgnoreMouse and not fdVal.NonDraggable and fdVal.storage and not fdVal.storage.disabled then
            local root = self:GetRootFrame(windowFrame)
            local rootFd = root and self.FrameData[root]
            if fdVal.storage.isMoving or (rootFd and rootFd.storage and rootFd.storage.isMoving) then
                return nil
            end
            return windowFrame
        end
    end

    local currentState = top.GetParent and top:GetParent() or nil
    while currentState and currentState ~= UIParent do
        local fdVal = self.FrameData[currentState]
        if fdVal and not fdVal.IgnoreMouse and not fdVal.NonDraggable and fdVal.storage and not fdVal.storage.disabled then
            local root = self:GetRootFrame(currentState)
            local rootFd = root and self.FrameData[root]
            if fdVal.storage.isMoving or (rootFd and rootFd.storage and rootFd.storage.isMoving) then
                return nil
            end
            return currentState
        end
        currentState = currentState.GetParent and currentState:GetParent() or nil
    end

    return nil
end

function ns:InitMouseWheelCaptureFrame()
    if wheelCaptureFrame then return end
    wheelCaptureFrame = CreateFrame("Frame")
    wheelCaptureFrame:SetPoint("TOPLEFT", nil)
    wheelCaptureFrame:SetPoint("BOTTOMRIGHT", nil)
    local wheelPollElapsed = 0
    wheelCaptureFrame:SetScript("OnUpdate", function(_, elapsed)
        wheelPollElapsed = wheelPollElapsed + (elapsed or 0)
        if wheelPollElapsed < 0.05 then return end
        wheelPollElapsed = 0
        ns:CheckMouseWheelCapture()
    end)
    wheelCaptureFrame:SetScript("OnEvent", function() ns:CheckMouseWheelCapture() end)
    pcall(wheelCaptureFrame.RegisterEvent, wheelCaptureFrame, "MODIFIER_STATE_CHANGED")
    wheelCaptureFrame:SetScript("OnMouseWheel", function(_, delta)
        for _, windowFrame in ipairs(resolveMouseFocusList()) do
            if self.MoveHandles[windowFrame] then
                windowFrame = windowFrame:GetParent()
            end
            local fdVal = windowFrame and self.FrameData[windowFrame]
            if fdVal and not (fdVal.IgnoreMouse or fdVal.IgnoreMouseWheel) and fdVal.storage and not fdVal.storage.disabled then
                onMouseWheel(windowFrame, delta)
                break
            end
        end
    end)
    wheelCaptureFrame:EnableMouse(false)
    wheelCaptureFrame:EnableMouseWheel(false)
end

function ns:CheckMouseWheelCapture()
    if not wheelCaptureFrame then return end
    for windowFrame in pairs(self.CurrentMouseoverFrames) do
        if not (windowFrame and windowFrame.IsShown and windowFrame:IsShown() and windowFrame.IsMouseOver and windowFrame:IsMouseOver()) then
            self.CurrentMouseoverFrames[windowFrame] = nil
        end
    end
    local savedDB = self:InitializeDatabase()
    local shouldCapture = false
    if savedDB.enableScale ~= false and IsControlKeyDown and IsControlKeyDown() and next(self.CurrentMouseoverFrames) then
        for _, windowFrame in ipairs(resolveMouseFocusList()) do
            if self.MoveHandles[windowFrame] then
                windowFrame = windowFrame:GetParent()
            end
            local fdVal = windowFrame and self.FrameData[windowFrame]
            if fdVal and not (fdVal.IgnoreMouse or fdVal.IgnoreMouseWheel) and fdVal.storage and not fdVal.storage.disabled then
                shouldCapture = true
                break
            elseif windowFrame and windowFrame.IsMouseWheelEnabled and windowFrame:IsMouseWheelEnabled() then
                shouldCapture = false
                break
            end
        end
    end
    if shouldCapture and not wheelCaptureFrame:IsMouseWheelEnabled() then
        wheelCaptureFrame:EnableMouseWheel(true)
    elseif not shouldCapture and wheelCaptureFrame:IsMouseWheelEnabled() then
        wheelCaptureFrame:EnableMouseWheel(false)
    end
    if self.UpdateHoverTooltip then
        self:UpdateHoverTooltip()
    end
end

function ns:WaitForGlobalMouseUp(frame)
    if not mouseUpListenerFrame then
        mouseUpListenerFrame = CreateFrame("Frame")
        mouseUpListenerFrame:SetScript("OnEvent", function(_, _, button)
            if button ~= "LeftButton" then return end
            mouseUpListenerFrame:UnregisterEvent("GLOBAL_MOUSE_UP")
            if not mouseUpListenerFrame.targetFrame then return end
            local tfVal = mouseUpListenerFrame.targetFrame
            mouseUpListenerFrame.targetFrame = nil
            local fdVal = self.FrameData[tfVal]
            local handle = fdVal and fdVal.moveHandles and fdVal.moveHandles[1]
            doOnMouseUp(tfVal, button, handle)
        end)
    end
    mouseUpListenerFrame.targetFrame = frame
    pcall(mouseUpListenerFrame.RegisterEvent, mouseUpListenerFrame, "GLOBAL_MOUSE_UP")
end

local hookedScripts = setmetatable({}, { __mode = "k" })

function FrameDragController.bindFrameScript(frame, scriptName, handler)
    if not frame or not scriptName or type(handler) ~= "function" then return end
    if frame.HasScript and not frame:HasScript(scriptName) then return end
    hookedScripts[frame] = hookedScripts[frame] or {}
    if hookedScripts[frame][scriptName] then return end
    hookedScripts[frame][scriptName] = true

    if frame.HookScript then
        local hOk = pcall(frame.HookScript, frame, scriptName, handler)
        if hOk then
            if type(hooksecurefunc) == "function" then
                pcall(hooksecurefunc, frame, "SetScript", function(self, name)
                    if name == scriptName and self == frame then
                        pcall(frame.HookScript, frame, scriptName, handler)
                    end
                end)
            end
            return
        end
    end

    local isCallOk, existing = pcall(frame.GetScript, frame, scriptName)
    if isCallOk and type(existing) == "function" then
        if frame.SetScript then
            pcall(frame.SetScript, frame, scriptName, function(...)
                existing(...)
                handler(...)
            end)
        end
    elseif frame.SetScript then
        pcall(frame.SetScript, frame, scriptName, handler)
    end
end

function FrameDragController.constructMoveHandle(frame, parentFrame)
    local isCallOk, handle = pcall(CreateFrame, "Frame", nil, parentFrame, "PanelDragBarTemplate")
    if not isCallOk or not handle then return nil end
    handle:SetParent(frame)
    handle:SetAllPoints(frame)
    handle:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    if handle.SetPropagateMouseMotion then
        pcall(handle.SetPropagateMouseMotion, handle, true)
    end
    if handle.SetPropagateMouseClicks then
        pcall(handle.SetPropagateMouseClicks, handle, true)
    end
    handle.onDragStartCallback = returnFalse
    FrameDragController.bindFrameScript(handle, "OnMouseDown", onMouseDown)
    FrameDragController.bindFrameScript(handle, "OnMouseUp", onMouseUp)
    FrameDragController.bindFrameScript(handle, "OnEnter", handleFrameMouseEnter)
    FrameDragController.bindFrameScript(handle, "OnLeave", handleFrameMouseLeave)
    FrameDragController.bindFrameScript(handle, "OnDragStop", function(self)
        local anchorTarget = self:GetParent()
        local root = anchorTarget and ns:GetRootFrame(anchorTarget)
        local fdVal = root and ns.FrameData[root]
        if fdVal and fdVal.storage and fdVal.storage.points and fdVal.storage.points.dragged then
            fdVal.storage.isMoving = true
        end
        onMouseUp(self, "LeftButton")
    end)
    return handle
end

function FrameDragController.constructMoveHandles(frame, frameData)
    if frameData.moveHandles then
        for _, handle in pairs(frameData.moveHandles) do
            handle:SetScript("OnEvent", nil)
            handle:SetScript("OnUpdate", nil)
            handle:Hide()
            ns.MoveHandles[handle] = nil
        end
    end
    frameData.moveHandles = {}
    local parentData = frameData
    while parentData.parentData do
        parentData = parentData.parentData
    end
    local rootParent = (parentData and parentData.storage and parentData.storage.frame) or frame
    local moveHandle = FrameDragController.constructMoveHandle(frame, rootParent)
    if moveHandle then
        table.insert(frameData.moveHandles, moveHandle)
        ns.MoveHandles[moveHandle] = true
    end
end

function FrameDragController.installDraggableFrameHooks(frame, frameName, frameData, frameParent)
    if not frame then return false end
    if ns.BLACKLIST_FRAMES and ns.BLACKLIST_FRAMES[frameName] then return false end

    if hasInCombat() and (frameData.ForceUseSecureMoveHandle or frame:IsProtected()) then
        return false
    end

    local savedDB = ns:InitializeDatabase()
    local clampFrame = false
    if (not frameParent or frameData.Detachable) and savedDB.clampToScreen ~= false then
        clampFrame = true
    end

    if ns.FrameData[frame] and ns.FrameData[frame].storage and not frameData.storage then
        frameData.storage = ns.FrameData[frame].storage
        frameData.parentData = frameParent and ns.FrameData[frameParent] or nil
        frameData.storage.frameName = frameName
        frameData.storage.frameParent = frameParent
        ns.FrameData[frame] = frameData
    end

    if frameData.storage and frameData.storage.hooked then
        if not frameData.storage.disabled then
            return true
        end
        frameData.storage.disabled = false
        if not frameData.UseSecureCursorDrag then
            pcall(frame.SetMovable, frame, true)
            if not frameData.IgnoreClamping then
                pcall(frame.SetClampedToScreen, frame, clampFrame)
            end
        end
        if not frameData.IgnoreMouse then
            if not frameData.NonDraggable then
                local rootFrameData = frameData
                while rootFrameData.parentData do
                    rootFrameData = rootFrameData.parentData
                end
                if not frameData.UseSecureCursorDrag then
                    if frameData.ForceUseSecureMoveHandle or frame:IsProtected() or (rootFrameData.storage and rootFrameData.storage.frame:IsProtected()) then
                        FrameDragController.constructMoveHandles(frame, frameData)
                    else
                        pcall(frame.EnableMouse, frame, true)
                    end
                end
            end
            if not frameData.IgnoreMouseWheel then
                pcall(frame.EnableMouseWheel, frame, true)
            end
        end
        return true
    end

    frameData.parentData = frameParent and ns.FrameData[frameParent] or nil
    frameData.storage = {
        hooked = true,
        frame = frame,
        frameName = frameName,
        frameParent = frameParent,
    }
    ns.FrameData[frame] = frameData
    if not frameParent then
        ns.hookedFrames[frameName] = frame
    end

    if not frameData.UseSecureCursorDrag then
        pcall(frame.SetMovable, frame, true)
        if not frameData.IgnoreClamping then
            pcall(frame.SetClampedToScreen, frame, clampFrame)
        end
    end

    if not frameData.IgnoreMouse then
        if not frameData.NonDraggable then
            local rootFrameData = frameData
            while rootFrameData.parentData do
                rootFrameData = rootFrameData.parentData
            end
            if frameData.UseSecureCursorDrag then
                FrameDragController.bindFrameScript(frame, "OnMouseDown", onMouseDown)
                FrameDragController.bindFrameScript(frame, "OnMouseUp", onMouseUp)
                FrameDragController.bindFrameScript(frame, "OnHide", onSubFrameHide)
            elseif frameData.ForceUseSecureMoveHandle or frame:IsProtected() or (rootFrameData.storage and rootFrameData.storage.frame:IsProtected()) then
                FrameDragController.constructMoveHandles(frame, frameData)
            else
                pcall(frame.EnableMouse, frame, true)
                FrameDragController.bindFrameScript(frame, "OnMouseDown", onMouseDown)
                FrameDragController.bindFrameScript(frame, "OnMouseUp", onMouseUp)
            end
        end

        if not frameData.IgnoreMouseWheel then
            FrameDragController.bindFrameScript(frame, "OnEnter", handleFrameMouseEnter)
            FrameDragController.bindFrameScript(frame, "OnLeave", handleFrameMouseLeave)
            if frame.IsMouseOver and frame:IsMouseOver() then
                runNext(function()
                    if frame:IsMouseOver() then handleFrameMouseEnter(frame) end
                end)
            end
        end
    end

    FrameDragController.bindFrameScript(frame, "OnShow", handleFrameShowEvent)
    if frameParent then
        FrameDragController.bindFrameScript(frame, "OnHide", onSubFrameHide)
    end

    if type(hooksecurefunc) == "function" then
        if frameData.ForcePosition or (not frameData.IgnoreMouse and not frameData.NonDraggable) then
            pcall(hooksecurefunc, frame, "SetPoint", onSetPoint)
        end
        if not frameData.UseSecureCursorDrag then
            pcall(hooksecurefunc, frame, "SetWidth", onSizeUpdate)
            pcall(hooksecurefunc, frame, "SetHeight", onSizeUpdate)
        end
    end

    handleFrameShowEvent(frame)
    onSizeUpdate(frame)
    onSetPoint(frame)

    return true
end

function ns:ProcessFrameTree(frameName, frameData, frameParent, retried)
    if not frameName or (self.BLACKLIST_FRAMES and self.BLACKLIST_FRAMES[frameName]) then
        return
    end
    local frame = self:GetFrameFromName(frameName)
    if not frame then
        if not retried then
            runNext(function()
                self:ProcessFrameTree(frameName, frameData, frameParent, true)
            end)
        end
        return
    end

    if hasInCombat() and (frameData.ForceUseSecureMoveHandle or frame:IsProtected()) then
        self:EnqueuePostCombatCallback(function()
            self:ProcessFrameTree(frameName, frameData, frameParent, retried)
        end)
        return
    end

    if not FrameDragController.installDraggableFrameHooks(frame, frameName, frameData, frameParent) then
        return
    end

    if type(frameData.SubFrames) == "table" then
        for subFrameName, subFrameData in pairs(frameData.SubFrames) do
            if type(subFrameData) == "table" then
                self:ProcessFrameTree(subFrameName, subFrameData, frame, retried)
            end
        end
    end
end

function ns:UpdateAllClampStates()
    local savedDB = self:InitializeDatabase()
    local clamp = savedDB.clampToScreen ~= false
    for frame, fdVal in pairs(self.FrameData) do
        if frame and fdVal and fdVal.storage and (not fdVal.storage.frameParent or fdVal.Detachable) and not fdVal.IgnoreClamping and not fdVal.UseSecureCursorDrag then
            if not (hasInCombat() and frame:IsProtected()) then
                pcall(frame.SetClampedToScreen, frame, clamp)
            end
        end
    end
end

function ns:ScanUnhookedStandardFrames()
    if type(self.STANDARD_FRAMES) ~= "table" then return end
    for frameName, frameData in pairs(self.STANDARD_FRAMES) do
        if type(frameData) == "table" and not self.hookedFrames[frameName] and self:GetFrameFromName(frameName) then
            self:ProcessFrameTree(frameName, frameData, nil, true)
        end
    end
end

function ns:HookLazyFrameTriggers()
    local talentsToggle = _G["EUI_ClassicTalentsToggle"]
    if hasFrameObject(talentsToggle) then
        FrameDragController.bindFrameScript(talentsToggle, "OnClick", function()
            ns:ScanUnhookedStandardFrames()
        end)
    end
    if not self._hookedLazyTalentFuncs and type(hooksecurefunc) == "function" then
        self._hookedLazyTalentFuncs = true
        if type(_G.ToggleTalentFrame) == "function" then
            pcall(hooksecurefunc, "ToggleTalentFrame", function()
                ns:ScanUnhookedStandardFrames()
            end)
        end
        if type(_G.ToggleSpellBook) == "function" then
            pcall(hooksecurefunc, "ToggleSpellBook", function()
                ns:ScanUnhookedStandardFrames()
            end)
        end
        if type(_G.ShowUIPanel) == "function" then
            pcall(hooksecurefunc, "ShowUIPanel", function(frame)
                if frame and ns.FrameData[frame] then
                    onSetPoint(frame)
                end
            end)
        end
        if type(_G.UpdateUIPanelPositions) == "function" then
            pcall(hooksecurefunc, "UpdateUIPanelPositions", function(currentFrame)
                if currentFrame and ns.FrameData[currentFrame] then
                    onSetPoint(currentFrame)
                else
                    for _, windowFrame in pairs(ns.hookedFrames) do
                        if windowFrame and windowFrame.IsShown and windowFrame:IsShown() then
                            onSetPoint(windowFrame)
                        end
                    end
                end
            end)
        end
    end
end

function ns:ScanAllFrames()
    if type(self.STANDARD_FRAMES) == "table" then
        for frameName, frameData in pairs(self.STANDARD_FRAMES) do
            if type(frameData) == "table" then
                self:ProcessFrameTree(frameName, frameData, nil)
            end
        end
    end

    if type(self.LOD_ADDON_FRAMES) == "table" then
        for _, framesTable in pairs(self.LOD_ADDON_FRAMES) do
            if type(framesTable) == "table" then
                for frameName, frameData in pairs(framesTable) do
                    if type(frameData) == "table" and self:GetFrameFromName(frameName) then
                        self:ProcessFrameTree(frameName, frameData, nil)
                    end
                end
            end
        end
    end

    if type(_G.UIPanelWindows) == "table" then
        for frameName in pairs(_G.UIPanelWindows) do
            if type(frameName) == "string" and not (self.BLACKLIST_FRAMES and self.BLACKLIST_FRAMES[frameName]) then
                local windowFrame = _G[frameName]
                if hasFrameObject(windowFrame) and not self.FrameData[windowFrame] then
                    self:ProcessFrameTree(frameName, {}, nil)
                end
            end
        end
    end

    self:HookLazyFrameTriggers()

    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ResetFrame(frameName, silent)
    if not frameName then return end
    local savedDB = self:InitializeDatabase()
    local frame = self.hookedFrames[frameName] or self:GetFrameFromName(frameName)
    local fdVal = frame and self.FrameData[frame]

    savedDB.positions[frameName] = nil
    savedDB.scales[frameName] = nil
    self.SessionScales[frameName] = nil

    if frame and not (hasInCombat() and frame:IsProtected()) then
        FrameDragController.applyClampedFrameScale(frame, 1.0, false)
        if fdVal and fdVal.storage and fdVal.storage.points then
            if fdVal.storage.points.startPoints then
                FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.startPoints)
                fdVal.storage.points.startPoints = nil
            end
            fdVal.storage.points.dragPoints = nil
            fdVal.storage.points.dragged = nil
        end
        if type(UpdateUIPanelPositions) == "function" then
            pcall(UpdateUIPanelPositions, frame)
        end
    end

    if not silent then
        self:PrintMsg(string.format(self:L("MSG_SINGLE_RESET"), frameName))
    end
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ResetAllPositions()
    local savedDB = self:InitializeDatabase()
    wipe(savedDB.positions)
    savedDB.trackerPos = nil

    for frame, fdVal in pairs(self.FrameData) do
        if frame and fdVal and fdVal.storage and fdVal.storage.points then
            if not (hasInCombat() and frame:IsProtected()) then
                if fdVal.storage.points.startPoints then
                    FrameDragController.applySavedFrameAnchors(frame, fdVal.storage.points.startPoints)
                end
            end
            wipe(fdVal.storage.points)
        end
    end

    if not hasInCombat() and type(UpdateUIPanelPositions) == "function" then
        pcall(UpdateUIPanelPositions)
    end
    if self.UpdateQuestTracker then
        self:UpdateQuestTracker()
    end

    self:PrintMsg(self:L("MSG_POS_RESET"))
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ResetAllScales()
    local savedDB = self:InitializeDatabase()
    wipe(savedDB.scales)
    wipe(self.SessionScales)
    savedDB.trackerScale = nil
    savedDB.trackerWidth = self.DEFAULTS.trackerWidth
    savedDB.trackerHeight = self.DEFAULTS.trackerHeight

    for frame, fdVal in pairs(self.FrameData) do
        if frame and fdVal and fdVal.storage and not fdVal.storage.frameParent then
            if not (hasInCombat() and frame:IsProtected()) then
                FrameDragController.applyClampedFrameScale(frame, 1.0, false)
            end
        end
    end
    if self.UpdateQuestTracker then
        self:UpdateQuestTracker()
    end

    self:PrintMsg(self:L("MSG_SCALE_RESET"))
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ResetOpenFrames()
    for frameName, frame in pairs(self.hookedFrames) do
        if frame and frame.IsShown and frame:IsShown() then
            self:ResetFrame(frameName, true)
        end
    end
    self:PrintMsg(self:L("MSG_OPEN_RESET"))
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ResetToDefaults()
    local savedDB = self:InitializeDatabase()
    self:ResetAllPositions()
    self:ResetAllScales()
    for entryKey, entryValue in pairs(self.DEFAULTS) do
        if type(entryValue) == "table" then
            savedDB[entryKey] = {}
        else
            savedDB[entryKey] = entryValue
        end
    end
    self:UpdateAllClampStates()
    if self.ResetQuestTrackerPosition then
        self:ResetQuestTrackerPosition(true)
    elseif self.UpdateQuestTracker then
        self:UpdateQuestTracker()
    end
    self:PrintMsg(self:L("MSG_DEFAULTS_RESET"))
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end

function ns:ComputeManagedFrameStatistics()
    local hookedCount = 0
    for _ in pairs(self.hookedFrames) do
        hookedCount = hookedCount + 1
    end

    local savedDB = self:InitializeDatabase()
    local posCount = 0
    for _, entryValue in pairs(savedDB.positions) do
        if type(entryValue) == "table" and entryValue.dragged and entryValue.dragPoints then
            posCount = posCount + 1
        end
    end

    local scaleCount = 0
    for _ in pairs(savedDB.scales) do
        scaleCount = scaleCount + 1
    end

    return hookedCount, posCount, scaleCount
end

local eventFrame = CreateFrame("Frame")
function FrameDragController.safeRegisterEvent(ev)
    pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

FrameDragController.safeRegisterEvent("ADDON_LOADED")
FrameDragController.safeRegisterEvent("PLAYER_LOGIN")
FrameDragController.safeRegisterEvent("PLAYER_ENTERING_WORLD")
FrameDragController.safeRegisterEvent("PLAYER_REGEN_ENABLED")
FrameDragController.safeRegisterEvent("GLOBAL_MOUSE_DOWN")

function FrameDragController.commitSpecificFixes(addOnName)
    if addOnName == "Blizzard_Collections" then
        local checkbox = _G.WardrobeTransmogFrame and _G.WardrobeTransmogFrame.ToggleSecondaryAppearanceCheckbox
        if checkbox and checkbox.Label then
            checkbox.Label:ClearAllPoints()
            checkbox.Label:SetPoint("LEFT", checkbox, "RIGHT", 2, 1)
            checkbox.Label:SetPoint("RIGHT", checkbox, "RIGHT", 160, 1)
        end
    elseif addOnName == "Blizzard_EncounterJournal" and _G.EncounterJournalTooltip then
        FrameDragController.bindFrameScript(_G.EncounterJournalTooltip, "OnHide", function()
            _G.EncounterJournalTooltip:ClearAllPoints()
        end)
    elseif addOnName == "Blizzard_Communities" and _G.CommunitiesFrame and _G.CommunitiesFrame.NotificationSettingsDialog then
        local dialog = _G.CommunitiesFrame.NotificationSettingsDialog
        dialog:ClearAllPoints()
        dialog:SetAllPoints()
    end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ns:InitializeDatabase()
            ns:InitMouseWheelCaptureFrame()
            ns:ScanAllFrames()
            if ns.InitUI then
                ns:InitUI()
            end
        elseif ns.LOD_ADDON_FRAMES and ns.LOD_ADDON_FRAMES[arg1] then
            for frameName, frameData in pairs(ns.LOD_ADDON_FRAMES[arg1]) do
                if type(frameData) == "table" then
                    ns:ProcessFrameTree(frameName, frameData, nil)
                end
            end
            FrameDragController.commitSpecificFixes(arg1)
            if ns.RefreshSettingsUI then
                ns:RefreshSettingsUI()
            end
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ns:InitializeDatabase()
        ns:InitMouseWheelCaptureFrame()
        ns:ScanAllFrames()
        runNext(function()
            ns:ScanAllFrames()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns:FlushPostCombatCallbackQueue()
        ns:ScanAllFrames()
    elseif event == "GLOBAL_MOUSE_DOWN" then
        ns:ScanUnhookedStandardFrames()
    end
end)

if type(hooksecurefunc) == "function" and type(_G.UpdateScaleForFit) == "function" then
    hooksecurefunc("UpdateScaleForFit", function(frame)
        local fdVal = ns.FrameData[frame]
        if not fdVal or not fdVal.storage or fdVal.storage.disabled then return end
        if hasInCombat() and frame:IsProtected() then return end
        local savedDB = ns:InitializeDatabase()
        local frameName = ns:GetFrameName(frame)
        if frameName and savedDB.scales[frameName] then
            FrameDragController.applyClampedFrameScale(frame, savedDB.scales[frameName], false)
        elseif frameName and ns.SessionScales[frameName] then
            FrameDragController.applyClampedFrameScale(frame, ns.SessionScales[frameName], false)
        end
    end)
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
FrameDragController.EnqueuePostCombatCallback = ns.EnqueuePostCombatCallback
FrameDragController.EnqueueDeferredAnchorRestore = ns.EnqueueDeferredAnchorRestore
FrameDragController.ComputeManagedFrameStatistics = ns.ComputeManagedFrameStatistics
FrameDragController.FlushPostCombatCallbackQueue = ns.FlushPostCombatCallbackQueue
FrameDragController.FlushDeferredAnchorRestoreQueue = ns.FlushDeferredAnchorRestoreQueue
