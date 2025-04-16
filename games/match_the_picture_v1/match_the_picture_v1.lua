--[[
    Название: Повтори Рисунок
    Автор: Avondale, дискорд - avonda

    Чтобы начать игру нужно:
        1 игрок - нажать на любую синюю кнопку
        Несколько игроков - встать на 2 или более зон и нажать любую синюю кнопку

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
    StageNum = 1,
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

    for iPlayerID = 1, #tGame.StartPositions do
        tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
    end    

    tGame.PreviewColor = tonumber(tGame.PreviewColor)
    CBlock.iColor = tGame.PreviewColor

    tGameResults.PlayersCount = tConfig.PlayerCount

    tGameStats.TotalStages = tConfig.RoundCount
    CGameMode.InitPlayers()
    CGameMode.AnnounceGameStart()
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
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    if #tGame.StartPositions == 1 then
        GameSetupTickSinglePlayer()
    else
        GameSetupTickMultiPlayer()
    end
end

function GameSetupTickSinglePlayer()
    for iX = math.floor(tGame.Cols/2)-1, math.floor(tGame.Cols/2) + 1 do
        for iY = math.floor(tGame.Rows/2), math.floor(tGame.Rows/2) + 2 do
            tFloor[iX][iY].iColor = CColors.BLUE
            tFloor[iX][iY].iBright = tConfig.Bright
            if tFloor[iX][iY].bClick then bAnyButtonClick = true; end
        end
    end

    if bAnyButtonClick then
        bAnyButtonClick = false

        tPlayerInGame[1] = true
        CGameMode.iAlivePlayerCount = 1

        iGameState = GAMESTATE_GAME
        CAudio.PlayVoicesSync("match-the-picture/match-the-picture-guide.mp3")
        CGameMode.StartNextRoundCountDown(tConfig.GameCountdown)
    end
end

function GameSetupTickMultiPlayer()
    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if iPlayersReady > 1 and (bAnyButtonClick or (tConfig.AutoStart and iPlayersReady == #tGame.StartPositions)) then
        bAnyButtonClick = false
        CGameMode.iAlivePlayerCount = iPlayersReady
        iGameState = GAMESTATE_GAME

        CAudio.PlaySyncFromScratch("")
        CAudio.PlayVoicesSync("match-the-picture/match-the-picture-guide.mp3")
        
        CGameMode.StartNextRoundCountDown(tConfig.GameCountdown)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Blocks()
    CPaint.FinishedPlayerZones()
    CPaint.Preview()
    CPaint.PlayersFrames()
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
CGameMode.iWinnerID = -1
CGameMode.iRound = 1
CGameMode.bRoundStarted = false
CGameMode.iPlayerCount = 1
CGameMode.iAlivePlayerCount = 0
CGameMode.tPlayerCoinsThisRound = {}
CGameMode.iFinishedCount = 0
CGameMode.tPlayerFinished = {}
CGameMode.tPlayerFieldScore = {}
CGameMode.bPlayerMovesCount = false

CGameMode.tMap = {}
CGameMode.iMapCoinCount = 0

CGameMode.InitPlayers = function()
    CGameMode.iPlayerCount = #tGame.StartPositions

    for iPlayerID = 1, CGameMode.iPlayerCount do
        tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
    end
end

CGameMode.AnnounceGameStart = function()
    CAudio.PlayVoicesSync("match-the-picture/match-the-picture.mp3")

    if #tGame.StartPositions > 1 then
        CAudio.PlayVoicesSync("choose-color.mp3")
    else
        CAudio.PlayVoicesSync("press-center-for-start.mp3")
    end
end

CGameMode.StartNextRoundCountDown = function(iCountDownTime)
    CGameMode.PrepareNextRound()

    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then

            if CGameMode.iRound == 1 then
                CGameMode.StartGame()
            end

            CGameMode.StartRound()
            
            return nil
        else
            if CGameMode.iCountdown <= 5 then
                CAudio.PlaySyncFromScratch("")
                CAudio.PlayLeftAudio(CGameMode.iCountdown)
            end
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlayVoicesSync(CAudio.START_GAME)

    if CGameMode.iPlayerCount == 1 then
        tGameStats.TargetScore = tConfig.RoundCount
    end
end

CGameMode.PrepareNextRound = function()
    CGameMode.tPlayerCoinsThisRound = {}
    CGameMode.iFinishedCount = 0
    CGameMode.tPlayerFinished = {}
    CGameMode.tPlayerFieldScore = {}

    CPaint.ResetAnimation()

    CBlock.tBlocks = {}
    CGameMode.tMap = CMaps.GetRandomMap()
    --CBlock.NewRandomColor()

    for iPlayerID = 1, CGameMode.iPlayerCount do
        if tPlayerInGame[iPlayerID] then 
            CMaps.LoadMapForPlayer(CGameMode.tMap, iPlayerID)
        end
    end

    CBlock.AnimateVisibility(true)
end

CGameMode.StartRound = function()
    CAudio.PlayRandomBackground()
    CGameMode.bRoundStarted = true

    CBlock.AnimateVisibility(false)
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundStarted = false
    CGameMode.bPlayerMovesCount = false

    if CGameMode.iRound == tGameStats.TotalStages then
        CGameMode.EndGame()
    else
        CGameMode.iRound = CGameMode.iRound + 1
        tGameStats.StageNum = CGameMode.iRound

        CGameMode.StartNextRoundCountDown(tConfig.RoundCountdown)
    end
end

CGameMode.EndGame = function()
    if CGameMode.iPlayerCount == 1 then
        if tGameStats.Players[1].Score > 0 then
            CAudio.PlayVoicesSync(CAudio.VICTORY)
            tGameResults.Won = true
            tGameResults.Color = CColors.GREEN
            CGameMode.iWinnerID = 1
        else
            CAudio.PlayVoicesSync(CAudio.DEFEAT)
            tGameResults.Won = false
            tGameResults.Color = CColors.RED
        end
    else
        local iMaxScore = -999

        for iPlayerID = 1, CGameMode.iPlayerCount do
            if tPlayerInGame[iPlayerID] and tGameStats.Players[iPlayerID].Score > iMaxScore then
                iMaxScore = tGameStats.Players[iPlayerID].Score
                CGameMode.iWinnerID = iPlayerID
            end
        end

        CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
        CAudio.PlayVoicesSync(CAudio.VICTORY)

        tGameResults.Won = true
        tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color
    end

    iGameState = GAMESTATE_POSTGAME

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)   

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
end

CGameMode.PlayerTouchedGround = function(iPlayerID, iX, iY)
    if CBlock.tBlocks[iX][iY].bVisible then
        CGameMode.AddPlayerFieldScore(iPlayerID, -1)
    else
        CGameMode.AddPlayerFieldScore(iPlayerID, 1)
    end
    CBlock.tBlocks[iX][iY].bVisible = not CBlock.tBlocks[iX][iY].bVisible

    CGameMode.CalculatePlayerField(iPlayerID)
end

CGameMode.PlayerTouchedMine = function(iPlayerID, iX, iY)
    if CBlock.tBlocks[iX][iY].bVisible then
        CGameMode.AddPlayerFieldScore(iPlayerID, 1)
    else
        CGameMode.AddPlayerFieldScore(iPlayerID, -1)
    end
    CBlock.tBlocks[iX][iY].bVisible = not CBlock.tBlocks[iX][iY].bVisible

    CGameMode.CalculatePlayerField(iPlayerID)
end

CGameMode.AddPlayerFieldScore = function(iPlayerID, iScorePlus)
    if CGameMode.tPlayerFieldScore[iPlayerID] == nil then
        CGameMode.tPlayerFieldScore[iPlayerID] = 0
    end

    CGameMode.tPlayerFieldScore[iPlayerID] = CGameMode.tPlayerFieldScore[iPlayerID] + iScorePlus
end

CGameMode.CalculatePlayerField = function(iPlayerID)
    --CLog.print("Player #"..iPlayerID.." Score: "..CGameMode.tPlayerFieldScore[iPlayerID]..", Target: "..CGameMode.iMapCoinCount)

    if CGameMode.tPlayerFieldScore[iPlayerID] == CGameMode.iMapCoinCount then
        CGameMode.PlayerFinish(iPlayerID)
    else
        CAudio.PlaySystemAsync(CAudio.CLICK)
    end
end

CGameMode.PlayerFinish = function(iPlayerID)
    CAudio.PlaySystemAsync(CAudio.STAGE_DONE)

    CGameMode.iFinishedCount = CGameMode.iFinishedCount + 1
    CGameMode.tPlayerFinished[iPlayerID] = true

    local iFinishBonusMultiplier = #tGame.StartPositions - CGameMode.iFinishedCount

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + (CGameMode.iAlivePlayerCount - (CGameMode.iFinishedCount-1))

    if (CGameMode.iPlayerCount > 1) and tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end

    if CGameMode.iFinishedCount == CGameMode.iAlivePlayerCount then
        CGameMode.EndRound()
    end    
end
--//

--MAPS
CMaps = {}
CMaps.iRandomMapID = 0
CMaps.iRandomMapIDIncrement = math.random(-2,2)

CMaps.GetRandomMap = function()
    if CMaps.iRandomMapID == 0 then 
        CMaps.iRandomMapID = math.random(1, #tGame.Maps)
    end
    if CMaps.iRandomMapIDIncrement == 0 then
        CMaps.iRandomMapIDIncrement = 1
    end

    CMaps.iRandomMapID = CMaps.iRandomMapID + CMaps.iRandomMapIDIncrement
    if CMaps.iRandomMapID > #tGame.Maps then
        CMaps.iRandomMapID = (CMaps.iRandomMapID-#tGame.Maps)
    elseif CMaps.iRandomMapID < 1 then
        CMaps.iRandomMapID = #tGame.Maps + (CMaps.iRandomMapID)
    end

    --CLog.print("random map #"..CMaps.iRandomMapID)

    return tGame.Maps[CMaps.iRandomMapID]
end

CMaps.LoadMapForPlayer = function(tMap, iPlayerID)
    local iMapX = 0
    local iMapY = 0
    local iBlockCount = 0
    local iCoinCount = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil then 
                iBlockType = tMap[iMapY][iMapX]
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
            iBlockCount = iBlockCount + 1

            if iBlockType == CBlock.BLOCK_TYPE_GROUND then
                iCoinCount = iCoinCount + 1
            end
        end

        iMapX = 0
    end

    CGameMode.iMapCoinCount = iCoinCount
end
--//

--BLOCK
CBlock = {}
CBlock.tBlocks = {}
CBlock.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iPlayerID = 0,
    iBright = 0,
    bVisible = true,
    bCooldown = false
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_MINE = 2

CBlock.iColor = CColors.NONE

CBlock.NewBlock = function(iX, iY, iBlockType, iPlayerID)
    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iPlayerID = iPlayerID
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false
end

CBlock.RegisterBlockClick = function(iX, iY)
    if not CGameMode.bRoundStarted then return; end
    if tFloor[iX][iY].bDefect then return; end
    if CBlock.tBlocks[iX][iY].bCooldown then return; end
    if not CGameMode.bPlayerMovesCount then return; end

    local iPlayerID = CBlock.tBlocks[iX][iY].iPlayerID

    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_MINE then
        CGameMode.PlayerTouchedMine(iPlayerID, iX, iY)
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
        CGameMode.PlayerTouchedGround(iPlayerID, iX, iY)
    end

    CBlock.tBlocks[iX][iY].bCooldown = true
    AL.NewTimer(tConfig.PixelClickCooldown, function()
        CBlock.tBlocks[iX][iY].bCooldown = false 
    end)
end

CBlock.AnimateVisibility = function(bVisible)
    for iPlayerID = 1, CGameMode.iPlayerCount do
        local iY = tGame.StartPositions[iPlayerID].Y

        AL.NewTimer(CPaint.ANIMATION_DELAY, function()
            for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX do
                if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                    CBlock.tBlocks[iX][iY].bVisible = bVisible

                    if bVisible == false and tFloor[iX][iY].bDefect and CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                        CGameMode.PlayerTouchedGround(CBlock.tBlocks[iX][iY].iPlayerID, iX, iY)
                    end
                end
            end

            if iY < tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY then
                iY = iY + 1
                return CPaint.ANIMATION_DELAY
            end
            CGameMode.bPlayerMovesCount = not bVisible
            return nil
        end)
    end
end

--[[
CBlock.NewRandomColor = function()
    CBlock.iColor = math.random(1,6)
end
]]
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                    if not CBlock.tBlocks[iX][iY].bVisible then
                        tFloor[iX][iY].iColor = CBlock.iColor
                        tFloor[iX][iY].iBright = CColors.BRIGHT0
                    else
                        tFloor[iX][iY].iColor = CBlock.iColor
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright
                    end
                end
            end
        end
    end
end

CPaint.Preview = function()
    if CGameMode.tMap == {} then return; end

    CPaint.PreviewBorder()

    local iMapX = 0
    local iMapY = 0

    for iY = tGame.PreviewPosY, tGame.StartPositionSizeY-1 + tGame.PreviewPosY  do
        iMapY = iMapY + 1

        for iX = tGame.PreviewPosX, tGame.StartPositionSizeX-1 + tGame.PreviewPosX do
            iMapX = iMapX + 1

            tFloor[iX][iY].iColor = CColors.NONE
            tFloor[iX][iY].iBright = CColors.BRIGHT15
            if CGameMode.tMap[iMapY] and CGameMode.tMap[iMapY][iMapX] and CGameMode.tMap[iMapY][iMapX] == CBlock.BLOCK_TYPE_GROUND then 
                tFloor[iX][iY].iColor = tGame.PreviewColor
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end

        iMapX = 0
    end    
end

CPaint.PreviewBorder = function()
    SetColColorBright({X = tGame.PreviewPosX, Y = tGame.PreviewPosY-1}, tGame.StartPositionSizeX-1, CBlock.iColor, 2)
    SetColColorBright({X = tGame.PreviewPosX, Y = tGame.PreviewPosY + tGame.StartPositionSizeY}, tGame.StartPositionSizeX-1, CBlock.iColor, 2)

    SetRowColorBright(tGame.PreviewPosX-1, tGame.PreviewPosY-1, tGame.StartPositionSizeY-1, CBlock.iColor, 2)
    SetRowColorBright(tGame.PreviewPosX+tGame.StartPositionSizeX, tGame.PreviewPosY-1, tGame.StartPositionSizeY-1, CBlock.iColor, 2)
end

CPaint.FinishedPlayerZones = function()
    for iPlayerID = 1, CGameMode.iPlayerCount do
        if tPlayerInGame[iPlayerID] and CGameMode.tPlayerFinished[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y do
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
        end
    end   
end

CPaint.PlayersFrames = function()
    for iPlayerID = 1, CGameMode.iPlayerCount do
        if tPlayerInGame[iPlayerID] then
            CPaint.PlayerFrame(iPlayerID, tConfig.Bright+1)
        end
    end    
end

CPaint.PlayerFrame = function(iPlayerID, iBright)
    SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y-1}, tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright)
    SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY}, tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright)

    SetRowColorBright(tGame.StartPositions[iPlayerID].X-1, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright)
    SetRowColorBright(tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright)
end

CPaint.ResetAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
        end
    end
end

--[[
CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    CTimer.New(CPaint.ANIMATION_DELAY*3, function()
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
            return CPaint.ANIMATION_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end
]]
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

function RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
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

function SetAllButtonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end

function SetRowColorBright(iStartX, iY, iSize, iColor, iBright)
    if iStartX < 1 or iStartX > tGame.Cols then return; end
    if iY + iSize+1 > tGame.Rows then return; end

    for i = 0, iSize do
        local iX = iStartX
        iY = iY + 1

        if not (iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetColColorBright(tStart, iSize, iColor, iBright)
    if tStart.X < 1 or tStart.X > tGame.Cols then return; end
    if tStart.Y < 1 or tStart.Y > tGame.Rows then return; end

    for i = 0, iSize do
        local iX = tStart.X + i
        local iY = tStart.Y

        if not (iX < 1 or iX > tGame.Cols) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
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
            else
                AL.NewTimer(500, function()
                    tFloor[click.X][click.Y].bClick = false
                end)
            end

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
            CBlock.RegisterBlockClick(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and not CBlock.tBlocks[defect.X][defect.Y].bVisible 
        and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_GROUND then    
            CGameMode.PlayerTouchedGround(CBlock.tBlocks[defect.X][defect.Y].iPlayerID, defect.X, defect.Y)
        end
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click then
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