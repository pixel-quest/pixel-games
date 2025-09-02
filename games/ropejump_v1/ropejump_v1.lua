--[[
    Название: Скакалка/Веревка
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Игроки стоят на безопасных мостах из белых пикселей и уклоняются от красной полоски которая наносит урон.
        Наступание на пискели вне моста также наносит урон.
        Синие монеты дают жизни если их собирать.
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
    StageNum = 1,
    TotalStages = 1,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 1,
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
    iTime = 0,
    bBridge = false,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local bAnyButtonClick = false

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
    tGame.CenterX = math.floor(tGame.Cols/2)
    tGame.CenterY = math.floor(tGame.Rows/2)
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CGameMode.PaintBridges()
    CGameMode.PaintAnimated()

    if not CGameMode.bCountDownStarted then
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
    
        if CGameMode.bCanAutoStart then
            for iX = tGame.CenterX-1, tGame.CenterX + 1 do
                for iY = tGame.CenterY, tGame.CenterY + 2 do
                    tFloor[iX][iY].iColor = CColors.BLUE
                    tFloor[iX][iY].iBright = tConfig.Bright
                    if tFloor[iX][iY].bClick then bAnyButtonClick = true; end
                end
            end
        end
    end    

    if bAnyButtonClick then
        bAnyButtonClick = false

        if not CGameMode.bCountDownStarted then
            CGameMode.StartCountDown(5)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CGameMode.PaintBridges()
    CRope.Paint()
    CGameMode.PaintCoin()
    CGameMode.PaintAnimated()
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
CGameMode.tAnimatedPixels = {}
CGameMode.bCanAutoStart = false
CGameMode.bLavaCD = false
CGameMode.tBridges = {}
CGameMode.tCoin = {}

CGameMode.BRIDGE_HEIGHT = 3

CGameMode.InitGameMode = function()
    if tGame.DamageDelay == nil then tGame.DamageDelay = 250; end

    tGameStats.TotalLives = tConfig.TeamHealth
    tGameStats.CurrentLives = tConfig.TeamHealth
    tGameStats.TotalStars = tConfig.JumpCount

    CGameMode.BuildBridges()
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("ropejump/ropejump-guide.mp3")
    CAudio.PlayVoicesSync("press-center-for-start.mp3")

    AL.NewTimer(CAudio.GetVoicesDuration("ropejump/ropejump-guide.mp3")*1000, function()
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

    CGameMode.PlaceCoin(math.random(1, #CGameMode.tBridges), math.random(tGame.iMinX, tGame.iMaxX))

    CRope.TimerLoop()
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    if bVictory then
        tGameResults.Won = true
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
        tGameResults.Color = CColors.GREEN
    else
        tGameResults.Won = false
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)        
end

CGameMode.AnimateDamage = function(iX, iY)
    local iAnimId = #CGameMode.tAnimatedPixels+1
    CGameMode.tAnimatedPixels[iAnimId] = {}
    CGameMode.tAnimatedPixels[iAnimId].iX = iX
    CGameMode.tAnimatedPixels[iAnimId].iY = iY
    CGameMode.tAnimatedPixels[iAnimId].bSwitch = false
    CGameMode.tAnimatedPixels[iAnimId].iCount = 5

    tFloor[iX][iY].bAnimated = true

    AL.NewTimer(200, function()
       CGameMode.tAnimatedPixels[iAnimId].bSwitch = not CGameMode.tAnimatedPixels[iAnimId].bSwitch 
       CGameMode.tAnimatedPixels[iAnimId].iCount = CGameMode.tAnimatedPixels[iAnimId].iCount - 1
       if CGameMode.tAnimatedPixels[iAnimId].iCount > 0 then return 200; end


       CGameMode.tAnimatedPixels[iAnimId] = nil
       tFloor[iX][iY].bAnimated = false
       return nil;
    end)
end

CGameMode.PaintAnimated = function()
    for iAnimId = 1, #CGameMode.tAnimatedPixels do
        if CGameMode.tAnimatedPixels[iAnimId] then
            iColor = CColors.MAGENTA
            if CGameMode.tAnimatedPixels[iAnimId].bSwitch then iColor = CColors.RED; end
            tFloor[CGameMode.tAnimatedPixels[iAnimId].iX][CGameMode.tAnimatedPixels[iAnimId].iY].iColor = iColor
            tFloor[CGameMode.tAnimatedPixels[iAnimId].iX][CGameMode.tAnimatedPixels[iAnimId].iY].iBright = tConfig.Bright
        end
    end
end

CGameMode.BuildBridges = function()
    local iY = CGameMode.BRIDGE_HEIGHT+1

    for iBridgeID = 1, 6 do
        CGameMode.tBridges[iBridgeID] = {}
        CGameMode.tBridges[iBridgeID].iY = iY

        iY = iY + CGameMode.BRIDGE_HEIGHT*2
        if iY + CGameMode.BRIDGE_HEIGHT-1 > tGame.iMaxY then break; end
    end
end

CGameMode.PaintBridges = function()
    for iBridgeID = 1, #CGameMode.tBridges do
        for iX = 1, tGame.Cols do
            for iY = CGameMode.tBridges[iBridgeID].iY, CGameMode.tBridges[iBridgeID].iY + CGameMode.BRIDGE_HEIGHT-1 do
                tFloor[iX][iY].iColor = CColors.WHITE
                tFloor[iX][iY].iBright = tConfig.Bright-1
                tFloor[iX][iY].bBridge = true
            end
        end
    end
end

CGameMode.PlaceCoin = function(iBridgeID, iX)
    CGameMode.tCoin = {}
    CGameMode.tCoin.iBridgeID = iBridgeID
    CGameMode.tCoin.iX = iX
end

CGameMode.PaintCoin = function()
    if CGameMode.tCoin.iBridgeID then
        local iY = CGameMode.tBridges[CGameMode.tCoin.iBridgeID].iY+1
        tFloor[CGameMode.tCoin.iX][iY].iColor = CColors.BLUE
        tFloor[CGameMode.tCoin.iX][iY].iBright = tConfig.Bright

        if tFloor[CGameMode.tCoin.iX][iY].bClick then CGameMode.CollectCoin(true) end
        if tFloor[CGameMode.tCoin.iX][iY].bDefect then CGameMode.CollectCoin(false) end
    end    
end

CGameMode.CollectCoin = function(bAddScore)
    if bAddScore then
        tGameStats.CurrentLives = tGameStats.CurrentLives + 1
        if tGameStats.CurrentLives > tGameStats.TotalLives then tGameStats.TotalLives = tGameStats.CurrentLives; end
        tGameResults.Score = tGameResults.Score + 50
    end
    CGameMode.PlaceCoin(math.random(1, #CGameMode.tBridges), math.random(tGame.iMinX, tGame.iMaxX))
end
--//

--ROPE
CRope = {}

CRope.MAX_VELOCITY = 200

CRope.iY = 0
CRope.iVelocity = 10

CRope.Paint = function()
    if CRope.iY > 0 and CRope.iY <= tGame.Rows then
        for iX = 1, tGame.Cols do
            if not tFloor[iX][CRope.iY].bAnimated then
                tFloor[iX][CRope.iY].iColor = CColors.RED
                tFloor[iX][CRope.iY].iBright = tConfig.Bright

                if tFloor[iX][CRope.iY].bClick and tFloor[iX][CRope.iY].iWeight > 10 and (CTime.unix() - tFloor[iX][CRope.iY].iTime)*1000 <= tGame.DamageDelay then
                    CRope.DamagePlayer()
                    CGameMode.AnimateDamage(iX, CRope.iY)
                end
            end
        end
    end
end

CRope.TimerLoop = function()
    CRope.iY = math.floor(-tGame.Rows/2)-1

    AL.NewTimer(CRope.MAX_VELOCITY+50-CRope.iVelocity, function()
        CRope.iY = CRope.iY - 1

        if CRope.iY == math.floor(-tGame.Rows/2) then
            tGameStats.CurrentStars = tGameStats.CurrentStars + 1
        
            tGameResults.Score = tGameResults.Score + 30

            if tGameStats.CurrentStars == tGameStats.TotalStars then
                CGameMode.EndGame(true)
            else
                CAudio.PlaySystemAsync(CAudio.STAGE_DONE)
                if tGameStats.TotalStars - tGameStats.CurrentStars <= 5 then
                    CAudio.PlayLeftAudio(tGameStats.TotalStars - tGameStats.CurrentStars)
                end
            end
        elseif CRope.iY <= -tGame.Rows - 2 then
            CRope.iY = tGame.Rows
            CRope.iVelocity = CRope.iVelocity + (CRope.MAX_VELOCITY/tConfig.JumpCount)
        end

        if iGameState == GAMESTATE_GAME then
            return CRope.MAX_VELOCITY+1-CRope.iVelocity
        end
    end)
end

CRope.DamagePlayer = function()
    tGameStats.CurrentLives = tGameStats.CurrentLives-1
    if tGameStats.CurrentLives <= 0 and tConfig.TeamHealth > 0 then
        CGameMode.EndGame(false)
    else
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
    end

    tGameResults.Score = tGameResults.Score - 10
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
            tFloor[click.X][click.Y].iWeight = 0
            return;
        end

        if click.Click then
            tFloor[click.X][click.Y].iTime = CTime.unix()
        end

        if click.Click and not tFloor[click.X][click.Y].bDefect and not tFloor[click.X][click.Y].bBridge then
            CGameMode.AnimateDamage(click.X, click.Y)

            if iGameState == GAMESTATE_GAME and not CGameMode.bLavaCD then
                CRope.DamagePlayer()

                CGameMode.bLavaCD = true
                AL.NewTimer(250, function()
                    CGameMode.bLavaCD = false
                end)
            end
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

    if click.Click then bAnyButtonClick = true; end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end