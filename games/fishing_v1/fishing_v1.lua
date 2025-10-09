--[[
    Название: Рыбалка
    Автор: Avondale, дискорд - avonda
    Описание механики: 
        Игрокам нужно ловить рыбу на скорость, кидая удочку с края своей зоны
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
    TargetScore = 1,
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

    CPaint.PlayerZones()

    local bAllPlayers = true
    local iPlayerCount = 0
    for iPlayerID = 1, 6 do
        if not tPlayerInGame[iPlayerID] then 
            bAllPlayers = false
            tGameStats.Players[iPlayerID].Color = CColors.NONE
        else
            iPlayerCount = iPlayerCount + 1
            tGameStats.Players[iPlayerID].Color = CGameMode.tPlayerColors[iPlayerID]
        end
    end

    if not CGameMode.bCountDownStarted then    
        if (bAllPlayers and CGameMode.bCanAutoStart) or (bAnyButtonClick and iPlayerCount > 0) then
            CGameMode.StartCountDown(5)
        end
    end

    tGameResults.PlayersCount = iPlayerCount
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)  
    CPaint.PlayerZones()  
    CFish.Paint()
    CHook.Paint()
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

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.BLUE
CGameMode.tPlayerColors[2] = CColors.MAGENTA
CGameMode.tPlayerColors[3] = CColors.CYAN
CGameMode.tPlayerColors[4] = CColors.RED
CGameMode.tPlayerColors[5] = CColors.YELLOW
CGameMode.tPlayerColors[6] = CColors.GREEN

CGameMode.PLAYER_ZONE_SIZE_X = 0
CGameMode.PLAYER_ZONE_SIZE_Y = 0
CGameMode.HOOK_MAX_SIZE = 0
CGameMode.tPlayerCooldown = {}

CGameMode.InitGameMode = function()
    tGameStats.TargetScore = tConfig.TargetScore

    CGameMode.PLAYER_ZONE_SIZE_X = math.floor((tGame.iMaxX-tGame.iMinX+1)/3)
    CGameMode.PLAYER_ZONE_SIZE_Y = math.floor((tGame.iMaxY-tGame.iMinY+1)/3.5)
    CGameMode.HOOK_MAX_SIZE = math.floor((tGame.iMaxY-tGame.iMinY+1)/3)+1
end

CGameMode.Announcer = function()
    CAudio.PlayVoicesSync("fishing/fishing-rules.mp3")
    CAudio.PlayVoicesSync("choose-color.mp3")

    AL.NewTimer(CAudio.GetVoicesDuration("fishing/fishing-rules.mp3") * 1000 + 3000, function()
        CGameMode.bCanAutoStart = true
    end)    
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
   
    CGameMode.GameLoop() 
end

CGameMode.EndGame = function(iWinnerID)
    CGameMode.iWinnerID = iWinnerID

    tGameResults.Color = tGameStats.Players[CGameMode.iWinnerID].Color
    tGameResults.Won = true

    CAudio.StopBackground()
    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(tGameStats.Players[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.GameLoop = function()
    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
        CHook.Tick()
        return 200
    end)

    AL.NewTimer(150, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
        CFish.Tick()
        return 150
    end)

    AL.NewTimer(2500, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end

        local iY = tGame.CenterY-1
        local iX = 0
        local iVelX = 1
        if math.random(1,2) == 1 then
            iY = tGame.CenterY+1
            iX = tGame.Cols
            iVelX = -1
        end
        CFish.NewFish(iX, iY, iVelX)

        return math.random(500, 3000)
    end)
end

CGameMode.PlayerFire = function(iX, iY, iVelY, iPlayerID)
    if CGameMode.tPlayerCooldown[iPlayerID] then return; end

    CAudio.PlaySystemAsync("fishing/rod_throw.mp3")
    CHook.Launch(iX, iY, iVelY, iPlayerID)
    CGameMode.tPlayerCooldown[iPlayerID] = true
end

CGameMode.AddPlayerScore = function(iPlayerID, iScorePlus)
    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iScorePlus
    tGameResults.Score = tGameResults.Score + iScorePlus
    if tGameStats.Players[iPlayerID].Score >= tGameStats.TargetScore then
        CGameMode.EndGame(iPlayerID)
    end
end
--//

--HOOK
CHook = {}
CHook.tHooks = {}

CHook.Launch = function(iX, iY, iVelY, iPlayerID)
    local iHookID = #CHook.tHooks+1
    CHook.tHooks[iHookID] = {}
    CHook.tHooks[iHookID].iX = iX
    CHook.tHooks[iHookID].iY = iY
    CHook.tHooks[iHookID].iVelY = iVelY
    CHook.tHooks[iHookID].iSize = 0
    CHook.tHooks[iHookID].bBack = false
    CHook.tHooks[iHookID].iPlayerID = iPlayerID
    CHook.tHooks[iHookID].iFishID = 0
end

CHook.Tick = function()
    for iHookID = 1, #CHook.tHooks do
        if CHook.tHooks[iHookID] then
            if not CHook.tHooks[iHookID].bBack then
                CHook.tHooks[iHookID].iSize = CHook.tHooks[iHookID].iSize + 1
                if CHook.tHooks[iHookID].iSize == CGameMode.HOOK_MAX_SIZE then
                    CHook.tHooks[iHookID].bBack = true
                end
            else
                CHook.tHooks[iHookID].iSize = CHook.tHooks[iHookID].iSize - 1
                if CHook.tHooks[iHookID].iSize == -1 then
                    CGameMode.tPlayerCooldown[CHook.tHooks[iHookID].iPlayerID] = false

                    if CHook.tHooks[iHookID].iFishID ~= 0 then
                        CGameMode.AddPlayerScore(CHook.tHooks[iHookID].iPlayerID, 1)
                        CFish.tFish[CHook.tHooks[iHookID].iFishID] = nil
                    end

                    CHook.tHooks[iHookID] = nil
                end
            end

            if CHook.tHooks[iHookID] then
                if CHook.tHooks[iHookID].iFishID == 0 then
                    for iFishID = 1, #CFish.tFish do
                        if CFish.tFish[iFishID] and not CFish.tFish[iFishID].bCaught then
                            if CFish.tFish[iFishID].iY == CHook.tHooks[iHookID].iY+(CHook.tHooks[iHookID].iSize*CHook.tHooks[iHookID].iVelY)-CHook.tHooks[iHookID].iVelY then
                                if CFish.tFish[iFishID].iX >= CHook.tHooks[iHookID].iX-2 and CFish.tFish[iFishID].iX+CFish.FISH_SIZE <= CHook.tHooks[iHookID].iX+1 then
                                    CHook.tHooks[iHookID].iFishID = iFishID
                                    CFish.tFish[iFishID].bCaught = true
                                    CAudio.PlaySystemAsync(CAudio.CLICK)
                                    break;
                                end
                            end
                        end
                    end
                else
                    CFish.tFish[CHook.tHooks[iHookID].iFishID].iX = CHook.tHooks[iHookID].iX-3
                    CFish.tFish[CHook.tHooks[iHookID].iFishID].iY = CHook.tHooks[iHookID].iY+(CHook.tHooks[iHookID].iSize*CHook.tHooks[iHookID].iVelY)-CHook.tHooks[iHookID].iVelY
                end
            end
        end
    end    
end

CHook.Paint = function()
    local function hookPixel(iX, iY, iColor)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end

    for iHookID = 1, #CHook.tHooks do
        if CHook.tHooks[iHookID] then
            for iY = CHook.tHooks[iHookID].iY, CHook.tHooks[iHookID].iY+(CHook.tHooks[iHookID].iSize*CHook.tHooks[iHookID].iVelY)-CHook.tHooks[iHookID].iVelY, CHook.tHooks[iHookID].iVelY do
                hookPixel(CHook.tHooks[iHookID].iX, iY, CGameMode.tPlayerColors[CHook.tHooks[iHookID].iPlayerID])
            end

            hookPixel(CHook.tHooks[iHookID].iX-1, CHook.tHooks[iHookID].iY+(CHook.tHooks[iHookID].iSize*CHook.tHooks[iHookID].iVelY), CGameMode.tPlayerColors[CHook.tHooks[iHookID].iPlayerID])
            
            hookPixel(CHook.tHooks[iHookID].iX-2, CHook.tHooks[iHookID].iY+(CHook.tHooks[iHookID].iSize*CHook.tHooks[iHookID].iVelY)-CHook.tHooks[iHookID].iVelY, CGameMode.tPlayerColors[CHook.tHooks[iHookID].iPlayerID])
        end
    end
end
--//

--fish
CFish = {}
CFish.tFish = {}
CFish.FISH_SIZE = 1

CFish.NewFish = function(iX, iY, iVelX)
    local iFishID = #CFish.tFish+1
    CFish.tFish[iFishID] = {}
    CFish.tFish[iFishID].iX = iX
    CFish.tFish[iFishID].iY = iY
    CFish.tFish[iFishID].iVelX = iVelX
    CFish.tFish[iFishID].bCaught = false
end

CFish.Tick = function()
    for iFishID = 1, #CFish.tFish do
        if CFish.tFish[iFishID] then
            if not CFish.tFish[iFishID].bCaught then
                CFish.tFish[iFishID].iX = CFish.tFish[iFishID].iX + CFish.tFish[iFishID].iVelX
                if CFish.tFish[iFishID].iX < 0 or CFish.tFish[iFishID].iX > tGame.Cols then
                    CFish.tFish[iFishID] = nil
                end
            end
        end
    end
end

CFish.Paint = function()
    for iFishID = 1, #CFish.tFish do
        if CFish.tFish[iFishID] then
            for iX = CFish.tFish[iFishID].iX, CFish.tFish[iFishID].iX+CFish.FISH_SIZE do
                if tFloor[iX] then
                    tFloor[iX][CFish.tFish[iFishID].iY].iColor = CColors.WHITE
                    tFloor[iX][CFish.tFish[iFishID].iY].iBright = tConfig.Bright
                end
            end
        end
    end
end
--//

--paint
CPaint = {}

CPaint.PlayerZones = function()
    local iStartX = tGame.iMinX
    local iStartY = tGame.iMinY

    for iPlayerID = 1, 6 do
        local iBright = 1
        if iGameState == GAMESTATE_SETUP and tPlayerInGame[iPlayerID] then
            iBright = tConfig.Bright-2
        end

        local bZoneClick = false

        for iX = iStartX, iStartX + CGameMode.PLAYER_ZONE_SIZE_X-1 do
            for iY = iStartY, iStartY + CGameMode.PLAYER_ZONE_SIZE_Y-1 do
                tFloor[iX][iY].iColor = CGameMode.tPlayerColors[iPlayerID]
                tFloor[iX][iY].iBright = iBright

                if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                    bZoneClick = true
                end

                if iGameState == GAMESTATE_GAME then
                    if not tPlayerInGame[iPlayerID] then
                        tFloor[iX][iY].iColor = CColors.NONE
                    elseif not CGameMode.tPlayerCooldown[iPlayerID] then
                        if (iStartY > tGame.CenterY and (iY == iStartY or iY == iStartY+1)) or (iStartY < tGame.CenterY and (iY == iStartY + CGameMode.PLAYER_ZONE_SIZE_Y-1 or iY == iStartY + CGameMode.PLAYER_ZONE_SIZE_Y-2)) then
                            tFloor[iX][iY].iBright = tConfig.Bright+1
                            if tFloor[iX][iY].bDefect then
                                tFloor[iX][iY].iColor = CColors.NONE
                            elseif tFloor[iX][iY].bClick then
                                local iVelY = 1
                                local iLaunchY = iStartY + CGameMode.PLAYER_ZONE_SIZE_Y-1
                                if iStartY > tGame.CenterY then 
                                    iVelY = -1; 
                                    iLaunchY = iStartY;
                                end
                                CGameMode.PlayerFire(iX, iLaunchY, iVelY, iPlayerID)
                            end
                        end
                    end
                end
            end
        end

        if iGameState == GAMESTATE_SETUP then
            if bZoneClick then
                tPlayerInGame[iPlayerID] = true
            elseif not CGameMode.bCountDownStarted then
                tPlayerInGame[iPlayerID] = false
            end
        end

        iStartX = iStartX + CGameMode.PLAYER_ZONE_SIZE_X
        if iPlayerID == 3 then
            iStartX = tGame.iMinX
            iStartY = tGame.iMaxY - CGameMode.PLAYER_ZONE_SIZE_Y + 1
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

    bAnyButtonClick = true
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end