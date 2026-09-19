-- ArjMapper v1.0 - Custom Mapper for Duris MUD
--
-- v1.0:
--   - Initial release for Arjinius Client
--   - Bronze/gold theme with smart room positioning
--   - Section colors, door detection, tooltips, zoom

ArjMapper = ArjMapper or {}

-- ============================================================
-- CONFIGURATION
-- ============================================================

ArjMapper.config = {
    apiBase = "https://www.newduris.com/api/wiki/zones/",

    wildFontSize = 11,
    wildZoom     = 1.4,
    
    roomSize     = 14,
    cellSize     = 18,
    passageWidth = 14,
    viewRadius   = 5,  -- Reduced for performance (was 7)
    playerDotSize = 6,
    
    debug = false,

    colors = {
        background     = {12, 11, 9},       -- warm dark (matches UI console bg)
        floorColor     = {90, 75, 55},      -- muted bronze for rooms AND passages
        wallColor      = {25, 22, 18},      -- warm dark walls
        roomHighlight  = {120, 95, 65},     -- brighter bronze for current room
        playerDot      = {255, 95, 85},     -- coral red (good contrast)
        playerGlow     = {255, 120, 100},   -- glow effect
        doorClosed     = {160, 70, 70},     -- muted red for doors
        doorOpen       = {180, 150, 90},    -- warm gold (fits theme)
        upExit         = {230, 220, 195},   -- cream/parchment (unified arrows)
        downExit       = {230, 220, 195},   -- cream/parchment (unified arrows)
        farExit        = {110, 90, 70},     -- darker warm brown
    },
    
    -- Colors for different disconnected sections (far exits) - warm bronze variants
    sectionColors = {
        {140, 110, 80},   -- muted bronze
        {110, 90, 70},    -- darker bronze
        {130, 100, 75},   -- warm tan
        {100, 85, 65},    -- deep bronze
        {150, 120, 90},   -- light bronze
        {120, 95, 70},    -- medium bronze
        {95, 80, 60},     -- shadow bronze
        {135, 105, 80},   -- copper
    },
}

-- ============================================================
-- STATE
-- ============================================================

ArjMapper.state = {
    enabled        = true,
    lastRenderTime = 0,  -- Throttle rendering
    currentZone    = nil,
    currentRoom    = nil,
    currentCoords  = nil,
    currentZ       = 0,
    inWilderness   = false,
    zoneData       = {},
    visitedRooms   = {},
    roomDoors      = {},   -- [roomId] = { north = true, south = false, ... }
    lastZoneId     = nil,
    lastDisplayMode = nil,
}

ArjMapper.ui = {
    wildConsole   = nil,
    zoneContainer = nil,
    roomLabels    = {},
}

ArjMapper.handlers = {}

-- ============================================================
-- DURIS COLOR TABLES
-- ============================================================

ArjMapper.fgRGB = {
    r = "128,0,0",     R = "255,0,0",
    g = "0,128,0",     G = "0,255,0",
    b = "0,0,128",     B = "0,128,255",
    c = "0,128,128",   C = "0,255,255",
    m = "128,0,128",   M = "255,0,255",
    y = "128,128,0",   Y = "255,255,0",
    w = "192,192,192", W = "255,255,255",
    L = "96,96,96",    l = "96,96,96",
}

ArjMapper.bgRGB = {
    r = "80,0,0",      R = "128,0,0",
    g = "0,80,0",      G = "0,128,0",
    b = "0,0,60",      B = "0,0,100",
    c = "0,60,60",     C = "0,100,100",
    m = "60,0,60",     M = "100,0,100",
    y = "60,60,0",     Y = "100,100,0",
    w = "60,60,60",    W = "100,100,100",
    L = "32,32,32",    l = "32,32,32",
}

-- ============================================================
-- WILDERNESS PARSER
-- ============================================================

function ArjMapper:parseWildernessMap(rawMap)
    if not rawMap then return "" end
    local result = {}
    local i, len = 1, #rawMap
    local currentFg, currentBg = nil, nil

    local function cellChunk(ch)
        if not currentFg and not currentBg then return ch end
        local prefix
        if currentFg and currentBg then
            prefix = "<" .. currentFg .. ":" .. currentBg .. ">"
        elseif currentFg then
            prefix = "<" .. currentFg .. ">"
        else
            prefix = "<:" .. currentBg .. ">"
        end
        return prefix .. ch .. "<r>"
    end

    while i <= len do
        local ch = rawMap:sub(i, i)
        if ch == "&" and i < len then
            local nxt = rawMap:sub(i+1, i+1)
            if nxt == "+" and i + 2 <= len then
                currentFg = self.fgRGB[rawMap:sub(i+2, i+2)]
                i = i + 3
            elseif nxt == "=" and i + 3 <= len then
                local fgCode = rawMap:sub(i+2, i+2)
                local bgCode = rawMap:sub(i+3, i+3)
                if self.fgRGB[fgCode] then currentFg = self.fgRGB[fgCode] end
                currentBg = self.bgRGB[bgCode]
                i = i + 4
            elseif nxt == "n" or nxt == "N" or nxt == "]" then
                table.insert(result, "<r>")
                currentFg, currentBg = nil, nil
                i = i + 2
            else
                i = i + 1
            end
        elseif ch == "\\" and i < len and rawMap:sub(i+1, i+1) == "n" then
            table.insert(result, "<r>\n")
            currentFg, currentBg = nil, nil
            i = i + 2
        else
            table.insert(result, cellChunk(ch))
            i = i + 1
        end
    end
    return table.concat(result)
end

-- ============================================================
-- WILDERNESS DETECTION
-- ============================================================

function ArjMapper:isWilderness(roomData)
    if not roomData then return false end
    if not roomData.num or roomData.num == 0 then return true end
    if roomData.exits then
        for _, dest in pairs(roomData.exits) do
            if type(dest) == "boolean" then return true end
            break
        end
    end
    return false
end

-- ============================================================
-- UI SETUP
-- ============================================================

function ArjMapper:setupUI()
    if not ArjUI or not ArjUI.mapWrap then return false end

    local bg = self.config.colors.background

    if self.ui.wildConsole then self.ui.wildConsole:hide() end
    self.ui.wildConsole = Geyser.MiniConsole:new({
        name = "ArjMapper_Wild_" .. os.time(),
        x = 0, y = 0, width = "100%", height = "100%",
    }, ArjUI.mapWrap)
    self.ui.wildConsole:setColor(bg[1], bg[2], bg[3])
    self.ui.wildConsole:setFontSize(math.floor(self.config.wildFontSize * self.config.wildZoom))
    self.ui.wildConsole:setFont("Consolas")
    self.ui.wildConsole:hide()

    if self.ui.zoneContainer then self.ui.zoneContainer:hide() end
    self.ui.zoneContainer = Geyser.Label:new({
        name = "ArjMapper_Zone_" .. os.time(),
        x = 0, y = 0, width = "100%", height = "100%",
    }, ArjUI.mapWrap)
    -- Add clipping to prevent room labels from rendering outside the container
    -- TODO: Will need to handle this differently since Qt Labels don't clip children by default
    self.ui.zoneContainer:setStyleSheet(string.format(
        "QLabel { background-color: rgb(%d,%d,%d); }", bg[1], bg[2], bg[3]))
    self.ui.zoneContainer:hide()

    -- Create hover tooltip label (instant, no delay)
    self.ui.hoverLabel = Geyser.Label:new({
        name = "ArjMapper_Hover_" .. os.time(),
        x = 0, y = 0, width = 200, height = 24,
    }, ArjUI.mapWrap)
    self.ui.hoverLabel:setStyleSheet([[
        QLabel {
            background-color: rgba(15, 14, 12, 240);
            color: #d4a855;
            border: 1px solid #5a4b37;
            border-radius: 3px;
            padding: 2px 6px;
            font-size: 11px;
            font-weight: bold;
        }
    ]])
    self.ui.hoverLabel:hide()
    self.ui.hoverLabel:raise()

    -- Create control buttons
    self:setupControls()

    return true
end

-- ============================================================
-- UI CONTROLS (Zoom, World Map, Zone Link)
-- ============================================================

function ArjMapper:setupControls()
    if not ArjUI or not ArjUI.mapWrap then return end
    
    local btnStyle = [[
        QLabel {
            background-color: rgba(10, 9, 8, 220);
            color: #a09080;
            border: 1px solid #5a4b37;
            border-radius: 3px;
            font-size: 14px;
            font-weight: bold;
        }
        QLabel:hover {
            background-color: rgba(22, 20, 15, 240);
            color: #d0c0a0;
            border-color: #8c6e46;
        }
    ]]

    -- Zoom In button (+)
    if self.ui.zoomIn then self.ui.zoomIn:hide() end
    self.ui.zoomIn = Geyser.Label:new({
        name = "ArjMapper_ZoomIn_" .. os.time(),
        x = "82%", y = "2%",
        width = "8%", height = "8%",
    }, ArjUI.mapWrap)
    self.ui.zoomIn:setStyleSheet(btnStyle)
    self.ui.zoomIn:echo("<center>+</center>")
    self.ui.zoomIn:setClickCallback(function()
        ArjMapper:zoomIn()
    end)
    self.ui.zoomIn:show()
    self.ui.zoomIn:raise()

    -- Zoom Out button (-)
    if self.ui.zoomOut then self.ui.zoomOut:hide() end
    self.ui.zoomOut = Geyser.Label:new({
        name = "ArjMapper_ZoomOut_" .. os.time(),
        x = "91%", y = "2%",
        width = "8%", height = "8%",
    }, ArjUI.mapWrap)
    self.ui.zoomOut:setStyleSheet(btnStyle)
    self.ui.zoomOut:echo("<center>−</center>")
    self.ui.zoomOut:setClickCallback(function()
        ArjMapper:zoomOut()
    end)
    self.ui.zoomOut:show()
    self.ui.zoomOut:raise()
end

-- ============================================================
-- ZOOM FUNCTIONS
-- ============================================================

function ArjMapper:zoomIn()
    if not self.state or not self.config then return end
    
    -- Don't zoom zone map when in wilderness mode
    if self.state.inWilderness or self.state.lastDisplayMode == "wilderness" then
        -- Wilderness zoom: increase font size
        self.config.wildZoom = math.min(2.0, (self.config.wildZoom or 1.0) + 0.1)
        if self.ui and self.ui.wildConsole then
            self.ui.wildConsole:setFontSize(math.floor(self.config.wildFontSize * self.config.wildZoom))
        end
        return
    end
    
    local newSize = self.config.roomSize + 2
    if newSize <= 24 then
        self.config.roomSize = newSize
        self.config.cellSize = newSize + 6
        self.config.passageWidth = math.max(4, math.floor(newSize / 3))
        self:clearZoneDisplay()
        self:renderZoneMap()
    end
end

function ArjMapper:zoomOut()
    if not self.state or not self.config then return end
    
    -- Don't zoom zone map when in wilderness mode
    if self.state.inWilderness or self.state.lastDisplayMode == "wilderness" then
        -- Wilderness zoom: decrease font size
        self.config.wildZoom = math.max(0.5, (self.config.wildZoom or 1.0) - 0.1)
        if self.ui and self.ui.wildConsole then
            self.ui.wildConsole:setFontSize(math.floor(self.config.wildFontSize * self.config.wildZoom))
        end
        return
    end
    
    local newSize = self.config.roomSize - 2
    if newSize >= 8 then
        self.config.roomSize = newSize
        self.config.cellSize = newSize + 6
        self.config.passageWidth = math.max(4, math.floor(newSize / 3))
        self:clearZoneDisplay()
        self:renderZoneMap()
    end
end

-- ============================================================
-- WILDERNESS DISPLAY
-- ============================================================

function ArjMapper:showWilderness()
    if not self.ui.wildConsole and not self:setupUI() then return end
    if self.state.lastDisplayMode == "wilderness" then return end

    self:clearZoneDisplay()
    if self.ui.zoneContainer then self.ui.zoneContainer:hide() end
    if ArjUI and ArjUI.mapper then ArjUI.mapper:hide() end

    self.ui.wildConsole:show()
    self.state.lastDisplayMode = "wilderness"
end

function ArjMapper:updateWildernessMap(mapData)
    if not self.ui.wildConsole or not mapData or not mapData.map then return end

    local parsed = self:parseWildernessMap(mapData.map)
    local containerH = self.ui.wildConsole:get_height() or 250
    local fontSize = math.floor(self.config.wildFontSize * self.config.wildZoom)
    local lineHeight = fontSize + 2

    local lineCount = 0
    for _ in parsed:gmatch("[^\n]+") do lineCount = lineCount + 1 end

    local vPadding = math.max(0, math.floor((containerH - lineCount * lineHeight) / (lineHeight * 2)))

    self.ui.wildConsole:clear()
    self.ui.wildConsole:decho(string.rep("\n", vPadding) .. parsed)
end

-- ============================================================
-- ZONE - CLEAR
-- ============================================================

function ArjMapper:clearZoneDisplay()
    for key, label in pairs(self.ui.roomLabels) do
        if type(label) == "table" and label.hide then 
            label:hide() 
        end
    end
    self.ui.roomLabels = {}
end

-- ============================================================
-- ZONE - SHOW
-- ============================================================

function ArjMapper:showZoneMap()
    if not self.ui.zoneContainer and not self:setupUI() then return end

    if self.ui.wildConsole then self.ui.wildConsole:hide() end
    if ArjUI and ArjUI.mapper then ArjUI.mapper:hide() end

    self.ui.zoneContainer:show()
    self.state.lastDisplayMode = "zone"

    self:renderZoneMap()
end

-- ============================================================
-- ZONE LAYOUT WITH SECTION DETECTION
-- ============================================================

function ArjMapper:computeZoneLayout(zoneId)
    local data = self.state.zoneData[zoneId]
    if not data or not data.nodes or not data.edges then return false end
    if data.layoutComputed then return true end

    local nodesById = {}
    local exitCount = {}  -- track how many exits each room has (hub detection)
    for _, n in ipairs(data.nodes) do
        nodesById[n.id] = n
        n.gx, n.gy, n.gz = nil, nil, nil
        n.exits = {}
        n.section = nil
        exitCount[n.id] = 0
    end

    -- Build adjacency and reverse adjacency (for bidirectional detection)
    local adjacency = {}
    local reverseAdj = {}  -- reverseAdj[to][from] = dir
    for _, e in ipairs(data.edges) do
        if e.from and e.to and e.direction then
            local dir = e.direction:lower():gsub("%s+", "")
            adjacency[e.from] = adjacency[e.from] or {}
            table.insert(adjacency[e.from], { to = e.to, dir = dir })
            
            reverseAdj[e.to] = reverseAdj[e.to] or {}
            reverseAdj[e.to][e.from] = dir
            
            if nodesById[e.from] then
                nodesById[e.from].exits[dir] = e.to
                exitCount[e.from] = (exitCount[e.from] or 0) + 1
            end
        end
    end

    local dirVec = {
        north     = {  0,  1,  0 },
        south     = {  0, -1,  0 },
        east      = {  1,  0,  0 },
        west      = { -1,  0,  0 },
        up        = {  0,  0,  1 },
        down      = {  0,  0, -1 },
        northeast = {  1,  1,  0 },
        northwest = { -1,  1,  0 },
        southeast = {  1, -1,  0 },
        southwest = { -1, -1,  0 },
    }
    
    -- Opposite directions for loop closure
    local opposite = {
        north = "south", south = "north",
        east = "west", west = "east",
        up = "down", down = "up",
        northeast = "southwest", southwest = "northeast",
        northwest = "southeast", southeast = "northwest",
    }

    local occupied = {}
    local function gridKey(x, y, z) return x .. "," .. y .. "," .. z end
    local function isOccupied(x, y, z) return occupied[gridKey(x, y, z)] ~= nil end
    local function getOccupant(x, y, z) return occupied[gridKey(x, y, z)] end
    local function occupy(x, y, z, id) occupied[gridKey(x, y, z)] = id end

    -- Check if placing at (tx, ty) would close a loop with an already-placed neighbor
    local function wouldCloseLoop(nodeId, tx, ty, tz)
        local node = nodesById[nodeId]
        if not node then return false end
        
        for dir, targetId in pairs(node.exits) do
            local target = nodesById[targetId]
            if target and target.gx then
                local vec = dirVec[dir]
                if vec then
                    local expectedX = tx + vec[1]
                    local expectedY = ty + vec[2]
                    local expectedZ = tz + vec[3]
                    if target.gx == expectedX and target.gy == expectedY and (target.gz or 0) == expectedZ then
                        return true  -- This placement closes a loop!
                    end
                end
            end
        end
        return false
    end

    -- Find free spot with loop closure awareness
    local function findFreeSpot(tx, ty, tz, dirHintX, dirHintY, nodeId)
        if not isOccupied(tx, ty, tz) then
            return tx, ty, tz
        end
        
        local candidates = {}
        for r = 1, 50 do
            for dx = -r, r do
                for dy = -r, r do
                    if math.abs(dx) == r or math.abs(dy) == r then
                        local nx, ny = tx + dx, ty + dy
                        if not isOccupied(nx, ny, tz) then
                            local score = r * 10
                            
                            -- Direction preference
                            if dirHintX and dirHintX ~= 0 then
                                if (dirHintX > 0 and dx < 0) or (dirHintX < 0 and dx > 0) then
                                    score = score + 100
                                elseif (dirHintX > 0 and dx > 0) or (dirHintX < 0 and dx < 0) then
                                    score = score - 5
                                end
                            end
                            if dirHintY and dirHintY ~= 0 then
                                if (dirHintY > 0 and dy < 0) or (dirHintY < 0 and dy > 0) then
                                    score = score + 100
                                elseif (dirHintY > 0 and dy > 0) or (dirHintY < 0 and dy < 0) then
                                    score = score - 5
                                end
                            end
                            
                            -- Bonus for loop closure
                            if nodeId and wouldCloseLoop(nodeId, nx, ny, tz) then
                                score = score - 200  -- Strong preference for loop closure
                            end
                            
                            table.insert(candidates, {x = nx, y = ny, score = score})
                        end
                    end
                end
            end
            
            if #candidates > 0 then
                table.sort(candidates, function(a, b) return a.score < b.score end)
                return candidates[1].x, candidates[1].y, tz
            end
        end
        return tx, ty, tz
    end

    -- Sort nodes by exit count (hubs first) for better initial placement
    local sortedNodes = {}
    for _, n in ipairs(data.nodes) do
        table.insert(sortedNodes, n)
    end
    table.sort(sortedNodes, function(a, b)
        return (exitCount[a.id] or 0) > (exitCount[b.id] or 0)
    end)

    -- Track sections and their bounds for packing
    local currentSection = 0
    local globalVisited = {}
    local sectionBounds = {}  -- [section] = {minX, maxX, minY, maxY}

    for _, startNode in ipairs(sortedNodes) do
        if not globalVisited[startNode.id] then
            currentSection = currentSection + 1
            sectionBounds[currentSection] = {minX = 0, maxX = 0, minY = 0, maxY = 0}
            
            local startId = startNode.id
            if nodesById[startId].gx == nil then
                local sx, sy, sz = 0, 0, 0
                if currentSection > 1 then
                    -- Pack sections: place new section after previous section's bounds
                    local prevBounds = sectionBounds[currentSection - 1]
                    sx = prevBounds.maxX + 3  -- 3 cell gap between sections
                end
                local fx, fy, fz = findFreeSpot(sx, sy, sz, 0, 0, startId)
                nodesById[startId].gx, nodesById[startId].gy, nodesById[startId].gz = fx, fy, fz
                occupy(fx, fy, fz, startId)
                sectionBounds[currentSection].minX = fx
                sectionBounds[currentSection].maxX = fx
                sectionBounds[currentSection].minY = fy
                sectionBounds[currentSection].maxY = fy
            end
            nodesById[startId].section = currentSection

            -- BFS with priority for bidirectional edges
            local queue = { startId }
            local qIdx = 1
            globalVisited[startId] = true

            while qIdx <= #queue do
                local id = queue[qIdx]
                qIdx = qIdx + 1

                local node = nodesById[id]
                if node and node.gx then
                    local baseX, baseY, baseZ = node.gx, node.gy, node.gz or 0
                    local neighbors = adjacency[id] or {}
                    
                    -- Sort neighbors: bidirectional edges first, then by exit count
                    table.sort(neighbors, function(a, b)
                        local aHasReturn = reverseAdj[id] and reverseAdj[id][a.to]
                        local bHasReturn = reverseAdj[id] and reverseAdj[id][b.to]
                        if aHasReturn and not bHasReturn then return true end
                        if bHasReturn and not aHasReturn then return false end
                        return (exitCount[a.to] or 0) > (exitCount[b.to] or 0)
                    end)

                    for _, edge in ipairs(neighbors) do
                        local target = nodesById[edge.to]
                        if target then
                            if target.gx == nil then
                                local vec = dirVec[edge.dir]
                                local idealX, idealY, idealZ
                                if vec then
                                    idealX = baseX + vec[1]
                                    idealY = baseY + vec[2]
                                    idealZ = baseZ + vec[3]
                                else
                                    idealX, idealY, idealZ = baseX + 1, baseY, baseZ
                                end

                                local dirHintX = vec and vec[1] or 0
                                local dirHintY = vec and vec[2] or 0
                                local fx, fy, fz = findFreeSpot(idealX, idealY, idealZ, dirHintX, dirHintY, target.id)
                                target.gx, target.gy, target.gz = fx, fy, fz
                                occupy(fx, fy, fz, target.id)
                                
                                -- Update section bounds
                                local bounds = sectionBounds[currentSection]
                                if fx < bounds.minX then bounds.minX = fx end
                                if fx > bounds.maxX then bounds.maxX = fx end
                                if fy < bounds.minY then bounds.minY = fy end
                                if fy > bounds.maxY then bounds.maxY = fy end
                            end
                            
                            target.section = currentSection
                            
                            if not globalVisited[target.id] then
                                globalVisited[target.id] = true
                                table.insert(queue, target.id)
                            end
                        end
                    end
                end
            end
        end
    end

    data.sectionCount = currentSection
    data.sectionBounds = sectionBounds
    data.layoutComputed = true
    return true
end

-- ============================================================
-- GET SECTION COLOR
-- ============================================================

function ArjMapper:getSectionColor(section)
    local colors = self.config.sectionColors
    if not section or section < 1 then return colors[1] end
    local idx = ((section - 1) % #colors) + 1
    return colors[idx]
end

-- ============================================================
-- CHECK IF EXIT IS FAR AND GET TARGET SECTION
-- ============================================================

function ArjMapper:getExitInfo(node, dir, nodesById)
    local targetId = node.exits[dir]
    if not targetId then return nil end
    
    local target = nodesById[targetId]
    if not target or not target.gx or not target.gy then return nil end
    
    local dx = math.abs(target.gx - node.gx)
    local dy = math.abs(target.gy - node.gy)
    
    return {
        isFar = (dx > 1 or dy > 1),
        targetSection = target.section,
        targetId = targetId
    }
end

-- ============================================================
-- CREATE OR GET LABEL
-- ============================================================

function ArjMapper:getLabel(key, x, y, w, h, tooltip, roomId)
    local label = self.ui.roomLabels[key]
    if not label then
        label = Geyser.Label:new({
            name = "Arj_" .. key .. "_" .. os.time(),
            x = x, y = y,
            width = w, height = h,
        }, self.ui.zoneContainer)
        self.ui.roomLabels[key] = label
    else
        label:move(x, y)
        label:resize(w, h)
    end
    
    -- Set instant hover tooltip if provided (for room labels)
    if tooltip and roomId then
        label:setOnEnter(function()
            if ArjMapper.ui.hoverLabel then
                ArjMapper.ui.hoverLabel:echo("<center>" .. tooltip .. "</center>")
                -- Position above the room, centered
                local labelX = x - 80 + w/2  -- center the 200px wide hover label
                local labelY = y - 28  -- above the room
                if labelY < 0 then labelY = y + h + 4 end  -- below if too high
                ArjMapper.ui.hoverLabel:move(labelX, labelY)
                ArjMapper.ui.hoverLabel:show()
                ArjMapper.ui.hoverLabel:raise()
            end
        end)
        label:setOnLeave(function()
            if ArjMapper.ui.hoverLabel then
                ArjMapper.ui.hoverLabel:hide()
            end
        end)
    end
    
    return label
end
-- ZONE RENDER
-- ============================================================

function ArjMapper:renderZoneMap()
    if not self.ui.zoneContainer then return end
    
    -- Throttle: don't re-render more than 4x per second
    local now = os.clock()
    if now - (self.state.lastRenderTime or 0) < 0.25 then return end
    self.state.lastRenderTime = now

    local zoneId = self.state.currentZone
    local currentRoom = self.state.currentRoom
    local data = self.state.zoneData[zoneId]

    if not data or not data.nodes or #data.nodes == 0 then
        self.ui.zoneContainer:echo([[
            <center><br/><br/><font color='#888' size='4'>No map data</font></center>
        ]])
        return
    end

    if not self:computeZoneLayout(zoneId) then
        self.ui.zoneContainer:echo([[
            <center><br/><br/><font color='#888' size='4'>Layout failed</font></center>
        ]])
        return
    end

    if self.state.lastZoneId ~= zoneId then
        self:clearZoneDisplay()
        self.state.lastZoneId = zoneId
    end

    -- Find player
    local playerGX, playerGY, playerGZ = 0, 0, 0
    local playerNode = nil
    local nodesById = {}
    
    for _, node in ipairs(data.nodes) do
        nodesById[node.id] = node
        if node.id == currentRoom and node.gx and node.gy then
            playerGX, playerGY = node.gx, node.gy
            playerGZ = node.gz or 0
            playerNode = node
        end
    end
    
    self.state.currentZ = playerGZ

    local containerW = self.ui.zoneContainer:get_width() or 250
    local containerH = self.ui.zoneContainer:get_height() or 250

    local roomSize = self.config.roomSize
    local cellSize = self.config.cellSize
    local passageWidth = self.config.passageWidth
    local viewRadius = self.config.viewRadius

    local centerX = math.floor(containerW / 2)
    local centerY = math.floor(containerH / 2)

    self.ui.zoneContainer:echo("")

    local colors = self.config.colors
    local activeLabels = {}
    local rc = colors.roomColor
    
    -- Get doors for current room from state
    local currentRoomDoors = self.state.roomDoors[currentRoom] or {}

    -- Render rooms on current Z level
    for _, node in ipairs(data.nodes) do
        if node.gx and node.gy and (node.gz or 0) == playerGZ then
            local dx = node.gx - playerGX
            local dy = node.gy - playerGY

            if math.abs(dx) <= viewRadius and math.abs(dy) <= viewRadius then
                local cellCenterX = centerX + (dx * cellSize)
                local cellCenterY = centerY - (dy * cellSize)
                
                local roomX = cellCenterX - roomSize/2
                local roomY = cellCenterY - roomSize/2

                -- Only render rooms that are fully within the container bounds (with small margin)
                if roomX >= 0 and roomX + roomSize <= containerW and
                   roomY >= 0 and roomY + roomSize <= containerH then

                    -- Build tooltip with room info (format like web: #ID - Name)
                    local roomName = node.label or node.name or ("Room " .. tostring(node.id))
                    -- Strip Duris color codes (&+X, &-X, &=XY, &N, &], etc.)
                    roomName = roomName:gsub("&%+%a", ""):gsub("&%-%a", ""):gsub("&=%a%a", ""):gsub("&[nN%]]", "")
                    local tooltip = "#" .. tostring(node.id) .. " - " .. roomName

                    -- Unified floor approach: room and passages are same color, walls only on outer edges
                    local roomKey = "room_" .. tostring(node.id)
                    local roomLabel = self:getLabel(roomKey, roomX, roomY, roomSize, roomSize, tooltip, node.id)
                    local isCurrentRoom = (node.id == currentRoom)
                    local floorC = colors.floorColor
                    local roomC = isCurrentRoom and colors.roomHighlight or floorC
                    local exits = node.exits or {}
                    
                    -- Get door info for this room (only current room has live door data)
                    local doorInfo = {}
                    if node.id == currentRoom then
                        doorInfo = currentRoomDoors
                    end
                    
                    -- Floor tile with subtle rounded corners
                    local cornerRadius = 3
                    roomLabel:setStyleSheet(string.format(
                        "background-color: rgb(%d,%d,%d); border-radius: %dpx;",
                        roomC[1], roomC[2], roomC[3], cornerRadius))
                    roomLabel:show()
                    roomLabel:raise()
                    activeLabels[roomKey] = true

                    -- Helper to get passage color (same as floor, unless door/far)
                    local function getPassageColor(dir)
                        if doorInfo[dir] then
                            return colors.doorClosed
                        end
                        local exitInfo = self:getExitInfo(node, dir, nodesById)
                        if exitInfo and exitInfo.isFar then
                            return colors.farExit
                        end
                        return floorC  -- same as room floor
                    end

                    -- Passages extend the floor - same color as room
                    -- North passage
                    if exits.north then
                        local passKey = "pass_n_" .. tostring(node.id)
                        local passX = cellCenterX - passageWidth/2
                        local passY = roomY - (cellSize - roomSize)/2
                        local passH = (cellSize - roomSize)/2
                        
                        local passLabel = self:getLabel(passKey, passX, passY, passageWidth, passH)
                        local pc = getPassageColor("north")
                        passLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d);", pc[1], pc[2], pc[3]))
                        passLabel:show()
                        activeLabels[passKey] = true
                    end

                    -- South passage
                    if exits.south then
                        local passKey = "pass_s_" .. tostring(node.id)
                        local passX = cellCenterX - passageWidth/2
                        local passY = roomY + roomSize
                        local passH = (cellSize - roomSize)/2
                        
                        local passLabel = self:getLabel(passKey, passX, passY, passageWidth, passH)
                        local pc = getPassageColor("south")
                        passLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d);", pc[1], pc[2], pc[3]))
                        passLabel:show()
                        activeLabels[passKey] = true
                    end

                    -- East passage
                    if exits.east then
                        local passKey = "pass_e_" .. tostring(node.id)
                        local passX = roomX + roomSize
                        local passY = cellCenterY - passageWidth/2
                        local passW = (cellSize - roomSize)/2
                        
                        local passLabel = self:getLabel(passKey, passX, passY, passW, passageWidth)
                        local pc = getPassageColor("east")
                        passLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d);", pc[1], pc[2], pc[3]))
                        passLabel:show()
                        activeLabels[passKey] = true
                    end

                    -- West passage
                    if exits.west then
                        local passKey = "pass_w_" .. tostring(node.id)
                        local passX = roomX - (cellSize - roomSize)/2
                        local passY = cellCenterY - passageWidth/2
                        local passW = (cellSize - roomSize)/2
                        
                        local passLabel = self:getLabel(passKey, passX, passY, passW, passageWidth)
                        local pc = getPassageColor("west")
                        passLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d);", pc[1], pc[2], pc[3]))
                        passLabel:show()
                        activeLabels[passKey] = true
                    end

                    -- Up indicator (arrow in top-right corner)
                    if exits.up then
                        local upKey = "up_" .. tostring(node.id)
                        local indSize = 10
                        local upLabel = self:getLabel(upKey, roomX + roomSize - indSize, roomY, indSize, indSize)
                        local uc = colors.upExit
                        upLabel:setStyleSheet(string.format(
                            "background-color: transparent; color: rgb(%d,%d,%d); font-size: 9px; font-weight: bold;",
                            uc[1], uc[2], uc[3]))
                        upLabel:echo("<center>▲</center>")
                        upLabel:show()
                        upLabel:raise()
                        activeLabels[upKey] = true
                    end

                    -- Down indicator (arrow in bottom-right corner)
                    if exits.down then
                        local downKey = "down_" .. tostring(node.id)
                        local indSize = 10
                        local downLabel = self:getLabel(downKey, roomX + roomSize - indSize, roomY + roomSize - indSize, indSize, indSize)
                        local dc = colors.downExit
                        downLabel:setStyleSheet(string.format(
                            "background-color: transparent; color: rgb(%d,%d,%d); font-size: 9px; font-weight: bold;",
                            dc[1], dc[2], dc[3]))
                        downLabel:echo("<center>▼</center>")
                        downLabel:show()
                        downLabel:raise()
                        activeLabels[downKey] = true
                    end

                    -- Diagonal passages with small connecting squares
                    -- Creates a visual "stepping stone" path in the diagonal direction
                    local diagPassSize = math.floor(passageWidth * 0.8)
                    local diagOffset = math.floor(cellSize / 3)
                    
                    -- Northeast passage
                    if exits.northeast or exits.ne then
                        local neKey = "pass_ne_" .. tostring(node.id)
                        local neX = roomX + roomSize - 2
                        local neY = roomY - diagOffset + diagPassSize/2
                        local neLabel = self:getLabel(neKey, neX, neY, diagPassSize, diagPassSize)
                        local pc = getPassageColor("northeast")
                        neLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d); border-radius: 2px;",
                            pc[1], pc[2], pc[3]))
                        neLabel:show()
                        activeLabels[neKey] = true
                    end
                    
                    -- Northwest passage
                    if exits.northwest or exits.nw then
                        local nwKey = "pass_nw_" .. tostring(node.id)
                        local nwX = roomX - diagOffset + diagPassSize/2
                        local nwY = roomY - diagOffset + diagPassSize/2
                        local nwLabel = self:getLabel(nwKey, nwX, nwY, diagPassSize, diagPassSize)
                        local pc = getPassageColor("northwest")
                        nwLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d); border-radius: 2px;",
                            pc[1], pc[2], pc[3]))
                        nwLabel:show()
                        activeLabels[nwKey] = true
                    end
                    
                    -- Southeast passage
                    if exits.southeast or exits.se then
                        local seKey = "pass_se_" .. tostring(node.id)
                        local seX = roomX + roomSize - 2
                        local seY = roomY + roomSize - diagPassSize/2
                        local seLabel = self:getLabel(seKey, seX, seY, diagPassSize, diagPassSize)
                        local pc = getPassageColor("southeast")
                        seLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d); border-radius: 2px;",
                            pc[1], pc[2], pc[3]))
                        seLabel:show()
                        activeLabels[seKey] = true
                    end
                    
                    -- Southwest passage
                    if exits.southwest or exits.sw then
                        local swKey = "pass_sw_" .. tostring(node.id)
                        local swX = roomX - diagOffset + diagPassSize/2
                        local swY = roomY + roomSize - diagPassSize/2
                        local swLabel = self:getLabel(swKey, swX, swY, diagPassSize, diagPassSize)
                        local pc = getPassageColor("southwest")
                        swLabel:setStyleSheet(string.format(
                            "background-color: rgb(%d,%d,%d); border-radius: 2px;",
                            pc[1], pc[2], pc[3]))
                        swLabel:show()
                        activeLabels[swKey] = true
                    end
                end
            end
        end
    end

    -- Player dot with glow effect
    if playerNode then
        -- Outer glow ring
        local glowKey = "player_glow"
        local glowSize = self.config.playerDotSize + 4
        local glowLabel = self:getLabel(glowKey, centerX - glowSize/2, centerY - glowSize/2, glowSize, glowSize)
        local gc = colors.playerGlow
        glowLabel:setStyleSheet(string.format(
            "background-color: rgba(%d,%d,%d,80); border-radius: %dpx;",
            gc[1], gc[2], gc[3], math.floor(glowSize/2)))
        glowLabel:show()
        glowLabel:raise()
        activeLabels[glowKey] = true
        
        -- Inner dot
        local dotKey = "player_dot"
        local dotSize = self.config.playerDotSize
        local dotLabel = self:getLabel(dotKey, centerX - dotSize/2, centerY - dotSize/2, dotSize, dotSize)
        local dc = colors.playerDot
        dotLabel:setStyleSheet(string.format(
            "background-color: rgb(%d,%d,%d); border-radius: %dpx; border: 1px solid rgba(255,255,255,100);",
            dc[1], dc[2], dc[3], math.floor(dotSize/2)))
        dotLabel:show()
        dotLabel:raise()
        activeLabels[dotKey] = true
    end

    -- Hide unused
    for key, label in pairs(self.ui.roomLabels) do
        if not activeLabels[key] and type(label) == "table" and label.hide then
            label:hide()
        end
    end
    
    -- Raise our zoom buttons above the map after rendering
    if self.ui.zoomIn then self.ui.zoomIn:raise() end
    if self.ui.zoomOut then self.ui.zoomOut:raise() end
end

-- ============================================================
-- FETCH ZONE DATA
-- ============================================================

function ArjMapper:fetchZoneData(zoneId, callback)
    if not zoneId then return end

    if self.state.zoneData[zoneId] then
        if callback then callback(self.state.zoneData[zoneId]) end
        return
    end

    local url = self.config.apiBase .. tostring(zoneId) .. "/map-data"
    local tempFile = getMudletHomeDir() .. "/arjmapper_zone_" .. zoneId .. ".json"

    local handlerId, errorId

    handlerId = registerAnonymousEventHandler("sysDownloadDone", function(event, filename)
        if filename == tempFile then
            local file = io.open(filename, "r")
            if file then
                local content = file:read("*a")
                file:close()
                local ok, data = pcall(yajl.to_value, content)
                if ok and data then
                    self.state.zoneData[zoneId] = data
                    self:out(string.format("<green>[Mapper]<reset> Zone %s: %d rooms\n",
                        tostring(zoneId), #(data.nodes or {})))
                    
                    if callback then callback(data) end
                end
                os.remove(filename)
            end
            killAnonymousEventHandler(handlerId)
            if errorId then killAnonymousEventHandler(errorId) end
        end
    end)

    errorId = registerAnonymousEventHandler("sysDownloadError", function(event, err, filename)
        if filename == tempFile then
            self:out("<yellow>[Mapper]<reset> Zone fetch failed\n")
            killAnonymousEventHandler(handlerId)
            killAnonymousEventHandler(errorId)
        end
    end)

    downloadFile(tempFile, url)
end

-- ============================================================
-- PARSE DOORS FROM GMCP EXITS
-- Duris uses # to mark doors, e.g., "South#" means south has a door
-- ============================================================

function ArjMapper:parseDoorsFromGMCP(roomData)
    local doors = {}
    
    if roomData and roomData.exits then
        -- The exits might be in format { "North", "South#", "East" }
        -- or { north = 123, south = 456 }
        -- We need to check the raw GMCP data
        
        -- Check if we have the raw exit string from somewhere
        -- For now, we'll store this per-room as we visit
    end
    
    return doors
end

-- ============================================================
-- PROCESS ROOM
-- ============================================================

function ArjMapper:processRoom(roomData)
    if not self.state.enabled or not roomData then return end

    local wasWild = self.state.inWilderness
    local isWild = self:isWilderness(roomData)

    self.state.inWilderness = isWild

    if isWild then
        if not wasWild then self:out("<yellow>[Mapper]<reset> Wilderness\n") end
        self:showWilderness()
        return
    end

    if wasWild then self:out("<green>[Mapper]<reset> Zone\n") end

    local roomId = roomData.num
    local zoneId = roomData.zone
    if not roomId or roomId == 0 then return end

    self.state.currentRoom = roomId
    self.state.currentZone = zoneId
    self.state.currentCoords = roomData.coords
    self.state.visitedRooms[roomId] = true
    
    -- Parse doors from exits
    -- GMCP might have: { ["East #"] = 123 } or { east = 123 } with separate door info
    -- The # indicates a door
    local doors = {}
    if roomData.exits then
        for exitKey, dest in pairs(roomData.exits) do
            local keyStr = tostring(exitKey):lower()
            
            -- Check if the key contains # (door marker)
            if keyStr:match("#") then
                -- Extract direction by removing # and extra spaces
                local cleanDir = keyStr:gsub("#", ""):gsub("%s+", "")
                doors[cleanDir] = true
                
                if self.config.debug then
                    self:out(string.format("<dim_gray>[Door] Found door: '%s' -> '%s'<reset>\n", keyStr, cleanDir))
                end
            end
        end
    end
    self.state.roomDoors[roomId] = doors

    if zoneId and not self.state.zoneData[zoneId] then
        self:fetchZoneData(zoneId, function() self:showZoneMap() end)
    else
        self:showZoneMap()
    end
end

function ArjMapper:processWildernessMap(mapData)
    if not self.state.enabled then return end
    self:updateWildernessMap(mapData)
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

function ArjMapper:setupHandlers()
    for _, h in ipairs(self.handlers) do killAnonymousEventHandler(h) end
    self.handlers = {}

    table.insert(self.handlers, registerAnonymousEventHandler("gmcp.Room.Info", function()
        if gmcp and gmcp.Room and gmcp.Room.Info then
            ArjMapper:processRoom(gmcp.Room.Info)
        end
    end))

    table.insert(self.handlers, registerAnonymousEventHandler("gmcp.Room.Map", function()
        if gmcp and gmcp.Room and gmcp.Room.Map then
            ArjMapper:processWildernessMap(gmcp.Room.Map)
        end
    end))
end

-- ============================================================
-- UTILITY
-- ============================================================

function ArjMapper:out(text)
    if ArjUI and ArjUI.console then
        ArjUI.console:cecho(text)
    else
        cecho(text)
    end
end

-- ============================================================
-- COMMANDS
-- ============================================================

function ArjMapper:setupAliases()
    if self.alias then killAlias(self.alias) end

    self.alias = tempAlias("^mapper ?(.*)$", function()
        local cmd = (matches[2] or ""):lower()

        if cmd == "on" then
            ArjMapper.state.enabled = true
            ArjMapper:out("<green>[Mapper]<reset> Enabled\n")

        elseif cmd == "off" then
            ArjMapper.state.enabled = false
            ArjMapper:out("<yellow>[Mapper]<reset> Disabled\n")
            
        elseif cmd == "debug" then
            -- Show current room's GMCP data
            if gmcp and gmcp.Room and gmcp.Room.Info then
                ArjMapper:out("<cyan>[Debug] Room Info:<reset>\n")
                ArjMapper:out(string.format("  num = %s\n", tostring(gmcp.Room.Info.num)))
                ArjMapper:out(string.format("  zone = %s\n", tostring(gmcp.Room.Info.zone)))
                
                if gmcp.Room.Info.exits then
                    ArjMapper:out("<cyan>[Debug] Exits (raw):<reset>\n")
                    for k, v in pairs(gmcp.Room.Info.exits) do
                        ArjMapper:out(string.format("  key='%s' (%s) -> value='%s' (%s)\n", 
                            tostring(k), type(k), tostring(v), type(v)))
                    end
                end
                
                -- Show what doors we detected
                local roomId = gmcp.Room.Info.num
                if roomId and ArjMapper.state.roomDoors[roomId] then
                    ArjMapper:out("<cyan>[Debug] Detected doors:<reset>\n")
                    for dir, val in pairs(ArjMapper.state.roomDoors[roomId]) do
                        ArjMapper:out(string.format("  %s = %s\n", dir, tostring(val)))
                    end
                else
                    ArjMapper:out("<cyan>[Debug] No doors detected<reset>\n")
                end
                
                -- Show zone data exits for this room
                local zoneId = gmcp.Room.Info.zone
                if zoneId and ArjMapper.state.zoneData[zoneId] then
                    local data = ArjMapper.state.zoneData[zoneId]
                    for _, node in ipairs(data.nodes or {}) do
                        if node.id == roomId then
                            ArjMapper:out("<cyan>[Debug] Zone data exits for this room:<reset>\n")
                            for dir, dest in pairs(node.exits or {}) do
                                ArjMapper:out(string.format("  %s -> %s\n", dir, tostring(dest)))
                            end
                            break
                        end
                    end
                end
            else
                ArjMapper:out("<yellow>[Debug] No GMCP Room data available<reset>\n")
            end

        elseif cmd == "status" then
            ArjMapper:showStatus()

        elseif cmd == "reload" then
            ArjMapper.state.zoneData = {}
            ArjMapper.state.lastZoneId = nil
            ArjMapper:clearZoneDisplay()
            ArjMapper:out("<cyan>[Mapper]<reset> Cache cleared\n")

        elseif cmd:match("^size%s+(%d+)") then
            local val = tonumber(cmd:match("^size%s+(%d+)"))
            if val and val >= 8 and val <= 20 then
                ArjMapper.config.roomSize = val
                ArjMapper.config.cellSize = val + 6
                ArjMapper:clearZoneDisplay()
                ArjMapper:renderZoneMap()
                ArjMapper:out(string.format("<cyan>[Mapper]<reset> Room size: %d\n", val))
            end

        else
            ArjMapper:out("<cyan>[Mapper v1.0]<reset>\n")
            ArjMapper:out("  on | off | status | reload | debug\n")
            ArjMapper:out("  size <8-20> - room size\n")
            ArjMapper:out("\n")
            ArjMapper:out("  <90,170,255>▲<reset>=Up  <90,210,130>▼<reset>=Down  <255,70,70>●<reset>=You\n")
            ArjMapper:out("  <220,70,70>━<reset>=Door  <255,200,100>■<reset>=Diagonal  Colored=Section\n")
        end
    end)
    
    -- Alias to reload/refresh map layout
    tempAlias("^/mapreload$", function()
        ArjMapper.state.zoneData = {}
        ArjMapper:clearZoneDisplay()
        ArjMapper:out("<cyan>[Mapper]<reset> Cache cleared. Move or 'look' to reload.\n")
    end)
end

function ArjMapper:showStatus()
    self:out("\n<cyan>══ ArjMapper v1.0 ══<reset>\n")
    self:out(string.format("  Mode: %s\n",
        self.state.inWilderness and "<yellow>Wild<reset>" or "<green>Zone<reset>"))
    self:out(string.format("  Zone: %s | Room: %s | Z: %d\n",
        tostring(self.state.currentZone), tostring(self.state.currentRoom), self.state.currentZ or 0))
    
    local data = self.state.zoneData[self.state.currentZone]
    if data and data.sectionCount then
        self:out(string.format("  Sections: %d disconnected areas\n", data.sectionCount))
    end
    
    local cached = 0
    for _ in pairs(self.state.zoneData) do cached = cached + 1 end
    self:out(string.format("  Cached: %d zones\n", cached))
    self:out("<cyan>════════════════════<reset>\n")
end

-- ============================================================
-- INIT / CLEANUP
-- ============================================================

function ArjMapper:kill()
    for _, h in ipairs(self.handlers) do killAnonymousEventHandler(h) end
    self.handlers = {}
    if self.alias then killAlias(self.alias) end
    self:clearZoneDisplay()
    if self.ui.wildConsole then self.ui.wildConsole:hide() end
    if self.ui.zoneContainer then self.ui.zoneContainer:hide() end
end

function ArjMapper:init()
    self:kill()

    -- Delay banner and UI setup until ArjUI is ready
    tempTimer(0.5, function()
        ArjMapper:out("\n<green>══ ArjMapper v1.0 ══<reset>\n")
        ArjMapper:out("  <dim_gray>Type 'mapper' for help<reset>\n")
        ArjMapper:out("<green>════════════════════<reset>\n\n")
        ArjMapper:setupUI()
    end)

    self:setupHandlers()
    self:setupAliases()
end

ArjMapper:init()