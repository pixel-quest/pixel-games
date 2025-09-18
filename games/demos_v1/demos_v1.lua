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
    ScoreboardVariant = 10,
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
    CPaint.DemoThinker()
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
    CPaint.Demo()
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
CPaint.FUNC_CLICK = 4

CPaint.sLoadedDemo = ""

CPaint.LoadDemo = function(sDemoName)
    CPaint.sLoadedDemo = sDemoName
    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_LOAD]()
end

CPaint.Demo = function()
    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_PAINT]()
end

CPaint.UnloadDemo = function(fCallback)
    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(1100, function()
        iGameState = GAMESTATE_GAME
        fCallback()
    end)
end

CPaint.DemoThinker = function()
    AL.NewTimer(CPaint.tDemoList[CPaint.sLoadedDemo].THINK_DELAY, function()
        if CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_THINK]() and iGameState == GAMESTATE_GAME then return CPaint.tDemoList[CPaint.sLoadedDemo].THINK_DELAY end 
    end)

    if tConfig.SwitchEffects then
        AL.NewTimer(60000, function()
            if iGameState == GAMESTATE_GAME then
                CPaint.UnloadDemo(function()
                    CPaint.LoadDemo(tConfig.DemoName_List[math.random(1,#tConfig.DemoName_List-1)])
                    CPaint.DemoThinker()
                end)
            end
        end)
    end
end

CPaint.DemoClick = function(iX, iY)
    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_CLICK](iX, iY)
end
--//

----DEMO LIST
CPaint.tDemoList = {}

--MATRIX
CPaint.tDemoList["matrix"] = {}
CPaint.tDemoList["matrix"].THINK_DELAY = 120
CPaint.tDemoList["matrix"].COLOR = "0x00ff0a"
CPaint.tDemoList["matrix"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["matrix"].tVars = {}
    CPaint.tDemoList["matrix"].tVars.tParticles = {}

    local function randX()
        local iX = 0
        repeat iX = math.random(1, tGame.Cols)
        until tFloor[iX][1].iColor == CColors.NONE

        return iX
    end

    AL.NewTimer(200, function()
        for iParticle = 1, math.random(0,2) do
            local iParticleID = #CPaint.tDemoList["matrix"].tVars.tParticles+1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] = {}
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX = randX()
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY = 1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize = math.random(7, 20)
        end

        if iGameState == GAMESTATE_GAME then return 200; end
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
CPaint.tDemoList["matrix"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--MATRIX2
CPaint.tDemoList["matrix2"] = {}
CPaint.tDemoList["matrix2"].THINK_DELAY = 120
CPaint.tDemoList["matrix2"].COLOR = "0x00ff0a"
CPaint.tDemoList["matrix2"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["matrix2"].tVars = {}
    CPaint.tDemoList["matrix2"].tVars.tParticles = {}

    local function randY()
        local iY = 0
        repeat iY = math.random(1, tGame.Rows)
        until tFloor[1][iY].iColor == CColors.NONE

        return iY
    end

    AL.NewTimer(400, function()
        for iParticle = 1, math.random(0,2) do
            local iParticleID = #CPaint.tDemoList["matrix2"].tVars.tParticles+1
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] = {}
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY = randY()
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize = math.random(7, 20)
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX = tGame.Cols + CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize
        end

        if iGameState == GAMESTATE_GAME then return 400; end
    end)
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    for iParticleID = 1, #CPaint.tDemoList["matrix2"].tVars.tParticles do
        if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] then
            for iX = CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX + CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize do
                if iX >= 1 and iX <= tGame.Cols then
                    local iBright = (10 + math.floor(CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize/4)) - (iX - CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX)
                    if iBright > 10 then iBright = 10 end
                    if iBright < 0 then iBright = 0 end
                    tFloor[iX][CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY].iColor = tonumber(CPaint.tDemoList["matrix2"].COLOR)
                    tFloor[iX][CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY].iBright = iBright
                end
            end
        end
    end
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_THINK] = function()

    for iParticleID = 1, #CPaint.tDemoList["matrix2"].tVars.tParticles do
        if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] then
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX = CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX - 1
            if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX < 1 - CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize+1 then
                CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] = nil
            end
        end
    end

    return true
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--DERBY
CPaint.tDemoList["derby"] = {}
CPaint.tDemoList["derby"].THINK_DELAY = 200
CPaint.tDemoList["derby"].COLOR = "0xFF00FF"
CPaint.tDemoList["derby"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["derby"].tVars = {}
    CPaint.tDemoList["derby"].tVars.tParticles = {}

    local function randXY()
        local iX = 0
        local iY = 0
        repeat iX = math.random(1, tGame.Cols); iY = math.random(1, tGame.Rows)
        until tFloor[iX][iY].iColor == CColors.NONE

        return iX, iY
    end

    for iParticleID = 1, math.ceil(math.abs(tGame.Cols - tGame.Rows)/2) do
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID] = {}
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY = randXY()
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY = 0

        AL.NewTimer(1, function()
            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = math.random(1, tGame.Cols)
            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = math.random(1, tGame.Rows)

            if iGameState == GAMESTATE_GAME then return math.random(200, 500); end
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
CPaint.tDemoList["derby"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--RAINBOWWAVE
CPaint.tDemoList["rainbowwave"] = {}
CPaint.tDemoList["rainbowwave"].THINK_DELAY = 100
CPaint.tDemoList["rainbowwave"].SIZE = 1
CPaint.tDemoList["rainbowwave"].COLORS = 
{
    {CColors.RED, 3}, 
    {CColors.RED, 4}, 
    {CColors.RED, 5}, 
    {CColors.RED, 4}, 
    {CColors.RED, 3},  
    {CColors.YELLOW, 3}, 
    {CColors.YELLOW, 4}, 
    {CColors.YELLOW, 5}, 
    {CColors.YELLOW, 4}, 
    {CColors.YELLOW, 3},  
    {CColors.GREEN, 3}, 
    {CColors.GREEN, 4}, 
    {CColors.GREEN, 5}, 
    {CColors.GREEN, 4}, 
    {CColors.GREEN, 3}, 
    {CColors.CYAN, 3}, 
    {CColors.CYAN, 4}, 
    {CColors.CYAN, 5}, 
    {CColors.CYAN, 4}, 
    {CColors.CYAN, 3}, 
    {CColors.BLUE, 3}, 
    {CColors.BLUE, 4}, 
    {CColors.BLUE, 5}, 
    {CColors.BLUE, 4}, 
    {CColors.BLUE, 3}, 
    {CColors.MAGENTA, 3}, 
    {CColors.MAGENTA, 4}, 
    {CColors.MAGENTA, 5}, 
    {CColors.MAGENTA, 4}, 
    {CColors.MAGENTA, 3}, 
}

CPaint.tDemoList["rainbowwave"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowwave"].tVars = {}
    CPaint.tDemoList["rainbowwave"].tVars.tParticles = {}
    CPaint.tDemoList["rainbowwave"].tVars.iNextY = 1
    CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus = 1
    CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = 1

    CPaint.tDemoList["rainbowwave"].SIZE = math.floor(tGame.Rows/3)
    CPaint.tDemoList["rainbowwave"].tVars.iNextY = math.floor(tGame.Rows/2 - CPaint.tDemoList["rainbowwave"].SIZE/2)

    AL.NewTimer(200, function()
        CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = CPaint.tDemoList["rainbowwave"].tVars.iColorOffset + 1

        if iGameState == GAMESTATE_GAME then return 200; end
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
                tFloor[CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX][iY].iColor = CPaint.tDemoList["rainbowwave"].COLORS[iColorID][1]
                tFloor[CPaint.tDemoList["rainbowwave"].tVars.tParticles[iParticleID].iX][iY].iBright = CPaint.tDemoList["rainbowwave"].COLORS[iColorID][2]
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
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--RAINBOWSNAKE
CPaint.tDemoList["rainbowsnake"] = {}
CPaint.tDemoList["rainbowsnake"].THINK_DELAY = 30
CPaint.tDemoList["rainbowsnake"].START_COLORS = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}}
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowsnake"].tVars = {}
    CPaint.tDemoList["rainbowsnake"].tVars.tColor = CPaint.tDemoList["rainbowsnake"].START_COLORS[math.random(1,#CPaint.tDemoList["rainbowsnake"].START_COLORS)]
    CPaint.tDemoList["rainbowsnake"].tVars.iX = 0
    CPaint.tDemoList["rainbowsnake"].tVars.iY = 1
    CPaint.tDemoList["rainbowsnake"].tVars.tBlocks = {}
    CPaint.tDemoList["rainbowsnake"].tVars.tParticles = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX][iY] = CColors.NONE
        end
    end

    AL.NewTimer(10, function()
        CPaint.tDemoList["rainbowsnake"].tVars.tColor = RGBRainbowNextColor(CPaint.tDemoList["rainbowsnake"].tVars.tColor,1)

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

    CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[CPaint.tDemoList["rainbowsnake"].tVars.iX][CPaint.tDemoList["rainbowsnake"].tVars.iY] = tonumber(RGBTableToHex(CPaint.tDemoList["rainbowsnake"].tVars.tColor))

    return true
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--COLORSNAKE
CPaint.tDemoList["colorsnake"] = {}
CPaint.tDemoList["colorsnake"].THINK_DELAY = 30
CPaint.tDemoList["colorsnake"].START_COLORS = {"0x0088FF", "0xFFAA00", "0xFF7700", "0xFF0033", "0x9911AA", "0xAADD22"}
CPaint.tDemoList["colorsnake"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["colorsnake"].tVars = {}
    CPaint.tDemoList["colorsnake"].tVars.iColor = tonumber(CPaint.tDemoList["colorsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["colorsnake"].START_COLORS)])
    CPaint.tDemoList["colorsnake"].tVars.iColorCount = 0
    CPaint.tDemoList["colorsnake"].tVars.iX = 0
    CPaint.tDemoList["colorsnake"].tVars.iY = 1
    CPaint.tDemoList["colorsnake"].tVars.tBlocks = {}
    CPaint.tDemoList["colorsnake"].tVars.tParticles = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX][iY] = CColors.NONE
        end
    end

    AL.NewTimer(10, function()
        CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 1
        CPaint.tDemoList["colorsnake"].tVars.iColorCount = CPaint.tDemoList["colorsnake"].tVars.iColorCount + 1
        if CPaint.tDemoList["colorsnake"].tVars.iColorCount >= 255 then 
            if math.random(1,2) == 1 then
                CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 1600255
            else
                CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 3200255
            end
            if CPaint.tDemoList["colorsnake"].tVars.iColor <= 0 then
                CPaint.tDemoList["colorsnake"].tVars.iColor = tonumber(CPaint.tDemoList["colorsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["colorsnake"].START_COLORS)])
            end
            CPaint.tDemoList["colorsnake"].tVars.iColorCount = 0
        end

        if iGameState == GAMESTATE_GAME then return 10 end
    end)
end
CPaint.tDemoList["colorsnake"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX][iY]
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end
CPaint.tDemoList["colorsnake"][CPaint.FUNC_THINK] = function()
    CPaint.tDemoList["colorsnake"].tVars.iX = CPaint.tDemoList["colorsnake"].tVars.iX + 1
    if CPaint.tDemoList["colorsnake"].tVars.iX > tGame.Cols then CPaint.tDemoList["colorsnake"].tVars.iX = 1; CPaint.tDemoList["colorsnake"].tVars.iY = CPaint.tDemoList["colorsnake"].tVars.iY + 1; end    
    if CPaint.tDemoList["colorsnake"].tVars.iY > tGame.Rows then CPaint.tDemoList["colorsnake"].tVars.iY = 1; end

    CPaint.tDemoList["colorsnake"].tVars.tBlocks[CPaint.tDemoList["colorsnake"].tVars.iX][CPaint.tDemoList["colorsnake"].tVars.iY] = CPaint.tDemoList["colorsnake"].tVars.iColor

    return true
end
--//

--RAINBOWDEMO
CPaint.tDemoList["rainbowdemo"] = {}
CPaint.tDemoList["rainbowdemo"].THINK_DELAY = 120
CPaint.tDemoList["rainbowdemo"].NEARTABLES = {{0,-1},{-1,0},{1,0},{0,1},} 
CPaint.tDemoList["rainbowdemo"].START_COLORS = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}}
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowdemo"].tVars = {}
    CPaint.tDemoList["rainbowdemo"].tVars.tClicked = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY] = {}
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = false
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = {255,0,0}
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = tConfig.Bright
        end
    end

    AL.NewTimer(400, function()

        if iGameState == GAMESTATE_GAME then return 400; end
    end)
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked then
                tFloor[iX][iY].iColor = tonumber(RGBTableToHex(CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor))
                tFloor[iX][iY].iBright = CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright
            end
        end
    end
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_THINK] = function()

    return true
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_CLICK] = function(iX, iY)
    if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked then return; end

    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = true
    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = tConfig.Bright

    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = CPaint.tDemoList["rainbowdemo"].START_COLORS[math.random(1,#CPaint.tDemoList["rainbowdemo"].START_COLORS)]
    for iNear = 1, #CPaint.tDemoList["rainbowdemo"].NEARTABLES do
        local iXPlus, iYPlus = CPaint.tDemoList["rainbowdemo"].NEARTABLES[iNear][1], CPaint.tDemoList["rainbowdemo"].NEARTABLES[iNear][2]
        if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus] and CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus] and CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus].bClicked then
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = RGBRainbowNextColor(CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus].tColor, 10)
            break;
        end
    end

    AL.NewTimer(1000, function()
        if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright > 1 then
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright-1 
            return 100; 
        end

        CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = false
        return nil;
    end)
end
--//

----//

--UTIL прочие утилиты
function RGBToHex(r,g,b)
    local rgb = (r * 0x10000) + (g * 0x100) + b
    return "0x"..string.format("%06x", rgb)
end

function RGBTableToHex(tRGB)
    return RGBToHex(tRGB[1],tRGB[2],tRGB[3])
end

function RGBRainbowNextColor(tRGBIn, iMultiplier)
    local tRGB = {0,0,0}
    if iMultiplier == nil then iMultiplier = 1 end

    if (tRGBIn[1] > 0 and tRGBIn[3] == 0) then
        tRGB[1] = tRGBIn[1] - iMultiplier
        tRGB[2] = tRGBIn[2] + iMultiplier
    end

    if (tRGBIn[2] > 0 and tRGBIn[1] == 0) then
        tRGB[2] = tRGBIn[2] - iMultiplier
        tRGB[3] = tRGBIn[3] + iMultiplier
    end

    if (tRGBIn[3] > 0 and tRGBIn[2] == 0) then
        tRGB[1] = tRGBIn[1] + iMultiplier
        tRGB[3] = tRGBIn[3] - iMultiplier
    end

    return tRGB
end

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

        if iGameState == GAMESTATE_GAME and click.Click then
            CPaint.DemoClick(click.X, click.Y)
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
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end