--[[
    Название: Крестики-нолики
    Автор: https://t.me/bolokhontsevbis
    Описание: Классическая игра крестики-нолики до трех побед.
    Формат: дуэль 1v1, поле 15x15 (3x3 зоны по 5x5).
]]
math.randomseed(os.time())
require("avonlib")

local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CColors = require("colors")

local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3

local PLAYER_X = 1
local PLAYER_O = 2

local GRID_SIZE = 3
local ZONE_SIZE = 5
local FIELD_SIZE = GRID_SIZE * ZONE_SIZE -- 15

local tGame = { Cols = 24, Rows = 15, Buttons = {} }
local tConfig = {}
local tFloor = {}
local tButtons = {}
local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0

local tFloorStruct = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
}

local tButtonStruct = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
}

local tGameStats = {
    StageLeftDuration = 0,
    StageTotalDuration = 0,
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = {
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
}

-- Итог для движка. Мы не завершаем игру "навсегда", а перезапускаем матч.
-- Но структура нужна и остается совместимой с API движка.
local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = CColors.NONE,
}

local DEFAULT_CONFIG = {
    Bright = 5,
    RoundWinTarget = 3,
    TurnTimeSec = 8,
    RoundStartCountdown = 2,
    RoundEndDelayMs = 2200,
    RestartDelayMs = 3000,
    HoverMinWeight = 10,
}

-- Пиксельные маски 5x5:
-- X/O - для клеток поля
-- W/I/N - для финального экрана победы.
local SYMBOL_MASKS = {
    X5 = {
        {0, 0, 0, 0, 0},
        {0, 1, 0, 1, 0},
        {0, 0, 1, 0, 0},
        {0, 1, 0, 1, 0},
        {0, 0, 0, 0, 0},
    },
    O5 = {
        {0, 0, 0, 0, 0},
        {0, 1, 1, 1, 0},
        {0, 1, 0, 1, 0},
        {0, 1, 1, 1, 0},
        {0, 0, 0, 0, 0},
    },
    W5 = {
        {1, 0, 0, 0, 1},
        {1, 0, 0, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 1, 0, 1, 1},
        {1, 0, 0, 0, 1},
    },
    I5 = {
        {1, 1, 1, 1, 1},
        {0, 0, 1, 0, 0},
        {0, 0, 1, 0, 0},
        {0, 0, 1, 0, 0},
        {1, 1, 1, 1, 1},
    },
    N5 = {
        {1, 0, 0, 0, 1},
        {1, 1, 0, 0, 1},
        {1, 0, 1, 0, 1},
        {1, 0, 0, 1, 1},
        {1, 0, 0, 0, 1},
    },
}

-- Живое состояние матча/раунда.
local tData = {
    board = {},
    currentPlayer = PLAYER_X,
    startingPlayer = PLAYER_O,
    movesCount = 0,
    roundActive = false,
    roundEndLeftMs = 0,
    winningLine = nil,
    winningPlayer = 0,
    turnElapsedMs = 0,
    turnLeftSec = 0,
    setupCountdownLeft = 0,
    setupElapsedMs = 0,
    hoverCell = nil,
    matchWinner = 0,
    matchRestartLeftMs = 0,
    field = {
        startX = 5,
        startY = 1,
        endX = 19,
        endY = 15,
    },
    playerColors = {
        [PLAYER_X] = CColors.GREEN,
        [PLAYER_O] = CColors.MAGENTA,
    },
}

-- Ограничение значения диапазоном [minValue, maxValue].
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

-- Применяет дефолты только к отсутствующим полям config.json.
local function applyConfigDefaults()
    for key, value in pairs(DEFAULT_CONFIG) do
        if tConfig[key] == nil then
            tConfig[key] = value
        end
    end
end

-- Пустое поле 3x3 (0 = пусто, 1 = X, 2 = O).
local function newBoard()
    return {
        { 0, 0, 0 },
        { 0, 0, 0 },
        { 0, 0, 0 },
    }
end

-- Заливает всю арену и все кнопки одним цветом/яркостью.
-- Используется как "очистка кадра" перед отрисовкой текущего состояния.
local function setGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
    for iBtn, _ in pairs(tButtons) do
        tButtons[iBtn].iColor = iColor
        tButtons[iBtn].iBright = iBright
    end
end

-- Безопасная установка одного пикселя (с проверкой границ арены).
local function paintPixel(iX, iY, iColor, iBright)
    if iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows then
        return
    end
    tFloor[iX][iY].iColor = iColor
    tFloor[iX][iY].iBright = iBright
end

-- Заливка прямоугольника.
local function fillRect(x1, y1, x2, y2, iColor, iBright)
    for x = x1, x2 do
        for y = y1, y2 do
            paintPixel(x, y, iColor, iBright)
        end
    end
end

-- Рисует только рамку прямоугольника толщиной 1 пиксель.
local function paintRectBorder(rect, iColor, iBright)
    for x = rect.x1, rect.x2 do
        paintPixel(x, rect.y1, iColor, iBright)
        paintPixel(x, rect.y2, iColor, iBright)
    end
    for y = rect.y1, rect.y2 do
        paintPixel(rect.x1, y, iColor, iBright)
        paintPixel(rect.x2, y, iColor, iBright)
    end
end

-- Геометрия игрового квадрата 15x15:
-- - всегда квадрат
-- - центрирован по X в арене 24x15.
local function buildFieldGeometry()
    local startX = math.floor((tGame.Cols - FIELD_SIZE) / 2) + 1
    local startY = 1

    startX = clamp(startX, 1, math.max(1, tGame.Cols - FIELD_SIZE + 1))
    startY = clamp(startY, 1, math.max(1, tGame.Rows - FIELD_SIZE + 1))

    tData.field.startX = startX
    tData.field.startY = startY
    tData.field.endX = startX + FIELD_SIZE - 1
    tData.field.endY = startY + FIELD_SIZE - 1
end

-- Возвращает прямоугольник клетки (зоны) 5x5 по координатам row/col (1..3).
local function getZoneRect(row, col)
    local x1 = tData.field.startX + (col - 1) * ZONE_SIZE
    local y1 = tData.field.startY + (row - 1) * ZONE_SIZE
    return {
        x1 = x1,
        y1 = y1,
        x2 = x1 + ZONE_SIZE - 1,
        y2 = y1 + ZONE_SIZE - 1,
    }
end

-- Внешняя рамка игрового квадрата 15x15.
local function getOuterFrame()
    return {
        x1 = tData.field.startX,
        y1 = tData.field.startY,
        x2 = tData.field.endX,
        y2 = tData.field.endY,
    }
end

-- Преобразует координату пикселя арены в индекс клетки 3x3.
-- Если пиксель вне поля, возвращает nil, nil.
local function pointToCell(x, y)
    if x < tData.field.startX or x > tData.field.endX or y < tData.field.startY or y > tData.field.endY then
        return nil, nil
    end

    local col = math.floor((x - tData.field.startX) / ZONE_SIZE) + 1
    local row = math.floor((y - tData.field.startY) / ZONE_SIZE) + 1
    if row < 1 or row > 3 or col < 1 or col > 3 then
        return nil, nil
    end
    return row, col
end

-- Рисует маску 5x5 внутри клетки 5x5.
local function drawMaskInZone(row, col, mask, iColor, iBright)
    local zone = getZoneRect(row, col)
    for y = 1, 5 do
        for x = 1, 5 do
            if mask[y][x] == 1 then
                paintPixel(zone.x1 + x - 1, zone.y1 + y - 1, iColor, iBright)
            end
        end
    end
end

-- Рисует маску 5x5 в произвольной точке арены.
-- Нужна для надписи WIN на полном экране победы.
local function drawMaskAt(startX, startY, mask, iColor, iBright)
    for y = 1, 5 do
        for x = 1, 5 do
            if mask[y][x] == 1 then
                paintPixel(startX + x - 1, startY + y - 1, iColor, iBright)
            end
        end
    end
end

-- Полноэкранный экран победы:
-- - вся арена цветом победителя
-- - надпись WIN по центру
-- - рамка по краю арены.
local function drawWinScreen(baseBright)
    local winColor = tData.playerColors[tData.matchWinner]
    local textBright = clamp(baseBright + 1, 1, CColors.BRIGHT100)
    local gap = 1
    local wordWidth = 5 + gap + 5 + gap + 5
    local wordStartX = math.floor((tGame.Cols - wordWidth) / 2) + 1
    local wordStartY = math.floor((tGame.Rows - 5) / 2) + 1

    -- Экран победы покрывает всю арену (24x15).
    fillRect(1, 1, tGame.Cols, tGame.Rows, winColor, baseBright)
    drawMaskAt(wordStartX, wordStartY, SYMBOL_MASKS.W5, CColors.WHITE, textBright)
    drawMaskAt(wordStartX + 5 + gap, wordStartY, SYMBOL_MASKS.I5, CColors.WHITE, textBright)
    drawMaskAt(wordStartX + 10 + gap * 2, wordStartY, SYMBOL_MASKS.N5, CColors.WHITE, textBright)
    paintRectBorder({ x1 = 1, y1 = 1, x2 = tGame.Cols, y2 = tGame.Rows }, winColor, textBright)
end

-- Переключение хода: активный игрок + таймер хода.
local function setTurn(playerId)
    tData.currentPlayer = playerId
    tData.turnElapsedMs = 0
    tData.turnLeftSec = tConfig.TurnTimeSec
    tGameStats.StageLeftDuration = tData.turnLeftSec
end

-- Проверка победы по всем 8 линиям.
-- Возвращает: winnerPlayerId (0/1/2), winningLine (или nil).
local function checkWinner()
    local lines = {
        { { row = 1, col = 1 }, { row = 1, col = 2 }, { row = 1, col = 3 } },
        { { row = 2, col = 1 }, { row = 2, col = 2 }, { row = 2, col = 3 } },
        { { row = 3, col = 1 }, { row = 3, col = 2 }, { row = 3, col = 3 } },
        { { row = 1, col = 1 }, { row = 2, col = 1 }, { row = 3, col = 1 } },
        { { row = 1, col = 2 }, { row = 2, col = 2 }, { row = 3, col = 2 } },
        { { row = 1, col = 3 }, { row = 2, col = 3 }, { row = 3, col = 3 } },
        { { row = 1, col = 1 }, { row = 2, col = 2 }, { row = 3, col = 3 } },
        { { row = 1, col = 3 }, { row = 2, col = 2 }, { row = 3, col = 1 } },
    }

    for _, line in pairs(lines) do
        local a = tData.board[line[1].row][line[1].col]
        local b = tData.board[line[2].row][line[2].col]
        local c = tData.board[line[3].row][line[3].col]
        if a ~= 0 and a == b and b == c then
            return a, line
        end
    end
    return 0, nil
end

-- Старт нового раунда внутри матча (счет матча не сбрасывается).
local function startRound()
    tData.board = newBoard()
    tData.movesCount = 0
    tData.winningLine = nil
    tData.winningPlayer = 0
    tData.hoverCell = nil
    tData.roundEndLeftMs = 0
    tData.roundActive = true
    tData.startingPlayer = tData.startingPlayer == PLAYER_X and PLAYER_O or PLAYER_X
    setTurn(tData.startingPlayer)
end

-- Финал матча: запоминаем победителя и переходим на экран POSTGAME.
local function finishMatch(winnerPlayer)
    tData.roundActive = false
    tData.roundEndLeftMs = 0
    tGameResults.Won = winnerPlayer ~= 0
    tGameResults.PlayersCount = 2
    tGameResults.Score = math.max(tGameStats.Players[1].Score, tGameStats.Players[2].Score)
    tGameResults.Color = winnerPlayer ~= 0 and tData.playerColors[winnerPlayer] or CColors.NONE
    tData.matchWinner = winnerPlayer
    tData.matchRestartLeftMs = tConfig.RestartDelayMs
    iGameState = GAMESTATE_POSTGAME
end

-- Раунд завершен (победа или ничья):
-- - фиксируем линию победы
-- - ставим задержку перед следующим раундом/финалом матча
-- - обновляем счет матча при победе.
local function completeRound(winnerPlayer, winningLine)
    tData.roundActive = false
    tData.winningLine = winningLine
    tData.winningPlayer = winnerPlayer
    tData.roundEndLeftMs = tConfig.RoundEndDelayMs
    tData.hoverCell = nil
    if winnerPlayer ~= 0 then
        tGameStats.Players[winnerPlayer].Score = tGameStats.Players[winnerPlayer].Score + 1
    end
end

-- Вызывается после задержки RoundEndDelayMs:
-- - либо завершает матч (если достигли цели)
-- - либо запускает следующий раунд.
local function finishDelayedRound()
    local target = tConfig.RoundWinTarget
    local scoreX = tGameStats.Players[PLAYER_X].Score
    local scoreO = tGameStats.Players[PLAYER_O].Score

    if scoreX >= target then
        finishMatch(PLAYER_X)
        return
    end
    if scoreO >= target then
        finishMatch(PLAYER_O)
        return
    end

    if tGameStats.StageNum >= tGameStats.TotalStages then
        if scoreX > scoreO then
            finishMatch(PLAYER_X)
        elseif scoreO > scoreX then
            finishMatch(PLAYER_O)
        else
            finishMatch(0)
        end
        return
    end

    tGameStats.StageNum = tGameStats.StageNum + 1
    startRound()
end

-- Основной рендер игрового состояния (не финальный полноэкранный экран):
-- 1) фон квадрата 15x15
-- 2) hover подсветка клетки
-- 3) подсветка победной линии раунда
-- 4) символы X/O
-- 5) пульсирующая рамка текущего игрока.
local function drawBoard()
    local baseBright = clamp(tConfig.Bright, 1, CColors.BRIGHT100)
    local dimBright = math.max(1, baseBright - 4)
    local hoverBright = math.max(1, baseBright - 2)
    local accentBright = clamp(baseBright + 1, 1, CColors.BRIGHT100)

    setGlobalColorBright(CColors.NONE, baseBright)

    -- Фон поля 15x15. Сетка не рисуется отдельными линиями.
    local frame = getOuterFrame()
    fillRect(frame.x1, frame.y1, frame.x2, frame.y2, CColors.BLUE, dimBright)

    -- Hover-подсветка активной зоны 5x5.
    if tData.hoverCell then
        local hover = getZoneRect(tData.hoverCell.row, tData.hoverCell.col)
        fillRect(hover.x1, hover.y1, hover.x2, hover.y2, CColors.WHITE, hoverBright)
    end

    -- Победная линия: подсветка трех клеток цветом победителя.
    if tData.winningLine and tData.winningPlayer ~= 0 then
        local winColor = tData.playerColors[tData.winningPlayer]
        for _, cell in pairs(tData.winningLine) do
            local zone = getZoneRect(cell.row, cell.col)
            fillRect(zone.x1, zone.y1, zone.x2, zone.y2, winColor, accentBright)
        end
    end

    -- Символы X/O строго по 5x5 маскам.
    for row = 1, GRID_SIZE do
        for col = 1, GRID_SIZE do
            local mark = tData.board[row][col]
            if mark == PLAYER_X then
                drawMaskInZone(row, col, SYMBOL_MASKS.X5, tData.playerColors[PLAYER_X], baseBright)
            elseif mark == PLAYER_O then
                drawMaskInZone(row, col, SYMBOL_MASKS.O5, tData.playerColors[PLAYER_O], baseBright)
            end
        end
    end

    -- Рамка всего поля цветом текущего игрока с пульсом ~раз в 0.5с.
    local pulse = math.floor(CTime.unix() * 2) % 2
    local playerColor = tData.playerColors[tData.currentPlayer] or CColors.WHITE
    local frameBright = clamp(baseBright + pulse, 1, CColors.BRIGHT100)
    paintRectBorder(frame, playerColor, frameBright)
end

-- Полный перезапуск матча:
-- - сброс счета и состояния
-- - переход либо в setup countdown, либо сразу в GAME.
local function resetMatch()
    tGameStats.StageNum = 1
    tGameStats.Players[PLAYER_X].Score = 0
    tGameStats.Players[PLAYER_O].Score = 0
    tData.board = newBoard()
    tData.movesCount = 0
    tData.roundActive = false
    tData.roundEndLeftMs = 0
    tData.winningLine = nil
    tData.winningPlayer = 0
    tData.hoverCell = nil
    tData.matchWinner = 0
    tData.matchRestartLeftMs = 0
    tGameResults.AfterDelay = false

    if tConfig.RoundStartCountdown > 0 then
        tData.setupCountdownLeft = tConfig.RoundStartCountdown
        tData.setupElapsedMs = 0
        tGameStats.StageLeftDuration = tConfig.RoundStartCountdown
        iGameState = GAMESTATE_SETUP
    else
        iGameState = GAMESTATE_GAME
        startRound()
    end
end

-- Тик режима SETUP (обратный отсчет перед стартом матча/раунда).
local function gameSetupTick(deltaMs)
    drawBoard()

    tData.setupElapsedMs = tData.setupElapsedMs + deltaMs
    while tData.setupElapsedMs >= 1000 do
        tData.setupElapsedMs = tData.setupElapsedMs - 1000
        tData.setupCountdownLeft = tData.setupCountdownLeft - 1
        tGameStats.StageLeftDuration = tData.setupCountdownLeft
    end

    if tData.setupCountdownLeft <= 0 then
        iGameState = GAMESTATE_GAME
        startRound()
    end
end

-- Тик основного игрового режима:
-- - рендер
-- - ожидание конца раунда
-- - обработка таймера хода.
local function gameTick(deltaMs)
    drawBoard()

    if tData.roundEndLeftMs > 0 then
        tData.roundEndLeftMs = tData.roundEndLeftMs - deltaMs
        if tData.roundEndLeftMs <= 0 then
            finishDelayedRound()
        end
        return
    end

    if not tData.roundActive then
        return
    end

    if tConfig.TurnTimeSec <= 0 then
        return
    end

    tData.turnElapsedMs = tData.turnElapsedMs + deltaMs
    while tData.turnElapsedMs >= 1000 do
        tData.turnElapsedMs = tData.turnElapsedMs - 1000
        tData.turnLeftSec = tData.turnLeftSec - 1
        tGameStats.StageLeftDuration = tData.turnLeftSec

        if tData.turnLeftSec <= 0 then
            local nextPlayer = tData.currentPlayer == PLAYER_X and PLAYER_O or PLAYER_X
            setTurn(nextPlayer)
            break
        end
    end
end

-- Обязательный метод движка: инициализация игры.
function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)
    applyConfigDefaults()

    tFloor = {}
    for x = 1, tGame.Cols do
        tFloor[x] = {}
        for y = 1, tGame.Rows do
            tFloor[x][y] = CHelp.ShallowCopy(tFloorStruct)
        end
    end

    tButtons = {}
    for _, btn in pairs(tGame.Buttons or {}) do
        tButtons[btn] = CHelp.ShallowCopy(tButtonStruct)
    end

    buildFieldGeometry()

    tGameStats.ScoreboardVariant = 6
    tGameStats.TargetScore = tConfig.RoundWinTarget
    tGameStats.StageNum = 1
    tGameStats.TotalStages = tConfig.RoundWinTarget * 2 - 1
    tGameStats.StageLeftDuration = tConfig.RoundStartCountdown
    tGameStats.Players[PLAYER_X].Score = 0
    tGameStats.Players[PLAYER_O].Score = 0
    tGameStats.Players[PLAYER_X].Color = tData.playerColors[PLAYER_X]
    tGameStats.Players[PLAYER_O].Color = tData.playerColors[PLAYER_O]
    resetMatch()

    iPrevTickTime = CTime.unix()
end

-- Обязательный метод движка: кадр/тик логики.
function NextTick()
    local now = CTime.unix()
    local deltaMs = (now - iPrevTickTime) * 1000

    if iGameState == GAMESTATE_SETUP then
        gameSetupTick(deltaMs)
    elseif iGameState == GAMESTATE_GAME then
        gameTick(deltaMs)
    elseif iGameState == GAMESTATE_POSTGAME then
        drawWinScreen(clamp(tConfig.Bright, 1, CColors.BRIGHT100))
        tData.matchRestartLeftMs = tData.matchRestartLeftMs - deltaMs
        if tData.matchRestartLeftMs <= 0 then
            resetMatch()
        end
    end

    AL.CountTimers(deltaMs)
    iPrevTickTime = now
    return nil
end

-- Обязательный метод движка: отдать текущий снимок пола/кнопок.
function RangeFloor(setPixel, setButton)
    for x = 1, tGame.Cols do
        for y = 1, tGame.Rows do
            setPixel(x, y, tFloor[x][y].iColor, tFloor[x][y].iBright)
        end
    end
    for iBtn, tBtn in pairs(tButtons) do
        setButton(iBtn, tBtn.iColor, tBtn.iBright)
    end
end

-- Обязательный метод движка: статистика для табло.
function GetStats()
    return tGameStats
end

-- Обязательный метод движка: пауза.
function PauseGame()
    bGamePaused = true
end

-- Обязательный метод движка: снятие паузы.
function ResumeGame()
    bGamePaused = false
    iPrevTickTime = CTime.unix()
    tData.turnElapsedMs = 0
    tData.setupElapsedMs = 0
end

-- Обязательный метод движка: форс-переход этапа.
function SwitchStage()
    if iGameState == GAMESTATE_SETUP then
        iGameState = GAMESTATE_GAME
        startRound()
        return
    end
    if iGameState == GAMESTATE_GAME then
        completeRound(0, nil)
    end
end

-- Обязательный метод движка: нажатие на пиксель.
-- Здесь:
-- - обновляем hover
-- - валидируем возможность хода
-- - ставим X/O
-- - проверяем победу/ничью
-- - переключаем ход.
function PixelClick(click)
    if bGamePaused then
        return
    end
    if not (tFloor[click.X] and tFloor[click.X][click.Y]) then
        return
    end

    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    local row, col = pointToCell(click.X, click.Y)
    if click.Click and row and col then
        tData.hoverCell = { row = row, col = col }
    elseif not click.Click and tData.hoverCell and row and col then
        if tData.hoverCell.row == row and tData.hoverCell.col == col then
            tData.hoverCell = nil
        end
    end

    if iGameState ~= GAMESTATE_GAME or not click.Click then
        return
    end
    if click.Weight <= tConfig.HoverMinWeight then
        return
    end
    if not tData.roundActive or tData.roundEndLeftMs > 0 then
        return
    end
    if not row or not col then
        return
    end
    if tData.board[row][col] ~= 0 then
        return
    end

    tData.board[row][col] = tData.currentPlayer
    tData.movesCount = tData.movesCount + 1
    tData.hoverCell = nil

    local winner, line = checkWinner()
    if winner ~= 0 then
        completeRound(winner, line)
        return
    end
    if tData.movesCount >= 9 then
        completeRound(0, nil)
        return
    end

    local nextPlayer = tData.currentPlayer == PLAYER_X and PLAYER_O or PLAYER_X
    setTurn(nextPlayer)
end

-- Обязательный метод движка: нажатие кнопки.
function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then
        return
    end
    tButtons[click.Button].bClick = click.Click
end

-- Обязательный метод движка: дефект пикселя.
function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

-- Обязательный метод движка: дефект кнопки.
function DefectButton(defect)
    if tButtons[defect.Button] == nil then
        return
    end
    tButtons[defect.Button].bDefect = defect.Defect
    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end
end
