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
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundStarted = false

    CGameMode.iMapCoinCount = 0
    CGameMode.iMapCoinReq = 0
    CGameMode.iMapCoinCollected = 0

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
end

CMap.GenerateRandomMap = function()
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
    CMap.GenerateCoins()
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

    if CMap.tGenerationRules.iSafeZoneType ~= CMap.tGenerationConsts.SAFEZONE_TYPE_PATTERN then
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

        local iXInc = #CShapes.tSmall + math.random(-#CShapes.tSmall+2,2)
        local iYInc = #CShapes.tSmall[1] + math.random(0,2)

        for iX = 1, tGame.Cols, iXInc do
            for iY = 1, tGame.Rows, iYInc do
                safeformation(iX, iY, tShape)
            end
        end
    end

    if CMap.tGenerationRules.bBigEdge then
        local iSizeX = math.random(1,3)
        local iSizeY = math.random(1,3)

        for iPos = 1, 6 do
            if math.random(1,100) >= 40 then
                if iPos == 1 then
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

    for iChunkId = 1, math.random(3,6) do
        CBlock.NewBlockFormationFromShape(CBlock.LAYER_GROUND, math.random(1, tGame.Cols), math.random(1, tGame.Rows), iBlockType, CShapes.GetRandomMediumShape())
    end
end

CMap.GenerateCoins = function()
    for iCoinId = 1, math.random(20,30) do
        local iX = math.random(1, tGame.Cols)
        local iY = math.random(1, tGame.Rows)

        if not tFloor[iX][iY].bDefect and CBlock.IsEmpty(CBlock.LAYER_COINS, iX, iY) and CBlock.IsEmpty(CBlock.LAYER_SAFEGROUND, iX, iY) then
            CBlock.NewBlock(CBlock.LAYER_COINS, iX, iY, CBlock.BLOCK_TYPE_COIN)
            CGameMode.iMapCoinCount = CGameMode.iMapCoinCount + 1
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

CBlock.NewBlock = function(iLayer, iX, iY, iBlockType)
    if CBlock.tBlocks[iLayer] == nil then CBlock.tBlocks[iLayer] = {} end
    if CBlock.tBlocks[iLayer][iX] == nil then CBlock.tBlocks[iLayer][iX] = {} end

    CBlock.tBlocks[iLayer][iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iLayer][iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iLayer][iX][iY].iBright = tConfig.Bright
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

CBlock.RegisterBlockClick = function(iX, iY)
    if iGameState ~= GAMESTATE_GAME or bGamePaused or not CGameMode.bRoundStarted then return; end

    for iLayer = CBlock.MAX_LAYER, 1, -1 do 
        if CBlock.tBlocks[iLayer] and CBlock.tBlocks[iLayer][iX] and CBlock.tBlocks[iLayer][iX][iY] and not CBlock.tBlocks[iLayer][iX][iY].bCollected then
            if CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN then
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectCoin()
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_SAFEGROUND then
                break;
            elseif CBlock.tBlocks[iLayer][iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA then
                CBlock.tBlocks[iLayer][iX][iY].bCollected = true
                CGameMode.PlayerCollectLava()
                CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType])
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
    if CGameMode.iCountdown >= 0 then
        local tShape = CShapes.tNumbers[CGameMode.iCountdown]
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
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iLayer][iX][iY].iBlockType]
                    tFloor[iX][iY].iBright = CBlock.tBlocks[iLayer][iX][iY].iBright + (iBrightOffset or 0)
                end
            end
        end
    end
end

CPaint.ObjectsLayer = function(iLayer, iBrightOffset)
    for iObjectId = 1, #CBlock.tObjects[iLayer] do
        local tObject = CBlock.tObjects[iLayer][iObjectId]
        local iShapeSizeX = #tObject.tShape
        local iShapeSizeY = #tObject.tShape[1]
        local iShapeX = 0
        local iShapeY = 0

        for iX = tObject.iX, tObject.iX+iShapeSizeX-1 do
            iShapeX = iShapeX + 1
            for iY = tObject.iY, tObject.iY+iShapeSizeY-1 do
                iShapeY = iShapeY + 1
                if not tFloor[iX][iY].bAnimated and CBlock.IsValidPosition(iX, iY) and tShape[iShapeX][iShapeY] == 1 then
                    tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[tObject.iBlockType]
                    tFloor[iX][iY].iBright = tObject.iBright + (iBrightOffset or 0)
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

CShapes.GetRandomSmallShape = function()
    return CShapes.tSmall[math.random(1, #CShapes.tSmall)]
end

CShapes.GetRandomMediumShape = function()
    return CShapes.tMedium[math.random(1, #CShapes.tMedium)]
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