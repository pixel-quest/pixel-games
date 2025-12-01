-- Название: Танцы
-- Автор: Avondale, дискорд - avonda
-- Описание механики: танцуй, нажимая набегающие пиксели
-- Идеи по доработке:
--    1. Сейчас пиксели ловятся, если просто стоять. Хотелось бы наказывать за пустые нажатия, но есть сложность с инертностью датчиков
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
local GAMESTATE_TUTORIAL = 1
local GAMESTATE_SETUP = 2
local GAMESTATE_GAME = 3
local GAMESTATE_POSTGAME = 4
local GAMESTATE_FINISH = 5

local bGamePaused = false
local iGameState = GAMESTATE_RULES
local iPrevTickTime = 0
local bAnyButtonClick = false
local tPlayerInGame = {}
local iSongStartedTime = 0
local bCountDownStarted = false
local tArenaPlayerReady = {}

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
    ScoreboardVariant = 7,
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
    iPixelID = 0,
    bAnimated = false,
    iAnimationPriority = 0,
}
local tButtonStruct = {
    iColor = CColors.NONE,
    iBright = tConfig.Bright,
    bClick = false,
    bDefect = false,
}

local tPlayerIDtoColor = {}
tPlayerIDtoColor[1] = CColors.RED
tPlayerIDtoColor[2] = CColors.BLUE
tPlayerIDtoColor[3] = CColors.MAGENTA
tPlayerIDtoColor[4] = CColors.CYAN
tPlayerIDtoColor[5] = CColors.WHITE
tPlayerIDtoColor[6] = CColors.YELLOW

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
        tButtons[iId].iColor = CColors.BLUE
        tButtons[iId].iBright = CColors.BRIGHT70
    end

    if not tGame.MirrorGame then
        tGame.Direction = 1
    else
        tGame.Direction = 2
    end
    tGame.StartPositionSize = tConfig.StartPositionSize or 4

    SetupPlayerPositions()

    iPrevTickTime = CTime.unix()

    local err = CAudio.PreloadFile("audio_v2/"..tGame["SongName"])
    if err ~= nil then error(err); end

    CAudio.PlayVoicesSync("dance/dance_game.mp3")

    if tConfig.SkipTutorial or not AL.NewRulesScript then
        iGameState = GAMESTATE_TUTORIAL
        CAudio.PlayVoicesSync("choose-color.mp3")
        if tGame.ArenaMode then 
            CAudio.PlayVoicesSync("press-zone-for-start.mp3")
        else
            --CAudio.PlaySync("voices/press-button-for-start.mp3")
        end
    else
        tGameStats.StageLeftDuration = AL.Rules.iCountDownTime
        AL.NewTimer(1000, function()
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration == 0 then
                iGameState = GAMESTATE_TUTORIAL
                CAudio.PlayVoicesSync("choose-color.mp3")
                if tGame.ArenaMode then 
                    CAudio.PlayVoicesSync("press-zone-for-start.mp3")
                else
                    --CAudio.PlaySync("voices/press-button-for-start.mp3")
                end
            
                return nil;
            end

            if tGameStats.StageLeftDuration <= 5 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000;
        end)
    end
end

function SetupPlayerPositions()
    local iY = 4
    if tGame.Direction == 2 then
        iY = tGame.Rows - 3
    end

    local iX = 1

    tGame.StartPositions = {}
    for iPlayerID = 1, 6 do
        if iX < tGame.Cols then
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = iX
            tGame.StartPositions[iPlayerID].Y = iY
            tGame.StartPositions[iPlayerID].Color = tPlayerIDtoColor[iPlayerID]
        end

        iX = iX + tGame.StartPositionSize + 1
    end
end

function NextTick()
    if iGameState == GAMESTATE_RULES then
        RulesTick()
    end

    if iGameState == GAMESTATE_TUTORIAL then
        TutorialTick()
    end

    --[[
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end
    ]]

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
    CSongSync.Count((CTime.unix() - iSongStartedTime) * 1000 - tConfig.SongStartDelayMS)

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

function TutorialTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)

    local iPlayersReady = 0

    if tGame.ArenaMode then
        bAnyButtonClick = false
    end

    if not CSongSync.bOn then
        for iPos, tPos in ipairs(tGame.StartPositions) do
            if iPos <= #tGame.StartPositions then

                local iBright = CColors.BRIGHT15
                local iCheckY = tPos.Y-3
                if tGame.Direction == 2 then
                    iCheckY = tPos.Y
                end

                if CheckPositionClick({X = tPos.X, Y = iCheckY}, tGame.StartPositionSize) or (tGame.ArenaMode and tPlayerInGame[iPos]) then
                    tGameStats.Players[iPos].Color = tPos.Color
                    iBright = tConfig.Bright
                    iPlayersReady = iPlayersReady + 1
                    tPlayerInGame[iPos] = true
                elseif not CTutorial.bStarted then
                    tGameStats.Players[iPos].Color = CColors.NONE
                    tPlayerInGame[iPos] = false
                end

                CPaint.PlayerZone(iPos, iBright)

                if tPlayerInGame[iPos] and tGame.ArenaMode then
                    local iCenterX = tPos.X + math.floor(tGame.StartPositionSize/3)
                    local iCenterY = tPos.Y + math.floor(tGame.StartPositionSize/2)-1

                    local bArenaClick = false
                    for iX = iCenterX, iCenterX+1 do
                        for iY = iCenterY, iCenterY+1 do
                            tFloor[iX][iY].iColor = CColors.MAGENTA
                            tFloor[iX][iY].iBright = tConfig.Bright

                            if tArenaPlayerReady[iPos] then
                                tFloor[iX][iY].iBright = tConfig.Bright+2
                            end

                            if tFloor[iX][iY].bClick then 
                                bArenaClick = true
                            end
                        end
                    end

                    if bArenaClick then
                        bAnyButtonClick = true
                    end

                    tArenaPlayerReady[iPos] = bArenaClick
                end  
            end
        end
    end

    tGameResults.PlayersCount = iPlayersReady

    if iPlayersReady > 1 and not CTutorial.bStarted then
        if tGame.ArenaMode then
            if not bCountDownStarted then
                CGameMode.CountDown(5)
            end
            
            return nil
        end

        bAnyButtonClick = false

        if not CTutorial.bStarted then
            if iPlayersReady > 0 then
                CTutorial.PreStart()
                if tConfig.SkipTutorial then
                    CTutorial.bSkipDelayOn = false
                    CTutorial.Skip()
                end
            end
        elseif not bCountDownStarted then
            CTutorial.Skip()
        end
    end

    if CTutorial.bStarted and CSongSync.bOn then
        GameTick()
    else
        CPaint.Borders()
    end
end

--[[
function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    SetAllButtonsColorBright(CColors.BLUE, tConfig.Bright)

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then

            local iBright = CColors.BRIGHT15
            if CheckPositionClick({X = tPos.X, Y = tPos.Y-1}, tGame.StartPositionSize) or (bCountDownStarted and tPlayerInGame[iPos]) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if not bCountDownStarted and iPlayersReady > 0 and bAnyButtonClick then
        CTimer.tTimers = {}

        --iGameState = GAMESTATE_GAME
        bCountDownStarted = true
        CGameMode.CountDown(5)
    end
end
]]

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.Borders()
    CPaint.PlayerZones()
    CPaint.Pixels() -- красим движущиеся пиксели
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

--TUTORIAL
CTutorial = {}
CTutorial.bStarted = false
CTutorial.bSkipDelayOn = true
CTutorial.bPreStarted = false
CTutorial.bTrueStarted = false
CTutorial.bDisableErrorSound = true
CTutorial.bKillTutorialTimers = false
CTutorial.bEnded = false

CTutorial.PreStart = function()
    CAudio.ResetSync() -- обрыв звука
    CAudio.PlayVoicesSync("dance/dance_tutorial_part1.mp3")
    CTutorial.bStarted = true

    AL.NewTimer(5000, function()
        if CTutorial.bKillTutorialTimers then return nil; end
        CTutorial.bSkipDelayOn = false
    end)

    AL.NewTimer(13000, function()
        if CTutorial.bKillTutorialTimers then return nil; end
        CTutorial.bDisableErrorSound = false
        CTutorial.bPreStarted = true
    end)

    AL.NewTimer(24000, function()
        if CTutorial.bKillTutorialTimers then return nil; end
        CTutorial.Start()
    end)
end

CTutorial.Start = function()
    if CTutorial.bTrueStarted then return; end

    CTutorial.bTrueStarted = true
    CAudio.ResetSync() -- обрыв звука
    CAudio.PlayVoicesSync("dance/dance_tutorial_part2.mp3")
    CAudio.PlayVoicesSync("dance/dance_tutorial_part3.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("dance/dance_tutorial_part2.mp3") + CAudio.GetVoicesDuration("dance/dance_tutorial_part3.mp3")) * 1000, function()
        if not CTutorial.bEnded then
            CTutorial.Skip()
        end
    end)

    CGameMode.PixelMovement()
    CSongSync.Start(tTutorialSong)

    AL.NewTimer(5000, function()
        if CTutorial.bKillTutorialTimers then return nil; end
        CTutorial.bDisableErrorSound = false
    end)
end

CTutorial.Skip = function()
    if CTutorial.bSkipDelayOn then return end

    CTutorial.bEnded = true

    CSongSync.Clear()
    CGameMode.Clear()
    CAudio.ResetSync() -- обрыв звука

    CAudio.PlayVoicesSync("choose-color.mp3")

    CTutorial.bDisableErrorSound = false

    CTutorial.bKillTutorialTimers = true
    bCountDownStarted = true
    CGameMode.CountDown(5)
end
--//

--SONGSYNC
CSongSync = {}
CSongSync.iTime = 0
CSongSync.iSongPoint = 1
CSongSync.bOn = false
CSongSync.tSong = {}

CSongSync.Start = function(tSong)
    CSongSync.bOn = true
    CSongSync.tSong = tSong
    CSongSync.iTime = 0
    CSongSync.iSongPoint = 1
    tGameStats.TargetScore = 1

    for i = 1, #CSongSync.tSong do
        if CSongSync.tSong[i] then
            CSongSync.tSong[i][1] = CSongSync.tSong[i][1] - (tConfig.PixelMoveDelayMS * (tGame.Rows - tGame.StartPositions[1].Y))

            --[[
            for j = 2, #CSongSync.tSong[i] do
                if CSongSync.tSong[i][j] then
                    tGameStats.TargetScore = tGameStats.TargetScore + 1
                end
            end
            ]]
        end
    end

    if iGameState == GAMESTATE_GAME then
        CAudio.PlayDanceSync(tGame["SongName"])
    end
    iSongStartedTime = CTime.unix()
end

CSongSync.Clear = function()
    CSongSync.bOn = false
    CSongSync.tSong = {}
    CSongSync.iTime = 0
    CSongSync.iSongPoint = 0
end

CSongSync.Count = function(iTimePassed)
    if (not CSongSync.bOn) or (iGameState ~= GAMESTATE_GAME and iGameState ~= GAMESTATE_TUTORIAL) or (iGameState == GAMESTATE_TUTORIAL and CTutorial.bKillTutorialTimers) then return; end
    for i = 1, #CSongSync.tSong do
        if CSongSync.tSong[i] ~= nil then
            if CSongSync.tSong[i][1] - iTimePassed <= 0 then
                local iBatchID = math.random(1,999)
                local iPos = 0
                for j = 2, #CSongSync.tSong[i] do
                    iPos = iPos + 1
                    CGameMode.SpawnPixelForPlayers(iPos, iBatchID, CSongSync.tSong[i][j])
                end

                if i == #CSongSync.tSong then
                    if iGameState == GAMESTATE_TUTORIAL then
                        --AL.NewTimer(5000, function()
                        --    CTutorial.Skip()
                        --end)
                    else
                        AL.NewTimer(5000, function()
                            CGameMode.EndGame()
                        end)
                    end
                end

                CSongSync.tSong[i] = nil
                CSongSync.iSongPoint = i
                CGameMode.CountTargetScore()
            end
        end
    end
end
--//

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = -1
CGameMode.iWinnerID = -1
CGameMode.tPixels = {}
CGameMode.tPixelStruct = {
    iPointX = 0,
    iPointY = 0,
    iColor = CColors.GREEN,
    iBright = CColors.BRIGHT50,
    iPlayerID = 0,
    bClickable = true,
    bProlong = false,
    bVisual = false,
    iBatchID = 0,
}
CGameMode.tPlayerPixelBatches = {}
CGameMode.tPlayerRowClick = {}
CGameMode.iMaxPlayerScore = -999
CGameMode.iMaxPlayerScorePlayerID = -1

CGameMode.CountDown = function(iCountDownTime)
    CSongSync.Clear()
    CGameMode.Clear()

    bCountDownStarted = true

    CGameMode.iCountdown = iCountDownTime

    CAudio.ResetSync()
    AL.NewTimer(1, function()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        --[[if tGame.ArenaMode and not bAnyButtonClick then
            bCountDownStarted = false
            return nil
        end]]

        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1

            iGameState = GAMESTATE_GAME

            CGameMode.PixelMovement()
            CSongSync.Start(tGame["Song"])

            CGameMode.SongTimer()

            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.PixelMovement = function()
    AL.NewTimer(tConfig.PixelMoveDelayMS, function()
        if (iGameState ~= GAMESTATE_GAME and iGameState ~= GAMESTATE_TUTORIAL) or (iGameState == GAMESTATE_TUTORIAL and CTutorial.bKillTutorialTimers) then return nil end

        for i = 1, #CGameMode.tPixels do
            if CGameMode.tPixels[i] ~= nil then
                CGameMode.MovePixel(i)
                CGameMode.CalculatePixel(i)
            end
        end

        if iGameState == GAMESTATE_TUTORIAL then -- в туториале пиксели падают медленее
            return math.floor(tConfig.PixelMoveDelayMS * 1.5)
        end

        return tConfig.PixelMoveDelayMS
    end)
end

CGameMode.MovePixel = function(iPixelID)
    if (tGame.Direction == 1 and CGameMode.tPixels[iPixelID].iPointY < 1)
    or (tGame.Direction == 2 and CGameMode.tPixels[iPixelID].iPointY > tGame.Rows+1)
    then return; end

    if not CGameMode.tPixels[iPixelID].bProlong and (CGameMode.tPixels[iPixelID].iPointY > 0 and CGameMode.tPixels[iPixelID].iPointY <= tGame.Rows) then
        tFloor[CGameMode.tPixels[iPixelID].iPointX][CGameMode.tPixels[iPixelID].iPointY].iPixelID = 0
    end

    if tGame.Direction == 1 then
        CGameMode.tPixels[iPixelID].iPointY = CGameMode.tPixels[iPixelID].iPointY - 1
    elseif tGame.Direction == 2 then
        CGameMode.tPixels[iPixelID].iPointY = CGameMode.tPixels[iPixelID].iPointY + 1
    end

    if CGameMode.tPixels[iPixelID].iPointY > 0 and CGameMode.tPixels[iPixelID].iPointY < tGame.Rows then
        tFloor[CGameMode.tPixels[iPixelID].iPointX][CGameMode.tPixels[iPixelID].iPointY].iPixelID = iPixelID
    end
end

CGameMode.CalculatePixel = function(iPixelID)
    if CGameMode.tPixels[iPixelID] == nil then return; end

    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID

    if (tGame.Direction == 1 and CGameMode.tPixels[iPixelID].iPointY <= tGame.StartPositions[iPlayerID].Y)
    or (tGame.Direction == 2 and CGameMode.tPixels[iPixelID].iPointY >= tGame.StartPositions[iPlayerID].Y) then
        CGameMode.tPixels[iPixelID].iBright = CColors.BRIGHT100

        if (tGame.Direction == 1 and CGameMode.tPixels[iPixelID].iPointY == 0) or (tGame.Direction == 2 and CGameMode.tPixels[iPixelID].iPointY == tGame.Rows+1) then
            if CGameMode.tPixels[iPixelID].bVisual then CGameMode.tPixels[iPixelID] = nil return; end

            if CGameMode.tPixels[iPixelID].bProlong then
                if tGame.Direction == 1 then
                    CGameMode.tPixels[iPixelID].iPointY = -1
                elseif tGame.Direction == 2 then
                    CGameMode.tPixels[iPixelID].iPointY = tGame.Rows+2
                end
            else
                CPaint.AnimateHit(iPlayerID, false, CGameMode.tPixels[iPixelID].iPointX)
                CGameMode.tPixels[iPixelID] = nil
            end
        else
            CGameMode.PlayerHitRow(CGameMode.tPixels[iPixelID].iPointX, CGameMode.tPixels[iPixelID].iPointY, false)
        end
    end
end

CGameMode.PlayerHitRow = function(iX, iY, bEvent)
    if iGameState ~= GAMESTATE_TUTORIAL and iGameState ~= GAMESTATE_GAME then return; end

    if tGame.Direction == 1 then
        if (not (iGameState == GAMESTATE_TUTORIAL and iY == tConfig.StartPositionSize_Max) or CTutorial.bTrueStarted) and (iY <= tGame.StartPositions[1].Y and iY > 0) then
            local bClickAny = false
            for iY1 = 1, tGame.StartPositions[1].Y do
                if tFloor[iX][iY1].bClick then
                    bClickAny = true
                end
            end

            if bClickAny then
                for iY2 = 1, tGame.StartPositions[1].Y do
                    if tFloor[iX][iY2].iPixelID and CGameMode.tPixels[tFloor[iX][iY2].iPixelID] and CGameMode.tPixels[tFloor[iX][iY2].iPixelID].bClickable then
                        CGameMode.ScorePixel(tFloor[iX][iY2].iPixelID)
                    end
                end
            end
        elseif bEvent and (CSongSync.bOn or (iGameState == GAMESTATE_TUTORIAL and CTutorial.bStarted)) then
            CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.NONE)
        end
    elseif tGame.Direction == 2 then
        if iY >= tGame.StartPositions[1].Y and iY < tGame.Rows then
            local bClickAny = false
            for iY1 = tGame.Rows, tGame.StartPositions[1].Y, -1 do
                if tFloor[iX][iY1].bClick then
                    bClickAny = true
                end
            end

            if bClickAny then
                for iY2 = tGame.Rows, tGame.StartPositions[1].Y, -1 do
                    if tFloor[iX][iY2].iPixelID and CGameMode.tPixels[tFloor[iX][iY2].iPixelID] and CGameMode.tPixels[tFloor[iX][iY2].iPixelID].bClickable then
                        CGameMode.ScorePixel(tFloor[iX][iY2].iPixelID)
                    end
                end
            end
        elseif bEvent and (CSongSync.bOn or (iGameState == GAMESTATE_TUTORIAL and CTutorial.bStarted)) then
            CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.NONE)
        end
    end
end

CGameMode.ScorePixel = function(iPixelID)
    if CGameMode.tPixels[iPixelID].bVisual then return; end
    if not CGameMode.tPixels[iPixelID].bClickable then return; end
    CGameMode.tPixels[iPixelID].bClickable = false

    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID

    --if iGameState == GAMESTATE_GAME then
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

        if tGameStats.Players[iPlayerID].Score > CGameMode.iMaxPlayerScore then
            CGameMode.iMaxPlayerScore = tGameStats.Players[iPlayerID].Score
            CGameMode.iMaxPlayerScorePlayerID = iPlayerID
            CGameMode.CountTargetScore()
        end
    --end
    if not CGameMode.tPixels[iPixelID].bProlong then
        --CPaint.AnimateRow(CGameMode.tPixels[iPixelID].iPointX, CGameMode.tPixels[iPixelID].iColor)
        CPaint.AnimateHit(iPlayerID, true, CGameMode.tPixels[iPixelID].iPointX)
    end

    CGameMode.tPixels[iPixelID].iColor = tGame.StartPositions[iPlayerID].Color

    if not CGameMode.tPixels[iPixelID].bProlong then 
        CGameMode.tPixels[iPixelID].bVisual = true
        CGameMode.tPixels[iPixelID].bClickable = false   

        AL.NewTimer(tConfig.PixelMoveDelayMS*2, function()
            if CGameMode.tPixels[iPixelID] and CGameMode.tPixels[iPixelID].iPointX then
                if tGame.Direction == 1 then
                    for iY = 1, tGame.StartPositions[iPlayerID].Y do
                        tFloor[CGameMode.tPixels[iPixelID].iPointX][iY].iPixelID = 0
                    end
                elseif tGame.Direction == 2 then
                    for iY = tGame.Rows, tGame.StartPositions[1].Y, -1 do
                        tFloor[CGameMode.tPixels[iPixelID].iPointX][iY].iPixelID = 0
                    end
                end
            end
        end)
    end
end

CGameMode.SpawnPixelForPlayers = function(iPointX, iBatchID, iPixelType)
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CGameMode.SpawnPixelForPlayer(i, iPointX, iBatchID, iPixelType)
        end
    end
end

CGameMode.SpawnPixelForPlayer = function(iPlayerID, iPointX, iBatchID, iPixelType)
    if iPixelType == "N" then return; end
    if 5 - iPointX > tGame.StartPositionSize then return; end

    iPointX = tGame.StartPositions[iPlayerID].X + 4 - iPointX
    local iPixelID = #CGameMode.tPixels+1

    CGameMode.tPixels[iPixelID] = CHelp.ShallowCopy(CGameMode.tPixelStruct)
    CGameMode.tPixels[iPixelID].iPointX = iPointX
    CGameMode.tPixels[iPixelID].iPlayerID = iPlayerID
    CGameMode.tPixels[iPixelID].iBright = tConfig.Bright
    CGameMode.tPixels[iPixelID].bClickable = true
    CGameMode.tPixels[iPixelID].iBatchID = iBatchID

    if tGame.Direction == 1 then
        CGameMode.tPixels[iPixelID].iPointY = tGame.Rows
    elseif tGame.Direction == 2 then
        CGameMode.tPixels[iPixelID].iPointY = 0
    end

    if string.match(iPixelType, "L") and not tConfig.EasyMode then
        CGameMode.tPixels[iPixelID].iColor = CColors.GREEN
    elseif string.match(iPixelType, "R")  and not tConfig.EasyMode then
        CGameMode.tPixels[iPixelID].iColor = CColors.GREEN
    elseif string.match(iPixelType, "H") then
        CGameMode.tPixels[iPixelID].iColor = CColors.BLUE
    end

    if tGame.Direction == 2 then
        if CGameMode.tPixels[iPixelID].iColor == CColors.GREEN then
           CGameMode.tPixels[iPixelID].iColor = CColors.YELLOW
        elseif CGameMode.tPixels[iPixelID].iColor == CColors.YELLOW then
           CGameMode.tPixels[iPixelID].iColor = CColors.GREEN
        end
    end

    CGameMode.tPixels[iPixelID].bProlong = string.match(iPixelType, "P") --and not tConfig.EasyMode
    CGameMode.tPixels[iPixelID].bVisual = string.match(iPixelType, "H")

    if CGameMode.tPlayerPixelBatches[iPlayerID] == nil then CGameMode.tPlayerPixelBatches[iPlayerID] = {} end
    CGameMode.tPlayerPixelBatches[iPlayerID][iBatchID] = true
end

CGameMode.EndGame = function()
    local iMaxScore = -1

    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] and tGameStats.Players[i] and tGameStats.Players[i].Score > iMaxScore then
            iMaxScore = tGameStats.Players[i].Score
            CGameMode.iWinnerID = i
        end
    end

    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color
    tGameResults.Won = true

    CPaint.ClearAnimations()
    --CPaint.AnimateEnd(tGameStats.Players[CGameMode.iWinnerID].Color)
    iGameState = GAMESTATE_POSTGAME
    CAudio.ResetSync()
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.Clear = function()
    --tPlayerInGame = {}

    for iPlayerID = 1, #tGame.StartPositions do
        tGameStats.Players[iPlayerID].Score = 0
    end

    CGameMode.tPixels = {}
    CGameMode.tPlayerPixelBatches = {}
    CGameMode.tPlayerRowClick = {}
end

CGameMode.SongTimer = function()
    tGameStats.StageLeftDuration = CSongSync.tSong[#CSongSync.tSong][1]/1000
    tGameStats.StageTotalDuration = CSongSync.tSong[#CSongSync.tSong][1]/1000

    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

        if tGameStats.StageLeftDuration > 0 then
            return 1000
        end

        return nil;
    end)
end

CGameMode.CountTargetScore = function()
    if CGameMode.iMaxPlayerScorePlayerID == -1 then return end

    tGameStats.TargetScore = tGameStats.Players[CGameMode.iMaxPlayerScorePlayerID].Score + #CSongSync.tSong - CSongSync.iSongPoint
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATE_DELAY = 50
CPaint.tHitAnimatedForPlayerID = {}

CPaint.Borders = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            local iColor = CColors.WHITE
            if tFloor[tGame.StartPositions[i].X-1] then
                SetRowColorBright(tGame.StartPositions[i].X-1, tGame.Rows, iColor, CColors.BRIGHT70)
            end

            if tFloor[tGame.StartPositions[i].X+tGame.StartPositionSize] then
                SetRowColorBright(tGame.StartPositions[i].X+tGame.StartPositionSize, tGame.Rows, iColor, CColors.BRIGHT70)
            end
        end
    end
end

CPaint.Pixels = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if tFloor[iX][iY] and tFloor[iX][iY].iPixelID and CGameMode.tPixels[tFloor[iX][iY].iPixelID] ~= nil then
                if not tFloor[iX][iY].bAnimated or tFloor[iX][iY].iAnimationPriority <= 0 then
                    tFloor[iX][iY].iColor = CGameMode.tPixels[tFloor[iX][iY].iPixelID].iColor
                    tFloor[iX][iY].iBright = CGameMode.tPixels[tFloor[iX][iY].iPixelID].iBright
                end
            end
        end
    end

    --[[
    for i = 1, #CGameMode.tPixels do
        if CGameMode.tPixels[i] then
            tFloor[CGameMode.tPixels[i].iPointX][CGameMode.tPixels[i].iPointY].iColor = CGameMode.tPixels[i].iColor
            tFloor[CGameMode.tPixels[i].iPointX][CGameMode.tPixels[i].iPointY].iBright = CGameMode.tPixels[i].iBright
        end
    end
    ]]
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    if tGame.Direction == 1 then
        SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y-1,}, tGame.StartPositionSize-1, tGame.StartPositions[iPlayerID].Color, iBright)
        SetColColorBright({X = tGame.StartPositions[iPlayerID].X+1, Y = tGame.StartPositions[iPlayerID].Y-2,}, tGame.StartPositionSize-3, tGame.StartPositions[iPlayerID].Color, iBright)
    elseif tGame.Direction == 2 then
        SetColColorBright({X = tGame.StartPositions[iPlayerID].X+1, Y = tGame.StartPositions[iPlayerID].Y+2,}, tGame.StartPositionSize-3, tGame.StartPositions[iPlayerID].Color, iBright)
        SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y+1,}, tGame.StartPositionSize-1, tGame.StartPositions[iPlayerID].Color, iBright)
    end
end

CPaint.PlayerZones = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CPaint.PlayerZone(i, CColors.BRIGHT15)
        end
    end
end

CPaint.AnimateRow = function(iX, iColor)
    for iY = 1, tGame.Rows do
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = CColors.BRIGHT15
        tFloor[iX][iY].bAnimated = true
    end

    if tConfig.RowColorSwitch then
        AL.NewTimer(tConfig.PixelMoveDelayMS, function()
            for iY = 1, tGame.Rows do
                tFloor[iX][iY].bAnimated = false
            end
        end)
    end
end

CPaint.AnimateHit = function(iPlayerID, bHit, iPixelX)
    if CPaint.tHitAnimatedForPlayerID[iPlayerID] then return; end
    CPaint.tHitAnimatedForPlayerID[iPlayerID] = true

    local iColor = CColors.GREEN
    if not bHit then iColor = CColors.RED end

    local iY = tGame.Rows
    if tGame.Direction == 2 then iY = 1 end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSize-1 do
        tFloor[iX][iY].bAnimated = true
        tFloor[iX][iY].iAnimationPriority = 1
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = tConfig.Bright

        if iX == iPixelX then
            tFloor[iX][iY].iBright = 7
        end
    end    

    AL.NewTimer(tConfig.PixelMoveDelayMS, function()
        CPaint.tHitAnimatedForPlayerID[iPlayerID] = false     
    end)
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if not tFloor[iX] or not tFloor[iX][iY] or tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true
    tFloor[iX][iY].iAnimationPriority = 1

    if not CTutorial.bDisableErrorSound and (tConfig.OutOfZoneSound or iGameState == GAMESTATE_TUTORIAL) then
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
    end

    if iGameState == GAMESTATE_TUTORIAL and CTutorial.bPreStarted and CTutorial.bStarted and not CTutorial.bTrueStarted then
        CTutorial.bDisableErrorSound = true

        AL.NewTimer(1500, function()
            CTutorial.Start()
        end)
    end

    local iCount = 0
    AL.NewTimer(CPaint.ANIMATE_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.RED
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = iColor
            iCount = iCount + 1
        end

        if iCount <= iFlickerCount then
            return CPaint.ANIMATE_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false
        tFloor[iX][iY].iAnimationPriority = 0


        return nil
    end)
end

CPaint.ClearAnimations = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
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

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
end

function SetRowColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart
        local iY = 1 + i

        if not (iY < 1 or iY > tGame.Rows) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
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

function SetColColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart.X + i
        local iY = tStart.Y

        if not (iX < 1 or iX > tGame.Cols) and not (iY < 1 or iY > tGame.Rows) and not tFloor[iX][iY].bAnimated then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end
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
        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
            return;
        end
        
        if iGameState == GAMESTATE_TUTORIAL and not CTutorial.bStarted then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
            else
                AL.NewTimer(500, function()
                    tFloor[click.X][click.Y].bClick = false
                end)
            end

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click then
            CGameMode.PlayerHitRow(click.X, click.Y, true)
        end
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or tButtons[click.Button].bDefect then return end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end
end


-----------------------------------------------------------

tTutorialSong =
{
    { 9000, "N", "N", "N", "N" },
    { 9500, "N", "N", "N", "N" },
    { 10000, "N", "N", "N", "N" },
    { 10500, "N", "N", "N", "N" },
    { 11000, "L", "N", "N", "N" },
    { 11500, "N", "N", "N", "N" },
    { 12000, "N", "N", "N", "N" },
    { 12500, "N", "N", "N", "N" },
    { 13000, "N", "R", "N", "N" },
    { 13500, "N", "N", "N", "N" },
    { 14000, "N", "N", "N", "N" },
    { 14500, "N", "N", "N", "N" },
    { 15000, "N", "N", "L", "N" },
    { 15500, "N", "N", "N", "N" },
    { 16000, "N", "N", "N", "N" },
    { 16500, "N", "N", "N", "N" },
    { 17000, "N", "N", "N", "R" },
    { 17500, "N", "N", "N", "N" },
    { 18000, "N", "N", "N", "N" },
    { 18500, "N", "N", "N", "N" },
    { 19000, "N", "N", "L", "N" },
    { 19500, "N", "N", "N", "N" },
    { 20000, "N", "N", "N", "N" },
    { 20500, "N", "N", "N", "N" },
    { 21000, "N", "R", "N", "N" },
    { 21500, "N", "N", "N", "N" },
    { 22000, "N", "N", "N", "N" },
    { 22500, "N", "N", "N", "N" },
    { 23000, "L", "N", "N", "N" },
    { 23500, "N", "R", "N", "N" },
    { 24000, "L", "N", "N", "N" },
    { 24500, "N", "R", "N", "N" },
    { 25000, "N", "N", "L", "N" },
    { 25500, "N", "N", "N", "R" },
    { 26000, "N", "N", "L", "N" },
    { 26500, "N", "N", "N", "R" },
    { 27000, "N", "N", "N", "N" },
    { 27500, "N", "L", "R", "N" },
    { 28000, "L", "R", "N", "N" },
    { 28500, "N", "L", "R", "N" },
    { 29000, "N", "N", "L", "R" },
    { 29500, "N", "L", "R", "N" },
    { 30000, "L", "R", "N", "N" },
    { 30500, "N", "N", "N", "N" },
    { 31000, "N", "N", "N", "N" },
    { 31500, "N", "N", "N", "N" },

    { 45000, "N", "N", "N", "N" },
    { 45500, "LP", "N", "N", "N" },
    { 46000, "LP", "N", "N", "N" },
    { 46500, "LP", "N", "N", "N" },
    { 47000, "LP", "N", "N", "N" },
    { 47500, "LP", "N", "N", "N" },
    { 48000, "L", "N", "N", "N" },
    { 48500, "N", "N", "RP", "N" },
    { 49000, "N", "N", "RP", "N" },
    { 49500, "N", "N", "RP", "N" },
    { 50000, "N", "N", "RP", "N" },
    { 50500, "N", "N", "RP", "N" },
    { 51000, "N", "N", "R", "N" },
    { 51500, "N", "LP", "N", "N" },
    { 52000, "N", "LP", "R", "N" },
    { 52500, "N", "LP", "N", "N" },
    { 53000, "N", "LP", "R", "N" },
    { 53500, "N", "LP", "N", "N" },
    { 54000, "N", "LP", "R", "N" },
    { 54500, "N", "L", "N", "N" },
    { 55000, "N", "N", "N", "N" },
    { 55500, "N", "L", "RP", "N" },
    { 56000, "N", "N", "RP", "N" },
    { 56500, "N", "L", "RP", "N" },
    { 57000, "N", "N", "RP", "N" },
    { 57500, "N", "L", "RP", "N" },
    { 58000, "N", "N", "R", "N" },
    { 58500, "N", "N", "N", "N" },
    { 65000, "N", "N", "N", "N" },
    { 65500, "L", "N", "N", "N" },
    { 66000, "N", "N", "N", "N" },
    { 66500, "N", "R", "N", "N" },
    { 67000, "N", "N", "N", "N" },
    { 67500, "N", "N", "L", "N" },
    { 68000, "N", "N", "N", "N" },
    { 68500, "N", "N", "N", "R" },
    { 69000, "N", "N", "N", "N" },
    { 69500, "H", "H", "H", "H" },
    { 70000, "N", "N", "N", "N" },
    { 70500, "N", "N", "L", "N" },
    { 71000, "N", "N", "N", "N" },
    { 71500, "N", "R", "N", "N" },
    { 72000, "N", "N", "N", "N" },
    { 72500, "L", "N", "N", "N" },
    { 73000, "N", "N", "N", "N" },
    { 73500, "H", "H", "H", "H" },
    { 74000, "N", "N", "N", "N" },
    { 74500, "N", "N", "N", "N" },
    { 75000, "N", "N", "N", "N" },
    { 75500, "N", "N", "N", "N" },
    { 76000, "N", "N", "N", "N" },
    { 84500, "N", "N", "N", "N" }
}
