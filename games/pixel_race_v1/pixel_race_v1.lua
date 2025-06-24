--[[
    Название: Пиксель гонка
    Автор: Avondale, дискорд - avonda
    
    Описание механики: 
        Игроки бегают по кругу собирая пиксели
        когда время заканчивается побеждает тот кто собрал больше всех
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
    StageNum = 0,
    TotalStages = 0,
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

local tTeamColors = {}
tTeamColors[6] = CColors.RED
tTeamColors[5] = CColors.BLUE
tTeamColors[4] = CColors.MAGENTA
tTeamColors[3] = CColors.CYAN
tTeamColors[2] = CColors.GREEN
tTeamColors[1] = CColors.WHITE

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

    CGameMode.iMinX = 1
    CGameMode.iMinY = 1
    CGameMode.iMaxX = tGame.Cols
    CGameMode.iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        CGameMode.iMinX = AL.NFZ.iMinX
        CGameMode.iMinY = AL.NFZ.iMinY
        CGameMode.iMaxX = AL.NFZ.iMaxX
        CGameMode.iMaxY = AL.NFZ.iMaxY
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
    SetGlobalColorBright(CColors.YELLOW, tConfig.Bright-3)
    SetAllButtonColorBright(CColors.NONE, tConfig.Bright, false)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
    CPaint.Track()
    CPaint.StartPositions()

    local iPlayersReady = 0

    for iPlayerID = 1, #CGameMode.tPlayerStartPositionTrackSegment do
        if CGameMode.tPlayerStartPositionClick[iPlayerID] then
            tPlayerInGame[iPlayerID] = true

            tGameStats.Players[iPlayerID].Color = tTeamColors[iPlayerID]
        elseif tPlayerInGame[iPlayerID] and not CGameMode.bCountDownStarted then
            AL.NewTimer(250, function()
                if not CGameMode.tPlayerStartPositionClick[iPlayerID] and not CGameMode.bCountDownStarted then
                    tPlayerInGame[iPlayerID] = false
                    tGameStats.Players[iPlayerID].Color = CColors.NONE
                end
            end)
        end

        if tPlayerInGame[iPlayerID] then iPlayersReady = iPlayersReady + 1; end
    end

    if bAnyButtonClick or (iPlayersReady > 1 and CGameMode.bCanAutoStart) then
        bAnyButtonClick = false
        if iPlayersReady < 2 or CGameMode.bCountDownStarted then return; end

        CGameMode.StartCountDown(10)
    end

    tGameResults.PlayersCount = iPlayersReady
end

function GameTick()
    SetGlobalColorBright(CColors.YELLOW, tConfig.Bright-2)
    SetAllButtonColorBright(CColors.NONE, tConfig.Bright, false)
    CPaint.Track()
    CPaint.Pixels()
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
CGameMode.bCountDownStarted = false

CGameMode.tPlayerStartPositionTrackSegment = {}
CGameMode.tPlayerStartPositionClick = {}
CGameMode.tPlayerTargetPixel = {}
CGameMode.iWinnerID = 0

CGameMode.InitGameMode = function()
    CTrack.GenerateTrack()
    local iSegmentId = 2
    for iPlayerId = 1, 6 do
        CGameMode.tPlayerStartPositionTrackSegment[iPlayerId] = iSegmentId

        CGameMode.tPlayerTargetPixel[iPlayerId] = {}
        CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId = iSegmentId
        CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId = 1

        CGameMode.NewTargetPixelForPlayer(iPlayerId)

        iSegmentId = iSegmentId + 2
    end
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("choose-color.mp3")

    AL.NewTimer(1000, function()
        CGameMode.bCanAutoStart = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

    AL.NewTimer(1000, function()
        CAudio.PlaySystemSyncFromScratch("")
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
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    iGameState = GAMESTATE_GAME

    tGameStats.StageLeftDuration = tConfig.TimeLimit

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        if tGameStats.StageLeftDuration <= 0 then
            CGameMode.EndGame()
            return nil
        elseif tGameStats.StageLeftDuration <= 25 then
            CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
        end

        return 1000
    end)
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -1

    for iPlayerId = 1, #CGameMode.tPlayerStartPositionTrackSegment do
        if tPlayerInGame[iPlayerId] and tGameStats.Players[iPlayerId].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerId].Score
            CGameMode.iWinnerID = iPlayerId
        end
    end

    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color
    tGameResults.Won = true

    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.NewTargetPixelForPlayer = function(iPlayerId)
    CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId = CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId + math.random(4,8)
    if CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId > #CTrack.tSegments then CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId = 1 + math.random(3,6); end

    local tSegment = CTrack.tSegments[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId]

    for i = 1, 10 do
        CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId = math.random(1, CTrack.iSegmentLength)
        if tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iTeamId == 0 
        and not tFloor[tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iX][tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iY].bDefect 
        and tFloor[tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iX][tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iY].iColor == CColors.NONE
        then
            tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iTeamId = iPlayerId

            --CLog.print(iPlayerId.." "..tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iX.." "..tSegment.tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId].iY)
            break;
        end

        if i == 10 then
            CGameMode.NewTargetPixelForPlayer(iPlayerId)
        end
    end
end

CGameMode.PlayerCollectTargetPixel = function(iPlayerId)
    tGameStats.Players[iPlayerId].Score = tGameStats.Players[iPlayerId].Score + 1
    tGameResults.Score = tGameResults.Score + 1

    if tGameStats.TargetScore < tGameStats.Players[iPlayerId].Score then
        tGameStats.TargetScore = tGameStats.Players[iPlayerId].Score
    end

    CAudio.PlaySystemAsync(CAudio.CLICK)

    CGameMode.NewTargetPixelForPlayer(iPlayerId)
end
--//

--TRACK
CTrack = {}
CTrack.tSegments = {}
CTrack.iSegmentLength = 4

CTrack.GenerateTrack = function()
    CTrack.iSegmentLength = math.floor((CGameMode.iMaxY-CGameMode.iMinY+1)/5)
    if CTrack.iSegmentLength < 4 then CTrack.iSegmentLength = 4; end

    local iQuarter = 1

    local function createSegment(iSegmentId, iX, iY)
        CTrack.tSegments[iSegmentId] = {}
        CTrack.tSegments[iSegmentId].tPixels = {}
        for iSegmentPixelId = 1, CTrack.iSegmentLength do
            CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId] = {}
            CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iX = iX
            CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iY = iY
            CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iTeamId = 0

            if iQuarter % 2 ~= 0 then
                CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iY = iY + iSegmentPixelId-1
            else
                CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iX = iX + iSegmentPixelId-1
            end
        end        
    end

    local iX = CGameMode.iMinX + math.random(1,3)
    local iY = CGameMode.iMinY + math.random(1,2)

    local iStartY = tonumber(iY)
    local iQ3MinY = 1

    for iSegmentId = 1, (tGame.Cols+tGame.Rows)*2 do
        createSegment(iSegmentId, iX, iY)

        if iQuarter % 2 ~= 0 then
            if iQuarter == 1 then
                iX = iX + 1
                if iX >= CGameMode.iMaxX-math.random(1,3) then
                    iQuarter = iQuarter + 1
                    iX = iX - CTrack.iSegmentLength
                    iQ3MinY = iY + CTrack.iSegmentLength + 2
                    iY = iY + math.floor(CTrack.iSegmentLength/2)
                end
            else
                iX = iX - 1
                if iX <= CGameMode.iMinX+math.random(1,3) then
                    iQuarter = iQuarter + 1
                    --iX = iX + CTrack.iSegmentLength
                end
            end
            if ((iY > CGameMode.iMinY+1 and iY < CGameMode.iMaxY-CTrack.iSegmentLength-1) and math.random(1,3) == 2 and iY > iQ3MinY) then
                iY = iY + math.random(-1,1)
            end
            if iY <= iQ3MinY and iY < CGameMode.iMaxY-CTrack.iSegmentLength then iY = iY + 1; end
        else
            if iQuarter == 2 then
                iY = iY + 1
                if iY >= CGameMode.iMaxY-math.random(1,2) then
                    iQuarter = iQuarter + 1
                    iY = iY - CTrack.iSegmentLength
                end
            else
                iY = iY - 1
                if iY <= iStartY+CTrack.iSegmentLength-2 then
                    break;
                end
            end 
            if (iX > CGameMode.iMinX+1 and iX < CGameMode.iMaxX-CTrack.iSegmentLength-1) and math.random(1,3) == 2 then
                iX = iX + math.random(-1,1)
            end
        end
    end
end
--//

--Paint
CPaint = {}
CPaint.Track = function()
    for iSegmentId = 1, #CTrack.tSegments do
        for iSegmentPixelId = 1, #CTrack.tSegments[iSegmentId].tPixels do
            tFloor[CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iX][CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iY].iColor = CColors.NONE
            tFloor[CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iX][CTrack.tSegments[iSegmentId].tPixels[iSegmentPixelId].iY].iBright = tConfig.Bright
        end
    end
end

CPaint.Pixels = function()
    for iPlayerId = 1, #CGameMode.tPlayerTargetPixel do
        if tPlayerInGame[iPlayerId] and CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId then
            local tSegmentPixel = CTrack.tSegments[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentId].tPixels[CGameMode.tPlayerTargetPixel[iPlayerId].iSegmentPixelId]

            tFloor[tSegmentPixel.iX][tSegmentPixel.iY].iColor = tGameStats.Players[iPlayerId].Color
            tFloor[tSegmentPixel.iX][tSegmentPixel.iY].iBright = tConfig.Bright
        
            if tFloor[tSegmentPixel.iX][tSegmentPixel.iY].bClick or tFloor[tSegmentPixel.iX][tSegmentPixel.iY].bDefect then
                CGameMode.PlayerCollectTargetPixel(iPlayerId)
                tSegmentPixel.iTeamId = 0
            end
        end
    end
end

CPaint.StartPositions = function()
    for iPlayerId = 1, #CGameMode.tPlayerStartPositionTrackSegment do
        CGameMode.tPlayerStartPositionClick[iPlayerId] = false

        local tSegment = CTrack.tSegments[CGameMode.tPlayerStartPositionTrackSegment[iPlayerId]]
        for iSegmentPixelId = 1, #tSegment.tPixels do
            tFloor[tSegment.tPixels[iSegmentPixelId].iX][tSegment.tPixels[iSegmentPixelId].iY].iColor = tTeamColors[iPlayerId]
            tFloor[tSegment.tPixels[iSegmentPixelId].iX][tSegment.tPixels[iSegmentPixelId].iY].iBright = tConfig.Bright

            if tFloor[tSegment.tPixels[iSegmentPixelId].iX][tSegment.tPixels[iSegmentPixelId].iY].bClick then
                CGameMode.tPlayerStartPositionClick[iPlayerId] = true
            end

            if not tPlayerInGame[iPlayerId] then
                tFloor[tSegment.tPixels[iSegmentPixelId].iX][tSegment.tPixels[iSegmentPixelId].iY].iBright = tConfig.Bright-2
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
        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
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
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end
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