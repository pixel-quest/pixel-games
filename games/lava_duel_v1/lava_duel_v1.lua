--[[
    Название: Лава Битва
    Автор: Avondale, дискорд - avonda

    Описание механики: От 2 до 6 игроков соревнуются кто быстрее соберёт все монетки, не наступив на лаву
          Чтобы начать игру нужно встать на свои цвета и нажать на кнопку
          Стоять на краю поля в начале безопасно

    Идеи по доработке: 
    - Больше уровней
    - Улучшенная генерация уровней
    - Редактор уровней
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
local tPlayerInGame = {}
local iPlayerCount = 0
local bAnyButtonClick = false
local bFirstRound = true

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
    ScoreboardVariant = 6,
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
    bAnimated = false,
}
local tButtonStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
}

local tTeamColors = {}
tTeamColors[1] = CColors.GREEN
tTeamColors[2] = CColors.YELLOW
tTeamColors[3] = CColors.MAGENTA
tTeamColors[4] = CColors.BLUE
tTeamColors[5] = CColors.CYAN
tTeamColors[6] = CColors.WHITE

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

    if tGame.StartPositions == nil then
        tGame.StartPositions = {}

        local iOffset = 1
        local iX = iOffset
        local iY = 2

        for iPlayerID = 1, 6 do
            tGame.StartPositions[iPlayerID] = {}
            tGame.StartPositions[iPlayerID].X = iX
            tGame.StartPositions[iPlayerID].Y = iY
            tGame.StartPositions[iPlayerID].Color = tTeamColors[iPlayerID]

            iX = iX + tGame.StartPositionSizeX + iOffset
            if iX + tGame.StartPositionSizeX > tGame.Cols then
                iX = iOffset
                iY = iY + tGame.StartPositionSizeY + 1
            end
        end
    else
        for iPlayerID = 1, #tGame.StartPositions do
            tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
        end 
    end

    tGameStats.TargetScore = 6 * tConfig.RoundCount
    tGameStats.TotalStages = tConfig.RoundCount

    CAudio.PlayVoicesSync("lavaduel/lavaduel-rules.mp3")

    CAudio.PlayVoicesSync("choose-color.mp3")
    
    if tGame.ArenaMode then 
        CAudio.PlayVoicesSync("press-zone-for-start.mp3")

        iPrevTickTime = CTime.unix()
        AL.NewTimer(5000, function()
            CGameMode.bArenaCanStart = true
        end)
    else
        --CAudio.PlaySync("voices/press-button-for-start.mp3")
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
    CAnimate.Tick((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    if CGameMode.iRound == 0 then SetAllButonColorBright(CColors.GREEN, tConfig.Bright) end

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or (CGameMode.bCountdownStarted and tPlayerInGame[iPos]) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright, false)

            if tPlayerInGame[iPos] and tGame.ArenaMode then
                local iCenterX = tPos.X + math.floor(tGame.StartPositionSizeX/3)
                local iCenterY = tPos.Y + math.floor(tGame.StartPositionSizeY/3)

                local bArenaClick = false
                for iX = iCenterX, iCenterX+1 do
                    for iY = iCenterY, iCenterY+1 do
                        tFloor[iX][iY].iColor = CColors.MAGENTA

                        if tFloor[iX][iY].bClick then 
                            bArenaClick = true
                        end
                    end
                end

                if CGameMode.bArenaCanStart and bArenaClick then
                    bAnyButtonClick = true 
                end
            end 
        end
    end

    if (iPlayersReady > 0 and bAnyButtonClick) or (iPlayersReady >= iPlayerCount and CGameMode.iRound > 0) or (tGame.AutoStartPlayerCount and tGame.AutoStartPlayerCount > 0 and iPlayersReady >= tGame.AutoStartPlayerCount) then
        tGameResults.PlayersCount = iPlayersReady

        bAnyButtonClick = false
        iPlayerCount = iPlayersReady
        iGameState = GAMESTATE_GAME
        CGameMode.CountDownNextRound()
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.PlayerZones()
    CPaint.Blocks()
end

function PostGameTick()
    
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if not tFloor[iX] or not tFloor[iX][iY] or not tFloor[iX][iY].iColor then
                CLog.print("lavaduel ERROR while attempting to range floor at X:"..iX.." Y:"..iY..". Map ID:"..CMaps.iRandomMapID)
            else
                setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
            end
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tConfig.Bright)
    end
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = -1
CGameMode.iWinnerID = -1
CGameMode.tMap = {}
CGameMode.tMapLavaFrames = {}
CGameMode.iRound = 0
CGameMode.bRoundStarted = false
CGameMode.tPlayerFinished = {}
CGameMode.tPlayerScoreThisRound = {}
CGameMode.iPlayersFinished = 0
CGameMode.tPlayersCoinCollected = {}
CGameMode.iMapCoinCount = 0
CGameMode.bArenaCanStart = false
CGameMode.bCountdownStarted = false
CGameMode.tPlayerLavaCD = {}

CGameMode.CountDownNextRound = function()
    CGameMode.bRoundStarted = false
    CGameMode.tPlayerFinished = {}
    CGameMode.tPlayerScoreThisRound = {}
    CGameMode.iPlayersFinished = 0
    CGameMode.tPlayersCoinCollected = {}
    CGameMode.iMapCoinCount = 0
    CGameMode.bCountdownStarted = true

    local iCountDownTime = tConfig.RoundCountdown

    if bFirstRound then
        iCountDownTime = tConfig.GameCountdown
    end

    CAnimate.Reset()

    CGameMode.iCountdown = iCountDownTime
    CGameMode.iRound = CGameMode.iRound + 1
    tGameStats.StageNum = CGameMode.iRound
    CGameMode.LoadNewMap()

    --tGameStats.TargetScore = iPlayerCount * tConfig.RoundCount

    CAudio.PlayVoicesSyncFromScratch("quest/zone-edge.mp3")

    AL.NewTimer(6000, function()
        CAudio.ResetSync()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.iCountdown = -1

            CGameMode.StartRound()

            if bFirstRound then
                bFirstRound = false
                CAudio.PlayVoicesSync(CAudio.START_GAME)
            end

            return nil
        else 
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end 
    end)
end

CGameMode.LoadNewMap = function()
    CBlock.tBlocks = {}
    CGameMode.tMap, CGameMode.tMapLavaFrames = CMaps.GetRandomMap()

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CMaps.LoadMapForPlayer(CGameMode.tMap, iPlayerID)
        end
    end
end

CGameMode.StartRound = function()
    CAudio.PlayRandomBackground()

    CGameMode.bRoundStarted = true
    CBlock.AnimateVisibility()
end

CGameMode.PlayerFinished = function(iPlayerID)
    CGameMode.tPlayerFinished[iPlayerID] = true 
    CGameMode.iPlayersFinished = CGameMode.iPlayersFinished + 1

    local iAddScore = iPlayerCount - (CGameMode.iPlayersFinished-1)
    --if CGameMode.tPlayerScoreThisRound[iPlayerID] then
    --    iAddScore = CGameMode.tPlayerScoreThisRound[iPlayerID] * (tConfig.ScorePlacementMultiplierStart -  (CGameMode.iPlayersFinished*tConfig.ScorePlacementMultiplierDecreasePerPlace))
    --end

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + iAddScore

    CAudio.PlaySystemAsync(CAudio.STAGE_DONE)

    if CGameMode.iPlayersFinished >= iPlayerCount then
        CGameMode.EndRound()
    end
end

CGameMode.EndRound = function()
    CAudio.StopBackground()

    CGameMode.bRoundStarted = false
    local bEndGame = false
    local iMaxScore = -999 -- в случае если несколько игроков побили нужный для победы счёт, считаем у кого из них больше чтоб определить победителя

    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] and tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
        end
    end

    tGameStats.TargetScore = iMaxScore
    if iMaxScore <= 0 then
        tGameStats.TargetScore = 1
    end

    if CGameMode.iRound >= tConfig.RoundCount then
        CGameMode.EndGame()
    else
        CGameMode.CountDownNextRound()
    end
end

CGameMode.EndGame = function()
    iGameState = GAMESTATE_POSTGAME

    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlayVoicesSync(CAudio.VICTORY)

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)

    tGameResults.Won = true
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    AL.NewTimer(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)    
end

CGameMode.PlayerRoundScoreAdd = function(iPlayerID, iScore)
    if CGameMode.tPlayerScoreThisRound[iPlayerID] == nil then CGameMode.tPlayerScoreThisRound[iPlayerID] = 0 end
    CGameMode.tPlayerScoreThisRound[iPlayerID] = CGameMode.tPlayerScoreThisRound[iPlayerID] + iScore  

    if CGameMode.tPlayersCoinCollected[iPlayerID] == nil then CGameMode.tPlayersCoinCollected[iPlayerID] = 0 end
    CGameMode.tPlayersCoinCollected[iPlayerID] = CGameMode.tPlayersCoinCollected[iPlayerID] + 1

    CAudio.PlaySystemAsync(CAudio.CLICK);

    if CGameMode.tPlayersCoinCollected[iPlayerID] == CGameMode.iMapCoinCount then
        CGameMode.PlayerFinished(iPlayerID)
    end  
end

CGameMode.PlayerTouchedLava = function(iPlayerID, iX, iY)
    if CGameMode.tPlayerFinished[iPlayerID] or not CGameMode.bRoundStarted or CGameMode.tPlayerLavaCD[iPlayerID] then return false; end

    if tGameStats.Players[iPlayerID].Score > 0 then
        tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + tConfig.LavaScorePenalty
    end

    CAudio.PlaySystemAsync(CAudio.MISCLICK)

    CGameMode.tPlayerLavaCD[iPlayerID] = true
    AL.NewTimer(250, function()
        CGameMode.tPlayerLavaCD[iPlayerID] = false
    end)
    return true;
end
--//

--MAPS
CMaps = {}
CMaps.iRandomMapID = 0
CMaps.iRandomMapIDIncrement = math.random(-2,2)

CMaps.GetRandomMap = function()
    if tConfig.GenerateRandomLevels == 1 then
        return CMaps.GenerateRandomMap()
    else
        if CMaps.iRandomMapID == 0 then 
            CMaps.iRandomMapID = math.random(1, #tGame.Maps)
        end
        if CMaps.iRandomMapIDIncrement == 0 then
            CMaps.iRandomMapIDIncrement = 1
        end

        CMaps.iRandomMapID = CMaps.iRandomMapID + CMaps.iRandomMapIDIncrement
        if CMaps.iRandomMapID > #tGame.Maps then
            CMaps.iRandomMapID = (CMaps.iRandomMapID-#tGame.Maps)
        elseif CMaps.iRandomMapID < 1 then
            CMaps.iRandomMapID = #tGame.Maps + (CMaps.iRandomMapID)
        end

        --CLog.print("random map #"..CMaps.iRandomMapID)

        return tGame.Maps[CMaps.iRandomMapID], tGame.MapLavaFrames[CMaps.iRandomMapID]
    end
end

CMaps.LoadMapForPlayer = function(tMap, iPlayerID)
    local iMapX = 0
    local iMapY = 0
    local iBlockCount = 0
    local iCoinCount = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositionSizeY-1 + tGame.StartPositions[iPlayerID].Y  do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositionSizeX-1 + tGame.StartPositions[iPlayerID].X do
            iMapX = iMapX + 1

            local iBlockType = CBlock.BLOCK_TYPE_GROUND
            if tMap[iMapY] ~= nil and tMap[iMapY][iMapX] ~= nil then 
                iBlockType = tMap[iMapY][iMapX]
            end

            if iBlockType == CBlock.BLOCK_TYPE_COIN then
                iCoinCount = iCoinCount + 1
            end

            CBlock.NewBlock(iX, iY, iBlockType, iPlayerID)
            iBlockCount = iBlockCount + 1
        end

        iMapX = 0
    end

    CGameMode.iMapCoinCount = iCoinCount
    --CLog.print("Map Loaded: "..iBlockCount.." blocks "..iCoinCount.." coins")
end

CMaps.GenerateRandomMap = function()
    local tMap = {}

    --local iChunkMaxSizeX =  math.floor(tGame.StartPositionSizeX/2)-1
    --local iChunkMaxSizeY =  math.floor(tGame.StartPositionSizeY/2)-1

    for iX = 1, tGame.StartPositionSizeX do
        if tMap[iX] == nil then tMap[iX] = {} end
        for iY = 1, tGame.StartPositionSizeY do
            local iBlockType = CBlock.RandomBlockType()
            tMap[iX][iY] = iBlockType
        end
    end

    return tMap, tGame.MapLavaFrames[math.random(1, #tGame.MapLavaFrames)]
end
--//

--BLOCK
CBlock = {}
CBlock.tBlocks = {}
CBlock.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iPlayerID = 0,
    iBright = 0,
    bVisible = false,
}

CBlock.BLOCK_TYPE_GROUND = 1
CBlock.BLOCK_TYPE_LAVA = 2
CBlock.BLOCK_TYPE_COIN = 3
CBlock.BLOCK_TYPE_FINISH = 4

CBlock.tBLOCK_TYPE_TO_COLOR = {}
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_GROUND]                   = CColors.WHITE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_LAVA]                     = CColors.RED
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_COIN]                     = CColors.BLUE
CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.BLOCK_TYPE_FINISH]                   = CColors.GREEN

CBlock.RandomBlockType = function()
    local iBlockType = math.random(1,2)
    if iBlockType == 2 then iBlockType = 3 end

    return iBlockType
end

CBlock.NewBlock = function(iX, iY, iBlockType, iPlayerID)

    if CBlock.tBlocks[iX] == nil then CBlock.tBlocks[iX] = {} end
    CBlock.tBlocks[iX][iY] = CHelp.ShallowCopy(CBlock.tBlockStructure)
    CBlock.tBlocks[iX][iY].iBlockType = iBlockType
    CBlock.tBlocks[iX][iY].iPlayerID = iPlayerID
    CBlock.tBlocks[iX][iY].iBright = tConfig.Bright
    CBlock.tBlocks[iX][iY].bVisible = false

    if tFloor[iX][iY].bDefect and iBlockType == CBlock.BLOCK_TYPE_COIN then
        CBlock.RegisterBlockClick(iX,iY)
    end
end

CBlock.RegisterBlockClick = function(iX, iY)
    local iPlayerID = CBlock.tBlocks[iX][iY].iPlayerID
    if CGameMode.tPlayerFinished[iPlayerID] then return; end

    if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_LAVA and CBlock.tBlocks[iX][iY].bCollected == false then
        if tFloor[iX][iY].bClick and CGameMode.PlayerTouchedLava(iPlayerID, iX, iY) then
            CBlock.tBlocks[iX][iY].bCollected = true
            CPaint.AnimatePixelFlicker(iX, iY, 3, CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType])
        end
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected == false then
        CBlock.tBlocks[iX][iY].bCollected = true
        CGameMode.PlayerRoundScoreAdd(iPlayerID, 1)
    elseif CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_FINISH and not CGameMode.tPlayerFinished[iPlayerID] then
        CGameMode.PlayerFinished(iPlayerID)
        --CBlock.tBlocks[iX][iY].iBright = tConfig.StepBright
    else
        --CBlock.tBlocks[iX][iY].iBright = tConfig.StepBright
    end
end

CBlock.AnimateVisibility = function()
    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then 
            local iY = tGame.StartPositions[iPlayerID].Y

            AL.NewTimer(CPaint.ANIMATION_DELAY, function()
                for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX do
                    if CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                        CBlock.tBlocks[iX][iY].bVisible = true

                        if tFloor[iX][iY].bClick then
                            CBlock.RegisterBlockClick(iX,iY)
                        end
                    end
                end

                if iY < tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY then
                    iY = iY + 1
                    return CPaint.ANIMATION_DELAY
                end
                return nil
            end)
        end
    end
end
--//

--ANIMATE
CAnimate = {}
CAnimate.iFrame = 0
CAnimate.iTime = 0
CAnimate.tBlocks = {}
CAnimate.tBlockStructure = {
    iBlockType = 0,
    bCollected = false,
    iPlayerID = 0,
    iBright = 0,
}

CAnimate.ANIMATE_BLOCK_NONE = 0
CAnimate.ANIMATE_BLOCK_LAVA = 1
CAnimate.ANIMATE_BLOCK_COIN = 2

CAnimate.tBLOCK_TYPE_TO_COLOR = {}
CAnimate.tBLOCK_TYPE_TO_COLOR[CAnimate.ANIMATE_BLOCK_LAVA] = CColors.RED
CAnimate.tBLOCK_TYPE_TO_COLOR[CAnimate.ANIMATE_BLOCK_COIN] = CColors.BLUE

CAnimate.Reset = function()
    CAnimate.iFrame = 0
    CAnimate.iTime = 0
    CAnimate.tBlocks = {}
end

CAnimate.Tick = function(iTimePassed)
    if not CGameMode.bRoundStarted or bGamePaused or CGameMode.tMapLavaFrames == nil or CGameMode.tMapLavaFrames[1] == nil then return end

    CAnimate.iTime = CAnimate.iTime + iTimePassed

    CAnimate.iFrame = math.ceil(CAnimate.iTime / tConfig.BlockMoveAnimationTimeMS)

    if CAnimate.iFrame == 0 then
        CAnimate.iFrame = 1
    end

    if CAnimate.iFrame > #CGameMode.tMapLavaFrames then
        CAnimate.iFrame = 1
        CAnimate.iTime = 0  
    end

    CAnimate.DrawFrame(CAnimate.iFrame)
end

CAnimate.DrawFrame = function(iFrame)
    --CAnimate.tBlocks = {}

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CAnimate.DrawFrameForPlayer(iFrame, iPlayerID)
        end
    end
end

CAnimate.DrawFrameForPlayer = function(iFrame, iPlayerID)
    local iMapY = 0
    local iMapX = 0

    for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1 do
        iMapY = iMapY + 1

        for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X + tGame.StartPositionSizeX-1 do
            iMapX = iMapX + 1

            CAnimate.AddFrameBlock(iX, iY, CGameMode.tMapLavaFrames[iFrame][iMapY][iMapX], iPlayerID)
        end

        iMapX = 0
    end
end

CAnimate.AddFrameBlock = function(iX, iY, iBlockType, iPlayerID)
    if CAnimate.tBlocks[iX] == nil then CAnimate.tBlocks[iX] = {} end

    local bWasClicked = false
    if CAnimate.tBlocks[iX][iY] and CAnimate.tBlocks[iX][iY].bCollected then
        bWasClicked = true
    end

    CAnimate.tBlocks[iX][iY] = CHelp.ShallowCopy(CAnimate.tBlockStructure)
    CAnimate.tBlocks[iX][iY].iBlockType = iBlockType
    CAnimate.tBlocks[iX][iY].iBright = tConfig.Bright
    CAnimate.tBlocks[iX][iY].iPlayerID = iPlayerID
    CAnimate.tBlocks[iX][iY].bCollected = bWasClicked

    if tFloor[iX][iY].bClick then
        CAnimate.RegisterBlockClick(iX, iY)
    end
end

CAnimate.RegisterBlockClick = function(iX, iY)
    if CAnimate.tBlocks[iX][iY] then
        if CAnimate.tBlocks[iX][iY].iBlockType == CAnimate.ANIMATE_BLOCK_LAVA and not CAnimate.tBlocks[iX][iY].bCollected then
            AL.NewTimer(250, function()
                if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 and CAnimate.tBlocks[iX] and CAnimate.tBlocks[iX][iY] and CGameMode.PlayerTouchedLava(CAnimate.tBlocks[iX][iY].iPlayerID, iX, iY) then
                    CAnimate.tBlocks[iX][iY].bCollected = true
                    CPaint.AnimatePixelFlicker(iX, iY, 3, CAnimate.tBLOCK_TYPE_TO_COLOR[CAnimate.tBlocks[iX][iY].iBlockType])
                end
            end)
        elseif CAnimate.tBlocks[iX][iY].iBlockType == CAnimate.ANIMATE_BLOCK_COIN and not CAnimate.tBlocks[iX][iY].bCollected then
            CAnimate.tBlocks[iX][iY].bCollected = true
            CGameMode.PlayerRoundScoreAdd(CAnimate.tBlocks[iX][iY].iPlayerID, 1)
        end
    end
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 50

CPaint.Blocks = function()
    for iX = 1, tGame.Cols do
        if CBlock.tBlocks[iX] then
            for iY = 1, tGame.Rows do
                if not tFloor[iX][iY].bAnimated and CBlock.tBlocks[iX][iY] and CBlock.tBlocks[iX][iY].bVisible and not CGameMode.tPlayerFinished[CBlock.tBlocks[iX][iY].iPlayerID] then
                    if CAnimate.tBlocks[iX] and CAnimate.tBlocks[iX][iY] and CAnimate.tBlocks[iX][iY].iBlockType > 0 then
                        tFloor[iX][iY].iColor = CAnimate.tBLOCK_TYPE_TO_COLOR[CAnimate.tBlocks[iX][iY].iBlockType]
                        tFloor[iX][iY].iBright = CAnimate.tBlocks[iX][iY].iBright

                    elseif CBlock.tBlocks[iX] and CBlock.tBlocks[iX][iY] then
                        tFloor[iX][iY].iColor = CBlock.tBLOCK_TYPE_TO_COLOR[CBlock.tBlocks[iX][iY].iBlockType]
                        tFloor[iX][iY].iBright = CBlock.tBlocks[iX][iY].iBright

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_GROUND then
                            tFloor[iX][iY].iBright = CColors.BRIGHT15
                        end

                        if CBlock.tBlocks[iX][iY].iBlockType == CBlock.BLOCK_TYPE_COIN and CBlock.tBlocks[iX][iY].bCollected then
                            tFloor[iX][iY].iBright = CColors.BRIGHT0
                        end
                    end
                end
            end
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright, bPaintStart)
    SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
        tGame.StartPositions[iPlayerID].Y, 
        tGame.StartPositionSizeX-1, 
        tGame.StartPositionSizeY-1, 
        tGame.StartPositions[iPlayerID].Color, 
        iBright)

    --[[
    if bPaintStart then
        SetRectColorBright(math.floor(tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX/2)-1, 
            math.floor(tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSizeY/2)-1, 
            math.floor(tGame.StartPositionSizeX/2)-2, 
            math.floor(tGame.StartPositionSizeY/2)-2, 
            CColors.BLUE, 
            CColors.BRIGHT50)
    end
    ]]
    
    if CGameMode.iRound > 0 and not CGameMode.bRoundStarted then
        SetColColorBright(tGame.StartPositions[iPlayerID], tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright+2)
        SetColColorBright({X = tGame.StartPositions[iPlayerID].X, Y = tGame.StartPositions[iPlayerID].Y + tGame.StartPositionSizeY-1}, tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Color, iBright+2)

        SetRowColorBright(tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright+2)
        SetRowColorBright(tGame.StartPositions[iPlayerID].X+tGame.StartPositionSizeX-1, tGame.StartPositions[iPlayerID].Y-1, tGame.StartPositionSizeY-1, tGame.StartPositions[iPlayerID].Color, iBright+2)
    end
end

CPaint.PlayerZones = function()
    for i = 1, #tGame.StartPositions do
        if tPlayerInGame[i] then
            CPaint.PlayerZone(i, CColors.BRIGHT30)
        end
    end
end

CPaint.ResetAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
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

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if not tFloor[iX][iY].bAnimated then
                tFloor[iX][iY].iColor = iColor
                tFloor[iX][iY].iBright = iBright
            end
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end

function SetAllButonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end

function SetRowColorBright(tStart, iY, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart
        iY = iY + 1

        if not (iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetColColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize do
        local iX = tStart.X + i
        local iY = tStart.Y

        if not (iX < 1 or iX > tGame.Cols) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
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

        if click.Click and click.Weight > 5 and iGameState == GAMESTATE_GAME and CGameMode.bRoundStarted then
            if CAnimate.tBlocks[click.X] and CAnimate.tBlocks[click.X][click.Y] and CAnimate.tBlocks[click.X][click.Y].iBlockType > 0 then
                CAnimate.RegisterBlockClick(click.X, click.Y)
            elseif CBlock.tBlocks[click.X] and CBlock.tBlocks[click.X][click.Y] then
                CBlock.RegisterBlockClick(click.X, click.Y)
            end
        end
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then 
        tFloor[defect.X][defect.Y].bDefect = defect.Defect

        if defect.Defect and iGameState == GAMESTATE_GAME and CGameMode.bRoundStarted then
            if CBlock.tBlocks[defect.X] and CBlock.tBlocks[defect.X][defect.Y] and CBlock.tBlocks[defect.X][defect.Y].iBlockType == CBlock.BLOCK_TYPE_COIN then
                CBlock.RegisterBlockClick(defect.X, defect.Y)
            end
        end    
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end
    tButtons[click.Button].bClick = click.Click

    if iGameState == GAMESTATE_SETUP and click.Click == true then
        bAnyButtonClick = true
    end    
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect
end