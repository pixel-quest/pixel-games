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
    ScoreboardVariant = 9,
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
    bAnimated = false
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

    for iPlayerID = 1, #tGame.StartPositions do
        tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
    end 

    CAudio.PlayVoicesSync("glassbridge/glassbridge_voice_guide.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("glassbridge/glassbridge_voice_guide.mp3"))*1000 + 2000, function()
        CGameMode.bCanStart = true
    end)
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

    if CGameMode.bCanStart and tGame.StartButtonFloorX then
        for iX = tGame.StartButtonFloorX, tGame.StartButtonFloorX + 1 do
            for iY = tGame.StartButtonFloorY, tGame.StartButtonFloorY + 2 do
                tFloor[iX][iY].iColor = CColors.BLUE
                tFloor[iX][iY].iBright = tConfig.Bright
                if tFloor[iX][iY].bClick then bAnyButtonClick = true; end
            end
        end
    end

    if bAnyButtonClick then
        if not CGameMode.bCountDownStarted then
            CAudio.PlaySyncFromScratch("")
            CGameMode.StartCountDown(5)
            SetAllButtonColorBright(CColors.NONE, tConfig.Bright)
        end
    else
        SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
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

CGameMode.bCanStart = false

CGameMode.iTotalSquares = 0
CGameMode.iClaimedSquares = 0

CGameMode.bAntiSpamSwitch = false

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
    CAudio.PlayMusic("glassbridge/glassbridge_music_background.mp3")
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
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].iTouch = 0
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad = false
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].bClaimed = false
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].iRealX = (tGame.SquareRows[iRowId].X + (iSquareX-1)*3)
                CGameMode.tSquares[iRowId][iSquareX][iSquareY].iRealY = (tGame.SquareRows[iRowId].Y + (iSquareY-1)*3)

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
    if not bTouch then return; end

    if tSquareObject.bBad then
        if not tSquareObject.bClaimed then
            tSquareObject.bClaimed = true
            CAudio.PlaySystemAsync("glassbridge/glassbridge_effect_glassbreak.mp3")
        end
    else
        CGameMode.PlaySoundAntiSpam("glassbridge/glassbridge_effect_glassstep.mp3")

        if not tSquareObject.bClaimed then
            tSquareObject.bClaimed = true
            CGameMode.iClaimedSquares = CGameMode.iClaimedSquares + 1
            CAudio.PlaySystemSync(CAudio.CLICK)
        end
    end
end

CGameMode.IsSquareTouched = function(tSquareObject)
    for iX = tSquareObject.iRealX, tSquareObject.iRealX + 1 do
        for iY = tSquareObject.iRealY, tSquareObject.iRealY + 1 do
            if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                return true
            end
        end
    end

    return false
end

CGameMode.EndGame = function(bVictory)
    CAudio.StopBackground()

    CAudio.PlayVoicesSyncFromScratch("glassbridge/glassbridge_voice_endgame.mp3")

    tGameResults.Color = CColors.MAGENTA

    for iRowId = 1, #tGame.SquareRows do
        for iSquareX = 1, tGame.SquareRowLength do
            for iSquareY = 1, tGame.SquareRowHeight do
                if CGameMode.tSquares[iRowId][iSquareX][iSquareY] then
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad = true
                    CGameMode.tSquares[iRowId][iSquareX][iSquareY].iTouch = 4
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

CGameMode.PlaySoundAntiSpam = function(sSoundName)
    if CGameMode.bAntiSpamSwitch then return; end

    CAudio.PlaySystemAsync(sSoundName)

    CGameMode.bAntiSpamSwitch = true
    AL.NewTimer(250, function()
        CGameMode.bAntiSpamSwitch = false
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

                    if not tGame.StartPositions[iPlayerId].PreStartDraw then 
                        if CGameMode.iClaimedSquares < CGameMode.iTotalSquares/2 then
                            tFloor[iX][iY].iBright = tConfig.Bright-3
                        elseif tConfig.EndGameAfterFinish and iGameState == GAMESTATE_GAME and tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                            CGameMode.EndGame(true)
                        end
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
                if CGameMode.iClaimedSquares >= tGame.SquareRowLength then
                    tFloor[iX][iY].iBright = tConfig.Bright
                else
                    tFloor[iX][iY].iBright = tConfig.Bright-3
                end            
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
                local bTouch = CGameMode.IsSquareTouched(CGameMode.tSquares[iRowId][iSquareX][iSquareY])

                if CGameMode.tSquares[iRowId][iSquareX][iSquareY].bBad then
                    if CGameMode.tSquares[iRowId][iSquareX][iSquareY].bClaimed and (not tConfig.HardMode or bTouch or iGameState > GAMESTATE_GAME) then
                        iColor = CColors.RED
                    end
                else
                    if bTouch then
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

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(60, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = CColors.RED
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = 2
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
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

            if CEffect.bEffectOn == false then
                tFloor[iX][iY].iCoinId = 0
            end
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
        
        if click.Click then
            tFloor[click.X][click.Y].bClick = true
            tFloor[click.X][click.Y].bHold = false
        elseif not tFloor[click.X][click.Y].bHold then
            AL.NewTimer(500, function()
                if not tFloor[click.X][click.Y].bHold then
                    tFloor[click.X][click.Y].bHold = true
                    AL.NewTimer(750, function()
                        if tFloor[click.X][click.Y].bHold then
                            tFloor[click.X][click.Y].bClick = false
                        end
                    end)
                end
            end)
        end
        tFloor[click.X][click.Y].iWeight = click.Weight       

        if not tFloor[click.X][click.Y].bDefect and iGameState == GAMESTATE_GAME then
            if tFloor[click.X][click.Y].tSquareObject then
                CGameMode.PlayerTouchSquare(tFloor[click.X][click.Y].tSquareObject, click.Click)
            elseif click.Click and tFloor[click.X][click.Y].iColor == CColors.WHITE then
                CPaint.AnimatePixelFlicker(click.X, click.Y, 3, CColors.WHITE)
                CGameMode.PlaySoundAntiSpam(CAudio.MISCLICK)
            end
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