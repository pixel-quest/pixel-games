--[[
    Название: Уклонись
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Прицел бегает за игроками и раз в несколько секунд пытается задеть их различными эффектами
        Если игрок наступил на красный пиксель эффекта - команда теряет жизнь, потеряв все жизни команда проигрывает
        Иногда чтобы завершить эффект игрокам потребуется выполнить дополнительное действие - собрать монетки или нажать на кнопку
        Игра поддерживает управление геймпадом, один из игроков может контролировать прицел пытаясь попасть по другим игрокам

    Идеи по доработке: 
        Больше эффектов
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
    iWeight = 0,
    iCoinId = 0,
    bAnimated = false,
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

    tGameResults.PlayersCount = tConfig.PlayerCount

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
    if not tConfig.EliminationMode then
        tGameStats.TotalLives = tConfig.TeamHealth 
        tGameStats.CurrentLives = tConfig.TeamHealth
    end

    tGameStats.TotalStages = tConfig.EffectsCount
    tGameStats.StageNum = 1

    CCross.iBright = tConfig.Bright-2

    CCross.MovementDelay = tConfig.CrossMovementSpeed_Max - tConfig.CrossMovementSpeed
end

CGameMode.Announcer = function()
    CAudio.PlaySync("dodge_gamename.mp3")
    CAudio.PlaySync("dodge_rules.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
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

    CCross.Thinker()
    CEffect.Thinker()

    CEffect.NextEffectTimer()

    CCross.AiNewDest()
end

CGameMode.DamagePlayer = function(iDamage)
    if CGameMode.bDamageCooldown or iGameState ~= GAMESTATE_GAME then return; end

    tGameResults.Score = tGameResults.Score - 10

    if not tConfig.EliminationMode then 
        tGameStats.CurrentLives = tGameStats.CurrentLives - iDamage
        if tGameStats.CurrentLives <= 0 then
            CGameMode.EndGame(false)
        else 
            CAudio.PlayAsync(CAudio.MISCLICK)
        end
    else
        --CAudio.PlayAsync(CAudio.MISCLICK)
        CAudio.PlayAsync("player_out.mp3")     
    end

    CGameMode.bDamageCooldown = true
    CEffect.iColor = CColors.MAGENTA
    AL.NewTimer(tConfig.DamageCooldown, function()
        CGameMode.bDamageCooldown = false
        CEffect.iColor = CColors.RED
    end)
end

CGameMode.DamagePlayerCheck = function(iX, iY, iDamage)
    if CGameMode.bDamageCooldown or iGameState ~= GAMESTATE_GAME then return; end

    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect and tFloor[iX][iY].iCoinId == 0 then
        if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
            CGameMode.DamagePlayer(iDamage)

            CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.RED)
        end
    end
end

CGameMode.EndGame = function(bVictory)
    if iGameState ~= GAMESTATE_GAME then return; end

    CGameMode.bVictory = bVictory
    iGameState = GAMESTATE_POSTGAME
    CAudio.StopBackground()
    tGameResults.Won = bVictory

    CEffect.iCurrentEffect = 0
    CPaint.ClearAnimation()
    CCross.bHidden = true

    if bVictory then
        CAudio.PlaySync(CAudio.GAME_SUCCESS)
        CAudio.PlaySync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN
        CGameMode.GlobalColor(CColors.GREEN)
    else
        CAudio.PlaySync(CAudio.GAME_OVER)
        CAudio.PlaySync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
        CGameMode.GlobalColor(CColors.RED)
    end

    AL.NewTimer(tConfig.WinDurationMS, function()
        tGameResults.Won = bVictory
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.GlobalColor = function(iColor)
    local iRepeat = 0
    AL.NewTimer(0, function()
        SetGlobalColorBright(iColor, tConfig.Bright)
        iRepeat = iRepeat + 1
        if iRepeat < 3 then return 100; end
    end)
end
--//

--effect
CEffect = {}
CEffect.tEffects = {}
CEffect.tCurrentEffectData = {}

CEffect.iCurrentEffect = 0
CEffect.iNextEffect = 0
CEffect.iLastEffect = 0
CEffect.iColor = CColors.RED
CEffect.iPassedEffectsCount = 0
CEffect.iEndId = 0

CEffect.bCanCast = false
CEffect.bEffectOn = false
CEffect.bReadyToEnd = false

CEffect.FUNC_INIT = 1
CEffect.FUNC_SOUND = 2
CEffect.FUNC_DRAW = 3
CEffect.FUNC_TICK = 4
CEffect.FUNC_UNLOAD = 5
CEffect.FUNC_ANNOUNCER = 6

CEffect.CONST_LENGTH = 7
CEffect.CONST_TICK_DELAY = 8
CEffect.CONST_SPECIAL_ENDING_ON = 9

CEffect.SPECIAL_ENDING_COUNT = 2
CEffect.SPECIAL_ENDING_TYPE_DEFAULT = 0
CEffect.SPECIAL_ENDING_TYPE_BUTTON = 1
CEffect.SPECIAL_ENDING_TYPE_COINS = 2

CEffect.Thinker = function()
    AL.NewTimer(100, function()
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

        CPaint.Cross()

        if CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_COINS then
            CEffect.SpecialEndingPaintCoins()
        end

        if CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_BUTTON and CEffect.bReadyToEnd then
            SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
        end
    else
        CPaint.Cross()
    end
end

CEffect.NextEffectTimer = function()
    local iEffectId = CEffect.iLastEffect
    while iEffectId == CEffect.iLastEffect do
        iEffectId = math.random(1, #CEffect.tEffects)
    end
    --CLog.print("next effect: "..iEffectId)
    --iEffectId = 10

    CAudio.PlaySync("next_effect.mp3")
    CEffect.tEffects[iEffectId][CEffect.FUNC_ANNOUNCER]()

    if CEffect.tEffects[iEffectId][CEffect.CONST_SPECIAL_ENDING_ON] and math.random(1, 100) >= 50 then
        CEffect.iEndId = math.random(1, CEffect.SPECIAL_ENDING_COUNT)
    end

    tGameStats.StageLeftDuration = tConfig.PauseBetweenEffects
    AL.NewTimer(1000, function()
        if iGameState > GAMESTATE_GAME then return nil; end

        if tGameStats.StageLeftDuration <= 1 then
            CEffect.iNextEffect = iEffectId
            CEffect.bCanCast = true

            if not CCross.IsAiOn() then
                CAudio.PlaySync("dodge_effect_cast_ready.mp3")
            end

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
    if CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_COINS then
        CEffect.SpecialEndingCoins()
        return;
    end

    tGameStats.StageLeftDuration = CEffect.tEffects[CEffect.iCurrentEffect][CEffect.CONST_LENGTH]
    AL.NewTimer(1000, function()
        if tGameStats.StageLeftDuration <= 0 then
            if iGameState > GAMESTATE_GAME then return nil end

            if CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_BUTTON then
                CEffect.bReadyToEnd = true
                CEffect.SpecialEndingButton()
                return
            end

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
    CEffect.tCurrentEffectData = nil
    CEffect.tCurrentEffectData = {}
    CEffect.iCurrentEffect = 0
    CEffect.iEndId = CEffect.SPECIAL_ENDING_TYPE_DEFAULT
    CEffect.bReadyToEnd = false

    if iGameState > GAMESTATE_GAME then return nil end

    CAudio.PlaySync(CAudio.STAGE_DONE)
    --voice-- эффект закончен...

    CEffect.iPassedEffectsCount = CEffect.iPassedEffectsCount + 1
    if CEffect.iPassedEffectsCount < tConfig.EffectsCount then
        CEffect.bEffectOn = false
        CCross.AiNewDest()

        tGameResults.Score = tGameResults.Score + 100

        tGameStats.StageNum = tGameStats.StageNum + 1
        CEffect.NextEffectTimer()
    else
        CGameMode.EndGame(true)
    end
end

CEffect.LoadEffect = function(iEffectId)
    CEffect.bCanCast = false
    CEffect.bEffectOn = true

    CEffect.iCurrentEffect = iEffectId

    CEffect.tEffects[iEffectId][CEffect.FUNC_INIT]()
    CEffect.tEffects[iEffectId][CEffect.FUNC_SOUND]()
end

CEffect.PaintEffectPixel = function(iX, iY)
    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bAnimated then
        tFloor[iX][iY].iColor = CEffect.iColor
        tFloor[iX][iY].iBright = tConfig.Bright
        CGameMode.DamagePlayerCheck(iX, iY, 1)
    end
end

CEffect.SpecialEndingButton = function()
    CAudio.PlayAsync("special_effect_button.mp3")
end

CEffect.SpecialEndingButtonPressButton = function()
    CEffect.EndCurrentEffect()
end

CEffect.SpecialEndingCoins = function()
    CAudio.PlayAsync("special_effect_coins.mp3")

    CEffect.tCurrentEffectData.tCoins = {}

    for iCoinId = 1, math.random(5, 15) do
        local iX = 0
        local iY = 0

        repeat
            iX = math.random(1, tGame.Cols)
            iY = math.random(1, tGame.Rows)
        until tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect and tFloor[iX][iY].iCoinId == 0 and tFloor[iX][iY].iColor ~= CCross.iColor

        CEffect.tCurrentEffectData.tCoins[iCoinId] = {}
        CEffect.tCurrentEffectData.tCoins[iCoinId].iX = iX
        CEffect.tCurrentEffectData.tCoins[iCoinId].iY = iY
        tFloor[iX][iY].iCoinId = iCoinId
    end

    tGameStats.TotalStars = #CEffect.tCurrentEffectData.tCoins
end

CEffect.SpecialEndingPaintCoins = function()
    for iCoinId = 1, #CEffect.tCurrentEffectData.tCoins do
        if CEffect.tCurrentEffectData.tCoins[iCoinId] then
            tFloor[CEffect.tCurrentEffectData.tCoins[iCoinId].iX][CEffect.tCurrentEffectData.tCoins[iCoinId].iY].iColor = CColors.BLUE
            tFloor[CEffect.tCurrentEffectData.tCoins[iCoinId].iX][CEffect.tCurrentEffectData.tCoins[iCoinId].iY].iBright = tConfig.Bright
        end
    end
end

CEffect.SpecialEndingCollectCoin = function(iCoinId, iX, iY)
    if CEffect.tCurrentEffectData.tCoins[iCoinId] == nil then return end

    CEffect.tCurrentEffectData.tCoins[iCoinId] = nil

    tGameResults.Score = tGameResults.Score + 5

    tGameStats.CurrentStars = tGameStats.CurrentStars + 1
    if tGameStats.CurrentStars >= tGameStats.TotalStars then
        CEffect.EndCurrentEffect()

        tGameStats.TotalStars = 0
        tGameStats.CurrentStars = 0
    else
        CAudio.PlayAsync(CAudio.CLICK)
    end

    AL.NewTimer(1000, function()
        tFloor[iX][iY].iCoinId = 0
    end)
end
--//

--EFFECT TABLES
--[[TEMPLATE:
CEffect.EFFECT_ = 0
CEffect.tEffects[CEffect.EFFECT_] = {}
CEffect.tEffects[CEffect.EFFECT_][CEffect.CONST_LENGTH] = 20
CEffect.tEffects[CEffect.EFFECT_][CEffect.CONST_TICK_DELAY] = 200
CEffect.tEffects[CEffect.EFFECT_][CEffect.CONST_SPECIAL_ENDING_ON] = false

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_][CEffect.FUNC_ANNOUNCER] = function()

end

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
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.CONST_TICK_DELAY] = 150
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.CONST_SPECIAL_ENDING_ON] = false

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_SHOT][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_shot.mp3")
end

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

            local i = 0
            for iX = tProjectile.iX, tProjectile.iX + tProjectile.iVelX*2, iIncX do
                for iY = tProjectile.iY, tProjectile.iY + tProjectile.iVelY*2, iIncY do  
                    i = i + 1 
                    CEffect.PaintEffectPixel(iX, iY)
                    if i >= 2 then
                        CEffect.PaintEffectPixel(iX+tProjectile.iVelY, iY+tProjectile.iVelX)
                        CEffect.PaintEffectPixel(iX-tProjectile.iVelY, iY-tProjectile.iVelX)
                    end
                    if i >= 3 then
                        CEffect.PaintEffectPixel(iX+tProjectile.iVelY*2, iY+tProjectile.iVelX*2)
                        CEffect.PaintEffectPixel(iX-tProjectile.iVelY*2, iY-tProjectile.iVelX*2)
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
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.CONST_LENGTH] = 6
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.CONST_TICK_DELAY] = 200
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.CONST_SPECIAL_ENDING_ON] = false

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_CIRCLE][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_circle.mp3")
end

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
            if tFloor[iX2] and tFloor[iX2][iY] and not tFloor[iX2][iY].bAnimated then
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
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_enemy.mp3")

    if not CCross.IsAiOn() then
        CAudio.PlaySync("dodge_enemy_controls.mp3")
    end
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true
    CCross.bHidden = true

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
    CAudio.PlayAsync("dodge_enemy_voiceline.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_ENEMY][CEffect.FUNC_DRAW] = function()
    for iUnitID = 1, CEffect.tCurrentEffectData.iUnitCount do
        if CEffect.tCurrentEffectData.tUnits[iUnitID] then
            for iX = CEffect.tCurrentEffectData.tUnits[iUnitID].iX, CEffect.tCurrentEffectData.tUnits[iUnitID].iX-1 + CEffect.tCurrentEffectData.iUnitSize do
                for iY = CEffect.tCurrentEffectData.tUnits[iUnitID].iY, CEffect.tCurrentEffectData.tUnits[iUnitID].iY-1 + CEffect.tCurrentEffectData.iUnitSize do
                    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bAnimated then
                        tFloor[iX][iY].iColor = CEffect.iColor
                        tFloor[iX][iY].iBright = tConfig.Bright
                        CGameMode.DamagePlayerCheck(iX, iY, 1)

                        if CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_DEFAULT then
                            if tGameStats.StageLeftDuration <= (tConfig.Bright-1) then
                                tFloor[iX][iY].iBright = (tConfig.Bright-1) - ((tConfig.Bright-1) - tGameStats.StageLeftDuration)
                            end
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
        if iUnitID == 1 and not CCross.IsAiOn() then
            return CPad.iXPlus, CPad.iYPlus
        end
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
    CCross.bHidden = false
end
----

---- эффект: линия
CEffect.EFFECT_LINE = 4
CEffect.tEffects[CEffect.EFFECT_LINE] = {}
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.CONST_LENGTH] = 10
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.CONST_TICK_DELAY] = 75
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_line.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_INIT] = function()
    CEffect.tCurrentEffectData.iTargetX = math.random(1, tGame.Cols)
    CEffect.tCurrentEffectData.iTargetY = 1
    CEffect.tCurrentEffectData.iLineWidth = 1
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_SOUND] = function()
    CAudio.PlaySync("electro-laser.mp3")
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

    Line(CCross.iX, CCross.iY, CEffect.tCurrentEffectData.iTargetX, CEffect.tCurrentEffectData.iTargetY, function(iX, iY)
        for iX2 = (iX-CEffect.tCurrentEffectData.iLineWidth), iX do
            CEffect.PaintEffectPixel(iX2, iY)
        end

        for iY2 = (iY-CEffect.tCurrentEffectData.iLineWidth), iY do
            CEffect.PaintEffectPixel(iX, iY2)
        end
    end)
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_TICK] = function()
    if CEffect.tCurrentEffectData.iTargetX < tGame.Cols+1 and CEffect.tCurrentEffectData.iTargetY == 0 then
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX + 1
    elseif CEffect.tCurrentEffectData.iTargetX >= tGame.Cols and CEffect.tCurrentEffectData.iTargetY < tGame.Rows+1 then
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY + 1
    elseif CEffect.tCurrentEffectData.iTargetY >= tGame.Rows and CEffect.tCurrentEffectData.iTargetX > 0 then
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX - 1
    elseif CEffect.tCurrentEffectData.iTargetY > 0 then
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY - 1
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_LINE][CEffect.FUNC_UNLOAD] = function()
    CAudio.PlaySyncFromScratch("")
end
----

----эффект: лазер
CEffect.EFFECT_LASER = 5
CEffect.tEffects[CEffect.EFFECT_LASER] = {}
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.CONST_LENGTH] = 7
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.CONST_TICK_DELAY] = 200
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_laser.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_INIT] = function()

end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_SOUND] = function()
    CAudio.PlaySync("electro-laser.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_DRAW] = function()
    for iX = CCross.iX, tGame.Cols do
        CEffect.PaintEffectPixel(iX, CCross.iY)
    end

    for iX = CCross.iX, 1, -1 do
        CEffect.PaintEffectPixel(iX, CCross.iY)
    end

    for iY = CCross.iY, tGame.Rows do
        CEffect.PaintEffectPixel(CCross.iX, iY)
    end

    for iY = CCross.iY, 1, -1 do
        CEffect.PaintEffectPixel(CCross.iX, iY)
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_TICK] = function()
    
end
----

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_LASER][CEffect.FUNC_UNLOAD] = function()
    CAudio.PlaySyncFromScratch("")
end

---- эффект: закрас
CEffect.EFFECT_DRAW = 6
CEffect.tEffects[CEffect.EFFECT_DRAW] = {}
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.CONST_LENGTH] = 20
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.CONST_TICK_DELAY] = 150
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_draw.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_INIT] = function()
    CEffect.tCurrentEffectData.tPixels = {}
    CEffect.tCurrentEffectData.iLastCrossX = 0
    CEffect.tCurrentEffectData.iLastCrossY = 0
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_SOUND] = function()
    CAudio.PlayAsync("spray-paint.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_DRAW] = function()
    for iPixelId = 1, #CEffect.tCurrentEffectData.tPixels do
        if CEffect.tCurrentEffectData.tPixels[iPixelId] then
            CEffect.PaintEffectPixel(CEffect.tCurrentEffectData.tPixels[iPixelId].iX, CEffect.tCurrentEffectData.tPixels[iPixelId].iY)
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_TICK] = function()
    if not (CCross.iX == CEffect.tCurrentEffectData.iLastCrossX and CCross.iY == CEffect.tCurrentEffectData.iLastCrossY) then
        local iPixelId = #CEffect.tCurrentEffectData.tPixels+1

        CEffect.tCurrentEffectData.tPixels[iPixelId] = {}
        CEffect.tCurrentEffectData.tPixels[iPixelId].iX = CCross.iX
        CEffect.tCurrentEffectData.tPixels[iPixelId].iY = CCross.iY
    end

    CEffect.tCurrentEffectData.iLastCrossX = CCross.iX
    CEffect.tCurrentEffectData.iLastCrossY = CCross.iY
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_DRAW][CEffect.FUNC_UNLOAD] = function()
    
end
----

----эффект: закрас линией
CEffect.EFFECT_LINEDRAW = 7
CEffect.tEffects[CEffect.EFFECT_LINEDRAW] = {}
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.CONST_LENGTH] = 8
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.CONST_TICK_DELAY] = 140
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.CONST_SPECIAL_ENDING_ON] = false

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_linedraw.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_INIT] = function()
    CEffect.tCurrentEffectData.tPixels = {}

    CEffect.tCurrentEffectData.iTargetX = math.random(1, tGame.Cols)
    CEffect.tCurrentEffectData.iTargetY = 1
    CEffect.tCurrentEffectData.iLineWidth = 1

    CCross.bBlockMovement = true
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_SOUND] = function()
    CAudio.PlayAsync("spray-paint.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_DRAW] = function()
    for iPixelId = 1, #CEffect.tCurrentEffectData.tPixels do
        if CEffect.tCurrentEffectData.tPixels[iPixelId] then
            CEffect.PaintEffectPixel(CEffect.tCurrentEffectData.tPixels[iPixelId].iX, CEffect.tCurrentEffectData.tPixels[iPixelId].iY)
        end
    end 
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_TICK] = function()
    if CEffect.tCurrentEffectData.iTargetX < tGame.Cols+1 and CEffect.tCurrentEffectData.iTargetY == 0 then
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX + 1
    elseif CEffect.tCurrentEffectData.iTargetX >= tGame.Cols and CEffect.tCurrentEffectData.iTargetY < tGame.Rows+1 then
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY + 1
    elseif CEffect.tCurrentEffectData.iTargetY >= tGame.Rows and CEffect.tCurrentEffectData.iTargetX > 0 then
        CEffect.tCurrentEffectData.iTargetX = CEffect.tCurrentEffectData.iTargetX - 1
    elseif CEffect.tCurrentEffectData.iTargetY > 0 then
        CEffect.tCurrentEffectData.iTargetY = CEffect.tCurrentEffectData.iTargetY - 1
    end

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
        local iPixelId = #CEffect.tCurrentEffectData.tPixels+1
        CEffect.tCurrentEffectData.tPixels[iPixelId] = {}
        CEffect.tCurrentEffectData.tPixels[iPixelId].iX = iX
        CEffect.tCurrentEffectData.tPixels[iPixelId].iY = iY
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

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_LINEDRAW][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
end
----

----эффект: полоска
CEffect.EFFECT_STRIPE = 8
CEffect.tEffects[CEffect.EFFECT_STRIPE] = {}
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.CONST_LENGTH] = 8
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.CONST_TICK_DELAY] = 175
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_stripe.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true
    CCross.bHidden = true

    CEffect.tCurrentEffectData.iX = CCross.iX
    CEffect.tCurrentEffectData.iY = CCross.iY
    CEffect.tCurrentEffectData.iLineType = math.random(1,2)
    CEffect.tCurrentEffectData.iVel = 1
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_SOUND] = function()
    CAudio.PlayAsync("lightsaber-ignition.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_DRAW] = function()
    if CEffect.tCurrentEffectData.iLineType == 1 then
        for iY = 1, tGame.Rows do
            CEffect.PaintEffectPixel(CEffect.tCurrentEffectData.iX, iY)
        end
    else
        for iX = 1, tGame.Cols do
            CEffect.PaintEffectPixel(iX, CEffect.tCurrentEffectData.iY)
        end    
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_TICK] = function()
    if CEffect.tCurrentEffectData.iLineType == 1 then
        CEffect.tCurrentEffectData.iX = CEffect.tCurrentEffectData.iX + CEffect.tCurrentEffectData.iVel
        if CEffect.tCurrentEffectData.iX == tGame.Cols or CEffect.tCurrentEffectData.iX == 1 then
            CEffect.tCurrentEffectData.iVel = -CEffect.tCurrentEffectData.iVel
            CAudio.PlayAsync("lightsaber-swing.mp3")
        end
    else
        CEffect.tCurrentEffectData.iY = CEffect.tCurrentEffectData.iY + CEffect.tCurrentEffectData.iVel
        if CEffect.tCurrentEffectData.iY == tGame.Rows or CEffect.tCurrentEffectData.iY == 1 then
            CEffect.tCurrentEffectData.iVel = -CEffect.tCurrentEffectData.iVel
            CAudio.PlayAsync("lightsaber-swing.mp3")
        end
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_STRIPE][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
    CCross.bHidden = false
end
----

----эффект: мяч
CEffect.EFFECT_BALL = 9
CEffect.tEffects[CEffect.EFFECT_BALL] = {}
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.CONST_LENGTH] = 12
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.CONST_TICK_DELAY] = 125
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_ball.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true
    CCross.bHidden = true

    CEffect.tCurrentEffectData.tBalls = {}
    CEffect.tCurrentEffectData.iBallCount = math.random(2,3)
    for iBallId = 1, CEffect.tCurrentEffectData.iBallCount do
        CEffect.tCurrentEffectData.tBalls[iBallId] = {} 
        CEffect.tCurrentEffectData.tBalls[iBallId].iX = CCross.iX 
        CEffect.tCurrentEffectData.tBalls[iBallId].iY = CCross.iY 
        CEffect.tCurrentEffectData.tBalls[iBallId].iVelX = math.random(-1,1) 
        CEffect.tCurrentEffectData.tBalls[iBallId].iVelY = math.random(-1,1) 
        CEffect.tCurrentEffectData.tBalls[iBallId].iSize = 2
        CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown = 5

        if CEffect.tCurrentEffectData.tBalls[iBallId].iVelX == 0 then CEffect.tCurrentEffectData.tBalls[iBallId].iVelX = 1 end
        if CEffect.tCurrentEffectData.tBalls[iBallId].iVelY == 0 then CEffect.tCurrentEffectData.tBalls[iBallId].iVelY = -1 end
    end

    CEffect.tCurrentEffectData.bCollisionEnabled = true
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_SOUND] = function()
    CAudio.PlaySync("ball-kick.mp3")
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_DRAW] = function()
    for iBallId = 1, CEffect.tCurrentEffectData.iBallCount do
        if CEffect.tCurrentEffectData.tBalls[iBallId] then
            for iX = CEffect.tCurrentEffectData.tBalls[iBallId].iX, CEffect.tCurrentEffectData.tBalls[iBallId].iX + CEffect.tCurrentEffectData.tBalls[iBallId].iSize-1 do
                for iY = CEffect.tCurrentEffectData.tBalls[iBallId].iY, CEffect.tCurrentEffectData.tBalls[iBallId].iY + CEffect.tCurrentEffectData.tBalls[iBallId].iSize-1 do
                    CEffect.PaintEffectPixel(iX, iY)
                end
            end
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_TICK] = function()
    for iBallId = 1, CEffect.tCurrentEffectData.iBallCount do
        if CEffect.tCurrentEffectData.tBalls[iBallId] then
            local bCheckCollision = true

            CEffect.tCurrentEffectData.tBalls[iBallId].iX = CEffect.tCurrentEffectData.tBalls[iBallId].iX + CEffect.tCurrentEffectData.tBalls[iBallId].iVelX
            if CEffect.tCurrentEffectData.tBalls[iBallId].iX == 1 or CEffect.tCurrentEffectData.tBalls[iBallId].iX+CEffect.tCurrentEffectData.tBalls[iBallId].iSize-1 == tGame.Cols then
                CEffect.tCurrentEffectData.tBalls[iBallId].iVelX = -CEffect.tCurrentEffectData.tBalls[iBallId].iVelX
                bCheckCollision = false
            end

            CEffect.tCurrentEffectData.tBalls[iBallId].iY = CEffect.tCurrentEffectData.tBalls[iBallId].iY + CEffect.tCurrentEffectData.tBalls[iBallId].iVelY
            if CEffect.tCurrentEffectData.tBalls[iBallId].iY == 1 or CEffect.tCurrentEffectData.tBalls[iBallId].iY + CEffect.tCurrentEffectData.tBalls[iBallId].iSize-1 == tGame.Rows then
                CEffect.tCurrentEffectData.tBalls[iBallId].iVelY = -CEffect.tCurrentEffectData.tBalls[iBallId].iVelY
                bCheckCollision = false
            end

            if not bCheckCollision then
                CAudio.PlayAsync("ball-bounce.mp3")
            end

            if CEffect.tCurrentEffectData.tBalls[iBallId].iX < 1 then CEffect.tCurrentEffectData.tBalls[iBallId].iX = 3 end
            if CEffect.tCurrentEffectData.tBalls[iBallId].iX > tGame.Cols then CEffect.tCurrentEffectData.tBalls[iBallId].iX = tGame.Cols-3 end
            if CEffect.tCurrentEffectData.tBalls[iBallId].iY < 1 then CEffect.tCurrentEffectData.tBalls[iBallId].iY = 3 end
            if CEffect.tCurrentEffectData.tBalls[iBallId].iY > tGame.Rows then CEffect.tCurrentEffectData.tBalls[iBallId].iY = tGame.Rows-3 return end      

            if CEffect.tCurrentEffectData.bCollisionEnabled and CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown == 0 and bCheckCollision then
                for iCheckBallId = 1, CEffect.tCurrentEffectData.iBallCount do
                    if iCheckBallId ~= iBallId and RectIntersects(
                    CEffect.tCurrentEffectData.tBalls[iBallId].iX+CEffect.tCurrentEffectData.tBalls[iBallId].iVelX, CEffect.tCurrentEffectData.tBalls[iBallId].iY+CEffect.tCurrentEffectData.tBalls[iBallId].iVelY, CEffect.tCurrentEffectData.tBalls[iBallId].iSize, 
                    CEffect.tCurrentEffectData.tBalls[iCheckBallId].iX, CEffect.tCurrentEffectData.tBalls[iCheckBallId].iY, CEffect.tCurrentEffectData.tBalls[iCheckBallId].iSize
                    ) then
                        CEffect.tCurrentEffectData.tBalls[iBallId].iVelX = -CEffect.tCurrentEffectData.tBalls[iBallId].iVelX
                        CEffect.tCurrentEffectData.tBalls[iBallId].iVelY = -CEffect.tCurrentEffectData.tBalls[iBallId].iVelY
                        CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown = 5

                        CAudio.PlayAsync("ball-bounce.mp3")

                        return;
                    end
                end
            elseif CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown > 0 then 
                CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown = CEffect.tCurrentEffectData.tBalls[iBallId].iCollisionCooldown - 1
            end
        end
    end    
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_BALL][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
    CCross.bHidden = false
end
----

--Эффект: пушка
CEffect.EFFECT_GUN = 10
CEffect.tEffects[CEffect.EFFECT_GUN] = {}
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.CONST_LENGTH] = 15
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.CONST_TICK_DELAY] = 150
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.CONST_SPECIAL_ENDING_ON] = true

-- Озвучка эффекта голосом до отсчёта "Следующий эффект: ..."
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_ANNOUNCER] = function()
    CAudio.PlaySync("dodge_effect_gun.mp3")
end

-- прогрузка переменных эффекта
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_INIT] = function()
    CCross.bBlockMovement = true
    CCross.bHidden = true

    CEffect.tCurrentEffectData.iSize = 3
    CEffect.tCurrentEffectData.iX = math.random(1, tGame.Cols-CEffect.tCurrentEffectData.iSize)
    CEffect.tCurrentEffectData.iY = math.random(1, 2)
    if CEffect.tCurrentEffectData.iY > 1 then CEffect.tCurrentEffectData.iY = tGame.Rows end

    CEffect.tCurrentEffectData.tProjectiles = {}
    CEffect.tCurrentEffectData.bCooldown = false
end

-- звуковое сопровождение эффекта
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_SOUND] = function()
    
end

-- отрисовка эффекта
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_DRAW] = function()
    for iX = 1, tGame.Cols do
        CEffect.PaintEffectPixel(iX, CEffect.tCurrentEffectData.iY)
    end

    local iStartY = CEffect.tCurrentEffectData.iY
    if iStartY > 1 then iStartY = iStartY - CEffect.tCurrentEffectData.iSize end

    for iY = iStartY, iStartY + CEffect.tCurrentEffectData.iSize-1 do
        for iX = CEffect.tCurrentEffectData.iX, CEffect.tCurrentEffectData.iX + CEffect.tCurrentEffectData.iSize-1 do
            CEffect.PaintEffectPixel(iX, iY)
        end
    end

    for iProjectileID = 1, #CEffect.tCurrentEffectData.tProjectiles do
        local tProjectile = CEffect.tCurrentEffectData.tProjectiles[iProjectileID]
        if tProjectile ~= nil then
            for iX = tProjectile.iX, tProjectile.iX + CEffect.tCurrentEffectData.iSize-1 do
                CEffect.PaintEffectPixel(iX, tProjectile.iY)
            end
        end
    end
end

-- логический цикл эффекта
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_TICK] = function()
    local function movegun(iXPlus)
        if iXPlus == 0 then return; end

        if (CEffect.tCurrentEffectData.iX + iXPlus) > 0 and (CEffect.tCurrentEffectData.iX + iXPlus + CEffect.tCurrentEffectData.iSize-1) <= tGame.Cols then
            CEffect.tCurrentEffectData.iX = CEffect.tCurrentEffectData.iX + iXPlus
        end
    end

    local function shootgun()
        if not CEffect.tCurrentEffectData.bCooldown then
            local iProjectileID = #CEffect.tCurrentEffectData.tProjectiles+1
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID] = {}
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iX = CEffect.tCurrentEffectData.iX
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY = CEffect.tCurrentEffectData.iY
            CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVel = 1
            if CEffect.tCurrentEffectData.iY > 1 then 
                CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iVel = -1 
                CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY = CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY - (CEffect.tCurrentEffectData.iSize-1)
            else
                CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY = CEffect.tCurrentEffectData.tProjectiles[iProjectileID].iY + (CEffect.tCurrentEffectData.iSize-1)
            end

            CAudio.PlayAsync("plasma.mp3")

            CEffect.tCurrentEffectData.bCooldown = true
            AL.NewTimer(500, function()
                CEffect.tCurrentEffectData.bCooldown = false
            end)
        end
    end

    for iProjectileID = 1, #CEffect.tCurrentEffectData.tProjectiles do
        local tProjectile = CEffect.tCurrentEffectData.tProjectiles[iProjectileID]
        if tProjectile ~= nil then
            tProjectile.iY = tProjectile.iY + tProjectile.iVel

            if (tProjectile.iY + CEffect.tCurrentEffectData.iSize) < 1 or tProjectile.iY > tGame.Rows then
                tProjectile = nil
                CEffect.tCurrentEffectData.tProjectiles[iProjectileID] = nil
            end
        end
    end

    if CCross.IsAiOn() then
        local iXPlus = 0
        if CCross.iAiDestX < CEffect.tCurrentEffectData.iX then iXPlus = -1
        elseif CCross.iAiDestX > CEffect.tCurrentEffectData.iX then iXPlus = 1
        else CCross.AiNewDest() end

        movegun(iXPlus)
        shootgun()
    else 
        movegun(CPad.iXPlus)

        if CPad.bTrigger then
            shootgun()
            CPad.bTrigger = false
        end
    end
end

-- выгрузка эффекта
CEffect.tEffects[CEffect.EFFECT_GUN][CEffect.FUNC_UNLOAD] = function()
    CCross.bBlockMovement = false
    CCross.bHidden = false
end
----

--//

--cross
CCross = {}
CCross.iX = math.floor(tGame.Cols/2)
CCross.iY = math.floor(tGame.Rows/2)
CCross.iSize = 4
CCross.iColor = 3
CCross.iBright = 5
CCross.iAiDestX = 0
CCross.iAiDestY = 0
CCross.bBlockMovement = false
CCross.bHidden = false
CCross.iTicksNewDest = 0
CCross.MovementDelay = 200

CCross.Move = function(iXPlus, iYPlus)
    if CCross.bBlockMovement then return; end

    local iNewX = CCross.iX + iXPlus
    local iNewY = CCross.iY + iYPlus

    if iNewX > 1 and iNewX <= tGame.Cols-1 then
        CCross.iX = iNewX
    end

    if iNewY > 1 and iNewY <= tGame.Rows-1 then
        CCross.iY = iNewY
    end    
end
    
CCross.Thinker = function()
    AL.NewTimer(CCross.MovementDelay, function()
        if CCross.IsAiOn() then
            CCross.iTicksNewDest = CCross.iTicksNewDest + 1

            if CCross.iTicksNewDest > 10 or (CCross.iAiDestX == CCross.iX and CCross.iAiDestY == CCross.iY) then
                CCross.AiNewDest()
                CCross.iTicksNewDest = 0
            end

            if CEffect.bCanCast then 
                CCross.CastEffect()
            end

            CCross.Move(CCross.AIGetDestXYPlus())
        else
            CCross.Move(CPad.iXPlus, CPad.iYPlus)

            if CEffect.bCanCast and CPad.bTrigger then
                CCross.CastEffect()
            end
        end

        return CCross.MovementDelay
    end) 
end

CCross.IsAiOn = function()
    return CPad.LastInteractionTime == -1 or (CTime.unix() - CPad.LastInteractionTime > tConfig.CrossAFKTimer)
end

CCross.AiNewDest = function()
    local iMax = -999

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            local iWeight = tFloor[iX][iY].iWeight + math.random(-5,5)
            if iWeight > iMax then
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

CCross.CastEffect = function()
    if CEffect.bCanCast then
        CEffect.LoadEffect(CEffect.iNextEffect)
        CEffect.EffectTimer()

        CCross.iBright = tConfig.Bright-2
    end
end
--//

--paint
CPaint = {}
CPaint.ANIMATION_DELAY = 100

CPaint.Cross = function()
    if CCross.bHidden then return end

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

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(CPaint.ANIMATION_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated or iGameState > GAMESTATE_GAME then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.MAGENTA
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = iColor
            iCount = iCount + 1
        end
        
        if iCount <= iFlickerCount then
            return CPaint.ANIMATION_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end

CPaint.ClearAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do 
            tFloor[iX][iY].bAnimated = false
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
    --CLog.print(tostring(bUp).." "..tostring(bDown).." "..tostring(bLeft).." "..tostring(bRight).." "..tostring(bTrigger))

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

    if CPad.iXPlus ~= 0 or CPad.iYPlus ~= 0 then
        CCross.Move(CPad.iXPlus, CPad.iYPlus)
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
            end

            if CEffect.bEffectOn == false then
                tFloor[iX][iY].iCoinId = 0
            end
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
    if tFloor[click.X] and tFloor[click.X][click.Y] then
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if not tFloor[click.X][click.Y].bDefect and click.Click and tFloor[click.X][click.Y].iColor == CColors.RED then
            CGameMode.DamagePlayerCheck(click.X, click.Y, 1)
        end

        if click.Click and CEffect.bEffectOn and tFloor[click.X][click.Y].iCoinId > 0 then
            CEffect.SpecialEndingCollectCoin(tFloor[click.X][click.Y].iCoinId, click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and CEffect.bEffectOn and tFloor[defect.X][defect.Y].iCoinId > 0 then
            CEffect.SpecialEndingCollectCoin(tFloor[defect.X][defect.Y].iCoinId, defect.X, defect.Y)
        end
    end
end

function ButtonClick(click)
    if click.GamepadAddress and click.GamepadAddress > 0 then
        CPad.Click(click.GamepadUpClick, click.GamepadDownClick, click.GamepadLeftClick, click.GamepadRightClick, click.GamepadTriggerClick)
    else
        if tButtons[click.Button] == nil then return end
        tButtons[click.Button].bClick = click.Click
        bAnyButtonClick = true

        if click.Click and iGameState == GAMESTATE_GAME and CEffect.bEffectOn and CEffect.bReadyToEnd and CEffect.iEndId == CEffect.SPECIAL_ENDING_TYPE_BUTTON then
            CEffect.SpecialEndingButtonPressButton()
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
