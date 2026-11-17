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
    Scoreboard = 
    {
        GridCols = 4,
        GridRows = 2,
        HeaderWidget = {},
        BottomWidget = {Text = "", Icon = "timer"},
        GameStatsWidgets = {},
    },
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
    iPlayerID = 0,
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

    tGame.StartPositions = {}
    tGame.StartPositionSizeX = 3
    tGame.StartPositionSizeY = 3

    local iX = tGame.iMinX + 1
    local iY = tGame.iMinY + 1
    local iInc = math.floor((tGame.iMaxY-tGame.iMinY+1)/5)
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        tGame.StartPositions[iPlayerID] = {}
        tGame.StartPositions[iPlayerID].X = iX
        tGame.StartPositions[iPlayerID].Y = iY

        iX = iX + tGame.StartPositionSizeX + iInc
        if iX > tGame.iMaxX-tGame.StartPositionSizeX then
            iX = tGame.iMinX + 1
            iY = iY + tGame.StartPositionSizeX + iInc
            if iY > tGame.iMaxY-tGame.StartPositionSizeY then break; end
        end
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
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or (CGameMode.bCountDownStarted and CGameMode.tPlayers[iPos]) then
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                CGameMode.CreatePlayer(iPos, tGame.StartPositions[iPos].X+1, tGame.StartPositions[iPos].Y+1)
            else
                CGameMode.tPlayers[iPos] = nil
            end

            SetRectColorBright(tGame.StartPositions[iPos].X, tGame.StartPositions[iPos].Y, 
                tGame.StartPositionSizeX, tGame.StartPositionSizeY, 
                CGameMode.tPlayerColors[iPos], iBright)
        end
    end

    if not CGameMode.bCountDownStarted and iPlayersReady > 1 and CGameMode.bCanAutoStart then
        CGameMode.bCountDownStarted = true
        CGameMode.StartCountDown(5)
    end

    CGameMode.UpdatePlayersProgress()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CGameMode.DrawTargetPixels()
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
CGameMode.bCanAutoStart = false

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.RED
CGameMode.tPlayerColors[2] = CColors.GREEN
CGameMode.tPlayerColors[3] = CColors.YELLOW
CGameMode.tPlayerColors[4] = CColors.MAGENTA
CGameMode.tPlayerColors[5] = CColors.BLUE
CGameMode.tPlayerColors[6] = CColors.CYAN
CGameMode.tPlayerColors[7] = CColors.WHITE

CGameMode.tPlayers = {}

CGameMode.InitGameMode = function()

end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("pixeldash/pixel-dash-rules.mp3")
        CAudio.PlayVoicesSync("choose-color.mp3")
        AL.NewTimer((CAudio.GetVoicesDuration("pixeldash/pixel-dash-rules.mp3")+CAudio.GetVoicesDuration("choose-color.mp3"))*1000, function()
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
        tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration

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

    tGameStats.StageLeftDuration = tConfig.TimeLimit
    tGameStats.StageTotalDuration = tGameStats.StageLeftDuration
    
    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration

        if tGameStats.StageLeftDuration == 0 then
            CGameMode.EndGame()
            return nil;
        else
            return 1000;
        end
    end)
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -1
    local iWinnerID = 1
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if CGameMode.tPlayers[iPlayerID] ~= nil and CGameMode.tPlayers[iPlayerID].iScore > iMaxScore then
            iWinnerID = iPlayerID
            iMaxScore = CGameMode.tPlayers[iPlayerID].iScore
        end
    end

    SetGlobalColorBright(CGameMode.tPlayerColors[iWinnerID], tConfig.Bright)
    tGameResults.Color = CGameMode.tPlayerColors[iWinnerID]

    CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[iWinnerID])
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    tGameResults.Won = true
    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()    
        iGameState = GAMESTATE_FINISH
    end)  
end

CGameMode.CreatePlayer = function(iPlayerID, iX, iY)
    CGameMode.tPlayers[iPlayerID] = {}
    CGameMode.tPlayers[iPlayerID].iScore = 0
    CGameMode.tPlayers[iPlayerID].iTargetX = iX
    CGameMode.tPlayers[iPlayerID].iTargetY = iY
end

CGameMode.AddScoreToPlayer = function(iPlayerID, iScorePlus)
    CGameMode.tPlayers[iPlayerID].iScore = CGameMode.tPlayers[iPlayerID].iScore + iScorePlus
    if CGameMode.tPlayers[iPlayerID].iScore > tGameStats.TargetScore then tGameStats.TargetScore = CGameMode.tPlayers[iPlayerID].iScore; end

    CAudio.PlaySystemAsync(CAudio.CLICK)

    tGameResults.Score = tGameResults.Score + 1

    CGameMode.UpdatePlayersProgress();
end

CGameMode.NewTargetForPlayer = function(iPlayerID)
    local oldX = CGameMode.tPlayers[iPlayerID].iTargetX
    local oldY = CGameMode.tPlayers[iPlayerID].iTargetY
    repeat
        CGameMode.tPlayers[iPlayerID].iTargetX = oldX + math.random(-2, 2)
        CGameMode.tPlayers[iPlayerID].iTargetY = oldY + math.random(-2, 2)
    until tFloor[CGameMode.tPlayers[iPlayerID].iTargetX] and tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY] 
        and tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iPlayerID == 0 and not tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].bDefect

    tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iPlayerID = iPlayerID
end

CGameMode.UpdatePlayersProgress = function()
    tGameStats.Scoreboard.GameStatsWidgets = {}
    tGameStats.Scoreboard.GridRows = 0

    local iTruePlayer = 0
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if CGameMode.tPlayers[iPlayerID] then
            iTruePlayer = iTruePlayer + 1
            if iTruePlayer % 2 ~= 0 then
                tGameStats.Scoreboard.GridRows = tGameStats.Scoreboard.GridRows + 1
            end
            tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets+1] =             
            {
                Type = "progress_bar",
                Position = {Col = 0, ColSpan = 2, Row = tGameStats.Scoreboard.GridRows-1, RowSpan = 1},
                Value = CGameMode.tPlayers[iPlayerID].iScore/tGameStats.TargetScore*100,
                Label = CGameMode.tPlayers[iPlayerID].iScore,
                Color = CGameMode.tPlayerColors[iPlayerID]
            }
            if iTruePlayer % 2 == 0 then
                tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets].Position.Col = 2
            end          
        end
    end
end

CGameMode.DrawTargetPixels = function()
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if CGameMode.tPlayers[iPlayerID] ~= nil then
            tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iColor = CGameMode.tPlayerColors[iPlayerID]
            tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iBright = tConfig.Bright
            tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iPlayerID = iPlayerID

            if tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].bClick or tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].bDefect then
                CGameMode.AddScoreToPlayer(iPlayerID, 1)
                CGameMode.NewTargetForPlayer(iPlayerID)
                tFloor[CGameMode.tPlayers[iPlayerID].iTargetX][CGameMode.tPlayers[iPlayerID].iTargetY].iPlayerID = 0
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