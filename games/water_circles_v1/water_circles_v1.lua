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

    CTimer.New(tConfig.CircleTickTime, function()
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

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
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

CCircles.New = function(iX, iY)
    local iCircleId = #CCircles.tCircles+1

    CCircles.tCircles[iCircleId] = {}
    CCircles.tCircles[iCircleId].iX = iX
    CCircles.tCircles[iCircleId].iY = iY
    CCircles.tCircles[iCircleId].iSize = 1
    CCircles.tCircles[iCircleId].iColor = math.random(1,7)
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