--[[
    Название: Час Пик
    Автор: Avondale, дискорд - avonda

    Чтобы начать игру надо встать на цвета и нажать кнопку

    Описание механики: 
        Передвигать машинки чтобы выбратся с парковки
    
        Два типа карт: на одних можно двигать машинки в любую сторону, на других только вперед назад

        Кто быстрее передвинул все нужные машинки тот и победил

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
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    bSelected = false,
    iMovePieceID = 0,
    iMoveX = 0,
    iMoveY = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}
local bAnyButtonClick = false
local bCountDownStarted = false

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

    CAudio.PlaySync("games/huarong.mp3")
    CAudio.PlaySync("voices/huarong-guide.mp3")
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright)

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then

            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or (bCountDownStarted and tPlayerInGame[iPos]) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = tConfig.Bright
                tPlayerInGame[iPos] = true
                iPlayersReady = iPlayersReady + 1
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if not bCountDownStarted and iPlayersReady > 0 and bAnyButtonClick then
        CGameMode.StartCountDown(5)
    end    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет    
    CPaint.PlayerZones()
    CPaint.Pieces()
end

function PostGameTick()
    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            local iColor = tFloor[iX][iY].iColor
            local iBright = tFloor[iX][iY].iBright
            if tFloor[iX][iY].bSelected then
                iColor = CColors.WHITE
                iBright = CColors.BRIGHT15
            end

            setPixel(iX , iY, iColor, iBright)
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
CGameMode.iWinnerID = -1
CGameMode.tFinishPosPlayerX = {}
CGameMode.tFinishPosPlayerY = {}

CGameMode.bOneAxisMoveMode = false
CGameMode.iOneAxisMoveModeScorableCount = 0

CGameMode.StartCountDown = function(iCountDownTime)
    bCountDownStarted = true
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
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
    iGameState = GAMESTATE_GAME

    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    
    CPieces.Init()
    CGameMode.LoadPiecesForPlayers(math.random(1, #tGame.Maps))
end

CGameMode.LoadPiecesForPlayers = function(iMapID)
    CGameMode.bOneAxisMoveMode = false
    CGameMode.iOneAxisMoveModeScorableCount = 0

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.LoadPiecesForPlayer(iPlayerID, iMapID)
        end
    end

    tGameStats.TargetScore = #tGame.Maps[iMapID]
    if CGameMode.bOneAxisMoveMode then
        tGameStats.TargetScore = CGameMode.iOneAxisMoveModeScorableCount 
    end
end

CGameMode.LoadPiecesForPlayer = function(iPlayerID, iMapID)
    CGameMode.iOneAxisMoveModeScorableCount = 0 -- костыль :)

    CGameMode.tFinishPosPlayerX[iPlayerID] = {}
    CGameMode.tFinishPosPlayerX[iPlayerID].iX = tGame.StartPositions[iPlayerID].X+math.floor(tGame.StartPositionSizeX/2)
    CGameMode.tFinishPosPlayerX[iPlayerID].iY = tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY

    CGameMode.tFinishPosPlayerY[iPlayerID] = {}
    CGameMode.tFinishPosPlayerY[iPlayerID].iX = tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX
    CGameMode.tFinishPosPlayerY[iPlayerID].iY = tGame.StartPositions[iPlayerID].Y+math.floor(tGame.StartPositionSizeY/2)  

    for i = 1, #tGame.Maps[iMapID] do
        CPieces.NewPiece(
            iPlayerID,
            tGame.StartPositions[iPlayerID].X-1+tGame.Maps[iMapID][i].X, 
            tGame.StartPositions[iPlayerID].Y-1+tGame.Maps[iMapID][i].Y, 
            tGame.Maps[iMapID][i].SizeX, 
            tGame.Maps[iMapID][i].SizeY,
            tGame.Maps[iMapID][i].Color)

        if tGame.Maps[iMapID][i].Scorable then
            CGameMode.bOneAxisMoveMode = true
            CGameMode.iOneAxisMoveModeScorableCount = CGameMode.iOneAxisMoveModeScorableCount + 1 
        end
    end
end

CGameMode.IsPointInBounds = function(iPlayerID, iX, iY)
    return (iX >= tGame.StartPositions[iPlayerID].X and iX < tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX) 
        and (iY >= tGame.StartPositions[iPlayerID].Y and iY < tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY)
        or (iX == CGameMode.tFinishPosPlayerX[iPlayerID].iX and iY == CGameMode.tFinishPosPlayerX[iPlayerID].iY)
        or (iX == CGameMode.tFinishPosPlayerY[iPlayerID].iX and iY == CGameMode.tFinishPosPlayerY[iPlayerID].iY)
end

CGameMode.EndGame = function(iPlayerID)
    CGameMode.iWinnerID = iPlayerID

    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)     
end
--//

--PIECES
CPieces = {}
CPieces.tPieces = {}
CPieces.tBlocked = {}
CPieces.tPlayerSelectedPiece = {}

CPieces.Init = function()
    for iX = 1, tGame.Cols do
        CPieces.tBlocked[iX] = {}
        for iY = 1, tGame.Rows do
            CPieces.tBlocked[iX][iY] = {}
            CPieces.tBlocked[iX][iY].bBlocked = false
            CPieces.tBlocked[iX][iY].iPieceID = 0
        end
    end
end

CPieces.NewPiece = function(iPlayerID, iX, iY, iSizeX, iSizeY, iColor)
    local iPieceID = #CPieces.tPieces+1
    CPieces.tPieces[iPieceID] = {}
    CPieces.tPieces[iPieceID].iPlayerID = iPlayerID
    CPieces.tPieces[iPieceID].iX = iX
    CPieces.tPieces[iPieceID].iY = iY
    CPieces.tPieces[iPieceID].iSizeX = iSizeX
    CPieces.tPieces[iPieceID].iSizeY = iSizeY
    CPieces.tPieces[iPieceID].iColor = iColor --CPieces.RandomColor()
    CPieces.tPieces[iPieceID].bSelected = false

    CPieces.PieceBlock(iPieceID, true)
end

--[[
CPieces.PiecePrevColor = math.random(1,7)
CPieces.RandomColor = function()
    local iColor = CPieces.PiecePrevColor+math.random(1,3)
    if iColor > 7 then iColor = 1 + iColor-7 end
    
    return iColor
end
]]

CPieces.PieceBlock = function(iPieceID, bBlock)
    for iX = CPieces.tPieces[iPieceID].iX, CPieces.tPieces[iPieceID].iX + CPieces.tPieces[iPieceID].iSizeX-1 do
        for iY = CPieces.tPieces[iPieceID].iY, CPieces.tPieces[iPieceID].iY + CPieces.tPieces[iPieceID].iSizeY-1 do
            CPieces.tBlocked[iX][iY].bBlocked = bBlock
            CPieces.tBlocked[iX][iY].iPieceID = iPieceID
        end
    end
end

CPieces.PlayerSelectPiece = function(iPieceID)
    local iPlayerID = CPieces.tPieces[iPieceID].iPlayerID

    CPieces.ClearHighlightedMoves(iPlayerID)

    if CPieces.SelectValidMovesForPiece(iPieceID, true) > 0 then
        if CPieces.tPlayerSelectedPiece[iPlayerID] ~= nil then
            CPieces.SelectValidMovesForPiece(CPieces.tPlayerSelectedPiece[iPlayerID], false)
            CPieces.tPieces[CPieces.tPlayerSelectedPiece[iPlayerID]].bSelected = false
            CPieces.tPlayerSelectedPiece[iPlayerID] = nil

            CPieces.SelectValidMovesForPiece(iPieceID, true) 
        end

        CPieces.tPlayerSelectedPiece[iPlayerID] = iPieceID
        CPieces.tPieces[iPieceID].bSelected = true
    end
end

CPieces.SelectValidMovesForPiece = function(iPieceID, bSelect)
    local iMovesCount = 0
    local tXYi = {}

    if CGameMode.bOneAxisMoveMode then
        if CPieces.tPieces[iPieceID].iSizeX >= CPieces.tPieces[iPieceID].iSizeY then
            tXYi = 
            {
                {1,0},
                {-1,0},
            }
        else
            tXYi = 
            {
                {0,1},
                {0,-1},
            }
        end 
    else
        tXYi = 
            {
                {1,0},
                {-1,0},
                {0,1},
                {0,-1},
            }
    end
    
    for i = 1, #tXYi do
        local iMoveX = CPieces.tPieces[iPieceID].iX+tXYi[i][1]
        local iMoveY = CPieces.tPieces[iPieceID].iY+tXYi[i][2]

        if CPieces.PieceCanMove(iPieceID, iMoveX, iMoveY) then
            iMovesCount = iMovesCount + 1
            CPieces.HighlightValidMove(iPieceID, iMoveX, iMoveY, true)
        end
    end

    CLog.print(iMovesCount.." valid moves!")

    return iMovesCount
end

CPieces.HighlightValidMove = function(iPieceID, iStartX, iStartY, bHighlight)
    for iX = iStartX, iStartX + CPieces.tPieces[iPieceID].iSizeX-1 do
        for iY = iStartY, iStartY + CPieces.tPieces[iPieceID].iSizeY-1 do
            if not CPieces.tBlocked[iX][iY].bBlocked then
                tFloor[iX][iY].bSelected = bHighlight
                tFloor[iX][iY].iMovePieceID = iPieceID
                tFloor[iX][iY].iMoveX = iStartX
                tFloor[iX][iY].iMoveY = iStartY
            end
        end
    end  
end

CPieces.PlayerSelectHighlightedMove = function(iPieceID, iMoveX, iMoveY)
    CPieces.ClearHighlightedMoves(CPieces.tPieces[iPieceID].iPlayerID)

    if CPieces.PieceCanMove(iPieceID, iMoveX, iMoveY) then
        CPieces.PieceMove(iPieceID, iMoveX, iMoveY)
    end
end

CPieces.PieceCanMove = function(iPieceID, iStartX, iStartY)
    for iX = iStartX, iStartX + CPieces.tPieces[iPieceID].iSizeX-1 do
        for iY = iStartY, iStartY + CPieces.tPieces[iPieceID].iSizeY-1 do
            if not CGameMode.IsPointInBounds(CPieces.tPieces[iPieceID].iPlayerID, iX, iY) then return false end
            if CPieces.tBlocked[iX][iY].bBlocked and CPieces.tBlocked[iX][iY].iPieceID ~= iPieceID then return false end
        end
    end  

    return true
end

CPieces.PieceMove = function(iPieceID, iX, iY)
    CPieces.PieceBlock(iPieceID, false)

    CPieces.tPieces[iPieceID].iX = iX
    CPieces.tPieces[iPieceID].iY = iY

    CPieces.PieceBlock(iPieceID, true)

    local iPlayerID = CPieces.tPieces[iPieceID].iPlayerID
    for iFinishCheckX = iX, iX + CPieces.tPieces[iPieceID].iSizeX-1 do
        for iFinishCheckY = iY, iY + CPieces.tPieces[iPieceID].iSizeY-1 do 
            if CGameMode.tFinishPosPlayerX[iPlayerID].iX == iFinishCheckX and CGameMode.tFinishPosPlayerX[iPlayerID].iY == iFinishCheckY 
                or CGameMode.tFinishPosPlayerY[iPlayerID].iX == iFinishCheckX and CGameMode.tFinishPosPlayerY[iPlayerID].iY == iFinishCheckY  then
                CPieces.PieceFinsh(iPieceID)
            end
        end
    end
end

CPieces.PieceFinsh = function(iPieceID)
    local iPlayerID = CPieces.tPieces[iPieceID].iPlayerID

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1
    if tGameStats.Players[iPlayerID].Score == tGameStats.TargetScore then
        CGameMode.EndGame(iPlayerID)
    end

    CPieces.PieceBlock(iPieceID, false)
    CPieces.tPieces[iPieceID] = nil
end

CPieces.ClearHighlightedMoves = function(iPlayerID)
    if CPieces.tPlayerSelectedPiece[iPlayerID] ~= nil then
        CPieces.tPieces[CPieces.tPlayerSelectedPiece[iPlayerID]].bSelected = false
        CPieces.tPlayerSelectedPiece[iPlayerID] = nil
    end

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY do
            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].bSelected = false
                tFloor[iX][iY].iMovePieceID = 0
                tFloor[iX][iY].iMoveX = 0
                tFloor[iX][iY].iMoveY = 0
            end
        end
    end
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.Pieces = function()
    for iPieceID = 1, #CPieces.tPieces do
        if CPieces.tPieces[iPieceID] and CPieces.tPieces[iPieceID].iX ~= 0 then
            local iBright = tConfig.Bright
            if CPieces.tPieces[iPieceID].bSelected then iBright = iBright + 2 end

            SetRectColorBright(CPieces.tPieces[iPieceID].iX, CPieces.tPieces[iPieceID].iY, 
                CPieces.tPieces[iPieceID].iSizeX-1, CPieces.tPieces[iPieceID].iSizeY-1, 
                CPieces.tPieces[iPieceID].iColor, iBright)
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    if iGameState < GAMESTATE_GAME then
        SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
            tGame.StartPositions[iPlayerID].Y, 
            tGame.StartPositionSizeX-1, 
            tGame.StartPositionSizeY-1, 
            tGame.StartPositions[iPlayerID].Color, 
            iBright)
    end
    
    SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y-1}, tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright+2)
    SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY}, tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright+2)

    SetRowColorBright(tGame.StartPositions[iPlayerID].X-1, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright+2)
    SetRowColorBright(tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright+2)

    if CGameMode.tFinishPosPlayerX[iPlayerID] and CGameMode.tFinishPosPlayerX[iPlayerID].iX then
        tFloor[CGameMode.tFinishPosPlayerX[iPlayerID].iX][CGameMode.tFinishPosPlayerX[iPlayerID].iY].iColor = CColors.NONE
        tFloor[CGameMode.tFinishPosPlayerX[iPlayerID].iX][CGameMode.tFinishPosPlayerX[iPlayerID].iY].iBright = iBright
    end
    if CGameMode.tFinishPosPlayerY[iPlayerID] and CGameMode.tFinishPosPlayerY[iPlayerID].iX then
        tFloor[CGameMode.tFinishPosPlayerY[iPlayerID].iX][CGameMode.tFinishPosPlayerY[iPlayerID].iY].iColor = CColors.NONE
        tFloor[CGameMode.tFinishPosPlayerY[iPlayerID].iX][CGameMode.tFinishPosPlayerY[iPlayerID].iY].iBright = iBright
    end    
end

CPaint.PlayerZones = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CPaint.PlayerZone(i, CColors.BRIGHT30)
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
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
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

function SetRowColorBright(tStart, iY, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart
        iY = iY + 1

        if not (iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetColColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart.X + i
        local iY = tStart.Y

        if not (iX < 1 or iX > tGame.Cols) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
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

    if click.Click and iGameState == GAMESTATE_GAME then
        if CPieces.tBlocked[click.X] and CPieces.tBlocked[click.X][click.Y] and CPieces.tBlocked[click.X][click.Y].bBlocked then
            CPieces.PlayerSelectPiece(CPieces.tBlocked[click.X][click.Y].iPieceID)
        elseif tFloor[click.X][click.Y].bSelected then
            CPieces.PlayerSelectHighlightedMove(tFloor[click.X][click.Y].iMovePieceID, tFloor[click.X][click.Y].iMoveX, tFloor[click.X][click.Y].iMoveY)
        end
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