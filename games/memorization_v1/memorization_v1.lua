--[[
    Название: Запоминалка
    Автор: Avondale, дискорд - avonda

    Описание механики: 
        Игрокам подсвечивается последовательность, её нужно повторить. Доступен соревновательный режим
    Идеи по доработке: 
        Можно добавить жизней
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
    iButtonId = 0,
    iPlayerID = 0
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}

local tTeamColors = {}
tTeamColors[1] = CColors.GREEN
tTeamColors[2] = CColors.YELLOW
tTeamColors[3] = CColors.MAGENTA
tTeamColors[4] = CColors.CYAN
tTeamColors[5] = CColors.BLUE
tTeamColors[6] = CColors.WHITE

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

    if tGame.StartPositions == nil then
        tGame.StartPositions = {}
        if tGame.PlayerCount == nil then tGame.PlayerCount = tConfig.PlayerCount; end

        tGame.StartPositionSizeX = 8
        tGame.StartPositionSizeY = math.ceil(tConfig.ButtonsCount/3)*3 - 1

        local iStartX = 2
        local iStartY = 2
        local iDistance = math.ceil(tGame.Rows/5)

        if tConfig.PlayerCount <= 2 then
            iStartY = math.floor(tGame.Rows/2) - math.floor(tGame.StartPositionSizeY/2)+1
            iDistance = iDistance * 2
        end

        if tConfig.PlayerCount == 1 then
            iStartX = math.floor(tGame.Cols/2) - math.floor(tGame.StartPositionSizeX/2)+1
        end

        local iX = iStartX
        local iY = iStartY

        for iPlayerID = 1, tGame.PlayerCount do
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = iX
            tGame.StartPositions[iPlayerID].Y = iY
            tGame.StartPositions[iPlayerID].Color = tTeamColors[iPlayerID]

            iY = iY + iDistance + tGame.StartPositionSizeY
            if iY + tGame.StartPositionSizeY-1 > tGame.Rows then
                iY = iStartY
                iX = iX + iDistance + tGame.StartPositionSizeX

                if iX + tGame.StartPositionSizeX-1 > tGame.Cols then break; end 
            end
        end
    else
        for iPlayerID = 1, #tGame.StartPositions do
            tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
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
    SetGlobalColorBright(CColors.NONE, 0) -- красим всё поле в один цвет
    if not CGameMode.bCountDownStarted then
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
    end

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or (CGameMode.bCountDownStarted and tPlayerInGame[iPos]) then
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
                        tFloor[iX][iY].iColor = CColors.MAGENTA
                        tFloor[iX][iY].iBright = tConfig.Bright

                        if tFloor[iX][iY].bClick then 
                            bArenaClick = true
                        end
                    end
                end

                if bArenaClick then
                    bAnyButtonClick = true 
                end
            end 
        end
    end

    if not CGameMode.bCountDownStarted and ((iPlayersReady > 0 and bAnyButtonClick) or (not tGame.ArenaMode and (iPlayersReady > 1 or iPlayersReady == #tGame.StartPositions) and CGameMode.bCanStartGame)) then
        bAnyButtonClick = false

        CGameMode.iRealPlayerCount = iPlayersReady

        CGameMode.StartCountDown(10)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, 0)
    SetAllButtonColorBright(CColors.NONE, 0, false) 
    CPaint.PlayerGameZones() 
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
CGameMode.bCanStartGame = false
CGameMode.bCountDownStarted = false
CGameMode.tPlayerSequence = {}
CGameMode.tPlayerSequencePoint = {}
CGameMode.tPlayerSequenceLocalPoint = {}
CGameMode.tPlayerSequencePreviewPoint = {}
CGameMode.tPlayerCanMove = {}
CGameMode.tPlayerSequenceAnimatedPoint = {}
CGameMode.iRealPlayerCount = 0

CGameMode.tPlayerOut = {}
CGameMode.iPlayerOutCount = 0

CGameMode.InitGameMode = function()
    tGameResults.PlayersCount = tConfig.PlayerCount
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("memorization/memorization_guide.mp3")

    if #tGame.StartPositions > 1 then
        CAudio.PlayVoicesSync("choose-color.mp3")
    else
        CAudio.PlayVoicesSync("press-center-for-start.mp3")
    end

    if tGame.ArenaMode then 
        CAudio.PlayVoicesSync("press-zone-for-start.mp3")
    end

    AL.NewTimer(CAudio.GetVoicesDuration("memorization/memorization_guide.mp3") * 1000, function()
        CGameMode.bCanStartGame = true
    end)
end

CGameMode.PrepareGame = function()
    for iPlayerID = 1, 6 do
        if tPlayerInGame[iPlayerID] then
            CGameMode.tPlayerSequence[iPlayerID] = {}
            for i = 1, tConfig.ButtonsCount do
                CGameMode.tPlayerSequence[iPlayerID][i] = math.random(1, tConfig.ButtonsCount)
            end

            CGameMode.tPlayerSequencePoint[iPlayerID] = 1
            CGameMode.tPlayerSequenceLocalPoint[iPlayerID] = 0
            CGameMode.tPlayerSequencePreviewPoint[iPlayerID] = 0
            CGameMode.tPlayerCanMove[iPlayerID] = false
            CGameMode.tPlayerSequenceAnimatedPoint[iPlayerID] = 0
        end
    end

    tGameStats.TargetScore = tConfig.ButtonsCount
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
    CGameMode.PrepareGame()

    iGameState = GAMESTATE_GAME

    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    AL.NewTimer(2000, function()
        for iPlayerID = 1, 6 do
            if tPlayerInGame[iPlayerID] then
                CGameMode.PreviewSequenceForPlayer(iPlayerID)
            end
        end
    end)
end

CGameMode.EndGame = function(bVictory, iWinnerID)
    iGameState = GAMESTATE_POSTGAME
    CAudio.StopBackground()

    if bVictory then
        CGameMode.iWinnerID = iWinnerID

        if tConfig.PlayerCount > 1 then
            CAudio.PlaySyncColorSound(tGame.StartPositions[iWinnerID].Color)
        end
        CAudio.PlayVoicesSync(CAudio.VICTORY)

        SetGlobalColorBright(tGameStats.Players[iWinnerID].Color, tConfig.Bright)
        tGameResults.Color = tGame.StartPositions[iWinnerID].Color
    else
        CAudio.PlayVoicesSync(CAudio.DEFEAT)  

        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED    
    end

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)    
end

CGameMode.PreviewSequenceForPlayer = function(iPlayerID)
    CGameMode.tPlayerSequenceLocalPoint[iPlayerID] = 0
    CGameMode.tPlayerSequencePreviewPoint[iPlayerID] = 0
    CGameMode.tPlayerCanMove[iPlayerID] = false

    local bSwitch = true
    local iPreviewPoint = 0
    AL.NewTimer(100, function()
        if not bSwitch then 
            bSwitch = true
            CGameMode.tPlayerSequencePreviewPoint[iPlayerID] = 0
            return 350 
        end

        iPreviewPoint = iPreviewPoint + 1
        CGameMode.tPlayerSequencePreviewPoint[iPlayerID] = iPreviewPoint

        if CGameMode.tPlayerSequencePreviewPoint[iPlayerID] > CGameMode.tPlayerSequencePoint[iPlayerID] then
            CGameMode.tPlayerCanMove[iPlayerID] = true
            CGameMode.tPlayerSequencePreviewPoint[iPlayerID] = 0
            return nil
        else
            CAudio.PlaySystemSync(CAudio.CLICK)
            bSwitch = false
            return 800
        end
    end)
end

CGameMode.PlayerClickButton = function(iPlayerID, iButtonId)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.tPlayerCanMove[iPlayerID] then return; end

    if iButtonId == CGameMode.tPlayerSequence[iPlayerID][CGameMode.tPlayerSequenceLocalPoint[iPlayerID]+1] then
        CAudio.PlaySystemSync(CAudio.CLICK)
        CGameMode.tPlayerSequenceLocalPoint[iPlayerID] = CGameMode.tPlayerSequenceLocalPoint[iPlayerID] + 1
        CGameMode.tPlayerSequenceAnimatedPoint[iPlayerID] = iButtonId
        CGameMode.tPlayerCanMove[iPlayerID] = false

        if CGameMode.tPlayerSequenceLocalPoint[iPlayerID] == CGameMode.tPlayerSequencePoint[iPlayerID] then
            tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

            if CGameMode.tPlayerSequencePoint[iPlayerID] == #CGameMode.tPlayerSequence[iPlayerID] then
                CGameMode.EndGame(true, iPlayerID)
            else
                CGameMode.tPlayerSequencePoint[iPlayerID] = CGameMode.tPlayerSequencePoint[iPlayerID] + 1
                AL.NewTimer(1500, function()
                    CGameMode.PreviewSequenceForPlayer(iPlayerID)
                end)
            end
        else
            AL.NewTimer(1500, function()
                CGameMode.tPlayerCanMove[iPlayerID] = true
            end)           
        end

        AL.NewTimer(350, function()
            CGameMode.tPlayerSequenceAnimatedPoint[iPlayerID] = 0
        end)
    else
        CAudio.PlaySystemSync(CAudio.MISCLICK)
        CGameMode.PlayerOut(iPlayerID)
    end
end

CGameMode.PlayerOut = function(iPlayerID)
    CGameMode.tPlayerOut[iPlayerID] = true
    CGameMode.iPlayerOutCount = CGameMode.iPlayerOutCount + 1

    if CGameMode.iPlayerOutCount == CGameMode.iRealPlayerCount then
        CGameMode.EndGame(false)
    end
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
    if CGameMode.tPlayerOut[iPlayerID] then
        SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
            tGame.StartPositions[iPlayerID].Y, 
            tGame.StartPositionSizeX-1, 
            tGame.StartPositionSizeY-1, 
            CColors.RED, 
            tConfig.Bright-1)

        return
    end

    SetRectColorBright(tGame.StartPositions[iPlayerID].X-1, 
        tGame.StartPositions[iPlayerID].Y-1, 
        tGame.StartPositionSizeX+1, 
        tGame.StartPositionSizeY+1, 
        tGame.StartPositions[iPlayerID].Color, 
        1)

    local iX = tGame.StartPositions[iPlayerID].X
    local iY = tGame.StartPositions[iPlayerID].Y
    for iButtonId = 1, tConfig.ButtonsCount do
        local iColor = CColors.WHITE
        local iBright = tConfig.Bright

        if not CGameMode.tPlayerCanMove[iPlayerID] then
            if iButtonId == CGameMode.tPlayerSequence[iPlayerID][CGameMode.tPlayerSequencePreviewPoint[iPlayerID]] then
                iColor = CColors.BLUE
                iBright = iBright + 1
            else
                iBright = iBright - 2
            end
        end

        if iButtonId == CGameMode.tPlayerSequenceAnimatedPoint[iPlayerID] then
            iColor = tGame.StartPositions[iPlayerID].Color
        end

        for i = iX, iX + 1 do
            for j = iY, iY + 1 do
                if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                    tFloor[i][j].iColor = iColor
                    tFloor[i][j].iBright = iBright
                    tFloor[i][j].iPlayerID = iPlayerID           
                    tFloor[i][j].iButtonId = iButtonId           
                end            
            end
        end

        iX = iX + 3
        if iX > tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX then
            iX = tGame.StartPositions[iPlayerID].X
            iY = iY + 3
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

        if iGameState == GAMESTATE_SETUP then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
                tFloor[click.X][click.Y].bHold = false
            elseif not tFloor[click.X][click.Y].bHold then
                AL.NewTimer(500, function()
                    if not tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bHold = true
                        AL.NewTimer(750, function()
                            if tFloor[click.X][click.Y].bHold then
                                tFloor[click.X][click.Y].bClick = false
                            end
                        end)
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and not tFloor[click.X][click.Y].bDefect and click.Weight > 5 then
            if tFloor[click.X][click.Y].iPlayerID > 0 and tFloor[click.X][click.Y].iButtonId > 0 then
                CGameMode.PlayerClickButton(tFloor[click.X][click.Y].iPlayerID, tFloor[click.X][click.Y].iButtonId)
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