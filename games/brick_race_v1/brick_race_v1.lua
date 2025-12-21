-- Название: Brick Race
-- Автор: @openai
-- Описание механики: одиночная гонка в стиле Brick Game с уклонением от препятствий
-- Идеи по доработке: добавить несколько режимов сложности и таблицу рекордов

math.randomseed(os.time())

local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CColors = require("colors")

local tGame = {
    Cols = 24,
    Rows = 15,
    Buttons = {},
}

local tConfig = {}

local GAMESTATE_PLAYING = 1
local GAMESTATE_GAMEOVER = 2

local PLAYER_WIDTH = 2
local PLAYER_HEIGHT = 2
local OBJECT_SIZE = 2
local BOOSTER_DURATION = 5
local INVULN_DURATION = 1
local BASE_SPEED = 2
local SPEED_INCREASE_RATE = 0.05

local iGameState = GAMESTATE_PLAYING
local iPrevTickTime = 0
local bGamePaused = false

local tFloor = {}
local tButtons = {}

local tStats = {
    StageLeftDuration = 0,
    StageTotalDuration = 0,
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = {
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
    AfterDelay = false,
    PlayersCount = 1,
    Score = 0,
    Color = CColors.GREEN,
}

local tPixel = {
    Color = CColors.NONE,
    Bright = CColors.BRIGHT0,
    Click = false,
    Defect = false,
}

local tObjects = {}
local iPlayerY = 1
local fSpeedResetTime = 0
local fSpawnTimer = 0
local fNextSpawn = 1.2
local fBoosterUntil = 0
local fInvulnUntil = 0

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function ResetRun()
    tObjects = {}
    fSpeedResetTime = CTime.unix()
    fSpawnTimer = 0
    fNextSpawn = 1.2
    fBoosterUntil = 0
    fInvulnUntil = CTime.unix() + INVULN_DURATION
end

local function GetCurrentSpeed()
    local elapsed = CTime.unix() - fSpeedResetTime
    if elapsed < 0 then
        elapsed = 0
    end
    return BASE_SPEED + elapsed * SPEED_INCREASE_RATE
end

local function SpawnObject()
    local roll = math.random()
    local objectType = "enemy"
    if roll < 0.15 then
        objectType = "booster"
    elseif roll < 0.4 then
        objectType = "obstacle"
    end

    local size = OBJECT_SIZE
    local y = math.random(1, tGame.Rows - size + 1)
    local x = tGame.Cols - size + 1

    for _, object in ipairs(tObjects) do
        if object.x > tGame.Cols - size * 2 and not (y + size - 1 < object.y or y > object.y + object.h - 1) then
            return
        end
    end

    table.insert(tObjects, {
        x = x,
        y = y,
        w = size,
        h = size,
        type = objectType,
    })
end

local function Intersects(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function UpdateObjects(delta)
    local speed = GetCurrentSpeed()
    local multiplier = 1
    if CTime.unix() < fBoosterUntil then
        multiplier = 2
    end

    local i = 1
    while i <= #tObjects do
        local object = tObjects[i]
        object.x = object.x - speed * delta

        if object.x + object.w < 1 then
            if object.type ~= "booster" then
                tStats.Players[1].Score = tStats.Players[1].Score + multiplier
            end
            table.remove(tObjects, i)
        else
            i = i + 1
        end
    end
end

local function HandleCollisions()
    local player = { x = 1, y = iPlayerY, w = PLAYER_WIDTH, h = PLAYER_HEIGHT }
    local i = 1
    while i <= #tObjects do
        local object = tObjects[i]
        if Intersects(player, object) then
            if object.type == "booster" then
                fBoosterUntil = CTime.unix() + BOOSTER_DURATION
                table.remove(tObjects, i)
            elseif CTime.unix() >= fInvulnUntil then
                tStats.CurrentLives = tStats.CurrentLives - 1
                tStats.Players[1].Lives = tStats.CurrentLives
                if tStats.CurrentLives <= 0 then
                    iGameState = GAMESTATE_GAMEOVER
                    tGameResults.Score = tStats.Players[1].Score
                    return
                end
                ResetRun()
                return
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

local function DrawObject(object, color)
    for x = math.floor(object.x), math.floor(object.x + object.w - 1) do
        for y = object.y, object.y + object.h - 1 do
            if x >= 1 and x <= tGame.Cols and y >= 1 and y <= tGame.Rows then
                tFloor[x][y].Color = color
                tFloor[x][y].Bright = tConfig.Bright
            end
        end
    end
end

local function DrawFrame()
    for x = 1, tGame.Cols do
        for y = 1, tGame.Rows do
            tFloor[x][y].Color = CColors.NONE
            tFloor[x][y].Bright = tConfig.Bright
        end
    end

    for _, object in ipairs(tObjects) do
        if object.type == "enemy" then
            DrawObject(object, CColors.RED)
        elseif object.type == "obstacle" then
            DrawObject(object, CColors.WHITE)
        elseif object.type == "booster" then
            DrawObject(object, CColors.YELLOW)
        end
    end

    local player = { x = 1, y = iPlayerY, w = PLAYER_WIDTH, h = PLAYER_HEIGHT }
    DrawObject(player, CColors.GREEN)
end

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    if tConfig.Bright == nil then
        tConfig.Bright = CColors.BRIGHT70
    end

    for x = 1, tGame.Cols do
        tFloor[x] = {}
        for y = 1, tGame.Rows do
            tFloor[x][y] = CHelp.ShallowCopy(tPixel)
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tPixel)
    end

    tStats.CurrentLives = tConfig.PlayerLives or 3
    tStats.TotalLives = tStats.CurrentLives
    tStats.Players[1].Lives = tStats.CurrentLives
    tStats.Players[1].Score = 0
    tStats.Players[1].Color = CColors.GREEN

    iPlayerY = math.floor((tGame.Rows - PLAYER_HEIGHT) / 2) + 1
    fSpeedResetTime = CTime.unix()
    fSpawnTimer = 0
    fNextSpawn = 1.2
    fBoosterUntil = 0
    fInvulnUntil = 0

    iGameState = GAMESTATE_PLAYING
    iPrevTickTime = CTime.unix()
end

function NextTick()
    if bGamePaused then
        return
    end

    if iGameState == GAMESTATE_GAMEOVER then
        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
        return tGameResults
    end

    local now = CTime.unix()
    local delta = now - iPrevTickTime
    if delta < 0 then
        delta = 0
    end
    iPrevTickTime = now

    fSpawnTimer = fSpawnTimer + delta
    local speed = GetCurrentSpeed()
    fNextSpawn = math.max(0.6, 1.6 - speed * 0.1 + math.random() * 0.2)
    if fSpawnTimer >= fNextSpawn then
        fSpawnTimer = 0
        SpawnObject()
    end

    UpdateObjects(delta)
    HandleCollisions()
    DrawFrame()
end

function RangeFloor(setPixel, setButton)
    for x = 1, tGame.Cols do
        for y = 1, tGame.Rows do
            setPixel(x, y, tFloor[x][y].Color, tFloor[x][y].Bright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.Color, tButton.Bright)
    end
end

function GetStats()
    return tStats
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
    iPrevTickTime = CTime.unix()
end

function SwitchStage()
end

function PixelClick(tClick)
    if tClick.Click then
        iPlayerY = Clamp(tClick.Y, 1, tGame.Rows - PLAYER_HEIGHT + 1)
    end
end

function ButtonClick(tClick)
end

function DefectPixel(tDefect)
end

function DefectButton(tDefect)
end
