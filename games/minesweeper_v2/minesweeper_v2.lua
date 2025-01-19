--[[
    Название: Название механики
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
]]
math.randomseed(os.time())
require("avonlib")

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

local tPlayerInGame = {}
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
    TargetScore = 1,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = CColors.NONE,
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

    CGameMode.InitGameMode()

    CAudio.PlaySync("games/minesweeper.mp3")
    CAudio.PlaySync("voices/choose-color.mp3")
    CAudio.PlaySync("voices/minesweeper-guide.mp3")
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

        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
    end

    if iGameState == GAMESTATE_FINISH then
        tGameResults.AfterDelay = false
        return tGameResults
    end     

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    local iPlayersReady = 0

    for iPlayerID = 1, #tGame.StartPositions do
        local iBright = CColors.BRIGHT15
        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionSizeX, tGame.StartPositionSizeY) then
            tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
            iBright = tConfig.Bright
            iPlayersReady = iPlayersReady + 1
            tPlayerInGame[iPlayerID] = true
        else
            tGameStats.Players[iPlayerID].Color = CColors.NONE
            tPlayerInGame[iPlayerID] = false
        end

        CPaint.PlayerZone(iPlayerID, iBright)           
    end

    if iPlayersReady > 1 and bAnyButtonClick then
        bAnyButtonClick = false
        CGameMode.iAlivePlayerCount = iPlayersReady
        iGameState = GAMESTATE_GAME

        CGameMode.StartNextRoundCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end           
    end    

    CPaint.Blocks()
end

function PostGameTick()
    
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
CGameMode.iAlivePlayerCount = 0
CGameMode.tPlayerCoinsThisRound = {}
CGameMode.iFinishedCount = 0
CGameMode.tPlayerFinished = {}

CGameMode.tMap = {}
CGameMode.tMapCoinCount = {}

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = tConfig.RoundCount
    CGameMode.iPlayerCount = #tGame.StartPositions

    for iPlayerID = 1, CGameMode.iPlayerCount do
        tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
    end
end

CGameMode.StartNextRoundCountDown = function(iCountDownTime)
    CGameMode.PrepareNextRound()

    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then

            if CGameMode.iRound == 1 then
                CGameMode.StartGame()
            end

            CGameMode.StartRound()
            
            return nil
        else
            if CGameMode.iCountdown <= 5 then
                CAudio.PlaySyncFromScratch("")
                CAudio.PlayLeftAudio(CGameMode.iCountdown)
            end
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
    CGameMode.tMapCoinCount = {}

    CBlock.tBlocks = {}
    CGameMode.tMap = CMaps.GetRandomMap()
    CMaps.LoadMap(CGameMode.tMap)

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

        CGameMode.StartNextRoundCountDown(5)
    end
end

CGameMode.EndGame = function()
    local iMaxScore = -999

    for iPlayerID = 1, CGameMode.iPlayerCount do
        if tPlayerInGame[iPlayerID] and tGameStats.Players[iPlayerID].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerID].Score
            CGameMode.iWinnerID = iPlayerID
        end
    end

    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)
    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    tGameResults.Won = true
    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.PlayerTouchedGround = function(iPlayerID)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

    if CGameMode.tPlayerCoinsThisRound[iPlayerID] == nil then CGameMode.tPlayerCoinsThisRound[iPlayerID] = 0 end
    CGameMode.tPlayerCoinsThisRound[iPlayerID] = CGameMode.tPlayerCoinsThisRound[iPlayerID] + 1

    if CGameMode.tPlayerCoinsThisRound[iPlayerID] >= CGameMode.tMapCoinCount[iPlayerID] then
        CGameMode.PlayerFinish(iPlayerID)
    else
        CAudio.PlayAsync(CAudio.CLICK)
    end

    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end
end

CGameMode.PlayerFinish = function(iPlayerID)
    CAudio.PlayAsync(CAudio.STAGE_DONE)

    CGameMode.iFinishedCount = CGameMode.iFinishedCount + 1
    CGameMode.tPlayerFinished[iPlayerID] = true

    local iFinishBonusMultiplier = #tGame.StartPositions - CGameMode.iFinishedCount

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + (CGameMode.tPlayerCoinsThisRound[iPlayerID] * iFinishBonusMultiplier)

    if CGameMode.iFinishedCount == CGameMode.iAlivePlayerCount then
        CGameMode.EndRound()
    end    
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

    return tGame.Maps[CMaps.iRandomMapID]
end

CMaps.LoadMap = function(tMap)
    local iMapX = 0
    local iMapY = 0
    local iBlockCount = 0
    local iCoinCount = 0

    for iY = tGame.GameY, tGame.GameSizeY do
        iMapY = iMapY + 1

        for iX = tGame.GameX, tGame.GameSizeX do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_MINE
            local iPlayerID = 0
            if tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil and tMap[iMapY][iMapX] > 0 then 
                if tPlayerInGame[tMap[iMapY][iMapX]] then
                    iBlockType = CBlock.BLOCK_TYPE_GROUND
                    iPlayerID = tMap[iMapY][iMapX]
                    CGameMode.tMapCoinCount[iPlayerID] = (CGameMode.tMapCoinCount[iPlayerID] or 0) + 1
                    if CGameMode.tMapCoinCount[iPlayerID] > tGameStats.TargetScore then tGameStats.TargetScore = CGameMode.tMapCoinCount[iPlayerID] end
                end
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
            iBlockCount = iBlockCount + 1

            if iBlockType == CBlock.BLOCK_TYPE_GROUND then
                iCoinCount = iCoinCount + 1
            end
        end

        iMapX = 0
    end
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
CBlock.bAnimationOn = false
CBlock.bAnimSwitch = false

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
    if not CGameMode.bRoundStarted or CBlock.tBlocks[iX][iY].bVisible then return; end

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_MINE and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CBlock.tBlocks[iX][iY].bVisible = true
        CAudio.PlayAsync(CAudio.MISCLICK)

    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CBlock.tBlocks[iX][iY].bVisible = true

        CGameMode.PlayerTouchedGround(CBlock.tBlocks[iX][iY].iPlayerID)
    end
end

CBlock.AnimateVisibility = function(bVisible)
    CBlock.bAnimationOn = bVisible

    if CBlock.bAnimationOn then
        AL.NewTimer(500, function()
            CBlock.bAnimSwitch = not CBlock.bAnimSwitch

            if CBlock.bAnimationOn then return 500; end
            return nil
        end)
    end
end
--//

--PAINT
CPaint = {}

CPaint.PlayerZone = function(iPlayerID, iBright)
     for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y do
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
        end
    end   
end

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                    if CBlock.bAnimationOn then
                        tFloor[iX][iY].iColor = CColors.NONE
                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND and CBlock.bAnimSwitch then
                            tFloor[iX][iY].iColor = tGameStats.Players[CBlock.tBlocks[iX][iY].iPlayerID].Color                        
                        elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_MINE and not CBlock.bAnimSwitch then
                            tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        end
                    else
                        if not CBlock.tBlocks[iX][iY].bVisible then
                            tFloor[iX][iY].iColor = CColors.NONE
                        else
                            if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                                if CGameMode.tPlayerFinished[CBlock.tBlocks[iX][iY].iPlayerID] then
                                    tFloor[iX][iY].iColor = CColors.GREEN
                                else
                                    tFloor[iX][iY].iColor = tGameStats.Players[CBlock.tBlocks[iX][iY].iPlayerID].Color
                                end
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
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
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

function SetAllButtonColorBright(iColor, iBright, bCheckDefect)
    for i, tButton in pairs(tButtons) do
        if not bCheckDefect or not tButtons[i].bDefect then
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
	iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    if tFloor[click.X] and tFloor[click.X][click.Y] then
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
            CBlock.RegisterBlockClick(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end

    if defect.Defect and CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and not CBlock.tBlocks[defect.X][defect.Y].bVisible 
    and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_GROUND then    
        CBlock.RegisterBlockClick(defect.X, defect.Y)
    end    
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click and not tButtons[click.Button].bDefect then
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