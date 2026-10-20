--===========================================================================
-- EzWoW - Frame Mover
-- Core/Init.lua : Namespace, Taint-Safe Frame Resolvers & SavedVariables Bootstrap
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreBootstrap = ns.CoreBootstrap or {}
ns.CoreBootstrap = CoreBootstrap
function CoreBootstrap.hasInCombat()
    return InCombatLockdown and InCombatLockdown()
end

function CoreBootstrap.hasFrameObject(val)
    return type(val) == "table" and type(val.IsObjectType) == "function" and val:IsObjectType("Frame")
end

function CoreBootstrap.runNext(fn)
    if type(RunNextFrame) == "function" then
        RunNextFrame(fn)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

function CoreBootstrap.resolveMouseFocusList()
    if type(GetMouseFoci) == "function" then
        return GetMouseFoci()
    elseif type(GetMouseFocus) == "function" then
        local windowFrame = GetMouseFocus()
        return windowFrame and { windowFrame } or {}
    end
    return {}
end

function CoreBootstrap.untaintedSetNil(tbl, key)
    if TextureLoadingGroupMixin and TextureLoadingGroupMixin.RemoveTexture then
        TextureLoadingGroupMixin.RemoveTexture({ textures = tbl }, key)
    else
        tbl[key] = nil
    end
end

function CoreBootstrap.returnFalse()
    return false
end

function ns:InitializeDatabase()
    if self.db and self.db == _G.EzWoW_FrameMoverDB and type(self.db.positions) == "table" and type(self.db.scales) == "table" then
        return self.db
    end
    if type(_G.EzWoW_FrameMoverDB) ~= "table" then
        _G.EzWoW_FrameMoverDB = {}
    end
    local savedDB = _G.EzWoW_FrameMoverDB
    for entryKey, entryValue in pairs(self.DEFAULTS) do
        if savedDB[entryKey] == nil then
            if type(entryValue) == "table" then
                savedDB[entryKey] = {}
            else
                savedDB[entryKey] = entryValue
            end
        end
    end
    if type(savedDB.positions) ~= "table" then savedDB.positions = {} end
    if type(savedDB.scales) ~= "table" then savedDB.scales = {} end

    for entryKey, entryValue in pairs(savedDB.positions) do
        if type(entryValue) ~= "table" then
            savedDB.positions[entryKey] = nil
        elseif type(entryValue[1]) == "table" and not entryValue.dragPoints then
            savedDB.positions[entryKey] = { dragPoints = entryValue, dragged = true }
        end
    end

    self.db = savedDB
    return savedDB
end

function ns:PrintMsg(msg)
    if not msg or msg == "" then return end
    local prefix = "|cff7aa2f7[EzWoW-FrameMover]|r "
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
    else
        print(prefix .. tostring(msg))
    end
end

function ns:GetFrameFromName(frameName)
    if not frameName or frameName == "" then return nil end
    if self.FrameRegistry[frameName] then
        return self.FrameRegistry[frameName]
    end
    local currentState = _G
    for part in string.gmatch(frameName, "([^.]+)") do
        if type(currentState) ~= "table" or not currentState[part] then
            return nil
        end
        currentState = currentState[part]
    end
    if CoreBootstrap.hasFrameObject(currentState) then
        return currentState
    end
    return nil
end

function ns:GetFrameName(frame)
    local fdVal = frame and self.FrameData[frame]
    return fdVal and fdVal.storage and fdVal.storage.frameName
end

function ns:GetRootFrame(frame)
    local currentState = frame
    while currentState and self.FrameData[currentState] and self.FrameData[currentState].storage do
        local stateEntry = self.FrameData[currentState].storage
        if stateEntry.detached or not stateEntry.frameParent then
            return currentState
        end
        currentState = stateEntry.frameParent
    end
    return currentState or frame
end

function ns:SetupPointStorage(frame)
    local frameName = self:GetFrameName(frame)
    if not frameName then return false end
    local fdVal = self.FrameData[frame]
    if not fdVal or not fdVal.storage then return false end

    local savedDB = self:InitializeDatabase()
    if savedDB.savePositions == false then
        local points = fdVal.storage.points
        if not points then
            fdVal.storage.points = {}
        elseif savedDB.positions and points == savedDB.positions[frameName] then
            -- detach from SavedVariables so drags made after turning saving off stay session-only
            fdVal.storage.points = CopyTable and CopyTable(points) or points
        end
        return true
    end

    if fdVal.storage.points and fdVal.storage.points == savedDB.positions[frameName] then
        return true
    end
    if type(fdVal.storage.points) == "table" and (fdVal.storage.points.dragged or fdVal.storage.points.startPoints or fdVal.storage.points.detachPoints) then
        savedDB.positions[frameName] = fdVal.storage.points
    else
        if type(savedDB.positions[frameName]) ~= "table" then
            savedDB.positions[frameName] = {}
        end
        fdVal.storage.points = savedDB.positions[frameName]
    end

    if fdVal.storage.points.detachPoints then
        local relName = fdVal.storage.points.detachPoints[1] and fdVal.storage.points.detachPoints[1].relativeFrameName
        local relFrame = relName and self:GetFrameFromName(relName)
        if relFrame then
            fdVal.storage.detached = true
            fdVal.storage.points.detachPoints[1].relativeFrame = relFrame
        else
            wipe(fdVal.storage.points)
        end
    end
    return true
end

ns.IsInCombatLockdownState = CoreBootstrap.hasInCombat
ns.IsValidUIFrameObject = CoreBootstrap.hasFrameObject
ns.RunOnNextFrameTick = CoreBootstrap.runNext
ns.CollectHoveredFrameStack = CoreBootstrap.resolveMouseFocusList
ns.ClearTableKeyUntainted = CoreBootstrap.untaintedSetNil
ns.AlwaysReturnFalse = CoreBootstrap.returnFalse

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreBootstrap.InitializeDatabase = ns.InitializeDatabase
CoreBootstrap.CollectHoveredFrameStack = ns.CollectHoveredFrameStack
CoreBootstrap.IsValidUIFrameObject = ns.IsValidUIFrameObject
CoreBootstrap.IsInCombatLockdownState = ns.IsInCombatLockdownState
CoreBootstrap.AlwaysReturnFalse = ns.AlwaysReturnFalse
CoreBootstrap.RunOnNextFrameTick = ns.RunOnNextFrameTick
CoreBootstrap.ClearTableKeyUntainted = ns.ClearTableKeyUntainted
