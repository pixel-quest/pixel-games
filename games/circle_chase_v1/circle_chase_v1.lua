--[[
    Название: Погоня за кругом
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Игроки бегают за кругом/от круга
        У круга переодически меняется цвет, а за нажатия по этому кругу - игроку с этим цветом даются очки
        соотвественно игрокам нужно избегать круга пока он не станет их цвета, после этого наоборот за кругом нужно гнатся
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

local bAnyButtonClick = false
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
    local POS_SIZE = math.floor((tGame.iMaxY-tGame.iMinY+1) / 3)

    local iMaxPlayers = 0
    local iPlayersReadyCount = 0

    for iPlayerID = 1, 6 do
        iMaxPlayers = iMaxPlayers + 1

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

        if bClick then
            tPlayerInGame[iPlayerID] = true
            iPlayersReadyCount = iPlayersReadyCount + 1
            tGameStats.Players[iPlayerID].Color = CGameMode.tPlayerColors[iPlayerID]
        elseif not CGameMode.bCountDownStarted then
            tPlayerInGame[iPlayerID] = false
            tGameStats.Players[iPlayerID].Color = CColors.NONE
        end

        iStartX = iStartX + 2 + POS_SIZE
        if iStartX+POS_SIZE-1 >= tGame.iMaxX then
            iStartX = tGame.iMinX+2
            iStartY = iStartY + 3 + POS_SIZE
            if iStartY+POS_SIZE-1 >= tGame.iMaxY then break; end
        end
    end

    if not CGameMode.bCountDownStarted then 
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

        if (iPlayersReadyCount == iMaxPlayers and CGameMode.bCanAutoStart) or (bAnyButtonClick and iPlayersReadyCount > 1) then
            CGameMode.StartCountDown(5)
        end
    end

    tGameResults.PlayersCount = iPlayersReadyCount
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    

    CCircle.Paint()
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
CGameMode.iWinnerID = 0

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.BLUE
CGameMode.tPlayerColors[2] = CColors.MAGENTA
CGameMode.tPlayerColors[3] = CColors.CYAN
CGameMode.tPlayerColors[4] = CColors.RED
CGameMode.tPlayerColors[5] = CColors.YELLOW
CGameMode.tPlayerColors[6] = CColors.GREEN

CGameMode.InitGameMode = function()
    CCircle.CIRCLE_RADIUS = tConfig.CircleSize
    CCircle.iX = tGame.CenterX
    CCircle.iY = tGame.CenterY
    CCircle.NewTarget()
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("circle_chase/cc_rules.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("circle_chase/cc_rules.mp3")*1000 + 3000, function()
            CGameMode.bCanAutoStart = true
        end)    
    else
        CGameMode.bCanAutoStart = true
    end

    CAudio.PlayVoicesSync("choose-color.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.ResetSync()
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
    iGameState = GAMESTATE_GAME

    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    tGameStats.StageLeftDuration = tConfig.SwitchDuration*(tGameResults.PlayersCount*2)
    tGameStats.StageTotalDuration = tGameStats.StageLeftDuration

    CCircle.ListPlayers()
    CCircle.SwitchPlayer()

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        if iGameState ~= GAMESTATE_GAME or tGameStats.StageLeftDuration == 0 then return nil; end
        return 1000
    end)

    AL.NewTimer(150, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end 
        CCircle.Movement()
        return 150;
    end)

    AL.NewTimer(500, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
        CCircle.Think()
        return 500;
    end)

    AL.NewTimer(tConfig.SwitchDuration*1000, function()
        if not CCircle.SwitchPlayer() then
            CGameMode.EndGame()
            return nil;
        end 
        return tConfig.SwitchDuration*1000
    end)
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -1

    for iPlayerID = 1, 6 do
        if tPlayerInGame[iPlayerID] and tGameStats.Players[iPlayerID].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerID].Score
            CGameMode.iWinnerID = iPlayerID
        end
    end

    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color
    tGameResults.Won = true

    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[CGameMode.iWinnerID])
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(CGameMode.tPlayerColors[CGameMode.iWinnerID], tConfig.Bright)

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end
--//

--Circle
CCircle = {}

CCircle.iX = 0
CCircle.iY = 0
CCircle.iTargetX = 0
CCircle.iTargetY = 0
CCircle.CIRCLE_RADIUS = 3

CCircle.iCurrentPlayerID = 1
CCircle.iClickCount = 0

CCircle.tPlayersList = {}
CCircle.iListPosition = 0

CCircle.ListPlayers = function()
    local i = 1

    for iPlayerID = 1, 6 do
        if tPlayerInGame[iPlayerID] then
            CCircle.tPlayersList[i] = iPlayerID
            i = i + 1
        end
    end

    CCircle.tPlayersList = TableConcat(ShuffleTable(CCircle.tPlayersList), ShuffleTable(CHelp.DeepCopy(CCircle.tPlayersList)))

    CLog.print(#CCircle.tPlayersList)
    CLog.print(table.concat(CCircle.tPlayersList, ", "))
end

CCircle.NewTarget = function()
    CCircle.iTargetX = math.random(1, tGame.Cols)
    CCircle.iTargetY = math.random(1, tGame.Rows)
end

CCircle.SwitchPlayer = function()
    CCircle.iListPosition = CCircle.iListPosition + 1
    if CCircle.iListPosition > #CCircle.tPlayersList then return false; end
    CCircle.iCurrentPlayerID = CCircle.tPlayersList[CCircle.iListPosition]

    CAudio.PlaySystemAsync("dodge/lightsaber-swing.mp3")
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[CCircle.iCurrentPlayerID])

    return true 
end

CCircle.Movement = function()
    local iXPlus = 0
    local iYPlus = 0

    if CCircle.iX < CCircle.iTargetX then
        iXPlus = 1
    elseif CCircle.iX > CCircle.iTargetX then
        iXPlus = -1
    end

    if iXPlus == 0 and iYPlus == 0 then
        CCircle.NewTarget()
    else
        if CCircle.iY < CCircle.iTargetY then
            iYPlus = 1
        elseif CCircle.iY > CCircle.iTargetY then
            iYPlus = -1
        end

        CCircle.iX = CCircle.iX + iXPlus
        CCircle.iY = CCircle.iY + iYPlus
    end
end

CCircle.Think = function()
    tGameStats.Players[CCircle.iCurrentPlayerID].Score = tGameStats.Players[CCircle.iCurrentPlayerID].Score + CCircle.iClickCount

    if tGameStats.Players[CCircle.iCurrentPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[CCircle.iCurrentPlayerID].Score
    end

    tGameResults.Score = tGameResults.Score + CCircle.iClickCount
end

CCircle.Paint = function()
    CCircle.iClickCount = 0

    local iXM = CCircle.iX
    local iYM = CCircle.iY
    local iR = CCircle.CIRCLE_RADIUS

    local iX = -iR
    local iY = 0
    local iR2 = 2-2*iR

    local paintCirclePixel = function(iX, iY)
        for iX2 = iX-1, iX+1 do
            for iY2 = iY-1, iY+1 do
                if tFloor[iX2] and tFloor[iX2][iY2] and tFloor[iX2][iY2].iColor == CColors.NONE then
                    tFloor[iX2][iY2].iColor = CGameMode.tPlayerColors[CCircle.iCurrentPlayerID]
                    tFloor[iX2][iY2].iBright = tConfig.Bright

                    if tFloor[iX2][iY2].bClick and not tFloor[iX2][iY2].bDefect then
                        CCircle.iClickCount = CCircle.iClickCount + 1
                    end
                end
            end
        end
    end

    paintCirclePixel(iXM, iYM)

    repeat
        paintCirclePixel(iXM-iX, iYM+iY)
        paintCirclePixel(iXM-iY, iYM-iX)
        paintCirclePixel(iXM+iX, iYM-iY)
        paintCirclePixel(iXM+iY, iYM+iX)

        iR = iR2
        if iR <= iY then 
            iY = iY+1
            iR2 = iR2 + (iY * 2 + 1) 
        end
        if iR > iX or iR2 > iY then 
            iX = iX+1
            iR2 = iR2 + (iX * 2 + 1) 
        end
    until iX > 0
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

    if click.Click then bAnyButtonClick = true; end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end