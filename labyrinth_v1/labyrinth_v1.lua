--[[
    Название: Лабиринт
    Автор: Avondale, дискорд - avonda

    Описание механики: 
        Игроки пытаются собрать все монетки в лабиринте и не попасться врагам которые по нему бегают

    Идеи по доработке: 
        Запретить перепрыгивать через стены?
        Сделать чтобы враги могли нормально ходить сквозь друг друга

]]
math.randomseed(os.time())

local CLog = require("log")
local CInspect = require("inspect")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 24,
    Rows = 15, 
    Buttons = {}, 
}
local tConfig = {}

-- стейты или этапы игры
local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4

local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0
local bAnyButtonClick = false

local tGameStats = {
    StageLeftDuration = 0, 
    StageTotalDuration = 0, 
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    bBlocked = false,
    iUnitID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}    
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct) 
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tButtonStruct)
    end

    CGameMode.InitGameMode()

    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
    CPaint.Objects()

    if bAnyButtonClick then
        bAnyButtonClick = false

        if CGameMode.iCountdown == 0 then
            CGameMode.StartCountDown(5)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Objects()
end

function PostGameTick()
    local iColor = CColors.GREEN
    if CGameMode.bVictory == false then
        iColor = CColors.RED
    end

    SetGlobalColorBright(iColor, tConfig.Bright)
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.bVictory = false

CGameMode.InitGameMode = function()
    tGameStats.CurrentLives = tConfig.Health
    tGameStats.TotalLives = tConfig.Health

    CMaps.LoadMap(CMaps.GetRandomMapID())
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    iGameState = GAMESTATE_GAME

    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    CTimer.New(1000, function()
        if iGameState == GAMESTATE_GAME then
            CUnits.ProcessUnits()
            return tConfig.UnitThinkDelay
        end

        return nil
    end)

    CBlock.AnimateVisibility()
end

CGameMode.Victory = function()
    CAudio.StopBackground()
    CAudio.PlaySync(CAudio.GAME_SUCCESS)
    CAudio.PlaySync(CAudio.VICTORY)
    CGameMode.bVictory = true
    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = true
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.Defeat = function()
    CAudio.StopBackground()
    CAudio.PlaySync(CAudio.GAME_OVER)    
    CAudio.PlaySync(CAudio.DEFEAT)
    CGameMode.bVictory = false
    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = false
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.RoundScoreAdd = function(iScore)
    tGameStats.CurrentStars = tGameStats.CurrentStars + 1

    if tGameStats.CurrentStars >= tGameStats.TotalStars then
        CGameMode.Victory()
    end

    CAudio.PlayAsync(CAudio.CLICK);
end

CGameMode.PlayerTouchedLava = function()
    tGameStats.CurrentLives = tGameStats.CurrentLives - 1

    if tGameStats.CurrentLives <= 0 then
        CGameMode.Defeat()
    end

    CAudio.PlayAsync(CAudio.MISCLICK);
end
--//

--MAPS
CMaps = {}

CMaps.GetRandomMapID = function()
    return math.random(1, #tGame.Maps)
end

CMaps.LoadMap = function(iMapID)
    local iCoinCount = 0

    for iY = 1, tGame.Rows  do
        for iX = 1, tGame.Cols do
            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if tGame.Maps[iMapID][iY] ~= nil and tGame.Maps[iMapID][iY][iX] ~= nil then 
                iBlockType = tGame.Maps[iMapID][iY][iX]
            end

            if iBlockType == 9 then
                iBlockType = CBlock.BLOCK_TYPE_GROUND
                CUnits.NewUnit(iX, iY)
            end

            if iBlockType == CBlock.BLOCK_TYPE_LAVA or iBlockType == CBlock.BLOCK_TYPE_START then
                tFloor[iX][iY].bBlocked = true
            end

            if iBlockType == CBlock.BLOCK_TYPE_COIN then
                iCoinCount = iCoinCount + 1
            end

            CBlock.NewBlock(iX, iY, iBlockType)
        end
    end

    tGameStats.TotalStars = iCoinCount
    CBlock.LoadBlockList()
end
--//

--BLOCK
CBlock = {}
CBlock.tBlocks = {}
CBlock.tBlockList = nil
CBlock.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iBright = 0,
    bVisible = false,
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_LAVA = 2
CBlock.BLOCK_TYPE_COIN = 3
CBlock.BLOCK_TYPE_START = 4

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.WHITE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA]                     = CColors.RED
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_START]                    = CColors.GREEN

CBlock.RandomBlockType = function()
    local iBlockType = math.random(1,2)
    if iBlockType == 2 then iBlockType = 3 end

    return iBlockType
end

CBlock.NewBlock = function(iX, iY, iBlockType)
    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false

    if iBlockType == CBlock.BLOCK_TYPE_START then
        CBlock.tBlocks[iX][iY].bVisible = true
    end
end

CBlock.RegisterBlockClick = function(iX, iY)
    if not CBlock.tBlocks[iX][iY].bVisible then return; end

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CGameMode.PlayerTouchedLava()
        CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType])
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CGameMode.RoundScoreAdd(1)
    end
end

CBlock.AnimateVisibility = function()
    local iY = 1

    CTimer.New(CPaint.ANIMATION_DELAY, function()
        for iX = 1, tGame.Cols do
            if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                CBlock.tBlocks[iX][iY].bVisible = true

                if tFloor[iX][iY].bClick then
                    CBlock.RegisterBlockClick(iX, iY)
                end
            end
        end

        if iY < tGame.Rows then
            iY = iY + 1
            return CPaint.ANIMATION_DELAY
        end

        return nil
    end)
end

CBlock.LoadBlockList = function()
    CBlock.tBlockList = {}
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            local iBlockID = #CBlock.tBlockList+1
            CBlock.tBlockList[iBlockID] = {}
            CBlock.tBlockList[iBlockID].iX = iX
            CBlock.tBlockList[iBlockID].iY = iY
        end
    end
end
--//

--UNITS
CUnits = {}
CUnits.UNIT_SIZE = 2

CUnits.tUnits = {}
CUnits.tUnitStruct = {
    iX = 0,
    iY = 0,
    iColor = 0,
    tShadow = {},
    bCanDamage = true,
    iDestX = 0,
    iDestY = 0,
    tPath = {},
    iStep = 2,
    iCantMove = 0,
}

CUnits.NewUnit = function(iX, iY)
    iUnitID = #CUnits.tUnits+1
    CUnits.tUnits[iUnitID] = CHelp.ShallowCopy(CUnits.tUnitStruct)
    CUnits.tUnits[iUnitID].iX = iX
    CUnits.tUnits[iUnitID].iY = iY
    CUnits.tUnits[iUnitID].iColor = CColors.YELLOW
    CUnits.tUnits[iUnitID].bCanDamage = true
end

CUnits.RandomDestinationForUnit = function(iUnitID)
    CUnits.tUnits[iUnitID].iDestX = math.random( 1, tGame.Cols )
    CUnits.tUnits[iUnitID].iDestY = math.random( 1, tGame.Rows )
    CUnits.tUnits[iUnitID].iStep = 2

    if tFloor[CUnits.tUnits[iUnitID].iDestX][CUnits.tUnits[iUnitID].iDestY].bBlocked then
        CUnits.RandomDestinationForUnit(iUnitID)
        return;
    end

    local tStartBlock = {iX = CUnits.tUnits[iUnitID].iX, iY = CUnits.tUnits[iUnitID].iY}
    local tGoalBlock = {iX = CUnits.tUnits[iUnitID].iDestX, iY = CUnits.tUnits[iUnitID].iDestY}

    CUnits.tUnits[iUnitID].tPath = CPath.Path(tStartBlock, tGoalBlock, CBlock.tBlockList)
    if CUnits.tUnits[iUnitID].tPath == nil then
        CUnits.RandomDestinationForUnit(iUnitID)
        return;
    end
end

CUnits.RectHasUnitsOrBlocked = function(iXStart, iYStart, iSize)
    if iXStart < 0 or iXStart > tGame.Cols or iYStart < 0 or iYStart > tGame.Rows then return true end

    for iX = iXStart, iXStart + iSize do
        for iY = iYStart, iYStart + iSize do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].iUnitID > 0 then return true end
                if tFloor[iX][iY].bDefect then return true end
                if tFloor[iX][iY].bBlocked then return true end
            end
        end
    end

    return false
end

CUnits.ProcessUnits = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            CUnits.UnitThink(iUnitID)
        end
    end
end

--UNIT AI
CUnits.UnitThink = function(iUnitID)
    CUnits.UnitThinkDefault(iUnitID)
end

CUnits.UnitThinkDefault = function(iUnitID)
    if CUnits.tUnits[iUnitID].iDestX == 0 or (CUnits.tUnits[iUnitID].iX == CUnits.tUnits[iUnitID].iDestX and CUnits.tUnits[iUnitID].iY == CUnits.tUnits[iUnitID].iDestY) then
        CLog.print("New Destination for unit #"..iUnitID)
        CUnits.RandomDestinationForUnit(iUnitID)
    end

    local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitID)

    if CUnits.CanMove(iUnitID, iXPlus, iYPlus) then
        CUnits.Move(iUnitID, iXPlus, iYPlus) 
        CUnits.tUnits[iUnitID].iStep = CUnits.tUnits[iUnitID].iStep + 1        
    else
        CUnits.tUnits[iUnitID].iCantMove = CUnits.tUnits[iUnitID].iCantMove + 1

        if CUnits.tUnits[iUnitID].iCantMove >= 5 then
            CUnits.tUnits[iUnitID].iCantMove = 0
            CLog.print("Unit #"..iUnitID.." cant move! generating new destination")
            CUnits.RandomDestinationForUnit(iUnitID)
        end
    end
end
--/

--UNIT MOVEMENT
CUnits.CanMove = function(iUnitID, iXPlus, iYPlus)
    if iXPlus == 0 and iYPlus == 0 then return false end

    local iX = CUnits.tUnits[iUnitID].iX + iXPlus
    local iY = CUnits.tUnits[iUnitID].iY + iYPlus

    --if CUnits.tUnits[iUnitID].tShadow ~= nil and CUnits.tUnits[iUnitID].tShadow.iX == iX and CUnits.tUnits[iUnitID].tShadow.iY == iY then return false end

    for iXCheck = iX, iX + CUnits.UNIT_SIZE-1 do
        for iYCheck = iY, iY + CUnits.UNIT_SIZE-1 do
            if not tFloor[iXCheck] or not tFloor[iXCheck][iYCheck] then return true end
            if tFloor[iXCheck][iYCheck].iUnitID > 0 and tFloor[iXCheck][iYCheck].iUnitID ~= iUnitID then return false end
            if tFloor[iXCheck][iYCheck].bBlocked then return false end
            --if tFloor[iXCheck][iYCheck].bDefect then return false end
        end
    end

    return true
end

CUnits.Move = function(iUnitID, iXPlus, iYPlus)
    CUnits.tUnits[iUnitID].tShadow = {iX = CUnits.tUnits[iUnitID].iX, iY = CUnits.tUnits[iUnitID].iY}

    CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iXPlus
    CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iYPlus

    if CheckPositionClick({X = CUnits.tUnits[iUnitID].iX, Y = CUnits.tUnits[iUnitID].iY}, CUnits.UNIT_SIZE, CUnits.UNIT_SIZE) then
        CUnits.UnitDamagePlayer(iUnitID, 1)
    end
end

CUnits.GetDestinationXYPlus = function(iUnitID)
    if CUnits.tUnits[iUnitID].tPath == nil or CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep] == nil then 
        CUnits.RandomDestinationForUnit(iUnitID)
        return 0, 0 
    end

    local tStep = CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep]

    --CLog.print(tStep.iX - CUnits.tUnits[iUnitID].iX.." "..tStep.iY - CUnits.tUnits[iUnitID].iY)
    return tStep.iX - CUnits.tUnits[iUnitID].iX, tStep.iY - CUnits.tUnits[iUnitID].iY
end

--UNIT EVENTS
CUnits.UnitDamagePlayer = function(iUnitID, iHealthPenalty)
    if not CUnits.tUnits[iUnitID].bCanDamage then return; end 

    CAudio.PlayAsync(CAudio.MISCLICK)

    tGameStats.CurrentLives = tGameStats.CurrentLives - iHealthPenalty

    CUnits.tUnits[iUnitID].bCanDamage = false
    CUnits.tUnits[iUnitID].iColor = CColors.MAGENTA
    CTimer.New(2000, function()
        CUnits.tUnits[iUnitID].bCanDamage = true
        CUnits.tUnits[iUnitID].iColor = CColors.YELLOW
        return nil;
    end)
end
--/
--//

--PATHFINDING
CPath = {}
CPath.INF = 1/0
CPath.MAX_ITER = 5000
CPath.tCached = {}

CPath.Dist = function(iX1, iY1, iX2, iY2)
    return math.sqrt(math.pow(iX2 - iX1, 2) + math.pow(iY2 - iY1, 2))
end

CPath.DistBetween = function(tBlock1, tBlock2)
    return CPath.Dist(tBlock1.iX, tBlock1.iY, tBlock2.iX, tBlock2.iY)
end

CPath.Cost = function(tBlock1, tBlock2)
    return CPath.Dist(tBlock1.iX, tBlock1.iY, tBlock2.iX, tBlock2.iY)
end

CPath.LowScore = function(tSet, tScores)
    local iLowest, tBest = CPath.INF, nil
    for _, tBlock in ipairs(tSet) do
        local iScore = tScores[tBlock]
        if iScore < iLowest then
            iLowest, tBest = iScore, tBlock
        end
    end

    return tBest
end

CPath.Neighbors = function(tBlock, tBlocks)
    local tNeighbors = {}
    for _, tNeighbor in ipairs(tBlocks) do
        if not CPath.Equals(tBlock, tNeighbor) and CPath.ValidNeighbor(tBlock, tNeighbor) then
            table.insert(tNeighbors, tNeighbor)
        end
    end

    return tNeighbors
end

CPath.NotIn = function(tSet, tBlock)
    for _, tSetBlock in ipairs(tSet) do
        if CPath.Equals(tSetBlock, tBlock) then return false end
    end

    return true
end

CPath.Remove = function(tSet, tBlock)
    for i, tSetBlock in ipairs(tSet) do
        if tSetBlock == tBlock then
            tSet[i] = tSet[#tSet]
            tSet[#tSet] = nil
            return;
        end
    end
end

CPath.Unwind = function(tPath, tMap, tBlock)
    if tMap[tBlock] then
        table.insert(tPath, 1, tMap[tBlock])
        return CPath.Unwind(tPath, tMap, tMap[tBlock])
    else
        return tPath
    end
end

CPath.ValidNeighbor = function(tBlock, tNeighbor)
    if not tFloor[tNeighbor.iX] or not tFloor[tNeighbor.iX][tNeighbor.iY] then return false end
    if not CBlock.tBlocks[tNeighbor.iX] or not CBlock.tBlocks[tNeighbor.iX][tNeighbor.iY] then return false end
    if tFloor[tNeighbor.iX][tNeighbor.iY].bBlocked then return false end
    if CPath.DistBetween(tBlock, tNeighbor) > 1 then return false end 

    for iX = tNeighbor.iX, tNeighbor.iX + CUnits.UNIT_SIZE-1 do
        if not tFloor[iX] or not CBlock.tBlocks[iX] then return false end
        for iY = tNeighbor.iY, tNeighbor.iY + CUnits.UNIT_SIZE-1 do  
            if not tFloor[iX][iY] or not CBlock.tBlocks[iX][iY] then return false end
            if tFloor[iX][iY].bBlocked then return false end
        end
    end

    return true
end

CPath.Equals = function(tBlock1, tBlock2)
    return tBlock1.iX == tBlock2.iX and tBlock1.iY == tBlock2.iY
end

CPath.AStar = function(tStartBlock, tGoalBlock, tBlocks)
    local tClosedSet = {}
    local tOpenSet = {tStartBlock}
    local tCameFrom = {}

    local tGScore, tFScore = {}, {}
    tGScore[tStartBlock] = 0
    tFScore[tStartBlock] = tGScore[tStartBlock] + CPath.Cost(tStartBlock, tGoalBlock)

    local iIter = 0
    while #tOpenSet > 0 do
        iIter = iIter + 1
        if iIter >= CPath.MAX_ITER then
            return nil
        end

        local tCurrent = CPath.LowScore(tOpenSet, tFScore)
        if CPath.Equals(tCurrent, tGoalBlock) then
            local tPath = CPath.Unwind({}, tCameFrom, tCurrent)
            table.insert(tPath, tCurrent)
            return tPath
        end

        --CLog.print(tCurrent.iX.."-"..tCurrent.iY.." g:"..tGoalBlock.iX.."-"..tGoalBlock.iY)

        CPath.Remove(tOpenSet, tCurrent)
        table.insert(tClosedSet, tCurrent)

        local tNeighbors = CPath.Neighbors(tCurrent, tBlocks)
        for _, tNeighbor in ipairs(tNeighbors) do
            if CPath.NotIn(tClosedSet, tNeighbor) then
                local tTentGScore = tGScore[tCurrent] + CPath.DistBetween(tCurrent, tNeighbor)

                if CPath.NotIn(tOpenSet, tNeighbor) or tTentGScore < tGScore[tNeighbor] then
                    tCameFrom[tNeighbor] = tCurrent
                    tGScore[tNeighbor] = tTentGScore
                    tFScore[tNeighbor] = tGScore[tNeighbor] + CPath.Cost(tNeighbor, tGoalBlock)

                    if CPath.NotIn(tOpenSet, tNeighbor) then
                        table.insert(tOpenSet, tNeighbor)
                    end
                end
            end
        end
    end

    return nil
end

CPath.Path = function(tStartBlock, tGoalBlock, tBlocks)
    if not CPath.tCached[tStartBlock] then
        CPath.tCached[tStartBlock] = {}
    elseif CPath.tCached[tStartBlock][tGoalBlock] then
        return CPath.tCached[tStartBlock][tGoalBlock]
    end

    local tResPath = CPath.AStar(tStartBlock, tGoalBlock, tBlocks)
    CPath.tCached[tStartBlock][tGoalBlock] = tResPath

    --[[
    if tResPath == nil then
        CLog.print("Cant calculate path!")
    else
        CLog.print("Path calculated!")
        for i, tStep in ipairs(tResPath) do
            CLog.print("Step #"..i..": "..tStep.iX.."-"..tStep.iY)
        end
    end
    ]]

    return tResPath
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.Objects = function()
    CPaint.Blocks()
    CPaint.Units()
end

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX][iY] then
                    if not CBlock.tBlocks[iX][iY].bVisible then
                        tFloor[iX][iY].iColor = CColors.RED
                        tFloor[iX][iY].iBright = tConfig.Bright
                    else
                        tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                            tFloor[iX][iY].iBright = CColors.BRIGHT15
                        end

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected then
                            tFloor[iX][iY].iBright = CColors.BRIGHT0
                        end
                    end
                end
            end
        end
    end
end

CPaint.Units = function()
    if iGameState ~= GAMESTATE_GAME then return; end

    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            if CUnits.tUnits[iUnitID].tShadow ~= nil and CUnits.tUnits[iUnitID].tShadow.iX ~= nil then
                CPaint.UnitShadow(iUnitID)
            end

            CPaint.Unit(iUnitID)
        end
    end
end

CPaint.Unit = function(iUnitID)
    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.UNIT_SIZE-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.UNIT_SIZE-1 do

            if tFloor[iX] and tFloor[iX][iY] and CBlock.tBlocks[iX][iY].bVisible then
                tFloor[iX][iY].iUnitID = iUnitID
                tFloor[iX][iY].iColor = CUnits.tUnits[iUnitID].iColor
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
    end
end

CPaint.UnitShadow = function(iUnitID)
    for iX = CUnits.tUnits[iUnitID].tShadow.iX, CUnits.tUnits[iUnitID].tShadow.iX + CUnits.UNIT_SIZE-1 do
        for iY = CUnits.tUnits[iUnitID].tShadow.iY, CUnits.tUnits[iUnitID].tShadow.iY + CUnits.UNIT_SIZE-1 do
            if tFloor[iX] and tFloor[iX][iY] and CBlock.tBlocks[iX][iY].bVisible then
                tFloor[iX][iY].iColor = CUnits.tUnits[iUnitID].iColor
                tFloor[iX][iY].iBright = 1
            end
        end
    end
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    CTimer.New(CPaint.ANIMATION_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.MAGENTA
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = iColor
            iCount = iCount + 1
        end
        
        if iCount <= iFlickerCount then
            return CPaint.ANIMATION_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end
--//

--TIMER класс отвечает за таймеры, очень полезная штука. можно вернуть время нового таймера с тем же колбеком
CTimer = {}
CTimer.tTimers = {}

CTimer.New = function(iSetTime, fCallback)
    CTimer.tTimers[#CTimer.tTimers+1] = {iTime = iSetTime, fCallback = fCallback}
end

-- просчёт таймеров каждый тик
CTimer.CountTimers = function(iTimePassed)
    for i = 1, #CTimer.tTimers do
        if CTimer.tTimers[i] ~= nil then
            CTimer.tTimers[i].iTime = CTimer.tTimers[i].iTime - iTimePassed

            if CTimer.tTimers[i].iTime <= 0 then
                iNewTime = CTimer.tTimers[i].fCallback()
                if iNewTime and iNewTime ~= nil then -- если в return было число то создаём новый таймер с тем же колбеком
                    iNewTime = iNewTime + CTimer.tTimers[i].iTime
                    CTimer.New(iNewTime, CTimer.tTimers[i].fCallback)
                end

                CTimer.tTimers[i] = nil
            end
        end
    end
end
--//

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSizeX, iSizeY)
    for iX = tStart.X, tStart.X + iSizeX - 1 do
        for iY = tStart.Y, tStart.Y + iSizeY - 1 do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].bClick then
                    return true
                end 
            end
        end
    end

    return false
end

function SetPositionColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i / iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetRectColorBright(iX, iY, iSizeX, iSizeY, iColor, iBright)
    for i = iX, iX + iSizeX do
        for j = iY, iY + iSizeY do
            if not (i < 1 or j > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
end

function RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iUnitID = 0
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end

function SetAllButtonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end
--//

--//
function GetStats()
    return tGameStats
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if click.Click and iGameState == GAMESTATE_GAME then
        if CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
            CBlock.RegisterBlockClick(click.X, click.Y)
        end

        if tFloor[click.X][click.Y].iUnitID > 0 then
            CUnits.UnitDamagePlayer(tFloor[click.X][click.Y].iUnitID, 1)
        end
    end    
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click then
        bAnyButtonClick = true
    end    
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end