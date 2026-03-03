--[[
    Название: Флэппи бёрд
    Автор: Avondale, дискорд - avonda
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
    CGameMode.PaintZones()
    CPipes.Paint()
    CBirds.Paint()

    if not CGameMode.bCountDownStarted and CGameMode.bCanAutoStart and CGameMode.iPlayersReady > 1 then
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CGameMode.PaintZones()
    CPipes.Paint()
    CBirds.Paint()
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

CGameMode.MAX_PLAYERS = 6

CGameMode.iGameZoneX = 1
CGameMode.iGameZoneY = 1
CGameMode.iGameZoneSizeX = 10
CGameMode.iGameZoneSizeY = 10
CGameMode.iGameZoneMiddleY = 5

CGameMode.tPlayerInGame = {}
CGameMode.iPlayerZoneSizeX = 2
CGameMode.iPlayerZoneSizeY = 3

CGameMode.iYGravity = -1
CGameMode.iPipesVel = 1

CGameMode.iPlayersReady = 0
CGameMode.iPlayersAlive = 0
CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.BLUE
CGameMode.tPlayerColors[2] = CColors.MAGENTA
CGameMode.tPlayerColors[3] = CColors.CYAN
CGameMode.tPlayerColors[4] = CColors.YELLOW
CGameMode.tPlayerColors[5] = CColors.GREEN
CGameMode.tPlayerColors[6] = CColors.RED

CGameMode.InitGameMode = function()
    --CGameMode.iPlayerZoneSizeX = math.floor((tGame.iMaxX-tGame.iMinX+1)/(CGameMode.MAX_PLAYERS+1))

    CGameMode.iGameZoneX = tGame.iMinX
    CGameMode.iGameZoneY = tGame.iMinY
    CGameMode.iGameZoneSizeX = tGame.iMaxX
    CGameMode.iGameZoneSizeY = tGame.iMaxY - CGameMode.iPlayerZoneSizeY

    if not tGame.MirrorGame then
        CGameMode.iGameZoneY = CGameMode.iGameZoneY + CGameMode.iPlayerZoneSizeY
    else
        CGameMode.iYGravity = 1
        CGameMode.iPipesVel = -1
    end

    CGameMode.iGameZoneMiddleX = CGameMode.iGameZoneX+math.floor((CGameMode.iGameZoneSizeX-CGameMode.iGameZoneX+1)/2)
    CGameMode.iGameZoneMiddleY = CGameMode.iGameZoneY+math.floor((CGameMode.iGameZoneSizeY-CGameMode.iGameZoneY+1)/2)

    CBirds.BIRD_SIZE = tConfig.BirdSize

    tGameStats.TargetScore = tConfig.Lives

    CPipes.Init()
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("flappy-bird/flappy-bird-rules.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("flappy-bird/flappy-bird-rules.mp3")*1000, function()
            CGameMode.bCanAutoStart = true
        end)    
    else
        CGameMode.bCanAutoStart = true
    end
end

CGameMode.PaintZones = function()
    local iStartX = tGame.iMaxX-CGameMode.iPlayerZoneSizeX
    local iStartY = tGame.iMinY

    if tGame.MirrorGame then
        iStartX = tGame.iMinX+1
        iStartY = tGame.iMaxY-CGameMode.iPlayerZoneSizeY+1
    end

    for iPlayerID = 1, CGameMode.MAX_PLAYERS do
        if iGameState == GAMESTATE_SETUP or CGameMode.tPlayerInGame[iPlayerID] then
            local iBright = 1
            if CGameMode.tPlayerInGame[iPlayerID] and iGameState == GAMESTATE_SETUP then iBright = tConfig.Bright-1; 
            elseif CGameMode.tPlayerInGame[iPlayerID] and iGameState == GAMESTATE_GAME then
                local tBird = CBirds.GetPlayerBird(iPlayerID)
                if tBird.bAlive and not tBird.bTapCD then
                    iBright = tConfig.Bright-1
                end
            end

            local bClick = false
            for iX = iStartX, iStartX + CGameMode.iPlayerZoneSizeX-1 do
                for iY = iStartY+1, iStartY + CGameMode.iPlayerZoneSizeY-1 do
                    tFloor[iX][iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                    tFloor[iX][iY].iBright = iBright

                    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick then
                        bClick = true
                    end
                end
            end

            if bClick then
                if iGameState == GAMESTATE_SETUP then
                    if not CGameMode.tPlayerInGame[iPlayerID] then
                        CGameMode.iPlayersReady = CGameMode.iPlayersReady + 1
                    end
                    CGameMode.tPlayerInGame[iPlayerID] = true
                    tGameStats.Players[iPlayerID].Color = CGameMode.tPlayerColors[iPlayerID]
                elseif iGameState == GAMESTATE_GAME then
                    CBirds.PlayerTapBird(CBirds.GetPlayerBird(iPlayerID))
                end
            else
                if iGameState == GAMESTATE_SETUP and not CGameMode.bCountDownStarted then
                    if CGameMode.tPlayerInGame[iPlayerID] then
                        CGameMode.iPlayersReady = CGameMode.iPlayersReady - 1
                    end
                    CGameMode.tPlayerInGame[iPlayerID] = false
                    tGameStats.Players[iPlayerID].Color = CColors.NONE
                end
            end
        end

        iStartX = iStartX + (1 + CGameMode.iPlayerZoneSizeX) * -CGameMode.iPipesVel
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

    CGameMode.iPlayersAlive = CGameMode.iPlayersReady

    CGameMode.SpawnBirds()

    AL.NewTimer(tConfig.TickRate * 4, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CPipes.Tick()

        return tConfig.TickRate 
    end)

    AL.NewTimer(tConfig.TickRate , function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CBirds.Tick()

        return tConfig.TickRate      
    end)

    AL.NewTimer(tConfig.TickRate/3, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CBirds.Animate()

        return tConfig.TickRate/3
    end)
end

CGameMode.EndGame = function()
    local iMaxScore = -1
    local iWinnerID = 1
    for iPlayerID = 1, CGameMode.MAX_PLAYERS do
        if tGameStats.Players[iPlayerID].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerID].Score
            iWinnerID = iPlayerID
        end
    end

    tGameResults.Color = CGameMode.tPlayerColors[iWinnerID]
    tGameResults.Won = true

    CAudio.StopBackground()
    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[iWinnerID])
    CAudio.PlayVoicesSync(CAudio.VICTORY)    

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(CGameMode.tPlayerColors[iWinnerID], tConfig.Bright)

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)        
end

CGameMode.SpawnBirds = function()
    local iX = CGameMode.iGameZoneMiddleX - (CGameMode.iPipesVel*CBirds.BIRD_SIZE*3)

    for iPlayerID = 1, CGameMode.MAX_PLAYERS do
        if CGameMode.tPlayerInGame[iPlayerID] then
            CBirds.Add(iX, CGameMode.iGameZoneMiddleY, iPlayerID)

            tGameStats.Players[iPlayerID].Score = tConfig.Lives

            iX = iX + CGameMode.iPipesVel + (CGameMode.iPipesVel*CBirds.BIRD_SIZE)
        end
    end
end

CGameMode.AddScore = function()
    tGameResults.Score = tGameResults.Score + 100 - tConfig.Lives
end
--//

--PIPES
CPipes = {}
CPipes.tPipes = AL.Stack()
CPipes.PIPE_SIZE_X = 2

CPipes.iColor = 0

CPipes.Init = function()
    CPipes.iColor = CColors.GREEN

    local iX = CGameMode.iGameZoneX+1
    if tGame.MirrorGame then
        iX = CGameMode.iGameZoneX + CGameMode.iGameZoneSizeX-3
    end

    for i = 1, 10 do
        CPipes.AddNew(iX)
        iX = iX + -CGameMode.iPipesVel * (CPipes.PIPE_SIZE_X + tConfig.StepSize-1)
    end
end

CPipes.AddNew = function(iX)
    local tPipe = {}

    tPipe.iX = iX
    tPipe.iY = CGameMode.iGameZoneY
    tPipe.iSizeY = CGameMode.iGameZoneSizeY
    tPipe.iSplitY = math.random(CGameMode.iGameZoneY+tConfig.GapSize, CGameMode.iGameZoneY+CGameMode.iGameZoneSizeY-1-tConfig.GapSize)

    CPipes.tPipes.Push(tPipe)
end

CPipes.Tick = function()
    for iPipeID = 1, CPipes.tPipes.Size() do
        local tPipe = CPipes.tPipes.Pop()

        tPipe.iX = tPipe.iX + CGameMode.iPipesVel

        if (not tGame.MirrorGame and tPipe.iX <= tGame.Cols) or (tGame.MirrorGame and tPipe.iX > 0) then
            CPipes.tPipes.Push(tPipe)
        else
            CGameMode.AddScore()
            CPipes.AddNew(tPipe.iX + ((-CGameMode.iPipesVel * (CPipes.PIPE_SIZE_X + tConfig.StepSize-1)*10)))
        end
    end
end

CPipes.Paint = function()
    for iPipeID = 1, CPipes.tPipes.Size() do
        local tPipe = CPipes.tPipes.Pop()

        for iX = tPipe.iX, tPipe.iX + CPipes.PIPE_SIZE_X-1 do
            for iY = tPipe.iY, tPipe.iY + tPipe.iSizeY-1 do
                if iY <= tPipe.iSplitY-math.floor(tConfig.GapSize/2) or iY > tPipe.iSplitY+math.ceil(tConfig.GapSize/2) then
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CPipes.iColor
                        tFloor[iX][iY].iBright = tConfig.Bright
                    end
                end
            end
        end

        CPipes.tPipes.Push(tPipe)
    end
end
--//

--Birds
CBirds = {}
CBirds.tBirds = {}

CBirds.BIRD_SIZE = 2

CBirds.Add = function(iX, iY, iPlayerID)
    local iBirdID = #CBirds.tBirds+1
    CBirds.tBirds[iBirdID] = {} 
    CBirds.tBirds[iBirdID].iX = iX 
    CBirds.tBirds[iBirdID].iY = iY 
    CBirds.tBirds[iBirdID].iPlayerID = iPlayerID 
    CBirds.tBirds[iBirdID].iBirdID = iBirdID
    CBirds.tBirds[iBirdID].iBright = tConfig.Bright

    CBirds.tBirds[iBirdID].bAlive = true
    CBirds.tBirds[iBirdID].bTapCD = false
    CBirds.tBirds[iBirdID].iInvulnerableTicks = 0
end

CBirds.Tick = function()
    for iBirdID = 1, #CBirds.tBirds do
        if CBirds.tBirds[iBirdID].bAlive then
            if CBirds.tBirds[iBirdID].iInvulnerableTicks > 0 then
                CBirds.tBirds[iBirdID].iInvulnerableTicks = CBirds.tBirds[iBirdID].iInvulnerableTicks - 1
            else
                if not CBirds.tBirds[iBirdID].bTapCD then
                    CBirds.tBirds[iBirdID].iY = CBirds.tBirds[iBirdID].iY + CGameMode.iYGravity
                end

                if CBirds.tBirds[iBirdID].iY < tGame.iMinY-1 or CBirds.tBirds[iBirdID].iY > tGame.iMaxY then
                    CBirds.DamageBird(iBirdID)
                else
                    CBirds.CheckCollision(CBirds.tBirds[iBirdID])
                end
            end
        end
    end
end

CBirds.Paint = function()
    for iBirdID = 1, #CBirds.tBirds do
        if CBirds.tBirds[iBirdID].bAlive then
            for iX = CBirds.tBirds[iBirdID].iX, CBirds.tBirds[iBirdID].iX + CBirds.BIRD_SIZE-1 do
                for iY = CBirds.tBirds[iBirdID].iY, CBirds.tBirds[iBirdID].iY + CBirds.BIRD_SIZE-1 do
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CGameMode.tPlayerColors[CBirds.tBirds[iBirdID].iPlayerID]
                        tFloor[iX][iY].iBright = CBirds.tBirds[iBirdID].iBright
                    end
                end
            end
        end
    end
end

CBirds.CheckCollision = function(tBird)
    for iPipeID = 1, CPipes.tPipes.Size() do
        local tPipe = CPipes.tPipes.Pop()

        if tBird.iX + CBirds.BIRD_SIZE-1 >= tPipe.iX and tBird.iX <= tPipe.iX + CPipes.PIPE_SIZE_X-1 then
            if tBird.iY <= tPipe.iSplitY-math.floor(tConfig.GapSize/2) or tBird.iY + CBirds.BIRD_SIZE-1 > tPipe.iSplitY+math.ceil(tConfig.GapSize/2) then
                CBirds.DamageBird(tBird.iBirdID)
            end
        end

        CPipes.tPipes.Push(tPipe)
    end
end

CBirds.DamageBird = function(iBirdID)
    tGameStats.Players[CBirds.tBirds[iBirdID].iPlayerID].Score = tGameStats.Players[CBirds.tBirds[iBirdID].iPlayerID].Score - 1
    if tGameStats.Players[CBirds.tBirds[iBirdID].iPlayerID].Score <= 0 then
        CBirds.KillBird(iBirdID)
        return true;
    end

    CBirds.tBirds[iBirdID].iInvulnerableTicks = 4

    CBirds.tBirds[iBirdID].iY = CGameMode.iGameZoneMiddleY 

    CAudio.PlaySystemAsync(CAudio.MISCLICK)

    return false
end

CBirds.KillBird = function(iBirdID)
    CBirds.tBirds[iBirdID].bAlive = false
    CAudio.PlaySystemAsync(CAudio.GAME_OVER)

    CGameMode.iPlayersAlive = CGameMode.iPlayersAlive - 1
    if CGameMode.iPlayersAlive <= 1 then
        CGameMode.EndGame()
    end
end

CBirds.GetPlayerBird = function(iPlayerID)
    for iBirdID = 1, #CBirds.tBirds do
        if CBirds.tBirds[iBirdID].iPlayerID == iPlayerID then
            return CBirds.tBirds[iBirdID]
        end
    end

    return nil
end

CBirds.PlayerTapBird = function(tBird)
    if tBird.bAlive and not tBird.bTapCD and tBird.iY > 0 and tBird.iY < tGame.Rows then
        tBird.iY = tBird.iY + -CGameMode.iYGravity

        tBird.bTapCD = true
        AL.NewTimer(tConfig.TickRate/2.5, function()
            tBird.bTapCD = false
        end)

        if tBird.iInvulnerableTicks == 0 then
            CBirds.CheckCollision(tBird)
        end
    end
end

CBirds.Animate = function()
    for iBirdID = 1, #CBirds.tBirds do
        if CBirds.tBirds[iBirdID].bAlive and CBirds.tBirds[iBirdID].iInvulnerableTicks > 0 and CBirds.tBirds[iBirdID].iBright == tConfig.Bright then
            CBirds.tBirds[iBirdID].iBright = 1
        else
            CBirds.tBirds[iBirdID].iBright = tConfig.Bright
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