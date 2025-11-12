--[[
    Название: ПингПонг на 4 игрока
    Автор: Avondale, дискорд - avonda

    Описание:
        У четверых игроков есть ворота(реальных игроков может быть от 1 до 4, недостающих заменят боты), игроки управляют платформой чтобы отбивать мяч от ворот.
        Мяч летает по всему полю. у игроков ограничены жизни, побеждает тот кто останется последним. мяч ускоряется после каждого отскока.
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
local GAMESTATE_RULES = 0
local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4

local bGamePaused = false
local iGameState = GAMESTATE_RULES
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
    ScoreboardVariant = 0,
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
    tGame.CenterY = math.floor((tGame.iMaxY-tGame.iMinY+1)/2)

    CGameMode.InitGameMode()

    if tConfig.SkipTutorial or not AL.NewRulesScript then
        iGameState = GAMESTATE_SETUP
        CGameMode.Announcer()
    else
        tGameStats.StageLeftDuration = AL.Rules.iCountDownTime
        AL.NewTimer(1000, function()
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration == 0 then
                iGameState = GAMESTATE_SETUP
                CGameMode.Announcer()
            
                return nil;
            end

            if tGameStats.StageLeftDuration <= 5 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000;
        end)
    end
end

function NextTick()
    if iGameState == GAMESTATE_RULES then
        RulesTick()
    end

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

function RulesTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    local tNewFloor, bSkip = AL.Rules.FillFloor(tFloor)

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if tNewFloor[iX] and tNewFloor[iX][iY] then
                tFloor[iX][iY].iColor = tNewFloor[iX][iY]
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
    end

    tConfig.SkipTutorial = bSkip
end

function GameSetupTick()
    tGameStats.ScoreBoardVariant = 6
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    if not CGameMode.bCountDownStarted then SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true) end
    CGameMode.PaintPositions()
    CBuildings.Paint()

    local iPlayersReady = 0

    for iPlayerID = 1, #tGame.StartPositions do
        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionsSizeX, tGame.StartPositionsSizeY) then
            tPlayerInGame[iPlayerID] = true
        elseif not CGameMode.bCountDownStarted then
            AL.NewTimer(250, function()
                if not CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionsSizeX, tGame.StartPositionsSizeY) and not CGameMode.bCountDownStarted then
                    tPlayerInGame[iPlayerID] = false
                end
            end)
        end

        if tPlayerInGame[iPlayerID] then iPlayersReady = iPlayersReady + 1; end
    end

    if iPlayersReady > 0 and CGameMode.bCanAutoStart then
        if iPlayersReady < 1 or CGameMode.bCountDownStarted then return; end

        CGameMode.StartCountDown(10)
    end

    tGameResults.PlayersCount = iPlayersReady    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CGameMode.PaintPositions()
    CPods.PaintPods()
    CBall.Paint()
    CBuildings.Paint()
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
CGameMode.iAlivePlayerCount = 0
CGameMode.iWinnerID = 0

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.GREEN
CGameMode.tPlayerColors[2] = CColors.RED
CGameMode.tPlayerColors[3] = CColors.BLUE
CGameMode.tPlayerColors[4] = CColors.MAGENTA

CGameMode.InitGameMode = function()
    tGame.StartPositions = {}
    tGame.StartPositionsSizeX = tGame.CenterX-1
    tGame.StartPositionsSizeY = 2
    tGame.StartPositions[1] = {X = tGame.iMinX, Y = tGame.iMinY}
    tGame.StartPositions[2] = {X = tGame.CenterX+2, Y = tGame.iMinY}
    tGame.StartPositions[3] = {X = tGame.iMinX, Y = tGame.iMaxY-1}
    tGame.StartPositions[4] = {X = tGame.CenterX+2, Y = tGame.iMaxY-1}

    CPods.POD_SIZE = math.floor(tGame.CenterX/3)
    if CPods.POD_SIZE % 2 == 0 then CPods.POD_SIZE = CPods.POD_SIZE + 1; end

    tGameStats.TargetScore = tConfig.Lives
        for iPlayerID = 1, #tGame.StartPositions do
        tGameStats.Players[iPlayerID].Score = tConfig.Lives
        tGameStats.Players[iPlayerID].Color = CGameMode.tPlayerColors[iPlayerID]
    end

    CGameMode.iAlivePlayerCount = #tGame.StartPositions

    local iBuildingSize = 2--math.floor((tGame.iMaxY-tGame.iMinY)/3)
    CBuildings.NewBuilding(tGame.CenterX, tGame.iMinY, 2, iBuildingSize, 0, 0)
    CBuildings.NewBuilding(tGame.CenterX, tGame.iMaxY-iBuildingSize+1, 2, iBuildingSize, 0, 0)
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("pong4/pong4-rules.mp3")

        AL.NewTimer(CAudio.GetVoicesDuration("pong4/pong4-rules.mp3")*1000 + 3000, function()
            CGameMode.bCanAutoStart = true
        end)    
    else
        CGameMode.bCanAutoStart = true
    end

    CAudio.PlayVoicesSync("choose-color.mp3")
end

CGameMode.PaintPositions = function()
    for iPlayerID = 1, #tGame.StartPositions do
        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX-1 do
            for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionsSizeY-1 do
                tFloor[iX][iY].iColor = CGameMode.tPlayerColors[iPlayerID]

                local iBright = 1
                if iGameState == GAMESTATE_SETUP and tPlayerInGame[iPlayerID] then iBright = tConfig.Bright; end
                tFloor[iX][iY].iBright = iBright
            end
        end 
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.ResetSync()
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
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    CPods.InitPods()
    iGameState = GAMESTATE_GAME

    CBall.NewBall(CColors.YELLOW)

    AL.NewTimer(math.random(3000,12000), function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
        
        if math.random(1,3) == 2 then
            local iSize = math.random(2,6)
            
            local iY = tGame.CenterY-1
            if math.random(1,2) == 2 then iY = tGame.CenterY+1; end

            local iX = 1 - iSize
            local iVelX = 1
            if math.random(1,2) == 2 then
                iX = tGame.Cols
                iVelX = -1
            end

            CBuildings.NewBuilding(iX, iY, iSize, 1, iVelX, 0)
        end

        return math.random(3000,12000)
    end)

    CPods.Thinker()
    CBuildings.Thinker()
    CBall.Thinker()
end

CGameMode.EndGame = function(iWinnerID)
    CGameMode.iWinnerID = iWinnerID

    tGameResults.Color = CGameMode.tPlayerColors[iWinnerID]
    tGameResults.Won = not CPods.tPods[iWinnerID].bAI

    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[iWinnerID])
    CAudio.PlayVoicesSync(CAudio.VICTORY)    

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(CGameMode.tPlayerColors[iWinnerID], tConfig.Bright)

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.PlayerDeath = function(iPlayerID)
    CPods.tPods[iPlayerID] = nil
    CBuildings.NewBuilding(tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].Y, tGame.StartPositionsSizeX, tGame.StartPositionsSizeY)

    CGameMode.iAlivePlayerCount = CGameMode.iAlivePlayerCount - 1
    if CGameMode.iAlivePlayerCount == 1 then
        for iPlayerID = 1, #tGame.StartPositions do
            if CPods.tPods[iPlayerID] then
                CGameMode.EndGame(iPlayerID)
            end
        end 
    else
        CAudio.PlaySystemAsync(CAudio.GAME_OVER)
    end
end
--//

--BALL
CBall = {}
CBall.iX = 0
CBall.iY = 0
CBall.iVelX = 0
CBall.iVelY = 0
CBall.iPrevX = 0
CBall.iPrevY = 0
CBall.bStopped = true
CBall.iSpeed = 0

CBall.MAX_SPEED = 200

CBall.NewBall = function(iColor)
    CBall.iX = CBall.RandomX()
    CBall.iY = tGame.CenterY

    CBall.iVelX = math.random(0,1) if CBall.iVelX == 0 then CBall.iVelX = -1; end
    CBall.iVelY = math.random(0,1) if CBall.iVelY == 0 then CBall.iVelY = -1; end

    CBall.iColor = iColor

    CBall.iSpeed = 10

    AL.NewTimer(math.random(1000, 4000), function()
        CBall.bStopped = false
        CAudio.PlaySystemAsync("dodge/ball-kick.mp3")
    end)
end

CBall.RandomX = function()
    local iX = 0

    repeat
        iX = math.random(tGame.iMinX, tGame.iMaxX)
    until
        (iX ~= (tGame.iMinX + math.floor(tGame.StartPositionsSizeX/2))-1) and (iX ~= (tGame.iMinX + math.floor(tGame.StartPositionsSizeX/2))+1) and (iX ~= (tGame.iMaxX - math.floor(tGame.StartPositionsSizeX/2))-1) and (iX ~= (tGame.iMaxX - math.floor(tGame.StartPositionsSizeX/2))+1)

    return iX
end

CBall.Paint = function()
    tFloor[CBall.iX][CBall.iY].iColor = CBall.iColor
    tFloor[CBall.iX][CBall.iY].iBright = tConfig.Bright
end

CBall.Thinker = function()
    AL.NewTimer(300, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        if not CBall.bStopped then
            local iNewX = CBall.iX + CBall.iVelX
            local iNewY = CBall.iY + CBall.iVelY
            local bValid = true

            for iBuildingID = 1, #CBuildings.tBuildings do
                if CBuildings.tBuildings[iBuildingID] then
                    if (iNewY >= CBuildings.tBuildings[iBuildingID].iY and iNewY <= CBuildings.tBuildings[iBuildingID].iY + CBuildings.tBuildings[iBuildingID].iSizeY-1) or
                        (CBall.iY >= CBuildings.tBuildings[iBuildingID].iY and CBall.iY <= CBuildings.tBuildings[iBuildingID].iY + CBuildings.tBuildings[iBuildingID].iSizeY-1) then
                        if (iNewX >= CBuildings.tBuildings[iBuildingID].iX and iNewX <= CBuildings.tBuildings[iBuildingID].iX + CBuildings.tBuildings[iBuildingID].iSizeX-1) 
                        or (CBall.iX >= CBuildings.tBuildings[iBuildingID].iX and CBall.iX <= CBuildings.tBuildings[iBuildingID].iX + CBuildings.tBuildings[iBuildingID].iSizeX-1) then
                            if CBuildings.tBuildings[iBuildingID].iVelX ~= 0 then
                                if CBall.iY == CBuildings.tBuildings[iBuildingID].iY then
                                    CBall.iY = CBall.iY + CBall.iVelY
                                    if CBall.iVelX == 1 then CBall.iVelX = -1; else CBall.iVelX = 1; end
                                else
                                    if CBall.iVelY == 1 then CBall.iVelY = -1; else CBall.iVelY = 1; end
                                end
                            else
                                if CBall.iY ~= CBuildings.tBuildings[iBuildingID].iY and CBall.iY ~= (CBuildings.tBuildings[iBuildingID].iY + CBuildings.tBuildings[iBuildingID].iSizeY-1) then
                                    if CBall.iVelY == 1 then CBall.iVelY = -1; else CBall.iVelY = 1; end
                                else
                                    if CBall.iVelX == 1 then CBall.iVelX = -1; else CBall.iVelX = 1; end
                                end
                            end

                            bValid = false
                        
                            break;
                        end
                    end
                end
            end

            if bValid then
                if iNewY <= tGame.iMinY + 3 or iNewY >= tGame.iMaxY - 3 then
                    for iPlayerID = 1, #tGame.StartPositions do
                        if CPods.tPods[iPlayerID] then
                            if iNewX >= tGame.StartPositions[iPlayerID].X and iNewX <= tGame.StartPositions[iPlayerID].X + tGame.StartPositionsSizeX-1 then
                                if (tGame.StartPositions[iPlayerID].Y < tGame.CenterY and iNewY == tGame.iMinY) or (tGame.StartPositions[iPlayerID].Y > tGame.CenterY and iNewY == tGame.iMaxY) then
                                    CBall.ScoreGoal(iPlayerID)
                                    break;
                                end
                            end

                            if iNewY == CPods.tPods[iPlayerID].iY then
                                if (iNewX >= CPods.tPods[iPlayerID].iX and iNewX <= CPods.tPods[iPlayerID].iX + CPods.POD_SIZE-1) or (CBall.iX >= CPods.tPods[iPlayerID].iX and CBall.iX <= CPods.tPods[iPlayerID].iX + CPods.POD_SIZE-1) then
                                    if CBall.iVelY == 1 then CBall.iVelY = -1; else CBall.iVelY = 1; end

                                    if CBall.iX < CPods.tPods[iPlayerID].iX or CBall.iX > CPods.tPods[iPlayerID].iX + CPods.POD_SIZE-1 then
                                        if CBall.iVelX == 1 then CBall.iVelX = -1; else CBall.iVelX = 1; end
                                    end

                                    bValid = false
                                end 
                            end
                        end
                    end
                end
            end

            if bValid then
                if iNewX < 1 then bValid = false; CBall.iVelX = 1; end
                if iNewX > tGame.Cols then bValid = false; CBall.iVelX = -1; end
                if iNewY < 1 then bValid = false; CBall.iVelY = 1; end
                if iNewY > tGame.Rows then bValid = false; CBall.iVelY = -1; end
            end

            if bValid then 
                CBall.iX = iNewX
                CBall.iY = iNewY
            else
                CAudio.PlaySystemAsync("dodge/ball-bounce.mp3")

                CBall.iSpeed = CBall.iSpeed + 10
                if CBall.iSpeed > CBall.MAX_SPEED then CBall.iSpeed = CBall.MAX_SPEED end

                return 1;
            end
        end

        return (CBall.MAX_SPEED+100) - CBall.iSpeed
    end)
end

CBall.ScoreGoal = function(iPlayerID)
    CBall.bStopped = true

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score - 1
    if tGameStats.Players[iPlayerID].Score > 0 then
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
    else
        CGameMode.PlayerDeath(iPlayerID)
    end

    if CGameMode.iAlivePlayerCount > 1 then
        AL.NewTimer(3000, function()
            CBall.NewBall(CColors.YELLOW)
        end)
    end
end
--//

--PODS
CPods = {}
CPods.tPods = {}
CPods.POD_SIZE = 3

CPods.InitPods = function()
    for iPlayerID = 1, #tGame.StartPositions do
        CPods.NewPod(iPlayerID, tPlayerInGame[iPlayerID], tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X+tGame.StartPositionsSizeX-CPods.POD_SIZE, tGame.StartPositions[iPlayerID].Y)
        if tGame.StartPositions[iPlayerID].Y == tGame.iMinY then CPods.tPods[iPlayerID].iY = tGame.iMinY+1; end
    end
end

CPods.NewPod = function(iPlayerID, bAI, iMinX, iMaxX, iY)
    CPods.tPods[iPlayerID] = {}
    CPods.tPods[iPlayerID].bAI = bAI
    CPods.tPods[iPlayerID].iMinX = iMinX
    CPods.tPods[iPlayerID].iMaxX = iMaxX
    CPods.tPods[iPlayerID].iX = iMinX
    CPods.tPods[iPlayerID].iY = iY
    CPods.tPods[iPlayerID].iAITargetX = 0
end

CPods.PaintPods = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if CPods.tPods[iPlayerID] then
            for iX = CPods.tPods[iPlayerID].iX, CPods.tPods[iPlayerID].iX+CPods.POD_SIZE-1 do
                tFloor[iX][CPods.tPods[iPlayerID].iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                tFloor[iX][CPods.tPods[iPlayerID].iY].iBright = tConfig.Bright
            end
        end
    end
end

CPods.Thinker = function()
    AL.NewTimer(150, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        for iPlayerID = 1, #tGame.StartPositions do
            if CPods.tPods[iPlayerID] then
                if tPlayerInGame[iPlayerID] then
                    CPods.ThinkPlayer(iPlayerID)
                else
                    CPods.ThinkAI(iPlayerID)
                end
            end
        end

        return 150
    end)
end

CPods.ThinkPlayer = function(iPlayerID)
    local iMW1 = -1
    local iMW1X = CPods.tPods[iPlayerID].iMinX
    local iMW2 = -1
    local iMW2X = CPods.tPods[iPlayerID].iMaxX+CPods.POD_SIZE-1

    for iY = CPods.tPods[iPlayerID].iY-1, CPods.tPods[iPlayerID].iY+1 do
        for iX = CPods.tPods[iPlayerID].iMinX, CPods.tPods[iPlayerID].iMaxX+CPods.POD_SIZE-1 do
            if not tFloor[iX][iY].bDefect then
                if tFloor[iX][iY].iWeight > iMW1 then
                    iMW1 = tFloor[iX][iY].iWeight
                    iMW1X = iX
                elseif tFloor[iX][iY].iWeight > iMW2 then
                    iMW2 = tFloor[iX][iY].iWeight
                    iMW2X = iX
                end
            end
        end
    end

    if iMW1 > 0 then
        if iMW2 > 0 then
            CPods.tPods[iPlayerID].iX = math.floor((iMW1X+iMW2X)/2)
        else
            CPods.tPods[iPlayerID].iX = iMW1X
        end

        CPods.tPods[iPlayerID].iX = CPods.tPods[iPlayerID].iX - math.floor(CPods.POD_SIZE/2)
    end

    if CPods.tPods[iPlayerID].iX < CPods.tPods[iPlayerID].iMinX then CPods.tPods[iPlayerID].iX = CPods.tPods[iPlayerID].iMinX; end
    if CPods.tPods[iPlayerID].iX > CPods.tPods[iPlayerID].iMaxX then CPods.tPods[iPlayerID].iX = CPods.tPods[iPlayerID].iMaxX; end
end

CPods.ThinkAI = function(iPlayerID)
    if CPods.tPods[iPlayerID].iAITargetX == 0 or CPods.tPods[iPlayerID].iX == CPods.tPods[iPlayerID].iAITargetX then
        CPods.tPods[iPlayerID].iAITargetX = math.random(CPods.tPods[iPlayerID].iMinX, CPods.tPods[iPlayerID].iMaxX)
    end

    if CBall.iX >= CPods.tPods[iPlayerID].iMinX-4 and CBall.iX <= CPods.tPods[iPlayerID].iMaxX+4 and math.random(1,100) <= tConfig.EnemySkill then
        if CBall.iX < CPods.tPods[iPlayerID].iX then
            CPods.Move(iPlayerID, -1)
        elseif CBall.iX > (CPods.tPods[iPlayerID].iX+CPods.POD_SIZE-2) then
            CPods.Move(iPlayerID, 1)
        end
    else
        if CPods.tPods[iPlayerID].iX < CPods.tPods[iPlayerID].iAITargetX then
            CPods.Move(iPlayerID, 1)
        elseif CPods.tPods[iPlayerID].iX > CPods.tPods[iPlayerID].iAITargetX then
            CPods.Move(iPlayerID, -1)
        end
    end
end

CPods.Move = function(iPlayerID, iXPlus)
    local iNewX = CPods.tPods[iPlayerID].iX + iXPlus
    if iNewX >= CPods.tPods[iPlayerID].iMinX and iNewX <= CPods.tPods[iPlayerID].iMaxX then
        CPods.tPods[iPlayerID].iX = iNewX
    end
end
--//

--buildings
CBuildings = {}
CBuildings.tBuildings = {}

CBuildings.NewBuilding = function(iX, iY, iSizeX, iSizeY, iVelX, iVelY)
    local iBuildingID = #CBuildings.tBuildings+1
    CBuildings.tBuildings[iBuildingID] = {}
    CBuildings.tBuildings[iBuildingID].iX = iX
    CBuildings.tBuildings[iBuildingID].iY = iY
    CBuildings.tBuildings[iBuildingID].iSizeX = iSizeX
    CBuildings.tBuildings[iBuildingID].iSizeY = iSizeY
    CBuildings.tBuildings[iBuildingID].iVelX = iVelX
    CBuildings.tBuildings[iBuildingID].iVelY = iVelY
end

CBuildings.Paint = function()
    for iBuildingID = 1, #CBuildings.tBuildings do
        if CBuildings.tBuildings[iBuildingID] then
            SetRectColorBright(CBuildings.tBuildings[iBuildingID].iX, CBuildings.tBuildings[iBuildingID].iY, CBuildings.tBuildings[iBuildingID].iSizeX, CBuildings.tBuildings[iBuildingID].iSizeY, CColors.WHITE, tConfig.Bright)
        end
    end
end

CBuildings.Thinker = function()
    AL.NewTimer(350, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        for iBuildingID = 1, #CBuildings.tBuildings do
            if CBuildings.tBuildings[iBuildingID] and (CBuildings.tBuildings[iBuildingID].iVelX ~= 0 or CBuildings.tBuildings[iBuildingID].iVelY ~= 0) then
                CBuildings.Move(iBuildingID)
            end
        end
        return 350
    end)
end

CBuildings.Move = function(iBuildingID)
    if not CBuildings.tBuildings[iBuildingID] or not CBuildings.tBuildings[iBuildingID].iX or not CBuildings.tBuildings[iBuildingID].iVelX then return; end

    CBuildings.tBuildings[iBuildingID].iX = CBuildings.tBuildings[iBuildingID].iX + CBuildings.tBuildings[iBuildingID].iVelX
    CBuildings.tBuildings[iBuildingID].iY = CBuildings.tBuildings[iBuildingID].iY + CBuildings.tBuildings[iBuildingID].iVelY

    if (CBuildings.tBuildings[iBuildingID].iX > tGame.Cols or CBuildings.tBuildings[iBuildingID].iX + CBuildings.tBuildings[iBuildingID].iSizeX < 1) or (CBuildings.tBuildings[iBuildingID].iY > tGame.Rows or CBuildings.tBuildings[iBuildingID].iY + CBuildings.tBuildings[iBuildingID].iSizeY < 1) then 
        CBuildings.tBuildings[iBuildingID] = nil
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

        if iGameState <= GAMESTATE_SETUP then
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