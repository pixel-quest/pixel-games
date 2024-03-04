-- Название: Пиксель дуэль
-- Автор: @AnatoliyB (телеграм)
-- Описание механики: соревновательная механика, кто быстрее соберет необходимое количество очков, наступая на пиксели своего цвета
--      пиксели могут перемещаться после нажатия, могут не воявляться до обновления пола(настраиваемо).
--      После окончания этапа пол становится "заморожен", за исключением пикселей на которых стоит игрок. Наступать на другие пиксели нельзя
--      Внимание: Для старта игры требуется "встать" минимум на два цвета и нажать любую кнопку на стене!
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
local GameObj = {
    Cols = 24, -- пикселей по горизонтали (X), обязательные параметр для всех игр
    Rows = 15, -- пикселей по вертикали (Y), обязательные параметр для всех игр
    Buttons = {2, 6, 10, 14, 18, 22, 26, 30, 34, 42, 46, 50, 54, 58, 62, 65, 69, 73, 77}, -- номера кнопок в комнате
    StartPositionSize = 2, -- размер стартовой зоны для игрока, для маленькой выездной платформы удобно ставить тут 1
    StartPositions = { -- координаты расположения стартовых зон должны быть возле стены, т.к для старта надо нажать кнопку на стене
        { X = 2, Y = 2, Color = colors.RED },
        { X = 6, Y = 2, Color = colors.YELLOW },
        { X = 10, Y = 2, Color = colors.GREEN },
        { X = 14, Y = 2, Color = colors.CYAN },
        { X = 18, Y = 2, Color = colors.BLUE },
        { X = 22, Y = 2, Color = colors.MAGENTA },
    },
}

-- Насторойки, которые может подкручивать админ при запуске игры
-- Объект конфига игры, см. файл config.json
local GameConfigObj = {
	Bright = colors.Bright70, -- не рекомендуется играть на полной яркости, обычно хватает 70%
	PointsToWin = 10, -- очки, необходимые для победы
	FillingPercentage = 10, -- процент заполнения пола цветными пикселями
	MovePixels = false, -- переменная, отвечающая за движение пикселя после нажатия
	StartDuration = 8, -- продолжительность старта
	StageDuration = 10, -- продолжительность этапа
	WinDurationSec = 10, -- продолжительность этапа победы перед завершением игры
	StopDurationSec = 3, -- продолжительность "заморозки"
	WrongEffectDuration = 1, -- длятельность моргания
	StopColor = colors.RED, -- цвет пола, во время эфекта "заморозки"
	WrongColor = colors.MAGENTA, -- цвет моргания пикселя, при нажатии на замороженный пиксель
}


-- Структура статистики игры (служебная): используется для отображения информации на табло
-- Переодически запрашивается через метод GetStats()
local GameStats = {
    StageLeftDuration = 3, -- seconds
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
    Click = false, -- переменная означающая, можно ли совершить клик по пикселю
    Defect = false, -- дефектный пиксель
    effect = {
        activatedAt = 0.5,
        durations = {
            durationOff = 500,
            durationOn = 500,
        },
    },
} 


local freezed = false -- переменная, отвечающая за этап заморозки
local CONST_STAGE_CHOOSE_COLOR = 0 -- выбор цвета
local CONST_STAGE_GAME = 1 -- игра
local CONST_STAGE_WIN = 3 -- победа
local Stage = CONST_STAGE_CHOOSE_COLOR -- текущий этап
local StageStartTime = 0 -- время начала текущего этапа

local LeftAudioPlayed = { -- 5... 4... 3... 2... 1... Победа
    [5] = false,
    [4] = false,
    [3] = false,
    [2] = false,
    [1] = false,
}

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
            FloorMatrix[x][y] = help.DeepCopy(Pixel) -- заполняем нулевыми пикселями
        end
    end

    

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.DeepCopy(Pixel) -- тип аналогичен пикселю
        -- и подсветим все кнопки по-умлочанию, чтобы потребовать нажатия для старта
        ButtonsList[num].Color = colors.BLUE
        ButtonsList[num].Bright = colors.BRIGHT70
    end

    GameStats.TargetScore = GameConfigObj.PointsToWin

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

-- processEffects: отвечает за эфект моргания во время этапа заморозки пола
function processEffects() 
	for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
			local pixel = FloorMatrix[x][y]
			if pixel.effect ~= nil then
				-- воспроизведем эффект
                local timeSinceEffectActivated = (time.unix() - pixel.effect.activatedAt) * 1000
				if timeSinceEffectActivated > GameConfigObj.WrongEffectDuration then
					pixel.effect = nil
					goto continue
				end

				while timeSinceEffectActivated > pixel.effect.durations.durationOn+pixel.effect.durations.durationOff do
                    timeSinceEffectActivated = timeSinceEffectActivated - (pixel.effect.durations.durationOn + pixel.effect.durations.durationOff)
                end
				if timeSinceEffectActivated < pixel.effect.durations.durationOn then
					pixel.Color = GameConfigObj.WrongColor
				else 
					pixel.Color = colors.NONE
				end
			end
            ::continue::
		end
	end
end

-- NextTick (служебный): метод игрового тика
-- Вызывается ПРИМЕРНО каждые ~35мс (28 кадров в секунду)
-- Ориентировать на время периода нельзя, вместо этого нужно использовать абсолютное время time.unix()
-- Не вызывается, когда игра на паузе или завершена
-- Чтобы нивелировать паузу, нужно запоминать время паузы и делать сдвиг
function NextTick()
    if Stage == CONST_STAGE_CHOOSE_COLOR then -- этап выбора цвета
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
                or currentPlayersCount < 2 then -- если менее двух игроков
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
                Stage = Stage + 1
                switchStage(Stage)
            end
        end
    elseif Stage == CONST_STAGE_GAME then -- этап игры
    -- часть логики производится в обработке клика
    -- происходит проверка длительности этапа и вызов эфекта заморозки 
        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageLeftDuration = GameConfigObj.StageDuration - timeSinceStageStart + 1
        if timeSinceStageStart > GameConfigObj.StageDuration+GameConfigObj.StopDurationSec then
            switchStage(Stage+1)
            freezed = false
        elseif timeSinceStageStart > GameConfigObj.StageDuration then
            stageFreeze()
            freezed = true
            GameStats.StageLeftDuration = 0
            processEffects()
            
        elseif timeSinceStageStart > GameConfigObj.StageDuration-2.5 then
            if not freezed then
                audio.PlaySync(audio.ONE_TWO_FREE_FREEZE)
                freezed = true
            end
        end
    elseif Stage == CONST_STAGE_WIN then -- этап 
        local timeSinceStageStart = time.unix() - StageStartTime
        GameStats.StageTotalDuration = GameConfigObj.WinDurationSec
        GameStats.StageLeftDuration = GameStats.StageTotalDuration - timeSinceStageStart

        if GameStats.StageLeftDuration <= 0 then -- время завершать игру
            switchStage(Stage+1)
        end
        return GameResults
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

-- переменная, отвечающая за начало и конец моргания processEffects
local wrongAreaEffect = {
	durationOn =  200,
	durationOff = 120,
}

local flag = true

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
    if not flag then
        Stage = CONST_STAGE_WIN
    end
    FloorMatrix[click.X][click.Y].Click = click.Click
    if Stage ~= CONST_STAGE_GAME then
        return -- игнорируем клики вне этапа игры
    end
    -- Если есть игрок с таким цветом, засчитываем очки
    local pixel = help.DeepCopy(FloorMatrix[click.X][click.Y])
    if flag and not freezed then
        FloorMatrix[click.X][click.Y].Color = colors.NONE
    end
    local clickedColor = help.DeepCopy(pixel.Color)
    
    local player = getPlayerByColor(clickedColor)
    if player == nil and not freezed then
        return
    end
    
    audio.PlayAsync(audio.CLICK)
    if not freezed and flag then 
        player.Score = player.Score + 1
    end
    
    
    
    if click.Click and pixel.effect == nil and clickedColor > colors.NONE then
        if freezed == false then
            local playerIdx = playerIdxByColor(clickedColor)
            if playerIdx >= 0 then
				audio.PlayAsync(audio.CLICK)
                -- игрок набрал нужное количесто очков для победы
                if GameStats.Players[playerIdx].Score >= GameConfigObj.PointsToWin then
					audio.PlaySync(audio.VICTORY)
                    switchStage(CONST_STAGE_WIN)
					setGlobalColorBright(clickedColor, GameConfigObj.Bright)
                    flag = false
					return
				end
            end
        elseif clickedColor == GameConfigObj.StopColor then
            audio.PlayAsync(audio.MISCLICK)
            if freezed then
                FloorMatrix[click.X][click.Y].effect = {
					activatedAt = time.unix(),
					durations = help.ShallowCopy(wrongAreaEffect),
				}
            end
        end
        -- и переместим пиксель в другое пустое место
        if GameConfigObj.MovePixels then
			for randomAttempt = 0, 50 do
				local x = math.random(1, GameObj.Cols)
                local y = math.random(1, GameObj.Rows)
				if FloorMatrix[x][y].Color == colors.NONE and not FloorMatrix[x][y].Defect then
					FloorMatrix[x][y].Color = clickedColor
					FloorMatrix[x][y].Bright = GameConfigObj.Bright
					break
				end
			end
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
    if Stage ~= CONST_STAGE_CHOOSE_COLOR then
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
function DefectButton(defect)
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

-- Установка глобального цвета
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
	GameStats.StageTotalDuration = GameConfigObj.StageDuration
    freezing = false

	if newStage == CONST_STAGE_CHOOSE_COLOR or newStage == CONST_STAGE_WIN then
		audio.StopBackground()
		return
	else 
		audio.PlayRandomBackground()
	end

	-- очистим поле
	for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            FloorMatrix[x][y].effect = nil
			FloorMatrix[x][y].Color = colors.NONE
			FloorMatrix[x][y].Bright = colors.BRIGHT0
		end
	end
	-- заполнить все цветными на рандомных местах, пока не достигнем нужного процента
	local color = colors.RED -- будем поочередно расставлять цвета
	for filled = 1,GameObj.Cols*GameObj.Rows*GameConfigObj.FillingPercentage/100 do 
		color = color + 1
		if color == colors.NONE or color >= colors.WHITE then
			color = colors.RED
		end
		for randomAttempt = 1, math.ceil(GameObj.Cols*GameObj.Rows*GameConfigObj.FillingPercentage/(100*6)) do 
            local x  = math.random(1, GameObj.Cols)
            local y  = math.random(1, GameObj.Rows)
            if FloorMatrix[x][y].Color == colors.NONE and
                not FloorMatrix[x][y].Click and -- под ноги не размещаем
                not FloorMatrix[x][y].Defect then -- не назначаем на дефектные пиксели
                FloorMatrix[x][y].Bright = GameConfigObj.Bright
                FloorMatrix[x][y].Color = color
                break
             end
            
		end
	end

	-- пропустим занятые старт позиции
	if newStage == CONST_STAGE_GAME then
		for _, startPosition in ipairs(GameObj.StartPositions) do
			if checkPositionClick(startPosition, GameObj.StartPositionSize) then
				setColorBrightForStartPosition(startPosition, GameObj.StartPositionSize, colors.NONE, colors.BRIGHT0)
			end
		end
	end
end

-- Расставить пиксели всех игроков
function placeAllPlayerPixels()
    for playerIdx, player in ipairs(GameStats.Players) do
        placePixel(player.Color)
    end
end



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

-- заморозить пол
function stageFreeze() 
	for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            if not FloorMatrix[x][y].Defect then
                FloorMatrix[x][y].Bright = GameConfigObj.Bright
                if FloorMatrix[x][y].Click then
                    FloorMatrix[x][y].Color = colors.GREEN
                else 
                    FloorMatrix[x][y].Color = GameConfigObj.StopColor
                end
            end
		end
	end
end

-- проверка цвета игрока
function playerIdxByColor(color) 
	if color == colors.NONE then
		return -1
	end
	for playerIdx, player in pairs(GameStats.Players) do
		if player.Color == color then
			return playerIdx
		end
	end
	return -1
end
