-- Название: Название механики
-- Автор: @ваш_телеграм
-- Описание механики: в общих словах, что происходит в механике
-- Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь

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
--      .PlaySyncColorSound(color) - проигрывает название цвета по его номеру
--      .PlayLeftAudio(num) - проигрывает голос "остатка" по числу (22, 12, 5 ... 0)
--      .PlayAsync(name) - проигрывает звук асинхронно
-- Станданртные звуки: CLICK, MISCLICK, GAME_OVER, GAME_SUCCESS, STAGE_DONE
-- Стандартные голоса: START_GAME, PAUSE, DEFEAT, VICTORY, CHOOSE_COLOR, LEFT_10SEC, LEFT_20SEC, BUTTONS
--              числа: ZERO, ONE, TWO, THREE, FOUR, FIVE
--              цвета: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
local audio = require("audio")

-- Константы цветов (0 - 7): NONE, RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE
-- Константы яркости (0 - 7): BRIGHT0, BRIGHT15, BRIGHT30, BRIGHT45, BRIGHT60, BRIGHT70, BRIGHT85, BRIGHT100
local colors = require("colors")

-- Полезные стандартные функции
--      math.floor() – отбрасывает дробную часть и переводит значение в целочисленный тип
--      math.random() – генерирует псевдослучайное вещественное число в диапазоне [0 до 1]
--      math.random(upper) – генерирует целое число в диапазоне [1..upper]
--      math.random(lower, upper) – генерирует целое число в диапазоне [lower..upper]

-- Импортированные конфиги (ниже приведен лишь ПРИМЕР структуры,
--  сами объекты будут переопределены в StartGame() при декодировании json)
-- Объект игры, см. файл game.json
local GameObj = {
    Cols = 24, -- пикселей по горизонтали (X), обязательные параметр для всех игр
    Rows = 15, -- пикселей по вертикали (Y), обязательные параметр для всех игр
    Buttons = {2, 6, 10, 14, 18, 22, 26, 30, 34, 42, 46, 50, 54, 58, 62, 65, 69, 73, 77}, -- номера кнопок в комнате
}
-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {}

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
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false,
    Defect = false,
}

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    for x=1,GameObj.Cols do
        FloorMatrix[x] = {}    -- новый столбец
        for y=1,GameObj.Rows do
            FloorMatrix[x][y] = Pixel -- заполняем нулевыми пикселями
        end
    end

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = shallowCopy(Pixel) -- тип аналогичен пикселю
    end
end

-- PauseGame (служебный): пауза игры
function PauseGame()
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
--  Бывает полезно, чтобы отснять краткое превью игры для каталога
function SwitchStage()
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентировать на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    GameResults.Won=true
    return GameResults
end

-- RangeFloor (служебный): метод для снятия снапшота пола
-- Вызывается в тот же игровой тик следом за методом NextTick()
--
-- Параметры:
--  setPixel = func(x int, y int, color int, bright int)
--  setButton = func(button int, color int, bright int)
function RangeFloor(setPixel, setButton)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            setPixel(x,y,FloorMatrix[x][y].Color,FloorMatrix[x][y].Bright)
        end
    end

    for num, button in pairs(ButtonsList) do
        setButton(num,button.Color,button.Bright)
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
    FloorMatrix[click.X][click.Y].Click = click.Click
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  click = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(click)
    ButtonsList[click.Button].Click = click.Click
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
    FloorMatrix[defect.X][defect.Y].Defect = defect.Defect
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
    ButtonsList[defect.Button].Defect = defect.Defect
end

-- ======== Ниже вспомогательные методы внутренней логики =======

-- Функция-помощник для неглубокого копирования таблицы
function shallowCopy(t)
    local t2 = {}
    for k,v in pairs(t) do
        t2[k] = v
    end
    return t2
end
