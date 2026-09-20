-- ArjUI Core v1.1 (Mudlet 4.19.1)
-- GMCP-based UI for Duris MUD
-- Dark Fantasy Aesthetic

ArjUI = ArjUI or {}
ArjUI.VERSION = "1.1.0"
ArjUI.eventHandlers = ArjUI.eventHandlers or {}
ArjUI.playerName = ArjUI.playerName or nil
ArjUI.captureTriggers = ArjUI.captureTriggers or {}
ArjUI.capturing = nil
ArjUI.captureBuffer = {}
ArjUI.customCommands = ArjUI.customCommands or {
  players = {},    -- { {text="Label", cmd="command"}, ... } - target auto-appended
  mobs = {},
  objects = {},
  inventory = {},
  equipment = {}
}
-- Private messaging system (session-only, not persisted)
ArjUI.privateChats = {}  -- { [playerName] = { window, history, unread } }
ArjUI.tellContacts = {}  -- List of players we've had tells with

-- ============================================================
-- CLEANUP
-- ============================================================

function ArjUI:kill()
  for _, handler in ipairs(self.eventHandlers) do
    killAnonymousEventHandler(handler)
  end
  self.eventHandlers = {}
  -- Kill capture triggers
  for _, tid in pairs(self.captureTriggers or {}) do
    pcall(function() killTrigger(tid) end)
  end
  self.captureTriggers = {}
  self.capturing = nil
  self.captureBuffer = {}
  -- Kill routeall trigger
  if self.routeAllTriggerId then
    pcall(function() killTrigger(self.routeAllTriggerId) end)
    self.routeAllTriggerId = nil
  end
  -- Also kill by name in case it's a permanent trigger
  if exists("ArjUI_RouteAll", "trigger") > 0 then
    pcall(function() killTrigger("ArjUI_RouteAll") end)
  end
  -- Clean up popup if open
  if self.addCmdPopup then pcall(function() self.addCmdPopup:hide() end) end
  -- Clean up private chat windows (Label-based custom windows)
  for pname, chat in pairs(self.privateChats or {}) do
    if chat.window then 
      pcall(function() 
        chat.window:hide()
      end)
    end
  end
  if self.bg then
    self.bg:hide()
    self.bg = nil
  end
  if self.main then
    self.main:hide()
    self.main = nil
  end
  -- Restore default borders so main console is visible again
  setBorderTop(0)
  setBorderBottom(0)
  setBorderLeft(0)
  setBorderRight(0)
  -- Re-enable main command line
  pcall(function() enableCommandLine("main") end)
  pcall(function() enableCommandLine() end)
end

function ArjUI:applyBackground()
  -- Package installs to profile folder: getMudletHomeDir()/profiles/[profile]/[package]/
  -- Try multiple possible paths
  local possiblePaths = {
    getMudletHomeDir() .. "/Arjinius Client V1.0/NewDuris v1.png",  -- Old location
    getMudletHomeDir() .. "/Arjinius Client/NewDuris v1.png",       -- Without version
  }
  
  -- Also try profile-relative path if available
  if getProfileName then
    local profile = getProfileName()
    if profile then
      table.insert(possiblePaths, 1, getMudletHomeDir() .. "/profiles/" .. profile .. "/Arjinius Client V1.0/NewDuris v1.png")
      table.insert(possiblePaths, 2, getMudletHomeDir() .. "/profiles/" .. profile .. "/Arjinius Client/NewDuris v1.png")
    end
  end
  
  local bgPath = nil
  for _, path in ipairs(possiblePaths) do
    local normalPath = path:gsub("/", "\\")
    local f = io.open(normalPath, "r")
    if f then
      f:close()
      bgPath = path:gsub("\\", "/")  -- Qt needs forward slashes
      break
    end
  end
  
  if self.bg then
    if bgPath then
      self.bg:setStyleSheet(string.format([[
        border-image: url("%s") 0 0 0 0 stretch stretch;
      ]], bgPath))
    else
      -- Fallback: dark gradient background
      self.bg:setStyleSheet([[
        background-color: qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 #0a0908,stop:0.5 #12100c,stop:1 #0a0908);
      ]])
    end
  end
end

-- ============================================================
-- UTILITIES
-- ============================================================

local function styleSafe(widget, css)
  if widget and widget.setStyleSheet then
    widget:setStyleSheet(css)
  end
end

local function labelSet(labelObj, text)
  if not labelObj then return end
  if labelObj.clear then labelObj:clear() end
  if labelObj.echo then labelObj:echo(text or "") end
end

local function makePanel(parent, name, x, y, w, h, css)
  local panel = Geyser.Label:new({
    name = name, x = x, y = y, width = w, height = h,
  }, parent)
  styleSafe(panel, css)
  labelSet(panel, "")
  return panel
end

local function makeConsole(parent, name, x, y, w, h, fontSize, wrap)
  local console = Geyser.MiniConsole:new({
    name = name, x = x, y = y, width = w, height = h, fontSize = fontSize or 10
  }, parent)
  -- Warm-tinted background - MiniConsoles don't support true transparency
  -- Use a color that blends with the bronze theme
  console:setBgColor(12, 11, 9)
  console:setFgColor(200, 200, 200)
  console:setWrap(wrap or 200)
  setBackgroundColor(console.name, 12, 11, 9, 255)
  return console
end

local function toNum(x) return tonumber(x) end

local function upper3(pos)
  if not pos or type(pos) ~= "string" then return "" end
  return string.upper(pos:sub(1,3))
end

local function pick(tbl, ...)
  if not tbl then return nil end
  for i = 1, select("#", ...) do
    local k = select(i, ...)
    local v = tbl[k]
    if v ~= nil then return v end
  end
  return nil
end

local function stripColors(text)
  if not text then return "" end
  text = text:gsub("&%+.", "")
  text = text:gsub("&=..", "")
  text = text:gsub("&[nN%]]", "")
  text = text:gsub("\27%][^\7]*\7", "")
  text = text:gsub("\27%][^\27]*\27\\", "")
  text = text:gsub("\27%[%d*;?%d*m", "")
  return text
end

-- Duris color code to decho RGB format (for MiniConsoles)
local durisColors = {
  r = "<128,0,0>",       R = "<255,0,0>",
  g = "<0,128,0>",       G = "<0,255,0>",
  b = "<0,0,170>",       B = "<85,85,255>",
  c = "<0,128,128>",     C = "<0,255,255>",
  m = "<128,0,128>",     M = "<255,0,255>",
  y = "<128,128,0>",     Y = "<255,255,0>",
  w = "<192,192,192>",   W = "<255,255,255>",
  L = "<96,96,96>",      l = "<96,96,96>",
}

-- Convert Duris color codes to Mudlet decho format (RGB)
local function durisToDecho(text)
  if not text then return "" end
  local result = {}
  local i, len = 1, #text
  local currentColor = nil
  local buffer = ""
  
  local function flushBuffer()
    if buffer ~= "" then
      if currentColor then
        table.insert(result, currentColor .. buffer)
      else
        table.insert(result, buffer)
      end
      buffer = ""
    end
  end
  
  while i <= len do
    local ch = text:sub(i, i)
    if ch == "&" and i < len then
      local nxt = text:sub(i+1, i+1)
      if nxt == "+" and i + 2 <= len then
        flushBuffer()
        local colorCode = text:sub(i+2, i+2)
        currentColor = durisColors[colorCode]
        i = i + 3
      elseif nxt == "n" or nxt == "N" or nxt == "]" then
        flushBuffer()
        currentColor = nil
        i = i + 2
      elseif nxt == "=" and i + 3 <= len then
        flushBuffer()
        local fgCode = text:sub(i+2, i+2)
        currentColor = durisColors[fgCode]
        i = i + 4
      else
        i = i + 1
      end
    else
      buffer = buffer .. ch
      i = i + 1
    end
  end
  
  flushBuffer()
  return table.concat(result)
end




-- ============================================================
-- TARGET NORMALIZATION (FIX: clickable mobs/objs passing tags)
-- ============================================================

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeTargetName(name)
  if not name then return "" end

  -- 1) remove formats we already handle
  local s = stripColors(name)

  -- 2) remove Mudlet-style tags like <red>, <reset>, etc.
  s = s:gsub("<[^>]+>", "")

  -- 2b) sometimes we get partial/broken tag fragments; strip common leftovers
  s = s:gsub("</[%w_]+", "")
       :gsub("<[%w_]+", "")
       :gsub("/[%w_]+>", "")

  -- 3) collapse whitespace
  s = trim(s):gsub("%s+", " ")

  -- 4) optionally strip leading articles (often helps targeting)
  s = s:gsub("^[Aa]n%s+", "")
       :gsub("^[Aa]%s+", "")
       :gsub("^[Tt]he%s+", "")

  return trim(s)
end

local function quoteIfNeeded(s)
  s = trim(s or "")
  if s:find("%s") then
    return "'" .. s .. "'"
  end
  return s
end

local function durisTargetKey(name)
  -- Start from the clean display name
  local s = normalizeTargetName(name)
  s = trim(s)
  if s == "" then return "" end

  -- If it has an "of ..." tail, drop it (corpse of a raccoon -> corpse)
  -- This avoids the classic "that isn't a container" / parse confusion.
  if s:find("%s+[Oo][Ff]%s+") then
    local head = s:match("^(.-)%s+[Oo][Ff]%s+.+$")
    if head and head ~= "" then s = trim(head) end
  end

  -- If it's still multi-word, prefer the last word as a stable keyword
  -- (black wolf -> wolf) which Duris will generally match.
  if s:find("%s") then
    s = s:match("(%S+)$") or s
  end

  return trim(s)
end

-- ============================================================
-- UI INITIALIZATION
-- ============================================================

function ArjUI:init()
  self:kill()
  
  -- Layout constants as percentages for DPI-independent scaling
  -- Tuned to match the decorative background frame
  self.bannerPct = 10.5     -- top margin (below New Duris banner)
  self.frameInsetXPct = 2.5 -- side margins (inside decorative frame)
  self.frameInsetBottomPct = 2.8  -- bottom margin (above bottom frame)

  local w, h = getMainWindowSize()

  -- Create background label at ROOT level (no parent) so it sits behind everything including main console
  self.bg = Geyser.Label:new({
    name = "ArjUI_Background", x = 0, y = 0, width = "100%", height = "100%"
  })
  self.bg:setStyleSheet([[background-color: #000000;]])
  self:applyBackground()

  -- Reserve ALL space with borders so main console has nowhere to render
  -- This pushes the main console out of view
  setBorderTop(h)
  setBorderBottom(0)
  setBorderLeft(0)
  setBorderRight(0)

  pcall(function() disableCommandLine("main") end)
  pcall(function() disableCommandLine() end)

  -- Main container for our UI, sits on top of background (transparent so bg shows through gaps)
  self.main = Geyser.Container:new({
    name = "ArjUI_Main", x = 0, y = 0, width = "100%", height = "100%"
  })

  -- Use percentage-based positioning for DPI independence
  local rootX = self.frameInsetXPct .. "%"
  local rootY = self.bannerPct .. "%"
  local rootW = (100 - self.frameInsetXPct * 2) .. "%"
  local rootH = (100 - self.bannerPct - self.frameInsetBottomPct) .. "%"

  self.uiRoot = Geyser.Container:new({
    name = "ArjUI_Root", x = rootX, y = rootY, width = rootW, height = rootH
  }, self.main)

  local colors = {
    -- Backgrounds: warm-tinted dark (not pure black)
    bgDark = "#0a0908", bgMid = "#0f0e0c", bgLight = "#16140f",
    -- Border hierarchy: primary (muted bronze), secondary (darker), dividers (near-neutral)
    borderPrimary = "#8c6e46",   -- muted bronze for primary panels
    borderSecondary = "#5a4b37", -- darker bronze for secondary panels  
    borderDivider = "#3c3832",   -- near-neutral warm gray for dividers
    borderDark = "#2a2520",      -- darkest for subtle edges
    accent = "#c9a227",          -- warm gold accent (unchanged)
    -- Text colors (unchanged - no font changes)
    textDim = "#8a8a8a", textMid = "#b0b0b0", textBright = "#e6e6e6",
    textGold = "#d4a855", textRed = "#c45050", textGreen = "#50c070", textBlue = "#7090c0",
  }
  self.colors = colors

  self.styles = {
    -- Primary panels (main output, map, input) - stronger bronze border, near-opaque
    panel = string.format("background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 %s,stop:1 %s); border: 2px solid %s; border-top: 2px solid %s; border-radius: 4px;", colors.bgMid, colors.bgDark, colors.borderSecondary, colors.borderPrimary),
    -- Primary content panels (main output, input) - opaque for readability
    panelPrimary = "background-color: rgba(10, 9, 8, 250); border: 2px solid #5a4b37; border-top: 2px solid #8c6e46; border-radius: 4px;",
    -- Secondary panels (side info) - softer border, slight transparency (85-90%)
    panelGlass = "background-color: rgba(10, 9, 8, 218); border: 1px solid #5a4b37; border-top: 1px solid #8c6e46; border-radius: 4px;",
    header = string.format("background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 %s,stop:1 %s); border: 1px solid %s; border-bottom: 1px solid %s; color: %s; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;", colors.bgLight, colors.bgMid, colors.borderDivider, colors.borderSecondary, colors.textDim),
    headerCombat = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #1a100c,stop:1 #0f0e0c); border: 1px solid #4a3028; border-bottom: 1px solid #5a3830; color: #c45050; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;",
    headerTarget = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #18140c,stop:1 #0f0e0c); border: 1px solid #4a4028; border-bottom: 1px solid #5a4830; color: #d4a855; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;",
    headerAffects = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #10140c,stop:1 #0f0e0c); border: 1px solid #384a28; border-bottom: 1px solid #405830; color: #50c070; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;",
    areaName = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #0c1012,stop:1 #0a0908); border: 1px solid #3c3832; border-bottom: 1px solid #5a4b37; color: #70b0c0; qproperty-alignment: 'AlignCenter'; font-weight: bold; font-size: 11px;",
    areaNameHover = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #10141a,stop:1 #0c1012); border: 1px solid #5a4b37; border-bottom: 1px solid #8c6e46; color: #90d0e0; qproperty-alignment: 'AlignCenter'; font-weight: bold; font-size: 11px;",
    exits = string.format("background-color: %s; border: 1px solid %s; color: %s; font-size: 10px;", colors.bgMid, colors.borderDivider, colors.textDim),
    pos = string.format("background-color: %s; border: 1px solid %s; color: %s; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;", colors.bgLight, colors.borderDivider, colors.textBlue),
    posAlert = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #1a0c0c,stop:1 #120808); border: 1px solid #8a4040; border-top: 1px solid #a05050; color: #ff6060; qproperty-alignment: 'AlignCenter'; font-size: 9px; font-weight: bold;",
    tankName = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #10140c,stop:1 #0a0908); border: 1px solid #384a28; border-bottom: 1px solid #405830; color: #70d070; qproperty-alignment: 'AlignLeft'; font-weight: bold; font-size: 11px; padding-left: 4px;",
    tankNameMe = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #1a0c0c,stop:0.5 #200f0f,stop:1 #1a0c0c); border: 1px solid #5a3028; border-bottom: 1px solid #6a3830; color: #ff7070; qproperty-alignment: 'AlignLeft'; font-weight: bold; font-size: 11px; padding-left: 4px;",
    targetName = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #16120a,stop:1 #0a0908); border: 1px solid #5a4b37; border-bottom: 1px solid #8c6e46; color: #e0b060; qproperty-alignment: 'AlignLeft'; font-weight: bold; font-size: 11px; padding-left: 4px;",
    targetDead = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #0c0b0a,stop:1 #0a0908); border: 1px solid #3c3832; border-bottom: 1px solid #3c3832; color: #606060; qproperty-alignment: 'AlignLeft'; font-weight: bold; font-size: 11px; padding-left: 4px;",
    roomName = string.format("background-color: %s; border: 1px solid %s; color: %s; qproperty-alignment: 'AlignCenter'; font-size: 12px; font-weight: bold;", colors.bgMid, colors.borderDivider, colors.textBlue),
    separator = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #0a0908,stop:0.5 #5a4b37,stop:1 #0a0908); border: none; border-radius: 1px;",  -- warm bronze separator with gradient
    inputBar = "background-color: qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #12100c,stop:1 #0a0908); border: 2px solid #5a4b37; border-top: 2px solid #8c6e46; border-radius: 4px; color: #d0d0d8; font-size: 12px; font-family: Consolas; padding: 3px 6px;",
    exitButton = "background-color: transparent; color: #7090c0; font-size: 10px; font-weight: bold;",
    exitButtonHover = "background-color: #1a2a3a; color: #90b0e0; font-size: 10px; font-weight: bold; border-radius: 2px;",
    exitButtonClosed = "background-color: transparent; color: #b08040; font-size: 10px; font-weight: bold; border-bottom: 1px solid #8a5a20;",
    exitButtonLocked = "background-color: transparent; color: #c05050; font-size: 10px; font-weight: bold; border-bottom: 1px solid #8a3030;",
  }

  self.gaugeStyles = {
    -- Gauge borders use warm-tinted versions of their colors
    hpFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #6b1010,stop:0.5 #8b2020,stop:1 #6b1010); border: none; border-radius: 2px;",
    hpBack = "background-color: #0a0908; border: 1px solid #3a2520; border-radius: 3px;",
    mpFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #102060,stop:0.5 #203080,stop:1 #102060); border: none; border-radius: 2px;",
    mpBack = "background-color: #0a0908; border: 1px solid #2a3040; border-radius: 3px;",
    mvFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #105010,stop:0.5 #207020,stop:1 #105010); border: none; border-radius: 2px;",
    mvBack = "background-color: #0a0908; border: 1px solid #2a3a20; border-radius: 3px;",
    xpFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #301050,stop:0.5 #502080,stop:1 #301050); border: none; border-radius: 2px;",
    xpBack = "background-color: #0a0908; border: 1px solid #302540; border-radius: 3px;",
    targetFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #5a4010,stop:0.5 #7a5520,stop:1 #5a4010); border: none; border-radius: 2px;",
    targetBack = "background-color: #0a0908; border: 1px solid #3c3020; border-radius: 3px;",
    deadFront = "background-color: #1a1816; border: none; border-radius: 2px;",
    deadBack = "background-color: #0a0908; border: 1px solid #2a2520; border-radius: 3px;",
    gaugeText = "color: #e6e6e6; font-size: 9px; font-weight: bold;",
  }

  local gap = "0.2%"  -- minimal gap between panels
  local leftW, centerW, rightW = "16.5%", "57%", "26%"  -- total ~99.5%, fills more space
  local bottomH, topH = "16.5%", "83%"

  self.topSection = makePanel(self.uiRoot, "ArjUI_TopSection", "0%", "0%", "100%", topH, self.styles.panel)
  styleSafe(self.topSection, "background-color: transparent; border: none;")
  self.bottomBar = makePanel(self.uiRoot, "ArjUI_BottomBar", "0%", "83.5%", "100%", bottomH, self.styles.panel)
  styleSafe(self.bottomBar, "background-color: transparent; border: none;")

  -- LEFT COLUMN (container for distinct panels with gaps)
  self.leftCol = makePanel(self.topSection, "ArjUI_LeftCol", 0, 0, leftW, "100%", self.styles.panel)
  styleSafe(self.leftCol, "background-color: transparent; border: none;")  -- transparent container

  -- SECTION 1: Area + Map (0% - 35%) - Larger map section
  self.mapSection = makePanel(self.leftCol, "ArjUI_MapSection", 0, 0, "100%", "35%", self.styles.panel)
  styleSafe(self.mapSection, self.styles.panelGlass)
  
  -- Globe/World Map link (top-left, above area label)
  self.globeBtn = Geyser.Label:new({ name = "ArjUI_GlobeBtn", x = "3%", y = "1%", width = "12%", height = "12%" }, self.mapSection)
  self.globeBtn:setStyleSheet([[
    QLabel { background-color: rgba(10,9,8,200); color: #7be; border: 1px solid #5a4b37; border-radius: 10px; font-size: 11px; }
    QLabel:hover { background-color: rgba(22,20,15,220); color: #9df; border-color: #8c6e46; }
  ]])
  self.globeBtn:echo("<center>🌐</center>")
  self.globeBtn:setClickCallback(function() openUrl("https://www.newduris.com/wiki/map") end)
  self.globeBtn:setOnEnter(function() self.globeBtn:setCursor("PointingHand") end)
  self.globeBtn:setOnLeave(function() self.globeBtn:setCursor("Arrow") end)
  
  -- Area label (next to globe)
  self.areaLabel = Geyser.Label:new({ name = "ArjUI_AreaLabel", x = "16%", y = "1%", width = "81%", height = "12%" }, self.mapSection)
  styleSafe(self.areaLabel, self.styles.areaName)
  labelSet(self.areaLabel, "Unknown Area")
  self.areaLabel:setClickCallback(function()
    if self.state.zoneId then openUrl("https://www.newduris.com/wiki/zones/" .. tostring(self.state.zoneId)) end
  end)
  self.areaLabel:setOnEnter(function()
    if self.state.zoneId then styleSafe(self.areaLabel, self.styles.areaNameHover); self.areaLabel:setCursor("PointingHand") end
  end)
  self.areaLabel:setOnLeave(function() styleSafe(self.areaLabel, self.styles.areaName); self.areaLabel:setCursor("Arrow") end)

  -- Map - below globe and area label (with clipping to prevent overflow)
  self.mapWrap = makePanel(self.mapSection, "ArjUI_MapWrap", "3%", "14%", "94%", "83%", self.styles.panel)
  self.mapWrap:setStyleSheet("background-color: rgba(10,9,8,240); border: 2px solid #5a4b37; border-top: 2px solid #8c6e46; border-radius: 4px; overflow: hidden;")
  self.mapper = Geyser.Mapper:new({ name = "ArjUI_Mapper", x = 2, y = 2, width = "96%", height = "96%" }, self.mapWrap)

  -- SECTION 2: Exits + Time (36% - 40%) - Split into two halves
  self.exitsSection = makePanel(self.leftCol, "ArjUI_ExitsSection", 0, "36%", "50%", "4%", self.styles.panel)
  styleSafe(self.exitsSection, self.styles.panelGlass)
  
  self.exitsWrap = Geyser.Label:new({ name = "ArjUI_ExitsWrap", x = "3%", y = "5%", width = "94%", height = "90%" }, self.exitsSection)
  styleSafe(self.exitsWrap, self.styles.exits)
  self.exitButtons = {}
  
  -- Time of day section (right half) - clickable to send 'time' command
  self.timeSection = makePanel(self.leftCol, "ArjUI_TimeSection", "51%", "36%", "49%", "4%", self.styles.panel)
  styleSafe(self.timeSection, self.styles.panelGlass)
  
  self.timeLabel = Geyser.Label:new({ name = "ArjUI_TimeLabel", x = "5%", y = "5%", width = "90%", height = "90%" }, self.timeSection)
  self.timeLabel:setStyleSheet("background-color: transparent; color: #a0a0b0; font-size: 10px; qproperty-alignment: 'AlignCenter';")
  self.timeLabel:echo("☀ Day")
  self.timeLabel:setClickCallback(function() send("time") end)

  -- SECTION 3: Mobs (41% - 69%)
  self.mobsSection = makePanel(self.leftCol, "ArjUI_MobsSection", 0, "41%", "100%", "28%", self.styles.panel)
  styleSafe(self.mobsSection, self.styles.panelGlass)
  
  self.mobsHeader = Geyser.Label:new({ name = "ArjUI_MobsHeader", x = "3%", y = "3%", width = "94%", height = "14%" }, self.mobsSection)
  styleSafe(self.mobsHeader, self.styles.headerCombat)
  labelSet(self.mobsHeader, "⚔ MOBS")
  self.mobsBox = makeConsole(self.mobsSection, "ArjUI_MobsBox", "3%", "18%", "94%", "79%", 9, 30)

  -- SECTION 4: Items (70% - 100%) - extends to match output window bottom
  self.itemsSection = makePanel(self.leftCol, "ArjUI_ItemsSection", 0, "70%", "100%", "30%", self.styles.panel)
  styleSafe(self.itemsSection, self.styles.panelGlass)
  
  self.objsHeader = Geyser.Label:new({ name = "ArjUI_ObjsHeader", x = "3%", y = "3%", width = "94%", height = "13%" }, self.itemsSection)
  styleSafe(self.objsHeader, self.styles.headerTarget)
  labelSet(self.objsHeader, "◆ ITEMS")
  self.objsBox = makeConsole(self.itemsSection, "ArjUI_ObjsBox", "3%", "17%", "94%", "80%", 9, 30)

  -- CENTER COLUMN (with gaps on sides) - primary panel, near-opaque for readability
  self.centerCol = makePanel(self.topSection, "ArjUI_CenterCol", "16.7%", 0, centerW, "100%", self.styles.panel)
  styleSafe(self.centerCol, self.styles.panelPrimary)

  self.xpGauge = Geyser.Gauge:new({ name = "ArjUI_TNLTop", x = "0.5%", y = "0.5%", width = "99%", height = "2.2%" }, self.centerCol)
  self.xpGauge.front:setStyleSheet(self.gaugeStyles.xpFront)
  self.xpGauge.back:setStyleSheet(self.gaugeStyles.xpBack)
  self.xpGauge.text:setStyleSheet(self.gaugeStyles.gaugeText)

  self.roomLabel = Geyser.Label:new({ name = "ArjUI_RoomLabel", x = "0.5%", y = "3.0%", width = "99%", height = "3.2%" }, self.centerCol)
  styleSafe(self.roomLabel, self.styles.roomName)

  self.console = makeConsole(self.centerCol, "ArjUI_Console", "0.5%", "6.5%", "99%", "88%", 10, 400)

  self.inputBar = Geyser.CommandLine:new({ name = "ArjUI_Input", x = "0.5%", y = "95%", width = "99%", height = "4.5%" }, self.centerCol)
  self.inputBar:setStyleSheet(self.styles.inputBar)
  self.inputBar:setFontSize(12)

  -- RIGHT COLUMN (container for distinct panels with gaps) - extends to target bar bottom
  self.rightCol = makePanel(self.uiRoot, "ArjUI_RightCol", "73.9%", "0%", rightW, "100%", self.styles.panel)
  styleSafe(self.rightCol, "background-color: transparent; border: none;")  -- transparent container

  -- SECTION 1: Tabbed Pane (0% - 45%) - Info tabs fill top space
  self.tabSection = makePanel(self.rightCol, "ArjUI_TabSection", 0, 0, "100%", "45%", self.styles.panel)
  styleSafe(self.tabSection, self.styles.panelGlass)

  -- TABBED PANE (Group/Stats/Inv/Eq/Skills)
  self.tabButtons = {}
  self.tabPanels = {}
  self.activeTab = "group"
  
  local tabNames = { "group", "stats", "inv", "eq", "who" }
  local tabLabels = { "GROUP", "STATS", "INV", "EQ", "WHO" }
  local tabW = 19  -- percentage width per tab
  
  for i, tabName in ipairs(tabNames) do
    local xPos = string.format("%d%%", 2 + (i-1) * tabW)
    local btn = Geyser.Label:new({ name = "ArjUI_Tab_" .. tabName, x = xPos, y = "2%", width = (tabW - 1) .. "%", height = "5%" }, self.tabSection)
    btn:echo("<center>" .. tabLabels[i] .. "</center>")
    self.tabButtons[tabName] = btn
    
    btn:setClickCallback(function() self:switchTab(tabName) end)
    btn:setOnEnter(function() btn:setCursor("PointingHand") end)
    btn:setOnLeave(function() btn:setCursor("Arrow") end)
  end
  
  -- Tab content area
  self.tabContent = Geyser.Container:new({ name = "ArjUI_TabContent", x = "3%", y = "8%", width = "94%", height = "90%" }, self.tabSection)
  
  -- GROUP panel (default) - Container for dynamic gauge widgets
  self.groupContainer = Geyser.Container:new({ name = "ArjUI_GroupContainer", x = 0, y = 0, width = "100%", height = "100%" }, self.tabContent)
  self.tabPanels.group = self.groupContainer
  self.groupWidgets = {}  -- Store dynamically created group member widgets
  
  -- STATS panel
  self.statsBox = makeConsole(self.tabContent, "ArjUI_StatsBox", 0, 0, "100%", "100%", 9, 40)
  self.statsBox:hide()
  self.tabPanels.stats = self.statsBox
  
  -- INVENTORY panel
  self.invBox = makeConsole(self.tabContent, "ArjUI_InvBox", 0, 0, "100%", "100%", 9, 40)
  self.invBox:hide()
  self.tabPanels.inv = self.invBox
  
  -- EQ panel (equipment)
  self.eqBox = makeConsole(self.tabContent, "ArjUI_EqBox", 0, 0, "100%", "100%", 9, 50)
  self.eqBox:hide()
  self.tabPanels.eq = self.eqBox
  
  -- WHO panel
  self.whoBox = makeConsole(self.tabContent, "ArjUI_WhoBox", 0, 0, "100%", "100%", 9, 60)
  self.whoBox:hide()
  self.tabPanels.who = self.whoBox
  
  self:updateTabStyles()

  -- SECTION 2: Players (46% - 72%) - Players section above chat (expanded to fill gap)
  self.playersSection = makePanel(self.rightCol, "ArjUI_PlayersSection", 0, "46%", "100%", "26%", self.styles.panel)
  styleSafe(self.playersSection, self.styles.panelGlass)

  self.enemyHeader = Geyser.Label:new({ name = "ArjUI_EnemyHeader", x = "3%", y = "3%", width = "94%", height = "14%" }, self.playersSection)
  styleSafe(self.enemyHeader, self.styles.headerCombat)
  labelSet(self.enemyHeader, "⚔ PLAYERS")
  self.enemyBox = makeConsole(self.playersSection, "ArjUI_EnemyBox", "3%", "18%", "94%", "79%", 9, 60)

  -- SECTION 3: Chat (73% - 100%) - Chat at bottom, sits just above credit box
  self.chatSection = makePanel(self.rightCol, "ArjUI_ChatSection", 0, "73%", "100%", "27%", self.styles.panel)
  styleSafe(self.chatSection, self.styles.panelGlass)

  -- Chat tabs
  self.chatTabs = {}
  self.chatPanels = {}
  self.activeChatTab = "all"
  
  local chatTabNames = { "all", "tells", "nchat", "room", "guild", "group" }
  local chatTabLabels = { "ALL", "TELLS", "NCHAT", "ROOM", "GUILD", "GROUP" }
  local chatTabW = 16  -- percentage width per tab
  
  for i, tabName in ipairs(chatTabNames) do
    local xPos = string.format("%d%%", 2 + (i-1) * chatTabW)
    local btn = Geyser.Label:new({ name = "ArjUI_ChatTab_" .. tabName, x = xPos, y = "2%", width = (chatTabW - 1) .. "%", height = "8%" }, self.chatSection)
    btn:echo("<center>" .. chatTabLabels[i] .. "</center>")
    self.chatTabs[tabName] = btn
    
    btn:setClickCallback(function() self:switchChatTab(tabName) end)
    btn:setOnEnter(function() btn:setCursor("PointingHand") end)
    btn:setOnLeave(function() btn:setCursor("Arrow") end)
  end
  
  -- Chat content area
  self.chatContent = Geyser.Container:new({ name = "ArjUI_ChatContent", x = "3%", y = "12%", width = "94%", height = "86%" }, self.chatSection)
  
  -- ALL chat panel (default)
  self.chatBox = makeConsole(self.chatContent, "ArjUI_ChatBox", 0, 0, "100%", "100%", 9, 60)
  self.chatPanels.all = self.chatBox
  
  -- TELLS panel
  self.tellsBox = makeConsole(self.chatContent, "ArjUI_TellsBox", 0, 0, "100%", "100%", 9, 60)
  self.tellsBox:hide()
  self.chatPanels.tells = self.tellsBox
  
  -- NCHAT panel
  self.nchatBox = makeConsole(self.chatContent, "ArjUI_NchatBox", 0, 0, "100%", "100%", 9, 60)
  self.nchatBox:hide()
  self.chatPanels.nchat = self.nchatBox
  
  -- ROOM panel (say/yell)
  self.roomBox = makeConsole(self.chatContent, "ArjUI_RoomBox", 0, 0, "100%", "100%", 9, 60)
  self.roomBox:hide()
  self.chatPanels.room = self.roomBox
  
  -- GUILD panel
  self.guildBox = makeConsole(self.chatContent, "ArjUI_GuildBox", 0, 0, "100%", "100%", 9, 60)
  self.guildBox:hide()
  self.chatPanels.guild = self.guildBox
  
  -- GROUP panel
  self.groupChatBox = makeConsole(self.chatContent, "ArjUI_GroupChatBox", 0, 0, "100%", "100%", 9, 60)
  self.groupChatBox:hide()
  self.chatPanels.group = self.groupChatBox
  
  self:updateChatTabStyles()

  -- Credit box (directly under chat panel, same width as right column)
  local creditX = "73.9%"  -- same as rightCol
  local creditW = rightW   -- same width as rightCol (26%)
  local creditY = (100 - self.frameInsetBottomPct + 0.3) .. "%"
  self.creditBox = Geyser.Label:new({
    name = "ArjUI_CreditBox",
    x = creditX, y = creditY, width = creditW, height = 20
  }, self.main)
  self.creditBox:setStyleSheet([[
    background-color: rgba(15, 14, 12, 0.85);
    border: 1px solid #3c3428;
    border-radius: 3px;
    color: #8a7a5a;
    font-size: 9px;
    qproperty-alignment: 'AlignRight | AlignVCenter';
    padding-right: 8px;
  ]])
  self.creditBox:echo("Arjinius Client v1.0")
  
  -- Hover tooltip (appears above credit box)
  local tooltipY = (100 - self.frameInsetBottomPct - 3.2) .. "%"
  self.creditTooltip = Geyser.Label:new({
    name = "ArjUI_CreditTooltip",
    x = creditX, y = tooltipY, width = creditW, height = 36
  }, self.main)
  self.creditTooltip:setStyleSheet([[
    background-color: rgba(15, 14, 12, 0.95);
    border: 1px solid #5a4b37;
    border-radius: 3px;
    color: #c0b090;
    font-size: 8px;
    padding: 4px;
  ]])
  self.creditTooltip:echo("<center>A Mudlet client for New Duris\nCreated by Arjin / Arjinius</center>")
  self.creditTooltip:hide()
  
  self.creditBox:setOnEnter(function()
    self.creditBox:setStyleSheet([[
      background-color: rgba(20, 18, 14, 0.95);
      border: 1px solid #5a4b37;
      border-radius: 3px;
      color: #d4a855;
      font-size: 9px;
      qproperty-alignment: 'AlignRight | AlignVCenter';
      padding-right: 8px;
    ]])
    self.creditTooltip:show()
    self.creditTooltip:raise()
  end)
  self.creditBox:setOnLeave(function()
    self.creditBox:setStyleSheet([[
      background-color: rgba(15, 14, 12, 0.85);
      border: 1px solid #3c3428;
      border-radius: 3px;
      color: #8a7a5a;
      font-size: 9px;
      qproperty-alignment: 'AlignRight | AlignVCenter';
      padding-right: 8px;
    ]])
    self.creditTooltip:hide()
  end)

  -- BOTTOM BAR (aligned with columns above)
  -- Vitals: under left column (0-16.5%)
  -- Tank: first half under output (16.7%-45.2%)
  -- Target: second half under output (45.4%-73.7%)
  self.myVitalsWrap = makePanel(self.bottomBar, "ArjUI_MyVitalsWrap", "0%", "3%", "16.5%", "94%", self.styles.panel)
  styleSafe(self.myVitalsWrap, self.styles.panelGlass)

  self.hpGauge = Geyser.Gauge:new({ name="ArjUI_HP", x="4%", y="4%", width="92%", height="19%" }, self.myVitalsWrap)
  self.hpGauge.front:setStyleSheet(self.gaugeStyles.hpFront)
  self.hpGauge.back:setStyleSheet(self.gaugeStyles.hpBack)
  self.hpGauge.text:setStyleSheet(self.gaugeStyles.gaugeText)

  self.mpGauge = Geyser.Gauge:new({ name="ArjUI_MP", x="4%", y="26%", width="92%", height="19%" }, self.myVitalsWrap)
  self.mpGauge.front:setStyleSheet(self.gaugeStyles.mpFront)
  self.mpGauge.back:setStyleSheet(self.gaugeStyles.mpBack)
  self.mpGauge.text:setStyleSheet(self.gaugeStyles.gaugeText)

  self.mvGauge = Geyser.Gauge:new({ name="ArjUI_MV", x="4%", y="48%", width="92%", height="19%" }, self.myVitalsWrap)
  self.mvGauge.front:setStyleSheet(self.gaugeStyles.mvFront)
  self.mvGauge.back:setStyleSheet(self.gaugeStyles.mvBack)
  self.mvGauge.text:setStyleSheet(self.gaugeStyles.gaugeText)

  self.posLabel = Geyser.Label:new({ name="ArjUI_PosLabel", x="4%", y="70%", width="92%", height="26%" }, self.myVitalsWrap)
  styleSafe(self.posLabel, self.styles.pos)
  labelSet(self.posLabel, "STANDING")

  -- TANK (with gap from vitals) - Name as header, HP gauge, buffs below
  -- Tank: 16.7% to 45.2% (first half under output window)
  self.tankWrap = makePanel(self.bottomBar, "ArjUI_TankWrap", "16.7%", "3%", "28.3%", "94%", self.styles.panel)
  styleSafe(self.tankWrap, self.styles.panelGlass)
  
  -- Tank name as header (replaces "TANK" label)
  self.tankNameLabel = Geyser.Label:new({ name="ArjUI_TankName", x="3%", y="2%", width="80%", height="14%" }, self.tankWrap)
  styleSafe(self.tankNameLabel, self.styles.tankName)
  labelSet(self.tankNameLabel, "---")
  
  self.tankPosLabel = Geyser.Label:new({ name="ArjUI_TankPos", x="85%", y="2%", width="12%", height="14%" }, self.tankWrap)
  styleSafe(self.tankPosLabel, self.styles.pos)
  
  self.tankHpGauge = Geyser.Gauge:new({ name="ArjUI_TankHP", x="3%", y="18%", width="94%", height="18%" }, self.tankWrap)
  self.tankHpGauge.front:setStyleSheet(self.gaugeStyles.hpFront)
  self.tankHpGauge.back:setStyleSheet(self.gaugeStyles.hpBack)
  self.tankHpGauge.text:setStyleSheet("color: #d0d0d0; font-size: 10px; font-weight: bold;")
  
  -- Buffs section under tank
  self.buffsHeader = Geyser.Label:new({ name="ArjUI_BuffsHeader", x="3%", y="38%", width="94%", height="12%" }, self.tankWrap)
  styleSafe(self.buffsHeader, self.styles.headerAffects)
  labelSet(self.buffsHeader, "✦ BUFFS")
  self.buffsBox = makeConsole(self.tankWrap, "ArjUI_BuffsBox", "3%", "51%", "94%", "46%", 8, 40)

  self.separator = Geyser.Label:new({ name = "ArjUI_Separator", x = "45.2%", y = "5%", width = "0.3%", height = "90%" }, self.bottomBar)
  styleSafe(self.separator, self.styles.separator)

  -- TARGET (with gap from tank) - Name as header, HP gauge, debuffs below
  -- Target: 45.5% to 73.7% (aligned with output window right edge)
  self.targetWrap = makePanel(self.bottomBar, "ArjUI_TargetWrap", "45.5%", "3%", "28.2%", "94%", self.styles.panel)
  styleSafe(self.targetWrap, self.styles.panelGlass)
  
  -- Target position label on left (mirrors tank layout)
  self.targetPosLabel = Geyser.Label:new({ name="ArjUI_TargetPos", x="3%", y="2%", width="12%", height="14%" }, self.targetWrap)
  styleSafe(self.targetPosLabel, self.styles.pos)
  
  -- Target name as header (to the right of position)
  self.targetNameLabel = Geyser.Label:new({ name="ArjUI_TargetName", x="17%", y="2%", width="80%", height="14%" }, self.targetWrap)
  styleSafe(self.targetNameLabel, self.styles.targetName)
  labelSet(self.targetNameLabel, "No Target")
  
  self.targetHpGauge = Geyser.Gauge:new({ name="ArjUI_TargetHP", x="3%", y="18%", width="94%", height="18%" }, self.targetWrap)
  self.targetHpGauge.front:setStyleSheet(self.gaugeStyles.targetFront)
  self.targetHpGauge.back:setStyleSheet(self.gaugeStyles.targetBack)
  self.targetHpGauge.text:setStyleSheet("color: #d0d0d0; font-size: 10px; font-weight: bold;")
  
  -- Debuffs section under target
  self.debuffsHeader = Geyser.Label:new({ name="ArjUI_DebuffsHeader", x="3%", y="38%", width="94%", height="12%" }, self.targetWrap)
  styleSafe(self.debuffsHeader, self.styles.headerCombat)
  labelSet(self.debuffsHeader, "☠ DEBUFFS")
  self.debuffsBox = makeConsole(self.targetWrap, "ArjUI_DebuffsBox", "3%", "51%", "94%", "46%", 8, 40)

  -- STATE
  self.state = {
    hp = 1, hpmax = 1, mana = 1, manamax = 1, move = 1, movemax = 1,
    tnl = 0, tnlBaseline = nil, position = "standing",
    area = "Unknown", room = "Unknown", roomId = nil, zoneId = nil,
    exits = {}, exitsRaw = {}, npcs = {}, items = {}, players = {},
    target = nil, targetHpPct = 100, targetCond = nil, targetPos = nil,
    tank = nil, tankHp = nil, tankMaxHp = nil, tankCond = nil, tankPos = nil, iAmTank = false,
    group = {}, groupSize = 0, groupMax = 0, affects = {},
    doors = {},
    coins = { platinum = 0, gold = 0, silver = 0, copper = 0 },
    usesMana = true, fighting = nil,
    charLevel = nil, charClass = nil, charRace = nil, charGuild = nil, charTitle = nil,
    quest = nil,
    timeOfDay = "day",  -- day, night, dawn, dusk
  }
  
  -- Initialize login flag (reset on each init so reconnects work)
  self.initialDataRequested = false

  local h
  h = registerAnonymousEventHandler("sysWindowResizeEvent", function() self:layout() end)
  table.insert(self.eventHandlers, h)

  h = registerAnonymousEventHandler("sysConnectionEvent", function()
    self:applyBackground()
    tempTimer(0.2, function() if self and self.applyBackground then self:applyBackground() end end)
  end)
  table.insert(self.eventHandlers, h)

  h = registerAnonymousEventHandler("sysAppStyleSheetChange", function()
    self:applyBackground()
    tempTimer(0.2, function() if self and self.applyBackground then self:applyBackground() end end)
  end)
  table.insert(self.eventHandlers, h)

  self:layout()

  self:loadCustomCommands()
  self:registerGMCPHandlers()
  self:renderAll()
  
  -- If GMCP data already exists (reconnecting to existing session), render again after short delay
  tempTimer(1, function()
    if ArjUI and gmcp and gmcp.Char and gmcp.Char.Vitals then
      ArjUI:renderAll()
    end
  end)
  
  -- Output launch message to the UI console
  if self.console then
    self.console:cecho("\n<gold>══ Arjinius Client v" .. ArjUI.VERSION .. " ══<reset>\n")
    self.console:cecho("<dim_gray>  A Mudlet client for New Duris<reset>\n")
    self.console:cecho("<dim_gray>  Created by Arjin / Arjinius<reset>\n")
    self.console:cecho("<gold>═══════════════════════════════<reset>\n\n")
  end
end

function ArjUI:layout()
  if not self.uiRoot then return end
  local w, h = getMainWindowSize()
  setBorderTop(h)
  
  -- Calculate pixel values from percentages for resize
  local banner = h * (self.bannerPct or 5.5) / 100
  local insetX = w * (self.frameInsetXPct or 3.8) / 100
  local insetBottom = h * (self.frameInsetBottomPct or 3.5) / 100
  
  if self.main and w and h then
    self.main:move(0, 0)
    self.main:resize(w, h)
  end
  if self.bg and w and h then
    self.bg:move(0, 0)
    self.bg:resize(w, h)
  end
  local rootW = math.max(0, w - (insetX * 2))
  local rootH = math.max(0, h - banner - insetBottom)
  self.uiRoot:move(insetX, banner)
  self.uiRoot:resize(rootW, rootH)
  
  -- Reposition credit box and tooltip on resize (aligned under chat/right column)
  if self.creditBox then
    local creditX = insetX + rootW * 0.739  -- 73.9% of rootW from left edge
    local creditW = rootW * 0.26            -- 26% width (same as rightCol)
    local creditY = h - insetBottom + 3
    self.creditBox:move(creditX, creditY)
    self.creditBox:resize(creditW, 20)
    if self.creditTooltip then
      self.creditTooltip:move(creditX, creditY - 38)
      self.creditTooltip:resize(creditW, 36)
    end
  end
end

-- ============================================================
-- CONTEXT MENUS
-- ============================================================

function ArjUI:showContextMenu(items, x, y)
  -- Hide any existing menu
  if self.currentMenu then self.currentMenu:hide() end

  -- If caller didn't pass coordinates, use the actual mouse position
  if not x or not y then
    x, y = getMousePosition()
  end

  -- Clamp so it never spawns off-screen
  local winW, winH = getMainWindowSize()
  local menuW = 110
  local menuH = (#items * 22 + 26)  -- Extra space for close button

  x = math.max(0, math.min(x, winW - menuW - 2))
  y = math.max(0, math.min(y, winH - menuH - 2))

  local menu = Geyser.Label:new({
    name = "ArjUI_Menu_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000,9999)),
    x = x, y = y, width = menuW, height = menuH,
  }, self.main)
  menu:setStyleSheet("background-color: #0f0e0c; border: 1px solid #5a4b37; border-radius: 3px;")
  menu:raise()
  
  -- Close button at top
  local closeBtn = Geyser.Label:new({
    name = menu.name .. "_close",
    x = menuW - 20, y = 2, width = 18, height = 18,
  }, menu)
  closeBtn:setStyleSheet("background-color: #1a1610; color: #c05050; font-size: 10px; font-weight: bold; border: 1px solid #5a4b37; border-radius: 2px;")
  closeBtn:echo("<center>X</center>")
  closeBtn:setClickCallback(function()
    menu:hide()
    self.currentMenu = nil
  end)
  closeBtn:setOnEnter(function()
    closeBtn:setStyleSheet("background-color: #c05050; color: #ffffff; font-size: 10px; font-weight: bold; border: 1px solid #5a4b37; border-radius: 2px;")
  end)
  closeBtn:setOnLeave(function()
    closeBtn:setStyleSheet("background-color: #1a1610; color: #c05050; font-size: 10px; font-weight: bold; border: 1px solid #5a4b37; border-radius: 2px;")
  end)

  for i, item in ipairs(items) do
    local btn = Geyser.Label:new({
      name = menu.name .. "_" .. i, x = 2, y = (i-1) * 22 + 22, width = 106, height = 20,
    }, menu)
    btn:setStyleSheet("background-color: transparent; color: #c0b8a0; font-size: 10px; padding-left: 5px;")
    btn:echo(item.text)

    btn:setClickCallback(function()
      menu:hide()
      self.currentMenu = nil
      -- Check for special commands
      if item.cmd and item.cmd:match("^arjui_add_") then
        local category = item.cmd:gsub("^arjui_add_", "")
        self:showAddCommandPopup(category)
      elseif item.cmd and item.cmd:match("^arjui_spell_") then
        local category = item.cmd:gsub("^arjui_spell_", "")
        self:showAddSpellPopup(category)
      elseif item.cmd and item.cmd:match("^arjui_remove_") then
        local category = item.cmd:gsub("^arjui_remove_", "")
        self:showRemoveCommandMenu(category)
      elseif item.cmd and item.cmd:match("^arjui_del_") then
        -- Handle actual deletion: arjui_del_category_index
        local parts = item.cmd:match("^arjui_del_(.+)_(%d+)$")
        if parts then
          local cat, idx = item.cmd:match("^arjui_del_(.+)_(%d+)$")
          idx = tonumber(idx)
          if self.customCommands[cat] and idx and self.customCommands[cat][idx] then
            local removed = table.remove(self.customCommands[cat], idx)
            self:saveCustomCommands()
            cecho(string.format("<green>[ArjUI]<reset> Removed '%s'.\n", removed.text))
          end
        end
      elseif item.cmd and item.cmd ~= "" then
        send(item.cmd)
      end
    end)

    btn:setOnEnter(function()
      btn:setStyleSheet("background-color: #1a1610; color: #e0d8c0; font-size: 10px; padding-left: 5px;")
    end)

    btn:setOnLeave(function()
      btn:setStyleSheet("background-color: transparent; color: #c0b8a0; font-size: 10px; padding-left: 5px;")
    end)
  end

  -- Auto-hide after 10 seconds so it can't get stuck
  tempTimer(10, function() 
    if menu then pcall(function() menu:hide() end) end
  end)

  self.currentMenu = menu
end

-- ============================================================
-- CUSTOM COMMANDS - LOAD/SAVE
-- ============================================================

function ArjUI:loadCustomCommands()
  local path = getMudletHomeDir() .. "/arjui_custom_commands.json"
  local file = io.open(path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(yajl.to_value, content)
    if ok and data then
      self.customCommands = data
      cecho("<dim_gray>[ArjUI] Custom commands loaded.\n")
    end
  end
end

function ArjUI:saveCustomCommands()
  local path = getMudletHomeDir() .. "/arjui_custom_commands.json"
  local ok, json = pcall(yajl.to_string, self.customCommands)
  if ok then
    local file = io.open(path, "w")
    if file then
      file:write(json)
      file:close()
      cecho("<dim_gray>[ArjUI] Custom commands saved.\n")
    end
  end
end

-- ============================================================
-- CUSTOM COMMANDS - ADD POPUP
-- ============================================================

function ArjUI:showAddCommandPopup(category)
  -- Clean up any existing popup
  if self.addCmdPopup then
    self.addCmdPopup:hide()
    self.addCmdPopup = nil
  end
  
  local w, h = getMainWindowSize()
  local popupW, popupH = 280, 140
  local popupX = (w - popupW) / 2
  local popupY = (h - popupH) / 2
  
  -- Main popup container
  local popup = Geyser.Label:new({
    name = "ArjUI_AddCmdPopup_" .. os.time(),
    x = popupX, y = popupY, width = popupW, height = popupH
  }, self.main)
  popup:setStyleSheet("background-color: #0f0e0c; border: 2px solid #8c6e46; border-radius: 4px;")
  popup:raise()
  
  -- Title
  local title = Geyser.Label:new({
    name = popup.name .. "_title",
    x = 0, y = 5, width = popupW, height = 20
  }, popup)
  title:setStyleSheet("background-color: transparent; color: #d4a855; font-size: 11px; font-weight: bold;")
  title:echo("<center>Add " .. category:upper() .. " Command</center>")
  
  -- Label field
  local labelLbl = Geyser.Label:new({
    name = popup.name .. "_labelLbl",
    x = 10, y = 30, width = 50, height = 22
  }, popup)
  labelLbl:setStyleSheet("background-color: transparent; color: #a09080; font-size: 10px;")
  labelLbl:echo("Label:")
  
  local labelInput = Geyser.CommandLine:new({
    name = popup.name .. "_labelInput",
    x = 65, y = 30, width = popupW - 80, height = 22
  }, popup)
  labelInput:setStyleSheet("background-color: #16140f; border: 1px solid #5a4b37; color: #d0d0d8; font-size: 10px;")
  
  -- Command field
  local cmdLbl = Geyser.Label:new({
    name = popup.name .. "_cmdLbl",
    x = 10, y = 58, width = 50, height = 22
  }, popup)
  cmdLbl:setStyleSheet("background-color: transparent; color: #a09080; font-size: 10px;")
  cmdLbl:echo("Command:")
  
  local cmdInput = Geyser.CommandLine:new({
    name = popup.name .. "_cmdInput",
    x = 65, y = 58, width = popupW - 80, height = 22
  }, popup)
  cmdInput:setStyleSheet("background-color: #16140f; border: 1px solid #5a4b37; color: #d0d0d8; font-size: 10px;")
  
  -- Help text
  local helpLbl = Geyser.Label:new({
    name = popup.name .. "_help",
    x = 10, y = 82, width = popupW - 20, height = 16
  }, popup)
  helpLbl:setStyleSheet("background-color: transparent; color: #606060; font-size: 9px;")
  helpLbl:echo("Target name auto-added to command")
  
  -- Save button
  local saveBtn = Geyser.Label:new({
    name = popup.name .. "_save",
    x = 10, y = 102, width = (popupW - 30) / 2, height = 28
  }, popup)
  saveBtn:setStyleSheet("background-color: #1a1610; border: 1px solid #5a4b37; color: #d4a855; font-size: 10px; font-weight: bold; border-radius: 3px;")
  saveBtn:echo("<center>Save</center>")
  saveBtn:setClickCallback(function()
    local label = labelInput:getText()
    local cmd = cmdInput:getText()
    if label and label ~= "" and cmd and cmd ~= "" then
      self.customCommands[category] = self.customCommands[category] or {}
      table.insert(self.customCommands[category], { text = label, cmd = cmd })
      self:saveCustomCommands()
      cecho(string.format("<green>[ArjUI]<reset> Added '%s' to %s menu.\n", label, category))
      popup:hide()
      self.addCmdPopup = nil
    end
  end)
  
  -- Cancel button
  local cancelBtn = Geyser.Label:new({
    name = popup.name .. "_cancel",
    x = (popupW - 30) / 2 + 20, y = 102, width = (popupW - 30) / 2, height = 28
  }, popup)
  cancelBtn:setStyleSheet("background-color: #1a1610; border: 1px solid #5a4b37; color: #a09080; font-size: 10px; font-weight: bold; border-radius: 3px;")
  cancelBtn:echo("<center>Cancel</center>")
  cancelBtn:setClickCallback(function()
    popup:hide()
    self.addCmdPopup = nil
  end)
  
  self.addCmdPopup = popup
  labelInput:setFocus()
end

-- ============================================================
-- CUSTOM COMMANDS - ADD SPELL POPUP
-- ============================================================

function ArjUI:showAddSpellPopup(category)
  -- Clean up any existing popup
  if self.addCmdPopup then
    self.addCmdPopup:hide()
    self.addCmdPopup = nil
  end
  
  local w, h = getMainWindowSize()
  local popupW, popupH = 280, 140
  local popupX = (w - popupW) / 2
  local popupY = (h - popupH) / 2
  
  -- Main popup container
  local popup = Geyser.Label:new({
    name = "ArjUI_AddSpellPopup_" .. os.time(),
    x = popupX, y = popupY, width = popupW, height = popupH
  }, self.main)
  popup:setStyleSheet("background-color: #0f0e0c; border: 2px solid #8c6e46; border-radius: 4px;")
  popup:raise()
  
  -- Title
  local title = Geyser.Label:new({
    name = popup.name .. "_title",
    x = 0, y = 5, width = popupW, height = 20
  }, popup)
  title:setStyleSheet("background-color: transparent; color: #d4a855; font-size: 11px; font-weight: bold;")
  title:echo("<center>Add Spell to " .. category:upper() .. "</center>")
  
  -- Label field
  local labelLbl = Geyser.Label:new({
    name = popup.name .. "_labelLbl",
    x = 10, y = 30, width = 50, height = 22
  }, popup)
  labelLbl:setStyleSheet("background-color: transparent; color: #a09080; font-size: 10px;")
  labelLbl:echo("Label:")
  
  local labelInput = Geyser.CommandLine:new({
    name = popup.name .. "_labelInput",
    x = 65, y = 30, width = popupW - 80, height = 22
  }, popup)
  labelInput:setStyleSheet("background-color: #16140f; border: 1px solid #5a4b37; color: #d0d0d8; font-size: 10px;")
  
  -- Spell name field
  local spellLbl = Geyser.Label:new({
    name = popup.name .. "_spellLbl",
    x = 10, y = 58, width = 50, height = 22
  }, popup)
  spellLbl:setStyleSheet("background-color: transparent; color: #a09080; font-size: 10px;")
  spellLbl:echo("Spell:")
  
  local spellInput = Geyser.CommandLine:new({
    name = popup.name .. "_spellInput",
    x = 65, y = 58, width = popupW - 80, height = 22
  }, popup)
  spellInput:setStyleSheet("background-color: #16140f; border: 1px solid #5a4b37; color: #d0d0d8; font-size: 10px;")
  
  -- Help text
  local helpLbl = Geyser.Label:new({
    name = popup.name .. "_help",
    x = 10, y = 82, width = popupW - 20, height = 16
  }, popup)
  helpLbl:setStyleSheet("background-color: transparent; color: #606060; font-size: 9px;")
  helpLbl:echo("Sends: cast 'spell name' target")
  
  -- Save button
  local saveBtn = Geyser.Label:new({
    name = popup.name .. "_save",
    x = 10, y = 102, width = (popupW - 30) / 2, height = 28
  }, popup)
  saveBtn:setStyleSheet("background-color: #1a1610; border: 1px solid #5a4b37; color: #d4a855; font-size: 10px; font-weight: bold; border-radius: 3px;")
  saveBtn:echo("<center>Save</center>")
  saveBtn:setClickCallback(function()
    local label = labelInput:getText()
    local spell = spellInput:getText()
    if label and label ~= "" and spell and spell ~= "" then
      self.customCommands[category] = self.customCommands[category] or {}
      -- Store with spell flag so we know to format it specially
      table.insert(self.customCommands[category], { text = label, cmd = spell, isSpell = true })
      self:saveCustomCommands()
      cecho(string.format("<green>[ArjUI]<reset> Added spell '%s' to %s menu.\n", label, category))
      popup:hide()
      self.addCmdPopup = nil
    end
  end)
  
  -- Cancel button
  local cancelBtn = Geyser.Label:new({
    name = popup.name .. "_cancel",
    x = (popupW - 30) / 2 + 20, y = 102, width = (popupW - 30) / 2, height = 28
  }, popup)
  cancelBtn:setStyleSheet("background-color: #1a1610; border: 1px solid #5a4b37; color: #a09080; font-size: 10px; font-weight: bold; border-radius: 3px;")
  cancelBtn:echo("<center>Cancel</center>")
  cancelBtn:setClickCallback(function()
    popup:hide()
    self.addCmdPopup = nil
  end)
  
  self.addCmdPopup = popup
  labelInput:setFocus()
end

-- ============================================================
-- CUSTOM COMMANDS - REMOVE FROM MENU
-- ============================================================

function ArjUI:showRemoveCommandMenu(category)
  local commands = self.customCommands[category] or {}
  if #commands == 0 then
    cecho("<yellow>[ArjUI]<reset> No custom commands to remove.\n")
    return
  end
  
  local items = {}
  for i, cmd in ipairs(commands) do
    table.insert(items, {
      text = "✕ " .. cmd.text,
      cmd = "arjui_del_" .. category .. "_" .. i
    })
  end
  table.insert(items, { text = "───────────", cmd = "" })
  table.insert(items, { text = "Cancel", cmd = "" })
  
  self:showContextMenu(items)
end

-- ============================================================
-- CONTEXT MENU WITH CUSTOM COMMANDS
-- ============================================================

function ArjUI:getContextMenuItems(category, target)
  local items = {}
  
  -- Default commands based on category
  if category == "players" then
    items = {
      { text = "Look", cmd = "look " .. target },
      { text = "Assist", cmd = "assist " .. target },
      { text = "Follow", cmd = "follow " .. target },
      { text = "Rescue", cmd = "rescue " .. target },
      { text = "Consent", cmd = "consent " .. target },
      { text = "Group", cmd = "group " .. target },
    }
  elseif category == "mobs" then
    items = {
      { text = "Look", cmd = "look " .. target },
      { text = "Consider", cmd = "consider " .. target },
      { text = "Kill", cmd = "kill " .. target },
    }
  elseif category == "objects" then
    items = {
      { text = "Examine", cmd = "examine " .. target },
      { text = "Get", cmd = "get " .. target },
    }
  elseif category == "inventory" then
    items = {
      { text = "Examine", cmd = "examine " .. target },
      { text = "Drop", cmd = "drop " .. target },
      { text = "Wear", cmd = "wear " .. target },
      { text = "Wield", cmd = "wield " .. target },
      { text = "Hold", cmd = "hold " .. target },
    }
  elseif category == "equipment" then
    items = {
      { text = "Examine", cmd = "examine " .. target },
      { text = "Remove", cmd = "remove " .. target },
    }
  end
  
  -- Add custom commands (regular commands first, then spells)
  local customCmds = self.customCommands[category] or {}
  local hasRegular = false
  local hasSpells = false
  
  -- First pass: add regular commands
  for _, cmd in ipairs(customCmds) do
    if not cmd.isSpell then
      hasRegular = true
      local finalCmd = cmd.cmd .. " " .. target
      table.insert(items, { text = cmd.text, cmd = finalCmd })
    end
  end
  
  -- Second pass: add spells with separator if we have both
  for _, cmd in ipairs(customCmds) do
    if cmd.isSpell then
      if not hasSpells and hasRegular then
        -- Add separator before first spell if we had regular commands
        table.insert(items, { text = "───────────", cmd = "" })
      end
      hasSpells = true
      local finalCmd = "cast '" .. cmd.cmd .. "' " .. target
      table.insert(items, { text = "✨ " .. cmd.text, cmd = finalCmd })
    end
  end
  
  -- Add/Remove options
  table.insert(items, { text = "───────────", cmd = "" })
  table.insert(items, { text = "➕ Add Command", cmd = "arjui_add_" .. category })
  table.insert(items, { text = "✨ Add Spell", cmd = "arjui_spell_" .. category })
  if #(self.customCommands[category] or {}) > 0 then
    table.insert(items, { text = "➖ Remove Command", cmd = "arjui_remove_" .. category })
  end
  
  return items
end

-- ============================================================
-- PRIVATE MESSAGING SYSTEM
-- ============================================================

function ArjUI:openPrivateChat(playerName)
  local name = playerName:lower()
  local displayName = playerName:sub(1,1):upper() .. playerName:sub(2):lower()
  
  -- If window already exists, just show and focus it
  if self.privateChats[name] and self.privateChats[name].window then
    self.privateChats[name].window:show()
    self.privateChats[name].window:raise()
    self.privateChats[name].unread = 0
    self.privateChats[name].visible = true
    -- Replay all history to ensure messages are visible
    if self.privateChats[name].historyBox then
      self.privateChats[name].historyBox:clear()
      for _, msg in ipairs(self.privateChats[name].history or {}) do
        self:displayPrivateMessage(name, msg.sender, msg.text, msg.outgoing)
      end
    end
    self:renderTellContacts()
    return
  end
  
  -- Create new chat window
  local w, h = getMainWindowSize()
  local chatW, chatH = 300, 220
  local chatX = w - chatW - 30
  local chatY = h - chatH - 80
  
  -- Use Container as the main window (can hold any widget type)
  local chatWin = Geyser.Container:new({
    name = "ArjUI_PrivateChat_" .. name,
    x = chatX, y = chatY, width = chatW, height = chatH
  })
  
  -- Background panel
  local bgPanel = Geyser.Label:new({
    name = chatWin.name .. "_bg",
    x = 0, y = 0, width = "100%", height = "100%"
  }, chatWin)
  bgPanel:setStyleSheet([[
    background-color: #0f0e0c;
    border: 2px solid #8c6e46;
    border-radius: 4px;
  ]])
  
  -- Title bar (draggable)
  local titleBar = Geyser.Label:new({
    name = chatWin.name .. "_title",
    x = 0, y = 0, width = chatW - 24, height = 22
  }, chatWin)
  titleBar:setStyleSheet([[
    background-color: #1a1610;
    color: #d4a855;
    font-size: 10px;
    font-weight: bold;
    padding-left: 8px;
  ]])
  titleBar:echo(displayName)
  
  -- Drag functionality
  local isDragging = false
  local dragStartX, dragStartY = 0, 0
  local winStartX, winStartY = 0, 0
  
  titleBar:setClickCallback(function(event)
    -- Start drag on click
    isDragging = true
    dragStartX, dragStartY = getMousePosition()
    winStartX = chatWin:get_x()
    winStartY = chatWin:get_y()
  end)
  
  titleBar:setReleaseCallback(function(event)
    isDragging = false
  end)
  
  titleBar:setMoveCallback(function(event)
    if isDragging then
      local mouseX, mouseY = getMousePosition()
      local newX = winStartX + (mouseX - dragStartX)
      local newY = winStartY + (mouseY - dragStartY)
      chatWin:move(newX, newY)
    end
  end)
  
  -- Close button
  local closeBtn = Geyser.Label:new({
    name = chatWin.name .. "_close",
    x = chatW - 24, y = 0, width = 24, height = 22
  }, chatWin)
  closeBtn:setStyleSheet([[
    background-color: #1a1610;
    color: #c05050;
    font-size: 12px;
    font-weight: bold;
  ]])
  closeBtn:echo("<center>X</center>")
  closeBtn:setClickCallback(function()
    chatWin:hide()
    self.privateChats[name].visible = false
  end)
  
  -- Message history area
  local historyBox = Geyser.MiniConsole:new({
    name = chatWin.name .. "_history",
    x = 4, y = 24, width = chatW - 8, height = chatH - 56,
    fontSize = 9,
    wrapAt = 40
  }, chatWin)
  historyBox:setBgColor(10, 9, 8)
  historyBox:setFgColor(200, 200, 200)
  historyBox:setWrap(40)
  
  -- Input field
  local inputBox = Geyser.CommandLine:new({
    name = chatWin.name .. "_input",
    x = 4, y = chatH - 30, width = chatW - 68, height = 24
  }, chatWin)
  inputBox:setStyleSheet("background-color: #16140f; border: 1px solid #5a4b37; color: #d0d0d8; font-size: 10px;")
  inputBox:setAction(function(msg)
    if msg and msg ~= "" then
      send("tell " .. name .. " " .. msg)
      inputBox:clear()
    end
  end)
  
  -- Send button
  local sendBtn = Geyser.Label:new({
    name = chatWin.name .. "_send",
    x = chatW - 60, y = chatH - 30, width = 55, height = 24
  }, chatWin)
  sendBtn:setStyleSheet("background-color: #1a1610; border: 1px solid #5a4b37; color: #d4a855; font-size: 10px; font-weight: bold;")
  sendBtn:echo("<center>Send</center>")
  sendBtn:setClickCallback(function()
    local msg = inputBox:getText()
    if msg and msg ~= "" then
      send("tell " .. name .. " " .. msg)
      inputBox:clear()
    end
  end)
  
  chatWin:raise()
  
  -- Store window reference
  local existingHistory = (self.privateChats[name] and self.privateChats[name].history) or {}
  self.privateChats[name] = {
    window = chatWin,
    historyBox = historyBox,
    displayName = displayName,
    history = existingHistory,
    unread = 0,
    visible = true
  }
  
  -- Add to contacts
  self:addTellContact(displayName)
  
  -- Replay history
  for _, msg in ipairs(existingHistory) do
    self:displayPrivateMessage(name, msg.sender, msg.text, msg.outgoing)
  end
  
  -- Clear unread
  self:renderTellContacts()
end

function ArjUI:addPrivateChatMessage(playerName, sender, text, outgoing)
  local name = playerName:lower()
  
  -- Initialize if needed
  self.privateChats[name] = self.privateChats[name] or { history = {}, unread = 0 }
  
  -- Add to history
  table.insert(self.privateChats[name].history, {
    sender = sender,
    text = text,
    outgoing = outgoing,
    time = os.date("%H:%M")
  })
  
  -- Keep history reasonable (last 100 messages)
  while #self.privateChats[name].history > 100 do
    table.remove(self.privateChats[name].history, 1)
  end
  
  -- Check if window exists and is visible using our visible flag
  local windowOpen = self.privateChats[name].window and self.privateChats[name].visible
  
  -- Display if window is open and visible
  if windowOpen then
    self:displayPrivateMessage(name, sender, text, outgoing)
    -- Window is open, so mark as read
    self.privateChats[name].unread = 0
  else
    -- Window not open or not visible, increment unread for incoming messages only
    if not outgoing then
      self.privateChats[name].unread = (self.privateChats[name].unread or 0) + 1
      self:renderTellContacts()
    end
  end
end

function ArjUI:displayPrivateMessage(playerName, sender, text, outgoing)
  local name = playerName:lower()
  local chat = self.privateChats[name]
  if not chat or not chat.historyBox then return end
  
  local time = os.date("%H:%M")
  if outgoing then
    chat.historyBox:cecho(string.format("<dim_gray>[%s] <medium_orchid>You<reset>: %s\n", time, text))
  else
    chat.historyBox:cecho(string.format("<dim_gray>[%s] <gold>%s<reset>: %s\n", time, sender, text))
  end
end

function ArjUI:addTellContact(playerName)
  local displayName = playerName:sub(1,1):upper() .. playerName:sub(2):lower()
  
  -- Check if already in contacts
  for _, contact in ipairs(self.tellContacts) do
    if contact:lower() == displayName:lower() then
      return
    end
  end
  
  -- Add to front of list (most recent first)
  table.insert(self.tellContacts, 1, displayName)
  
  -- Keep list reasonable
  while #self.tellContacts > 20 do
    table.remove(self.tellContacts)
  end
  
  self:renderTellContacts()
end

function ArjUI:handleIncomingTell(sender, text)
  local name = sender:lower()
  local displayName = sender:sub(1,1):upper() .. sender:sub(2):lower()
  
  -- Add to contacts
  self:addTellContact(displayName)
  
  -- Add message to history (this handles unread count internally)
  self:addPrivateChatMessage(name, displayName, text, false)
end

function ArjUI:renderTellContacts()
  if not self.tellsBox then return end
  
  self.tellsBox:clear()
  
  if #self.tellContacts == 0 then
    self.tellsBox:cecho("<dim_gray>No recent conversations.\n")
    self.tellsBox:cecho("<dim_gray>Tells will appear here.\n")
    return
  end
  
  self.tellsBox:cecho("<dim_gray>── Recent Conversations ──\n\n")
  
  for _, contact in ipairs(self.tellContacts) do
    local name = contact:lower()
    local unread = 0
    if self.privateChats[name] then
      unread = self.privateChats[name].unread or 0
    end
    
    local displayText
    if unread > 0 then
      displayText = string.format("<gold>%s<reset> <red>(%d new)<reset>\n", contact, unread)
    else
      displayText = string.format("<medium_orchid>%s<reset>\n", contact)
    end
    
    self.tellsBox:cechoLink(displayText, function()
      self:openPrivateChat(contact)
    end, "Click to open chat with " .. contact, true)
  end
end

-- ============================================================
-- GMCP HANDLERS
-- ============================================================

function ArjUI:registerGMCPHandlers()
  local h
  
  h = registerAnonymousEventHandler("gmcp.Char.Vitals", function() self:onCharVitals() end)
  table.insert(self.eventHandlers, h)
  h = registerAnonymousEventHandler("gmcp.Room.Info", function() self:onRoomInfo() end)
  table.insert(self.eventHandlers, h)
  h = registerAnonymousEventHandler("gmcp.Combat.Update", function() self:onCombatUpdate() end)
  table.insert(self.eventHandlers, h)
  h = registerAnonymousEventHandler("gmcp.Group.Status", function() self:onGroupStatus() end)
  table.insert(self.eventHandlers, h)
  h = registerAnonymousEventHandler("gmcp.Comm.Channel", function() self:onCommChannel() end)
  table.insert(self.eventHandlers, h)
  h = registerAnonymousEventHandler("gmcp.Char.Affects", function() self:onCharAffects() end)
  table.insert(self.eventHandlers, h)
  
  -- Char.Status: sent once on character entry and on level change (self only)
  h = registerAnonymousEventHandler("gmcp.Char.Status", function() self:onCharStatus() end)
  table.insert(self.eventHandlers, h)
  -- Quest.Status: bartender quest state (login, accept, progress, complete)
  h = registerAnonymousEventHandler("gmcp.Quest.Status", function() self:onQuestStatus() end)
  table.insert(self.eventHandlers, h)
  
  -- Prompt-based refresh for immediate updates
  h = registerAnonymousEventHandler("sysDataSendRequest", function() 
    -- Refresh combat displays on every command sent
    self:renderTarget()
    self:renderTank()
  end)
  table.insert(self.eventHandlers, h)
  
  -- Send GMCP handshake when protocol is enabled
  h = registerAnonymousEventHandler("sysProtocolEnabled", function(_, protocol)
    if protocol == "GMCP" then
      sendGMCP('Core.Hello {"client":"Mudlet-ArjUI","version":"' .. ArjUI.VERSION .. '"}')
      sendGMCP('Core.Supports.Set ["Char 1","Char.Vitals 1","Char.Status 1","Char.Affects 1","Room 1","Room.Info 1","Group 1","Group.Status 1","Comm 1","Comm.Channel 1","Combat 1"]')
    end
  end)
  table.insert(self.eventHandlers, h)
  
  -- On socket connect, reset flag and enable GMCP modules
  h = registerAnonymousEventHandler("sysConnectionEvent", function()
    self.initialDataRequested = false
    if gmod and gmod.enableModule then
      gmod.enableModule("ArjUI", "Char")
      gmod.enableModule("ArjUI", "Char.Vitals")
      gmod.enableModule("ArjUI", "Char.Status")
      gmod.enableModule("ArjUI", "Char.Affects")
      gmod.enableModule("ArjUI", "Room")
      gmod.enableModule("ArjUI", "Room.Info")
      gmod.enableModule("ArjUI", "Group")
      gmod.enableModule("ArjUI", "Group.Status")
      gmod.enableModule("ArjUI", "Comm")
      gmod.enableModule("ArjUI", "Comm.Channel")
      gmod.enableModule("ArjUI", "Combat")
      gmod.enableModule("ArjUI", "Quest")
      gmod.enableModule("ArjUI", "Quest.Status")
    end
  end)
  table.insert(self.eventHandlers, h)
  
  -- Detect character login and render UI.
  -- Primary signal: first gmcp.Char.Status after connect (server sends it once on
  -- character entry, independent of prompt settings). Fallback: default prompt shape.
  self.loginTrigger = tempRegexTrigger("^< \\d+h/\\d+H \\d+v/\\d+V Pos:", function()
    if ArjUI then ArjUI:onLoginDetected() end
  end)
  table.insert(self.eventHandlers, self.loginTrigger)
  
  
  -- Room refresh triggers disabled - GMCP Room.Info handles this automatically
  -- self.dropTrigger = tempRegexTrigger("^(You drop|.+ drops) ", function()
  --   tempTimer(0.3, function() if ArjUI then send("look", false) end end)
  -- end)
  -- self.getTrigger = tempRegexTrigger("^(You get|You pick up|.+ gets) ", function()
  --   tempTimer(0.3, function() if ArjUI then send("look", false) end end)
  -- end)
  
  -- Trigger to detect when a mob dies (clears target and resets tank bar to self)
  self.deathTrigger = tempRegexTrigger("^.+ is dead! R\\.I\\.P\\.$", function()
    -- Clear target
    ArjUI.state.target = nil
    ArjUI.state.targetHpPct = 100
    ArjUI.state.targetCond = nil
    ArjUI.state.targetPos = nil
    ArjUI.state.targetBleeding = false
    -- Reset tank bar to self (combat ended)
    ArjUI.state.iAmTank = true
    ArjUI.state.tank = nil
    ArjUI.state.tankCond = nil
    ArjUI.state.tankHpPct = nil
    ArjUI:renderTarget()
    ArjUI:renderTank()
  end)
  
  -- Trigger to detect flee (clears target and resets tank bar to self)
  self.fleeTrigger = tempRegexTrigger("^You flee ", function()
    -- Clear target
    ArjUI.state.target = nil
    ArjUI.state.targetHpPct = 100
    ArjUI.state.targetCond = nil
    ArjUI.state.targetPos = nil
    ArjUI.state.targetBleeding = false
    -- Reset tank bar to self (combat ended for us)
    ArjUI.state.iAmTank = true
    ArjUI.state.tank = nil
    ArjUI.state.tankCond = nil
    ArjUI.state.tankHpPct = nil
    ArjUI:renderTarget()
    ArjUI:renderTank()
  end)
  
  -- Trigger to detect player death (clears all combat state)
  -- Matches account menu which appears after death
  self.playerDeathTrigger = tempRegexTrigger("ACCOUNT MENU", function()
    -- Clear target
    ArjUI.state.target = nil
    ArjUI.state.targetHpPct = 100
    ArjUI.state.targetCond = nil
    ArjUI.state.targetPos = nil
    ArjUI.state.targetBleeding = false
    -- Reset tank bar to self
    ArjUI.state.iAmTank = true
    ArjUI.state.tank = nil
    ArjUI.state.tankCond = nil
    ArjUI.state.tankHpPct = nil
    ArjUI:renderTarget()
    ArjUI:renderTank()
  end)
  
  -- Trigger to detect assist (sets assist target for YOU bar)
  self.assistTrigger = tempRegexTrigger("^You are now assisting (.+)\\.$", function()
    local assistName = matches[2]
    if assistName and assistName ~= "" then
      ArjUI.state.assistTarget = assistName
      ArjUI.state.iAmTank = false
      ArjUI:updateAssistTarget()
      ArjUI:renderTank()
    end
  end)
  
  -- Trigger to detect stop assisting
  self.stopAssistTrigger = tempRegexTrigger("^You are no longer assisting ", function()
    ArjUI.state.assistTarget = nil
    ArjUI.state.iAmTank = true
    ArjUI:renderTank()
  end)
  
  -- Time of day triggers (automatic announcements)
  self.timeDayTrigger = tempRegexTrigger("^The day has begun\\.$", function()
    ArjUI.state.timeOfDay = "day"
    ArjUI:renderTime()
  end)
  self.timeNightTrigger = tempRegexTrigger("^The night has begun\\.$", function()
    ArjUI.state.timeOfDay = "night"
    ArjUI:renderTime()
  end)
  self.timeDawnTrigger = tempRegexTrigger("^The sun rises", function()
    ArjUI.state.timeOfDay = "dawn"
    ArjUI:renderTime()
  end)
  self.timeDuskTrigger = tempRegexTrigger("^The sun sets", function()
    ArjUI.state.timeOfDay = "dusk"
    ArjUI:renderTime()
  end)
  
  -- Parse 'time' command output: "It is 9pm, on the Day of the Deception"
  -- Gag the output if it was from our silent auto-query
  self.timeCommandTrigger = tempRegexTrigger("^It is (\\d+)(am|pm)", function()
    local hour = tonumber(matches[2])
    local ampm = matches[3]
    -- Convert to 24h for easier day/night detection
    if ampm == "pm" and hour ~= 12 then hour = hour + 12 end
    if ampm == "am" and hour == 12 then hour = 0 end
    -- Determine time of day: 6am-6pm = day, 6pm-6am = night, with dawn/dusk at transitions
    if hour >= 6 and hour < 7 then
      ArjUI.state.timeOfDay = "dawn"
    elseif hour >= 7 and hour < 18 then
      ArjUI.state.timeOfDay = "day"
    elseif hour >= 18 and hour < 19 then
      ArjUI.state.timeOfDay = "dusk"
    else
      ArjUI.state.timeOfDay = "night"
    end
    ArjUI:renderTime()
    -- Gag if this was from auto-query (within 3 seconds of login)
    if ArjUI.timeQuerySilent then
      deleteLine()
    end
  end)
  
  -- Gag the additional time output lines when silent
  self.timeGagTrigger1 = tempRegexTrigger("^The \\d+.. Day of the ", function()
    if ArjUI.timeQuerySilent then deleteLine() end
  end)
  self.timeGagTrigger2 = tempRegexTrigger("^Time elapsed since boot-up:", function()
    if ArjUI.timeQuerySilent then deleteLine() end
  end)
  self.timeGagTrigger3 = tempRegexTrigger("^Current time is:", function()
    if ArjUI.timeQuerySilent then deleteLine() end
  end)
  self.timeGagTrigger4 = tempRegexTrigger("^\\s+\\w+ \\w+ +\\d+ \\d+:\\d+:\\d+ \\d+", function()
    if ArjUI.timeQuerySilent then 
      deleteLine()
      -- Last line of time output - clear the silent flag
      ArjUI.timeQuerySilent = false
    end
  end)
  
  -- Trigger to parse combat prompt line for tank, target, and positions
  -- Format: < T: Seveiwyn TP: sta TC: excellent E: wolf EP: sta EC: small wounds>
  self.combatPromptTrigger = tempRegexTrigger("^< T: (.+) TP: (\\w+) TC: ([^E]+) E: (.+) EP: (\\w+) EC: ([^>]+)>", function()
    local tankName = matches[2]:gsub("%s+$", "")  -- trim trailing space
    local tankPos = matches[3]
    local tankCond = matches[4]:gsub("%s+$", "")  -- trim trailing space
    local enemyName = matches[5]:gsub("%s+$", "")
    local enemyPos = matches[6]
    local enemyCond = matches[7]:gsub("%s+$", "")
    
    -- Update tank info (T: is who is tanking)
    if tankName and tankName ~= "" then
      local myName = ArjUI.playerName or ""
      if tankName:lower() == myName:lower() then
        -- I am the tank - show my own HP
        ArjUI.state.iAmTank = true
        ArjUI.state.assistTarget = nil
      else
        -- Someone else is tanking - show their info
        ArjUI.state.iAmTank = false
        ArjUI.state.tank = tankName
        ArjUI.state.tankPos = tankPos
        ArjUI.state.tankCond = tankCond
        ArjUI.state.tankHpPct = ArjUI:conditionToPercent(tankCond)
      end
      ArjUI:renderTank()
    end
    
    -- Update target info (E: is the enemy)
    if enemyName and enemyName ~= "" then
      ArjUI.state.target = enemyName
      ArjUI.state.targetPos = enemyPos
      ArjUI.state.targetCond = enemyCond
      ArjUI.state.targetHpPct = ArjUI:conditionToPercent(enemyCond)
      ArjUI:renderTarget()
    end
  end)
end

-- Called once per character login (from Char.Status or the prompt fallback)
function ArjUI:onLoginDetected()
  if self.initialDataRequested then return end
  self.initialDataRequested = true
  -- Render after short delay to allow any pending GMCP data to arrive
  tempTimer(0.5, function()
    if ArjUI then ArjUI:renderAll() end
  end)
  -- Query time silently on login
  tempTimer(1.0, function()
    ArjUI.timeQuerySilent = true
    send("time", false)
  end)
end

-- Convert condition text to approximate HP percentage
function ArjUI:conditionToPercent(cond)
  if not cond then return 100 end
  local c = cond:lower()
  if c:find("excellent") then return 100
  elseif c:find("few scratches") then return 90
  elseif c:find("small wounds") then return 80
  elseif c:find("few wounds") then return 70
  elseif c:find("several wounds") then return 60
  elseif c:find("big nasty") then return 40
  elseif c:find("nasty wounds") then return 50
  elseif c:find("pretty hurt") then return 30
  elseif c:find("awful") then return 20
  elseif c:find("bleeding") then return 5
  elseif c:find("dead") then return 0
  else return 50 end
end

function ArjUI:onCharVitals()
  if not gmcp or not gmcp.Char or not gmcp.Char.Vitals then return end
  local v = gmcp.Char.Vitals
  local pname = pick(v, "name", "char", "player")
  if pname and type(pname) == "string" and pname ~= "" then self.playerName = self.playerName or pname end
  self.state.hp = toNum(pick(v, "hp", "health")) or self.state.hp
  self.state.hpmax = toNum(pick(v, "maxHp", "maxhp", "max_health")) or self.state.hpmax
  self.state.mana = toNum(pick(v, "mana", "mp")) or self.state.mana
  self.state.manamax = toNum(pick(v, "maxMana", "maxmana", "maxMp")) or self.state.manamax
  self.state.move = toNum(pick(v, "move", "mv")) or self.state.move
  self.state.movemax = toNum(pick(v, "maxMove", "maxmove", "maxMv")) or self.state.movemax
  local newTnl = toNum(pick(v, "tnl", "toNextLevel"))
  if newTnl then
    if not self.state.tnlBaseline then self.state.tnlBaseline = newTnl
    elseif newTnl > self.state.tnl then self.state.tnlBaseline = newTnl end
    self.state.tnl = newTnl
  end
  if v.position then self.state.position = v.position end
  if v.usesMana ~= nil then self.state.usesMana = (v.usesMana == true) end
  self.state.fighting = (type(v.fighting) == "string" and v.fighting ~= "") and v.fighting or nil
  local coins = self.state.coins
  coins.platinum = toNum(v.platinum) or coins.platinum
  coins.gold = toNum(v.gold) or coins.gold
  coins.silver = toNum(v.silver) or coins.silver
  coins.copper = toNum(v.copper) or coins.copper
  self:renderVitals()
  self:renderTNLBar()
  self:renderTank()
  if self.activeTab == "stats" then self:renderStats() end
end

function ArjUI:onRoomInfo()
  if not gmcp or not gmcp.Room or not gmcp.Room.Info then return end
  local r = gmcp.Room.Info
  self.state.room = r.name or self.state.room
  self.state.coloredRoom = r.colored_name or r.name or self.state.room
  self.state.area = r.area or r.zone or self.state.area
  self.state.coloredArea = r.colored_area or r.area or self.state.area
  self.state.roomId = r.num or self.state.roomId
  self.state.zoneId = r.zone or self.state.zoneId
  if r.exits then
    self.state.exits = {}
    self.state.exitsRaw = {}
    for dir, _ in pairs(r.exits) do
      local cleanDir = dir:gsub("#", ""):gsub("%s+", "")
      table.insert(self.state.exits, cleanDir:sub(1,1):upper())
      table.insert(self.state.exitsRaw, cleanDir:lower())
    end
    table.sort(self.state.exits)
  end
  self.state.doors = (type(r.doors) == "table") and r.doors or {}
  self.state.npcs = r.npcs or {}
  self.state.items = r.items or {}
  self.state.players = r.players or {}
  
  self:renderRoom()
  self:renderMobs()
  self:renderItems()
  self:renderPlayers()
end

function ArjUI:onCombatUpdate()
  if not gmcp or not gmcp.Combat or not gmcp.Combat.Update then return end
  local c = gmcp.Combat.Update
  
  -- Handle tank info if provided (rescue, swap, flee changes)
  if c.tank then
    local t = c.tank
    local tankName = t.name or ""
    local myName = self.playerName or ""
    
    if tankName:lower() == myName:lower() then
      -- I am the tank
      self.state.iAmTank = true
    else
      -- Someone else is tanking
      self.state.iAmTank = false
      self.state.tank = tankName
      self.state.tankPos = t.position or self.state.tankPos
      self.state.tankCond = t.health or t.condition or self.state.tankCond
      self.state.tankHpPct = toNum(pick(t, "healthPercent", "hpPercent", "hp_pct")) or self:conditionToPercent(self.state.tankCond)
    end
    self:renderTank()
  end
  
  -- Handle target/enemy info
  if c.target then
    local t = c.target
    self.state.target = t.name or "Unknown"
    self.state.targetHpPct = toNum(pick(t, "healthPercent", "hpPercent", "hp_pct")) or self.state.targetHpPct
    self.state.targetCond = t.health or self.state.targetCond
    self.state.targetPos = t.position or self.state.targetPos
    
    -- Track if target is bleeding to death (only exact match, for persistence)
    local condLower = (self.state.targetCond or ""):lower()
    if condLower:find("bleeding to death") then
      self.state.targetBleeding = true
    else
      self.state.targetBleeding = false
    end
    
    -- Clear the clear timer if we got fresh target data
    if self._targetClearTimer then 
      killTimer(self._targetClearTimer)
      self._targetClearTimer = nil
    end
  else
    -- No target in update - check if we should persist a bleeding target
    if self.state.target and self.state.targetBleeding then
      -- Target is bleeding to death - keep showing at 1% until confirmed dead
      self.state.targetHpPct = 1
      self.state.targetCond = "bleeding to death"
      -- Don't clear target yet
    else
      -- No bleeding target - clear normally
      self.state.target = nil
      self.state.targetHpPct = 100
      self.state.targetCond = nil
      self.state.targetPos = nil
      self.state.targetBleeding = false
    end
  end
  self:renderTarget()
end

function ArjUI:onGroupStatus()
  if not gmcp or not gmcp.Group or not gmcp.Group.Status then return end
  local g = gmcp.Group.Status
  self.state.group = g.members or {}
  self.state.groupSize = toNum(g.size) or #self.state.group
  self.state.groupMax = toNum(g.maxSize) or 0
  self:renderGroup()
  self:renderTank()  -- Update tank when group changes
end

function ArjUI:onCharStatus()
  -- Handle Char.Status for position updates AND player alignment tracking
  if not gmcp or not gmcp.Char or not gmcp.Char.Status then return end
  local s = gmcp.Char.Status
  
  -- Track alignment for any player we receive status for
  if s.name and s.alignment then
    self.state.playerAlignments = self.state.playerAlignments or {}
    self.state.playerAlignments[s.name:lower()] = s.alignment:lower()
    self:renderPlayers()  -- Re-render players with updated alignment
  end
  
  -- Char.Status is only ever about ourselves: record identity fields
  if type(s.name) == "string" and s.name ~= "" then self.playerName = s.name end
  self.state.charLevel = toNum(s.level) or self.state.charLevel
  self.state.charClass = s.class or self.state.charClass
  self.state.charRace = s.race or self.state.charRace
  self.state.charGuild = s.guild or self.state.charGuild
  self.state.charTitle = s.title or self.state.charTitle
  
  -- Update our own position if this is about us
  if s.position then self.state.position = s.position end
  self:renderVitals()
  self:renderTank()
  self:renderTarget()
  if self.activeTab == "stats" then self:renderStats() end
  
  -- First Char.Status after connect = character has entered the game
  self:onLoginDetected()
end

function ArjUI:onQuestStatus()
  if not gmcp or not gmcp.Quest or not gmcp.Quest.Status then return end
  local q = gmcp.Quest.Status
  if q.active == true then
    self.state.quest = {
      type = q.type, target = q.target or "",
      remaining = toNum(q.remaining),
      killCount = toNum(q.killCount), killRequired = toNum(q.killRequired),
      mapBought = q.mapBought == true,
    }
  else
    self.state.quest = nil
  end
  if self.activeTab == "stats" then self:renderStats() end
end

function ArjUI:onCommChannel()
  if not gmcp or not gmcp.Comm or not gmcp.Comm.Channel then return end
  local c = gmcp.Comm.Channel
  local channel = c.channel or "unknown"
  local sender = stripColors(c.sender or "Someone")
  local text = stripColors(c.text or "")
  
  -- Parse sender for tells - handle "You -> PlayerName" format for outgoing tells
  local actualSender = sender
  local isOutgoing = false
  if sender:match("^You %-> (.+)$") then
    actualSender = sender:match("^You %-> (.+)$")
    isOutgoing = true
  end
  
  -- Channel names as the server actually emits them (src/net/gmcp.c, chat_presentation.c):
  -- say, tell, gcc (guild), gsay (group), nchat, jchat, petition, wizmsg
  local colors = { tell = "<medium_orchid>", say = "<khaki>", group = "<medium_sea_green>", gsay = "<medium_sea_green>", gtell = "<medium_sea_green>", shout = "<indian_red>", auction = "<plum>", gossip = "<light_gray>", nchat = "<steel_blue>", jchat = "<cadet_blue>", guild = "<dark_orange>", gcc = "<dark_orange>", yell = "<tomato>", petition = "<gold>", wizmsg = "<orchid>" }
  local color = colors[channel] or "<dim_gray>"
  
  -- nchat/jchat carry the speaker's race-war alignment: colour the sender by it
  local senderColored = sender
  if c.alignment then
    local alignColors = { good = "<white>", evil = "<indian_red>", undead = "<medium_purple>", neutral = "<gray>" }
    local ac = alignColors[tostring(c.alignment):lower()]
    if ac then senderColored = ac .. sender .. color end
  end
  local formatted = string.format("%s[%s] %s<reset>: %s\n", color, channel, senderColored, text)
  
  -- Always send to ALL tab
  self.chatBox:cecho(formatted)
  
  -- Route to specific tab based on channel
  local channelLower = channel:lower()
  if channelLower == "tell" or channelLower == "tells" then
    -- Route to private messaging system only (don't echo to TELLS tab)
    if isOutgoing then
      self:handleOutgoingTell(actualSender, text)
    else
      self:handleIncomingTell(actualSender, text)
    end
    return  -- Don't continue to other tabs
  elseif channelLower == "nchat" or channelLower == "newbie" or channelLower == "jchat" then
    self.nchatBox:cecho(formatted)
  elseif channelLower == "say" or channelLower == "yell" or channelLower == "shout" then
    self.roomBox:cecho(formatted)
  elseif channelLower == "gcc" or channelLower == "guild" or channelLower == "clan" then
    self.guildBox:cecho(formatted)
  elseif channelLower == "group" or channelLower == "gtell" or channelLower == "party" or channelLower == "gsay" then
    self.groupChatBox:cecho(formatted)
  end
end

function ArjUI:onCharAffects()
  if not gmcp or not gmcp.Char or not gmcp.Char.Affects then return end
  self.state.affects = gmcp.Char.Affects or {}
  self:renderAffects()
end

-- Debug function to show GMCP player data in chat console
function ArjUI:debugPlayers()
  self.chatBox:cecho("<cyan>── GMCP Room.Info.players ──\n")
  if not gmcp or not gmcp.Room or not gmcp.Room.Info or not gmcp.Room.Info.players then
    self.chatBox:cecho("<dim_gray>No player data available\n")
    return
  end
  local players = gmcp.Room.Info.players
  if #players == 0 then
    self.chatBox:cecho("<dim_gray>No players in room\n")
    return
  end
  for i, p in ipairs(players) do
    self.chatBox:cecho(string.format("<white>Player %d:\n", i))
    for k, v in pairs(p) do
      self.chatBox:cecho(string.format("<dim_gray>  %s = <yellow>%s\n", tostring(k), tostring(v)))
    end
  end
end

-- Register /debugplayers alias
tempAlias("^/debugplayers$", function() ArjUI:debugPlayers() end)

-- ============================================================
-- RENDER FUNCTIONS
-- ============================================================

function ArjUI:getHpBarStyle(pct)
  local r1, g1, b1, r2, g2, b2
  if pct >= 75 then r1,g1,b1,r2,g2,b2 = 16,80,16,32,112,32
  elseif pct >= 50 then r1,g1,b1,r2,g2,b2 = 100,90,16,140,120,32
  elseif pct >= 25 then r1,g1,b1,r2,g2,b2 = 120,60,16,160,80,32
  else r1,g1,b1,r2,g2,b2 = 107,16,16,139,32,32 end
  return string.format("background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 rgb(%d,%d,%d),stop:0.5 rgb(%d,%d,%d),stop:1 rgb(%d,%d,%d)); border: none; border-radius: 2px;", r1,g1,b1,r2,g2,b2,r1,g1,b1)
end

function ArjUI:renderTNLBar()
  local tnl, base = self.state.tnl, self.state.tnlBaseline
  if tnl and tnl > 0 and base and base > 0 then
    self.xpGauge:setValue(math.max(0, base - tnl), base, string.format("TNL: %d", tnl))
  elseif tnl and tnl > 0 then
    self.xpGauge:setValue(0, 100, string.format("TNL: %d", tnl))
  else
    self.xpGauge:setValue(0, 100, "TNL")
  end
end

function ArjUI:renderVitals()
  local s = self.state
  local hpPct = s.hpmax > 0 and math.floor((s.hp / s.hpmax) * 100) or 100
  self.hpGauge.front:setStyleSheet(self:getHpBarStyle(hpPct))
  self.hpGauge:setValue(s.hp, s.hpmax, string.format("HP %d/%d", s.hp, s.hpmax))
  if s.usesMana == false then
    self.mpGauge:setValue(0, 1, "MP n/a")
  else
    self.mpGauge:setValue(s.mana, s.manamax, string.format("MP %d/%d", s.mana, s.manamax))
  end
  self.mvGauge:setValue(s.move, s.movemax, string.format("MV %d/%d", s.move, s.movemax))
  
  local posText = string.upper(s.position or "Standing")
  self.posLabel:echo(posText)
  if posText ~= "STANDING" then
    self.posLabel:setStyleSheet(self.styles.posAlert)
  else
    self.posLabel:setStyleSheet(self.styles.pos)
  end
end

function ArjUI:renderRoom()
  -- Use colored area/room names if available
  local coloredArea = self.state.coloredArea or self.state.area or "Unknown Area"
  local coloredRoom = self.state.coloredRoom or self.state.room or ""
  self.areaLabel:decho(durisToDecho(coloredArea))
  self.roomLabel:decho(durisToDecho(coloredRoom))
  self:renderExits()
end


function ArjUI:renderExits()
  -- Static exit button layout so positions never swap when exits update
  if not self.exitButtonsStatic then
    self.exitButtonsStatic = {}

    -- clear container once
    self.exitsWrap:echo("")

    -- Prefix label
    local prefix = Geyser.Label:new({ name = "ArjUI_ExitPrefix", x = 0, y = 0, width = 32, height = "100%" }, self.exitsWrap)
    prefix:setStyleSheet("background-color: transparent; color: #606070; font-size: 10px;")
    prefix:echo("Exits:")
    self.exitButtonsStatic.prefix = prefix

    -- Fixed slots using pixel offsets from prefix (more reliable for small panel)
    local slots = {
      n  = { x = 34,  label = "N",  cmd = "north" },
      e  = { x = 48,  label = "E",  cmd = "east"  },
      s  = { x = 62,  label = "S",  cmd = "south" },
      w  = { x = 76,  label = "W",  cmd = "west"  },
      u  = { x = 90,  label = "U",  cmd = "up"    },
      d  = { x = 104, label = "D",  cmd = "down"  },

      ne = { x = 120, label = "NE", cmd = "northeast" },
      nw = { x = 140, label = "NW", cmd = "northwest" },
      se = { x = 160, label = "SE", cmd = "southeast" },
      sw = { x = 180, label = "SW", cmd = "southwest" },

      ["in"]  = { x = 120, label = "IN",  cmd = "in"  },
      out = { x = 140, label = "OUT", cmd = "out" },
    }

    for key, info in pairs(slots) do
      local w = (info.label:len() == 1) and 12 or 18
      local btn = Geyser.Label:new({ name = "ArjUI_Exit_" .. key, x = info.x, y = 2, width = w, height = "85%" }, self.exitsWrap)
      btn:setStyleSheet(self.styles.exitButton)
      btn:echo("<center>" .. info.label .. "</center>")
      btn:setOnEnter(function() btn:setStyleSheet(self.styles.exitButtonHover); btn:setCursor("PointingHand") end)
      btn:setOnLeave(function() btn:setStyleSheet(self.styles.exitButton); btn:setCursor("Arrow") end)
      btn:hide()

      -- store intended send() command
      btn._cmd = info.cmd
      self.exitButtonsStatic[key] = btn
    end
  end

  -- Hide all buttons, then show only active exits
  for k, btn in pairs(self.exitButtonsStatic) do
    if k ~= "prefix" and btn and btn.hide then btn:hide() end
  end

  local exits = self.state.exitsRaw or {}
  if #exits == 0 then
    -- keep prefix visible; no exits
    return
  end

  -- exitsRaw contains full direction strings (lowercase). We map them to slots.
  for _, dir in ipairs(exits) do
    local d = (dir or ""):lower()

    -- map possible strings to our slot keys
    local keyMap = {
      north="n", n="n",
      east="e", e="e",
      south="s", s="s",
      west="w", w="w",
      up="u", u="u",
      down="d", d="d",
      northeast="ne", ne="ne",
      northwest="nw", nw="nw",
      southeast="se", se="se",
      southwest="sw", sw="sw",
      ["in"]="in",
      out="out",
    }

    local key = keyMap[d]
    local btn = key and self.exitButtonsStatic[key] or nil
    if btn then
      btn:show()
      local cmd = btn._cmd or d
      -- Room.Info.doors[dir] = { name, closed, locked } when the exit has a door
      local door = key and self.state.doors and self.state.doors[key] or nil
      local baseStyle = self.styles.exitButton
      if door and door.closed then
        baseStyle = door.locked and self.styles.exitButtonLocked or self.styles.exitButtonClosed
      end
      btn._baseStyle = baseStyle
      btn:setStyleSheet(baseStyle)
      btn:setOnLeave(function() btn:setStyleSheet(btn._baseStyle or self.styles.exitButton); btn:setCursor("Arrow") end)
      btn:setClickCallback(function() send(cmd) end)
    end
  end
end

function ArjUI:renderMobs()
  self.mobsBox:clear()
  local npcs = self.state.npcs or {}
  if #npcs == 0 then self.mobsBox:cecho("<dim_gray>(none)\n"); return end
  
  -- Track by keyword, preserve colored_name for display
  -- Room.Info.npcs[].fighting = "you" | player name | npc name | "someone" | "someone who has already left"
  local counts, order, coloredNames, fighting = {}, {}, {}, {}
  for _, npc in ipairs(npcs) do
    local keyword = npc.keyword or npc.name or "unknown"
    local colored = npc.colored_name or npc.name or keyword
    if keyword ~= "" then
      if not counts[keyword] then 
        counts[keyword] = 0
        table.insert(order, keyword)
        coloredNames[keyword] = colored
      end
      counts[keyword] = counts[keyword] + 1
      if type(npc.fighting) == "string" and npc.fighting ~= "" then
        -- prefer "you" over any other opponent when several share a keyword
        if npc.fighting == "you" or not fighting[keyword] then fighting[keyword] = npc.fighting end
      end
    end
  end
  
  for _, keyword in ipairs(order) do
    local count = counts[keyword]
    local colored = coloredNames[keyword] or keyword
    local coloredDisplay = durisToDecho(colored)
    local tag = ""
    local f = fighting[keyword]
    if f == "you" then
      tag = " <220,60,60>[vs YOU]"
    elseif f and not f:find("^someone") then
      tag = string.format(" <200,160,60>[vs %s]", stripColors(f):sub(1, 12))
    elseif f then
      tag = " <140,140,140>[fighting]"
    end
    local text = count > 1 and string.format("%s <128,128,128>(x%d)%s\n", coloredDisplay, count, tag) or string.format("%s%s\n", coloredDisplay, tag)
    self.mobsBox:dechoLink(text, function()
      self:showContextMenu(self:getContextMenuItems("mobs", keyword))
    end, "Click for options", true)
  end
end

function ArjUI:renderItems()
  self.objsBox:clear()
  local items = self.state.items or {}
  if #items == 0 then self.objsBox:cecho("<dim_gray>(none)\n"); return end
  
  -- Track by name (for commands), preserve colored_name for display
  local counts, order, coloredNames = {}, {}, {}
  for _, item in ipairs(items) do
    local name = item.name or "something"
    local colored = item.colored_name or name
    if not counts[name] then 
      counts[name] = 0
      table.insert(order, name)
      coloredNames[name] = colored
    end
    counts[name] = counts[name] + 1
  end
  
  for _, name in ipairs(order) do
    local count = counts[name]
    local colored = coloredNames[name] or name
    local coloredDisplay = durisToDecho(colored)
    local cmdName = normalizeTargetName(name)
    local text = count > 1 and string.format("%s <128,128,128>(x%d)\n", coloredDisplay, count) or string.format("%s\n", coloredDisplay)
    self.objsBox:dechoLink(text, function()
      local target = durisTargetKey(cmdName)
      self:showContextMenu(self:getContextMenuItems("objects", target))
    end, "Click for options", true)
  end
end

function ArjUI:renderPlayers()
  self.enemyBox:clear()
  local players = self.state.players or {}
  if #players == 0 then self.enemyBox:decho("<100,100,100>(none)\n"); return end
  
  local alignments = self.state.playerAlignments or {}
  
  for _, p in ipairs(players) do
    local name = p.name or "Someone"
    local displayName = normalizeTargetName(name)
    local cmdName = displayName  -- Use clean name for commands
    
    -- Check for alignment in player data from Room.Info, or from our tracked alignments
    local alignment = p.alignment or alignments[name:lower()] or "unknown"
    if type(alignment) == "string" then alignment = alignment:lower() end
    
    -- Color based on alignment: good=white, evil=red, neutral=gray
    local color
    if alignment == "evil" then
      color = "<220,60,60>"  -- Red for evil
    elseif alignment == "good" then
      color = "<220,220,220>"  -- White for good
    else
      color = "<140,140,140>"  -- Gray for neutral/unknown
    end
    
    -- Use unified context menu system for players
    local target = quoteIfNeeded(cmdName)
    self.enemyBox:dechoLink(string.format("%s%s\n", color, displayName), function()
      self:showContextMenu(self:getContextMenuItems("players", target))
    end, "Click for options", true)
  end
end

function ArjUI:renderTarget()
  if self.state.target then
    local pct = self.state.targetHpPct or 100
    local cond = self.state.targetCond or ""
    local condLower = cond:lower()
    
    -- Only show DEAD if condition explicitly contains "dead" as a word (not "bleeding to death")
    local isDead = (condLower == "dead" or condLower:find("^dead") or condLower:find("corpse"))
    
    if isDead then
      self.targetNameLabel:echo(self.state.target .. " [DEAD]")
      self.targetNameLabel:setStyleSheet(self.styles.targetDead)
      self.targetHpGauge.front:setStyleSheet(self.gaugeStyles.deadFront)
      self.targetHpGauge.back:setStyleSheet(self.gaugeStyles.deadBack)
      self.targetHpGauge:setValue(0, 100, "DEAD")
    else
      self.targetNameLabel:echo(self.state.target)
      self.targetNameLabel:setStyleSheet(self.styles.targetName)
      -- Use at least 1% so the bar shows something even when very low
      local displayPct = math.max(1, pct)
      self.targetHpGauge.front:setStyleSheet(self:getHpBarStyle(pct))
      self.targetHpGauge.back:setStyleSheet(self.gaugeStyles.targetBack)
      self.targetHpGauge:setValue(displayPct, 100, string.format("%d%% %s", pct, cond))
    end
    local tpos = upper3(self.state.targetPos)
    self.targetPosLabel:echo(tpos)
    self.targetPosLabel:setStyleSheet(tpos ~= "" and tpos ~= "STA" and self.styles.posAlert or self.styles.pos)
  else
    self.targetNameLabel:echo("No Target")
    self.targetNameLabel:setStyleSheet(self.styles.targetName)
    self.targetPosLabel:echo("")
    self.targetPosLabel:setStyleSheet(self.styles.pos)
    self.targetHpGauge.front:setStyleSheet(self.gaugeStyles.targetFront)
    self.targetHpGauge.back:setStyleSheet(self.gaugeStyles.targetBack)
    self.targetHpGauge:setValue(0, 100, "")
  end
end

-- Find group member by name and update assist target info
function ArjUI:updateAssistTarget()
  local assistName = self.state.assistTarget
  if not assistName then return end
  
  local members = self.state.group or {}
  for _, mem in ipairs(members) do
    local name = mem.name or ""
    if name:lower() == assistName:lower() or name:lower():find(assistName:lower()) then
      self.state.tank = mem.name
      self.state.tankHp = toNum(pick(mem, "hp", "health"))
      self.state.tankMaxHp = toNum(pick(mem, "maxHp", "maxhp", "max_health"))
      self.state.tankPos = mem.position
      self.state.tankCond = mem.condition or mem.health_desc
      return
    end
  end
end

function ArjUI:renderTank()
  local s = self.state
  
  -- If someone else is tanking (from combat prompt T:), show their info
  if not s.iAmTank and s.tank and s.tank ~= "" then
    local displayName = s.tank
    self.tankNameLabel:echo(displayName)
    self.tankNameLabel:setStyleSheet(self.styles.tankName)
    
    local tpos = upper3(s.tankPos)
    self.tankPosLabel:echo(tpos)
    self.tankPosLabel:setStyleSheet(tpos ~= "" and tpos ~= "STA" and self.styles.posAlert or self.styles.pos)
    
    -- Use tankHpPct from combat prompt condition parsing
    local pct = s.tankHpPct or 100
    local cond = s.tankCond or ""
    
    self.tankHpGauge.front:setStyleSheet(self:getHpBarStyle(pct))
    self.tankHpGauge:setValue(pct, 100, string.format("%d%% %s", pct, cond))
  else
    -- Show self (You) - I am the tank or no combat
    s.tank = self.playerName or "You"
    s.tankHp = s.hp
    s.tankMaxHp = s.hpmax
    s.tankPos = s.position
    s.iAmTank = true
    
    self.tankNameLabel:echo(s.tank or "You")
    self.tankNameLabel:setStyleSheet(self.styles.tankNameMe)
    
    local tpos = upper3(s.tankPos)
    self.tankPosLabel:echo(tpos)
    self.tankPosLabel:setStyleSheet(tpos ~= "" and tpos ~= "STA" and self.styles.posAlert or self.styles.pos)
    
    local thp = s.tankHp or s.hp or 0
    local tmax = s.tankMaxHp or s.hpmax or 1
    -- Handle negative HP (dying) - clamp to 0 for percentage but show actual value
    local displayHp = thp
    local pct = tmax > 0 and math.max(0, math.floor((thp / tmax) * 100)) or 0
    -- If HP is negative, show critical state
    if thp < 0 then pct = 0 end
    
    self.tankHpGauge.front:setStyleSheet(self:getHpBarStyle(pct))
    local hpText = string.format("HP %d/%d", displayHp, tmax)
    local pctText = string.format("%d%%", pct)
    self.tankHpGauge:setValue(math.max(0, thp), tmax, hpText .. "        " .. pctText)
  end
end

function ArjUI:clearGroupWidgets()
  for _, w in pairs(self.groupWidgets or {}) do
    if w.container then w.container:hide() end
  end
  self.groupWidgets = {}
end

function ArjUI:getGroupHpStyle(pct)
  if pct < 25 then
    return "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #6b1010,stop:0.5 #8b2020,stop:1 #6b1010); border: none; border-radius: 2px;"
  elseif pct < 50 then
    return "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #6b4010,stop:0.5 #8b5520,stop:1 #6b4010); border: none; border-radius: 2px;"
  elseif pct < 75 then
    return "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #4a6b10,stop:0.5 #608b20,stop:1 #4a6b10); border: none; border-radius: 2px;"
  else
    return "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #106b30,stop:0.5 #208b45,stop:1 #106b30); border: none; border-radius: 2px;"
  end
end

function ArjUI:renderGroup()
  self:clearGroupWidgets()
  local members = self.state.group or {}
  
  -- Styles
  local headerStyle = "background-color: transparent; color: #50c878; font-size: 10px; font-weight: bold; qproperty-alignment: 'AlignLeft';"
  local nameStyle = "background-color: transparent; color: #d0d0d0; font-size: 9px; font-weight: bold; qproperty-alignment: 'AlignLeft';"
  local posStyle = "background-color: transparent; color: #888888; font-size: 9px; qproperty-alignment: 'AlignRight';"
  local posAlertStyle = "background-color: transparent; color: #ff6666; font-size: 9px; font-weight: bold; qproperty-alignment: 'AlignRight';"
  local gaugeBack = "background-color: #08080c; border: 1px solid #153015; border-radius: 3px;"
  local mvFront = "background-color: qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #105050,stop:0.5 #207070,stop:1 #105050); border: none; border-radius: 2px;"
  local gaugeText = "color: #e0e0e0; font-size: 8px; font-weight: bold;"
  
  if #members == 0 then 
    local soloLabel = Geyser.Label:new({ name = "ArjUI_GroupSolo", x = "2%", y = "2%", width = "96%", height = "40%" }, self.groupContainer)
    soloLabel:setStyleSheet(headerStyle)
    soloLabel:echo("── Group ──\n\n(solo)\n\nType 'group <name>' to invite")
    self.groupWidgets.solo = { container = soloLabel }
    return 
  end
  
  -- Header
  local header = Geyser.Label:new({ name = "ArjUI_GroupHeader", x = "2%", y = "1%", width = "96%", height = "8%" }, self.groupContainer)
  header:setStyleSheet(headerStyle)
  local sizeText = tostring(self.state.groupSize or #members)
  if (self.state.groupMax or 0) > 0 then sizeText = sizeText .. "/" .. self.state.groupMax end
  header:echo("── Group (" .. sizeText .. ") ──")
  self.groupWidgets.header = { container = header }
  
  local yOffsetPct = 10  -- Start at 10% from top
  local rowHeightPct = math.min(15, 85 / math.max(#members, 1))  -- Dynamic row height based on member count
  
  for i, mem in ipairs(members) do
    local name = mem.name or "Unknown"
    local displayName = normalizeTargetName(name)
    local hp = toNum(pick(mem, "hp", "health", "hitpoints"))
    local maxHp = toNum(pick(mem, "maxHp", "maxhp", "max_health", "hpmax"))
    local pos = mem.position or "sta"
    local cond = mem.condition or mem.health_desc or ""
    
    -- Calculate HP% - use condition if no numeric HP available
    local hpPct
    if hp and maxHp and maxHp > 0 then
      hpPct = math.floor((hp / maxHp) * 100)
    elseif hp and hp > 0 and hp <= 100 then
      -- HP might already be a percentage
      hpPct = hp
    else
      hpPct = 100
    end
    
    local posUpper = (pos or ""):upper():sub(1,3)
    local isAlert = posUpper ~= "STA" and posUpper ~= ""
    local inRoom = (mem.inRoom ~= false)  -- Group.Status.members[].inRoom
    if mem.isNpc == true then displayName = displayName .. "*" end
    
    -- Container for this member (percentage-based positioning)
    local memContainer = Geyser.Container:new({ 
      name = "ArjUI_GroupMem_" .. i, 
      x = "2%", y = yOffsetPct .. "%", 
      width = "96%", height = rowHeightPct .. "%" 
    }, self.groupContainer)
    
    -- Name label (left)
    local nameLabel = Geyser.Label:new({ name = "ArjUI_GroupName_" .. i, x = 0, y = 0, width = "70%", height = "45%" }, memContainer)
    nameLabel:setStyleSheet(inRoom and nameStyle or nameStyle:gsub("#d0d0d0", "#707070"))
    nameLabel:echo(displayName:sub(1, 14))
    nameLabel:setClickCallback(function()
      self:showContextMenu(self:getContextMenuItems("players", name))
    end)
    nameLabel:setOnEnter(function() nameLabel:setCursor("PointingHand") end)
    nameLabel:setOnLeave(function() nameLabel:setCursor("Arrow") end)
    
    -- Position label (right)
    local posLabel = Geyser.Label:new({ name = "ArjUI_GroupPos_" .. i, x = "70%", y = 0, width = "30%", height = "45%" }, memContainer)
    posLabel:setStyleSheet(isAlert and posAlertStyle or posStyle)
    posLabel:echo(inRoom and ("[" .. posUpper .. "]") or "[AWAY]")
    
    -- HP gauge with condition text
    local hpGauge = Geyser.Gauge:new({ name = "ArjUI_GroupHP_" .. i, x = 0, y = "50%", width = "100%", height = "45%" }, memContainer)
    hpGauge.front:setStyleSheet(self:getGroupHpStyle(hpPct))
    hpGauge.back:setStyleSheet(gaugeBack)
    hpGauge.text:setStyleSheet(gaugeText)
    local hpText = cond ~= "" and string.format("%d%% %s", hpPct, cond) or string.format("HP %d%%", hpPct)
    hpGauge:setValue(hpPct, 100, hpText)
    
    self.groupWidgets[i] = { 
      container = memContainer, 
      nameLabel = nameLabel, 
      posLabel = posLabel,
      hpGauge = hpGauge
    }
    
    yOffsetPct = yOffsetPct + rowHeightPct + 1
  end
end

-- TAB SWITCHING
function ArjUI:switchTab(tabName)
  if self.activeTab == tabName then
    -- If clicking same tab, refresh the data
    self:requestTabData(tabName)
    return
  end
  
  -- Hide current panel
  if self.tabPanels[self.activeTab] then
    self.tabPanels[self.activeTab]:hide()
  end
  
  -- Show new panel
  self.activeTab = tabName
  if self.tabPanels[tabName] then
    self.tabPanels[tabName]:show()
  end
  
  self:updateTabStyles()
  self:renderActiveTab()
  
  -- Auto-request data if tab is empty
  local hasData = false
  if tabName == "stats" then hasData = self.state.statsRaw and #self.state.statsRaw > 0
  elseif tabName == "skills" then hasData = self.state.skillsRaw and #self.state.skillsRaw > 0
  elseif tabName == "inv" then hasData = self.state.invRaw and #self.state.invRaw > 0
  elseif tabName == "eq" then hasData = self.state.eqRaw and #self.state.eqRaw > 0
  elseif tabName == "group" then hasData = true  -- Group always has data from GMCP
  end
  
  if not hasData then
    self:requestTabData(tabName)
  end
end

function ArjUI:updateTabStyles()
  local activeStyle = "background-color: #16140f; border: 1px solid #5a4b37; border-top: 1px solid #8c6e46; border-bottom: none; color: #e6e6e6; font-size: 8px; font-weight: bold;"
  local inactiveStyle = "background-color: #0a0908; border: 1px solid #3c3832; color: #706050; font-size: 8px;"
  
  for name, btn in pairs(self.tabButtons) do
    if name == self.activeTab then
      btn:setStyleSheet(activeStyle)
    else
      btn:setStyleSheet(inactiveStyle)
    end
  end
end

-- CHAT TAB SWITCHING
function ArjUI:switchChatTab(tabName)
  if self.activeChatTab == tabName then return end
  
  -- Hide current panel
  if self.chatPanels[self.activeChatTab] then
    self.chatPanels[self.activeChatTab]:hide()
  end
  
  -- Show new panel
  self.activeChatTab = tabName
  if self.chatPanels[tabName] then
    self.chatPanels[tabName]:show()
  end
  
  self:updateChatTabStyles()
end

function ArjUI:updateChatTabStyles()
  local activeStyle = "background-color: #16140f; border: 1px solid #5a4b37; border-top: 1px solid #8c6e46; border-bottom: none; color: #e6e6e6; font-size: 7px; font-weight: bold;"
  local inactiveStyle = "background-color: #0a0908; border: 1px solid #3c3832; color: #706050; font-size: 7px;"
  
  for name, btn in pairs(self.chatTabs) do
    if name == self.activeChatTab then
      btn:setStyleSheet(activeStyle)
    else
      btn:setStyleSheet(inactiveStyle)
    end
  end
end

function ArjUI:renderActiveTab()
  if self.activeTab == "group" then
    self:renderGroup()
  elseif self.activeTab == "stats" then
    self:renderStats()
  elseif self.activeTab == "inv" then
    self:renderInventory()
  elseif self.activeTab == "eq" then
    self:renderEq()
  elseif self.activeTab == "who" then
    self:renderWho()
  end
end

function ArjUI:renderStats()
  self.statsBox:clear()
  local s = self.state
  self.statsBox:cecho("<dim_gray>── Live Stats ──\n\n")
  -- Identity (Char.Status: sent on login and level change)
  if self.playerName or s.charLevel then
    local ident = self.playerName or "You"
    if s.charLevel then ident = ident .. string.format(" <dim_gray>L<white>%d", s.charLevel) end
    if s.charClass and s.charClass ~= "" then ident = ident .. " <gold>" .. s.charClass end
    if s.charRace and s.charRace ~= "" then ident = ident .. " <dim_gray>(" .. s.charRace .. ")" end
    self.statsBox:cecho("<white>" .. ident .. "\n")
    if s.charGuild and s.charGuild ~= "" then
      self.statsBox:cecho("<dim_gray>Guild: <dark_orange>" .. s.charGuild .. "\n")
    end
    self.statsBox:cecho("\n")
  end
  self.statsBox:cecho(string.format("<medium_sea_green>HP: <white>%d<dim_gray>/<white>%d\n", s.hp or 0, s.hpmax or 0))
  if s.usesMana == false then
    self.statsBox:cecho("<steel_blue>Mana: <dim_gray>n/a\n")
  else
    self.statsBox:cecho(string.format("<steel_blue>Mana: <white>%d<dim_gray>/<white>%d\n", s.mana or 0, s.manamax or 0))
  end
  self.statsBox:cecho(string.format("<khaki>Move: <white>%d<dim_gray>/<white>%d\n", s.move or 0, s.movemax or 0))
  self.statsBox:cecho(string.format("<medium_orchid>TNL: <white>%d\n", s.tnl or 0))
  self.statsBox:cecho(string.format("<dim_gray>Position: <white>%s\n", s.position or "unknown"))
  if s.fighting then
    self.statsBox:cecho(string.format("<dim_gray>Fighting: <indian_red>%s\n", s.fighting))
  end
  -- Coins (Char.Vitals: platinum/gold/silver/copper)
  local c = s.coins or {}
  self.statsBox:cecho(string.format("<dim_gray>Coins: <white>%dp <gold>%dg <light_gray>%ds <sandy_brown>%dc\n",
    c.platinum or 0, c.gold or 0, c.silver or 0, c.copper or 0))
  self.statsBox:cecho(string.format("<dim_gray>Area: <cyan>%s\n", s.area or "Unknown"))
  self.statsBox:cecho(string.format("<dim_gray>Room: <white>%s\n", s.room or "Unknown"))
  -- Quest (Quest.Status)
  local q = s.quest
  if q then
    local line
    if q.type == "kill" and q.killRequired then
      line = string.format("Kill %s <dim_gray>(%d/%d)", q.target, q.killCount or 0, q.killRequired)
    elseif q.type == "ask" then
      line = "Ask " .. q.target
    else
      line = q.target
    end
    if q.remaining then line = line .. string.format(" <dim_gray>(%d more today)", q.remaining) end
    if q.mapBought then line = line .. " <dim_gray>[map]" end
    self.statsBox:cecho("\n<dim_gray>Quest: <gold>" .. line .. "\n")
  end
  self.statsBox:cecho("\n<dim_gray>Click tab to send 'stat'\n")
end

function ArjUI:renderInventory()
  self.invBox:clear()
  local inv = self.state.inventory
  
  if inv and inv.lines and #inv.lines > 0 then
    if inv.header then
      self.invBox:decho("<128,128,128>" .. stripColors(inv.header) .. "\n\n")
    end
    for _, itemLine in ipairs(inv.lines) do
      local coloredLine = durisToDecho(itemLine)
      self.invBox:decho(coloredLine .. "\n")
    end
  else
    self.invBox:cecho("<dim_gray>── Inventory ──\n\n")
    self.invBox:cecho("<dim_gray>(click tab to refresh)\n")
  end
end

function ArjUI:renderEq()
  self.eqBox:clear()
  local eq = self.state.equipment
  
  if eq and eq.lines and #eq.lines > 0 then
    self.eqBox:decho("<128,128,128>── Equipment ──\n\n")
    for _, eqLine in ipairs(eq.lines) do
      local coloredLine = durisToDecho(eqLine)
      self.eqBox:decho(coloredLine .. "\n")
    end
  else
    self.eqBox:cecho("<dim_gray>── Equipment ──\n\n")
    self.eqBox:cecho("<dim_gray>(click tab to refresh)\n")
  end
end

function ArjUI:renderWho()
  self.whoBox:clear()
  local who = self.state.whoList
  
  if who and who.lines and #who.lines > 0 then
    self.whoBox:decho("<128,128,128>── Who's Online ──\n\n")
    for _, whoLine in ipairs(who.lines) do
      local coloredLine = durisToDecho(whoLine)
      self.whoBox:decho(coloredLine .. "\n")
    end
  else
    self.whoBox:cecho("<dim_gray>── Who's Online ──\n\n")
    self.whoBox:cecho("<dim_gray>(click tab to refresh)\n")
  end
end

function ArjUI:renderAffects()
  -- Render buffs (positive affects) to buffsBox
  self.buffsBox:clear()
  -- Render debuffs (negative affects) to debuffsBox  
  self.debuffsBox:clear()
  
  local affects = self.state.affects or {}
  local buffs = {}
  local debuffs = {}
  
  -- Known debuff patterns (negative effects)
  local debuffPatterns = {
    "blind", "poison", "curse", "disease", "plague", "slow", "weak", 
    "fear", "stun", "paralyze", "silence", "confuse", "charm", "sleep",
    "bleed", "burn", "frost", "shock", "drain", "doom", "hex", "jinx"
  }
  
  local function isDebuff(name)
    local lower = name:lower()
    for _, pattern in ipairs(debuffPatterns) do
      if lower:find(pattern) then return true end
    end
    return false
  end
  
  -- Process affects into buffs/debuffs
  local function processAffect(name, duration)
    if type(name) ~= "string" then return end
    local entry = { name = name, duration = duration }
    if isDebuff(name) then
      table.insert(debuffs, entry)
    else
      table.insert(buffs, entry)
    end
  end
  
  if #affects > 0 then
    for _, aff in ipairs(affects) do
      local name = aff.name or aff
      local duration = aff.duration or aff.time or aff.remaining
      processAffect(name, duration)
    end
  else
    for name, info in pairs(affects) do
      local duration = type(info) == "table" and info.duration or (type(info) == "number" and info or nil)
      processAffect(name, duration)
    end
  end
  
  -- Render buffs in horizontal flow (columns)
  -- Format: "name (Xm)" with proper spacing between items
  local maxCols = 2    -- 2 columns with good spacing
  local colWidth = 18  -- wider columns for readability
  
  if #buffs == 0 then
    self.buffsBox:cecho("<dim_gray>(none)\n")
  else
    local col = 0
    for _, buff in ipairs(buffs) do
      local mins = buff.duration and tonumber(buff.duration) and math.floor(tonumber(buff.duration) / 60) or nil
      local text
      if mins and mins > 0 then
        local name = buff.name:sub(1, 10)  -- truncate name to 10 chars
        text = string.format("%s (%dm)", name, mins)
      else
        text = buff.name:sub(1, 14)
      end
      -- Pad to column width with space between columns
      text = text .. string.rep(" ", math.max(1, colWidth - #text))
      self.buffsBox:cecho(string.format("<medium_sea_green>%s", text))
      col = col + 1
      if col >= maxCols then
        self.buffsBox:echo("\n")
        col = 0
      end
    end
    if col > 0 then self.buffsBox:echo("\n") end
  end
  
  -- Render debuffs in horizontal flow (columns)
  if #debuffs == 0 then
    self.debuffsBox:cecho("<dim_gray>(none)\n")
  else
    local col = 0
    for _, debuff in ipairs(debuffs) do
      local mins = debuff.duration and tonumber(debuff.duration) and math.floor(tonumber(debuff.duration) / 60) or nil
      local text
      if mins and mins > 0 then
        local name = debuff.name:sub(1, 10)  -- truncate name to 10 chars
        text = string.format("%s (%dm)", name, mins)
      else
        text = debuff.name:sub(1, 14)
      end
      -- Pad to column width with space between columns
      text = text .. string.rep(" ", math.max(1, colWidth - #text))
      self.debuffsBox:cecho(string.format("<indian_red>%s", text))
      col = col + 1
      if col >= maxCols then
        self.debuffsBox:echo("\n")
        col = 0
      end
    end
    if col > 0 then self.debuffsBox:echo("\n") end
  end
end

function ArjUI:renderTime()
  if not self.timeLabel then return end
  local t = self.state.timeOfDay or "day"
  local icon, color, text
  if t == "day" then
    icon, color, text = "☀", "#e0c060", "Day"
  elseif t == "night" then
    icon, color, text = "☾", "#8080c0", "Night"
  elseif t == "dawn" then
    icon, color, text = "🌅", "#e0a060", "Dawn"
  elseif t == "dusk" then
    icon, color, text = "🌇", "#c08060", "Dusk"
  else
    icon, color, text = "☀", "#a0a0b0", "Day"
  end
  self.timeLabel:setStyleSheet(string.format(
    "background-color: transparent; color: %s; font-size: 10px; qproperty-alignment: 'AlignCenter';", color))
  self.timeLabel:echo(icon .. " " .. text)
end

function ArjUI:renderAll()
  self:renderVitals()
  self:renderTNLBar()
  self:renderRoom()
  self:renderMobs()
  self:renderItems()
  self:renderPlayers()
  self:renderTarget()
  self:renderTank()
  self:renderGroup()
  self:renderAffects()
  self:renderTellContacts()
  self:renderTime()
end

-- ============================================================
-- COMMAND OUTPUT CAPTURE SYSTEM
-- ============================================================
-- Capture system for inv/eq/who output using registerAnonymousEventHandler
function ArjUI:setupCaptureTriggers()
  -- Use sysDataSendRequest to detect when we send commands, then capture output
  -- Instead, we'll use a line-by-line approach with the main trigger system
  
  -- Kill any existing capture triggers
  if self.captureTriggerIds then
    for _, id in ipairs(self.captureTriggerIds) do
      killTrigger(id)
    end
  end
  self.captureTriggerIds = {}
  
  -- Inventory header trigger
  local invId = tempTrigger("You are carrying:", function()
    ArjUI.state.invCapture = { lines = {}, header = matches[1] or line }
    ArjUI.state.capturing = "inv"
    ArjUI.state.captureCount = 0
    ArjUI.state.capturedLines = {}  -- Reset dedup hash
  end)
  table.insert(self.captureTriggerIds, invId)
  
  -- Equipment header trigger
  local eqId = tempTrigger("You are using:", function()
    ArjUI.state.eqCapture = { lines = {}, header = matches[1] or line }
    ArjUI.state.capturing = "eq"
    ArjUI.state.captureCount = 0
    ArjUI.state.capturedLines = {}  -- Reset dedup hash
  end)
  table.insert(self.captureTriggerIds, eqId)
  
  -- Who header trigger
  local whoId = tempTrigger("Listing of the Gods", function()
    ArjUI.state.whoCapture = { lines = {} }
    ArjUI.state.capturing = "who"
    ArjUI.state.captureCount = 0
    ArjUI.state.capturedLines = {}  -- Reset dedup hash
  end)
  table.insert(self.captureTriggerIds, whoId)
  
  -- Generic line capture - fires on every line when capturing
  -- Use a hash to prevent duplicates
  local lineId = tempRegexTrigger(".+", function()
    if not ArjUI.state.capturing then return end
    local currentLine = matches[1] or line
    
    -- Skip if we've already seen this exact line in this capture session
    ArjUI.state.capturedLines = ArjUI.state.capturedLines or {}
    if ArjUI.state.capturedLines[currentLine] then return end
    
    -- Check for prompt (end of capture)
    if currentLine:match("^%s*<%s*%d+h") then
      if ArjUI.state.captureCount and ArjUI.state.captureCount > 0 then
        ArjUI:finishCapture()
      end
      return
    end
    
    -- Capture based on type
    if ArjUI.state.capturing == "inv" then
      if currentLine:match("^a ") or currentLine:match("^an ") or currentLine:match("^some ") or currentLine:match("^the ") or currentLine:match("^%d+ ") then
        ArjUI.state.capturedLines[currentLine] = true
        table.insert(ArjUI.state.invCapture.lines, currentLine)
        ArjUI.state.captureCount = (ArjUI.state.captureCount or 0) + 1
      end
    elseif ArjUI.state.capturing == "eq" then
      if currentLine:match("^<[^>]+>") then
        ArjUI.state.capturedLines[currentLine] = true
        table.insert(ArjUI.state.eqCapture.lines, currentLine)
        ArjUI.state.captureCount = (ArjUI.state.captureCount or 0) + 1
      end
    elseif ArjUI.state.capturing == "who" then
      -- Capture player lines [level class], listing headers, counts, etc.
      if currentLine:match("^%s*%[") or currentLine:match("^Listing of the Mortals") or 
         currentLine:match("^There are %d+") or currentLine:match("^Total visible") or 
         currentLine:match("^Record number") or currentLine:match("^<None>") or
         currentLine:match("^There are .* online") then
        ArjUI.state.capturedLines[currentLine] = true
        table.insert(ArjUI.state.whoCapture.lines, currentLine)
        ArjUI.state.captureCount = (ArjUI.state.captureCount or 0) + 1
      end
    end
  end)
  table.insert(self.captureTriggerIds, lineId)
  
  -- Outgoing tell capture removed - GMCP handles outgoing tells via "You -> PlayerName" format
  -- No need for text trigger since GMCP Comm.Channel already captures both incoming and outgoing
end

-- Handle outgoing tells (sent by player)
function ArjUI:handleOutgoingTell(target, text)
  local name = target:lower()
  local displayName = target:sub(1,1):upper() .. target:sub(2):lower()
  
  -- Add to contacts
  self:addTellContact(displayName)
  
  -- Add message to history as outgoing
  self:addPrivateChatMessage(name, "You", text, true)
end

function ArjUI:finishCapture()
  local captureType = self.state.capturing
  self.state.capturing = nil
  
  if captureType == "inv" then
    self.state.inventory = self.state.invCapture
    self:renderInventory()
  elseif captureType == "eq" then
    self.state.equipment = self.state.eqCapture
    self:renderEq()
  elseif captureType == "who" then
    self.state.whoList = self.state.whoCapture
    self:renderWho()
  end
end

-- Request data when clicking on a tab - sends command to main console
function ArjUI:requestTabData(tabName)
  if tabName == "stats" then
    send("stat")
  elseif tabName == "who" then
    send("who")
  elseif tabName == "inv" then
    send("inv")
  elseif tabName == "eq" then
    send("eq")
  end
end

-- ============================================================
-- ROUTEALL TRIGGER & ALIASES
-- ============================================================

function ArjUI:setupRouteAll()
  -- Kill existing routeall trigger if any
  if self.routeAllTriggerId then
    pcall(function() killTrigger(self.routeAllTriggerId) end)
    self.routeAllTriggerId = nil
  end
  -- Also kill by name in case it persists
  if exists("ArjUI_RouteAll", "trigger") > 0 then
    pcall(function() killTrigger("ArjUI_RouteAll") end)
  end
  -- Kill event handler if exists
  if self.routeAllHandler then
    pcall(function() killAnonymousEventHandler(self.routeAllHandler) end)
    self.routeAllHandler = nil
  end
  
  -- Create a regex trigger that matches every line
  -- Pattern "^.*$" matches entire line (same as working manual trigger)
  self.routeAllTriggerId = tempRegexTrigger("^.*$", function()
    if ArjUI and ArjUI.console then
      selectCurrentLine()
      copy()
      appendBuffer("ArjUI_Console")
      deleteLine()
    end
  end)
end

function ArjUI:setupAliases()
  -- Kill existing aliases if any
  if self.uiOnAlias then pcall(function() killAlias(self.uiOnAlias) end) end
  if self.uiOffAlias then pcall(function() killAlias(self.uiOffAlias) end) end
  if self.debugAlias then pcall(function() killAlias(self.debugAlias) end) end
  
  -- ui on - reinitialize the UI
  self.uiOnAlias = tempAlias("^ui on$", function()
    ArjUI:init()
    ArjUI:setupCaptureTriggers()
    ArjUI:setupRouteAll()
    cecho("<green>[ArjUI]<reset> UI enabled.\n")
  end)
  
  -- ui off - kill the UI and restore default Mudlet
  self.uiOffAlias = tempAlias("^ui off$", function()
    ArjUI:kill()
    cecho("<yellow>[ArjUI]<reset> UI disabled. Type 'ui on' to re-enable.\n")
  end)
  
  -- ui debug - show GMCP data status in ArjUI console
  self.debugAlias = tempAlias("^ui debug$", function()
    if ArjUI and ArjUI.console then
      ArjUI.console:cecho("\n<gold>══ GMCP Debug Info ══<reset>\n")
      ArjUI.console:cecho("<cyan>Char.Vitals:<reset> " .. (gmcp and gmcp.Char and gmcp.Char.Vitals and "YES" or "NO") .. "\n")
      ArjUI.console:cecho("<cyan>Char.Status:<reset> " .. (gmcp and gmcp.Char and gmcp.Char.Status and "YES" or "NO") .. "\n")
      ArjUI.console:cecho("<cyan>Char.Affects:<reset> " .. (gmcp and gmcp.Char and gmcp.Char.Affects and "YES" or "NO") .. "\n")
      ArjUI.console:cecho("<cyan>Room.Info:<reset> " .. (gmcp and gmcp.Room and gmcp.Room.Info and "YES" or "NO") .. "\n")
      ArjUI.console:cecho("<cyan>Group.Status:<reset> " .. (gmcp and gmcp.Group and gmcp.Group.Status and "YES" or "NO") .. "\n")
      if gmcp and gmcp.Char and gmcp.Char.Affects then
        local count = 0
        if type(gmcp.Char.Affects) == "table" then
          for _ in pairs(gmcp.Char.Affects) do count = count + 1 end
        end
        ArjUI.console:cecho("<cyan>Affects count:<reset> " .. count .. "\n")
      end
      ArjUI.console:cecho("<cyan>initialDataRequested:<reset> " .. tostring(ArjUI.initialDataRequested) .. "\n")
      ArjUI.console:cecho("<gold>═══════════════════════<reset>\n\n")
    end
  end)
end

-- ============================================================
-- BOOT
-- ============================================================

-- Auto-initialize on script load
ArjUI:init()
ArjUI:setupCaptureTriggers()
ArjUI:setupRouteAll()
ArjUI:setupAliases()