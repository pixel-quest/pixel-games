--[[
    Название: Классики
    Автор: Avondale, дискорд - avonda

    Описание механики:


    Идеи по доработке: 

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
    bAnimated = false,
}
local tButtonStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
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

    for iPlayerID = 1, #tGame.StartPositions do
        tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
    end

    CGameMode.InitGameMode()

    tGameStats.TargetScore = 1

    CAudio.PlaySyncFromScratch("games/classics-game.mp3")
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.PlayerZones()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    if bAnyButtonClick then
        bAnyButtonClick = false
        iGameState = GAMESTATE_GAME
        CGameMode.CountDownNextRound()
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.PlayerZones()
    CPaint.Blocks()
end

function PostGameTick()
    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
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
    CGameMode.EndGame()
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = -1
CGameMode.iWinnerID = -1
CGameMode.bGameStarted = false
CGameMode.tPlayerSeeds = {}
CGameMode.tPlayerMapTotalCoinCount = {}
CGameMode.tPlayerMapTotalCoinCollected = {}
CGameMode.iDefaultSeed = 1

CGameMode.InitGameMode = function()
    if tGame.Direction == "right" then
        CGameMode.iFinishPosition = tGame.StartPositionSizeX
    elseif tGame.Direction == "left" then
        CGameMode.iFinishPosition = 1
    end
end

CGameMode.CountDownNextRound = function()
    CGameMode.bGameStarted = false
    CGameMode.iDefaultSeed = math.random(1,99999)

    CGameMode.iCountdown = tConfig.GameCountdown
    tGameStats.StageLeftDuration = CGameMode.iCountdown

    CTimer.New(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown
        
        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1

            CGameMode.Start()
            CAudio.PlaySync(CAudio.START_GAME)

            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1 

            return 1000
        end
    end)
end

CGameMode.Start = function()
    CAudio.PlayRandomBackground()
    tGameStats.StageLeftDuration = tConfig.GameLength
    CGameMode.bGameStarted = true
    CGameMode.LoadMapsForPlayers()

    if tGameStats.StageLeftDuration > 1 then
        CTimer.New(1000, function()
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration <= 0 then
                CGameMode.EndGame()
                return nil
            end

            if tGameStats.StageLeftDuration < 10 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000
        end)
    end
end

CGameMode.LoadMapsForPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        CGameMode.tPlayerSeeds[iPlayerID] = CGameMode.iDefaultSeed
        CMaps.LoadMapForPlayer(iPlayerID)
        CBlock.AnimateVisibility(iPlayerID)
    end
end

CGameMode.PlayerRoundScoreAdd = function(iPlayerID, iScore)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScore

    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end

    CAudio.PlayAsync(CAudio.CLICK);
end

CGameMode.PlayerScorePenalty = function(iPlayerID, iPenalty)
    if tGameStats.Players[iPlayerID].Score > 0 then 
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score - iPenalty
    end

    CAudio.PlayAsync(CAudio.MISCLICK);
end

CGameMode.PlayerFinished = function(iPlayerID)
    CAudio.PlayAsync(CAudio.STAGE_DONE)  
    CBlock.ClearPlayerZone(iPlayerID)
    CMaps.LoadMapForPlayer(iPlayerID)
    CBlock.AnimateVisibility(iPlayerID)
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -999

    for i = 1, #tGame.StartPositions do
        if tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
        end
    end

    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)    
end
--//

--MAPS
CMaps = {}

CMaps.LoadMapForPlayer = function(iPlayerID)
    local tMap, fSeed = CMaps.GenerateRandomMapFromSeed(CGameMode.tPlayerSeeds[iPlayerID])
    CGameMode.tPlayerSeeds[iPlayerID] = fSeed
    CGameMode.tPlayerMapTotalCoinCount[iPlayerID] = 0
    CGameMode.tPlayerMapTotalCoinCollected[iPlayerID] = 0

    local iMapX = 0
    local iMapY = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if not tFloor[iX][iY].bDefect and tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil then 
                iBlockType = tMap[iMapY][iMapX]
            end

            if iBlockType == CBlock.BLOCK_TYPE_COIN then
                CGameMode.tPlayerMapTotalCoinCount[iPlayerID] = CGameMode.tPlayerMapTotalCoinCount[iPlayerID] + 1
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
        end

        iMapX = 0
    end
end

CMaps.GenerateRandomMapFromSeed = function(fSeed)
    local tMap = {}
    local iPrevZoneCoinCount = 1

    for iY = 1, tGame.StartPositionSizeY do
        tMap[iY] = {} 

        local iCoinCount = 0
        local iMaxCoinCount = 0

        iMaxCoinCount, fSeed = CRandom.IntFromSeed(1, 3, fSeed)
        if iMaxCoinCount > 2 then iMaxCoinCount = 2 end

        for iX = 1, tGame.StartPositionSizeX do
            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if iCoinCount < iMaxCoinCount then
                iBlockType, fSeed = CRandom.IntFromSeed(1, 3, fSeed)

                if iBlockType == CBlock.BLOCK_TYPE_GROUND then
                    if (tGame.StartPositionSizeX - iX) - (iMaxCoinCount - iCoinCount) < 0 then
                        iBlockType = CBlock.BLOCK_TYPE_COIN
                    end
                end

                if iBlockType == CBlock.BLOCK_TYPE_COIN then
                    iCoinCount = iCoinCount + 1
                end
            end

            tMap[iY][iX] = iBlockType
        end
    end

    return tMap, fSeed
end
--//

--BLOCK
CBlock = {}
CBlock.tBlocks = {}
CBlock.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iPlayerID = 0,
    iBright = 0,
    bVisible = false,
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_COIN = 2

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.WHITE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE

CBlock.NewBlock = function(iX, iY, iBlockType, iPlayerID)

    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iPlayerID = iPlayerID
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false
end

CBlock.RegisterBlockClick = function(iX, iY)
    if CBlock.tBlocks[iX][iY].bVisible == false then return; end

    local iPlayerID = CBlock.tBlocks[iX][iY].iPlayerID

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CGameMode.PlayerRoundScoreAdd(iPlayerID, 1)
        CGameMode.tPlayerMapTotalCoinCollected[iPlayerID] = CGameMode.tPlayerMapTotalCoinCollected[iPlayerID] + 1
        if CGameMode.tPlayerMapTotalCoinCollected[iPlayerID] == CGameMode.tPlayerMapTotalCoinCount[iPlayerID] then
            CGameMode.PlayerFinished(iPlayerID)
        end

    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND and CBlock.tBlocks[iX][iY].bCollected == false and tConfig.EnableMissPenalty then
        CBlock.tBlocks[iX][iY].bCollected = true
        CGameMode.PlayerScorePenalty(iPlayerID, 1)

        CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType])
    end
end

CBlock.AnimateVisibility = function(iPlayerID)
    local iY = tGame.StartPositions[iPlayerID].Y

    CTimer.New(CPaint.ANIMATION_DELAY*2, function()
        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX do
            if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                CBlock.tBlocks[iX][iY].bVisible = true
            end
        end

        if iY < tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY then
            iY = iY + 1
            return CPaint.ANIMATION_DELAY*2
        end

        return nil
    end)
end

CBlock.ClearPlayerZone = function(iPlayerID)
    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            CBlock.tBlocks[iX][iY] = nil
        end
    end
end
--//

--RANDOM
CRandom = {}

CRandom.fA = 45.0001
CRandom.fB = 1337.0000
CRandom.fM = 99.9999

CRandom.IntFromSeed = function(iMin, iMax, fSeed) -- возвращает iRand, fSeed
    local iRand, fSeed = CRandom.NextFromSeed(fSeed)

    return math.floor(iRand * (iMax-iMin) + iMin), fSeed
end

CRandom.NextFromSeed = function(fSeed)
    fSeed = (CRandom.fA * fSeed + CRandom.fB) % CRandom.fM
    return fSeed % 1, fSeed
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 75

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX][iY] and CBlock.tBlocks[iX][iY].bVisible then
                    if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                        tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN then 
                            tFloor[iX][iY].iColor = tGameStats.Players[CBlock.tBlocks[iX][iY].iPlayerID].Color

                            if CBlock.tBlocks[iX][iY].bCollected then
                                tFloor[iX][iY].iBright = 1
                            end
                        end
                    end
                end
            end
        end
    end
end

CPaint.PlayerZones = function()
    for i = 1, #tGame.StartPositions do
        CPaint.PlayerZone(i, tConfig.Bright)
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX + tGame.StartPositions[iPlayerID].X-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY + tGame.StartPositions[iPlayerID].Y-1 do
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
                tFloor[iX][iY].iBright = iBright-1
            end
        end
    end
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    CTimer.New(CPaint.ANIMATION_DELAY, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.RED
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

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
            end
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

    if click.Click and iGameState == GAMESTATE_GAME and CGameMode.bGameStarted then
        if CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
            CBlock.RegisterBlockClick(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect

    if defect.Defect and CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_COIN then
        CBlock.RegisterBlockClick(defect.X, defect.Y)
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_SETUP and click.Click == true then
        bAnyButtonClick = true
    end       
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect
end