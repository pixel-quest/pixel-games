--[[
    Название: Луч
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
        { Score = 0, Lives = 0, Color = CColors.GREEN },
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
    ScoreboardVariant = 5,
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

    if CGameMode.bCanAutoStart and not CGameMode.bCountDownStarted then
        CGameMode.StartCountDown(3)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CBeam.Paint()
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
CGameMode.bBlockMoved = false
CGameMode.bFinishedPause = false

CGameMode.tPlayerColors = {}

CGameMode.InitGameMode = function()
   tGameStats.TargetScore = tConfig.TargetScore
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("beam-bounce/bb-rules.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("beam-bounce/bb-rules.mp3")*1000, function()
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
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    iGameState = GAMESTATE_GAME
    CGameMode.NextRound()

    if tConfig.TimeLimit > 0 then
        tGameStats.StageTotalDuration = tConfig.TimeLimit
        tGameStats.StageLeftDuration = tConfig.TimeLimit
        AL.NewTimer(1000, function()
            if iGameState ~= GAMESTATE_GAME then return nil; end

            if not CGameMode.bFinishedPause then
                tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
                if tGameStats.StageLeftDuration == 0 then
                    CGameMode.bFinishedPause = true
                    CGameMode.EndGame(false)
                    return nil;
                end
            end

            return 1000;
        end)
    end
end

CGameMode.NextRound = function()
    CGameMode.LoadNewLevel()

    CAudio.PlaySystemAsync("dodge/lightsaber-ignition.mp3")

    CBeam.iDrawLimit = 0
    AL.NewTimer(100, function()
        CBeam.iDrawLimit = CBeam.iDrawLimit + 1
        if CGameMode.bBlockMoved or CBeam.iDrawLimit > 100 then 
            CBeam.iDrawLimit = 1000;
            return nil; 
        end
        return 100
    end)

    CGameMode.bFinishedPause = false
end

CGameMode.LoadNewLevel = function()
    repeat
        CObjects.tObjects = {}
        CBeam.iStartX = math.random(tGame.iMinX+3, tGame.iMaxX-3)
        CBeam.iStartY = math.random(tGame.iMinY+3, tGame.iMaxY-3) 
        CBeam.iStartVelX = 1; 
        if CBeam.iStartX > tGame.CenterX then CBeam.iStartVelX = -1; end
        CBeam.iStartVelY = 1; 
        if CBeam.iStartY > tGame.CenterY then CBeam.iStartVelY = -1; end

        local iX = CBeam.iStartX
        local iVelX = CBeam.iStartVelX
        local iY = CBeam.iStartY
        local iVelY = CBeam.iStartVelY
        for i = 1, (tGame.Cols+tGame.Rows)*3 do
            iX = iX + iVelX
            iY = iY + iVelY
            CBeam.tCorrectPoints[#CBeam.tCorrectPoints+1] = {iX = iX, iY = iY}

            local bCol = false

            for iObjectId = 1, #CObjects.tObjects-1 do
                if AL.RectIntersects2(iX+iVelX, iY, 1, 1, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iSizeX, CObjects.tObjects[iObjectId].iSizeY) then
                    iVelX = -iVelX
                    bCol = true
                elseif AL.RectIntersects2(iX, iY+iVelY, 1, 1, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iSizeX, CObjects.tObjects[iObjectId].iSizeY) then
                    iVelY = -iVelY
                    bCol = true
                end
            end

            if #CObjects.tObjects < 5 and not bCol then
                if iX + iVelX <= tGame.iMinX+2 then
                    CObjects.AddNew(iX-2, iY-iVelY-1,2,4,CColors.BLUE,CObjects.OBJECT_TYPE_MOVE_Y)
                    iVelX = -iVelX
                elseif iX + iVelX >= tGame.iMaxX-3 then
                    CObjects.AddNew(iX+2, iY-1,2,4,CColors.BLUE,CObjects.OBJECT_TYPE_MOVE_Y)
                    iVelX = -iVelX
                elseif iY + iVelY <= tGame.iMinY+2 then
                    CObjects.AddNew(iX+iVelX-1, iY-2,4,2,CColors.CYAN,CObjects.OBJECT_TYPE_MOVE_X)
                    iVelY = -iVelY
                elseif iY + iVelY >= tGame.iMaxY-3 then
                    CObjects.AddNew(iX-1, iY+2,4,2,CColors.CYAN,CObjects.OBJECT_TYPE_MOVE_X)
                    iVelY = -iVelY
                end
            end

            local iFinX = -10
            local iFinY = -10
            if iX+iVelX == tGame.iMinX then
                iFinX = tGame.iMinX-2
                iFinY = iY+iVelY
            elseif iX+iVelX == tGame.iMaxX then
                iFinX = tGame.iMaxX
                iFinY = iY+iVelY
            elseif iY+iVelY == tGame.iMinY then
                iFinY = tGame.iMinY-2
                iFinX = iX+iVelX
            elseif iY+iVelY == tGame.iMaxY then
                iFinY = tGame.iMaxY
                iFinX = iX+iVelX
            end

            if iFinX > -10 then
                CObjects.AddNew(iFinX, iFinY,3,3,CColors.RED,CObjects.OBJECT_TYPE_FINISH)
                break;
            end
        end
    until CBeam.Cast()

    for iObjectId = 1, #CObjects.tObjects-1 do
        local iTargetX = CObjects.tObjects[iObjectId].iX
        local iTargetY = CObjects.tObjects[iObjectId].iY

        if CObjects.tObjects[iObjectId].iObjectType == CObjects.OBJECT_TYPE_MOVE_X then
            repeat
                CObjects.tObjects[iObjectId].iX = math.random(tGame.iMinX, tGame.iMaxX)
            until CObjects.IsValidPosition(iObjectId, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY) and math.abs(CObjects.tObjects[iObjectId].iX-iTargetX) > 2
        elseif CObjects.tObjects[iObjectId].iObjectType == CObjects.OBJECT_TYPE_MOVE_Y then
            repeat
                CObjects.tObjects[iObjectId].iY = math.random(tGame.iMinY, tGame.iMaxY)
            until CObjects.IsValidPosition(iObjectId, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY) and math.abs(CObjects.tObjects[iObjectId].iY-iTargetY) > 2
        end
    end 

    CBeam.Cast()
end

CGameMode.HitFinish = function(iObjectId)
    CObjects.tObjects[#CObjects.tObjects].iColor = CColors.GREEN
    CGameMode.bFinishedPause = true

    tGameStats.Players[1].Score = tGameStats.Players[1].Score + 1
    if tGameStats.Players[1].Score >= tGameStats.TargetScore then
        AL.NewTimer(100,function()
            CGameMode.EndGame(true)
        end)
    else
        CAudio.PlaySystemAsync(CAudio.STAGE_DONE)
        AL.NewTimer(5000, function()
            CGameMode.NextRound()
        end)
    end
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    if bVictory then
        tGameResults.Won = true
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN
    else
        tGameResults.Won = false
        CAudio.PlayVoicesSync("notime.mp3")
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)  
end
--//

--Beam
CBeam = {}
CBeam.tBeam = {}
CBeam.tCorrectPoints = {}

CBeam.iStartX = 1
CBeam.iStartY = 1
CBeam.iStartVelX = 1
CBeam.iStartVelY = 1
CBeam.iDrawLimit = 1

CBeam.iColCount = 0
CBeam.iPrevTickColCount = 0

CBeam.Cast = function()
    CBeam.tBeam = {}
    local iX = CBeam.iStartX
    local iVelX = CBeam.iStartVelX
    local iY = CBeam.iStartY
    local iVelY = CBeam.iStartVelY

    CBeam.iPrevTickColCount = CBeam.iColCount
    CBeam.iColCount = 0

    while iX >= tGame.iMinX and iX <= tGame.iMaxX and iY >= tGame.iMinY and iY <= tGame.iMaxY do
        local iPoint = #CBeam.tBeam+1
        CBeam.tBeam[iPoint] = {}
        CBeam.tBeam[iPoint].iX = iX
        CBeam.tBeam[iPoint].iY = iY

        local bPrevCol = false
        for iObjectId = 1, #CObjects.tObjects do
            local colX = false
            local colY = false
            
            if AL.RectIntersects2(iX+iVelX, iY, 1, 1, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iSizeX, CObjects.tObjects[iObjectId].iSizeY) then
                iVelX = -iVelX
                colX = true
            end
            if AL.RectIntersects2(iX, iY+iVelY, 1, 1, CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iSizeX, CObjects.tObjects[iObjectId].iSizeY) then
                iVelY = -iVelY
                colY = true
            end

            if colX or colY then
                CBeam.iColCount = CBeam.iColCount + 1
                if CObjects.tObjects[iObjectId].iObjectType == CObjects.OBJECT_TYPE_FINISH then
                    return true;
                end
                if colX and colY then return false; end
                if bPrevCol then return false; end
                bPrevCol = true
            end
        end

        iX = iX + iVelX
        iY = iY + iVelY
    end

    return false;
end

CBeam.Paint = function()
    for iPoint = 1, #CBeam.tBeam do
        if iPoint > CBeam.iDrawLimit then return; end

        tFloor[CBeam.tBeam[iPoint].iX][CBeam.tBeam[iPoint].iY].iColor = CColors.GREEN;
        if tFloor[CBeam.tBeam[iPoint].iX][CBeam.tBeam[iPoint].iY].iBright > CColors.BRIGHT0 then
            tFloor[CBeam.tBeam[iPoint].iX][CBeam.tBeam[iPoint].iY].iBright = tFloor[CBeam.tBeam[iPoint].iX][CBeam.tBeam[iPoint].iY].iBright + 1
        else
            tFloor[CBeam.tBeam[iPoint].iX][CBeam.tBeam[iPoint].iY].iBright = tConfig.Bright
        end
    end
end
--//

--Objects
CObjects = {}
CObjects.tObjects = {}

CObjects.OBJECT_TYPE_MOVE_X = 1
CObjects.OBJECT_TYPE_MOVE_Y = 2
CObjects.OBJECT_TYPE_FINISH = 3

CObjects.AddNew = function(iX, iY, iSizeX, iSizeY, iColor, iObjectType)
    local iObjectId = #CObjects.tObjects+1
    CObjects.tObjects[iObjectId] = {}
    CObjects.tObjects[iObjectId].iX = iX
    CObjects.tObjects[iObjectId].iY = iY
    CObjects.tObjects[iObjectId].iSizeX = iSizeX
    CObjects.tObjects[iObjectId].iSizeY = iSizeY
    CObjects.tObjects[iObjectId].iColor = iColor
    CObjects.tObjects[iObjectId].iObjectType = iObjectType
    CObjects.tObjects[iObjectId].bMoveCooldown = false

    --return CObjects.IsValidPosition(iObjectId, iX, iY)
end

CObjects.TryMove = function(iObjectId, iPlusX, iPlusY)
    if CObjects.IsValidPosition(iObjectId, CObjects.tObjects[iObjectId].iX + iPlusX, CObjects.tObjects[iObjectId].iY + iPlusY) then
        CObjects.tObjects[iObjectId].iX = CObjects.tObjects[iObjectId].iX + iPlusX
        CObjects.tObjects[iObjectId].iY = CObjects.tObjects[iObjectId].iY + iPlusY

        CGameMode.bBlockMoved = true
        if CBeam.Cast() then
            CGameMode.HitFinish()
        else
            if CBeam.iColCount > CBeam.iPrevTickColCount then
                CAudio.PlaySystemAsync("dodge/lightsaber-swing.mp3")
            end
            CObjects.tObjects[iObjectId].bMoveCooldown = true
            AL.NewTimer(500, function()
                CObjects.tObjects[iObjectId].bMoveCooldown = false
            end) 
        end
    end
end

CObjects.IsValidPosition = function(iObjectId, iX, iY)
    if iX < tGame.iMinX or iY < tGame.iMinY then return false; end
    if iX+CObjects.tObjects[iObjectId].iSizeX-1 > tGame.iMaxX or iY+CObjects.tObjects[iObjectId].iSizeY-1 > tGame.iMaxY then return false; end

    for iColId = 1, #CObjects.tObjects do
        if iColId ~= iObjectId and CObjects.tObjects[iColId].iObjectType ~= CObjects.OBJECT_TYPE_FINISH then
            if AL.RectIntersects2(CObjects.tObjects[iColId].iX, CObjects.tObjects[iColId].iY, CObjects.tObjects[iColId].iSizeX, CObjects.tObjects[iColId].iSizeY, iX, iY, CObjects.tObjects[iObjectId].iSizeX, CObjects.tObjects[iObjectId].iSizeY) then
                return false;
            end
        end
    end

    return true
end

CObjects.Paint = function()
    for iObjectId = 1, #CObjects.tObjects do
        for iX = CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iX+CObjects.tObjects[iObjectId].iSizeX-1 do 
            for iY = CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iY+CObjects.tObjects[iObjectId].iSizeY-1 do 
                if tFloor[iX] and tFloor[iX][iY] then
                    tFloor[iX][iY].iColor = CObjects.tObjects[iObjectId].iColor
                    tFloor[iX][iY].iBright = tConfig.Bright
                end 
            end
        end

        if not CGameMode.bFinishedPause and not CObjects.tObjects[iObjectId].bMoveCooldown then
            local function paintMove(iX, iY, iPlusX, iPlusY)
                if tFloor[iX] and tFloor[iX][iY] and tFloor[iX][iY].iColor == CColors.NONE then
                    tFloor[iX][iY].iColor = CObjects.tObjects[iObjectId].iColor
                    tFloor[iX][iY].iBright = tConfig.Bright-3
                    if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                        CObjects.TryMove(iObjectId, iPlusX, iPlusY)
                    end
                end
            end

            if CObjects.tObjects[iObjectId].iObjectType == CObjects.OBJECT_TYPE_MOVE_X then
                for iY = CObjects.tObjects[iObjectId].iY, CObjects.tObjects[iObjectId].iY+CObjects.tObjects[iObjectId].iSizeY-1 do 
                    paintMove(CObjects.tObjects[iObjectId].iX-1, iY, -1, 0)
                    paintMove(CObjects.tObjects[iObjectId].iX+CObjects.tObjects[iObjectId].iSizeX, iY, 1, 0)
                end
            elseif CObjects.tObjects[iObjectId].iObjectType == CObjects.OBJECT_TYPE_MOVE_Y then
                for iX = CObjects.tObjects[iObjectId].iX, CObjects.tObjects[iObjectId].iX+CObjects.tObjects[iObjectId].iSizeX-1 do 
                    paintMove(iX, CObjects.tObjects[iObjectId].iY-1, 0, -1)
                    paintMove(iX, CObjects.tObjects[iObjectId].iY+CObjects.tObjects[iObjectId].iSizeY, 0, 1)            
                end
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