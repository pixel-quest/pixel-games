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
require("avonlib")

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
    BallDelayHitDecreaseMS = 20, -- уменьшение задержки после каждого удара игрока по мячу
    MinBallDelayMS = 70, -- минимальная задержка, ниже этой опустится не может
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
        { Score = 0, Lives = 0, Color = CColors.RED },
        { Score = 0, Lives = 0, Color = CColors.BLUE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 2,
    Score = 0,
    Color = CColors.NONE,
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

local bGamePaused = false

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

    iPrevTickTime = CTime.unix()

    tGame.StartPositionSize = 3

    CGameMode.iMinX = 1
    CGameMode.iMinY = 1
    CGameMode.iMaxX = tGame.Cols
    CGameMode.iMaxY = tGame.Rows

    if tGame.StartPositions == nil then
        if AL.RoomHasNFZ(tGame) then
            AL.LoadNFZInfo()
        
            CGameMode.iMinX = AL.NFZ.iMinX
            CGameMode.iMinY = AL.NFZ.iMinY
            CGameMode.iMaxX = AL.NFZ.iMaxX
            CGameMode.iMaxY = AL.NFZ.iMaxY
        end

        tGame.StartPositions = {}
        for iPlayerID = 1, 2 do
            tGame.StartPositions[iPlayerID] = {}
            if iPlayerID == 1 then
                tGame.StartPositions[iPlayerID].X = CGameMode.iMinX + tGame.StartPositionSize
            elseif iPlayerID == 2 then
                tGame.StartPositions[iPlayerID].X = CGameMode.iMaxX - tGame.StartPositionSize - 1
            end
            tGame.StartPositions[iPlayerID].Y = math.floor(CGameMode.iMaxY/2 + CGameMode.iMinY/2)-1
            tGame.StartPositions[iPlayerID].Color = tGameStats.Players[iPlayerID].Color
        end    
    else
        for iPlayerID = 1, #tGame.StartPositions do
            tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
        end 
    end

    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSyncFromScratch("ping-pong/ping-pong-game.mp3") -- Игра "Пинг-понг"

        AL.NewTimer(CAudio.GetVoicesDuration("ping-pong/ping-pong-game.mp3")*1000, function()
            CGameMode.bCanStart = true
        end)
    else
        CGameMode.bCanStart = true
    end
    
    CAudio.PlayVoicesSync(CAudio.CHOOSE_COLOR) -- Выберите цвет
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    elseif iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()

        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
    end

    if iGameState == GAMESTATE_FINISH then
        tGameResults.AfterDelay = false
        return tGameResults
    end   

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    tGameStats.TargetScore = tConfig.PointsToWinRound

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos == 2 or not tConfig.SoloGame then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSize) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                iPlayersReady = iPlayersReady + 1
            end

            SetPositionColorBright(tPos, tGame.StartPositionSize, tPos.Color, iBright)
        end
    end

    if CGameMode.bCanStart and (iPlayersReady == 2 or (tConfig.SoloGame and iPlayersReady == 1)) then
        iGameState = GAMESTATE_GAME
        CPod.ResetPods()
        CBall.NewBall()
        CGameMode.RoundStartedAt = CTime.unix()
        tGameStats.StageLeftDuration = 0
        CGameMode.NextRoundCountDown(5, true)

        if tConfig.SoloGame then
            tGameStats.Players[1].Color = tGame.StartPositions[1].Color
            CAI.Think()
        end
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

CGameMode.bCanStart = false

CGameMode.iMinX = 0
CGameMode.iMinY = 0
CGameMode.iMaxX = 0
CGameMode.iMaxY = 0

CGameMode.NextRoundCountDown = function(iCountDownTime, bFirstRound)
    CGameMode.iCountdown = iCountDownTime
    AL.NewTimer(1000, function()
        CAudio.ResetSync()

        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1
            CGameMode.LaunchBall()
            CAudio.PlayRandomBackground()

            if bFirstRound then
                CAudio.PlayVoicesSync(CAudio.START_GAME)
            end

            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

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

    AL.NewTimer(CBall.UpdateDelay, function()
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

    CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.GameWinner].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGameStats.Players[CGameMode.GameWinner].Color

    iGameState = GAMESTATE_POSTGAME

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
        return nil
    end)

    SetGlobalColorBright(tGameStats.Players[CGameMode.GameWinner].Color, tConfig.Bright)
end

-- Расчёт гола
CGameMode.ScoreGoalPlayer = function(iPlayerID)
    CAudio.StopBackground()
    CAudio.PlaySystemSync(CAudio.MISCLICK)

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
    CBall.tBall.iPosX = math.floor((CGameMode.iMaxX + (tGame.StartPositions[1].X) - (CGameMode.iMaxX-tGame.StartPositions[2].X))  /2)
    CBall.tBall.iPosY = math.random(CGameMode.iMinY+2, CGameMode.iMaxY-2)
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
        CAudio.PlaySystemSync(CAudio.CLICK)

        CBall.tBall.iVelocityX = CBall.tBall.iVelocityX * -1

        if iHitPosition == HIT_CORNER and CBall.tBall.iPosY > CGameMode.iMinY and CBall.tBall.iPosY < CGameMode.iMaxY then
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

    if (CBall.tBall.iPosY <= CGameMode.iMinY) or (CBall.tBall.iPosY >= CGameMode.iMaxY) then
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
            if tConfig.SoloGame then return; end
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

--AI
CAI = {}

CAI.GoalY = 0

CAI.Think = function()
    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        if CPad.AFK() then
            CAI.AIMove()
        else
            CAI.PadMove()
        end

        return 200
    end)
end

CAI.AIMove = function()
    if CAI.GoalY == 0 or CAI.GoalY == CPod.tPods[1].iPosY then
        CAI.GoalY = math.random(CGameMode.iMinY, CGameMode.iMaxY)
    end 

    if CPod.tPods[1].iPosY < CAI.GoalY then
        CPod.tPods[1].iPosY = CPod.tPods[1].iPosY + 1
    else
        CPod.tPods[1].iPosY = CPod.tPods[1].iPosY - 1
    end
end

CAI.PadMove = function()
    local iNewY = CPod.tPods[1].iPosY + CPad.iXPlus

    if iNewY > 0 and iNewY < tGame.Rows then
        CPod.tPods[1].iPosY = iNewY
    end

    CPad.iXPlus = 0
end
--//

--Pad
CPad = {}
CPad.LastInteractionTime = -1

CPad.iXPlus = 0
CPad.iYPlus = 0
CPad.bTrigger = false

CPad.Click = function(bUp, bDown, bLeft, bRight, bTrigger)
    if bUp == true or bDown == true or bLeft == true or bRight == true or bTrigger == true then
        CPad.LastInteractionTime = CTime.unix()
    end

    CPad.bTrigger = bTrigger

    if bUp then 
        CPad.iYPlus = -1
        CPad.iXPlus = 0
    end

    if bDown then 
        CPad.iYPlus = 1
        CPad.iXPlus = 0
    end

    if bLeft then
        CPad.iXPlus = -1
        CPad.iYPlus = 0
    end

    if bRight then 
        CPad.iXPlus = 1 
        CPad.iYPlus = 0
    end
end

CPad.AFK = function()
    return CPad.LastInteractionTime == -1 or (CTime.unix() - CPad.LastInteractionTime > tConfig.PadAFKTimer)
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
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
    iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    if tFloor[click.X] and tFloor[click.X][click.Y] and not bGamePaused then
        if iGameState == GAMESTATE_SETUP then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
                tFloor[click.X][click.Y].bHold = false
            elseif not tFloor[click.X][click.Y].bHold then
                AL.NewTimer(500, function()
                    if not tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bHold = true
                        AL.NewTimer(750, function()
                            if tFloor[click.X][click.Y].bHold then
                                tFloor[click.X][click.Y].bClick = false
                            end
                        end)
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        CPod.UpdatePodPositions(click.X)
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if click.GamepadAddress and click.GamepadAddress > 0 and not bGamePaused then
        CPad.Click(click.GamepadUpClick, click.GamepadDownClick, click.GamepadLeftClick, click.GamepadRightClick, click.GamepadTriggerClick)
    else
        if tButtons[click.Button] == nil then return; end
        tButtons[click.Button].bClick = click.Click
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return; end
    tButtons[defect.Button].bDefect = defect.Defect
end
