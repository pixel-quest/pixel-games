--[[
    Название: Сапёр
    Автор: Avondale, дискорд - avonda

    Чтобы начать игру нужно нажать на любую синюю кнопку

    Описание механики:
        Игрокам на несколько секунд показывается минное поле, затем оно покрывается туманом
        Нужно собрать все монеты как можно быстрее, стараясь не попадать на мины
        
        За монету даётся +1 очко, за мину -1 очко. 
        Очки за каждый раунд умножаются, в зависимости от позиции игрока, чем быстрее собрал все монеты - тем больше очков
        У кого больше очков тот и победил

    Идеи по доработке:
        Больше карт
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
    TargetScore = 1,
    StageNum = 1,
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

    tGameStats.TotalStages = tConfig.RoundCount
    CGameMode.InitPlayers()
    CGameMode.AnnounceGameStart()
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

    if bAnyButtonClick then
        bAnyButtonClick = false

        if CGameMode.iCountdown == 0 then
            iGameState = GAMESTATE_GAME
            CGameMode.StartNextRoundCountDown(tConfig.GameCountdown)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Blocks()
    CPaint.FinishedPlayerZones()
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
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.iWinnerID = -1
CGameMode.iRound = 1
CGameMode.bRoundStarted = false
CGameMode.iPlayerCount = 1
CGameMode.tPlayerCoinsThisRound = {}
CGameMode.iFinishedCount = 0
CGameMode.tPlayerFinished = {}

CGameMode.tMap = {}
CGameMode.iMapCoinCount = 0

CGameMode.InitPlayers = function()
    CGameMode.iPlayerCount = #tGame.StartPositions

    for iPlayerID = 1, CGameMode.iPlayerCount do
        tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
    end
end

CGameMode.AnnounceGameStart = function()
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartNextRoundCountDown = function(iCountDownTime)
    CGameMode.PrepareNextRound()

    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then

            if CGameMode.iRound == 1 then
                CGameMode.StartGame()
            end

            CGameMode.StartRound()
            
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlaySync(CAudio.START_GAME)
end

CGameMode.PrepareNextRound = function()
    CGameMode.tPlayerCoinsThisRound = {}
    CGameMode.iFinishedCount = 0
    CGameMode.tPlayerFinished = {}

    CPaint.ResetAnimation()

    CBlock.tBlocks = {}
    CGameMode.tMap = CMaps.GetRandomMap()

    for iPlayerID = 1, CGameMode.iPlayerCount do
        CMaps.LoadMapForPlayer(CGameMode.tMap, iPlayerID)
    end

    CBlock.AnimateVisibility(true)
end

CGameMode.StartRound = function()
    CAudio.PlayRandomBackground()
    CGameMode.bRoundStarted = true

    CBlock.AnimateVisibility(false)
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundStarted = false

    if CGameMode.iRound == tGameStats.TotalStages then
        CGameMode.EndGame()
    else
        CGameMode.iRound = CGameMode.iRound + 1
        tGameStats.StageNum = CGameMode.iRound

        CGameMode.StartNextRoundCountDown(tConfig.RoundCountdown)
    end
end

CGameMode.EndGame = function()
    if CGameMode.iPlayerCount == 1 then
        if tGameStats.Players[1].Score > 0 then
            CAudio.PlaySync(CAudio.VICTORY)
        else
            CAudio.PlaySync(CAudio.DEFEAT)
        end
    else
        local iMaxScore = -999

        for iPlayerID = 1, CGameMode.iPlayerCount do
            if tGameStats.Players[iPlayerID].Score > iMaxScore then
                iMaxScore = tGameStats.Players[iPlayerID].Score
                CGameMode.iWinnerID = iPlayerID
            end
        end

        iGameState = GAMESTATE_POSTGAME

        CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
        CAudio.PlaySync(CAudio.VICTORY)
    end

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.PlayerTouchedGround = function(iPlayerID)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

    if CGameMode.tPlayerCoinsThisRound[iPlayerID] == nil then CGameMode.tPlayerCoinsThisRound[iPlayerID] = 0 end
    CGameMode.tPlayerCoinsThisRound[iPlayerID] = CGameMode.tPlayerCoinsThisRound[iPlayerID] + 1

    if CGameMode.tPlayerCoinsThisRound[iPlayerID] >= CGameMode.iMapCoinCount then
        CGameMode.iFinishedCount = CGameMode.iFinishedCount + 1
        CGameMode.tPlayerFinished[iPlayerID] = true

        local iFinishBonusMultiplier = #tGame.StartPositions - CGameMode.iFinishedCount

        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + (CGameMode.tPlayerCoinsThisRound[iPlayerID] * iFinishBonusMultiplier)

        if CGameMode.iFinishedCount == CGameMode.iPlayerCount then
            CGameMode.EndRound()
        end
    end

    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end

    CAudio.PlayAsync(CAudio.CLICK)
end

CGameMode.PlayerTouchedMine = function(iPlayerID)
    --if tGameStats.Players[iPlayerID].Score > 0 then
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score - 1
    --end

    CAudio.PlayAsync(CAudio.MISCLICK)
end
--//

--MAPS
CMaps = {}
CMaps.iRandomMapID = 0
CMaps.iRandomMapIDIncrement = math.random(-2,2)

CMaps.GetRandomMap = function()
    if CMaps.iRandomMapID == 0 then 
        CMaps.iRandomMapID = math.random(1, #tGame.Maps)
    end
    if CMaps.iRandomMapIDIncrement == 0 then
        CMaps.iRandomMapIDIncrement = 1
    end

    CMaps.iRandomMapID = CMaps.iRandomMapID + CMaps.iRandomMapIDIncrement
    if CMaps.iRandomMapID > #tGame.Maps then
        CMaps.iRandomMapID = (CMaps.iRandomMapID-#tGame.Maps)
    elseif CMaps.iRandomMapID < 1 then
        CMaps.iRandomMapID = #tGame.Maps + (CMaps.iRandomMapID)
    end

    CLog.print("random map #"..CMaps.iRandomMapID)

    return tGame.Maps[CMaps.iRandomMapID]
end

CMaps.LoadMapForPlayer = function(tMap, iPlayerID)
    local iMapX = 0
    local iMapY = 0
    local iBlockCount = 0
    local iCoinCount = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil then 
                iBlockType = tMap[iMapY][iMapX]
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
            iBlockCount = iBlockCount + 1

            if iBlockType == CBlock.BLOCK_TYPE_GROUND then
                iCoinCount = iCoinCount + 1
            end
        end

        iMapX = 0
    end

    CGameMode.iMapCoinCount = iCoinCount
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
    bVisible = true,
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_MINE = 2

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_MINE]                     = CColors.RED

CBlock.NewBlock = function(iX, iY, iBlockType, iPlayerID)
    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iPlayerID = iPlayerID
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false
end

CBlock.RegisterBlockClick = function(iX, iY)
    if not CGameMode.bRoundStarted then return; end

    local iPlayerID = CBlock.tBlocks[iX][iY].iPlayerID

    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_MINE and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CBlock.tBlocks[iX][iY].bVisible = true
        CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType])

        CGameMode.PlayerTouchedMine(iPlayerID)
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CBlock.tBlocks[iX][iY].bVisible = true

        CGameMode.PlayerTouchedGround(iPlayerID)
    end
end

CBlock.AnimateVisibility = function(bVisible)
    for iPlayerID = 1, CGameMode.iPlayerCount do
        local iY = tGame.StartPositions[iPlayerID].Y

        CTimer.New(CPaint.ANIMATION_DELAY, function()
            for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX do
                if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                    CBlock.tBlocks[iX][iY].bVisible = bVisible

                    if bVisible == false and tFloor[iX][iY].bDefect and CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                        CBlock.RegisterBlockClick(iX, iY)
                    end
                end
            end

            if iY < tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY then
                iY = iY + 1
                return CPaint.ANIMATION_DELAY
            end
            return nil
        end)
    end
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                    if not CBlock.tBlocks[iX][iY].bVisible then
                        tFloor[iX][iY].iColor = CColors.WHITE
                        tFloor[iX][iY].iBright = 2
                    else
                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                            tFloor[iX][iY].iColor = tGameStats.Players[CBlock.tBlocks[iX][iY].iPlayerID].Color
                        else
                            tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        end
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright
                    end
                end
            end
        end
    end
end

CPaint.FinishedPlayerZones = function()
    for iPlayerID = 1, CGameMode.iPlayerCount do
        if CGameMode.tPlayerFinished[iPlayerID] then
            for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
                for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y do
                    tFloor[iX][iY].iBright = tConfig.Bright
                    tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
                end
            end
        end
    end
end

CPaint.ResetAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
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

    if click.Click and CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
        CBlock.RegisterBlockClick(click.X, click.Y)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect

    if defect.Defect and CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and not CBlock.tBlocks[defect.X][defect.Y].bVisible 
    and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_GROUND then    
        CBlock.RegisterBlockClick(defect.X, defect.Y)
    end
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