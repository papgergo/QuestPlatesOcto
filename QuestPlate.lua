local f = CreateFrame("Frame")
-- Constants
local MAX_ICONS = 20
local UPDATE_INTERVAL = 0.1 -- Slightly increased for performance

local questObjectives = {}
local iconPool = {}

-- Saved Settings
QuestPlateOctoDB = QuestPlateOctoDB or {}
local defaults = {
    iconSize = 16,
    xOffset = 22,
    yOffset = 14
}

local function ApplyDefaults()
    for k, v in pairs(defaults) do
        if QuestPlateOctoDB[k] == nil then
            QuestPlateOctoDB[k] = v
        end
    end
end

local function GetQuestIdByTitle(title, level)
    local wantedTitle = string.lower(title)
    local wantedLevel = tonumber(level)

    if QuestieOcto and QuestieOcto.DatabaseAPI and QuestieOcto.DatabaseAPI:IsReady() then
        local DB = QuestieOcto.DatabaseAPI
        for i = 1, table.getn(DB:GetQuestIDs()) do
            local id = DB:GetQuestIDs()[i]
            local q = QuestieOcto.QuestModel:Get(id)
            if q and tonumber(q.level) == wantedLevel and string.lower(q.title) == wantedTitle then
                return id
            end
        end
    end

    if pfDB and pfDB.quests and pfDB.quests.data and pfDB.quests.loc then
        for id, _ in pairs(pfDB.quests.data) do
            local loc = pfDB.quests.loc[id]
            local questTitle = type(loc) == "table" and (loc.T or loc[1]) or loc
            local questLevel = pfDB.quests.data[id] and (pfDB.quests.data[id].lvl or pfDB.quests.data[id].level)
            if questTitle and tonumber(questLevel) == wantedLevel and string.lower(questTitle) == wantedTitle then
                return id
            end
        end
    end
end

local function GetDataFromQuestie(questId, itemName)
    local DB = QuestieOcto.DatabaseAPI
    local q = QuestieOcto.QuestModel:Get(questId)
    if not q or not q.objectives or not q.objectives.item then
        return nil
    end

    local questieMobs = {}
    local seenMobs = {}
    local lowerItemName = string.lower(itemName)

    for i = 1, table.getn(q.objectives.item) do
        local itemId = q.objectives.item[i]
        if string.lower(DB:GetItemName(itemId) or "") == lowerItemName then
            local sources = DB:GetItemSources(itemId)
            if sources and sources.Creature then
                for mobId, _ in pairs(sources.Creature) do
                    local mobName = DB:GetCreatureName(mobId)
                    if mobName and not seenMobs[mobName] then
                        table.insert(questieMobs, mobName)
                        seenMobs[mobName] = true
                    end
                end
            end
            if sources and sources.Reference then
                for refId, _ in pairs(sources.Reference) do
                    local refLoot = DB:GetReferenceLootRaw(refId)
                    if refLoot and refLoot.U then
                        for mobId, _ in pairs(refLoot.U) do
                            local mobName = DB:GetCreatureName(mobId)
                            if mobName and not seenMobs[mobName] then
                                table.insert(questieMobs, mobName)
                                seenMobs[mobName] = true
                            end
                        end
                    end
                end
            end
        end
    end

    if table.getn(questieMobs) > 0 then
        return questieMobs
    end
    return nil
end

-- source: https://github.com/GabHST/QuestPlates
local function GetDataFromPfDb(questId, itemName)
    if not pfDB or not pfDB.quests or not pfDB.items or not pfDB.units then
        return nil
    end

    local questData = pfDB.quests.data and pfDB.quests.data[questId]
    if not questData or not questData.obj or not questData.obj.I then
        return nil
    end

    local qdata = pfDB["quests"]["data"]
    local itemData = pfDB["items"]["data"]
    local itemLoc = pfDB["items"]["loc"]
    local uloc = pfDB["units"]["loc"]
    local refloot = pfDB["refloot"] and pfDB["refloot"]["data"]
    local itemNameLower = string.lower(itemName or "")
    local pfMobs = {}
    local seenMobs = {}

    if questId and qdata[questId] and qdata[questId]["obj"] then
        local obj = qdata[questId]["obj"]
        if obj["I"] then
            for _, itemid in pairs(obj["I"]) do
                local sourceName = itemLoc and itemLoc[itemid]
                if type(sourceName) == "string" and string.lower(sourceName) == itemNameLower and itemData[itemid] then
                    -- direct unit drops
                    if itemData[itemid]["U"] then
                        for unitid, _ in pairs(itemData[itemid]["U"]) do
                            local name = uloc[unitid]
                            if name and not seenMobs[name] then
                                table.insert(pfMobs, name)
                                seenMobs[name] = true
                            end
                        end
                    end
                    -- reference loot (shared loot tables)
                    if itemData[itemid]["R"] and refloot then
                        for ref, _ in pairs(itemData[itemid]["R"]) do
                            if refloot[ref] and refloot[ref]["U"] then
                                for unitid, _ in pairs(refloot[ref]["U"]) do
                                    local name = uloc[unitid]
                                    if name and not seenMobs[name] then
                                        table.insert(pfMobs, name)
                                        seenMobs[name] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if obj["U"] then
            for _, unitid in pairs(obj["U"]) do
                local name = uloc[unitid]
                if name and not seenMobs[name] then
                    table.insert(pfMobs, name)
                    seenMobs[name] = true
                end
            end
        end
    end

    if table.getn(pfMobs) > 0 then
        return pfMobs
    end
    return nil
end

local function GetItemDropSource(questId, itemName)
    if not questId or not itemName then
        return nil
    end

    local mobs = {}

    if QuestieOcto and QuestieOcto.DatabaseAPI and QuestieOcto.DatabaseAPI:IsReady() then
        local itemSources = GetDataFromQuestie(questId, itemName)
        if itemSources then
            mobs = itemSources
        end
    end

    if table.getn(mobs) == 0 and pfDB and pfDB.quests and pfDB.items and pfDB.units then
        local itemSources = GetDataFromPfDb(questId, itemName)
        if itemSources then
            mobs = itemSources
        end
    else
        if table.getn(mobs) == 0 then
            return nil
        end
    end

    if table.getn(mobs) > 0 then
        return mobs
    end
    return nil
end

local function GetMonsterDataFromQuestie(questId, objectiveName)
    local DB = QuestieOcto.DatabaseAPI
    local q = QuestieOcto.QuestModel:Get(questId)
    if not q or not q.objectives or not q.objectives.monster then
        return nil
    end

    local questieMobs = {}
    local seenMobs = {}

    for i = 1, table.getn(q.objectives.monster) do
        local mobId = q.objectives.monster[i]
        local mobName = DB:GetCreatureName(mobId)
        if mobName and not seenMobs[mobName] then
            table.insert(questieMobs, mobName)
            seenMobs[mobName] = true
        end
    end

    if table.getn(questieMobs) > 0 then
        return questieMobs
    end
    return nil
end

local function GetMonsterDataFromPfDb(questId)
    if not pfDB or not pfDB.quests or not pfDB.quests.data or not pfDB.units or not pfDB.units.loc then
        return nil
    end

    local questData = pfDB.quests.data[questId]
    if not questData or not questData.obj or not questData.obj.U then
        return nil
    end

    local uloc = pfDB.units.loc
    local pfMobs = {}
    local seenMobs = {}

    for _, unitid in pairs(questData.obj.U) do
        local name = uloc[unitid]
        if name and not seenMobs[name] then
            table.insert(pfMobs, name)
            seenMobs[name] = true
        end
    end

    return table.getn(pfMobs) > 0 and pfMobs or nil
end

function UpdateQuestObjectives()
    wipe(questObjectives)

    local numEntries = GetNumQuestLogEntries()
    if numEntries == 0 then
        return
    end

    for i = 1, numEntries do
        SelectQuestLogEntry(i)
        local questTitle, questLevel, _, isHeader, _, isComplete = GetQuestLogTitle(i)

        if not isHeader and not isComplete then
            local questId = GetQuestIdByTitle(questTitle, questLevel)
            local numObjectives = GetNumQuestLeaderBoards()

            for j = 1, numObjectives do
                local description, objectiveType = GetQuestLogLeaderBoard(j)
                local name, current, total = string.match(description, "(.+):%s*(%d+)/(%d+)")

                if name and current and total and tonumber(current) < tonumber(total) then
                    local mobs = {}
                    local icon = ""

                    if objectiveType == "monster" then
                        local sources
                        if QuestieOcto and QuestieOcto.DatabaseAPI and QuestieOcto.DatabaseAPI:IsReady() then
                            sources = GetMonsterDataFromQuestie(questId, name)
                        end
                        -- Get all kill objectives from pfDB for this quest
                        if (not sources or table.getn(sources) == 0) and pfDB then
                            sources = GetMonsterDataFromPfDb(questId)
                        end
                        if sources then
                            mobs = sources
                            icon = "Interface\\AddOns\\QuestPlateOcto\\img\\kill"
                        else
                            -- Fallback: parse the name directly from the quest log text
                            local mobName = string.gsub(name, "%s+slain$", "")
                            if mobName and mobName ~= "" then
                                mobs = {mobName}
                                icon = "Interface\\AddOns\\QuestPlateOcto\\img\\kill"
                            end
                        end
                    elseif objectiveType == "item" and questId then
                        local sources = GetItemDropSource(questId, name)
                        if sources then
                            mobs = sources
                        end
                        icon = "Interface\\AddOns\\QuestPlateOcto\\img\\item"
                    end

                    for _, mobName in pairs(mobs) do
                        local lowerMobName = string.lower(mobName)
                        if not questObjectives[lowerMobName] then
                            questObjectives[lowerMobName] = {}
                        end
                        local remaining = total - current

                        questObjectives[lowerMobName][name] = {
                            icon = icon,
                            text = remaining
                        }
                    end
                end
            end
        end
    end
end

local function CreateIconPool()
    for i = 1, MAX_ICONS do
        local iconFrame = CreateFrame("Frame", nil, f)
        iconFrame:SetSize(QuestPlateOctoDB.iconSize, QuestPlateOctoDB.iconSize)
        local texture = iconFrame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(iconFrame)
        iconFrame.texture = texture
        local text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", iconFrame, "RIGHT", 0, 0)
        iconFrame.text = text

        iconFrame:Hide()
        table.insert(iconPool, iconFrame)
    end
end

local function UpdateIconAppearance()
    for _, icon in pairs(iconPool) do
        icon:SetSize(QuestPlateOctoDB.iconSize, QuestPlateOctoDB.iconSize)
    end
    -- Force a redraw of nameplates
    if updater then
        updater:SetScript("OnUpdate", updater:GetScript("OnUpdate"))
    end
end

local function GetNameplateTextRegions(nameplate)
    local regions = {nameplate:GetRegions()}
    local texts = {}

    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text and text ~= "" then
                table.insert(texts, text)
            end
        end
    end

    return texts
end

local function GetNameplateDisplayName(nameplate)
    if not nameplate then
        return nil
    end

    if nameplate.name and nameplate.name.GetText then
        local nameText = nameplate.name:GetText()
        if nameText and nameText ~= "" then
            return nameText
        end
    end

    local texts = GetNameplateTextRegions(nameplate)
    for _, text in ipairs(texts) do
        if text then
            return text
        end
    end

    return nil
end

local function GetNameplateHealthBar(nameplate)
    for i, child in ipairs({nameplate:GetChildren()}) do
        if child and child:GetObjectType() == "StatusBar" then
            return child
        end
    end
    return nil
end

local updater = CreateFrame("Frame")
local elapsed = 0
updater:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < UPDATE_INTERVAL then
        return
    end
    elapsed = 0

    for _, icon in pairs(iconPool) do
        if icon.inUse then
            icon:Hide()
            icon.inUse = false
        end
    end

    local iconIndex = 1
    for i = 1, WorldFrame:GetNumChildren() do
        local frame = select(i, WorldFrame:GetChildren())
        if frame and frame:IsShown() then
            local unitName = GetNameplateDisplayName(frame)
            local healthBar = GetNameplateHealthBar(frame)

            if unitName and healthBar then
                local objectives = questObjectives[string.lower(unitName)]

                if objectives then
                    local prevIcon = nil
                    for _, objectiveData in pairs(objectives) do
                        if iconIndex <= MAX_ICONS then
                            local icon = iconPool[iconIndex]
                            icon:ClearAllPoints()
                            if prevIcon then
                                icon:SetPoint("RIGHT", prevIcon, "RIGHT", 25, 0)
                            else
                                icon:SetPoint("RIGHT", healthBar, "RIGHT", QuestPlateOctoDB.xOffset,
                                    QuestPlateOctoDB.yOffset)
                            end
                            icon.texture:SetTexture(objectiveData.icon)
                            icon.text:SetText(objectiveData.text)
                            icon:Show()
                            icon.inUse = true
                            prevIcon = icon
                            iconIndex = iconIndex + 1
                        end
                    end
                end
            end
        end
    end
end)

local scanner = CreateFrame("Frame")
local updatePending = false
local updateDelay = 0.5
local timeSinceEvent = 0

scanner:RegisterEvent("QUEST_LOG_UPDATE")
scanner:RegisterEvent("PLAYER_LOGIN")
scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
scanner:RegisterEvent("QUEST_WATCH_UPDATE")
scanner:RegisterEvent("UNIT_QUEST_LOG_CHANGED")

scanner:SetScript("OnEvent", function()
    updatePending = true
    timeSinceEvent = 0

    if event == "PLAYER_LOGIN" then
        ApplyDefaults()
        CreateIconPool()
    end
end)

scanner:SetScript("OnUpdate", function()
    if not updatePending then
        return
    end
    timeSinceEvent = timeSinceEvent + elapsed
    if timeSinceEvent >= updateDelay then
        updatePending = false
        UpdateQuestObjectives()
    end
end)

-- Dependency Checker
local dependencyChecker = CreateFrame("Frame")
local dependencyCheckTimer = 0
local hasCheckedDependencies = false

dependencyChecker:RegisterEvent("PLAYER_ENTERING_WORLD")
dependencyChecker:SetScript("OnEvent", function()
    dependencyChecker:SetScript("OnUpdate", function()
        dependencyCheckTimer = dependencyCheckTimer + elapsed
        if dependencyCheckTimer > 5 and not hasCheckedDependencies then
            hasCheckedDependencies = true
            dependencyChecker:SetScript("OnUpdate", nil) -- Stop updating

            local questieReady = QuestieOcto and QuestieOcto.DatabaseAPI and QuestieOcto.DatabaseAPI:IsReady()
            if not pfDB and not questieReady then
                print(
                    "|cff3399ffQuestPlateOcto|r: Neither |cffffff00Questie-octo|r nor |cffffff00pfQuest|r is enabled. This addon requires one of them to function.")
            end
        end
    end)
end)

-- Slash Commands
SLASH_QUESTPLATEOCTO1 = "/qp"
SlashCmdList["QUESTPLATEOCTO"] = function(msg)
    local command, value = string.match(msg, "^(%S+)%s*(.-)$")
    command = command and string.lower(command) or "help"
    value = value and string.lower(value) or ""

    if command == "scale" or command == "size" then
        local num = tonumber(value)
        if num and num > 4 and num < 64 then
            QuestPlateOctoDB.iconSize = num
            print("|cff3399ffQuestPlateOcto|r: Icon size set to |cffffff00" .. num .. "|r.")
            UpdateIconAppearance()
        else
            num = QuestPlateOctoDB.iconSize
            print("|cff3399ffQuestPlateOcto|r: Usage: /qp scale <number> (Current: " .. num .. ")")
        end
    elseif command == "x" then
        local num = tonumber(value)
        if num then
            QuestPlateOctoDB.xOffset = num
            print("|cff3399ffQuestPlateOcto|r: Icon X-Offset set to |cffffff00" .. num .. "|r.")
        else
            num = QuestPlateOctoDB.xOffset
            print("|cff3399ffQuestPlateOcto|r: Usage: /qp x <number> (Current: " .. num .. ")")
        end
    elseif command == "y" then
        local num = tonumber(value)
        if num then
            QuestPlateOctoDB.yOffset = num
            print("|cff3399ffQuestPlateOcto|r: Icon Y-Offset set to |cffffff00" .. num .. "|r.")
        else
            num = QuestPlateOctoDB.yOffset
            print("|cff3399ffQuestPlateOcto|r: Usage: /qp y <number> (Current: " .. num .. ")")
        end
    else
        local scale = QuestPlateOctoDB.iconSize
        local xOffset = QuestPlateOctoDB.xOffset
        local yOffset = QuestPlateOctoDB.yOffset
        print("|cff3399ff--- QuestPlateOcto Commands ---|r")
        print("/qp scale " .. scale .. " - Sets the icon size (Default: 16).")
        print("/qp x " .. xOffset .. "  - Sets the horizontal offset (Default: 22).")
        print("/qp y " .. yOffset .. "  - Sets the vertical offset (Default: 14).")
    end
end
