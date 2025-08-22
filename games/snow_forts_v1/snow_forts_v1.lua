--[[
    Название: Снежные Крепости
    Автор: Avondale, дискорд - avonda
    Описание механики: 

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
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
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
    iTeamID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

tPlayerInGame = {}

local tPlayerColors = {}
tPlayerColors[1] = CColors.GREEN
tPlayerColors[2] = CColors.YELLOW
tPlayerColors[3] = CColors.BLUE
tPlayerColors[4] = CColors.MAGENTA

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

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end

    tGame.iMinX = 1
    tGame.iMinY = 1
    tGame.iMaxX = tGame.Cols
    tGame.iMaxY = tGame.Rows

    tGame.iCenterY = math.floor(tGame.Rows/2)
    if AL.NFZ.bLoaded then
        tGame.iMinX = AL.NFZ.iMinX
        tGame.iMinY = AL.NFZ.iMinY
        tGame.iMaxX = AL.NFZ.iMaxX
        tGame.iMaxY = AL.NFZ.iMaxY

        tGame.CenterX = AL.NFZ.iCenterX
        tGame.CenterY = AL.NFZ.iCenterY
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
    CForts.Paint()

    local iPlayersReady = 0

    for iPlayerID = 1, #CForts.tForts do
        if CheckPositionClick(CForts.tForts[iPlayerID].iX, CForts.tForts[iPlayerID].iY, CForts.iFortSize) then
            tPlayerInGame[iPlayerID] = true
            tGameStats.Players[iPlayerID].Score = tConfig.FortHealth

            tGameStats.Players[iPlayerID].Color = tPlayerColors[iPlayerID]
        elseif not CGameMode.bCountDownStarted then
            AL.NewTimer(250, function()
                if not CheckPositionClick(CForts.tForts[iPlayerID].iX, CForts.tForts[iPlayerID].iY, CForts.iFortSize) and not CGameMode.bCountDownStarted then
                    tPlayerInGame[iPlayerID] = false
                    tGameStats.Players[iPlayerID].Color = CColors.NONE
                    tGameStats.Players[iPlayerID].Score = 0
                end
            end)
        end

        if tPlayerInGame[iPlayerID] then iPlayersReady = iPlayersReady + 1; end
    end

    if bAnyButtonClick or (iPlayersReady >= 4 and CGameMode.bCanAutoStart) then
        bAnyButtonClick = false
        if iPlayersReady < 1 or CGameMode.bCountDownStarted then return; end

        CGameMode.StartCountDown(3)
    end

    tGameResults.PlayersCount = iPlayersReady
end

function GameTick()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if tFloor[iX][iY].iTeamID == 0 then
                tFloor[iX][iY].iColor = CColors.NONE
                tFloor[iX][iY].iBright = CColors.BRIGHT0
            else
                tFloor[iX][iY].iColor = tPlayerColors[tFloor[iX][iY].iTeamID]
                tFloor[iX][iY].iBright = tConfig.Bright

                if tFloor[iX][iY].bDefect or tFloor[iX][iY].bClick then
                    CGameMode.PlayerCollectSnowball(tFloor[iX][iY].iTeamID)
                    tFloor[iX][iY].iTeamID = 0
                end
            end
        end
    end


    CForts.Paint()
    CProjectiles.Paint()
    CShields.Paint()
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
CGameMode.bCanAutoStart = false
CGameMode.iCountdown = 0
CGameMode.bCountDownStarted = false

CGameMode.iSnowballZoneStartX = 0
CGameMode.iSnowballZoneStartY = 0
CGameMode.iSnowballZoneEndX = 0
CGameMode.iSnowballZoneEndY = 0

CGameMode.iMaxSnowballsSpawned = 0
CGameMode.iCurrentSnowballSpawnedCount = 0

CGameMode.iAlivePlayerCount = 0

CGameMode.InitGameMode = function()
    tGameStats.TargetScore = tConfig.FortHealth

    CForts.iFortSize = math.floor(tGame.Rows/3)
    CForts.iMaxSnowballs = (CForts.iFortSize-2) * (CForts.iFortSize-2)

    CForts.NewFort(tGame.iMinX, tGame.iMinY)
    CShields.NewShield(1, CForts.tForts[1].iX+CForts.iFortSize, CForts.tForts[1].iY, 1, 2, CForts.tForts[1].iX+CForts.iFortSize, CForts.tForts[1].iY+CForts.iFortSize-1)
    CShields.NewShield(1, CForts.tForts[1].iX, CForts.tForts[1].iY+CForts.iFortSize, 2, 1, CForts.tForts[1].iX+CForts.iFortSize-1, CForts.tForts[1].iY+CForts.iFortSize)

    CForts.NewFort(tGame.iMaxX - CForts.iFortSize+1, tGame.iMinY)
    CShields.NewShield(2, CForts.tForts[2].iX-1, CForts.tForts[2].iY, 1, 2, CForts.tForts[2].iX-1, CForts.tForts[2].iY+CForts.iFortSize-1)
    CShields.NewShield(2, CForts.tForts[2].iX-1, CForts.tForts[2].iY+CForts.iFortSize, 2, 1, CForts.tForts[2].iX+CForts.iFortSize-1, CForts.tForts[2].iY+CForts.iFortSize)    

    CForts.NewFort(tGame.iMinX, tGame.iMaxY - CForts.iFortSize+1)
    CShields.NewShield(3, CForts.tForts[3].iX+CForts.iFortSize, CForts.tForts[3].iY-1, 1, 2, CForts.tForts[3].iX+CForts.iFortSize, CForts.tForts[3].iY+CForts.iFortSize-1)
    CShields.NewShield(3, CForts.tForts[3].iX, CForts.tForts[3].iY-1, 2, 1, CForts.tForts[3].iX+CForts.iFortSize-1, CForts.tForts[3].iY-1)

    CForts.NewFort(tGame.iMaxX - CForts.iFortSize+1, tGame.iMaxY - CForts.iFortSize+1)
    CShields.NewShield(4, CForts.tForts[4].iX-1, CForts.tForts[4].iY, 1, 2, CForts.tForts[4].iX-1, CForts.tForts[4].iY+CForts.iFortSize-1)
    CShields.NewShield(4, CForts.tForts[4].iX, CForts.tForts[4].iY-1, 2, 1, CForts.tForts[4].iX+CForts.iFortSize-1, CForts.tForts[4].iY-1)

    CGameMode.iSnowballZoneStartX = CForts.tForts[1].iX + CForts.iFortSize + 2
    CGameMode.iSnowballZoneStartY = CForts.tForts[1].iY + CForts.iFortSize + 1
    CGameMode.iSnowballZoneEndX = CForts.tForts[4].iX - 2
    CGameMode.iSnowballZoneEndY = CForts.tForts[4].iY - 1

    CGameMode.iMaxSnowballsSpawned = tGame.Cols

    CGameMode.iAlivePlayerCount = #CForts.tForts
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("snow-forts/snowforts-guide.mp3")
    CAudio.PlayVoicesSync("choose-color.mp3")
    AL.NewTimer(CAudio.GetVoicesDuration("snow-forts/snowforts-guide.mp3"), function()
        CGameMode.bCanAutoStart = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

    AL.NewTimer(1000, function()
        CAudio.PlaySystemSyncFromScratch("")
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
    iGameState = GAMESTATE_GAME
    
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    CGameMode.SnowBallMachine()
    CForts.CrossHairMovement()
    CShields.Thinker()
    CProjectiles.Thinker()
end

CGameMode.EndGame = function(iWinnerID)
    CGameMode.iWinnerID = iWinnerID

    CAudio.StopBackground()
    iGameState = GAMESTATE_POSTGAME  

    CAudio.PlaySyncFromScratch("")
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)  

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright) 
end

CGameMode.SnowBallMachine = function()
    AL.NewTimer(10, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        if CGameMode.iCurrentSnowballSpawnedCount < CGameMode.iMaxSnowballsSpawned then
            if CGameMode.iCurrentSnowballSpawnedCount < CGameMode.iMaxSnowballsSpawned/2 then
                CGameMode.SpawnSnowBall()
                return 10
            end

            CGameMode.SpawnSnowBall()
            return 100
        else
            return 500
        end
    end)
end

CGameMode.SpawnSnowBall = function()
    local iX = math.random(CGameMode.iSnowballZoneStartX, CGameMode.iSnowballZoneEndX)
    local iY = math.random(CGameMode.iSnowballZoneStartY, CGameMode.iSnowballZoneEndY)

    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].iTeamID == 0 then
        local iTeamID = 0
        local iAttempts = 0

        repeat iTeamID = math.random(1, #CForts.tForts); iAttempts = iAttempts + 1; if iAttempts > #CForts.tForts*2 then return nil; end;
        until CForts.tForts[iTeamID].iSnowballsSpawned <= math.floor(CGameMode.iMaxSnowballsSpawned/#CForts.tForts)

        tFloor[iX][iY].iTeamID = iTeamID
        CForts.tForts[iTeamID].iSnowballsSpawned = CForts.tForts[iTeamID].iSnowballsSpawned + 1 
    end
end

CGameMode.PlayerCollectSnowball = function(iFortID)
    CGameMode.iCurrentSnowballSpawnedCount = CGameMode.iCurrentSnowballSpawnedCount - 1
    CForts.tForts[iFortID].iSnowballsSpawned = CForts.tForts[iFortID].iSnowballsSpawned - 1 

    CForts.AddSnowballs(iFortID, 1)
end
--//

--FORTS
CForts = {}
CForts.tForts = {}
CForts.iFortSize = 5
CForts.iMaxSnowballs = 9

CForts.bMovedToCenter = false

CForts.NewFort = function(iX, iY)
    local iFortID = #CForts.tForts+1
    CForts.tForts[iFortID] = {}
    CForts.tForts[iFortID].iX = iX
    CForts.tForts[iFortID].iY = iY

    CForts.tForts[iFortID].iSnowballsCount = 0
    CForts.tForts[iFortID].iSnowballsSpawned = 0
    CForts.tForts[iFortID].bThrowCooldown = false

    CForts.tForts[iFortID].iCrossHairPosX = iX
    CForts.tForts[iFortID].iCrossHairPosY = iY

    CForts.tForts[iFortID].bAlive = true
end

CForts.Paint = function()
    for iFortID = 1, #CForts.tForts do
        local iSnowballID = 0
        for iX = CForts.tForts[iFortID].iX, CForts.tForts[iFortID].iX + CForts.iFortSize-1 do
            for iY = CForts.tForts[iFortID].iY, CForts.tForts[iFortID].iY + CForts.iFortSize-1 do
                if not CForts.bMovedToCenter or CForts.tForts[iFortID].bAlive then
                    local iColor = CColors.WHITE
                    local iBright = tConfig.Bright

                    if CForts.tForts[iFortID].bAlive then
                        if iX ~= CForts.tForts[iFortID].iX and iX ~= CForts.tForts[iFortID].iX + CForts.iFortSize-1 then
                            if iY ~= CForts.tForts[iFortID].iY and iY ~= CForts.tForts[iFortID].iY + CForts.iFortSize-1 then
                                iColor = tPlayerColors[iFortID]

                                if iGameState == GAMESTATE_SETUP then
                                    if not tPlayerInGame[iFortID] then iBright = 1; end
                                elseif iGameState == GAMESTATE_GAME then
                                    iSnowballID = iSnowballID + 1
                                    if iSnowballID > CForts.tForts[iFortID].iSnowballsCount then
                                        iBright = 1
                                    elseif CForts.tForts[iFortID].bThrowCooldown then
                                        iBright = iBright-1
                                    end

                                    if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                                        if CForts.CanThrowSnowBall(iFortID) then
                                            CForts.ThrowSnowBall(iFortID)
                                        end
                                    end
                                end
                            end
                        end

                        if iGameState == GAMESTATE_GAME then
                            if iX == CForts.tForts[iFortID].iCrossHairPosX and iY == CForts.tForts[iFortID].iCrossHairPosY then
                                iColor = CColors.CYAN
                            end
                        end
                    else
                        iColor = CColors.RED
                        iBright = 1
                    end

                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = iColor
                        tFloor[iX][iY].iBright = iBright
                    end
                end
            end
        end
    end
end

CForts.CrossHairMovement = function()
    for iFortID = 1, #CForts.tForts do
        AL.NewTimer(300, function()
            if iGameState ~= GAMESTATE_GAME or not CForts.tForts[iFortID].bAlive then return nil; end

            if CForts.tForts[iFortID].iCrossHairPosX < CForts.tForts[iFortID].iX + CForts.iFortSize-1 and CForts.tForts[iFortID].iCrossHairPosY == CForts.tForts[iFortID].iY then
                CForts.tForts[iFortID].iCrossHairPosX = CForts.tForts[iFortID].iCrossHairPosX + 1
            elseif CForts.tForts[iFortID].iCrossHairPosX == CForts.tForts[iFortID].iX + CForts.iFortSize-1 and CForts.tForts[iFortID].iCrossHairPosY < CForts.tForts[iFortID].iY + CForts.iFortSize-1 then
                CForts.tForts[iFortID].iCrossHairPosY = CForts.tForts[iFortID].iCrossHairPosY + 1
            elseif CForts.tForts[iFortID].iCrossHairPosX > CForts.tForts[iFortID].iX and CForts.tForts[iFortID].iCrossHairPosY == CForts.tForts[iFortID].iY + CForts.iFortSize-1 then
                CForts.tForts[iFortID].iCrossHairPosX = CForts.tForts[iFortID].iCrossHairPosX - 1
            elseif CForts.tForts[iFortID].iCrossHairPosX == CForts.tForts[iFortID].iX and CForts.tForts[iFortID].iCrossHairPosY > CForts.tForts[iFortID].iY then
                CForts.tForts[iFortID].iCrossHairPosY = CForts.tForts[iFortID].iCrossHairPosY - 1
            end

            if not tFloor[CForts.tForts[iFortID].iCrossHairPosX] or not tFloor[CForts.tForts[iFortID].iCrossHairPosX][CForts.tForts[iFortID].iCrossHairPosY] then
                return 10
            end

            return 300
        end)
    end
end

CForts.AddSnowballs = function(iFortID, iAmount)
    CForts.tForts[iFortID].iSnowballsCount = CForts.tForts[iFortID].iSnowballsCount + iAmount
    if CForts.tForts[iFortID].iSnowballsCount > CForts.iMaxSnowballs then
        CForts.tForts[iFortID].iSnowballsCount = CForts.iMaxSnowballs
    end
end

CForts.GetNextShotVelocity = function(iFortID)
    local iVelX = 0
    local iVelY = 0

    if CForts.tForts[iFortID].iCrossHairPosX == CForts.tForts[iFortID].iX then
        iVelX = -1
    elseif CForts.tForts[iFortID].iCrossHairPosX == CForts.tForts[iFortID].iX + CForts.iFortSize-1 then
        iVelX = 1
    end
    if CForts.tForts[iFortID].iCrossHairPosY == CForts.tForts[iFortID].iY then
        iVelY = -1
    elseif CForts.tForts[iFortID].iCrossHairPosY == CForts.tForts[iFortID].iY + CForts.iFortSize-1 then
        iVelY = 1
    end

    return iVelX, iVelY
end

CForts.CanThrowSnowBall = function(iFortID)
    if CForts.tForts[iFortID].bThrowCooldown or CForts.tForts[iFortID].iSnowballsCount < 1 or not CForts.tForts[iFortID].bAlive then return false; end

    if not tFloor[CForts.tForts[iFortID].iCrossHairPosX] or not tFloor[CForts.tForts[iFortID].iCrossHairPosX][CForts.tForts[iFortID].iCrossHairPosY] then return false; end

    local iVelX, iVelY = CForts.GetNextShotVelocity(iFortID)
    local iNewX = CForts.tForts[iFortID].iCrossHairPosX + iVelX
    local iNewY = CForts.tForts[iFortID].iCrossHairPosY + iVelY
    if not tFloor[iNewX] or not tFloor[iNewX][iNewY] then return false; end

    return true    
end

CForts.ThrowSnowBall = function(iFortID)
    CForts.tForts[iFortID].iSnowballsCount = CForts.tForts[iFortID].iSnowballsCount - 1 
    CForts.tForts[iFortID].bThrowCooldown = true
    AL.NewTimer(600, function()
        CForts.tForts[iFortID].bThrowCooldown = false
    end)

    local iVelX, iVelY = CForts.GetNextShotVelocity(iFortID)
    CProjectiles.NewProjectile(CForts.tForts[iFortID].iCrossHairPosX, CForts.tForts[iFortID].iCrossHairPosY, iVelX, iVelY, iFortID)
end

CForts.DamageFort = function(iFortID)
    tGameStats.Players[iFortID].Score = tGameStats.Players[iFortID].Score-1

    if tGameStats.Players[iFortID].Score <= 0 then
        CForts.KillFort(iFortID)
        return;
    end

    CAudio.PlaySystemAsync("snow-forts/snowball-hit-fort.mp3")
end

CForts.KillFort = function(iFortID)
    CForts.tForts[iFortID].bAlive = false

    for iShieldID = 1, #CShields.tShields do
        if CShields.tShields[iShieldID] and CShields.tShields[iShieldID].iTeamID == iFortID then
            CShields.tShields[iShieldID] = nil
        end
    end

    CGameMode.iAlivePlayerCount = CGameMode.iAlivePlayerCount -1
    if CGameMode.iAlivePlayerCount == 1 then
        for iFortID = 1, #CForts.tForts do
            if CForts.tForts[iFortID].bAlive then
                CGameMode.EndGame(iFortID)
                return;
            end
        end
    elseif CGameMode.iAlivePlayerCount == 2 then
        CAudio.PlayVoicesSync("snow-forts/duel.mp3")

        if CForts.tForts[1].bAlive and CForts.tForts[4].bAlive then
            CForts.Overtime(1,4)
        end

        if CForts.tForts[2].bAlive and CForts.tForts[3].bAlive then
            CForts.Overtime(2,3)
        end

        return;
    end


    CAudio.PlaySystemAsync("game-over.mp3")--sound killed fort   
end

CForts.Overtime = function(iFortID1, iFortID2)
    CForts.bMovedToCenter = true
    local iNewY = tGame.iCenterY+1-math.floor(CForts.iFortSize/2)

    CForts.tForts[iFortID1].iY = iNewY
    CForts.tForts[iFortID1].iCrossHairPosX = CForts.tForts[iFortID1].iX
    CForts.tForts[iFortID1].iCrossHairPosY = CForts.tForts[iFortID1].iY

    CForts.tForts[iFortID2].iY = iNewY
    CForts.tForts[iFortID2].iCrossHairPosX = CForts.tForts[iFortID2].iX
    CForts.tForts[iFortID2].iCrossHairPosY = CForts.tForts[iFortID2].iY

    for iShieldID = 1, #CShields.tShields do
        if CShields.tShields[iShieldID] and CShields.tShields[iShieldID].iSizeY > 1 then
            CShields.tShields[iShieldID].iY = iNewY
            CShields.tShields[iShieldID].iControlYMin = iNewY
            CShields.tShields[iShieldID].iControlYMax = iNewY + CForts.iFortSize
        else
            CShields.tShields[iShieldID] = nil
        end
    end
end
--//

--shields
CShields = {}
CShields.tShields = {}

CShields.NewShield = function(iTeamID, iX, iY, iSizeX, iSizeY, iMaxX, iMaxY)
    local iShieldID = #CShields.tShields+1
    CShields.tShields[iShieldID] = {}
    CShields.tShields[iShieldID].iTeamID = iTeamID
    CShields.tShields[iShieldID].iX = iX
    CShields.tShields[iShieldID].iY = iY
    CShields.tShields[iShieldID].iSizeX = iSizeX
    CShields.tShields[iShieldID].iSizeY = iSizeY

    CShields.tShields[iShieldID].iControlXMin = iX
    CShields.tShields[iShieldID].iControlYMin = iY    
    CShields.tShields[iShieldID].iControlXMax = iMaxX
    CShields.tShields[iShieldID].iControlYMax = iMaxY

    CShields.tShields[iShieldID].iTargetX = 0
    CShields.tShields[iShieldID].iTargetY = 0
end

CShields.Paint = function()
    for iShieldID = 1, #CShields.tShields do
        if CShields.tShields[iShieldID] then
            for iX = CShields.tShields[iShieldID].iX, CShields.tShields[iShieldID].iX + CShields.tShields[iShieldID].iSizeX-1 do
                for iY = CShields.tShields[iShieldID].iY, CShields.tShields[iShieldID].iY + CShields.tShields[iShieldID].iSizeY-1 do
                    tFloor[iX][iY].iColor = tPlayerColors[CShields.tShields[iShieldID].iTeamID]
                    tFloor[iX][iY].iBright = tConfig.Bright
                end
            end
        end
    end
end

CShields.Thinker = function()
    AL.NewTimer(100, function()
        for iShieldID = 1, #CShields.tShields do
            if CShields.tShields[iShieldID] and CForts.tForts[CShields.tShields[iShieldID].iTeamID].bAlive then
                if CShields.tShields[iShieldID].iTargetX == 0 or (CShields.tShields[iShieldID].iX == CShields.tShields[iShieldID].iTargetX and CShields.tShields[iShieldID].iY == CShields.tShields[iShieldID].iTargetY) then
                    for iX = CShields.tShields[iShieldID].iControlXMin, CShields.tShields[iShieldID].iControlXMax do
                        for iY = CShields.tShields[iShieldID].iControlYMin, CShields.tShields[iShieldID].iControlYMax do
                            if tFloor[iX][iY].bClick then 
                                CShields.tShields[iShieldID].iTargetX = iX
                                CShields.tShields[iShieldID].iTargetY = iY

                                if CShields.tShields[iShieldID].iTargetX + CShields.tShields[iShieldID].iSizeX-1 > tGame.iMaxX then CShields.tShields[iShieldID].iTargetX = CShields.tShields[iShieldID].iTargetX - (CShields.tShields[iShieldID].iSizeX-1); end
                                if CShields.tShields[iShieldID].iTargetY + CShields.tShields[iShieldID].iSizeY-1 > tGame.iMaxY then CShields.tShields[iShieldID].iTargetY = CShields.tShields[iShieldID].iTargetY - (CShields.tShields[iShieldID].iSizeY-1); end
                            end
                        end
                    end
                else
                    if CShields.tShields[iShieldID].iX < CShields.tShields[iShieldID].iTargetX then
                        CShields.tShields[iShieldID].iX = CShields.tShields[iShieldID].iX + 1
                    elseif CShields.tShields[iShieldID].iX > CShields.tShields[iShieldID].iTargetX then
                        CShields.tShields[iShieldID].iX = CShields.tShields[iShieldID].iX - 1                
                    end

                    if CShields.tShields[iShieldID].iY < CShields.tShields[iShieldID].iTargetY then
                        CShields.tShields[iShieldID].iY = CShields.tShields[iShieldID].iY + 1
                    elseif CShields.tShields[iShieldID].iY > CShields.tShields[iShieldID].iTargetY then
                        CShields.tShields[iShieldID].iY = CShields.tShields[iShieldID].iY - 1                
                    end
                end
            end
        end

        if iGameState == GAMESTATE_GAME then return 100; end
    end)
end

--projectiles
CProjectiles = {}
CProjectiles.tProjectiles = {}

CProjectiles.NewProjectile = function(iX, iY, iVelX, iVelY, iTeamID)
    local iProjectileID = #CProjectiles.tProjectiles+1
    CProjectiles.tProjectiles[iProjectileID] = {}
    CProjectiles.tProjectiles[iProjectileID].iX = iX
    CProjectiles.tProjectiles[iProjectileID].iY = iY
    CProjectiles.tProjectiles[iProjectileID].iVelX = iVelX
    CProjectiles.tProjectiles[iProjectileID].iVelY = iVelY
    CProjectiles.tProjectiles[iProjectileID].iTeamID = iTeamID
end

CProjectiles.Paint = function()
    for iProjectileID = 1, #CProjectiles.tProjectiles do
        if CProjectiles.tProjectiles[iProjectileID] then
            local iX = CProjectiles.tProjectiles[iProjectileID].iX
            local iY = CProjectiles.tProjectiles[iProjectileID].iY
            tFloor[iX][iY].iColor = CColors.WHITE
            tFloor[iX][iY].iBright = tConfig.Bright+1
        end
    end
end

CProjectiles.Thinker = function()
    AL.NewTimer(100, function()
        for iProjectileID = 1, #CProjectiles.tProjectiles do
            if CProjectiles.tProjectiles[iProjectileID] then
                CProjectiles.tProjectiles[iProjectileID].iX = CProjectiles.tProjectiles[iProjectileID].iX + CProjectiles.tProjectiles[iProjectileID].iVelX
                CProjectiles.tProjectiles[iProjectileID].iY = CProjectiles.tProjectiles[iProjectileID].iY + CProjectiles.tProjectiles[iProjectileID].iVelY
                local bDestroy = false

                if CProjectiles.tProjectiles[iProjectileID].iX < 1 or CProjectiles.tProjectiles[iProjectileID].iX > tGame.Cols or CProjectiles.tProjectiles[iProjectileID].iY < 1 or CProjectiles.tProjectiles[iProjectileID].iY > tGame.Rows then
                    bDestroy = true
                end

                if not bDestroy then
                    for iShieldID = 1, #CShields.tShields do
                        if CShields.tShields[iShieldID] and CShields.tShields[iShieldID].iTeamID ~= CProjectiles.tProjectiles[iProjectileID].iTeamID then 
                            if AL.RectIntersects2(CProjectiles.tProjectiles[iProjectileID].iX, CProjectiles.tProjectiles[iProjectileID].iY, 1, 1, CShields.tShields[iShieldID].iX, CShields.tShields[iShieldID].iY, CShields.tShields[iShieldID].iSizeX, CShields.tShields[iShieldID].iSizeY) then
                                CAudio.PlaySystemAsync("snow-forts/snowball-hit-shield.mp3")
                                bDestroy = true
                                break;
                            end
                        end
                    end
                end

                if not bDestroy then
                    for iFortID = 1, #CForts.tForts do
                        if iFortID ~= CProjectiles.tProjectiles[iProjectileID].iTeamID and CForts.tForts[iFortID].bAlive then
                            if AL.RectIntersects(CProjectiles.tProjectiles[iProjectileID].iX, CProjectiles.tProjectiles[iProjectileID].iY, 1, CForts.tForts[iFortID].iX, CForts.tForts[iFortID].iY, CForts.iFortSize) then
                                bDestroy = true
                                CForts.DamageFort(iFortID)
                                break;
                            end
                        end
                    end
                end

                if bDestroy then
                    CProjectiles.tProjectiles[iProjectileID] = nil
                end
            end
        end

        if iGameState == GAMESTATE_GAME then
            return 100
        end
    end)
end
--

--UTIL прочие утилиты
function CheckPositionClick(iStartX, iStartY, iSize)
    for iX = iStartX, iStartX + iSize - 1 do
        for iY = iStartY, iStartY + iSize - 1 do
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