-- Заставка "Радуга"
-- Автор: Anatoliy B
-- Телеграм: https://t.me/AnatoliyB

-- Методы работы с JSON
--      .decode(jsonString) - декодирование строки в объект
--      .encode(jsonObject) - кодирование объекта в строку
local json = require("json")

-- Имплементация некоторых функций работы с временем
--      .unix_nano() - возвращает текущее время в наносекундах
--      .unix() - возвращает текущее время в секундах (с дробной частью), по сути это unix_nano() / 1 000 000 000
local time = require("time")

-- Методы работы с аудио
--      .PlayRandomBackground() - проигрывает случайную фоновую музыку
--      .PlayBackground(name) - проигрывает фоновую музыку по названию
--      .StopBackground() - останавливает фоновую музыку
--      .PlaySync(name) - проигрывает звук синхронно
--      .PlaySyncFromScratch(name) - проигрывает звук синхронно, очищая существующую очередь звуков
--      .PlayAsync(name) - проигрывает звук асинхронно
-- Станданртные звуки: CLICK, MISCLICK, GAME_OVER, GAME_SUCCESS, STAGE_DONE
-- Стандартные голоса: PAUSE, DEFEAT, VICTORY, CHOOSE_COLOR, LEFT_10SEC, LEFT_20SEC, BUTTONS
--              числа: ZERO, ONE, TWO, THREE, FOUR, FIVE
--              цвета: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
local audio = require("audio")

-- Константы цветов (0 - 7): NONE, RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE
-- Константы яркости (0 - 7): BRIGHT0, BRIGHT15, BRIGHT30, BRIGHT45, BRIGHT60, BRIGHT70, BRIGHT85, BRIGHT100
local colors = require("colors")

-- Импортированные конфиги (ниже приведен лишь ПРИМЕР структуры,
--  сами объекты будут переопределены в StartGame() при декодировании json)
local gameObj = { -- Объект игры
    cols = 24, -- пикселей по горизонтали (X)
    rows = 15, -- пикселей по вертикали (Y)
    colors = { -- массив градиента цветов для радуги
        {color=colors.RED,bright=colors.BRIGHT15},
        {color=colors.RED,bright=colors.BRIGHT30},
    }
}
-- Насторойки, которые может подкручивать админ при запуске игры
local gameConfigObj = {
    delay = 100, -- задержка отрисовки в мс
}

-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()
local GameStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
    CurrentStars = 0,
    TotalStars = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE }
    },
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
}
-- Структура результата игры (служебная): должна возвращаться в NextTick() в момент завершения игры
-- После этого NextTick(), RangeFloor() и GetStats() больше не вызываются, игра окончена
local GameResults = {
    Won = false,
}

-- Локальные переменные для внутриигровой логики
local FloorMatrix = {} -- матрица пола
local ButtonsList = {} -- список кнопок
local Pixel = { -- пиксель тип
    color = colors.NONE,
    bright = colors.BRIGHT0,
}
local GradientLength = 0
local GradientOffset = 0
local LastChangesTimestamp = 0

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    gameObj = json.decode(gameJson)
    gameConfigObj = json.decode(gameConfigJson)

    for x=1,gameObj.cols do
        FloorMatrix[x] = {}    -- create a new col
        for y=1,gameObj.rows do
            FloorMatrix[x][y] = Pixel -- init by zero pixels
        end
    end

    for b=1, 2*(gameObj.cols+gameObj.rows) do
        ButtonsList[b] = Pixel -- the same type as pixel
    end

    GradientLength = table.getn(gameObj.colors)
    audio.PlaySyncFromScratch("") -- just reset audio player on start new game
    audio.PlayRandomBackground()
end

-- PauseGame (служебный): пауза игры
function PauseGame()
    audio.PlaySyncFromScratch(audio.PAUSE)
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
function SwitchStage()
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО 28 раз в секунду (период ~35мс)
-- Ориентировать на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    local diffMs = (time.unix() - LastChangesTimestamp) * 1000

    if diffMs < gameConfigObj.delay then
        return
    end

    for x=1,gameObj.cols do
        for y=1,gameObj.rows do
            FloorMatrix[x][y]=gameObj.colors[(x+y+GradientOffset) % GradientLength + 1]
        end
    end

    for b=1, table.getn(ButtonsList) do
        ButtonsList[b]=gameObj.colors[(b+GradientOffset) % GradientLength + 1]
    end

    GradientOffset = GradientOffset + 1
    LastChangesTimestamp = time.unix()

    --GameResults.Won=true
    --return GameResults
end

-- RangeFloor (служебный): метод для снятия снапшота пола
-- Вызывается в тот же игровой тик следом за методом NextTick()
--
-- Параметры:
--  setPixel = func(x int, y int, color int, bright int)
--  setButton = func(button int, color int, bright int)
function RangeFloor(setPixel, setButton)
    for x=1,gameObj.cols do
        for y=1,gameObj.rows do
            setPixel(x,y,FloorMatrix[x][y].color,FloorMatrix[x][y].bright)
        end
    end

    for b=1, table.getn(ButtonsList) do
        setButton(b,ButtonsList[b].color,ButtonsList[b].bright)
    end
end

-- GetStats (служебный): отдает текущую статистику игры (время, жизни, очки) для отображения на табло
-- Вызывается в тот же игровой тик следом за методом RangeFloor()
function GetStats()
    return GameStats
end


-- PixelClick (служебный): метод нажатия/отпускания пикселя
--
-- Параметры:
--  click = {
--      X: int,
--      Y: int,
--      Click: bool,
--      Weight: int,
--  }
function PixelClick(click)
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  click = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(click)
end

-- DefectPixel (служебный): метод дефектовки/раздефектовки пикселя
-- Используется для исключения плохих пикселей из игры
--
-- Параметры:
--  defect = {
--      X: int,
--      Y: int,
--      Defect: bool,
--  }
function DefectPixel(defect)
end

-- DefectButton (служебный): метод дефектовки/раздефектовки кнопки
-- Используется для исключения плохих кнопок из игры
--
-- Параметры:
--  defect = {
--      Button: int,
--      Defect: bool,
-- }
function DefectButton(defect)
end
