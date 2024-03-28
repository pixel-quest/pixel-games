-- Название: Перебежка(вроде так)
-- Автор: @GhostVeek (телеграм)
-- Описание механики: командная механика, игроки встают на пиксели, обозначающие безопасную зону
-- по полу двигается "лава", наступать на нее нельзя. Игроки должны собирать светящиеся кнопки,
-- наступая на лаву снимаются жизни
-- Идеи по доработке:
--

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
--              цвета: RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE
local audio = require("audio")

-- Константы цветов (0 - 7): NONE, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
-- Константы яркости (0 - 7): BRIGHT0, BRIGHT15, BRIGHT30, BRIGHT45, BRIGHT60, BRIGHT70, BRIGHT85, BRIGHT100
local colors = require("colors")

-- Библиотека help позволяющая вызывать методы глубокого и неглубокого копирования
--      .ShallowCopy(table) - неглубокое копирование таблицы
--      .DeepCopy(table) - глубокое копирования таблицы
local help = require("help")

-- Библиотека log, позволяющая выводить строку в консоль разработчика
--      .print(string)
local log = require("log")

-- Полезные стандартные функции
--      math.ceil() – округление вверх
--      math.floor() – отбрасывает дробную часть и переводит значение в целочисленный тип
--      math.random(upper) – генерирует целое число в диапазоне [1..upper]
--      math.random(lower, upper) – генерирует целое число в диапазоне [lower..upper]
--      math.random(lower, upper) – генерирует целое число в диапазоне [lower..upper]

-- Импортированные конфиги (ниже приведен лишь ПРИМЕР структуры,
--  сами объекты будут переопределены в StartGame() при декодировании json)
-- Объект игры, см. файл game.json

-- Написать сюда позицию рядом с каждой кнопкой, все зеленого цвета
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
    },-- дописать позиции для каждой кнопки
    -- пока не знаю, что сюда можно еще дописать
}

-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json

--убрать все лишнее
-- ввести переменную, отвечающую за кол-во горящих кнопок
local GameConfigObj = {
    Bright = colors.Bright70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
    PointsToWin = 10, -- очки, необходимые для победы в одном этапе
    FillingPercentage = 10, -- процент заполнения пола цветными пикселями
    StageDuration = 10, -- продолжительность этапа
    WinDurationSec = 10, -- продолжительность этапа победы перед завершением игры
    StopDurationSec = 3, -- продолжительность "заморозки"
    WrongEffectDuration = 1, -- длятельность моргания
    StopColor = colors.RED, -- цвет пола, во время эфекта "заморозки"
    WrongColor = colors.MAGENTA, -- цвет моргания пикселя, при нажатии на замороженный пиксель
    NumberOfButtons = 3, -- количество кнопок вызываемых за оин раз
}


-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()

-- Не знаю пока, стоит ли вообще считать игроков, если можно играть даже одному
local GameStats = {
    StageLeftDuration = 3, -- seconds
    StageTotalDuration = 6, -- seconds
    Players = {
        {Score = 0, Color = colors.GREEN},
    },
    CurrentStars = 0,
    CurrentLives = 0,
    TotalLives = 3,
    TargetScore = 0, -- очки
    StageNum = 1,
    TotalStages = 4,
    TargetColor = colors.NONE,
}

-- Структура результата игры (служебная): должна возвращаться в NextTick() в момент завершения игры
-- После этого NextTick(), RangeFloor() и GetStats() больше не вызываются, игра окончена
local GameResults = {
    Won = false, -- в этой игре не используется, победа ноунейма не имеет смысла
}

--Это оставляется
-- Локальные переменные для внутриигровой логики
local FloorMatrix = {} -- матрица пола
local ButtonsList = {} -- список кнопок

--По идее переменная клик нужна только для того,
-- чтобы можно было проверить наступил ли человек не туда
-- так как кнопка имеет такую штуку, что она светится,
-- то нужно ввести доп переменную, отвечающую за это
local Pixel = { -- пиксель тип
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false, -- переменная означающая, можно ли совершить клик по пикселю
    Defect = false, -- дефектный пиксель
    EffectActivatedAt = nil,
}

-- freezed убрать, создать новые этапы игры, не поню сколько, но по идее есть этап
-- старт, этам игр, их вроде 5, и этап побуды, когда все загорается зеленым
local CONST_STAGE_CHOOSE_COLOR = 0 -- выбор цвета
local CONST_STAGE_GAME = 1 -- игра
local CONST_STAGE_WIN = 2 -- победа
local CONST_STAGE_GAMEOVER = 3 -- проигрыш
local Stage = CONST_STAGE_CHOOSE_COLOR -- текущий этап
local StageStartTime = 0 -- время начала текущего этапа
local StageStartTime2 = 0
-- ввести, что-то наподобие local STAGE_FLOOR = 1
-- но лучше наверное пользоваться этапом из GameStats, надо посоветоваться
--и таких столько, сколько этапов

local LeftAudioPlayed = { -- 5... 4... 3... 2... 1... Победа
    [5] = false,
    [4] = false,
    [3] = false,
    [2] = false,
    [1] = false,
}

ActPlayer = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
-- константы отвечающие за направление движения
local Move_right = 1
local Move_left = -1
local Move_up = 2
local Move_down = -2
local Move_main_diagonal = 3
local Move_side_diagonal = -3

local StartPlayersCount = 0

-- расположение зон и кнопок. Рандом
function RandomZone()
    local active = countActivePlayers()
    local kol = 0
    local array = {}
    for i, num in pairs(GameObj.Buttons) do
        array[i] = num
    end
    for i = 0, 1000 do
        local index = math.random(1, 20)
        --if ButtonsList[array[index]].Bright == colors.BRIGHT70 and ButtonsList[array[index]].Colors ~= colors.NONE and not GameObj.StartPositions[index].Clik then
        if not ButtonsList[array[index]].Defect --[[and not GameObj.StartPositions[index].Clik]] and ButtonsList[GameObj.Buttons[index]].Color ~= colors.BLUE then
            kol = kol + 1
            ButtonsList[GameObj.Buttons[index]].Color = colors.BLUE
            ButtonsList[GameObj.Buttons[index]].Bright = colors.BRIGHT70
            for i=0, GameObj.StartPositionSize*GameObj.StartPositionSize-1 do
                local x = GameObj.StartPositions[index].X + i%GameObj.StartPositionSize
                local y = GameObj.StartPositions[index].Y + math.floor(i/GameObj.StartPositionSize)

                FloorMatrix[x][y].Color = colors.GREEN
                FloorMatrix[x][y].Bright = colors.BRIGHT70
            end
        end
        if kol >= active then
            break
        end
    end
end


-- Вункция для рисования по колоннам, задаются координаты начала
function DrawnColumns(X)

    --[[for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= colors.GREEN then
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
		end
	end]]
    if GameConfigObj.WidthLine > 1 and X > 23 then
        X = X - GameConfigObj.WidthLine
    end
    for i = 0, GameConfigObj.WidthLine do
        for j = 1, GameObj.Rows do
            if FloorMatrix[X+i][j].Color ~= colors.GREEN then
                FloorMatrix[X+i][j].Color = colors.RED
                FloorMatrix[X+i][j].Bright = colors.BRIGHT70
            end
        end
    end
end

-- Вункция для рисования по колоннам, задаются координаты начала
function DrawnRows(Y)
    --[[for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= colors.GREEN  then
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
		end
	end]]

    if GameConfigObj.WidthLine > 1 and Y > 14 then
        Y = Y - GameConfigObj.WidthLine
    end
    for i = 0, GameConfigObj.WidthLine do
        for j = 1, GameObj.Cols do
            if FloorMatrix[j][Y+i].Color ~= colors.GREEN then
                FloorMatrix[j][Y+i].Color = colors.RED
                FloorMatrix[j][Y+i].Bright = colors.BRIGHT70
            end
        end
    end
end

local x = 0
local y = 0
-- функция для движения по колоннам
function MoveColumns(direction)
    -- нужно будет проверять значение координат, чтобы если что сменить направление
    if direction > 0 then
        x = x + 1
        DrawnColumns(x)
    else
        if x > 1 then
            x = x - 1
        end
        DrawnColumns(x)
    end
end

-- функция для движения по столбцам
function MoveRows(direction)
    -- нужно будет проверять значение координат, чтобы если что сменить направление
    if direction > 0 then
        y = y + 1
        DrawnRows(y)
    else
        if y > 1 then
            y = y - 1
        end
        DrawnRows(y)
    end
end

-- нарисовать крест
function DrawnCross(X, Y)
    --[[for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= colors.GREEN  then
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
		end
	end]]
    if GameConfigObj.WidthLine > 1 and X > 23 then
        X = X - GameConfigObj.WidthLine
    end
    for i = 0, GameConfigObj.WidthLine do
        for j = 1, GameObj.Rows do
            if FloorMatrix[X+i][j].Color ~= colors.GREEN then
                FloorMatrix[X+i][j].Color = colors.RED
                FloorMatrix[X+i][j].Bright = colors.BRIGHT70
            end
        end
    end

    if GameConfigObj.WidthLine > 1 and Y > 14 then
        Y = Y - GameConfigObj.WidthLine
    end
    for i = 0, GameConfigObj.WidthLine do
        for j = 1, GameObj.Cols do
            if FloorMatrix[j][Y+i].Color ~= colors.GREEN then
                FloorMatrix[j][Y+i].Color = colors.RED
                FloorMatrix[j][Y+i].Bright = colors.BRIGHT70
            end
        end
    end

end

function MoveCross(direction1, direction2)
    --[[for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= colors.GREEN then
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
		end
	end]]
    -- нужно следить за координатами
    if direction2 > 0 then
        y = y + 1
    else
        if y > 1 then
            y = y - 1
        end
    end

    if direction1 > 0 then
        x = x + 1
    else
        if x > 1 then
            x = x - 1
        end
    end
    DrawnCross(x, y)
end

function DrawnDiagonal(X, Y)
    if GameConfigObj.WidthLine > 1 and Y > 14 then
        Y = Y - GameConfigObj.WidthLine
    end
    if GameConfigObj.WidthLine > 1 and X > 14 then
        X = X - GameConfigObj.WidthLine
    end
    for k = 0, GameConfigObj.WidthLine do
        X = X + k
        local i = X
        local j = Y
        while i <= 24 and j <= 15 do
            if FloorMatrix[i][j].Color ~= colors.GREEN then
                FloorMatrix[i][j].Color = colors.RED
                FloorMatrix[i][j].Bright = colors.BRIGHT70
            end
            i = i + 1
            j = j + 1
        end

        i = X
        j = Y
        while i > 0 and j > 0 do
            if FloorMatrix[i][j].Color ~= colors.GREEN then
                FloorMatrix[i][j].Color = colors.RED
                FloorMatrix[i][j].Bright = colors.BRIGHT70
            end
            i = i - 1
            j = j - 1
        end
    end
end

function MoveDiagonal(direction)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if FloorMatrix[x][y].Color ~= colors.GREEN  then
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
        end
    end
    if direction > 0 then
        if x ~= 24 then
            x = x + 1
        else
            if y ~= 1 then
                y = y - 1
            end
        end
        DrawnDiagonal(x, y)
    else
        if x ~= 1 then
            x = x - 1
        else
            if y ~= 15 then
                y = y + 1
            end
        end
        DrawnDiagonal(x, y)
    end
end


CTimer = {}
CTimer.tTimers = {}

CTimer.New = function(iSetTime, fCallback)
    CTimer.tTimers[#CTimer.tTimers+1] = {iTime = iSetTime, fCallback = fCallback}
end

-- Просчёт таймеров каждый тик
CTimer.CountTimers = function(iTimePassed)
    for i = 1, #CTimer.tTimers do
        if CTimer.tTimers[i] ~= nil then
            CTimer.tTimers[i].iTime = CTimer.tTimers[i].iTime - iTimePassed

            if CTimer.tTimers[i].iTime <= 0 then
                iNewTime = CTimer.tTimers[i].fCallback()
                if iNewTime and iNewTime ~= nil then -- если в return было число то создаём новый таймер с тем же колбеком
                    iNewTime = iNewTime + CTimer.tTimers[i].iTime
                    CTimer.New(iNewTime, CTimer.tTimers[i].fCallback)
                end

                CTimer.tTimers[i] = nil
            end
        end
    end
end
--//


--не изменяется совершенно, удаляется только победные очки, а может и нет, надо уточнить
-- StartGame (служебный): инициализация и старт игры
function StartGame(gameJson, gameConfigJson) -- старт игры
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    --[[CTimer.New(1000, function()
        log.print(#CTimer.tTimers)
        return 1000
    end)]]

    -- ограничение на размер стартовой позиции
    if GameObj.StartPositionSize == nil or
            GameObj.StartPositionSize < 1 or GameObj.StartPositionSize > 2 then
        GameObj.StartPositionSize = 2
    end

    for x=1,GameObj.Cols do
        FloorMatrix[x] = {}    -- новый столбец
        for y=1,GameObj.Rows do
            FloorMatrix[x][y] = help.DeepCopy(Pixel) -- заполняем нулевыми пикселями
        end
    end


    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.DeepCopy(Pixel) -- тип аналогичен пикселю
        -- и подсветим все кнопки по-умлочанию, чтобы потребовать нажатия для старта
        ButtonsList[num].Color = colors.BLUE
        ButtonsList[num].Bright = colors.BRIGHT70
    end

    --GameStats.TargetScore = GameConfigObj.PointsToWin

    audio.PlaySyncFromScratch("games/pixel-duel-game.mp3") -- Игра "Пиксель дуэль"
    audio.PlaySync("voices/choose-color.mp3") -- Выберите цвет
    audio.PlaySync("voices/get_ready_sea.mp3") -- Приготовьтесь и запомните свой цвет, вам будет нужно его искать
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
    switchStage(Stage+1)
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентировать на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг

-- изменить этап старта, по идее можно начать игру и с одним человеком
local NumberPlayer = 0
local iPrevTickTime = 0
local StartSwitchStage = 1
local flag = false
function NextTick()
    if Stage == CONST_STAGE_CHOOSE_COLOR then -- этап выбора цвета
        GameStats.CurrentLives = GameStats.TotalLives
        CTimer.CountTimers((time.unix() - iPrevTickTime) * 1000)
        iPrevTickTime = time.unix()

        x = GameConfigObj.OriginCoordinateX
        y = GameConfigObj.OriginCoordinateY
        -- если есть хоть один клик на позиции, подсвечиваем её и заводим игрока по индексу
        for positionIndex, startPosition in ipairs(GameObj.StartGame) do
            local bright = colors.BRIGHT70
            if checkPositionClick(startPosition, GameObj.StartPositionSize) then
                --GameStats.Players[1].Color = startPosition.Color
                bright = GameConfigObj.Bright
            else
                GameStats.Players[1].Color = colors.NONE
            end
            setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, startPosition.Color, bright)
        end

        local currentPlayersCount = countActivePlayers()
        if currentPlayersCount ~= StartPlayersCount -- если с момента нажатия кнопки количество игроков изменилось
                or currentPlayersCount < 1 then -- если менее двух игроков
            -- нельзя стартовать
            StartPlayersCount = 0
            resetCountdown()
        end

        if StartPlayersCount > 0 then
            GameStats.Players[1].Color = colors.GREEN
            local timeSinceCountdown = time.unix() - StageStartTime
            GameStats.StageTotalDuration = 3 -- сек обратный отсчет
            GameStats.StageLeftDuration = math.ceil(GameStats.StageTotalDuration - timeSinceCountdown)

            local alreadyPlayed = LeftAudioPlayed[GameStats.StageLeftDuration]
            if alreadyPlayed ~= nil and not alreadyPlayed then
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
                LeftAudioPlayed[GameStats.StageLeftDuration] = true
            end

            -- здесь будет переключение на первый этап игры
            if GameStats.StageLeftDuration <= 0 then -- начинаем игру
                for x=1,GameObj.Cols do
                    for y=1,GameObj.Rows do
                        FloorMatrix[x][y].EffectActivatedAt = nil
                        FloorMatrix[x][y].Color = colors.NONE
                        FloorMatrix[x][y].Bright = colors.BRIGHT0
                    end
                end
                GameStats.StageLeftDuration = GameConfigObj.StageDuration
                Stage = Stage + 1
                setGlobalColorBright(colors.NONE, colors.BRIGHT70)
                switchStage(Stage)
            end
        end
        -- так же логика будет проводится в этапе клика. Клик будет на кнопки,
        -- таких этапов будет 5, где к каждому нужно написать функцию движения пола
        -- будет ограничение по времени, думаю закинуть в конфиг
        -- наверное нужна будет переменная, которая отвечает есть ли горящие кнопки или нет,
        -- если нет, то рандомом определяем новые горящие кнопки и позиции под ними
        -- для этого нужна функция, учитывающая дефект кнопок
        -- движение пола нужно будет обсудить
        -- нужно учитыватб количество жизней

    elseif Stage == CONST_STAGE_GAME then -- этап игры
        -- часть логики производится в обработке клика
        -- происходит проверка длительности этапа и вызов эфекта заморозки
        processEffects()
        local timeSinceStageStart = time.unix() - StageStartTime
        local timer = time.unix() - StageStartTime2
        if 1 <= math.ceil(timeSinceStageStart)-1 then
            GameStats.StageLeftDuration = GameStats.StageLeftDuration - 0.5
            flag = false
        end
        if timer >= GameConfigObj.Complexity/10 then
            switchStage(Stage)
        elseif GameStats.StageLeftDuration <= 0 then
            Stage = CONST_STAGE_GAMEOVER
            GameStats.StageLeftDuration = GameConfigObj.WinDurationSec
            switchStage(Stage)
        end

        -- по идее нужен только swithcStage, который делает пол полностью зеленым навсегда
    elseif Stage == CONST_STAGE_WIN or Stage == CONST_STAGE_GAMEOVER then -- этап
        local timeSinceStageStart = time.unix() - StageStartTime
        flag = false
        if 1 <= timeSinceStageStart then
            GameStats.StageLeftDuration = GameStats.StageLeftDuration - 1
            switchStage(Stage)
            --flag = false
        end
        if GameStats.StageLeftDuration <= -1 then -- время завершать игру
            setGlobalColorBright(colors.NONE, colors.BRIGHT0)
            --switchStage(Stage)
            return GameResults
        end
        --return GameResults

    end


end



-- RangeFloor (служебный): метод для снятия снапшота пола
-- Вызывается в тот же игровой тик следом за методом NextTick()
--
-- Параметры:
--  setPixel = func(x int, y int, color int, bright int)
--  setButton = func(button int, color int, bright int)

--Что такое снапшот? По идее не используется
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

-- убрать freezed, сделать так, чт о если набрано необходимое количество очков,
-- идет переключение на след этап, если этап последний, то идет этап победы
-- если жизни кончились, то идет этап поражения, полы загораются красным навсегда
-- убрать подсчет очков, добавить убывание жизни при наступании куда не следует
function PixelClick(click)
    FloorMatrix[click.X][click.Y].Click = click.Click
    if Stage ~= CONST_STAGE_GAME then
        return -- игнорируем клики вне этапа игры
    end
    -- Если есть игрок с таким цветом, засчитываем очки
    if FloorMatrix[click.X][click.Y].Color == colors.RED then
        FloorMatrix[click.X][click.Y].EffectActivatedAt = {
            ActivatedAt = time.unix(),
            Durations = GameObj.Durations,
        }
        if FloorMatrix[click.X][click.Y].EffectActivatedAt ~= nil then
        end
        --processEffects()
        GameStats.CurrentLives = GameStats.CurrentLives - 1
        if GameStats.CurrentLives <= 0 then
            log.print("0 lives")
            GameStats.CurrentLives = 0
            Stage = CONST_STAGE_GAMEOVER
            GameStats.StageLeftDuration = GameConfigObj.WinDurationSec
            --switchStage(Stage)
        end
    else
        for positionIndex, startPosition in ipairs(GameObj.StartPositions) do
            for i=0, GameObj.StartPositionSize*GameObj.StartPositionSize-1 do
                local x = startPosition.X + i%GameObj.StartPositionSize
                local y = startPosition.Y + math.floor(i/GameObj.StartPositionSize)
                if click.X == x and click.Y == y then
                    startPosition.Clik = true
                else startPosition.Clik = false
                end
            end
        end
    end

    audio.PlayAsync(audio.CLICK)

    -- if click.Color == colors.RED , то
    -- в принципе все, здесь больше ничего не нужно
    return nil
end

-- ButtonClick (служебный): метод нажатия/отпускания кнопки
--
-- Параметры:
--  click = {
--      Button: int,
--      Click: bool,
--  }
-- усовершенствовать, чтобы не кликались дефектные, организовать сдесь счет очков
function ButtonClick(click)


    if Stage == CONST_STAGE_CHOOSE_COLOR then
        --return -- игнорируем клики вне этапа игры
        ButtonsList[click.Button].Click = click.Click
        if StartPlayersCount == 0 and click.Click then
            StartPlayersCount = countActivePlayers()
            StageStartTime = time.unix()
        end
    end
    -- если кнопка не дефектная
    if Stage == CONST_STAGE_GAME then
        ButtonsList[click.Button].Click = click.Click
        if ButtonsList[click.Button].Color == colors.BLUE and ButtonsList[click.Button].Bright == colors.BRIGHT70 then
            GameStats.Players[1].Score = GameStats.Players[1].Score + 1
            ButtonsList[click.Button].Color = colors.NONE
            ButtonsList[click.Button].Bright = colors.BRIGHT70
        end
        if GameStats.StageNum > GameStats.TotalStages --[[and GameStats.Players[1].Score == GameConfigObj.PointsToWin]] then
            Stage = Stage + 1
            GameStats.Players[1].Score = GameConfigObj.PointsToWin
            GameStats.StageLeftDuration = GameConfigObj.WinDurationSec
            switchStage(Stage)
        end
        if GameStats.Players[1].Score >= GameConfigObj.PointsToWin  then
            GameStats.StageNum = GameStats.StageNum + 1
            GameStats.Players[1].Score = 0
        end
    end
    -- если этап игры, то при нажатии на кнопку увеличиваются очки,
    -- каждые NumberOfButtons очков загораются новые кнопки и меняются безопасные зоны
    -- если достаточное количество очков, то меняем этап игры либо объявляем победу
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
    FloorMatrix[defect.X][defect.Y].Click = false
    FloorMatrix[defect.X][defect.Y].Defect = true

    if defect.Defect then
        FloorMatrix[defect.X][defect.Y].Click = false  --  переместим пиксель
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
-- возможно следует подправить
function DefectButton(defect)
    ButtonsList[defect.Button].Defect = defect.Defect
    -- потушим кнопку, если она дефектована и засветим, если дефектовку сняли
    if defect.Defect then
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT0
    else
        ButtonsList[defect.Button].Color = colors.NONE
        ButtonsList[defect.Button].Bright = colors.BRIGHT70
    end
end


-- processEffects: отвечает за эфект моргания во время этапа заморозки пола
-- остается тем же самым
function processEffects()
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            local pixel = FloorMatrix[x][y]
            if pixel.EffectActivatedAt ~= nil then
                log.print("bad_click")
                -- воспроизведем эффект
                local timeSinceEffectActivated = (time.unix() - pixel.EffectActivatedAt.ActivatedAt) * 1000
                if timeSinceEffectActivated > GameConfigObj.WrongEffectDuration then
                    pixel.EffectActivatedAt = nil
                    goto continue
                end

                while timeSinceEffectActivated > pixel.EffectActivatedAt.Durations.DurationOn+pixel.EffectActivatedAt.Durations.DurationOff do
                    timeSinceEffectActivated = timeSinceEffectActivated - (pixel.EffectActivatedAt.Durations.DurationOn + pixel.EffectActivatedAt.Durations.DurationOff)
                end
                if timeSinceEffectActivated < pixel.EffectActivatedAt.Durations.DurationOn then
                    pixel.Color = GameConfigObj.WrongColor
                else
                    pixel.Color = colors.NONE
                end
            end
            ::continue::
        end
    end
end

-- Установка глобального цвета
-- остается
function setGlobalColorBright(color, bright)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if not FloorMatrix[x][y].Defect then
                FloorMatrix[x][y].Color = color
                FloorMatrix[x][y].Bright = bright
            end
        end
    end

    for num, button in pairs(ButtonsList) do
        if not ButtonsList[num].Defect then
            ButtonsList[num].Color = color
            ButtonsList[num].Bright = bright
        end
    end
end

-- Сбросить звук обратного отсчета
function resetCountdown()
    for i = 1, #LeftAudioPlayed do
        LeftAudioPlayed[i] = false
    end
end




local act = 0;
local count = 0
local count1 = 0
-- Переключение этапа игры
-- очищение пола остается, но оно происходит только при смене этапа
-- freezing уходит
-- тут в принципе остается только зачистка пола,
-- либо можно сделать так, чтобы в NextTick не вызывать функции отвечающие за этап,
-- а вызывать их здесь, в некстите только проверять на количество очков и переключение этапов
function switchStage(newStage)
    --GameStats.StageNum = newStage
    if not flag then
        StageStartTime = time.unix()
        flag = true
    end
    StageStartTime2 = time.unix()
    GameStats.StageTotalDuration = GameConfigObj.StageDuration

    if newStage == CONST_STAGE_CHOOSE_COLOR then
        audio.StopBackground()
        return
    else
        audio.PlayRandomBackground()
    end
    local count = 0;
    for j=1, 19 do
        if ButtonsList[GameObj.Buttons[j]].Color == colors.BLUE and ButtonsList[GameObj.Buttons[j]].Bright == colors.BRIGHT70 then
            count = count + 1;
        end
    end
    -- очистим поле
    if count == 0 then
        for x=1,GameObj.Cols do
            for y=1,GameObj.Rows do
                FloorMatrix[x][y].EffectActivatedAt = nil
                FloorMatrix[x][y].Color = colors.NONE
                FloorMatrix[x][y].Bright = colors.BRIGHT0
            end
        end
    else
        for x=1,GameObj.Cols do
            for y=1,GameObj.Rows do
                if FloorMatrix[x][y].Color ~= colors.GREEN then
                    FloorMatrix[x][y].EffectActivatedAt = nil
                    FloorMatrix[x][y].Color = colors.NONE
                    FloorMatrix[x][y].Bright = colors.BRIGHT0
                end
            end
        end
    end

    if newStage == CONST_STAGE_GAME then
        local count = 0
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Color == colors.BLUE and ButtonsList[num].Bright == colors.BRIGHT70 then
                count = count + 1
            end
        end
        if GameStats.Players[1].Score >= GameConfigObj.PointsToWin and GameStats.StageNum == GameStats.TotalStages then
            count = 1
        end

        if count == 0  then
            RandomZone()
        end
        if GameStats.StageNum == 1 then
            if x <= 1 or x >= 24 then
                Move_right = Move_right * (-1)
            end
            MoveColumns(Move_right)
        end
        if GameStats.StageNum == 2 then
            if y <= 1 or y >= 15 then
                Move_up = Move_up * (-1)
            end
            MoveRows(Move_up)
        end
        if GameStats.StageNum == 3 then
            if GameStats.Players[1].Score == 0 and count == 0 then
                --log.print("chsnge")
                x = GameConfigObj.OriginCoordinateX
                y = GameConfigObj.OriginCoordinateY
                count = count + 1
            end
            if y <= 1 or y >= 15 then
                Move_up = Move_up * (-1)
            end
            if x <= 1 or x >= 24 then
                Move_right = Move_right * (-1)
            end
            MoveCross(Move_right, Move_up)
        end

        if GameStats.StageNum == 4 then
            if GameStats.Players[1].Score == 0 and count == 0 then
                x = GameConfigObj.OriginCoordinateX
                y = GameConfigObj.OriginCoordinateY
                count1 = count1 + 1
            end
            if x <= 1 and y >=15 or x >= 24 and y <= 1 then
                Move_main_diagonal = Move_main_diagonal * (-1)
            end
            MoveDiagonal(Move_main_diagonal)
        end

    end

    if newStage == CONST_STAGE_GAMEOVER then
        setGlobalColorBright(colors.RED, colors.BRIGHT70)
    end
    if newStage == CONST_STAGE_WIN then
        setGlobalColorBright(colors.GREEN, colors.BRIGHT70)
    end
    -- здесь просто сделать функции, которые отвечают за пол
    -- будет что-то наподобие...
    --[[if STAGE_FLOOR == 1 then
        if что-то с временем или очками then
            -- вызов функции которая двигает лаву по строкам
            -- вызов функции, которая двигает лаву по столбцам
        end
    else if STAGE_FLOOR = 2 then и так далее]]
    -- в каждом if проверять на оставшееся время, если оно кончилось, то объявляется поражение

end


-- не нужно, можно конечно доработать, и сделать так чтобы кнопки не назначались там,
-- где стоит игрок
--размещение пикселей
function placePixel(color)
    if color == colors.NONE then
        return
    end
    for randomAttempt=1,100 do
        local x = math.random(1, GameObj.Cols)
        local y = math.random(1, GameObj.Rows)
        if FloorMatrix[x][y].Color == colors.NONE and
                not FloorMatrix[x][y].Click and
                not FloorMatrix[x][y].Defect then -- не назначаем на дефектные пиксели
            FloorMatrix[x][y].Bright = GameConfigObj.Bright
            FloorMatrix[x][y].Color = color
            break
        end
    end
end

-- проверка позиции
-- спросить как работает
function checkPositionClick(startPosition, positionSize)
    for i=0, positionSize*positionSize-1 do
        local x = startPosition.X + i%positionSize
        local y = startPosition.Y + math.floor(i/positionSize)

        if x < 1 or x > GameObj.Cols or
                y < 1 or y > GameObj.Rows then
            goto continue -- ignore outside the game field
        end

        if FloorMatrix[x][y].Click then
            --NumberPlayer = NumberPlayer + 1
            log.print("+1")
            startPosition.Clik = true
            -- в гейм джесон изменить клик на тру
            return true
        end
        ::continue::
    end
    startPosition.Clik = false
    return false
end

-- Установить цвет стартовой позиции, хотя может сделать ее зеленой, ну или другого цвета
-- не нужна по идее



-- Расставить пиксели всех игроков
function placeAllPlayerPixels()
    for playerIdx, player in ipairs(GameStats.Players) do
        placePixel(player.Color)
    end
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

-- Посчитать количество активных игроков
function countActivePlayers()
    local activePlayers = 0
    for _, player in ipairs(GameObj.StartGame) do
        if player.Clik then
            activePlayers = activePlayers + 1
        end
    end
    return activePlayers
end




