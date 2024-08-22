--[[
    Название: Проводник
    Автор: Avondale, дискорд - avonda
    Описание механики:
        Два игрока управляют пикселем, проводя его по лабиринту
        
        Чтобы победить нужно дойти синим пикселем до красного пикселя в конце лабиринта в противоположном от старта углу
        В настройках также можно включить/выключить таймер, по истечению которого игрокам будет засчитано поражение

        Чтобы управлять пикселем игроки ходят по краям комнаты на отмеченных зонах
        Игрок стоит слева от пикселя - пиксель идёт влево, и наоборот

    Идеи по доработке:

]]
math.randomseed(os.time())

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
    iControlId = 0,
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

    CGameMode.init()
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
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
    
    CCamera.DrawWorld()
    CPaint.UI()

    if bAnyButtonClick then
        CAudio.PlaySyncFromScratch("")
        CGameMode.StartCountDown(5)
        iGameState = GAMESTATE_GAME
    end    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет

    CCamera.DrawWorld()
    CPaint.Hero()
    CPaint.UI()
end

function PostGameTick()
    CPaint.Hero()

    if CGameMode.bVictory then
        SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)
    else
        SetAllButtonColorBright(CColors.RED, tConfig.Bright)
    end    
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

CGameMode.bVictory = false

CGameMode.iDifficulty = 2

CGameMode.iHeroX = 2
CGameMode.iHeroY = 1
CGameMode.iHeroColor = CColors.BLUE

CGameMode.iHeroPlusX = 0
CGameMode.iHeroPlusY = 0

CGameMode.DIFFICULTY_WORLD_SIZE = {}
CGameMode.DIFFICULTY_WORLD_SIZE[1] = 31
CGameMode.DIFFICULTY_WORLD_SIZE[2] = 37
CGameMode.DIFFICULTY_WORLD_SIZE[3] = 41
CGameMode.DIFFICULTY_WORLD_SIZE[4] = 41

CGameMode.DIFFICULTY_TIMER = {}
CGameMode.DIFFICULTY_TIMER[1] = 300
CGameMode.DIFFICULTY_TIMER[2] = 250
CGameMode.DIFFICULTY_TIMER[3] = 180
CGameMode.DIFFICULTY_TIMER[4] = 60

CGameMode.init = function()
    CGameMode.iDifficulty = tConfig.Difficulty

    CWorld.init()

    CGameMode.HeroMove(0, 0)
end

CGameMode.Announcer = function()
    CAudio.PlaySync("mazeguide_gamename.mp3")
    CAudio.PlaySync("mazeguide_guide.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
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
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    CTimer.New(tConfig.MovementTick, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        if CWorld.tBlocks[CGameMode.iHeroX][CGameMode.iHeroY].iBlockType == CWorld.BLOCK_TYPE_FINISH then
            CGameMode.EndGame(true)
        end

        CGameMode.HeroMove(CGameMode.iHeroPlusX, 0)
        CGameMode.HeroMove(0, CGameMode.iHeroPlusY)

        CGameMode.iHeroPlusX = 0
        CGameMode.iHeroPlusY = 0

        return tConfig.MovementTick
    end)

    if tConfig.TimerOn then
        tGameStats.StageLeftDuration = CGameMode.DIFFICULTY_TIMER[CGameMode.iDifficulty]
        CTimer.New(1000, function()
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration == 0 then
                CGameMode.EndGame(false)
                return nil
            end

            CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)

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
        CAudio.PlaySync(CAudio.GAME_SUCCESS)
        CAudio.PlaySync(CAudio.VICTORY)
    else
        CAudio.PlaySync(CAudio.GAME_OVER)
        CAudio.PlaySync(CAudio.DEFEAT)
    end

    CTimer.New(10000, function()
        iGameState = GAMESTATE_FINISH
    end)

    local iY = 1
    CTimer.New(240, function()
        for iX = 1, tGame.Cols do
            if bVictory then
                tFloor[iX][iY].iColor = CColors.GREEN
            else
                tFloor[iX][iY].iColor = CColors.RED
            end

            tFloor[iX][iY].iBright = tConfig.Bright
        end

        iY = iY + 1
        if iY > tGame.Rows then return nil end

        return 240
    end)
end

CGameMode.HeroMove = function(iXPlus, iYPlus)
    if CWorld.tBlocks[CGameMode.iHeroX+iXPlus] and CWorld.tBlocks[CGameMode.iHeroX+iXPlus][CGameMode.iHeroY+iYPlus] 
    and CWorld.tBlocks[CGameMode.iHeroX+iXPlus][CGameMode.iHeroY+iYPlus].iBlockType ~= CWorld.BLOCK_TYPE_TERRAIN then
        CGameMode.iHeroX = CGameMode.iHeroX + iXPlus
        CGameMode.iHeroY = CGameMode.iHeroY + iYPlus
    end

    CCamera.FocusOnWorldPos(CGameMode.iHeroX, CGameMode.iHeroY)
end

CGameMode.PlayerControl = function(iControlId, iX, iY)
    local iHeroCamX, iHeroCamY = CCamera.WorldPosToCamPos(CGameMode.iHeroX, CGameMode.iHeroY)

    if iControlId == 1 then
        if iX < iHeroCamX then
            CGameMode.iHeroPlusX = -1
        elseif iX > iHeroCamX then
            CGameMode.iHeroPlusX = 1
        end
    elseif iControlId == 2 then
        if iY < iHeroCamY then
            CGameMode.iHeroPlusY = -1
        elseif iY > iHeroCamY then
            CGameMode.iHeroPlusY = 1
        end
    end
end
--//

--PAINT
CPaint = {}

CPaint.Hero = function()
    local iHeroCamX, iHeroCamY = CCamera.WorldPosToCamPos(CGameMode.iHeroX, CGameMode.iHeroY)    

    tFloor[iHeroCamX][iHeroCamY].iColor = CGameMode.iHeroColor
    tFloor[iHeroCamX][iHeroCamY].iBright = tConfig.Bright
end

CPaint.UI = function()
    local iHeroCamX, iHeroCamY = CCamera.WorldPosToCamPos(CGameMode.iHeroX, CGameMode.iHeroY)    

    local function paintpixel(iX, iY, iColor, iControlId)
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iControlId = iControlId

        if iGameState == GAMESTATE_GAME then 
            if iX == iHeroCamX or iY == iHeroCamY then
                tFloor[iX][iY].iBright = tFloor[iX][iY].iBright - 3
            end

            if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
                CGameMode.PlayerControl(iControlId, iX, iY)
            end        
        end
    end

    for iX = 1, tGame.Cols-2 do
        for iY = tGame.Rows-(tConfig.ControlPanelWidth-1), tGame.Rows do
            paintpixel(iX, iY, CColors.MAGENTA, 1)
        end
    end

    for iY = 1, tGame.Rows-2 do
        for iX = tGame.Cols-(tConfig.ControlPanelWidth-1), tGame.Cols do
            paintpixel(iX, iY, CColors.YELLOW, 2)
        end
    end
end
--

--WORLD
CWorld = {}

CWorld.BLOCK_TYPE_EMPTY = 1
CWorld.BLOCK_TYPE_TERRAIN = 2
CWorld.BLOCK_TYPE_START = 3
CWorld.BLOCK_TYPE_FINISH = 4

CWorld.BLOCK_TYPE_TO_COLOR = {}
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_EMPTY] = CColors.NONE
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_TERRAIN] = CColors.WHITE
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_START] = CColors.GREEN
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_FINISH] = CColors.RED

CWorld.tBlocks = {}
CWorld.tBlockList = {}

CWorld.iSizeX = 0
CWorld.iSizeY = 0
CWorld.iDepth = 0

CWorld.tChunks = {}

CWorld.CHUNK_MAX_DEPTH = 200

CWorld.bPlayerActionsPaused = false

CWorld.DistanceBetweenTwoPoints = function(iX1, iY1, iX2, iY2)
    return math.abs(iX1-iX2) + math.abs(iY1-iY2)
end

CWorld.init = function()
    CWorld.iSizeX = CGameMode.DIFFICULTY_WORLD_SIZE[CGameMode.iDifficulty]
    CWorld.iSizeY = CGameMode.DIFFICULTY_WORLD_SIZE[CGameMode.iDifficulty]

    for iX = 1, CWorld.iSizeX do
        for iY = 1, CWorld.iSizeY do
            CWorld.SetBlock(iX, iY, CWorld.BLOCK_TYPE_TERRAIN)
        end
    end

    CWorld.tChunks[1] = {iX = 2, iY = 2, iDepth = 0}
    while true do
        local bEnd = true
        for iChunkId = 1, #CWorld.tChunks do
            if CWorld.tChunks[iChunkId] and CWorld.tChunks[iChunkId].iDepth < CWorld.CHUNK_MAX_DEPTH then
                bEnd = false
                CWorld.CarveChunk(CWorld.tChunks[iChunkId])
            end
        end

        if bEnd then break; end
    end
    CWorld.tChunks = nil
    
    CWorld.tBlocks[2][1].iBlockType = CWorld.BLOCK_TYPE_START
    CWorld.tBlocks[CWorld.iSizeX-1][CWorld.iSizeY].iBlockType = CWorld.BLOCK_TYPE_FINISH
end

CWorld.CarveChunk = function(tChunk)
    CWorld.iDepth = CWorld.iDepth + 1
    tChunk.iDepth = tChunk.iDepth + 1

    local iX = tChunk.iX
    local iY = tChunk.iY

    CWorld.tBlocks[iX][iY].iBlockType = CWorld.BLOCK_TYPE_EMPTY

    local iR = math.random(0,3)
    for i = 0, 3 do
        local iD = (i + iR) % 4
        local iDX = 0
        local iDY = 0
        
        if iD == 0 then
            iDX = 1
        elseif iD == 1 then
            iDX = -1
        elseif iD == 2 then
            iDY = 1
        else
            iDY = -1
        end

        local iNX = iX + iDX
        local iNY = iY + iDY
        local iNX2 = iNX + iDX
        local iNY2 = iNY + iDY
        if CWorld.tBlocks[iNX] and CWorld.tBlocks[iNX][iNY] and CWorld.tBlocks[iNX][iNY].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then
            if CWorld.tBlocks[iNX2] and CWorld.tBlocks[iNX2][iNY2] and CWorld.tBlocks[iNX2][iNY2].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then
                CWorld.tBlocks[iNX][iNY].iBlockType = CWorld.BLOCK_TYPE_EMPTY

                local iChunkId = #CWorld.tChunks+1
                CWorld.tChunks[iChunkId] = {}
                CWorld.tChunks[iChunkId].iX = iNX2
                CWorld.tChunks[iChunkId].iY = iNY2

                if tChunk.iDepth < CWorld.CHUNK_MAX_DEPTH then
                    CWorld.tChunks[iChunkId].iDepth = tChunk.iDepth
                    CWorld.CarveChunk(CWorld.tChunks[iChunkId])
                else
                    CWorld.tChunks[iChunkId].iDepth = 0
                end
            end
        end
    end
end

CWorld.SetBlock = function(iX, iY, iBlockType)
    if CWorld.tBlocks[iX] == nil then CWorld.tBlocks[iX] = {} end

    CWorld.tBlocks[iX][iY] = {}
    CWorld.tBlocks[iX][iY].iBlockType = iBlockType

    --CWorld.tBlocks[iX][iY].iBlockId = #CWorld.tBlockList+1
    --CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId] = {}
    --CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId].iX = iX
    --CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId].iY = iY   
end

CWorld.IsValidPositionForUnit = function(iUnitX, iUnitY, iSize)
    for iX = iUnitX, iUnitX+iSize-1 do
        for iY = iUnitY, iUnitY+iSize-1 do
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then
                if CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then return false end
            end
        end
    end

    return true
end
--//

--CAMERA
CCamera = {}
CCamera.iX = 1
CCamera.iY = 1

CCamera.WorldPosToCamPos = function(iX, iY)
    return (iX - CCamera.iX)+1, (iY - CCamera.iY)+1
end

CCamera.CamPosToWorldPos = function(iX, iY)
    return (iX + CCamera.iX)-1, (iY + CCamera.iY)-1
end

CCamera.IsValidCamPos = function(iX, iY)
    return iX >= 1 and iX <= tGame.Cols and iY >= 1 and iY <= tGame.Rows
end

CCamera.IsPosOnCamera = function(iX, iY, iSize)
    iSize = iSize or 3

    return iX >= CCamera.iX-iSize and iX <= CCamera.iX+tGame.Cols+iSize and iY >= CCamera.iY-iSize and iY <= CCamera.iY+tGame.Rows+iSize
end

CCamera.FocusOnWorldPos = function(iX, iY)
    CCamera.SnapToWorldPos(iX-math.floor(tGame.Cols/2), iY-math.floor(tGame.Rows/2))
end

CCamera.SnapToWorldPos = function(iX, iY)
    local iPlusNeg = 0
    local iPlusPos = 4

    if iX < iPlusNeg then iX = iPlusNeg end
    if iX > CWorld.iSizeX-tGame.Cols+iPlusPos then iX = CWorld.iSizeX-tGame.Cols+iPlusPos end
    if iY < iPlusNeg then iY = iPlusNeg end
    if iY > CWorld.iSizeY-tGame.Rows+iPlusPos then iY = CWorld.iSizeY-tGame.Rows+iPlusPos end

    CCamera.iX = iX
    CCamera.iY = iY
end

CCamera.DrawWorld = function()
    for iX = CCamera.iX, CCamera.iX+tGame.Cols-1 do
        for iY = CCamera.iY, CCamera.iY+tGame.Rows-1 do
            local iBlockType = CWorld.BLOCK_TYPE_TERRAIN
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then iBlockType = CWorld.tBlocks[iX][iY].iBlockType end

            local iScreenX, iScreenY = CCamera.WorldPosToCamPos(iX, iY)
            tFloor[iScreenX][iScreenY].iColor = CWorld.BLOCK_TYPE_TO_COLOR[iBlockType]
            tFloor[iScreenX][iScreenY].iBright = tConfig.Bright
            tFloor[iScreenX][iScreenY].iBlockType = iBlockType
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

    if click.Click and iGameState == GAMESTATE_GAME and tFloor[click.X] and tFloor[click.X][click.Y] and not tFloor[click.X][click.Y].bDefect and tFloor[click.X][click.Y].iControlId > 0 then
        CGameMode.PlayerControl(tFloor[click.X][click.Y].iControlId, click.X, click.Y)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
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