--[[
    Название: Рефлекс/Реакция
    Автор: Avondale, дискорд - avonda
    Описание механики:
        У игроков на поле есть 6 цветов на выбор.
        После начала раунда спустя небольшой промежуток времени(каждый раз разный) объявляется цвет.
        Игрокам нужно нажать на этот цвет.
        Кто быстрее нажал на правильный цвет получит больше очков.
        Выигрывает тот кто по истечению всех раундов набрал больше очков.

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
    iPlayerID = 0
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tArenaPlayerReady = {}

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

    for iPlayerID = 1, #tGame.StartPositions do
        tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)

    local iPlayersReady = 0

    if tGame.ArenaMode then
        bAnyButtonClick = false
    end

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or CGameMode.bCountDownStarted and tPlayerInGame[iPos] then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)

            if tPlayerInGame[iPos] and tGame.ArenaMode then
                local iCenterX = tPos.X + math.floor(tGame.StartPositionSizeX/3)
                local iCenterY = tPos.Y + math.floor(tGame.StartPositionSizeY/3)

                local bArenaClick = false
                for iX = iCenterX, iCenterX+1 do
                    for iY = iCenterY, iCenterY+1 do
                        tFloor[iX][iY].iColor = 5
                        if tArenaPlayerReady[iPos] then
                            tFloor[iX][iY].iBright = tConfig.Bright+2
                        end

                        if tFloor[iX][iY].bClick then 
                            bArenaClick = true
                        end
                    end
                end

                if bArenaClick then
                    bAnyButtonClick = true 
                    tArenaPlayerReady[iPos] = true
                else
                    tArenaPlayerReady[iPos] = false
                end
            end            
        end
    end

    if bAnyButtonClick then
        if iPlayersReady > 0 and not CGameMode.bCountDownStarted then
            CGameMode.iPlayerCount = iPlayersReady
            tGameResults.PlayersCount = iPlayersReady
            CGameMode.StartCountDown(1)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)    
    CPaint.PlayerZones() 
    CPaint.TargetColor()
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

CGameMode.MAX_COLOR_COUNT = 6

CGameMode.iCountdown = 0
CGameMode.iPlayerCount = 0
CGameMode.iRountCount = 0
CGameMode.bRoundOn = false
CGameMode.bCountDownStarted = false

CGameMode.iBestScore = 0
CGameMode.iWinnerID = 1

CGameMode.iFinishedPlayerCount = 0
CGameMode.iCorrectlyFinishedPlayerCount = 0
CGameMode.tFinishedPlayer = {}
CGameMode.tPlayerCorrectColor = {}
CGameMode.tPlayerColorOffset = {}
CGameMode.tPlayerPosition = {}

CGameMode.tTargetPixelColor = {}

CGameMode.tColors = {}
CGameMode.tColors[1] = CColors.RED
CGameMode.tColors[2] = CColors.GREEN
CGameMode.tColors[3] = CColors.YELLOW
CGameMode.tColors[4] = CColors.BLUE
CGameMode.tColors[5] = CColors.MAGENTA
CGameMode.tColors[6] = CColors.CYAN
CGameMode.tColors[7] = CColors.WHITE

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = tConfig.RoundCount
end

CGameMode.Announcer = function()
    CAudio.PlaySync("reflex_gamename.mp3")
    CAudio.PlaySync("reflex_guide.mp3")
    CAudio.PlaySync("voices/choose-color.mp3")

    if tGame.ArenaMode then 
        CAudio.PlaySync("press-zone-for-start.mp3")
    else
        CAudio.PlaySync("voices/press-button-for-start.mp3")
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.iRountCount = CGameMode.iRountCount + 1
    tGameStats.StageNum = CGameMode.iRountCount
    CGameMode.bCountDownStarted = true

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if tGame.ArenaMode and CGameMode.iRountCount == 1 then
            if not bAnyButtonClick then
                CGameMode.bCountDownStarted = false      
                CGameMode.iRountCount = 0        
                return nil
            end
        end

        if CGameMode.iCountdown <= 0 then
            if CGameMode.iRountCount == 1 then
                CGameMode.StartGame()
            end
            
            CGameMode.StartNextRound()

            return nil
        else
            --CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    --CAudio.PlaySync(CAudio.START_GAME)
    iGameState = GAMESTATE_GAME
    CAudio.PlayRandomBackground()

    AL.NewTimer(250, function()
        if iGameState == GAMESTATE_GAME and CGameMode.tTargetPixelColor[1] == nil then
            for iPlayerID = 1,6 do
                CGameMode.PlayerFieldOffsetIncrement(iPlayerID)
            end
        end

        if iGameState >= GAMESTATE_POSTGAME then return nil end
        return 250
    end)
end

CGameMode.StartNextRound = function()
    CGameMode.bRoundOn = true

    CAudio.PlaySync("reflex_warning.mp3")

    AL.NewTimer(math.random(1,5)*1000, function()
        if CGameMode.bRoundOn then
            CGameMode.NewTargetPixelColor(math.random(1, tGame.PreviewHeight))
        end
    end)
end

CGameMode.NewTargetPixelColor = function(iColorCount)
    for i = 1, iColorCount do
        repeat CGameMode.tTargetPixelColor[i] = CGameMode.tColors[math.random(1,CGameMode.MAX_COLOR_COUNT)]
        until i == 1 or CGameMode.tTargetPixelColor[i] ~= CGameMode.tTargetPixelColor[i-1] 
        CAudio.PlaySyncColorSound(CGameMode.tTargetPixelColor[i])   
    end

    if iColorCount == 1 then
        tGameStats.TargetColor = CGameMode.tTargetPixelColor[1]
    end
end

CGameMode.PlayerHitPixelColor = function(iPlayerID, iColor)
    if CGameMode.tPlayerCorrectColor[iPlayerID] == nil then CGameMode.tPlayerCorrectColor[iPlayerID] = {}; CGameMode.tPlayerCorrectColor[iPlayerID].iColorCount = 0 end

    for i = 1, #CGameMode.tTargetPixelColor do
        if iColor == CGameMode.tTargetPixelColor[i] then
            if CGameMode.tPlayerCorrectColor[iPlayerID][iColor] == nil then
                CGameMode.tPlayerCorrectColor[iPlayerID][iColor] = true
                CGameMode.tPlayerCorrectColor[iPlayerID].iColorCount = CGameMode.tPlayerCorrectColor[iPlayerID].iColorCount + 1

                if CGameMode.tPlayerCorrectColor[iPlayerID].iColorCount == #CGameMode.tTargetPixelColor then
                    CGameMode.PlayerCorrectTarget(iPlayerID)
                    CGameMode.tFinishedPlayer[iPlayerID] = true
                
                    return true
                end

                return false
            else
                return false
            end
        end
    end
    
    CGameMode.PlayerWrongTarget(iPlayerID)
    CGameMode.tFinishedPlayer[iPlayerID] = false
    return true
end

CGameMode.EndRound = function()
    CGameMode.bRoundOn = false
    CGameMode.iFinishedPlayerCount = 0
    CGameMode.iCorrectlyFinishedPlayerCount = 0
    CGameMode.tFinishedPlayer = {}
    CGameMode.tPlayerCorrectColor = {}
    CGameMode.tTargetPixelColor = {}
    CGameMode.tPlayerPosition = {}
    tGameStats.TargetColor = CColors.NONE

    if CGameMode.iRountCount == tConfig.RoundCount then
        CGameMode.EndGame()
    else
        CGameMode.StartCountDown(tConfig.RoundCountdown)    
    end
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    tGameResults.Won = true
    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)    

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)       
end

CGameMode.PlayerClickPixel = function(iPlayerID, iColor)
    if CGameMode.tFinishedPlayer[iPlayerID] ~= nil then return; end

    if CGameMode.PlayerHitPixelColor(iPlayerID, iColor) then
        CGameMode.iFinishedPlayerCount = CGameMode.iFinishedPlayerCount + 1

        if CGameMode.iFinishedPlayerCount == CGameMode.iPlayerCount then
            AL.NewTimer(2000, function()
                CGameMode.EndRound()
            end)
        end
    end
end

CGameMode.PlayerCorrectTarget = function(iPlayerID)
    CAudio.PlayAsync(CAudio.CLICK)

    local iScoreIncrease = (CGameMode.iPlayerCount - CGameMode.iCorrectlyFinishedPlayerCount) * 2
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScoreIncrease

    CGameMode.iCorrectlyFinishedPlayerCount = CGameMode.iCorrectlyFinishedPlayerCount + 1

    CGameMode.tPlayerPosition[iPlayerID] = CGameMode.iCorrectlyFinishedPlayerCount

    if tGameStats.Players[iPlayerID].Score > CGameMode.iBestScore then
        CGameMode.iBestScore = tGameStats.Players[iPlayerID].Score
        CGameMode.iWinnerID = iPlayerID
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end
end

CGameMode.PlayerWrongTarget = function(iPlayerID)
    CAudio.PlayAsync(CAudio.MISCLICK)
end

CGameMode.PlayerFieldOffsetIncrement = function(iPlayerID)
    if CGameMode.tPlayerColorOffset[iPlayerID] == nil then CGameMode.tPlayerColorOffset[iPlayerID] = 0 end 
    CGameMode.tPlayerColorOffset[iPlayerID] = CGameMode.tPlayerColorOffset[iPlayerID] + 1
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

    if CGameMode.tPlayerPosition[iPlayerID] ~= nil then
        local tLetter = tLoadedLetters[CGameMode.tPlayerPosition[iPlayerID]]

        local iX = tGame.StartPositions[iPlayerID].X
        local iY = tGame.StartPositions[iPlayerID].Y-1

        for iLocalY = 1, tLetter.iSizeY do
            for iLocalX = 1, tLetter.iSizeX do
                if tLetter.tPaint[iLocalY][iLocalX] == 1 then
                    if tFloor[iX+iLocalX] and tFloor[iX+iLocalX][iY+iLocalY] then
                        tFloor[iX+iLocalX][iY+iLocalY].iColor = iColor
                        tFloor[iX+iLocalX][iY+iLocalY].iBright = iBright
                    end
                end
            end
        end
    else
        SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
            tGame.StartPositions[iPlayerID].Y, 
            tGame.StartPositionSizeX-1, 
            tGame.StartPositionSizeY-1, 
            iColor, 
            iBright)
    end

    if iGameState == GAMESTATE_GAME and CGameMode.tFinishedPlayer[iPlayerID] == nil then
        CPaint.PlayerZonePixels(iPlayerID, tConfig.Bright)
    end
end

CPaint.PlayerZonePixels = function(iPlayerID, iBright)
    for iY = tGame.StartPositions[iPlayerID].PixelsY, tGame.StartPositions[iPlayerID].PixelsY+1 do
        for iColor = 1, CGameMode.MAX_COLOR_COUNT do
            local iColorOff = iColor
            if CGameMode.tPlayerColorOffset[iPlayerID] then
                iColorOff = math.ceil((iColor + CGameMode.tPlayerColorOffset[iPlayerID]) % CGameMode.MAX_COLOR_COUNT)
                if iColorOff == 0 then iColorOff = CGameMode.MAX_COLOR_COUNT end
            end 

            local iX = tGame.StartPositions[iPlayerID].X + iColor-1
            if not tFloor[iX][iY].bDefect then
                local iColorBright = iBright
                if CGameMode.tPlayerCorrectColor[iPlayerID] and CGameMode.tPlayerCorrectColor[iPlayerID][iColorOff] == true then
                    iColorBright = 2
                end

                tFloor[iX][iY].iColor = CGameMode.tColors[iColorOff]
                tFloor[iX][iY].iBright = iColorBright
                tFloor[iX][iY].iPlayerID = iPlayerID
            end
        end
    end
end

CPaint.TargetColor = function()
    if #CGameMode.tTargetPixelColor < 1 then return; end

    local iYStart = tGame.PreviewY
    local iColor = 0
    for iY = iYStart, iYStart+tGame.PreviewHeight-1 do
        iColor = iColor + 1
        if iColor > #CGameMode.tTargetPixelColor then iColor = 1 end
        for iX = 1, tGame.Cols do
            tFloor[iX][iY].iColor = CGameMode.tTargetPixelColor[iColor]
            tFloor[iX][iY].iBright = tConfig.Bright
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

tLoadedLetters = {}

tLoadedLetters[1] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {0, 1, 0,},
        {1, 1, 0,},
        {0, 1, 0,},
        {0, 1, 0,},
        {1, 1, 1,}
    }
}

tLoadedLetters[2] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 1, 0, 0},
        {1, 1, 1, 1}
    }
}

tLoadedLetters[3] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[4] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 0, 1, 0},
        {0, 1, 1, 0},
        {1, 0, 1, 0},
        {1, 1, 1, 1},
        {0, 0, 1, 0}
    }
}

tLoadedLetters[5] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 1},
        {1, 1, 1, 0}
    }
}

tLoadedLetters[6] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[7] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 0, 1, 0}
    }
}

tLoadedLetters[8] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[9] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0}
    }
}