    --[[
    Название: День Рождения
    Автор: Avondale, дискорд - avonda

    Выбор фонов:
        - Название фона вписывается в настройку "BackgroundName"
        
        Список фонов:
            "test" - тортик с огоньками

    Написание текста:
        - Текст пишется в настройку "Text"
        - Поддерживаются цифры 0-9 и символы ! ?
        - При нехватке места на строке буквы переносятся на следующую
        - В среднем максимум в строке 5 символов, но зависит от их ширины

        Поддерживаются только русские ЗАГЛАВНЫЕ буквы
        
        Если буква неопределена - вместо неё будет нарисован квадрат 4x5

    Выбор музыки:
        - Название звука вписывается в настройку "Music"


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

    CPaint.sBackgroundName = tConfig.BackgroundName
    CPaint.iTextColor = tConfig.TextColor
    CPaint.bAnimateText = tConfig.TextAnimation == 1

    CPaint.BackgroundFrameTimerStart()

    if CPaint.bAnimateText then
        CPaint.AnimateTextTimerStart()
    end

    CAudio.PlayBackground(tConfig.Music)
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
    CPaint.Text()
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

CPaint.PaintBG = function()
    if CPaint.sBackgroundName == "" then return end

    local tBg = tGame.Backgrounds[CPaint.sBackgroundName][CPaint.iBackgroundFrameId]

    for iY = 1, tGame.Rows do
        for iX = 1, tGame.Cols do
            tFloor[iX][iY].iColor = tBg[iY][iX]
            tFloor[iX][iY].iBright = tConfig.Bright
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

CPaint.AnimateTextTimerStart = function()
    CTimer.New(tConfig.AnimationDelay, function()
        CPaint.iTextAnimationFrame = CPaint.iTextAnimationFrame + 1
        if CPaint.iTextAnimationFrame == 5 then CPaint.iTextAnimationFrame = 1 end

        if iGameState == GAMESTATE_GAME then
            return tConfig.AnimationDelay
        end

        return nil        
    end)
end

CPaint.Text = function()
    local sText = tConfig.Text
    local iX = 0
    local iY = 1

    if CPaint.bAnimateText then
        iY = 4
    end

    for i = 1, #sText do
        local tLetter = tLoadedLetters["default"]
        local iLetterByte = sText:byte(i)
        CLog.print(i.." "..iLetterByte)
        if iLetterByte ~= 208 then
            if tLoadedLetters[iLetterByte] ~= nil then
                tLetter = tLoadedLetters[iLetterByte]
            end

            local iAnimY = 0
            if CPaint.bAnimateText and CPaint.iTextAnimationFrame % 2 ~= 0 then
                if (CPaint.iTextAnimationFrame == 1 and i % 2 ~= 0) or (CPaint.iTextAnimationFrame == 3 and i % 2 == 0) then
                    iAnimY = -2
                else
                    iAnimY = 2
                end
            end

            for iLocalY = 1, tLetter.iSizeY do
                for iLocalX = 1, tLetter.iSizeX do
                    if tLetter.tPaint[iLocalY][iLocalX] == 1 then
                        if tFloor[iX+iLocalX] and tFloor[iX+iLocalX][iY+iLocalY+iAnimY] then
                            tFloor[iX+iLocalX][iY+iLocalY+iAnimY].iColor = CPaint.iTextColor
                            tFloor[iX+iLocalX][iY+iLocalY+iAnimY].iBright = tConfig.Bright
                        end
                    end
                end
            end

            iX = iX + tLetter.iSizeX+1
            if (iX + 4) > tGame.Cols then
                iX = 0
                iY = iY + 7
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

tLoadedLetters = {}

tLoadedLetters["default"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 1, 1, 1},
        {1, 1, 1, 1},
        {1, 1, 1, 1},
        {1, 1, 1, 1}
    }
}
tLoadedLetters["DEFAULT"] = tLoadedLetters["default"]

tLoadedLetters[" "] =
{
    iSizeX = 1,
    iSizeY = 5,
    tPaint = {
        {0,},
        {0,},
        {0,},
        {0,},
        {0,}
    }
}
tLoadedLetters[32] = tLoadedLetters[" "]

tLoadedLetters["!"] =
{
    iSizeX = 1,
    iSizeY = 5,
    tPaint = {
        {1,},
        {1,},
        {1,},
        {0,},
        {1,}
    }
}

tLoadedLetters[33] = tLoadedLetters["!"]

tLoadedLetters["?"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 0},
        {0, 0, 0, 1},
        {0, 1, 1, 1},
        {0, 0, 0, 0},
        {0, 1, 0, 0}
    }
}
tLoadedLetters[63] = tLoadedLetters["?"]

tLoadedLetters["0"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1,},
        {1, 0, 1,},
        {1, 0, 1,},
        {1, 0, 1,},
        {1, 1, 1,}
    }
}
tLoadedLetters[48] = tLoadedLetters["0"]

tLoadedLetters["1"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {0, 1, 0,},
        {1, 1, 0,},
        {0, 1, 0,},
        {0, 1, 0,},
        {1, 1, 1,}
    }
}
tLoadedLetters[49] = tLoadedLetters["1"]

tLoadedLetters["2"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 1, 0, 0},
        {1, 1, 1, 1}
    }
}
tLoadedLetters[50] = tLoadedLetters["2"]

tLoadedLetters["3"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}
tLoadedLetters[51] = tLoadedLetters["3"]

tLoadedLetters["4"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 0, 1, 0},
        {0, 1, 1, 0},
        {1, 0, 1, 0},
        {1, 1, 1, 1},
        {0, 0, 1, 0}
    }
}
tLoadedLetters[52] = tLoadedLetters["4"]

tLoadedLetters["5"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 1},
        {1, 1, 1, 0}
    }
}
tLoadedLetters[53] = tLoadedLetters["5"]

tLoadedLetters["6"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}
tLoadedLetters[54] = tLoadedLetters["6"]

tLoadedLetters["7"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 0, 1, 0}
    }
}
tLoadedLetters[55] = tLoadedLetters["7"]

tLoadedLetters["8"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}
tLoadedLetters[56] = tLoadedLetters["8"]

tLoadedLetters["9"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0}
    }
}
tLoadedLetters[57] = tLoadedLetters["9"]

tLoadedLetters["А"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {1, 1, 1, 1},
        {1, 0, 0, 1},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["а"] = tLoadedLetters["А"]
tLoadedLetters["A"] = tLoadedLetters["А"]
tLoadedLetters[65] = tLoadedLetters["А"]
tLoadedLetters[144] = tLoadedLetters["А"]

tLoadedLetters["Б"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 0},
        {1, 1, 1, 1},
        {1, 0, 0, 1},
        {1, 1, 1, 1}
    }
}
tLoadedLetters["б"] = tLoadedLetters["Б"]
tLoadedLetters[145] = tLoadedLetters["Б"]

tLoadedLetters["В"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, },
        {1, 0, 1, },
        {1, 1, 0, },
        {1, 0, 1, },
        {1, 1, 1, }
    }
}
tLoadedLetters["в"] = tLoadedLetters["В"]
tLoadedLetters[146] = tLoadedLetters["В"]

tLoadedLetters["Г"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, },
        {1, 0, 0, },
        {1, 0, 0, },
        {1, 0, 0, },
        {1, 0, 0, }
    }
}
tLoadedLetters["г"] = tLoadedLetters["Г"]
tLoadedLetters[147] = tLoadedLetters["Г"]

tLoadedLetters["Д"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 1, 0},
        {0, 1, 0, 1, 0},
        {0, 1, 0, 1, 0},
        {1, 1, 1, 1, 1},
        {1, 0, 0, 0, 1}
    }
}
tLoadedLetters["д"] = tLoadedLetters["Д"]
tLoadedLetters[148] = tLoadedLetters["Д"]

tLoadedLetters["Е"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1,},
        {1, 0, 0,},
        {1, 1, 1,},
        {1, 0, 0,},
        {1, 1, 1,}
    }
}
tLoadedLetters["е"] = tLoadedLetters["Е"]
tLoadedLetters[149] = tLoadedLetters["Е"]
tLoadedLetters["ё"] = tLoadedLetters["Е"]
tLoadedLetters["Ё"] = tLoadedLetters["Е"]
tLoadedLetters[129] = tLoadedLetters["Е"]

tLoadedLetters["Ж"] =
{
    iSizeX = 7,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 1, 0, 0, 1,},
        {0, 1, 0, 1, 0, 1, 0,},
        {0, 0, 1, 1, 1, 0, 0,},
        {0, 1, 0, 1, 0, 1, 0,},
        {1, 0, 0, 1, 0, 0, 1,}
    }
}
tLoadedLetters["ж"] = tLoadedLetters["Ж"]
tLoadedLetters[150] = tLoadedLetters["Ж"]

tLoadedLetters["З"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, },
        {0, 0, 1, },
        {0, 1, 1, },
        {0, 0, 1, },
        {1, 1, 1, }
    }
}
tLoadedLetters["з"] = tLoadedLetters["З"]
tLoadedLetters[151] = tLoadedLetters["З"]

tLoadedLetters["И"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 0, 1},
        {1, 0, 0, 1, 1},
        {1, 0, 1, 0, 1},
        {1, 1, 0, 0, 1},
        {1, 0, 0, 0, 1}
    }
}
tLoadedLetters["и"] = tLoadedLetters["И"]
tLoadedLetters[152] = tLoadedLetters["И"]
tLoadedLetters["Й"] = tLoadedLetters["И"]
tLoadedLetters["й"] = tLoadedLetters["И"]
tLoadedLetters[153] = tLoadedLetters["И"]

tLoadedLetters["К"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 1},
        {1, 0, 1, 0},
        {1, 1, 0, 0},
        {1, 0, 1, 0},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["к"] = tLoadedLetters["К"]
tLoadedLetters[154] = tLoadedLetters["К"]

tLoadedLetters["Л"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 1},
        {0, 1, 0, 1},
        {0, 1, 0, 1},
        {0, 1, 0, 1},
        {1, 1, 0, 1}
    }
}
tLoadedLetters["л"] = tLoadedLetters["Л"]
tLoadedLetters[155] = tLoadedLetters["Л"]

tLoadedLetters["М"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 0, 1},
        {1, 1, 0, 1, 1},
        {1, 0, 1, 0, 1},
        {1, 0, 0, 0, 1},
        {1, 0, 0, 0, 1}
    }
}
tLoadedLetters["м"] = tLoadedLetters["М"]
tLoadedLetters[156] = tLoadedLetters["М"]

tLoadedLetters["Н"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 1},
        {1, 0, 0, 1},
        {1, 1, 1, 1},
        {1, 0, 0, 1},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["н"] = tLoadedLetters["Н"]
tLoadedLetters[157] = tLoadedLetters["Н"]

tLoadedLetters["О"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {0, 1, 0,},
        {1, 0, 1,},
        {1, 0, 1,},
        {1, 0, 1,},
        {0, 1, 0,}
    }
}
tLoadedLetters["о"] = tLoadedLetters["О"]
tLoadedLetters[158] = tLoadedLetters["О"]

tLoadedLetters["П"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 1},
        {1, 0, 0, 1},
        {1, 0, 0, 1},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["п"] = tLoadedLetters["П"]
tLoadedLetters[159] = tLoadedLetters["П"]

tLoadedLetters["Р"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 0},
        {1, 0, 0, 1},
        {1, 1, 1, 0},
        {1, 0, 0, 0},
        {1, 0, 0, 0}
    }
}
tLoadedLetters["р"] = tLoadedLetters["Р"]
tLoadedLetters[160] = tLoadedLetters["Р"]

tLoadedLetters["С"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, },
        {1, 0, 0, },
        {1, 0, 0, },
        {1, 0, 0, },
        {1, 1, 1, }
    }
}
tLoadedLetters["с"] = tLoadedLetters["С"]
tLoadedLetters[161] = tLoadedLetters["С"]

tLoadedLetters["Т"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1},
        {0, 1, 0},
        {0, 1, 0},
        {0, 1, 0},
        {0, 1, 0}
    }
}
tLoadedLetters["т"] = tLoadedLetters["Т"]
tLoadedLetters[162] = tLoadedLetters["Т"]

tLoadedLetters["У"] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {1, 0, 1},
        {1, 0, 1},
        {1, 1, 1},
        {0, 0, 1},
        {1, 1, 1}
    }
}
tLoadedLetters["у"] = tLoadedLetters["У"]
tLoadedLetters[163] = tLoadedLetters["У"]

tLoadedLetters["Ф"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 1, 0},
        {1, 0, 1, 0, 1},
        {0, 1, 1, 1, 0},
        {0, 0, 1, 0, 0},
        {0, 0, 1, 0, 0}
    }
}
tLoadedLetters["ф"] = tLoadedLetters["Ф"]
tLoadedLetters[164] = tLoadedLetters["Ф"]

tLoadedLetters["Х"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 1},
        {1, 0, 0, 1},
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["х"] = tLoadedLetters["Х"]
tLoadedLetters[165] = tLoadedLetters["Х"]

    tLoadedLetters["Ц"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 1, 0},
        {1, 0, 1, 0},
        {1, 0, 1, 0},
        {1, 1, 1, 1},
        {0, 0, 0, 1}
    }
}
tLoadedLetters["ц"] = tLoadedLetters["Ц"]
tLoadedLetters[166] = tLoadedLetters["Ц"]

tLoadedLetters["Ч"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 1},
        {1, 0, 0, 1},
        {1, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 0, 1}
    }
}
tLoadedLetters["ч"] = tLoadedLetters["Ч"]
tLoadedLetters[167] = tLoadedLetters["Ч"]

tLoadedLetters["Ш"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {1, 0, 1, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 1, 1, 1, 1}
    }
}
tLoadedLetters["ш"] = tLoadedLetters["Ш"]
tLoadedLetters[168] = tLoadedLetters["Ш"]
tLoadedLetters["Щ"] = tLoadedLetters["Ш"]
tLoadedLetters["щ"] = tLoadedLetters["Ш"]
tLoadedLetters[169] = tLoadedLetters["Ш"]

tLoadedLetters["Ъ"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 0, 0},
        {0, 1, 0, 0},
        {0, 1, 1, 1},
        {0, 1, 0, 1},
        {0, 1, 1, 1}
    }
}
tLoadedLetters["ъ"] = tLoadedLetters["Ъ"]
tLoadedLetters[170] = tLoadedLetters["Ъ"]

tLoadedLetters["Ы"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0, 0, 1},
        {1, 0, 0, 0, 1},
        {1, 1, 1, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 1, 1, 0, 1}
    }
}
tLoadedLetters["ы"] = tLoadedLetters["Ы"]
tLoadedLetters[171] = tLoadedLetters["Ы"]

tLoadedLetters["Ь"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 0, 0},
        {1, 0, 0},
        {1, 1, 1},
        {1, 0, 1},
        {1, 1, 1}
    }
}
tLoadedLetters["ь"] = tLoadedLetters["Ь"]
tLoadedLetters[172] = tLoadedLetters["Ь"]

tLoadedLetters["Э"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 0},
        {0, 0, 0, 1},
        {0, 1, 1, 1},
        {0, 0, 0, 1},
        {1, 1, 1, 0}
    }
}
tLoadedLetters["э"] = tLoadedLetters["Э"]
tLoadedLetters[173] = tLoadedLetters["Э"]

tLoadedLetters["Ю"] =
{
    iSizeX = 5,
    iSizeY = 5,
    tPaint = {
        {1, 0, 1, 1, 1},
        {1, 0, 1, 0, 1},
        {1, 1, 1, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 0, 1, 1, 1}
    }
}
tLoadedLetters["ю"] = tLoadedLetters["Ю"]
tLoadedLetters[174] = tLoadedLetters["Ю"]

tLoadedLetters["Я"] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 1},
        {1, 1, 1, 1},
        {0, 1, 0, 1},
        {1, 0, 0, 1}
    }
}
tLoadedLetters["я"] = tLoadedLetters["Я"]
tLoadedLetters[175] = tLoadedLetters["Я"]