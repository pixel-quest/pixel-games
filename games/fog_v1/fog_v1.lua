--[[
    Название: Туман
    Автор: Avondale, дискорд - avonda

    Описание механики: 

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
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет    
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright) 
    CWorld.Draw()

    if bAnyButtonClick and not CGameMode.bCountDownStarted then
        CGameMode.StartCountDown(5)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет    
    CWorld.Draw()
    CUnits.DrawUnits()
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
CGameMode.bVictory = false

CGameMode.InitGameMode = function()
    CWorld.Load()

    tGameStats.TotalStars = tConfig.CoinCount
    tGameStats.TotalLives = tConfig.TeamHealth
    tGameStats.CurrentLives = tConfig.TeamHealth
end

CGameMode.Announcer = function()
    CAudio.PlaySync("fog_gamename.mp3")
    CAudio.PlaySync("fog_guide.mp3")
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

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
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    iGameState = GAMESTATE_GAME

    AL.NewTimer(tConfig.UnitThinkDelay, function()
        if iGameState ~= GAMESTATE_GAME then return nil end

        CUnits.Think()

        return tConfig.UnitThinkDelay
    end)
end

CGameMode.PlayerClick = function(iX, iY)
    if CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_COIN then
        CGameMode.PlayerAddScore(1)
        CWorld.SetBlock(iX, iY, CWorld.BLOCK_TYPE_EMPTY)
    end    

    CWorld.Vision(iX, iY, true)
    AL.NewTimer(500, function()
        if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
            CWorld.Vision(iX, iY, true)
            return 500
        else
            CWorld.Vision(iX, iY, false)
            return nil
        end
    end)

    if CUnits.IsUnitOnPosition(iX, iY) then
        CUnits.DamagePlayer()
    end
end

CGameMode.PlayerAddScore = function(iAmount)
    CAudio.PlayAsync(CAudio.CLICK)
    tGameStats.CurrentStars = tGameStats.CurrentStars + 1

    if tGameStats.CurrentStars >= tGameStats.TotalStars then
        CGameMode.EndGame(true)
    end
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    CAudio.StopBackground()

    if bVictory then
        CAudio.PlaySync(CAudio.GAME_SUCCESS)
        CAudio.PlaySync(CAudio.VICTORY)
    else
        CAudio.PlaySync(CAudio.GAME_OVER)
        CAudio.PlaySync(CAudio.DEFEAT)
    end

    iGameState = GAMESTATE_POSTGAME

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)   

    if CGameMode.bVictory then
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
    else
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
    end
end
--//

--UNITS
CUnits = {}
CUnits.tUnits = {}

CUnits.iUnitColor = CColors.RED
CUnits.bDamageCooldown = false

CUnits.UNIT_DAMAGE = 1
CUnits.UNIT_DAMAGE_COOLDOWN = 1500

CUnits.CreateUnit = function(iX, iY)
    local iUnitId = #CUnits.tUnits+1
    CUnits.tUnits[iUnitId] = {}
    CUnits.tUnits[iUnitId].iX = iX
    CUnits.tUnits[iUnitId].iY = iY
    CUnits.tUnits[iUnitId].bLastMoveX = false

    CWorld.tBlocks[iX][iY].iUnitId = iUnitId
    CUnits.NewDestinationForUnit(iUnitId)
end

CUnits.NewDestinationForUnit = function(iUnitId)
    CUnits.tUnits[iUnitId].iDestX = math.random(1, tGame.Cols)
    CUnits.tUnits[iUnitId].iDestY = math.random(1, tGame.Rows)    
end

CUnits.DrawUnits = function()
    for iUnitId = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitId] then
            tFloor[CUnits.tUnits[iUnitId].iX][CUnits.tUnits[iUnitId].iY].iColor = CUnits.iUnitColor
            tFloor[CUnits.tUnits[iUnitId].iX][CUnits.tUnits[iUnitId].iY].iBright = tConfig.Bright
        end
    end
end

CUnits.Think = function()
    for iUnitId = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitId] then
            CUnits.UnitThink(iUnitId)
        end
    end
end

CUnits.UnitThink = function(iUnitId)
    local iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitId)

    if iXPlus == 0 and iYPlus == 0 then
        CUnits.NewDestinationForUnit(iUnitId)
        iXPlus, iYPlus = CUnits.GetDestinationXYPlus(iUnitId)
    end

    local iNewX = CUnits.tUnits[iUnitId].iX
    local iNewY = CUnits.tUnits[iUnitId].iY

    if not CUnits.tUnits[iUnitId].bLastMoveX then
        iNewX = iNewX + iXPlus
        CUnits.tUnits[iUnitId].bLastMoveX = true
    else
        iNewY = iNewY + iYPlus
        CUnits.tUnits[iUnitId].bLastMoveX = false
    end

    if CUnits.CanMove(iUnitId, iNewX, iNewY) then
        CUnits.Move(iUnitId, iNewX, iNewY)
    else
        CUnits.NewDestinationForUnit(iUnitId)  
    end
end

CUnits.GetDestinationXYPlus = function(iUnitId)
    local iX = 0
    local iY = 0

    if CUnits.tUnits[iUnitId].iX < CUnits.tUnits[iUnitId].iDestX then
        iX = 1
    elseif CUnits.tUnits[iUnitId].iX > CUnits.tUnits[iUnitId].iDestX then
        iX = -1
    end

    if CUnits.tUnits[iUnitId].iY < CUnits.tUnits[iUnitId].iDestY then
        iY = 1
    elseif CUnits.tUnits[iUnitId].iY > CUnits.tUnits[iUnitId].iDestY then
        iY = -1
    end

    return iX, iY
end

CUnits.CanMove = function(iUnitId, iX, iY)
    if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then
        if CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_EMPTY then
            if CWorld.tBlocks[iX][iY].iUnitId > 0 and CWorld.tBlocks[iX][iY].iUnitId ~= iUnitId then
                if CUnits.tUnits[CWorld.tBlocks[iX][iY].iUnitId].iX ~= iX or CUnits.tUnits[CWorld.tBlocks[iX][iY].iUnitId].iY ~= iY then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

CUnits.Move = function(iUnitId, iX, iY)
    CUnits.tUnits[iUnitId].iX = iX
    CUnits.tUnits[iUnitId].iY = iY
    CWorld.tBlocks[iX][iY].iUnitId = iUnitId

    CUnits.Collision(iX, iY)
end

CUnits.Collision = function(iX, iY)
    if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 10 then
        CUnits.DamagePlayer()
    end
end

CUnits.DamagePlayer = function()
    if CUnits.bDamageCooldown then return; end

    tGameStats.CurrentLives = tGameStats.CurrentLives - CUnits.UNIT_DAMAGE
    if tGameStats.CurrentLives == 0 then
        CGameMode.EndGame(false)
    else
        CAudio.PlayAsync(CAudio.MISCLICK)

        CUnits.bDamageCooldown = true
        CUnits.iUnitColor = CColors.MAGENTA

        AL.NewTimer(CUnits.UNIT_DAMAGE_COOLDOWN, function()
            CUnits.bDamageCooldown = false
            CUnits.iUnitColor = CColors.RED           
        end)
    end
end

CUnits.IsUnitOnPosition = function(iX, iY)
    if CWorld.tBlocks[iX][iY].iUnitId > 0 then
        if CUnits.tUnits[CWorld.tBlocks[iX][iY].iUnitId].iX == iX and CUnits.tUnits[CWorld.tBlocks[iX][iY].iUnitId].iY == iY then
            return CWorld.tBlocks[iX][iY].iUnitId
        end
    end
    return false
end
--//

--WORLD
CWorld = {}
CWorld.tBlocks = {}

CWorld.BLOCK_TYPE_EMPTY = 1
CWorld.BLOCK_TYPE_TERRAIN = 2
CWorld.BLOCK_TYPE_COIN = 3
CWorld.BLOCK_TYPE_SAFEZONE = 4

CWorld.BLOCK_TYPE_TO_COLOR = {}
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_EMPTY] = CColors.NONE
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_TERRAIN] = CColors.CYAN
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_COIN] = CColors.YELLOW
CWorld.BLOCK_TYPE_TO_COLOR[CWorld.BLOCK_TYPE_SAFEZONE] = CColors.GREEN
CWorld.FOG_COLOR = CColors.BLUE

CWorld.VISION_RADIUS = 1

CWorld.Load = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            CWorld.SetBlock(iX, iY, CWorld.BLOCK_TYPE_EMPTY)
        end
    end

    for iStructureId = 1, math.random(2,4) do
        local iBlockType = CWorld.BLOCK_TYPE_SAFEZONE
        if iStructureId > 2 and math.random(1, 3) == 3 then iBlockType = CWorld.BLOCK_TYPE_TERRAIN end

        CWorld.CreateStructure(math.random(1, tGame.Cols), math.random(1, tGame.Rows), iBlockType)       
    end

    for iCoinId = 1, tConfig.CoinCount do
        local iX = 0
        local iY = 0

        repeat
            iX = math.random(1, tGame.Cols)
            iY = math.random(1, tGame.Rows)
        until CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] and CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_EMPTY and not tFloor[iX][iY].bDefect

        CWorld.SetBlock(iX, iY, CWorld.BLOCK_TYPE_COIN)
    end

    for iUnitId = 1, tConfig.UnitCount do
        local iX = 1
        local iY = 1

        repeat
            iX = math.random(1, tGame.Cols)
            iY = math.random(1, tGame.Rows)
        until CUnits.CanMove(0, iX, iY)   

        CUnits.CreateUnit(iX, iY)
    end
end

CWorld.SetBlock = function(iX, iY, iBlockType)
    if CWorld.tBlocks[iX] == nil then CWorld.tBlocks[iX] = {} end
    CWorld.tBlocks[iX][iY] = {} 
    CWorld.tBlocks[iX][iY].iBlockType = iBlockType 
    CWorld.tBlocks[iX][iY].bVisible = false  
    CWorld.tBlocks[iX][iY].iUnitId = 0  
end

CWorld.Draw = function()
    for iX = 1, tGame.Cols do 
        for iY = 1, tGame.Rows do 
            if CWorld.tBlocks[iX][iY].bVisible or CWorld.tBlocks[iX][iY].iBlockType == CWorld.BLOCK_TYPE_SAFEZONE then
                tFloor[iX][iY].iColor = CWorld.BLOCK_TYPE_TO_COLOR[CWorld.tBlocks[iX][iY].iBlockType]
            else
                tFloor[iX][iY].iColor = CWorld.FOG_COLOR
            end
            tFloor[iX][iY].iBright = tConfig.Bright          
        end
    end
end

CWorld.Vision = function(iXStart, iYStart, bVisible)
    for iX = iXStart - CWorld.VISION_RADIUS, iXStart + CWorld.VISION_RADIUS do
        for iY = iYStart - CWorld.VISION_RADIUS, iYStart + CWorld.VISION_RADIUS do
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iX][iY] then
                CWorld.tBlocks[iX][iY].bVisible = bVisible

                if bVisible then
                    local iUnitId = CUnits.IsUnitOnPosition(iX, iY)
                    if iUnitId then
                        CUnits.tUnits[iUnitId].iDestX = iXStart
                        CUnits.tUnits[iUnitId].iDestY = iYStart
                    end
                end
            end
        end
    end
end

CWorld.CreateStructure = function(iXStart, iYStart, iBlockType)
    local iSize = math.random(2,3)

    for iX = iXStart, iXStart+iSize do
        for iY = iYStart, iYStart+iSize do
            if CWorld.tBlocks[iX] and CWorld.tBlocks[iY] then
                CWorld.SetBlock(iX, iY, iBlockType)
            end
        end
    end
end
--//

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

function Dist(iX1, iY1, iX2, iY2)
    return math.sqrt(math.pow(iX2 - iX1, 2) + math.pow(iY2 - iY1, 2))
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

        if click.Click and iGameState == GAMESTATE_GAME then
            CGameMode.PlayerClick(click.X, click.Y)
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and CWorld.tBlocks[defect.X][defect.Y].iBlockType == CWorld.BLOCK_TYPE_COIN then
            CGameMode.PlayerClick(defect.X, defect.Y)
        end
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click

    if click.Click then bAnyButtonClick = true end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end