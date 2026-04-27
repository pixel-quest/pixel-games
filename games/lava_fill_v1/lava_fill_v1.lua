--[[
    Название: Название механики
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
    TargetScore = 0,
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
    iCoin = -1,
    bAnimated = false
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
    iCoin = -1,
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
    CShape.Paint()

    if CGameMode.bCanAutoStart and not CGameMode.bCountDownStarted then
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CObjects.Paint()
    CCoins.Paint()    
    CShape.Paint()
end

function PostGameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CShape.Paint()    
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

CGameMode.tPlayerColors = {}

CGameMode.InitGameMode = function()
    CShape.Init()
    tGameStats.Players[1].Score = CShape.iFill
    tGameStats.TargetScore = CShape.iMaxFill
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("lava-fill/lava-fill-rules.mp3")
        CAudio.PlayVoicesSync("stand_on_green_zone_and_wait.mp3")
        AL.NewTimer((CAudio.GetVoicesDuration("lava-fill/lava-fill-rules.mp3")*1000) + (CAudio.GetVoicesDuration("stand_on_green_zone_and_wait.mp3")*1000), function()
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

    CGameMode.SpawnNewRandomObjects()

    for iCoin = 1, tConfig.CoinCount do
        CCoins.NewRandomCoin()
    end

    CShape.iFadeTime = tConfig.FadeTime
    AL.NewTimer(1000, function()
        if iGameState ~= GAMESTATE_GAME then return end;

        CShape.iFadeTime = CShape.iFadeTime - 1

        if CShape.iFadeTime <= 0 then
            CShape.DecreaseFill()
        end

        tGameStats.StageLeftDuration = CShape.iFadeTime

        return 1000;
    end)

    AL.NewTimer(tConfig.ObjectsTickRate, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        CObjects.Tick()

        return tConfig.ObjectsTickRate
    end)
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    if bVictory then
        tGameResults.Won = true
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN
    else
        tGameResults.Won = false
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)        
end

CGameMode.SpawnNewRandomObjects = function()
    if not CObjects.bClearing then
        CObjects.Clear(function() 
            local iRand = math.random(1,2)
            local iSize = math.random(2,4)
            if iRand == 1 then
                CObjects.NewObject(1, -iSize, tGame.Cols, iSize, 0, 1)
            else
                CObjects.NewObject(-iSize, 1, iSize, tGame.Rows, 1, 0)
            end
        end)
    end
end

CGameMode.PlayerStepOnLava = function(iX, iY)
    AL.NewTimer(tGame.BurnDelay, function()
        if iGameState == GAMESTATE_GAME and tFloor[iX][iY].bClick and not tFloor[iX][iY].bAnimated and tFloor[iX][iY].iColor == CColors.RED then
            CAudio.PlaySystemAsync(CAudio.MISCLICK)

            CShape.DecreaseFill()
            tGameStats.StageLeftDuration = CShape.iFadeTime

            CGameMode.AnimatePixelFlicker(iX, iY, 5, CColors.RED)
        end
    end)
end

CGameMode.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(30, function()
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
            return 200
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end
--//

--Shape
CShape = {}
CShape.tShape = {}
CShape.iFill = 0
CShape.iFadeTime = 0

CShape.Init = function()
    CShape.iX = tGame.CenterX + 1
    CShape.iY = tGame.CenterY 

    CShape.iR = math.floor((tGame.iMaxY-tGame.iMinY+1)/2)
    if (tGame.iMaxX-tGame.iMaxY) <= 5 then CShape.iR = math.ceil(CShape.iR/2) end

    CShape.iMaxFill = 0
    CShape.iYFill = {}

    CShape.iFillColor = CColors.GREEN
    CShape.iLavaColor = CColors.RED

    local tPixels = {}

    local function createPixel(iPaintX, iPaintY, iY, bEdge)
        if tFloor[iPaintX] and tFloor[iPaintX][iPaintY] and tFloor[iPaintX][iPaintY].iColor == CColors.NONE then
            tFloor[iPaintX][iPaintY].iColor = CColors.WHITE

            iPixel = (CShape.iYFill[iY] * CShape.iR) + iY + 1
            tPixels[iPixel] = {}
            tPixels[iPixel].iX = iPaintX
            tPixels[iPixel].iY = iPaintY
            tPixels[iPixel].bEdge = bEdge

            CShape.iMaxFill = CShape.iMaxFill + 1
            CShape.iYFill[iY] = CShape.iYFill[iY] + 1
        end
    end

    for iY = 0, CShape.iR do
        CShape.iYFill[iY] = 0

        local bEdge = iY <= 1 or iY >= CShape.iR

        local iX = 0
        local iD = -CShape.iR-1

        while iX <= iY do
            createPixel(CShape.iX + iX, CShape.iY + iY, iY, bEdge)
            createPixel(CShape.iX - iX, CShape.iY + iY, iY, bEdge)
            createPixel(CShape.iX + iX, CShape.iY - iY, iY, bEdge)
            createPixel(CShape.iX - iX, CShape.iY - iY, iY, bEdge)
            createPixel(CShape.iX + iY, CShape.iY + iX, iY, bEdge)
            createPixel(CShape.iX - iY, CShape.iY + iX, iY, bEdge)
            createPixel(CShape.iX + iY, CShape.iY - iX, iY, bEdge)
            createPixel(CShape.iX - iY, CShape.iY - iX, iY, bEdge)        

            iX = iX + 1
            if iD < 0 then
                iD = iD + 2 * iX + 1
            else
                iY = iY - 1
                iD = iD + 2 * (iX - iY) + 1
            end
        end
    end    

    CShape.iFill = math.floor(CShape.iMaxFill*0.1)
    CShape.iFadeTime = tConfig.FadeTime

    local iPixel = 0
    for iTempPixel = 1, #tPixels do
        if tPixels[iTempPixel] ~= nil then
            iPixel = iPixel + 1
            CShape.tShape[iPixel] = tPixels[iTempPixel]
        end
    end
end

CShape.DecreaseFill = function()
    CShape.iFill = CShape.iFill - 1
    tGameStats.Players[1].Score = CShape.iFill
    if CShape.iFill <= 0 then
        CGameMode.EndGame(false)
    end

    CShape.iFadeTime = tConfig.FadeTime    
end

CShape.Paint = function()
    for iPixel = 1, #CShape.tShape do
        if CShape.tShape[iPixel] and not tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].bAnimated then
            if iPixel <= CShape.iFill then
                tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].iColor = CShape.iFillColor
            
                if iPixel == CShape.iFill and CShape.iFadeTime < tConfig.Bright then
                    tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].iBright = tConfig.Bright - (tConfig.Bright - CShape.iFadeTime)
                else
                    tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].iBright = tConfig.Bright+1
                end
            elseif CShape.tShape[iPixel].bEdge then
                tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].iColor = CShape.iLavaColor
                tFloor[CShape.tShape[iPixel].iX][CShape.tShape[iPixel].iY].iBright = tConfig.Bright+1
            end    
        end
    end
end
--//

--objects
CObjects = {}
CObjects.tObjects = {}
CObjects.bClearing = false

CObjects.NewObject = function(iX, iY, iSizeX, iSizeY, iVelX, iVelY)
    local iObjectID = #CObjects.tObjects+1
    CObjects.tObjects[iObjectID] = {}
    CObjects.tObjects[iObjectID].iX = iX
    CObjects.tObjects[iObjectID].iY = iY
    CObjects.tObjects[iObjectID].iSizeX = iSizeX
    CObjects.tObjects[iObjectID].iSizeY = iSizeY
    CObjects.tObjects[iObjectID].iVelX = iVelX
    CObjects.tObjects[iObjectID].iVelY = iVelY

    CObjects.tObjects[iObjectID].iBright = 0
    CObjects.tObjects[iObjectID].iTargetBright = tConfig.Bright-1
end

CObjects.Tick = function()
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] then
            if CObjects.tObjects[iObjectID].iVelX ~= 0 then
                CObjects.tObjects[iObjectID].iX = CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iVelX

                if CObjects.tObjects[iObjectID].iX <= 1  then
                    CObjects.tObjects[iObjectID].iVelX = 1
                elseif (CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iSizeX-1 >= tGame.Cols) then
                    CObjects.tObjects[iObjectID].iVelX = -1
                end
            elseif CObjects.tObjects[iObjectID].iVelY ~= 0 then
                CObjects.tObjects[iObjectID].iY = CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iVelY

                if CObjects.tObjects[iObjectID].iY <= 1  then
                    CObjects.tObjects[iObjectID].iVelY = 1
                elseif (CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iSizeY-1 >= tGame.Rows) then
                    CObjects.tObjects[iObjectID].iVelY = -1
                end
            end

            if not CObjects.bClearing and CObjects.tObjects[iObjectID].iBright < CObjects.tObjects[iObjectID].iTargetBright then
                CObjects.tObjects[iObjectID].iBright = CObjects.tObjects[iObjectID].iBright + 1
            end
        end
    end
end

CObjects.Paint = function()
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] then
            for iX = CObjects.tObjects[iObjectID].iX, CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iSizeX-1 do
                for iY = CObjects.tObjects[iObjectID].iY, CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iSizeY-1 do
                    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bAnimated then
                        tFloor[iX][iY].iColor = CColors.RED
                        tFloor[iX][iY].iBright = CObjects.tObjects[iObjectID].iBright

                        if CObjects.tObjects[iObjectID].iBright == CObjects.tObjects[iObjectID].iTargetBright and tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                            CGameMode.PlayerStepOnLava(iX,iY)
                        end
                    end
                end
            end
        end
    end
end

CObjects.Clear = function(fCallback)
    if #CObjects.tObjects == 0 then
        fCallback()
        return;
    end

    CObjects.bClearing = true

    AL.NewTimer(tConfig.ObjectsTickRate, function()
        if iGameState ~= GAMESTATE_GAME then return end

        local bDone = false

        for iObjectID = 1, #CObjects.tObjects do
            if CObjects.tObjects[iObjectID] then
                CObjects.tObjects[iObjectID].iBright = CObjects.tObjects[iObjectID].iBright-1
                if CObjects.tObjects[iObjectID].iBright <= 0 then 
                    bDone = true 
                end
            end
        end

        if not bDone then
            return tConfig.ObjectsTickRate
        else
            CObjects.tObjects = {}
            CObjects.bClearing = false
            fCallback()
        end
    end)
end
--//

--coins
CCoins = {}
CCoins.tCoins = AL.Stack()

CCoins.Paint = function()
    for iCoin = 1, CCoins.tCoins.Size() do
        local tCoin = CCoins.tCoins.Pop()
        local bClick = false

        if tCoin.bButton then
            tButtons[tCoin.iButton].iColor = CColors.BLUE
            tButtons[tCoin.iButton].iBright = tConfig.Bright
            tButtons[tCoin.iButton].iCoin = iCoin

            bClick = tButtons[tCoin.iButton].bClick or tButtons[tCoin.iButton].bDefect
        else
            tFloor[tCoin.iX][tCoin.iY].iColor = CColors.BLUE
            tFloor[tCoin.iX][tCoin.iY].iBright = tConfig.Bright
            tFloor[tCoin.iX][tCoin.iY].iCoin = iCoin

            bClick = tFloor[tCoin.iX][tCoin.iY].bClick or tFloor[tCoin.iX][tCoin.iY].bDefect
        end

        if bClick then
            CCoins.Collected()
        else
            CCoins.tCoins.Push(tCoin)
        end
    end
end

CCoins.NewRandomCoin = function()
    local tCoin = {}

    if not tGame.NoButtonsGame and math.random(1,10) == 5 then
        tCoin.bButton = true
        repeat
            tCoin.iButton = tGame.Buttons[math.random(1, #tGame.Buttons)]
        until tButtons[tCoin.iButton].iCoin <= 0 and not tButtons[tCoin.iButton].bDefect
        tButtons[tCoin.iButton].iCoin = 1
    else
        repeat
            tCoin.iX = math.random(tGame.iMinX, tGame.iMaxX)    
            tCoin.iY = math.random(tGame.iMinY, tGame.iMaxY)    
        until (tCoin.iX < CShape.iX - CShape.iR or tCoin.iX > CShape.iX + CShape.iR) and tFloor[tCoin.iX][tCoin.iY].iCoin <= 0 and not tFloor[tCoin.iX][tCoin.iY].bDefect
        tFloor[tCoin.iX][tCoin.iY].iCoin = 1
    end

    CCoins.tCoins.Push(tCoin)
end

CCoins.Collected = function()
    CShape.iFill = CShape.iFill + tConfig.CoinReward

    CShape.iFadeTime = tConfig.FadeTime
    tGameStats.StageLeftDuration = CShape.iFadeTime

    tGameStats.Players[1].Score = CShape.iFill

    if CShape.iFill >= CShape.iMaxFill then
        CGameMode.EndGame(true)
    else
        CAudio.PlaySystemAsync(CAudio.CLICK)
        CCoins.NewRandomCoin()

        if CShape.iFill % 5 == 0 then
            CGameMode.SpawnNewRandomObjects()
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
            end
            tFloor[iX][iY].iCoin = -1
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

        if iGameState == GAMESTATE_GAME and click.Click and not tFloor[click.X][click.Y].bDefect and not tFloor[click.X][click.Y].bAnimated and tFloor[click.X][click.Y].iColor == CColors.RED and tFloor[click.X][click.Y].iBright >= tConfig.Bright-2 then
            CGameMode.PlayerStepOnLava(click.X, click.Y)
        end
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