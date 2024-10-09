-- Название: Пиксель дуэль
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: соревновательная механика, кто быстрее добежит до своего пикселя
--      пиксели других игроков при этом могут тоже перемещаться (hard режим, настраивается)
--      Внимание: Для старта игры требуется "встать" минимум на два цвета и нажать светящуюся кнопку на стене!
-- Идеи по доработке:
--		1. Перерывы 5..10 сек на передышку, т.к бегать реально тяжело, тем более если поставить больше очков;
--		2. Вести счёт для серии коротких игр условно до 3х побед;
--		3. Модификация с заполняющимся полем: таргет - яркий, а после нажатия тускнеет и остается до конца).

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
    --[[StartPositions = { -- координаты расположения стартовых зон должны быть возле стены, т.к для старта надо нажать кнопку на стене
        { X = 2, Y = 2, Color = colors.RED },
        { X = 6, Y = 2, Color = colors.YELLOW },
        { X = 10, Y = 2, Color = colors.GREEN },
        { X = 14, Y = 2, Color = colors.CYAN },
        { X = 18, Y = 2, Color = colors.BLUE },
        { X = 22, Y = 2, Color = colors.MAGENTA },
    },]]
}
-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
    Bright = colors.BRIGHT70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
    PointsToWin = 10, -- сколько очков необходимо набрать для победы
    MoveAllPixels = false, -- hard режим – при нажатии пиксели других игроков тоже перемещаются в новые места
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
        { Score = 0, Lives = 0, Color = 0 },
        { Score = 0, Lives = 0, Color = 0 },
        { Score = 0, Lives = 0, Color = 0 },
        { Score = 0, Lives = 0, Color = 0 },
        { Score = 0, Lives = 0, Color = 0 },
        { Score = 0, Lives = 0, Color = 0 },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
}
-- Структура результата игры (служебная): должна возвращаться в NextTick() в момент завершения игры
-- После этого NextTick(), RangeFloor() и GetStats() больше не вызываются, игра окончена
local GameResults = {
    Won = false, -- в этой игре не используется, победа ноунейма не имеет смысла
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
local StartPlayersCount = 0 -- количество игроков в момент нажатия кнопки старт

local CountDownStarted = false
local PlayerInGame = {}

-- Этапы игры
local CONST_STAGE_CHOOSE_COLOR = 0 -- выбор цвета
local CONST_STAGE_GAME = 1 -- игра
local CONST_STAGE_WIN = 2 -- победа
local Stage = CONST_STAGE_CHOOSE_COLOR -- текущий этап
local StageStartTime = 0 -- время начала текущего этапа

-- Звуки оставшихся очков, проигрываются только один раз
local LeftAudioPlayed = { -- 5... 4... 3... 2... 1... Победа
    [5] = false,
    [4] = false,
    [3] = false,
    [2] = false,
    [1] = false,
}

local tArenaPlayerReady = {}

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    -- ограничение на размер стартовой позиции
    if GameObj.StartPositionSize == nil then
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
        ButtonsList[num].Bright = colors.BRIGHT70
    end

    GameStats.TargetScore = GameConfigObj.PointsToWin

    audio.PlaySyncFromScratch("games/pixel-duel-game.mp3") -- Игра "Пиксель дуэль"
    audio.PlaySync("voices/choose-color.mp3") -- Выберите цвет
    audio.PlaySync("voices/get_ready_sea.mp3") -- Приготовьтесь и запомните свой цвет, вам будет нужно его искать

    if GameObj.ArenaMode then 
        audio.PlaySync("press-zone-for-start.mp3")
    else
        audio.PlaySync("voices/press-button-for-start.mp3")
    end
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
    switchStage(Stage+1)
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентироваться на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    if Stage == CONST_STAGE_CHOOSE_COLOR then -- этап выбора цвета
        local bAnyPlayerClick = false

        -- если есть хоть один клик на позиции, подсвечиваем её и заводим игрока по индексу
        for positionIndex, startPosition in ipairs(GameObj.StartPositions) do
            local bright = colors.BRIGHT15
            if checkPositionClick(startPosition, GameObj.StartPositionSize) or (CountDownStarted and PlayerInGame[positionIndex]) then
                GameStats.Players[positionIndex].Color = startPosition.Color
                bright = GameConfigObj.Bright
                PlayerInGame[positionIndex] = true
            else
                GameStats.Players[positionIndex].Color = colors.NONE
                PlayerInGame[positionIndex] = false
            end
            setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, startPosition.Color, bright)

            if PlayerInGame[positionIndex] and GameObj.ArenaMode then
                local iCenterX = startPosition.X + math.floor(GameObj.StartPositionSize/3)
                local iCenterY = startPosition.Y + math.floor(GameObj.StartPositionSize/3)
                local bArenaClick = false

                for iX = iCenterX, iCenterX+1 do
                    for iY = iCenterY, iCenterY+1 do
                        FloorMatrix[iX][iY].Color = 5
                        if tArenaPlayerReady[positionIndex] then
                            FloorMatrix[iX][iY].Bright = GameConfigObj.Bright+2
                        end

                        if FloorMatrix[iX][iY].Click and not FloorMatrix[iX][iY].Defect then 
                            bArenaClick = true
                        end
                    end
                end

                if bArenaClick then
                    bAnyPlayerClick = true
                    tArenaPlayerReady[positionIndex] = true               
                else
                    tArenaPlayerReady[positionIndex] = false
                end                
            end
        end

        if bAnyPlayerClick then
            StartPlayersCount = countActivePlayers()

            if StageStartTime == 0 then
                StageStartTime = time.unix()
            end     
        else
            StartPlayersCount = 0
            StageStartTime = 0
        end

        --[[
        local currentPlayersCount = countActivePlayers()
        if currentPlayersCount ~= StartPlayersCount -- если с момента нажатия кнопки количество игроков изменилось
                or currentPlayersCount < 2 then -- если менее двух игроков
            -- нельзя стартовать
            StartPlayersCount = 0
            resetCountdown()
        end
        ]]

        if StartPlayersCount > 0 then
            CountDownStarted = true

            audio.PlaySyncFromScratch("") -- очистить очередь звуков
            local timeSinceCountdown = time.unix() - StageStartTime
            GameStats.StageTotalDuration = 3 -- сек обратный отсчет
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceCountdown)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end

            if GameStats.StageLeftDuration <= 0 then -- начинаем игру
                switchStage(Stage+1)
            end
        end
    elseif Stage == CONST_STAGE_GAME then -- этап игры
        GameStats.StageTotalDuration = 0
        -- Вся логика происходит в обработке клика
    elseif Stage == CONST_STAGE_WIN then -- этап выигрыша
        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageTotalDuration = GameConfigObj.WinDurationSec
        GameStats.StageLeftDuration = GameStats.StageTotalDuration - timeSinceStageStart

        if GameStats.StageLeftDuration <= 0 then -- время завершать игру
            -- в этой игре никакие флаги результата не используются, победа ноунейма не имеет смысла
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

    if Stage ~= CONST_STAGE_GAME then
        return -- игнорируем клики вне этапа игры
    end

    -- Если есть игрок с таким цветом, засчитываем очки
    local clickedColor = FloorMatrix[click.X][click.Y].Color
    local player = getPlayerByColor(clickedColor)
    if player == nil then
        return
    end

    audio.PlayAsync(audio.CLICK)
    player.Score = player.Score + 1

    -- игрок набрал нужное количесто очков для победы
    if player.Score >= GameConfigObj.PointsToWin then
        audio.PlaySyncFromScratch(audio.GAME_SUCCESS)
        audio.PlaySyncColorSound(player.Color)
        audio.PlaySync(audio.VICTORY)

        switchStage(CONST_STAGE_WIN)
        setGlobalColorBright(player.Color, GameConfigObj.Bright)
        return
    else -- еще не победил
        local leftScores = GameConfigObj.PointsToWin - player.Score
        local alreadyPlayed = LeftAudioPlayed[leftScores]
        if alreadyPlayed ~= nil and not alreadyPlayed then
            audio.PlayLeftAudio(leftScores)
            LeftAudioPlayed[leftScores] = true
        end
    end

    -- и переместим пиксель в другое пустое место
    if GameConfigObj.MoveAllPixels then -- для всех игроков
        setGlobalColorBright(colors.NONE, colors.BRIGHT0)
        placeAllPlayerPixels()
    else -- переместим только пиксель нажавшего игрока
        placePixel(player.Color)
        FloorMatrix[click.X][click.Y].Color = colors.NONE
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
    if Stage ~= CONST_STAGE_CHOOSE_COLOR then
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

    if FloorMatrix[defect.X][defect.Y].Color > colors.NONE then --  переместим пиксель
        placePixel(FloorMatrix[defect.X][defect.Y].Color)
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
    ButtonsList[defect.Button].Defect = defect.Defect
    -- потушим кнопку, если она дефектована и засветим, если дефектовку сняли
    if defect.Defect then
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT0
    else
        ButtonsList[defect.Button].Color = colors.BLUE
        ButtonsList[defect.Button].Bright = colors.BRIGHT70
    end
end

-- ======== Ниже вспомогательные методы внутренней логики =======

-- Установка глобального цвета
function setGlobalColorBright(color, bright)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            FloorMatrix[x][y].Color = color
            FloorMatrix[x][y].Bright = bright
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
    Stage = newStage
    StageStartTime = time.unix()

    resetCountdown()

    if Stage == CONST_STAGE_GAME then
        audio.PlayRandomBackground()
        audio.PlaySync(audio.START_GAME)

        -- Очистим поле
        setGlobalColorBright(colors.NONE, colors.BRIGHT0)

        -- Поставим по одному пикселю каждому игроку
        placeAllPlayerPixels()
    else
        audio.StopBackground()
    end
end

-- Расставить пиксели всех игроков
function placeAllPlayerPixels()
    for playerIdx, player in ipairs(GameStats.Players) do
        placePixel(player.Color)
    end
end

-- Поставить пиксель конкретного цвета в случайном месте
function placePixel(color)
    if color == colors.NONE or getPlayerByColor(color) == nil then
        return
    end

    local minX = 1
    local maxX = GameObj.Cols
    local minY = 1
    local maxY = GameObj.Rows

    if GameObj.ArenaMode ~= nil and GameObj.ArenaMode then
        local _,player = getPlayerByColor(color)
        minX = GameObj.StartPositions[player].X
        maxX = GameObj.StartPositions[player].X + GameObj.StartPositionSize-1
        minY = GameObj.StartPositions[player].Y
        maxY = GameObj.StartPositions[player].Y + GameObj.StartPositionSize-1
    end

    for randomAttempt=1,100 do
        local x = math.random(minX, maxX)
        local y = math.random(minY, maxY)
        if FloorMatrix[x][y].Color == colors.NONE and
                not FloorMatrix[x][y].Click and
                not FloorMatrix[x][y].Defect then -- не назначаем на дефектные пиксели
            FloorMatrix[x][y].Bright = GameConfigObj.Bright
            FloorMatrix[x][y].Color = color
            break
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
            goto continue -- ignore outside the game field
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
            goto continue -- ignore outside the game field
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
            return player, playerIdx
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
