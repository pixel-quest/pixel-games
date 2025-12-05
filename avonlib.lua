_G.AL = {}
local LOC = {}

local CColors = require("colors")
local CVideos = require("video")
local CAudio = require("audio")

--STACK
AL.Stack = function()
    local tStack = {}
    tStack.tTable = {}

    tStack.Push = function(item)
        table.insert(tStack.tTable, item)
    end

    tStack.Pop = function()
        return table.remove(tStack.tTable, 1)
    end

    tStack.PopLast = function()
        return table.remove(tStack.tTable, #tStack.tTable)
    end

    tStack.Size = function()
        return #tStack.tTable
    end

    return tStack
end
--//

--TIMER
local tTimers = AL.Stack()

AL.NewTimer = function(iSetTime, fCallback)
    tTimers.Push({iTime = iSetTime, fCallback = fCallback})
end

AL.CountTimers = function(iTimePassed)
    for i = 1, tTimers.Size() do
        local tTimer = tTimers.Pop()

        tTimer.iTime = tTimer.iTime - iTimePassed

        if tTimer.iTime <= 0 then
            local iNewTime = tTimer.fCallback()
            if iNewTime then
                tTimer.iTime = tTimer.iTime + iNewTime
            else
                tTimer = nil
            end
        end

        if tTimer then
            tTimers.Push(tTimer)
        end
    end
end
--//

--RECT
function AL.RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end

function AL.RectIntersects2(iX1, iY1, iSizeX1, iSizeY1, iX2, iY2, iSizeX2, iSizeY2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSizeX2-1 or iX2 > iX1+iSizeX1-1 then return false; end

    if iY1+iSizeY1-1 < iY2 or iY2+iSizeY2-1 < iY1 then return false; end

    return true
end
--//

--NFZ - NoFeetZone / Pixel Wall Zone / Зона Пиксельной Стены
AL.NFZ = {}
local tGame = {}

AL.RoomHasNFZ = function(tGameIn)
    tGame = tGameIn

    if tGame and tGame.NoFeetZones ~= nil then
        if #tGame.NoFeetZones > 0 then 
            return true; 
        end
    end

    return false;
end

AL.IsPixelInNFZ = function(iX, iY)
    return AL.IsRectInNFZ(iX, iY, 1, 1)
end

AL.IsRectInNFZ = function(iX, iY, iSizeX, iSizeY)
    for iNFZId = 1, #tGame.NoFeetZones do
        if AL.RectIntersects2(iX, iY, iSizeX, iSizeY, tGame.NoFeetZones[iNFZId].X,tGame.NoFeetZones[iNFZId].Y, tGame.NoFeetZones[iNFZId].SizeX, tGame.NoFeetZones[iNFZId].SizeY) then
            return true;
        end
    end

    return false    
end

AL.LoadNFZInfo = function()
    AL.NFZ = {}

    AL.NFZ.iMinX = NFZ_LoadMinX()
    AL.NFZ.iMinY = NFZ_LoadMinY()
    AL.NFZ.iMaxX = NFZ_LoadMaxX()
    AL.NFZ.iMaxY = NFZ_LoadMaxY()   

    AL.NFZ.iCenterX = math.floor((AL.NFZ.iMaxX - AL.NFZ.iMinX)/2)
    AL.NFZ.iCenterY = math.floor((AL.NFZ.iMaxY - AL.NFZ.iMinY)/2)

    AL.NFZ.bLoaded = true
end

NFZ_LoadMinX = function()
    local iMinX = 1

    for iNFZId = 1, #tGame.NoFeetZones do
        if tGame.NoFeetZones[iNFZId].X + tGame.NoFeetZones[iNFZId].SizeX < math.floor(tGame.Cols/2) and (tGame.NoFeetZones[iNFZId].X + tGame.NoFeetZones[iNFZId].SizeX) > iMinX then
            iMinX = tGame.NoFeetZones[iNFZId].X + tGame.NoFeetZones[iNFZId].SizeX
        end
    end    

    return iMinX
end
NFZ_LoadMinY = function()
    local iMinY = 1

    for iNFZId = 1, #tGame.NoFeetZones do
        if tGame.NoFeetZones[iNFZId].Y + tGame.NoFeetZones[iNFZId].SizeY < math.floor(tGame.Rows/2) and (tGame.NoFeetZones[iNFZId].Y + tGame.NoFeetZones[iNFZId].SizeY) > iMinY then
            iMinY = tGame.NoFeetZones[iNFZId].Y + tGame.NoFeetZones[iNFZId].SizeY
        end
    end      

    return iMinY
end
NFZ_LoadMaxX = function()
    local iMaxX = tGame.Cols

    for iNFZId = 1, #tGame.NoFeetZones do
        if tGame.NoFeetZones[iNFZId].SizeX < tGame.Cols/2 and tGame.NoFeetZones[iNFZId].X > math.floor(tGame.Cols/2) and tGame.NoFeetZones[iNFZId].X < iMaxX then
            iMaxX = tGame.NoFeetZones[iNFZId].X
        end
    end    

    return iMaxX
end
NFZ_LoadMaxY = function()
    local iMaxY = tGame.Rows

    for iNFZId = 1, #tGame.NoFeetZones do
        if tGame.NoFeetZones[iNFZId].SizeY < tGame.Rows/2 and tGame.NoFeetZones[iNFZId].Y > math.floor(tGame.Rows/2) and tGame.NoFeetZones[iNFZId].Y < iMaxY then
            iMaxY = tGame.NoFeetZones[iNFZId].Y
        end
    end    

    return iMaxY
end
--//

--COLORS
AL.Colors = {}

AL.LoadColors = function()
    if tGame.Colors ~= nil then
        for iColor = 1, #tGame.Colors do
            AL.Colors[iColor] = tonumber(tGame.Colors[iColor])
        end
    else
        AL.Colors = 
        {
            CColors.MAGENTA,
            CColors.BLUE,
            CColors.GREEN,
            CColors.CYAN,
            CColors.YELLOW,
            CColors.RED
        };
    end
end
--//

--RULES
AL.NewRulesScript = true
AL.Rules = {}

AL.Rules.iCountDownTime = 15
AL.Rules.bVideoOn = false 
AL.Rules.bSoundOn = false
AL.Rules.videoSkipDuration = 9.5

AL.Rules.FillFloor = function(tFloor)
    local tReturnFloor = {}
    local iSkip = 0

    if not AL.Rules.bVideoOn then
        CVideos.Play("tutorial/skip.mp4")
        AL.Rules.bVideoOn = true

        AL.NewTimer(AL.Rules.videoSkipDuration*1000, function()
            CVideos.Stop()
        end)
    end

    if not AL.Rules.bSoundOn then
        CAudio.PlayVoicesSync("tutorial/skip.mp3")
        AL.Rules.bSoundOn = true
    end

    local function redPixel(iX, iY)
        tReturnFloor[iX][iY] = CColors.RED
    
        if iSkip == 0 and (tFloor[iX][iY].Click or tFloor[iX][iY].bClick) and not tFloor[iX][iY].Defect and not tFloor[iX][iY].bDefect then
            iSkip = 2
        end
    end

    local function greenPixel(iX, iY)
        tReturnFloor[iX][iY] = CColors.GREEN
        if (tFloor[iX][iY].Click or tFloor[iX][iY].bClick) and not tFloor[iX][iY].Defect and not tFloor[iX][iY].bDefect then 
            iSkip = 1
        end
    end

    for iX = 1, #tFloor do
        tReturnFloor[iX] = {}
        for iY = 1, #tFloor[iX] do
            if tFloor[iX][iY] then
                if iY >= (#tFloor[iX]/2) then
                    redPixel(iX, iY)
                else
                    greenPixel(iX, iY)
                end
            end
        end
    end

    return tReturnFloor, iSkip==2
end
--//