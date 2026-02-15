--[[
    Название: Перебежка
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
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

local iTotalButtons = 0
local iDeffectButtons = 0

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
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 8,
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
    iObjectId = 0,
    tSafeZoneButton = nil,
    bAnimated = false
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
    bGoal = false,
    bSafeZoneOn = false,
    iSafeZoneX = 0,
    iSafeZoneY = 0,
    iSafeZoneBright = 0
}

local tPlayerInGame = {}
local bAnyButtonClick = false

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}    
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct) 
        end
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

    if tConfig.LasersCount and tConfig.LasersCount > 0 and AL.InitLasers then
        AL.InitLasers(tGame)
    end

    tGame.SafeZoneSizeX = 2
    tGame.SafeZoneSizeY = 2

    if tGame.Buttons == nil or tGame.Buttons == {} or tGame.DisableButtonsGameplay then
        GenerateButtons()
    end

    LoadButtons()

    tGameResults.PlayersCount = tConfig.PlayerCount

    tGame.LavaObjects = {}
    tGame.LavaObjects[1] = 
    {
        {
            PosX = 1,
            PosY = 1,
            SizeX = tGame.Cols,
            SizeY = 2,
            VelX = 0,
            VelY = 1,
            IgnoreBoundsX = false,
            IgnoreBoundsY = false,
            Collision = false
        }
    }
    tGame.LavaObjects[2] = 
    {
        {
            PosX = 1,
            PosY = 1,
            SizeX = 2,
            SizeY = tGame.Rows,
            VelX = 1,
            VelY = 0,
            IgnoreBoundsX = false,
            IgnoreBoundsY = false,
            Collision = false
        }
    }
    tGame.LavaObjects[3] = 
    {
        {
            PosX = 1,
            PosY = -1,
            SizeX = 3,
            SizeY = tGame.Cols,
            VelX = -1,
            VelY = 0,
            IgnoreBoundsX = true,
            IgnoreBoundsY = true,
            Collision = false,
            Diagonal = true,
            DiagonalDirection = 1
        }
    }
    tGame.LavaObjects[4] = 
    {
        {
            PosX = 3,
            PosY = -1,
            SizeX = 3,
            SizeY = tGame.Cols,
            VelX = -1,
            VelY = 0,
            IgnoreBoundsX = true,
            IgnoreBoundsY = true,
            Collision = false,
            Diagonal = true,
            DiagonalDirection = -1
        }
    }
    tGame.LavaObjects[5] = 
    {
        {
            PosX = 1,
            PosY = 1,
            SizeX = tGame.Cols,
            SizeY = 2,
            VelX = 0,
            VelY = 1,
            IgnoreBoundsX = false,
            IgnoreBoundsY = false,
            Collision = false
        },
        {
            PosX = 1,
            PosY = 1,
            SizeX = 2,
            SizeY = tGame.Rows,
            VelX = 1,
            VelY = 0,
            IgnoreBoundsX = false,
            IgnoreBoundsY = false,
            Collision = false
        }
    }

    CGameMode.InitGameMode()
    CGameMode.Announcer()    
end

function LoadButtons()
    tButtons = {}
    local iPrevButton = -1
    for _, iButton in pairs(tGame.Buttons) do
        tButtons[iButton] = CHelp.ShallowCopy(tButtonStruct)
        iTotalButtons = iTotalButtons + 1

        local iX = iButton
        local iY = 1

        local iSide = 1

        if iX > tGame.Cols*2 + tGame.Rows then
            iX = 1
            iY = tGame.Rows - (iButton - (tGame.Cols*2 + tGame.Rows)) + 1
            iSide = 4
        elseif iX > tGame.Cols + tGame.Rows then
            iX = tGame.Cols - (iButton - (tGame.Cols + tGame.Rows)) + 1
            iY = tGame.Rows - (tGame.SafeZoneSizeY/2)
            iSide = 3
        elseif iX > tGame.Cols then
            iX = tGame.Cols - (tGame.SafeZoneSizeX/2)
            iY = iButton - tGame.Cols 
            iSide = 2
        end

        for _, iButton2 in pairs(tGame.Buttons) do
            if iButton ~= iButton2 and tButtons[iButton2] and AL.RectIntersects(iX, iY, tGame.SafeZoneSizeX, tButtons[iButton2].iSafeZoneX, tButtons[iButton2].iSafeZoneY, tGame.SafeZoneSizeX) then
                if iY < tButtons[iButton2].iSafeZoneY then
                    iY = iY - 1
                elseif iY > tButtons[iButton2].iSafeZoneY then
                    iY = iY + 1
                elseif iX < tButtons[iButton2].iSafeZoneX then
                    iX = iX - 1
                else
                    iX = iX + 1
                end
            end
        end

        if iX >= tGame.iMaxX then
            iX = tGame.iMaxX-1 
        end
        if iY >= tGame.iMaxY then
            iY = tGame.iMaxY-1
        end
        if iX < tGame.iMinX then
            iX = tGame.iMinX
        end
        if iY < tGame.iMinY then
            iY = tGame.iMinY
        end

        tButtons[iButton].iSafeZoneX = iX
        tButtons[iButton].iSafeZoneY = iY
        tButtons[iButton].iSide = iSide
    end
end

function GenerateButtons()
    tGame.Buttons = {}
    tGame.DisableButtonsGameplay = true
    for iButton = 2, (tGame.Cols + tGame.Rows)*2, 4 do
        tGame.Buttons[#tGame.Buttons+1] = iButton
    end
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

    local iButton = 0
    local iPosI = 1
    for iPos, tPos in pairs(tButtons) do
        if not tPos.bDefect then
            --iPosI = iPosI + 1
            --if iPosI % 2 ~= 0 then 
                iButton = iButton + 1
                --if iButton > tConfig.MaxPlayerCount then break; end

                local iBright = CColors.BRIGHT15
                if CGameMode.SafeZoneClicked(tPos) or (bCountDownStarted and tPlayerInGame[iPos]) then
                    iBright = tConfig.Bright
                    iPlayersReady = iPlayersReady + 1
                    tPlayerInGame[iPos] = true
                    tPos.bSafeZoneOn = true
                    tPos.iSafeZoneBright = tConfig.Bright
                else
                    tPlayerInGame[iPos] = false
                    tPos.bSafeZoneOn = false
                end

                CPaint.SafeZone(tPos, iBright)
            --end
        end
    end

    if not bCountDownStarted and iPlayersReady > 0 and CGameMode.bCanStart then
        bCountDownStarted = true
        bAnyButtonClick = false
        CGameMode.StartCountDown(tConfig.GameCountdown)
    elseif bCountDownStarted then
        CGameMode.iRealPlayerCount = iPlayersReady
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Lava()
    CPaint.Buttons()
    CPaint.SafeZones()
end

function PostGameTick()

end

function RangeFloor(setPixel, setButton, setLasers)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end

    if setLasers and AL.bRoomHasLasers then
        AL.SetLasers(setLasers)
    end
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.bVictory = false
CGameMode.iRealPlayerCount = 0
CGameMode.bCanStart = false

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = #tGame.LavaObjects
end

CGameMode.Announcer = function()
    if not tConfig.SkipTutorial then 
        CAudio.PlayVoicesSync("dash/perebejka-game.mp3")

        local iAudioDur = 0

        if not tGame.DisableButtonsGameplay then
            CAudio.PlayVoicesSync("dash/dash_rules_default.mp3")
            CAudio.PlayVoicesSync("stand_on_green_and_get_ready.mp3")
            iAudioDur = (CAudio.GetVoicesDuration("dash/dash_rules_default.mp3"))*1000 
        else
            CAudio.PlayVoicesSync("dash/dash_rules_nobuttons.mp3")
            CAudio.PlayVoicesSync("stand_on_green_and_get_ready.mp3")
            iAudioDur = (CAudio.GetVoicesDuration("dash/dash_rules_nobuttons.mp3"))*1000
        end

        AL.NewTimer(iAudioDur + CAudio.GetVoicesDuration("stand_on_green_and_get_ready.mp3")*1000, function()
            CGameMode.bCanStart = true
        end)
    else
        CAudio.PlayVoicesSync("stand_on_green_and_get_ready.mp3")
        CGameMode.bCanStart = true
    end
end

CGameMode.StartCountDown = function(iCountDownTime)
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
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    iGameState = GAMESTATE_GAME

    if CGameMode.iRealPlayerCount > 8 then
        CGameMode.iRealPlayerCount = 8
    end

    for _, tButton in pairs(tButtons) do
        if tButton.bSafeZoneOn then
            CGameMode.ResetSafeZoneTimer(tButton)
        end
    end

    tGameStats.TotalStars = #tGame.LavaObjects*(CGameMode.iRealPlayerCount*tConfig.StarsPerPlayer)
    tGameStats.TotalLives = tConfig.Lives
    tGameStats.CurrentLives = tConfig.Lives
    --tGameStats.TotalLives = math.ceil(#tGame.LavaObjects*CGameMode.iRealPlayerCount*tConfig.HealthMultiplier)
    --tGameStats.CurrentLives = math.ceil(#tGame.LavaObjects*CGameMode.iRealPlayerCount*tConfig.HealthMultiplier)

    for i = 1, CGameMode.iRealPlayerCount do
        CGameMode.AssignRandomGoal()
    end

    CLava.LoadMap()
    AL.NewTimer(tConfig.LavaFrameDelay, function()
        if iGameState == GAMESTATE_GAME then
            CLava.UpdateObjects()
            return tConfig.LavaFrameDelay
        end

        return nil
    end)

    CGameMode.RandomLasers(math.random(math.ceil(tConfig.LasersCount/2), tConfig.LasersCount))
end

CGameMode.SafeZoneClicked = function(tButton)
    if tButton.bDefect then return false end 

    for iX = tButton.iSafeZoneX, tButton.iSafeZoneX + tGame.SafeZoneSizeX-1 do
        for iY = tButton.iSafeZoneY, tButton.iSafeZoneY + tGame.SafeZoneSizeY-1 do
            if tFloor[iX] and tFloor[iX][iY] and tFloor[iX][iY].bClick then
                return true
            end
        end
    end

    return false
end

CGameMode.ReachGoal = function(tButton)
    tGameStats.CurrentStars = tGameStats.CurrentStars + 1 

    if tGameStats.CurrentStars == tGameStats.TotalStars then
        CGameMode.EndGame(true)
    else
        CAudio.PlaySystemAsync(CAudio.CLICK)
        CGameMode.AssignRandomGoal()
        tButton.bGoal = false
        CGameMode.ResetSafeZoneTimer(tButton)

        if tGameStats.CurrentStars % (CGameMode.iRealPlayerCount*tConfig.StarsPerPlayer) == 0 then
            CGameMode.NextStage()
        end
    end
end

CGameMode.AssignRandomGoal = function(iAttemptCount)
    if iAttemptCount == nil then iAttemptCount = 0 end
    if iAttemptCount >= 20 then CLog.print("cant find empty button to asign a goal"); return; end

    local iButtonId = tGame.Buttons[math.random(1, #tGame.Buttons)]
    if tButtons[iButtonId] and not tButtons[iButtonId].bDefect and not tButtons[iButtonId].bGoal and (not tButtons[iButtonId].bSafeZoneOn or iAttemptCount > 10) then
        tButtons[iButtonId].bGoal = true
        tButtons[iButtonId].bSafeZoneOn = true
        tButtons[iButtonId].iSafeZoneBright = tConfig.Bright
    else
        CGameMode.AssignRandomGoal(iAttemptCount + 1)
    end
end

CGameMode.ResetSafeZoneTimer = function(tButton)
    local iTime = tConfig.SafeZoneResetTimer

    AL.NewTimer(1000, function()
        if tConfig.HardZoneDespawn or not CGameMode.SafeZoneClicked(tButton) then
            iTime = iTime - 1
            if tButton.iSafeZoneBright > 1 then
                tButton.iSafeZoneBright = tButton.iSafeZoneBright - 1
            end

            if iTime > 0 then 
                return 1000
            else
                tButton.bSafeZoneOn = false
                return nil
            end
        else
            return 1000
        end
    end)
end

CGameMode.NextStage = function()
    CAudio.PlaySystemAsync(CAudio.STAGE_DONE)
      
    if tGameStats.StageNum < tGameStats.TotalStages then
        tGameStats.StageNum = tGameStats.StageNum + 1
        if tConfig.RandomLevels then
            CLava.iMapId = math.random(1, #tGame.LavaObjects)
        else
            CLava.iMapId = tGameStats.StageNum
        end
        CLava.LoadMap()

        CGameMode.SwitchAllLasers(false)
        CGameMode.RandomLasers(math.random(math.ceil(tConfig.LasersCount/2), tConfig.LasersCount))

        CLava.bCooldown = true
        AL.NewTimer(tConfig.StageSwitchHitRegDelay, function()
            CLava.bCooldown = false
        end)
    end
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    CAudio.StopBackground()
    iGameState = GAMESTATE_POSTGAME
    tGameResults.Won = bVictory

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)

    if bVictory then
        CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
        CAudio.PlayVoicesSync(CAudio.VICTORY)
        tGameResults.Color = CColors.GREEN
        SetGlobalColorBright(CColors.GREEN, tConfig.Bright)
        CGameMode.SwitchAllLasers(true)
    else
        CAudio.PlaySystemSync(CAudio.GAME_OVER)
        CAudio.PlayVoicesSync(CAudio.DEFEAT)
        tGameResults.Color = CColors.RED
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
    end
end

CGameMode.SwitchAllLasers = function(bOn)
    if AL.bRoomHasLasers then
        for iLine = 1, AL.Lasers.iLines do
            for iRow = 1, AL.Lasers.iRows do
                AL.SwitchLaser(iLine, iRow, bOn)
            end
        end
    end
end

CGameMode.RandomLasers = function(iCount)
    if AL.bRoomHasLasers then
        for i = 1, iCount do
            AL.SwitchLaser(math.random(1, AL.Lasers.iLines), math.random(1, AL.Lasers.iLines), true)
        end
    end
end
--//

--LAVA
CLava = {}
CLava.iMapId = 1
CLava.tMapObjects = {}
CLava.iColor = CColors.RED
CLava.bCooldown = false

CLava.tMapObjectStruct = 
{
    iX = 0,
    iY = 0,
    iSizeX = 0,
    iSizeY = 0,
    iVelX = 0,
    iVelY = 0,
    bIgnoreBoundsX = false,
    bIgnoreBoundsY = false,
    bCollision = false,
    bDiagonal = false,
    iDiagonalDirection = 0
}

CLava.LoadMap = function()
    CLava.tMapObjects = {}

    for iObjectId = 1, #tGame.LavaObjects[CLava.iMapId] do
        CLava.tMapObjects[iObjectId] = CHelp.ShallowCopy(CLava.tMapObjectStruct)
        CLava.tMapObjects[iObjectId].iX = tGame.LavaObjects[CLava.iMapId][iObjectId].PosX
        CLava.tMapObjects[iObjectId].iY = tGame.LavaObjects[CLava.iMapId][iObjectId].PosY
        CLava.tMapObjects[iObjectId].iSizeX = tGame.LavaObjects[CLava.iMapId][iObjectId].SizeX
        CLava.tMapObjects[iObjectId].iSizeY = tGame.LavaObjects[CLava.iMapId][iObjectId].SizeY
        CLava.tMapObjects[iObjectId].iVelX = tGame.LavaObjects[CLava.iMapId][iObjectId].VelX
        CLava.tMapObjects[iObjectId].iVelY = tGame.LavaObjects[CLava.iMapId][iObjectId].VelY
        CLava.tMapObjects[iObjectId].bIgnoreBoundsX = tGame.LavaObjects[CLava.iMapId][iObjectId].IgnoreBoundsX
        CLava.tMapObjects[iObjectId].bIgnoreBoundsY = tGame.LavaObjects[CLava.iMapId][iObjectId].IgnoreBoundsY
        CLava.tMapObjects[iObjectId].bCollision = tGame.LavaObjects[CLava.iMapId][iObjectId].Collision
        CLava.tMapObjects[iObjectId].bDiagonal = tGame.LavaObjects[CLava.iMapId][iObjectId].Diagonal
        CLava.tMapObjects[iObjectId].iDiagonalDirection = tGame.LavaObjects[CLava.iMapId][iObjectId].DiagonalDirection
    end
end

CLava.UpdateObjects = function()
    for iObjectId = 1, #CLava.tMapObjects do
        if CLava.tMapObjects[iObjectId] then
            CLava.ObjectMovement(iObjectId)
        end
    end
end

CLava.ObjectMovement = function(iObjectId)
    local tObject = CLava.tMapObjects[iObjectId]

    local iX = tObject.iX + tObject.iVelX
    local iY = tObject.iY + tObject.iVelY

    local bCantMoveX = false
    local bCantMoveY = false
    for iXCheck = iX, iX + tObject.iSizeX-1 do
        for iYCheck = iY, iY + tObject.iSizeY-1 do
            if not tFloor[iXCheck] and not tObject.bIgnoreBoundsX then 
                bCantMoveX = true
            end
            if tFloor[iXCheck] and not tFloor[iXCheck][iYCheck] and not tObject.bIgnoreBoundsY then
                bCantMoveY = true
            end

            if tObject.bCollision and (tFloor[iXCheck] and tFloor[iXCheck][iYCheck]) and tFloor[iXCheck][iYCheck].iObjectId > 0 and tFloor[iXCheck][iYCheck].iObjectId ~= iObjectId then
                --collision
            end

            if tObject.bDiagonal then
                if 
                    tObject.iDiagonalDirection == 1 and (iX < -tObject.iSizeY + tObject.iSizeX or iX > tGame.Cols - tObject.iSizeX)
                or 
                    tObject.iDiagonalDirection == -1 and (iX < tObject.iSizeX+1 or iX > tGame.Cols + tObject.iSizeY - tObject.iSizeX)
                then
                    bCantMoveX = true
                    break
                end
            end

            if bCantMoveX and bCantMoveY then break end
        end
    end
    if bCantMoveX then
        tObject.iVelX = -tObject.iVelX
    end
    if bCantMoveY then
        tObject.iVelY = -tObject.iVelY
    end

    tObject.iX = tObject.iX + tObject.iVelX
    tObject.iY = tObject.iY + tObject.iVelY
end

CLava.PlayerStep = function()
    if CLava.bCooldown then return end
    CLava.bCooldown = true
    CLava.iColor = CColors.MAGENTA

    tGameStats.CurrentLives = tGameStats.CurrentLives - 1
    if tGameStats.CurrentLives == 0 then
        CGameMode.EndGame(false)
    else
        CAudio.PlaySystemAsync(CAudio.MISCLICK)
        AL.NewTimer(tConfig.LavaCooldown, function()
            CLava.bCooldown = false
            CLava.iColor = CColors.RED
        end)
    end
end

CLava.PlayerStepDelay = function(iX, iY)
    if CLava.bCooldown or tFloor[iX][iY].bDelayed then return end
    tFloor[iX][iY].bDelayed = true

    AL.NewTimer(tGame.BurnDelay, function()
        if tFloor[iX][iY].bClick and (tFloor[iX][iY].tSafeZoneButton == nil or not tFloor[iX][iY].tSafeZoneButton.bSafeZoneOn) then
            CLava.PlayerStep()

            CPaint.AnimatePixelFlicker(iX, iY, 3, CColors.RED)
        end
        tFloor[iX][iY].bDelayed = false
    end)
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 100

CPaint.Lava = function()
    for iObjectId = 1, #CLava.tMapObjects do
        if CLava.tMapObjects[iObjectId] then
            CPaint.LavaObject(iObjectId)
        end
    end
end

CPaint.LavaObject = function(iObjectId)
    local iXStart = CLava.tMapObjects[iObjectId].iX

    for iY = CLava.tMapObjects[iObjectId].iY, CLava.tMapObjects[iObjectId].iSizeY + CLava.tMapObjects[iObjectId].iY -1 do
        if CLava.tMapObjects[iObjectId].bDiagonal then
            iXStart = iXStart + CLava.tMapObjects[iObjectId].iDiagonalDirection
        end

        for iX = iXStart, CLava.tMapObjects[iObjectId].iSizeX + iXStart -1 do
            if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = CLava.iColor
                tFloor[iX][iY].iBright = tConfig.Bright
                tFloor[iX][iY].iObjectId = iObjectId

                if tFloor[iX][iY].bClick and (tFloor[iX][iY].tSafeZoneButton == nil or not tFloor[iX][iY].tSafeZoneButton.bSafeZoneOn) then
                    CLava.PlayerStepDelay(iX, iY)
                end
            end
        end
    end
end

CPaint.Buttons = function()
    for _, tButton in pairs(tButtons) do
        if tButton.bGoal then
            tButton.iColor = CColors.BLUE
        end
    end
end

CPaint.SafeZones = function()
    for _, tButton in pairs(tButtons) do
        if tButton.bSafeZoneOn then
            local iBright = tButton.iSafeZoneBright
            if CGameMode.SafeZoneClicked(tButton) then
                iBright = iBright + 1
            end

            CPaint.SafeZone(tButton, iBright)
        end
    end 
end

CPaint.SafeZone = function(tButton, iBright)
    --if tButton.bDefect then return false end 

    for iX = tButton.iSafeZoneX, tButton.iSafeZoneX + tGame.SafeZoneSizeX-1 do
        for iY = tButton.iSafeZoneY, tButton.iSafeZoneY + tGame.SafeZoneSizeY-1 do
            tFloor[iX][iY].iColor = CColors.GREEN
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].tSafeZoneButton = tButton

            if tGame.DisableButtonsGameplay and tButton.bGoal then
                tFloor[iX][iY].iColor = CColors.BLUE
            end
        end
    end
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(CPaint.ANIMATION_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.MAGENTA
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = iColor
            iCount = iCount + 1
        end
        
        if iCount <= iFlickerCount then
            return CPaint.ANIMATION_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                tFloor[iX][iY].iObjectId = 0
            end
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
    if not tFloor[click.X] or not tFloor[click.X][click.Y] then return; end  

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

    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight

    if click.Click and iGameState == GAMESTATE_GAME then
        if tFloor[click.X][click.Y].iColor == CColors.RED then
            CLava.PlayerStepDelay(click.X, click.Y)
        elseif tFloor[click.X][click.Y].tSafeZoneButton ~= nil and tGame.DisableButtonsGameplay and tFloor[click.X][click.Y].tSafeZoneButton.bGoal then
            CGameMode.ReachGoal(tFloor[click.X][click.Y].tSafeZoneButton)
        end
    end
end

function DefectPixel(defect)
    if not tFloor[defect.X] or not tFloor[defect.X][defect.Y] then return; end

    tFloor[defect.X][defect.Y].bDefect = defect.Defect
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_GAME and tButtons[click.Button].bGoal then
        CGameMode.ReachGoal(tButtons[click.Button])
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil or tGame.DisableButtonsGameplay then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0

        iDeffectButtons = iDeffectButtons + 1
        if iDeffectButtons > math.floor(iTotalButtons/2) then
            GenerateButtons()
            LoadButtons()
        end
    end   
end