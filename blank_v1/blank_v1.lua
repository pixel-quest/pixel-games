-- Название: Отладочный режим
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: отладочный режим подсветки шагов

local inspect = require("inspect")
local CLog = require("log")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 24, -- пикселей по горизонтали (X), обязательные параметр для всех игр
    Rows = 15, -- пикселей по вертикали (Y), обязательные параметр для всех игр
    RisingStepMs = 50,
    FadingStepMs = 200,
}
local tConfig = {}

local tStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
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

local tFloor = {} -- матрица пола
local tButtons = {} -- список кнопок

-- Базовый пиксель тип
local CPixel = {
    iX = 0,
    iY = 1,
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iTimestamp = CTime.unix(),
    bRising = false,
    bChanged = true, -- нужен, чтобы не перебивать команду глобального цвета
}

function CPixel:SetBright(iBright)
    if self.iBright ~= iBright then
        self.iBright = iBright
        self.bChanged = true
    end
end

function CPixel:ProcessTick()
    local iTimeSinceMs = (CTime.unix() - self.iTimestamp) * 1000
    if self.bRising then
        if iTimeSinceMs < 1*tGame.RisingStepMs then
            self:SetBright(CColors.BRIGHT15)
        elseif iTimeSinceMs < 2*tGame.RisingStepMs then
            self:SetBright(CColors.BRIGHT30)
        elseif iTimeSinceMs < 3*tGame.RisingStepMs then
            self:SetBright(CColors.BRIGHT45)
        elseif iTimeSinceMs < 4*tGame.RisingStepMs then
            self:SetBright(CColors.BRIGHT60)
        else
            self:SetBright(CColors.BRIGHT70)
        end
    else
        if iTimeSinceMs < 1*tGame.FadingStepMs then
            self:SetBright(CColors.BRIGHT60)
        elseif iTimeSinceMs < 2*tGame.FadingStepMs then
            self:SetBright(CColors.BRIGHT45)
        elseif iTimeSinceMs < 3*tGame.FadingStepMs then
            self:SetBright(CColors.BRIGHT30)
        elseif iTimeSinceMs < 4*tGame.FadingStepMs then
            self:SetBright(CColors.BRIGHT15)
        else
            self:SetBright(CColors.BRIGHT0)
        end
    end
end

function CPixel:ProcessClick(bClick)
    if bClick then
        if not self.bRising then
            CAudio.PlayAsync(CAudio.CLICK)
            self.iColor = CColors.GREEN
            self.iBright = CColors.BRIGHT0
            self.bRising = true
            self.iTimestamp = CTime.unix()
            self.bChanged = true
        end
    else
        if self.bRising then
            self.iColor = CColors.GREEN
            self.iBright = CColors.BRIGHT70
            self.bRising = false
            self.iTimestamp = CTime.unix()
            self.bChanged = true
        end
    end
end

local tZeroPixel = CHelp.DeepCopy(CPixel)

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for x=1,tGame.Cols do
        tFloor[x] = {}    -- новый столбец
        for y=1,tGame.Rows do
            tFloor[x][y] = CHelp.DeepCopy(CPixel) -- заполняем нулевыми пикселями
        end
    end

    -- в этом режиме кнопка может быть людая
    for iNum=0, 2*(tGame.Rows+tGame.Cols)+1 do
        tButtons[iNum] = CHelp.DeepCopy(CPixel) -- тип аналогичен пикселю
    end
end

-- NextTick (служебный): метод игрового тика
function NextTick()
    tZeroPixel:ProcessTick()

    for x=1,tGame.Cols do
        for y=1,tGame.Rows do
            tFloor[x][y]:ProcessTick()
        end
    end

    for iNum, tButton in pairs(tButtons) do
        tButton:ProcessTick()
    end
end

-- RangeFloor (служебный): метод для снятия снапшота пола
function RangeFloor(setPixel, setButton)
    if tZeroPixel.bChanged then
        setPixel(tZeroPixel.iX,tZeroPixel.iY,tZeroPixel.iColor,tZeroPixel.iBright)
        tZeroPixel.bChanged = false
    end
    
    
    for x=1,tGame.Cols do
        for y=1,tGame.Rows do
            if tFloor[x][y].bChanged then
                setPixel(x, y, tFloor[x][y].iColor, tFloor[x][y].iBright)
                tFloor[x][y].bChanged = false
            end
        end
    end

    for iNum, tButton in pairs(tButtons) do
        if tButton.bChanged then
            setButton(iNum,tButton.iColor,tButton.iBright)
            tButton.bChanged = false
        end
    end
end

-- GetStats (служебный): отдает текущую статистику игры (время, жизни, очки) для отображения на табло
function GetStats()
    return tStats
end

-- PauseGame (служебный): пауза игры
function PauseGame()
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
function SwitchStage()
end

-- PixelClick (служебный): метод нажатия/отпускания пикселя
--
-- Параметры:
--  tClick = {
--      X: int,
--      Y: int,
--      Click: bool,
--      Weight: int,
--  }
function PixelClick(tClick)
    if tClick.X < 1 then -- ZeroPixel
        tZeroPixel.iX = tClick.X
        tZeroPixel.iY = tClick.Y
        tZeroPixel:ProcessClick(tClick.Click)
    else
        tFloor[tClick.X][tClick.Y]:ProcessClick(tClick.Click)
    end
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  tClick = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(tClick)
    tButtons[tClick.Button]:ProcessClick(tClick.Click)
end

-- DefectPixel (служебный): метод дефектовки/раздефектовки пикселя
function DefectPixel(tDefect)
end

-- DefectButton (служебный): метод дефектовки/раздефектовки кнопки
function DefectButton(tDefect)
end
