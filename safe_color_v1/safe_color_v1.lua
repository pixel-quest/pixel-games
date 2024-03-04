-- Название: Безопасный цвет
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: кооперативная механика, в которой требуется быстро встать на сегменты озвученного цвета,
--      другие сегменты загораются красным, обжигая тех, кто не успел.
--      Базово количество безопасных сегментов = количеству игроков.
--      Можно играть "Режим обнимашек" – когда на старте не все игроки занимают стартовую позицию или становятся по два.
--      Внимание: Для старта игры требуется занять позиции и нажать любую светящуюся кнопку на стене!
-- Идеи по доработке:
--		1. Можно сделать вариант на выбывание с уменьшением количества безопасных сегментов

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
-- Станданртные звуки: CLICK, MISCLICK, GAME_OVER, GAME_SUCCESS, STAGE_DONE
-- Стандартные голоса: START_GAME, PAUSE, DEFEAT, VICTORY, CHOOSE_COLOR, LEFT_10SEC, LEFT_20SEC, BUTTONS
--              числа: ZERO, ONE, TWO, THREE, FOUR, FIVE
--              цвета: RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE
local audio = require("audio")

-- Константы цветов (0 - 7): NONE, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
-- Константы яркости (0 - 7): BRIGHT0, BRIGHT15, BRIGHT30, BRIGHT45, BRIGHT60, BRIGHT70, BRIGHT85, BRIGHT100
local colors = require("colors")

-- Полезные стандартные функции
--      math.ceil() – округление вверх
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
    StartPositionSize = 2, -- размер стартовой зоны для игрока, для маленькой выездной платформы удобно ставить тут 1
    StartPositions = { -- координаты расположения стартовых зон должны быть возле стены, т.к для старта надо нажать кнопку на стене
        { X = 2, Y = 2, Color = colors.GREEN },
        { X = 6, Y = 2, Color = colors.GREEN },
        { X = 10, Y = 2, Color = colors.GREEN },
        { X = 14, Y = 2, Color = colors.GREEN },
        { X = 18, Y = 2, Color = colors.GREEN },
        { X = 22, Y = 2, Color = colors.GREEN },
    },
    BurnEffect = { -- тайминги эффекта моргания
        DurationOnMs = 200,
        DurationOffMs = 120,
        TotalDurationMs = 1500,
    },
    YOffset = 1, -- смещение по вертикали, костыль для московской комнаты
}
-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
    Bright = colors.BRIGHT70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
    StartLives = 0, -- количество жизней, 0 - бесконечно
    StagesQty = 10, -- сколько очков необходимо набрать для победы
    StageDurationSec = 4,
    StopDurationSec = 4,
    WinDurationSec = 10, -- длительность этапа победы перед завершением игры
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
        { Score = 0, Lives = 0, Color = colors.YELLOW },
        { Score = 0, Lives = 0, Color = colors.GREEN },
        { Score = 0, Lives = 0, Color = colors.CYAN },
        { Score = 0, Lives = 0, Color = colors.BLUE },
        { Score = 0, Lives = 0, Color = colors.MAGENTA },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
}
-- Структура результата игры (служебная): должна возвращаться в NextTick() в момент завершения игры
-- После этого NextTick(), RangeFloor() и GetStats() больше не вызываются, игра окончена
local GameResults = {
    Won = false, -- победили или проиграли
}

-- Локальные переменные для внутриигровой логики
local FloorMatrix = {} -- матрица пола
local ButtonsList = {} -- список кнопок
local Pixel = { -- пиксель тип
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false,
    Defect = false,
    EffectActivatedAt = nil,
}
local StartPlayersCount = 0 -- количество игроков в момент нажатия кнопки старт

-- Этапы игры
local CONST_STAGE_START = 0 -- выбор мест
local CONST_STAGE_GAME = 1 -- игра
local StageStartTime = 0 -- время начала текущего этапа

-- Звуки обратного отсчета и прохождения этапа, проигрываются один раз
local LeftAudioPlayed = { -- 3... 2... 1...
    [3] = false,
    [2] = false,
    [1] = false,
}
local StageDonePlayed = false

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    -- ограничение на размер стартовой позиции
    if GameObj.StartPositionSize == nil or
            GameObj.StartPositionSize < 1 or GameObj.StartPositionSize > 2 then
        GameObj.StartPositionSize = 2
    end

    for x=1,GameObj.Cols do
        FloorMatrix[x] = {}    -- новый столбец
        for y=1,GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel) -- заполняем нулевыми пикселями
        end
    end

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel) -- тип аналогичен пикселю
        -- и подсветим все кнопки по-умлочанию, чтобы потребовать нажатия для старта
        ButtonsList[num].Color = colors.BLUE
        ButtonsList[num].Bright = GameConfigObj.Bright
    end

    GameStats.TotalStars = GameConfigObj.StagesQty
    GameStats.TotalLives = GameConfigObj.StartLives
    GameStats.CurrentLives = GameConfigObj.StartLives

    audio.PlaySyncFromScratch("games/safe-color-game.mp3") -- Игра "Безопасный цвет"
    audio.PlaySync("voices/stand_on_green_and_get_ready.mp3") -- Встаньте на зеленую зону и приготовьтесь
    audio.PlaySync("voices/listen_carefully_color.mp3") -- Внимательно меня слушайте, я скажу вам цвет, на который нужно будет встать
    audio.PlaySync("voices/press-button-for-start.mp3") -- Для старта игры, нажмите светящуюся кнопку на стене
end

-- PauseGame (служебный): пауза игры
function PauseGame()
    audio.PlaySyncFromScratch(audio.PAUSE)
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
    audio.PlaySyncFromScratch(audio.START_GAME)
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
function SwitchStage()
    switchStage(GameStats.StageNum+1)
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентировать на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    if GameStats.StageNum == CONST_STAGE_START then -- этап старта
        -- если есть хоть один клик на позиции, подсвечиваем её и заводим игрока по индексу
        for positionIndex, startPosition in ipairs(GameObj.StartPositions) do
            local bright = colors.BRIGHT15
            if checkPositionClick(startPosition, GameObj.StartPositionSize) then
                GameStats.Players[positionIndex].Color = startPosition.Color
                bright = GameConfigObj.Bright
            else
                GameStats.Players[positionIndex].Color = colors.NONE
            end
            setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, startPosition.Color, bright)
        end

        local currentPlayersCount = countActivePlayers()
        if currentPlayersCount ~= StartPlayersCount -- если с момента нажатия кнопки количество игроков изменилось
                or currentPlayersCount < 1 then -- если менее одного игрока
            -- нельзя стартовать
            StartPlayersCount = 0
            resetCountdown()
        end

        if StartPlayersCount > 0 then
            local timeSinceCountdown = time.unix() - StageStartTime
            GameStats.StageTotalDuration = 3 -- сек обратный отсчет
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceCountdown)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end

            if GameStats.StageLeftDuration <= 0 then -- начинаем игру
                switchStage(GameStats.StageNum+1)
            end
        end
    elseif GameStats.StageNum <= GameConfigObj.StagesQty then -- этап игры
        local timeSinceStageStart = time.unix() - StageStartTime
        if timeSinceStageStart > GameConfigObj.StageDurationSec + GameConfigObj.StopDurationSec then -- время переключить этап
            switchStage(GameStats.StageNum+1)
        elseif timeSinceStageStart > GameConfigObj.StageDurationSec then -- время поджигать пол
            GameStats.StageLeftDuration = 0
            -- (яркость - 1) это чтобы видеть отличие красных зон от заливки
            setGlobalColorBrightExceptColor(colors.RED, GameConfigObj.Bright-1, targetColor(GameStats.StageNum))
            processClicksAndEffects()

            -- если это был последний этап
            if GameStats.StageNum == GameConfigObj.StagesQty then
                audio.PlaySyncFromScratch(audio.GAME_SUCCESS)
                audio.PlaySync(audio.VICTORY)
                setGlobalColorBrightExceptColor(colors.GREEN, GameConfigObj.Bright, colors.NONE)
                switchStage(GameStats.StageNum+1)
            elseif not StageDonePlayed then
                audio.PlayAsync(audio.STAGE_DONE)
                StageDonePlayed = true
            end
        else
            local timeSinceStageStart = time.unix() - StageStartTime
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceStageStart)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end
        end
    else -- этап финиша
        processClicksAndEffects()

        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageTotalDuration = GameConfigObj.WinDurationSec
        GameStats.StageLeftDuration = GameStats.StageTotalDuration - timeSinceStageStart

        if GameStats.StageLeftDuration <= 0 then -- время завершать игру
            return GameResults
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
    if GameStats.StageNum ~= CONST_STAGE_START then
        return -- не интересуют клики кнопок вне этапа выбора цвета
    end
    if ButtonsList[click.Button] == nil then
        return -- не интересуют кнопки не из списка, иначе будет ошибка
    end
    ButtonsList[click.Button].Click = click.Click

    -- нажали кнопку, стартуем обратный отсчет
    if StartPlayersCount == 0 and click.Click then
        StartPlayersCount = countActivePlayers()
        StageStartTime = time.unix()
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
    if defect.Defect then
        FloorMatrix[defect.X][defect.Y].Click = false
    end
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
    if ButtonsList[defect.Button] == nil then
        return -- не интересуют кнопки не из списка, иначе будет ошибка
    end
    ButtonsList[defect.Button].Defect = defect.Defect
    -- потушим кнопку, если она дефектована и засветим, если дефектовку сняли
    if defect.Defect then
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT0
    else
        ButtonsList[defect.Button].Color = colors.BLUE
        ButtonsList[defect.Button].Bright = GameConfigObj.Bright
    end
end

-- ======== Ниже вспомогательные методы внутриигровой логики =======

-- Сбросить звук обратного отсчета
function resetCountdown()
    for i = 1, #LeftAudioPlayed do
        LeftAudioPlayed[i] = false
    end
end

-- Переключение этапа игры
function switchStage(newStage)
    GameStats.StageNum = newStage
    StageStartTime = time.unix()
    GameStats.StageTotalDuration = GameConfigObj.StageDurationSec

    GameStats.TargetColor = targetColor(GameStats.StageNum)

    if GameStats.StageNum > GameConfigObj.StagesQty then
        audio.StopBackground()
        return
    else
        if GameStats.StageNum > CONST_STAGE_START then
            audio.PlayRandomBackground()
        end
        GameStats.CurrentStars = GameStats.StageNum
        setGlobalColorBrightExceptColor(colors.NONE, colors.BRIGHT0, colors.NONE)
        StageDonePlayed = false
        resetCountdown()

        audio.PlaySyncFromScratch("") -- очистим очередь звуков, чтобы обрезать долгие речи на старте
        audio.PlaySyncColorSound(GameStats.TargetColor)
    end

    -- заполним все цветными, пропуская нужный цвет
    local newColor = colors.NONE
    for x = 1, GameObj.Cols, 2 do
        for y = 1+GameObj.YOffset, GameObj.Rows, 2 do
            for randomAttempt = 0, 50 do
                newColor = math.random(1, 6)
                if newColor == GameStats.TargetColor then
                    goto continue
                end
                if x > 1 and FloorMatrix[x-1][y].Color == newColor then
                    goto continue
                end
                if y > 1 and FloorMatrix[x][y-1].Color == newColor then
                    goto continue
                end
                do break end
                ::continue::
            end

            FloorMatrix[x][y].Color = newColor
            FloorMatrix[x][y].Bright = GameConfigObj.Bright

            if x + 1 <= GameObj.Cols then
                FloorMatrix[x+1][y].Color = newColor
                FloorMatrix[x+1][y].Bright = GameConfigObj.Bright
            end
            if y + 1 <= GameObj.Rows then
                FloorMatrix[x][y+1].Color = newColor
                FloorMatrix[x][y+1].Bright = GameConfigObj.Bright
            end
            if x + 1 <= GameObj.Cols and y + 1 <= GameObj.Rows then
                FloorMatrix[x+1][y+1].Color = newColor
                FloorMatrix[x+1][y+1].Bright = GameConfigObj.Bright
            end
        end
    end

    -- дозаполним нужный цвет по количеству игроков
    for p = 1, countActivePlayers() do
        for randomAttempt = 0, 50 do
            x = math.random(GameObj.Cols/2)*2-1
            y = math.random(GameObj.Rows/2)*2-1 + GameObj.YOffset

            if FloorMatrix[x][y].Color == GameStats.TargetColor then
                goto continue
            end
            if x > 1 and FloorMatrix[x-1][y].Color == GameStats.TargetColor then
                goto continue
            end
            if y > 1 and FloorMatrix[x][y-1].Color == GameStats.TargetColor then
                goto continue
            end
            if x+2 <= GameObj.Cols and FloorMatrix[x+2][y].Color == GameStats.TargetColor then
                goto continue
            end
            if y+2 <= GameObj.Rows and FloorMatrix[x][y+2].Color == GameStats.TargetColor then
                goto continue
            end

            FloorMatrix[x][y].Color = GameStats.TargetColor
            FloorMatrix[x][y].Bright = GameConfigObj.Bright

            FloorMatrix[x][y+1].Color = GameStats.TargetColor
            FloorMatrix[x][y+1].Bright = GameConfigObj.Bright

            FloorMatrix[x+1][y].Color = GameStats.TargetColor
            FloorMatrix[x+1][y].Bright = GameConfigObj.Bright

            FloorMatrix[x+1][y+1].Color = GameStats.TargetColor
            FloorMatrix[x+1][y+1].Bright = GameConfigObj.Bright
            do break end
            ::continue::
        end
    end
end

-- Проверить стартовую позицию на ниличие человека на ней
function checkPositionClick(startPosition, positionSize)
    for i=0, positionSize*positionSize-1 do
        local x = startPosition.X + i%positionSize
        local y = startPosition.Y + math.floor(i/positionSize)

        if x < 1 or x > GameObj.Cols or
                y < 1 or y > GameObj.Rows then
            goto continue -- игнорируем координаты за пределами поля
        end

        if FloorMatrix[x][y].Click then
            return true
        end
        ::continue::
    end
    return false
end

-- Установить цвет стартовой позиции
function setColorBrightForStartPosition(startPosition, positionSize, color, bright)
    for i=0, positionSize*positionSize-1 do
        local x = startPosition.X + i%positionSize
        local y = startPosition.Y + math.floor(i/positionSize)

        if x < 1 or x > GameObj.Cols or
                y < 1 or y > GameObj.Rows then
            goto continue -- игнорируем координаты за пределами поля
        end

        FloorMatrix[x][y].Color = color
        FloorMatrix[x][y].Bright = bright
        ::continue::
    end
end

-- Найти игрока по цвету
function getPlayerByColor(color)
    if color == colors.NONE then
        return nil
    end
    for playerIdx, player in ipairs(GameStats.Players) do
        if player.Color == color then
            return player
        end
    end
end

-- Посчитать количество активных игроков
function countActivePlayers()
    local activePlayers = 0
    for _, player in ipairs(GameStats.Players) do
        if player.Color > colors.NONE then
            activePlayers = activePlayers + 1
        end
    end
    return activePlayers
end

-- Целевой цвет этапа
function targetColor(stageNum)
    if stageNum < CONST_STAGE_GAME or stageNum > GameConfigObj.StagesQty then
        return colors.NONE
    end
    return stageNum%colors.WHITE + 1
end

-- Залить всё поле цветом, пропуская exceptColor
function setGlobalColorBrightExceptColor(color, bright, exceptColor)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= exceptColor then
                FloorMatrix[x][y].Color = color
                FloorMatrix[x][y].Bright = bright
            end
        end
    end
end

-- Обработка кликов и эффектов
function processClicksAndEffects()
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            local pixel = FloorMatrix[x][y]
            -- есть эффект горения
            if pixel.EffectActivatedAt ~= nil then
                -- воспроизведем эффект
                local timeSinceEffectActivated = (time.unix() - pixel.EffectActivatedAt) * 1000
                if timeSinceEffectActivated > GameObj.BurnEffect.TotalDurationMs then
                    if pixel.Click then -- продлим эффект, если еще нажат
                        -- g.minusLive() -- но жизнь больше не вычитаем
                        pixel.EffectActivatedAt = time.unix()
                    else -- сбросим эффект
                        pixel.EffectActivatedAt = nil
                        pixel.Color = colors.RED
                        goto continue
                    end
                end

                while timeSinceEffectActivated > GameObj.BurnEffect.DurationOnMs+GameObj.BurnEffect.DurationOffMs do
                    timeSinceEffectActivated = timeSinceEffectActivated - (GameObj.BurnEffect.DurationOnMs+GameObj.BurnEffect.DurationOffMs)
                end
                if timeSinceEffectActivated < GameObj.BurnEffect.DurationOnMs then
                    pixel.Color = colors.MAGENTA
                else
                    pixel.Color = colors.NONE
                end
            elseif not pixel.Defect and pixel.Click and -- есть нажатие
                pixel.Bright < GameConfigObj.Bright and -- яркость заливки меньше, чем таргет цвета
                    GameStats.StageNum <= GameConfigObj.StagesQty then -- это еще не финиш
                -- минус жизнь, старт эффект
                audio.PlayAsync(audio.MISCLICK)
                minusLive()
                pixel.EffectActivatedAt = time.unix()
            end
            ::continue::
        end
    end
end

-- Минус жизнь
function minusLive()
    if GameConfigObj.StartLives > 0 then
        GameStats.CurrentLives = GameStats.CurrentLives - 1
        if GameStats.CurrentLives == 0 then -- game over
            audio.PlaySync(audio.GAME_OVER)
            audio.PlaySync(audio.DEFEAT)
            setGlobalColorBrightExceptColor(colors.RED, GameConfigObj.Bright-1, colors.NONE)
            switchStage(GameConfigObj.StagesQty+1)
        end
    end
end
