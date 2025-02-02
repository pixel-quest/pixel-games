--[[
    Название: тетрис
    Автор: Avondale, дискорд - avonda
    Описание механики:
        обычный тетрис, только играется ногами
        управление фигурами - нажатия по полю с цветом игрока(желтый/фиолетовый)
        нажатие на зеленую линию переворачивает фигуру
        за закрытие линий даются очки, чем больше линий за одну фигуру закрыто - тем больше очков
        за комбо даётся бонус, чем больше комбо подряд тем больше бонус
        у кого больше очков тот и победил(не обязательно тот кто дольше продержался)
        после каждой закрытой линии игра ускоряется

    Идеи по доработке:
        цветов мало для фигур
        перевороты фигур так себе работают, нужно писать смещение по X/Y для каждого отдельного вращения каждой фигуры

        функция хард дропа(моментального опускания фигуры) есть в коде, но непонятно как реализовывать кнопку под неё, чтобы всегда был доступ
        превью следующей фигуры, было бы круто сделать но просто нету места под это, так же как сохранение фигуры в слот(и кнопка нужна так что с этим двойная проблема)
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
    TargetScore = 1,
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

    for iPlayerID = 1, #tGame.StartPositions do
        tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
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
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionControlsY) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                CGameMode.tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                CGameMode.tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if iPlayersReady > 0 then
        if not tGame.NewStart then
            SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)
        end

        if bAnyButtonClick or (tGame.NewStart and iPlayersReady == #tGame.StartPositions) then
            tGameResults.PlayersCount = iPlayersReady
            CGameMode.iRealPlayerCount = iPlayersReady
            iGameState = GAMESTATE_GAME
            CGameMode.StartCountDown(5)
        end
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет

    for iPlayerID = 1, #tGame.StartPositions do
        if CGameMode.tPlayerInGame[iPlayerID] then
            CPaint.PlayerZone(iPlayerID, tConfig.Bright)
        end
    end
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
CGameMode.iWinnerID = 1
CGameMode.tPlayerInGame = {}
CGameMode.tPlayerLost = {}
CGameMode.tPlayerSeed = {}
CGameMode.iMoveDownTickRate = 1
CGameMode.bVerticalGame = true

CGameMode.iRealPlayerCount = 0
CGameMode.iPlayerLostCount = 0

CGameMode.InitGameMode = function()
    CGameMode.iMoveDownTickRate = tConfig.MoveDownTickRate
    CBlocks.iStartSeed = math.random(1, 99999)

    if tGame.StartPositionSizeX > tGame.StartPositionSizeY then
        CGameMode.bVerticalGame = false
    end
end

CGameMode.Announcer = function()
    CAudio.PlaySync("tetris_intro_voice.mp3")
    CAudio.PlaySync("voices/choose-color.mp3")
    if not tGame.NewStart then
        CAudio.PlaySync("voices/press-button-for-start.mp3") 
    end   
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    if CGameMode.bVerticalGame then
        CTetris.LoadPlayerFields(tGame.StartPositionSizeX, tGame.StartPositionSizeY)
    else
        CTetris.LoadPlayerFields(tGame.StartPositionSizeY, tGame.StartPositionSizeX)
    end

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
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayBackground("tetris_bgsong.mp3")

    CTetris.FirstBlock()

    AL.NewTimer(CGameMode.iMoveDownTickRate, function()
        if iGameState == GAMESTATE_GAME then
            CTetris.MoveAllActiveDown()
            return CGameMode.iMoveDownTickRate
        end
    end)

    AL.NewTimer(100, function()
        if iGameState == GAMESTATE_GAME then
            CTetris.MoveLeftRightAll()
            return 100
        end
    end)
end

CGameMode.PlayerClearedLines = function(iPlayerID, iLinesCleared)
    if iLinesCleared == 1 then
        CGameMode.PlayerAddScore(iPlayerID, 100)
    elseif iLinesCleared == 2 then
        CGameMode.PlayerAddScore(iPlayerID, 300)
    elseif iLinesCleared == 3 then
        CGameMode.PlayerAddScore(iPlayerID, 500)
    else
        CGameMode.PlayerAddScore(iPlayerID, 800)
    end

    CAudio.PlayAsync("tetris_clear_"..iLinesCleared.."_line.mp3")
end

CGameMode.PlayerAddScore = function(iPlayerID, iScorePlus)
     tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScorePlus
    if tGameStats.Players[iPlayerID].Score > tGameStats.TargetScore then tGameStats.TargetScore = tGameStats.Players[iPlayerID].Score end  
end

CGameMode.PlayerOut = function(iPlayerID)
    CGameMode.tPlayerLost[iPlayerID] = true
    CGameMode.iPlayerLostCount = CGameMode.iPlayerLostCount + 1 

    if CGameMode.iPlayerLostCount == CGameMode.iRealPlayerCount then
        CGameMode.EndGame()
    else
        CAudio.PlayAsync(CAudio.GAME_OVER)
    end
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -999

    for i = 1, #tGame.StartPositions do
        if tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
            tGameResults.Score = tGameStats.Players[i].Score
        end
    end

    iGameState = GAMESTATE_POSTGAME
    
    CAudio.PlaySyncFromScratch("")
    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)  

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
end
--//

--tetris
CTetris = {}
CTetris.tPlayerField = {}
CTetris.tPlayerFieldLines = {}
CTetris.tPlayerActiveBlock = {}
CTetris.tPlayerMoveX = {}
CTetris.tPlayerLineClearCombo = {}
CTetris.iFieldSizeX = 0
CTetris.iFieldSizeY = 0

CTetris.LoadPlayerFields = function(iFieldSizeX, iFieldSizeY)
    CTetris.iFieldSizeX = iFieldSizeX
    if CGameMode.bVerticalGame then 
        CTetris.iFieldSizeY = iFieldSizeY - tGame.StartPositionControlsY
    else
        CTetris.iFieldSizeY = tGame.StartPositionControlsY-1
    end

    for iPlayerID = 1, #tGame.StartPositions do
        if CGameMode.tPlayerInGame[iPlayerID] then
            CTetris.tPlayerField[iPlayerID] = {}
            CTetris.tPlayerFieldLines[iPlayerID] = {}
            for iX = 1, CTetris.iFieldSizeX do
                CTetris.tPlayerField[iPlayerID][iX] = {}
                for iY = 1, CTetris.iFieldSizeY do
                    CTetris.tPlayerField[iPlayerID][iX][iY] = CColors.NONE

                    if not CTetris.tPlayerFieldLines[iPlayerID][iY] then
                        CTetris.tPlayerFieldLines[iPlayerID][iY] = 0
                    end
                end
            end
        end
    end
end

CTetris.FirstBlock = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if CGameMode.tPlayerInGame[iPlayerID] then
            CTetris.SpawnNextBlockForPlayer(iPlayerID)
        end
    end
end

CTetris.SpawnNextBlockForPlayer = function(iPlayerID)
    CTetris.tPlayerActiveBlock[iPlayerID] = {}
    CTetris.tPlayerActiveBlock[iPlayerID].iBlockType = CBlocks.NextBlockTypeForPlayer(iPlayerID)
    CTetris.tPlayerActiveBlock[iPlayerID].iX = math.floor(CTetris.iFieldSizeX/2)
    CTetris.tPlayerActiveBlock[iPlayerID].iY = -math.floor(#CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType]/2)
    CTetris.tPlayerActiveBlock[iPlayerID].iRotation = 1

end

CTetris.MoveAllActiveDown = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if CGameMode.tPlayerInGame[iPlayerID] and not CGameMode.tPlayerLost[iPlayerID] then
            CTetris.MovePlayerActiveDown(iPlayerID)
        end
    end

    CAudio.PlayAsync("tetris_movedown.mp3")
end

CTetris.MovePlayerActiveDown = function(iPlayerID)
    if not CTetris.CheckActiveCanMove(iPlayerID, 0, 1, 0) then
        CTetris.PlaceActiveBlock(iPlayerID)
        return true
    else
        CTetris.tPlayerActiveBlock[iPlayerID].iY = CTetris.tPlayerActiveBlock[iPlayerID].iY + 1
        return false
    end
end

CTetris.MoveLeftRightAll = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if CGameMode.tPlayerInGame[iPlayerID] and not CGameMode.tPlayerLost[iPlayerID] then
            CTetris.MoveLeftRightPlayer(iPlayerID)
        end
    end    
end

CTetris.MoveLeftRightPlayer = function(iPlayerID)
    if not CTetris.tPlayerMoveX[iPlayerID] or CTetris.tPlayerMoveX[iPlayerID] == 0 or CTetris.tPlayerMoveX[iPlayerID] == CTetris.tPlayerActiveBlock[iPlayerID].iX then return; end

    if CTetris.tPlayerMoveX[iPlayerID] + #CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][CTetris.tPlayerActiveBlock[iPlayerID].iRotation][1] -1 > CTetris.iFieldSizeX then  
        CTetris.tPlayerMoveX[iPlayerID] = CTetris.iFieldSizeX+1 - #CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][CTetris.tPlayerActiveBlock[iPlayerID].iRotation][1]
    end

    local iXPlus = 0

    if CTetris.tPlayerMoveX[iPlayerID] < CTetris.tPlayerActiveBlock[iPlayerID].iX then
        iXPlus = -1
    elseif CTetris.tPlayerMoveX[iPlayerID] > CTetris.tPlayerActiveBlock[iPlayerID].iX then
        iXPlus = 1
    end

    if CTetris.CheckActiveCanMove(iPlayerID, iXPlus, 0, 0) then
        CTetris.tPlayerActiveBlock[iPlayerID].iX = CTetris.tPlayerActiveBlock[iPlayerID].iX + iXPlus
    end
end

CTetris.CheckActiveCanMove = function(iPlayerID, iXPlus, iYPlus, iRotationPlus)

    local tActiveBlock = CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][CTetris.tPlayerActiveBlock[iPlayerID].iRotation+iRotationPlus] or CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][1]

    for iLocalY = 1, #tActiveBlock do
        for iLocalX = 1, #tActiveBlock[iLocalY] do
            if tActiveBlock[iLocalY][iLocalX] == 1 then
                local iX = iLocalX + CTetris.tPlayerActiveBlock[iPlayerID].iX -1 + iXPlus
                local iY = iLocalY + CTetris.tPlayerActiveBlock[iPlayerID].iY -1 + iYPlus

                if iY > 0 then
                    if not CTetris.tPlayerField[iPlayerID][iX] or not CTetris.tPlayerField[iPlayerID][iX][iY] then return false end
                    if CTetris.tPlayerField[iPlayerID][iX][iY] > 0 then return false end
                end
            end
        end
    end    

    return true
end

CTetris.PlaceActiveBlock = function(iPlayerID)
    local tActiveBlock = CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][CTetris.tPlayerActiveBlock[iPlayerID].iRotation]
    local iLinesCleared = 0

    for iLocalY = 1, #tActiveBlock do
        for iLocalX = 1, #tActiveBlock[iLocalY] do
            if tActiveBlock[iLocalY][iLocalX] == 1 then
                local iX = iLocalX + CTetris.tPlayerActiveBlock[iPlayerID].iX -1
                local iY = iLocalY + CTetris.tPlayerActiveBlock[iPlayerID].iY -1

                if iY > 0 then
                    CTetris.tPlayerField[iPlayerID][iX][iY] = CBlocks.tBlockColor[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType]
                    CTetris.tPlayerFieldLines[iPlayerID][iY] = CTetris.tPlayerFieldLines[iPlayerID][iY] + 1

                    if CTetris.tPlayerFieldLines[iPlayerID][iY] >= CTetris.iFieldSizeX then
                        CTetris.ClearLine(iPlayerID, iY)
                        iLinesCleared = iLinesCleared + 1
                    end
                end
            end
        end
    end      

    if iLinesCleared > 0 then
        CGameMode.PlayerClearedLines(iPlayerID, iLinesCleared)
        CTetris.tPlayerLineClearCombo[iPlayerID] = (CTetris.tPlayerLineClearCombo[iPlayerID] or 0) + 1
        if CTetris.tPlayerLineClearCombo[iPlayerID] > 1 then
            CGameMode.PlayerAddScore(iPlayerID, (CTetris.tPlayerLineClearCombo[iPlayerID]-1) * 50)
        end
    else
        CTetris.tPlayerLineClearCombo[iPlayerID] = 0

        CAudio.PlayAsync("tetris_place.mp3")
    end

    if CTetris.tPlayerActiveBlock[iPlayerID].iY <= 1 then
        CTetris.tPlayerActiveBlock[iPlayerID] = nil
        CGameMode.PlayerOut(iPlayerID)
        return;
    end

    CTetris.SpawnNextBlockForPlayer(iPlayerID)
end

CTetris.ClearLine = function(iPlayerID, iY)
    for iLinesLocalY = iY, 2, -1 do
        CTetris.tPlayerFieldLines[iPlayerID][iLinesLocalY] = CTetris.tPlayerFieldLines[iPlayerID][iLinesLocalY-1]
    end
    CTetris.tPlayerFieldLines[iPlayerID][1] = 0

    for iLocalY = iY, 2, -1 do
        for iLocalX = 1, CTetris.iFieldSizeX do
            CTetris.tPlayerField[iPlayerID][iLocalX][iLocalY] = CTetris.tPlayerField[iPlayerID][iLocalX][iLocalY-1]
            CTetris.tPlayerField[iPlayerID][iLocalX][iLocalY-1] = 0
        end
    end

    CGameMode.iMoveDownTickRate = CGameMode.iMoveDownTickRate - tConfig.MoveDownTickRateDecreasePerClearedLine
end

CTetris.tButtonRotateCD = {}
CTetris.ButtonRotateActive = function(iPlayerID)
    if not CTetris.tPlayerActiveBlock[iPlayerID] or CTetris.tButtonRotateCD[iPlayerID] then return; end

    if CTetris.CheckActiveCanMove(iPlayerID, 0, 0, 1) then
        CTetris.tPlayerActiveBlock[iPlayerID].iRotation = CTetris.tPlayerActiveBlock[iPlayerID].iRotation + 1
        if #CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType] < CTetris.tPlayerActiveBlock[iPlayerID].iRotation then CTetris.tPlayerActiveBlock[iPlayerID].iRotation = 1 end
        CAudio.PlayAsync("tetris_rotate.mp3")
    end

    CTetris.tButtonRotateCD[iPlayerID]  = true
    AL.NewTimer(300, function()
        CTetris.tButtonRotateCD[iPlayerID]  = false
    end)   
end

CTetris.tButtonPlaceCD = {}
CTetris.ButtonPlaceActive = function(iPlayerID)
    if not CTetris.tPlayerActiveBlock[iPlayerID] or CTetris.tButtonPlaceCD[iPlayerID] then return; end
    
    local iHardDropLines = 0
    while not CTetris.MovePlayerActiveDown(iPlayerID) do iHardDropLines = iHardDropLines + 1 end
    CGameMode.PlayerAddScore(iPlayerID, iHardDropLines*2)

    CTetris.tButtonPlaceCD[iPlayerID] = true
    AL.NewTimer(1500, function()
        CTetris.tButtonPlaceCD[iPlayerID] = false
    end)
end

CTetris.ButtonMove = function(iPlayerID, iX)
    CTetris.tPlayerMoveX[iPlayerID] = iX
end
--//

--blocks
CBlocks = {}
CBlocks.tBlocks = {}
CBlocks.iStartSeed = 1

CBlocks.TB_O = 1
CBlocks.TB_I = 2
CBlocks.TB_J = 3
CBlocks.TB_L = 4
CBlocks.TB_T = 5
CBlocks.TB_S = 6
CBlocks.TB_Z = 7

CBlocks.tBlockColor = {}
CBlocks.tBlockColor[CBlocks.TB_O] = CColors.YELLOW
CBlocks.tBlockColor[CBlocks.TB_I] = CColors.CYAN
CBlocks.tBlockColor[CBlocks.TB_J] = CColors.BLUE
CBlocks.tBlockColor[CBlocks.TB_L] = CColors.RED
CBlocks.tBlockColor[CBlocks.TB_T] = CColors.MAGENTA
CBlocks.tBlockColor[CBlocks.TB_S] = CColors.BLUE
CBlocks.tBlockColor[CBlocks.TB_Z] = CColors.RED

CBlocks.tBlocks[CBlocks.TB_O] = {}
CBlocks.tBlocks[CBlocks.TB_O].iBlockWidth = 2
CBlocks.tBlocks[CBlocks.TB_O][1] = {
    {1, 1},
    {1, 1},
}

CBlocks.tBlocks[CBlocks.TB_I] = {}
CBlocks.tBlocks[CBlocks.TB_I].iBlockWidth = 1
CBlocks.tBlocks[CBlocks.TB_I][1] = {
    {1,},
    {1,},
    {1,},
    {1,},
}
CBlocks.tBlocks[CBlocks.TB_I][2] = {
    {1, 1, 1, 1},
}

CBlocks.tBlocks[CBlocks.TB_J] = {}
CBlocks.tBlocks[CBlocks.TB_J].iBlockWidth = 2
CBlocks.tBlocks[CBlocks.TB_J][1] = {
    {0,1},
    {0,1},
    {1,1},
}
CBlocks.tBlocks[CBlocks.TB_J][2] = {
    {1, 0, 0},
    {1, 1, 1},
}
CBlocks.tBlocks[CBlocks.TB_J][3] = {
    {1,1},
    {1,0},
    {1,0},
}
CBlocks.tBlocks[CBlocks.TB_J][4] = {
    {1, 1, 1},
    {0, 0, 1},
}

CBlocks.tBlocks[CBlocks.TB_L] = {}
CBlocks.tBlocks[CBlocks.TB_L].iBlockWidth = 2
CBlocks.tBlocks[CBlocks.TB_L][1] = {
    {1,0},
    {1,0},
    {1,1},
}
CBlocks.tBlocks[CBlocks.TB_L][2] = {
    {0, 0, 1},
    {1, 1, 1},
}
CBlocks.tBlocks[CBlocks.TB_L][3] = {
    {1,1},
    {0,1},
    {0,1},
}
CBlocks.tBlocks[CBlocks.TB_L][4] = {
    {1, 1, 1},
    {1, 0, 0},
}

CBlocks.tBlocks[CBlocks.TB_T] = {}
CBlocks.tBlocks[CBlocks.TB_T].iBlockWidth = 3
CBlocks.tBlocks[CBlocks.TB_T][1] = {
    {0, 1, 0},
    {1, 1, 1},
}
CBlocks.tBlocks[CBlocks.TB_T][2] = {
    {1,0},
    {1,1},
    {1,0},
}
CBlocks.tBlocks[CBlocks.TB_T][3] = {
    {1, 1, 1},
    {0, 1, 0},
}
CBlocks.tBlocks[CBlocks.TB_T][4] = {
    {0,1},
    {1,1},
    {0,1},
}

CBlocks.tBlocks[CBlocks.TB_S] = {}
CBlocks.tBlocks[CBlocks.TB_S].iBlockWidth = 3
CBlocks.tBlocks[CBlocks.TB_S][1] = {
    {0, 1, 1},
    {1, 1, 0},
}
CBlocks.tBlocks[CBlocks.TB_S][2] = {
    {1,0},
    {1,1},
    {0,1},
}

CBlocks.tBlocks[CBlocks.TB_Z] = {}
CBlocks.tBlocks[CBlocks.TB_Z].iBlockWidth = 3
CBlocks.tBlocks[CBlocks.TB_Z][1] = {
    {1, 1, 0},
    {0, 1, 1},
}
CBlocks.tBlocks[CBlocks.TB_Z][2] = {
    {0,1},
    {1,1},
    {1,0},
}

CBlocks.NextBlockTypeForPlayer = function(iPlayerID)
    if not CGameMode.tPlayerSeed[iPlayerID] then CGameMode.tPlayerSeed[iPlayerID] = CBlocks.iStartSeed end
    local iBlockType = 0

    iBlockType, CGameMode.tPlayerSeed[iPlayerID] = CRandom.IntFromSeed(1, #CBlocks.tBlocks+1, CGameMode.tPlayerSeed[iPlayerID])

    return iBlockType
end

--//

--paint
CPaint = {}

CPaint.PlayerZone = function(iPlayerID, iBright)
    if iGameState == GAMESTATE_SETUP then
        CPaint.FillPlayerZoneWithColor(iPlayerID, iBright, tGame.StartPositions[iPlayerID].Color)
    else
        CPaint.TetrisPlayerZone(iPlayerID, iBright)
        CPaint.TetrisPlayerCurrentBlock(iPlayerID, iBright)
        CPaint.PlayerZoneBorders(iPlayerID, iBright, CColors.WHITE)
    end
end

CPaint.FillPlayerZoneWithColor = function(iPlayerID, iBright, iColor)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do
            if (CGameMode.bVerticalGame and iY > tGame.StartPositionControlsY) or (not CGameMode.bVerticalGame and iX <= tGame.StartPositionControlsY) then
                tFloor[iX][iY].iColor = CColors.NONE
            else
                tFloor[iX][iY].iColor = iColor
            end

            tFloor[iX][iY].iBright = iBright
        end
    end
end

CPaint.TetrisPlayerZone = function(iPlayerID, iBright)
    local iLocalX = 1
    local iLocalY = 1
    local iMaxWeight = 5

    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do
            if (CGameMode.bVerticalGame and iY > tGame.StartPositionControlsY) or (not CGameMode.bVerticalGame and iX < tGame.StartPositionControlsY) then
                CPaint.PaintTetrisPixel(iPlayerID, iBright, iLocalX, iLocalY, iX, iY)
            elseif (CGameMode.bVerticalGame and iY == tGame.StartPositionControlsY) or (not CGameMode.bVerticalGame and iX == tGame.StartPositionControlsY) then
                if --[[iX < tGame.StartPositions[iPlayerID].X + math.floor(tGame.StartPositionSizeX/2) and]] not CGameMode.tPlayerLost[iPlayerID] then
                    tFloor[iX][iY].iColor = CColors.GREEN

                    if not tFloor[iX][iY].fFunction then 
                        tFloor[iX][iY].fFunction = function()
                            if iGameState == GAMESTATE_GAME then
                                CTetris.ButtonRotateActive(iPlayerID, iLocalX)
                            end
                        end
                    end
                else
                    tFloor[iX][iY].iColor = CColors.RED

                    --[[
                    if not tFloor[iX][iY].fFunction then 
                        tFloor[iX][iY].fFunction = function()
                            if iGameState == GAMESTATE_GAME then
                                CTetris.ButtonPlaceActive(iPlayerID, iLocalX)
                            end
                        end
                    end
                    ]]
                end
            else
                if not CGameMode.tPlayerLost[iPlayerID] then
                    tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color

                    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > iMaxWeight then 
                        if CGameMode.bVerticalGame then
                            CTetris.ButtonMove(iPlayerID, tGame.StartPositionSizeX - iLocalX+1)
                        else
                            CTetris.ButtonMove(iPlayerID, tGame.StartPositionSizeY - iLocalY+1)
                        end
                        iMaxWeight = tFloor[iX][iY].iWeight
                    end
                else
                    tFloor[iX][iY].iColor = CColors.RED
                end
            end

            tFloor[iX][iY].iBright = iBright
            if CTetris.tPlayerActiveBlock[iPlayerID] and 
            ((CGameMode.bVerticalGame and iY < tGame.StartPositionControlsY and CTetris.tPlayerActiveBlock[iPlayerID].iX == tGame.StartPositionSizeX - iLocalX+1) 
            or (not CGameMode.bVerticalGame and iX > tGame.StartPositionControlsY and CTetris.tPlayerActiveBlock[iPlayerID].iX == tGame.StartPositionSizeY - iY+2)) then
                tFloor[iX][iY].iBright = iBright-2
            end

            iLocalY = iLocalY + 1
        end
        iLocalX = iLocalX + 1
        iLocalY = 1
    end
end

CPaint.PaintTetrisPixel = function(iPlayerID, iBright, iLocalX, iLocalY, iX, iY)
    if CGameMode.bVerticalGame then
        tFloor[iX][iY].iColor = CTetris.tPlayerField[iPlayerID][tGame.StartPositionSizeX-iLocalX+1][tGame.StartPositionSizeY-iLocalY+1]
    else
        tFloor[iX][iY].iColor = CTetris.tPlayerField[iPlayerID][tGame.StartPositionSizeY-iLocalY+1][iLocalX]
    end 
end

CPaint.TetrisPlayerCurrentBlock = function(iPlayerID, iBright)
    if CTetris.tPlayerActiveBlock[iPlayerID] then
        local tActiveBlock = CBlocks.tBlocks[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType][CTetris.tPlayerActiveBlock[iPlayerID].iRotation]

        for iLocalY = 1, #tActiveBlock do
            for iLocalX = 1, #tActiveBlock[iLocalY] do
                if tActiveBlock[iLocalY][iLocalX] == 1 then
                    local iX = 0
                    local iY = 0
                    if CGameMode.bVerticalGame then
                        iX = tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX - (iLocalX + CTetris.tPlayerActiveBlock[iPlayerID].iX -1)
                        iY = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY - (iLocalY + CTetris.tPlayerActiveBlock[iPlayerID].iY -1)
                    else
                        iX = tGame.StartPositions[iPlayerID].X + iLocalY-1 + CTetris.tPlayerActiveBlock[iPlayerID].iY -1 
                        iY = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY - (iLocalX + CTetris.tPlayerActiveBlock[iPlayerID].iX -1)
                    end

                    if (CGameMode.bVerticalGame and iY <= tGame.Rows) or (not CGameMode.bVerticalGame and iX > 0) then
                        tFloor[iX][iY].iColor = CBlocks.tBlockColor[CTetris.tPlayerActiveBlock[iPlayerID].iBlockType]
                        tFloor[iX][iY].iBright = iBright
                    end
                end
            end
        end

    end
end

CPaint.PlayerZoneBorders = function(iPlayerID, iBright, iColor)
    if CGameMode.bVerticalGame then
        if tGame.StartPositions[iPlayerID].X-1 > 0 then
           SetRectColorBright(tGame.StartPositions[iPlayerID].X-1, 1, 0, tGame.StartPositionSizeY, iColor, iBright) 
        end

        if tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX <= tGame.Cols then
           SetRectColorBright(tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX, 1, 0, tGame.StartPositionSizeY, iColor, iBright) 
        end    
    else
        if tGame.StartPositions[iPlayerID].Y-1 > 0 then
           SetRectColorBright(1, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeX-1, 0, iColor, iBright) 
        end

        if tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY <= tGame.Rows then
           SetRectColorBright(1, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY, tGame.StartPositionSizeX-1, 0, iColor, iBright) 
        end    
    end
end
--//

--RANDOM
CRandom = {}

CRandom.fA = 45.0001
CRandom.fB = 1337.0000
CRandom.fM = 99.9999

CRandom.IntFromSeed = function(iMin, iMax, fSeed) -- возвращает iRand, fSeed
    local iRand, fSeed = CRandom.NextFromSeed(fSeed)

    return math.floor(iRand * (iMax-iMin) + iMin), fSeed
end

CRandom.NextFromSeed = function(fSeed)
    fSeed = (CRandom.fA * fSeed + CRandom.fB) % CRandom.fM
    return fSeed % 1, fSeed
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
        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and not tFloor[click.X][click.Y].bDefect then
            if tFloor[click.X][click.Y].fFunction then tFloor[click.X][click.Y].fFunction() end
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