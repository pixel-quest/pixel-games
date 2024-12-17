--[[
    Название: стеклянный мост
    Автор: Avondale, дискорд - avonda

    Описание механики: 
        Стеклянный мост из игры в кальмара.
        Игроки прыгают по стёклам, каждый прыжок выбор из двух стёкл - одно закалённое, второе обычное.
        Закалённое(зелёное) безопасно, обычное(красное) выбивает игрока из игры.

        Игрокам нужно дойти от маленькой зелёной зоны до большой зёленой, развернуться и до финальной жёлтой. 
        Жёлтая зона загорится только после того как будут выполнены условия для честного прохождения(на все зелёные плиты наступят хотябы один раз)

        Игроку для победы нужно обязательно пройти по всем зелёным плитам, срезать нельзя.

        После окончания времени(5 минут по стандартным настройкам) все оставшиеся стёкла разбиваются пулями(становятся красными) и все кто не дошёл до жёлтой зоны - проигрывают.

    Идеи по доработке: 

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
local bAnyButtonClick = false

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

    CAudio.PlaySync("glassbridge_voice_guide.mp3")
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
    SetAllFloorColorBright(CColors.WHITE, 1) -- красим всё поле в один цвет
    CPaint.PlayerZones()

    if bAnyButtonClick then
        if not CGameMode.bCountDownStarted then
            CAudio.PlaySyncFromScratch("")
            CGameMode.StartCountDown(5)
            SetAllButtonColorBright(CColors.NONE, tConfig.Bright)
        end
    else
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)
    end
end

function GameTick()
    SetAllFloorColorBright(CColors.WHITE, 2) -- красим всё поле в один цвет  
    CPaint.PlayerZones()
    CPaint.Squares()
    CPaint.Finish()
end

function PostGameTick()
    SetAllFloorColorBright(CColors.WHITE, 2) -- красим всё поле в один цвет  
    CPaint.PlayerZones()
    CPaint.Squares()
    CPaint.Finish()
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
    if iGameState == GAMESTATE_GAME then
        CGameMode.EndGame()
    end
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.bCountDownStarted = false
CGameMode.tSquares = {}
CGameMode.bVictory = false

CGameMode.iTotalSquares = 0
CGameMode.iClaimedSquares = 0

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
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
    CAudio.PlayBackground("glassbridge_music_background.mp3")
    iGameState = GAMESTATE_GAME
    CGameMode.LoadSquares()

    if tConfig.TimeLimit > 0 then
        tGameStats.StageLeftDuration = tConfig.TimeLimit
        AL.NewTimer(1000, function()
            if iGameState ~= GAMESTATE_GAME then return nil end

            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration <= 0 then
                CGameMode.EndGame()
                return nil
            end

            CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)

            return 1000
        end)
    end
end

CGameMode.LoadSquares = function()
    for iRowId = 1, #tGame.SquareRows do
        CGameMode.tSquares[iRowId] = {}
        for iSquareX = 1, tGame.SquareRowLength do
            CGameMode.tSquares[iRowId][iSquareX] = {}
            local bTaken = false
            for iSquareY = 1, tGame.SquareRowHeight do
                CGameMode.tSquares[iRowId][iSquareX][iSquareY] = {}
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].bTouch = false
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad = false
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].bClaimed = false

                CGameMode.iTotalSquares = CGameMode.iTotalSquares + 1

                if (not bTaken and math.random(1, 100) > 50) or (not bTaken and iSquareY == tGame.SquareRowHeight) then
                    bTaken = true
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad = true
                end
            end
        end
    end
end

CGameMode.PlayerTouchSquare = function(tSquareObject, bTouch)
    if not tSquareObject.bBad or bTouch then
        tSquareObject.bTouch = bTouch

        if tSquareObject.bBad and not tSquareObject.bClaimed then
            tSquareObject.bClaimed = true

            CAudio.PlayAsync("glassbridge_effect_glassbreak.mp3")

            --CAudio.StopBackground()
            --AL.NewTimer(4000, function()
            --    CAudio.PlayBackground("glassbridge_music_background.mp3")
            --end)
        elseif not tSquareObject.bBad then
            CAudio.PlayAsync("glassbridge_effect_glassstep.mp3")

            if not tSquareObject.bClaimed then
                tSquareObject.bClaimed = true
                CGameMode.iClaimedSquares = CGameMode.iClaimedSquares + 1
            end
        end
    end
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    CAudio.PlaySyncFromScratch("glassbridge_voice_endgame.mp3")

    tGameResults.Color = CColors.MAGENTA

    for iRowId = 1, #tGame.SquareRows do
        for iSquareX = 1, tGame.SquareRowLength do
            for iSquareY = 1, tGame.SquareRowHeight do
                if CGameMode.tSquares[iRowId][iSquareX][iSquareY] then
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad = true
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].bTouch = true
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].bClaimed = true
                end 
            end
        end
    end

    iGameState = GAMESTATE_POSTGAME

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end
--//

CPaint = {}

CPaint.PlayerZones = function()
    for iPlayerId = 1, #tGame.StartPositions do
        if iGameState >= GAMESTATE_GAME or tGame.StartPositions[iPlayerId].PreStartDraw then
            for iX = tGame.StartPositions[iPlayerId].X, tGame.StartPositions[iPlayerId].X + tGame.StartPositionSizeX-1 do
                for iY = tGame.StartPositions[iPlayerId].Y, tGame.StartPositions[iPlayerId].Y + tGame.StartPositionSizeY-1 do
                    tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerId].Color
                    tFloor[iX][iY].iBright = tConfig.Bright

                    if not tGame.StartPositions[iPlayerId].PreStartDraw and CGameMode.iClaimedSquares < CGameMode.iTotalSquares/2 then
                        tFloor[iX][iY].iBright = tConfig.Bright-3
                    end
                end
            end
        end
    end
end

CPaint.Finish = function()
    if iGameState == GAMESTATE_GAME then
        for iX = tGame.FinishX, tGame.FinishX+1 do
            for iY = 1, tGame.Rows do
                tFloor[iX][iY].iColor = CColors.GREEN
                tFloor[iX][iY].iBright = tConfig.Bright            
            end
        end
    end

    local iY = math.ceil(tGame.Rows/2)
    for iX = 1, tGame.Cols do
        if tFloor[iX][iY].iColor == CColors.WHITE then
            tFloor[iX][iY].iColor = CColors.RED
        end
    end
end

CPaint.Squares = function()
    for iRowId = 1, #tGame.SquareRows do
        local iX = tGame.SquareRows[iRowId].X
        for iSquareX = 1, tGame.SquareRowLength do
            local iY = tGame.SquareRows[iRowId].Y
            for iSquareY = 1, tGame.SquareRowHeight do
                local iColor = CColors.NONE
                local iBright = tConfig.Bright

                if CGameMode.tSquares[iRowId][iSquareX][iSquareY].bTouch then
                    if CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad then
                        iColor = CColors.RED
                    else
                        iColor = CColors.GREEN
                    end
                end

                SetRectColorBright(iX, iY, 1, 1, iColor, iBright, CGameMode.tSquares[iRowId][iSquareX][iSquareY])

                iY = iY + 3
            end

            iX = iX + 3
        end
    end
end

------------------------------AVONLIB
_G.AL = {}
local LOC = {}

--STACK
AL.Stack = function()
    local tStack = {}
    tStack.tTable = {}

    tStack.Push = function(item)
        table.insert(tStack.tTable, item)
    end

    tStack.Pop = function()
        return table.remove(tStack.tTable, 1)
    end

    tStack.Size = function()
        return #tStack.tTable
    end

    return tStack
end
--//

--TIMER
local tTimers = AL.Stack()

AL.NewTimer = function(iSetTime, fCallback)
    tTimers.Push({iTime = iSetTime, fCallback = fCallback})
end

AL.CountTimers = function(iTimePassed)
    for i = 1, tTimers.Size() do
        local tTimer = tTimers.Pop()

        tTimer.iTime = tTimer.iTime - iTimePassed

        if tTimer.iTime <= 0 then
            local iNewTime = tTimer.fCallback()
            if iNewTime then
                tTimer.iTime = tTimer.iTime + iNewTime
            else
                tTimer = nil
            end
        end

        if tTimer then
            tTimers.Push(tTimer)
        end
    end
end
--//

--RECT
function AL.RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end
--//
------------------------------------

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

function SetRectColorBright(iX, iY, iSizeX, iSizeY, iColor, iBright, tSquareObject)
    for i = iX, iX + iSizeX do
        for j = iY, iY + iSizeY do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright
                tFloor[i][j].tSquareObject = tSquareObject or nil
            end            
        end
    end
end

function SetAllFloorColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
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
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if not tFloor[click.X][click.Y].bDefect and iGameState == GAMESTATE_GAME and tFloor[click.X][click.Y].tSquareObject then
            CGameMode.PlayerTouchSquare(tFloor[click.X][click.Y].tSquareObject, click.Click)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
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