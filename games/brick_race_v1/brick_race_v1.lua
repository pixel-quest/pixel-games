-- Название: Brick Race
-- Автор: OpenAI Assistant
-- Описание механики: гонка в стиле brick game. Игрок двигает машинку по вертикали и избегает машинок/препятствий.

local json = require("json")
local time = require("time")
local help = require("help")
local colors = require("colors")

local GameObj = {
    Cols = 24,
    Rows = 15,
    Buttons = {},
}

local GameConfigObj = {}

local GameStats = {
    StageLeftDuration = 0,
    StageTotalDuration = 0,
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = {
        { Score = 0, Lives = 0, Color = colors.GREEN },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
        { Score = 0, Lives = 0, Color = colors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = colors.NONE,
}

local GameResults = {
    Won = false,
}

local FloorMatrix = {}
local ButtonsList = {}
local Pixel = {
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false,
    Defect = false,
}

local CAR_SHAPE = {
    {1, 0, 1, 0},
    {1, 1, 1, 1},
    {1, 0, 1, 0},
}

local CAR_WIDTH = 4
local CAR_HEIGHT = 3

local BOOSTER_SIZE = 2

local State = {
    LastTick = 0,
    PlayerX = 1,
    PlayerY = 1,
    TargetPlayerY = 1,
    Speed = 0,
    SpeedTimer = 0,
    ObstacleTimer = 0,
    BoosterTimer = 0,
    MoveAccumulator = 0,
    BorderOffset = 0,
    BoosterActiveUntil = 0,
    CrashCooldownUntil = 0,
    Obstacles = {},
    Boosters = {},
    Lives = 3,
    RoadTop = 1,
    RoadBottom = 1,
    Lanes = {},
}

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function ClearFloor()
    for x = 1, GameObj.Cols do
        for y = 1, GameObj.Rows do
            FloorMatrix[x][y].Color = colors.NONE
            FloorMatrix[x][y].Bright = colors.BRIGHT0
        end
    end
end

local function DrawShape(startX, startY, shape, color, bright)
    for y = 1, #shape do
        for x = 1, #shape[y] do
            if shape[y][x] == 1 then
                local drawX = startX + x - 1
                local drawY = startY + y - 1
                if drawX >= 1 and drawX <= GameObj.Cols and drawY >= 1 and drawY <= GameObj.Rows then
                    FloorMatrix[drawX][drawY].Color = color
                    FloorMatrix[drawX][drawY].Bright = bright
                end
            end
        end
    end
end

local function DrawBooster(startX, startY, color, bright)
    for y = 0, BOOSTER_SIZE - 1 do
        for x = 0, BOOSTER_SIZE - 1 do
            local drawX = startX + x
            local drawY = startY + y
            if drawX >= 1 and drawX <= GameObj.Cols and drawY >= 1 and drawY <= GameObj.Rows then
                FloorMatrix[drawX][drawY].Color = color
                FloorMatrix[drawX][drawY].Bright = bright
            end
        end
    end
end

local function RectsOverlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
    return ax1 <= bx2 and ax2 >= bx1 and ay1 <= by2 and ay2 >= by1
end

local function IsAreaFree(x1, y1, x2, y2)
    for _, obstacle in ipairs(State.Obstacles) do
        if RectsOverlap(x1, y1, x2, y2, obstacle.X, obstacle.Y, obstacle.X + CAR_WIDTH - 1, obstacle.Y + CAR_HEIGHT - 1) then
            return false
        end
    end

    for _, booster in ipairs(State.Boosters) do
        if RectsOverlap(x1, y1, x2, y2, booster.X, booster.Y, booster.X + BOOSTER_SIZE - 1, booster.Y + BOOSTER_SIZE - 1) then
            return false
        end
    end

    return true
end

local function ResetAfterCrash(now)
    State.Speed = GameConfigObj.BaseSpeed
    State.SpeedTimer = GameConfigObj.SpeedIncreaseInterval
    State.ObstacleTimer = GameConfigObj.CrashSpawnDelay
    State.BoosterTimer = GameConfigObj.BoosterSpawnInterval
    State.MoveAccumulator = 0
    State.BoosterActiveUntil = 0
    State.Obstacles = {}
    State.Boosters = {}
end

local function LaneHasObstacle(laneY, minX)
    for _, obstacle in ipairs(State.Obstacles) do
        if obstacle.Y == laneY and obstacle.X >= minX then
            return true
        end
    end
    return false
end

local function SpawnObstacle()
    if #State.Obstacles >= GameConfigObj.MaxObstacles then
        return
    end

    local minY = State.RoadTop + 1
    local maxY = State.RoadBottom - CAR_HEIGHT
    if maxY < minY then
        return
    end

    for _ = 1, 6 do
        local spawnY = State.Lanes[math.random(1, #State.Lanes)] or math.random(minY, maxY)
        local spawnX = GameObj.Cols - CAR_WIDTH + 1
        local minDistanceX = spawnX - (CAR_WIDTH * 2)
        if not LaneHasObstacle(spawnY, minDistanceX)
            and IsAreaFree(spawnX, spawnY, spawnX + CAR_WIDTH - 1, spawnY + CAR_HEIGHT - 1) then
            table.insert(State.Obstacles, {
                X = spawnX,
                Y = spawnY,
                Scored = false,
            })
            return
        end
    end
end

local function SpawnBooster()
    if #State.Boosters >= GameConfigObj.MaxBoosters then
        return
    end

    local minY = State.RoadTop + 1
    local maxY = State.RoadBottom - BOOSTER_SIZE
    if maxY < minY then
        return
    end

    for _ = 1, 6 do
        local spawnY = math.random(minY, maxY)
        local spawnX = GameObj.Cols - BOOSTER_SIZE + 1
        if IsAreaFree(spawnX, spawnY, spawnX + BOOSTER_SIZE - 1, spawnY + BOOSTER_SIZE - 1) then
            table.insert(State.Boosters, {
                X = spawnX,
                Y = spawnY,
            })
            return
        end
    end
end

function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    GameConfigObj.Bright = GameConfigObj.Bright or 5
    GameConfigObj.Lives = GameConfigObj.Lives or 3
    GameConfigObj.BaseSpeed = GameConfigObj.BaseSpeed or 3
    GameConfigObj.SpeedIncreaseStep = GameConfigObj.SpeedIncreaseStep or 0.5
    GameConfigObj.SpeedIncreaseInterval = GameConfigObj.SpeedIncreaseInterval or 6
    GameConfigObj.ObstacleSpawnInterval = GameConfigObj.ObstacleSpawnInterval or 1.3
    GameConfigObj.BoosterSpawnInterval = GameConfigObj.BoosterSpawnInterval or 8
    GameConfigObj.BoosterDuration = GameConfigObj.BoosterDuration or 5
    GameConfigObj.CrashCooldown = GameConfigObj.CrashCooldown or 1.2
    GameConfigObj.CrashSpawnDelay = GameConfigObj.CrashSpawnDelay or 1.2
    GameConfigObj.PointsPerObstacle = GameConfigObj.PointsPerObstacle or 1
    GameConfigObj.PlayerMoveSpeed = GameConfigObj.PlayerMoveSpeed or 6
    GameConfigObj.MaxObstacles = GameConfigObj.MaxObstacles or 3
    GameConfigObj.MaxBoosters = GameConfigObj.MaxBoosters or 1

    for x = 1, GameObj.Cols do
        FloorMatrix[x] = {}
        for y = 1, GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel)
        end
    end

    for _, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel)
    end

    local now = time.unix()
    State.LastTick = now
    State.PlayerX = 1
    State.RoadTop = 1
    State.RoadBottom = GameObj.Rows
    State.PlayerY = math.floor((GameObj.Rows - CAR_HEIGHT) / 2) + 1
    State.TargetPlayerY = State.PlayerY
    State.Speed = GameConfigObj.BaseSpeed
    State.SpeedTimer = GameConfigObj.SpeedIncreaseInterval
    State.ObstacleTimer = GameConfigObj.ObstacleSpawnInterval
    State.BoosterTimer = GameConfigObj.BoosterSpawnInterval
    State.MoveAccumulator = 0
    State.BorderOffset = 0
    State.BoosterActiveUntil = 0
    State.CrashCooldownUntil = 0
    State.Obstacles = {}
    State.Boosters = {}
    State.Lives = GameConfigObj.Lives
    State.Lanes = {}
    local laneY = State.RoadTop + 1
    local laneStep = CAR_HEIGHT + 1
    while laneY <= State.RoadBottom - CAR_HEIGHT do
        table.insert(State.Lanes, laneY)
        laneY = laneY + laneStep
    end

    GameStats.CurrentLives = State.Lives
    GameStats.TotalLives = State.Lives
    GameStats.Players[1].Score = 0
    GameStats.Players[1].Lives = State.Lives
    GameStats.CurrentStars = 0
    GameStats.ScoreboardVariant = 0
end

function NextTick()
    local now = time.unix()
    local delta = now - State.LastTick
    if delta < 0 then
        delta = 0
    end
    State.LastTick = now

    if State.Lives <= 0 then
        GameResults.Won = false
        return GameResults
    end

    State.SpeedTimer = State.SpeedTimer - delta
    while State.SpeedTimer <= 0 do
        State.Speed = State.Speed + GameConfigObj.SpeedIncreaseStep
        State.SpeedTimer = State.SpeedTimer + GameConfigObj.SpeedIncreaseInterval
    end

    State.ObstacleTimer = State.ObstacleTimer - delta
    while State.ObstacleTimer <= 0 do
        SpawnObstacle()
        State.ObstacleTimer = State.ObstacleTimer + GameConfigObj.ObstacleSpawnInterval
    end

    State.BoosterTimer = State.BoosterTimer - delta
    while State.BoosterTimer <= 0 do
        SpawnBooster()
        State.BoosterTimer = State.BoosterTimer + GameConfigObj.BoosterSpawnInterval
    end

    State.MoveAccumulator = State.MoveAccumulator + (State.Speed * delta)
    local steps = math.floor(State.MoveAccumulator)
    if steps > 0 then
        State.MoveAccumulator = State.MoveAccumulator - steps
        State.BorderOffset = (State.BorderOffset + steps) % 3

        for i = #State.Obstacles, 1, -1 do
            local obstacle = State.Obstacles[i]
            obstacle.X = obstacle.X - steps
            if obstacle.X + CAR_WIDTH - 1 < 1 then
                table.remove(State.Obstacles, i)
            end
        end

        for i = #State.Boosters, 1, -1 do
            local booster = State.Boosters[i]
            booster.X = booster.X - steps
            if booster.X + BOOSTER_SIZE - 1 < 1 then
                table.remove(State.Boosters, i)
            end
        end
    end

    local playerX1 = State.PlayerX
    local playerY1 = State.PlayerY
    local playerX2 = State.PlayerX + CAR_WIDTH - 1
    local playerY2 = State.PlayerY + CAR_HEIGHT - 1

    local crashAvailable = now >= State.CrashCooldownUntil

    for i = #State.Boosters, 1, -1 do
        local booster = State.Boosters[i]
        local boosterX1 = booster.X
        local boosterY1 = booster.Y
        local boosterX2 = booster.X + BOOSTER_SIZE - 1
        local boosterY2 = booster.Y + BOOSTER_SIZE - 1

        if RectsOverlap(playerX1, playerY1, playerX2, playerY2, boosterX1, boosterY1, boosterX2, boosterY2) then
            State.BoosterActiveUntil = now + GameConfigObj.BoosterDuration
            table.remove(State.Boosters, i)
        end
    end

    for _, obstacle in ipairs(State.Obstacles) do
        local obstacleX1 = obstacle.X
        local obstacleY1 = obstacle.Y
        local obstacleX2 = obstacle.X + CAR_WIDTH - 1
        local obstacleY2 = obstacle.Y + CAR_HEIGHT - 1

        if crashAvailable and RectsOverlap(playerX1, playerY1, playerX2, playerY2, obstacleX1, obstacleY1, obstacleX2, obstacleY2) then
            State.Lives = State.Lives - 1
            GameStats.CurrentLives = State.Lives
            GameStats.Players[1].Lives = State.Lives
            State.CrashCooldownUntil = now + GameConfigObj.CrashCooldown
            ResetAfterCrash(now)
            break
        end
    end

    local targetMinY = State.RoadTop + 1
    local targetMaxY = State.RoadBottom - CAR_HEIGHT
    State.TargetPlayerY = Clamp(State.TargetPlayerY, targetMinY, targetMaxY)
    local moveDistance = GameConfigObj.PlayerMoveSpeed * delta
    if State.PlayerY < State.TargetPlayerY then
        State.PlayerY = math.min(State.PlayerY + moveDistance, State.TargetPlayerY)
    elseif State.PlayerY > State.TargetPlayerY then
        State.PlayerY = math.max(State.PlayerY - moveDistance, State.TargetPlayerY)
    end
    State.PlayerY = Clamp(State.PlayerY, targetMinY, targetMaxY)

    local multiplier = 1
    if now <= State.BoosterActiveUntil then
        multiplier = 2
    end

    for _, obstacle in ipairs(State.Obstacles) do
        if not obstacle.Scored and obstacle.X + CAR_WIDTH - 1 < State.PlayerX then
            obstacle.Scored = true
            GameStats.Players[1].Score = GameStats.Players[1].Score + (GameConfigObj.PointsPerObstacle * multiplier)
            GameStats.CurrentStars = GameStats.Players[1].Score
        end
    end

    ClearFloor()

    for _, booster in ipairs(State.Boosters) do
        DrawBooster(booster.X, booster.Y, colors.YELLOW, GameConfigObj.Bright)
    end

    for _, obstacle in ipairs(State.Obstacles) do
        DrawShape(obstacle.X, obstacle.Y, CAR_SHAPE, colors.RED, GameConfigObj.Bright)
    end

    DrawShape(State.PlayerX, math.floor(State.PlayerY + 0.5), CAR_SHAPE, colors.GREEN, GameConfigObj.Bright)

    for x = 1, GameObj.Cols do
        local dash = (x + State.BorderOffset) % 3
        if dash ~= 0 then
            FloorMatrix[x][State.RoadTop].Color = colors.WHITE
            FloorMatrix[x][State.RoadTop].Bright = GameConfigObj.Bright
            FloorMatrix[x][State.RoadBottom].Color = colors.WHITE
            FloorMatrix[x][State.RoadBottom].Bright = GameConfigObj.Bright
        end
    end
end

function RangeFloor(setPixel, setButton)
    for x = 1, GameObj.Cols do
        for y = 1, GameObj.Rows do
            setPixel(x, y, FloorMatrix[x][y].Color, FloorMatrix[x][y].Bright)
        end
    end

    for num, button in pairs(ButtonsList) do
        setButton(num, button.Color, button.Bright)
    end
end

function GetStats()
    return GameStats
end

function PauseGame()
    State.PauseStarted = time.unix()
end

function ResumeGame()
    if State.PauseStarted then
        local shift = time.unix() - State.PauseStarted
        State.LastTick = State.LastTick + shift
        State.BoosterActiveUntil = State.BoosterActiveUntil + shift
        State.CrashCooldownUntil = State.CrashCooldownUntil + shift
        State.PauseStarted = nil
    end
end

function SwitchStage()
end

function PixelClick(click)
    if not click.Click then
        return
    end

    local targetY = click.Y - math.floor(CAR_HEIGHT / 2)
    State.TargetPlayerY = Clamp(targetY, State.RoadTop + 1, State.RoadBottom - CAR_HEIGHT)
end

function ButtonClick(click)
    if ButtonsList[click.Button] == nil then
        return
    end
    ButtonsList[click.Button].Click = click.Click
end

function DefectPixel(defect)
    FloorMatrix[defect.X][defect.Y].Defect = defect.Defect
end

function DefectButton(defect)
    if ButtonsList[defect.Button] == nil then
        return
    end
    ButtonsList[defect.Button].Defect = defect.Defect
end
