-- Название: Найди цвет
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: Встать на определенный сегмент с нужным цветом для смены этапа
--    Внимание: Для старта игры требуется занять позицю и нажать любую кнопку на стене!

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
    YOffset = 1, -- смещение по вертикали, костыль для московской комнаты
    StartPositionSize = 2, -- размер стартовой зоны для игрока, для маленькой выездной платформы удобно ставить тут 1
}
-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
    Bright = colors.BRIGHT70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
    StagesQty=10, -- сколько очков необходимо набрать для победы
    WinDurationSec = 10, -- длительность этапа победы перед завершением игры
    BlockSize = 2,
    CircleDrawDelayMs = 30,
    GameDurationSec = 10
}

-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()
local GameStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
    CurrentStars = 0,
    TotalStars = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = colors.RED },
        { Score = 0, Lives = 0, Color = colors.YELLOW },
        { Score = 0, Lives = 0, Color = colors.GREEN },
        { Score = 0, Lives = 0, Color = colors.CYAN },
        { Score = 0, Lives = 0, Color = colors.BLUE },
        { Score = 0, Lives = 0, Color = colors.MAGENTA },
    },
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
    ScoreboardVariant = 2,
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
    Click = false,
    Defect = false,
}
local StartPlayersCount = 0 -- количество игроков в момент нажатия кнопки старт
local TargetPositions = {}
local StageDoneAt = 0

local CountDownStarted = false
local PlayerInGame = {}
local iGameLoadTime = time.unix()
local iGameSetupTimestamp = 0

-- Этапы игры
local CONST_STAGE_FINISH = -1
local CONST_STAGE_START = 0
local CONST_STAGE_FIRST = 1
local StageStartTime = 0 -- время начала текущего этапа
local GameStartTime = 0 --время начала игровых этапов
local Circle
local STAGE_DONE_SEC = 1

--Звуки оставшихся очков, проигрываются только один раз
local LeftAudioPlayed = { -- 3... 2... 1...
    [12] = false,
    [5] = false,
    [4] = false,
    [3] = false,
    [2] = false,
    [1] = false,
}
local StageDonePlayed = false

local tColors = {}
tColors[1] = colors.GREEN
tColors[2] = colors.RED
tColors[3] = colors.YELLOW
tColors[4] = colors.MAGENTA
tColors[5] = colors.CYAN
tColors[6] = colors.BLUE
tColors[7] = colors.WHITE

-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    -- ограничение на размер стартовой позиции
    if GameObj.StartPositionSize == nil or
            GameObj.StartPositionSize < 1 or GameObj.StartPositionSize > 2 then
        GameObj.StartPositionSize = 2
    end

    if GameConfigObj.BlockSize < 1 then
        GameConfigObj.BlockSize = 1
        GameObj.YOffset = 0
    elseif GameConfigObj.BlockSize > 2 then
        GameConfigObj.BlockSize = 2
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
        ButtonsList[num].Color = colors.NONE
        ButtonsList[num].Bright = colors.BRIGHT70
    end

    if GameObj.StartPositions == nil then
        GameObj.StartPositions = {}

        local iX = 2
        local iY = math.floor(GameObj.Rows/2)
        for iPlayerID = 1, GameConfigObj.PlayerCount do
            GameObj.StartPositions[iPlayerID] = {}
            GameObj.StartPositions[iPlayerID].X = iX
            GameObj.StartPositions[iPlayerID].Y = iY
            GameObj.StartPositions[iPlayerID].Color = colors.GREEN

            iX = iX + (GameObj.StartPositionSize*2)
            if iX + GameObj.StartPositionSize > GameObj.Cols then
                iX = 2
                iY = iY + (GameObj.StartPositionSize+1)
            end
        end
    else
        for iPlayerID = 1, #GameObj.StartPositions do
            GameObj.StartPositions[iPlayerID].Color = tonumber(GameObj.StartPositions[iPlayerID].Color)
        end 
    end   

    GameStats.TotalStars = GameConfigObj.StagesQty
    GameStats.TotalStages=GameConfigObj.StagesQty

    GameResults.PlayersCount = GameConfigObj.PlayerCount

    audio.PlayVoicesSyncFromScratch("find-color/find-color-game.mp3") -- Игра "Найди цвет"
    audio.PlayVoicesSync("stand_on_green_and_get_ready.mp3") -- Встаньте на зеленую зону и приготовьтесь
    --audio.PlaySync("voices/press-button-for-start.mp3") -- Для старта игры, нажмите светящуюся кнопку на стене
end

-- PauseGame (служебный): пауза игры
function PauseGame()
    audio.PlayVoicesSyncFromScratch(audio.PAUSE)
end

-- ResumeGame (служебный): снятие игры с паузы
function ResumeGame()
    audio.PlayVoicesSyncFromScratch(audio.START_GAME)
end

-- SwitchStage (служебный): может быть использован для принудительного переключению этапа
function SwitchStage()
    if GameStats.StageNum == CONST_STAGE_START then return; end
    switchStage(GameStats.StageNum+1)
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентироваться на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    if GameStats.StageNum == CONST_STAGE_START then -- этап выбора цвета
        local bDisPos = false
        if iGameSetupTimestamp == 0 or (time.unix() - 1) >= iGameSetupTimestamp then
            iGameSetupTimestamp = time.unix()
            bDisPos = true
        end

        StartPlayersCount = 0
        -- если есть хоть один клик на позиции, подсвечиваем её и заводим игрока по индексу
        for positionIndex, startPosition in ipairs(GameObj.StartPositions) do

            local bright = colors.BRIGHT15
            if checkPositionClick(startPosition, GameObj.StartPositionSize) or (not bDisPos and PlayerInGame[positionIndex]) or (PlayerInGame[positionIndex] and CountDownStarted) then
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

        if StartPlayersCount > 1 and (time.unix() - 5) >= iGameLoadTime then
            if not CountDownStarted then StageStartTime = time.unix() end
            CountDownStarted = true

            audio.PlaySyncFromScratch("") -- очистить очередь звуков
            local timeSinceCountdown = time.unix() - StageStartTime
            GameStats.StageTotalDuration = 5 -- сек обратный отсчет
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceCountdown)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end

            if GameStats.StageLeftDuration <= 0 then -- начинаем игру
                switchStage(GameStats.StageNum+1)
            end
        else
            CountDownStarted = false
        end
    elseif GameStats.StageNum == CONST_STAGE_FINISH then
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

    elseif GameStats.StageNum <= GameConfigObj.StagesQty then -- этап игры
        local timeSinceGameStart = time.unix() - GameStartTime
        GameStats.StageTotalDuration = GameConfigObj.GameDurationSec
        GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceGameStart)

        local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
        if alreadyPlayed ~= nil and not alreadyPlayed then
            audio.PlayLeftAudio(GameStats.StageLeftDuration)
            LeftAudioPlayed[GameStats.StageLeftDuration] = true
        end

        -- time to switch stage
        local timeSinceStageDoneAt = time.unix() - StageDoneAt
        if StageDoneAt ~= 0 and timeSinceStageDoneAt > STAGE_DONE_SEC then
            Circle = nil
            switchStage(GameStats.StageNum+1)
        end

        local LastClickedPos = 1
        local AllPosClicked = true
        for targetIndex, targetPosition in ipairs(TargetPositions) do
            local PosClicked = checkPositionClick(TargetPositions[targetIndex], GameConfigObj.BlockSize)
            AllPosClicked = AllPosClicked and PosClicked
            if PosClicked then
                if TargetPositions[targetIndex].ClickedAt == 0 then
                    TargetPositions[targetIndex].ClickedAt = time.unix()
                end
                setColorBrightForStartPosition(TargetPositions[targetIndex], GameConfigObj.BlockSize, GameStats.TargetColor, colors.BRIGHT15)
            else
                TargetPositions[targetIndex].ClickedAt = 0
                setColorBrightForStartPosition(TargetPositions[targetIndex], GameConfigObj.BlockSize, GameStats.TargetColor, GameConfigObj.Bright)
            end


            if TargetPositions[targetIndex].ClickedAt > TargetPositions[LastClickedPos].ClickedAt then
                LastClickedPos = targetIndex
            end

        end

        if AllPosClicked and StageDoneAt == 0 then
            StageDoneAt = time.unix()
            if not StageDonePlayed then
                audio.PlaySystemAsync(audio.STAGE_DONE)
                StageDonePlayed = true

                GameResults.Score = GameResults.Score + (10 * GameStats.StageLeftDuration)
            end
            Circle = {
                X0 = TargetPositions[LastClickedPos].X,
                Y0 = TargetPositions[LastClickedPos].Y,
                Radius = 1,
                Color = targetColor(GameStats.StageNum),
                LastDraw = 0
            }
        end


        if Circle~=nil then
            local timeSinceLastDrawMs = (time.unix() - Circle.LastDraw)*1000 --время с момента последней отрисовки круга в миллисекундах
            if timeSinceLastDrawMs > GameConfigObj.CircleDrawDelayMs then
                drawCircle(Circle.X0, Circle.Y0, Circle.Radius, Circle.Color, colors.BRIGHT85)
                drawCircle(Circle.X0, Circle.Y0, Circle.Radius+1, Circle.Color, colors.BRIGHT45)
                drawCircle(Circle.X0, Circle.Y0, Circle.Radius+1, Circle.Color, colors.BRIGHT15)

                Circle.LastDraw = time.unix()
                Circle.Radius = Circle.Radius + 1
            end
        end


        timeSinceGameStart = time.unix() - GameStartTime
        if timeSinceGameStart > GameConfigObj.GameDurationSec or GameStats.StageNum > GameConfigObj.StagesQty then
            if GameStats.StageNum > GameConfigObj.StagesQty then
                setGlobalColorBright(colors.GREEN, GameConfigObj.Bright)
                audio.PlaySystemSyncFromScratch(audio.GAME_SUCCESS)
                audio.PlayVoicesSync(audio.VICTORY)
                GameResults.Won = true
                GameResults.Color = colors.GREEN
            else
                setGlobalColorBright(colors.RED, GameConfigObj.Bright)
                audio.PlaySystemSync(audio.GAME_OVER)
                audio.PlayVoicesSync(audio.DEFEAT)
                GameResults.Won = false
                GameResults.Color = colors.RED
            end
            switchStage(CONST_STAGE_FINISH)

            --log.print(inspect(GameResults))
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
    if click.X < 1 or click.X > GameObj.Cols or
            click.Y < 1 + GameObj.YOffset or click.Y > GameObj.Rows then
        return
    end

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
    if not click or not ButtonsList[click.Button] then return; end

    if GameStats.StageNum ~= CONST_STAGE_START then
        return -- не интересуют клики кнопок вне этапа выбора цвета
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

        if FloorMatrix[defect.X][defect.Y].Color == GameStats.TargetColor then
            switchStage(GameStats.StageNum)
        end
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
    if not ButtonsList[defect.Button] then return end

    ButtonsList[defect.Button].Defect = defect.Defect
    -- потушим кнопку, если она дефектована и засветим, если дефектовку сняли
    if defect.Defect then
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT0
    else
        ButtonsList[defect.Button].Color = colors.BLUE
        --Bd = d + 4*(x-y) + 10
        --y = y - 1
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
    if newStage == CONST_STAGE_FIRST and newStage ~= GameStats.StageNum then
        audio.PlayRandomBackground()
        resetCountdown()
        GameStartTime = time.unix()
    end

    GameStats.StageNum = newStage
    StageStartTime = time.unix()
    StageDoneAt = 0
    StageDonePlayed = false

    if newStage < CONST_STAGE_FIRST or newStage > GameConfigObj.StagesQty  then
        audio.StopBackground()
        return
    end

    GameStats.CurrentStars = newStage

    local TargetColor=targetColor(newStage)
    GameStats.TargetColor=TargetColor

    audio.PlaySyncFromScratch("") -- очистим очередь звуков, чтобы обрезать долгие речи на старте
    audio.PlaySyncColorSound(GameStats.TargetColor)

    local NewColor

    for y = GameObj.YOffset+1, GameObj.Rows, GameConfigObj.BlockSize do
        for x = 1, GameObj.Cols, GameConfigObj.BlockSize do
            for randomAttempt = 0, 50 do
                NewColor = tColors[math.random(1, 7)]
                if NewColor==TargetColor then
                    goto continue
                end
                if x>1 and FloorMatrix[x-1][y].Color == NewColor then
                    goto continue
                end
                if y>1 and FloorMatrix[x][y-1].Color == NewColor then
                    goto continue
                end
                do
                    break
                end
                ::continue::
            end

            for nx = x, math.min(x + GameConfigObj.BlockSize, GameObj.Cols) do
                for ny = y, math.min(y + GameConfigObj.BlockSize, GameObj.Rows) do
                    FloorMatrix[nx][ny].Color = NewColor
                    FloorMatrix[nx][ny].Bright = GameConfigObj.Bright
                end
            end

        end
    end

    local NewTargetPositions = {}
    local currentPlayersCount = countActivePlayers()

    -- дозаполним нужный цвет по количеству игроков
    for p = 1, countActivePlayers() do
        for randomAttempt = 0, 50 do
            x = (math.random(GameObj.Cols/GameConfigObj.BlockSize)-1)*GameConfigObj.BlockSize + 1
            y = (math.random(GameObj.Rows/GameConfigObj.BlockSize)-1)*GameConfigObj.BlockSize + 1 + GameObj.YOffset

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

            if FloorMatrix[x][y].Defect then goto continue end

            FloorMatrix[x][y].Color = GameStats.TargetColor
            FloorMatrix[x][y].Bright = GameConfigObj.Bright

            if GameConfigObj.BlockSize > 1 then
                FloorMatrix[x][y+1].Color = GameStats.TargetColor
                FloorMatrix[x][y+1].Bright = GameConfigObj.Bright

                FloorMatrix[x+1][y].Color = GameStats.TargetColor
                FloorMatrix[x+1][y].Bright = GameConfigObj.Bright

                FloorMatrix[x+1][y+1].Color = GameStats.TargetColor
                FloorMatrix[x+1][y+1].Bright = GameConfigObj.Bright
            end
            do break end
            ::continue::
        end
        table.insert(NewTargetPositions, p, {X = x, Y = y, ClickedAt = 0})
    end
    TargetPositions = NewTargetPositions

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

function targetColor(stage)
    if stage < CONST_STAGE_FIRST then
        return 0
    end
    return tColors[stage%7+1]
end

function drawCircle(x0, y0, radius, color, bright)
    if radius < 0 then
        return
    end

    local x = 0
    local y = radius
    local d = 3-2*radius

    while x <= y do
        drawPixel(x0+x, y0+y, color, bright)
        drawPixel(x0+x, y0+y-1, color, bright)
        drawPixel(x0+x, y0-y, color, bright)
        drawPixel(x0+x, y0-y-1, color, bright)

        drawPixel(x0-x, y0+y, color, bright)
        drawPixel(x0-x, y0+y+1, color, bright)
        drawPixel(x0-x, y0-y, color, bright)
        drawPixel(x0-x, y0-y+1, color, bright)

        drawPixel(x0+y, y0+x, color, bright)
        drawPixel(x0+y-1, y0+x, color, bright)
        drawPixel(x0+y, y0-x, color, bright)
        drawPixel(x0+y-1, y0-x, color, bright)

        drawPixel(x0-y, y0+x, color, bright)
        drawPixel(x0-y+1, y0+x, color, bright)
        drawPixel(x0-y, y0-x, color, bright)
        drawPixel(x0-y+1, y0-x, color, bright)

        if d < 0 then
            d = d + 4*x + 6
        else
            d = d + 4*(x-y) + 10
            y = y - 1
        end

        x = x + 1

    end
end

function drawPixel(x, y, color, bright)
    if x < 1 or x > GameObj.Cols or
            y < 1 + GameObj.YOffset or y > GameObj.Rows then
        return
    end
    FloorMatrix[x][y].Color = color
    FloorMatrix[x][y].Bright = bright
end
