--[[
    Название: Рефлекс/Реакция
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

local tPlayerInGame = {}

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
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    iPlayerID = 0
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
    CGameMode.Announcer()
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

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if bAnyButtonClick then
        bAnyButtonClick = false

        if iPlayersReady > 0 then
            iGameState = GAMESTATE_GAME

            CGameMode.iPlayerCount = iPlayersReady
            CGameMode.StartCountDown(5)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)    
    CPaint.PlayerZones() 
    CPaint.TargetColor()
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
CGameMode.iPlayerCount = 0
CGameMode.iRountCount = 0
CGameMode.bRoundOn = false

CGameMode.iBestScore = 0
CGameMode.iWinnerID = 0

CGameMode.iFinishedPlayerCount = 0
CGameMode.iCorrectlyFinishedPlayerCount = 0
CGameMode.tFinishedPlayer = {}

CGameMode.iTargetPixelColor = CColors.NONE

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = tConfig.RoundCount
end

CGameMode.Announcer = function()
    --voice gamename
    --voice guide
    CAudio.PlaySync("voices/choose-color.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.iRountCount = CGameMode.iRountCount + 1
    tGameStats.StageNum = CGameMode.iRountCount


    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            if CGameMode.iRountCount == 1 then
                CGameMode.StartGame()
            end
            
            CGameMode.StartNextRound()

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
    CAudio.PlayRandomBackground()
end

CGameMode.StartNextRound = function()
    CGameMode.bRoundOn = true

    AL.NewTimer(math.random(2,8)*1000, function()
        CGameMode.NewTargetPixelColor()
    end)
end

CGameMode.NewTargetPixelColor = function()
    CGameMode.iTargetPixelColor = math.random(1,7)
    CAudio.PlaySyncColorSound(CGameMode.iTargetPixelColor)
    tGameStats.TargetColor = CGameMode.iTargetPixelColor
end

CGameMode.EndRound = function()
    CGameMode.bRoundOn = false
    CGameMode.iFinishedPlayerCount = 0
    CGameMode.iCorrectlyFinishedPlayerCount = 0
    CGameMode.tFinishedPlayer = {}
    CGameMode.iTargetPixelColor = CColors.NONE
    tGameStats.TargetColor = CColors.NONE

    if CGameMode.iRountCount == tConfig.RoundCount then
        CGameMode.EndGame()
    else
        CGameMode.StartCountDown(tConfig.RoundCountdown)    
    end
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    CAudio.PlaySync(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)       
end

CGameMode.PlayerClickPixel = function(iPlayerID, iColor)
    if CGameMode.tFinishedPlayer[iPlayerID] ~= nil then return; end

    if iColor == CGameMode.iTargetPixelColor then
        CGameMode.PlayerCorrectTarget(iPlayerID)
        CGameMode.tFinishedPlayer[iPlayerID] = true
    else
        CGameMode.PlayerWrongTarget(iPlayerID)
        CGameMode.tFinishedPlayer[iPlayerID] = false
    end

    CGameMode.iFinishedPlayerCount = CGameMode.iFinishedPlayerCount + 1

    if CGameMode.iFinishedPlayerCount == CGameMode.iPlayerCount then
        AL.NewTimer(2000, function()
            CGameMode.EndRound()
        end)
    end
end

CGameMode.PlayerCorrectTarget = function(iPlayerID)
    CAudio.PlayAsync(CAudio.CLICK)

    local iScoreIncrease = (CGameMode.iPlayerCount - CGameMode.iCorrectlyFinishedPlayerCount) * 2
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScoreIncrease

    CGameMode.iCorrectlyFinishedPlayerCount = CGameMode.iCorrectlyFinishedPlayerCount + 1

    if tGameStats.Players[iPlayerID].Score > CGameMode.iBestScore then
        CGameMode.iBestScore = tGameStats.Players[iPlayerID].Score
        CGameMode.iWinnerID = iPlayerID
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end
end

CGameMode.PlayerWrongTarget = function(iPlayerID)
    CAudio.PlayAsync(CAudio.MISCLICK)
end

--//

--PAINT
CPaint = {}

CPaint.PlayerZones = function()
    for iPlayerID = 1, 6 do
        if tGame.StartPositions[iPlayerID] and tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    local iColor = tGame.StartPositions[iPlayerID].Color

    if iGameState == GAMESTATE_GAME then
        if CGameMode.tFinishedPlayer[iPlayerID] ~= nil then
            if CGameMode.tFinishedPlayer[iPlayerID] == true then
                iColor = CColors.GREEN
            elseif CGameMode.tFinishedPlayer[iPlayerID] == false then
                iColor = CColors.RED
            end
        else
            iBright = iBright-2
        end
    end

    SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
        tGame.StartPositions[iPlayerID].Y, 
        tGame.StartPositionSizeX-1, 
        tGame.StartPositionSizeY-1, 
        iColor, 
        iBright)

    if iGameState == GAMESTATE_GAME and CGameMode.tFinishedPlayer[iPlayerID] == nil then
        CPaint.PlayerZonePixels(iPlayerID, tConfig.Bright)
    end
end

CPaint.PlayerZonePixels = function(iPlayerID, iBright)
    for iY = tGame.StartPositions[iPlayerID].PixelsY, tGame.StartPositions[iPlayerID].PixelsY+1 do
        for iColor = 1, 7 do
            local iX = tGame.StartPositions[iPlayerID].X + iColor-1
            if not tFloor[iX][iY].bDefect then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                tFloor[iX][iY].iPlayerID = iPlayerID
            end
        end
    end
end

CPaint.TargetColor = function()
    if CGameMode.iTargetPixelColor == CColors.NONE then return; end

    local iYStart = math.ceil(tGame.Rows/2)
    for iY = iYStart, iYStart+1 do
        for iX = 1, tGame.Cols do
            tFloor[iX][iY].iColor = CGameMode.iTargetPixelColor
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end
--//

------------------------------AVONLIB
_G.AL = {}
local LOC = {}

--STACK
AL.Stack = function()
    local tStack = {}
    tStack.tTable = {}

    tStack.Push = function(item)
        table.insert(tStack.tTable, item)
    end

    tStack.Pop = function()
        return table.remove(tStack.tTable, 1)
    end

    tStack.Size = function()
        return #tStack.tTable
    end

    return tStack
end
--//

--TIMER
local tTimers = AL.Stack()

AL.NewTimer = function(iSetTime, fCallback)
    tTimers.Push({iTime = iSetTime, fCallback = fCallback})
end

AL.CountTimers = function(iTimePassed)
    for i = 1, tTimers.Size() do
        local tTimer = tTimers.Pop()

        tTimer.iTime = tTimer.iTime - iTimePassed

        if tTimer.iTime <= 0 then
            local iNewTime = tTimer.fCallback()
            if iNewTime then
                tTimer.iTime = tTimer.iTime + iNewTime
            else
                tTimer = nil
            end
        end

        if tTimer then
            tTimers.Push(tTimer)
        end
    end
end
--//

--RECT
function AL.RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end
--//
------------------------------------

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
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if iGameState == GAMESTATE_GAME and CGameMode.bRoundOn and click.Click and not tFloor[click.X][click.Y].bDefect and tFloor[click.X][click.Y].iPlayerID > 0 then
        CGameMode.PlayerClickPixel(tFloor[click.X][click.Y].iPlayerID, tFloor[click.X][click.Y].iColor)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click then bAnyButtonClick = true end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end