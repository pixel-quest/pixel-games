-- Название: Танцы
-- Автор: Avondale, дискорд - avonda
-- Описание механики: танцуй, нажимая набегающие пиксели
-- Идеи по доработке:
--    1. Сейчас пиксели ловятся, если просто стоять. Хотелось бы наказывать за пустые нажатия, но есть сложность с инертностью датчиков

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
local iSongStartedTime = 0

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
}

local tFloor = {}
local tButtons = {}

local tFloorStruct = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    iPixelID = 0,
    bAnimated = false,
}
local tButtonStruct = {
    iColor = CColors.NONE,
    iBright = tConfig.Bright,
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
        tButtons[iId].iColor = CColors.BLUE
        tButtons[iId].iBright = CColors.BRIGHT70
    end

    local err = CAudio.PreloadFile(tGame["SongName"])
    if err ~= nil then error(err); end

    CAudio.PlaySync("voices/choose-color.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        CSongSync.Count((CTime.unix() - iSongStartedTime) * 1000)
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)

    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then

            local iBright = CColors.BRIGHT15
            if CheckPositionClick({X = tPos.X, Y = tPos.Y-1}, tGame.StartPositionSize) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if iPlayersReady > 0 and bAnyButtonClick then
        iGameState = GAMESTATE_GAME
        CGameMode.CountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.Borders()
    CPaint.PlayerZones()
    CPaint.Pixels() -- красим движущиеся пиксели
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
        setButton(i, tButton.iColor, tConfig.Bright)
    end
end

function SwitchStage()

end

--SONGSYNC
CSongSync = {}
CSongSync.iTime = 0
CSongSync.iSongPoint = 1
CSongSync.bOn = false
CSongSync.tSong = {}

CSongSync.Start = function()
    CSongSync.bOn = true
    CSongSync.tSong = tGame["Song"]
    tGameStats.TargetScore = 0
    for i = 1, #CSongSync.tSong do
        if CSongSync.tSong[i] then
            CSongSync.tSong[i][1] = CSongSync.tSong[i][1] - (tConfig.PixelMoveDelayMS * (tGame.Rows - 3))

            for j = 2, #CSongSync.tSong[i] do
                if CSongSync.tSong[i][j] then
                    tGameStats.TargetScore = tGameStats.TargetScore + 1
                end
            end
        end
    end

    CAudio.PlaySync(tGame["SongName"])
    iSongStartedTime = CTime.unix()
end

CSongSync.Count = function(iTimePassed)
    if (not CSongSync.bOn) or iGameState ~= GAMESTATE_GAME then return; end
    for i = 1, #CSongSync.tSong do
        if CSongSync.tSong[i] ~= nil then
            if CSongSync.tSong[i][1] - iTimePassed <= 0 then
                local iBatchID = math.random(1,999)
                for j = 2, #CSongSync.tSong[i] do
                    CGameMode.SpawnPixelForPlayers(CSongSync.tSong[i][j], iBatchID)
                end

                if i == #CSongSync.tSong then
                    CTimer.New(5000, function()
                        CGameMode.EndGame()
                    end)
                end

                CSongSync.tSong[i] = nil
            end
        end
    end
end
--//

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = -1
CGameMode.iWinnerID = -1
CGameMode.tPixels = {}
CGameMode.tPixelStruct = {
    iPointX = 0,
    iPointY = 0,
    iColor = CColors.RED,
    iBright = CColors.BRIGHT50,
    iPlayerID = 0,
    bClickable = false,
    iBatchID = 0,
}
CGameMode.tPlayerPixelBatches = {}

CGameMode.CountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
        CAudio.PlayLeftAudio(CGameMode.iCountdown)

        CGameMode.iCountdown = CGameMode.iCountdown - 1
        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1

            CAudio.PlaySync(CAudio.START_GAME)

            CGameMode.PixelMovement()
            CSongSync.Start()

            return nil
        else
            return 1000
        end
    end)
end

CGameMode.PixelMovement = function()
    CTimer.New(tConfig.PixelMoveDelayMS, function()
        if iGameState ~= GAMESTATE_GAME then return nil end

        for i = 1, #CGameMode.tPixels do
            if CGameMode.tPixels[i] ~= nil then
                CGameMode.MovePixel(i)
                CGameMode.CalculatePixel(i)
            end
        end

        return tConfig.PixelMoveDelayMS
    end)
end

CGameMode.MovePixel = function(iPixelID)
    tFloor[CGameMode.tPixels[iPixelID].iPointX][CGameMode.tPixels[iPixelID].iPointY].iPixelID = 0

    CGameMode.tPixels[iPixelID].iPointY = CGameMode.tPixels[iPixelID].iPointY - 1

    if CGameMode.tPixels[iPixelID].iPointY > 0 then
        tFloor[CGameMode.tPixels[iPixelID].iPointX][CGameMode.tPixels[iPixelID].iPointY].iPixelID = iPixelID
    end
end

CGameMode.CalculatePixel = function(iPixelID)
    if CGameMode.tPixels[iPixelID] == nil then return; end

    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID

    if CGameMode.tPixels[iPixelID].iPointY <= tGame.StartPositions[iPlayerID].Y then
        CGameMode.tPixels[iPixelID].iBright = CColors.BRIGHT100
        CGameMode.tPixels[iPixelID].bClickable = true

        if CGameMode.tPixels[iPixelID].iPointY < 1 then
            if CGameMode.tPlayerPixelBatches[iPlayerID][CGameMode.tPixels[iPixelID].iBatchID] then
                CGameMode.tPlayerPixelBatches[iPlayerID][CGameMode.tPixels[iPixelID].iBatchID] = false
                CPaint.AnimateRow(tGame.StartPositions[iPlayerID].X - 1, CColors.RED)
                CPaint.AnimateRow(tGame.StartPositions[iPlayerID].X + tGame.StartPositionSize, CColors.RED)
            end

            CGameMode.tPixels[iPixelID] = nil
        elseif tFloor[CGameMode.tPixels[iPixelID].iPointX][CGameMode.tPixels[iPixelID].iPointY].bClick == true then
            CGameMode.ScorePixel(iPixelID)
        end
    end
end

CGameMode.ScorePixel = function(iPixelID)
    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

    if CGameMode.tPlayerPixelBatches[iPlayerID][CGameMode.tPixels[iPixelID].iBatchID] == true then
        CPaint.AnimateRow(tGame.StartPositions[iPlayerID].X - 1, CColors.GREEN)
        CPaint.AnimateRow(tGame.StartPositions[iPlayerID].X + tGame.StartPositionSize, CColors.GREEN)
    end

    CGameMode.tPixels[iPixelID] = nil
end

CGameMode.SpawnPixelForPlayers = function(iPointX, iBatchID)
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CGameMode.SpawnPixelForPlayer(i, iPointX, iBatchID)
        end
    end
end

CGameMode.SpawnPixelForPlayer = function(iPlayerID, iPointX, iBatchID)
    --local iPointX = math.random(tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSize-1)
    iPointX = tGame.StartPositions[iPlayerID].X + 4 - iPointX
    local iPixelID = #CGameMode.tPixels+1

    CGameMode.tPixels[iPixelID] = CHelp.ShallowCopy(CGameMode.tPixelStruct)
    CGameMode.tPixels[iPixelID].iPointX = iPointX
    CGameMode.tPixels[iPixelID].iPointY = tGame.Rows
    CGameMode.tPixels[iPixelID].iPlayerID = iPlayerID
    CGameMode.tPixels[iPixelID].iColor = tGameStats.Players[iPlayerID].Color
    CGameMode.tPixels[iPixelID].iBright = tConfig.Bright
    CGameMode.tPixels[iPixelID].bClickable = false
    CGameMode.tPixels[iPixelID].iBatchID = iBatchID

    if CGameMode.tPlayerPixelBatches[iPlayerID] == nil then CGameMode.tPlayerPixelBatches[iPlayerID] = {} end
    CGameMode.tPlayerPixelBatches[iPlayerID][iBatchID] = true
end

CGameMode.EndGame = function()
    local iMaxScore = -1

    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] and tGameStats.Players[i] and tGameStats.Players[i].Score > iMaxScore then
            iMaxScore = tGameStats.Players[i].Score
            CGameMode.iWinnerID = i
        end
    end

    CPaint.ClearAnimations()
    --CPaint.AnimateEnd(tGameStats.Players[CGameMode.iWinnerID].Color)
    iGameState = GAMESTATE_POSTGAME
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATE_DELAY = 50

CPaint.Borders = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            local iColor = CColors.WHITE
            SetRowColorBright(tGame.StartPositions[i].X-1, tGame.Rows, iColor, CColors.BRIGHT70)
            SetRowColorBright(tGame.StartPositions[i].X+tGame.StartPositionSize, tGame.Rows, iColor, CColors.BRIGHT70)
        end
    end
end

CPaint.Pixels = function()
    for i = 1, #CGameMode.tPixels do
        if CGameMode.tPixels[i] then
            tFloor[CGameMode.tPixels[i].iPointX][CGameMode.tPixels[i].iPointY].iColor = CGameMode.tPixels[i].iColor
            tFloor[CGameMode.tPixels[i].iPointX][CGameMode.tPixels[i].iPointY].iBright = CGameMode.tPixels[i].iBright
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    SetColColorBright(tGame.StartPositions[iPlayerID], tGame.StartPositionSize-1, tGame.StartPositions[iPlayerID].Color, iBright)
    SetColColorBright({X = tGame.StartPositions[iPlayerID].X+1, Y = tGame.StartPositions[iPlayerID].Y-1,}, tGame.StartPositionSize-3, tGame.StartPositions[iPlayerID].Color, iBright)
end

CPaint.PlayerZones = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CPaint.PlayerZone(i, CColors.BRIGHT15)
        end
    end
end

CPaint.AnimateRow = function(iX, iColor)
    for iY = 1, tGame.Rows do
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].bAnimated = true
    end

    CTimer.New(tConfig.PixelMoveDelayMS, function()
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
        end
    end)
end

CPaint.ClearAnimations = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
        end
    end
end
--//

--TIMER класс отвечает за таймеры, очень полезная штука. можно вернуть время нового таймера с тем же колбеком
CTimer = {}
CTimer.tTimers = {}

CTimer.New = function(iSetTime, fCallback)
    CTimer.tTimers[#CTimer.tTimers+1] = {iTime = iSetTime, fCallback = fCallback}
end

-- просчёт таймеров каждый тик
CTimer.CountTimers = function(iTimePassed)
    for i = 1, #CTimer.tTimers do
        if CTimer.tTimers[i] ~= nil then
            CTimer.tTimers[i].iTime = CTimer.tTimers[i].iTime - iTimePassed

            if CTimer.tTimers[i].iTime <= 0 then
                iNewTime = CTimer.tTimers[i].fCallback()
                if iNewTime and iNewTime ~= nil then -- если в return было число то создаём новый таймер с тем же колбеком
                    iNewTime = iNewTime + CTimer.tTimers[i].iTime
                    CTimer.New(iNewTime, CTimer.tTimers[i].fCallback)
                end

                CTimer.tTimers[i] = nil
            end
        end
    end
end
--//

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSize)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i/iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then
            if tFloor[iX][iY].bClick then
                return true
            end
        end
    end

    return false
end

function SetPositionColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i / iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
end

function SetRowColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart
        local iY = 1 + i

        if not (iY < 1 or iY > tGame.Rows) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
end

function SetColColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart.X + i
        local iY = tStart.Y

        if not (iX < 1 or iX > tGame.Cols) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
end

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
            end
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
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
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    local iPixelID = tFloor[click.X][click.Y].iPixelID
    if click.Click and iPixelID and iPixelID ~= 0 and CGameMode.tPixels[iPixelID] and CGameMode.tPixels[iPixelID].bClickable then
        CGameMode.ScorePixel(iPixelID)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_SETUP and click.Click == true then
        bAnyButtonClick = true
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect
end
