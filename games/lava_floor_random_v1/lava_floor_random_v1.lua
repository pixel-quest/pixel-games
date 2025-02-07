--[[
    Название: пол это лава - генерация
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        игра пол это лава, но со случайно сгенерироваными уровнями
        в конфиге можно задать сид генерации, один и тот же сид = одна и та же серия уровней

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
        { Score = 0, Lives = 0, Color = CColors.GREEN },
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
    bAnimated = false,
    bProtectedFromLava = false,
    iCoinId = 0,
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
    --SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
    CPaint.GameSetup()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.GameField()
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
CGameMode.bRoundStarted = false

CGameMode.iMapCoinCount = 0
CGameMode.iMapCoinReq = 0
CGameMode.iMapCoinCollected = 0

CGameMode.tGameSetupCoins = {}
CGameMode.iGameSetupCollectedCoins = 0

CGameMode.iRoundTimeLimit = 60

CGameMode.InitGameMode = function()
    if tConfig.Seed ~= 0 then 
        math.randomseed(tonumber(tConfig.Seed))
    else
        local iSeed = math.random(1, tConfig.Seed_Max)
        math.randomseed(iSeed)
        --CLog.print("Seed: "..iSeed)
    end

    CMap.LoadGenConsts()
    CGameMode.GameSetupRandomCoins()

    tGameStats.TotalStages = tConfig.RoundCount
end

CGameMode.Announcer = function()
    --voice gamename and guide
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.GameSetupRandomCoins = function()
    for iCoin = 1, math.random(5,6) do
        local iX = math.random(1, tGame.Cols)
        local iY = math.random(1, tGame.Rows)

        if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect and tFloor[iX][iY].iCoinId == 0 then
            local iCoinId = #CGameMode.tGameSetupCoins+1
            CGameMode.tGameSetupCoins[iCoinId] = {}
            CGameMode.tGameSetupCoins[iCoinId].iX = iX
            CGameMode.tGameSetupCoins[iCoinId].iY = iY
            CGameMode.tGameSetupCoins[iCoinId].bCollected = false
            tFloor[iX][iY].iCoinId = iCoinId
        end
    end

    tGameStats.TargetScore = #CGameMode.tGameSetupCoins
end

CGameMode.PlayerCollectGameSetupCoin = function(iCoinId)
    CGameMode.tGameSetupCoins[iCoinId].bCollected = true
    CGameMode.iGameSetupCollectedCoins = CGameMode.iGameSetupCollectedCoins + 1

    tGameStats.Players[1].Score = tGameStats.Players[1].Score + 1

    if CGameMode.iGameSetupCollectedCoins == #CGameMode.tGameSetupCoins then
        CGameMode.EndGameSetup()
        CAudio.PlaySync(CAudio.STAGE_DONE)
    else
        CAudio.PlaySync(CAudio.CLICK)
    end
end

CGameMode.EndGameSetup = function()
    iGameState = GAMESTATE_GAME
    CGameMode.StartNextRoundCountDown(tConfig.RoundCountdown)
end

CGameMode.StartNextRoundCountDown = function(iCountDownTime)
    CMap.GenerateRandomMap()

    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            if tGameStats.StageNum == 0 then
                CGameMode.StartGame()
            end

            CGameMode.StartRound()
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlaySync(CAudio.START_GAME)
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    if bVictory then
        tGameResults.Won = true
        CAudio.PlaySync(CAudio.VICTORY)
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
        tGameResults.Color = CColors.GREEN
    else
        tGameResults.Won = false
        CAudio.PlaySync(CAudio.DEFEAT)
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)        
end

CGameMode.StartRound = function()
    CAudio.PlayRandomBackground()
    CGameMode.bRoundStarted = true

    tGameStats.Players[1].Score = 0
    tGameStats.TargetScore = CGameMode.iMapCoinReq

    tGameStats.StageLeftDuration = CGameMode.iRoundTimeLimit
    AL.NewTimer(1000, function()
        if CGameMode.bRoundStarted then
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        
            if tGameStats.StageLeftDuration <= 0 then
                if CGameMode.iMapCoinCollected >= CGameMode.iMapCoinReq then
                    CGameMode.EndRound()
                else
                    CGameMode.EndGame(false)
                end

                return nil;
            end

            return 1000
        end
    end)
    AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
        if not CGameMode.bRoundStarted then return nil; end

        CBlock.CalculateMovableObjects()

        return CPaint.ANIMATION_DELAY*4
    end)
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundStarted = false

    tGameResults.Score = tGameResults.Score + (tGameStats.StageLeftDuration*10) --+ ((tConfig.RoundTimeLimit_Max - tConfig.RoundTimeLimit)*4)

    tGameStats.StageLeftDuration = 0

    CBlock.Clear()

    tGameStats.Players[1].Score = tGameResults.Score
    tGameStats.TargetScore = tGameResults.Score

    if tGameStats.StageNum == tGameStats.TotalStages then
        CGameMode.EndGame(true)
    else
        tGameStats.StageNum = tGameStats.StageNum + 1
        CGameMode.StartNextRoundCountDown(tConfig.RoundCountdown)
    end
end

CGameMode.PlayerCollectCoin = function()
    CAudio.PlayAsync(CAudio.CLICK)

    CGameMode.iMapCoinCollected = CGameMode.iMapCoinCollected + 1
    tGameStats.Players[1].Score = tGameStats.Players[1].Score + 1
    tGameResults.Score = tGameResults.Score + 25
    tGameStats.CurrentStars = tGameResults.Score

    if CGameMode.iMapCoinCollected == CGameMode.iMapCoinReq then
        CAudio.PlayAsync(CAudio.STAGE_DONE)
        tGameStats.TargetScore = CGameMode.iMapCoinCount
    elseif CGameMode.iMapCoinCollected == CGameMode.iMapCoinCount then
        CAudio.PlayAsync(CAudio.STAGE_DONE)
        CGameMode.EndRound()
    end
end

CGameMode.PlayerCollectLava = function()
    CAudio.PlayAsync(CAudio.MISCLICK)
    tGameResults.Score = tGameResults.Score - 10 
    tGameStats.CurrentStars = tGameResults.Score
end
--//

--MAP
CMap = {}
CMap.LoadGenConsts = function()
    CMap.tGenerationConsts = {}
    CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM = 1
    CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN = 2
    CMap.tGenerationConsts.SAFEZONE_TYPE_MAX = 2

    CMap.tGenerationConsts.MAX_COIN_COUNT = (tGame.Cols + tGame.Rows)*2
    CMap.tGenerationConsts.COINGEN_TYPE_RANDOM = 1
    CMap.tGenerationConsts.COINGEN_TYPE_PATTERN = 2
    CMap.tGenerationConsts.COINGEN_TYPE_MAX = 2

    CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM = 1
    CMap.tGenerationConsts.MOVINGGEN_TYPE_PATH = 2
    CMap.tGenerationConsts.MOVINGGEN_TYPE_WALL = 3
    CMap.tGenerationConsts.MOVINGGEN_TYPE_MAX = 3
end

CMap.DefaultGenerationRules = function()
    CMap.tGenerationRules = {}
    CMap.tGenerationRules.bFullLavaGround = false
    CMap.tGenerationRules.bBigEdge = false

    CMap.tGenerationRules.iSmallSafeZoneMinCount = 2
    CMap.tGenerationRules.iSmallSafeZoneMaxCount = 4
    CMap.tGenerationRules.iMediumSafeZoneMinCount = 1
    CMap.tGenerationRules.iMediumSafeZoneMaxCount = 2

    CMap.tGenerationRules.iEdgeMinSize = 1
    CMap.tGenerationRules.iEdgeMaxSize = 3

    CMap.tGenerationRules.iSafeZoneType = 1

    CMap.tGenerationRules.iMovingGenType = 1

    CMap.tGenerationRules.iMovingBlocksMinCount = 1
    CMap.tGenerationRules.iMovingBlocksMaxCount = 2

    CMap.tGenerationRules.iCoinGenType = 1

    CMap.tGenerationRules.iSmallShapeFrom = 1
    CMap.tGenerationRules.iSmallShapeTo = #CShapes.tSmall
end

CMap.GenerateRules = function()
    while CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM and CMap.tGenerationRules.iCoinGenType == CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM do
        CMap.tGenerationRules.iSafeZoneType = math.random(1, CMap.tGenerationConsts.SAFEZONE_TYPE_MAX)
        CMap.tGenerationRules.iCoinGenType = math.random(1, CMap.tGenerationConsts.COINGEN_TYPE_MAX)
    end

    if math.random(1, 100) >= 60 then
        CMap.tGenerationRules.bBigEdge = true
        CMap.tGenerationRules.iSmallSafeZoneMinCount = 1
        CMap.tGenerationRules.iSmallSafeZoneMaxCount = 2
        CMap.tGenerationRules.iMediumSafeZoneMinCount = 0
        CMap.tGenerationRules.iMediumSafeZoneMaxCount = 1
    end

    if math.random(1,4) == 3 then
        CMap.tGenerationRules.bFullLavaGround = true
        CMap.tGenerationRules.iSmallSafeZoneMinCount = CMap.tGenerationRules.iSmallSafeZoneMinCount * 2
        CMap.tGenerationRules.iSmallSafeZoneMaxCount = CMap.tGenerationRules.iSmallSafeZoneMaxCount * 2
        CMap.tGenerationRules.iMediumSafeZoneMinCount = CMap.tGenerationRules.iMediumSafeZoneMinCount * 2
        CMap.tGenerationRules.iMediumSafeZoneMaxCount = CMap.tGenerationRules.iMediumSafeZoneMaxCount * 2
    end

    if CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
        CMap.tGenerationRules.iEdgeMinSize = 0
        CMap.tGenerationRules.iEdgeMaxSize = 1        
    end

    CMap.tGenerationRules.iSmallShapeFrom = math.random(1, #CShapes.tSmall-1)
    CMap.tGenerationRules.iSmallShapeTo = CMap.tGenerationRules.iSmallShapeFrom + 1
end

CMap.GenerateRandomMap = function()
    CMap.DefaultGenerationRules()
    CMap.GenerateRules()

    for iX = 1, tGame.Cols do
        CBlock.tBlockMovement[iX] = {}
        for iY = 1, tGame.Rows do
            if CMap.tGenerationRules.bFullLavaGround then
                CBlock.NewBlock(CBlock.LAYER_GROUND, iX, iY, CBlock.BLOCK_TYPE_LAVA)
            else
                CBlock.NewBlock(CBlock.LAYER_GROUND, iX, iY, CBlock.BLOCK_TYPE_GROUND)
            end

            CBlock.tBlockMovement[iX][iY] = false
        end
    end

    CMap.GeneateSafeGround()

    --[[
    if CMap.tGenerationRules.bFullLavaGround or math.random(1,100) <= 40 then
        CMap.GenerateRandomShapeChunks()
    else
        CBlock.NewBlockFormationFromShape(CBlock.LAYER_GROUND, math.random(1, tGame.Cols), math.random(1, tGame.Rows), CBlock.BLOCK_TYPE_LAVA, CShapes.GetRandomMediumShape())
    end
    ]]

    CMap.tGenerationRules.iMovingGenType = math.random(CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM, CMap.tGenerationConsts.MOVINGGEN_TYPE_PATH)
    if (CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_SAFEGROUND] < (tGame.Cols*6)) and CMap.tGenerationRules.bFullLavaGround or math.random(1, 100) > 50 then
        if CMap.tGenerationRules.iMovingGenType == CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM then
            if (CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA] or 0) < 100 then
                CMap.tGenerationRules.iMovingBlocksMaxCount = 5
            end
            CMap.GenerateRandomMovingObjects(CMap.tGenerationRules.bFullLavaGround)
        else
            CMap.GenerateMainPath()
            CMap.GeneratePathMovingObjects(CMap.tGenerationRules.bFullLavaGround)
        end
    elseif not CMap.tGenerationRules.bFullLavaGround and (CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA] or 0) < (tGame.Cols*5) then
        CMap.tGenerationRules.iMovingGenType = CMap.tGenerationConsts.MOVINGGEN_TYPE_WALL
        if math.random(1,100) <= 60 then
            CMap.GenerateMovingLavaWall(math.random(1,2))
        else
            CMap.GenerateMovingLavaWall(1)
            CMap.GenerateMovingLavaWall(2)
        end
    end 

    CMap.GenerateCoins()
    if CGameMode.iMapCoinCount < tGame.Cols then
        CMap.tGenerationRules.iCoinGenType = 1
        CMap.GenerateCoins()
    end

    CGameMode.iRoundTimeLimit = math.floor(CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_COIN] * tConfig.RoundTimePerCoin)

    --CLog.print("Total lavablocks: "..CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA])
    --CLog.print("Total safeblocks: "..CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_SAFEGROUND])

    --осторожно костыль
    if CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_SAFEGROUND] > (tGame.Rows*tGame.Cols*0.9) then
        CBlock.Clear()
        AL.NewTimer(1,function()
            CMap.GenerateRandomMap()
        end)
    end
    --
end

CMap.GeneateSafeGround = function()
    local function safeformation(iX, iY, tShape)
        CBlock.NewBlockFormationFromShape(CBlock.LAYER_SAFEGROUND, iX, iY, CBlock.BLOCK_TYPE_SAFEGROUND, tShape)
    end
    local function safeobject(iX, iY, tShape)
        return CBlock.NewObject(CBlock.LAYER_SAFEGROUND, iX, iY, CBlock.BLOCK_TYPE_SAFEGROUND, tShape)
    end
    local function safefill(iStartX, iStartY, iSizeX, iSizeY)
        for iX = iStartX, iStartX + iSizeX-1 do
            for iY = iStartY, iStartY + iSizeY-1 do
                if CBlock.IsValidPosition(iX, iY) then
                    CBlock.NewBlock(CBlock.LAYER_SAFEGROUND, iX, iY, CBlock.BLOCK_TYPE_SAFEGROUND)
                    --if iStartY > 1 and ((iSizeX > 1 and iSizeX < 5) or (iSizeY > 1 and iSizeY < 5)) then
                    --    CBlock.tBlockMovement[iX][iY] = true
                    --end
                end
            end
        end
    end

    if CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM then
        for iSmallShapeId = 1, math.random(CMap.tGenerationRules.iSmallSafeZoneMinCount, CMap.tGenerationRules.iSmallSafeZoneMaxCount) do
            local tShape = CShapes.GetRandomSmallShape(CMap.tGenerationRules.iSmallShapeFrom, CMap.tGenerationRules.iSmallShapeTo)
            local iShapeSizeX = #tShape
            local iShapeSizeY = #tShape[1]

            safeformation(math.random(1, tGame.Cols-iShapeSizeX), math.random(1, tGame.Rows-iShapeSizeY), tShape)
        end

        for iMediumShapeId = 1, math.random(CMap.tGenerationRules.iMediumSafeZoneMinCount,CMap.tGenerationRules.iMediumSafeZoneMaxCount) do
            local tShape = CShapes.GetRandomSmallShape(CMap.tGenerationRules.iSmallShapeFrom, CMap.tGenerationRules.iSmallShapeTo)
            local iShapeSizeX = #tShape
            local iShapeSizeY = #tShape[1]

            safeformation(math.random(1, tGame.Cols-iShapeSizeX), math.random(1, tGame.Rows-iShapeSizeY), tShape)       
        end
    elseif CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
        local tShape = CShapes.GetRandomSmallShape(CMap.tGenerationRules.iSmallShapeFrom, CMap.tGenerationRules.iSmallShapeTo)
        local iXInc = #tShape + math.random(1,#tShape)
        local iYInc = #tShape + math.random(1,#tShape[1])

        for iX = 1, tGame.Cols, iXInc do
            for iY = 1, tGame.Rows, iYInc do
                safeformation(iX, iY, tShape)
            end
        end
    end

    if CMap.tGenerationRules.bBigEdge then
        local function randomsize() return math.random(CMap.tGenerationRules.iEdgeMinSize,CMap.tGenerationRules.iEdgeMaxSize) end

        for iPos = 1, 6 do
            if math.random(1,100) >= 40 then
                if iPos == 1 then
                    safefill(1, 1, randomsize(), tGame.Rows)
                elseif iPos == 2 then
                    local iSizeX = randomsize()
                    safefill(tGame.Cols-iSizeX+1, 1, iSizeX, tGame.Rows) 
                elseif iPos == 3 then
                    safefill(1, 1, tGame.Cols, randomsize())
                elseif iPos == 4 then
                    local iSizeY = randomsize()
                    safefill(1, tGame.Rows-iSizeY+1, tGame.Cols, iSizeY)
                elseif iPos == 5 then
                    safefill(1, math.floor(tGame.Rows/2), tGame.Cols, randomsize())
                elseif iPos == 6 then
                    safefill(math.floor(tGame.Cols/2), 1, randomsize(), tGame.Rows)
                end
            end
        end
    end
end

CMap.GenerateRandomShapeChunks = function()
    local iBlockType = CBlock.BLOCK_TYPE_LAVA

    if CMap.tGenerationRules.bFullLavaGround then
        iBlockType = CBlock.BLOCK_TYPE_GROUND
    end

    for iChunkId = 1, math.random(1,6) do
        CBlock.NewBlockFormationFromShape(CBlock.LAYER_GROUND, math.random(1, tGame.Cols), math.random(1, tGame.Rows), iBlockType, CShapes.GetRandomMediumShape())
    end
end

CMap.GenerateRandomMovingObjects = function(bSafeground)
    local iLayer = CBlock.LAYER_MOVING_LAVA
    local iBlockType = CBlock.BLOCK_TYPE_LAVA
    local iLimit = nil
    if bSafeground then
        iLayer = CBlock.LAYER_MOVING_SAFEGROUND
        iBlockType = CBlock.BLOCK_TYPE_SAFEGROUND
        iLimit = 3
    end    

    local function randXY(iShapeSizeX, iShapeSizeY)
        local iX = 1
        local iY = 1

        repeat
            iX = math.random(1,tGame.Cols-iShapeSizeX)
            iY = math.random(1,tGame.Rows-iShapeSizeY)
        until CBlock.IsValidPosition(iX, iY)

        return iX, iY
    end

    for iMovingId = 1, math.random(CMap.tGenerationRules.iMovingBlocksMinCount, CMap.tGenerationRules.iMovingBlocksMaxCount) do
        local tShape = CShapes.GetRandomSmallShape(CMap.tGenerationRules.iSmallShapeFrom, CMap.tGenerationRules.iSmallShapeTo)
        local iX, iY = randXY(#tShape, #tShape[1])
        local iObjectId = CBlock.NewObject(iLayer, iX, iY, iBlockType, tShape)

        if math.random(1,100) <= 90 then
            if math.random(1,100) >= 50 then
                CBlock.tObjects[iLayer][iObjectId].iVelX = math.random(-1,1)
            else
                CBlock.tObjects[iLayer][iObjectId].iVelY = math.random(-1,1)
            end
        else
            CBlock.tObjects[iLayer][iObjectId].iVelX = math.random(-1,1)
            CBlock.tObjects[iLayer][iObjectId].iVelY = math.random(-1,1)
        end
        if CBlock.tObjects[iLayer][iObjectId].iVelX == 0 and CBlock.tObjects[iLayer][iObjectId].iVelY == 0 then CBlock.tObjects[iLayer][iObjectId].iVelX = 1 end
    end
end

CMap.GenerateMainPath = function()
    local iXOffset = math.random(1, math.floor(tGame.Rows/2.5))
    local iYOffset = math.random(1, math.floor(tGame.Cols/2.5))

    local tPoints = {}
    tPoints[1] = {iX = 1+iXOffset, iY = 1+iYOffset}
    tPoints[2] = {iX = tGame.Cols-iXOffset, iY = 1+iYOffset}
    tPoints[3] = {iX = tGame.Cols-iXOffset, iY = tGame.Rows-iYOffset}
    tPoints[4] = {iX = 1+iXOffset, iY = tGame.Rows-iYOffset}

    if math.random(1,100) > 50 then
        local tPointCopy = tPoints[4]
        tPoints[4] = tPoints[2]
        tPoints[2] = tPointCopy
    end

    CBlock.NewPath(tPoints)
end

CMap.GeneratePathMovingObjects = function(bSafeground)
    local iLayer = CBlock.LAYER_MOVING_LAVA
    local iBlockType = CBlock.BLOCK_TYPE_LAVA
    if bSafeground then
        iLayer = CBlock.LAYER_MOVING_SAFEGROUND
        iBlockType = CBlock.BLOCK_TYPE_SAFEGROUND
    end

    local iPathId = 1
    local tPath = CBlock.tPaths[iPathId]

    local tShape = CShapes.GetRandomSmallShape()

    for iPathObject = 1, #tPath do
        local iObjectId = CBlock.NewObject(iLayer, tPath[iPathObject].iX, tPath[iPathObject].iY, iBlockType, tShape)
        CBlock.tObjects[iLayer][iObjectId].iPathPoint = iPathObject        
        CBlock.tObjects[iLayer][iObjectId].iPathId = iPathId    
    end
end

CMap.GenerateMovingLavaWall = function(iDir)
    local iWallSize = math.random(1,3)

    local iStartX = math.random(1,tGame.Cols-iWallSize)
    local iStartY = math.random(1,tGame.Rows-iWallSize)

    local iSizeX = iWallSize
    local iSizeY = iWallSize

    local iVelX = 0
    local iVelY = 0

    if iDir == 1 then
        iStartX = 1
        iSizeX = tGame.Cols
        while iVelY == 0 do iVelY = math.random(-1,1) end
    else
        iStartY = 1
        iSizeY = tGame.Rows
        while iVelX == 0 do iVelX = math.random(-1,1) end
    end

    local tShape = {}
    for iShapeX = 1, iSizeX do
        tShape[iShapeX] = {}
        for iShapeY = 1, iSizeY do
            tShape[iShapeX][iShapeY] = 1
        end
    end   

    local iObjectId = CBlock.NewObject(CBlock.LAYER_MOVING_LAVA, iStartX, iStartY, CBlock.BLOCK_TYPE_LAVA, tShape)
    CBlock.tObjects[CBlock.LAYER_MOVING_LAVA][iObjectId].iVelX = iVelX
    CBlock.tObjects[CBlock.LAYER_MOVING_LAVA][iObjectId].iVelY = iVelY
end

CMap.GenerateCoins = function()
    local function PlaceCoin(iX, iY)
        if CGameMode.iMapCoinCount < CMap.tGenerationConsts.MAX_COIN_COUNT then
            if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect and CBlock.IsEmpty(CBlock.LAYER_COINS, iX, iY) and CBlock.IsEmpty(CBlock.LAYER_SAFEGROUND, iX, iY) then
                CBlock.NewBlock(CBlock.LAYER_COINS, iX, iY, CBlock.BLOCK_TYPE_COIN)
                CGameMode.iMapCoinCount = CGameMode.iMapCoinCount + 1    

                if CBlock.tBlocks[CBlock.LAYER_GROUND][iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA then
                    CBlock.tBlocks[CBlock.LAYER_GROUND][iX][iY].iBlockType = CBlock.BLOCK_TYPE_GROUND
                end        
            end
        end
    end

    if CMap.tGenerationRules.iCoinGenType == CMap.tGenerationConsts.COINGEN_TYPE_RANDOM then
        for iCoinId = 1, math.random(math.floor(CMap.tGenerationConsts.MAX_COIN_COUNT/2),math.floor(CMap.tGenerationConsts.MAX_COIN_COUNT*2)) do
            local iX = math.random(1, tGame.Cols)
            local iY = math.random(1, tGame.Rows)

            PlaceCoin(iX, iY)
        end
    elseif CMap.tGenerationRules.iCoinGenType == CMap.tGenerationConsts.COINGEN_TYPE_PATTERN then
        local tPattern = CShapes.GetRandomPattern()
        local iPatternSizeX = #tPattern
        local iPatternSizeY = #tPattern[1]

        local iPatternX = 0
        local iPatternY = 0

        local iStartX = math.random(1,math.floor(tGame.Cols/4))
        local iStartY =  math.random(1,math.floor(tGame.Rows/4))

        local iX = iStartX
        local iY = iStartY

        local iInc = math.random(0,3)

        for i = 1, 50 do
            for iPatternY = 1, iPatternSizeY do
                iY = iY + 1
                for iPatternX = 1, iPatternSizeX do
                    iX = iX + 1
                    if tPattern[iPatternX][iPatternY] > 0 then
                        PlaceCoin(iX, iY)
                    end     
                end
                iX = iStartX
            end

            iY = iY + iInc

            if iY >= tGame.Rows then 
                iY = iStartY
                iStartX = iStartX + iPatternSizeX + iInc
            end 
        end
    end

    CGameMode.iMapCoinReq = math.floor(CGameMode.iMapCoinCount/2)   
end
--//

--BLOCK
CBlock = {}

CBlock.tBlocks = {}
CBlock.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iBright = 0,
}

CBlock.tObjects = {}
CBlock.tObjectStructure = {
    iX = 0,
    iY = 0,
    iBlockType = 0,
    iBright = 0,
    tShape = {},
    iPathId = 0,
    iPathPoint = 1,
    iVelX = 0,
    iVelY = 0
}

CBlock.tPaths = {}

CBlock.tBlockMovement = {}

CBlock.LAYER_GROUND = 1
CBlock.LAYER_COINS = 2
CBlock.LAYER_MOVING_LAVA = 3
CBlock.LAYER_SAFEGROUND = 4
CBlock.LAYER_MOVING_SAFEGROUND = 5

CBlock.MAX_LAYER = 5

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_LAVA = 2
CBlock.BLOCK_TYPE_COIN = 3
CBlock.BLOCK_TYPE_SAFEGROUND = 4

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.NONE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA]                     = CColors.RED
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_SAFEGROUND]               = CColors.GREEN
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.LAYER_MOVING_SAFEGROUND]             = CColors.CYAN

CBlock.tBlocksCountPerType = {}

CBlock.NewBlock = function(iLayer, iX, iY, iBlockType)
    if CBlock.tBlocks[iLayer] == nil then CBlock.tBlocks[iLayer] = {} end
    if CBlock.tBlocks[iLayer][iX] == nil then CBlock.tBlocks[iLayer][iX] = {} end

    CBlock.tBlocks[iLayer][iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iLayer][iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iLayer][iX][iY].iBright = tConfig.Bright

    CBlock.tBlocksCountPerType[iBlockType] = (CBlock.tBlocksCountPerType[iBlockType] or 0) + 1
end

CBlock.NewObject = function(iLayer, iX, iY, iBlockType, tShape)
    if CBlock.tObjects[iLayer] == nil then CBlock.tObjects[iLayer] = {} end

    local iObjectId = #CBlock.tObjects[iLayer]+1
    CBlock.tObjects[iLayer][iObjectId] = CHelp.ShallowCopy(CBlock.tObjectStructure)
    CBlock.tObjects[iLayer][iObjectId].iBlockType = iBlockType
    CBlock.tObjects[iLayer][iObjectId].iX = iX
    CBlock.tObjects[iLayer][iObjectId].iY = iY
    CBlock.tObjects[iLayer][iObjectId].iBright = tConfig.Bright
    CBlock.tObjects[iLayer][iObjectId].tShape = tShape

    return iObjectId
end

CBlock.NewBlockFormationFromShape = function(iLayer, iStartX, iStartY, iBlockType, tShapeIn)
    local tShape = tShapeIn

    local iShapeX = 0
    local iShapeY = 0
    local iShapeSizeX = #tShape
    local iShapeSizeY = #tShape[1]

    for iX = iStartX, iStartX+iShapeSizeX-1 do
        iShapeX = iShapeX + 1
        for iY = iStartY, iStartY+iShapeSizeY-1 do
            iShapeY = iShapeY + 1
            if tShape[iShapeX][iShapeY] == 1 and CBlock.IsValidPosition(iX, iY) then
                CBlock.NewBlock(iLayer, iX, iY, iBlockType)
            end
        end
        iShapeY = 0
    end
end

CBlock.NewPath = function(tPoints)
    local iPathId = #CBlock.tPaths+1
    CBlock.tPaths[iPathId] = {}

    for iPathPoint = 1, #tPoints do
        CBlock.tPaths[iPathId][iPathPoint] = {}
        CBlock.tPaths[iPathId][iPathPoint].iX = tPoints[iPathPoint].iX
        CBlock.tPaths[iPathId][iPathPoint].iY = tPoints[iPathPoint].iY
    end
end

CBlock.RegisterBlockClick = function(iX, iY)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.bRoundStarted then return; end

    for iLayer = CBlock.MAX_LAYER, 1, -1 do 
        if CBlock.tBlocks[iLayer] and CBlock.tBlocks[iLayer][iX] and CBlock.tBlocks[iLayer][iX][iY] and not CBlock.tBlocks[iLayer][iX][iY].bCollected then
            if CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA and not tFloor[iX][iY].bProtectedFromLava and tFloor[iX][iY].iColor == CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA] then
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectLava()
                CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType])

                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN then
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectCoin()

                --[[tFloor[iX][iY].bProtectedFromLava = true
                AL.NewTimer(CPaint.ANIMATION_DELAY*10, function()
                    tFloor[iX][iY].bProtectedFromLava = false  
                end)]]
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                break;
            end
        end
    end
end

CBlock.LavaObjectClick = function(iX, iY)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.bRoundStarted or not CBlock.IsEmpty(CBlock.LAYER_SAFEGROUND, iX, iY) or tFloor[iX][iY].bProtectedFromLava --[[or (not CBlock.IsEmpty(CBlock.LAYER_COINS, iX, iY) and not CBlock.tBlocks[CBlock.LAYER_COINS][iX][iY].bCollected)]] then return; end

    CGameMode.PlayerCollectLava()
    CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA])    
end

CBlock.CalculateMovableObjects = function()
    for iLayer = 1, CBlock.MAX_LAYER do
        if CBlock.tObjects[iLayer] then
            for iObjectId = 1, #CBlock.tObjects[iLayer] do
                if CBlock.tObjects[iLayer][iObjectId] then
                    if CBlock.tObjects[iLayer][iObjectId].iPathId > 0 then
                        local tPath = CBlock.tPaths[CBlock.tObjects[iLayer][iObjectId].iPathId]
                        local tPathCurrentPoint = tPath[CBlock.tObjects[iLayer][iObjectId].iPathPoint]

                        local iXPlus = 0
                        if CBlock.tObjects[iLayer][iObjectId].iX < tPathCurrentPoint.iX then
                            iXPlus = 1
                        elseif CBlock.tObjects[iLayer][iObjectId].iX > tPathCurrentPoint.iX then
                            iXPlus = -1
                        end 
                        local iYPlus = 0
                        if CBlock.tObjects[iLayer][iObjectId].iY < tPathCurrentPoint.iY then
                            iYPlus = 1
                        elseif CBlock.tObjects[iLayer][iObjectId].iY > tPathCurrentPoint.iY then
                            iYPlus = -1
                        end 

                        if iXPlus == 0 and iYPlus == 0 then
                            CBlock.tObjects[iLayer][iObjectId].iPathPoint = CBlock.tObjects[iLayer][iObjectId].iPathPoint + 1
                            if not tPath[CBlock.tObjects[iLayer][iObjectId].iPathPoint] then CBlock.tObjects[iLayer][iObjectId].iPathPoint = 1 end
                        else
                            CBlock.tObjects[iLayer][iObjectId].iX = CBlock.tObjects[iLayer][iObjectId].iX + iXPlus
                            CBlock.tObjects[iLayer][iObjectId].iY = CBlock.tObjects[iLayer][iObjectId].iY + iYPlus
                        end
                    elseif (CBlock.tObjects[iLayer][iObjectId].iVelX ~= 0 or CBlock.tObjects[iLayer][iObjectId].iVelY ~= 0) then
                        CBlock.tObjects[iLayer][iObjectId].iX = CBlock.tObjects[iLayer][iObjectId].iX + CBlock.tObjects[iLayer][iObjectId].iVelX
                        CBlock.tObjects[iLayer][iObjectId].iY = CBlock.tObjects[iLayer][iObjectId].iY + CBlock.tObjects[iLayer][iObjectId].iVelY

                        local iNextX = CBlock.tObjects[iLayer][iObjectId].iX + CBlock.tObjects[iLayer][iObjectId].iVelX
                        local iNextY = CBlock.tObjects[iLayer][iObjectId].iY + CBlock.tObjects[iLayer][iObjectId].iVelY
                        if iNextX < 1 or iNextX + #CBlock.tObjects[iLayer][iObjectId].tShape-1 > tGame.Cols or (CBlock.tBlockMovement[iNextX] and CBlock.tBlockMovement[iNextX][iNextY]) then
                            CBlock.tObjects[iLayer][iObjectId].iVelX = -CBlock.tObjects[iLayer][iObjectId].iVelX
                        end
                        if iNextY < 1 or iNextY + #CBlock.tObjects[iLayer][iObjectId].tShape[1]-1 > tGame.Rows or (CBlock.tBlockMovement[iNextX] and CBlock.tBlockMovement[iNextX][iNextY]) then
                            CBlock.tObjects[iLayer][iObjectId].iVelY = -CBlock.tObjects[iLayer][iObjectId].iVelY
                        end                        
                    end
                end
            end
        end
    end
end

CBlock.IsValidPosition = function(iX, iY)
    return iX >= 1 and iX <= tGame.Cols and iY >= 1 and iY <= tGame.Rows
end

CBlock.IsEmpty = function(iLayer, iX, iY)
    return not CBlock.tBlocks[iLayer] or not CBlock.tBlocks[iLayer][iX] or not CBlock.tBlocks[iLayer][iX][iY]
end

CBlock.IsEmptyOnAllLayers = function(iX, iY)
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iLayer][iX] then
            for iY = 1, tGame.Rows do
                if CBlock.tBlocks[iLayer][iX][iY] and CBlock.tBlocks[iLayer][iX][iY].iBlockType ~= CBlock.BLOCK_TYPE_GROUND then
                    return false
                end
            end
        end
    end

    return true
end

CBlock.Clear = function()
    CGameMode.iMapCoinCount = 0
    CGameMode.iMapCoinReq = 0
    CGameMode.iMapCoinCollected = 0

    CBlock.tBlocks = {}   
    CBlock.tObjects = {} 
    CBlock.tPaths = {}
    CBlock.tBlocksCountPerType = {}
    CBlock.tBlockMovement = {}
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 100

CPaint.GameField = function()
    if CGameMode.bRoundStarted then
        CPaint.BlocksAndObjects()
    else
        CPaint.SafeZonePreview()
        CPaint.CountDown()   
    end
end

CPaint.GameSetup = function()
    for iCoinId = 1, #CGameMode.tGameSetupCoins do
        if not CGameMode.tGameSetupCoins[iCoinId].bCollected then
            tFloor[CGameMode.tGameSetupCoins[iCoinId].iX][CGameMode.tGameSetupCoins[iCoinId].iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]
            tFloor[CGameMode.tGameSetupCoins[iCoinId].iX][CGameMode.tGameSetupCoins[iCoinId].iY].iBright = tConfig.Bright
            tFloor[CGameMode.tGameSetupCoins[iCoinId].iX][CGameMode.tGameSetupCoins[iCoinId].iY].iCoinId = iCoinId
        end
    end
end

CPaint.CountDown = function()
    if CGameMode.iCountdown >= 0 and tGameStats.StageLeftDuration >= 0 then
        local tShape = CShapes.tNumbers[tGameStats.StageLeftDuration]
        if tShape then
            local iShapeX = 0
            local iShapeY = 0
            local iShapeSizeX = #tShape[1]
            local iShapeSizeY = #tShape

            local iXStart = math.ceil(tGame.Cols/2 - iShapeSizeX/2)
            local iYStart = math.floor(tGame.Rows/3)

            for iY = iYStart, iYStart+iShapeSizeY-1 do
                iShapeY = iShapeY + 1
                for iX = iXStart, iXStart+iShapeSizeX-1 do
                    iShapeX = iShapeX+1
                    if tShape[iShapeY][iShapeX] > 0 then
                        tFloor[iX][iY].iColor = CColors.WHITE
                        tFloor[iX][iY].iBright = tConfig.Bright + 2
                    end
                end
                iShapeX = 0
            end
        end
    end
end

CPaint.BlocksAndObjects = function()
    for iLayer = 1, CBlock.MAX_LAYER do
        if CBlock.tBlocks[iLayer] then
            CPaint.BlocksLayer(iLayer)
        end
        if CBlock.tObjects[iLayer] then
            CPaint.ObjectsLayer(iLayer)
        end
    end
end

CPaint.BlocksLayer = function(iLayer, iBrightOffset)
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iLayer][iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.IsValidPosition(iX, iY) and CBlock.tBlocks[iLayer][iX][iY] and not CBlock.tBlocks[iLayer][iX][iY].bCollected then
                    local iBright = CBlock.tBlocks[iLayer][iX][iY].iBright + (iBrightOffset or 0)
                    --if tFloor[iX][iY].iColor == CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA] and CBlock.tBlocks[CBlock.LAYER_GROUND][iX][iY].iBlockType ~= CBlock.BLOCK_TYPE_LAVA then iBright = iBright - 2 end

                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType]
                    tFloor[iX][iY].iBright = iBright
                end
            end
        end
    end
end

CPaint.ObjectsLayer = function(iLayer, iBrightOffset)
    for iObjectId = 1, #CBlock.tObjects[iLayer] do
        local tObject = CBlock.tObjects[iLayer][iObjectId]
        local tShape = tObject.tShape
        local iShapeSizeX = #tShape
        local iShapeSizeY = #tShape[1]
        local iShapeX = 0
        local iShapeY = 0

        for iX = tObject.iX, tObject.iX+iShapeSizeX-1 do
            iShapeX = iShapeX + 1
            for iY = tObject.iY, tObject.iY+iShapeSizeY-1 do
                iShapeY = iShapeY + 1
                if CBlock.IsValidPosition(iX, iY) and not tFloor[iX][iY].bAnimated and tShape[iShapeX][iShapeY] == 1 then
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[tObject.iBlockType]
                    tFloor[iX][iY].iBright = tObject.iBright + (iBrightOffset or 0)

                    if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                        if tObject.iBlockType == CBlock.BLOCK_TYPE_LAVA then
                            if tFloor[iX][iY].iWeight > 10 then
                                AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
                                    if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
                                        CBlock.LavaObjectClick(iX, iY)
                                    end
                                end)
                            end
                        end
                    end

                    if tObject.iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                        tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.LAYER_MOVING_SAFEGROUND]
                        tFloor[iX][iY].bProtectedFromLava = true
                        AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
                            tFloor[iX][iY].bProtectedFromLava = false  
                        end)
                    else
                        tFloor[iX][iY].bProtectedFromLava = false
                    end
                end
            end
            iShapeY = 0
        end
    end
end

CPaint.SafeZonePreview = function()
    local function checkandpaintblockslayer(iLayer)
        if CBlock.tBlocks[iLayer] then
            CPaint.BlocksLayer(iLayer, -2)
        end
    end
    local function checkandpaintobjectslayer(iLayer)
        if CBlock.tObjects[iLayer] then
            CPaint.ObjectsLayer(iLayer, -2)
        end
    end

    checkandpaintblockslayer(CBlock.LAYER_SAFEGROUND)
    checkandpaintblockslayer(CBlock.LAYER_MOVING_SAFEGROUND)
    checkandpaintobjectslayer(CBlock.LAYER_SAFEGROUND)
    checkandpaintobjectslayer(CBlock.LAYER_MOVING_SAFEGROUND)
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(CPaint.ANIMATION_DELAY*3, function()
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

--SHAPES
CShapes = {}

CShapes.RotateShape = function(tShapeIn)
    local tShapeOut = tShapeIn

    return tShapeOut
end

CShapes.GetRandomShapeFromTable = function(tTable, iFrom, iTo)
    local iLimit = iLimitIn
    if iFrom == nil or iFrom > #tTable or iFrom < 1 then iFrom = 1 end
    if iTo == nil or iTo > #tTable or iTo < 1 then iTo = #tTable end
    if iFrom > iTo then iFrom = 1 end
    return tTable[math.random(iFrom, iTo)]
end

CShapes.GetRandomSmallShape = function(iFrom, iTo)
    return CShapes.GetRandomShapeFromTable(CShapes.tSmall, iFrom, iTo)
end

CShapes.GetRandomMediumShape = function(iFrom, iTo)
    return CShapes.GetRandomShapeFromTable(CShapes.tMedium, iFrom, iTo)
end

CShapes.GetRandomPattern = function(iLimit)
    return CShapes.GetRandomShapeFromTable(CShapes.tPatterns, iFrom, iTo)
end

CShapes.tSmall = {}
CShapes.tSmall[1] =
{
    {1,1},
    {1,1},
}
CShapes.tSmall[2] =
{
    {1,1,1},
    {1,1,1},
    {1,1,1},
}
CShapes.tSmall[3] =
{
    {1,1},
    {1,1},
    {1,1},
}
CShapes.tSmall[4] =
{
    {1,1,1},
    {0,1,0},
    {1,1,1},
}
CShapes.tSmall[5] =
{
    {1,0,1},
    {1,1,1},
    {1,0,1},
}
CShapes.tSmall[6] =
{
    {0,1,0},
    {1,1,1},
    {0,1,0},
}
CShapes.tSmall[7] =
{
    {1,1,1},
}
CShapes.tSmall[8] =
{
    {1,1,1,1},
}
CShapes.tSmall[9] =
{
    {1,},
    {1,},
    {1,},
}
CShapes.tSmall[10] =
{
    {1,},
    {1,},
    {1,},
    {1,},
}

CShapes.tMedium = {}
CShapes.tMedium[1] = 
{
    {1,1,1,1,1},
    {1,1,1,1,1},
    {1,1,1,1,1},
    {1,1,1,1,1},
    {1,1,1,1,1},
}
CShapes.tMedium[2] = 
{
    {0,0,1,0,0},
    {0,1,1,1,0},
    {1,1,1,1,1},
    {0,1,1,1,0},
    {0,0,1,0,0},
}

CShapes.tMedium[3] =
{
    {0,0,1,0,0},
    {0,1,1,1,0},
    {1,1,1,1,1},
}
CShapes.tMedium[4] =
{
    {1,1,1,1,1},
    {0,1,1,1,0},
    {0,0,1,0,0},
}
CShapes.tMedium[5] =
{
    {0,0,1},
    {0,1,1},
    {1,1,1},
    {0,1,1},
    {0,0,1},
}
CShapes.tMedium[6] =
{
    {1,0,0},
    {1,1,0},
    {1,1,1},
    {1,1,0},
    {1,0,0},
}

CShapes.tPatterns = {}
CShapes.tPatterns[1] =
{
    {1,0,1},
    {0,1,0},
    {1,0,1},
}
CShapes.tPatterns[2] =
{
    {0,1,0},
    {1,0,1},
    {0,1,0},
}
CShapes.tPatterns[3] =
{
    {1,1},
    {1,1},
}
CShapes.tPatterns[4] =
{
    {0,1},
    {1,1},
}
CShapes.tPatterns[5] =
{
    {1,1},
    {1,0},
}
CShapes.tPatterns[6] =
{
    {0,1},
    {1,0},
}
CShapes.tPatterns[7] =
{
    {1,0,0,1},
    {0,1,1,0},
    {0,1,1,0},
    {1,0,0,1},
}

CShapes.tNumbers = {}
CShapes.tNumbers[0] = 
{
    {0,0,0,0,0},
    {0,0,0,0,0},
    {0,0,0,0,0},
    {0,0,0,0,0},
    {0,0,0,0,0},
    {0,0,0,0,0},
    {0,0,0,0,0},
    --[[{0,1,1,1,0,0,0,1,1,1,0},
    {1,0,0,0,1,0,1,0,0,0,1},
    {1,0,0,0,0,0,1,0,0,0,1},
    {1,0,0,1,1,0,1,0,0,0,1},
    {1,0,0,0,1,0,1,0,0,0,1},
    {1,0,0,0,1,0,1,0,0,0,1},
    {0,1,1,1,0,0,0,1,1,1,0},]]
}
CShapes.tNumbers[1] = 
{
    {0,0,1,0,0},
    {0,1,1,0,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
    {0,1,1,1,0},
}
CShapes.tNumbers[2] = 
{
    {0,1,1,1,0},
    {1,0,0,0,1},
    {0,0,0,0,1},
    {0,0,0,1,0},
    {0,0,1,0,0},
    {0,1,0,0,0},
    {1,1,1,1,1},
}
CShapes.tNumbers[3] = 
{
    {0,1,1,1,0},
    {1,0,0,0,1},
    {0,0,0,0,1},
    {0,1,1,1,0},
    {0,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
}
CShapes.tNumbers[4] = 
{
    {0,0,1,1,0},
    {0,1,0,1,0},
    {1,0,0,1,0},
    {1,1,1,1,1},
    {0,0,0,1,0},
    {0,0,0,1,0},
    {0,0,0,1,0},
}
CShapes.tNumbers[5] = 
{
    {1,1,1,1,1},
    {1,0,0,0,0},
    {1,1,1,1,0},
    {0,0,0,0,1},
    {0,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
}
CShapes.tNumbers[6] = 
{
    {0,1,1,1,0},
    {1,0,0,0,1},
    {1,0,0,0,0},
    {1,1,1,1,0},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
}
CShapes.tNumbers[7] = 
{
    {1,1,1,1,1},
    {0,0,0,0,1},
    {0,0,0,1,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
    {0,0,1,0,0},
}
CShapes.tNumbers[8] = 
{
    {0,1,1,1,0},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
}
CShapes.tNumbers[9] = 
{
    {0,1,1,1,0},
    {1,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,1},
    {0,0,0,0,1},
    {1,0,0,0,1},
    {0,1,1,1,0},
}
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                --tFloor[iX][iY].bProtectedFromLava = false
            end
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
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and not tFloor[click.X][click.Y].bDefect and click.Weight > 10 then
            if iGameState == GAMESTATE_SETUP then
                if tFloor[click.X][click.Y].iCoinId > 0 and not CGameMode.tGameSetupCoins[tFloor[click.X][click.Y].iCoinId].bCollected then
                    CGameMode.PlayerCollectGameSetupCoin(tFloor[click.X][click.Y].iCoinId)
                end
            else
                CBlock.RegisterBlockClick(click.X, click.Y)
            end
        end

    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
        tFloor[defect.X][defect.Y].bProtectedFromLava = true

        if iGameState == GAMESTATE_SETUP then
            if tFloor[click.X][click.Y].iCoinId > 0 and not CGameMode.tGameSetupCoins[tFloor[click.X][click.Y].iCoinId].bCollected then
                CGameMode.PlayerCollectGameSetupCoin(tFloor[click.X][click.Y].iCoinId)
            end
        else
            CBlock.RegisterBlockClick(defect.X, defect.Y)
        end
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_SETUP then
        --CGameMode.EndGameSetup()
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