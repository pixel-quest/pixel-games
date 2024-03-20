-- Название: Повторить игру?
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: служебная механика для переключения игры в случае поражения

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

-- Базовый пиксель тип
local CPixel = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
}

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
end

-- NextTick (служебный): метод игрового тика
function NextTick()

end

-- RangeFloor (служебный): метод для снятия снапшота пола
function RangeFloor(setPixel, setButton)
    for x=1,tGame.Cols do
        for y=1,tGame.Rows do
            setPixel(x, y, tFloor[x][y].iColor, tFloor[x][y].iBright)
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
    tFloor[tClick.X][tClick.Y].bClick = tClick.Click
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  tClick = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(tClick)
end

-- DefectPixel (служебный): метод дефектовки/раздефектовки пикселя
function DefectPixel(tDefect)
end

-- DefectButton (служебный): метод дефектовки/раздефектовки кнопки
function DefectButton(tDefect)
end
