    --[[
    Название: Заставка - Герои
    Автор: Avondale, дискорд - avonda

    Выбор фонов:
        - Название фона вписывается в настройку "BackgroundName"
        
        Список фонов:
            "minion" - миньон
            "creeper" - крипер
            "skull" - череп
            "amongus" - амогус
            "hulk" - халк
            "batsign" - лого бэтмена
            "marvel" - железный человек и капитан америка
            "mario" - марио


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

    CPaint.OffsetTimer()

    CPaint.sBackgroundName = tConfig.BackgroundName
    CPaint.BackgroundFrameTimerStart()

    if CPaint.sBackgroundName ~= "" then
        CAudio.PlayBackground("backgrounds/heroes/"..CPaint.sBackgroundName..".mp3")
    end
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
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CPaint.PaintBG()
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

--Paint
CPaint = {}
CPaint.sBackgroundName = ""
CPaint.iBackgroundFrameId = 1

CPaint.iTextColor = 1
CPaint.bAnimateText = false
CPaint.iTextAnimationFrame = 1

CPaint.iOffset = 0

CPaint.PaintBG = function()
    local tBg = nil
    if CPaint.sBackgroundName ~= "" then
        tBg = tGame.Backgrounds[CPaint.sBackgroundName][CPaint.iBackgroundFrameId]
    end

    local iX = 0
    local iXInc = 1
    local iY = 0
    local iYInc = 1

    if tConfig.MirrorImage then 
        iX = tGame.Cols+1
        iXInc = -1
        iY = tGame.Rows+1
        iYInc = -1
    end

    local iXStart = iX

    for iBGY = 1, tGame.Rows do
        iX = iXStart
        iY = iY + iYInc
        for iBGX = 1, tGame.Cols do
            iX = iX + iXInc

            local tBackgroundColor = CPaint.GetBackgroundColor(iX, iY)
            if tBackgroundColor ~= nil then
                tFloor[iX][iY].iColor = tBackgroundColor.color
                tFloor[iX][iY].iBright = tBackgroundColor.bright
            end

            if tBg ~= nil and tBg[iBGY][iBGX] ~= 8 then
                tFloor[iX][iY].iColor = tBg[iBGY][iBGX]
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
    end
end

CPaint.BackgroundFrameTimerStart = function()
    if CPaint.sBackgroundName == "" then return end

    CTimer.New(tConfig.AnimationDelay, function()
        CPaint.iBackgroundFrameId = CPaint.iBackgroundFrameId + 1

        if CPaint.iBackgroundFrameId > #tGame.Backgrounds[CPaint.sBackgroundName] then
            CPaint.iBackgroundFrameId = 1
        end

        if iGameState == GAMESTATE_GAME then
            return tConfig.AnimationDelay
        end

        return nil
    end)
end

CPaint.OffsetTimer = function()
    CTimer.New(tConfig.AnimationDelay, function()
        CPaint.iOffset = CPaint.iOffset + 1

        return tConfig.AnimationDelay
    end)
end

CPaint.GetBackgroundColor = function(iX, iY)
    local iId = math.floor((iX + iY + CPaint.iOffset) %(#tGame.Colors))

    if iId == 0 then iId = 1 end

    return tGame.Colors[iId]
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