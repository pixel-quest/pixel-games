-- Название: Рисовашка
-- Автор: @ProAlgebra (телеграм)
-- Описание механики: Можно рисовать в комнате. На полу цвета с разной яркостью. 30 кнопка отключает рисование и позволяет ходить по рисунку
-- 34 кнопка очищает поле. Палитра цветов игнорирует сломанные пиксели, если они выпадают палитра сдвигается.
-- В долгих планах на неделю: Добавить в конфиг настройку, чтобы администратор мог написать имя ребёнка на полу (3-4 буквы)

-- Логгер в консоль
--      .print(string) - напечатать строку в консоль разработчика в браузере
local log = require("log")

-- Библиотека github.com/kikito/inspect.lua
-- для человекочитаемого вывода
local inspect = require("inspect")

-- Вспомогательные методы
--      .ShallowCopy(table) - неглубокое копирования таблицы
--      .DeepCopy(table) - глубокое копирования таблицы
local help = require("help")

-- Методы работы с JSON
--      .decode(jsonString) - декодирование строки в объект
--      .encode(jsonObject) - кодирование объекта в строку
local json = require("json")

-- Имплементация некоторых функций работы с временем
--      .unix() - возвращает текущее время в секундах (с дробной частью)
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
--      .PreloadFile(name) - зарянее подгрузить тяжелый файл в память
-- Станданртные звуки: CLICK, MISCLICK, GAME_OVER, GAME_SUCCESS, STAGE_DONE
-- Стандартные голоса: START_GAME, PAUSE, DEFEAT, VICTORY, CHOOSE_COLOR, LEFT_10SEC, LEFT_20SEC, BUTTONS
--              числа: ZERO, ONE, TWO, THREE, FOUR, FIVE
--              цвета: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
local audio = require("audio")

-- Константы цветов (0 - 7): NONE, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
-- Константы яркости (0 - 7): BRIGHT0, BRIGHT15, BRIGHT30, BRIGHT45, BRIGHT60, BRIGHT70, BRIGHT85, BRIGHT100
local colors = require("colors")

-- Полезные стандартные функции
--      math.floor() – отбрасывает дробную часть и переводит значение в целочисленный тип
--      math.random(upper) – генерирует целое число в диапазоне [1..upper]
--      math.random(lower, upper) – генерирует целое число в диапазоне [lower..upper]
--      math.random(lower, upper) – генерирует целое число в диапазоне [lower..upper]

-- Импортированные конфиги (ниже приведен лишь ПРИМЕР структуры,
--  сами объекты будут переопределены в StartGame() при декодировании json)
-- Объект игры, см. файл game.json
local GameObj = {
    Cols = 24, -- пикселей по горизонтали (X), обязательные параметр для всех игр
    Rows = 15, -- пикселей по вертикали (Y), обязательные параметр для всех игр
    Buttons = {2, 6, 10, 14, 18, 22, 26, 30, 34, 42, 46, 50, 54, 58, 62, 65, 69, 73, 77}, -- номера кнопок в комнате
    Colors = { -- массив градиента цветов для радуги
        {Color=colors.RED,Bright=colors.BRIGHT15},
        {Color=colors.RED,Bright=colors.BRIGHT30},
    }
}
-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
    Delay = 100, -- задержка отрисовки в мс
}

-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()
local GameStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
    ScoreboardVariant = 10,
}
gameState = {
    State = -1,
    Color = 0,
    Bright = 0
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
    Click = 0,
    Defect = false
}
local GradientLength = 0
local GradientOffset = 0
local LastChangesTimestamp = 0

local bGamePaused = false

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)
    
    for x=1,GameObj.Cols do
        FloorMatrix[x] = {}    -- новый столбец
        for y=1,GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel) -- заполняем нулевыми пикселями
        end
    end

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel) -- тип аналогичен пикселю
    end
    ButtonsList[GameObj.SaveButton].Color = colors.GREEN
    ButtonsList[GameObj.SaveButton].Bright = colors.BRIGHT70

    GradientLength = table.getn(GameObj.Colors)
    audio.PlayVoicesSyncFromScratch("coloring-book/coloring-book-tutorial.mp3") -- just reset audio player on start new game
    audio.PlayRandomBackground()
end

-- PauseGame (служебный): пауза игры
function PauseGame()
    bGamePaused = true
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
    bGamePaused = false
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
--  Бывает полезно, чтобы отснять краткое превью игры для каталога
function SwitchStage()
    drawColor = 0
    xColor = 1
    yColor = 1
    stateDraw = 0
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            FloorMatrix[x][y].Color = colors.NONE-- заполняем нулевыми пикселями
        end
    end

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel) -- тип аналогичен пикселю
    end
    ButtonsList[GameObj.SaveButton].Color = colors.GREEN
    ButtonsList[GameObj.SaveButton].Bright = colors.BRIGHT70
    gameState.Color = -1

end

local tColors = {}
tColors[0] = colors.NONE
tColors[1] = colors.RED
tColors[2] = colors.GREEN
tColors[3] = colors.YELLOW
tColors[4] = colors.MAGENTA
tColors[5] = colors.CYAN
tColors[6] = colors.BLUE
tColors[7] = colors.WHITE

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентироваться на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
drawColor = 0
xColor = 1
yColor = 1
stateDraw = 0
function NextTick()
    if drawColor == 21 then
        return
    end

    if FloorMatrix[xColor][yColor].Defect == true then
        if stateDraw == 0 then
            xColor = xColor + 1
            if xColor > 24 then
                xColor = 24
                stateDraw = 1
            end
            return
        end
        if stateDraw == 1 then
            yColor = yColor + 1
            if yColor > 15 then
                yColor = 15
                stateDraw = 2
            end
            return
        end
        if stateDraw == 2 then
            xColor = xColor - 1
            return
        end
    end
    FloorMatrix[xColor][yColor].Color = tColors[math.floor(drawColor / 3) + 1]
    FloorMatrix[xColor][yColor].Bright = math.floor( GameConfigObj.bright / (math.fmod(drawColor,3) + 1))
    if stateDraw == 0 then
        xColor = xColor + 1
        if xColor > 24 then
            xColor = 24
            stateDraw = 1
        end
    end
    if stateDraw == 1 then
        yColor = yColor + 1
        if yColor > 15 then
            yColor = 15
            stateDraw = 2
        end
    end
    if stateDraw == 2 then
        xColor = xColor - 1
    end
    drawColor = drawColor + 1
    -- Эта заставка бесконечная
    -- return GameResult
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
function SetLeftColor()
    if gameState.Color ~= colors.NONE then
        audio.PlaySyncFromScratch("")
        audio.PlaySyncColorSound(gameState.Color)
    end

    for i=5,11 do
        FloorMatrix[1][i].Color = gameState.Color
        FloorMatrix[1][i].Bright = gameState.Bright
    end
end

function PixelClick(click)
    if click.Click == false or click.Weight < 3 or bGamePaused then
        return
    end
    if time.unix() < FloorMatrix[click.X][click.Y].Click   + 1  then
        FloorMatrix[click.X][click.Y].click = time.unix()
        return
    end


    FloorMatrix[click.X][click.Y].Click = time.unix()

    if FloorMatrix[click.X][click.Y].State == 1 or click.Y < 3 or click.Y > 13 or click.X < 3 or click.X > 22 or gameState == -1 then
        if FloorMatrix[click.X][click.Y].Color ~= colors.NONE and FloorMatrix[click.X][click.Y].Color ~= gameState.Color then
            gameState.Color = FloorMatrix[click.X][click.Y].Color
            gameState.Bright = FloorMatrix[click.X][click.Y].Bright
            SetLeftColor()
        end
        return
    end
    if  gameState.Color == -1 then
        return
    end
    if FloorMatrix[click.X][click.Y].Color ~= gameState.Color and FloorMatrix[click.X][click.Y].Color ~= colors.NONE then
        FloorMatrix[click.X][click.Y].Color = gameState.Color
        return
    end
    if FloorMatrix[click.X][click.Y].Color ~= colors.NONE then
        FloorMatrix[click.X][click.Y].Color = colors.NONE
    else
        FloorMatrix[click.X][click.Y].Color = gameState.Color
        FloorMatrix[click.X][click.Y].Bright = gameState.Bright
        
    end
    
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  click = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(click)
    if click.Click == false or bGamePaused then
        return
    end
    if time.unix() < ButtonsList[click.Button].Click + 1  then
        ButtonsList[click.Button].click = time.unix()
        return
    end


    ButtonsList[click.Button].Click = time.unix()
    gameState.Color = 0
    SetLeftColor()
    gameState.Color = -1
    

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
    if defect.Defect == true then
        log.print("true")
    else
        log.print("false")    
    end
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
end
