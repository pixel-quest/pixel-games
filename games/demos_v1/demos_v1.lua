--[[
    Название: Анимированные заставки
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
local CVideos = require("video")
local CEvents = require("events")

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
    ScoreboardVariant = 10,
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
    iParticleID = 0,
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

    if tConfig.ColorOptions ~= nil then
        --CAudio.PlayVoicesSyncFromScratch("choose-color.mp3")
        CPaint.LoadDemo("_choice")

        local iTime = 10

        AL.NewTimer(1000, function()
            iTime = iTime -1
            tGameStats.StageLeftDuration = iTime

            if iTime == 0 then
                VideoSelectBranch()
            else
                if iTime <= 5 then
                    CAudio.ResetSync()
                    CAudio.PlayLeftAudio(iTime)
                end

                return 1000
            end
        end)
    else
        CPaint.LoadDemo(tConfig.DemoName)
    end
    
    CPaint.DemoThinker()

    if tConfig.Video ~= "" then
        tGameStats.ScoreBoardVariant = 0
        VideoPlay(tConfig.Video)
    end

    if tConfig.Sound and tConfig.Sound ~= "" then
        CAudio.PlayVoicesSyncFromScratch(tConfig.Sound)
    end

    if tConfig.GameDuration > 0 then
        AL.NewTimer(tConfig.GameDuration * 1000, function()
            iGameState = GAMESTATE_FINISH
        end)
    end

    if tConfig.Events ~= nil then
        InitEvents()
    end
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

    if tGameResults.selected_branch ~= nil then
        tGameResults.Won = true
        tGameResults.AfterDelay = false
        return tGameResults
    end

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright)
    CPaint.Demo()
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
    if iGameState == GAMESTATE_GAME then
        CPaint.SwitchDemo()
        CPaint.bForceSwitch = true
    end   
end

local bVideoPlaying
function VideoPlay(name)
    if bVideoPlaying then return; end

    CVideos.Play(name)
    bVideoPlaying = true
    if tConfig.VideoDuration then
        AL.NewTimer(tConfig.VideoDuration*1000, function()
            bVideoPlaying = false

            if tConfig.VideoLoop then
                VideoPlay(tConfig.Video)
            end
            if tConfig.Sound and tConfig.Sound ~= "" and tConfig.AudioLoop then
                CAudio.PlayVoicesSyncFromScratch(tConfig.Sound)
            end
        end)
    end
end

function VideoSelectBranch()
    local iShift = tConfig.ColorOptions[1].shift
    --[[
    local iMax = -1

    for iOptionID = 1, #tConfig.ColorOptions do
        if CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] and CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] > iMax then
            iMax = CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID]
            iShift = tConfig.ColorOptions[iOptionID].shift
        end
    end
    ]]

    for iOptionID = 1, #tConfig.ColorOptions do
        if CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] and CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] > 0 then
            iShift = tConfig.ColorOptions[iOptionID].shift
            break;
        end
    end

    CLog.print("Chosen branch: "..iShift)
    tGameResults.selected_branch = iShift
end

function InitEvents()
    for _,tEvent in pairs(tConfig.Events) do
        AL.NewTimer(tEvent.ts*1000, function() 
            CEvents.Send(tEvent.text or "", tEvent.sound or "", tEvent.recepients or {})

            if tEvent.repeat_count and tEvent.repeat_count > 0 then
                tEvent.repeat_count = tEvent.repeat_count - 1
                return tEvent.repeat_delay*1000
            end
        end)
    end
end

--PAINT
CPaint = {}

CPaint.FUNC_LOAD = 1
CPaint.FUNC_PAINT = 2
CPaint.FUNC_THINK = 3
CPaint.FUNC_CLICK = 4

CPaint.sLoadedDemo = ""

CPaint.bForceSwitch = false

CPaint.LoadDemo = function(sDemoName)
    CPaint.sLoadedDemo = sDemoName
    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_LOAD]()

    if not tConfig.NoMusic then
        CAudio.PlayRandomBackground()
    end
end

CPaint.Demo = function()
    if iGameState ~= GAMESTATE_GAME then return; end

    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_PAINT]()

    if CPaint.sLoadedDemo ~= "_choice" and tConfig.PictureName and tConfig.PictureName ~= "none" and tPictures[tConfig.PictureName] ~= nil then
        CPaint.Picture(tConfig.PictureName)
    end
end

CPaint.Picture = function(sPictureName)
    local iSizeX = #tPictures[sPictureName][1]
    local iSizeY = #tPictures[sPictureName]
    local iStartX = 1
    local iStartY = 1

    local iPicX = 0
    local iPicY = 0

    for iY = iStartY, iStartY+iSizeY-1 do
        iPicY = iPicY + 1
        for iX = iStartX, iStartX+iSizeX-1 do
            iPicX = iPicX + 1
            if tFloor[iX] and tFloor[iX][iY] and tPictures[sPictureName][iPicY] and tPictures[sPictureName][iPicY][iPicX] and tPictures[sPictureName][iPicY][iPicX] ~= "0xEMPTY1" then
                tFloor[iX][iY].iColor = tonumber(tPictures[sPictureName][iPicY][iPicX])
                tFloor[iX][iY].iBright = tConfig.Bright
            end
        end
        iPicX = 0
    end
end

CPaint.UnloadDemo = function(fCallback)
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)

    CPaint.tDemoList[CPaint.sLoadedDemo].tVars = nil
    iGameState = GAMESTATE_POSTGAME
    AL.NewTimer(250, function()
        iGameState = GAMESTATE_GAME
        fCallback()
    end)
end

CPaint.DemoThinker = function()
    AL.NewTimer(CPaint.tDemoList[CPaint.sLoadedDemo].THINK_DELAY, function()
        if iGameState == GAMESTATE_GAME and CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_THINK]() then return CPaint.tDemoList[CPaint.sLoadedDemo].THINK_DELAY end 
    end)

    if tConfig.SwitchEffects then
        AL.NewTimer(tConfig.SwitchEffectsTimer*1000, function()
            if CPaint.bForceSwitch then CPaint.bForceSwitch = false; return; end

            if iGameState == GAMESTATE_GAME then
                CPaint.SwitchDemo()
            end
        end)
    end
end

CPaint.SwitchDemo = function()
    CPaint.UnloadDemo(function()
        local sNewDemo = ""

        repeat sNewDemo = tConfig.DemoName_List[math.random(1,#tConfig.DemoName_List-1)]
        until sNewDemo ~= CPaint.sLoadedDemo

        CPaint.LoadDemo(sNewDemo)
        CPaint.DemoThinker()
    end)
end

CPaint.DemoClick = function(iX, iY)
    CPaint.tDemoList[CPaint.sLoadedDemo][CPaint.FUNC_CLICK](iX, iY)
end
--//

----DEMO LIST
CPaint.tDemoList = {}

--CHOICE
CPaint.tDemoList["_choice"] = {}
CPaint.tDemoList["_choice"].THINK_DELAY = 120
CPaint.tDemoList["_choice"].COLOR = "0xffffff"
CPaint.tDemoList["_choice"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["_choice"].tVars = {}
    CPaint.tDemoList["_choice"].tVars.iOptionsCount = (#tConfig.ColorOptions or 2)
    CPaint.tDemoList["_choice"].tVars.tOptionsClicks = {}
end
CPaint.tDemoList["_choice"][CPaint.FUNC_PAINT] = function()
    local iSizeY = tGame.Rows
    local iSizeX = tGame.Cols

    if CPaint.tDemoList["_choice"].tVars.iOptionsCount  <= 2 then
        iSizeY = math.floor(iSizeY/CPaint.tDemoList["_choice"].tVars.iOptionsCount)
    else
        iSizeX = math.floor(iSizeX/CPaint.tDemoList["_choice"].tVars.iOptionsCount)
    end

    local iStartX = 1
    local iStartY = 1

    CPaint.tDemoList["_choice"].tVars.tOptionsClicks = {}

    for iOptionID = 1, CPaint.tDemoList["_choice"].tVars.iOptionsCount do
        for iX = iStartX, iStartX+iSizeX-1 do
            for iY = iStartY, iStartY+iSizeY-1 do
                tFloor[iX][iY].iColor = tonumber(tConfig.ColorOptions[iOptionID].color)
                tFloor[iX][iY].iBright = tConfig.Bright

                if tFloor[iX][iY].bClick and not tFloor[iX][iY].bDefect then
                    CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] = (CPaint.tDemoList["_choice"].tVars.tOptionsClicks[iOptionID] or 0) + 1
                end
            end
        end
        if CPaint.tDemoList["_choice"].tVars.iOptionsCount  <= 2 then 
            iStartY = iStartY + iSizeY+1
        else
            iStartX = iStartX + iSizeX
        end
    end
end
CPaint.tDemoList["_choice"][CPaint.FUNC_THINK] = function()

    return true
end
CPaint.tDemoList["_choice"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--MATRIX
CPaint.tDemoList["matrix"] = {}
CPaint.tDemoList["matrix"].THINK_DELAY = 120
CPaint.tDemoList["matrix"].COLOR = "0x00ff0a"
CPaint.tDemoList["matrix"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["matrix"].tVars = {}
    CPaint.tDemoList["matrix"].tVars.tParticles = {}

    local function randX()
        local iX = 0
        repeat iX = math.random(1, tGame.Cols)
        until tFloor[iX][1].iColor == CColors.NONE

        return iX
    end

    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["matrix"].tVars or CPaint.sLoadedDemo ~= "matrix" then return; end

        for iParticle = 1, math.random(0,2) do
            local iParticleID = #CPaint.tDemoList["matrix"].tVars.tParticles+1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] = {}
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX = randX()
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY = 1
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize = math.random(7, 20)
        end

        return 200
    end)
end
CPaint.tDemoList["matrix"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    for iParticleID = 1, #CPaint.tDemoList["matrix"].tVars.tParticles do
        if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] then
            for iY = CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY - CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize, CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY do
                if iY >= 1 and iY <= tGame.Rows then
                    local iBright = (10 + math.floor(CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize/4)) + (iY - CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY)
                    if iBright > 10 then iBright = 10 end
                    if iBright < 0 then iBright = 0 end
                    tFloor[CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX][iY].iColor = tonumber(CPaint.tDemoList["matrix"].COLOR)
                    tFloor[CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iX][iY].iBright = iBright
                end
            end
        end
    end
end
CPaint.tDemoList["matrix"][CPaint.FUNC_THINK] = function()

    for iParticleID = 1, #CPaint.tDemoList["matrix"].tVars.tParticles do
        if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] then
            CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY =  CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY + 1
            if CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iY > tGame.Rows + CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID].iSize+1 then
                CPaint.tDemoList["matrix"].tVars.tParticles[iParticleID] = nil
            end
        end
    end

    return true
end
CPaint.tDemoList["matrix"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--MATRIX2
CPaint.tDemoList["matrix2"] = {}
CPaint.tDemoList["matrix2"].THINK_DELAY = 120
CPaint.tDemoList["matrix2"].COLOR = "0x00ff0a"
CPaint.tDemoList["matrix2"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["matrix2"].tVars = {}
    CPaint.tDemoList["matrix2"].tVars.tParticles = {}

    local function randY()
        local iY = 0
        repeat iY = math.random(1, tGame.Rows)
        until tFloor[1][iY].iColor == CColors.NONE

        return iY
    end

    AL.NewTimer(400, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["matrix2"].tVars or CPaint.sLoadedDemo ~= "matrix2" then return; end

        for iParticle = 1, math.random(0,2) do
            local iParticleID = #CPaint.tDemoList["matrix2"].tVars.tParticles+1
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] = {}
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY = randY()
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize = math.random(7, 20)
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX = tGame.Cols + CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize
        end

        return 400
    end)
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright)

    for iParticleID = 1, #CPaint.tDemoList["matrix2"].tVars.tParticles do
        if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] then
            for iX = CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX + CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize do
                if iX >= 1 and iX <= tGame.Cols then
                    local iBright = (10 + math.floor(CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize/4)) - (iX - CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX)
                    if iBright > 10 then iBright = 10 end
                    if iBright < 0 then iBright = 0 end
                    tFloor[iX][CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY].iColor = tonumber(CPaint.tDemoList["matrix2"].COLOR)
                    tFloor[iX][CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iY].iBright = iBright
                end
            end
        end
    end
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_THINK] = function()

    for iParticleID = 1, #CPaint.tDemoList["matrix2"].tVars.tParticles do
        if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] then
            CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX = CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX - 1
            if CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iX < 1 - CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID].iSize+1 then
                CPaint.tDemoList["matrix2"].tVars.tParticles[iParticleID] = nil
            end
        end
    end

    return true
end
CPaint.tDemoList["matrix2"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--DERBY
CPaint.tDemoList["derby"] = {}
CPaint.tDemoList["derby"].THINK_DELAY = 200
CPaint.tDemoList["derby"].COLOR = "0xFF00FF"
CPaint.tDemoList["derby"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["derby"].tVars = {}
    CPaint.tDemoList["derby"].tVars.tParticles = {}

    local function randXY()
        local iX = 0
        local iY = 0
        repeat iX = math.random(1, tGame.Cols); iY = math.random(1, tGame.Rows)
        until tFloor[iX][iY].iColor == CColors.NONE

        return iX, iY
    end

    for iParticleID = 1, math.ceil(math.abs(tGame.Cols - tGame.Rows)/2) do
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID] = {}
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY = randXY()
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX = 0
        CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY = 0

        AL.NewTimer(1, function()
            if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["derby"].tVars or CPaint.sLoadedDemo ~= "derby" then return; end

            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX = math.random(1, tGame.Cols)
            CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY = math.random(1, tGame.Rows)

            return math.random(200, 500)
        end)
    end
end
CPaint.tDemoList["derby"][CPaint.FUNC_PAINT] = function()
    SetAllButtonColorBright(CColors.MAGENTA, tConfig.Bright)

    local function paintPixel(iX, iY, iBright, iParticleID)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = tonumber(CPaint.tDemoList["derby"].COLOR)
            tFloor[iX][iY].iBright = iBright
            tFloor[iX][iY].iParticleID = iParticleID
        end
    end

    for iParticleID = 1, #CPaint.tDemoList["derby"].tVars.tParticles do
        if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX > 0 then
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX-1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX+1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY-1, tConfig.Bright-2, iParticleID)
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY+1, tConfig.Bright-2, iParticleID)
        end

        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX+1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX-1, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY+1, tConfig.Bright, iParticleID)
        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY-1, tConfig.Bright, iParticleID)

        if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX > 0 then
            paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY, tConfig.Bright-1, iParticleID)
        end

        paintPixel(CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX, CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY, tConfig.Bright-1, iParticleID)
    end
end
CPaint.tDemoList["derby"][CPaint.FUNC_THINK] = function()
    for iParticleID = 1, #CPaint.tDemoList["derby"].tVars.tParticles do
        local iXPlus = 0
        local iYPlus = 0

        if math.random(0,1) == 0 then
            if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX < CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX then
                iXPlus = 1
            elseif CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX > CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestX then
                iXPlus = -1
            end
        end
        if math.random(0,1) == 1 then
            if CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY < CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY then
                iYPlus = 1
            elseif CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY > CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iDestY then
                iYPlus = -1
            end        
        end

        if iXPlus ~= 0 or iYPlus ~= 0 then
            if tFloor[CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus][CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus].iParticleID == 0 
            or tFloor[CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus][CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus].iParticleID == iParticleID then
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevX = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iPrevY = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY

                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iX + iXPlus
                CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY = CPaint.tDemoList["derby"].tVars.tParticles[iParticleID].iY + iYPlus
            end
        end
    end

    return true
end
CPaint.tDemoList["derby"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--RAINBOWWAVE
CPaint.tDemoList["rainbowwave"] = {}
CPaint.tDemoList["rainbowwave"].THINK_DELAY = 100
CPaint.tDemoList["rainbowwave"].SIZE = 1
CPaint.tDemoList["rainbowwave"].COLORS = 
{
    {CColors.RED, 3}, 
    {CColors.RED, 4}, 
    {CColors.RED, 5}, 
    {CColors.RED, 4}, 
    {CColors.RED, 3},  
    {CColors.YELLOW, 3}, 
    {CColors.YELLOW, 4}, 
    {CColors.YELLOW, 5}, 
    {CColors.YELLOW, 4}, 
    {CColors.YELLOW, 3},  
    {CColors.GREEN, 3}, 
    {CColors.GREEN, 4}, 
    {CColors.GREEN, 5}, 
    {CColors.GREEN, 4}, 
    {CColors.GREEN, 3}, 
    {CColors.CYAN, 3}, 
    {CColors.CYAN, 4}, 
    {CColors.CYAN, 5}, 
    {CColors.CYAN, 4}, 
    {CColors.CYAN, 3}, 
    {CColors.BLUE, 3}, 
    {CColors.BLUE, 4}, 
    {CColors.BLUE, 5}, 
    {CColors.BLUE, 4}, 
    {CColors.BLUE, 3}, 
    {CColors.MAGENTA, 3}, 
    {CColors.MAGENTA, 4}, 
    {CColors.MAGENTA, 5}, 
    {CColors.MAGENTA, 4}, 
    {CColors.MAGENTA, 3}, 
}

CPaint.tDemoList["rainbowwave"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowwave"].tVars = {}
    CPaint.tDemoList["rainbowwave"].tVars.tParticles = AL.Stack()
    CPaint.tDemoList["rainbowwave"].tVars.iNextY = 1
    CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus = 1
    CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = 1

    CPaint.tDemoList["rainbowwave"].SIZE = math.floor(tGame.Rows/3)
    CPaint.tDemoList["rainbowwave"].tVars.iNextY = math.floor(tGame.Rows/2 - CPaint.tDemoList["rainbowwave"].SIZE/2)

    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["rainbowwave"].tVars or CPaint.sLoadedDemo ~= "rainbowwave" then return; end

        CPaint.tDemoList["rainbowwave"].tVars.iColorOffset = CPaint.tDemoList["rainbowwave"].tVars.iColorOffset + 1

        return 200
    end)

    AL.NewTimer(200, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["rainbowwave"].tVars or CPaint.sLoadedDemo ~= "rainbowwave" then return; end

        CPaint.tDemoList["rainbowwave"].tVars.iNextY = CPaint.tDemoList["rainbowwave"].tVars.iNextY + CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus
        if CPaint.tDemoList["rainbowwave"].tVars.iNextY+CPaint.tDemoList["rainbowwave"].SIZE-1 == tGame.Rows or CPaint.tDemoList["rainbowwave"].tVars.iNextY == 1 then
           CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus = -CPaint.tDemoList["rainbowwave"].tVars.iNextYPlus 
        end

        return 200
    end)
end
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_PAINT] = function()
    for iParticleID = 1, CPaint.tDemoList["rainbowwave"].tVars.tParticles.Size() do
        local tParticle = CPaint.tDemoList["rainbowwave"].tVars.tParticles.Pop()
        for iY = tParticle.iY, tParticle.iY + CPaint.tDemoList["rainbowwave"].SIZE-1 do
            local iColorID = math.floor(((tParticle.iY + CPaint.tDemoList["rainbowwave"].SIZE-1 - iY) + CPaint.tDemoList["rainbowwave"].tVars.iColorOffset) %(#CPaint.tDemoList["rainbowwave"].COLORS))
            if iColorID == 0 then iColorID = #CPaint.tDemoList["rainbowwave"].COLORS end
            tFloor[tParticle.iX][iY].iColor = CPaint.tDemoList["rainbowwave"].COLORS[iColorID][1]
            tFloor[tParticle.iX][iY].iBright = CPaint.tDemoList["rainbowwave"].COLORS[iColorID][2]
        end
        CPaint.tDemoList["rainbowwave"].tVars.tParticles.Push(tParticle)
    end
end
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_THINK] = function()
    local tNewParticle = {}
    tNewParticle.iX = tGame.Cols+1
    tNewParticle.iY = CPaint.tDemoList["rainbowwave"].tVars.iNextY
    CPaint.tDemoList["rainbowwave"].tVars.tParticles.Push(tNewParticle)

    for iParticleID = 1, CPaint.tDemoList["rainbowwave"].tVars.tParticles.Size() do
        local tParticle = CPaint.tDemoList["rainbowwave"].tVars.tParticles.Pop()

        tParticle.iX = tParticle.iX - 1
        if tParticle.iX > 0 then
            CPaint.tDemoList["rainbowwave"].tVars.tParticles.Push(tParticle)
        end
    end

    return true
end
CPaint.tDemoList["rainbowwave"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--RAINBOWSNAKE
CPaint.tDemoList["rainbowsnake"] = {}
CPaint.tDemoList["rainbowsnake"].THINK_DELAY = 30
CPaint.tDemoList["rainbowsnake"].START_COLORS = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}}
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowsnake"].tVars = {}
    CPaint.tDemoList["rainbowsnake"].tVars.tColor = CPaint.tDemoList["rainbowsnake"].START_COLORS[math.random(1,#CPaint.tDemoList["rainbowsnake"].START_COLORS)]
    CPaint.tDemoList["rainbowsnake"].tVars.iX = 0
    CPaint.tDemoList["rainbowsnake"].tVars.iY = 1
    CPaint.tDemoList["rainbowsnake"].tVars.tBlocks = {}
    CPaint.tDemoList["rainbowsnake"].tVars.tParticles = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX][iY] = CColors.NONE
        end
    end

    AL.NewTimer(10, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["rainbowsnake"].tVars or CPaint.sLoadedDemo ~= "rainbowsnake" then return; end

        CPaint.tDemoList["rainbowsnake"].tVars.tColor = RGBRainbowNextColor(CPaint.tDemoList["rainbowsnake"].tVars.tColor,1)

        return 10
    end)
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[iX][iY]
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_THINK] = function()
    CPaint.tDemoList["rainbowsnake"].tVars.iX = CPaint.tDemoList["rainbowsnake"].tVars.iX + 1
    if CPaint.tDemoList["rainbowsnake"].tVars.iX > tGame.Cols then CPaint.tDemoList["rainbowsnake"].tVars.iX = 1; CPaint.tDemoList["rainbowsnake"].tVars.iY = CPaint.tDemoList["rainbowsnake"].tVars.iY + 1; end    
    if CPaint.tDemoList["rainbowsnake"].tVars.iY > tGame.Rows then CPaint.tDemoList["rainbowsnake"].tVars.iY = 1; end

    CPaint.tDemoList["rainbowsnake"].tVars.tBlocks[CPaint.tDemoList["rainbowsnake"].tVars.iX][CPaint.tDemoList["rainbowsnake"].tVars.iY] = tonumber(RGBTableToHex(CPaint.tDemoList["rainbowsnake"].tVars.tColor))

    return true
end
CPaint.tDemoList["rainbowsnake"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--COLORSNAKE
CPaint.tDemoList["colorsnake"] = {}
CPaint.tDemoList["colorsnake"].THINK_DELAY = 30
CPaint.tDemoList["colorsnake"].START_COLORS = {"0x0088FF", "0xFFAA00", "0xFF7700", "0xFF0033", "0x9911AA", "0xAADD22"}
CPaint.tDemoList["colorsnake"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["colorsnake"].tVars = {}
    CPaint.tDemoList["colorsnake"].tVars.iColor = tonumber(CPaint.tDemoList["colorsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["colorsnake"].START_COLORS)])
    CPaint.tDemoList["colorsnake"].tVars.iColorCount = 0
    CPaint.tDemoList["colorsnake"].tVars.iX = 0
    CPaint.tDemoList["colorsnake"].tVars.iY = 1
    CPaint.tDemoList["colorsnake"].tVars.tBlocks = {}
    CPaint.tDemoList["colorsnake"].tVars.tParticles = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX][iY] = CColors.NONE
        end
    end

    AL.NewTimer(10, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["colorsnake"].tVars or CPaint.sLoadedDemo ~= "colorsnake" then return; end

        CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 1
        CPaint.tDemoList["colorsnake"].tVars.iColorCount = CPaint.tDemoList["colorsnake"].tVars.iColorCount + 1
        if CPaint.tDemoList["colorsnake"].tVars.iColorCount >= 255 then 
            if math.random(1,2) == 1 then
                CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 1600255
            else
                CPaint.tDemoList["colorsnake"].tVars.iColor = CPaint.tDemoList["colorsnake"].tVars.iColor - 3200255
            end
            if CPaint.tDemoList["colorsnake"].tVars.iColor <= 0 then
                CPaint.tDemoList["colorsnake"].tVars.iColor = tonumber(CPaint.tDemoList["colorsnake"].START_COLORS[math.random(1, #CPaint.tDemoList["colorsnake"].START_COLORS)])
            end
            CPaint.tDemoList["colorsnake"].tVars.iColorCount = 0
        end

        return 10
    end)
end
CPaint.tDemoList["colorsnake"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = CPaint.tDemoList["colorsnake"].tVars.tBlocks[iX][iY]
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end
end
CPaint.tDemoList["colorsnake"][CPaint.FUNC_THINK] = function()
    CPaint.tDemoList["colorsnake"].tVars.iX = CPaint.tDemoList["colorsnake"].tVars.iX + 1
    if CPaint.tDemoList["colorsnake"].tVars.iX > tGame.Cols then CPaint.tDemoList["colorsnake"].tVars.iX = 1; CPaint.tDemoList["colorsnake"].tVars.iY = CPaint.tDemoList["colorsnake"].tVars.iY + 1; end    
    if CPaint.tDemoList["colorsnake"].tVars.iY > tGame.Rows then CPaint.tDemoList["colorsnake"].tVars.iY = 1; end

    CPaint.tDemoList["colorsnake"].tVars.tBlocks[CPaint.tDemoList["colorsnake"].tVars.iX][CPaint.tDemoList["colorsnake"].tVars.iY] = CPaint.tDemoList["colorsnake"].tVars.iColor

    return true
end
--//

--RAINBOWDEMO
CPaint.tDemoList["rainbowdemo"] = {}
CPaint.tDemoList["rainbowdemo"].THINK_DELAY = 120
CPaint.tDemoList["rainbowdemo"].NEARTABLES = {{0,-1},{-1,0},{1,0},{0,1},} 
CPaint.tDemoList["rainbowdemo"].START_COLORS = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}}
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbowdemo"].tVars = {}
    CPaint.tDemoList["rainbowdemo"].tVars.tClicked = {}

    for iX = 1, tGame.Cols do
        CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX] = {}
        for iY = 1, tGame.Rows do
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY] = {}
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = false
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = {255,0,0}
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = tConfig.Bright
        end
    end
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked then
                tFloor[iX][iY].iColor = tonumber(RGBTableToHex(CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor))
                tFloor[iX][iY].iBright = CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright
            end
        end
    end
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_THINK] = function()

    return true
end
CPaint.tDemoList["rainbowdemo"][CPaint.FUNC_CLICK] = function(iX, iY)
    if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked then return; end

    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = true
    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = tConfig.Bright

    CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = CPaint.tDemoList["rainbowdemo"].START_COLORS[math.random(1,#CPaint.tDemoList["rainbowdemo"].START_COLORS)]
    for iNear = 1, #CPaint.tDemoList["rainbowdemo"].NEARTABLES do
        local iXPlus, iYPlus = CPaint.tDemoList["rainbowdemo"].NEARTABLES[iNear][1], CPaint.tDemoList["rainbowdemo"].NEARTABLES[iNear][2]
        if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus] and CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus] and CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus].bClicked then
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].tColor = RGBRainbowNextColor(CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX+iXPlus][iY+iYPlus].tColor, 10)
            break;
        end
    end

    AL.NewTimer(1000, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["rainbowdemo"].tVars or CPaint.sLoadedDemo ~= "rainbowdemo" then return; end

        if CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright > 1 then
            CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright = CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].iBright-1 
            return 100; 
        end

        CPaint.tDemoList["rainbowdemo"].tVars.tClicked[iX][iY].bClicked = false
        return nil;
    end)
end
--//

--RAINBOW
CPaint.tDemoList["rainbow"] = {}
CPaint.tDemoList["rainbow"].THINK_DELAY = 100
CPaint.tDemoList["rainbow"].COLOR = "0xffffff"
CPaint.tDemoList["rainbow"].COLORS = {CColors.WHITE, CColors.CYAN, CColors.BLUE, CColors.MAGENTA, CColors.RED, CColors.YELLOW, CColors.GREEN}
CPaint.tDemoList["rainbow"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["rainbow"].tVars = {}

    CPaint.tDemoList["rainbow"].tVars.tColors = {}
    for iColorID = 1, #CPaint.tDemoList["rainbow"].COLORS do
        for iBright = CColors.BRIGHT30, CColors.BRIGHT100 do
            table.insert(CPaint.tDemoList["rainbow"].tVars.tColors, {iColor = CPaint.tDemoList["rainbow"].COLORS[iColorID], iBright = iBright})
        end
        for iBright = CColors.BRIGHT100, CColors.BRIGHT30, -1 do
            table.insert(CPaint.tDemoList["rainbow"].tVars.tColors, {iColor = CPaint.tDemoList["rainbow"].COLORS[iColorID], iBright = iBright})
        end
    end

    CPaint.tDemoList["rainbow"].tVars.iColorOffset = 0
end
CPaint.tDemoList["rainbow"][CPaint.FUNC_PAINT] = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            local id = tonumber((iX+iY+CPaint.tDemoList["rainbow"].tVars.iColorOffset) % #CPaint.tDemoList["rainbow"].tVars.tColors + 1)
            tFloor[iX][iY].iColor = CPaint.tDemoList["rainbow"].tVars.tColors[id].iColor
            tFloor[iX][iY].iBright = CPaint.tDemoList["rainbow"].tVars.tColors[id].iBright
        end
    end

    for iButtonID, tButton in pairs(tButtons) do
        local id = tonumber((iButtonID+CPaint.tDemoList["rainbow"].tVars.iColorOffset) % #CPaint.tDemoList["rainbow"].tVars.tColors + 1)
        tButtons[iButtonID].iColor = CPaint.tDemoList["rainbow"].tVars.tColors[id].iColor
        tButtons[iButtonID].iBright = CPaint.tDemoList["rainbow"].tVars.tColors[id].iBright
    end
end
CPaint.tDemoList["rainbow"][CPaint.FUNC_THINK] = function()
    CPaint.tDemoList["rainbow"].tVars.iColorOffset = CPaint.tDemoList["rainbow"].tVars.iColorOffset + 1

    return true
end
CPaint.tDemoList["rainbow"][CPaint.FUNC_CLICK] = function(iX, iY)
    
end
--//

--WATERCIRCLES
CPaint.tDemoList["watercircles"] = {}
CPaint.tDemoList["watercircles"].THINK_DELAY = 120
CPaint.tDemoList["watercircles"].COLORS = {CColors.WHITE, CColors.CYAN, CColors.BLUE, CColors.MAGENTA, CColors.RED, CColors.YELLOW, CColors.GREEN}
CPaint.tDemoList["watercircles"][CPaint.FUNC_LOAD] = function()
    CPaint.tDemoList["watercircles"].tVars = {}
    CPaint.tDemoList["watercircles"].tVars.tCircles = AL.Stack()
    CPaint.tDemoList["watercircles"].tVars.iLastX = -1
    CPaint.tDemoList["watercircles"].tVars.iLastY = -1
    CPaint.tDemoList["watercircles"].tVars.bCD = false
end
CPaint.tDemoList["watercircles"][CPaint.FUNC_PAINT] = function()
    for iCircleId = 1, CPaint.tDemoList["watercircles"].tVars.tCircles.Size() do
        local tCircle = CPaint.tDemoList["watercircles"].tVars.tCircles.Pop()

        local function paintCirclePixel(iX, iY)
            for iX2 = iX-1, iX+1 do
                for iY2 = iY-1, iY+1 do
                    if tFloor[iX2] and tFloor[iX2][iY2] then
                        tFloor[iX2][iY2].iColor = tCircle.iColor
                        
                        tFloor[iX2][iY2].iBright = tConfig.Bright-2
                        if iX2 == iX or iY2 == iY then
                            tFloor[iX2][iY2].iBright = tConfig.Bright
                        end
                    end
                end
            end
        end

        local iXM = tCircle.iX
        local iYM = tCircle.iY
        local iR = tCircle.iSize

        local iX = -iR
        local iY = 0
        local iR2 = 2-2*iR

        repeat
            paintCirclePixel(iXM-iX, iYM+iY)
            paintCirclePixel(iXM-iY, iYM-iX)
            paintCirclePixel(iXM+iX, iYM-iY)
            paintCirclePixel(iXM+iY, iYM+iX)

            iR = iR2
            if iR <= iY then 
                iY = iY+1
                iR2 = iR2 + (iY * 2 + 1) 
            end
            if iR > iX or iR2 > iY then 
                iX = iX+1
                iR2 = iR2 + (iX * 2 + 1) 
            end
        until iX > 0

        CPaint.tDemoList["watercircles"].tVars.tCircles.Push(tCircle)
    end
end
CPaint.tDemoList["watercircles"][CPaint.FUNC_THINK] = function()
    for iCircleId = 1, CPaint.tDemoList["watercircles"].tVars.tCircles.Size() do
        local tCircle = CPaint.tDemoList["watercircles"].tVars.tCircles.Pop()
        tCircle.iSize = tCircle.iSize + 1

        if tCircle.iSize < math.floor(tGame.Cols*1.5) then
            CPaint.tDemoList["watercircles"].tVars.tCircles.Push(tCircle)
        end 
    end

    return true
end
CPaint.tDemoList["watercircles"][CPaint.FUNC_CLICK] = function(iX, iY)
    if CPaint.tDemoList["watercircles"].tVars.bCD or (iX == CPaint.tDemoList["watercircles"].tVars.iLastX and iY == CPaint.tDemoList["watercircles"].tVars.iLastY) then return; end
    CPaint.tDemoList["watercircles"].tVars.iLastX = iX; CPaint.tDemoList["watercircles"].tVars.iLastY = iY;

    local tNewCircle = {}
    tNewCircle.iX = iX
    tNewCircle.iY = iY
    tNewCircle.iSize = 1
    tNewCircle.iColor = CPaint.tDemoList["watercircles"].COLORS[math.random(1,#CPaint.tDemoList["watercircles"].COLORS)]
    CPaint.tDemoList["watercircles"].tVars.tCircles.Push(tNewCircle)

    CPaint.tDemoList["watercircles"].tVars.bCD = true
    AL.NewTimer(400, function()
        if iGameState ~= GAMESTATE_GAME or not CPaint.tDemoList["watercircles"].tVars or CPaint.sLoadedDemo ~= "watercircles" then return; end

        CPaint.tDemoList["watercircles"].tVars.bCD = false
    end)
end
--//
----//

--PICTURES
tPictures = {}
tPictures["arrow1"] =
{
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0XFFFFFF","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"},         
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0XFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}
}
tPictures["arrow2"] =
{
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0x000000","0x000000","0x000000","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0x000000","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0x000000","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0x000000","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0x000000","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0XFFFFFF","0x000000","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0x000000","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0XFFFFFF","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0XFFFFFF","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0x000000","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}        
}
tPictures["arrow3"] =
{
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1","0xFFFFFF","0xFFFFFF","0xEMPTY1","0xEMPTY1"}, 
    {"0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1","0xEMPTY1"}
}
----//

--UTIL прочие утилиты
function RGBToHex(r,g,b)
    local rgb = (r * 0x10000) + (g * 0x100) + b
    return "0x"..string.format("%06x", rgb)
end

function RGBTableToHex(tRGB)
    return RGBToHex(tRGB[1],tRGB[2],tRGB[3])
end

function RGBRainbowNextColor(tRGBIn, iMultiplier)
    local tRGB = {0,0,0}
    if iMultiplier == nil then iMultiplier = 1 end

    if (tRGBIn[1] > 0 and tRGBIn[3] == 0) then
        tRGB[1] = tRGBIn[1] - iMultiplier
        tRGB[2] = tRGBIn[2] + iMultiplier
    end

    if (tRGBIn[2] > 0 and tRGBIn[1] == 0) then
        tRGB[2] = tRGBIn[2] - iMultiplier
        tRGB[3] = tRGBIn[3] + iMultiplier
    end

    if (tRGBIn[3] > 0 and tRGBIn[2] == 0) then
        tRGB[1] = tRGBIn[1] + iMultiplier
        tRGB[3] = tRGBIn[3] - iMultiplier
    end

    return tRGB
end

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
            tFloor[iX][iY].iParticleID = 0
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

        if iGameState == GAMESTATE_GAME and click.Click then
            CPaint.DemoClick(click.X, click.Y)
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
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end