--[[
    Название: Олимпиада
    Автор: Avondale, дискорд - avonda

    От 2 до 4 игроков
    Чтобы начать игру нужно занять свои места и нажать кнопку

    Описание механики: 
        Несколько спортивных мини игр в одной игре

        Прыжки в длину с места: прыгнуть как можно дальше, чем дальше тем больше очков
        Челночный бег: бег по одному отрезку с несколькими разворотами, кто первее добежал тому больше очков
        Прыжки через лаву: челночный бег но с перерыгиванием лавы
        Классики: челночный бег но с классиками

        Кто набрал больше очков со всех мини игр тот и победил

    Идеи по доработке: 
        Больше мини игр
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
local tPlayerInGame = {}
local bAnyButtonClick = false
local bCountDownStared = false

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
    iPlayerID = 0,
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

    tGameStats.TotalStages = CGameMode.GAMEMODE_COUNT

    CAudio.PlaySync("games/olympics.mp3")
    CAudio.PlaySync("voices/choose-color.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")    
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    local iPlayersReady = 0

    for iPos = 1, #tGame.StartPositions do
        local iBright = CColors.BRIGHT15
        if CGameMode.PlayerOnStart(iPos) or (bCountDownStared and tPlayerInGame[iPos]) then
            tGameStats.Players[iPos].Color = tGame.StartPositions[iPos].Color
            iBright = tConfig.Bright
            iPlayersReady = iPlayersReady + 1
            tPlayerInGame[iPos] = true
        else
            tGameStats.Players[iPos].Color = CColors.NONE
            tPlayerInGame[iPos] = false
        end

        CPaint.PlayerZone(iPos, iBright)
    end

    if not bCountDownStared and iPlayersReady > 1 and bAnyButtonClick then
        bAnyButtonClick = false
        bCountDownStared = true

        CGameMode.StartCountDown(tConfig.GameCountdown)
    end    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)  
    CGameMode.tGameModeTick[CGameMode.iGameMode]()
    CPaint.PlayersZones()
end

function PostGameTick()
    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
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
CGameMode.iRound = 0
CGameMode.bRoundOn = false
CGameMode.PlayerData = {}
CGameMode.iRealPlayerCount = 0
CGameMode.iFinishedCount = 0
CGameMode.tPlayerFinished = {}

CGameMode.GAMEMODE_LONGJUMP = 1
CGameMode.GAMEMODE_SHUTTLE_RACE = 2
CGameMode.GAMEMODE_LAVA_STRIPES = 3
CGameMode.GAMEMODE_CLASSICS = 4
CGameMode.GAMEMODE_COUNT = 4

CGameMode.iGameMode = 0
CGameMode.tGameModeAnnouncer = {}
CGameMode.tGameModeStart = {}
CGameMode.tGameModeTick = {}
CGameMode.tGameModeClick = {}

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.PrepareNextRound()

    CTimer.New(1000, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            if CGameMode.iRound == 0 then
                CGameMode.StartGame()
            end

            CGameMode.StartNextRound()
            return nil
        else
            if CGameMode.iCountdown <= 5 then
                if CGameMode.AllPlayersOnStart() then
                    CAudio.PlaySyncFromScratch("")
                    CAudio.PlayLeftAudio(CGameMode.iCountdown)
                else
                    CAudio.PlaySync("voices/get-back.mp3")
                    return 3000
                end
            end
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.CountRealPlayers = function()
    CGameMode.iRealPlayerCount = 0
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.iRealPlayerCount = CGameMode.iRealPlayerCount + 1
        end
    end
end

CGameMode.StartGame = function()
    CGameMode.CountRealPlayers()
    iGameState = GAMESTATE_GAME
    CAudio.PlaySync(CAudio.START_GAME)   
end

CGameMode.PrepareNextRound = function()
    CGameMode.iFinishedCount = 0
    CGameMode.PlayerData = {}
    CGameMode.tPlayerFinished = {}

    CGameMode.NextGameModeType()

    CAudio.PlaySyncFromScratch("")
    CGameMode.tGameModeAnnouncer[CGameMode.iGameMode]()
end

CGameMode.StartNextRound = function()
    CAudio.PlayRandomBackground()
    CGameMode.bRoundOn = true
    CGameMode.iRound = CGameMode.iRound + 1
    tGameStats.StageNum = CGameMode.iRound 

    CGameMode.tGameModeStart[CGameMode.iGameMode]()
end

CGameMode.NextGameModeType = function()
    if CGameMode.iGameMode == 0 then
        CGameMode.iGameMode = math.random(1, CGameMode.GAMEMODE_COUNT)
    else
        CGameMode.iGameMode = CGameMode.iGameMode + 1
        if CGameMode.iGameMode > CGameMode.GAMEMODE_COUNT then
            CGameMode.iGameMode = 1
        end
    end
end

CGameMode.EndRound = function()
    CAudio.StopBackground()
    CGameMode.bRoundOn = false
    CPaint.ResetAnimation()

    if CGameMode.iRound == CGameMode.GAMEMODE_COUNT then
        CGameMode.EndGame()
    else
        CAudio.PlayAsync("voices/get-back.mp3")
        CTimer.New(5000, function()
            CGameMode.StartCountDown(tConfig.RoundCountdown)
        end)
    end
end

CGameMode.EndGame = function()
    local iMaxScore = -999

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and tGameStats.Players[iPlayerID].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerID].Score
            CGameMode.iWinnerID = iPlayerID
        end
    end

    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.PlayerOnStart = function(iPlayerID)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
        if tFloor[iX][CGameMode.GetStartY(iPlayerID)].bClick then
            return true
        end
    end  

    return false
end

CGameMode.AllPlayersOnStart = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            if not CGameMode.PlayerOnStart(iPlayerID) then
                return false
            end
        end
    end

    return true
end

CGameMode.AddScoreToPlayer = function(iPlayerID, iScore)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScore
    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score
    end
end

CGameMode.PlayerFinished = function(iPlayerID)
    CAudio.PlaySync(CAudio.STAGE_DONE)

    CGameMode.tPlayerFinished[iPlayerID] = true

    CGameMode.iFinishedCount = CGameMode.iFinishedCount + 1
    if CGameMode.iFinishedCount == CGameMode.iRealPlayerCount then
        CGameMode.EndRound()
    end
end

CGameMode.GetStartY = function(iPlayerID)
    return tGame.StartPositions[iPlayerID].Y
end

--LONGJUMP GAMEMODE
CGameMode.tGameModeAnnouncer[CGameMode.GAMEMODE_LONGJUMP] = function()
    CGameMode.iCountdown = CGameMode.iCountdown + 7
    CAudio.PlaySync("voices/longjump-guide.mp3")
end

CGameMode.tGameModeStart[CGameMode.GAMEMODE_LONGJUMP] = function()
    CGameMode.LongJumpInitPlayers()
end

CGameMode.LongJumpInitPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.PlayerData[iPlayerID] = {}
            CGameMode.PlayerData[iPlayerID].iLandingSpotY = 0
            CGameMode.PlayerData[iPlayerID].iLandCount = 0
        end
    end
end

CGameMode.tGameModeTick[CGameMode.GAMEMODE_LONGJUMP] = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and not CGameMode.tPlayerFinished[iPlayerID] then
            CGameMode.LongJumpPaintPlayerZone(iPlayerID)
        end
    end
end

CGameMode.LongJumpPaintPlayerZone = function(iPlayerID)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do  
            local iColor = CColors.WHITE

            if iY <= CGameMode.GetStartY(iPlayerID)+2 then
                iColor = tGameStats.Players[iPlayerID].Color
            end

            if CGameMode.bRoundOn and iY == CGameMode.PlayerData[iPlayerID].iLandingSpotY then
                iColor = CColors.GREEN
            end

            local iBright = tConfig.Bright
            if not CGameMode.bRoundOn then
                iBright = iBright - 2
            end

            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iPlayerID = iPlayerID
        end
    end
end

CGameMode.tGameModeClick[CGameMode.GAMEMODE_LONGJUMP] = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 or CGameMode.tPlayerFinished[iPlayerID] then return; end

    if iY > CGameMode.GetStartY(iPlayerID)+2 and CGameMode.PlayerData[iPlayerID].iLandingSpotY == 0 then
        CGameMode.LongJumpPlayerLanded(iPlayerID, iY)
    elseif iY <= CGameMode.GetStartY(iPlayerID)+2 and CGameMode.PlayerData[iPlayerID].iLandingSpotY ~= 0 then
        CGameMode.PlayerData[iPlayerID].iLandingSpotY = 0
    end
end

CGameMode.LongJumpPlayerLanded = function(iPlayerID, iY)
    CLog.print(iPlayerID.." landed at "..iY)

    CGameMode.PlayerData[iPlayerID].iLandingSpotY = iY
    local iDistance = iY
    CGameMode.AddScoreToPlayer(iPlayerID, iDistance)

    CGameMode.PlayerData[iPlayerID].iLandCount = CGameMode.PlayerData[iPlayerID].iLandCount + 1

    if CGameMode.PlayerData[iPlayerID].iLandCount == tConfig.LongJumpCount then
        CGameMode.PlayerFinished(iPlayerID)
    end
end
--//

--SHUTTLE GAMEMODE
CGameMode.tGameModeAnnouncer[CGameMode.GAMEMODE_SHUTTLE_RACE] = function()
    CGameMode.iCountdown = CGameMode.iCountdown + 5
    CAudio.PlaySync("voices/shuttle-guide.mp3")
end

CGameMode.tGameModeStart[CGameMode.GAMEMODE_SHUTTLE_RACE] = function()
    CGameMode.ShuttleInitPlayers()
end

CGameMode.ShuttleInitPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.PlayerData[iPlayerID] = {}
            CGameMode.PlayerData[iPlayerID].iFinishY = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
            CGameMode.PlayerData[iPlayerID].iFinishCount = 0
            CGameMode.PlayerData[iPlayerID].bFinished = false
        end
    end
end

CGameMode.tGameModeTick[CGameMode.GAMEMODE_SHUTTLE_RACE] = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and CGameMode.PlayerData[iPlayerID] then
            CGameMode.ShuttlePaintPlayerZone(iPlayerID)
        end
    end
end

CGameMode.ShuttlePaintPlayerZone = function(iPlayerID)
    if CGameMode.PlayerData[iPlayerID] == nil then return; end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do  
            local iColor = CColors.WHITE
            if iY == CGameMode.PlayerData[iPlayerID].iFinishY then    
                iColor = CColors.GREEN
            end

            local iBright = tConfig.Bright
            if not CGameMode.bRoundOn then
                iBright = iBright - 2
            end

            if CGameMode.PlayerData[iPlayerID].bFinished then
                iColor = tGame.StartPositions[iPlayerID].Color
            end

            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iPlayerID = iPlayerID
        end
    end    
end

CGameMode.tGameModeClick[CGameMode.GAMEMODE_SHUTTLE_RACE] = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 then return; end
    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if iY == CGameMode.PlayerData[iPlayerID].iFinishY then
        CGameMode.PlayerData[iPlayerID].iFinishCount = CGameMode.PlayerData[iPlayerID].iFinishCount + 1
        if CGameMode.PlayerData[iPlayerID].iFinishCount > tConfig.ShuttleRaceCount then
            CGameMode.AddScoreToPlayer(iPlayerID, (#tGame.StartPositions-CGameMode.iFinishedCount)*20)
            CGameMode.PlayerData[iPlayerID].bFinished = true
            CGameMode.PlayerFinished(iPlayerID)
        else
            CAudio.PlayAsync(CAudio.CLICK)
            CGameMode.PlayerData[iPlayerID].iFinishY = CGameMode.ShuttleGetNewFinishForPlayer(iPlayerID, CGameMode.PlayerData[iPlayerID].iFinishY)
        end
    end
end

CGameMode.ShuttleGetNewFinishForPlayer = function(iPlayerID, iFinishY)
    if iFinishY == tGame.StartPositions[iPlayerID].Y+1 then
        return tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
    end

    return tGame.StartPositions[iPlayerID].Y+1
end
--//

--LAVA STRIPES
CGameMode.tGameModeAnnouncer[CGameMode.GAMEMODE_LAVA_STRIPES] = function()
    CGameMode.iCountdown = CGameMode.iCountdown + 6
    CAudio.PlaySync("voices/olympics-lava-guide.mp3")
end

CGameMode.tGameModeStart[CGameMode.GAMEMODE_LAVA_STRIPES] = function()
    CGameMode.LavaInitPlayers()
end

CGameMode.LavaInitPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.PlayerData[iPlayerID] = {}
            CGameMode.PlayerData[iPlayerID].iFinishY = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
            CGameMode.PlayerData[iPlayerID].iFinishCount = 0
            CGameMode.PlayerData[iPlayerID].bFinished = false
            CGameMode.PlayerData[iPlayerID].tLavaYPressed = {}
        end
    end
end

CGameMode.tGameModeTick[CGameMode.GAMEMODE_LAVA_STRIPES] = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and CGameMode.PlayerData[iPlayerID] then
            CGameMode.LavaPaintPlayerZone(iPlayerID)
        end
    end
end

CGameMode.LavaPaintPlayerZone = function(iPlayerID)
    if CGameMode.PlayerData[iPlayerID] == nil then return; end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do  
            if not tFloor[iX][iY].bAnimated then
                local iColor = CGameMode.LavaGetColorFromY(iY, iPlayerID)

                local iBright = tConfig.Bright
                if not CGameMode.bRoundOn then
                    iBright = iBright - 2
                end

                if CGameMode.PlayerData[iPlayerID].bFinished then
                    iColor = tGame.StartPositions[iPlayerID].Color
                end

                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                tFloor[iX][iY].iPlayerID = iPlayerID
            end
        end
    end    
end

CGameMode.LavaGetColorFromY = function(iY, iPlayerID)
    if iY == CGameMode.PlayerData[iPlayerID].iFinishY then    
        return CColors.GREEN
    end

    if CGameMode.LavaIsLavaY(iY, iPlayerID) then
        return CColors.RED
    end

    return CColors.WHITE
end

CGameMode.LavaIsLavaY = function(iY, iPlayerID)
    if iPlayerID ~= nil and CGameMode.GetStartY(iPlayerID) == iY then return false end

    return iY % 3 ~= 0
end

CGameMode.tGameModeClick[CGameMode.GAMEMODE_LAVA_STRIPES] = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 then return; end
    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if iY == CGameMode.PlayerData[iPlayerID].iFinishY then
        CGameMode.PlayerData[iPlayerID].iFinishCount = CGameMode.PlayerData[iPlayerID].iFinishCount + 1
        if CGameMode.PlayerData[iPlayerID].iFinishCount > tConfig.LavaCount then
            CGameMode.AddScoreToPlayer(iPlayerID, (#tGame.StartPositions-CGameMode.iFinishedCount)*20)
            CGameMode.PlayerData[iPlayerID].bFinished = true
            CGameMode.PlayerFinished(iPlayerID)
        else
            CAudio.PlayAsync(CAudio.CLICK)
            CGameMode.PlayerData[iPlayerID].iFinishY = CGameMode.LavaGetNewFinishForPlayer(iPlayerID, CGameMode.PlayerData[iPlayerID].iFinishY)
        end
    elseif CGameMode.LavaIsLavaY(iY, iPlayerID) and not CGameMode.PlayerData[iPlayerID].tLavaYPressed[iY] then
        CGameMode.PlayerData[iPlayerID].tLavaYPressed[iY] = true
        CGameMode.AddScoreToPlayer(iPlayerID, -5)
        CAudio.PlayAsync(CAudio.MISCLICK)
        CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.RED)
    end
end

CGameMode.LavaGetNewFinishForPlayer = function(iPlayerID, iFinishY)
    CGameMode.PlayerData[iPlayerID].tLavaYPressed = {}

    if iFinishY == tGame.StartPositions[iPlayerID].Y+1 then
        return tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
    end

    return tGame.StartPositions[iPlayerID].Y+1
end
--//

--CLASSICS
CGameMode.tGameModeAnnouncer[CGameMode.GAMEMODE_CLASSICS] = function()
    CGameMode.iCountdown = CGameMode.iCountdown + 5
    CAudio.PlaySync("voices/olympics-classics-guide.mp3")
end

CGameMode.tGameModeStart[CGameMode.GAMEMODE_CLASSICS] = function()
    CGameMode.ClassicsInitPlayers()
end

CGameMode.ClassicsInitPlayers = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.PlayerData[iPlayerID] = {}
            CGameMode.PlayerData[iPlayerID].iFinishY = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
            CGameMode.PlayerData[iPlayerID].iFinishCount = 0
            CGameMode.PlayerData[iPlayerID].bFinished = false
        end
    end
end

CGameMode.tGameModeTick[CGameMode.GAMEMODE_CLASSICS] = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and CGameMode.PlayerData[iPlayerID] then
            CGameMode.ClassicsPaintPlayerZone(iPlayerID)
        end
    end
end

CGameMode.ClassicsPaintPlayerZone = function(iPlayerID)
    if CGameMode.PlayerData[iPlayerID] == nil then return; end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do  
            if not tFloor[iX][iY].bAnimated then
                local iColor = CGameMode.ClassicsGetColorFromXY(iX, iY, iPlayerID)

                local iBright = tConfig.Bright
                if not CGameMode.bRoundOn then
                    iBright = iBright - 2
                end

                if CGameMode.PlayerData[iPlayerID].bFinished then
                    iColor = tGame.StartPositions[iPlayerID].Color
                end

                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                tFloor[iX][iY].iPlayerID = iPlayerID
            end
        end
    end    
end

CGameMode.ClassicsGetColorFromXY = function(iX, iY, iPlayerID)
    if iY == CGameMode.PlayerData[iPlayerID].iFinishY then    
        return CColors.GREEN
    end

    if CGameMode.ClassicsIsLavaXY(iX, iY) then
        return CColors.RED
    end

    return CColors.WHITE
end

CGameMode.ClassicsIsLavaXY = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 then return; end

    if CGameMode.GetStartY(iPlayerID) == iY then return false end

    if iY == (tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1) then return false end
    if iY == (tGame.StartPositions[iPlayerID].Y+1) then return false end

    iX = iX - tGame.StartPositions[iPlayerID].X

    if iY % 2 == 0 then
        if iX == 1 or iX == 2 then return true end
    else
        if iX ~= 1 and iX ~= 2 then return true end
    end

    return false
end

CGameMode.tGameModeClick[CGameMode.GAMEMODE_CLASSICS] = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 then return; end
    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if iY == CGameMode.PlayerData[iPlayerID].iFinishY then
        CGameMode.PlayerData[iPlayerID].iFinishCount = CGameMode.PlayerData[iPlayerID].iFinishCount + 1
        if CGameMode.PlayerData[iPlayerID].iFinishCount > tConfig.ClassicsCount then
            CGameMode.AddScoreToPlayer(iPlayerID, (#tGame.StartPositions-CGameMode.iFinishedCount)*20)
            CGameMode.PlayerData[iPlayerID].bFinished = true
            CGameMode.PlayerFinished(iPlayerID)
        else
            CAudio.PlayAsync(CAudio.CLICK)
            CGameMode.PlayerData[iPlayerID].iFinishY = CGameMode.ClassicsGetNewFinishForPlayer(iPlayerID, CGameMode.PlayerData[iPlayerID].iFinishY)
        end
    elseif CGameMode.ClassicsIsLavaXY(iX, iY) then
        CGameMode.AddScoreToPlayer(iPlayerID, -5)
        CAudio.PlayAsync(CAudio.MISCLICK)
        CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.RED)
    end
end

CGameMode.ClassicsGetNewFinishForPlayer = function(iPlayerID, iFinishY)
    if iFinishY == tGame.StartPositions[iPlayerID].Y+1 then
        return tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1
    end

    return tGame.StartPositions[iPlayerID].Y+1
end
--//

--[[ TEMPLATE
CGameMode.tGameModeAnnouncer[CGameMode.GAMEMODE_] = function()
    --play sound
end

CGameMode.tGameModeStart[CGameMode.GAMEMODE_] = function()

end

CGameMode.tGameModeTick[CGameMode.GAMEMODE_] = function()

end

CGameMode.tGameModeClick[CGameMode.GAMEMODE_] = function(iX, iY)
    local iPlayerID = tFloor[iX][iY].iPlayerID
    if iPlayerID == 0 then return; end

end
]]
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.PlayersZones = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    if iGameState == GAMESTATE_GAME and not CGameMode.PlayerOnStart(iPlayerID) then
        iBright = iBright - 2
    end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
        tFloor[iX][tGame.StartPositions[iPlayerID].Y].iBright = iBright
        tFloor[iX][tGame.StartPositions[iPlayerID].Y].iColor = tGame.StartPositions[iPlayerID].Color
    end   

    if CGameMode.tPlayerFinished[iPlayerID] then
        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            for iY = tGame.StartPositions[iPlayerID].Y+1, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y do
                tFloor[iX][iY].iBright = tConfig.Bright
                tFloor[iX][iY].iColor = CColors.GREEN
            end
        end
    end
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    CTimer.New(CPaint.ANIMATION_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated then return; end

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

CPaint.ResetAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
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
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if click.Click and iGameState == GAMESTATE_GAME and CGameMode.bRoundOn then
        CGameMode.tGameModeClick[CGameMode.iGameMode](click.X, click.Y)
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

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end