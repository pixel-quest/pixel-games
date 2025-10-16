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
    StageNum = 0,
    TotalStages = 0,
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

    iPrevTickTime = CTime.unix()

    tGameResults.PlayersCount = 2

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
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
    
    CCamera.DrawWorld()
    CPaint.UI()

    if bAnyButtonClick then
        CAudio.ResetSync()
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

CGameMode.bCanStart = false

CGameMode.bVictory = false

CGameMode.iDifficulty = 2

CGameMode.iHeroX = 2
CGameMode.iHeroY = 1
CGameMode.iHeroColor = CColors.BLUE

CGameMode.iHeroPlusX = 0
CGameMode.iHeroPlusY = 0

CGameMode.DIFFICULTY_WORLD_SIZE = {}
CGameMode.DIFFICULTY_WORLD_SIZE[1] = 20
CGameMode.DIFFICULTY_WORLD_SIZE[2] = 30
CGameMode.DIFFICULTY_WORLD_SIZE[3] = 40
CGameMode.DIFFICULTY_WORLD_SIZE[4] = 50

CGameMode.DIFFICULTY_TIMER = {}
CGameMode.DIFFICULTY_TIMER[1] = 300
CGameMode.DIFFICULTY_TIMER[2] = 250
CGameMode.DIFFICULTY_TIMER[3] = 200
CGameMode.DIFFICULTY_TIMER[4] = 150

CGameMode.init = function()
    CGameMode.iDifficulty = tConfig.Difficulty

    CWorld.init()

    CGameMode.HeroMove(0, 0)
    CCamera.FocusOnWorldPos(CGameMode.iHeroX, CGameMode.iHeroY)
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("mazeguide/mazeguide_gamename.mp3")
        CAudio.PlayVoicesSync("mazeguide/mazeguide_guide.mp3")
        AL.NewTimer((CAudio.GetVoicesDuration("mazeguide/mazeguide_guide.mp3"))*1000 + 3000, function()
            CGameMode.bCanStart = true
        end)
    else
        CGameMode.bCanStart = true
    end

    if not tConfig.AutoStart then
        CAudio.PlayVoicesSync("press-button-for-start.mp3")
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
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
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    AL.NewTimer(tConfig.MovementTick, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        if CWorld.tBlocks[CGameMode.iHeroX][CGameMode.iHeroY].iBlockType == CWorld.BLOCK_TYPE_FINISH then
            CGameMode.EndGame(true)
        end

        CGameMode.HeroMove(CGameMode.iHeroPlusX, CGameMode.iHeroPlusY)
        CCamera.FocusOnWorldPos(CGameMode.iHeroX, CGameMode.iHeroY)

        CGameMode.iHeroPlusX = 0
        CGameMode.iHeroPlusY = 0

        return tConfig.MovementTick
    end)

    if tConfig.TimerOn then
        tGameStats.StageLeftDuration = CGameMode.DIFFICULTY_TIMER[CGameMode.iDifficulty]
        AL.NewTimer(1000, function()
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
    CAudio.ResetSync()
    iGameState = GAMESTATE_POSTGAME

    if bVictory then
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN

        tGameResults.Score = (tConfig.Difficulty * 100 + tGameStats.StageLeftDuration) * 2 * tConfig.Difficulty
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
    end

    tGameResults.Won = bVictory

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)

    local iY = 1
    AL.NewTimer(240, function()
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
    if iXPlus ~= 0 and CWorld.tBlocks[CGameMode.iHeroX+iXPlus] and CWorld.tBlocks[CGameMode.iHeroX+iXPlus][CGameMode.iHeroY] 
    and CWorld.tBlocks[CGameMode.iHeroX+iXPlus][CGameMode.iHeroY].iBlockType ~= CWorld.BLOCK_TYPE_TERRAIN then
        CGameMode.iHeroX = CGameMode.iHeroX + iXPlus
        return;
    end

    if iYPlus ~= 0 and CWorld.tBlocks[CGameMode.iHeroX][CGameMode.iHeroY+iYPlus] 
    and CWorld.tBlocks[CGameMode.iHeroX][CGameMode.iHeroY+iYPlus].iBlockType ~= CWorld.BLOCK_TYPE_TERRAIN then
        CGameMode.iHeroY = CGameMode.iHeroY + iYPlus
    end    
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
        local bActive = false

        if iX == iHeroCamX or iY == iHeroCamY then
            tFloor[iX][iY].iBright = tFloor[iX][iY].iBright - 3
        end

        if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
            if iGameState == GAMESTATE_GAME then
                CGameMode.PlayerControl(iControlId, iX, iY)
            end
            bActive = true
        end        

        return bActive
    end

    for iY = 1, tGame.Rows do
        for iX = tGame.Cols-(tConfig.ControlPanelWidth-1), tGame.Cols do
            tFloor[iX][iY].iColor = CColors.WHITE
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end

    local bActive1 = false
    local bActive2 = false
    for iX = 1, tGame.Cols-2 do
        for iY = tGame.Rows-(tConfig.ControlPanelWidth-1), tGame.Rows do
            if paintpixel(iX, iY, CColors.MAGENTA, 1) then bActive1 = true; end
        end
    end

    for iY = 1, tGame.Rows-2 do
        for iX = tGame.Cols-(tConfig.ControlPanelWidth-1), tGame.Cols do
            if paintpixel(iX, iY, CColors.YELLOW, 2) then bActive2 = true; end
        end
    end

    if iGameState == GAMESTATE_SETUP and tConfig.AutoStart and bActive1 and bActive2 and CGameMode.bCanStart then
        bAnyButtonClick = true
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

CWorld.tCells = nil

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

    CWorld.tCells = AL.Stack()

    CWorld.tCells.Push({iX = 2, iY = 2,})
    while CWorld.tCells.Size() > 0 do
        CWorld.Carve(CWorld.tCells.PopLast())
    end
    
    CWorld.SetBlock(2, 1, CWorld.BLOCK_TYPE_START)
    CWorld.SetBlock(CWorld.iSizeX, CWorld.iSizeY+1, CWorld.BLOCK_TYPE_FINISH)
end

CWorld.Carve = function(tCell)
    CWorld.iDepth = CWorld.iDepth + 1

    local iX = tCell.iX
    local iY = tCell.iY

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
        if CWorld.tBlocks[iNX] and CWorld.tBlocks[iNX][iNY] and CWorld.tBlocks[iNX][iNY].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then
            local iNX2 = iNX + iDX
            local iNY2 = iNY + iDY            
            if CWorld.tBlocks[iNX2] and CWorld.tBlocks[iNX2][iNY2] and CWorld.tBlocks[iNX2][iNY2].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then
                CWorld.tBlocks[iNX][iNY].iBlockType = CWorld.BLOCK_TYPE_EMPTY
                CWorld.tCells.Push(tCell)
                CWorld.tCells.Push({iX = iNX2, iY = iNY2,})
                return;
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
                tFloor[click.X][click.Y].iWeight = click.Weight
            else
                AL.NewTimer(500, function()
                    tFloor[click.X][click.Y].bClick = false
                end)
            end

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and iGameState == GAMESTATE_GAME and tFloor[click.X] and tFloor[click.X][click.Y] and not tFloor[click.X][click.Y].bDefect and tFloor[click.X][click.Y].iControlId > 0 then
            CGameMode.PlayerControl(tFloor[click.X][click.Y].iControlId, click.X, click.Y)
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