--[[
    Название: Трубопровод
    Автор: Avondale, дискорд - avonda
    Описание механики:
        Нужно соединить все трубы
        Чтобы вращать трубы наступайте на зеленые пиксели
        Ваше время ограничено

    Идеи по доработке:
        Больше типов труб (T-формы например)
        Раунды?
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
    TargetScore = 0,
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
    iPipeID = 0,
    iPipeRotationID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local bAnyButtonClick = false

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

    if not CGameMode.bCountDownStarted then
        if bAnyButtonClick then
            CGameMode.StartCountDown(5)
            return
        end

        for iX = math.floor(tGame.Cols/2), math.floor(tGame.Cols/2) + 1 do
            for iY = math.floor(tGame.Rows/2), math.floor(tGame.Rows/2) + 1 do
                tFloor[iX][iY].iColor = CColors.BLUE
                tFloor[iX][iY].iBright = tConfig.Bright

                if tFloor[iX][iY].bClick and CGameMode.bCanStartGame then
                    CGameMode.StartCountDown(5)
                end
            end
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CPaint.Pipes()
end

function PostGameTick()
    CPaint.Pipes()
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
CGameMode.bCanStartGame = false
CGameMode.bCountDownStarted = false
CGameMode.iCountdown = 0
CGameMode.bVictory = false

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("pipes/pipes_rules.mp3")
    CAudio.PlayVoicesSync("press-center-for-start.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("pipes/pipes_rules.mp3")*1000), function()
        CGameMode.bCanStartGame = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
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
    CGameMode.GenerateMap()
    tGameStats.TargetScore = #CPipes.tPipes
    CPipes.StartWaterFlow()

    iGameState = GAMESTATE_GAME
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    if tConfig.TimeLimit > 0 then
        tGameStats.StageLeftDuration = tConfig.TimeLimit
        AL.NewTimer(1000, function()
            if iGameState ~= GAMESTATE_GAME then return; end

            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
            if tGameStats.StageLeftDuration == 0 then 
                CGameMode.EndGame(false)
                return nil
            elseif tGameStats.StageLeftDuration < 10 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000
        end)
    end
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    CAudio.StopBackground()
    CAudio.PlaySyncFromScratch("")
    iGameState = GAMESTATE_POSTGAME

    if bVictory then
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN

        tGameResults.Score = ((#CPipes.tPipes*10) - (tGameStats.StageLeftDuration - tConfig.TimeLimit))*50
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
    end

    tGameResults.Won = bVictory

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.GenerateMap = function()
    CPipes.tPipes = {}

    local iStartX = math.floor(tGame.Cols/2)
    local iStartY = math.floor(tGame.Rows/2)
    local iStartDirection = math.random(1,4)

    local function directionToPlus(iLocDirection, iLocX, iLocY)
        local iXPlus = 0
        local iYPlus = 0
        if iLocDirection == 1 then iYPlus = 3 end
        if iLocDirection == 2 then iXPlus = -3 end
        if iLocDirection == 3 then iYPlus = -3 end
        if iLocDirection == 4 then iXPlus = 3 end
        return iLocX + iXPlus, iLocY + iYPlus
    end
    local function checkEmpty(iX, iY)
        return CPipes.GetPipeOnCoord(iX, iY) == nil
    end
    local function validDirection(iLocDirection, iLocX, iLocY, iDist)
        if iDist == nil then iDist = 3 end
        local iNextX, iNextY = directionToPlus(iLocDirection, iLocX, iLocY)
        return iNextX >= 1 and iNextX+iDist-1 <= tGame.Cols and iNextY >= 1 and iNextY+iDist-1 <= tGame.Rows and checkEmpty(iNextX, iNextY)
    end    
    local function newDirection(iDirection, iX, iY)
        local iPrevDirection = tonumber(iDirection)
        local iAttempts = 0
        local iNewDirection = iDirection

        repeat 
            iNewDirection = iNewDirection + 1; 
            if iNewDirection > 4 then iNewDirection = 1 end; 

            iAttempts = iAttempts + 1; 
            if iAttempts > 4 then 
                return iPrevDirection; 
            end
        until iNewDirection ~= iPrevDirection and validDirection(iNewDirection, iX, iY)

        return iNewDirection;
    end
    local function newPipe(iX, iY, iPipeType)
        local iPipeID = CPipes.NewPipe(iX, iY, iPipeType)

        for iCheckDirection = 1, 4 do
            local iCheckX, iCheckY = directionToPlus(iCheckDirection, iX, iY)
            local iNearPipeID = CPipes.GetPipeOnCoord(iCheckX, iCheckY)
            if iNearPipeID then
                CPipes.tPipes[iNearPipeID].tChildren[#CPipes.tPipes[iNearPipeID].tChildren+1] = iPipeID
                CPipes.tPipes[iPipeID].tChildren[#CPipes.tPipes[iPipeID].tChildren+1] = iNearPipeID
            end
        end
    end

    local function nextPipe(iX, iY, iDirectionIn)
        local bTurn = math.random(1,100) > 60 or #CPipes.tPipes == 0
        local bQuad = bTurn and math.random(1,100) > 70 or #CPipes.tPipes == 0
        local iDirection = tonumber(iDirectionIn)

        if #CPipes.tPipes >= 100 then return; end

        if bTurn or not validDirection(iDirection, iX, iY) then 
            iDirection = newDirection(iDirection, iX, iY)
            if iDirection == iDirectionIn then return; end
        end

        if bTurn or iDirection ~= iDirectionIn then
            if not bQuad then
                newPipe(iX, iY, CPipes.PIPE_TYPE_TURN)
                local iNextX, iNextY = directionToPlus(iDirection, iX, iY)
                nextPipe(iNextX, iNextY, iDirection) 
            else
                newPipe(iX, iY, CPipes.PIPE_TYPE_QUAD)
                local iQuadDirection = tonumber(iDirection)
                for i = 1, 5 do
                    if validDirection(iQuadDirection, iX, iY) then
                        local iNextX, iNextY = directionToPlus(iQuadDirection, iX, iY)
                        nextPipe(iNextX, iNextY, iQuadDirection) 
                    end
                    iQuadDirection = newDirection(iX, iY, iQuadDirection)
                    if iQuadDirection == iDirection then iQuadDirection = math.random(1,4) end
                end
            end
        elseif validDirection(iDirectionIn, iX, iY) then
            newPipe(iX, iY, CPipes.PIPE_TYPE_STRAIGHT)
            local iNextX, iNextY = directionToPlus(iDirectionIn, iX, iY)
            nextPipe(iNextX, iNextY, iDirectionIn) 
        end
    end

    nextPipe(iStartX, iStartY, iStartDirection)
end
--//

--PIPES
CPipes = {}
CPipes.tPipes = {}

CPipes.PIPE_TYPE_STRAIGHT = 1
CPipes.PIPE_TYPE_TURN = 2
CPipes.PIPE_TYPE_TSHAPE = 3
CPipes.PIPE_TYPE_QUAD = 4

CPipes.iConnected = 0

CPipes.NewPipe = function(iX, iY, iPipeType)
    local iPipeID = #CPipes.tPipes+1
    CPipes.tPipes[iPipeID] = {}    
    CPipes.tPipes[iPipeID].iX = iX
    CPipes.tPipes[iPipeID].iY = iY
    CPipes.tPipes[iPipeID].iPipeType = iPipeType
    CPipes.tPipes[iPipeID].iPipeFrame = math.random(1, #CPipes.tPipeShapes[iPipeType])
    CPipes.tPipes[iPipeID].bRotateCD = false
    CPipes.tPipes[iPipeID].bConnectedToWater = iPipeID == 1
    CPipes.tPipes[iPipeID].tChildren = {}

    return iPipeID
end

CPipes.GetPipeOnCoord = function(iX, iY)
    for iPipeID = 1, #CPipes.tPipes do
        if CPipes.tPipes[iPipeID].iX == iX and CPipes.tPipes[iPipeID].iY == iY then return iPipeID end;
    end   
    return nil
end

CPipes.PlayerRotatePipe = function(iPipeID)
    if CPipes.tPipes[iPipeID].bRotateCD then return; end
    
    CPipes.tPipes[iPipeID].iPipeFrame = CPipes.tPipes[iPipeID].iPipeFrame + 1
    if CPipes.tPipes[iPipeID].iPipeFrame > #CPipes.tPipeShapes[CPipes.tPipes[iPipeID].iPipeType] then
        CPipes.tPipes[iPipeID].iPipeFrame = 1 
    end

    CPipes.tPipes[iPipeID].bRotateCD = true
    AL.NewTimer(250, function()
        CPipes.tPipes[iPipeID].bRotateCD = false
    end)

    CPipes.StartWaterFlow()
end

CPipes.StartWaterFlow = function()
    CPipes.iConnected = 1
    for iPipeID = 2, #CPipes.tPipes do
        CPipes.tPipes[iPipeID].bConnectedToWater = false
    end

    CPipes.WaterFlow(1)
    tGameStats.Players[1].Score = CPipes.iConnected 
    if CPipes.iConnected == tGameStats.TargetScore then
        CGameMode.EndGame(true)
    end
end

CPipes.WaterFlow = function(iPipeID)
    for iChild = 1, #CPipes.tPipes[iPipeID].tChildren do
        local iChildPipeID = CPipes.tPipes[iPipeID].tChildren[iChild]
        if not CPipes.tPipes[iChildPipeID].bConnectedToWater and iChildPipeID ~= iPipeID then
            if CPipes.tPipes[iPipeID].bConnectedToWater and CPipes.PipesConnect(iPipeID, iChildPipeID) then
                CPipes.tPipes[iChildPipeID].bConnectedToWater = true
                CPipes.iConnected = CPipes.iConnected + 1
                CPipes.WaterFlow(iChildPipeID)    
            end       
        end
    end
end

CPipes.PipesConnect = function(iPipeID1, iPipeID2)
    local tPipe1 = CPipes.tPipes[iPipeID1]
    local tPipe2 = CPipes.tPipes[iPipeID2]

    if tPipe1.iPipeType == CPipes.PIPE_TYPE_STRAIGHT and tPipe2.iPipeType == CPipes.PIPE_TYPE_STRAIGHT then
        if tPipe1.iPipeFrame == 1 and tPipe2.iPipeFrame == 1 and tPipe1.iX == tPipe2.iX then return true; end
        if tPipe1.iPipeFrame == 2 and tPipe2.iPipeFrame == 2 and tPipe1.iY == tPipe2.iY then return true; end
    end

    if tPipe1.iPipeType == CPipes.PIPE_TYPE_STRAIGHT and tPipe2.iPipeType == CPipes.PIPE_TYPE_TURN then
        if tPipe1.iX == tPipe2.iX and tPipe1.iPipeFrame == 1 then
            if tPipe1.iY < tPipe2.iY and tPipe2.iPipeFrame >= 3 then return true; end
            if tPipe1.iY > tPipe2.iY and tPipe2.iPipeFrame <= 2 then return true; end
        end
        if tPipe1.iY == tPipe2.iY and tPipe1.iPipeFrame == 2 then
            if tPipe1.iX < tPipe2.iX and (tPipe2.iPipeFrame == 2 or tPipe2.iPipeFrame == 3) then return true; end
            if tPipe1.iX > tPipe2.iX and (tPipe2.iPipeFrame == 1 or tPipe2.iPipeFrame == 4) then return true; end
        end
    end
    if tPipe2.iPipeType == CPipes.PIPE_TYPE_STRAIGHT and tPipe1.iPipeType == CPipes.PIPE_TYPE_TURN then
        if tPipe2.iX == tPipe1.iX and tPipe2.iPipeFrame == 1 then
            if tPipe2.iY < tPipe1.iY and tPipe1.iPipeFrame >= 3 then return true; end
            if tPipe2.iY > tPipe1.iY and tPipe1.iPipeFrame <= 2 then return true; end
        end
        if tPipe2.iY == tPipe1.iY and tPipe2.iPipeFrame == 2 then
            if tPipe2.iX < tPipe1.iX and (tPipe1.iPipeFrame == 2 or tPipe1.iPipeFrame == 3) then return true; end
            if tPipe2.iX > tPipe1.iX and (tPipe1.iPipeFrame == 1 or tPipe1.iPipeFrame == 4) then return true; end
        end
    end

    if tPipe1.iPipeType == CPipes.PIPE_TYPE_TURN and tPipe2.iPipeType == CPipes.PIPE_TYPE_TURN then
        if tPipe1.iX == tPipe2.iX then
            if tPipe1.iY < tPipe2.iY and (tPipe1.iPipeFrame == 1 or tPipe1.iPipeFrame == 2) and (tPipe2.iPipeFrame == 3 or tPipe2.iPipeFrame == 4) then return true; end
            if tPipe1.iY > tPipe2.iY and (tPipe1.iPipeFrame == 3 or tPipe1.iPipeFrame == 4) and (tPipe2.iPipeFrame == 1 or tPipe2.iPipeFrame == 2) then return true; end
        end
        if tPipe1.iY == tPipe2.iY then
            if tPipe1.iX < tPipe2.iX and (tPipe1.iPipeFrame == 1 or tPipe1.iPipeFrame == 4) and (tPipe2.iPipeFrame == 2 or tPipe2.iPipeFrame == 3) then return true; end
            if tPipe1.iX > tPipe2.iX and (tPipe1.iPipeFrame == 2 or tPipe1.iPipeFrame == 3) and (tPipe2.iPipeFrame == 1 or tPipe2.iPipeFrame == 4) then return true; end
        end
    end

    if tPipe1.iPipeType == CPipes.PIPE_TYPE_QUAD and tPipe2.iPipeType == CPipes.PIPE_TYPE_QUAD then return true; end
    if tPipe1.iPipeType == CPipes.PIPE_TYPE_QUAD and tPipe2.iPipeType == CPipes.PIPE_TYPE_STRAIGHT then
        if tPipe1.iX == tPipe2.iX and tPipe2.iPipeFrame == 1 then return true end
        if tPipe1.iY == tPipe2.iY and tPipe2.iPipeFrame == 2 then return true end
    end
    if tPipe1.iPipeType == CPipes.PIPE_TYPE_QUAD and tPipe2.iPipeType == CPipes.PIPE_TYPE_TURN then
        if tPipe1.iX == tPipe2.iX then
            if tPipe1.iY < tPipe2.iY and tPipe2.iPipeFrame >= 3 then return true; end
            if tPipe1.iY > tPipe2.iY and tPipe2.iPipeFrame <= 2 then return true; end
        end
        if tPipe1.iY == tPipe2.iY then
            if tPipe1.iX < tPipe2.iX and (tPipe2.iPipeFrame == 2 or tPipe2.iPipeFrame == 3) then return true; end
            if tPipe1.iX > tPipe2.iX and (tPipe2.iPipeFrame == 1 or tPipe2.iPipeFrame == 4) then return true; end
        end        
    end    
    if tPipe2.iPipeType == CPipes.PIPE_TYPE_QUAD and tPipe1.iPipeType == CPipes.PIPE_TYPE_STRAIGHT then
        if tPipe2.iX == tPipe1.iX and tPipe1.iPipeFrame == 1 then return true end
        if tPipe2.iY == tPipe1.iY and tPipe1.iPipeFrame == 2 then return true end
    end
    if tPipe2.iPipeType == CPipes.PIPE_TYPE_QUAD and tPipe1.iPipeType == CPipes.PIPE_TYPE_TURN then
        if tPipe2.iX == tPipe1.iX then
            if tPipe2.iY < tPipe1.iY and tPipe1.iPipeFrame >= 3 then return true; end
            if tPipe2.iY > tPipe1.iY and tPipe1.iPipeFrame <= 2 then return true; end
        end
        if tPipe2.iY == tPipe1.iY then
            if tPipe2.iX < tPipe1.iX and (tPipe1.iPipeFrame == 2 or tPipe1.iPipeFrame == 3) then return true; end
            if tPipe2.iX > tPipe1.iX and (tPipe1.iPipeFrame == 1 or tPipe1.iPipeFrame == 4) then return true; end
        end        
    end   

    return false
end

CPipes.tPipeShapes = {}

CPipes.tPipeShapesColors = {}
CPipes.tPipeShapesColors[0] = CColors.NONE 
CPipes.tPipeShapesColors[1] = CColors.BLUE 
CPipes.tPipeShapesColors[2] = CColors.GREEN 

CPipes.tPipeShapes[CPipes.PIPE_TYPE_STRAIGHT] = {}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_STRAIGHT][1] = 
{
    {0,1,0},
    {0,2,0},
    {0,1,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_STRAIGHT][2] = 
{
    {0,0,0},
    {1,2,1},
    {0,0,0},
}

CPipes.tPipeShapes[CPipes.PIPE_TYPE_TURN] = {}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TURN][1] = 
{
    {0,0,0},
    {0,2,1},
    {0,1,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TURN][2] = 
{
    {0,0,0},
    {1,2,0},
    {0,1,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TURN][3] = 
{
    {0,1,0},
    {1,2,0},
    {0,0,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TURN][4] = 
{
    {0,1,0},
    {0,2,1},
    {0,0,0},
}

CPipes.tPipeShapes[CPipes.PIPE_TYPE_TSHAPE] = {}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TSHAPE][1] = 
{
    {0,0,0},
    {1,2,1},
    {0,1,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TSHAPE][2] = 
{
    {0,1,0},
    {1,2,0},
    {0,1,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TSHAPE][3] = 
{
    {0,1,0},
    {1,2,1},
    {0,0,0},
}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_TSHAPE][4] = 
{
    {0,1,0},
    {0,2,1},
    {0,1,0},
}

CPipes.tPipeShapes[CPipes.PIPE_TYPE_QUAD] = {}
CPipes.tPipeShapes[CPipes.PIPE_TYPE_QUAD][1] = 
{
    {0,1,0},
    {1,1,1},
    {0,1,0},
}

--//

--PAINT
CPaint = {}

CPaint.Pipes = function()
    for iPipeID = 1, #CPipes.tPipes do
        if CPipes.tPipes[iPipeID] then
            local tShape = CPipes.tPipeShapes[CPipes.tPipes[iPipeID].iPipeType][CPipes.tPipes[iPipeID].iPipeFrame]
            local iShapeX = 1
            local iShapeY = 1

            for iY = CPipes.tPipes[iPipeID].iY, CPipes.tPipes[iPipeID].iY + #tShape-1 do
                for iX = CPipes.tPipes[iPipeID].iX, CPipes.tPipes[iPipeID].iX + #tShape[iShapeY]-1 do
                    tFloor[iX][iY].iColor = CPipes.tPipeShapesColors[tShape[iShapeY][iShapeX]] 
                    tFloor[iX][iY].iBright = tConfig.Bright+1
                    tFloor[iX][iY].iPipeID = iPipeID

                    if tShape[iShapeY][iShapeX] == 1 and not CPipes.tPipes[iPipeID].bConnectedToWater then
                        tFloor[iX][iY].iBright = tConfig.Bright-2
                    end

                    if tShape[iShapeY][iShapeX] == 2 then
                        tFloor[iX][iY].iPipeRotationID = iPipeID
                    end

                    if tShape[iShapeY][iShapeX] ~= 0 and iGameState == GAMESTATE_POSTGAME then
                        if CGameMode.bVictory then
                            tFloor[iX][iY].iColor = CColors.GREEN
                        else
                            tFloor[iX][iY].iColor = CColors.RED
                        end
                    end

                    iShapeX = iShapeX + 1
                end
                iShapeX = 1
                iShapeY = iShapeY + 1
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

        if iGameState == GAMESTATE_GAME and click.Click and click.Weight > 10 then
            if tFloor[click.X][click.Y].iPipeRotationID > 0 and CPipes.tPipes[tFloor[click.X][click.Y].iPipeRotationID] then
                CPipes.PlayerRotatePipe(tFloor[click.X][click.Y].iPipeRotationID)
            end
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
    if tButtons[click.Button] == nil or bGamePaused then return end
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