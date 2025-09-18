-- Название: Море волнуется
-- Автор: @GhostVeek (телеграм)
-- Описание механики: соревновательная механика, кто быстрее соберет необходимое количество пикселей своего цвета.
--      Пиксели могут перемещаться после нажатия, а могут пропадать до обновления пола (настраиваемо).
--      После окончания этапа пол становится "заморожен", за исключением пикселей на которых стоит игрок.
--      Внимание: Для старта игры требуется "встать" минимум на два цвета и нажать светящуюся кнопку на стене!
-- Идеи по доработке:
--      1. Кооперативное прохождение

require('avonlib')

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
    BurnEffect = { -- тайминги эффекта моргания
        DurationOnMs = 200,
        DurationOffMs = 120,
        TotalDurationMs = 1500,
    },
}

-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
    Bright = colors.Bright70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
    PointsToWin = 50, -- очки, необходимые для победы
    FillingPercentage = 50, -- процент заполнения пола цветными пикселями
    MovePixels = true, -- переменная, отвечающая за движение пикселя после нажатия
    StageDurationSec = 8, -- продолжительность этапа
    WinDurationSec = 10, -- продолжительность этапа победы перед завершением игры
    StopDurationSec = 3, -- продолжительность "заморозки"
}


-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()
local GameStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
    CurrentStars = 0,
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
    TargetScore = 0, -- очки
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
    ScoreboardVariant = 7,
}

-- Структура результата игры (служебная): должна возвращаться в NextTick() в момент завершения игры
-- После этого NextTick(), RangeFloor() и GetStats() больше не вызываются, игра окончена
local GameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = colors.NONE,
}

-- Локальные переменные для внутриигровой логики
local FloorMatrix = {} -- матрица пола
local ButtonsList = {} -- список кнопок
local Pixel = { -- пиксель тип
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false, -- переменная означающая, можно ли совершить клик по пикселю
    Defect = false, -- дефектный пиксель
    EffectActivatedAt = nil,
}

local CONST_STAGE_CHOOSE_COLOR = 0 -- выбор цвета
local CONST_STAGE_GAME = 1 -- игра
local CONST_STAGE_WIN = -1 -- победа
local StartPlayersCount = 0 -- количество игроков в момент нажатия кнопки старт
local StageStartTime = 0 -- время начала текущего этапа
local Freezing = false -- переменная, отвечающая за начало заморозки
local Freezed = false -- переменная, отвечающая за этап заморозки

local LeftAudioPlayed = { -- 5... 4... 3... 2... 1... Победа
    [5] = false,
    [4] = false,
    [3] = false,
    [2] = false,
    [1] = false,
}

local CountDownStarted = false
local PlayerInGame = {}
local iGameLoadTime = time.unix()
local iGameSetupTimestamp = 0

local tColors = {}
tColors[0] = colors.NONE
tColors[1] = colors.RED
tColors[2] = colors.GREEN
tColors[3] = colors.YELLOW
tColors[4] = colors.MAGENTA
tColors[5] = colors.CYAN
tColors[6] = colors.BLUE
tColors[7] = colors.WHITE

local bGamePaused = false

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson) -- старт игры
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

    if AL.RoomHasNFZ(GameObj) then
        AL.LoadNFZInfo()
    end

    GameObj.iMinX = 1
    GameObj.iMinY = 1
    GameObj.iMaxX = GameObj.Cols
    GameObj.iMaxY = GameObj.Rows
    GameObj.CenterX = math.floor(GameObj.Cols/2)
    GameObj.CenterY = math.floor(GameObj.Rows/2)

    if AL.NFZ.bLoaded then
        GameObj.iMinX = AL.NFZ.iMinX
        GameObj.iMinY = AL.NFZ.iMinY
        GameObj.iMaxX = AL.NFZ.iMaxX
        GameObj.iMaxY = AL.NFZ.iMaxY
    end

    if GameObj.StartPositions == nil then
        GameObj.StartPositions = {}

        local iX = GameObj.iMinX + 1
        local iY = GameObj.CenterY
        for iPlayerID = 1, 6 do
            GameObj.StartPositions[iPlayerID] = {}
            GameObj.StartPositions[iPlayerID].X = iX
            GameObj.StartPositions[iPlayerID].Y = iY
            GameObj.StartPositions[iPlayerID].Color = tColors[iPlayerID]

            iX = iX + (GameObj.StartPositionSize*2)
            if iX + GameObj.StartPositionSize > GameObj.iMaxX then
                iX = GameObj.CenterX - (GameObj.StartPositionSize*2)
                iY = iY + (GameObj.StartPositionSize*2)
            end
        end
    else
        for iPlayerID = 1, #GameObj.StartPositions do
            GameObj.StartPositions[iPlayerID].Color = tonumber(GameObj.StartPositions[iPlayerID].Color)
        end 
    end     

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel) -- тип аналогичен пикселю
        -- и подсветим все кнопки по-умлочанию, чтобы потребовать нажатия для старта
        ButtonsList[num].Color = colors.NONE
        ButtonsList[num].Bright = colors.BRIGHT70
    end

    GameStats.TargetScore = GameConfigObj.PointsToWin

    audio.PlayVoicesSyncFromScratch("sea-is-rough/statues-game.mp3") -- Игра "Море волнуется"
    audio.PlayVoicesSync("choose-color.mp3") -- Выберите цвет
    audio.PlayVoicesSync("get_ready_remember_color.mp3") -- Приготовьтесь и запомните свой цвет, вам будет нужно его искать
    --audio.PlaySync("voices/press-button-for-start.mp3") -- Для старта игры, нажмите светящуюся кнопку на стене

end


-- PauseGame (служебный): пауза игры
function PauseGame()
    bGamePaused = true
    audio.PlayVoicesSyncFromScratch(audio.PAUSE)
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
    StageStartTime = time.unix()
    bGamePaused = false
    audio.PlayVoicesSyncFromScratch(audio.START_GAME)
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
function SwitchStage()
    if GameStats.StageNum == CONST_STAGE_CHOOSE_COLOR then return; end
    switchStage(GameStats.StageNum+1)
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентироваться на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    if GameStats.StageNum == CONST_STAGE_CHOOSE_COLOR then -- этап выбора цвета
        local bDisPos = false
        if iGameSetupTimestamp == 0 or (time.unix() - 2) >= iGameSetupTimestamp then
            iGameSetupTimestamp = time.unix()
            bDisPos = true
        end

        StartPlayersCount = 0
        -- если есть хоть один клик на позиции, подсвечиваем её и заводим игрока по индексу
        for positionIndex, startPosition in ipairs(GameObj.StartPositions) do
            local bright = colors.BRIGHT15
            if checkPositionClick(startPosition, GameObj.StartPositionSize) or (CountDownStarted and PlayerInGame[positionIndex]) or (not bDisPos and PlayerInGame[positionIndex]) then
                GameStats.Players[positionIndex].Color = startPosition.Color
                bright = GameConfigObj.Bright
                PlayerInGame[positionIndex] = true
                StartPlayersCount = StartPlayersCount + 1
            elseif bDisPos then  
                GameStats.Players[positionIndex].Color = colors.NONE
                PlayerInGame[positionIndex] = false 
            end
            setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, startPosition.Color, bright)
        end

        if StartPlayersCount > 1 and (time.unix() - 10) >= iGameLoadTime then
            if not CountDownStarted then StageStartTime = time.unix() end
            CountDownStarted = true

            GameResults.PlayersCount = StartPlayersCount

            audio.ResetSync() -- очистить очередь звуков
            local timeSinceCountdown = time.unix() - StageStartTime
            GameStats.StageTotalDuration = 5 -- сек обратный отсчет
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceCountdown)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end

            if GameStats.StageLeftDuration <= 0 then -- начинаем игру
                switchStage(GameStats.StageNum + 1)
                resetCountdown()
            end
        else
            CountDownStarted = false
        end
    elseif GameStats.StageNum >= CONST_STAGE_GAME then -- этап игры
        -- часть логики производится в обработке клика
        -- происходит проверка длительности этапа и вызов эфекта заморозки
        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageLeftDuration = GameConfigObj.StageDurationSec - timeSinceStageStart + 1
        if timeSinceStageStart > GameConfigObj.StageDurationSec+GameConfigObj.StopDurationSec then
            switchStage(GameStats.StageNum+1)
        elseif timeSinceStageStart > GameConfigObj.StageDurationSec then
            audio.StopBackground()
            GameStats.StageLeftDuration = 0
            stageFreeze()
            processEffects()

        elseif timeSinceStageStart > GameConfigObj.StageDurationSec-2.5 then
            if not Freezing then
                audio.PlayVoicesSync("sea-is-rough/one-two-three-freeze.mp3")
                Freezing = true
            end
        end
    elseif GameStats.StageNum == CONST_STAGE_WIN then -- этап победы
        if not GameResults.AfterDelay then
            GameResults.AfterDelay = true
            return GameResults
        end

        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageTotalDuration = GameConfigObj.WinDurationSec
        GameStats.StageLeftDuration = GameStats.StageTotalDuration - timeSinceStageStart

        if GameStats.StageLeftDuration <= 0 then -- время завершать игру
            GameResults.AfterDelay = false
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
    if GameStats.StageNum < CONST_STAGE_GAME then
        return -- игнорируем клики вне этапа игры
    end

    if bGamePaused then 
        FloorMatrix[click.X][click.Y].Click = false
        return;
    end

    -- Если есть игрок с таким цветом, засчитываем очки
    local pixel = FloorMatrix[click.X][click.Y]
    local clickedColor = pixel.Color

    if click.Click and pixel.EffectActivatedAt == nil and clickedColor > colors.NONE then
        if not Freezed then
            local player = getPlayerByColor(clickedColor)
            if player ~= nil then
                audio.PlaySystemAsync(audio.CLICK)
                player.Score = player.Score + 1
                -- игрок набрал нужное количесто очков для победы
                if player.Score >= GameConfigObj.PointsToWin then
                    audio.PlaySystemSyncFromScratch(audio.GAME_SUCCESS)
                    audio.PlayVoicesSync(audio.VICTORY)
                    switchStage(CONST_STAGE_WIN)
                    setGlobalColorBright(clickedColor, GameConfigObj.Bright)

                    GameResults.Won = true
                    GameResults.Color = player.Color
                    return
                else -- еще не победил
                    local leftScores = GameConfigObj.PointsToWin - player.Score
                    if leftScores <= 5 and not LeftAudioPlayed[leftScores] then
                        --log.print("play "..leftScores)
                        audio.PlayLeftAudio(leftScores)
                        LeftAudioPlayed[leftScores] = true
                    end
                end
            end
        elseif clickedColor == colors.RED then
            audio.PlaySystemAsync(audio.MISCLICK)
            FloorMatrix[click.X][click.Y].EffectActivatedAt = time.unix()
        end
        -- и переместим пиксель в другое пустое место
        if GameConfigObj.MovePixels then
            placePixel(clickedColor)
        end

        -- стираем его на текущем месте
        FloorMatrix[click.X][click.Y].Color = colors.NONE
    end
    return nil
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  click = {
--      Button: int,
--      Click: bool,
--  }
function ButtonClick(click)
    if GameStats.StageNum ~= CONST_STAGE_CHOOSE_COLOR then
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
        FloorMatrix[defect.X][defect.Y].Color = colors.NONE
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
    ButtonsList[defect.Button].defect = defect.Defect
    -- потушим кнопку, если она дефектована и засветим, если дефектовку сняли
    if defect.Defect then
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT0
    else
        ButtonsList[defect.Button].Color = colors.BLUE
        ButtonsList[defect.Button].Bright = colors.BRIGHT70
    end
end

-- ======== Ниже вспомогательные методы внутриигровой логики =======

-- processEffects: отвечает за эфект моргания во время этапа заморозки пола
function processEffects()
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            local pixel = FloorMatrix[x][y]
            if pixel.EffectActivatedAt ~= nil then -- воспроизведем эффект
                local timeSinceEffectActivated = (time.unix() - pixel.EffectActivatedAt) * 1000
                if timeSinceEffectActivated > GameObj.BurnEffect.TotalDurationMs then
                    pixel.EffectActivatedAt = nil
                    goto continue
                end

                while timeSinceEffectActivated > GameObj.BurnEffect.DurationOnMs+GameObj.BurnEffect.DurationOffMs do
                    timeSinceEffectActivated = timeSinceEffectActivated - (GameObj.BurnEffect.DurationOnMs+GameObj.BurnEffect.DurationOffMs)
                end
                if timeSinceEffectActivated < GameObj.BurnEffect.DurationOnMs then
                    pixel.Color = colors.MAGENTA
                else
                    pixel.Color = colors.NONE
                end
            end
            ::continue::
        end
    end
end

-- Установка глобального цвета
function setGlobalColorBright(color, bright)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            FloorMatrix[x][y].Color = color
            FloorMatrix[x][y].Bright = bright
            FloorMatrix[x][y].EffectActivatedAt = nil
        end
    end

    for num, button in pairs(ButtonsList) do
        ButtonsList[num].Color = color
        ButtonsList[num].Bright = bright
    end
end

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
    Freezing = false
    Freezed = false

    if GameStats.StageNum == CONST_STAGE_CHOOSE_COLOR or
            GameStats.StageNum == CONST_STAGE_WIN then
        audio.StopBackground()
        return
    else
        audio.ResetSync() -- очистим очередь звуков, чтобы обрезать долгие речи на старте
        audio.PlayRandomBackground()
    end

    -- очистим поле
    setGlobalColorBright(colors.NONE, colors.BRIGHT0)

    -- заполнить все цветными на рандомных местах, пока не достигнем нужного процента
    local color = colors.RED -- будем поочередно расставлять цвета
    for filled = 1,GameObj.Cols*GameObj.Rows*GameConfigObj.FillingPercentage/100 do
        color = color + 1
        if tColors[color] == nil or tColors[color] == colors.NONE or tColors[color] >= colors.WHITE then
            color = 1
        end
        placePixel(tColors[color])
    end

    -- пропустим занятые старт позиции
    if GameStats.StageNum == CONST_STAGE_GAME then
        for _, startPosition in ipairs(GameObj.StartPositions) do
            if checkPositionClick(startPosition, GameObj.StartPositionSize) then
                setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, colors.NONE, colors.BRIGHT0)
            end
        end
    end
end

-- Размещение пикселя
function placePixel(color)
    if color == colors.NONE then
        return
    end
    for randomAttempt=1,10 do
        local x = math.random(1, GameObj.Cols)
        local y = math.random(1, GameObj.Rows)
        if FloorMatrix[x][y].Color == colors.NONE and
                -- not FloorMatrix[x][y].Click and -- под ноги не размещаем
                not FloorMatrix[x][y].Defect then -- не назначаем на дефектные пиксели
            FloorMatrix[x][y].Bright = GameConfigObj.Bright
            FloorMatrix[x][y].Color = color
            break
        end
    end
end

-- Проверка стартовой позиции
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

-- Заморозить пол
function stageFreeze()
    Freezed = true
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            FloorMatrix[x][y].Bright = GameConfigObj.Bright
            if FloorMatrix[x][y].Click then
                FloorMatrix[x][y].Color = colors.GREEN
            else
                FloorMatrix[x][y].Color = colors.RED
            end
        end
    end
end
