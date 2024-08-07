--[[
    Название: Название механики
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
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
}
local tButtonStruct = { 
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

    CGameMode.InitGameMode()
    CGameMode.Announcer()
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
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    if bAnyButtonClick then
        CAudio.PlaySyncFromScratch("")
        CGameMode.StartCountDown(5)
        iGameState = GAMESTATE_GAME
    end    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет    
    CEffect.DrawCurrentEffect()
    CPaint.Cross()
end

function PostGameTick()
    if CGameMode.bVictory then
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
    else
        SetGlobalColorBright(CCross.iColor, tConfig.Bright)
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
CGameMode.bDamageCooldown = false

CGameMode.InitGameMode = function()
    tGameStats.TotalLives = tConfig.TeamHealth 
    tGameStats.CurrentLives = tConfig.TeamHealth
    tGameStats.TotalStages = tConfig.EffectsCount
    tGameStats.StageNum = 1

    CCross.iBright = tConfig.Bright-2
end

CGameMode.Announcer = function()
    --voice-- название игры
    --voice-- объяснение правил
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
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

    CCross.Thinker()
    CEffect.Thinker()

    CEffect.NextEffectTimer()

    CCross.AiNewDest()
end

CGameMode.DamagePlayer = function(iDamage)
    if CGameMode.bDamageCooldown then return; end

    tGameStats.CurrentLives = tGameStats.CurrentLives - iDamage
    if tGameStats.CurrentLives <= 0 then
        CGameMode.EndGame(false)
    else 
        CAudio.PlayAsync(CAudio.MISCLICK)
    end

    CGameMode.bDamageCooldown = true
    CEffect.iColor = CColors.MAGENTA
    CTimer.New(tConfig.DamageCooldown, function()
        CGameMode.bDamageCooldown = false
        CEffect.iColor = CColors.RED
    end)
end

CGameMode.DamagePlayerCheck = function(iX, iY, iDamage)
    if CGameMode.bDamageCooldown then return; end

    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect then
        if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
            CGameMode.DamagePlayer(iDamage)
        end
    end
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    iGameState = GAMESTATE_POSTGAME
    CAudio.StopBackground()

    if bVictory then
        CAudio.PlaySync(CAudio.GAME_SUCCESS)
        CAudio.PlaySync(CAudio.VICTORY)
    else
        CAudio.PlaySync(CAudio.GAME_OVER)
        CAudio.PlaySync(CAudio.DEFEAT)
    end

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = bVictory
        iGameState = GAMESTATE_FINISH
    end)
end
--//

--effect
CEffect = {}
CEffect.tEffects = {}
CEffect.tCurrentEffectData = {}

CEffect.iCurrentEffect = 0
CEffect.iLastEffect = 0
CEffect.bEffectOn = false
CEffect.iColor = CColors.RED
CEffect.iPassedEffectsCount = 0

CEffect.FUNC_INIT = 1
CEffect.FUNC_SOUND = 2
CEffect.FUNC_DRAW = 3
CEffect.FUNC_TICK = 4
CEffect.FUNC_UNLOAD = 5

CEffect.CONST_LENGTH = 6
CEffect.CONST_TICK_DELAY = 7

CEffect.Thinker = function()
    CTimer.New(100, function()
        if iGameState > GAMESTATE_GAME then return; end

        if CEffect.iCurrentEffect ~= 0 then
            CEffect.tEffects[CEffect.iCurrentEffect][CEffect.FUNC_TICK]() 
        
            return CEffect.tEffects[CEffect.iCurrentEffect][CEffect.CONST_TICK_DELAY]
        else
            return 100
        end
    end)
end

CEffect.DrawCurrentEffect = function()
    if CEffect.iCurrentEffect ~= 0 then
        CEffect.tEffects[CEffect.iCurrentEffect][CEffect.FUNC_DRAW]() 
    end
end

CEffect.NextEffectTimer = function()
    local iEffectId = CEffect.iLastEffect
    while iEffectId == CEffect.iLastEffect do
        iEffectId = math.random(1, #CEffect.tEffects)
    end
    CLog.print("next effect: "..iEffectId)
    --iEffectId = 5

    --voice-- следующий эффект...
    --voice-- название эффекта

    tGameStats.StageLeftDuration = tConfig.PauseBetweenEffects
    CTimer.New(1000, function()
        if tGameStats.StageLeftDuration <= 1 then
            CEffect.LoadEffect(iEffectId)
            CEffect.EffectTimer()

            CCross.iBright = tConfig.Bright-2

            return nil
        else
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration <= 5 then
                CAudio.PlaySyncFromScratch("")
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)

                CCross.iBright = (tConfig.Bright-2) + (6 - tGameStats.StageLeftDuration)
            end
            return 1000
        end
    end)
end

CEffect.EffectTimer = function()
    tGameStats.StageLeftDuration = CEffect.tEffects[CEffect.iCurrentEffect][CEffect.CONST_LENGTH]
    CTimer.New(1000, function()
        if iGameState > GAMESTATE_GAME then return nil end

        if tGameStats.StageLeftDuration <= 0 then
            CEffect.EndCurrentEffect()

            return nil
        else
            --CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            return 1000
        end
    end)
end

CEffect.EndCurrentEffect = function()
    CEffect.iLastEffect = CEffect.iCurrentEffect

    CEffect.tEffects[CEffect.iCurrentEffect][CEffect.FUNC_UNLOAD]()
    CEffect.tCurrentEffectData = {}
    CEffect.iCurrentEffect = 0

    if iGameState > GAMESTATE_GAME then return nil end

    --voice-- эффект закончен...

    CEffect.iPassedEffectsCount = CEffect.iPassedEffectsCount + 1
    if CEffect.iPassedEffectsCount < tConfig.EffectsCount then
        CEffect.bEffectOn = false
        CCross.AiNewDest()

        tGameStats.StageNum = tGameStats.StageNum + 1
        CEffect.NextEffectTimer()
    else
        CGameMode.EndGame(true)
    end
end

CEffect.LoadEffect = function(iEffectId)
    CEffect.bEffectOn = true

    CEffect.iCurrentEffect = iEffectId

    CEffect.tEffects[iEffectId][CEffect.FUNC_INIT]()
    CEffect.tEffects[iEffectId][CEffect.FUNC_SOUND]()
end
--//

--EFFECT TABLES
--[[TEMPLATE:
CEffect.EFFECT_ = 0
CEffect.tEffects[CEffect.EFFECT_] = {}
CEffect.tEffects[CEffect.EFFECT_][CEffect.CONST_LENGTH] = 20
CEffect.tEffects[CEffect.EFFECT_][CEffect.CONST_TICK_DELAY] = 200

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_INIT] = function()
    CEffect.tCurrentEffectData.iA = 1
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_SOUND] = function()
    
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_DRAW] = function()
    
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_TICK] = function()
    
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_UNLOAD] = function()
    
end
--]]

---- эффект: выстрел в 4 стороны
CEffect.EFFECT_SHOT = 1
CEffect.tEffects[CEffect.EFFECT_SHOT] = {}
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.CONST_LENGTH] = 3
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.CONST_TICK_DELAY] = 100

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true

    CEffect.tCurrentEffectData.iMaxProjectiles = 4
    CEffect.tCurrentEffectData.tProjectiles = {}

    for iProjectileID = 1, CEffect.tCurrentEffectData.iMaxProjectiles do
        CEffect.tCurrentEffectData.tProjectiles[iProjectileID] = {}
        CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iX = CCross.iX
        CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY = CCross.iY
        CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelX = 0
        CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelY = 0

        if iProjectileID == 1 then
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelX = -1
        elseif iProjectileID == 2 then
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelY = -1
        elseif iProjectileID == 3 then
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelX = 1
        elseif iProjectileID == 4 then
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVelY = 1
        end
    end
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_SOUND] = function()
    CAudio.PlayAsync("plasma.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_DRAW] = function()
    for iProjectileID = 1, CEffect.tCurrentEffectData.iMaxProjectiles do
        local tProjectile = CEffect.tCurrentEffectData.tProjectiles[iProjectileID]
        if tProjectile then
            local iIncX = 1 if tProjectile.iVelX ~= 0 then iIncX = tProjectile.iVelX end
            local iIncY = 1 if tProjectile.iVelY ~= 0 then iIncY = tProjectile.iVelY end

            for iX = tProjectile.iX, tProjectile.iX + tProjectile.iVelX*2, iIncX do
                for iY = tProjectile.iY, tProjectile.iY + tProjectile.iVelY*2, iIncY do   
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CEffect.iColor
                        tFloor[iX][iY].iBright = tConfig.Bright
                        CGameMode.DamagePlayerCheck(iX, iY, 1)
                    end
                end
            end
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_TICK] = function()
    for iProjectileID = 1, CEffect.tCurrentEffectData.iMaxProjectiles do
        local tProjectile = CEffect.tCurrentEffectData.tProjectiles[iProjectileID]
        if tProjectile then
            tProjectile.iX = tProjectile.iX + tProjectile.iVelX
            tProjectile.iY = tProjectile.iY + tProjectile.iVelY

            if (tProjectile.iX < 1 or tProjectile.iX > tGame.Cols) or (tProjectile.iY < 1 or tProjectile.iY > tGame.Rows) then
                CEffect.tCurrentEffectData.tProjectiles[iProjectileID] = nil
            end
        end
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
end
----

----эффект: круг
CEffect.EFFECT_CIRCLE = 2
CEffect.tEffects[CEffect.EFFECT_CIRCLE] = {}
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.CONST_LENGTH] = 10
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.CONST_TICK_DELAY] = 200

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true

    CEffect.tCurrentEffectData.iX = CCross.iX
    CEffect.tCurrentEffectData.iY = CCross.iY
    CEffect.tCurrentEffectData.iSize = 1
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_SOUND] = function()
    CAudio.PlayAsync("plasma.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_DRAW] = function()
    local function PaintCirclePixel(iX, iY)
        for iX2 = iX-1, iX+1 do
            if tFloor[iX2] and tFloor[iX2][iY] then
                tFloor[iX2][iY].iColor = CEffect.iColor
                
                tFloor[iX2][iY].iBright = tConfig.Bright-2
                if iX2 == iX then
                    tFloor[iX2][iY].iBright = tConfig.Bright
                end

                CGameMode.DamagePlayerCheck(iX2, iY, 1)
            end
        end
    end

    local iX = CEffect.tCurrentEffectData.iX
    local iY = CEffect.tCurrentEffectData.iY
    local iSize = CEffect.tCurrentEffectData.iSize
    local iSize2 = 3-2*iSize

    for i = 0, iSize do
        PaintCirclePixel(iX + i, iY + iSize)
        PaintCirclePixel(iX + i, iY - iSize)
        PaintCirclePixel(iX - i, iY + iSize)
        PaintCirclePixel(iX - i, iY - iSize)

        PaintCirclePixel(iX + iSize, iY + i)
        PaintCirclePixel(iX + iSize, iY - i)
        PaintCirclePixel(iX - iSize, iY + i)
        PaintCirclePixel(iX - iSize, iY - i)

        if iSize2 < 0 then
            iSize2 = iSize2 + 4*i + 6
        else
            iSize2 = iSize2 + 4*(i-iSize) + 10
            iSize = iSize - 1
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_TICK] = function()
    CEffect.tCurrentEffectData.iSize = CEffect.tCurrentEffectData.iSize + 1
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
end
----

----эффект: враг
CEffect.EFFECT_ENEMY = 3
CEffect.tEffects[CEffect.EFFECT_ENEMY] = {}
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.CONST_LENGTH] = 20
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.CONST_TICK_DELAY] = 250

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true

    CEffect.tCurrentEffectData.iUnitCount = math.random(2,3)
    CEffect.tCurrentEffectData.iUnitSize = math.random(2,3)
    CEffect.tCurrentEffectData.tUnits = {}

    for iUnitID = 1, CEffect.tCurrentEffectData.iUnitCount do
        CEffect.tCurrentEffectData.tUnits[iUnitID] = {}
        CEffect.tCurrentEffectData.tUnits[iUnitID].iX = CCross.iX
        CEffect.tCurrentEffectData.tUnits[iUnitID].iY = CCross.iY
        CEffect.tCurrentEffectData.tUnits[iUnitID].iDestX = math.random(1, tGame.Cols)
        CEffect.tCurrentEffectData.tUnits[iUnitID].iDestY = math.random(1, tGame.Rows)
    end
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_SOUND] = function()
    
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_DRAW] = function()
    for iUnitID = 1, CEffect.tCurrentEffectData.iUnitCount do
        if CEffect.tCurrentEffectData.tUnits[iUnitID] then
            for iX = CEffect.tCurrentEffectData.tUnits[iUnitID].iX, CEffect.tCurrentEffectData.tUnits[iUnitID].iX-1 + CEffect.tCurrentEffectData.iUnitSize do
                for iY = CEffect.tCurrentEffectData.tUnits[iUnitID].iY, CEffect.tCurrentEffectData.tUnits[iUnitID].iY-1 + CEffect.tCurrentEffectData.iUnitSize do
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CEffect.iColor
                        tFloor[iX][iY].iBright = tConfig.Bright
                        CGameMode.DamagePlayerCheck(iX, iY, 1)

                        if tGameStats.StageLeftDuration <= (tConfig.Bright-1) then
                            tFloor[iX][iY].iBright = (tConfig.Bright-1) - ((tConfig.Bright-1) - tGameStats.StageLeftDuration)
                        end
                    end
                end        
            end
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_TICK] = function()
    local function GetDestXYPlus(iUnitID)
        local iX = 0
        local iY = 0

        --pad unit
        --if iUnitID == 1 and (CPad.LastInteractionTime ~= -1 and CPad.LastInteractionTime < 10) then
        --    return CPad.iXPlus, CPad.iYPlus
        --end
        --

        if CEffect.tCurrentEffectData.tUnits[iUnitID].iX < CEffect.tCurrentEffectData.tUnits[iUnitID].iDestX then
            iX = 1
        elseif CEffect.tCurrentEffectData.tUnits[iUnitID].iX > CEffect.tCurrentEffectData.tUnits[iUnitID].iDestX then
            iX = -1
        end

        if CEffect.tCurrentEffectData.tUnits[iUnitID].iY < CEffect.tCurrentEffectData.tUnits[iUnitID].iDestY then
            iY = 1
        elseif CEffect.tCurrentEffectData.tUnits[iUnitID].iY > CEffect.tCurrentEffectData.tUnits[iUnitID].iDestY then
            iY = -1
        end

        return iX, iY
    end

    for iUnitID = 1, CEffect.tCurrentEffectData.iUnitCount do
        if CEffect.tCurrentEffectData.tUnits[iUnitID] then  
            local iXPlus, iYPlus = GetDestXYPlus(iUnitID)
            CEffect.tCurrentEffectData.tUnits[iUnitID].iX = CEffect.tCurrentEffectData.tUnits[iUnitID].iX + iXPlus
            CEffect.tCurrentEffectData.tUnits[iUnitID].iY = CEffect.tCurrentEffectData.tUnits[iUnitID].iY + iYPlus

            if (CEffect.tCurrentEffectData.tUnits[iUnitID].iX == CEffect.tCurrentEffectData.tUnits[iUnitID].iDestX) 
            and (CEffect.tCurrentEffectData.tUnits[iUnitID].iY == CEffect.tCurrentEffectData.tUnits[iUnitID].iDestY) then
                CEffect.tCurrentEffectData.tUnits[iUnitID].iDestX = math.random(1, tGame.Cols)
                CEffect.tCurrentEffectData.tUnits[iUnitID].iDestY = math.random(1, tGame.Rows)
            end
        end
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
end
----

---- эффект: линия
CEffect.EFFECT_LINE = 4
CEffect.tEffects[CEffect.EFFECT_LINE] = {}
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.CONST_LENGTH] = 10
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.CONST_TICK_DELAY] = 75

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_INIT] = function()
    CEffect.tCurrentEffectData.iTargetX = math.random(1, tGame.Cols)
    CEffect.tCurrentEffectData.iTargetY = 1
    CEffect.tCurrentEffectData.iTargetDir = 1
    CEffect.tCurrentEffectData.iLineWidth = 1
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_SOUND] = function()
    
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_DRAW] = function()
    local function Line(iX1, iY1, iX2, iY2, fDraw)
        local iDX, iSX = math.abs( iX2 - iX1 ), iX1 < iX2 and 1 or -1
        local iDY, iSY = -math.abs( iY2 - iY1 ), iY1 < iY2 and 1 or -1
        local iDXDY = iDX + iDY

        for i = 1, tGame.Cols + tGame.Rows do  
            local iE = iDXDY + iDXDY
            if iE >= iDY then
                iDXDY, iX1 = iDXDY + iDY, iX1 + iSX
            end
            
            if iE <= iDX then
                iDXDY, iY1 = iDXDY + iDX, iY1 + iSY
            end
            fDraw(iX1, iY1, 1)
        end
    end

    local function Pixel(iX, iY)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = CEffect.iColor
            tFloor[iX][iY].iBright = tConfig.Bright
            CGameMode.DamagePlayerCheck(iX, iY, 1)
        end
    end

    Line(CCross.iX, CCross.iY, CEffect.tCurrentEffectData.iTargetX, CEffect.tCurrentEffectData.iTargetY, function(iX, iY)
        for iX2 = (iX-CEffect.tCurrentEffectData.iLineWidth), iX do
            Pixel(iX2, iY)
        end

        for iY2 = (iY-CEffect.tCurrentEffectData.iLineWidth), iY do
            Pixel(iX, iY2)
        end
    end)
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_TICK] = function()
    local iIncrement = 1

    if CEffect.tCurrentEffectData.iTargetX < tGame.Cols+1 and CEffect.tCurrentEffectData.iTargetY == 0 then
        CEffect.tCurrentEffectData.iTargetDir = 1
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX + iIncrement
    elseif CEffect.tCurrentEffectData.iTargetX >= tGame.Cols and CEffect.tCurrentEffectData.iTargetY < tGame.Rows+1 then
        CEffect.tCurrentEffectData.iTargetDir = 2
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY + iIncrement
    elseif CEffect.tCurrentEffectData.iTargetY >= tGame.Rows and CEffect.tCurrentEffectData.iTargetX > 0 then
        CEffect.tCurrentEffectData.iTargetDir = 3
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX - iIncrement
    elseif CEffect.tCurrentEffectData.iTargetY > 0 then
        CEffect.tCurrentEffectData.iTargetDir = 4
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY - iIncrement
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_UNLOAD] = function()
    
end
----

----эффект: лазер
CEffect.EFFECT_LASER = 5
CEffect.tEffects[CEffect.EFFECT_LASER] = {}
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.CONST_LENGTH] = 7
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.CONST_TICK_DELAY] = nil

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_INIT] = function()

end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_SOUND] = function()
    
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_DRAW] = function()
    local function Pixel(iX, iY)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = CEffect.iColor
            tFloor[iX][iY].iBright = tConfig.Bright

            CGameMode.DamagePlayerCheck(iX, iY, 1)
        end
    end

    for iX = CCross.iX, tGame.Cols do
        Pixel(iX, CCross.iY)
    end

    for iX = CCross.iX, 1, -1 do
        Pixel(iX, CCross.iY)
    end

    for iY = CCross.iY, tGame.Rows do
        Pixel(CCross.iX, iY)
    end

    for iY = CCross.iY, 1, -1 do
        Pixel(CCross.iX, iY)
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_TICK] = function()
    
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_UNLOAD] = function()
    
end

--//

--cross
CCross = {}
CCross.iX = math.floor(tGame.Cols/2)
CCross.iY = math.floor(tGame.Rows/2)
CCross.iSize = 4
CCross.iColor = 3
CCross.iBright = 5
CCross.bAiOn = true
CCross.iAiDestX = 0
CCross.iAiDestY = 0
CCross.bBlockMovement = false

CCross.Move = function(iXPlus, iYPlus)
    if CCross.bBlockMovement then return; end

    local iNewX = CCross.iX + iXPlus
    local iNewY = CCross.iY + iYPlus

    if iNewX > 0 and iNewX <= tGame.Cols then
        CCross.iX = iNewX
    end

    if iNewY > 0 and iNewY <= tGame.Rows then
        CCross.iY = iNewY
    end    
end
    
CCross.Thinker = function()
    CTimer.New(tConfig.CrossMovementDelay, function()
        CCross.bAiOn = (CPad.LastInteractionTime == -1 or (CTime.unix() - CPad.LastInteractionTime > tConfig.CrossAFKTimer))

        if CCross.bAiOn then
            if CCross.iAiDestX == CCross.iX and CCross.iAiDestY == CCross.iY then
                CCross.AiNewDest()
            end

            CCross.Move(CCross.AIGetDestXYPlus())
        else
            CCross.Move(CPad.iXPlus, CPad.iYPlus)
        end

        return tConfig.CrossMovementDelay
    end) 
end

CCross.AiNewDest = function()
    local iMax = -999

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            local iWeight = tFloor[iX][iY].iWeight + math.random(-5,5)
            if iWeight >= iMax then
                iMax = iWeight
                CCross.iAiDestX = iX
                CCross.iAiDestY = iY
            end
        end
    end
end

CCross.AIGetDestXYPlus = function()
    local iXPlus = 0
    local iYPlus = 0

    if CCross.iX < CCross.iAiDestX then
        iXPlus = 1
    elseif CCross.iX > CCross.iAiDestX then
        iXPlus = -1
    end

    if CCross.iY < CCross.iAiDestY then
        iYPlus = 1
    elseif CCross.iY > CCross.iAiDestY then
        iYPlus = -1
    end    

    return iXPlus, iYPlus
end
--//

--paint
CPaint = {}

CPaint.Cross = function()
    for iX = (CCross.iX - math.floor(CCross.iSize/2)), (CCross.iX + math.floor(CCross.iSize/2)) do
        if tFloor[iX] and tFloor[iX][CCross.iY] and iX ~= CCross.iX then
            tFloor[iX][CCross.iY].iColor = CCross.iColor
            tFloor[iX][CCross.iY].iBright = CCross.iBright
        end
    end 

    for iY = (CCross.iY - math.floor(CCross.iSize/2)), (CCross.iY + math.floor(CCross.iSize/2)) do
        if tFloor[CCross.iX] and tFloor[CCross.iX][iY] and iY ~= CCross.iY then
            tFloor[CCross.iX][iY].iColor = CCross.iColor
            tFloor[CCross.iX][iY].iBright = CCross.iBright
        end
    end     
end
--//

--Pad
CPad = {}
CPad.LastInteractionTime = -1

CPad.iXPlus = 0
CPad.iYPlus = 0
CPad.bTrigger = false

CPad.Click = function(bUp, bDown, bLeft, bRight, bTrigger)
    CPad.LastInteractionTime = CTime.unix()

    CPad.bTrigger = bTrigger

    CPad.iXPlus = 0
    CPad.iYPlus = 0

    if bUp then CPad.iYPlus = CPad.iYPlus - 1 end
    if bDown then CPad.iYPlus = CPad.iYPlus + 1 end

    if bLeft then CPad.iXPlus = CPad.iXPlus - 1 end
    if bRight then CPad.iXPlus = CPad.iXPlus + 1 end
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
end

function ResumeGame()
    bGamePaused = false
	iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if not tFloor[click.X][click.Y].bDefect and click.Click and tFloor[click.X][click.Y].iColor == CColors.RED then
        CGameMode.DamagePlayer(1)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if click.GamepadAddress and click.GamepadAddress > 0 then
        CPad.Click(click.GamepadUpClick, click.GamepadDownClick, click.GamepadLeftClick, click.GamepadRightClick, click.GamepadTriggerClick)
    else
        if tButtons[click.Button] == nil then return end
        tButtons[click.Button].bClick = click.Click
        bAnyButtonClick = true
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