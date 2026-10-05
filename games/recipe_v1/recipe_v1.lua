--[[
    Название: Рецепт
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
    Scoreboard = 
    {
        GridCols = 4,
        GridRows = 2,
        HeaderWidget = {},
        BottomWidget = {Text = "", Icon = "timer"},
        GameStatsWidgets = {},
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
    tGame.CenterY = math.ceil((tGame.iMaxY-tGame.iMinY+1)/2)

    tGame.StartPositions = {}
    tGame.StartPositionSizeX = #CGameMode.tColors
    tGame.StartPositionSizeY = 5

    local iStartX = math.floor((tGame.Cols - (tGame.iMaxX-tGame.iMinX))/2) + tGame.iMinX
    local iX = iStartX
    local iY = tGame.iMinY

    for iPlayerID = 1, #CGameMode.tPlayerColors do
        tGame.StartPositions[iPlayerID] = {}
        tGame.StartPositions[iPlayerID].X = iX
        tGame.StartPositions[iPlayerID].Y = iY

        iX = iX + tGame.StartPositionSizeX + 1
        if iX + tGame.StartPositionSizeX > tGame.iMaxX then
            iX = iStartX
            iY = iY + tGame.StartPositionSizeY + 2
            if iY + tGame.StartPositionSizeY > tGame.iMaxY then break; end
        end
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

    local iPlayersReady = 0

    for iPlayerID = 1, #tGame.StartPositions do
        local iBright = CColors.BRIGHT15
        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionSizeX, tGame.StartPositionSizeY) or CGameMode.bCountDownStarted and tPlayerInGame[iPlayerID] then
            iBright = tConfig.Bright
            iPlayersReady = iPlayersReady + 1
            tPlayerInGame[iPlayerID] = true
        else
            tPlayerInGame[iPlayerID] = false
        end

        CPaint.PlayerZone(iPlayerID, iBright)
    end

    CGameMode.iPlayerCount = iPlayersReady
    tGameResults.PlayersCount = iPlayersReady

    if not CGameMode.bCountDownStarted then
        if iPlayersReady > 1 and CGameMode.bCanAutoStart then
            CGameMode.StartCountDown(9)
        end
    end    

    CGameMode.UpdatePlayersProgress()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CPaint.PlayerZones()
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
CGameMode.bRoundOn = false

CGameMode.tColors = {}
CGameMode.tColors[1] = CColors.RED
CGameMode.tColors[2] = CColors.GREEN
CGameMode.tColors[3] = CColors.YELLOW
CGameMode.tColors[4] = CColors.BLUE
CGameMode.tColors[5] = CColors.MAGENTA
CGameMode.tColors[6] = CColors.CYAN
CGameMode.tColors[7] = CColors.WHITE

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.BLUE
CGameMode.tPlayerColors[2] = CColors.MAGENTA
CGameMode.tPlayerColors[3] = CColors.CYAN
CGameMode.tPlayerColors[4] = CColors.YELLOW
CGameMode.tPlayerColors[5] = CColors.GREEN
CGameMode.tPlayerColors[6] = CColors.RED
CGameMode.tPlayerColors[7] = CColors.WHITE

CGameMode.tPointRewardForPosition = {}
CGameMode.tPointRewardForPosition[1] = 50
CGameMode.tPointRewardForPosition[2] = 30
CGameMode.tPointRewardForPosition[3] = 20
CGameMode.tPointRewardForPosition[4] = 15
CGameMode.tPointRewardForPosition[5] = 10
CGameMode.tPointRewardForPosition[6] = 8
CGameMode.tPointRewardForPosition[7] = 6

CGameMode.tRecipe = {}

CGameMode.iPlayerCount = 0
CGameMode.tPlayerPosition = {}
CGameMode.tPlayerScore = {}
CGameMode.iPointsPlayerCount = 0
CGameMode.iFinishedPlayerCount = 0
CGameMode.tFinishedPlayer = {}
CGameMode.tPlayerRecipeProgress = {}
CGameMode.tPlayerClickedColor = {}

CGameMode.InitGameMode = function()
    tGameStats.StageNum = 0
    tGameStats.TotalStages = tConfig.RoundCount
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then
        CAudio.PlayVoicesSync("choose-color.mp3")
        --voice gamename rules
        AL.NewTimer(1000, function()
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
            tGameStats.Scoreboard.BottomWidget.Text = ""
            CGameMode.StartGame()
            
            return nil
        else
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    iGameState = GAMESTATE_GAME
    CAudio.PlayRandomBackground()
    CGameMode.CountDownNextRound()
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local bVictory = false
    local iWinnerID = -1
    local iMaxScore = 0
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] and (CGameMode.tPlayerScore[iPlayerID] or 0) > iMaxScore then
            bVictory = true
            iWinnerID = iPlayerID
            iMaxScore = CGameMode.tPlayerScore[iPlayerID]
        end
    end
    tGameResults.Won = bVictory

    if bVictory then
        CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[iWinnerID])
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        SetGlobalColorBright(CGameMode.tPlayerColors[iWinnerID], tConfig.Bright)
        tGameResults.Color = CGameMode.tPlayerColors[iWinnerID]
    else
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
        tGameResults.Color = CColors.RED
    end

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end) 
end

CGameMode.CountDownNextRound = function()
    tGameStats.StageLeftDuration = 6
    AL.NewTimer(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        if tGameStats.StageLeftDuration == 0 then
            tGameStats.Scoreboard.BottomWidget.Text = ""
            CGameMode.StartRound()
        else
            tGameStats.Scoreboard.BottomWidget.Text = tGameStats.StageLeftDuration
            CAudio.ResetSync()
            CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            CGameMode.UpdatePlayersProgress()
            return 1000;
        end
    end)
end

CGameMode.StartRound = function()
    CGameMode.tPlayerPosition = {}
    CGameMode.iPointsPlayerCount = 0
    CGameMode.iFinishedPlayerCount = 0
    CGameMode.tFinishedPlayer = {}
    CGameMode.tPlayerRecipeProgress = {}
    CGameMode.tPlayerClickedColor = {}

    tGameStats.StageNum = tGameStats.StageNum + 1
    CGameMode.tRecipe = CHelp.DeepCopy(CGameMode.tColors)
    CGameMode.tRecipe = ShuffleTable(CGameMode.tRecipe)
    CGameMode.bRoundOn = true

    CGameMode.UpdatePlayersProgress()
end

CGameMode.EndRound = function()
    CGameMode.bRoundOn = false

    if tGameStats.StageNum == tGameStats.TotalStages then
        CGameMode.EndGame()
    else
        CGameMode.CountDownNextRound()
    end
end

CGameMode.UpdatePlayersProgress = function()
    tGameStats.Scoreboard.GameStatsWidgets = {}
    tGameStats.Scoreboard.GridCols = tConfig.RecipeLength
    tGameStats.Scoreboard.GridRows = 3

    tGameStats.Scoreboard.GameStatsWidgets[1] =             
    {
        Type = "image_text",
        Position = {Col = 0, ColSpan = tGameStats.Scoreboard.GridCols, Row = 0, RowSpan = 1},
        Icon = "stage",
        TextPosition = "left",
        Text = tGameStats.StageNum.."/"..tGameStats.TotalStages
    }    

    if #CGameMode.tRecipe > 0 then
        tGameStats.Scoreboard.GameStatsWidgets[2] =             
        {
            Type = "image_text",
            Position = {Col = 0, ColSpan = tGameStats.Scoreboard.GridCols, Row = 1, RowSpan = 1},
            Icon = "star",
            TextPosition = "left",
            Text = "Рецепт:"
        }            
        if tGame.Locale and tGame.Locale ~= "ru" then
            tGameStats.Scoreboard.GameStatsWidgets[2].Text = "Recipe:"
        end

        for iRecipeColor = 1, tConfig.RecipeLength do
            tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets+1] =             
            {
                Type = "progress_bar",
                Position = {Col = iRecipeColor-1, ColSpan = 1, Row = 3, RowSpan = 1},
                Value = 100,
                Label = "",
                Color = CGameMode.tRecipe[iRecipeColor]
            }
        end
    end

    local iTruePlayer = 0
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            iTruePlayer = iTruePlayer + 1
            tGameStats.Scoreboard.GridRows = tGameStats.Scoreboard.GridRows + 1
            tGameStats.Scoreboard.GameStatsWidgets[#tGameStats.Scoreboard.GameStatsWidgets+1] =             
            {
                Type = "progress_bar",
                Position = {Col = 0, ColSpan = tGameStats.Scoreboard.GridCols, Row = tGameStats.Scoreboard.GridRows-1, RowSpan = 1},
                Value = (CGameMode.tPlayerScore[iPlayerID] or 0)/tGameStats.TargetScore*100,
                Label = CGameMode.tPlayerScore[iPlayerID],
                Color = CGameMode.tPlayerColors[iPlayerID]
            }
        end
    end
end

CGameMode.PlayerClickColor = function(iPlayerID, iColor)
    if CGameMode.tPlayerClickedColor[iPlayerID] == nil then CGameMode.tPlayerClickedColor[iPlayerID] = {}; end

    if iGameState ~= GAMESTATE_GAME or not CGameMode.bRoundOn or CGameMode.tPlayerClickedColor[iPlayerID][iColor] or CGameMode.tFinishedPlayer[iPlayerID] ~= nil then return; end

    if CGameMode.tPlayerRecipeProgress[iPlayerID] == nil then CGameMode.tPlayerRecipeProgress[iPlayerID] = 1; end

    if iColor == CGameMode.tRecipe[CGameMode.tPlayerRecipeProgress[iPlayerID]] then
        CGameMode.tPlayerClickedColor[iPlayerID][iColor] = true

        if CGameMode.tPlayerRecipeProgress[iPlayerID] == tConfig.RecipeLength then
            CGameMode.tFinishedPlayer[iPlayerID] = true
            CGameMode.iFinishedPlayerCount = CGameMode.iFinishedPlayerCount + 1

            CGameMode.iPointsPlayerCount = CGameMode.iPointsPlayerCount + 1
            CGameMode.tPlayerPosition[iPlayerID] = CGameMode.iPointsPlayerCount
            CGameMode.tPlayerScore[iPlayerID] = (CGameMode.tPlayerScore[iPlayerID] or 0) + CGameMode.tPointRewardForPosition[CGameMode.iPointsPlayerCount]
            if CGameMode.tPlayerScore[iPlayerID] > tGameStats.TargetScore then tGameStats.TargetScore = CGameMode.tPlayerScore[iPlayerID]; end

            CAudio.PlaySystemAsync(CAudio.STAGE_DONE)
        else
            CGameMode.tPlayerRecipeProgress[iPlayerID] = CGameMode.tPlayerRecipeProgress[iPlayerID] + 1
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    else
        CGameMode.tFinishedPlayer[iPlayerID] = false
        CGameMode.iFinishedPlayerCount = CGameMode.iFinishedPlayerCount + 1
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
    end

    if CGameMode.iFinishedPlayerCount == CGameMode.iPlayerCount then
        CGameMode.EndRound()
    end

    CGameMode.UpdatePlayersProgress()
end
--//

--PAINt
CPaint = {}

CPaint.PlayerZones = function()
    for iPlayerID = 1, #CGameMode.tPlayerColors do
        if tGame.StartPositions[iPlayerID] and tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    local iColor = CGameMode.tPlayerColors[iPlayerID]

    if iGameState == GAMESTATE_GAME then
        if CGameMode.tFinishedPlayer[iPlayerID] ~= nil then
            if CGameMode.tFinishedPlayer[iPlayerID] == true then
                iColor = CColors.GREEN
            elseif CGameMode.tFinishedPlayer[iPlayerID] == false then
                iColor = CColors.RED
            end
        else
            iBright = iBright-2
        end
    end

    if CGameMode.tPlayerPosition[iPlayerID] ~= nil then
        local tLetter = tLoadedLetters[CGameMode.tPlayerPosition[iPlayerID]]

        if tGame.MirrorGameY then
            local iX = tGame.StartPositions[iPlayerID].X
            local iY = tGame.StartPositions[iPlayerID].Y-1

            for iLocalY = 1, tLetter.iSizeY do
                for iLocalX = 1, tLetter.iSizeX do
                    if tLetter.tPaint[iLocalY][iLocalX] == 1 then
                        if tFloor[iX+iLocalX] and tFloor[iX+iLocalX][iY+iLocalY] then
                            tFloor[iX+iLocalX][iY+iLocalY].iColor = iColor
                            tFloor[iX+iLocalX][iY+iLocalY].iBright = iBright
                        end
                    end
                end
            end
        else
            local iX = tGame.StartPositions[iPlayerID].X+1 + tLetter.iSizeX
            local iY = tGame.StartPositions[iPlayerID].Y + tLetter.iSizeY

            for iLocalY = 1, tLetter.iSizeY do
                for iLocalX = 1, tLetter.iSizeX do
                    if tLetter.tPaint[iLocalY][iLocalX] == 1 then
                        if tFloor[iX-iLocalX] and tFloor[iX-iLocalX][iY-iLocalY] then
                            tFloor[iX-iLocalX][iY-iLocalY].iColor = iColor
                            tFloor[iX-iLocalX][iY-iLocalY].iBright = iBright
                        end
                    end
                end
            end
        end
    else
        SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
            tGame.StartPositions[iPlayerID].Y, 
            tGame.StartPositionSizeX, 
            tGame.StartPositionSizeY, 
            iColor, 
            iBright)
    end

    if iGameState == GAMESTATE_GAME and CGameMode.tFinishedPlayer[iPlayerID] == nil then
        CPaint.PlayerZonePixels(iPlayerID, tConfig.Bright)
    end
end

CPaint.PlayerZonePixels = function(iPlayerID, iBright)
    local iStartY = tGame.StartPositions[iPlayerID].Y
    if not tGame.MirrorGameY then
        iStartY = iStartY + tGame.StartPositionSizeY-2
    end

    for iY = iStartY, iStartY+1 do
        for iColor = 1, #CGameMode.tColors do
            if iGameState == GAMESTATE_GAME then
                local iX = tGame.StartPositions[iPlayerID].X + iColor-1
                if (not CGameMode.tPlayerClickedColor[iPlayerID] or not CGameMode.tPlayerClickedColor[iPlayerID][CGameMode.tColors[iColor]]) and not tFloor[iX][iY].bDefect then
                    local iColorBright = iBright
                    tFloor[iX][iY].iColor = CGameMode.tColors[iColor]
                    tFloor[iX][iY].iBright = iColorBright
                    
                    if CGameMode.bRoundOn and tFloor[iX][iY].bClick then
                        CGameMode.PlayerClickColor(iPlayerID, CGameMode.tColors[iColor])
                    end
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

tLoadedLetters = {}

tLoadedLetters[1] =
{
    iSizeX = 3,
    iSizeY = 5,
    tPaint = {
        {0, 1, 0,},
        {1, 1, 0,},
        {0, 1, 0,},
        {0, 1, 0,},
        {1, 1, 1,}
    }
}

tLoadedLetters[2] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 1, 0, 0},
        {1, 1, 1, 1}
    }
}

tLoadedLetters[3] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 0, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[4] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 0, 1, 0},
        {0, 1, 1, 0},
        {1, 0, 1, 0},
        {1, 1, 1, 1},
        {0, 0, 1, 0}
    }
}

tLoadedLetters[5] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 1},
        {1, 1, 1, 0}
    }
}

tLoadedLetters[6] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[7] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {1, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0},
        {0, 0, 1, 0}
    }
}

tLoadedLetters[8] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 0}
    }
}

tLoadedLetters[9] =
{
    iSizeX = 4,
    iSizeY = 5,
    tPaint = {
        {0, 1, 1, 0},
        {1, 0, 0, 1},
        {0, 1, 1, 1},
        {0, 0, 0, 1},
        {0, 0, 1, 0}
    }
}