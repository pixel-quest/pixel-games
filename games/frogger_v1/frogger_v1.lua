--[[
    Название: Фроггер
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Игроки должны за ограниченное время перебежать дорогу как можно больше раз, туда обратно, не попадаясь под машины
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
    Won = true,
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
    iClickTime = 0,
    bDamageCooldown = false,
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
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CSafeZones.Paint()
end

function GameTick()
    SetGlobalColorBright(CColors.YELLOW, tConfig.Bright)
    SetAllButtonColorBright(CColors.NONE, CColors.BRIGHT0, false)
    CSafeZones.Paint()
    CLanes.Paint()
    CUnits.Paint()
end

function PostGameTick()
    SetGlobalColorBright(CColors.YELLOW, tConfig.Bright)
    SetAllButtonColorBright(CColors.NONE, CColors.BRIGHT0, false)
    CSafeZones.Paint()
    CLanes.Paint()    
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
CGameMode.bCanAutoStart = false

CGameMode.InitGameMode = function()
    tGameStats.CurrentLives = tConfig.Lives
    tGameStats.TotalLives = tConfig.Lives
    tGameStats.StageTotalDuration = tConfig.TimeLimit
    tGameStats.StageLeftDuration = tConfig.TimeLimit

    if tConfig.Vertical then
        CSafeZones.NewSafeZone(1, 1, CSafeZones.SAFE_ZONE_SIZE, tGame.Rows, true, true)
        CSafeZones.NewSafeZone(tGame.Cols - CSafeZones.SAFE_ZONE_SIZE+1, 1, CSafeZones.SAFE_ZONE_SIZE, tGame.Rows, true, false)
        local iLaneCountPerZone = math.ceil(((tGame.Cols - (CSafeZones.SAFE_ZONE_SIZE*2)) / CLanes.LANE_SIZE) / 2)
        
        for iSafeZoneID = 1, 2 do
            local iX = CSafeZones.tZones[iSafeZoneID].iX
            local iXPlus = -CLanes.LANE_SIZE
            if iSafeZoneID == 1 then iXPlus = CLanes.LANE_SIZE; end
            iX = iX + iXPlus

            for i = 1, iLaneCountPerZone do
                if iLaneCountPerZone % 2 ~= 0 and i == iLaneCountPerZone and iSafeZoneID > 1 then break; end
                CLanes.NewLane(iX, 1)
                iX = iX + iXPlus
            end
        end
    else
        CSafeZones.NewSafeZone(1, 1, tGame.Cols, CSafeZones.SAFE_ZONE_SIZE, true, true)
        CSafeZones.NewSafeZone(1, tGame.Rows - CSafeZones.SAFE_ZONE_SIZE+1, tGame.Cols, CSafeZones.SAFE_ZONE_SIZE, true, false)
        local iLaneCountPerZone = math.ceil(((tGame.Rows - (CSafeZones.SAFE_ZONE_SIZE*2)) / CLanes.LANE_SIZE) / 2)

        for iSafeZoneID = 1, 2 do
            local iY = CSafeZones.tZones[iSafeZoneID].iY
            local iYPlus = -CLanes.LANE_SIZE
            if iSafeZoneID == 1 then iYPlus = CLanes.LANE_SIZE; end
            iY = iY + iYPlus

            for i = 1, iLaneCountPerZone do
                if iLaneCountPerZone % 2 ~= 0 and i == iLaneCountPerZone and iSafeZoneID > 1 then break; end
                CLanes.NewLane(1, iY)
                iY = iY + iYPlus
            end
        end
    end

    AL.NewTimer(1000, function()
        if iGameState ~= GAMESTATE_SETUP then return nil; end

        if CGameMode.bCanAutoStart and CSafeZones.CheckNoOutsideClicks(CSafeZones.iSafeZoneTargetID) then
            CGameMode.StartGame()
            return nil;
        end

        return 1000
    end)
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("frogger/frogger.mp3")
    CAudio.PlayVoicesSync("frogger/frogger-rules.mp3")

    AL.NewTimer(1000, function()
        CGameMode.bCanAutoStart = true
    end)
end

CGameMode.StartGame = function()
    iGameState = GAMESTATE_GAME
    CSafeZones.NextTarget()
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    AL.NewTimer(3000, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        if CSafeZones.CheckNoOutsideClicks(CSafeZones.iSafeZoneTargetID) then
            CSafeZones.NextTarget()
            CGameMode.RewardForTarget()
            return 3000
        end

        return 1000
    end)    

    AL.NewTimer(1000, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1
        if tGameStats.StageLeftDuration == 0 then
            CGameMode.EndGame(true)
            return nil;
        end

        return 1000
    end)

    AL.NewTimer(250, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CUnits.Think()

        return 250
    end)
end

CGameMode.EndGame = function(bTimeOut)
    iGameState = GAMESTATE_POSTGAME
    CAudio.StopBackground()

    CAudio.PlaySystemSync("game-over.mp3")
    if bTimeOut then
        CAudio.PlayVoicesSync("notime.mp3")
        tGameResults.Color = CColors.YELLOW
    else
        CAudio.PlayVoicesSync("nolives.mp3")
        tGameResults.Color = CColors.RED
    end

    AL.NewTimer(5000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.RewardForTarget = function()
    tGameStats.TotalStars = tGameStats.TotalStars + 1
    tGameResults.Score = tGameResults.Score + 100

    tGameStats.StageLeftDuration = tGameStats.StageLeftDuration + math.floor(tConfig.TimeLimit/10)

    local iClearLaneID = math.random(1, #CLanes.tLanes)
    CLanes.ClearUnitsFromLane(iClearLaneID)
    CLanes.tLanes[iClearLaneID].iColor = CColors.RED
    AL.NewTimer(1000, function()
        CLanes.SpawnUnitsOnLane(iClearLaneID)
    end)
    AL.NewTimer(1500, function()
        CLanes.tLanes[iClearLaneID].iColor = CColors.NONE
    end)
end

CGameMode.DamagePlayer = function()
    CAudio.PlaySystemAsync(CAudio.MISCLICK)
    tGameStats.CurrentLives = tGameStats.CurrentLives - 1
    if tGameStats.CurrentLives == 0 then
        CGameMode.EndGame(false)
    end
end
--//

--SAFEZONES
CSafeZones = {}
CSafeZones.tZones = {}
CSafeZones.iSafeZoneTargetID = 1

CSafeZones.SAFE_ZONE_SIZE = 2

CSafeZones.NewSafeZone = function(iX, iY, iSizeX, iSizeY, bTargetable, bTarget)
    local iSafeZoneID = #CSafeZones.tZones+1
    CSafeZones.tZones[iSafeZoneID] = {}
    CSafeZones.tZones[iSafeZoneID].iX = iX
    CSafeZones.tZones[iSafeZoneID].iY = iY
    CSafeZones.tZones[iSafeZoneID].iSizeX = iSizeX
    CSafeZones.tZones[iSafeZoneID].iSizeY = iSizeY
    CSafeZones.tZones[iSafeZoneID].bTargetable = bTargetable
    CSafeZones.tZones[iSafeZoneID].bTarget = bTarget
end

CSafeZones.Paint = function()
    for iSafeZoneID = 1, #CSafeZones.tZones do
        local iColor = CColors.YELLOW
        local iBright = tConfig.Bright

        if CSafeZones.tZones[iSafeZoneID].bTarget then
            iColor = CColors.GREEN
        elseif iGameState == GAMESTATE_SETUP then
            iColor = CColors.NONE
        end

        SetRectColorBright(CSafeZones.tZones[iSafeZoneID].iX, CSafeZones.tZones[iSafeZoneID].iY, CSafeZones.tZones[iSafeZoneID].iSizeX, CSafeZones.tZones[iSafeZoneID].iSizeY, iColor, iBright)
    end
end

CSafeZones.CheckNoOutsideClicks = function(iSafeZoneID)
    if CheckPositionClick(CSafeZones.tZones[iSafeZoneID].iX, CSafeZones.tZones[iSafeZoneID].iY, CSafeZones.tZones[iSafeZoneID].iSizeX, CSafeZones.tZones[iSafeZoneID].iSizeY) then
        for iX = 1, tGame.Cols do
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bDefect and not AL.RectIntersects2(iX, iY, 1, 1, CSafeZones.tZones[iSafeZoneID].iX, CSafeZones.tZones[iSafeZoneID].iY, CSafeZones.tZones[iSafeZoneID].iSizeX, CSafeZones.tZones[iSafeZoneID].iSizeY) then
                    if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
                        return false
                    end
                end
            end
        end
    
        return true
    end

    return false
end

CSafeZones.NextTarget = function()
    CSafeZones.tZones[CSafeZones.iSafeZoneTargetID].bTarget = false

    CSafeZones.iSafeZoneTargetID = CSafeZones.iSafeZoneTargetID + 1
    if CSafeZones.iSafeZoneTargetID > 2 then CSafeZones.iSafeZoneTargetID = 1; end
    CSafeZones.tZones[CSafeZones.iSafeZoneTargetID].bTarget = true
end
--//

--LANES
CLanes = {}
CLanes.tLanes = {}

CLanes.LANE_SIZE = 2

CLanes.NewLane = function(iX, iY)
    local iLaneID = #CLanes.tLanes+1

    CLanes.tLanes[iLaneID] = {}
    CLanes.tLanes[iLaneID].iX = iX
    CLanes.tLanes[iLaneID].iY = iY
    CLanes.tLanes[iLaneID].iSizeX = CLanes.LANE_SIZE
    CLanes.tLanes[iLaneID].iSizeY = CLanes.LANE_SIZE
    CLanes.tLanes[iLaneID].iColor = CColors.NONE

    if tConfig.Vertical then
        CLanes.tLanes[iLaneID].iSizeY = tGame.Rows-iY+1
    else
        CLanes.tLanes[iLaneID].iSizeX = tGame.Cols-iX+1
    end

    CLanes.SpawnUnitsOnLane(iLaneID)
end

CLanes.SpawnUnitsOnLane = function(iLaneID)
    local iLaneVelocity = math.random(0,1)
    if iLaneVelocity == 0 then iLaneVelocity = -1; end

    for iUnit = 1, math.random(1,4) do
        CUnits.SpawnNewUnitOnLane(iLaneID, iLaneVelocity)
    end
end

CLanes.ClearUnitsFromLane = function(iLaneID)
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] and CUnits.tUnits[iUnitID].iLaneID == iLaneID then
            CUnits.FadeKillUnit(iUnitID)
        end
    end
end

CLanes.Paint = function()
    for iLaneID = 1, #CLanes.tLanes do
        SetRectColorBright(CLanes.tLanes[iLaneID].iX, CLanes.tLanes[iLaneID].iY, CLanes.tLanes[iLaneID].iSizeX, CLanes.tLanes[iLaneID].iSizeY, CLanes.tLanes[iLaneID].iColor, 1)
    end
end
--//

--UNITS
CUnits = {}
CUnits.tUnits = {}

CUnits.tUnitColors = {}
CUnits.tUnitColors[1] = CColors.RED
CUnits.tUnitColors[2] = CColors.CYAN
CUnits.tUnitColors[3] = CColors.WHITE

CUnits.SpawnNewUnitOnLane = function(iLaneID, iVelocity)
    local iUnitID = #CUnits.tUnits+1
    CUnits.tUnits[iUnitID] = {}
    CUnits.tUnits[iUnitID].iLaneID = iLaneID
    CUnits.tUnits[iUnitID].iX = CLanes.tLanes[iLaneID].iX
    CUnits.tUnits[iUnitID].iY = CLanes.tLanes[iLaneID].iY
    CUnits.tUnits[iUnitID].iXVel = 0
    CUnits.tUnits[iUnitID].iYVel = 0
    CUnits.tUnits[iUnitID].bDamageCooldown = false
    CUnits.tUnits[iUnitID].iBright = tConfig.Bright

    if tConfig.Vertical then
        CUnits.tUnits[iUnitID].iYVel = iVelocity
        CUnits.tUnits[iUnitID].iY = math.random(CLanes.tLanes[iLaneID].iY, CLanes.tLanes[iLaneID].iY+CLanes.tLanes[iLaneID].iSizeY)
    else
        CUnits.tUnits[iUnitID].iXVel = iVelocity
        CUnits.tUnits[iUnitID].iX = math.random(CLanes.tLanes[iLaneID].iX, CLanes.tLanes[iLaneID].iX+CLanes.tLanes[iLaneID].iSizeX)
    end

    CUnits.tUnits[iUnitID].iColor = CUnits.tUnitColors[math.random(1, #CUnits.tUnitColors)]
end

CUnits.Paint = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            for iX = CUnits.tUnits[iUnitID].iX, CUnits.tUnits[iUnitID].iX + CLanes.LANE_SIZE-1 do
                for iY = CUnits.tUnits[iUnitID].iY, CUnits.tUnits[iUnitID].iY + CLanes.LANE_SIZE-1 do
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CUnits.tUnits[iUnitID].iColor
                        tFloor[iX][iY].iBright = CUnits.tUnits[iUnitID].iBright

                        if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect and tFloor[iX][iY].iWeight > 5 and not tFloor[iX][iY].bDamageCooldown then
                            if (CTime.unix() - tFloor[iX][iY].iClickTime)*1000 < tGame.DamageDelay then
                                CUnits.DamagePlayer(iUnitID)

                                tFloor[iX][iY].bDamageCooldown = true
                                AL.NewTimer(500, function()
                                    tFloor[iX][iY].bDamageCooldown = false
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end

CUnits.DamagePlayer = function(iUnitID)
    if not CUnits.tUnits[iUnitID].bDamageCooldown then
        CUnits.tUnits[iUnitID].bDamageCooldown = true
        local iColor = CUnits.tUnits[iUnitID].iColor
        CUnits.tUnits[iUnitID].iColor = CColors.MAGENTA
        AL.NewTimer(1000, function()
            CUnits.tUnits[iUnitID].bDamageCooldown = false
            CUnits.tUnits[iUnitID].iColor = iColor
        end)

        CGameMode.DamagePlayer()
    end
end

CUnits.Think = function()
    for iUnitID = 1, #CUnits.tUnits do
        if CUnits.tUnits[iUnitID] then
            CUnits.tUnits[iUnitID].iX = CUnits.tUnits[iUnitID].iX + CUnits.tUnits[iUnitID].iXVel
            CUnits.tUnits[iUnitID].iY = CUnits.tUnits[iUnitID].iY + CUnits.tUnits[iUnitID].iYVel

            if CUnits.tUnits[iUnitID].iX > tGame.Cols then CUnits.tUnits[iUnitID].iX = 0; end
            if CUnits.tUnits[iUnitID].iX < 0 then CUnits.tUnits[iUnitID].iX = tGame.Cols; end
            if CUnits.tUnits[iUnitID].iY > tGame.Rows then CUnits.tUnits[iUnitID].iY = 0; end
            if CUnits.tUnits[iUnitID].iY < 0 then CUnits.tUnits[iUnitID].iY = tGame.Rows; end
        end
    end     
end

CUnits.FadeKillUnit = function(iUnitID)
    AL.NewTimer(100, function()
        CUnits.tUnits[iUnitID].iBright = CUnits.tUnits[iUnitID].iBright - 1
        if CUnits.tUnits[iUnitID].iBright <= 0 then
            CUnits.tUnits[iUnitID] = nil
            return nil;
        end

        return 200
    end)
end
--//

--UTIL прочие утилиты
function CheckPositionClick(iStartX, iStartY, iSizeX, iSizeY)
    for iX = iStartX, iStartX + iSizeX - 1 do
        for iY = iStartY, iStartY + iSizeY - 1 do
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

        if click.Click then
           tFloor[click.X][click.Y].iClickTime = CTime.unix() 
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