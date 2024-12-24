--[[
    Название: Название механики
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
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
    TargetScore = 0,
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
    iCoinPlayerID = 0
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

    tGameResults.PlayersCount = tConfig.PlayerCount

    tGameStats.TargetScore = tGame.StartPositionSizeX * tGame.StartPositionSizeY
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
    SetFloorColorBright(CColors.RED, 2) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright, false)

            if tPlayerInGame[iPos] and tGame.ArenaMode then
                local iCenterX = tPos.X + math.floor(tGame.StartPositionSizeX/3)
                local iCenterY = tPos.Y + math.floor(tGame.StartPositionSizeY/3)

                local bArenaClick = false
                for iX = iCenterX, iCenterX+1 do
                    for iY = iCenterY, iCenterY+1 do
                        tFloor[iX][iY].iColor = 5

                        if tFloor[iX][iY].bClick then 
                            bArenaClick = true
                        end
                    end
                end

                if CGameMode.bArenaCanStart and bArenaClick then
                    bAnyButtonClick = true 
                end
            end 
        end
    end

    if (iPlayersReady > 0 and bAnyButtonClick) then
        bAnyButtonClick = false
        iGameState = GAMESTATE_GAME
        CGameMode.PrepareGame()
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetFloorColorBright(CColors.RED, 2) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.NONE, 0, false) 
    CPaint.PlayerGameZones()
    CPaint.Animations()
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
CGameMode.iWinnerID = 0
CGameMode.tPlayerFieldInfo = {}

CGameMode.PrepareGame = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.tPlayerFieldInfo[iPlayerID] = {}
            CGameMode.tPlayerFieldInfo[iPlayerID].iFillY = 0
            CGameMode.tPlayerFieldInfo[iPlayerID].iFillX = 0
        end
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
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
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    CGameMode.GameLoop()
end

CGameMode.GameLoop = function()
    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        CGameMode.SpawnCoins()

        return tConfig.CoinSpawnTime * 1000
    end)
end

CGameMode.PlayerAddScore = function(iPlayerID, iBonus)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iBonus
    tGameResults.Score = tGameResults.Score + iBonus

    if tGameStats.Players[iPlayerID].Score >= tGameStats.TargetScore then
        CGameMode.EndGame(iPlayerID)
    else
        CGameMode.tPlayerFieldInfo[iPlayerID].iFillY = CGameMode.tPlayerFieldInfo[iPlayerID].iFillY + iBonus
        if CGameMode.tPlayerFieldInfo[iPlayerID].iFillY >= tGame.StartPositionSizeY then
            CGameMode.tPlayerFieldInfo[iPlayerID].iFillY = CGameMode.tPlayerFieldInfo[iPlayerID].iFillY - tGame.StartPositionSizeY
            CGameMode.tPlayerFieldInfo[iPlayerID].iFillX = CGameMode.tPlayerFieldInfo[iPlayerID].iFillX + 1
        end
    end
end

CGameMode.SpawnCoins = function()
    local iCoinCount = math.random(1,3)

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            for iCoin = 1, iCoinCount do
                CGameMode.SpawnCoinForPlayer(iPlayerID)
            end
        end
    end
end

CGameMode.SpawnCoinForPlayer = function(iPlayerID)
    local iX = 0
    local iY = 0
    local iAttemptCount = 0

    repeat
        iX = math.random(tGame.StartPositions[iPlayerID].X + CGameMode.tPlayerFieldInfo[iPlayerID].iFillX, tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX-1)
        iY = math.random(tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY-1)

        iAttemptCount = iAttemptCount + 1
        if iAttemptCount > 25 then return false end
    until tFloor[iX][iY].iCoinPlayerID == 0 and not tFloor[iX][iY].bDefect 
    and (iX ~= tGame.StartPositions[iPlayerID].X + CGameMode.tPlayerFieldInfo[iPlayerID].iFillX or iY >= tGame.StartPositions[iPlayerID].Y + CGameMode.tPlayerFieldInfo[iPlayerID].iFillY)

    tFloor[iX][iY].iCoinPlayerID = iPlayerID
end

CGameMode.PlayerCollectCoin = function(iPlayerID, iX, iY)
    tFloor[iX][iY].iCoinPlayerID = 0

    if not CGameMode.IsPlayerPaintedZone(iPlayerID, iX, iY) then
        CAudio.PlayAsync(CAudio.CLICK)
        CGameMode.PlayerAddScore(iPlayerID, tConfig.PixelPoints)
        CPaint.AnimatePixelDrop(iX, iY, -1, tGameStats.Players[iPlayerID].Color)
    end
end

CGameMode.IsPlayerPaintedZone = function(iPlayerID, iX, iY)
    return iX < tGame.StartPositions[iPlayerID].X + CGameMode.tPlayerFieldInfo[iPlayerID].iFillX 
    or (iX == tGame.StartPositions[iPlayerID].X + CGameMode.tPlayerFieldInfo[iPlayerID].iFillX and iY < tGame.StartPositions[iPlayerID].Y + CGameMode.tPlayerFieldInfo[iPlayerID].iFillY)
end

CGameMode.EndGame = function(iWinnerID)
    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    SetGlobalColorBright(tGameStats.Players[iWinnerID].Color, tConfig.Bright)
    tGameResults.Color = tGame.StartPositions[iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)    
end
--//

--PAINT
CPaint = {}

CPaint.PlayerZone = function(iPlayerID, iBright, bPaintStart)
    SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
        tGame.StartPositions[iPlayerID].Y, 
        tGame.StartPositionSizeX-1, 
        tGame.StartPositionSizeY-1, 
        tGame.StartPositions[iPlayerID].Color, 
        iBright)
end

CPaint.PlayerGameZones = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CPaint.PlayerGameZone(iPlayerID)
        end
    end
end

CPaint.PlayerGameZone = function(iPlayerID)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX-1 do        
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY-1 do
            tFloor[iX][iY].iBright = tConfig.Bright
            local iColor = CColors.NONE

            if tFloor[iX][iY].iCoinPlayerID > 0 then
                iColor = CColors.BLUE
            end

            if CGameMode.IsPlayerPaintedZone(iPlayerID, iX, iY) then
                iColor = tGame.StartPositions[iPlayerID].Color
            end

            tFloor[iX][iY].iColor = iColor
        end
    end        
end

CPaint.tAnimatedPixels = {}
CPaint.Animations = function()
    for iPixelID = 1, #CPaint.tAnimatedPixels do
        if CPaint.tAnimatedPixels[iPixelID] and tFloor[CPaint.tAnimatedPixels[iPixelID].iX][CPaint.tAnimatedPixels[iPixelID].iY].iColor == CColors.NONE then
            tFloor[CPaint.tAnimatedPixels[iPixelID].iX][CPaint.tAnimatedPixels[iPixelID].iY].iColor = CPaint.tAnimatedPixels[iPixelID].iColor
        end
    end
end

CPaint.AnimatePixelDrop = function(iX, iY, iVelX, iColor)
    local iPixelID = #CPaint.tAnimatedPixels+1
    CPaint.tAnimatedPixels[iPixelID] = {}
    CPaint.tAnimatedPixels[iPixelID].iX = iX
    CPaint.tAnimatedPixels[iPixelID].iY = iY
    CPaint.tAnimatedPixels[iPixelID].iVelX = iVelX
    CPaint.tAnimatedPixels[iPixelID].iColor = iColor

    AL.NewTimer(50, function()
        CPaint.tAnimatedPixels[iPixelID].iX = CPaint.tAnimatedPixels[iPixelID].iX + CPaint.tAnimatedPixels[iPixelID].iVelX
        if CPaint.tAnimatedPixels[iPixelID].iX < 1 or CPaint.tAnimatedPixels[iPixelID].iVelX > tGame.Cols or tFloor[CPaint.tAnimatedPixels[iPixelID].iX][CPaint.tAnimatedPixels[iPixelID].iY].iColor == CColors.RED then
            CPaint.tAnimatedPixels[iPixelID] = nil
            return nil
        end

        return 50
    end)
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

function SetFloorColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
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

        if click.Click and not tFloor[click.X][click.Y].bDefect then
            if tFloor[click.X][click.Y].iCoinPlayerID > 0 then
                CGameMode.PlayerCollectCoin(tFloor[click.X][click.Y].iCoinPlayerID, click.X, click.Y)
            end
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and tFloor[defect.X][defect.Y].iCoinPlayerID > 0 then
            tFloor[defect.X][defect.Y].iCoinPlayerID = 0
        end
    end
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