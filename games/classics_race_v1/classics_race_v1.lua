--[[
    Название: Классики Эстафета
    Автор: Avondale, дискорд - avonda

    Описание механики:
        Эстафета кто соберет больше монет
        Чтобы начать нажмите кнопку

    В game.json можно выбрать направление бега: "left" или "right" в "Direction"


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
local GAMESTATE_TUTORIAL = 5

local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0
local bAnyButtonClick = false

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
    bAnimated = false,
}
local tButtonStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
}

local tTeamColor = {}
tTeamColor[1] = CColors.YELLOW
tTeamColor[2] = CColors.MAGENTA
tTeamColor[3] = CColors.CYAN
tTeamColor[4] = CColors.GREEN

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

    local iMinX = 1
    local iMinY = 1
    local iMaxX = tGame.Cols
    local iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        iMinX = AL.NFZ.iMinX
        iMinY = AL.NFZ.iMinY
        iMaxX = AL.NFZ.iMaxX
        iMaxY = AL.NFZ.iMaxY

        tGame.CenterX = AL.NFZ.iCenterX
        tGame.CenterY = AL.NFZ.iCenterY
    end

    tGame.StartPositions = {}
    tGame.StartPositionSizeX = math.floor(iMaxX*0.8) - iMinX
    tGame.StartPositionSizeY = 3

    if tGame.StartPositionOffsetX then
        tGame.StartPositionSizeX = tGame.StartPositionSizeX - tGame.StartPositionOffsetX
    end

    local iY = iMinY+1
    for iPlayerID = 1, tConfig.TeamCount do
        if iY <= iMaxY-tGame.StartPositionSizeY then
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = math.floor(iMaxX/10)+ iMinX
            tGame.StartPositions[iPlayerID].Y = iY

            iY = iY + tGame.StartPositionSizeY+2

            tGame.StartPositions[iPlayerID].Color = tTeamColor[iPlayerID]
            tGameStats.Players[iPlayerID].Color = tTeamColor[iPlayerID]
            CGameMode.tPlayerCanFinish[iPlayerID] = true
        end
    end

    if tConfig.TeamCount == 2 and #tGame.StartPositions == 2 then
        tGame.StartPositions[2].Y = iMaxY - tGame.StartPositionSizeY
    end

    tGameResults.PlayersCount = tConfig.PlayerCount

    CGameMode.InitGameMode()

    tGameStats.TargetScore = 1

    CAudio.PlayVoicesSyncFromScratch("classics-race/classics-race-game.mp3")
    CAudio.PlayVoicesSync("classics-race/classics-race-guide.mp3")
    --CAudio.PlaySync("voices/press-button-for-start.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("classics-race/classics-race-guide.mp3"))*1000 + 2000, function()
        CGameMode.bCanStart = true
    end)
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_TUTORIAL then
        TutorialTick()
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.PlayerZones()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    if bAnyButtonClick then
        bAnyButtonClick = false
        iGameState = GAMESTATE_TUTORIAL

        if tConfig.SkipTutorial then
            CTutorial.End()
        else
            CTutorial.Start()
        end
    end
end

function TutorialTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    if not CTutorial.bSkipDelayOn then SetAllButtonColorBright(CColors.GREEN, tConfig.Bright) end
    CPaint.PlayerZones()
    CPaint.Blocks()

    if bAnyButtonClick then
        bAnyButtonClick = false

        if not CTutorial.bSkipDelayOn then
            CTutorial.End()
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.PlayerZones()
    CPaint.Blocks()
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

--TUTORIAL
CTutorial = {}
CTutorial.iFinishCount = 0
CTutorial.bSkipDelayOn = true
CTutorial.bEnded = false

CTutorial.MAX_FINISH = 4

CTutorial.Start = function()
    CAudio.PlayVoicesSyncFromScratch("classics-race/classics-race-tutorial.mp3")

    AL.NewTimer(20000, function()
        if not CTutorial.bEnded then
            CTutorial.LoadMaps()
            CAudio.PlayRandomBackground()
        end
    end)

    AL.NewTimer(5000, function()
        CTutorial.bSkipDelayOn = false
    end)    
end

CTutorial.LoadMaps = function()
    CGameMode.bGameStarted = true
    CGameMode.LoadMapsForPlayers()
end

CTutorial.PlayerFinished = function(iPlayerID)
    CAudio.PlaySystemAsync(CAudio.STAGE_DONE)
    CBlock.ClearPlayerZone(iPlayerID)
    CMaps.LoadMapForPlayer(iPlayerID)
    CBlock.AnimateVisibility(iPlayerID)

    CTutorial.iFinishCount = CTutorial.iFinishCount + 1
    if CTutorial.iFinishCount == CTutorial.MAX_FINISH then
        CAudio.StopBackground()
        CAudio.PlayVoicesSyncFromScratch("classics-race/tutorial-end.mp3")

        AL.NewTimer(3000, function()
            CTutorial.End()
        end)
    end
end

CTutorial.End = function()
    CTutorial.bEnded = true
    CAudio.StopBackground()
    CBlock.tBlocks = {}
    CGameMode.bGameStarted = false
    iGameState = GAMESTATE_GAME
    CGameMode.CountDownNextRound()
end
--//

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = -1
CGameMode.iWinnerID = -1
CGameMode.bGameStarted = false
CGameMode.tPlayerSeeds = {}
CGameMode.tPlayerCanFinish = {}
CGameMode.iDefaultSeed = 1
CGameMode.bCanStart = false

CGameMode.iFinishPosition = 1

CGameMode.InitGameMode = function()
    if tGame.Direction == "right" then
        CGameMode.iFinishPosition = tGame.StartPositionSizeX
    elseif tGame.Direction == "left" then
        CGameMode.iFinishPosition = 1
    end
end

CGameMode.CountDownNextRound = function()
    CGameMode.bGameStarted = false
    CGameMode.iDefaultSeed = math.random(1,99999)

    CGameMode.iCountdown = tConfig.GameCountdown
    tGameStats.StageLeftDuration = CGameMode.iCountdown

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown
        
        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1

            CGameMode.Start()
            CAudio.PlayVoicesSync(CAudio.START_GAME)

            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1 

            return 1000
        end
    end)
end

CGameMode.Start = function()
    CAudio.PlayRandomBackground()
    tGameStats.StageLeftDuration = tConfig.GameLength
    CGameMode.bGameStarted = true
    CGameMode.LoadMapsForPlayers()

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

        if tGameStats.StageLeftDuration <= 0 then
            return CGameMode.EndGame()
        end

        if tGameStats.StageLeftDuration < 10 then
            CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
        end

        return 1000
    end)
end

CGameMode.LoadMapsForPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        CGameMode.tPlayerSeeds[iPlayerID] = CGameMode.iDefaultSeed
        CMaps.LoadMapForPlayer(iPlayerID)
        CBlock.AnimateVisibility(iPlayerID)
    end
end

CGameMode.PlayerRoundScoreAdd = function(iPlayerID, iScore)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScore

    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end

    CAudio.PlaySystemAsync(CAudio.CLICK);
end

CGameMode.PlayerScorePenalty = function(iPlayerID, iPenalty)
    if tGameStats.Players[iPlayerID].Score > 0 then 
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score - iPenalty
    end

    CAudio.PlaySystemAsync(CAudio.MISCLICK);
end

CGameMode.PlayerFinished = function(iPlayerID)
    if not CGameMode.tPlayerCanFinish[iPlayerID] then return; end
    CGameMode.tPlayerCanFinish[iPlayerID] = false

    CAudio.PlaySystemSync(CAudio.STAGE_DONE)
    CBlock.ClearPlayerZone(iPlayerID)
    CMaps.LoadMapForPlayer(iPlayerID)
    CBlock.AnimateVisibility(iPlayerID)

    AL.NewTimer(3000, function()
        CGameMode.tPlayerCanFinish[iPlayerID] = true
    end)
end

CGameMode.EndGame = function()
    local iMaxScore = -999

    for i = 1, #tGame.StartPositions do
        if tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
        elseif tGameStats.Players[i].Score == iMaxScore then
            CAudio.PlaySystemAsync("draw_overtime.mp3")
            tGameStats.StageLeftDuration = 10
            return 1000
        end
    end

    CAudio.StopBackground()
    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)    

    return nil
end
--//

--MAPS
CMaps = {}

CMaps.LoadMapForPlayer = function(iPlayerID)
    local tMap, fSeed = CMaps.GenerateRandomMapFromSeed(CGameMode.tPlayerSeeds[iPlayerID])
    CGameMode.tPlayerSeeds[iPlayerID] = fSeed

    local iMapX = 0
    local iMapY = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil then 
                iBlockType = tMap[iMapY][iMapX]
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
        end

        iMapX = 0
    end
end

CMaps.GenerateRandomMapFromSeed = function(fSeed)
    local tMap = {}
    local iPrevZoneCoinCount = 1

    for iX = 1, tGame.StartPositionSizeX do
        if iX == CGameMode.iFinishPosition then
            for iY = 1, tGame.StartPositionSizeY do
                if tMap[iY] == nil then tMap[iY] = {} end
                tMap[iY][iX] = CBlock.BLOCK_TYPE_FINISH
            end
        else
            local iCoinCount = 0
            local iMaxCoinCount = 0

            iMaxCoinCount, fSeed = CRandom.IntFromSeed(0, 3, fSeed)

            if iPrevZoneCoinCount == 0 and iMaxCoinCount == 0 then
                iMaxCoinCount = 2
            end
            iPrevZoneCoinCount = iMaxCoinCount

            for iY = 1, tGame.StartPositionSizeY do
                if tMap[iY] == nil then tMap[iY] = {} end

                local iBlockType = CBlock.BLOCK_TYPE_GROUND
                if iMaxCoinCount == 0 then
                    iBlockType = CBlock.BLOCK_TYPE_REDGROUND
                elseif iCoinCount < iMaxCoinCount then
                    iBlockType, fSeed = CRandom.IntFromSeed(1, 3, fSeed)

                    if iBlockType == CBlock.BLOCK_TYPE_GROUND then
                        if (tGame.StartPositionSizeY - iY) - (iMaxCoinCount - iCoinCount) < 0 then
                            iBlockType = CBlock.BLOCK_TYPE_COIN
                        end
                    end

                    if iBlockType == CBlock.BLOCK_TYPE_COIN then
                        iCoinCount = iCoinCount + 1
                    end
                end

                tMap[iY][iX] = iBlockType
            end
        end
    end

    return tMap, fSeed
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
    bVisible = false,
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_COIN = 2
CBlock.BLOCK_TYPE_FINISH = 3
CBlock.BLOCK_TYPE_REDGROUND = 4

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.WHITE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_FINISH]                   = CColors.GREEN
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_REDGROUND]                = CColors.RED

CBlock.RandomBlockType = function()
    local iBlockType = math.random(1,2)
    if iBlockType == 2 then iBlockType = 3 end

    return iBlockType
end

CBlock.NewBlock = function(iX, iY, iBlockType, iPlayerID)

    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iPlayerID = iPlayerID
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false
end

CBlock.RegisterBlockClick = function(iX, iY)
    if CBlock.tBlocks[iX][iY].bVisible == false then return; end

    local iPlayerID = CBlock.tBlocks[iX][iY].iPlayerID

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true

        if iGameState == GAMESTATE_GAME then
            CGameMode.PlayerRoundScoreAdd(iPlayerID, 1)
        elseif iGameState == GAMESTATE_TUTORIAL then
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    elseif (CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND or CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_REDGROUND) and CBlock.tBlocks[iX][iY].bCollected == false and tConfig.EnableMissPenalty then
        CBlock.tBlocks[iX][iY].bCollected = true

        if iGameState == GAMESTATE_GAME then
            CGameMode.PlayerScorePenalty(iPlayerID, 1)
        elseif iGameState == GAMESTATE_TUTORIAL then
            CAudio.PlaySystemAsync(CAudio.MISCLICK)
        end

        CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType])
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_FINISH then
        if iGameState == GAMESTATE_GAME then
            CGameMode.PlayerFinished(iPlayerID)
        elseif iGameState == GAMESTATE_TUTORIAL then
            CTutorial.PlayerFinished(iPlayerID)
        end
    end
end

CBlock.AnimateVisibility = function(iPlayerID)
    local iX = 1
    if tGame.Direction == "right" then
        iX = tGame.StartPositions[iPlayerID].X
    elseif tGame.Direction == "left" then
        iX = tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1
    end

    AL.NewTimer(CPaint.ANIMATION_DELAY, function()
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY do
            if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                CBlock.tBlocks[iX][iY].bVisible = true

                if tFloor[iX][iY].bClick or (tFloor[iX][iY].bDefect and CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN) then
                    CBlock.RegisterBlockClick(iX,iY)
                end
            end
        end

        if tGame.Direction == "right" then
            if iX < tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX then
                iX = iX + 1
                return CPaint.ANIMATION_DELAY
            end
        elseif tGame.Direction == "left" then
            if iX > tGame.StartPositions[iPlayerID].X then
                iX = iX - 1
                return CPaint.ANIMATION_DELAY
            end
        end

        return nil
    end)
end

CBlock.ClearPlayerZone = function(iPlayerID)
    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            CBlock.tBlocks[iX][iY] = nil
        end
    end
end
--//

--RANDOM
CRandom = {}

CRandom.fA = 45.0001
CRandom.fB = 1337.0000
CRandom.fM = 99.9999

CRandom.IntFromSeed = function(iMin, iMax, fSeed) -- возвращает iRand, fSeed
    local iRand, fSeed = CRandom.NextFromSeed(fSeed)

    return math.floor(iRand * (iMax-iMin) + iMin), fSeed
end

CRandom.NextFromSeed = function(fSeed)
    fSeed = (CRandom.fA * fSeed + CRandom.fB) % CRandom.fM
    return fSeed % 1, fSeed
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 75

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX][iY] and CBlock.tBlocks[iX][iY].bVisible then
                    if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                        tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                            --tFloor[iX][iY].iBright = CColors.BRIGHT15
                        end

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected then
                            tFloor[iX][iY].iBright = CColors.BRIGHT0
                        end
                    end
                end
            end
        end
    end
end

CPaint.PlayerZones = function()
    --if CGameMode.bGameStarted then return; end

    local iZonesClicked = 0
    for i = 1, #tGame.StartPositions do
        if CPaint.PlayerZone(i, tConfig.Bright) then
            iZonesClicked = iZonesClicked + 1
        end
    end

    if iGameState == GAMESTATE_SETUP and tConfig.AutoStart and iZonesClicked == #tGame.StartPositions and CGameMode.bCanStart then
        bAnyButtonClick = true
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    local iXStart = 1
    local iXEnd = 1
    local iXInc = 1
    if tGame.Direction == "right" then
        iXStart = tGame.StartPositions[iPlayerID].X-1
        iXEnd = 1
        iXInc = -1
    elseif tGame.Direction == "left" then
        iXStart = tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX
        iXEnd = tGame.Cols
        iXInc = 1
    end

    local bClick = false

    for iX = iXStart, iXEnd, iXInc do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY + tGame.StartPositions[iPlayerID].Y-1 do
            tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
            tFloor[iX][iY].iBright = iBright

            if tFloor[iX][iY].bClick then
                bClick = true
            end
        end
    end

    return bClick
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(CPaint.ANIMATION_DELAY, function()
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

function SetAllButtonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
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
            else
                AL.NewTimer(500, function()
                    tFloor[click.X][click.Y].bClick = false
                end)
            end

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and (iGameState == GAMESTATE_GAME or iGameState == GAMESTATE_TUTORIAL) and CGameMode.bGameStarted then
            if CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
                CBlock.RegisterBlockClick(click.X, click.Y)
            end
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_COIN then
            CBlock.RegisterBlockClick(defect.X, defect.Y)
        end
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if (iGameState == GAMESTATE_SETUP or iGameState == GAMESTATE_TUTORIAL) and click.Click == true then
        bAnyButtonClick = true
    end       
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect
end