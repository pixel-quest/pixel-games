--[[
Название: Защита Базы
Версия: 1.4
Автор: Avondale, дискорд - avonda

Описание механики:
    По центру карты стоит база, которую защищают игроки
    На базу со всех сторон топают враги, которых надо топтать
    Враги бывают разных типов
    Большинство врагов наносит урон доходя до базы пешком, некоторые атакуют из далека
    У базы ограниченое колво здоровья, если здоровья нет - игра проиграна
    Для победы нужно раздавить определенное число врагов

Чтобы начать игру нужно нажать на любую кнопку

Сложности:
    Сложность выбирается в config.json, параметры сложностей настраиваются в game.json
    
    Уровни:
    "Very Easy" - для одного игрока
    "Easy" - легкий для новичков
    "Medium" - средний для тех кто уже играл
    "Hard" - испытание для самых быстрых

-------------------------------------------------------------------
Что нужно доделать:
    Искуственный интеллект получше
    Эффекты, анимации, звуки

Идеи по доработке механники:
    Хардкорная сложность?
    Постройка укреплений?
    Помогающие юниты?

Описание типов врагов:
    Обычный враг (UNIT_TYPE_DEFLT):
        Белый квадрат 2 на 2, не представляет особой опасности

    Катапульта/Арта (UNIT_TYPE_SHOOT):
        Красная пушка, которая обстреливает базу игрока с края карты
        Выманивает игроков из центра карты, очень важно для баланса
        Этот юнит поидее самый законченный и особо доделывать его ненадо, даже ИИ норм

    Иллюзионист/Ловкач (UNIT_TYPE_BLINK):
        Розовый квадрат 2 на 2, относительно опасен
        Может несколько раз уклонится от удара игрока, отпрыгивает назад при этом

        Доделать:
            Нужен звук телепорта назад и мб анимация какаято

    Слизень (UNIT_TYPE_SLIME):
        Синий квадрат 2 на 2, особо опасен
        При смерти распадается на 4 юнита 1x1

        Доделать:
            Звук распада, анимация?

Идеи для новых типов врагов:
    неуверен что они нужны, иногда лучше не добавлять в игру лишней сложности
    + изза больших ограничений платформы тут особо много чего не придумаешь

    Танк/Тяжелый (UNIT_TYPE_HEAVY):
        3 на 3 квадрат зеленого цвета
        Чтобы убить нужно несколько раз ударить

        Уже прописан в коде, но работает неочень, поэтому я его отключил

        1 - непонятно как будут регистрироватся нажатия, скорее всего иногда за один удар будет несколько что неочень
        2 - иллюзионист существует с той же целью, но реализуется лучше и работает интереснее

        даже если есть способ исправить первую проблему, то я не думаю что есть смысл добавлять этого юнита изза второй проблемы

    Призыватель:
        3 на 3 квадрат жёлтого цвета
        Издалека призывает юнитов

        ухудшеная версия катапульты, которая уже готова и работает понятнее, призванные юниты это как снаряды, но медленее и их можно убить
        если катапульта будет слишком имбовой заменить на это?
        или сделать так чтобы призыватель возраждал убитых юнитов? тоесть некромант... и как это анимировать?

    Бегун:
        1 на 1 квадрат голубого цвета
        Бежит быстрее чем остальные

        только для хардкорной сложности наверное можно сделать
]]
math.randomseed(os.time())

local CLog = require("log")
local CInspect = require("inspect")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 24,
    Rows = 15,
    Buttons = {},
}
local tConfig = {}

-- стейты или этапы игры
local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4

local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0
local bAnyButtonClick = false

local tGameStats = {
    StageLeftDuration = 0,
    StageTotalDuration = 0,
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
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
}

local tGameResults = {
    Won = false,
}

local tFloor = {}
local tButtons = {}

local tFloorStruct = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    bBlocked = false,
    iUnitID = 0,
}
local tButtonStruct = {
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
}

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct)
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tButtonStruct)
    end

    CGameMode.PrepareGame()
end

function NextTick()
    if bGamePaused then return end

    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    CPaint.Objects()
    SetAllButtonsColorBright(CColors.BLUE, tConfig.Bright)

    if bAnyButtonClick then
        CGameMode.StartCountDown(5)
        iGameState = GAMESTATE_GAME
    end
end

function GameTick()
    CPaint.Objects()
end

function PostGameTick()
    CPaint.Objects()
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX, iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end
end

function SwitchStage()

end

--GAMEMODE
CGameMode = {}
CGameMode.tSettings = {}
CGameMode.iCountdown = 0
CGameMode.bVictory = false

CGameMode.tBase = {
    iX = 0,
    iY = 0,
    iSize = 2,
    iHealth = 0,
    iColor = 0,
}

CGameMode.PrepareGame = function()
    CGameMode.tSettings = tGame["Settings"][tConfig.Difficulty]

    tGameStats.TotalStars = CGameMode.tSettings.UnitsToKill

    CGameMode.tBase.iX = math.floor(tGame.Cols/2)
    CGameMode.tBase.iY = math.floor(tGame.Rows/2)
    CGameMode.tBase.iHealth = CGameMode.tSettings.BaseHealth
    CGameMode.tBase.iColor = tConfig.BaseColor

    tGameStats.TotalLives = CGameMode.tBase.iHealth
    tGameStats.CurrentLives = CGameMode.tBase.iHealth

    CUnits.UnitSettings()

    CAudio.PlaySync("games/tower-defence-game.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CTimer.New(1000, function()
        CAudio.PlaySyncFromScratch("")
        
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            CAudio.PlaySync(CAudio.START_GAME)
            CAudio.PlayRandomBackground()
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CLog.print("Game Started!")

    CTimer.New(1, function()
        if iGameState == GAMESTATE_GAME then
            CGameMode.SpawnUnits()
            return tConfig.UnitSpawnDelay
        else
            return nil
        end
    end)

    CTimer.New(tConfig.UnitThinkDelay, function()
        if iGameState < GAMESTATE_FINISH then
            CUnits.ProcessUnits()
            return tConfig.UnitThinkDelay
        end

        return nil
    end)

    CTimer.New(tConfig.ProjectileDelay, function()
        if iGameState == GAMESTATE_GAME then
            CProjectile.CalculateProjectiles()
            return tConfig.ProjectileDelay
        else
            return nil
        end
    end)
end

CGameMode.Victory = function()
    CAudio.StopBackground()
    CAudio.PlaySync(CAudio.GAME_SUCCESS)
    CAudio.PlaySync(CAudio.VICTORY)
    CGameMode.bVictory = true
    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = true
        iGameState = GAMESTATE_FINISH
    end)

    CAnimation.EndGameFill(CColors.GREEN)
end

CGameMode.Defeat = function()
    CAudio.StopBackground()
    CAudio.PlaySync(CAudio.GAME_OVER)    
    CAudio.PlaySync(CAudio.DEFEAT)
    CGameMode.bVictory = false
    CGameMode.tBase.iColor = CColors.RED
    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = false
        iGameState = GAMESTATE_FINISH
    end)

    CAnimation.EndGameFill(CColors.RED)
end

CGameMode.SpawnUnits = function()
    for i = 1, CGameMode.tSettings.UnitCountPerSpawn do
        --CGameMode.SpawnUnit(CUnits.UNIT_TYPE_DEFLT)
        CGameMode.SpawnUnit(CUnits.RandomUnitType())
    end
end

CGameMode.SpawnUnit = function(iUnitType)
    local iXPoint = 0
    local iYPoint = 0

    local bXMain = iUnitType == CUnits.UNIT_TYPE_SHOOT or math.random(0,1) == 0
    local bHighPoint = math.random(0,1) == 1

    if bXMain then
        iYPoint = math.random(1, tGame.Rows)

        iXPoint = 1
        if bHighPoint then
            iXPoint = tGame.Cols
        end
    else
        if math.random(1,2) == 1 then
            iXPoint = math.random(1, math.floor(tGame.Cols/3))
        else
            iXPoint = math.random(math.ceil(tGame.Cols/2 + tGame.Cols/3), tGame.Cols)
        end

        iYPoint = 1
        if bHighPoint then
            iYPoint = tGame.Rows
        end
    end

    CUnits.NewUnit(iXPoint, iYPoint, iUnitType, true, bXMain)
end

CGameMode.DamageBase = function(iDamageAmount)
    CGameMode.tBase.iHealth = CGameMode.tBase.iHealth - iDamageAmount
    tGameStats.CurrentLives = CGameMode.tBase.iHealth

    CAudio.PlayAsync(CAudio.MISCLICK)

    if CGameMode.tBase.iHealth <= 0 then
        CGameMode.Defeat()
    end
end
--//

--UNITS
CUnits = {}

CUnits.tUnits = {}
CUnits.tUnitStruct = {
    iX = 0,
    iY = 0,
    iStartX = 0,
    iStartY = 0,
    iUnitType = 1,
    iHealth = 1,
    iSize = 2,
    bScoreable = true,
    bXMain = true,
    iSpecial = 0,
    tShadow = {},
}

CUnits.UNIT_TYPE_COUNT = 4

CUnits.UNIT_TYPE_DEFLT = 1
CUnits.UNIT_TYPE_SHOOT = 2
CUnits.UNIT_TYPE_BLINK = 3
CUnits.UNIT_TYPE_SLIME = 4
CUnits.UNIT_TYPE_HEAVY = 5

CUnits.UNIT_TYPE_TO_COLOR = {}
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_DEFLT] = CColors.WHITE
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_SHOOT] = CColors.RED
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_BLINK] = CColors.MAGENTA
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_SLIME] = CColors.BLUE
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_HEAVY] = CColors.GREEN

CUnits.UNIT_TYPE_HEALTH = {}
CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_DEFLT] = 1
CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_SHOOT] = 1
CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_BLINK] = 1
CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_SLIME] = 1
CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_HEAVY] = 4

CUnits.UNIT_TYPE_SIZE = {}
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_DEFLT] = 2
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_SHOOT] = 3
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_BLINK] = 2
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_SLIME] = 2
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_HEAVY] = 3

CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER = 1
CUnits.UNIT_DEATH_REASON_REACHED_BASE = 2
CUnits.UNIT_DEATH_REASON_FRIENDLY_FIRE = 3

CUnits.UnitSettings = function()
    CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_DEFLT] = CGameMode.tSettings.UnitHealthDefault
    CUnits.UNIT_TYPE_HEALTH[CUnits.UNIT_TYPE_SHOOT] = CGameMode.tSettings.UnitHealthShoot

    CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_DEFLT] = CGameMode.tSettings.UnitSizeDefault
    CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_BLINK] = CGameMode.tSettings.UnitSizeBlink
    CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_SLIME] = CGameMode.tSettings.UnitSizeSlime
end

CUnits.NewUnit = function(iX, iY, iUnitType,  bScoreable, bXMain, iSize)
    iUnitID = #CUnits.tUnits+1

    --CLog.print("Spawning unit #"..iUnitID.." at "..iX..":"..iY.." with type #"..iUnitType)

    CUnits.tUnits[iUnitID] = CHelp.ShallowCopy(CUnits.tUnitStruct)
    CUnits.tUnits[iUnitID].iX = iX
    CUnits.tUnits[iUnitID].iY = iY
    CUnits.tUnits[iUnitID].iUnitType = iUnitType
    CUnits.tUnits[iUnitID].iHealth = CUnits.UNIT_TYPE_HEALTH[iUnitType]
    CUnits.tUnits[iUnitID].bScoreable = bScoreable
    CUnits.tUnits[iUnitID].bXMain = bXMain
    CUnits.tUnits[iUnitID].iSpecial = 0

    if iSize == nil then
        CUnits.tUnits[iUnitID].iSize = CUnits.UNIT_TYPE_SIZE[iUnitType]
    else
        CUnits.tUnits[iUnitID].iSize = iSize
    end

    if bScoreable then
        while CUnits.RectHasUnitsOrBlocked(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize) do
            if CUnits.tUnits[iUnitID].bXMain then
                CUnits.tUnits[iUnitID].iY = math.random(1, tGame.Rows)
            else
                CUnits.tUnits[iUnitID].iX = math.random(1, tGame.Cols)
            end
        end
    end

    CUnits.tUnits[iUnitID].iStartX = CUnits.tUnits[iUnitID].iX
    CUnits.tUnits[iUnitID].iStartY = CUnits.tUnits[iUnitID].iY

    if iUnitType == CUnits.UNIT_TYPE_BLINK then
        CUnits.tUnits[iUnitID].iSpecial = CGameMode.tSettings.SpecialBlink
    end

    if iUnitType == CUnits.UNIT_TYPE_SHOOT then
        CUnits.tUnits[iUnitID].iSpecial = CGameMode.tSettings.SpecialShootDelay

        --local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitID)
        --CUnits.tUnits[iUnitID].iX = iX + iXPlus
        --CUnits.tUnits[iUnitID].iY = iY + iYPlus
    end
end

CUnits.RectHasUnitsOrBlocked = function(iXStart, iYStart, iSize)
    if iXStart < 0 or iXStart > tGame.Cols or iYStart < 0 or iYStart > tGame.Rows then return true end

    for iX = iXStart, iXStart + iSize do
        for iY = iYStart, iYStart + iSize do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].iUnitID > 0 then return true end
                if tFloor[iX][iY].bDefect then return true end
                if tFloor[iX][iY].bBlocked then return true end
            end
        end
    end

    return false
end

CUnits.RandomUnitType = function()
    if math.random(1, 100) > CGameMode.tSettings.SpecialUnitSpawnChance then
        return 1
    else
        return math.random(2,CUnits.UNIT_TYPE_COUNT)
    end
end

CUnits.ProcessUnits = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            CUnits.UnitThink(iUnitID)
        end
    end
end

--UNIT AI
CUnits.UnitThink = function(iUnitID)
    if iGameState == GAMESTATE_GAME then
        if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_SHOOT then
            CUnits.UnitThinkShoot(iUnitID)
        else
            CUnits.UnitThinkDefault(iUnitID)
        end
    elseif iGameState == GAMESTATE_POSTGAME and CGameMode.bVictory then
        -- если игра закончилась победой то враги отступают в страхе!
        iXPlus, iYPlus = CUnits.GetReverseDestinationXYPlus(iUnitID)
        CUnits.Move(iUnitID, iXPlus, iYPlus)
    end
end

CUnits.UnitThinkDefault = function(iUnitID)
    local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitID)

    if CUnits.CanMove(iUnitID, iXPlus, iYPlus) then
        CUnits.Move(iUnitID, iXPlus, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, 0) then
        CUnits.Move(iUnitID, iXPlus, 0)
    elseif CUnits.CanMove(iUnitID, 0, iYPlus) then
        CUnits.Move(iUnitID, 0, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, -1) then
        CUnits.Move(iUnitID, iXPlus, -1)        
    elseif CUnits.CanMove(iUnitID, -1, iYPlus) then
        CUnits.Move(iUnitID, -1, iYPlus)        
    elseif CUnits.CanMove(iUnitID, 1, iYPlus) then
        CUnits.Move(iUnitID, 1, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, 1) then
        CUnits.Move(iUnitID, iXPlus, 1)
    end
end

CUnits.UnitThinkShoot = function(iUnitID)
    local bCanShoot = false
    local bFired = false

    if CUnits.tUnits[iUnitID].iSpecial == nil or CUnits.tUnits[iUnitID].iSpecial <= 0 then
        CUnits.tUnits[iUnitID].iSpecial = CGameMode.tSettings.SpecialShootDelay
        bCanShoot = true
    else
        CUnits.tUnits[iUnitID].iSpecial = CUnits.tUnits[iUnitID].iSpecial - tConfig.UnitThinkDelay
    end

    if bCanShoot then
        local iXVel, iYVel = CUnits.GetDestinationXYPlus(iUnitID)
        CProjectile.New(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY+1, iXVel, 0, 1)

        CAudio.PlayAsync("plasma.mp3")

        bFired = true
    end

    local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitID)
    if math.random( 1,2 ) == 1 then
        iYPlus = math.random(-1,1)
    end

    if not (CUnits.tUnits[iUnitID].iX < 1 or CUnits.tUnits[iUnitID].iX > tGame.Cols-3) then
        iXPlus = 0
    end

    if not bFired and CUnits.CanMove(iUnitID, iXPlus, iYPlus) then
        CUnits.Move(iUnitID, iXPlus, iYPlus)
    end
end
--/

--UNIT MOVEMENT
CUnits.CanMove = function(iUnitID, iXPlus, iYPlus)
    if iXPlus == 0 and iYPlus == 0 then return false end

    local iX = CUnits.tUnits[iUnitID].iX + iXPlus
    local iY = CUnits.tUnits[iUnitID].iY + iYPlus

    for iXCheck = iX, iX + CUnits.tUnits[iUnitID].iSize-1 do
        for iYCheck = iY, iY + CUnits.tUnits[iUnitID].iSize-1 do
            if not tFloor[iXCheck] or not tFloor[iXCheck][iYCheck] then return true end
            if tFloor[iXCheck][iYCheck].iUnitID > 0 and tFloor[iXCheck][iYCheck].iUnitID ~= iUnitID then return false end
            if tFloor[iXCheck][iYCheck].bBlocked then return false end
            if tFloor[iXCheck][iYCheck].bDefect then return false end
            if tFloor[iXCheck][iYCheck].bClick then return false end
        end
    end

    return true
end

CUnits.Move = function(iUnitID, iXPlus, iYPlus)
    CUnits.tUnits[iUnitID].tShadow = {iX = CUnits.tUnits[iUnitID].iX, iY = CUnits.tUnits[iUnitID].iY}

    CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iXPlus
    CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iYPlus

    if Intersects(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize, CGameMode.tBase.iX, CGameMode.tBase.iY, CGameMode.tBase.iSize) then
        CGameMode.DamageBase(CUnits.tUnits[iUnitID].iHealth)
        CUnits.UnitKill(iUnitID, CUnits.UNIT_DEATH_REASON_REACHED_BASE)
        return;
    end

    CPaint.Unit(iUnitID) -- для просчёта коллизии

    if CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_HEAVY and
        CheckPositionClick({X = CUnits.tUnits[iUnitID].iX, Y = CUnits.tUnits[iUnitID].iY}, CUnits.tUnits[iUnitID].iSize) then

        CUnits.UnitTakeDamage(iUnitID, 1)
    end
end

CUnits.GetDestinationXYPlus = function(iUnitID)
    local iX = 0
    local iY = 0

    if CUnits.tUnits[iUnitID].iX < CGameMode.tBase.iX then
        iX = 1
    elseif CUnits.tUnits[iUnitID].iX > CGameMode.tBase.iX then
        iX = -1
    end

    if CUnits.tUnits[iUnitID].iY < CGameMode.tBase.iY then
        iY = 1
    elseif CUnits.tUnits[iUnitID].iY > CGameMode.tBase.iY then
        iY = -1
    end

    return iX, iY
end

CUnits.GetReverseDestinationXYPlus = function(iUnitID)
    local iX = 1
    local iY = 1

    if CUnits.tUnits[iUnitID].iX < CGameMode.tBase.iX then
        iX = -1
    elseif CUnits.tUnits[iUnitID].iX > CGameMode.tBase.iX then
        iX = 1
    end

    if CUnits.tUnits[iUnitID].iY < CGameMode.tBase.iY then
        iY = -1
    elseif CUnits.tUnits[iUnitID].iY > CGameMode.tBase.iY then
        iY = 1
    end

    return iX, iY
end
--/

--UNIT EVENTS
CUnits.UnitTakeDamage = function(iUnitID, iDamageAmount)
    CUnits.tUnits[iUnitID].iHealth = CUnits.tUnits[iUnitID].iHealth - iDamageAmount

    if CUnits.tUnits[iUnitID].iHealth <= 0 then
        CUnits.UnitKill(iUnitID, CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER)
    end
end

CUnits.UnitKill = function(iUnitID, iReasonID)
    local bTrueDeath = iReasonID ~= CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER or CUnits.UnitSpecial(iUnitID)

    if bTrueDeath then
        if iReasonID == CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER then
            CAudio.PlayAsync(CAudio.CLICK)

            if CUnits.tUnits[iUnitID].bScoreable then
                tGameStats.CurrentStars = tGameStats.CurrentStars + 1
                if tGameStats.CurrentStars >= tGameStats.TotalStars and CGameMode.tBase.iHealth > 0 then
                    CGameMode.Victory()
                end
            end

            if CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_SLIME and CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_SHOOT then
                CAnimation.Death(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize, CUnits.UNIT_TYPE_TO_COLOR[CUnits.tUnits[iUnitID].iUnitType])
            end
        end

        CUnits.tUnits[iUnitID] = nil
    end
end

-- просчёт смертей особых юнитов
CUnits.UnitSpecial = function(iUnitID)
    if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_BLINK and CUnits.tUnits[iUnitID].iSpecial > 0 then
        CAudio.PlayAsync("teleport.mp3")

        CUnits.tUnits[iUnitID].iSpecial = CUnits.tUnits[iUnitID].iSpecial - 1

        local iPlusX, iPlusY = CUnits.GetReverseDestinationXYPlus(iUnitID)

        if CUnits.tUnits[iUnitID].bXMain then
            CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iPlusX*math.random(1,2)
            CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iPlusY*math.random(2,4)
        else
            CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iPlusX*math.random(2,4)
            CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iPlusY*math.random(1,2)
        end

        CUnits.tUnits[iUnitID].tShadow = {}

        return false
    elseif CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_SLIME then
        local iSize = CUnits.tUnits[iUnitID].iSize-1
        if iSize > 0 then
            for i = 1, 4 do
                local iPlusX, iPlusY = CUnits.GetReverseDestinationXYPlus(iUnitID)

                CUnits.NewUnit(CUnits.tUnits[iUnitID].iX + iPlusX*math.random(1,5),
                    CUnits.tUnits[iUnitID].iY + iPlusY*math.random(1,5),
                    CUnits.UNIT_TYPE_SLIME,  false, CUnits.tUnits[iUnitID].bXMain, iSize)
            end
        end

        return true
    end

    return true
end
--/

--//

--Projectile
CProjectile = {}
CProjectile.tProjectiles = {}
CProjectile.tProjectileStruct = {
    iX = 0,
    iY = 0,
    iXVel = 0,
    iYVel = 0,
    iDamage = 0,
}

CProjectile.New = function(iX, iY, iXVel, iYVel, iDamage)
    local iProjectileID = #CProjectile.tProjectiles+1

    CProjectile.tProjectiles[iProjectileID] = CHelp.ShallowCopy(CProjectile.tProjectileStruct)
    CProjectile.tProjectiles[iProjectileID].iX = iX
    CProjectile.tProjectiles[iProjectileID].iY = iY
    CProjectile.tProjectiles[iProjectileID].iXVel = iXVel
    CProjectile.tProjectiles[iProjectileID].iYVel = iYVel
    CProjectile.tProjectiles[iProjectileID].iDamage = iDamage

    --CLog.print("New projectile fired! #"..iProjectileID)
end

CProjectile.Destroy = function(iProjectileID)
    CProjectile.tProjectiles[iProjectileID] = nil
end

CProjectile.CalculateProjectiles = function()
    for iProjectileID = 1, #CProjectile.tProjectiles do
        if CProjectile.tProjectiles[iProjectileID] then
            CProjectile.CalculateProjectile(iProjectileID)
        end
    end
end

CProjectile.CalculateProjectile = function(iProjectileID)
    CProjectile.tProjectiles[iProjectileID].iX = CProjectile.tProjectiles[iProjectileID].iX + CProjectile.tProjectiles[iProjectileID].iXVel
    CProjectile.tProjectiles[iProjectileID].iY = CProjectile.tProjectiles[iProjectileID].iY + CProjectile.tProjectiles[iProjectileID].iYVel

    if CProjectile.tProjectiles[iProjectileID].iX > tGame.Cols or CProjectile.tProjectiles[iProjectileID].iX < 0 or
    CProjectile.tProjectiles[iProjectileID].iY > tGame.Rows or CProjectile.tProjectiles[iProjectileID].iY < 0 then
        CProjectile.Destroy(iProjectileID)
        return;
    end

    if Intersects(CProjectile.tProjectiles[iProjectileID].iX, CProjectile.tProjectiles[iProjectileID].iY, 1, CGameMode.tBase.iX, CGameMode.tBase.iY, CGameMode.tBase.iSize) then
        --CLog.print("Projectile hit target!")
        CGameMode.DamageBase(CProjectile.tProjectiles[iProjectileID].iDamage)
        CProjectile.Destroy(iProjectileID)
        return;
    end

    if not tFloor[CProjectile.tProjectiles[iProjectileID].iX] or not tFloor[CProjectile.tProjectiles[iProjectileID].iX][CProjectile.tProjectiles[iProjectileID].iY] then return; end

    if tFloor[CProjectile.tProjectiles[iProjectileID].iX][CProjectile.tProjectiles[iProjectileID].iY].iUnitID ~= 0 then
        local iFFID = tFloor[CProjectile.tProjectiles[iProjectileID].iX][CProjectile.tProjectiles[iProjectileID].iY].iUnitID

        if CUnits.tUnits[iFFID].iUnitType ~= CUnits.UNIT_TYPE_SHOOT then
            --CLog.print("Friendly Fire!")
            CAudio.PlayAsync(CAudio.CLICK)

            CUnits.UnitKill(iFFID, CUnits.UNIT_DEATH_REASON_FRIENDLY_FIRE)
            CProjectile.Destroy(iProjectileID)
            return;
        end
    end
end
--//

--ANIMATION
CAnimation = {}

CAnimation.iAnimationDelay = 150
CAnimation.iDeathAnimationIters = 3

CAnimation.tAnimated = {}
CAnimation.tAnimatedStruct = {
    iX = 0,
    iY = 0,
    iColor = 0,
    iBright = 0,
}

CAnimation.EndGameFill = function(iColor)
    local iStartX = CGameMode.tBase.iX
    local iStartY = CGameMode.tBase.iY
    local iSize = CGameMode.tBase.iSize

    CTimer.New(CAnimation.iAnimationDelay, function()
        for iX = iStartX, iStartX + iSize-1 do
            for iY = iStartY, iStartY + iSize-1 do
                local iAnimationID = #CAnimation.tAnimated+1
                CAnimation.tAnimated[iAnimationID] = CHelp.ShallowCopy(CAnimation.tAnimatedStruct)
                CAnimation.tAnimated[iAnimationID].iX = iX
                CAnimation.tAnimated[iAnimationID].iY = iY
                CAnimation.tAnimated[iAnimationID].iColor = iColor
                CAnimation.tAnimated[iAnimationID].iBright = tConfig.Bright
            end
        end

        iStartX = iStartX -1
        iStartY = iStartY -1
        iSize = iSize + 2

        return CAnimation.iAnimationDelay
    end)
end

CAnimation.Death = function(iStartX, iStartY, iSize, iColor)
    if iStartX == nil or iStartY == nil or iSize == nil or iColor == nil then return; end

    for iX = iStartX, iStartX + iSize-1 do
        for iY = iStartY, iStartY + iSize-1 do
            local iAnimationID = #CAnimation.tAnimated+1
            CAnimation.tAnimated[iAnimationID] = CHelp.ShallowCopy(CAnimation.tAnimatedStruct)
            CAnimation.tAnimated[iAnimationID].iX = iX
            CAnimation.tAnimated[iAnimationID].iY = iY
            CAnimation.tAnimated[iAnimationID].iColor = iColor
            CAnimation.tAnimated[iAnimationID].iBright = tConfig.Bright-1

            local iIters = 0
            local iXVel = 0
            local iYVel = 0

            if iX < iStartX + math.ceil(iSize/2) then
                iXVel = -1
            else
                iXVel = 1
            end

            if iY < iStartY + math.ceil(iSize/2) then
                iYVel = -1
            else
                iYVel = 1
            end

            CTimer.New(CAnimation.iAnimationDelay, function()
                iIters = iIters + 1

                CAnimation.tAnimated[iAnimationID].iX = CAnimation.tAnimated[iAnimationID].iX + iXVel
                CAnimation.tAnimated[iAnimationID].iY = CAnimation.tAnimated[iAnimationID].iY + iYVel
                CAnimation.tAnimated[iAnimationID].iBright = CAnimation.tAnimated[iAnimationID].iBright - 2

                if iIters < CAnimation.iDeathAnimationIters then
                    return CAnimation.iAnimationDelay
                end

                CAnimation.tAnimated[iAnimationID] = nil
                return nil
            end)          
        end
    end
end
--//

--Paint
CPaint = {}

CPaint.Objects = function()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.Base()
    CPaint.Units()
    CPaint.Projectiles()
    CPaint.Animations()
end

CPaint.Base = function()
    for iX = CGameMode.tBase.iX, CGameMode.tBase.iX + CGameMode.tBase.iSize-1 do
        for iY = CGameMode.tBase.iY, CGameMode.tBase.iY + CGameMode.tBase.iSize-1 do
            tFloor[iX][iY].iColor = CGameMode.tBase.iColor
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end

CPaint.Units = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            if CUnits.tUnits[iUnitID].tShadow ~= nil and CUnits.tUnits[iUnitID].tShadow.iX ~= nil then
                CPaint.UnitShadow(iUnitID)
            end

            CPaint.Unit(iUnitID)
        end
    end
end

CPaint.UnitShadow = function(iUnitID)
    if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_SHOOT then return; end

    for iX = CUnits.tUnits[iUnitID].tShadow.iX, CUnits.tUnits[iUnitID].tShadow.iX + CUnits.tUnits[iUnitID].iSize-1 do
        for iY = CUnits.tUnits[iUnitID].tShadow.iY, CUnits.tUnits[iUnitID].tShadow.iY + CUnits.tUnits[iUnitID].iSize-1 do
            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].iColor = CUnits.UNIT_TYPE_TO_COLOR[CUnits.tUnits[iUnitID].iUnitType]
                tFloor[iX][iY].iBright = 1
            end
        end
    end
end

CPaint.Unit = function(iUnitID)
    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.tUnits[iUnitID].iSize-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.tUnits[iUnitID].iSize-1 do

            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].iUnitID = iUnitID
                tFloor[iX][iY].iColor = CUnits.UNIT_TYPE_TO_COLOR[CUnits.tUnits[iUnitID].iUnitType]
                tFloor[iX][iY].iBright = tConfig.Bright

                -- отрисовка катапульты, лютый хардкод
                if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_SHOOT then
                    if CUnits.tUnits[iUnitID].iX < tGame.Cols/2 then
                        if iX >= CUnits.tUnits[iUnitID].iX+1 and iY ~= CUnits.tUnits[iUnitID].iY+1 then
                            tFloor[iX][iY].iColor = CColors.NONE
                        end
                    else
                        if iX <= CUnits.tUnits[iUnitID].iX+1 and iY ~= CUnits.tUnits[iUnitID].iY+1 then
                            tFloor[iX][iY].iColor = CColors.NONE
                        end
                    end
                end
            else
                --CLog.print("Unit #"..iUnitID.." is out of bounds!")
            end
        end
    end
end

CPaint.Projectiles = function()
    for iProjectileID = 1, #CProjectile.tProjectiles do
        if CProjectile.tProjectiles[iProjectileID] then
            local iX = CProjectile.tProjectiles[iProjectileID].iX
            local iY = CProjectile.tProjectiles[iProjectileID].iY

            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].iColor = CColors.RED
                tFloor[iX][iY].iBright = tConfig.Bright
            else
                --CLog.print("Projectile #"..iProjectileID.." is out of bounds!")
            end
        end
    end
end

CPaint.Animations = function()
    for iAnimationID = 1, #CAnimation.tAnimated do
        if CAnimation.tAnimated[iAnimationID] and CAnimation.tAnimated[iAnimationID].iX and CAnimation.tAnimated[iAnimationID].iY then
            local iX = CAnimation.tAnimated[iAnimationID].iX
            local iY = CAnimation.tAnimated[iAnimationID].iY

            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].iColor = CAnimation.tAnimated[iAnimationID].iColor
                tFloor[iX][iY].iBright = CAnimation.tAnimated[iAnimationID].iBright
            end
        end
    end
end
--//

--TIMER класс отвечает за таймеры, очень полезная штука. можно вернуть время нового таймера с тем же колбеком
CTimer = {}
CTimer.tTimers = {}

CTimer.New = function(iSetTime, fCallback)
    CTimer.tTimers[#CTimer.tTimers+1] = {iTime = iSetTime, fCallback = fCallback}
end

-- просчёт таймеров каждый тик
CTimer.CountTimers = function(iTimePassed)
    for i = 1, #CTimer.tTimers do
        if CTimer.tTimers[i] ~= nil then
            CTimer.tTimers[i].iTime = CTimer.tTimers[i].iTime - iTimePassed

            if CTimer.tTimers[i].iTime <= 0 then
                local iNewTime = CTimer.tTimers[i].fCallback()
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
            tFloor[iX][iY].iUnitID = 0
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end

function SetAllButtonsColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end

function Intersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end

function RandomPosInRadius(iX, iY, iSize)
    --CLog.print("RandomPosInRadius "..iX.." "..iY.." "..iSize)
    return math.random(iX, iSize-1), math.random(iY, iSize-1)
end
--//

--//
function GetStats()
    return tGameStats
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if tFloor[click.X][click.Y].iUnitID > 0 and iGameState == GAMESTATE_GAME then
        if CUnits.tUnits[tFloor[click.X][click.Y].iUnitID] then
            CUnits.UnitTakeDamage(tFloor[click.X][click.Y].iUnitID, 1)
        end
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click then
        bAnyButtonClick = true
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end
end
