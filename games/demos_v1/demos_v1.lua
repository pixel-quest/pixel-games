--[[
    Название: Анимированные заставки
    Автор: Avondale, дискорд - avonda
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
local iGameState = GAMESTATE_GAME
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
    TargetScore = 0,
    StageNum = 0,
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
    iParticleID = 0,
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
    CPaint.LoadDemo(tConfig.DemoName)
    CPaint.DemoThinker(tConfig.DemoName)
end

function NextTick()
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

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Demo(tConfig.DemoName)
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

--PAINT
CPaint = {}

CPaint.FUNC_LOAD = 1
CPaint.FUNC_PAINT = 2
CPaint.FUNC_THINK = 3

CPaint.LoadDemo = function(sDemoName)
    CPaint.tDemoList[sDemoName][CPaint.FUNC_LOAD]()
end

CPaint.Demo = function(sDemoName)
    CPaint.tDemoList[sDemoName][CPaint.FUNC_PAINT]()
end

CPaint.DemoThinker = function(sDemoName)
    AL.NewTimer(CPaint.tDemoList[sDemoName].THINK_DELAY, function()
        if CPaint.tDemoList[sDemoName][CPaint.FUNC_THINK]() and iGameState == GAMESTATE_GAME then return CPaint.tDemoList[sDemoName].THINK_DELAY end 
    end)
end
--//

----DEMO LIST
CPaint.tDemoList = {}

--MATRIX
CPaint.tDemoList["matrix"] = {}
CPaint.tDemoList["matrix"].THINK_DELAY = 120
CPaint.tDemoList["matrix"].COLOR = "0x00ff0a"
CPaint.tDemoList["matrix"].tVars = {}
CPaint.tDemoList["matrix"].tVars.tParticles = {}
CPaint.tDemoList["matrix"][CPaint.FUNC_LOAD] = function()
    local function randX()
        local iX = 0
        repeat iX = math.random(1, tGame.Cols)
        until tFloor[iX][1].iColor == CColors.NONE

        return iX
    end

    AL.NewTimer(400, function()
        for iParticle = 1, math.random(0,2) do
            local iParticleID = #CPaint.tDemoList["matrix"].tVars.tParticles+1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] = {}
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX = randX()
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY = 1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize = math.random(7, 20)
        end

        if iGameState == GAMESTATE_GAME then return 400; end
    end)
end
CPaint.tDemoList["matrix"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    for iParticleID = 1, #CPaint.tDemoList["matrix"].tVars.tParticles do
        if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] then
            for iY = CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY - CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize, CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY do
                if iY >= 1 and iY <= tGame.Rows then
                    local iBright = (10 + math.floor(CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize/4)) + (iY - CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY)
                    if iBright > 10 then iBright = 10 end
                    if iBright < 0 then iBright = 0 end
                    tFloor[CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX][iY].iColor = tonumber(CPaint.tDemoList["matrix"].COLOR)
                    tFloor[CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX][iY].iBright = iBright
                end
            end
        end
    end
end
CPaint.tDemoList["matrix"][CPaint.FUNC_THINK] = function()

    for iParticleID = 1, #CPaint.tDemoList["matrix"].tVars.tParticles do
        if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] then
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY =  CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY + 1
            if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY > tGame.Rows + CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize+1 then
                CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] = nil
            end
        end
    end

    return true
end
--//

--DERBY
CPaint.tDemoList["derby"] = {}
CPaint.tDemoList["derby"].THINK_DELAY = 200
CPaint.tDemoList["derby"].COLOR = "0xFF00FF"
CPaint.tDemoList["derby"].tVars = {}
CPaint.tDemoList["derby"].tVars.tParticles = {}
CPaint.tDemoList["derby"][CPaint.FUNC_LOAD] = function()
    local function randXY()
        local iX = 0
        local iY = 0
        repeat iX = math.random(1, tGame.Cols); iY = math.random(1, tGame.Rows)
        until tFloor[iX][iY].iColor == CColors.NONE

        return iX, iY
    end

    for iParticleID = 1, math.abs(tGame.Cols - tGame.Rows) do
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID] = {}
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY = randXY()
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY = 0

        AL.NewTimer(1, function()
            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = math.random(1, tGame.Cols)
            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = math.random(1, tGame.Rows)

            if iGameState == GAMESTATE_GAME then return math.random(200, 5000); end
        end)
    end
end
CPaint.tDemoList["derby"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.MAGENTA, tConfig.Bright)

    local function paintPixel(iX, iY, iBright, iParticleID)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = tonumber(CPaint.tDemoList["derby"].COLOR)
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iParticleID = iParticleID
        end
    end

    for iParticleID = 1, #CPaint.tDemoList["derby"].tVars.tParticles do
        if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX > 0 then
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX-1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX+1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY-1, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY+1, tConfig.Bright-2, iParticleID)
        end

        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX+1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX-1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY+1, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY-1, tConfig.Bright, iParticleID)

        if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX > 0 then
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-1, iParticleID)
        end

        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright-1, iParticleID)
    end
end
CPaint.tDemoList["derby"][CPaint.FUNC_THINK] = function()
    for iParticleID = 1, #CPaint.tDemoList["derby"].tVars.tParticles do
        local iXPlus = 0
        local iYPlus = 0

        if math.random(0,1) == 0 then
            if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX < CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX then
                iXPlus = 1
            elseif CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX > CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX then
                iXPlus = -1
            end
        end
        if math.random(0,1) == 1 then
            if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY < CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY then
                iYPlus = 1
            elseif CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY > CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY then
                iYPlus = -1
            end        
        end

        if iXPlus ~= 0 or iYPlus ~= 0 then
            if tFloor[CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus][CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus].iParticleID == 0 
            or tFloor[CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus][CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus].iParticleID == iParticleID then
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY

                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus
            end
        end
    end

    return true
end
--//

--RAINBOWWAVE
CPaint.tDemoList["rainbowwave"] = {}
CPaint.tDemoList["rainbowwave"].THINK_DELAY = 100
CPaint.tDemoList["rainbowwave"].SIZE = 1
CPaint.tDemoList["rainbowwave"].COLORS = {CColors.RED, CColors.YELLOW, CColors.GREEN, CColors.CYAN, CColors.BLUE, CColors.MAGENTA}
CPaint.tDemoList["rainbowwave"].tVars = {}
CPaint.tDemoList["rainbowwave"].tVars.tParticles = {}
CPaint.tDemoList["rainbowwave"].tVars.iNextY = 1
CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus = 1
CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = 1
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowwave"].SIZE = math.floor(tGame.Rows/3)
    CPaint.tDemoList["rainbowwave"].tVars.iNextY = math.floor(tGame.Rows/2 - CPaint.tDemoList["rainbowwave"].SIZE/2)

    AL.NewTimer(700, function()
        CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = CPaint.tDemoList["rainbowwave"].tVars.iColorOffset + 1

        if iGameState == GAMESTATE_GAME then return 500; end
    end)

    AL.NewTimer(200, function()
        CPaint.tDemoList["rainbowwave"].tVars.iNextY = CPaint.tDemoList["rainbowwave"].tVars.iNextY + CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus
        if CPaint.tDemoList["rainbowwave"].tVars.iNextY+CPaint.tDemoList["rainbowwave"].SIZE-1 == tGame.Rows or CPaint.tDemoList["rainbowwave"].tVars.iNextY == 1 then
           CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus = -CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus 
        end

        if iGameState == GAMESTATE_GAME then return 200; end
    end)
end
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_PAINT] = function()
    for iParticleID = 1, #CPaint.tDemoList["rainbowwave"].tVars.tParticles do
        if CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID] then
            for iY = CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iY, CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iY + CPaint.tDemoList["rainbowwave"].SIZE-1 do
                local iColorID = math.floor(((CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iY + CPaint.tDemoList["rainbowwave"].SIZE-1 - iY) + CPaint.tDemoList["rainbowwave"].tVars.iColorOffset) %(#CPaint.tDemoList["rainbowwave"].COLORS))
                if iColorID == 0 then iColorID = #CPaint.tDemoList["rainbowwave"].COLORS end
                tFloor[CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX][iY].iColor = CPaint.tDemoList["rainbowwave"].COLORS[iColorID]
                tFloor[CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX][iY].iBright = tConfig.Bright
            end
        end
    end
end
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_THINK] = function()
    local iNewParticleID = #CPaint.tDemoList["rainbowwave"].tVars.tParticles+1
    CPaint.tDemoList["rainbowwave"].tVars.tParticles[iNewParticleID] = {}
    CPaint.tDemoList["rainbowwave"].tVars.tParticles[iNewParticleID].iX = tGame.Cols+1
    CPaint.tDemoList["rainbowwave"].tVars.tParticles[iNewParticleID].iY = CPaint.tDemoList["rainbowwave"].tVars.iNextY

    for iParticleID = 1, #CPaint.tDemoList["rainbowwave"].tVars.tParticles do
        if CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID] then
            CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX = CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX-1
            if CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX < 1 then
                CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID] = nil
            end
        end
    end

    return true
end
--//

--RAINBOWSNAKE
CPaint.tDemoList["rainbowsnake"] = {}
CPaint.tDemoList["rainbowsnake"].THINK_DELAY = 30
CPaint.tDemoList["rainbowsnake"].START_COLORS = {"0x0088FF", "0xFFAA00", "0xFF7700", "0xFF0033", "0x9911AA", "0xAADD22"}
CPaint.tDemoList["rainbowsnake"].tVars = {}
CPaint.tDemoList["rainbowsnake"].tVars.iColor = tonumber(CPaint.tDemoList["rainbowsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["rainbowsnake"].START_COLORS)])
CPaint.tDemoList["rainbowsnake"].tVars.iColorCount = 0
CPaint.tDemoList["rainbowsnake"].tVars.iX = 0
CPaint.tDemoList["rainbowsnake"].tVars.iY = 1
CPaint.tDemoList["rainbowsnake"].tVars.tBlocks = {}
CPaint.tDemoList["rainbowsnake"].tVars.tParticles = {}
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_LOAD] = function()
    for iX = 1, tGame.Cols do
        CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX][iY] = CColors.NONE
        end
    end

    AL.NewTimer(10, function()
        CPaint.tDemoList["rainbowsnake"].tVars.iColor = CPaint.tDemoList["rainbowsnake"].tVars.iColor - 1
        CPaint.tDemoList["rainbowsnake"].tVars.iColorCount = CPaint.tDemoList["rainbowsnake"].tVars.iColorCount + 1
        if CPaint.tDemoList["rainbowsnake"].tVars.iColorCount >= 255 then 
            if math.random(1,2) == 1 then
                CPaint.tDemoList["rainbowsnake"].tVars.iColor = CPaint.tDemoList["rainbowsnake"].tVars.iColor - 1600256
            else
                CPaint.tDemoList["rainbowsnake"].tVars.iColor = CPaint.tDemoList["rainbowsnake"].tVars.iColor - 3200256
            end
            if CPaint.tDemoList["rainbowsnake"].tVars.iColor <= 0 then
                CPaint.tDemoList["rainbowsnake"].tVars.iColor = tonumber(CPaint.tDemoList["rainbowsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["rainbowsnake"].START_COLORS)])
            end
            CPaint.tDemoList["rainbowsnake"].tVars.iColorCount = 0
        end

        if iGameState == GAMESTATE_GAME then return 10 end
    end)
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX][iY]
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_THINK] = function()
    CPaint.tDemoList["rainbowsnake"].tVars.iX = CPaint.tDemoList["rainbowsnake"].tVars.iX + 1
    if CPaint.tDemoList["rainbowsnake"].tVars.iX > tGame.Cols then CPaint.tDemoList["rainbowsnake"].tVars.iX = 1; CPaint.tDemoList["rainbowsnake"].tVars.iY = CPaint.tDemoList["rainbowsnake"].tVars.iY + 1; end    
    if CPaint.tDemoList["rainbowsnake"].tVars.iY > tGame.Rows then CPaint.tDemoList["rainbowsnake"].tVars.iY = 1; end

    CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[CPaint.tDemoList["rainbowsnake"].tVars.iX][CPaint.tDemoList["rainbowsnake"].tVars.iY] = CPaint.tDemoList["rainbowsnake"].tVars.iColor

    return true
end
--//

----//

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
            tFloor[iX][iY].iParticleID = 0
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
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end