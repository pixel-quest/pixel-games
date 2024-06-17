-- Название: Хомяк накопитель
-- Автор: @ProAlgebra (телеграм)
-- Описание механики: Дети кликают на пиксели, в зависимости от цвета начисляется разное количество очков. Красный даёт 3, зелёный 1

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
        { Score = 0, Lives = 0, Color = colors.RED },
    },
    TargetScore = 0,
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
    Click = 0,
    Defect = false
}
local GradientLength = 0
local GradientOffset = 0
local LastChangesTimestamp = 0

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
    audio.PlaySyncFromScratch() -- инструкция по игре "Кликай на залёные и голубые панели, чтобы прокачивать своего хомяка. Постарайтесь прокачать его как можно больше за меньшее время"
end

-- PauseGame (служебный): пауза игры
function PauseGame()
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
end
gameState = {
    State = -1,
    Tick = 0,
}
-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
--  Бывает полезно, чтобы отснять краткое превью игры для каталога
function SwitchStage()
    gameState.State = gameState.State + 1
    if gameState.State == 3 then
        GameStats.TotalStars = GameConfigObj.level2
    end
    if gameState.State == 5 then
        GameStats.TotalStars = GameConfigObj.level3
    end
    if gameState.State >= 6 then
        GameStats.TotalStars = GameConfigObj.level4
    end
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентироваться на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг


function NextTick()
    if gameState.State == -1 then 
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Defect == false then
                 ButtonsList[num].Color = colors.RED
                 ButtonsList[num].Bright = GameConfigObj.bright
            end
        end
        gameState.State = 0
    end
    if gameState.State == 0 then 
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Defect == true then
                 ButtonsList[num].Color = colors.NONE
                 ButtonsList[num].Bright = 0
            end
        end
    end
    GameStats.StageLeftDuration = GameStats.CurrentStars
    GameStats.StageTotalDuration = GameStats.TotalStars
    if gameState.State == 1 then
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Defect == false then
                 ButtonsList[num].Color = colors.NONE
                 ButtonsList[num].Bright = GameConfigObj.bright
            end
        end
        GameStats.CurrentStars = 0
        GameStats.TotalStars = GameConfigObj.level1
        for x,mass in pairs(GameObj.level1) do
            for y,state in pairs(mass) do
                FloorMatrix[y][x].Color = state
                FloorMatrix[y][x].Bright = GameConfigObj.bright
                
            end
        end
        gameState.State = gameState.State + 1
    end
    if gameState.State == 2 then
        if GameStats.CurrentStars >= GameConfigObj.level1 then
            gameState.State = 3
            GameStats.TotalStars = GameConfigObj.level2
        end
    end
    if gameState.State == 4 then
        if GameStats.CurrentStars >= GameConfigObj.level2 then
            gameState.State = 5
            GameStats.TotalStars = GameConfigObj.level3
        end
    end
    if gameState.State == 6 then
        if GameStats.CurrentStars >= GameConfigObj.level3 then
            gameState.State = 7
            GameStats.TotalStars = GameConfigObj.level4
        end
    end
    if gameState.State == 3 then
        for x,mass in pairs(GameObj.level2) do
            for y,state in pairs(mass) do
                FloorMatrix[y][x].Color = state
                FloorMatrix[y][x].Bright = GameConfigObj.bright
                
            end
        end
        gameState.State = 4
    end
    if gameState.State == 5 then
        for x,mass in pairs(GameObj.level3) do
            for y,state in pairs(mass) do
                FloorMatrix[y][x].Color = state
                FloorMatrix[y][x].Bright = GameConfigObj.bright
                
            end
        end
        gameState.State = gameState.State + 1
    end
    if gameState.State == 7 then
        for x,mass in pairs(GameObj.level4) do
            for y,state in pairs(mass) do
                FloorMatrix[y][x].Color = state
                FloorMatrix[y][x].Bright = GameConfigObj.bright
                
            end
        end
        gameState.State = gameState.State + 1
    end
    if gameState.Tick < time.unix() then
        gameState.Tick = time.unix() + GameConfigObj.delay
        for y = 1,15 do
            for x = 19,24 do
                if FloorMatrix[x][y].Color == colors.GREEN then
                    FloorMatrix[x][y].Color = colors.NONE
                end
                if gameState.State >= 4 then
                    if FloorMatrix[x][y].Color == colors.CYAN then
                        FloorMatrix[x][y].Color = colors.NONE
                    end
                end
                if FloorMatrix[x][y].Defect == false then
                if FloorMatrix[x][y].Color == colors.NONE then
                    if gameState.State == 2 then
                        if math.random(0,100) < 20 then
                            FloorMatrix[x][y].Color = colors.GREEN
                            FloorMatrix[x][y].Bright = GameConfigObj.bright
                        end
                    end
                    if gameState.State >= 4 then
                        random = math.random(0,100)
                        if random < 10 + (gameState.State * 2) then
                            FloorMatrix[x][y].Color = colors.GREEN
                            FloorMatrix[x][y].Bright = GameConfigObj.bright
                        end
                        if random > 90 - (gameState.State * 3) then
                            FloorMatrix[x][y].Color = colors.CYAN
                            FloorMatrix[x][y].Bright = GameConfigObj.bright
                        end
                    end
                end
                end
                
            end
        end
    end
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
    if click.Click == false or click.Weight < 3 then
        return
    end
    if time.unix() < FloorMatrix[click.X][click.Y].Click   + 1  then
        FloorMatrix[click.X][click.Y].click = time.unix()
        return
    end
    FloorMatrix[click.X][click.Y].Click = time.unix()
    if FloorMatrix[click.X][click.Y].Color == colors.GREEN then
        FloorMatrix[click.X][click.Y].Color = colors.NONE
        audio.PlayAsync("CLICK")
        GameStats.CurrentStars = GameStats.CurrentStars + GameConfigObj.greenPoint
    end
    if gameState.State >= 4 then
        if FloorMatrix[click.X][click.Y].Color == colors.CYAN then
            FloorMatrix[click.X][click.Y].Color = colors.NONE
            audio.PlayAsync("CLICK")
            GameStats.CurrentStars = GameStats.CurrentStars + GameConfigObj.cyanPoint
        end
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
    if click.Click == false then
        return
    end
    if gameState.State >= 1 then
        return
    end
    if time.unix() < ButtonsList[click.Button].Click + 1  then
        ButtonsList[click.Button].click = time.unix()
        return
    end


    ButtonsList[click.Button].Click = time.unix()
    
    if ButtonsList[click.Button].Color == colors.RED then
        gameState.State = 1
        ButtonsList[click.Button].Color = colors.NONE
        audio.PlayRandomBackground()
    end

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
