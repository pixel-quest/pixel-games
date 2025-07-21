--[[
    Название: Пол это лава - На Выбывание
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Пол это лава красного цвета, на него нельзя наступать
        На полу стоят объекты разных других цветов, на них стоять можно
        Каждый раунд один из цветов пропадает и все объекты вместе с ним
        Перед пропаданием цвета нужно стоять на другом цвете чтобы не упасть в лаву
        Чтобы узнать какой цвет пропадёт нужно внимательно следить за перемещением квадратов перед раундом
        Под центральным квадратом лежит правильный цвет, но откроется он только после перемешивания квадратов
        Кто правильно проследил куда перешел центральный квадрат тот и знает цвет который пропадёт
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
    StageNum = 1,
    TotalStages = 5,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 9,
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
    bStepCD = false,
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

    iPrevTickTime = CTime.unix()

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end

    tGame.iMinX = 1
    tGame.iMinY = 1
    tGame.iMaxX = tGame.Cols
    tGame.iMaxY = tGame.Rows
    tGame.CenterX = math.floor(tGame.Cols/2)
    tGame.CenterY = math.floor(tGame.Rows/2)
    if AL.NFZ.bLoaded then
        tGame.iMinX = AL.NFZ.iMinX
        tGame.iMinY = AL.NFZ.iMinY
        tGame.iMaxX = AL.NFZ.iMaxX
        tGame.iMaxY = AL.NFZ.iMaxY

        tGame.CenterX = AL.NFZ.iCenterX
        tGame.CenterY = AL.NFZ.iCenterY
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
    SetGlobalColorBright(CColors.RED, tConfig.Bright)

    if not CGameMode.bCountDownStarted then
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

        if CGameMode.bCanAutoStart then
            for iX = tGame.CenterX-1, tGame.CenterX + 1 do
                for iY = tGame.CenterY, tGame.CenterY + 2 do
                    tFloor[iX][iY].iColor = CColors.BLUE
                    tFloor[iX][iY].iBright = tConfig.Bright
                    if tFloor[iX][iY].bClick then bAnyButtonClick = true; end
                end
            end
        end
    else
        SetAllButtonColorBright(CColors.NONE, tConfig.Bright)
        CObjects.PaintObjects(tConfig.Bright)
    end

    if bAnyButtonClick then
        bAnyButtonClick = false

        if not CGameMode.bCountDownStarted then
            CGameMode.StartCountDown(15)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    local iBrightIn = tConfig.Bright

    if CGameMode.bIntroInProgress then
        iBrightIn = CColors.BRIGHT15
    end

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if not tFloor[iX][iY].bStepCD then
                if tFloor[iX][iY].bClick and tFloor[iX][iY].iColor == CColors.RED then
                    AL.NewTimer(200, function()
                        if tFloor[iX][iY].iColor == CColors.RED and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
                            CGameMode.PlayerStepOnLava(iX, iY)
                        end
                    end)
                end

                tFloor[iX][iY].iColor = CColors.RED
                tFloor[iX][iY].iBright = iBrightIn
            end
        end
    end

    CObjects.PaintObjects(iBrightIn) 

    if CGameMode.bIntroInProgress then
        CIntro.Paint()
    end
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

function ShuffleColorsArray(tArrayIn)
    local tArray = CHelp.DeepCopy(tArrayIn)
    for iColorId = 1, #tArray do
        local iRand = math.random(1,#tArray)
        local iColor = tArray[iColorId]
        tArray[iColorId] = tArray[iRand]
        tArray[iRand] = iColor 
    end
    return tArray
end

local tColors = {}
tColors[1] = CColors.BLUE
tColors[2] = CColors.MAGENTA
tColors[3] = CColors.CYAN
tColors[4] = CColors.WHITE
tColors[5] = CColors.YELLOW
tColors[6] = CColors.GREEN
tColors = ShuffleColorsArray(tColors)

local tColorsForObjects = ShuffleColorsArray(tColors)

--GAMEMODE
CGameMode = {}
CGameMode.bCanAutoStart = false
CGameMode.bIntroInProgress = false
CGameMode.iCountdown = 0
CGameMode.iNextElimColorId = 1
CGameMode.tEliminatedColorIds = {}

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = #tColors-1

    CGameMode.PlaceRandomObjects()
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("lfe/lfe-rules.mp3")
    CAudio.PlayVoicesSync("press-center-for-start.mp3")

    AL.NewTimer(CAudio.GetVoicesDuration("lfe/lfe-rules.mp3")*1000 + 2000, function()
        CGameMode.bCanAutoStart = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.PlaySystemSyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            if CGameMode.iCountdown < 10 then
                CAudio.PlayLeftAudio(CGameMode.iCountdown)
            end
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    iGameState = GAMESTATE_GAME
    AL.NewTimer(5000, function()
        CIntro.Start()
    end)
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    tGameResults.Won = true
    tGameResults.Color = tColors[CGameMode.iNextElimColorId]

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.PlaceRandomObjects = function()
    local function spawnTop()
        local iX = tGame.iMinX + math.random(0,2)
        local iY = tGame.iMinY

        for i = 1, math.random(3,5) do
            local tShape = CShapes.tShapes[1]
            local bRotated = math.random(1,2) == 2 
            local iMidSize = math.random(4,6)
            if math.random(1,2) == 2 then 
                tShape = CShapes.tShapes[2]
                bRotated = true
            end

            if iX + iMidSize > tGame.iMaxX then iMidSize = (tGame.iMaxX - iX - 1) end

            if not bRotated then
                iMidSize = 3
            end

            CObjects.NewObject(iX, iY, tShape, iMidSize, bRotated)
        
            iX = iX + iMidSize + 1 + math.random(0,2)

            if iX > tGame.iMaxX-3 then break; end
        end
    end

    local function spawnBottom()
        local iX = tGame.iMinX + math.random(0,2)

        for i = 1, math.random(3,5) do
            local iY = tGame.iMaxY

            local tShape = CShapes.tShapes[1]
            local bRotated = math.random(1,2) == 2 
            local iMidSize = math.random(4,6)

            if math.random(1,2) == 2 then 
                tShape = CShapes.tShapes[3]
                bRotated = true
            end

            if iX + iMidSize > tGame.iMaxX then iMidSize = (tGame.iMaxX - iX - 1) end

            if not bRotated then
                iMidSize = math.random(2,3)
                iY = tGame.iMaxY - iMidSize
            else
                iY = tGame.iMaxY - 3
            end

            CObjects.NewObject(iX, iY, tShape, iMidSize, bRotated)
        
            iX = iX + iMidSize + 1 + math.random(0,3)

            if iX > tGame.iMaxX-3 then break; end
        end
    end

    local function SpawnCenter()
        local iX = 1
        local iY = tGame.CenterY

        local tShape = CShapes.tShapes[1]

        local iObjectCount = math.random(3,4)
    
        --iX = iX - (iObjectCount*3)

        for i = 1, iObjectCount do
            local iMidSize = math.random(6,10) - iObjectCount

            iX = iX + 2 + iMidSize + math.random(0,2)

            CObjects.NewObject(iX, iY, tShape, iMidSize, true)
        end
    end

    SpawnCenter()
    spawnTop()
    spawnBottom()
end

CGameMode.ColorElimCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.ColorElim(CGameMode.iNextElimColorId)
            tGameStats.StageNum = tGameStats.StageNum + 1
            CGameMode.iNextElimColorId = CGameMode.iNextElimColorId + 1
            if CGameMode.iNextElimColorId < #tColors then
                AL.NewTimer(5000, function()
                    CIntro.Start()
                end)
            else
                AL.NewTimer(2500, function()
                    CGameMode.EndGame()
                end)
            end

            return nil
        elseif CGameMode.iCountdown < 10 then
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
        end

        CGameMode.iCountdown = CGameMode.iCountdown - 1
        return 1000
    end)
end

CGameMode.ColorElim = function(iColorId)
    CAudio.PlaySyncColorSound(tColors[iColorId])

    CGameMode.tEliminatedColorIds[iColorId] = true

    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] ~= nil and CObjects.tObjects[iObjectID].iColor == tColors[iColorId] then
            for iX = CObjects.tObjects[iObjectID].iX, CObjects.tObjects[iObjectID].iX + #CObjects.tObjects[iObjectID].tShape[1] do
                for iY = CObjects.tObjects[iObjectID].iY, CObjects.tObjects[iObjectID].iY + #CObjects.tObjects[iObjectID].tShape do
                    if tFloor[iX] and tFloor[iX][iY] and tFloor[iX][iY].bClick then
                        AL.NewTimer(250, function()
                            if tFloor[iX][iY].iColor == CColors.RED and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
                                CGameMode.PlayerStepOnLava(iX, iY)
                            end
                        end)
                    end
                end
            end

            CObjects.tObjects[iObjectID] = nil
        end
    end
end

CGameMode.PlayerStepOnLava = function(iX, iY)
    if not tFloor[iX][iY].bStepCD then
        tFloor[iX][iY].bStepCD = true
        CAudio.PlaySystemAsync(CAudio.MISCLICK)

        tFloor[iX][iY].iColor = CColors.NONE

        local iReps = 5
        AL.NewTimer(0, function()
            iReps = iReps - 1

            if tFloor[iX][iY].iColor == CColors.NONE then 
                tFloor[iX][iY].iColor = CColors.MAGENTA
            else
                tFloor[iX][iY].iColor = CColors.NONE
            end

            if iReps > 0 then return 250; end

            tFloor[iX][iY].bStepCD = false
            return nil
        end)
    end
end
--//

--INTRO
CIntro = {}
CIntro.tCubes = {}
CIntro.bNoCubeMovement = true
CIntro.bShuffleEnded = false

CIntro.Start = function()
    CIntro.tCubes = {}
    CIntro.bNoCubeMovement = true
    CIntro.bShuffleEnded = false

    CAudio.PlayVoicesSync("lfe/lfe-follow-center-cube.mp3") --voice следите за перемещением центрального квадрата

    CGameMode.bIntroInProgress = true
    CIntro.SpawnCubes()

    local iMiddleFlickCount = 10
    AL.NewTimer(2000, function()
        if CIntro.tCubes[2].iColor == CColors.WHITE then
            CIntro.tCubes[2].iColor = CColors.RED
        else
            CIntro.tCubes[2].iColor = CColors.WHITE
        end

        iMiddleFlickCount = iMiddleFlickCount - 1
        if iMiddleFlickCount > 0 then
            return 250
        end

        CIntro.tCubes[2].iColor = CColors.WHITE
        CIntro.ShuffleCubes()
        return nil
    end)

    AL.NewTimer(0, function()
        local bCubesMoved = false

        for iCubeId = 1, 3 do
            if CIntro.tCubes[iCubeId].iX ~= CIntro.tCubes[iCubeId].iTargetX then
                if CIntro.tCubes[iCubeId].iX < CIntro.tCubes[iCubeId].iTargetX then
                    CIntro.tCubes[iCubeId].iX = CIntro.tCubes[iCubeId].iX + 1
                else
                    CIntro.tCubes[iCubeId].iX = CIntro.tCubes[iCubeId].iX - 1
                end
                bCubesMoved = true
            end
        end

        if not bCubesMoved then CIntro.bNoCubeMovement = true; end

        if CIntro.bShuffleEnded then
            CIntro.ShowTrueCubeColors()
            AL.NewTimer(5000, function()
                CIntro.End()
            end)
            return nil
        end

        return 300 - (20*tGameStats.StageNum)
    end)
end

CIntro.End = function()
    CGameMode.bIntroInProgress = false
    CGameMode.ColorElimCountDown(10)
end

CIntro.SpawnCubes = function()
    for iCubeId = 1, 3 do
        CIntro.tCubes[iCubeId] = {}
        CIntro.tCubes[iCubeId].iX = math.floor((tGame.iMaxX+1-tGame.iMinX)/2) + ((iCubeId*3)-6)
        CIntro.tCubes[iCubeId].iY = math.floor((tGame.iMaxY+1-tGame.iMinY)/2)
        CIntro.tCubes[iCubeId].iColor = CColors.WHITE
        CIntro.tCubes[iCubeId].iTargetX = CIntro.tCubes[iCubeId].iX

        if iCubeId == 2 then
            CIntro.tCubes[iCubeId].iTrueColor = CGameMode.iNextElimColorId
        else
            repeat CIntro.tCubes[iCubeId].iTrueColor = math.random(1,#tColors)
            until CIntro.CubeColorCheck(iCubeId)
        end
    end
end

CIntro.CubeColorCheck = function(iCubeId)
    if CIntro.tCubes[iCubeId].iTrueColor == CGameMode.iNextElimColorId then return false; end

    if tGameStats.StageNum < 5 or iCubeId == 1 then
        if CGameMode.tEliminatedColorIds[CIntro.tCubes[iCubeId].iTrueColor] then return false; end 
    end

    if iCubeId == 3 and CIntro.tCubes[iCubeId].iTrueColor == CIntro.tCubes[1].iTrueColor then return false; end

    return true
end

CIntro.ShuffleCubes = function()
    local iShuffleCount = 8

    AL.NewTimer(1000, function()
        if CIntro.bNoCubeMovement then
            if iShuffleCount <= 0 then 
                CIntro.bShuffleEnded = true
                return nil
            else
                CIntro.bNoCubeMovement = false
                CIntro.SwitchTwoCubes(math.random(1,3), math.random(1,3))
                iShuffleCount = iShuffleCount - 1
            end
        end

        return 100;
    end)
end

CIntro.SwitchTwoCubes = function(iCubeId1, iCubeId2)
    CAudio.PlayVoicesSync("lfe/lfe-remember-color.mp3") --voice запомните цвет

    CIntro.tCubes[iCubeId1].iTargetX = CIntro.tCubes[iCubeId2].iX
    CIntro.tCubes[iCubeId2].iTargetX = CIntro.tCubes[iCubeId1].iX
end

CIntro.ShowTrueCubeColors = function()
    for iCubeId = 1, #CIntro.tCubes do
        CIntro.tCubes[iCubeId].iColor = tColors[CIntro.tCubes[iCubeId].iTrueColor]
    end
end

CIntro.Paint = function()
    for iCubeId = 1, #CIntro.tCubes do
        for iX = CIntro.tCubes[iCubeId].iX, CIntro.tCubes[iCubeId].iX+1 do
            for iY = CIntro.tCubes[iCubeId].iY, CIntro.tCubes[iCubeId].iY+1 do
                tFloor[iX][iY].iColor = CIntro.tCubes[iCubeId].iColor
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
    end
end
--//

--OBJECTS
CObjects = {}
CObjects.tObjects = {}

CObjects.NewObject = function(iX, iY, tShape, iMidSize, bRotated)
    local iObjectID = #CObjects.tObjects+1
    CObjects.tObjects[iObjectID] = {}
    CObjects.tObjects[iObjectID].iX = iX
    CObjects.tObjects[iObjectID].iY = iY

    CObjects.tObjects[iObjectID].tShape = {}
    CObjects.tObjects[iObjectID].tShape[1] = tShape[1]
    CObjects.tObjects[iObjectID].tShape[iMidSize+1] = tShape[3]
    for i = 2, iMidSize do
        CObjects.tObjects[iObjectID].tShape[i] = tShape[2]
    end
    if bRotated then
        CObjects.tObjects[iObjectID].tShape = RotateTable(CObjects.tObjects[iObjectID].tShape)
    end

    if iObjectID <= #tColorsForObjects then
        CObjects.tObjects[iObjectID].iColor = tColorsForObjects[iObjectID]
    else
        CObjects.tObjects[iObjectID].iColor = tColorsForObjects[math.random(1,#tColors)]
    end
end

CObjects.PaintObjects = function(iBright)
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] ~= nil then
            for iObjectY = 1, #CObjects.tObjects[iObjectID].tShape do
                for iObjectX = 1, #CObjects.tObjects[iObjectID].tShape[iObjectY] do
                    if CObjects.tObjects[iObjectID].tShape[iObjectY][iObjectX] > 0 then
                        local iX = CObjects.tObjects[iObjectID].iX + iObjectX-1
                        local iY = CObjects.tObjects[iObjectID].iY + iObjectY-1

                        if tFloor[iX] and tFloor[iX][iY] then
                            tFloor[iX][iY].iColor = CObjects.tObjects[iObjectID].iColor
                            tFloor[iX][iY].iBright = iBright
                        end
                    end
                end
            end
        end
    end
end
--//

--SHAPES
CShapes = {}
CShapes.tShapes = {}

CShapes.tShapes[1] = 
{
    {1,1,1,1,1},
    {1,1,1,1,1},
    {1,1,1,1,1},
}
CShapes.tShapes[2] = 
{
    {1,1,1,1},
    {0,1,1,1},
    {1,1,1,1},
}
CShapes.tShapes[3] = 
{
    {1,1,1,1},
    {1,1,1,0},
    {1,1,1,1},
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
            if not tFloor[iX][iY].bStepCD then
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

function RotateTable(t)
   local tR = {}
   for c, t1 in ipairs(t[1]) do
      local col = {t1}
      for r = 2, #t do
         col[r] = t[r][c]
      end
      table.insert(tR, 1, col)
   end
   return tR
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
                tFloor[click.X][click.Y].bHold = true
                AL.NewTimer(1000, function()
                    if tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bClick = false
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        if iGameState == GAMESTATE_GAME and click.Click then
            if not tFloor[click.X][click.Y].bDefect and tFloor[click.X][click.Y].iColor == CColors.RED then
                CGameMode.PlayerStepOnLava(click.X, click.Y)
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