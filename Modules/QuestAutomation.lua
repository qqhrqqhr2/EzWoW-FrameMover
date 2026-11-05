--===========================================================================
-- EzWoW - Frame Mover
-- Modules/QuestAutomation.lua : Auto accept / auto turn-in (hold Shift to skip)
--===========================================================================
local ADDON_NAME, ns = ...
local type, ipairs, pcall, tonumber, tostring = type, ipairs, pcall, tonumber, tostring

local QuestAutomation = {}
ns.QuestAutomation = QuestAutomation

local function db()
    return ns:InitializeDatabase()
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function plain(value)
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if ok and secret then return nil end
    end
    return value
end

-- Holding Shift while talking to the NPC turns everything off for that talk.
local function paused()
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function acceptOn() return db().questAutoAccept == true and not paused() end
local function completeOn() return db().questAutoComplete == true and not paused() end
local function skipRisky() return db().questSkipRisky ~= false end
local function skipItems() return db().questSkipItems == true end

-- Single gossip options that are never picked automatically
-- (hearthstone binding, talent/skill resets, locked options).
local RISKY_WORDS = { "unlearn", "reset", "bind", "초기화", "귀환", "잊" }

local function riskyOption(option)
    local status = tonumber(plain(option.status)) or 0
    if status ~= 0 then return true end
    local name = plain(option.name)
    if type(name) ~= "string" then return true end
    local lower = name:lower()
    for _, word in ipairs(RISKY_WORDS) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

-- Option IDs already picked while this gossip window stays open
-- (stops a loop when an NPC keeps showing the same single option).
local pickedOptions = {}

-----------------------------------------------------------------------------
-- Gossip window (NPCs with several options)
-----------------------------------------------------------------------------
local function handleGossip()
    local gossip = C_GossipInfo
    if type(gossip) ~= "table" then return end
    if completeOn() then
        for _, info in ipairs(call(gossip.GetActiveQuests) or {}) do
            if type(info) == "table" and plain(info.isComplete) == true and plain(info.questID) then
                call(gossip.SelectActiveQuest, info.questID)
                return
            end
        end
    end
    if acceptOn() then
        for _, info in ipairs(call(gossip.GetAvailableQuests) or {}) do
            if type(info) == "table" and plain(info.questID) then
                local risky = plain(info.isTrivial) == true or plain(info.repeatable) == true
                    or ((tonumber(plain(info.frequency)) or 0) > 0)
                if not (skipRisky() and risky) then
                    call(gossip.SelectAvailableQuest, info.questID)
                    return
                end
            end
        end
        -- No quests here and only one thing to say: pick it.
        local active = call(gossip.GetActiveQuests) or {}
        local available = call(gossip.GetAvailableQuests) or {}
        if #active > 0 or #available > 0 then return end
        local options = call(gossip.GetOptions) or {}
        if #options ~= 1 then return end
        local option = options[1]
        if type(option) ~= "table" or riskyOption(option) then return end
        -- the client already picks options flagged for that by itself
        if plain(option.selectOptionWhenOnlyOption) == true then return end
        local optionID = plain(option.gossipOptionID)
        if not optionID or pickedOptions[optionID] then return end
        pickedOptions[optionID] = true
        call(gossip.SelectOption, optionID)
    end
end

-----------------------------------------------------------------------------
-- Quest greeting window (older style list)
-----------------------------------------------------------------------------
local function handleGreeting()
    if completeOn() then
        for i = 1, (call(GetNumActiveQuests) or 0) do
            local _, isComplete = call(GetActiveTitle, i)
            if isComplete then
                call(SelectActiveQuest, i)
                return
            end
        end
    end
    if acceptOn() then
        for i = 1, (call(GetNumAvailableQuests) or 0) do
            local isTrivial, frequency, isRepeatable
            if type(GetAvailableQuestInfo) == "function" then
                isTrivial, frequency, isRepeatable = call(GetAvailableQuestInfo, i)
            end
            local risky = isTrivial == true or isRepeatable == true or ((tonumber(frequency) or 0) > 0)
            if not (skipRisky() and risky) then
                call(SelectAvailableQuest, i)
                return
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Quest detail / progress / reward
-----------------------------------------------------------------------------
local function handleDetail()
    if not acceptOn() then return end
    if skipRisky() and ((call(QuestIsDaily) == true) or (call(QuestIsWeekly) == true)) then return end
    call(AcceptQuest)
end

local function handleProgress()
    if not completeOn() then return end
    if not call(IsQuestCompletable) then return end
    -- quests that take items (optional) or gold from you are left to you
    if skipItems() and (tonumber(call(GetNumQuestItems)) or 0) > 0 then return end
    if (tonumber(call(GetQuestMoneyToGet)) or 0) > 0 then return end
    call(CompleteQuest)
end

-- Marks the reward that sells for the most when there is a choice.
local bestMark
local function markBestReward(index)
    local button
    if type(QuestInfo_GetRewardButton) == "function" and QuestInfoFrame and QuestInfoFrame.rewardsFrame then
        button = call(QuestInfo_GetRewardButton, QuestInfoFrame.rewardsFrame, index)
    end
    button = button or _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
    if not button then return false end
    if not bestMark then
        bestMark = CreateFrame("Frame", nil, UIParent)
        bestMark:SetSize(18, 18)
        bestMark.icon = bestMark:CreateTexture(nil, "OVERLAY")
        bestMark.icon:SetAllPoints()
        bestMark.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    end
    bestMark:SetParent(button)
    bestMark:SetFrameLevel(button:GetFrameLevel() + 5)
    bestMark:ClearAllPoints()
    bestMark:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    bestMark:Show()
    return true
end

-- Vendor price (11th value of the item info).
-- Returns 0 when the item has no price, nil when the item is not loaded yet.
local function sellPrice(link)
    local getInfo = (C_Item and type(C_Item.GetItemInfo) == "function" and C_Item.GetItemInfo)
        or (type(GetItemInfo) == "function" and GetItemInfo)
    if not getInfo then return 0 end
    local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(getInfo, link)
    if not ok then return 0 end
    if name == nil then return nil end
    return tonumber(plain(price)) or 0
end

local function requestItem(link)
    if not (C_Item and type(C_Item.RequestLoadItemDataByID) == "function") then return end
    local itemID
    if type(C_Item.GetItemInfoInstant) == "function" then
        itemID = call(C_Item.GetItemInfoInstant, link)
    end
    itemID = tonumber(plain(itemID)) or tonumber(tostring(link):match("item:(%d+)"))
    if itemID then call(C_Item.RequestLoadItemDataByID, itemID) end
end

-- While the reward window is open and some choices were not loaded yet,
-- the mark is redone when item data arrives (a few times at most).
local rewardOpen, rewardWaiting, rewardRetries = false, false, 0
local MAX_REWARD_RETRIES = 5

local function updateBestReward()
    if bestMark then bestMark:Hide() end
    rewardWaiting = false
    local choices = tonumber(call(GetNumQuestChoices)) or 0
    if choices <= 1 or db().questMarkBest == false then return end
    local bestIndex, bestPrice = nil, 0
    for i = 1, choices do
        local link = call(GetQuestItemLink, "choice", i)
        if link then
            local price = sellPrice(link)
            if price == nil then
                rewardWaiting = true
                requestItem(link)
            elseif price > bestPrice then
                bestIndex, bestPrice = i, price
            end
        end
    end
    -- wait for every choice before picking, so the mark does not jump around
    if rewardWaiting and rewardRetries < MAX_REWARD_RETRIES then return end
    rewardWaiting = false
    if bestIndex then
        -- the reward buttons are laid out right after this event
        C_Timer.After(0, function()
            if not rewardOpen then return end
            if not markBestReward(bestIndex) then
                local link = call(GetQuestItemLink, "choice", bestIndex)
                if link then ns:PrintMsg(string.format(ns:L("MSG_QUEST_BEST"), link)) end
            end
        end)
    end
end

local retryQueued = false
local function onItemInfoReceived()
    if not (rewardOpen and rewardWaiting) or retryQueued then return end
    retryQueued = true
    -- several items usually arrive together; redo the mark once
    C_Timer.After(0.1, function()
        retryQueued = false
        if not (rewardOpen and rewardWaiting) then return end
        rewardRetries = rewardRetries + 1
        local ok, err = pcall(updateBestReward)
        if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
    end)
end

local function handleReward()
    rewardOpen, rewardRetries = true, 0
    local choices = tonumber(call(GetNumQuestChoices)) or 0
    if choices > 1 then
        updateBestReward()
        return
    end
    if bestMark then bestMark:Hide() end
    if not completeOn() then return end
    call(GetQuestReward, choices == 1 and 1 or 0)
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------
-- Shared and escort quests started by someone else ask for confirmation.
local function handleAcceptConfirm()
    if not acceptOn() then return end
    if type(ConfirmAcceptQuest) ~= "function" then return end
    call(ConfirmAcceptQuest)
    if type(StaticPopup_Hide) == "function" then
        C_Timer.After(0, function() call(StaticPopup_Hide, "QUEST_ACCEPT") end)
    end
end

local HANDLERS = {
    GOSSIP_SHOW = handleGossip,
    QUEST_GREETING = handleGreeting,
    QUEST_DETAIL = handleDetail,
    QUEST_PROGRESS = handleProgress,
    QUEST_COMPLETE = handleReward,
    QUEST_ACCEPT_CONFIRM = handleAcceptConfirm,
}

local eventFrame = CreateFrame("Frame")
for event in pairs(HANDLERS) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_FINISHED")
pcall(eventFrame.RegisterEvent, eventFrame, "GOSSIP_CLOSED")
pcall(eventFrame.RegisterEvent, eventFrame, "GET_ITEM_INFO_RECEIVED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "QUEST_FINISHED" then
        rewardOpen, rewardWaiting = false, false
        if bestMark then bestMark:Hide() end
        return
    elseif event == "GOSSIP_CLOSED" then
        for key in pairs(pickedOptions) do pickedOptions[key] = nil end
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        onItemInfoReceived()
        return
    end
    local handler = HANDLERS[event]
    if handler then
        local ok, err = pcall(handler)
        if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
    end
end)
