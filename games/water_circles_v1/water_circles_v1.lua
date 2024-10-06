--[[
    Название: Название механики
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
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
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
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

    AL.NewTimer(tConfig.CircleTickTime, function()
        CCircles.Tick()

        return tConfig.CircleTickTime
    end)

    CAudio.PlaySyncFromScratch("")
    CAudio.PlayRandomBackground()
end

function NextTick()
    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)

    for iCircleId = 1, #CCircles.tCircles do
        if CCircles.tCircles[iCircleId] ~= nil then
            CCircles.PaintCircle(iCircleId)
        end
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

--
CCircles = {}
CCircles.tCircles = {}
CCircles.bSpawnDelayOn = false
CCircles.LastClickX = 0
CCircles.LastClickY = 0

CCircles.New = function(iX, iY)
    if CCircles.bSpawnDelayOn or (iX == CCircles.LastClickX and iY == CCircles.LastClickY) then return; end

    local iCircleId = #CCircles.tCircles+1

    CCircles.tCircles[iCircleId] = {}
    CCircles.tCircles[iCircleId].iX = iX
    CCircles.tCircles[iCircleId].iY = iY
    CCircles.tCircles[iCircleId].iSize = 1
    CCircles.tCircles[iCircleId].iColor = math.random(1,7)

    CCircles.LastClickX = iX
    CCircles.LastClickY = iY

    CCircles.bSpawnDelayOn = true
    AL.NewTimer(tConfig.CircleSpawnDelay, function()
        CCircles.bSpawnDelayOn = false
    end)
end

CCircles.Tick = function()
    for iCircleId = 1, #CCircles.tCircles do
        if CCircles.tCircles[iCircleId] ~= nil then
            CCircles.UpdateCircle(iCircleId)
        end
    end
end

CCircles.UpdateCircle = function(iCircleId)
    CCircles.tCircles[iCircleId].iSize = CCircles.tCircles[iCircleId].iSize + 1

    if CCircles.tCircles[iCircleId].iSize >= tConfig.MaxCircleSize then
        CCircles.tCircles[iCircleId] = nil
    end 
end

CCircles.PaintCircle = function(iCircleId)
    local iX = CCircles.tCircles[iCircleId].iX
    local iY = CCircles.tCircles[iCircleId].iY
    local iSize = CCircles.tCircles[iCircleId].iSize
    local iSize2 = 3-2*iSize

    for i = 0, iSize do
        CCircles.PaintCirclePixel(iCircleId, iX + i, iY + iSize)
        CCircles.PaintCirclePixel(iCircleId, iX + i, iY - iSize)
        CCircles.PaintCirclePixel(iCircleId, iX - i, iY + iSize)
        CCircles.PaintCirclePixel(iCircleId, iX - i, iY - iSize)

        CCircles.PaintCirclePixel(iCircleId, iX + iSize, iY + i)
        CCircles.PaintCirclePixel(iCircleId, iX + iSize, iY - i)
        CCircles.PaintCirclePixel(iCircleId, iX - iSize, iY + i)
        CCircles.PaintCirclePixel(iCircleId, iX - iSize, iY - i)

        if iSize2 < 0 then
            iSize2 = iSize2 + 4*i + 6
        else
            iSize2 = iSize2 + 4*(i-iSize) + 10
            iSize = iSize - 1
        end
    end
end

CCircles.PaintCirclePixel = function(iCircleId, iX, iY)

    for iX2 = iX-1, iX+1 do
        if tFloor[iX2] and tFloor[iX2][iY] then
            tFloor[iX2][iY].iColor = CCircles.tCircles[iCircleId].iColor
            
            tFloor[iX2][iY].iBright = tConfig.Bright-2
            if iX2 == iX then
                tFloor[iX2][iY].iBright = tConfig.Bright
            end
        end
    end
end
--//

--LIB
_G.AL = {}
local LOC = {}

--STACK
AL.Stack = function()
    local tStack = {}
    tStack.tTable = {}

    tStack.Push = function(item)
        table.insert(tStack.tTable, item)
    end

    tStack.Pop = function()
        return table.remove(tStack.tTable, 1)
    end

    tStack.PopLast = function()
        return table.remove(tStack.tTable, #tStack.tTable)
    end

    tStack.Size = function()
        return #tStack.tTable
    end

    return tStack
end
--//

--TIMER
local tTimers = AL.Stack()

AL.NewTimer = function(iSetTime, fCallback)
    tTimers.Push({iTime = iSetTime, fCallback = fCallback})
end

AL.CountTimers = function(iTimePassed)
    for i = 1, tTimers.Size() do
        local tTimer = tTimers.Pop()

        tTimer.iTime = tTimer.iTime - iTimePassed

        if tTimer.iTime <= 0 then
            local iNewTime = tTimer.fCallback()
            if iNewTime then
                tTimer.iTime = tTimer.iTime + iNewTime
            else
                tTimer = nil
            end
        end

        if tTimer then
            tTimers.Push(tTimer)
        end
    end
end
--//

--RECT
function AL.RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end
--//
-----

--UTIL прочие утилиты

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

    if click.Click and not tFloor[click.X][click.Y].bDefect then
        CCircles.New(click.X, click.Y)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
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