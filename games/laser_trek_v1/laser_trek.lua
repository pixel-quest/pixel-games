--[[
    Название: Лазерный путь
    Автор: Avondale, дискорд - avonda
    Описание механики: открываешь невидимый путь пробираясь через лазеры(для игры обязательный лазеры)
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
    ScoreboardVariant = 0,
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
    iPoint = 0,
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

    iPrevTickTime = CTime.unix()

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end

    AL.InitLasers(tGame)

    tGame.iMinX = 1
    tGame.iMinY = 1
    tGame.iMaxX = tGame.Cols
    tGame.iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        tGame.iMinX = AL.NFZ.iMinX
        tGame.iMinY = AL.NFZ.iMinY
        tGame.iMaxX = AL.NFZ.iMaxX
        tGame.iMaxY = AL.NFZ.iMaxY
    end
    tGame.CenterX = math.floor((tGame.iMaxX-tGame.iMinX+1)/2)
    tGame.CenterY = math.ceil((tGame.iMaxY-tGame.iMinY+1)/2)

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
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CPath.PaintPath()

    if not CGameMode.bCountDownStarted and CGameMode.bCanAutoStart and CGameMode.bStartClicked then
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CPath.PaintPath()
end

function PostGameTick()
    
end

function RangeFloor(setPixel, setButton, setLasers)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end

    --AL.SetLasers(setLasers)
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.bCountDownStarted = false
CGameMode.bCanAutoStart = false
CGameMode.bStartClicked = false

CGameMode.tPlayerColors = {}

CGameMode.InitGameMode = function()
    while #CPath.tPath+20 < tConfig.PathSize do
        CPath.CreatePath(math.random(tGame.iMinX+1, tGame.iMaxX-1),math.random(tGame.iMinY+1, tGame.iMaxY-1))
    end
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        --voice gamename rules
        AL.NewTimer(1000, function()
            CGameMode.bCanAutoStart = true
        end)    
    else
        CGameMode.bCanAutoStart = true
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            if CGameMode.iCountdown <= 5 then
                CAudio.ResetSync()
                CAudio.PlayLeftAudio(CGameMode.iCountdown)
            end

            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    iGameState = GAMESTATE_GAME
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground() 

    AL.NewTimer(250, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        if CPath.iCurrentPoint < CPath.iTargetPoint then
            CPath.iCurrentPoint = CPath.iCurrentPoint + 1
        end

        if CPath.iPaintedPoint < CPath.iTargetPoint + CPath.PAINT_DIFF then
            CPath.iPaintedPoint = CPath.iPaintedPoint + 1
        end

        return 250
    end)
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    if bVictory then
        tGameResults.Won = true
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
        tGameResults.Color = CColors.GREEN
    else
        tGameResults.Won = false
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)        
end

CGameMode.PlayerMisStep = function(iX, iY)
    if not tFloor[iX][iY].bCooldown then
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
        CGameMode.AnimatePixelFlicker(iX, iY, 5, CColors.NONE)

        tFloor[iX][iY].bCooldown = true
        AL.NewTimer(1000, function()
            tFloor[iX][iY].bCooldown = false
        end)
    end
end

CGameMode.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(30, function()
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
            return 200
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end

CGameMode.SwitchAllLasers = function(bOn)
    if AL.bRoomHasLasers then
        for iLine = 1, AL.Lasers.iLines do
            for iRow = 1, AL.Lasers.iRows do
                AL.SwitchLaser(iLine, iRow, bOn)
            end
        end
    end
end

CGameMode.SwitchLineLasers = function(iLine, iType)
    if iType == 2 then
        AL.SwitchLaser(iLine, math.random(1, math.floor(AL.Lasers.iRows/2)), true)
        AL.SwitchLaser(iLine, math.random(math.ceil(AL.Lasers.iRows/2), AL.Lasers.iRows), true)
    elseif iType == 3 then
        for iRow = 1, AL.Lasers.iRows do
            AL.SwitchLaser(iLine, iRow, true)
        end
        AL.SwitchLaser(iLine, math.random(1, AL.Lasers.iRows), false)
    else
        AL.SwitchLaser(iLine, math.random(1, AL.Lasers.iRows), true)
    end

    CLog.print(iLine.." lasers on")
end

CGameMode.SwitchAllLineLasers = function(iLine)
    for iRow = 1, AL.Lasers.iRows do
        AL.SwitchLaser(iLine, iRow, true)
    end    

    CLog.print(iLine.." lasers full on")
end
--//

--PATH
CPath = {}
CPath.tPath = {}

CPath.PATH_WIDTH = 2
CPath.PAINT_DIFF = 6

CPath.iCurrentPoint = 2
CPath.iTargetPoint = 5 
CPath.iPaintedPoint = 2
CPath.iLastLaserSwitchPoint = 0

CPath.CreatePath = function(iStartX, iStartY)
    local iX = iStartX
    local iY = iStartY
    local iPlusX = 0
    local iPlusY = 0
    local iNextSwitch = 0

    for iPoint = 1, tConfig.PathSize do
        CPath.tPath[iPoint] = {}
        CPath.tPath[iPoint].iX = iX
        CPath.tPath[iPoint].iY = iY

        iNextSwitch = iNextSwitch - 1
        if iNextSwitch <= 0 or not CPath.CheckValidPoint(iPoint, iX+iPlusX, iY+iPlusY, 0) then
            local iAttemptsCount = 0
            repeat
                iAttemptsCount = iAttemptsCount + 1
                iPlusX = math.random(-1,1)
                iPlusY = math.random(-1,1)
            until CPath.CheckValidPoint(iPoint, iX+iPlusX, iY+iPlusY, iAttemptsCount)
            if iAttemptsCount >= 10 then
                CLog.print("path stuck")
                break;
            end
            iNextSwitch = math.random(1,3)
        end

        iX = iX + iPlusX
        iY = iY + iPlusY
    end
end

CPath.CheckValidPoint = function(iPoint, iX, iY, iAttemptsCount)
    if iAttemptsCount >= 10 then return true; end

    if iX == CPath.tPath[iPoint] and iY == CPath.tPath[iPoint] then return false; end
    if iX > tGame.iMaxX or iX < tGame.iMinX then return false; end
    if iY > tGame.iMaxY or iY < tGame.iMinY then return false; end

    for iPrevPoint = iPoint-10, iPoint-1 do
        if CPath.tPath[iPrevPoint] ~= nil then
            for iCheckX = CPath.tPath[iPrevPoint].iX, CPath.tPath[iPrevPoint].iX+CPath.PATH_WIDTH-1 do
                for iCheckY = CPath.tPath[iPrevPoint].iY, CPath.tPath[iPrevPoint].iY+CPath.PATH_WIDTH-1 do
                    if iCheckX == iX and iCheckY == iY then return false; end
                end
            end
        end
    end

    return true;
end

CPath.PaintPath = function()
    local iLimit = CPath.iPaintedPoint
    if iLimit > #CPath.tPath then iLimit = #CPath.tPath end

    for iPoint = CPath.iCurrentPoint-CPath.PAINT_DIFF, iLimit do
        if CPath.tPath[iPoint] then
            local iColor = CColors.WHITE
            local iBright = tConfig.Bright

            if iPoint <= 2 or iPoint >= #CPath.tPath-3 then 
                iColor = CColors.GREEN 
            elseif iPoint == iLimit then
                iColor = CColors.BLUE
            end

            if iPoint > 2 and iGameState < GAMESTATE_GAME then
                break;
            end

            if iPoint < CPath.iCurrentPoint then
                iBright = iBright - (CPath.iCurrentPoint - iPoint) + 1
                if iBright < 0 then iBright = 1; end
            end

            for iX = CPath.tPath[iPoint].iX, CPath.tPath[iPoint].iX+CPath.PATH_WIDTH-1 do
                for iY = CPath.tPath[iPoint].iY, CPath.tPath[iPoint].iY+CPath.PATH_WIDTH-1 do
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = iColor
                        tFloor[iX][iY].iBright = iBright
                        tFloor[iX][iY].iPoint = iPoint
                    end
                end
            end
        end
    end
end

CPath.PlayerClickAtPoint = function(iPoint)
    if iPoint > CPath.iTargetPoint then
        CPath.iTargetPoint = iPoint
        local iLaserPoint = CPath.iTargetPoint+math.floor(CPath.PAINT_DIFF/2)

        if (iPoint - CPath.iLastLaserSwitchPoint) > CPath.PAINT_DIFF+1 and CPath.tPath[iLaserPoint] ~= nil then
            CPath.iLastLaserSwitchPoint = iPoint
            CGameMode.SwitchAllLasers(false)
            CGameMode.SwitchLineLasers(CPath.tPath[iLaserPoint].iX)

            local iBackPoint = CPath.iTargetPoint-1-CPath.PAINT_DIFF
            if CPath.tPath[iBackPoint] ~= nil and math.abs(CPath.tPath[iLaserPoint].iX - CPath.tPath[iBackPoint].iX) > CPath.PAINT_DIFF then
                CGameMode.SwitchAllLineLasers(CPath.tPath[iBackPoint].iX)
            end
        end
    end

    if iPoint >= #CPath.tPath-1 then
        CGameMode.EndGame(true)
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
    for i = iX, iX + iSizeX-1 do
        for j = iY, iY + iSizeY-1 do
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright 
                tFloor[iX][iY].iPoint = 0
            end
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

function ReverseTable(t)
    for i = 1, #t/2, 1 do
        t[i], t[#t-i+1] = t[#t-i+1], t[i]
    end
    return t
end

function ShuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end

    return t
end

function TableConcat(...)
    local tR = {}
    local i = 1
    local function addtable(t)
        for j = 1, #t do
            tR[i] = t[j]
            i = i + 1
        end
    end

    for _,t in pairs({...}) do
        addtable(t)
    end

    return tR
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
        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
            return;
        end

        if iGameState == GAMESTATE_SETUP then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
                tFloor[click.X][click.Y].bHold = false

                if tFloor[click.X][click.Y].iPoint then
                    CGameMode.bStartClicked = true
                end

            elseif not tFloor[click.X][click.Y].bHold then
                tFloor[click.X][click.Y].bHold = true
                AL.NewTimer(1000, function()
                    if tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bClick = false
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if iGameState == GAMESTATE_GAME and click.Click and not tFloor[click.X][click.Y].bDefect then
            if tFloor[click.X][click.Y].iPoint > 0 then
                CPath.PlayerClickAtPoint(tFloor[click.X][click.Y].iPoint)
            else
                CGameMode.PlayerMisStep(click.X, click.Y)
            end
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end