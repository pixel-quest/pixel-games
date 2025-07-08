-- Название: Проигрыш видео
-- Автор: @VPreobrazhenskiy93 (телеграм)
-- Описание механики: проигрывает видео на фронте
-- Идеи по доработке: световые эффекты на полу, плюс управление освещением в игровой

local log = require("log")
local inspect = require("inspect")
local help = require("help")
local json = require("json")
local time = require("time")
local audio = require("audio")
local colors = require("colors")
local video = require("video")

local GameObj = {
    Cols = 24,
    Rows = 15,
    Buttons = {2, 6, 10, 14, 18, 22, 26, 30, 34, 42, 46, 50, 54, 58, 62, 65, 69, 73, 77},
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
        { Score = 0, Lives = 0, Color = colors.NONE },
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

-- Управление видео
local videoIndex = 1
local videoPlaying = false
local videoEndTime = nil
local startDelayEndTime = nil
local pausedAt = nil

local function PlayCurrentVideo()
    local v = GameObj.Videos[videoIndex]
    if not v then return end

    video.Play(v.Name)
    if v.Voice then
        audio.PlayVoicesSyncFromScratch(v.Voice)
    end
    videoEndTime = time.unix() + v.Duration
    videoPlaying = true
end

function StartGame(gameJson, gameConfigJson)
    GameObj = json.decode(gameJson)
    GameConfigObj = json.decode(gameConfigJson)

    for x = 1, GameObj.Cols do
        FloorMatrix[x] = {}
        for y = 1, GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel)
        end
    end

    for _, num in ipairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel)
    end

    if GameObj.Videos and #GameObj.Videos > 0 then
        startDelayEndTime = time.unix() + 1
        videoIndex = 1
        videoPlaying = false
        videoEndTime = nil
    else
        GameResults.Won = true
    end
end

function NextTick()
    if pausedAt then return end

    if startDelayEndTime and time.unix() >= startDelayEndTime then
        PlayCurrentVideo()
        startDelayEndTime = nil
    end

    if videoPlaying and videoEndTime and time.unix() >= videoEndTime then
        videoIndex = videoIndex + 1
        if videoIndex <= #GameObj.Videos then
            PlayCurrentVideo()
        else
            videoPlaying = false
            video.Stop()
            GameResults.Won = true
            return GameResults
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
    if videoPlaying and not pausedAt then
        pausedAt = time.unix()
        video.Pause()
    end
end

function ResumeGame()
    if videoPlaying and pausedAt then
        local pausedDuration = time.unix() - pausedAt
        videoEndTime = videoEndTime + pausedDuration
        pausedAt = nil
    end
    video.Resume()
end

function SwitchStage()
end

function PixelClick(click)
    FloorMatrix[click.X][click.Y].Click = click.Click
end

function ButtonClick(click)
    if ButtonsList[click.Button] == nil then return end
    ButtonsList[click.Button].Click = click.Click
end

function DefectPixel(defect)
    FloorMatrix[defect.X][defect.Y].Defect = defect.Defect
end

function DefectButton(defect)
    if ButtonsList[defect.Button] == nil then return end
    ButtonsList[defect.Button].Defect = defect.Defect
end
