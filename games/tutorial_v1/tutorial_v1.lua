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
    ScoreboardVariant = 0,
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

CGameMode.InitGameMode = function()
    
end

CGameMode.StartGame = function()
    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME then return; end

        CObjects.Tick()

        return 100;
    end)    

    CGameMode.SetStage(CStages.STAGE_INTRO)
end

CGameMode.SetStage = function(iStageID)
    CStages.StageSpawn[iStageID]()
    
    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME or CStages.iCurrentStageID ~= iStageID then return; end
        
        return CStages.StageTick[iStageID]()
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
    local iSafeZoneSize = math.floor(((tGame.iMaxY-tGame.iMinY+1)/3)/2)

    local iSlice1 = CObjects.NewObject(-tGame.iMaxX, tGame.CenterY-math.floor(iSafeZoneSize/2), tGame.iMaxX-tGame.iMinX+1, iSafeZoneSize, CColors.GREEN)
    CObjects.tObjects[iSlice1].iTargetX = tGame.iMinX
    CObjects.tObjects[iSlice1].iVelX = 1
    local iSlice2 = CObjects.NewObject(tGame.iMaxX, tGame.CenterY+math.floor(iSafeZoneSize/2), tGame.iMaxX-tGame.iMinX+1, iSafeZoneSize, CColors.GREEN)
    CObjects.tObjects[iSlice2].iTargetX = tGame.iMinX
    CObjects.tObjects[iSlice2].iVelX = -1
end

CStages.StageTick[CStages.STAGE_INTRO] = function()
    
    return 250;
end

CStages.StageClick[CStages.STAGE_INTRO] = function(iX, iY)
    
end
--//

--//

--OBJECTS
CObjects = {}
CObjects.tObjects = {}

CObjects.NewObject = function(iX, iY, iSizeX, iSizeY, iColor, bVisible)
    local iObjectID = #CObjects.tObjects+1
    CObjects.tObjects[iObjectID] = {}
    CObjects.tObjects[iObjectID].iX = iX
    CObjects.tObjects[iObjectID].iY = iY
    CObjects.tObjects[iObjectID].iSizeX = iSizeX
    CObjects.tObjects[iObjectID].iSizeY = iSizeY
    CObjects.tObjects[iObjectID].iColor = iColor
    CObjects.tObjects[iObjectID].bVisible = bVisible

    CObjects.tObjects[iObjectID].iVelX = 0
    CObjects.tObjects[iObjectID].iVelY = 0
    CObjects.tObjects[iObjectID].iTargetX = 0
    CObjects.tObjects[iObjectID].iTargetY = 0

    return iObjectID
end

CObjects.PaintObjects = function()
    for iObjectID = 1, #CObjects.tObjects do
        if CObjects.tObjects[iObjectID] then
            for iX = CObjects.tObjects[iObjectID].iX, CObjects.tObjects[iObjectID].iX + CObjects.tObjects[iObjectID].iSizeX-1 do
                for iY = CObjects.tObjects[iObjectID].iY, CObjects.tObjects[iObjectID].iY + CObjects.tObjects[iObjectID].iSizeY-1 do
                    if tFloor[iX] and tFloor[iX][iY] then
                        tFloor[iX][iY].iColor = CObjects.tObjects[iObjectID].iColor 
                        tFloor[iX][iY].iBright = tConfig.Bright 
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

            if CObjects.tObjects[iObjectID].iTargetX ~= 0 and CObjects.tObjects[iObjectID].iX == CObjects.tObjects[iObjectID].iTargetX then
                CObjects.tObjects[iObjectID].iVelX = 0
            end
            if CObjects.tObjects[iObjectID].iTargetY ~= 0 and CObjects.tObjects[iObjectID].iY == CObjects.tObjects[iObjectID].iTargetY then
                CObjects.tObjects[iObjectID].iVelY = 0
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

        if iGameState == GAMESTATE_GAME and CStages.iCurrentStageID > 0 then
            CStages.StageClick[CStages.iCurrentStageID](click.X, click.Y);
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