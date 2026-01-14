--[[
    Название: Обучение
    Автор: Avondale, дискорд - avonda
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
local iGameState = GAMESTATE_GAME
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
    ScoreboardVariant = 1,
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
    iObjectID = -1,
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
    CGameMode.StartGame()
end

function NextTick()
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

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CObjects.PaintObjects()
end

function PostGameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CObjects.PaintObjects()    
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
CGameMode.bLavaSoundOn = false

CGameMode.tPlayerColors = {}

CGameMode.InitGameMode = function()
    tGameStats.TotalStages = CStages.STAGE_FINAL
    CStages.iSafeZoneSize = Round((tGame.iMaxY-tGame.iMinY+1)/3)
    SetAllButtonColorBright(CColors.NONE, CColors.BRIGHT0)
end

CGameMode.StartGame = function()
    AL.NewTimer(CObjects.iObjectTickRate, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        CObjects.Tick()

        return CObjects.iObjectTickRate;
    end)    

    CGameMode.SetStage(CStages.STAGE_INTRO)
end

CGameMode.SetStage = function(iStageID)
    CStages.iCurrentStageID = iStageID
    tGameStats.StageNum = iStageID
    CObjects.Clear()
    CStages.StageSpawn[iStageID]()
end

CGameMode.PlayerStepOnLava = function(iX, iY, iObjectID)
    AL.NewTimer(tGame.BurnDelay, function()
        if not tFloor[iX][iY].bClick or tFloor[iX][iY].bAnimated then return; end

        CGameMode.AnimatePixelFlicker(iX, iY, 5, CColors.NONE)

        if CGameMode.bLavaSoundOn then
            CAudio.PlaySystemAsync(CAudio.MISCLICK)
        end
    end)
end

CGameMode.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    AL.NewTimer(30, function()
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
            return 200
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end
--//

--STAGES
CStages = {}
CStages.tStages = {}

CStages.STAGE_NONE = 0
CStages.STAGE_INTRO = 1
CStages.STAGE_SAFEZONE = 2
CStages.STAGE_BLUEPIXEL = 3
CStages.STAGE_APEARINGPIXELS = 4
CStages.STAGE_LAVAINTRODUCTION = 5
CStages.STAGE_DISAPEARINGLAVA = 6
CStages.STAGE_BUTTONS = 7
CStages.STAGE_PIXELSONLAVA = 8
CStages.STAGE_FINAL = 9

CStages.iCurrentStageID = 0

CStages.StageSpawn = {}
CStages.StageTick = {}
CStages.StageClick = {}

--INTRO
CStages.StageSpawn[CStages.STAGE_INTRO] = function()
    local iSlice1 = CObjects.NewObject(-tGame.iMaxX, tGame.CenterY-math.floor(CStages.iSafeZoneSize/4)-1, tGame.iMaxX-tGame.iMinX+1, math.floor(CStages.iSafeZoneSize/2)+1, CObjects.OBJECT_TYPE_SAFEZONE)
    CObjects.tObjects[iSlice1].iTargetX = tGame.iMinX
    CObjects.tObjects[iSlice1].iVelX = 1
    local iSlice2 = CObjects.NewObject(tGame.iMaxX, tGame.CenterY+math.floor(CStages.iSafeZoneSize/4)-1, tGame.iMaxX-tGame.iMinX+1, math.floor(CStages.iSafeZoneSize/2)+1, CObjects.OBJECT_TYPE_SAFEZONE)
    CObjects.tObjects[iSlice2].iTargetX = tGame.iMinX
    CObjects.tObjects[iSlice2].iVelX = -1

    local function lavaspawn(iStartY, iEndY)
        for iX = tGame.iMinX, (tGame.iMaxX-tGame.iMinX+1) do
            for iY = iStartY, iEndY do
                AL.NewTimer(math.random(200, 2500), function()
                    CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_LAVA)
                end)
            end
        end
    end

    AL.NewTimer(1500, function()
        lavaspawn(1, CObjects.tObjects[iSlice1].iY-1)
        lavaspawn(CObjects.tObjects[iSlice2].iY+CObjects.tObjects[iSlice2].iSizeY, tGame.iMaxY)
    end)

    CAudio.PlayVoicesSync("tutorial/welcome_tutorial.mp3")
    CAudio.PlayVoicesSync("tutorial/stand_on_green.mp3")

    AL.NewTimer((CAudio.GetVoicesDuration("tutorial/welcome_tutorial.mp3")+CAudio.GetVoicesDuration("tutorial/stand_on_green.mp3"))*1000 + 5000, function()
        CGameMode.SetStage(CStages.STAGE_BLUEPIXEL)
    end)
end

CStages.StageClick[CStages.STAGE_INTRO] = function(iX, iY)
    
end
--//

--BLUEPIXEL
CStages.StageSpawn[CStages.STAGE_BLUEPIXEL] = function()
    CGameMode.bLavaSoundOn = true

    CObjects.NewObject(tGame.iMinX, tGame.iMinY, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_LAVA)
    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_SAFEZONE)

    local iCoinX = tGame.CenterX
    local iCoinY = Round(CStages.iSafeZoneSize*2+1+(CStages.iSafeZoneSize/2))

    if tFloor[iCoinX][iCoinY].bDefect then
        for iY = iCoinY-1, iCoinY+1 do
            for iX = iCoinX-1, iCoinX+1 do
                if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect then
                    iCoinX = iX
                    iCoinY = iY
                    break;
                end
            end
        end
    end

    CObjects.NewObject(iCoinX, iCoinY, 1, 1, CObjects.OBJECT_TYPE_COIN)

    CAudio.PlayVoicesSync("tutorial/find_the_blue.mp3")
end

CStages.StageClick[CStages.STAGE_BLUEPIXEL] = function(iX, iY)
    if tFloor[iX][iY].iObjectID > 0 and CObjects.tObjects[tFloor[iX][iY].iObjectID] and CObjects.tObjects[tFloor[iX][iY].iObjectID].iType == CObjects.OBJECT_TYPE_COIN then
        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil
        CAudio.PlaySystemSync(CAudio.STAGE_DONE)
        CAudio.PlayVoicesSync("tutorial/after_sound.mp3")
        AL.NewTimer(CAudio.GetVoicesDuration("tutorial/after_sound.mp3")*1000+3000, function()
            CGameMode.SetStage(CStages.STAGE_APEARINGPIXELS)
        end)
    end
end
--//

--APEARINGPIXELS
CStages.StageSpawn[CStages.STAGE_APEARINGPIXELS] = function()
    CObjects.NewObject(tGame.iMinX, tGame.iMinY, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_LAVA)
    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize*2+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_LAVA)

    local iStartX = tGame.iMinX
    local iEndX = tGame.iMaxX
    local iStartY = CStages.iSafeZoneSize+1
    local iEndY = CStages.iSafeZoneSize+CStages.iSafeZoneSize

    CStages.iCoinsStage = 0
    CStages.tFutureCoins = {}

    for iX = iStartX, iEndX do
        for iY = iStartY, iEndY do
            if iY > iStartY and iY < iEndY and iX > iStartX and iX < iStartX+4 and not tFloor[iX][iY].bDefect then
                CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_COIN)
                tGameStats.TotalStars = tGameStats.TotalStars + 1
            else
                CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_SAFEZONE)

                if (iY == iStartY+1 or iY == iEndY-1) and iX > iStartX+6 and iX < tGame.iMaxX-6 and not tFloor[iX][iY].bDefect then
                    CStages.tFutureCoins[#CStages.tFutureCoins+1] = {iX = iX, iY = iY}
                end
            end
        end
    end

    CAudio.PlayVoicesSync("tutorial/find_more_blues.mp3")
end

CStages.StageClick[CStages.STAGE_APEARINGPIXELS] = function(iX, iY)
    if tFloor[iX][iY].iObjectID > 0 and CObjects.tObjects[tFloor[iX][iY].iObjectID] and CObjects.tObjects[tFloor[iX][iY].iObjectID].iType == CObjects.OBJECT_TYPE_COIN then
        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil    
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1

        if tGameStats.CurrentStars >= tGameStats.TotalStars then
            CStages.iCoinsStage = CStages.iCoinsStage + 1
            tGameStats.CurrentStars = 0
            tGameStats.TotalStars = 0

            CAudio.PlaySystemSync(CAudio.STAGE_DONE)

            if CStages.iCoinsStage >= 2 then
                CGameMode.SetStage(CStages.STAGE_LAVAINTRODUCTION)
            else
                for iFCoinID = 1, #CStages.tFutureCoins do
                    local iX = CStages.tFutureCoins[iFCoinID].iX
                    local iY = CStages.tFutureCoins[iFCoinID].iY
                    AL.NewTimer(50*iX, function()
                        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil
                        CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_COIN)
                    end)
                    tGameStats.TotalStars = tGameStats.TotalStars + 1
                end
                CStages.tFutureCoins = {}
            end
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    end
end
--//

--LAVAINTRODUCTION
CStages.StageSpawn[CStages.STAGE_LAVAINTRODUCTION] = function()
    CObjects.iObjectTickRate = 250

    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_SAFEZONE)

    local iLava1 = CObjects.NewObject(tGame.iMinX, tGame.iMinY, tGame.iMaxX-tGame.iMinX+1, 1, CObjects.OBJECT_TYPE_LAVA)
    CObjects.tObjects[iLava1].iVelY = 1
    CObjects.tObjects[iLava1].iTargetY = CStages.iSafeZoneSize
    CObjects.tObjects[iLava1].bCollidable = true
    local iLava2 = CObjects.NewObject(tGame.iMinX, tGame.iMaxY-1, tGame.iMaxX-tGame.iMinX+1, 1, CObjects.OBJECT_TYPE_LAVA)
    CObjects.tObjects[iLava2].iVelY = -1
    CObjects.tObjects[iLava2].iTargetY = CStages.iSafeZoneSize*2+1
    CObjects.tObjects[iLava2].bCollidable = true

    AL.NewTimer(50, function()
        CObjects.SpawnCoinsRandomly(math.floor(tGame.Cols/4), false)
    end)

    CAudio.PlayVoicesSync("tutorial/click_blues_avoiding_lava.mp3")
end

CStages.StageClick[CStages.STAGE_LAVAINTRODUCTION] = function(iX, iY)
    if tFloor[iX][iY].iObjectID > 0 and CObjects.tObjects[tFloor[iX][iY].iObjectID] and CObjects.tObjects[tFloor[iX][iY].iObjectID].iType == CObjects.OBJECT_TYPE_COIN then
        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil    
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1

        if tGameStats.CurrentStars >= tGameStats.TotalStars then
            tGameStats.CurrentStars = 0
            tGameStats.TotalStars = 0

            CAudio.PlaySystemSync(CAudio.STAGE_DONE)

            CGameMode.SetStage(CStages.STAGE_DISAPEARINGLAVA)
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    end
end
--//

--DISAPEARINGLAVA
CStages.StageSpawn[CStages.STAGE_DISAPEARINGLAVA] = function()
    local iLava1 = CObjects.NewObject(tGame.iMinX, tGame.iMinY, 1, tGame.iMaxY-tGame.iMinY+1, CObjects.OBJECT_TYPE_LAVA)
    CObjects.tObjects[iLava1].iVelX = 1
    CObjects.tObjects[iLava1].bCollidable = true

    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_SAFEZONE)

    AL.NewTimer(50, function()
        CObjects.SpawnCoinsRandomly(math.floor(tGame.Cols/2), true)
    end)

    CAudio.PlayVoicesSync("tutorial/jumping_blues.mp3") 
end

CStages.StageClick[CStages.STAGE_DISAPEARINGLAVA] = function(iX, iY)
    if tFloor[iX][iY].iObjectID > 0 and CObjects.tObjects[tFloor[iX][iY].iObjectID] and CObjects.tObjects[tFloor[iX][iY].iObjectID].iType == CObjects.OBJECT_TYPE_COIN then
        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil    
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1
        if tGameStats.CurrentStars >= tGameStats.TotalStars then
            tGameStats.CurrentStars = 0
            tGameStats.TotalStars = 0

            CAudio.PlaySystemSync(CAudio.STAGE_DONE)

            if tGame.NoButtonsGame then
                CGameMode.SetStage(CStages.STAGE_PIXELSONLAVA)
            else
                CGameMode.SetStage(CStages.STAGE_BUTTONS)
            end
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    end
end
--//

--BUTTONS
CStages.StageSpawn[CStages.STAGE_BUTTONS] = function()
    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_SAFEZONE)

    local iLava1 = CObjects.NewObject(tGame.iMinX, tGame.iMinY, 1, tGame.iMaxY-tGame.iMinY+1, CObjects.OBJECT_TYPE_LAVA)
    CObjects.tObjects[iLava1].iVelX = 1
    CObjects.tObjects[iLava1].iTargetX = tGame.CenterX
    CObjects.tObjects[iLava1].bCollidable = true
    local iLava2 = CObjects.NewObject(tGame.CenterX, tGame.iMinY, 1, tGame.iMaxY-tGame.iMinY+1, CObjects.OBJECT_TYPE_LAVA)
    CObjects.tObjects[iLava2].iVelX = 1
    CObjects.tObjects[iLava2].iTargetX = tGame.CenterX
    CObjects.tObjects[iLava2].bCollidable = true

    for iButton, tButton in pairs(tButtons) do
        if tButtons[iButton] and not tButtons[iButton].bDefect and math.random(1,3) == 2 then
            tButtons[iButton].iColor = CColors.BLUE
            tButtons[iButton].iBright = tConfig.Bright
            tGameStats.TotalStars = tGameStats.TotalStars + 1
        end 
    end

    CAudio.PlayVoicesSync("tutorial/click_buttons.mp3")
end

CStages.StageClick[CStages.STAGE_BUTTONS] = function(iButton, iNotButton)
    if iNotButton == nil and tButtons[iButton] and tButtons[iButton].iColor == CColors.BLUE then
        tButtons[iButton].iColor = CColors.NONE
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1

        if tGameStats.CurrentStars >= tGameStats.TotalStars then
            tGameStats.CurrentStars = 0
            tGameStats.TotalStars = 0

            CAudio.PlaySystemSync(CAudio.STAGE_DONE)

            CGameMode.SetStage(CStages.STAGE_PIXELSONLAVA)
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    end
end
--//

--PIXELSONLAVA
CStages.StageSpawn[CStages.STAGE_PIXELSONLAVA] = function()
    CObjects.NewObject(tGame.iMinX, CStages.iSafeZoneSize+1, tGame.iMaxX-tGame.iMinY+1, CStages.iSafeZoneSize, CObjects.OBJECT_TYPE_SAFEZONE)

    local function spawnBatch(iStartX, iEndX, iY)
        for iX = iStartX, iEndX do
            if iX % 2 == 0 then
                CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_LAVA)
                CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_COIN)
                tGameStats.TotalStars = tGameStats.TotalStars + 1
            end
        end
    end

    local iBatchX = math.floor((tGame.iMaxX-tGame.iMinX+1)/4)

    spawnBatch(iBatchX, tGame.iMaxX-iBatchX, math.floor(CStages.iSafeZoneSize/2))
    spawnBatch(iBatchX, tGame.iMaxX-iBatchX, tGame.iMaxY-math.floor(CStages.iSafeZoneSize/2))

    CAudio.PlayVoicesSync("tutorial/burning_blues.mp3")
end

CStages.StageClick[CStages.STAGE_PIXELSONLAVA] = function(iX, iY)
    if tFloor[iX][iY].iObjectID > 0 and CObjects.tObjects[tFloor[iX][iY].iObjectID] and CObjects.tObjects[tFloor[iX][iY].iObjectID].iType == CObjects.OBJECT_TYPE_COIN then
        CObjects.tObjects[tFloor[iX][iY].iObjectID] = nil    
        tGameStats.CurrentStars = tGameStats.CurrentStars + 1
        if tGameStats.CurrentStars >= tGameStats.TotalStars then
            tGameStats.CurrentStars = 0
            tGameStats.TotalStars = 0

            CGameMode.SetStage(CStages.STAGE_FINAL)
        else
            CAudio.PlaySystemAsync(CAudio.CLICK)
        end
    end
end
--//

--FINAL
CStages.StageSpawn[CStages.STAGE_FINAL] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            AL.NewTimer(math.random(100, 3000), function()
                CObjects.NewObject(iX, iY, 1, 1, CObjects.OBJECT_TYPE_SAFEZONE)
            end)
        end
    end

    tGameResults.Won = true
    tGameResults.Color = CColors.GREEN

    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(CAudio.GetVoicesDuration("tutorial/success.mp3")*1000 + tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)    

    CAudio.PlaySystemSync(CAudio.GAME_SUCCESS)
    CAudio.PlayVoicesSync("tutorial/success.mp3")
end

CStages.StageClick[CStages.STAGE_FINAL] = function(iX, iY)

end
--//

--//

--OBJECTS
CObjects = {}
CObjects.tObjects = {}

CObjects.OBJECT_TYPE_SAFEZONE = 1
CObjects.OBJECT_TYPE_LAVA = 2
CObjects.OBJECT_TYPE_COIN = 3

CObjects.OBJECT_TYPE_TO_COLOR = {}
CObjects.OBJECT_TYPE_TO_COLOR[CObjects.OBJECT_TYPE_SAFEZONE] = CColors.GREEN
CObjects.OBJECT_TYPE_TO_COLOR[CObjects.OBJECT_TYPE_LAVA] = CColors.RED
CObjects.OBJECT_TYPE_TO_COLOR[CObjects.OBJECT_TYPE_COIN] = CColors.BLUE

CObjects.iObjectTickRate = 100

CObjects.NewObject = function(iX, iY, iSizeX, iSizeY, iType)
    local iObjectID = #CObjects.tObjects+1
    CObjects.tObjects[iObjectID] = {}
    CObjects.tObjects[iObjectID].iX = iX
    CObjects.tObjects[iObjectID].iY = iY
    CObjects.tObjects[iObjectID].iSizeX = iSizeX
    CObjects.tObjects[iObjectID].iSizeY = iSizeY
    CObjects.tObjects[iObjectID].iType = iType

    CObjects.tObjects[iObjectID].bVisible = true
    CObjects.tObjects[iObjectID].iVelX = 0
    CObjects.tObjects[iObjectID].iVelY = 0
    CObjects.tObjects[iObjectID].iTargetX = 0
    CObjects.tObjects[iObjectID].iTargetY = 0
    CObjects.tObjects[iObjectID].bCollidable = false

    return iObjectID
end

CObjects.SpawnCoinsRandomly = function(iAmount, bCollidable)
    tGameStats.TotalStars = 0

    while tGameStats.TotalStars < iAmount do
        local iRandX = math.random(tGame.iMinX, tGame.iMaxX)
        local iRandY = math.random(tGame.iMinY, tGame.iMaxY)
    
        if not tFloor[iRandX][iRandY].bDefect and tFloor[iRandX][iRandY].iObjectID < 1 then
            local iCoinID = CObjects.NewObject(iRandX, iRandY, 1, 1, CObjects.OBJECT_TYPE_COIN)
            CObjects.tObjects[iCoinID].bCollidable = bCollidable

            tGameStats.TotalStars = tGameStats.TotalStars + 1
        end
    end
end

CObjects.Clear = function()
    CObjects.tObjects = {}
end

CObjects.PaintObjects = function()
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] then
            for iX = CObjects.tObjects[iObjectID].iX, CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iSizeX-1 do
                for iY = CObjects.tObjects[iObjectID].iY, CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iSizeY-1 do
                    if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bAnimated then
                        tFloor[iX][iY].iColor = CObjects.OBJECT_TYPE_TO_COLOR[CObjects.tObjects[iObjectID].iType]
                        tFloor[iX][iY].iBright = tConfig.Bright 
                        tFloor[iX][iY].iObjectID = iObjectID
                    end
                end
            end 
        end
    end
end

CObjects.Tick = function()
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] and (CObjects.tObjects[iObjectID].iVelX ~= 0 or CObjects.tObjects[iObjectID].iVelY ~= 0) then
            CObjects.tObjects[iObjectID].iX = CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iVelX
            CObjects.tObjects[iObjectID].iY = CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iVelY

            if CObjects.tObjects[iObjectID].bCollidable then
                if CObjects.tObjects[iObjectID].iVelX ~= 0 then
                    if CObjects.tObjects[iObjectID].iX <= tGame.iMinX then
                        CObjects.tObjects[iObjectID].iVelX = 1
                    elseif CObjects.tObjects[iObjectID].iX+CObjects.tObjects[iObjectID].iSizeX-1 >= tGame.iMaxX then
                        CObjects.tObjects[iObjectID].iVelX = -1
                    end
                end

                if CObjects.tObjects[iObjectID].iVelY ~= 0 then
                    if CObjects.tObjects[iObjectID].iY <= tGame.iMinY then
                        CObjects.tObjects[iObjectID].iVelY = 1
                    elseif CObjects.tObjects[iObjectID].iY+CObjects.tObjects[iObjectID].iSizeY-1 >= tGame.iMaxY then
                        CObjects.tObjects[iObjectID].iVelY = -1
                    end
                end

                if CObjects.tObjects[iObjectID].iTargetX ~= 0 and CObjects.tObjects[iObjectID].iX == CObjects.tObjects[iObjectID].iTargetX then
                    CObjects.tObjects[iObjectID].iVelX = -CObjects.tObjects[iObjectID].iVelX
                end
                if CObjects.tObjects[iObjectID].iTargetY ~= 0 and CObjects.tObjects[iObjectID].iY == CObjects.tObjects[iObjectID].iTargetY then
                    CObjects.tObjects[iObjectID].iVelY = -CObjects.tObjects[iObjectID].iVelY
                end

                for iColID = 1, #CObjects.tObjects do
                    if iColID ~= iObjectID and CObjects.tObjects[iColID] and CObjects.tObjects[iColID].bCollidable then
                        if CObjects.tObjects[iColID].iType == CObjects.OBJECT_TYPE_COIN 
                        and AL.RectIntersects2(CObjects.tObjects[iObjectID].iX, CObjects.tObjects[iObjectID].iY, CObjects.tObjects[iObjectID].iSizeX, CObjects.tObjects[iObjectID].iSizeY, CObjects.tObjects[iColID].iX, CObjects.tObjects[iColID].iY, 1, 1) then
                            CObjects.tObjects[iColID] = nil

                            local iRandX, iRandY
                            repeat
                                iRandX = math.random(tGame.iMinX, tGame.iMaxX)
                                iRandY = math.random(tGame.iMinY, tGame.iMaxY)
                            until not tFloor[iRandX][iRandY].bDefect and tFloor[iRandX][iRandY].iObjectID < 1

                            local iCoinID = CObjects.NewObject(iRandX, iRandY, 1, 1, CObjects.OBJECT_TYPE_COIN)
                            CObjects.tObjects[iCoinID].bCollidable = true
                        end
                    end
                end
            else
                if CObjects.tObjects[iObjectID].iTargetX ~= 0 and CObjects.tObjects[iObjectID].iX == CObjects.tObjects[iObjectID].iTargetX then
                    CObjects.tObjects[iObjectID].iVelX = 0
                end
                if CObjects.tObjects[iObjectID].iTargetY ~= 0 and CObjects.tObjects[iObjectID].iY == CObjects.tObjects[iObjectID].iTargetY then
                    CObjects.tObjects[iObjectID].iVelY = 0
                end
            end
        end
    end    
end

CObjects.Click = function(iX, iY)
    local iObjectID = tFloor[iX][iY].iObjectID
    if iObjectID > 0 and CObjects.tObjects[iObjectID] then
        if CObjects.tObjects[iObjectID].iType == CObjects.OBJECT_TYPE_LAVA then
            CGameMode.PlayerStepOnLava(iX, iY, iObjectID)
        elseif CObjects.tObjects[iObjectID].iType == CObjects.OBJECT_TYPE_COIN then

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
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
                tFloor[iX][iY].iObjectID = -1
            end
        end
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

function ShuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end

    return t
end

function TableConcat(...)
    local tR = {}
    local i = 1
    local function addtable(t)
        for j = 1, #t do
            tR[i] = t[j]
            i = i + 1
        end
    end

    for _,t in pairs({...}) do
        addtable(t)
    end

    return tR
end

function Round(i)
    if i%1 > 0.5 then
        return math.ceil(i)
    end

    return math.floor(i)
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

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight

        if click.Click and iGameState == GAMESTATE_GAME and CStages.iCurrentStageID > 0 then
            CStages.StageClick[CStages.iCurrentStageID](click.X, click.Y);
            CObjects.Click(click.X, click.Y)
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

    if click.Click and CStages.iCurrentStageID == CStages.STAGE_BUTTONS then
        CStages.StageClick[CStages.STAGE_BUTTONS](click.Button);
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