--[[
    Название: Танцы на выживание / Супертанцы
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
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
    TargetScore = 1,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
    Scoreboard = 
    {
        GridCols = 4,
        GridRows = 2,
        HeaderWidget = {},
        BottomWidget = {Text = "", Icon = "timer"},
        GameStatsWidgets = {}
    },
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
    bAnimated = false,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}

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

    iPrevTickTime = CTime.unix()

    local err = CAudio.PreloadFile("audio_v2/"..tGame["SongName"])
    if err ~= nil then error(err); end

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end

    tGame.iMinX = 1
    tGame.iMinY = 1
    tGame.iMaxX = tGame.Cols
    tGame.iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        tGame.iMinX = AL.NFZ.iMinX
        tGame.iMinY = AL.NFZ.iMinY
        tGame.iMaxX = AL.NFZ.iMaxX
        tGame.iMaxY = AL.NFZ.iMaxY
    end
    tGame.CenterX = math.floor((tGame.iMaxX-tGame.iMinX+1)/2)
    tGame.CenterY = math.ceil((tGame.iMaxY-tGame.iMinY+1)/2)

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
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)

    if tConfig.SingleTeam then
        tPlayerInGame[1] = true

        if CGameMode.bCanAutoStart and not CGameMode.bCountDownStarted then
            CGameMode.StartCountDown(5)
        end

        tGameResults.PlayersCount = 1
        CGameMode.iRealPlayerCount = 1
    else
        local iStartX = tGame.iMinX + 2
        local iStartY = tGame.iMinY + 1
        local POS_SIZE = math.floor((tGame.iMaxY-tGame.iMinY+1) / math.ceil(#CGameMode.tPlayerColors/2))

        CGameMode.iMaxPlayers = 0
        local iPlayersReadyCount = 0

        for iPlayerID = 1, #CGameMode.tPlayerColors do
            CGameMode.iMaxPlayers = CGameMode.iMaxPlayers + 1

            local iBright = 1
            if tPlayerInGame[iPlayerID] then iBright = 3; end

            local bClick = false
            for iX = iStartX, iStartX + POS_SIZE-1 do
                for iY = iStartY, iStartY + POS_SIZE-1 do
                    tFloor[iX][iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                    tFloor[iX][iY].iBright = iBright

                    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick then
                        bClick = true
                    end
                end
            end

            if bClick or (CGameMode.bCountDownStarted and tPlayerInGame[iPlayerID]) then
                tPlayerInGame[iPlayerID] = true
                iPlayersReadyCount = iPlayersReadyCount + 1
            elseif not CGameMode.bCountDownStarted then
                tPlayerInGame[iPlayerID] = false
            end

            iStartX = iStartX + 2 + POS_SIZE
            if iStartX+POS_SIZE-1 >= tGame.iMaxX then
                iStartX = tGame.iMinX+2
                iStartY = iStartY + 3 + POS_SIZE
                if iStartY+POS_SIZE-1 >= tGame.iMaxY then break; end
            end
        end

        if not CGameMode.bCountDownStarted then 
            if CGameMode.bCanAutoStart and iPlayersReadyCount > 1 then
                CGameMode.StartCountDown(10)
            end
        end

        tGameResults.PlayersCount = iPlayersReadyCount
        CGameMode.iRealPlayerCount = iPlayersReadyCount
    end

    CGameMode.UpdateGameStats()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CGameMode.PaintFlickers()
    CObjects.Paint()
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
CGameMode.bCountDownStarted = false
CGameMode.bCanAutoStart = false

CGameMode.iMaxPlayers = 1
CGameMode.iRealPlayerCount = 1
CGameMode.iWinnerID = 1

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.GREEN
CGameMode.tPlayerColors[2] = CColors.RED
CGameMode.tPlayerColors[3] = CColors.BLUE
CGameMode.tPlayerColors[4] = CColors.CYAN
CGameMode.tPlayerColors[5] = CColors.YELLOW
CGameMode.tPlayerColors[6] = CColors.MAGENTA
CGameMode.tPlayerColors[7] = CColors.WHITE

CGameMode.EFFECT_TYPE_COIN = 1
CGameMode.EFFECT_TYPE_PULSE = 2
CGameMode.EFFECT_TYPE_GUN = 3
CGameMode.EFFECT_TYPE_MAX = 3

CGameMode.iCurrentEffectType = 1

CGameMode.iRandCoinPlayerId = 1

CGameMode.tPlayerScores = {}
CGameMode.tCoinsSpawnedForPlayer = {}
CGameMode.tFlickers = AL.Stack()

CGameMode.iTeamLives = 0

CGameMode.InitGameMode = function()
    CObjects.iBright = tConfig.MinBright
    CObjects.MAX_COINS_DISPLAYED = tGame.iMaxX + tGame.iMaxY - tGame.iMinX - tGame.iMinY
    CGameMode.iTeamLives = tConfig.TeamLives
end

CGameMode.Announcer = function()
    local sVoice = "superdance/superdance-rules-single.mp3"
    if not tConfig.SingleTeam then
        sVoice = "superdance/superdance-rules-mp.mp3"
    end

    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync(sVoice)
        if not tConfig.SingleTeam then
            CAudio.PlayVoicesSync("choose-color.mp3")
        end
        AL.NewTimer(CAudio.GetVoicesDuration(sVoice) * 1000, function()
            CGameMode.bCanAutoStart = true
        end)    
    else
        CGameMode.bCanAutoStart = true
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown
        tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            if CGameMode.iCountdown <= 5 then
                CAudio.ResetSync()
                CAudio.PlayLeftAudio(CGameMode.iCountdown)
            end

            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    iGameState = GAMESTATE_GAME

    CAudio.ResetSync()

    CAudio.PlayDanceSync(tGame["SongName"])
    CGameMode.LoadSongEvents()

    CEffects.tLoadEffect[CGameMode.iCurrentEffectType]()

    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        if CObjects.iBright > tConfig.MinBright then CObjects.iBright = CObjects.iBright - 1; end

        return 100
    end)

    AL.NewTimer(tConfig.TickRate, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CObjects.Tick()

        return tConfig.TickRate
    end)

    AL.NewTimer(1000, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration
        if tGameStats.StageLeftDuration <= 0 then
            CGameMode.EndGame(true)
            return nil
        end

        for iObjectID = 1, CObjects.tObjects.Size() do
            local tObject = CObjects.tObjects.Pop()
            if tObject.iType == CObjects.OBJECT_TYPE_COIN then
                tObject.iFadeTicks = tObject.iFadeTicks - 1
            end
            CObjects.tObjects.Push(tObject)
        end

        return 1000
    end)
end

CGameMode.EndGame = function(bVictory)  
    CAudio.ResetSync()
    iGameState = GAMESTATE_POSTGAME

    if bVictory then
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)

        if tConfig.SingleTeam then
            CGameMode.iWinnerID = 1
        else
            local iMaxScore = -999
            for iPlayerID = 1, CGameMode.iMaxPlayers do
                if tPlayerInGame[iPlayerID] and CGameMode.tPlayerScores[iPlayerID] > iMaxScore then
                    CGameMode.iWinnerID = iPlayerID
                    iMaxScore = CGameMode.tPlayerScores[iPlayerID]
                end
            end

            CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[CGameMode.iWinnerID])
        end
        
        CAudio.PlayVoicesSync(CAudio.VICTORY)

        SetGlobalColorBright(CGameMode.tPlayerColors[CGameMode.iWinnerID], tConfig.MaxBright)
        tGameResults.Color = CGameMode.tPlayerColors[CGameMode.iWinnerID]
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)

        SetGlobalColorBright(CColors.RED, tConfig.MaxBright)
        tGameResults.Color = CColors.RED
    end

    tGameResults.Won = bVictory

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.NewEffectType = function()
    local iNew = 0
    if CObjects.iCoinsDisplayed < 10 and CGameMode.iCurrentEffectType ~= CGameMode.EFFECT_TYPE_COIN then
        iNew = CGameMode.EFFECT_TYPE_COIN
    else
        repeat iNew = math.random(1, CGameMode.EFFECT_TYPE_MAX)
        until iNew ~= CGameMode.iCurrentEffectType
    end

    if iNew == CGameMode.EFFECT_TYPE_COIN and CObjects.iCoinsDisplayed > CObjects.MAX_COINS_DISPLAYED then iNew = CGameMode.EFFECT_TYPE_GUN end

    CGameMode.iCurrentEffectType = iNew
    CEffects.tLoadEffect[CGameMode.iCurrentEffectType]()
end

CGameMode.LoadSongEvents = function()
    for iBatchID = 1, #tGame.Song+1 do
        if tGame.Song[iBatchID] then
            if iBatchID < #tGame.Song then
                AL.NewTimer(100 + tGame.Song[iBatchID][1], function()
                    CGameMode.SongEvent(iBatchID)
                end)
            else
                tGameStats.StageLeftDuration = math.floor(tGame.Song[iBatchID][1]/1000) + 10
                tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration
            end
        end
    end
end

CGameMode.SongEvent = function(iBatchID)
    local iCount = 0
    for i = 2, #tGame.Song[iBatchID] do
        if tGame.Song[iBatchID][i] ~= "N" then
            iCount = iCount + 1
        end
    end

    if iCount > 0 then
        CObjects.iBright = tConfig.MaxBright
        CGameMode.FlickFlickers()

        if iCount > 1 then
            CGameMode.SpawnRandomCoin()
        end

        if iCount > 3 then
            CGameMode.NewEffectType()
        end

        CEffects.tSpawnEffect[CGameMode.iCurrentEffectType]()

        if iBatchID > 10 and tGame.Song[iBatchID+1][1] - tGame.Song[iBatchID][1] > 500 then
            CGameMode.NewEffectType()
        end
    end
end

CGameMode.GetRandomPlayerID = function()
    if tConfig.SingleTeam then return 1; end

    local iPlayerID = 1
    repeat 
        iPlayerID = math.random(1, CGameMode.iMaxPlayers)
    until tPlayerInGame[iPlayerID]

    return iPlayerID
end

CGameMode.GetLeastCoinsPlayer = function()
    if tConfig.SingleTeam then return 1 end

    local iMin = 99999
    local iFound = 1
    for iPlayerID = 1, CGameMode.iMaxPlayers do 
        if tPlayerInGame[iPlayerID] and (CGameMode.tCoinsSpawnedForPlayer[iPlayerID] or 0) < iMin then
            iMin = CGameMode.tCoinsSpawnedForPlayer[iPlayerID] or 0
            iFound = iPlayerID
        end
    end

    return iFound
end

CGameMode.AddScoreToPlayer = function(iPlayerID, iAmount)
    CGameMode.tPlayerScores[iPlayerID] = (CGameMode.tPlayerScores[iPlayerID] or 0) + iAmount
    tGameResults.Score = tGameResults.Score + 1

    if not tConfig.SingleTeam and CGameMode.tPlayerScores[iPlayerID] > tGameStats.TargetScore then
        tGameStats.TargetScore = CGameMode.tPlayerScores[iPlayerID]
    end

    CGameMode.UpdateGameStats()
end

CGameMode.DamageTeam = function()
    CGameMode.iTeamLives = CGameMode.iTeamLives - 1

    CGameMode.UpdateGameStats()

    tGameResults.Score = tGameResults.Score - 1

    if CGameMode.iTeamLives <= 0 then
        CGameMode.EndGame(false)
    else
        CAudio.PlaySystemAsync("superdance/dance_misclick"..math.random(1,3)..".mp3")
    end
end

CGameMode.SpawnRandomCoin = function()
    local iX = 1
    local iY = 1
    repeat
        iX = math.random(tGame.iMinX, tGame.iMaxX)
        iY = math.random(tGame.iMinY, tGame.iMaxY)
    until tFloor[iX] and tFloor[iX][iY] and tFloor[iX][iY].iColor == CColors.NONE and not tFloor[iX][iY].bDefect

    if not tConfig.SingleTeam then
        repeat
            CGameMode.iRandCoinPlayerId = CGameMode.iRandCoinPlayerId + 1
            if CGameMode.iRandCoinPlayerId > CGameMode.iMaxPlayers then CGameMode.iRandCoinPlayerId = 1 end
        until tPlayerInGame[CGameMode.iRandCoinPlayerId]
    end

    CObjects.NewObject(iX, iY, CObjects.OBJECT_TYPE_COIN, CObjects.OBJECT_SHAPE_TYPE_NONE, CGameMode.iRandCoinPlayerId)
    if tConfig.SingleTeam then tGameStats.TargetScore = tGameStats.TargetScore + 1 end

    CGameMode.UpdateGameStats()
end

CGameMode.UpdateGameStats = function()
    tGameStats.Scoreboard.GameStatsWidgets = {}  

    if tConfig.SingleTeam then
        tGameStats.Scoreboard.GridRows = 1

        tGameStats.Scoreboard.GameStatsWidgets[1] =             
        {
            Type = "progress_bar",
            Position = {Col = 0, ColSpan = 2, Row = 0, RowSpan = 1},
            Value = (CGameMode.tPlayerScores[1] or 0)/tGameStats.TargetScore*100,
            Label = CGameMode.tPlayerScores[1] or 0,
            Color = CGameMode.tPlayerColors[1]
        }
        tGameStats.Scoreboard.GameStatsWidgets[2] =             
        {
            Type = "image_text",
            Position = {Col = 2, ColSpan = 2, Row = 0, RowSpan = 1},
            Icon = "heart",
            Text = CGameMode.iTeamLives,
            TextPosition = "inside"
        }
    else
        tGameStats.Scoreboard.GridRows = 0 
    
        local iTruePlayer = 0
        for iPlayerID = 1, #CGameMode.tPlayerColors do
            if tPlayerInGame[iPlayerID] then
                iTruePlayer = iTruePlayer + 1

                local iCol = 2
                if iTruePlayer % 2 ~= 0 then
                    tGameStats.Scoreboard.GridRows = tGameStats.Scoreboard.GridRows + 1
                    iCol = 0
                end

                tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets+1] =             
                {
                    Type = "progress_bar",
                    Position = {Col = iCol, ColSpan = 2, Row = tGameStats.Scoreboard.GridRows-1, RowSpan = 1},
                    Value = (CGameMode.tPlayerScores[iPlayerID] or 0)/tGameStats.TargetScore*100,
                    Label = CGameMode.tPlayerScores[iPlayerID] or 0,
                    Color = CGameMode.tPlayerColors[iPlayerID]
                }
            end
        end
    end
end

CGameMode.AddPixelFlicker = function(iX, iY)
    local tFlicker = {}
    tFlicker.iX = iX
    tFlicker.iY = iY
    tFlicker.iBright = tConfig.MinBright+2
    tFlicker.bVis = false

    tFloor[iX][iY].bAnimated = true

    CGameMode.tFlickers.Push(tFlicker)
end

CGameMode.PaintFlickers = function()
    for i = 1, CGameMode.tFlickers.Size() do
        local tFlicker = CGameMode.tFlickers.Pop()
        if tFlicker.bVis then
            tFloor[tFlicker.iX][tFlicker.iY].iColor = CColors.MAGENTA
            tFloor[tFlicker.iX][tFlicker.iY].iBright = tFlicker.iBright
        end
        CGameMode.tFlickers.Push(tFlicker)
    end
end

CGameMode.FlickFlickers = function()
    for i = 1, CGameMode.tFlickers.Size() do
        local tFlicker = CGameMode.tFlickers.Pop()

        tFlicker.bVis = not tFlicker.bVis
        if tFlicker.bVis then
            tFlicker.iBright = tFlicker.iBright - 1
        end

        if tFlicker.iBright > 0 then
            CGameMode.tFlickers.Push(tFlicker)
        else
            tFloor[tFlicker.iX][tFlicker.iY].bAnimated = false
        end
    end    

    for iObjectID = 1, CObjects.tObjects.Size() do
        local tObject = CObjects.tObjects.Pop()
        if tObject.iType ~= CObjects.OBJECT_TYPE_COIN or tObject.iFadeTicks > 0 then
            CObjects.tObjects.Push(tObject)
        else
            CObjects.iCoinsDisplayed = CObjects.iCoinsDisplayed - 1
        end
    end
end
--//

--Effects
CEffects = {}
CEffects.tLoadEffect = {}
CEffects.tSpawnEffect = {}

----Coin
CEffects.tLoadEffect[CGameMode.EFFECT_TYPE_COIN] = function()
    CEffects.iCoinX = math.random(tGame.iMinX+3, tGame.iMaxX-3)
    CEffects.iCoinY = math.random(tGame.iMinY+3, tGame.iMaxY-3)

    CEffects.iCoinVelX = 1
    if CEffects.iCoinX > tGame.CenterX then CEffects.iCoinVelX = -1 end
    CEffects.iCoinVelY = 0
    if math.random(0,1) == 1 then
        CEffects.iCoinVelY = 1
        if CEffects.iCoinY > tGame.CenterY then CEffects.iCoinVelY = -1 end
    end 

    CEffects.iCoinSpawned = 0
    if tConfig.SingleTeam then
        CEffects.iCoinToSpawn = math.random(6,12)
    else
        CEffects.iCoinToSpawn = 3*CGameMode.iRealPlayerCount
    end
end

CEffects.tSpawnEffect[CGameMode.EFFECT_TYPE_COIN] = function()
    local iPrevX = CEffects.iCoinX
    local iPrevY = CEffects.iCoinY
    local iRepCount = 0
    repeat
        CEffects.iCoinX = iPrevX + (CEffects.iCoinVelX*math.random(1,3)) + math.random(-2,2) + math.random(-iRepCount, iRepCount)
        CEffects.iCoinY = iPrevY + (CEffects.iCoinVelY*math.random(1,3)) + math.random(-2,2) + math.random(-iRepCount, iRepCount)

        iRepCount = iRepCount + 1
        if iRepCount > tGame.Cols then CGameMode.NewEffectType(); return; end
    until tFloor[CEffects.iCoinX] and tFloor[CEffects.iCoinX][CEffects.iCoinY] and tFloor[CEffects.iCoinX][CEffects.iCoinY].iColor == CColors.NONE and not tFloor[CEffects.iCoinX][CEffects.iCoinY].bDefect

    CObjects.NewObject(CEffects.iCoinX, CEffects.iCoinY, CObjects.OBJECT_TYPE_COIN, CObjects.OBJECT_SHAPE_TYPE_NONE, CGameMode.GetLeastCoinsPlayer())
    CEffects.iCoinSpawned = CEffects.iCoinSpawned + 1
    if tConfig.SingleTeam then tGameStats.TargetScore = tGameStats.TargetScore + 1 end
    
    if CEffects.iCoinX < tGame.iMinX+3 then CEffects.iCoinVelX = 1 end
    if CEffects.iCoinX > tGame.iMaxX-3 then CEffects.iCoinVelX = -1 end
    if CEffects.iCoinY < tGame.iMinY+3 then CEffects.iCoinVelY = 1 end
    if CEffects.iCoinY > tGame.iMaxY-3 then CEffects.iCoinVelY = -1 end

    if CEffects.iCoinSpawned >= CEffects.iCoinToSpawn then
        CGameMode.NewEffectType()
    end

    CGameMode.UpdateGameStats()
end
----//

----Pulse
CEffects.tLoadEffect[CGameMode.EFFECT_TYPE_PULSE] = function()
    CEffects.tPulseShapes = {}
    CEffects.iPulsePosX = math.random(1, tGame.Cols)
    CEffects.iPulsePosY = math.random(1, tGame.Rows)
    CEffects.iPulseCount = 0
    CEffects.iPulseTotal = math.random(1,3)
end

CEffects.tSpawnEffect[CGameMode.EFFECT_TYPE_PULSE] = function()
    CObjects.NewObject(CEffects.iPulsePosX, CEffects.iPulsePosY, CObjects.OBJECT_TYPE_LAVA_EXPANDING_SHAPE, CObjects.OBJECT_SHAPE_TYPE_CIRC, CGameMode.GetLeastCoinsPlayer())

    CEffects.iPulseCount = CEffects.iPulseCount + 1

    if CEffects.iPulseCount >= CEffects.iPulseTotal then
        CGameMode.NewEffectType()
    end
end
----//

----Gun
CEffects.tLoadEffect[CGameMode.EFFECT_TYPE_GUN] = function()
    CEffects.iGunSize = math.random(2,4)
    CEffects.iGunX = math.random(1,tGame.Cols-CEffects.iGunSize)
    CEffects.iGunVel = math.random(0,1) if CEffects.iGunVel == 0 then CEffects.iGunVel = 1 end
    CEffects.bGunTop = true if math.random(1,2) == 2 then CEffects.bGunTop = false end
    CEffects.iGunShots = 0
    CEffects.iGunTotal = math.random(6,12)
end

CEffects.tSpawnEffect[CGameMode.EFFECT_TYPE_GUN] = function()
    CEffects.iGunX = CEffects.iGunX + (CEffects.iGunSize*CEffects.iGunVel)
    if (CEffects.iGunVel == -1 and CEffects.iGunX <= 1) or (CEffects.iGunVel == 1 and CEffects.iGunX+CEffects.iGunSize > tGame.Cols) then
        CEffects.iGunVel = -CEffects.iGunVel
    else
        local iY = tGame.Rows 
        local iVelY = -1 
        if CEffects.bGunTop then
            iY = 1
            iVelY = 1
        end

        CObjects.NewObject(CEffects.iGunX, iY, CObjects.OBJECT_TYPE_LAVA_STATIC_SHAPE, CObjects.OBJECT_SHAPE_TYPE_RECT, CGameMode.GetLeastCoinsPlayer(), function(tObject)
            tObject.iShapeSize = CEffects.iGunSize
            tObject.iVelY = iVelY
            tObject.tShape = AL.Shapes.NewRectangle(CEffects.iGunSize, 1, false)

            return tObject
        end)

        CEffects.iGunShots = CEffects.iGunShots + 1
        if CEffects.iGunShots > CEffects.iGunTotal then
            CGameMode.NewEffectType()
        end
    end
end
----//

--//

--Objects
CObjects = {}
CObjects.tObjects = AL.Stack()

CObjects.OBJECT_TYPE_COIN = 1
CObjects.OBJECT_TYPE_LAVA_STATIC_SHAPE = 2
CObjects.OBJECT_TYPE_LAVA_EXPANDING_SHAPE = 3

CObjects.OBJECT_SHAPE_TYPE_NONE = 0
CObjects.OBJECT_SHAPE_TYPE_RECT = 1
CObjects.OBJECT_SHAPE_TYPE_CIRC = 2
CObjects.OBJECT_SHAPE_TYPE_TRIG = 3
CObjects.OBJECT_SHAPE_TYPE_RHMB = 4

CObjects.MAX_COINS_DISPLAYED = 50

CObjects.iBright = 0
CObjects.iCoinsDisplayed = 0

CObjects.NewObject = function(iX, iY, iType, iShapeType, iPlayerID, fInitObj)
    local tObject = {}

    tObject.iX = iX
    tObject.iY = iY
    tObject.iType = iType
    tObject.iShapeType = iShapeType
    tObject.iShapeSize = 1
    tObject.iPlayerID = iPlayerID
    tObject.iVelX = 0
    tObject.iVelY = 0
    tObject.bClicked = false
    tObject.bSpecialPixel = false
    tObject.iFadeTicks = 6
    tObject.bCooldown = false

    if iType == CObjects.OBJECT_TYPE_COIN then
        if CObjects.iCoinsDisplayed >= CObjects.MAX_COINS_DISPLAYED then return; end
        CObjects.iCoinsDisplayed = CObjects.iCoinsDisplayed + 1

        if tConfig.SingleTeam and CGameMode.iTeamLives < tConfig.TeamLives*1.5 and math.random(1,12) == 6 then
            tObject.bSpecialPixel = true
        end
    end

    if not tConfig.SingleTeam and iPlayerID then
        CGameMode.tCoinsSpawnedForPlayer[iPlayerID] = (CGameMode.tCoinsSpawnedForPlayer[iPlayerID] or 0) + 1
    end

    tObject.tShape = CObjects.GetShapeForObject(tObject.iShapeType, tObject.iShapeSize)

    if fInitObj then tObject = fInitObj(tObject) end
    CObjects.tObjects.Push(tObject)
end

CObjects.GetColorForObject = function(tObject)
    if (tObject.iType == CObjects.OBJECT_TYPE_COIN or not tConfig.SingleTeam) and tObject.iPlayerID ~= nil then
        if tObject.bSpecialPixel then return CColors.BLUE end
        return CGameMode.tPlayerColors[tObject.iPlayerID]
    else
        if tObject.bClicked and tConfig.SingleTeam then return CColors.MAGENTA; end
        return CColors.RED
    end
end

CObjects.Paint = function()
    for iObjectID = 1, CObjects.tObjects.Size() do
        local tObject = CObjects.tObjects.Pop()
        local bRemove = false
        local bClick = false
        local tClicksPos = {}

        local iBright = CObjects.iBright
        if tObject.iType == CObjects.OBJECT_TYPE_COIN and tObject.iFadeTicks <= tConfig.MinBright then
            iBright = iBright - (tConfig.MinBright+1 - tObject.iFadeTicks)
            if iBright < 1 then iBright = 1 end
        end

        if tObject.tShape ~= nil then
            for iPixel = 1, #tObject.tShape do
                if CObjects.PaintPixel(tObject.iX + tObject.tShape[iPixel].iX, tObject.iY + tObject.tShape[iPixel].iY, CObjects.GetColorForObject(tObject), iBright) then 
                    bClick = true 
                    tClicksPos[#tClicksPos+1] = {iX = tObject.iX + tObject.tShape[iPixel].iX, iY = tObject.iY + tObject.tShape[iPixel].iY}
                end
            end
        else
            bClick = CObjects.PaintPixel(tObject.iX, tObject.iY, CObjects.GetColorForObject(tObject), iBright)
        end

        if bClick and not tObject.bClicked and not tObject.bCooldown then
            if tObject.iType == CObjects.OBJECT_TYPE_COIN then
                bRemove = true
                CObjects.iCoinsDisplayed = CObjects.iCoinsDisplayed - 1

                if tConfig.SingleTeam then
                    CGameMode.AddScoreToPlayer(1, 1)

                    if tObject.bSpecialPixel then
                        CGameMode.iTeamLives = CGameMode.iTeamLives + 1
                    end
                else
                    CGameMode.AddScoreToPlayer(tObject.iPlayerID, 1)
                end
            elseif tObject.iType == CObjects.OBJECT_TYPE_LAVA_STATIC_SHAPE or tObject.iType == CObjects.OBJECT_TYPE_LAVA_EXPANDING_SHAPE then
                AL.NewTimer(tGame.BurnDelay, function()
                    local bCheck = false
                    for iClickPos = 1, #tClicksPos do
                        if tFloor[tClicksPos[iClickPos].iX][tClicksPos[iClickPos].iY].bClick and not tFloor[tClicksPos[iClickPos].iX][tClicksPos[iClickPos].iY].bDefect and not tFloor[tClicksPos[iClickPos].iX][tClicksPos[iClickPos].iY].bAnimated then
                            bCheck = true
                            if tConfig.SingleTeam then
                                CGameMode.AddPixelFlicker(tClicksPos[iClickPos].iX, tClicksPos[iClickPos].iY)
                            end

                            break;
                        end
                    end

                    if bCheck then
                        if tConfig.SingleTeam then
                            tObject.bClicked = true
                            CGameMode.DamageTeam()
                        elseif tObject.iPlayerID ~= nil then
                            CGameMode.AddScoreToPlayer(tObject.iPlayerID, 1)
                        
                            tObject.bCooldown = true
                            AL.NewTimer(250, function()
                                tObject.bCooldown = false
                            end)
                        end
                    end
                end)
            end
        end

        if not bRemove then
            CObjects.tObjects.Push(tObject)
        end
    end
end

CObjects.PaintPixel = function(iX, iY, iColor, iBright)
    if tFloor[iX] and tFloor[iX][iY] then
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = iBright

        if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
            return true
        end
    end

    return false
end

CObjects.Tick = function()
    for iObjectID = 1, CObjects.tObjects.Size() do
        local tObject = CObjects.tObjects.Pop()
        local bPush = true

        if tObject.iType == CObjects.OBJECT_TYPE_LAVA_EXPANDING_SHAPE and tObject.iShapeType > CObjects.OBJECT_SHAPE_TYPE_NONE then
            tObject.iShapeSize = tObject.iShapeSize + 1
            tObject.tShape = CObjects.GetShapeForObject(tObject.iShapeType, tObject.iShapeSize)

            bPush = tObject.iShapeSize < tGame.Cols + tGame.Rows
        elseif tObject.iType == CObjects.OBJECT_TYPE_LAVA_STATIC_SHAPE then
            tObject.iX = tObject.iX + tObject.iVelX
            tObject.iY = tObject.iY + tObject.iVelY

            bPush = tObject.iX+tObject.iShapeSize > 1 and tObject.iX-tObject.iShapeSize < tGame.Cols and tObject.iY+tObject.iShapeSize > 1 and tObject.iY-tObject.iShapeSize < tGame.Rows
        end

        if bPush then
            CObjects.tObjects.Push(tObject)
        end
    end
end

CObjects.GetShapeForObject = function(iShapeType, iShapeSize)
    if iShapeType == CObjects.OBJECT_SHAPE_TYPE_RECT then
        return AL.Shapes.NewRectangle(iShapeSize, iShapeSize, false)
    elseif iShapeType == CObjects.OBJECT_SHAPE_TYPE_CIRC then
        return AL.Shapes.NewCircle(iShapeSize, false)
    elseif iShapeType == CObjects.OBJECT_SHAPE_TYPE_TRIG then
        return AL.Shapes.NewTriangle(iShapeSize, false)
    elseif iShapeType == CObjects.OBJECT_SHAPE_TYPE_RHMB then
        return AL.Shapes.NewRhombus(iShapeSize, false)
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
    for i = iX, iX + iSizeX-1 do
        for j = iY, iY + iSizeY-1 do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
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

function SetAllButtonColorBright(iColor, iBright, bCheckDefect)
    for i, tButton in pairs(tButtons) do
        if not bCheckDefect or not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end

function ReverseTable(t)
    for i = 1, #t/2, 1 do
        t[i], t[#t-i+1] = t[#t-i+1], t[i]
    end
    return t
end

function ShuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end

    return t
end

function TableConcat(...)
    local tR = {}
    local i = 1
    local function addtable(t)
        for j = 1, #t do
            tR[i] = t[j]
            i = i + 1
        end
    end

    for _,t in pairs({...}) do
        addtable(t)
    end

    return tR
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
        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
            return;
        end

        if iGameState == GAMESTATE_SETUP then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
                tFloor[click.X][click.Y].bHold = false
            elseif not tFloor[click.X][click.Y].bHold then
                tFloor[click.X][click.Y].bHold = true
                AL.NewTimer(1000, function()
                    if tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bClick = false
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end
