--[[
    Название: Защита Базы 2
    Автор: Avondale, дискорд - avonda

    Описание механики: 
        Игрокам нужно защитить свою базу от врагов.
        Поле боя в два раза больше чем сама комната, чтобы по нему перемещатся нужно нажимать кнопки на стене, либо использовать геймпад
        Для того чтобы раздавить врага на него нужно наступить несколько раз
        Для победы нужно раздавить всех врагов(количество врагов зависит от уровня сложности).

        База изображена яркими зелеными пикселями. Основа базы в центре карты, но есть небольшие заборчики перед каждым из проходов.
        Когда враг доходит до пикселя базы - он об него самоуничтожается и пиксель пропадает.
        Если все пиксели базы будут уничтожены - игра будет проиграна.

        В помощь игрокам на карте присутствуют союзники, по одному на каждый проход, они также могут наносить урон врагам, но у них ограниченное количество жизней.
        Если союзнику долго не помогать то он погибнет.
        Чтобы лечить союзников нужно собирать бонусы, голубые пиксели которые случайно появляются на карте каждые 50 секунд.

        После того как половина базы или половина союзников уничтожены - игра переходит в режим эндгейма.
        В режиме эндгейма камера перемещается в центр экрана и ей больше нельзя управлять. Игрокам нужно добить остатки врагов или смирится с поражением.

    Идеи по доработке: 
        Больше карт, генерация карт.

        Разные типы врагов? Боссы?
            -насчёт типов врагов неуверен, в прошлой версии игры особые враги отпрыгивали назад и имели несколько жизней, сейчас все враги такие поэтому хз чем выделить особенных врагов, разве что колвом жизней

        Больше разрушений
            -сейчас игра полностью поддерживает динамическое изменение ландшафта, например база уже постепенно уничтожается и открывает проходы между союзниками чтобы они возвращались в центр.
            можно совместить этот пункт с предыдущим чтобы сделать особого юнита/босса, который спавнится в желтой непроходимой местности и начинает её разрушать, создавая новый проход для врагов.

        Постройка укреплений?
            -к прошлому пункту о динамическом изменении ландшафта, можно между волнами врагов давать паузу в которой игроки могут например отстроить новые укрепления там где считают нужным
            например поставить больше стен в проход где союзника больше нет
            но непонятно как определять куда игрок хочет чтото-поставить, а куда нет и просто мимо проходит

]]
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
    ScoreboardVariant = 3,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = CColors.NONE,
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iBlockType = 0,
    iWeight = 0,
    iUnitID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
    bActive = false
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

    tGameResults.PlayersCount = tConfig.PlayerCount

    CGameMode.init()
    CAnnouncer.GameLoad()
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()

        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            CLog.print(CInspect(tGameResults))
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    if bAnyButtonClick then
        CAudio.PlaySyncFromScratch("")
        CGameMode.StartCountDown(5)
        iGameState = GAMESTATE_GAME
    end

    CCamera.DrawWorld()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    
    CCamera.DrawWorld()
    CUnits.PaintUnits()
    
    CCamera.PaintActiveButtons()
end

function PostGameTick()
    if CGameMode.bVictory then
        SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)
    else
        SetAllButtonColorBright(CColors.RED, tConfig.Bright)
    end
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
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
CGameMode.iCountdown = 0
CGameMode.bVictory = false
CGameMode.iDifficulty = 1

CGameMode.DIFFICULTY_TARGET_SCORE = {}
CGameMode.DIFFICULTY_TARGET_SCORE[1] = 100
CGameMode.DIFFICULTY_TARGET_SCORE[2] = 150
CGameMode.DIFFICULTY_TARGET_SCORE[3] = 200
CGameMode.DIFFICULTY_TARGET_SCORE[4] = 250

CGameMode.DIFFICULTY_UNIT_THINK_DELAY = {}
CGameMode.DIFFICULTY_UNIT_THINK_DELAY[1] = 400
CGameMode.DIFFICULTY_UNIT_THINK_DELAY[2] = 350
CGameMode.DIFFICULTY_UNIT_THINK_DELAY[3] = 300
CGameMode.DIFFICULTY_UNIT_THINK_DELAY[4] = 250

CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY = {}
CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[1] = 2000
CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[2] = 1750
CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[3] = 1500
CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[4] = 1250

CGameMode.init = function()
    CGameMode.iDifficulty = tConfig.Difficulty
    tGameStats.TotalStars = CGameMode.DIFFICULTY_TARGET_SCORE[CGameMode.iDifficulty]

    CWorld.init()
    CCamera.init()
    CPath.init()
    CAnnouncer.init()

    CWorld.Load(tGame.Maps[1])
end

CGameMode.StartCountDown = function(iCountDownTime)
    CCamera.MoveToView(CCamera.VIEW_TOP_LEFT)

    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    --CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    AL.NewTimer(CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[CGameMode.iDifficulty], function()
        if iGameState ~= GAMESTATE_GAME then return nil end

        if CUnits.iAliveUnitCount < CUnits.MAX_UNIT_COUNT then
            local iSpawnerId = math.random(1, #CWorld.tEnemySpawners)
            CUnits.AddNewUnit(CWorld.tEnemySpawners[iSpawnerId].iX, CWorld.tEnemySpawners[iSpawnerId].iY, CUnits.UNIT_TYPE_ENEMY, iSpawnerId)
        end

        return CGameMode.DIFFICULTY_ENEMY_SPAWN_DELAY[CGameMode.iDifficulty]
    end)

    AL.NewTimer(CGameMode.DIFFICULTY_UNIT_THINK_DELAY[CGameMode.iDifficulty], function()
        if iGameState ~= GAMESTATE_GAME then return nil end
        CUnits.Think()

        return CGameMode.DIFFICULTY_UNIT_THINK_DELAY[CGameMode.iDifficulty] 
    end)

    local iAnnouncerWarnTime = 0
    local iBonusTime = 0
    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration + 1

        iAnnouncerWarnTime = iAnnouncerWarnTime + 1
        if iAnnouncerWarnTime == 15 then 
            iAnnouncerWarnTime = 0
            CAnnouncer.CountEnemiesAndWarn()
        end

        iBonusTime = iBonusTime + 1
        if iBonusTime == 50 then
            iBonusTime = 0
            CGameMode.DropBonus()
        end

        if iGameState == GAMESTATE_GAME then return 1000 end
        return nil
    end)

    --PAD TIMER
    AL.NewTimer(100, function()
        if CPad.LastInteractionTime ~= -1 and not CWorld.bEndGame then
            if CPad.AFK() then
                if CCamera.bFreeView then
                    CCamera.MoveToView(CCamera.VIEW_TOP_LEFT)
                end
                CCamera.bFreeView = false
            else
                if not CCamera.bFreeView then
                    CCamera.DeactivateAllButtons()
                end
                CCamera.bFreeView = true
                
                if CPad.bTrigger then
                    CCamera.AnimateMovementTo(CCamera.VIEW_X[CCamera.VIEW_CENTER], CCamera.VIEW_Y[CCamera.VIEW_CENTER], function() end)
                else

                    CCamera.iX = CCamera.iX + CPad.iXPlus
                    CCamera.iY = CCamera.iY + CPad.iYPlus
                end
            end
        end

        if iGameState == GAMESTATE_GAME and not CWorld.bEndGame then return 100 end
        return nil
    end)
    ----
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    CAudio.StopBackground()
    CAudio.PlaySyncFromScratch("")
    iGameState = GAMESTATE_POSTGAME

    if bVictory then
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
        CAudio.PlayVoicesSync("tower-defence2/td2_victory.mp3")
        tGameResults.Color = CColors.GREEN
        tGameResults.Score = tGameResults.Score + (10000 * CGameMode.iDifficulty)
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync("tower-defence2/td2_defeat.mp3")
        tGameResults.Color = CColors.RED
    end

    tGameResults.Won = bVictory

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)

    local iY = 1
    AL.NewTimer(tConfig.AnimationDelay*2, function()
        for iX = 1, tGame.Cols do
            if bVictory then
                tFloor[iX][iY].iColor = CColors.GREEN
            else
                tFloor[iX][iY].iColor = CColors.RED
            end

            tFloor[iX][iY].iBright = tConfig.Bright
        end

        iY = iY + 1
        if iY > tGame.Rows then return nil end

        return tConfig.AnimationDelay*2
    end)
end

CGameMode.DropBonus = function()
    if CWorld.bEndGame then return; end

    local iX = 0
    local iY = 0
    while(not CWorld.tBlocks[iX] or not CWorld.tBlocks[iX][iY] or CWorld.tBlocks[iX][iY].iBlockType ~= CWorld.BLOCK_TYPE_EMPTY) do
        iX = math.random(1, CWorld.iSizeX)
        iY = math.random(1, CWorld.iSizeY)
    end

    CWorld.tBlocks[iX][iY].iBlockType = CWorld.BLOCK_TYPE_BONUS
    CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_BONUS, iX, iY)
end

CGameMode.PlayerTakeBonus = function(iX, iY)
    CAudio.PlaySystemSync(CAudio.CLICK)
    CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_HEAL)

    if CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_BONUS then
        CWorld.tBlocks[iX][iY].iBlockType = CWorld.BLOCK_TYPE_EMPTY

        tGameResults.Score = tGameResults.Score + 500

        for iUnitID = 1, #CUnits.tUnits do
            if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive and CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
                CUnits.tUnits[iUnitID].iHealth = CUnits.tUnits[iUnitID].iHealth + math.random(8,18)
            end
        end
    end
end
--//

--ANNOUNCER
CAnnouncer = {}

CAnnouncer.EVENT_ENDGAME = 11
CAnnouncer[CAnnouncer.EVENT_ENDGAME] = {}
CAnnouncer[CAnnouncer.EVENT_ENDGAME].sSound = "td2_event_endgame.mp3"
CAnnouncer[CAnnouncer.EVENT_ENDGAME].bAnnounceOnOutsideView = false

CAnnouncer.EVENT_ALLY_DEATH = 22
CAnnouncer[CAnnouncer.EVENT_ALLY_DEATH] = {}
CAnnouncer[CAnnouncer.EVENT_ALLY_DEATH].sSound = "td2_event_ally_death.mp3"
CAnnouncer[CAnnouncer.EVENT_ALLY_DEATH].bAnnounceOnOutsideView = true

CAnnouncer.EVENT_STRUCTURE_DESTROYED = 33
CAnnouncer[CAnnouncer.EVENT_STRUCTURE_DESTROYED] = {}
CAnnouncer[CAnnouncer.EVENT_STRUCTURE_DESTROYED].sSound = "td2_event_structure_destroyed.mp3"
CAnnouncer[CAnnouncer.EVENT_STRUCTURE_DESTROYED].bAnnounceOnOutsideView = true

CAnnouncer.EVENT_UNIT_COUNT_WARNING = 44
CAnnouncer[CAnnouncer.EVENT_UNIT_COUNT_WARNING] = {}
CAnnouncer[CAnnouncer.EVENT_UNIT_COUNT_WARNING].sSound = "td2_event_lotsofenemies.mp3"
CAnnouncer[CAnnouncer.EVENT_UNIT_COUNT_WARNING].bAnnounceOnOutsideView = true

CAnnouncer.EVENT_BONUS = 55
CAnnouncer[CAnnouncer.EVENT_BONUS] = {}
CAnnouncer[CAnnouncer.EVENT_BONUS].sSound = "td2_event_bonus.mp3"
CAnnouncer[CAnnouncer.EVENT_BONUS].bAnnounceOnOutsideView = true

CAnnouncer.EVENT_HEAL = 66
CAnnouncer[CAnnouncer.EVENT_HEAL] = {}
CAnnouncer[CAnnouncer.EVENT_HEAL].sSound = "td2_event_heal_allies.mp3"
CAnnouncer[CAnnouncer.EVENT_HEAL].bAnnounceOnOutsideView = false

CAnnouncer.init = function()

end

CAnnouncer.AnnounceEvent = function(iEventID, iX, iY)
    if not CWorld.bEndGame and CAnnouncer[iEventID].bAnnounceOnOutsideView and iX and iY then
        local iView = CCamera.WorldPosToView(iX, iY)

        if iView > 0 and (CCamera.bFreeView or iView ~= CCamera.iCurrentView) then
            CAudio.PlayVoicesSync("tower-defence2/td2_view_"..iView..".mp3")
        end
    end

    CAudio.PlayVoicesSync("tower-defence2/"..CAnnouncer[iEventID].sSound)
end

CAnnouncer.PlaySoundAtPosition = function(sSoundName, iX, iY)
    if CWorld.bEndGame or CCamera.bFreeView or CCamera.WorldPosToView(iX, iY) == CCamera.iCurrentView then
        CAudio.PlaySystemAsync("tower-defence2/"..sSoundName)
    end  
end

CAnnouncer.GameLoad = function()
    CAudio.PlayVoicesSync("tower-defence2/td2_gamename.mp3")
    CAudio.PlayVoicesSync("tower-defence2/td2_difficulty_"..CGameMode.iDifficulty..".mp3")
    CAudio.PlayVoicesSync("tower-defence2/td2_guide.mp3")
end

CAnnouncer.CountEnemiesAndWarn = function()
    if CWorld.bEndGame or CUnits.iAliveUnitCount < 10 then return; end

    local tViewCount = {}
    tViewCount[CCamera.VIEW_TOP_LEFT] = 0
    tViewCount[CCamera.VIEW_TOP_RIGHT] = 0
    tViewCount[CCamera.VIEW_BOTTOM_LEFT] = 0
    tViewCount[CCamera.VIEW_BOTTOM_RIGHT] = 0

    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive and CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ENEMY then
            local iView = CCamera.WorldPosToView(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY)
            if iView > 0 then
                tViewCount[iView] = tViewCount[iView] + 1
            end
        end
    end

    local iMaxCount = 2
    local iMaxCountView = 0
    for iView = CCamera.VIEW_TOP_LEFT, CCamera.VIEW_BOTTOM_RIGHT do
        if tViewCount[iView] > iMaxCount then
            iMaxCount = tViewCount[iView]
            iMaxCountView = iView
        end
    end

    if iMaxCountView > 0 and (CCamera.bFreeView or iMaxCountView ~= CCamera.iCurrentView) then
        CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_UNIT_COUNT_WARNING, CCamera.VIEW_X[iMaxCountView], CCamera.VIEW_Y[iMaxCountView])
    end
end
--//

--UNITS
CUnits = {}
CUnits.tUnits = {}

CUnits.UNIT_TYPE_ENEMY = 1
CUnits.UNIT_TYPE_ALLY = 2
CUnits.UNIT_TYPE_NEUTRAL = 3

CUnits.ENEMY_CLASS_NONE = 0
CUnits.ENEMY_CLASS_BASIC = 1
CUnits.ENEMY_CLASS_BLINK = 2
CUnits.ENEMY_CLASS_SLIME = 3

CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER = 1
CUnits.UNIT_DEATH_REASON_KILLED_BY_UNIT = 2
CUnits.UNIT_DEATH_REASON_DESTROYED_STRUCTURE = 3

CUnits.UNIT_TYPE_TO_COLOR = {}
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_ENEMY] = CColors.RED
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_ALLY] = CColors.GREEN
CUnits.UNIT_TYPE_TO_COLOR[CUnits.UNIT_TYPE_NEUTRAL] = CColors.WHITE

CUnits.UNIT_TYPE_SIZE = {}
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_ENEMY] = 2
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_ALLY] = 2
CUnits.UNIT_TYPE_SIZE[CUnits.UNIT_TYPE_NEUTRAL] = 3

CUnits.UNIT_TYPE_MIN_SPAWN_HEALTH = {}
CUnits.UNIT_TYPE_MIN_SPAWN_HEALTH[CUnits.UNIT_TYPE_ENEMY] = 3
CUnits.UNIT_TYPE_MIN_SPAWN_HEALTH[CUnits.UNIT_TYPE_ALLY] = 50
CUnits.UNIT_TYPE_MIN_SPAWN_HEALTH[CUnits.UNIT_TYPE_NEUTRAL] = 10

CUnits.UNIT_TYPE_MAX_SPAWN_HEALTH = {}
CUnits.UNIT_TYPE_MAX_SPAWN_HEALTH[CUnits.UNIT_TYPE_ENEMY] = 15
CUnits.UNIT_TYPE_MAX_SPAWN_HEALTH[CUnits.UNIT_TYPE_ALLY] = 100
CUnits.UNIT_TYPE_MAX_SPAWN_HEALTH[CUnits.UNIT_TYPE_NEUTRAL] = 30

CUnits.MAX_UNIT_COUNT = 32

CUnits.iAliveUnitCount = 0
CUnits.iAliveAlliesCount = 0
CUnits.iTotalAlliesCount = 0

CUnits.AddNewUnit = function(iX, iY, iUnitType, iSpawnerId)
    local iUnitID = #CUnits.tUnits+1
    CUnits.tUnits[iUnitID] = {}
    CUnits.tUnits[iUnitID].iX = iX
    CUnits.tUnits[iUnitID].iY = iY
    CUnits.tUnits[iUnitID].iStartX = iX
    CUnits.tUnits[iUnitID].iStartY = iY
    CUnits.tUnits[iUnitID].bVisible = true

    CUnits.tUnits[iUnitID].iUnitType = iUnitType
    CUnits.tUnits[iUnitID].iEnemyClass = CUnits.ENEMY_CLASS_NONE
    if iUnitType == CUnits.UNIT_TYPE_ENEMY then
        CUnits.tUnits[iUnitID].iEnemyClass = CUnits.ENEMY_CLASS_BASIC
    elseif iUnitType == CUnits.UNIT_TYPE_ALLY then
        CUnits.iAliveAlliesCount = CUnits.iAliveAlliesCount + 1
        CUnits.iTotalAlliesCount = CUnits.iTotalAlliesCount + 1
    end

    CUnits.tUnits[iUnitID].iSize = CUnits.UNIT_TYPE_SIZE[iUnitType]

    CUnits.tUnits[iUnitID].iMinDamage = 1
    CUnits.tUnits[iUnitID].iMaxDamage = 2

    CUnits.tUnits[iUnitID].iSpawnerId = iSpawnerId or 0

    CUnits.tUnits[iUnitID].iHealth = math.random(CUnits.UNIT_TYPE_MIN_SPAWN_HEALTH[iUnitType], CUnits.UNIT_TYPE_MAX_SPAWN_HEALTH[iUnitType])
    CUnits.tUnits[iUnitID].bRecieveDamageCooldown = false
    CUnits.tUnits[iUnitID].bAlive = true

    CUnits.tUnits[iUnitID].bCanMove = true

    CUnits.tUnits[iUnitID].iCantFindPathFor = 0

    CDebug.Print("Unit #"..iUnitID.." spawned at X: "..iX.." Y: "..iY)
    CUnits.iAliveUnitCount = CUnits.iAliveUnitCount + 1

    return iUnitID
end

CUnits.Think = function()
    if CWorld.bPlayerActionsPaused then return; end

    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive then
            CUnits.UnitThink(iUnitID)
        end
    end
end

CUnits.UnitThink = function(iUnitID)
    if CUnits.tUnits[iUnitID].bCanMove then
        CUnits.CalculateNextMove(iUnitID)
    else
        CUnits.tUnits[iUnitID].tPath = nil
    end

    if not CUnits.tUnits[iUnitID].bRecieveDamageCooldown and CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_ALLY then
        CUnits.UnitCalculateCollision(iUnitID)
    end
end

CUnits.CalculateNextMove = function(iUnitID)
    if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ENEMY then
        CUnits.CalculateNextMoveEnemy(iUnitID)
    elseif CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
        CUnits.CalculateNextMoveAlly(iUnitID)
    end
end

CUnits.CalculateNextMoveEnemy = function(iUnitID)
    local iTargetStructId = CWorld.tEnemySpawners[CUnits.tUnits[iUnitID].iSpawnerId].iTargetStructId
    if CWorld.tStructureBlocks[iTargetStructId] == nil then
        iTargetStructId = CWorld.FindTargetStructureForSpawner(CUnits.tUnits[iUnitID].iSpawnerId)
    end

    local iX, iY = CUnits.GetPos(iUnitID)

    if CUnits.tUnits[iUnitID].tPath == nil or CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep] == nil then
        CUnits.tUnits[iUnitID].tPath = CPath.Path(CUnits.tUnits[iUnitID].iSize, iX, iY, CWorld.tStructureBlocks[iTargetStructId].iX, CWorld.tStructureBlocks[iTargetStructId].iY, CWorld.tBlockList, false, false)
        CUnits.tUnits[iUnitID].iStep = 1
    end

    if CUnits.tUnits[iUnitID].tPath ~= nil and CUnits.Move(iUnitID, CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep].iX, CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep].iY) then
        CUnits.tUnits[iUnitID].iStep = CUnits.tUnits[iUnitID].iStep + 1

        if CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep] == nil then
            CUnits.tUnits[iUnitID].tPath = nil
        end

        CUnits.tUnits[iUnitID].iCantFindPathFor = 0
    else
        CUnits.tUnits[iUnitID].iCantFindPathFor = CUnits.tUnits[iUnitID].iCantFindPathFor + 1
        if CUnits.tUnits[iUnitID].iCantFindPathFor == 10 then
            CUnits.tUnits[iUnitID].tPath = CPath.Path(CUnits.tUnits[iUnitID].iSize, iX, iY, CWorld.tStructureBlocks[iTargetStructId].iX, CWorld.tStructureBlocks[iTargetStructId].iY, CWorld.tBlockList, false, false)
        end
    end
end

CUnits.CalculateNextMoveAlly = function(iUnitID)
    if CUnits.tUnits[iUnitID].tPath == nil then
        if CUnits.tUnits[iUnitID].iTargetEnemyID == nil or CUnits.tUnits[iUnitID].iTargetEnemyID == 0 or CUnits.tUnits[CUnits.tUnits[iUnitID].iTargetEnemyID] == nil then
            CUnits.FindTargetForAlly(iUnitID)
        end

        if CUnits.tUnits[iUnitID].iTargetEnemyID ~= nil and CUnits.tUnits[iUnitID].iTargetEnemyID > 0 then
            CUnits.tUnits[iUnitID].tPath = CPath.Path(CUnits.tUnits[iUnitID].iSize, CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, 
               CUnits.tUnits[CUnits.tUnits[iUnitID].iTargetEnemyID].iX, CUnits.tUnits[CUnits.tUnits[iUnitID].iTargetEnemyID].iY, CWorld.tBlockList, false, true)
            CUnits.tUnits[iUnitID].iStep = 1
        end
    end

    if CUnits.tUnits[iUnitID].tPath ~= nil and CUnits.Move(iUnitID, CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep].iX, CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep].iY) then
        CUnits.tUnits[iUnitID].iStep = CUnits.tUnits[iUnitID].iStep + 1

        if CUnits.tUnits[iUnitID].tPath[CUnits.tUnits[iUnitID].iStep] == nil then
            CUnits.tUnits[iUnitID].tPath = nil
        end
    end    
end

CUnits.FindTargetForAlly = function(iUnitID)
    local iX, iY = CUnits.GetPos(iUnitID)  
    local iMinDist = 5
    local iTargetEnemyID = 0

    for iEnemyID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iEnemyID] and CUnits.tUnits[iEnemyID].iUnitType == CUnits.UNIT_TYPE_ENEMY and CUnits.tUnits[iEnemyID].bAlive then
            local iDist = CWorld.DistanceBetweenTwoPoints(iX, iY, CUnits.tUnits[iEnemyID].iX, CUnits.tUnits[iEnemyID].iY)
            if iDist < iMinDist then
                iMinDist = iDist
                iTargetEnemyID = iEnemyID
            end
        end
    end  

    CUnits.tUnits[iUnitID].iTargetEnemyID = iTargetEnemyID
    return iTargetEnemyID
end

CUnits.AllyRetreat = function(iUnitID)
    CUnits.tUnits[iUnitID].tPath = CPath.Path(CUnits.tUnits[iUnitID].iSize, CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, 
               CUnits.tUnits[iUnitID].iStartX, CUnits.tUnits[iUnitID].iStartY, CWorld.tBlockList, false, true)
    CUnits.tUnits[iUnitID].iStep = 1
end

CUnits.Move = function(iUnitID, iX, iY)
    if CWorld.IsValidPositionForUnit(iX, iY, CUnits.tUnits[iUnitID].iSize) then
        CUnits.tUnits[iUnitID].iX = iX
        CUnits.tUnits[iUnitID].iY = iY

        for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX+CUnits.tUnits[iUnitID].iSize-1 do
            for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY+CUnits.tUnits[iUnitID].iSize-1 do
                if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then
                    if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
                        CWorld.tBlocks[iX][iY].iAllyID = iUnitID
                    else
                        CWorld.tBlocks[iX][iY].iUnitID = iUnitID
                    end
                end
            end
        end

        return true
    end

    return false 
end

CUnits.UnitCalculateCollision = function(iUnitID)
    local bOnCamera = CCamera.IsPosOnCamera(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize)

    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.tUnits[iUnitID].iSize-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.tUnits[iUnitID].iSize-1 do
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then

                ----PLAYER COLLISION
                if bOnCamera and CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_ALLY then
                    local iCamX, iCamY = CCamera.WorldPosToCamPos(iX, iY)
                    if CCamera.IsValidCamPos(iCamX, iCamY) then
                        if tFloor[iCamX][iCamY].bClick and tFloor[iCamX][iCamY].iWeight > 10 then
                            CUnits.PlayerAttackUnit(iUnitID)
                            return;
                        end
                    end
                end
                ----

                ----ALLY COLLISION
                local iAllyID = CWorld.tBlocks[iX][iY].iAllyID
                if iAllyID > 0 then
                    if CUnits.tUnits[iAllyID] and CUnits.tUnits[iAllyID].bAlive then
                        if RectIntersects(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize,
                        CUnits.tUnits[iAllyID].iX, CUnits.tUnits[iAllyID].iY, CUnits.tUnits[iAllyID].iSize) then
                            CUnits.AllyAttackUnit(iAllyID, iUnitID)
                            return;
                        else
                            CWorld.tBlocks[iX][iY].iAllyID = 0   
                        end
                    end
                end
                ----

                ----STRUCTURE COLLISION
                if CWorld.tBlocks[iX][iY].iStructId ~= nil then
                    CWorld.DestroyStructure(iX, iY)
                    CUnits.UnitKilled(iUnitID, CUnits.UNIT_DEATH_REASON_DESTROYED_STRUCTURE)
                    return;
                end
                ----
            end
        end
    end
end

CUnits.GetPos = function(iUnitID)
    return CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY
end

CUnits.PlayerAttackUnit = function(iUnitID)
    CDebug.Print("Player Attack Unit #"..iUnitID)

    if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive and CUnits.tUnits[iUnitID].iUnitType ~= CUnits.UNIT_TYPE_ALLY then
       CUnits.DamageUnit(iUnitID, 1, CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER)
       CUnits.StunUnit(iUnitID, math.random(0.1, 2))
    end
end

CUnits.AllyAttackUnit = function(iAllyID, iUnitID)
    CUnits.DamageUnit(iUnitID, math.random(CUnits.tUnits[iAllyID].iMinDamage, CUnits.tUnits[iAllyID].iMaxDamage), CUnits.UNIT_DEATH_REASON_KILLED_BY_UNIT)
    CUnits.DamageUnit(iAllyID, math.random(CUnits.tUnits[iUnitID].iMinDamage, CUnits.tUnits[iUnitID].iMaxDamage), CUnits.UNIT_DEATH_REASON_KILLED_BY_UNIT)

    CUnits.StunUnit(iUnitID, math.random(1, 2))

    local iPlusX = 0
    local iPlusY = 0
    if CUnits.tUnits[iAllyID].iX > CUnits.tUnits[iUnitID].iX then iPlusX = -1 end
    if CUnits.tUnits[iAllyID].iX < CUnits.tUnits[iUnitID].iX then iPlusX = 1 end
    if CUnits.tUnits[iAllyID].iY > CUnits.tUnits[iUnitID].iY then iPlusY = -1 end
    if CUnits.tUnits[iAllyID].iY < CUnits.tUnits[iUnitID].iY then iPlusY = 1 end
    CUnits.BounceUnit(iUnitID, iPlusX, iPlusY)

    CUnits.AllyRetreat(iAllyID)
end

CUnits.DamageUnit = function(iUnitID, iDamage, iPossibleDeathReason)
    if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive and not CUnits.tUnits[iUnitID].bRecieveDamageCooldown then
        CUnits.tUnits[iUnitID].iHealth = CUnits.tUnits[iUnitID].iHealth - iDamage

        if iPossibleDeathReason == CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER then
            tGameResults.Score = tGameResults.Score + 100
        else
            tGameResults.Score = tGameResults.Score + 25
        end

        if CUnits.tUnits[iUnitID].iHealth <= 0 then
            CUnits.UnitKilled(iUnitID, iPossibleDeathReason)
        else
            CAnnouncer.PlaySoundAtPosition("td2_punch.mp3", CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY)

            CUnits.tUnits[iUnitID].bRecieveDamageCooldown = true
            AL.NewTimer(300, function()
                CUnits.tUnits[iUnitID].bRecieveDamageCooldown = false
            end)
        end
    end
end

CUnits.StunUnit = function(iUnitID, iDuration)
    if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bAlive and CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bCanMove then
        CUnits.tUnits[iUnitID].bCanMove = false

        if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
            iDuration = iDuration * 0.25
        end

        AL.NewTimer(iDuration*1000, function()
            if CUnits.tUnits[iUnitID] then
                CUnits.tUnits[iUnitID].bCanMove = true
            end
        end)
    end
end

CUnits.BounceUnit = function(iUnitID, iVelX, iVelY)
    local iDistance = 0

    AL.NewTimer(tConfig.AnimationDelay, function()
        if iDistance > 3 or not CUnits.tUnits[iUnitID] or CUnits.tUnits[iUnitID].bCanMove then return nil end

        if iDistance == 2 then
            CAnnouncer.PlaySoundAtPosition("td2_woosh.mp3", CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY)
        end

        local iDistanceIncrease = 0
        if iVelX ~= 0 and CWorld.IsValidPositionForUnit(CUnits.tUnits[iUnitID].iX + iVelX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize) and CUnits.tUnits[iUnitID].iX + iVelX > 0 and CUnits.tUnits[iUnitID].iX + iVelX < tGame.Cols then
            CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iVelX
            iDistanceIncrease = 1
        end
        if iVelY ~= 0 and CWorld.IsValidPositionForUnit(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY + iVelY, CUnits.tUnits[iUnitID].iSize) and CUnits.tUnits[iUnitID].iY + iVelX > 0 and CUnits.tUnits[iUnitID].iY + iVelY < tGame.Rows then
            CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iVelY
            iDistanceIncrease = iDistanceIncrease + 1
        end        
        if iDistanceIncrease == 0 then return nil end

        iDistance = iDistance + 1
        return tConfig.AnimationDelay
    end)
end

CUnits.UnitKilled = function(iUnitID, iUnitDeathReason)
    CUnits.tUnits[iUnitID].iHealth = 0
    CUnits.tUnits[iUnitID].bAlive = false
    CUnits.tUnits[iUnitID].bVisible = false

    if CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ENEMY then
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1
        if tGameStats.CurrentStars == tGameStats.TotalStars then
            CGameMode.EndGame(true)
        end

        tGameResults.Score = tGameResults.Score + (tGameStats.CurrentLives*3)

        if iUnitDeathReason == CUnits.UNIT_DEATH_REASON_KILLED_BY_PLAYER or iUnitDeathReason == CUnits.UNIT_DEATH_REASON_KILLED_BY_UNIT then
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    elseif CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
        CUnits.iAliveAlliesCount = CUnits.iAliveAlliesCount - 1

        tGameResults.Score = tGameResults.Score - 1000

        CAudio.PlaySystemAsync(CAudio.MISCLICK)
        CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_ALLY_DEATH, CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY)
        if not CWorld.bEndGame then
            if CUnits.iAliveAlliesCount < CUnits.iTotalAlliesCount/2 then
                CWorld.BeginEndGameStage()
            end
        end
    end

    CUnits.iAliveUnitCount = CUnits.iAliveUnitCount - 1

    AL.NewTimer(100, function()
        CUnits.tUnits[iUnitID] = nil
    end)
end

CUnits.PaintUnits = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].bVisible then
           CUnits.PaintUnit(iUnitID) 
        end
    end
end

CUnits.PaintUnit = function(iUnitID)
    if not CCamera.IsPosOnCamera(CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iSize) then return; end

    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.tUnits[iUnitID].iSize-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.tUnits[iUnitID].iSize-1 do
            local iCamX, iCamY = CCamera.WorldPosToCamPos(iX, iY)

            if tFloor[iCamX] and tFloor[iCamX][iCamY] then
                tFloor[iCamX][iCamY].iColor = CUnits.UNIT_TYPE_TO_COLOR[CUnits.tUnits[iUnitID].iUnitType]
                tFloor[iCamX][iCamY].iBright = tConfig.Bright
                tFloor[iCamX][iCamY].iUnitID = iUnitID

                if CUnits.tUnits[iUnitID].bRecieveDamageCooldown then
                    tFloor[iCamX][iCamY].iBright = tConfig.Bright-2
                end
            end
        end
    end
end
--//

--WORLD
CWorld = {}

CWorld.BLOCK_TYPE_EMPTY = 1
CWorld.BLOCK_TYPE_TERRAIN = 2
CWorld.BLOCK_TYPE_STRUCTURE = 3
CWorld.BLOCK_TYPE_BONUS = 4
CWorld.BLOCK_TYPE_ENEMY_SPAWN = 5
CWorld.BLOCK_TYPE_ALLY_SPAWN = 6

CWorld.BLOCK_TYPE_TO_COLOR = {}
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_EMPTY] = CColors.NONE
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_TERRAIN] = CColors.YELLOW
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_STRUCTURE] = CColors.GREEN
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_BONUS] = CColors.CYAN
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_ENEMY_SPAWN] = CColors.NONE
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_ALLY_SPAWN] = CColors.NONE

CWorld.tBlocks = {}
CWorld.tBlockList = {}
CWorld.tEnemySpawners = {}
CWorld.tStructureBlocks = {}

CWorld.iSizeX = 0
CWorld.iSizeY = 0

CWorld.bPlayerActionsPaused = false
CWorld.bEndGame = false

CWorld.init = function()
    CWorld.iSizeX = tGame.Cols*2
    CWorld.iSizeY = tGame.Rows*2
end

CWorld.DistanceBetweenTwoPoints = function(iX1, iY1, iX2, iY2)
    return math.abs(iX1-iX2) + math.abs(iY1-iY2)
end

CWorld.Load = function(tMap)
    for iY = 1, CWorld.iSizeY do
        for iX = 1, CWorld.iSizeX do
            if tMap[iY] and tMap[iY][iX] then
                CWorld.SetBlock(iX, iY, tMap[iY][iX])
            end
        end
    end

    for iSpawnerId = 1, #CWorld.tEnemySpawners do
        CWorld.FindTargetStructureForSpawner(iSpawnerId)
    end
end

CWorld.SetBlock = function(iX, iY, iBlockType)
    if CWorld.tBlocks[iX] == nil then CWorld.tBlocks[iX] = {} end

    CWorld.tBlocks[iX][iY] = {}
    CWorld.tBlocks[iX][iY].iBlockType = iBlockType

    CWorld.tBlocks[iX][iY].iBlockId = #CWorld.tBlockList+1
    CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId] = {}
    CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId].iX = iX
    CWorld.tBlockList[CWorld.tBlocks[iX][iY].iBlockId].iY = iY

    CWorld.tBlocks[iX][iY].iUnitID = 0
    CWorld.tBlocks[iX][iY].iAllyID = 0

    if iBlockType == CWorld.BLOCK_TYPE_ENEMY_SPAWN then
        local iSpawnerId = #CWorld.tEnemySpawners+1
        CWorld.tEnemySpawners[iSpawnerId] = {}
        CWorld.tEnemySpawners[iSpawnerId].iX = iX
        CWorld.tEnemySpawners[iSpawnerId].iY = iY
    end

    if iBlockType == CWorld.BLOCK_TYPE_ALLY_SPAWN then
        CUnits.Move(CUnits.AddNewUnit(iX, iY, CUnits.UNIT_TYPE_ALLY), iX, iY) 
    end

    if iBlockType == CWorld.BLOCK_TYPE_STRUCTURE then
        tGameStats.TotalLives = tGameStats.TotalLives + 1
        tGameStats.CurrentLives = tGameStats.CurrentLives + 1

        local iStructId = #CWorld.tStructureBlocks+1
        CWorld.tStructureBlocks[iStructId] = {}
        CWorld.tStructureBlocks[iStructId].iX = iX
        CWorld.tStructureBlocks[iStructId].iY = iY

        CWorld.tBlocks[iX][iY].iStructId = iStructId
    end    
end

CWorld.IsValidPositionForUnit = function(iUnitX, iUnitY, iSize)
    for iX = iUnitX, iUnitX+iSize-1 do
        for iY = iUnitY, iUnitY+iSize-1 do
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then
                if CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_TERRAIN then return false end
            end
        end
    end

    return true
end

CWorld.FindTargetStructureForSpawner = function(iSpawnerId)
    local iMinDist = 999
    local iTargetStructId = 1

    for iStructId = 1, #CWorld.tStructureBlocks do
        if CWorld.tStructureBlocks[iStructId] and CWorld.IsValidPositionForUnit(CWorld.tStructureBlocks[iStructId].iX, CWorld.tStructureBlocks[iStructId].iY, 2) then
            local iDist = CWorld.DistanceBetweenTwoPoints(CWorld.tStructureBlocks[iStructId].iX, CWorld.tStructureBlocks[iStructId].iY, CWorld.tEnemySpawners[iSpawnerId].iX, CWorld.tEnemySpawners[iSpawnerId].iY)
            if iDist < iMinDist then
                iMinDist = iDist
                iTargetStructId = iStructId
            end
        end
    end

    CWorld.tEnemySpawners[iSpawnerId].iTargetStructId = iTargetStructId
    return iTargetStructId
end

CWorld.DestroyStructure = function(iX, iY)
    tGameStats.CurrentLives = tGameStats.CurrentLives - 1

    tGameResults.Score = tGameResults.Score - 250

    if not CWorld.bEndGame and tGameStats.CurrentLives < tGameStats.TotalLives/2 then
        CWorld.BeginEndGameStage()
    end

    if tGameStats.CurrentLives == 0 then
        CGameMode.EndGame(false)
    else
        CAudio.PlaySystemSync(CAudio.MISCLICK)
        CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_STRUCTURE_DESTROYED, iX, iY)
    end

    CWorld.tBlocks[iX][iY].iBlockType = CWorld.BLOCK_TYPE_EMPTY

    CWorld.tStructureBlocks[CWorld.tBlocks[iX][iY].iStructId] = nil
    CWorld.tBlocks[iX][iY].iStructId = nil
end

CWorld.BeginEndGameStage = function()
    CWorld.bEndGame = true
    
    CAnnouncer.AnnounceEvent(CAnnouncer.EVENT_ENDGAME)

    CCamera.DeactivateAllButtons()
    CCamera.AnimateMovementTo(CCamera.VIEW_X[CCamera.VIEW_CENTER], CCamera.VIEW_Y[CCamera.VIEW_CENTER], function()
        CWorld.bPlayerActionsPaused = true
        AL.NewTimer(1500, function()
            CWorld.bPlayerActionsPaused = false
        end)
    end)

    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].iUnitType == CUnits.UNIT_TYPE_ALLY then
            CUnits.tUnits[iUnitID].iStartX = CWorld.iSizeX/2
            CUnits.tUnits[iUnitID].iStartY = CWorld.iSizeY/2
        end
    end
end
--//

--CAMERA
CCamera = {}
CCamera.iX = 1
CCamera.iY = 1
CCamera.iCurrentView = 1
CCamera.bFreeView = false

CCamera.BUTTON_DIRECTION_UP = 1
CCamera.BUTTON_DIRECTION_DOWN = 2
CCamera.BUTTON_DIRECTION_LEFT = 3
CCamera.BUTTON_DIRECTION_RIGHT = 4

CCamera.VIEW_TOP_LEFT = 1
CCamera.VIEW_TOP_RIGHT = 2
CCamera.VIEW_BOTTOM_LEFT = 3
CCamera.VIEW_BOTTOM_RIGHT = 4
CCamera.VIEW_CENTER = 5

CCamera.AVAILABLE_DIRECTIONS = {}

CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_LEFT] = {}
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_LEFT][CCamera.BUTTON_DIRECTION_DOWN] = CCamera.VIEW_BOTTOM_LEFT
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_LEFT][CCamera.BUTTON_DIRECTION_RIGHT] = CCamera.VIEW_TOP_RIGHT

CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_RIGHT] = {}
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_RIGHT][CCamera.BUTTON_DIRECTION_DOWN] = CCamera.VIEW_BOTTOM_RIGHT
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_TOP_RIGHT][CCamera.BUTTON_DIRECTION_LEFT] = CCamera.VIEW_TOP_LEFT

CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_LEFT] = {}
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_LEFT][CCamera.BUTTON_DIRECTION_UP] = CCamera.VIEW_TOP_LEFT
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_LEFT][CCamera.BUTTON_DIRECTION_RIGHT] = CCamera.VIEW_BOTTOM_RIGHT

CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_RIGHT] = {}
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_RIGHT][CCamera.BUTTON_DIRECTION_UP] = CCamera.VIEW_TOP_RIGHT
CCamera.AVAILABLE_DIRECTIONS[CCamera.VIEW_BOTTOM_RIGHT][CCamera.BUTTON_DIRECTION_LEFT] = CCamera.VIEW_BOTTOM_LEFT


CCamera.VIEW_X = {}
CCamera.VIEW_Y = {}

CCamera.init = function()
    CCamera.VIEW_X[CCamera.VIEW_TOP_LEFT] = 1
    CCamera.VIEW_X[CCamera.VIEW_TOP_RIGHT] = math.ceil(CWorld.iSizeX/2)
    CCamera.VIEW_X[CCamera.VIEW_BOTTOM_LEFT] = 1
    CCamera.VIEW_X[CCamera.VIEW_BOTTOM_RIGHT] = math.ceil(CWorld.iSizeX/2)
    CCamera.VIEW_X[CCamera.VIEW_CENTER] = math.ceil(tGame.Cols/2)

    CCamera.VIEW_Y[CCamera.VIEW_TOP_LEFT] = 1
    CCamera.VIEW_Y[CCamera.VIEW_TOP_RIGHT] = 1
    CCamera.VIEW_Y[CCamera.VIEW_BOTTOM_LEFT] = math.ceil(CWorld.iSizeY/2)-1
    CCamera.VIEW_Y[CCamera.VIEW_BOTTOM_RIGHT] = math.ceil(CWorld.iSizeY/2)-1
    CCamera.VIEW_Y[CCamera.VIEW_CENTER] = math.ceil(tGame.Rows/2)-1

    CCamera.iX = CCamera.VIEW_X[CCamera.VIEW_CENTER]
    CCamera.iY = CCamera.VIEW_Y[CCamera.VIEW_CENTER]    
end

CCamera.WorldPosToCamPos = function(iX, iY)
    return (iX - CCamera.iX)+1, (iY - CCamera.iY)+1
end

CCamera.CamPosToWorldPos = function(iX, iY)
    return (iX + CCamera.iX)-1, (iY + CCamera.iY)-1
end

CCamera.WorldPosToView = function(iX, iY)
    local iView = 0

    for iViewID = CCamera.VIEW_TOP_LEFT, CCamera.VIEW_BOTTOM_RIGHT do
        if iX >= CCamera.VIEW_X[iViewID] and iX <= CCamera.VIEW_X[iViewID]+tGame.Cols and iY >= CCamera.VIEW_Y[iViewID] and iY <= CCamera.VIEW_Y[iViewID]+tGame.Rows then
            iView = iViewID
        end
    end

    return iView
end

CCamera.IsValidCamPos = function(iX, iY)
    return iX >= 1 and iX <= tGame.Cols and iY >= 1 and iY <= tGame.Rows
end

CCamera.IsPosOnCamera = function(iX, iY, iSize)
    iSize = iSize or 3

    return iX >= CCamera.iX-iSize and iX <= CCamera.iX+tGame.Cols+iSize and iY >= CCamera.iY-iSize and iY <= CCamera.iY+tGame.Rows+iSize
end

CCamera.DrawWorld = function()
    for iX = CCamera.iX, CCamera.iX+tGame.Cols-1 do
        for iY = CCamera.iY, CCamera.iY+tGame.Rows-1 do
            local iBlockType = CWorld.BLOCK_TYPE_EMPTY
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then iBlockType = CWorld.tBlocks[iX][iY].iBlockType end

            local iScreenX, iScreenY = CCamera.WorldPosToCamPos(iX, iY)
            tFloor[iScreenX][iScreenY].iColor = CWorld.BLOCK_TYPE_TO_COLOR[iBlockType]
            tFloor[iScreenX][iScreenY].iBright = tConfig.Bright
            tFloor[iScreenX][iScreenY].iBlockType = iBlockType

            if iBlockType == CWorld.BLOCK_TYPE_STRUCTURE then
                tFloor[iScreenX][iScreenY].iBright = tConfig.Bright + 1
            end

            if not CWorld.bPlayerActionsPaused and tFloor[iScreenX][iScreenY].bDefect and iBlockType == CWorld.BLOCK_TYPE_BONUS then
                CGameMode.PlayerTakeBonus(CCamera.CamPosToWorldPos(iScreenX, iScreenY))
            end
        end
    end
end

CCamera.PaintActiveButtons = function()
    for iButton = 1, #tButtons do
        if tButtons[iButton] and not tButtons[iButton].bDefect and tButtons[iButton].bActive then
            tButtons[iButton].iColor = CColors.BLUE
            tButtons[iButton].iBright = tConfig.Bright
        end
    end
end

CCamera.AnimateMovementTo = function(iX, iY, fCallback)
    CWorld.bPlayerActionsPaused = true

    AL.NewTimer(tConfig.AnimationDelay, function()
        local iPlusX = 0
        local iPlusY = 0

        if CCamera.iX < iX then
            iPlusX = 1
        elseif CCamera.iX > iX then
            iPlusX = -1
        end

        if CCamera.iY < iY then
            iPlusY = 1
        elseif CCamera.iY > iY then
            iPlusY = -1
        end

        CCamera.iX = CCamera.iX + iPlusX        
        CCamera.iY = CCamera.iY + iPlusY        

        if CCamera.iX == iX and CCamera.iY == iY then
            CWorld.bPlayerActionsPaused = false
            fCallback()

            return nil
        end
        return tConfig.AnimationDelay
    end)
end

CCamera.MoveInDirection = function(iDirection)
    if CCamera.AVAILABLE_DIRECTIONS[CCamera.iCurrentView][iDirection] then
        CCamera.MoveToView(CCamera.AVAILABLE_DIRECTIONS[CCamera.iCurrentView][iDirection])
    end
end

CCamera.MoveToView = function(iView)
    CCamera.DeactivateAllButtons()
    CCamera.iCurrentView = iView

    CCamera.AnimateMovementTo(CCamera.VIEW_X[iView], CCamera.VIEW_Y[iView], function()
        for iDirection = CCamera.BUTTON_DIRECTION_UP, CCamera.BUTTON_DIRECTION_RIGHT do
            if CCamera.AVAILABLE_DIRECTIONS[CCamera.iCurrentView][iDirection] then
                CCamera.ActivateDirectionButtons(iDirection)
            end
        end
    end)
end

CCamera.GetButtonSide = function(iButton)
    local iDirection = CCamera.BUTTON_DIRECTION_UP

    if iButton > tGame.Cols*2 + tGame.Rows then
        iDirection = CCamera.BUTTON_DIRECTION_LEFT
    elseif iButton > tGame.Cols + tGame.Rows then
        iDirection = CCamera.BUTTON_DIRECTION_DOWN
    elseif iButton > tGame.Cols then
        iDirection = CCamera.BUTTON_DIRECTION_RIGHT
    end

    return iDirection
end

CCamera.DeactivateAllButtons = function()
    for iButton = 1, #tButtons do
        if tButtons[iButton] then
            tButtons[iButton].bActive = false
        end
    end   
end

CCamera.ActivateDirectionButtons = function(iDirection)
    for iButton = 1, #tButtons do
        if tButtons[iButton] and not tButtons[iButton].bDefect and (CCamera.GetButtonSide(iButton) == iDirection) then
            tButtons[iButton].bActive = true
        end
    end
end

CCamera.SideButtonPress = function(iButton)
    CCamera.MoveInDirection(CCamera.GetButtonSide(iButton))
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

    CPad.iXPlus = 0
    CPad.iYPlus = 0

    if bUp then CPad.iYPlus = CPad.iYPlus - 1 end
    if bDown then CPad.iYPlus = CPad.iYPlus + 1 end

    if bLeft then CPad.iXPlus = CPad.iXPlus - 1 end
    if bRight then CPad.iXPlus = CPad.iXPlus + 1 end
end

CPad.AFK = function()
    return CPad.LastInteractionTime == -1 or (CTime.unix() - CPad.LastInteractionTime > tConfig.PadAFKTimer)
end
--//

--PATHFINDING
CPath = {}

CPath.INF = 1/0
CPath.MAX_ITER = 100

CPath.tCache = {}
CPath.iCurrentUnitSize = 2
CPath.bCurrentUnitAlly = false

CPath.init = function()
    CPath.MAX_ITER = (tGame.Cols*2 + tGame.Rows*2)
end

CPath.Dist = function(iX1, iY1, iX2, iY2)
    return math.sqrt(math.pow(iX2 - iX1, 2) + math.pow(iY2 - iY1, 2))
end

CPath.DistBetween = function(tBlock1, tBlock2)
    return CPath.Dist(tBlock1.iX, tBlock1.iY, tBlock2.iX, tBlock2.iY)
end

CPath.Cost = function(tBlock1, tBlock2)
    return CPath.Dist(tBlock1.iX, tBlock1.iY, tBlock2.iX, tBlock2.iY)
end

CPath.LowScore = function(tSet, tScores)
    local iLowest, tBest = CPath.INF, nil
    for _, tBlock in ipairs(tSet) do
        local iScore = tScores[tBlock]
        if iScore < iLowest then
            iLowest, tBest = iScore, tBlock
        end
    end

    return tBest
end

CPath.Neighbors = function(tBlock, tBlocks)
    local tNeighbors = {}
    for _, tNeighbor in ipairs(tBlocks) do
        if not CPath.Equals(tBlock, tNeighbor) and CPath.ValidNeighbor(tBlock, tNeighbor) then
            table.insert(tNeighbors, tNeighbor)
        end
    end

    return tNeighbors
end

CPath.NotIn = function(tSet, tBlock)
    for _, tSetBlock in ipairs(tSet) do
        if CPath.Equals(tSetBlock, tBlock) then return false end
    end

    return true
end

CPath.Remove = function(tSet, tBlock)
    for i, tSetBlock in ipairs(tSet) do
        if tSetBlock == tBlock then
            tSet[i] = tSet[#tSet]
            tSet[#tSet] = nil
            return;
        end
    end
end

CPath.Unwind = function(tPath, tMap, tBlock)
    if tMap[tBlock] then
        table.insert(tPath, 1, tMap[tBlock])
        return CPath.Unwind(tPath, tMap, tMap[tBlock])
    else
        return tPath
    end
end

CPath.ValidNeighbor = function(tBlock, tNeighbor)
    if CPath.DistBetween(tBlock, tNeighbor) > 1 then return false end 

    if CPath.bCurrentUnitAlly then
        if not (CWorld.tBlocks[tNeighbor.iX] or CWorld.tBlocks[tNeighbor.iX][tNeighbor.iY]) 
        or CWorld.tBlocks[tNeighbor.iX][tNeighbor.iY].iBlockType == CWorld.BLOCK_TYPE_STRUCTURE then return false end
    end

    if not CWorld.IsValidPositionForUnit(tNeighbor.iX, tNeighbor.iY, CPath.iCurrentUnitSize) then return false end

    return true
end

CPath.Equals = function(tBlock1, tBlock2)
    return tBlock1.iX == tBlock2.iX and tBlock1.iY == tBlock2.iY
end

CPath.AStar = function(tStartBlock, tGoalBlock, tBlocks)
    local tClosedSet = {}
    local tOpenSet = {tStartBlock}
    local tCameFrom = {}

    local tGScore, tFScore = {}, {}
    tGScore[tStartBlock] = 0
    tFScore[tStartBlock] = tGScore[tStartBlock] + CPath.Cost(tStartBlock, tGoalBlock)

    local iIter = 0
    while #tOpenSet > 0 do
        iIter = iIter + 1

        local tCurrent = CPath.LowScore(tOpenSet, tFScore)
        if CPath.Equals(tCurrent, tGoalBlock) or iIter >= CPath.MAX_ITER then
            local tPath = CPath.Unwind({}, tCameFrom, tCurrent)
            table.insert(tPath, tCurrent)
            return tPath
        end

        CPath.Remove(tOpenSet, tCurrent)
        table.insert(tClosedSet, tCurrent)

        local tNeighbors = CPath.Neighbors(tCurrent, tBlocks)
        for _, tNeighbor in ipairs(tNeighbors) do
            if CPath.NotIn(tClosedSet, tNeighbor) then
                local tTentGScore = tGScore[tCurrent] + CPath.DistBetween(tCurrent, tNeighbor)

                if CPath.NotIn(tOpenSet, tNeighbor) or tTentGScore < tGScore[tNeighbor] then
                    tCameFrom[tNeighbor] = tCurrent
                    tGScore[tNeighbor] = tTentGScore
                    tFScore[tNeighbor] = tGScore[tNeighbor] + CPath.Cost(tNeighbor, tGoalBlock)

                    if CPath.NotIn(tOpenSet, tNeighbor) then
                        table.insert(tOpenSet, tNeighbor)
                    end
                end
            end
        end
    end

    return nil
end


CPath.Path = function(iUnitSize, iStartX, iStartY, iTargetX, iTargetY, tBlocks, bIgnoreCache, bUnitIsAlly)
    local tResPath = nil

    if not bIgnoreCache and CPath.tCache[iUnitSize] and CPath.tCache[iUnitSize][iStartX] and CPath.tCache[iUnitSize][iStartX][iStartY] and CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX] and CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX][iTargetY] then
        tResPath = CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX][iTargetY] 
    else
        CPath.iCurrentUnitSize = iUnitSize
        CPath.bCurrentUnitAlly = bUnitIsAlly
        tResPath = CPath.AStar({iX = iStartX, iY = iStartY}, 
            {iX = iTargetX, iY = iTargetY}, tBlocks)

        if CPath.tCache[iUnitSize] == nil then CPath.tCache[iUnitSize] = {} end
        if CPath.tCache[iUnitSize][iStartX] == nil then CPath.tCache[iUnitSize][iStartX] = {} end
        if CPath.tCache[iUnitSize][iStartX][iStartY] == nil then CPath.tCache[iUnitSize][iStartX][iStartY] = {} end
        if CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX] == nil then CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX] = {} end
        CPath.tCache[iUnitSize][iStartX][iStartY][iTargetX][iTargetY] = tResPath
    end

    if tResPath == nil then
        CDebug.Print("Cant find path from X:"..iStartX.." Y:"..iStartY.." to X:"..iTargetX.." Y:"..iTargetY.."!")
    end

    return tResPath
end
--//

--DEBUG
CDebug = {}
CDebug.bPrintsOn = false

CDebug.Print = function(sString)
    if CDebug.bPrintsOn then
        CLog.print(sString)
    end
end
--//

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSizeX, iSizeY)
    for iX = tStart.X, tStart.X + iSizeX - 1 do
        for iY = tStart.Y, tStart.Y + iSizeY - 1 do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].bClick then
                    return true
                end 
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

function SetRectColorBright(iX, iY, iSizeX, iSizeY, iColor, iBright)
    for i = iX, iX + iSizeX do
        for j = iY, iY + iSizeY do
            if not (i < 1 or j > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
end

function RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
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

function SetAllButtonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end
--//


--//
function GetStats()
    return tGameStats
end

function PauseGame()
    bGamePaused = true
    CWorld.bPlayerActionsPaused = true
end

function ResumeGame()
    bGamePaused = false
    CWorld.bPlayerActionsPaused = false
	iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    if tFloor[click.X] and tFloor[click.X][click.Y] then
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
            return;
        end

        if click.Click and not tFloor[click.X][click.Y].bDefect then
            if iGameState == GAMESTATE_GAME and not CWorld.bPlayerActionsPaused then
                if tFloor[click.X][click.Y].iUnitID > 0 then
                    CUnits.PlayerAttackUnit(tFloor[click.X][click.Y].iUnitID)
                elseif tFloor[click.X][click.Y].iBlockType == CWorld.BLOCK_TYPE_BONUS then
                    CGameMode.PlayerTakeBonus(CCamera.CamPosToWorldPos(click.X, click.Y))
                end
            end
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if bGamePaused then return; end

    if click.GamepadAddress and click.GamepadAddress > 0 then
        CPad.Click(click.GamepadUpClick, click.GamepadDownClick, click.GamepadLeftClick, click.GamepadRightClick, click.GamepadTriggerClick)
    else
        if tButtons[click.Button] == nil then return end
        tButtons[click.Button].bClick = click.Click

        if click.Click then 
            bAnyButtonClick = true

            if iGameState == GAMESTATE_GAME and tButtons[click.Button].bActive then
                CCamera.SideButtonPress(click.Button)
            end 
        end
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end