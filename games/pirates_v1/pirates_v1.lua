--[[
    Название: Пираты (карибского моря)
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Игроки управляют кораблями в море, стреляют в корабли друг друга из пушек и уклоняются от выстрелов
        Побеждает тот кто остаётся последним выжившим
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
local tPlayerInGame = {}

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
    ScoreboardVariant = 6,
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
    iPlayerID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tTeamColors = {}
tTeamColors[1] = CColors.GREEN
tTeamColors[2] = CColors.MAGENTA
tTeamColors[3] = CColors.WHITE
tTeamColors[4] = CColors.YELLOW
tTeamColors[5] = CColors.CYAN

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

    if tGame.StartPositions == nil then
        tGame.StartPositions = {}

        local iMinX = 1
        local iMinY = 1
        local iMaxX = tGame.Cols-1
        local iMaxY = tGame.Rows
        if AL.NFZ.bLoaded then
            iMinX = AL.NFZ.iMinX
            iMinY = AL.NFZ.iMinY
            iMaxX = AL.NFZ.iMaxX
            iMaxY = AL.NFZ.iMaxY
        end

        tGame.StartPositionSizeX = math.floor((iMaxX-iMinX)/tConfig.PlayerCount)
        if tGame.StartPositionSizeX < 4 then tGame.StartPositionSizeX = 4; end
        if tGame.StartPositionSizeX > 10 then tGame.StartPositionSizeX = 10; end
        tGame.StartPositionSizeY = iMaxY - iMinY + 1

        local iX = iMinX
        local iY = iMinY

        for iPlayerID = 1, tConfig.PlayerCount do
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = iX
            tGame.StartPositions[iPlayerID].Y = iY
            tGame.StartPositions[iPlayerID].Color = tTeamColors[iPlayerID]

            iX = iX + tGame.StartPositionSizeX + 1
            if iX + tGame.StartPositionSizeX-1 > iMaxX then
                break;
            end
        end
    else
        for iPlayerID = 1, #tGame.StartPositions do
            tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
        end 
    end   

    tGameStats.TargetScore = tConfig.ShipHealth

    CShips.Init()
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
    SetGlobalColorBright(CColors.BLUE, tConfig.Bright-2) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.BLUE, tConfig.Bright, true)

   local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright)
        end
    end

    if (iPlayersReady > 1 and bAnyButtonClick) or (iPlayersReady  == #tGame.StartPositions and CGameMode.bCanAutoStart) then
        bAnyButtonClick = false

        CGameMode.iAlivePlayerCount = iPlayersReady

        iGameState = GAMESTATE_GAME
        CShips.Spawn()
        CGameMode.Thinkers()
        CGameMode.StartCountDown(5)
    end    
end

function GameTick()
    SetGlobalColorBright(CColors.BLUE, tConfig.Bright-1) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.NONE, 0, false) 

    CPaint.Ships()
    CPaint.Projectiles()
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
CGameMode.bCanAutoStart = false
CGameMode.bGameStarted = false

CGameMode.iAlivePlayerCount = 0
CGameMode.iWinnerID = 0

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("pirates/pirates_guide.mp3")
    CAudio.PlayVoicesSync("choose-color.mp3")
    --CAudio.PlayVoicesSync("press-button-for-start.mp3")

    AL.NewTimer(CAudio.GetVoicesDuration("pirates/pirates_guide.mp3")*1000 + 3000, function()
        CGameMode.bCanAutoStart = true
    end)
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.PlaySystemSyncFromScratch("")
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

CGameMode.Thinkers = function()
    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CShips.ShipThinker()
        return 200
    end)

    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        CProjectiles.ProjectileThink()
        return 100
    end)
end

CGameMode.StartGame = function()
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    CGameMode.bGameStarted = true
end

CGameMode.EndGame = function()
    for iShipId = 1, #CShips.tShips do
        if CShips.tShips[iShipId].bAlive then
            CGameMode.iWinnerID = CShips.tShips[iShipId].iPlayerID
            break;
        end
    end

    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end) 
end
--//

--SHIPS
CShips = {}
CShips.tShips = {}
CShips.tPlayerIDToShipId = {}

CShips.Init = function()
    CShips.SHIP_SIZE_X = 3
    CShips.SHIP_SIZE_Y = math.floor(tGame.StartPositionSizeY/2)
    CShips.SHIP_HEALTH = tConfig.ShipHealth
    CShips.PLAYER_CONTROL_Y_OFFSET = -math.floor(CShips.SHIP_SIZE_Y/2)
end

CShips.Spawn = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CShips.NewShip(iPlayerID)
        end
    end
end

CShips.NewShip = function(iPlayerID)
    local iShipId = #CShips.tShips+1
    CShips.tShips[iShipId] = {}
    CShips.tShips[iShipId].iPlayerID = iPlayerID
    CShips.tShips[iShipId].iX = tGame.StartPositions[iPlayerID].X + math.floor(tGame.StartPositionSizeX/2)
    CShips.tShips[iShipId].iY = 1
    CShips.tShips[iShipId].iTargetY = 1
    CShips.tShips[iShipId].iLastControlX = 0
    CShips.tShips[iShipId].iLastControlY = 0
    CShips.tShips[iShipId].iHealth = CShips.SHIP_HEALTH
    CShips.tShips[iShipId].bAlive = true
    CShips.tShips[iShipId].bLeftCanShoot = true
    CShips.tShips[iShipId].bRightCanShoot = true
    CShips.tShips[iShipId].bOnFire = false

    if iPlayerID == 1 then CShips.tShips[iShipId].iX = tGame.StartPositions[iPlayerID].X + 2 end
    if iPlayerID == #tGame.StartPositions then CShips.tShips[iShipId].iX = tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-2 end

    CShips.tPlayerIDToShipId[iPlayerID] = iShipId
    tGameStats.Players[CShips.tShips[iShipId].iPlayerID].Score = CShips.tShips[iShipId].iHealth
end

CShips.ShipThinker = function()
    for iShipId = 1, #CShips.tShips do
        if CShips.tShips[iShipId] and CShips.tShips[iShipId].bAlive then
            if CShips.tShips[iShipId].iTargetY ~= CShips.tShips[iShipId].iY then
                if CShips.tShips[iShipId].iY > CShips.tShips[iShipId].iTargetY then
                    CShips.tShips[iShipId].iY = CShips.tShips[iShipId].iY - 1
                else
                    CShips.tShips[iShipId].iY = CShips.tShips[iShipId].iY + 1
                end
            end
        end
    end
end

CShips.PlayerControl = function(iPlayerID, iX, iY)
    local iShipId = CShips.tPlayerIDToShipId[iPlayerID]
    
    if CShips.tShips[iShipId].iLastControlX == 0 or (tFloor[CShips.tShips[iShipId].iLastControlX][CShips.tShips[iShipId].iLastControlY].iWeight <= tFloor[iX][iY].iWeight) or tFloor[CShips.tShips[iShipId].iLastControlX][CShips.tShips[iShipId].iLastControlY].bDefect then
        CShips.tShips[iShipId].iLastControlX = iX
        CShips.tShips[iShipId].iLastControlY = iY

        local iNewTargetY = iY+CShips.PLAYER_CONTROL_Y_OFFSET

        if iNewTargetY ~= CShips.tShips[iShipId].iTargetY and iNewTargetY+1 ~= CShips.tShips[iShipId].iTargetY and iNewTargetY-1 ~= CShips.tShips[iShipId].iTargetY then
            CShips.tShips[iShipId].iTargetY = iNewTargetY

            if CShips.tShips[iShipId].iTargetY < 1 then CShips.tShips[iShipId].iTargetY = 1 end
            if CShips.tShips[iShipId].iTargetY > tGame.StartPositionSizeY-CShips.SHIP_SIZE_Y+1 then CShips.tShips[iShipId].iTargetY = tGame.StartPositionSizeY-CShips.SHIP_SIZE_Y+1 end
        end
    end
end

CShips.ShipShoot = function(iShipId, iX, iY, bLeftSide)
    if bLeftSide then
        if CShips.tShips[iShipId].bLeftCanShoot then
            CShips.tShips[iShipId].bLeftCanShoot = false
            AL.NewTimer(2000, function()
                CShips.tShips[iShipId].bLeftCanShoot = true
            end) 
        else
            return false
        end
    else
        if CShips.tShips[iShipId].bRightCanShoot then
            CShips.tShips[iShipId].bRightCanShoot = false
            AL.NewTimer(2000, function()
                CShips.tShips[iShipId].bRightCanShoot = true
            end) 
        else
            return false
        end
    end

    local iVelX = -1
    if iX > CShips.tShips[iShipId].iX then
        iVelX = 1
    end
    CProjectiles.NewProjectile(iX, iY, iVelX, 0)

    CAudio.PlaySystemAsync("pirates/cannon.mp3")
    return true
end

CShips.DamageShip = function(iShipId)
    CShips.tShips[iShipId].iHealth = CShips.tShips[iShipId].iHealth - 1
    tGameStats.Players[CShips.tShips[iShipId].iPlayerID].Score = CShips.tShips[iShipId].iHealth

    if CShips.tShips[iShipId].iHealth == 0 then
        CAudio.PlaySystemAsync("pirates/ship_dead.mp3")
        CShips.tShips[iShipId].bAlive = false
        CGameMode.iAlivePlayerCount = CGameMode.iAlivePlayerCount - 1
        if CGameMode.iAlivePlayerCount == 1 then
            CGameMode.EndGame()
        end
    else
        CAudio.PlaySystemAsync("pirates/ship_hit.mp3")

        CShips.tShips[iShipId].bOnFire = true
        AL.NewTimer(250, function()
            CShips.tShips[iShipId].bOnFire = false
        end)
    end
end
--//

--Projectiles
CProjectiles = {}
CProjectiles.tProjectiles = {}

CProjectiles.NewProjectile = function(iX, iY, iVelX, iVelY)
    local iProjectileId = #CProjectiles.tProjectiles+1
    CProjectiles.tProjectiles[iProjectileId] = {}
    CProjectiles.tProjectiles[iProjectileId].iX = iX
    CProjectiles.tProjectiles[iProjectileId].iY = iY
    CProjectiles.tProjectiles[iProjectileId].iVelX = iVelX
    CProjectiles.tProjectiles[iProjectileId].iVelY = iVelY
end

CProjectiles.ProjectileThink = function()
    for iProjectileId = 1, #CProjectiles.tProjectiles do
        if CProjectiles.tProjectiles[iProjectileId] then
            CProjectiles.tProjectiles[iProjectileId].iX = CProjectiles.tProjectiles[iProjectileId].iX + CProjectiles.tProjectiles[iProjectileId].iVelX
            CProjectiles.tProjectiles[iProjectileId].iY = CProjectiles.tProjectiles[iProjectileId].iY + CProjectiles.tProjectiles[iProjectileId].iVelY

            if CProjectiles.tProjectiles[iProjectileId].iX < 1 or CProjectiles.tProjectiles[iProjectileId].iX > tGame.Cols or
            CProjectiles.tProjectiles[iProjectileId].iY < 1 or CProjectiles.tProjectiles[iProjectileId].iY > tGame.Rows then
                CProjectiles.tProjectiles[iProjectileId] = nil
            else
                CProjectiles.ProjectileCollision(iProjectileId)
            end
        end
    end
end

CProjectiles.ProjectileCollision = function(iProjectileId)
    for iShipId = 1, #CShips.tShips do
        if CShips.tShips[iShipId] and CShips.tShips[iShipId].bAlive then
            if CProjectiles.tProjectiles[iProjectileId].iX == CShips.tShips[iShipId].iX + math.floor(CShips.SHIP_SIZE_X/2) then
                if CProjectiles.tProjectiles[iProjectileId].iY >= CShips.tShips[iShipId].iY and CProjectiles.tProjectiles[iProjectileId].iY <= CShips.tShips[iShipId].iY + CShips.SHIP_SIZE_Y-1 then
                    CShips.DamageShip(iShipId)
                    CProjectiles.tProjectiles[iProjectileId] = nil
                    return;
                end
            end
        end
    end

    for iProjectileId2 = 1, #CProjectiles.tProjectiles do
        if iProjectileId ~= iProjectileId2 and CProjectiles.tProjectiles[iProjectileId2] then
            if CProjectiles.tProjectiles[iProjectileId].iX == CProjectiles.tProjectiles[iProjectileId2].iX and CProjectiles.tProjectiles[iProjectileId].iY == CProjectiles.tProjectiles[iProjectileId2].iY then
                CProjectiles.tProjectiles[iProjectileId2] = nil

                CProjectiles.tProjectiles[iProjectileId].iVelX = 0
                CProjectiles.tProjectiles[iProjectileId].iVelY = 0

                --sound projectiles hit

                AL.NewTimer(250, function()
                    CProjectiles.tProjectiles[iProjectileId] = nil
                end)

                return;
            end
        end
    end
end
--//

--PAINT
CPaint = {}

CPaint.PlayerZone = function(iPlayerID, iBright)
    for i = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
        for j = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) then     
                tFloor[i][j].iColor = tGame.StartPositions[iPlayerID].Color
                tFloor[i][j].iBright = iBright            
                tFloor[i][j].iPlayerID = iPlayerID          
            end            
        end
    end
end

CPaint.Ships = function()
    for iShipId = 1, #CShips.tShips do
        for iX = CShips.tShips[iShipId].iX, CShips.tShips[iShipId].iX + CShips.SHIP_SIZE_X-1 do
            for iY = CShips.tShips[iShipId].iY, CShips.tShips[iShipId].iY + CShips.SHIP_SIZE_Y-1 do
                if tFloor[iX] and tFloor[iX][iY] then
                    local iColor = tGame.StartPositions[CShips.tShips[iShipId].iPlayerID].Color
                    local iBright = tConfig.Bright

                    if CShips.tShips[iShipId].bAlive then
                        if iY ~= CShips.tShips[iShipId].iY and iY ~= CShips.tShips[iShipId].iY + CShips.SHIP_SIZE_Y-1 then
                            if iX == CShips.tShips[iShipId].iX + math.floor(CShips.SHIP_SIZE_X/2) then
                                iBright = iBright-2
                                if CShips.tShips[iShipId].bOnFire then
                                    iColor = CColors.RED
                                end
                            end
                        else
                            if iX == CShips.tShips[iShipId].iX or iX == CShips.tShips[iShipId].iX+CShips.SHIP_SIZE_X-1 then
                                iColor = CColors.BLUE
                                iBright = iBright-1
                            end
                        end 

                        if iGameState == GAMESTATE_GAME and CGameMode.bGameStarted then
                            if (iX == CShips.tShips[iShipId].iX and iShipId ~= 1 and CShips.tShips[iShipId].bLeftCanShoot) or (iX == CShips.tShips[iShipId].iX+CShips.SHIP_SIZE_X-1 and iShipId ~= #CShips.tShips and CShips.tShips[iShipId].bRightCanShoot) then
                                if iY == CShips.tShips[iShipId].iY + math.floor(CShips.SHIP_SIZE_Y/2)-1 or iY == CShips.tShips[iShipId].iY + math.floor(CShips.SHIP_SIZE_Y/2)+1 then
                                    iColor = CColors.RED

                                    local bLeftSide = true
                                    if iX > CShips.tShips[iShipId].iX then bLeftSide = false; end

                                    if not tFloor[iX][iY].bDefect and tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
                                        CShips.ShipShoot(iShipId, iX, iY, bLeftSide)
                                    end
                                end
                            end
                        end
                    else
                        iColor = CColors.RED
                        iBright = 1
                    end

                    tFloor[iX][iY].iColor = iColor
                    tFloor[iX][iY].iBright = iBright
                end
            end
        end
    end
end

CPaint.Projectiles = function()
    for iProjectileId = 1, #CProjectiles.tProjectiles do
        if CProjectiles.tProjectiles[iProjectileId] then
            tFloor[CProjectiles.tProjectiles[iProjectileId].iX][CProjectiles.tProjectiles[iProjectileId].iY].iColor = CColors.RED
            tFloor[CProjectiles.tProjectiles[iProjectileId].iX][CProjectiles.tProjectiles[iProjectileId].iY].iBright = tConfig.Bright+1
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

            return
        end

        if iGameState == GAMESTATE_GAME and click.Click and not tFloor[click.X][click.Y].bDefect and tFloor[click.X][click.Y].iPlayerID > 0 and tPlayerInGame[tFloor[click.X][click.Y].iPlayerID] then
            CShips.PlayerControl(tFloor[click.X][click.Y].iPlayerID, click.X, click.Y)
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

    if click.Click and not tButtons[click.Button].bDefect then
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