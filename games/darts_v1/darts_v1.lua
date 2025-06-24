--[[
    Название: Дартс
    Автор: Avondale, дискорд - avonda
    Описание механики:
        Игроки пытаются попасть в мишень, нажимая на свою зону.
        чем ближе к центру мишени тем больше очков
    Идеи по доработке: 
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
    TargetScore = 1,
    StageNum = 1,
    TotalStages = 3,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
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

local tPlayerInGame = {}
local bAnyButtonClick = false

local tPlayerIDtoColor = {}
tPlayerIDtoColor[1] = CColors.RED
tPlayerIDtoColor[2] = CColors.GREEN
tPlayerIDtoColor[3] = CColors.BLUE
tPlayerIDtoColor[4] = CColors.YELLOW
tPlayerIDtoColor[5] = CColors.MAGENTA
tPlayerIDtoColor[6] = CColors.CYAN

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

    tGame.CenterX = math.floor(tGame.Cols/2)
    tGame.CenterY = math.ceil(tGame.Rows/2)

    local iMinX = 1
    local iMinY = 1
    local iMaxX = tGame.Cols
    local iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        iMinX = AL.NFZ.iMinX
        iMinY = AL.NFZ.iMinY
        iMaxX = AL.NFZ.iMaxX
        iMaxY = AL.NFZ.iMaxY

        tGame.CenterX = AL.NFZ.iCenterX+iMinX
        tGame.CenterY = AL.NFZ.iCenterY+iMinY
    end

    CGameMode.iCrosshairMinX = tGame.CenterX-6
    CGameMode.iCrosshairMaxX = tGame.CenterX+6
    CGameMode.iCrosshairMinY = tGame.CenterY-6
    CGameMode.iCrosshairMaxY = tGame.CenterY+6

    tGameResults.PlayersCount = tConfig.PlayerCount

    if tGame.StartPositions == nil then
        tGame.StartPositions = {}
        tGame.StartPositionSize = 2

        local iStartX = iMinX + tGame.StartPositionSize
        local iStartY = iMinY + tGame.StartPositionSize

        local iX = iStartX
        local iY = iStartY
        for iPlayerID = 1, tConfig.PlayerCount do
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = iX
            tGame.StartPositions[iPlayerID].Y = iY
            tGame.StartPositions[iPlayerID].Color = tPlayerIDtoColor[iPlayerID]

            iY = iY + tGame.StartPositionSize + 3

            if iY >= iMaxY then
                iY = iStartY
                if iX == iStartX then
                    iX = iMaxX - (tGame.StartPositionSize*2)
                else
                    break;
                end
            end
        end
    else 
        for iPlayerID = 1, #tGame.StartPositions do
            tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
        end  
    end  

    tGameStats.TotalStages = tConfig.RoundCount

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
    if not CGameMode.bCountDownStarted then
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
    end
    
    CPaint.BG()

    local iPlayersReady = 0
    for iPlayerID = 1, #tGame.StartPositions do
        local iBright = tConfig.Bright

        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionSize, tGame.StartPositionSize) or (CGameMode.bCountDownStarted and tPlayerInGame[iPlayerID]) then
            tPlayerInGame[iPlayerID] = true
            iPlayersReady = iPlayersReady + 1
            tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
        else
            tPlayerInGame[iPlayerID] = false
            iBright = iBright-2
            tGameStats.Players[iPlayerID].Color = CColors.NONE
        end

        CPaint.PlayerZone(iPlayerID, iBright)
    end

    if not CGameMode.bCountDownStarted and ((iPlayersReady > 1 and CGameMode.bCanStart) or bAnyButtonClick) then
        CGameMode.StartCountDown(10)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CPaint.BG()

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright-1)
        end
    end

    CPaint.Crosshair()
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
CGameMode.iPlayerIDToMove = 0
CGameMode.bCountDownStarted = false
CGameMode.iCrosshairX = 0
CGameMode.iCrosshairY = 0
CGameMode.iCrosshairVel = 1
CGameMode.bPlayerCanMove = false
CGameMode.bPlayerMoved = false
CGameMode.iWinnerID = 0
CGameMode.bCanStart = false

CGameMode.iCrosshairMinX = 0
CGameMode.iCrosshairMaxX = 0
CGameMode.iCrosshairMinY = 0
CGameMode.iCrosshairMaxY = 0

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("darts/darts_rules.mp3")
    CAudio.PlayVoicesSync("choose-color.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("darts/darts_rules.mp3"))*1000, function()
        CGameMode.bCanStart = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

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
    iGameState = GAMESTATE_GAME 

    CGameMode.NextPlayerMove()
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -999

    for i = 1, #tGame.StartPositions do
        if tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
            tGameResults.Score = tGameStats.Players[i].Score
        end
    end

    iGameState = GAMESTATE_POSTGAME  

    CAudio.PlaySyncFromScratch("")
    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)  

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright) 
end

CGameMode.NextPlayerMove = function()
    CGameMode.iCrosshairX = tGame.CenterX
    CGameMode.iCrosshairY = CGameMode.iCrosshairMinY
    CGameMode.iCrosshairVel = 1
    CGameMode.bPlayerCanMove = false

    CGameMode.FindNextPlayerToMove()
end

CGameMode.FindNextPlayerToMove = function()
    repeat CGameMode.iPlayerIDToMove = CGameMode.iPlayerIDToMove + 1; if CGameMode.iPlayerIDToMove > #tGame.StartPositions then CGameMode.iPlayerIDToMove = 1; tGameStats.StageNum = tGameStats.StageNum+1 end
    until tPlayerInGame[CGameMode.iPlayerIDToMove]

    if tGameStats.StageNum <= tGameStats.TotalStages then
        CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iPlayerIDToMove].Color)
        tGameStats.TargetColor = tGame.StartPositions[CGameMode.iPlayerIDToMove].Color
        CGameMode.WaitForPlayerMove(true)
    else
        tGameStats.StageNum = tGameStats.StageNum-1
        CGameMode.EndGame()
    end
end

CGameMode.WaitForPlayerMove = function(bYAxis)
    AL.NewTimer(1500, function()
        CGameMode.bPlayerCanMove = true
        if CGameMode.bPlayerMoved then
            CGameMode.PlayerHit(bYAxis)
            CGameMode.bPlayerCanMove = false
            CGameMode.bPlayerMoved = false
            return nil;
        else
            if bYAxis then
                CGameMode.iCrosshairY = CGameMode.iCrosshairY + CGameMode.iCrosshairVel
                if CGameMode.iCrosshairY == CGameMode.iCrosshairMinY or CGameMode.iCrosshairY == CGameMode.iCrosshairMaxY then 
                    CGameMode.iCrosshairVel = -CGameMode.iCrosshairVel
                end
            else
                CGameMode.iCrosshairX = CGameMode.iCrosshairX + CGameMode.iCrosshairVel
                if CGameMode.iCrosshairX == CGameMode.iCrosshairMinX or CGameMode.iCrosshairX == CGameMode.iCrosshairMaxX then 
                    CGameMode.iCrosshairVel = -CGameMode.iCrosshairVel
                end
            end

            return 100;
        end
    end)
end

CGameMode.PlayerHit = function(bYAxis)
    CAudio.PlaySystemAsync(CAudio.CLICK)

    if bYAxis then
        AL.NewTimer(1000, function()
            CGameMode.iCrosshairX = CGameMode.iCrosshairMinX
            CGameMode.iCrosshairVel = 1
            CGameMode.WaitForPlayerMove(false)
        end)
    else
        CGameMode.RewardPlayerForHit()

        AL.NewTimer(3000, function()
            CGameMode.NextPlayerMove()
        end)
    end
end

CGameMode.RewardPlayerForHit = function()
    local iXDiff = math.abs(tGame.CenterX - CGameMode.iCrosshairX)
    local iYDiff = math.abs(tGame.CenterY - CGameMode.iCrosshairY)
    local iScore = (tGame.Cols-iXDiff*3) + (tGame.Rows-iYDiff*3)
    if iScore < 0 then iScore = 0 end
    if iXDiff < 3 and iYDiff < 3 then iScore = iScore*2 end
    if iXDiff == 0 and iYDiff == 0 then iScore = iScore*2 end

    CLog.print(iXDiff.." "..iYDiff.." "..iScore)

    tGameStats.Players[CGameMode.iPlayerIDToMove].Score = tGameStats.Players[CGameMode.iPlayerIDToMove].Score + iScore
    if tGameStats.Players[CGameMode.iPlayerIDToMove].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[CGameMode.iPlayerIDToMove].Score
    end
end
--//

--PAINT
CPaint = {}
CPaint.BG = function()
    CPaint.PaintCircle(tGame.CenterX, tGame.CenterY, 4, CColors.BLUE, tConfig.Bright-2)
    CPaint.PaintCircle(tGame.CenterX, tGame.CenterY, 3, CColors.CYAN, tConfig.Bright-2)    
    CPaint.PaintCircle(tGame.CenterX, tGame.CenterY, 2, CColors.CYAN, tConfig.Bright-1)
    CPaint.PaintCircle(tGame.CenterX, tGame.CenterY, 1, CColors.RED, tConfig.Bright)

    tFloor[tGame.CenterX][tGame.CenterY].iColor = CColors.YELLOW
    tFloor[tGame.CenterX][tGame.CenterY].iBright = tConfig.Bright+1
end

CPaint.PaintCircle = function(iX, iY, iSize, iColor, iBright)
    local iSize2 = 3-2*iSize

    for i = 0, iSize do
        CPaint.PaintCirclePixel(iX + i, iY + iSize, iColor, iBright)
        CPaint.PaintCirclePixel(iX + i, iY - iSize, iColor, iBright)
        CPaint.PaintCirclePixel(iX - i, iY + iSize, iColor, iBright)
        CPaint.PaintCirclePixel(iX - i, iY - iSize, iColor, iBright)

        CPaint.PaintCirclePixel(iX + iSize, iY + i, iColor, iBright)
        CPaint.PaintCirclePixel(iX + iSize, iY - i, iColor, iBright)
        CPaint.PaintCirclePixel(iX - iSize, iY + i, iColor, iBright)
        CPaint.PaintCirclePixel(iX - iSize, iY - i, iColor, iBright)      

        if iSize2 < 0 then
            iSize2 = iSize2 + 4*i + 6
        else
            iSize2 = iSize2 + 4*(i-iSize) + 10
            iSize = iSize - 1
        end         
    end 
end

CPaint.PaintCirclePixel = function(iX, iY, iColor, iBright)
    for iX2 = iX-1, iX+1 do
        if tFloor[iX2] and tFloor[iX2][iY] then
            tFloor[iX2][iY].iColor = iColor
            tFloor[iX2][iY].iBright = iBright

            if iX2 == iX then
                tFloor[iX2][iY].iBright = iBright
            end
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X+tGame.StartPositionSize-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSize-1 do
            tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
            tFloor[iX][iY].iBright = iBright

            if CGameMode.iPlayerIDToMove == iPlayerID then
                tFloor[iX][iY].iBright = iBright+1
            end
        end
    end

    if CGameMode.iPlayerIDToMove == iPlayerID and CGameMode.bPlayerCanMove then
        local iStartX = tGame.StartPositions[iPlayerID].X + tGame.StartPositionSize
        if tGame.StartPositions[iPlayerID].X > tGame.Cols/2 then 
            iStartX = tGame.StartPositions[iPlayerID].X - tGame.StartPositionSize
        end

        for iX = iStartX, iStartX+tGame.StartPositionSize-1 do
            for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSize-1 do
                if not tFloor[iX][iY].bDefect then
                    tFloor[iX][iY].iColor = CColors.WHITE
                    tFloor[iX][iY].iBright = iBright+2

                    if tFloor[iX][iY].bClick and CGameMode.bPlayerCanMove then
                        CGameMode.bPlayerMoved = true
                    end
                end
            end
        end
    end
end

CPaint.Crosshair = function()
    if tFloor[CGameMode.iCrosshairX] and tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY] then
        tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY].iColor = tGame.StartPositions[CGameMode.iPlayerIDToMove].Color
        tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY].iBright = tConfig.Bright+2
    end
end

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSizeX, iSizeY)
    for iX = tStart.X, tStart.X + iSizeX - 1 do
        for iY = tStart.Y, tStart.Y + iSizeY - 1 do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
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
        if iGameState == GAMESTATE_SETUP and not click.Click then
            AL.NewTimer(500, function()
                tFloor[click.X][click.Y].bClick = false
            end)

            return;
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
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