-- Название: Проигрыш видео
-- Автор: Avondale, дискорд - avonda и @VPreobrazhenskiy93 (телеграм)
-- Описание механики: проигрывает видео на фронте
-- Идеи по доработке: световые эффекты на полу, плюс управление освещением в игровой

math.randomseed(os.time())
require("avonlib")

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
    Choices = {},
    AskedChoice = ""
}
local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = colors.NONE,
    selected_branch = nil,
}
local FloorMatrix = {}
local ButtonsList = {}
local Pixel = {
    Color = colors.NONE,
    Bright = colors.BRIGHT0,
    Click = false,
    Defect = false,
}

local tColoredPixels = {}

local COLOR_PIXELS_COUNT = 5

-- Управление видео
local videoIndex = 1
local videoPlaying = false
local videoEndTime = nil
local startDelayEndTime = nil
local pausedAt = nil

local bColorsLoaded = false
local tColorChoiceCount = {}

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

    for _, option in ipairs(GameObj.ColorOptions or {}) do
        table.insert(GameStats.Choices, option.choice)
    end

    GameStats.AskedChoice = GameObj.AskedChoice

    for x = 1, GameObj.Cols do
        FloorMatrix[x] = {}
        for y = 1, GameObj.Rows do
            FloorMatrix[x][y] = help.ShallowCopy(Pixel)
        end
    end

    for _, num in ipairs(GameObj.Buttons) do
        ButtonsList[num] = help.ShallowCopy(Pixel)
    end

    iPrevTickTime = time.unix()

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end
    GameObj.iMinX = 1
    GameObj.iMinY = 1
    GameObj.iMaxX = GameObj.Cols
    GameObj.iMaxY = GameObj.Rows
    if AL.NFZ.bLoaded then
        GameObj.iMinX = AL.NFZ.iMinX
        GameObj.iMinY = AL.NFZ.iMinY
        GameObj.iMaxX = AL.NFZ.iMaxX
        GameObj.iMaxY = AL.NFZ.iMaxY
    end

    if GameObj.Videos and #GameObj.Videos > 0 then
        startDelayEndTime = time.unix() + 1
        videoIndex = 1
        videoPlaying = false
        videoEndTime = nil
    else
        tGameResults.Won = true
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

            if GameObj.Initial then
                audio.PlayVoicesSyncFromScratch("choose-color.mp3")
                bPlayerColorsMode = true
                PositionCountDown()
            elseif GameObj.ColorOptions ~= nil then
                if not bColorsLoaded then
                    audio.PlayVoicesSyncFromScratch("play-videos/collect-all-pixels.mp3")
                    LoadColorChoices()
                    GameStats.ScoreboardVariant = 11
                end
            else
                tGameResults.Won = true
                return tGameResults
            end
        end
    end

    if bPlayerColorsMode then
        PaintPositionChoices()
        if GameStats.StageLeftDuration <= 0 then
            tGameResults.ChosenColors = GetPostitionsArray()
            tGameResults.Won = true
            return tGameResults
        end
    end

    if tGameResults.selected_branch ~= nil then
        tGameResults.Won = true
        return tGameResults
    end

    AL.CountTimers((time.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = time.unix()  
end

local bPlayerColorsMode = false
local tPlayerInGame = {}
local tPlayerColors = {}
tPlayerColors[1] = colors.GREEN
tPlayerColors[2] = colors.RED
tPlayerColors[3] = colors.BLUE
tPlayerColors[4] = colors.MAGENTA
tPlayerColors[5] = colors.YELLOW
tPlayerColors[6] = colors.CYAN

function PaintPositionChoices()
    local iStartX = GameObj.iMinX+2
    local iStartY = GameObj.iMinY+1
    local iSize = math.floor((GameObj.iMaxY-GameObj.iMinY+1)/3)

    for iPlayerID = 1, #tPlayerColors do
        local bClick = false

        local iBright = 1
        if tPlayerInGame[iPlayerID] then iBright = 3; end

        for iX = iStartX, iStartX + iSize do
            for iY = iStartY, iStartY+iSize do
                FloorMatrix[iX][iY].Color = tPlayerColors[iPlayerID]
                FloorMatrix[iX][iY].Bright = iBright

                if FloorMatrix[iX][iY].Click and not FloorMatrix[iX][iY].Defect then
                    bClick = true
                end
            end
        end

        if bClick then
            tPlayerInGame[iPlayerID] = true
        elseif GameStats.StageLeftDuration > 3 then
            tPlayerInGame[iPlayerID] = false
        end

        iStartX = iStartX + iSize + 2
        if iStartX + iSize > GameObj.iMaxX then
            iStartX = GameObj.iMinX+2
            iStartY = iStartY + 2 + iSize

            if iStartY + iSize > GameObj.iMaxY then break; end
        end
    end
end

function PositionCountDown()
    GameStats.StageLeftDuration = 15

    AL.NewTimer(1000, function()
        if GameStats.StageLeftDuration <= 0 then
            return nil
        else
            if GameStats.StageLeftDuration <= 5 then
                audio.ResetSync()
                audio.PlayLeftAudio(GameStats.StageLeftDuration)
            end

            GameStats.StageLeftDuration = GameStats.StageLeftDuration - 1

            return 1000
        end
    end)
end

function GetPostitionsArray()
    local tPlayers = {}

    for iPlayerID = 1, #tPlayerColors do
        if tPlayerInGame[iPlayerID] then
            tPlayers[#tPlayers+1] = tPlayerColors[iPlayerID]
        end
    end

    return tPlayers
end

function LoadColorChoices()
    bColorsLoaded = true

    for iColorId = 1, #GameObj.ColorOptions do
        tColorChoiceCount[iColorId] = 0

        local iX = 1
        local iY = 1
        for iColorPixel = 1, COLOR_PIXELS_COUNT do
            local iMaxX = GameObj.iMaxX/#GameObj.ColorOptions * iColorId
            local iMinX = iMaxX - (GameObj.iMaxX/#GameObj.ColorOptions) + GameObj.iMinX

            repeat
            iX = math.random(iMinX, iMaxX)
            iY = math.random(GameObj.iMinY + (GameObj.iMaxY/4), GameObj.iMaxY - math.floor(GameObj.iMaxY/4))
            until FloorMatrix[iX] ~= nil and FloorMatrix[iX][iY] ~= nil and not FloorMatrix[iX][iY].bIsColorPixel and not FloorMatrix[iX][iY].Defect

            FloorMatrix[iX][iY].bIsColorPixel = true
            FloorMatrix[iX][iY].Color = tonumber(GameObj.ColorOptions[iColorId].color)
            FloorMatrix[iX][iY].iColorId = iColorId
            FloorMatrix[iX][iY].Bright = GameConfigObj.Bright 
        end
    end
end

function ClickColorPixel(iX, iY)
    local iColorId = FloorMatrix[iX][iY].iColorId

    FloorMatrix[iX][iY].bIsColorPixel = false
    FloorMatrix[iX][iY].Color = colors.NONE

    tColorChoiceCount[iColorId] = tColorChoiceCount[iColorId] + 1

    if tColorChoiceCount[iColorId] >= COLOR_PIXELS_COUNT then
        tGameResults.selected_branch = GameObj.ColorOptions[iColorId].shift

        log.print("Color "..iColorId.." selected!")

        for iX = 1, GameObj.Cols do
            for iY = 1, GameObj.Rows do
                FloorMatrix[iX][iY].iColor = colors.NONE
            end
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
    iPrevTickTime = time.unix()
end

function SwitchStage()
end

function PixelClick(click)
    if FloorMatrix[click.X] and FloorMatrix[click.X][click.Y] then
        if click.Click then
            FloorMatrix[click.X][click.Y].Click = true
        else
            AL.NewTimer(500, function()
                FloorMatrix[click.X][click.Y].Click = false
            end)
        end

        if click.Click then
            if FloorMatrix[click.X][click.Y].bIsColorPixel then
                ClickColorPixel(click.X, click.Y)
            end
        end
    end
end

function ButtonClick(click)
    if ButtonsList[click.Button] == nil then return end
    ButtonsList[click.Button].Click = click.Click
end

function DefectPixel(defect)
    FloorMatrix[defect.X][defect.Y].Defect = defect.Defect

    if FloorMatrix[defect.X][defect.Y].bIsColorPixel then
        ClickColorPixel(defect.X, defect.Y)
    end
end

function DefectButton(defect)
    if ButtonsList[defect.Button] == nil then return end
    ButtonsList[defect.Button].Defect = defect.Defect
end
