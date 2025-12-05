-- Название: Flappy Bird
-- Описание: одиночная аркада с прыжками через трубы

math.randomseed(os.time())

local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local GAMESTATE_SETUP = 1
local GAMESTATE_PLAY = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4
local GAMESTATE_READY = 5

local tGame = {
    Cols = 24,
    Rows = 15,
    Buttons = {},
}

local tConfig = {}

local tStats = {
    StageLeftDuration = 0,
    StageTotalDuration = 0,
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = {
        { Score = 0, Lives = 1, Color = CColors.YELLOW },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 0,
    StageNum = 1,
    TotalStages = 1,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 1,
    Score = 0,
    Color = CColors.YELLOW,
}

local tFloor = {}
local tButtons = {}
local tFlapZone = { x1 = 1, x2 = 2, y1 = 1, y2 = 2 }
local bGamePaused = false
local iPrevTickTime = 0
local iGameState = GAMESTATE_SETUP
local fPipeSpawnTimer = 0
local fPipeStepAccum = 0
local fFinishBlinkTime = 0
local fFinishBlinkAccum = 0
local bFinishStripeOn = true
local UpdatePhysics
local CheckCollision

local tBird = {
    x = 6,
    y = 8.0,
    vy = 0.0,
}

local tPipes = {}

local tFloorStruct = { iColor = CColors.NONE, iBright = CColors.BRIGHT0, bClick = false, bDefect = false, iWeight = 0 }
local tButtonStruct = { iColor = CColors.NONE, iBright = CColors.BRIGHT0, bClick = false, bDefect = false }

local function ResetFloor()
    for iX = 1, tGame.Cols do
        tFloor[iX] = {}
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = {
                iColor = tFloorStruct.iColor,
                iBright = tFloorStruct.iBright,
                bClick = false,
                bDefect = false,
                iWeight = 0,
            }
        end
    end
end

local function ResetButtons()
    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = {
            iColor = tButtonStruct.iColor,
            iBright = tButtonStruct.iBright,
            bClick = false,
            bDefect = false,
        }
    end
end

local function SetupFlapZone()
    local iStartX = 1
    local iEndX = math.min(2, tGame.Cols)

    local iEndY = math.max(1, tGame.Rows - 2)
    local iStartY = math.max(1, iEndY - 1)

    tFlapZone = {
        x1 = iStartX,
        x2 = iEndX,
        y1 = iStartY,
        y2 = iEndY,
    }
end

local function DrawPixel(iX, iY, iColor)
    if tFloor[iX] and tFloor[iX][iY] then
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].iBright = tConfig.Bright
    end
end

local function DrawPipe(pipe)
    local iGapTop = math.floor(pipe.gapY - (tConfig.PipeGap / 2))
    local iGapBottom = iGapTop + tConfig.PipeGap - 1
    for y = 1, tGame.Rows do
        if y < iGapTop or y > iGapBottom then
            if pipe.x >= 1 and pipe.x <= tGame.Cols then
                DrawPixel(math.floor(pipe.x + 0.5), y, CColors.GREEN)
            end
        end
    end
end

local function DrawBird()
    local iY = math.floor(tBird.y + 0.5)
    if iY >= 1 and iY <= tGame.Rows then
        DrawPixel(tBird.x, iY, CColors.YELLOW)
    end
end

local function DrawFlapZone()
    for iX = tFlapZone.x1, tFlapZone.x2 do
        for iY = tFlapZone.y1, tFlapZone.y2 do
            DrawPixel(iX, iY, CColors.MAGENTA)
        end
    end
end

local function DrawFinishStripe(bVisible)
    if not bVisible then return end

    local iWidth = math.min(3, tGame.Cols)
    local iStartX = math.max(1, math.floor((tGame.Cols - iWidth) / 2) + 1)
    local iEndX = math.min(tGame.Cols, iStartX + iWidth - 1)

    for iX = iStartX, iEndX do
        for iY = 1, tGame.Rows do
            local bLight = ((iX + iY) % 2 == 0)
            local iColor = bLight and CColors.WHITE or CColors.BLACK
            DrawPixel(iX, iY, iColor)
        end
    end
end

local function SpawnPipe(iX)
    local iGapCenter = math.random(4, tGame.Rows - 3)
    local iSpawnX = iX or (tGame.Cols + 2)
    table.insert(tPipes, { x = iSpawnX, gapY = iGapCenter, scored = false })
end

local function ResetGame()
    tBird.y = math.floor(tGame.Rows / 2)
    tBird.vy = 0
    tPipes = {}
    fPipeSpawnTimer = 0
    fPipeStepAccum = 0
    fFinishBlinkTime = 0
    fFinishBlinkAccum = 0
    bFinishStripeOn = true
    local iInitialPipeX = math.max(1, tGame.Cols - 2)
    SpawnPipe(iInitialPipeX)
    tStats.Players[1].Score = 0
    tGameResults.Score = 0
    tStats.StageTotalDuration = 0
    tStats.StageLeftDuration = 0
end

function DrawScene()
    ResetFloor()

    for _, pipe in ipairs(tPipes) do
        DrawPipe(pipe)
    end

    local bStripe = (iGameState == GAMESTATE_SETUP) or (iGameState == GAMESTATE_READY and bFinishStripeOn)
    DrawFinishStripe(bStripe)
    DrawBird()
    DrawFlapZone()
end

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    ResetFloor()
    ResetButtons()
    SetupFlapZone()
    ResetGame()

    iPrevTickTime = CTime.unix()
    iGameState = GAMESTATE_SETUP

end

function GameSetupTick()
    DrawScene()
end

local function GameReadyTick(fDelta)
    fFinishBlinkTime = fFinishBlinkTime + fDelta
    fFinishBlinkAccum = fFinishBlinkAccum + fDelta

    local fProgress = math.min(fFinishBlinkTime / 3, 1)
    local fPeriod = math.max(0.1, 0.6 - 0.4 * fProgress)
    if fFinishBlinkAccum >= fPeriod then
        fFinishBlinkAccum = fFinishBlinkAccum - fPeriod
        bFinishStripeOn = not bFinishStripeOn
    end

    if fFinishBlinkTime >= 3 then
        bFinishStripeOn = false
        iGameState = GAMESTATE_PLAY
        tBird.vy = -tConfig.FlapImpulse
        return
    end

    DrawScene()
end

function GameTick(fDelta)
    tStats.StageTotalDuration = tStats.StageTotalDuration + fDelta
    UpdatePhysics(fDelta)
    if CheckCollision() then
        ResetGame()
        iGameState = GAMESTATE_SETUP
    end
    DrawScene()
end

function PostGameTick()
    DrawScene()
end

local function FinishGame()
    iGameState = GAMESTATE_POSTGAME
    tGameResults.AfterDelay = false
    tGameResults.Won = false
end

function UpdatePhysics(fDelta)
    tBird.vy = tBird.vy + tConfig.Gravity * fDelta
    tBird.y = tBird.y + tBird.vy * fDelta

    if tBird.y < 1 then
        tBird.y = 1
        if tBird.vy < 0 then
            tBird.vy = 0
        end
    end

    fPipeStepAccum = fPipeStepAccum + (tConfig.PipeSpeed * fDelta)
    local iShift = math.floor(fPipeStepAccum)
    if iShift > 0 then
        fPipeStepAccum = fPipeStepAccum - iShift
        for i = #tPipes, 1, -1 do
            tPipes[i].x = tPipes[i].x - iShift
            if tPipes[i].x < -2 then
                table.remove(tPipes, i)
            end
        end
    end

    fPipeSpawnTimer = fPipeSpawnTimer + fDelta
    if fPipeSpawnTimer >= tConfig.PipeInterval then
        fPipeSpawnTimer = fPipeSpawnTimer - tConfig.PipeInterval
        SpawnPipe()
    end
end

function CheckCollision()
    local iY = math.floor(tBird.y + 0.5)
    if iY > tGame.Rows then
        return true
    end

    for _, pipe in ipairs(tPipes) do
        local iPipeX = math.floor(pipe.x + 0.5)
        if iPipeX == tBird.x then
            local iGapTop = math.floor(pipe.gapY - (tConfig.PipeGap / 2))
            local iGapBottom = iGapTop + tConfig.PipeGap - 1
            if iY < iGapTop or iY > iGapBottom then
                return true
            end
        end

        if iPipeX == tBird.x - 1 and not pipe.scored then
            pipe.scored = true
            tStats.Players[1].Score = tStats.Players[1].Score + 1
            tGameResults.Score = tStats.Players[1].Score
        end
    end

    return false
end

function NextTick()
    local fNow = CTime.unix()
    local fDelta = fNow - iPrevTickTime
    iPrevTickTime = fNow

    if bGamePaused then
        return
    end

    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
        return
    end

    if iGameState == GAMESTATE_READY then
        GameReadyTick(fDelta)
        return
    end

    if iGameState == GAMESTATE_PLAY then
        GameTick(fDelta)
        return
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
        iGameState = GAMESTATE_FINISH
    end

    if iGameState == GAMESTATE_FINISH then
        tGameResults.AfterDelay = false
        return tGameResults
    end
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        local tRow = tFloor[iX] or {}
        for iY = 1, tGame.Rows do
            local tCell = tRow[iY] or tFloorStruct
            local iColor = tCell.iColor or CColors.NONE
            local iBright = tCell.iBright or CColors.BRIGHT0
            setPixel(iX, iY, iColor, iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        local iColor = tButton.iColor or CColors.NONE
        local iBright = tButton.iBright or CColors.BRIGHT0
        setButton(i, iColor, iBright)
    end
end

function GetStats()
    return tStats
end

function PixelClick(tClick)
    if not tClick.Click or bGamePaused then return end

    if tClick.X < tFlapZone.x1 or tClick.X > tFlapZone.x2 or tClick.Y < tFlapZone.y1 or tClick.Y > tFlapZone.y2 then
        return
    end

    if iGameState == GAMESTATE_SETUP then
        iGameState = GAMESTATE_READY
        fFinishBlinkTime = 0
        fFinishBlinkAccum = 0
        bFinishStripeOn = true
        return
    end

    if iGameState == GAMESTATE_READY then
        return
    end

    if iGameState == GAMESTATE_PLAY then
        tBird.vy = -tConfig.FlapImpulse
        CAudio.PlaySystemAsync(CAudio.CLICK)
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
        if defect.Defect then
            tFloor[defect.X][defect.Y].iColor = CColors.NONE
            tFloor[defect.X][defect.Y].iBright = CColors.BRIGHT0
        end
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end

    tButtons[click.Button].bClick = click.Click

    if click.Click then
        PixelClick({ X = tFlapZone.x1, Y = tFlapZone.y1, Click = true })
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

function PauseGame()
    bGamePaused = true
    iPrevTickTime = CTime.unix()
end

function ResumeGame()
    bGamePaused = false
    iPrevTickTime = CTime.unix()
end

function SwitchStage()
    ResetGame()
    iGameState = GAMESTATE_SETUP
end
