-- Название: Хомяк накопитель
-- Автор: @ProAlgebra (телеграм)
-- Описание механики: Дети кликают на пиксели, в зависимости от цвета начисляется разное количество очков. Красный даёт 3, зелёный 1
math.randomseed(os.time())
require("avonlib")
local iPrevTickTime = 0

local log = require("log")
local inspect = require("inspect")
local help = require("help")
local json = require("json")
local time = require("time")
local audio = require("audio")
local colors = require("colors")

local GameObj = {
    Cols = 24, -- пикселей по горизонтали (X), обязательные параметр для всех игр
    Rows = 15, -- пикселей по вертикали (Y), обязательные параметр для всех игр
    Buttons = {2, 6, 10, 14, 18, 22, 26, 30, 34, 42, 46, 50, 54, 58, 62, 65, 69, 73, 77}, -- номера кнопок в комнате
    Colors = { -- массив градиента цветов для радуги
    }
}

local GameConfigObj = {
    Delay = 100, -- задержка отрисовки в мс
}

local GameStats = {
    StageLeftDuration = 0, -- seconds
    StageTotalDuration = 0, -- seconds
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = colors.GREEN },
    },
    TargetScore = 1,
    StageNum = 0,
    TotalStages = 4,
    TargetColor = colors.NONE,
    ScoreboardVariant = 4,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = colors.NONE,
}

local FloorMatrix = {} -- матрица пола
local ButtonsList = {} -- список кнопок
local Pixel = { -- пиксель тип
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = 0,
    Defect = false
}
local GradientLength = 0
local GradientOffset = 0
local LastChangesTimestamp = 0

local bGamePaused = false
local bGameOver = false

function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    for x=1,GameObj.Cols do
        FloorMatrix[x] = {}    -- новый столбец
        for y=1,GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel) -- заполняем нулевыми пикселями
        end
    end

    for i, num in pairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel) -- тип аналогичен пикселю
    end
    audio.PlayVoicesSyncFromScratch("hamster/hamster-guide.mp3") -- инструкция по игре "Кликай на залёные и голубые панели, чтобы прокачивать своего хомяка. Постарайтесь прокачать его как можно больше за меньшее время"
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
    iPrevTickTime = time.unix()
end

gameState = {
    State = -1,
    Tick = 0,
}

function SwitchStage()
    gameState.State = gameState.State + 1
    if gameState.State == 3 then
        GameStats.TargetScore = GameConfigObj.level2
    end
    if gameState.State == 5 then
        GameStats.TargetScore = GameConfigObj.level3
    end
    if gameState.State >= 6 then
        GameStats.TargetScore = GameConfigObj.level4
    end
end

function NextTick()
    AL.CountTimers((time.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = time.unix()

    if gameState.State == -1 then 
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Defect == false then
                 ButtonsList[num].Color = colors.BLUE
                 ButtonsList[num].Bright = GameConfigObj.Bright
            end
        end
        AutoStartTimer()
        gameState.State = 0
    end
    if gameState.State == 0 then 
        for i, num in pairs(GameObj.Buttons) do
            if ButtonsList[num].Defect == true then
                 ButtonsList[num].Color = colors.NONE
                 ButtonsList[num].Bright = 0
            end
        end
    end
    if gameState.State >= 1 then
        for i, num in pairs(GameObj.Buttons) do
            ButtonsList[num].Color = colors.NONE
            ButtonsList[num].Bright = GameConfigObj.Bright
        end
    end

    if not bGameOver and gameState.Tick < time.unix() then
        gameState.Tick = time.unix() + GameConfigObj.delay
        ReloadField()
    end

    if not bGameOver and GameStats.StageNum > 0 and GameStats.Players[1].Score >= GameConfigObj["level"..GameStats.StageNum] then
        if GameStats.StageNum < 4 then
            LoadNextLevel()
            audio.PlaySystemAsync(audio.STAGE_DONE)
        elseif GameStats.StageNum == 4 then
            WinGame()
        end
    end

    if gameState.State == 100 then
        tGameResults.AfterDelay = true
        return tGameResults 
    end

    if gameState.State == 1000 then
        tGameResults.AfterDelay = false
        return tGameResults
    end    
end

function AutoStartTimer()
    if GameObj.AutoStartTimer and GameObj.AutoStartTimer > 0 then
        AL.NewTimer(GameObj.AutoStartTimer*1000, function()
            if gameState.State < 1 then
                PlayerStartGame()
            end
        end)
    end
end

function PlayerStartGame()
    gameState.State = 1
    audio.PlayRandomBackground()
    LoadNextLevel()
end

function LoadNextLevel()
    GameStats.StageNum = GameStats.StageNum + 1
    local iLevel = GameStats.StageNum
    GameStats.Players[1].Score = 0
    GameStats.TargetScore = GameConfigObj["level"..iLevel]
    LoadLevelPainting(iLevel)
    ReloadField()   
end

function LoadLevelPainting(iLevel)
    for x,mass in pairs(GameObj["level"..iLevel]) do
        for y,state in pairs(mass) do
            FloorMatrix[y][x].Color = tonumber(state)
            FloorMatrix[y][x].Bright = GameConfigObj.Bright
        end
    end
end

function WinGame()
    bGameOver = true
    tGameResults.Won = true 
    tGameResults.Color = colors.GREEN

    audio.StopBackground()
    audio.PlayVoicesSync(audio.VICTORY)

    LoadLevelPainting(5)

    gameState.State = 100
    AL.NewTimer(10000, function()
        gameState.State = 1000
    end)
end

function ReloadField()
    for y = 1, GameObj.Rows do
        for x = GameObj.Cols-5,GameObj.Cols do
            if FloorMatrix[x][y].Color == colors.GREEN or FloorMatrix[x][y].Color == colors.CYAN then
                FloorMatrix[x][y].Color = colors.NONE
            end

            if not FloorMatrix[x][y].Defect  and FloorMatrix[x][y].Color == colors.NONE then
                if GameStats.StageNum >= 1 then
                    if math.random(0,100) < 20 then
                        FloorMatrix[x][y].Color = colors.GREEN
                        FloorMatrix[x][y].Bright = GameConfigObj.Bright
                    end
                end
                if GameStats.StageNum >= 3 then
                    random = math.random(0,100)
                    if random < 10 + (gameState.State * 2) then
                        FloorMatrix[x][y].Color = colors.GREEN
                        FloorMatrix[x][y].Bright = GameConfigObj.Bright
                    end
                    if random > 90 - (gameState.State * 3) then
                        FloorMatrix[x][y].Color = colors.CYAN
                        FloorMatrix[x][y].Bright = GameConfigObj.Bright
                    end
                end
            end
        end
    end
end

function RangeFloor(setPixel, setButton)
    for x=1,GameObj.Cols do
        for y=1,GameObj.Rows do
            setPixel(x,y,FloorMatrix[x][y].Color,FloorMatrix[x][y].Bright)
        end
    end
    
    for num, button in pairs(ButtonsList) do
        setButton(num,button.Color,button.Bright)
    end
end

function GetStats()
    return GameStats
end

function PixelClick(click)
    if not FloorMatrix[click.X] or not FloorMatrix[click.X][click.y] or bGamePaused or not click.Click or click.Weight < 3 or FloorMatrix[click.X][click.y].Defect or bGameOver then return; end

    if time.unix() < FloorMatrix[click.X][click.Y].Click + 1  then
        FloorMatrix[click.X][click.Y].click = time.unix()
        return
    end
    FloorMatrix[click.X][click.Y].Click = time.unix()
    if FloorMatrix[click.X][click.Y].Color == colors.GREEN then
        FloorMatrix[click.X][click.Y].Color = colors.NONE
        audio.PlaySystemAsync(audio.CLICK)
        GameStats.Players[1].Score = GameStats.Players[1].Score + GameConfigObj.greenPoint
        tGameResults.Score = tGameResults.Score + GameConfigObj.greenPoint
    end
    if FloorMatrix[click.X][click.Y].Color == colors.CYAN then
        FloorMatrix[click.X][click.Y].Color = colors.NONE
        audio.PlaySystemAsync(audio.CLICK)
        GameStats.Players[1].Score = GameStats.Players[1].Score + GameConfigObj.cyanPoint
        tGameResults.Score = tGameResults.Score + GameConfigObj.cyanPoint
    end 
end

function ButtonClick(click)
    if not ButtonsList[click.Button] or not click.Click or gameState.State >= 1 or ButtonsList[click.Button].Defect then return; end

    PlayerStartGame()
end

function DefectPixel(defect)
    if FloorMatrix[defect.X] and FloorMatrix[defect.X][defect.Y] then
        FloorMatrix[defect.X][defect.Y].Defect = defect.Defect
    end
end

function DefectButton(defect)
    if ButtonsList[defect.Button] then
        ButtonsList[defect.Button].Defect = defect.Defect
    end
end
