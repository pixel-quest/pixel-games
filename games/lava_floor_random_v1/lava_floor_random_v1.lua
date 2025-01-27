--[[
    Название: пол это лава - генерация
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        игра пол это лава, но со случайно сгенерироваными уровнями
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
<<<<<<< Updated upstream
=======
    bProtectedFromLava = false,
>>>>>>> Stashed changes
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
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
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

CGameMode.InitGameMode = function()
<<<<<<< Updated upstream
=======
    if tConfig.Seed ~= 0 then math.randomseed(tonumber(tConfig.Seed)) end

>>>>>>> Stashed changes
    tGameStats.TotalStages = tConfig.RoundCount
end

CGameMode.Announcer = function()
    --voice gamename and guide
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.EndGameSetup = function()
    iGameState = GAMESTATE_GAME
    CGameMode.StartNextRoundCountDown(5)
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

    tGameStats.StageLeftDuration = tConfig.RoundTimeLimit
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
<<<<<<< Updated upstream
=======

    AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
        if not CGameMode.bRoundStarted then return nil; end

        CBlock.CalculateMovableObjects()

        return CPaint.ANIMATION_DELAY*4
    end)
>>>>>>> Stashed changes
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundStarted = false

    CGameMode.iMapCoinCount = 0
    CGameMode.iMapCoinReq = 0
    CGameMode.iMapCoinCollected = 0

<<<<<<< Updated upstream
=======
    tGameResults.Score = tGameResults.Score + (tGameStats.StageLeftDuration*10) + ((tConfig.RoundTimeLimit_Max - tConfig.RoundTimeLimit)*4)

>>>>>>> Stashed changes
    tGameStats.StageLeftDuration = 0

    CBlock.Clear()

    tGameStats.Players[1].Score = tGameResults.Score
    tGameStats.TargetScore = tGameResults.Score

    if tGameStats.StageNum == tGameStats.TotalStages then
        CGameMode.EndGame(true)
    else
        tGameStats.StageNum = tGameStats.StageNum + 1
        CGameMode.StartNextRoundCountDown(5)
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
<<<<<<< Updated upstream
CMap.tGenerationRules = {}
CMap.tGenerationConsts = {}

CMap.tGenerationRules.bFullLavaGround = false
CMap.tGenerationRules.bBigEdge = false

CMap.tGenerationRules.iSmallSafeZoneMinCount = 2
CMap.tGenerationRules.iSmallSafeZoneMaxCount = 4
CMap.tGenerationRules.iMediumSafeZoneMinCount = 1
CMap.tGenerationRules.iMediumSafeZoneMaxCount = 2

CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM = 1
CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN = 2
CMap.tGenerationConsts.SAFEZONE_TYPE_MAX = 2
CMap.tGenerationRules.iSafeZoneType = 1

CMap.GenerateRules = function()
    CMap.tGenerationRules.iSafeZoneType = math.random(1, CMap.tGenerationConsts.SAFEZONE_TYPE_MAX)
=======
CMap.tGenerationConsts = {}
CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM = 1
CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN = 2
CMap.tGenerationConsts.SAFEZONE_TYPE_MAX = 2

CMap.tGenerationConsts.MAX_COIN_COUNT = 80
CMap.tGenerationConsts.COINGEN_TYPE_RANDOM = 1
CMap.tGenerationConsts.COINGEN_TYPE_PATTERN = 2
CMap.tGenerationConsts.COINGEN_TYPE_MAX = 2

CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM = 1
CMap.tGenerationConsts.MOVINGGEN_TYPE_PATH = 2
CMap.tGenerationConsts.MOVINGGEN_TYPE_WALL = 3
CMap.tGenerationConsts.MOVINGGEN_TYPE_MAX = 3

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
end

CMap.GenerateRules = function()
    CMap.tGenerationRules.iSafeZoneType = math.random(1, CMap.tGenerationConsts.SAFEZONE_TYPE_MAX)
    CMap.tGenerationRules.iCoinGenType = math.random(1, CMap.tGenerationConsts.COINGEN_TYPE_MAX)
>>>>>>> Stashed changes

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
<<<<<<< Updated upstream
end

CMap.GenerateRandomMap = function()
=======

    if CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
        CMap.tGenerationRules.iEdgeMinSize = 0
        CMap.tGenerationRules.iEdgeMaxSize = 1        
    end
end

CMap.GenerateRandomMap = function()
    CMap.DefaultGenerationRules()
>>>>>>> Stashed changes
    CMap.GenerateRules()

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if CMap.tGenerationRules.bFullLavaGround then
                CBlock.NewBlock(CBlock.LAYER_GROUND, iX, iY, CBlock.BLOCK_TYPE_LAVA)
            else
                CBlock.NewBlock(CBlock.LAYER_GROUND, iX, iY, CBlock.BLOCK_TYPE_GROUND)
            end
        end
    end

    CMap.GeneateSafeGround()
    CMap.GenerateRandomShapeChunks()
<<<<<<< Updated upstream
    CMap.GenerateCoins()
=======

    CMap.tGenerationRules.iMovingGenType = math.random(CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM, CMap.tGenerationConsts.MOVINGGEN_TYPE_PATH)
    if CMap.tGenerationRules.bFullLavaGround or math.random(1, 100) > 50 then
        if CMap.tGenerationRules.iMovingGenType == CMap.tGenerationConsts.MOVINGGEN_TYPE_RANDOM then
            if CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA] < 100 then
                CMap.tGenerationRules.iMovingBlocksMaxCount = 5
            end
            CMap.GenerateRandomMovingObjects(CMap.tGenerationRules.bFullLavaGround)
        else
            CMap.GeneratePathMovingObjects(CMap.tGenerationRules.bFullLavaGround)
        end
    elseif not CMap.tGenerationRules.bFullLavaGround and CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA] < 150 then
        CMap.tGenerationRules.iMovingGenType = CMap.tGenerationConsts.MOVINGGEN_TYPE_WALL
        CMap.GenerateMovingLavaWall()
    end 

    CMap.GenerateCoins()
    if CGameMode.iMapCoinCount < 30 then
        CMap.tGenerationRules.iCoinGenType = 1
        CMap.GenerateCoins()
    end

    CLog.print("Total lavablocks: "..CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_LAVA])
    CLog.print("Total safeblocks: "..CBlock.tBlocksCountPerType[CBlock.BLOCK_TYPE_SAFEGROUND])
>>>>>>> Stashed changes
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
                end
            end
        end
    end

<<<<<<< Updated upstream
    if CMap.tGenerationRules.iSafeZoneType ~= CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
=======
    if CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_RANDOM then
>>>>>>> Stashed changes
        for iSmallShapeId = 1, math.random(CMap.tGenerationRules.iSmallSafeZoneMinCount, CMap.tGenerationRules.iSmallSafeZoneMaxCount) do
            local tShape = CShapes.GetRandomSmallShape()
            local iShapeSizeX = #tShape
            local iShapeSizeY = #tShape[1]

            safeformation(math.random(1, tGame.Cols-iShapeSizeX), math.random(1, tGame.Rows-iShapeSizeY), tShape)
        end

        for iMediumShapeId = 1, math.random(CMap.tGenerationRules.iMediumSafeZoneMinCount,CMap.tGenerationRules.iMediumSafeZoneMaxCount) do
            local tShape = CShapes.GetRandomSmallShape()
            local iShapeSizeX = #tShape
            local iShapeSizeY = #tShape[1]

            safeformation(math.random(1, tGame.Cols-iShapeSizeX), math.random(1, tGame.Rows-iShapeSizeY), tShape)       
        end
    elseif CMap.tGenerationRules.iSafeZoneType == CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
        local tShape = CShapes.GetRandomSmallShape()

<<<<<<< Updated upstream
        local iXInc = #CShapes.tSmall + math.random(-#CShapes.tSmall+2,2)
        local iYInc = #CShapes.tSmall[1] + math.random(0,2)
=======
        local iXInc = #tShape + math.random(0,#tShape)
        local iYInc = #tShape + math.random(0,#tShape[1])
>>>>>>> Stashed changes

        for iX = 1, tGame.Cols, iXInc do
            for iY = 1, tGame.Rows, iYInc do
                safeformation(iX, iY, tShape)
            end
        end
    end

    if CMap.tGenerationRules.bBigEdge then
<<<<<<< Updated upstream
        local iSizeX = math.random(1,3)
        local iSizeY = math.random(1,3)
=======
        local function randomsize() return math.random(CMap.tGenerationRules.iEdgeMinSize,CMap.tGenerationRules.iEdgeMaxSize) end
>>>>>>> Stashed changes

        for iPos = 1, 6 do
            if math.random(1,100) >= 40 then
                if iPos == 1 then
<<<<<<< Updated upstream
                    safefill(1, 1, iSizeX, tGame.Rows)
                elseif iPos == 2 then
                    safefill(tGame.Cols-iSizeX+1, 1, iSizeX, tGame.Rows) 
                elseif iPos == 3 then
                    safefill(1, 1, tGame.Cols, iSizeY)
                elseif iPos == 4 then
                    safefill(1, tGame.Rows-iSizeY+1, tGame.Cols, iSizeY)
                elseif iPos == 5 then
                    safefill(1, math.floor(tGame.Rows/2), tGame.Cols, iSizeY)
                elseif iPos == 6 then
                    safefill(math.floor(tGame.Cols/2), 1, iSizeX, tGame.Rows)
=======
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
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
    for iChunkId = 1, math.random(3,6) do
=======
    for iChunkId = 1, math.random(1,6) do
>>>>>>> Stashed changes
        CBlock.NewBlockFormationFromShape(CBlock.LAYER_GROUND, math.random(1, tGame.Cols), math.random(1, tGame.Rows), iBlockType, CShapes.GetRandomMediumShape())
    end
end

<<<<<<< Updated upstream
CMap.GenerateCoins = function()
    for iCoinId = 1, math.random(20,30) do
        local iX = math.random(1, tGame.Cols)
        local iY = math.random(1, tGame.Rows)

        if not tFloor[iX][iY].bDefect and CBlock.IsEmpty(CBlock.LAYER_COINS, iX, iY) and CBlock.IsEmpty(CBlock.LAYER_SAFEGROUND, iX, iY) then
            CBlock.NewBlock(CBlock.LAYER_COINS, iX, iY, CBlock.BLOCK_TYPE_COIN)
            CGameMode.iMapCoinCount = CGameMode.iMapCoinCount + 1
=======
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
        local tShape = CShapes.GetRandomSmallShape(iLimit)
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

CMap.GeneratePathMovingObjects = function(bSafeground)  
    
end

CMap.GenerateMovingLavaWall = function()
    local iWallSize = math.random(1,3)

    local iStartX = math.random(1,tGame.Cols-iWallSize)
    local iStartY = math.random(1,tGame.Rows-iWallSize)

    local iSizeX = iWallSize
    local iSizeY = iWallSize

    local iVelX = 0
    local iVelY = 0

    if math.random(1,2) == 1 then
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

        local iStartX = math.random(1,math.floor(tGame.Cols/2))
        local iStartY =  math.random(1,math.floor(tGame.Rows/2))

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
>>>>>>> Stashed changes
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
    iPathPoint = 0,
    iVelX = 0,
    iVelY = 0
}

CBlock.tPaths = {}

CBlock.LAYER_GROUND = 1
CBlock.LAYER_MOVING_LAVA = 2
CBlock.LAYER_SAFEGROUND = 3
CBlock.LAYER_MOVING_SAFEGROUND = 4
CBlock.LAYER_COINS = 5
CBlock.LAYER_MOVING_COINS = 6

CBlock.MAX_LAYER = 6

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_LAVA = 2
CBlock.BLOCK_TYPE_COIN = 3
CBlock.BLOCK_TYPE_SAFEGROUND = 4

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.NONE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA]                     = CColors.RED
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_SAFEGROUND]               = CColors.GREEN

<<<<<<< Updated upstream
=======
CBlock.tBlocksCountPerType = {}

>>>>>>> Stashed changes
CBlock.NewBlock = function(iLayer, iX, iY, iBlockType)
    if CBlock.tBlocks[iLayer] == nil then CBlock.tBlocks[iLayer] = {} end
    if CBlock.tBlocks[iLayer][iX] == nil then CBlock.tBlocks[iLayer][iX] = {} end

    CBlock.tBlocks[iLayer][iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iLayer][iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iLayer][iX][iY].iBright = tConfig.Bright
<<<<<<< Updated upstream
=======

    CBlock.tBlocksCountPerType[iBlockType] = (CBlock.tBlocksCountPerType[iBlockType] or 0) + 1
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
=======
CBlock.NewPath = function(...)
    
end

>>>>>>> Stashed changes
CBlock.RegisterBlockClick = function(iX, iY)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.bRoundStarted then return; end

    for iLayer = CBlock.MAX_LAYER, 1, -1 do 
        if CBlock.tBlocks[iLayer] and CBlock.tBlocks[iLayer][iX] and CBlock.tBlocks[iLayer][iX][iY] and not CBlock.tBlocks[iLayer][iX][iY].bCollected then
            if CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN then
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectCoin()
<<<<<<< Updated upstream
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA then
=======

                tFloor[iX][iY].bProtectedFromLava = true
                AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
                    tFloor[iX][iY].bProtectedFromLava = false  
                end)
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA and not tFloor[iX][iY].bProtectedFromLava and tFloor[iX][iY].iColor == CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA] then
>>>>>>> Stashed changes
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectLava()
                CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType])
            end
        end
    end
end

<<<<<<< Updated upstream
=======
CBlock.LavaObjectClick = function(iX, iY)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.bRoundStarted or tFloor[iX][iY].bProtectedFromLava or not CBlock.IsEmpty(CBlock.LAYER_COINS, iX, iY) then return; end

    CGameMode.PlayerCollectLava()
    CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA])    
end

CBlock.CalculateMovableObjects = function()
    for iLayer = 1, CBlock.MAX_LAYER do
        if CBlock.tObjects[iLayer] then
            for iObjectId = 1, #CBlock.tObjects[iLayer] do
                if CBlock.tObjects[iLayer][iObjectId] then
                    if CBlock.tObjects[iLayer][iObjectId].iPathId > 0 then

                    elseif (CBlock.tObjects[iLayer][iObjectId].iVelX ~= 0 or CBlock.tObjects[iLayer][iObjectId].iVelY ~= 0) then
                        CBlock.tObjects[iLayer][iObjectId].iX = CBlock.tObjects[iLayer][iObjectId].iX + CBlock.tObjects[iLayer][iObjectId].iVelX
                        CBlock.tObjects[iLayer][iObjectId].iY = CBlock.tObjects[iLayer][iObjectId].iY + CBlock.tObjects[iLayer][iObjectId].iVelY

                        local iNextX = CBlock.tObjects[iLayer][iObjectId].iX + CBlock.tObjects[iLayer][iObjectId].iVelX
                        local iNextY = CBlock.tObjects[iLayer][iObjectId].iY + CBlock.tObjects[iLayer][iObjectId].iVelY
                        if iNextX < 1 or iNextX + #CBlock.tObjects[iLayer][iObjectId].tShape-1 > tGame.Cols then
                            CBlock.tObjects[iLayer][iObjectId].iVelX = -CBlock.tObjects[iLayer][iObjectId].iVelX
                        end
                        if iNextY < 1 or iNextY + #CBlock.tObjects[iLayer][iObjectId].tShape[1]-1 > tGame.Rows then
                            CBlock.tObjects[iLayer][iObjectId].iVelY = -CBlock.tObjects[iLayer][iObjectId].iVelY
                        end                        
                    end
                end
            end
        end
    end
end

>>>>>>> Stashed changes
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
    CBlock.tBlocks = {}   
    CBlock.tObjects = {} 
    CBlock.tPaths = {}
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

CPaint.CountDown = function()
<<<<<<< Updated upstream
    if CGameMode.iCountdown >= 0 then
        local tShape = CShapes.tNumbers[CGameMode.iCountdown]
=======
    if CGameMode.iCountdown >= 0 and tGameStats.StageLeftDuration >= 0 then
        local tShape = CShapes.tNumbers[tGameStats.StageLeftDuration]
>>>>>>> Stashed changes
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
                        tFloor[iX][iY].iBright = 7
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
<<<<<<< Updated upstream
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType]
                    tFloor[iX][iY].iBright = CBlock.tBlocks[iLayer][iX][iY].iBright + (iBrightOffset or 0)
=======
                    local iBright = CBlock.tBlocks[iLayer][iX][iY].iBright + (iBrightOffset or 0)
                    if tFloor[iX][iY].iColor ~= CColors.NONE then iBright = iBright - 1 end

                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType]
                    tFloor[iX][iY].iBright = iBright
>>>>>>> Stashed changes
                end
            end
        end
    end
end

CPaint.ObjectsLayer = function(iLayer, iBrightOffset)
    for iObjectId = 1, #CBlock.tObjects[iLayer] do
        local tObject = CBlock.tObjects[iLayer][iObjectId]
<<<<<<< Updated upstream
        local iShapeSizeX = #tObject.tShape
        local iShapeSizeY = #tObject.tShape[1]
=======
        local tShape = tObject.tShape
        local iShapeSizeX = #tShape
        local iShapeSizeY = #tShape[1]
>>>>>>> Stashed changes
        local iShapeX = 0
        local iShapeY = 0

        for iX = tObject.iX, tObject.iX+iShapeSizeX-1 do
            iShapeX = iShapeX + 1
            for iY = tObject.iY, tObject.iY+iShapeSizeY-1 do
                iShapeY = iShapeY + 1
<<<<<<< Updated upstream
                if not tFloor[iX][iY].bAnimated and CBlock.IsValidPosition(iX, iY) and tShape[iShapeX][iShapeY] == 1 then
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[tObject.iBlockType]
                    tFloor[iX][iY].iBright = tObject.iBright + (iBrightOffset or 0)
=======
                if CBlock.IsValidPosition(iX, iY) and not tFloor[iX][iY].bAnimated and tShape[iShapeX][iShapeY] == 1 then
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[tObject.iBlockType]
                    tFloor[iX][iY].iBright = tObject.iBright + (iBrightOffset or 0)

                    if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                        if tObject.iBlockType == CBlock.BLOCK_TYPE_LAVA then
                            if tFloor[iX][iY].iWeight > 10 then
                                AL.NewTimer(200, function()
                                    if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
                                        CBlock.LavaObjectClick(iX, iY)
                                    end
                                end)
                            end
                        end
                    end

                    if tObject.iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                        tFloor[iX][iY].bProtectedFromLava = true
                        AL.NewTimer(CPaint.ANIMATION_DELAY*4, function()
                            tFloor[iX][iY].bProtectedFromLava = false  
                        end)
                    else
                        tFloor[iX][iY].bProtectedFromLava = false
                    end
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
CShapes.GetRandomSmallShape = function()
    return CShapes.tSmall[math.random(1, #CShapes.tSmall)]
end

CShapes.GetRandomMediumShape = function()
    return CShapes.tMedium[math.random(1, #CShapes.tMedium)]
=======
CShapes.GetRandomShapeFromTable = function(tTable, iLimitIn)
    local iLimit = iLimitIn
    if iLimit == nil or iLimit > #tTable or iLimit < 1 then iLimit = #tTable end
    return tTable[math.random(1, iLimit)]
end

CShapes.GetRandomSmallShape = function(iLimit)
    return CShapes.GetRandomShapeFromTable(CShapes.tSmall, iLimit)
end

CShapes.GetRandomMediumShape = function(iLimit)
    return CShapes.GetRandomShapeFromTable(CShapes.tMedium, iLimit)
end

CShapes.GetRandomPattern = function(iLimit)
    return CShapes.GetRandomShapeFromTable(CShapes.tPatterns, iLimit)
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
    {0,0,1,0,0},
    {0,1,1,1,0},
    {1,1,1,1,1},
}
CShapes.tSmall[8] =
{
    {1,1,1,1,1},
    {0,1,1,1,0},
    {0,0,1,0,0},
}
CShapes.tSmall[9] =
{
    {0,0,1},
    {0,1,1},
    {1,1,1},
    {0,1,1},
    {0,0,1},
}
CShapes.tSmall[9] =
{
    {1,0,0},
    {1,1,0},
    {1,1,1},
    {1,1,0},
    {1,0,0},
=======
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
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======
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
>>>>>>> Stashed changes

CShapes.tNumbers = {}
CShapes.tNumbers[0] = 
{
    {0,1,1,1,0,0,0,1,1,1,0},
    {1,0,0,0,1,0,1,0,0,0,1},
    {1,0,0,0,0,0,1,0,0,0,1},
    {1,0,0,1,1,0,1,0,0,0,1},
    {1,0,0,0,1,0,1,0,0,0,1},
    {1,0,0,0,1,0,1,0,0,0,1},
    {0,1,1,1,0,0,0,1,1,1,0},
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
<<<<<<< Updated upstream
=======
                --tFloor[iX][iY].bProtectedFromLava = false
>>>>>>> Stashed changes
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
            CBlock.RegisterBlockClick(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
<<<<<<< Updated upstream
=======
        tFloor[defect.X][defect.Y].bProtectedFromLava = true
        CBlock.RegisterBlockClick(defect.X, defect.Y)
>>>>>>> Stashed changes
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_SETUP then
        CGameMode.EndGameSetup()
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