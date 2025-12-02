--[[
    Название: Поймай Рисунок
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Ловить пиксели правильного цвета чтобы собрать рисунок
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
    CPicture.Paint()

    if CGameMode.bCanAutoStart and not CGameMode.bCountDownStarted then
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CPicture.Paint()
    CCoins.Paint()
end

function PostGameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)   
    CPicture.Paint()
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
    CPicture.tColors = {CColors.RED, CColors.BLUE, CColors.YELLOW, CColors.MAGENTA}
    CPicture.PAINTED_COLOR = CColors.GREEN

    CPicture.Load(tConfig.PictureName)
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("catch-pixel/catch-rules.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("catch-pixel/catch-rules.mp3")*1000 + 1000, function()
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
    iGameState = GAMESTATE_GAME

    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    AL.NewTimer(300, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
    
        CCoins.Tick()

        return 300
    end)

    if tConfig.TimeLimit > 0 then
        tGameStats.StageLeftDuration = tConfig.TimeLimit
        tGameStats.StageTotalDuration = tConfig.TimeLimit

        AL.NewTimer(1000, function()
            if iGameState ~= GAMESTATE_GAME then return nil; end

            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
            if tGameStats.StageLeftDuration == 0 then
                CAudio.PlayVoicesSync("notime.mp3")
                CGameMode.EndGame(false)
            end

            return 1000;
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
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)    
end
--//

--COINS
CCoins = {}
CCoins.tCoins = AL.Stack()

CCoins.Paint = function()
    for iCoinID = 1, CCoins.tCoins.Size() do
        local tCoin = CCoins.tCoins.Pop()
        local bAlive = true

        if tCoin.iY > 0 and tCoin.iY <= tGame.Rows then 
            tFloor[tCoin.iX][tCoin.iY].iColor = tCoin.iColor
            if tCoin.bTrueColor then
                tFloor[tCoin.iX][tCoin.iY].iColor = CPicture.PAINTED_COLOR
            end
            tFloor[tCoin.iX][tCoin.iY].iBright = tConfig.Bright

            if tFloor[tCoin.iX][tCoin.iY].bClick and not tFloor[tCoin.iX][tCoin.iY].bDefect then
                CCoins.CoinCollected(tCoin.bTrueColor, tCoin.iColor)
                bAlive = false
            end
        end

        if bAlive then
            CCoins.tCoins.Push(tCoin)
        end
    end
end

CCoins.Tick = function()
    for iX = 1, tGame.Cols do
        if iX < CPicture.iStartX or iX > CPicture.iStartX + CPicture.iSizeX then
            if math.random(1,6) == 3 then
                CCoins.NewCoin(iX, -5)
            end
        end
    end

    for iCoinID = 1, CCoins.tCoins.Size() do
        local tCoin = CCoins.tCoins.Pop()

        tCoin.iY = tCoin.iY + 1

        if tCoin.iY <= tGame.Rows then
            CCoins.tCoins.Push(tCoin)
        end
    end
end

CCoins.NewCoin = function(iX, iY)
    local tNewCoin = {}
    tNewCoin.iX = iX
    tNewCoin.iY = iY
    tNewCoin.bTrueColor = (math.random(1,3) == 2)
    tNewCoin.iColor = CPicture.GetRandomColor()

    CCoins.tCoins.Push(tNewCoin)
end

CCoins.CoinCollected = function(bTrueColor, iCoinColor)
    if iGameState ~= GAMESTATE_GAME then return; end

    if bTrueColor then
        CPicture.iPixelsPainted = CPicture.iPixelsPainted + 1
        tGameStats.Players[1].Score = CPicture.iPixelsPainted

        CPicture.tPicture[CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted+1].iX][CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted+1].iY].bPainted = true

        if CPicture.iPixelsPainted == #CPicture.tPixels then
            CGameMode.EndGame(true)
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    else
        if CPicture.iPixelsPainted > 0 then
            CPicture.iPixelsPainted = CPicture.iPixelsPainted - 1
            tGameStats.Players[1].Score = CPicture.iPixelsPainted
            
            CPicture.tPicture[CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted].iX][CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted].iY].bPainted = false
            CPicture.tPicture[CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted].iX][CPicture.tPixels[#CPicture.tPixels-CPicture.iPixelsPainted].iY].iColor = iCoinColor
        end

        CAudio.PlaySystemAsync(CAudio.MISCLICK)
    end
end
--//

--PICTURE
CPicture = {}
CPicture.tPicture = {}
CPicture.tPixels = {}
CPicture.tColors = {}

CPicture.PAINTED_COLOR = 0

CPicture.iStartX = 0
CPicture.iStartY = 0
CPicture.iSizeX = 0

CPicture.iPixelsPainted = 0

CPicture.Paint = function()
    for iPixelID = 1, #CPicture.tPixels do
        local iX = CPicture.tPixels[iPixelID].iX
        local iY = CPicture.tPixels[iPixelID].iY

        local tPixel = CPicture.tPicture[iX][iY]
        if tPixel.bPaintable then
            local iColor = CPicture.PAINTED_COLOR
            if not tPixel.bPainted then
                iColor = tPixel.iColor
            end

            tFloor[CPicture.iStartX+iX][CPicture.iStartY+iY].iColor = iColor
            tFloor[CPicture.iStartX+iX][CPicture.iStartY+iY].iBright = tConfig.Bright+1
        end
    end
end

CPicture.Load = function(sPresetName)
    CPicture.tPicture = {}

    for iY = 1, #CPicture.tPresets[sPresetName] do
        for iX = 1, #CPicture.tPresets[sPresetName][iY] do
            if not CPicture.tPicture[iX] then CPicture.tPicture[iX] = {} end

            CPicture.tPicture[iX][iY] = {}
            CPicture.tPicture[iX][iY].bPaintable = (CPicture.tPresets[sPresetName][iY][iX] == 1)
            CPicture.tPicture[iX][iY].bPainted = false
            CPicture.tPicture[iX][iY].iColor = CPicture.GetRandomColor()
            
            if CPicture.tPicture[iX][iY].bPaintable then
                CPicture.tPicture[iX][iY].iPixelID = #CPicture.tPixels+1
                
                CPicture.tPixels[CPicture.tPicture[iX][iY].iPixelID] = {}
                CPicture.tPixels[CPicture.tPicture[iX][iY].iPixelID].iX = iX
                CPicture.tPixels[CPicture.tPicture[iX][iY].iPixelID].iY = iY
            end
        end
    end

    CPicture.iSizeX = #CPicture.tPicture
    local iSizeY = #CPicture.tPicture[1]

    tGameStats.TargetScore = #CPicture.tPixels

    CPicture.iStartX = tGame.CenterX - math.ceil(CPicture.iSizeX/2)
    CPicture.iStartY = tGame.CenterY - math.ceil(iSizeY/2)
end

CPicture.GetRandomColor = function()
    return CPicture.tColors[math.random(1,#CPicture.tColors)]
end

CPicture.tPresets = {}
CPicture.tPresets["elka"] = 
{
    {0,0,0,0,0,1,1,0,0,0,0,0},
    {0,0,0,0,0,1,1,0,0,0,0,0},
    {0,0,0,0,1,1,1,1,0,0,0,0},
    {0,0,0,0,1,1,1,1,0,0,0,0},
    {0,0,0,1,1,1,1,1,1,0,0,0},
    {0,0,0,1,1,1,1,1,1,0,0,0},
    {0,0,1,1,1,1,1,1,1,1,0,0},
    {0,0,1,1,1,1,1,1,1,1,0,0},
    {0,1,1,1,1,1,1,1,1,1,1,0},
    {0,1,1,1,1,1,1,1,1,1,1,0},
    {1,1,1,1,1,1,1,1,1,1,1,1},
    {0,0,0,1,1,1,1,1,1,0,0,0},
    {0,0,0,1,1,1,1,1,1,0,0,0},
    {0,0,0,1,1,1,1,1,1,0,0,0},
}
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