--[[
    Название: Вирус/Захват
    Автор: Avondale, дискорд - avonda
   
    Для старта игры нужно нажать на кнопку
    Любое количество игроков

    Описание механики: 
        Игроки пытаются закрасить всё поле, чтобы закрасить пиксель надо на него наступить
        Все игроки в одной команде зелёных
        Им противостоят вражеские команды юнитов, разных цветов

        Кто по истечении времени захватит больше пикселей - тот и победил

        Если у команды меньше 10 захваченных пикселей - она уничтожается
        Если закрасить всё поле - игра закончится не смотря на таймер

        В настройках можно увеличить количество вражеских команд и юнитов в каждой из них

    Идеи по доработке:
        1. Игроки в разных командах:
            непонятно каким образом опеределять кто из игроков где находится и кому засчитывать пиксели

        2. Убийство юнитов:
            могу реализовать систему где несколько раз наступив на юнита он погибает
            а если всех юнитов в команде затоптали то она уничтожается, либо вообще можно сделать чтобы их пиксели переходили игрокам
            но мне кажется такая система сделает игру слишком простой, очень похожей на защиту базы и вообще мега скучной, игроки сразу всех передавят и будут ждать конца таймера

        3. Более интересная система уничтожения команд:
            всёравно уничтожение команды с возможностью передачи пикселей игрокам звучит как интересная механника
            я думаю можно сделать систему выбывания
            после определенного времени команда с самым маленьким количеством пикселей уничтожается
            и её пиксели либо становятся ничьими, либо переходят другой команде(самой сильной или самой слабой?)
            либо команде игрока, но например для этого нужно нажать кнопку на стене
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
        { Score = 0, Lives = 0, Color = 2 },
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

    CGameMode.Init()
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

    if bAnyButtonClick then
        CAudio.PlaySyncFromScratch("")
        CGameMode.StartCountDown(5)
        bAnyButtonClick = false
    end

    CPaint.Units()    
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.Field()
    CPaint.Units()
end

function PostGameTick()
    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinner].Color, tConfig.Bright)
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
CGameMode.iWinner = 0

CGameMode.Init = function()
    CField.SetupField()
    CGameMode.SetupUnits()
end

CGameMode.Announcer = function()
    CAudio.PlaySync("games/virus.mp3")
    CAudio.PlaySync("voices/virus-guide.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

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
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    iGameState = GAMESTATE_GAME

    tGameStats.StageTotalDuration = tConfig.GameLength
    tGameStats.StageLeftDuration = tConfig.GameLength

    CTimer.New(tConfig.UnitThinkDelay, function()
        if iGameState == GAMESTATE_GAME then
            CUnits.ProcessUnits()
            return tConfig.UnitThinkDelay
        end

        return nil
    end)    

    CTimer.New(1000, function()
        if iGameState == GAMESTATE_GAME then
            tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

            if tGameStats.StageLeftDuration == 0 then
                CGameMode.TimeOutFindWinner()
                CGameMode.EndGame()
                return nil
            end

            if tGameStats.StageLeftDuration <= 5 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000
        end

        return nil
    end)        
end

CGameMode.TimeOutFindWinner = function()
    local iMaxScore = -999
    
    for iPlayerID = 1, tConfig.TeamCount+1 do 
        if tGameStats.Players[iPlayerID].Score > iMaxScore then
            iMaxScore = tGameStats.Players[iPlayerID].Score
            CGameMode.iWinner = iPlayerID
        end
    end
end

CGameMode.EndGame = function()
    CAudio.StopBackground()
    iGameState = GAMESTATE_POSTGAME
    CUnits.Clear()

    --CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinner].Color)
    --CAudio.PlaySync(CAudio.VICTORY)

    if CGameMode.iWinner == 1 then
        CAudio.PlaySync(CAudio.GAME_SUCCESS)
        CAudio.PlaySync(CAudio.VICTORY)
    else
        CAudio.PlaySync(CAudio.GAME_OVER)    
        CAudio.PlaySync(CAudio.DEFEAT)
    end

    CTimer.New(tConfig.WinDurationMS, function()
        tGameResults.Won = CGameMode.iWinner == 1
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.SetupUnits = function()
    for iTeamId = 2, tConfig.TeamCount+1 do
        tGameStats.Players[iTeamId].Color = iTeamId
        if iTeamId == 2 then tGameStats.Players[iTeamId].Color = 1 end

        for iUnit = 1, tConfig.UnitCountPerTeam do
            CUnits.NewUnit(math.random( 1, tGame.Cols ), math.random( 1, tGame.Rows ), iTeamId)
        end
    end 
end

CGameMode.DestroyTeam = function(iTeamId)
    CAudio.PlayAsync(CAudio.CLICK)

    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].iTeamId == iTeamId then
            CUnits.tUnits[iUnitID] = nil
        end
    end

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if CField.tField[iX] and CField.tField[iX][iY] and CField.tField[iX][iY] == iTeamId then
                CField.tField[iX][iY] = 0
            end
        end
    end

    tGameStats.Players[iTeamId].Score = 0
end
--//

--Field
CField = {}
CField.tField = {}

CField.SetupField = function()
    local iTargetScore = 0

    for iX = 1, tGame.Cols do
        CField.tField[iX] = {}

        for iY = 1, tGame.Rows do
            if tFloor[iX] ~= nil and tFloor[iX][iY] ~= nil and not tFloor[iX][iY].bDefect then
                CField.tField[iX][iY] = 0
                iTargetScore = iTargetScore + 1
            end
        end
    end

    tGameStats.TargetScore = iTargetScore
end

CField.PixelCapture = function(iX, iY, iPlayerID)
    if CField.tField[iX] and CField.tField[iX][iY] and CField.tField[iX][iY] ~= iPlayerID then
        if CField.tField[iX][iY] ~= 0 then
            tGameStats.Players[CField.tField[iX][iY]].Score = tGameStats.Players[CField.tField[iX][iY]].Score - 1

            if CField.tField[iX][iY] > 1 and tGameStats.Players[iPlayerID].Score >= 20 and tGameStats.Players[CField.tField[iX][iY]].Score <= 10 then
                CGameMode.DestroyTeam(CField.tField[iX][iY])
            end
        end

        CField.tField[iX][iY] = iPlayerID
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1

        if tGameStats.Players[iPlayerID].Score >= tGameStats.TargetScore then
            CGameMode.iWinner = iPlayerID
            CGameMode.EndGame()
        end
    end
end

CField.DefectPixelInGame = function(iX, iY)
    if CField.tField[iX] and CField.tField[iX][iY] then
        if CField.tField[iX][iY] ~= 0 then
            tGameStats.Players[CField.tField[iX][iY]].Score = tGameStats.Players[CField.tField[iX][iY]].Score - 1
        end

        CField.tField[iX][iY] = nil
        tGameStats.TargetScore = tGameStats.TargetScore - 1
    end
end
--//

--UNITS
CUnits = {}
CUnits.UNIT_SIZE = 2

CUnits.tUnits = {}
CUnits.tUnitStruct = {
    iX = 0,
    iY = 0,
    iColor = 0,
    iDestX = 0,
    iDestY = 0,
    tPath = {},
    iStep = 2,
    iTeamId = 0,
}

CUnits.NewUnit = function(iX, iY, iTeamId)
    iUnitID = #CUnits.tUnits+1
    CUnits.tUnits[iUnitID] = CHelp.ShallowCopy(CUnits.tUnitStruct)
    CUnits.tUnits[iUnitID].iX = iX
    CUnits.tUnits[iUnitID].iY = iY
    CUnits.tUnits[iUnitID].iTeamId = iTeamId
end

CUnits.Clear = function()
    CUnits.tUnits = {}
end

CUnits.RandomDestinationForUnit = function(iUnitID)
    CUnits.tUnits[iUnitID].iDestX = math.random( 1, tGame.Cols )
    CUnits.tUnits[iUnitID].iDestY = math.random( 1, tGame.Rows )
end

CUnits.ProcessUnits = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            CUnits.UnitThink(iUnitID)
        end
    end
end

--UNIT AI
CUnits.UnitThink = function(iUnitID)
    CUnits.UnitThinkDefault(iUnitID)
end

CUnits.UnitThinkDefault = function(iUnitID)
    if CUnits.tUnits[iUnitID].iDestX == 0 or (CUnits.tUnits[iUnitID].iX == CUnits.tUnits[iUnitID].iDestX and CUnits.tUnits[iUnitID].iY == CUnits.tUnits[iUnitID].iDestY) then
        CLog.print("New Destination for unit #"..iUnitID)
        CUnits.RandomDestinationForUnit(iUnitID)
    end

    local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitID)

    if CUnits.CanMove(iUnitID, iXPlus, iYPlus) then
        CUnits.Move(iUnitID, iXPlus, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, 0) then
        CUnits.Move(iUnitID, iXPlus, 0)
    elseif CUnits.CanMove(iUnitID, 0, iYPlus) then
        CUnits.Move(iUnitID, 0, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, -1) then
        CUnits.Move(iUnitID, iXPlus, -1)        
    elseif CUnits.CanMove(iUnitID, -1, iYPlus) then
        CUnits.Move(iUnitID, -1, iYPlus)        
    elseif CUnits.CanMove(iUnitID, 1, iYPlus) then
        CUnits.Move(iUnitID, 1, iYPlus)
    elseif CUnits.CanMove(iUnitID, iXPlus, 1) then
        CUnits.Move(iUnitID, iXPlus, 1)
    end
end
--/

--UNIT MOVEMENT
CUnits.CanMove = function(iUnitID, iXPlus, iYPlus)
    if iXPlus == 0 and iYPlus == 0 then return false end

    local iX = CUnits.tUnits[iUnitID].iX + iXPlus
    local iY = CUnits.tUnits[iUnitID].iY + iYPlus

    for iXCheck = iX, iX + CUnits.UNIT_SIZE-1 do
        for iYCheck = iY, iY + CUnits.UNIT_SIZE-1 do
            if not tFloor[iXCheck] or not tFloor[iXCheck][iYCheck] then return true end
            --if tFloor[iXCheck][iYCheck].bDefect then return false end
        end
    end

    return true
end

CUnits.Move = function(iUnitID, iXPlus, iYPlus)
    CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + iXPlus
    CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + iYPlus

    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.UNIT_SIZE-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.UNIT_SIZE-1 do
            CField.PixelCapture(iX, iY, CUnits.tUnits[iUnitID].iTeamId)
        end
    end    
end

CUnits.GetDestinationXYPlus = function(iUnitID)
    local iX = 0
    local iY = 0

    if CUnits.tUnits[iUnitID].iX < CUnits.tUnits[iUnitID].iDestX then
        iX = 1
    elseif CUnits.tUnits[iUnitID].iX > CUnits.tUnits[iUnitID].iDestX then
        iX = -1
    end

    if CUnits.tUnits[iUnitID].iY < CUnits.tUnits[iUnitID].iDestY then
        iY = 1
    elseif CUnits.tUnits[iUnitID].iY > CUnits.tUnits[iUnitID].iDestY then
        iY = -1
    end

    return iX, iY    
end

--//

--Paint
CPaint = {}

CPaint.Field = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if CField.tField[iX] and CField.tField[iX][iY] and CField.tField[iX][iY] > 0 then
                tFloor[iX][iY].iColor = tGameStats.Players[CField.tField[iX][iY]].Color
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
    end
end

CPaint.Units = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            CPaint.Unit(iUnitID)
        end
    end
end

CPaint.Unit = function(iUnitID)
    for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CUnits.UNIT_SIZE-1 do
        for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CUnits.UNIT_SIZE-1 do

            if tFloor[iX] and tFloor[iX][iY] then
                tFloor[iX][iY].iColor = tGameStats.Players[CUnits.tUnits[iUnitID].iTeamId].Color
                tFloor[iX][iY].iBright = tConfig.Bright+1
            end
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
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if iGameState == GAMESTATE_GAME and click.Click and not tFloor[click.X][click.Y].bDefect then
        CField.PixelCapture(click.X, click.Y, 1)
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect
    
    CField.DefectPixelInGame(defect.X, defect.Y)
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click and not CGameMode.bCountDownStarted then
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