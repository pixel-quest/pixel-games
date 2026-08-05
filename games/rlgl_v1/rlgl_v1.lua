--[[
    Название: Тише едешь - Дальше Будешь / Red Light, Green Light
    Автор: Avondale, дискорд - avonda
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
    TotalLives = 1,
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
        GameStatsWidgets = {}
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

local tPlayerInGame = {}

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

    local iStartX = tGame.iMinX + 2
    local iStartY = tGame.iMinY + 1
    local POS_SIZE = 2

    CGameMode.iMaxPlayers = 0
    local iPlayersReadyCount = 0

    for iPlayerID = 1, #CGameMode.tPlayerColors do
        CGameMode.iMaxPlayers = CGameMode.iMaxPlayers + 1

        local iBright = 1
        if tPlayerInGame[iPlayerID] then iBright = 3; end

        local bClick = false
        for iX = iStartX, iStartX + POS_SIZE-1 do
            for iY = iStartY, iStartY + POS_SIZE-1 do
                tFloor[iX][iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                tFloor[iX][iY].iBright = iBright

                if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick then
                    bClick = true
                end
            end
        end

        if bClick or (CGameMode.bCountDownStarted and tPlayerInGame[iPlayerID]) then
            tPlayerInGame[iPlayerID] = true
            iPlayersReadyCount = iPlayersReadyCount + 1
        elseif not CGameMode.bCountDownStarted then
            tPlayerInGame[iPlayerID] = false
        end

        iStartY = iStartY + 1 + POS_SIZE

        if iStartY+POS_SIZE-1 > tGame.iMaxY then
            iStartY = tGame.iMinY + 1
            iStartX = iStartX + 1 + POS_SIZE
            if iStartX+POS_SIZE-1 >= tGame.iMaxX then break; end
        end
    end

    if not CGameMode.bCountDownStarted then 
        if CGameMode.bCanAutoStart and iPlayersReadyCount > 1 then
            CGameMode.StartCountDown(10)
        end
    end

    tGameResults.PlayersCount = iPlayersReadyCount
    CGameMode.iRealPlayerCount = iPlayersReadyCount    

    CGameMode.UpdateGameStats()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CGameMode.PaintGame()
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

CGameMode.bRedLight = false
CGameMode.bDetectClicks = false
CGameMode.bDamaged = false

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.YELLOW
CGameMode.tPlayerColors[2] = CColors.WHITE
CGameMode.tPlayerColors[3] = CColors.CYAN
CGameMode.tPlayerColors[4] = CColors.RED
CGameMode.tPlayerColors[5] = CColors.MAGENTA
CGameMode.tPlayerColors[6] = CColors.GREEN
CGameMode.tPlayerColors[7] = CColors.BLUE

CGameMode.tPlayerScores = {}
CGameMode.tPlayerCoins = {}

CGameMode.tLavaSafePixels = {}
CGameMode.tLavaClickedPixels = {}

CGameMode.InitGameMode = function()
    tGameStats.TargetScore = tConfig.TargetScore
    tGameStats.TotalLives = tConfig.TotalLives
    tGameStats.CurrentLives = tConfig.TotalLives
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("rlgl/rlgl-rules.mp3")
        CAudio.PlayVoicesSync("choose-color.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("rlgl/rlgl-rules.mp3") * 1000, function()
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

    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if tPlayerInGame[iPlayerID] then
            CGameMode.tPlayerCoins[iPlayerID] = {}
            CGameMode.SpawnCoinForPlayer(iPlayerID)
        end
    end

    CGameMode.GreenLightRedLight()
end

CGameMode.EndGame = function(iWinnerID)
    iGameState = GAMESTATE_POSTGAME
    CAudio.ResetSync()
    CAudio.StopBackground()

    if iWinnerID then
        CGameMode.iWinnerID = iWinnerID

        CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[CGameMode.iWinnerID])
        CAudio.PlayVoicesSync(CAudio.VICTORY)

        SetGlobalColorBright(CGameMode.tPlayerColors[CGameMode.iWinnerID], tConfig.Bright)
        tGameResults.Color = CGameMode.tPlayerColors[CGameMode.iWinnerID]
        tGameResults.Won = true
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)

        SetGlobalColorBright(CColors.RED, tConfig.MaxBright)
        tGameResults.Color = CColors.RED
        tGameResults.Won = false
    end

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)  
end

CGameMode.SpawnCoinForPlayer = function(iPlayerID)
    if CGameMode.tPlayerCoins[iPlayerID].iX == nil or CGameMode.tPlayerCoins[iPlayerID].iX < tGame.CenterX then
        CGameMode.tPlayerCoins[iPlayerID].iX = math.random(tGame.iMaxX-4, tGame.iMaxX)  
    else
        CGameMode.tPlayerCoins[iPlayerID].iX = math.random(tGame.iMinX, tGame.iMinX+4)   
    end

    repeat CGameMode.tPlayerCoins[iPlayerID].iY = math.random(tGame.iMinY, tGame.iMaxY)
    until not tFloor[CGameMode.tPlayerCoins[iPlayerID].iX][CGameMode.tPlayerCoins[iPlayerID].iY].bDefect and tFloor[CGameMode.tPlayerCoins[iPlayerID].iX][CGameMode.tPlayerCoins[iPlayerID].iY].iPlayerID == 0
end

CGameMode.PlayerClickPixel = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    tFloor[iX][iY].iPlayerID = 0

    CGameMode.tPlayerScores[iPlayerID] = (CGameMode.tPlayerScores[iPlayerID] or 0) + 1

    CGameMode.SpawnCoinForPlayer(iPlayerID)

    CGameMode.UpdateGameStats()

    if CGameMode.tPlayerScores[iPlayerID] >= tConfig.TargetScore then
        CGameMode.EndGame(iPlayerID)
    end
end

CGameMode.DamagePlayer = function()
    if tConfig.TotalLives > 0 then
        tGameStats.CurrentLives = tGameStats.CurrentLives - 1
        
        CGameMode.UpdateGameStats()

        if tGameStats.CurrentLives <= 0 then
            CGameMode.EndGame(false)
        end
    end
end

CGameMode.PaintGame = function()
    if CGameMode.bRedLight then
        SetGlobalColorBright(CColors.RED, tConfig.Bright)

        for iSafe = 1, #CGameMode.tLavaSafePixels do
            tFloor[CGameMode.tLavaSafePixels[iSafe].iX][CGameMode.tLavaSafePixels[iSafe].iY].iColor = CColors.GREEN
        end
        for iClicked = 1, #CGameMode.tLavaClickedPixels do
            tFloor[CGameMode.tLavaClickedPixels[iClicked].iX][CGameMode.tLavaClickedPixels[iClicked].iY].iColor = CColors.MAGENTA
        end

        if CGameMode.bDetectClicks then
            for iX = 1, tGame.Cols do
                for iY = 1, tGame.Rows do
                    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].iColor == CColors.RED and tFloor[iX][iY].bClick then
                        CAudio.PlaySystemAsync(CAudio.MISCLICK)
                        CGameMode.tLavaClickedPixels[#CGameMode.tLavaClickedPixels+1] = {iX = iX, iY = iY} 

                        if not CGameMode.bDamaged then
                            CGameMode.bDamaged = true
                            CGameMode.DamagePlayer()

                            AL.NewTimer(1000, function()
                                CGameMode.bDamaged = false
                            end)
                        end
                    end
                end
            end
        end
    else
        for iPlayerID = 1, #CGameMode.tPlayerColors do
            if tPlayerInGame[iPlayerID] and CGameMode.tPlayerCoins[iPlayerID] then
                tFloor[CGameMode.tPlayerCoins[iPlayerID].iX][CGameMode.tPlayerCoins[iPlayerID].iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                tFloor[CGameMode.tPlayerCoins[iPlayerID].iX][CGameMode.tPlayerCoins[iPlayerID].iY].iBright = tConfig.Bright
                tFloor[CGameMode.tPlayerCoins[iPlayerID].iX][CGameMode.tPlayerCoins[iPlayerID].iY].iPlayerID = iPlayerID
            end
        end
    end
end

CGameMode.GreenLightRedLight = function()
    CAudio.ResetSync();
    CAudio.PlayVoicesSync("rlgl/rlgl.mp3")
    local iDur = CAudio.GetVoicesDuration("rlgl/rlgl.mp3")*1000

    AL.NewTimer(iDur, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        CGameMode.bRedLight = true

        CGameMode.tLavaSafePixels = {}
        CGameMode.tLavaClickedPixels = {}

        for iX = 1, tGame.Cols do
            for iY = 1, tGame.Rows do
                if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                    CGameMode.tLavaSafePixels[#CGameMode.tLavaSafePixels+1] = {iX = iX, iY = iY}
                end
            end
        end

        AL.NewTimer(tGame.BurnDelay, function()
            CGameMode.bDetectClicks = true
        end)

        AL.NewTimer(iDur + 1000, function()
            if iGameState ~= GAMESTATE_GAME then return; end

            CGameMode.bRedLight = false
            CGameMode.bDetectClicks = false
            CGameMode.GreenLightRedLight()
        end)
    end)
end

CGameMode.UpdateGameStats = function()
    tGameStats.Scoreboard.GameStatsWidgets = {}  

    if tConfig.TotalLives > 0 then
        tGameStats.Scoreboard.GameStatsWidgets[1] = 
        {
            Type = "image_text",
            Position = {Col = 0, ColSpan = 2, Row = 0, RowSpan = 1},
            Icon = "heart",
            Text = tGameStats.CurrentLives,
            TextPosition = "inside"
        }
        tGameStats.Scoreboard.GridRows = 1
    else
        tGameStats.Scoreboard.GridRows = 0
    end

    local iTruePlayer = 0
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if tPlayerInGame[iPlayerID] then
            iTruePlayer = iTruePlayer + 1

            local iCol = 2
            if iTruePlayer % 2 ~= 0 then
                tGameStats.Scoreboard.GridRows = tGameStats.Scoreboard.GridRows + 1
                iCol = 0
            end

            tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets+1] =             
            {
                Type = "progress_bar",
                Position = {Col = iCol, ColSpan = 2, Row = tGameStats.Scoreboard.GridRows-1, RowSpan = 1},
                Value = (CGameMode.tPlayerScores[iPlayerID] or 0)/tGameStats.TargetScore*100,
                Label = CGameMode.tPlayerScores[iPlayerID] or 0,
                Color = CGameMode.tPlayerColors[iPlayerID]
            }
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
            tFloor[iX][iY].iPlayerID = 0
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
    
        if iGameState == GAMESTATE_GAME and tFloor[click.X][click.Y].iPlayerID > 0 then
            CGameMode.PlayerClickPixel(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if iGameState == GAMESTATE_GAME and tFloor[defect.X][defect.Y].iPlayerID > 0 then
            CGameMode.PlayerClickPixel(defect.X, defect.Y)
        end
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