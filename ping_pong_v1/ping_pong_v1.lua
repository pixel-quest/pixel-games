-- Название: Пинг-понг
-- Автор: Avondale, discord: avonda

-- Описание механики: классичейский пинг-понг на двоих, отбиваем мяч платформой.
--    Для старта нужно обоим игрокам встать на свой цвет.
--    После каждого отбития мяча игра ускоряется.
--
-- Идеи по доработке:
--    1. несколько мячей
--    2. сложнее физика

-- Для каждой игры случайный сид, ставится один раз
math.randomseed(os.time())

local CLog = require("log")
local CInspect = require("inspect")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 0,
    Rows = 0,
    Buttons = {},
    StartPositionSize = 0,
    StartPositions = { {},{}, },
}

-- Настройки
local tConfig = {
    Bright = 5, -- яркость всех пикселей
    PodSize = 2, -- размер платформы (центр + 2 по краям = 5 пикселей)
    PointsToWinRound = 5, -- очков для победы
    WinDurationSec = 10, -- длительность этапа победы
    -- настройки задержки мяча, чем меньше задержка тем быстрее мяч двигается:
    InitialBallDelayMS = 250, -- начальный период движения мяча
    BallDelayHitDecreaseMS = 10, -- уменьшение задержки после каждого удара игрока по мячу
    MinBallDelayMS = 50, -- минимальная задержка, ниже этой опустится не может
}

-- Стейты или этапы игры
local GAMESTATE_SETUP = 1 -- стейт ожидания игроков, заканчивается когда оба игрока на своих местаъ
local GAMESTATE_GAME = 2 -- стейт игры, заканчивается когда один из игроков выигрывает 2 раунда игры
local GAMESTATE_POSTGAME = 3 -- стейт после игры, красит всё поле в цвет победителя
local GAMESTATE_FINISH = 4 -- стейт завершения игры

-- Куда попал мяч
local HIT_CENTER = 1
local HIT_CORNER = 2

local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0

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
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
}

local tFloor = {}
local tButtons = {}

local tFloorStruct = {
    iColor = CColors.NONE,
    iBright = tConfig.Bright,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    iX = 0,
    iY = 0,
}

local tButtonStruct = {
    iColor = CColors.NONE,
    bClick = false,
    bDefect = false,
}

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    if tConfig.PodSize < 1 then tConfig.PodSize = 1;
    elseif  tConfig.PodSize > 2 then tConfig.PodSize = 2; end

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct)
            tFloor[iX][iY].iX = iX
            tFloor[iX][iY].iY = iY
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tButtonStruct)
    end

    CAudio.PlaySyncFromScratch("games/ping-pong-game.mp3") -- Игра "Пинг-понг"
    CAudio.PlaySync(CAudio.CHOOSE_COLOR) -- Выберите цвет
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    elseif iGameState == GAMESTATE_GAME then
        GameTick()
    elseif iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
    elseif iGameState == GAMESTATE_FINISH then
        return tGameResults
    end

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    tGameStats.TargetScore = tConfig.PointsToWinRound

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        local iBright = CColors.BRIGHT15
        if CheckPositionClick(tPos, tGame.StartPositionSize) then
            tGameStats.Players[iPos].Color = tPos.Color
            iBright = tConfig.Bright
            iPlayersReady = iPlayersReady + 1
        end

        SetPositionColorBright(tPos, tGame.StartPositionSize, tPos.Color, iBright)
    end

    if iPlayersReady == 2 then
        iGameState = GAMESTATE_GAME
        CPod.ResetPods()
        CBall.NewBall()
        CGameMode.RoundStartedAt = CTime.unix()
        tGameStats.StageLeftDuration = 0
        CGameMode.NextRoundCountDown(5, true)
    end
end

function GameTick() -- красим игру
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    if CBall.tPrev ~= nil then
        SetPositionColorBright({X = math.ceil(CBall.tPrev.iPosX), Y = math.ceil(CBall.tPrev.iPosY)}, 1, CBall.tBall.iColor, 1) -- тень мяча
    end
    SetPositionColorBright({X = math.ceil(CBall.tBall.iPosX), Y = math.ceil(CBall.tBall.iPosY)}, 1, CBall.tBall.iColor, tConfig.Bright) -- сам мяч
    CPod.PaintPods() -- игроки
end

function PostGameTick()
    SetGlobalColorBright(tGameStats.Players[CGameMode.GameWinner].Color, tConfig.Bright)
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tConfig.Bright)
    end
end

function SwitchStage()
end

--GAMEMODE класс отвечает за раунды и счёт игроков
CGameMode = {}
CGameMode.RoundStartedAt = CTime.unix()
CGameMode.iCountdown = -1
CGameMode.GameWinner = -1

CGameMode.NextRoundCountDown = function(iCountDownTime, bFirstRound)
    CGameMode.iCountdown = iCountDownTime
    CTimer.New(1000, function()
        CAudio.PlayLeftAudio(CGameMode.iCountdown)

        CGameMode.iCountdown = CGameMode.iCountdown - 1
        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1
            CGameMode.LaunchBall()

            if bFirstRound then
                CAudio.PlaySync(CAudio.START_GAME)
            end

            return nil
        else
            return 1000
        end
    end)
end

-- Запуск мяча на старте и после каждого гола
CGameMode.LaunchBall = function()
    CGameMode.RoundStartedAt = CTime.unix()

    CBall.tBall.iVelocityX = math.random(0,1)
    if CBall.tBall.iVelocityX == 0 then CBall.tBall.iVelocityX = -1 end

    CBall.tBall.iVelocityY = math.random(0,1)
    if CBall.tBall.iVelocityY == 0 then CBall.tBall.iVelocityY = -1 end

    CTimer.New(CBall.UpdateDelay, function()
        if CGameMode.iCountdown ~= -1 then
            return nil
        end

        CBall.Movement()

        return CBall.UpdateDelay
    end)
end

-- Конец игры
CGameMode.EndGame = function(iWinnerID)
    CGameMode.GameWinner = iWinnerID

    CAudio.PlaySyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.GameWinner].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationSec*1000, function()
        iGameState = GAMESTATE_FINISH
        return nil
    end)
end

-- Расчёт гола
CGameMode.ScoreGoalPlayer = function(iPlayerID)
    CAudio.PlaySync(CAudio.MISCLICK)

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

    if tGameStats.Players[iPlayerID].Score >= tGameStats.TargetScore then
        CGameMode.EndGame(iPlayerID)
        return
    end

    CBall.NewBall()
    CGameMode.RoundStartedAt = CTime.unix()
    tGameStats.StageLeftDuration = 0
    CGameMode.NextRoundCountDown(3, false)
end

--BALL класс отвечает за позицию мяча и просчёт траектории
CBall = {}

CBall.UpdateDelay = tConfig.InitialBallDelayMS

CBall.tBall = {}
CBall.tPrev = nil
CBall.tBallStruct = {
    iPosX = 0,
    iPosY = 0,
    iColor = 0,
    iVelocityX = 0,
    iVelocityY = 0,
}

CBall.NewBall = function()
    CBall.UpdateDelay = tConfig.InitialBallDelayMS

    CBall.tPrev = nil
    CBall.tBall = CHelp.ShallowCopy(CBall.tBallStruct)
    CBall.tBall.iPosX = math.floor(tGame.Cols/2)
    CBall.tBall.iPosY = math.random(3, tGame.Rows-2)
    CBall.tBall.iColor = CColors.GREEN
    CBall.tBall.iVelocityX = 0
    CBall.tBall.iVelocityY = 0
end

CBall.Movement = function()
    if iGameState ~= GAMESTATE_GAME or CGameMode.iCountdown ~= -1 then return; end

    tGameStats.StageLeftDuration = CTime.unix() - CGameMode.RoundStartedAt

    CBall.tPrev = CHelp.ShallowCopy(CBall.tBall)

    local iPlayerCollision, iHitPosition = CPod.Collision(CBall.tBall.iVelocityY, CBall.tBall.iPosX, CBall.tBall.iPosY)

    if iPlayerCollision ~= 0 then
        CAudio.PlaySync(CAudio.CLICK)

        CBall.tBall.iVelocityX = CBall.tBall.iVelocityX * -1

        if iHitPosition == HIT_CORNER and CBall.tBall.iPosY > 1 and CBall.tBall.iPosY < tGame.Rows then
            CBall.tBall.iVelocityY = CBall.tBall.iVelocityY * -1
        end

        CBall.tBall.iPosX = CBall.tBall.iPosX + CBall.tBall.iVelocityX

        if CBall.UpdateDelay > tConfig.MinBallDelayMS then
            CBall.UpdateDelay = CBall.UpdateDelay - tConfig.BallDelayHitDecreaseMS
        end
    else
        CBall.tBall.iPosX = CBall.tBall.iPosX + CBall.tBall.iVelocityX
    end

    CBall.tBall.iPosY = CBall.tBall.iPosY + CBall.tBall.iVelocityY

    if (CBall.tBall.iPosY <= 1) or (CBall.tBall.iPosY >= tGame.Rows) then
        CBall.tBall.iVelocityY = CBall.tBall.iVelocityY * -1
    end

    if CBall.tBall.iPosX <= 0 then
        CGameMode.ScoreGoalPlayer(2)
    elseif CBall.tBall.iPosX > tGame.Cols then
        CGameMode.ScoreGoalPlayer(1)
    end
end
--//

--POD класс отвечает за позиции игроков
CPod = {}

CPod.tPods = {}
CPod.tStruct = {
    iPosX = 0,
    iPosY = 0,
}

-- для самой игры поидее эта функция вообще не нужна, только для веб версии
CPod.ResetPods = function()
    CPod.tPods[1] = CHelp.ShallowCopy(CPod.tStruct)
    CPod.tPods[1].iPosX = tGame.StartPositions[1].X
    CPod.tPods[1].iPosY = tGame.StartPositions[1].Y

    CPod.tPods[2] = CHelp.ShallowCopy(CPod.tStruct)
    CPod.tPods[2].iPosX = tGame.StartPositions[2].X+1
    CPod.tPods[2].iPosY = tGame.StartPositions[2].Y
end

CPod.PaintPods = function()
    for i = 1, 2 do
        tFloor[CPod.tPods[i].iPosX][CPod.tPods[i].iPosY].iColor = tGameStats.Players[i].Color

        for p = 1, tConfig.PodSize do
            if CPod.tPods[i].iPosY+p <= tGame.Rows then
                tFloor[CPod.tPods[i].iPosX][CPod.tPods[i].iPosY+p].iColor = tGameStats.Players[i].Color
            end

            if CPod.tPods[i].iPosY-p > 0 then
                tFloor[CPod.tPods[i].iPosX][CPod.tPods[i].iPosY-p].iColor = tGameStats.Players[i].Color
            end
        end
    end
end

-- Ставит позицию пода между двух максимальных нажатий
CPod.UpdatePodPositions = function(clickX)
    if iGameState == GAMESTATE_GAME then
        local tPod
        if clickX < math.floor(tGame.Cols/2) then
            tPod = CPod.tPods[1]
        else
            tPod = CPod.tPods[2]
        end

        local maxPoints = {}

        for iY = 1,tGame.Rows do
            local bClick = tFloor[tPod.iPosX-1][iY].bClick or tFloor[tPod.iPosX][iY].bClick or tFloor[tPod.iPosX+1][iY].bClick
            if not bClick then
                goto continue;
            end

            local iWeight = tFloor[tPod.iPosX-1][iY].iWeight+tFloor[tPod.iPosX][iY].iWeight+tFloor[tPod.iPosX+1][iY].iWeight

            if #maxPoints == 0 then
                maxPoints[1] = {
                    iY = iY,
                    iWeight = iWeight,
                }
            else -- #maxPoints == 1 or 2
                if iWeight >= maxPoints[1].iWeight then
                    maxPoints[2] = CHelp.ShallowCopy(maxPoints[1])
                    maxPoints[1] = {
                        iY = iY,
                        iWeight = iWeight,
                    }
                elseif maxPoints[2] == nil or iWeight >= maxPoints[2].iWeight then
                    maxPoints[2] = {
                        iY = iY,
                        iWeight = iWeight,
                    }
                end
            end
            ::continue::
        end

        if #maxPoints == 0 then
            -- не менять позицию
            -- tPod.iPosY = math.floor(tGame.Rows/2)
        elseif #maxPoints == 1 then
            tPod.iPosY = maxPoints[1].iY
        else
            tPod.iPosY = math.floor((maxPoints[1].iY + maxPoints[2].iY) / 2 )
        end
    end
end

-- Просчёт колизии с игроком
CPod.Collision = function(iVel, iX, iY)
    local i = 0
    if iX == CPod.tPods[1].iPosX+1 then i = 1; end
    if iX == CPod.tPods[2].iPosX-1 then i = 2; end

    if i == 0 then return 0; end

    if iY >= CPod.tPods[i].iPosY-tConfig.PodSize and iY <= CPod.tPods[i].iPosY+tConfig.PodSize then
        return i, HIT_CENTER
    elseif iVel == 1 and iY == CPod.tPods[i].iPosY-(tConfig.PodSize+1) then
        return i, HIT_CORNER
    elseif iVel == -1 and iY == CPod.tPods[i].iPosY+(tConfig.PodSize+1) then
        return i, HIT_CORNER
    end

    return 0
end
--//

-- TIMER класс отвечает за таймеры, очень полезная штука.
-- Можно вернуть время нового таймера с тем же колбеком
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

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSize)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i/iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then
            if tFloor[iX][iY].bClick then
                return true
            end
        end
    end

    return false
end

function SetPositionColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i / iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
end

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end
--//

-- Остальные служебные методы
function GetStats()
    return tGameStats
end

function PauseGame()
end

function ResumeGame()
    iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    CPod.UpdatePodPositions(click.X)
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return; end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return; end
    tButtons[defect.Button].bDefect = defect.Defect
end
