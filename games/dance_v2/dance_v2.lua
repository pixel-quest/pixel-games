--[[
    Название: Танцы (Версия 2)
    Автор: Avondale, дискорд - avonda
    Описание механики: 
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
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 7,
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
    iPixelID = 0
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local bAnyButtonClick = false
local tPlayerInGame = {}

local tTeamColors = {}
tTeamColors[1] = CColors.BLUE
tTeamColors[2] = CColors.MAGENTA
tTeamColors[3] = CColors.CYAN
tTeamColors[4] = CColors.WHITE
tTeamColors[5] = CColors.YELLOW
tTeamColors[6] = CColors.GREEN

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

    local err = CAudio.PreloadFile("audio_v2/"..tGame["SongName"])
    if err ~= nil then error(err); end

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

        tGame.CenterX = AL.NFZ.iCenterX
        tGame.CenterY = AL.NFZ.iCenterY
    end

    tGame.StartPositions = {}
    tGame.StartPositionsSizeX = 4
    tGame.StartPositionsSizeY = tGame.iMaxY - tGame.iMinY + 1

    if tConfig.SmallZones then
        tGame.StartPositionsSizeY = math.floor(tGame.iMaxY/2) - math.floor(tGame.iMinY/2)
    end

    local iStartX = math.floor((tGame.Cols - (tGame.iMaxX-tGame.iMinX))/2) + tGame.iMinX

    local iX = iStartX
    local iY = tGame.iMinY
    for iPlayerID = 1, 6 do
        tGame.StartPositions[iPlayerID] = {}
        tGame.StartPositions[iPlayerID].X = iX
        tGame.StartPositions[iPlayerID].Y = iY
        tGame.StartPositions[iPlayerID].Color = tTeamColors[iPlayerID]

        iX = iX + tGame.StartPositionsSizeX + 1
        if iX + tGame.StartPositionsSizeX-1 > tGame.iMaxX then 
            iX = iStartX
            iY = iY + tGame.StartPositionsSizeY+1
            if iY > tGame.iMaxY then break; end
        end
    end

    CPixels.PIXEL_START_Y = tGame.StartPositionsSizeY

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
    SetGlobalColorBright(CColors.WHITE, tConfig.Bright-1)
    if not CGameMode.bCountDownStarted then SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true) end
    CPaint.PlayerZones()

    local iPlayersReady = 0

    for iPlayerID = 1, #tGame.StartPositions do
        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionsSizeX, tGame.StartPositionsSizeY) then
            tPlayerInGame[iPlayerID] = true

            tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
        elseif not CGameMode.bCountDownStarted then
            AL.NewTimer(250, function()
                if not CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionsSizeX, tGame.StartPositionsSizeY) and not CGameMode.bCountDownStarted then
                    tPlayerInGame[iPlayerID] = false
                    tGameStats.Players[iPlayerID].Color = CColors.NONE
                end
            end)
        end

        if tPlayerInGame[iPlayerID] then iPlayersReady = iPlayersReady + 1; end
    end

    if bAnyButtonClick or (iPlayersReady > 1 and CGameMode.bCanAutoStart) then
        bAnyButtonClick = false
        if iPlayersReady < 1 or CGameMode.bCountDownStarted then return; end

        CGameMode.StartCountDown(10)
    end

    tGameResults.PlayersCount = iPlayersReady
end

function GameTick()
    SetGlobalColorBright(CColors.WHITE, tConfig.Bright-2)
    SetAllButtonColorBright(CColors.NONE, 0, false)

    CPaint.PlayerZones()
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
CGameMode.bCanAutoStart = false
CGameMode.iWinnerID = 0

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("dance2/dance2_guide.mp3")
    CAudio.PlayVoicesSync("choose-color.mp3")

    AL.NewTimer(CAudio.GetVoicesDuration("dance2/dance2_guide.mp3") * 1000, function()
        CGameMode.bCanAutoStart = true
    end)
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

    CAudio.PlayDanceSync(tGame["SongName"])
    CGameMode.LoadSongPixels()

    AL.NewTimer(0, function()
        CPixels.PixelMovement()
        return tConfig.PixelMoveDelayMS
    end)

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        if tGameStats.StageLeftDuration <= 0 then
            CGameMode.EndGame()
            return nil
        end

        return 1000
    end)
end

CGameMode.EndGame = function()
    local iMaxScore = -1

    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] and tGameStats.Players[i] and tGameStats.Players[i].Score > iMaxScore then
            iMaxScore = tGameStats.Players[i].Score
            CGameMode.iWinnerID = i
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

CGameMode.LoadSongPixels = function()
    for iBatchID = 1, #tGame.Song do
        if tGame.Song[iBatchID] then
            AL.NewTimer(tConfig.SongStartDelayMS + (tGame.Song[iBatchID][1] + tConfig.PixelMoveDelayMS), function()
                CGameMode.SpawnBatch(iBatchID)
            end)

            if iBatchID > 1 and tGame.Song[iBatchID-1][1] + 500 < tGame.Song[iBatchID][1] then
                AL.NewTimer((tGame.Song[iBatchID-1][1] - tConfig.PixelMoveDelayMS + 250), function()
                    tGame.Song[-1] = {1, "H", "H", "H", "H"}
                    CGameMode.SpawnBatch(-1)
                end)                
            end

            if iBatchID == #tGame.Song then
                tGameStats.StageLeftDuration = math.floor(tGame.Song[iBatchID][1]/1000) + 10
            end
        end
    end
end

CGameMode.SpawnBatch = function(iBatchID)
    local iBatchPixelCount = 0
    for i = 2, #tGame.Song[iBatchID] do
        if tGame.Song[iBatchID][i] and tGame.Song[iBatchID][i] ~= "N" then
            iBatchPixelCount = iBatchPixelCount + 1

            local iPixelX = i
            CPixels.tPixelFactory[iPixelX] = nil

            local iPixelType = CPixels.PIXEL_TYPE_NORMAL
            if string.match(tGame.Song[iBatchID][i], "P" ) then
                iPixelType = CPixels.PIXEL_TYPE_LONG
            end

            local iVelX = 0
            --[[
            if iBatchPixelCount == 1 and i == #tGame.Song[iBatchID] and (math.random(1,100) >= 80) then
                iVelX = -1
            end
            ]]

            local iColor = CColors.GREEN
            local bBad = false

            if string.match(tGame.Song[iBatchID][i], "L") then
                iColor = CColors.GREEN
            elseif string.match(tGame.Song[iBatchID][i], "R") then
                iColor = CColors.YELLOW
            end

            if string.match(tGame.Song[iBatchID][i], "H") then
                iColor = CColors.RED
                bBad = true
            end

            CGameMode.SpawnPixelForAllPlayers(iPixelType, iPixelX, iVelX, iColor, bBad)
        end
    end
end

CGameMode.SpawnPixelForAllPlayers = function(iPixelType, iPixelX, iVelX, iColor, bBad)
    local iVelY = 1
    if CPixels.PIXEL_START_Y > tGame.StartPositionsSizeY/2 then iVelY = -1; end

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CPixels.SpawnPixel(iPlayerID, iPixelType, iPixelX, iVelX, iVelY, iColor, bBad)
        end
    end    
end

CGameMode.AddPlayerScore = function(iPlayerID, iScore)
    tGameResults.Score = tGameResults.Score + iScore
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScore 

    if tGameStats.TargetScore < tGameStats.Players[iPlayerID].Score then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end   
end
--//

--Song Pixels
CPixels = {}
CPixels.tPixels = {}
CPixels.tPixelFactory = {}

CPixels.PIXEL_START_Y = 0

CPixels.PIXEL_TYPE_NORMAL = 1
CPixels.PIXEL_TYPE_LONG = 2

CPixels.SpawnPixel = function(iPlayerID, iPixelType, iPixelX, iVelX, iVelY, iColor, bBad)
    local iPixelID = #CPixels.tPixels+1
    CPixels.tPixels[iPixelID] = {}
    CPixels.tPixels[iPixelID].iPlayerID = iPlayerID
    CPixels.tPixels[iPixelID].iX = tGame.StartPositions[iPlayerID].X + iPixelX-2
    CPixels.tPixels[iPixelID].iY = tGame.StartPositions[iPlayerID].Y + CPixels.PIXEL_START_Y -1
    CPixels.tPixels[iPixelID].iVelX = iVelX
    CPixels.tPixels[iPixelID].iVelY = iVelY

    CPixels.tPixels[iPixelID].iColor = iColor
    CPixels.tPixels[iPixelID].iPixelType = iPixelType
    CPixels.tPixels[iPixelID].bBad = bBad
    CPixels.tPixels[iPixelID].bCollected = false

    if iPixelType == CPixels.PIXEL_TYPE_LONG then
        CPixels.tPixelFactory[iPixelX] = {}
        CPixels.tPixelFactory[iPixelX].iVelX = iVelX
        CPixels.tPixelFactory[iPixelX].iColor = iColor
        CPixels.tPixelFactory[iPixelX].bBad = bBad
    end

    if CPixels.tPixels[iPixelID].iColor == tGame.StartPositions[iPlayerID].Color then
        CPixels.tPixels[iPixelID].iColor = CColors.BLUE
    end
end

CPixels.PixelMovement = function()
    for iPixelID = 1, #CPixels.tPixels do
        if CPixels.tPixels[iPixelID] then
            local iPlayerID = CPixels.tPixels[iPixelID].iPlayerID
            CPixels.tPixels[iPixelID].iY = CPixels.tPixels[iPixelID].iY + CPixels.tPixels[iPixelID].iVelY

            if CPixels.tPixels[iPixelID].iY > tGame.StartPositions[iPlayerID].Y-1 and CPixels.tPixels[iPixelID].iY <= tGame.StartPositions[iPlayerID].Y + tGame.StartPositionsSizeY-1 then
                if CPixels.tPixels[iPixelID].iVelX ~= 0 then
                    CPixels.tPixels[iPixelID].iX = CPixels.tPixels[iPixelID].iX + CPixels.tPixels[iPixelID].iVelX
                    if CPixels.tPixels[iPixelID].iX < tGame.StartPositions[iPlayerID].X or CPixels.tPixels[iPixelID].iX >= tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX then
                        CPixels.tPixels[iPixelID].iVelX = -CPixels.tPixels[iPixelID].iVelX
                        CPixels.tPixels[iPixelID].iX = CPixels.tPixels[iPixelID].iX + (CPixels.tPixels[iPixelID].iVelX*2)
                    end
                end

                if tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY].bClick and tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY].iWeight > 5 then
                    CPixels.PlayerCollectPixel(iPixelID)
                end
            else
                CPixels.tPixels[iPixelID] = nil
            end
        end
    end

    for iPixelFactoryID = 2, tGame.StartPositionsSizeX+1 do
        if CPixels.tPixelFactory[iPixelFactoryID] ~= nil then
            CGameMode.SpawnPixelForAllPlayers(CPixels.PIXEL_TYPE_NORMAL, iPixelFactoryID, CPixels.tPixelFactory[iPixelFactoryID].iVelX, CPixels.tPixelFactory[iPixelFactoryID].iColor, CPixels.tPixelFactory[iPixelFactoryID].bBad)
        end
    end
end

CPixels.PlayerCollectPixel = function(iPixelID)
    if CPixels.tPixels[iPixelID] and not CPixels.tPixels[iPixelID].bCollected then
        CPixels.tPixels[iPixelID].bCollected = true

        CPixels.tPixels[iPixelID].iColor = tGameStats.Players[CPixels.tPixels[iPixelID].iPlayerID].Color

        if not CPixels.tPixels[iPixelID].bBad then
            CGameMode.AddPlayerScore(CPixels.tPixels[iPixelID].iPlayerID, 1)
        else
            CGameMode.AddPlayerScore(CPixels.tPixels[iPixelID].iPlayerID, -5)
        end
    end
end
--//

--PAINT
CPaint = {}

CPaint.PlayerZones = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if iGameState == GAMESTATE_SETUP then
            for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX-1 do
                for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionsSizeY-1 do
                    tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
                    tFloor[iX][iY].iBright = tConfig.Bright

                    if not tPlayerInGame[iPlayerID] then
                        tFloor[iX][iY].iBright = tConfig.Bright-3
                    end
                end
            end

            if tPlayerInGame[iPlayerID] and tGameStats.StageLeftDuration > 0 and tGameStats.StageLeftDuration < 10 then
                local iStartX = tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX-1
                local iStartY = tGame.StartPositions[iPlayerID].Y + math.floor(tGame.StartPositionsSizeY/2) + 2
                local iX = iStartX
                local iY = iStartY

                for iLetterX = 1, tLoadedLetters[tGameStats.StageLeftDuration].iSizeX do
                    for iLetterY = 1, tLoadedLetters[tGameStats.StageLeftDuration].iSizeY do
                        
                        if tLoadedLetters[tGameStats.StageLeftDuration].tPaint[iLetterY][iLetterX] > 0 then
                            tFloor[iX][iY].iColor = CColors.RED
                            tFloor[iX][iY].iBright = tConfig.Bright
                        end

                        iY = iY-1
                    end
                    iX = iX - 1
                    iY = iStartY
                
                    if iX < tGame.StartPositions[iPlayerID].X then
                        iX = iStartX
                    end
                end
            end
        else
            for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX-1 do
                for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionsSizeY-1 do
                    tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
                    tFloor[iX][iY].iBright = 1

                    if not tPlayerInGame[iPlayerID] then
                        tFloor[iX][iY].iColor = CColors.NONE
                    end
                end
            end               
        end
    end
end

CPaint.Pixels = function()
    for iPixelID = 1, #CPixels.tPixels do
        if CPixels.tPixels[iPixelID] then
            if tFloor[CPixels.tPixels[iPixelID].iX] and tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY] then
                tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY].iColor = CPixels.tPixels[iPixelID].iColor
                tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY].iBright = tConfig.Bright
                tFloor[CPixels.tPixels[iPixelID].iX][CPixels.tPixels[iPixelID].iY].iPixelID = iPixelIDP
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

        if iGameState == GAMESTATE_GAME then
            if click.Click and not tFloor[click.X][click.Y].bDefect then
                if tFloor[click.X][click.Y].iPixelID and tFloor[click.X][click.Y].iPixelID > 0 then
                    CPixels.PlayerCollectPixel(tFloor[click.X][click.Y].iPixelID)
                end
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