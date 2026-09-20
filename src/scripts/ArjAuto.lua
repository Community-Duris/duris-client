-- ArjAuto (Mudlet 4.19.1)
-- Automation and utility aliases for New Duris, adapted from the community
-- "lielz scripts" collection (2015-2024). Every automatic behaviour is OFF
-- until switched on with `auto <name> on`; the setting is remembered.
-- Type `auto` for help.

ArjAuto = ArjAuto or {}
ArjAuto.triggers = ArjAuto.triggers or {}
ArjAuto.aliases = ArjAuto.aliases or {}
ArjAuto.keys = ArjAuto.keys or {}
ArjAuto.timers = ArjAuto.timers or {}

-- ============================================================
-- PERSISTENCE
-- ============================================================

ArjAuto.toggleDefaults = {
  autoStand   = false, -- stand up after being knocked down, and when mem/pray finishes
  autoGroup   = false, -- 'group <name>' when someone gives you consent
  autoRescue  = false, -- rescue people on your rescue list when they are attacked
  autoAssist  = false, -- assist a group member who gets attacked while you are idle
  autoRage    = false, -- re-cast rage in combat when it abates (berserker)
  autoWield   = false, -- re-wield your weapon after being disarmed
  autoLoot    = false, -- take coins and essence from the corpse after a kill
  autoOre     = false, -- pick up ore and gems after mining
  autoFollow  = false, -- follow and consent when someone beckons you
  autoPlay    = false, -- bard: restart your song when it ends or fails
  trapKill    = false, -- order followers to kill enemies that dim/shadow in or enter the game
  scanReport  = false, -- send scan summaries to the report channel
  eventReport = false, -- send tracks, spell hits, scry and ship contact alerts to the report channel
  shipKeys    = false, -- Ctrl+F/P/S/R fire, Ctrl+Shift+letters for headings, F10-F12 speed
  roller      = false, -- character creation: reroll until the stat score threshold is met
}

ArjAuto.varDefaults = {
  target = "", container = "bag", food = "", weapon = "", held = "", door = "door",
  tank = "", spam = "", cargo = "0", contra = "0", song = "", healtarget = "",
  idscroll = "", channel = "echo", spamInterval = "1", scanInterval = "5",
  contactsInterval = "2", rollThreshold = "20.5",
}

function ArjAuto:path() return getMudletHomeDir() .. "/arjauto.json" end

function ArjAuto:load()
  self.settings = {}
  for k, v in pairs(self.toggleDefaults) do self.settings[k] = v end
  self.vars = {}
  for k, v in pairs(self.varDefaults) do self.vars[k] = v end
  self.rescueList = {}
  self.bidScores = {}
  self.loginCommands = {}
  local f = io.open(self:path(), "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(yajl.to_value, content)
  if not ok or type(data) ~= "table" then return end
  for k, v in pairs(data.settings or {}) do
    if self.toggleDefaults[k] ~= nil then self.settings[k] = (v == true) end
  end
  for k, v in pairs(data.vars or {}) do
    if self.varDefaults[k] ~= nil then self.vars[k] = tostring(v) end
  end
  if type(data.rescueList) == "table" then self.rescueList = data.rescueList end
  if type(data.bidScores) == "table" then self.bidScores = data.bidScores end
  if type(data.loginCommands) == "table" then self.loginCommands = data.loginCommands end
end

function ArjAuto:save()
  local ok, json = pcall(yajl.to_string, {
    settings = self.settings, vars = self.vars, rescueList = self.rescueList,
    bidScores = self.bidScores, loginCommands = self.loginCommands,
  })
  if not ok then return end
  local f = io.open(self:path(), "w")
  if f then f:write(json); f:close() end
end

-- ============================================================
-- HELPERS
-- ============================================================

local function note(text)
  if ArjUI and ArjUI.note then ArjUI:note(text) else cecho(text .. "<reset>\n") end
end

local function on(name) return ArjAuto.settings and ArjAuto.settings[name] == true end

local function var(name)
  local v = ArjAuto.vars and ArjAuto.vars[name]
  if v == nil or v == "" then return nil end
  return v
end

local function inCombat()
  return ArjUI and ArjUI.state and ArjUI.state.fighting ~= nil
end

local function standing()
  local p = ArjUI and ArjUI.state and ArjUI.state.position
  return p == nil or p == "standing"
end

local function myName()
  return (ArjUI and ArjUI.playerName) or ""
end

-- Names of player members of the current group (GMCP Group.Status)
local function groupMembers()
  local out = {}
  local members = ArjUI and ArjUI.state and ArjUI.state.group or {}
  for _, m in ipairs(members) do
    if m.name and m.isNpc ~= true then table.insert(out, m) end
  end
  return out
end

local function isGroupMember(name)
  if not name then return false end
  local n = name:lower()
  for _, m in ipairs(groupMembers()) do
    if (m.name or ""):lower() == n then return true end
  end
  return false
end

local function firstWord(s)
  return (tostring(s or ""):match("^(%S+)") or "")
end

local function addTrigger(pattern, fn)
  local id = tempRegexTrigger(pattern, fn)
  table.insert(ArjAuto.triggers, id)
  return id
end

local function addAlias(pattern, fn)
  local id = tempAlias(pattern, fn)
  table.insert(ArjAuto.aliases, id)
  return id
end

local function setVar(name, value)
  ArjAuto.vars[name] = value or ""
  ArjAuto:save()
  note(string.format("<cyan>[auto] %s = <white>%s", name, value ~= "" and value or "(cleared)"))
end

-- Send output to the configured report channel
function ArjAuto:report(text)
  local ch = var("channel") or "echo"
  if ch == "echo" then
    note("<light_gray>[report] " .. text)
  else
    send(ch .. " " .. text, false)
  end
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function ArjAuto:kill()
  for _, id in ipairs(self.triggers) do pcall(function() killTrigger(id) end) end
  for _, id in ipairs(self.aliases) do pcall(function() killAlias(id) end) end
  for _, id in ipairs(self.keys) do pcall(function() killKey(id) end) end
  for _, id in pairs(self.timers) do pcall(function() killTimer(id) end) end
  self.triggers, self.aliases, self.keys, self.timers = {}, {}, {}, {}
  for _, h in ipairs(self.handlers or {}) do pcall(function() killAnonymousEventHandler(h) end) end
  self.handlers = {}
end

function ArjAuto:init()
  self:kill()
  self:load()
  self.rescueLocked = false
  self.rebash = { generic = false, target = false, inLag = false }
  self.fleeStabArmed = false
  self.split = { bids = {}, dice = {}, pending = 0, caught = 0, result = 0, spend = false }
  self.idString = nil
  self.epic = { completed = {}, canReport = false, last = nil, lastAt = nil }
  self.roll = { score = 0, count = 0, best = 0 }
  self:setupCombatTriggers()
  self:setupGroupTriggers()
  self:setupUtilityTriggers()
  self:setupShipTriggers()
  self:setupSplitTriggers()
  self:setupIdTriggers()
  self:setupEpicTriggers()
  self:setupRollerTriggers()
  self:setupLoginTriggers()
  self:setupAliases()
  self:setupKeys()
end

-- ============================================================
-- COMBAT AUTOMATION
-- ============================================================

function ArjAuto:setupCombatTriggers()
  -- Auto stand: knocked down or finished memming/praying
  local standPatterns = {
    "^As (.*?) avoids your bash, you topple over and fall to the ground\\.$",
    "In your haste to slam people around, you slip and fall!",
    "^Unfortunately\\. (.*?) grabs your leg and yanks you down to the ground!$",
    "You manage with complete incompetence to throw yourself head first into the ground!",
    "avoids your maul, and you become FURIOUS when you hit the ground!",
    "^You are knocked to the ground",
    "You stagger and fall to your knees!",
    "The powerful sweep sends you crashing to the ground!",
    "The wave slams into you, knocking you off your feet!",
    "mighty kick sends you crashing",
    "^You slam up against (.+)$",
    "^Your prayers are complete\\.$",
    "^Your studies are complete\\.$",
    "^You snap out of your meditative trance, memorization complete\\.$",
    "^You feel fully infused\\.\\.\\.$",
  }
  for _, p in ipairs(standPatterns) do
    addTrigger(p, function()
      if on("autoStand") then send("stand", false) end
    end)
  end
  addTrigger("^You leap at (.+) only to realize he is down already\\.$", function()
    note("<white:red> ══ TARGET ALREADY DOWN ══")
  end)
  addTrigger("You fly right over your target and land on your head!", function()
    note("<white:red> ══ TARGET ALREADY DOWN ══")
  end)
  addTrigger("^You make a futile attempt (.*?), but \\w+ is simply immovable\\.$", function()
    note("<blue:yellow> ══ CANNOT TAKE THIS DOWN ══")
  end)

  -- Auto rage (berserker)
  addTrigger("^You feel yourself return to normal as your rage abates\\.$", function()
    if on("autoRage") and inCombat() then
      tempTimer(3, function() if on("autoRage") and inCombat() then send("rage", false) end end)
    end
  end)

  -- Auto wield after disarm
  addTrigger("(?:knocks your weapon from your grasp!|forces your weapon out of your hands with a fancy disarming maneuver\\.|You make a grave error in judgement, and lose control of your weapon\\.)", function()
    if on("autoWield") and var("weapon") then
      send("get " .. var("weapon"), false)
      send("wield " .. var("weapon"), false)
    end
  end)

  -- Rebash: after a successful bash there is ~14 s of reorient lag; queue a bash for when it ends
  addTrigger("Your skillful bash knocks", function()
    local r = ArjAuto.rebash
    r.inLag = true
    r.generic, r.target = false, false
    if ArjAuto.timers.rebash then pcall(function() killTimer(ArjAuto.timers.rebash) end) end
    ArjAuto.timers.rebash = tempTimer(13.99, function()
      local rb = ArjAuto.rebash
      rb.inLag = false
      if rb.generic then
        note("<white:firebrick>[auto] Bash lag over. Bashing!")
        send("bash", false)
      elseif rb.target then
        note("<white:firebrick>[auto] Bash lag over. Bashing " .. (var("target") or "") .. "!")
        send("bash " .. (var("target") or ""), false)
      end
      rb.generic, rb.target = false, false
    end)
  end)

  -- Flee-stab: after `fls`, when we flee, return and backstab the target
  local opposite = { north = "south", south = "north", east = "west", west = "east", up = "down", down = "up",
    northwest = "southeast", northeast = "southwest", southeast = "northwest", southwest = "northeast" }
  addTrigger("^You flee (\\w+)ward!$", function()
    if not ArjAuto.fleeStabArmed then return end
    ArjAuto.fleeStabArmed = false
    local back = opposite[matches[2]]
    if back and var("target") then
      send(back, false)
      send("backstab " .. var("target"), false)
    end
  end)
  addTrigger("(?:PANIC!  You couldn't escape!|You scramble madly to your feet!)", function()
    ArjAuto.fleeStabArmed = false
  end)

  -- Auto loot after a kill
  addTrigger("^You receive your share of experience\\.$", function()
    if on("autoLoot") then
      send("get coins corpse", false)
      send("get essence corpse", false)
      if var("container") then send("put all.coins " .. var("container"), false) end
    end
  end)
  addTrigger("^Your mining efforts turn up ", function()
    if on("autoOre") then
      send("get ore", false)
      send("get gem", false)
      if var("container") then
        send("put ore " .. var("container"), false)
        send("put gem " .. var("container"), false)
      end
    end
  end)

  -- Traps: enemies arriving by dimension door, shadow travel, or logging in next to you
  local trapPatterns = {
    { "^A black rift in space opens next to you, and an? (.+) steps out of it grinning\\.$", 2 },
    { "^An odd looking shadow silently arrives and slowly forms into an? (.+)\\.$", 2 },
    { "^An? (.+) appears in a (.*) flash of light\\.$", 2 },
    { "^An? (.+) has entered the game\\.$", 2 },
    { "^Oof! an? (.+) bumps into", 2 },
  }
  for _, t in ipairs(trapPatterns) do
    addTrigger(t[1], function()
      if on("trapKill") then
        local who = firstWord(matches[t[2]])
        if who ~= "" then send("order followers kill " .. who, false) end
      end
    end)
  end

  -- Spell hits worth telling the group about
  addTrigger("^A blanketing shroud of negative energy coalesces around (.+)\\.\\.\\.$", function()
    if on("eventReport") then ArjAuto:report(matches[2] .. " is BLACKMANTLED!") end
  end)
  addTrigger("^A dark light decends upon (.*), returning its flames of hell back into the abyss\\.$", function()
    if on("eventReport") then ArjAuto:report(matches[2] .. " hellfire down!") end
  end)
  addTrigger("^There are (.+) tracks going (.+)\\.$", function()
    if on("eventReport") then ArjAuto:report(matches[2] .. " tracks going " .. matches[3]) end
  end)
  addTrigger("^You feel an icy eye watching you\\.$", function()
    if on("eventReport") then ArjAuto:report("Icy eye! Someone is scrying me.") end
  end)
  addTrigger("^(.+) has set off your frost beacon at (.+)$", function()
    if on("eventReport") then ArjAuto:report("Frost beacon: " .. matches[2] .. " at " .. matches[3]) end
  end)
end

-- ============================================================
-- GROUP AUTOMATION: consent, rescue, assist
-- ============================================================

function ArjAuto:setupGroupTriggers()
  addTrigger("^(.+?) has just given you (?:his|her|its) consent\\.$", function()
    if not on("autoGroup") then return end
    -- "A large dracolich has just given you its consent." -> group the last word
    local who = matches[2]
    local last = who:match("(%S+)$") or who
    send("group " .. last, false)
  end)
  addTrigger("^(.+?) is in another group\\.$", function()
    if on("autoGroup") then send("tell " .. matches[2] .. " You are in another group.", false) end
  end)
  addTrigger("^You have been kicked out of (.+)'s group\\.$", function() note("<red> ══ KICKED FROM GROUP ══") end)
  addTrigger("^You are now a member of (.+)'s group\\.$", function() note("<green> ══ JOINED " .. matches[2]:upper() .. "'S GROUP ══") end)

  addTrigger("^(.+) beckons you to follow (?:him|her) and consent\\.$", function()
    if on("autoFollow") then
      send("follow " .. matches[2], false)
      send("consent " .. matches[2], false)
    end
  end)

  -- Rescue: fire on lines that show a listed ally being attacked
  local function tryRescue(victim)
    if not on("autoRescue") or ArjAuto.rescueLocked then return end
    victim = firstWord(victim)
    if victim == "" or not ArjAuto.rescueList[victim:lower()] then return end
    if victim:lower() == myName():lower() then return end
    send("rescue " .. victim, false)
    ArjAuto.rescueLocked = true
    -- Safety net: unlock after 6 s even if no response line matched
    tempTimer(6, function() ArjAuto.rescueLocked = false end)
  end
  local hitVerbs = "(?:punch|slash|pierce|bludgeon|maul|claw|whip|pound|crush)"
  local rescuePatterns = {
    { "^(.*) " .. hitVerbs .. " (?:grazes|wounds|hits|strikes|enshrouds|causes) (\\w+)", 3 },
    { "^(.*) (?:powerful|awesome|devastating|decent|fine|impressive|mighty|feeble|weak|crude) " .. hitVerbs .. " (?:grievously wounds|seriously wounds|grazes|wounds|hits|strikes|enshrouds|causes) (\\w+)", 3 },
    { "^(.*) misses (\\w+)\\.", 3 },
    { "^(\\w+) (?:dodges|parries|blocks|deflects) (.+) (?:attack|blow|lunge)", 2 },
    { "^(.*) attacks (\\w+)\\.\\s+\\[\\d+ Hits\\]$", 3 },
    { "^(.*) suddenly attacks (\\w+)!$", 3 },
    { "^(.*) turns to focus (?:his|her|its) attack on (\\w+)!", 3 },
  }
  for _, rp in ipairs(rescuePatterns) do
    addTrigger(rp[1], function() tryRescue(matches[rp[2]]) end)
  end
  local function unlock(delay, why)
    if delay > 0 then
      tempTimer(delay, function() ArjAuto.rescueLocked = false end)
    else
      ArjAuto.rescueLocked = false
    end
    if on("autoRescue") and why then note("<dim_gray>[auto] " .. why) end
  end
  addTrigger("Banzai! To the rescue\\.\\.\\.", function() unlock(5, "Rescue lag out.") end)
  addTrigger("^You fail the rescue\\.$", function() unlock(2, "Rescue failed.") end)
  addTrigger("(?:Who do you want to rescue\\?|But nobody is fighting (?:him|her|it)\\?|How can you rescue someone you are trying to kill\\?|You clamber to your feet\\.|You rise to your feet\\.|blow shatters the magic paralyzing you!|The earthen fist finally releases its grip on you\\.)", function()
    unlock(0, nil)
  end)

  -- Auto assist: a group member hits something and we are not fighting
  addTrigger("^(\\w+)'s (?:(?:powerful|awesome|devastating|decent|fine|impressive|mighty|feeble|weak|crude) )?" .. hitVerbs .. " (?:grievously wounds|seriously wounds|grazes|wounds|hits|strikes|enshrouds|causes) (.+?)(?: in a mist of blood| to grimace in pain| very hard| hard)?\\.$", function()
    if not on("autoAssist") or inCombat() or ArjAuto.assistLocked then return end
    local attacker, victim = matches[2], matches[3]
    if isGroupMember(attacker) and not isGroupMember(firstWord(victim)) then
      send("assist " .. attacker, false)
      ArjAuto.assistLocked = true
      tempTimer(2, function() ArjAuto.assistLocked = false end)
    end
  end)
end

-- ============================================================
-- UTILITY TRIGGERS: bard, scan reporting
-- ============================================================

function ArjAuto:setupUtilityTriggers()
  addTrigger("(?:^You finish your song\\.$|^Uh oh\\.\\. how did the song go, anyway\\?$)", function()
    if on("autoPlay") then
      if var("song") then
        note("<cyan>[auto] Restarting song " .. var("song"))
        send("play " .. var("song"), false)
      else
        note("<red>[auto] autoPlay is on but no song is set. Use: song <name>")
      end
    end
  end)
end

-- Called by ArjUI after it summarises a scan (see ArjUI:summarizeScan)
function ArjAuto:onScanSummary(total, parts)
  if on("scanReport") and total > 0 then
    local zone = ArjUI and ArjUI.state and ArjUI.state.area or "?"
    ArjAuto:report(string.format("%d seen: %s | %s", total, table.concat(parts, ", "), zone))
  end
end

-- ============================================================
-- SHIP: polling timers, orders relative to the locked target
-- ============================================================

function ArjAuto:shipState()
  return ArjUI and ArjUI.state and ArjUI.state.ship or {}
end

function ArjAuto:targetContact()
  local s = self:shipState()
  if not s.target then return nil end
  local list = s.contacts
  if type(list) ~= "table" or #list == 0 then list = s.textContacts end
  for _, c in ipairs(list or {}) do
    if tostring(c.id) == tostring(s.target) then return c end
  end
  return nil
end

function ArjAuto:setupShipTriggers()
  addTrigger("^You recieve (.*?) for the salvage of (.*?)!$", function()
    ArjAuto:stopTimer("shipScan")
    if on("eventReport") then ArjAuto:report("Sunk " .. matches[3]) end
  end)
  addTrigger("^Locked onto \\[(.+)\\]: (.+)$", function()
    if on("eventReport") then ArjAuto:report("Locked: " .. matches[2] .. " " .. matches[3]) end
  end)
  addTrigger("^Passengers:\\s+2/", function() note("<red> ══ TWO PASSENGERS ABOARD ══") end)
  addTrigger("^You disembark this ship\\.$", function()
    ArjAuto:stopTimer("contacts"); ArjAuto:stopTimer("lookout"); ArjAuto:stopTimer("shipScan")
  end)
  addTrigger("^Your ship has completed docking procedures\\.$", function()
    ArjAuto:stopTimer("contacts")
  end)
  addTrigger("^The first officer reports everything is in order and the ship is ready to go\\.$", function()
    if ArjAuto.contactsWanted then ArjAuto:startTimer("contacts", tonumber(var("contactsInterval")) or 2, "look contacts") end
  end)
  addTrigger("No target locked\\. Syntax: Scan", function() ArjAuto:stopTimer("shipScan") end)
end

function ArjAuto:startTimer(name, interval, command, condition)
  self:stopTimer(name)
  interval = math.max(0.3, tonumber(interval) or 1)
  self.timers[name] = tempTimer(interval, function()
    if not ArjAuto.timers[name] then return end
    if condition == nil or condition() then send(command, false) end
  end, true)
  note(string.format("<cyan>[auto] %s timer on: '%s' every %gs", name, command, interval))
end

function ArjAuto:stopTimer(name, quiet)
  if self.timers[name] then
    pcall(function() killTimer(ArjAuto.timers[name]) end)
    self.timers[name] = nil
    if not quiet then note("<cyan>[auto] " .. name .. " timer off") end
  end
end

function ArjAuto:orderHeadingRelative(offset)
  local c = self:targetContact()
  local bearing = c and tonumber(c.bearing)
  if not bearing then note("<cyan>[auto] No locked target with a bearing. Lock on and look at contacts first.") return end
  local h = (bearing + offset) % 360
  send("order heading " .. h, false)
end

-- ============================================================
-- LOOT SPLIT (bidscore)
-- Group members `gsay bid`; `split roll` gives each bidder a dice range
-- sized by their bidscore (1-20), rolls, announces the winner and
-- deducts points from them. Scores persist between sessions.
-- ============================================================

local function gsay(text) send("gsay " .. text, false) end

function ArjAuto:setupSplitTriggers()
  addTrigger("^(\\w+) group-says.* 'bid'$", function()
    local sp = ArjAuto.split
    if not sp.collecting then return end
    local name = matches[2]
    for _, n in ipairs(sp.bids) do
      if n == name then gsay("No bidding twice, " .. name) return end
    end
    table.insert(sp.bids, name)
    note(string.format("<cyan>[split] %s bid (score %d)", name, ArjAuto:bidScore(name)))
    send("tell " .. name .. " bid received", false)
  end)
  addTrigger("^Result for.* roll #\\d+ of a (\\d+) sided die: (\\d+)\\.$", function()
    local sp = ArjAuto.split
    if sp.pending <= 0 then return end
    sp.result = sp.result + tonumber(matches[3])
    sp.caught = sp.caught + 1
    if sp.caught >= sp.pending then
      -- Summing several dice raises the floor by one per extra die; normalise back to 1..N
      sp.result = sp.result - sp.caught + 1
      sp.pending = 0
      ArjAuto:announceWinner()
    end
  end)
end

function ArjAuto:bidScore(name)
  local s = tonumber(self.bidScores[name]) or 1
  return math.max(1, math.min(20, s))
end

function ArjAuto:splitStart()
  self.split = { bids = {}, dice = {}, pending = 0, caught = 0, result = 0, spend = false, collecting = true }
  gsay("[SPLIT] Bidding open. gsay 'bid' to bid.")
end

function ArjAuto:splitRoll(free)
  local sp = self.split
  sp.collecting = false
  if #sp.bids == 0 then gsay("[SPLIT] No bids received.") return end
  sp.spend = not free
  sp.dice, sp.result, sp.caught = {}, 0, 0
  local total, ranges = 0, {}
  for _, name in ipairs(sp.bids) do
    local n = free and 1 or self:bidScore(name)
    local first = total + 1
    total = total + n
    for i = first, total do sp.dice[i] = name end
    table.insert(ranges, string.format("%s %d-%d", name, first, total))
  end
  gsay("[SPLIT] Ranges: " .. table.concat(ranges, ", "))
  local hundreds = math.floor(total / 100)
  if hundreds > 4 then note("<red>[split] Too many dice (max 500).") return end
  if hundreds > 0 then
    sp.pending = hundreds + 1
    send("dice " .. hundreds .. " 100", false)
    send("dice 1 " .. ((total % 100) + hundreds), false)
  else
    sp.pending = 1
    send("dice 1 " .. total, false)
  end
end

function ArjAuto:announceWinner()
  local sp = self.split
  local winner = sp.dice[sp.result]
  if not winner then gsay("[SPLIT] Roll " .. sp.result .. " matched nobody, roll again.") return end
  gsay(string.format("[SPLIT] Roll %d: WINNER %s", sp.result, winner))
  if sp.spend then
    local onePointers = 0
    for _, n in ipairs(sp.bids) do if self:bidScore(n) < 2 then onePointers = onePointers + 1 end end
    local cost = #sp.bids - onePointers
    self.bidScores[winner] = math.max(1, self:bidScore(winner) - cost)
    for _, n in ipairs(sp.bids) do
      if n ~= winner then self.bidScores[n] = math.min(20, self:bidScore(n) + 1) end
    end
    self:save()
    gsay(string.format("[SPLIT] %s spent %d bidscore. Others +1.", winner, cost))
  end
  self:splitScores()
  sp.bids = {}
end

function ArjAuto:splitScores()
  local names = {}
  for n in pairs(self.bidScores) do table.insert(names, n) end
  table.sort(names)
  local parts = {}
  for _, n in ipairs(names) do table.insert(parts, n .. ":" .. self:bidScore(n)) end
  if #parts == 0 then note("<cyan>[split] No bidscores recorded.") return end
  gsay("[SPLIT] Bidscores: " .. table.concat(parts, " "))
end

-- ============================================================
-- IDENTIFY: compact an identify readout into one shareable line
-- ============================================================

function ArjAuto:setupIdTriggers()
  addTrigger("^(.+) weighs .+ pounds and is worth roughly .+$", function()
    ArjAuto.idString = matches[2] .. " |"
  end)
  addTrigger("^(.*)$", function()
    local id = ArjAuto.idString
    if not id then return end
    local str = matches[2] or ""
    if str:find("weighs .+ pounds") then return end
    if str:find("^%s*$") then return end
    if str:find("The following abilities are granted") or str:find("This item also affects your") then return end
    str = str:gsub("protection against being slept", "!SLEEP")
      :gsub("protection against being summoned", "!SUMMON")
      :gsub("You mystically sense that this item will affect your AC", "AC")
      :gsub("You magically sense that the damage dice for this weapon are", "dice")
      :gsub("able to float on water", "FLOAT")
      :gsub("^%s+", ""):gsub("%s+$", "")
    ArjAuto.idString = id .. " " .. str
  end)
  addTrigger("^(.+) has an item value of .+", function()
    local id = ArjAuto.idString
    ArjAuto.idString = nil
    if not id then return end
    note("<gold>[ID] <white>" .. id)
    if var("channel") ~= "echo" then ArjAuto:report("[ID] " .. id) end
  end)
  addTrigger("^You cannot seem to glean any information about that item\\.$", function()
    ArjAuto.idString = nil
  end)
end

-- ============================================================
-- EPIC ZONES: remember which zones show as completed this boot
-- ============================================================

function ArjAuto:setupEpicTriggers()
  addTrigger("^Epic Zones -+$", function() ArjAuto.epic.capturing = true end)
  addTrigger("^\\s+\\*(.+?)\\s+\\((.+)\\)", function()
    local e = ArjAuto.epic
    if not e.capturing then return end
    local zone = matches[2]
    if not e.completed[zone] then
      e.completed[zone] = os.time()
      e.last, e.lastAt = zone, os.time()
      if e.canReport then
        note("<gold>[epic] " .. zone .. " has just been completed.")
        if on("eventReport") then ArjAuto:report(zone .. " has been done!") end
      end
    end
  end)
  addTrigger("^\\* = already completed this boot\\.$", function()
    ArjAuto.epic.capturing = false
    ArjAuto.epic.canReport = true
  end)
end

function ArjAuto:epicReport()
  local names = {}
  for n in pairs(self.epic.completed) do table.insert(names, n) end
  table.sort(names)
  if #names == 0 then note("<cyan>[epic] Nothing recorded yet. Type 'epic zones' first.") return end
  local text = "Completed zones: " .. table.concat(names, " | ")
  note("<gold>[epic] <white>" .. text)
  if var("channel") ~= "echo" then ArjAuto:report(text) end
  if self.epic.last then
    local ago = os.time() - self.epic.lastAt
    note(string.format("<dim_gray>[epic] Most recent: %s, noted %dm%02ds ago", self.epic.last, math.floor(ago / 60), ago % 60))
  end
end

-- ============================================================
-- STAT ROLLER (character creation)
-- ============================================================

function ArjAuto:setupRollerTriggers()
  local function score(stat)
    if stat:find("very good") then return 2, "<green>very good"
    elseif stat:find("excellent") then return 3.5, "<magenta>excellent"
    elseif stat:find("good") then return 0.5, "<yellow>good" end
    return 0, nil
  end
  addTrigger("^(Agility|Constitution|Dexterity|Strength):\\s+(.*?)\\s+(Wisdom|Charisma|Intelligence|Power):\\s+(.*)$", function()
    if not on("roller") then return end
    local r = ArjAuto.roll
    local a, la = score(matches[3])
    local b, lb = score(matches[5])
    r.score = r.score + a + b
    if la then note(la .. " " .. matches[2]) end
    if lb then note(lb .. " " .. matches[4]) end
  end)
  addTrigger("^Place your bonuses as you think will fit your playing style", function()
    if not on("roller") then return end
    local r = ArjAuto.roll
    local threshold = tonumber(var("rollThreshold")) or 20.5
    r.count = r.count + 1
    if r.score > r.best then r.best = r.score end
    note(string.format("<white:blue>Roll %d: score %.1f (threshold %.1f, best %.1f)", r.count, r.score, threshold, r.best))
    if r.score >= threshold then
      note("<green> ══ KEEPER: threshold met, roller stopped ══")
      ArjAuto.settings.roller = false
      ArjAuto:save()
    else
      send("y", false)
    end
    r.score = 0
  end)
end

-- ============================================================
-- LOGIN COMMANDS
-- ============================================================

function ArjAuto:setupLoginTriggers()
  addTrigger("(?:^Retrieving rented items from storage\\.\\.\\.$|^Reconnecting\\.$|^You break camp and get ready to move on\\.\\.\\.$)", function()
    for _, cmd in ipairs(ArjAuto.loginCommands or {}) do send(cmd, false) end
    ArjAuto.epic = { completed = {}, canReport = false }
  end)
end

-- ============================================================
-- ALIASES
-- ============================================================

local raceBash = {
  -- evil races
  bo = "orc", bt = "troll", bd = "drow", bu = "duergar", bv = "goblin", b1 = "kobold",
  br = "ogre", bj = "githyanki", b2 = "drider", bk = "thri-kreen", bm = "minotaur",
  -- goodie races
  bh = "human", bb = "barbarian", bg = "gnome", bz = "githzerai", bl = "halfling",
  bw = "dwarf", be = "grey", bc = "centaur", bf = "firbolg", b3 = "shade", b4 = "beast",
}

function ArjAuto:setupAliases()
  -- help and toggles
  addAlias("^auto$", function() ArjAuto:help() end)
  addAlias("^auto set$", function() ArjAuto:showToggles() end)
  addAlias("^auto (\\w+) (on|off)$", function()
    local key, val = matches[2], matches[3] == "on"
    if ArjAuto.toggleDefaults[key] == nil then
      note("<indian_red>[auto] Unknown toggle '" .. key .. "'. Type 'auto set' to list them.")
      return
    end
    ArjAuto.settings[key] = val
    ArjAuto:save()
    if key == "shipKeys" then ArjAuto:setupKeys() end
    note(string.format("<cyan>[auto] %s is now %s.", key, val and "on" or "off"))
  end)
  addAlias("^vars$", function() ArjAuto:showVars() end)
  addAlias("^auto vars$", function() ArjAuto:showVars() end)

  -- variables
  addAlias("^tt (.+)$", function() setVar("target", matches[2]) end)
  addAlias("^tt$", function() setVar("target", "") end)
  addAlias("^ht (.+)$", function() setVar("healtarget", matches[2]) end)
  addAlias("^container (.+)$", function() setVar("container", matches[2]) end)
  addAlias("^food (.+)$", function() setVar("food", matches[2]) end)
  addAlias("^wep (.+)$", function() setVar("weapon", matches[2]) end)
  addAlias("^held (.+)$", function() setVar("held", matches[2]) end)
  addAlias("^dd (.+)$", function() setVar("door", matches[2]) end)
  addAlias("^tank (.+)$", function() setVar("tank", matches[2]) end)
  addAlias("^song (.+)$", function() setVar("song", matches[2]) end)
  addAlias("^cargo (\\d+)$", function() setVar("cargo", matches[2]) end)
  addAlias("^contra (\\d+)$", function() setVar("contra", matches[2]) end)
  addAlias("^idscroll (.+)$", function() setVar("idscroll", matches[2]) end)
  addAlias("^report channel (acc|gcc|gsay|nchat|say|echo)$", function() setVar("channel", matches[2]) end)
  addAlias("^roller threshold ([\\d.]+)$", function() setVar("rollThreshold", matches[2]) end)
  addAlias("^weakest$", function()
    local worst, pct = nil, 101
    for _, m in ipairs(groupMembers()) do
      local hp, mx = tonumber(m.hp), tonumber(m.maxHp)
      if hp and mx and mx > 0 and m.inRoom ~= false then
        local p = hp / mx * 100
        if p < pct then worst, pct = m.name, p end
      end
    end
    if worst then
      setVar("healtarget", worst)
      note(string.format("<cyan>[auto] Most hurt: <white>%s<cyan> at %d%%", worst, math.floor(pct)))
    else
      note("<cyan>[auto] No group member HP data.")
    end
  end)

  -- door and movement
  local function door() return var("door") or "door" end
  addAlias("^od$", function() send("open " .. door(), false) end)
  addAlias("^cd$", function() send("close " .. door(), false) end)
  addAlias("^od (\\w+)$", function() send("open " .. door() .. " " .. matches[2], false) end)
  addAlias("^cd (\\w+)$", function() send("close " .. door() .. " " .. matches[2], false) end)
  addAlias("^uod (.+)$", function()
    send("unlock " .. matches[2], false); send("open " .. matches[2], false); send("look " .. matches[2], false)
  end)
  addAlias("^ep$", function() send("enter portal", false) end)
  addAlias("^epx$", function() send("enter portal", false); send("exit", false); send("enter portal", false) end)
  addAlias("^egh$", function() send("enter guildhall", false) end)
  addAlias("^emw$", function() send("enter moonwell", false) end)
  addAlias("^ewh$", function() send("enter rift", false) end)
  addAlias("^enl$", function() send("enter locker", false) end)
  addAlias("^enl (.+)$", function() send("enter locker " .. matches[2], false) end)
  addAlias("^env$", function() send("enter 1.vortex", false) end)
  addAlias("^env (\\d+)$", function() send("enter " .. matches[2] .. ".vortex", false) end)
  addAlias("^sw (.+)$", function() speedwalk(matches[2]) end)
  addAlias("^lall$", function()
    for _, d in ipairs({ "north", "east", "south", "west", "up", "down" }) do send("look " .. d, false) end
  end)
  addAlias("^sfle*$", function() send("save", false); send("flee", false) end)
  addAlias("^fc (.+)$", function() send("follow " .. matches[2], false); send("consent " .. matches[2], false) end)
  addAlias("^of (.+)$", function() send("order followers " .. matches[2], false) end)
  addAlias("^rm$", function() send("rest", false); send("mem", false); send("med", false) end)
  addAlias("^abq$", function() send("ask bartender quest", false) end)
  addAlias("^aba$", function() send("ask bartender abandon", false) end)
  addAlias("^locate$", function()
    ArjAuto:report("Location: " .. ((ArjUI and ArjUI.state and ArjUI.state.area) or "unknown"))
  end)

  -- containers
  local function cont() return var("container") or "bag" end
  addAlias("^pcb$", function() send("put all.coins " .. cont(), false) end)
  addAlias("^gcb$", function() send("get coins " .. cont(), false) end)
  addAlias("^pab$", function() send("put all " .. cont(), false) end)
  addAlias("^gab$", function() send("get all " .. cont(), false) end)
  addAlias("^lib$", function() send("look in " .. cont(), false) end)
  addAlias("^pi (.+)$", function() send("put " .. matches[2] .. " " .. cont(), false) end)
  addAlias("^gi (.+)$", function() send("get " .. matches[2] .. " " .. cont(), false) end)
  addAlias("^grep (.+)$", function()
    send("get " .. matches[2] .. " " .. cont(), false); send("repair " .. matches[2], false); send("put " .. matches[2] .. " " .. cont(), false)
  end)
  addAlias("^rrep (.+)$", function()
    send("remove " .. matches[2], false); send("repair " .. matches[2], false); send("wear " .. matches[2], false)
  end)
  addAlias("^eat$", function()
    if not var("food") then note("<red>[auto] No food set. Use: food <keyword>") return end
    send("get " .. var("food") .. " " .. cont(), false); send("eat " .. var("food"), false)
  end)
  addAlias("^qf (.+)$", function() send("get " .. matches[2] .. " " .. cont(), false); send("quaff " .. matches[2], false) end)
  addAlias("^rq (.+)$", function() send("remove " .. matches[2], false); send("quaff " .. matches[2], false) end)

  -- corpses
  addAlias("^lc$", function() send("get all corpse", false) end)
  addAlias("^lc (\\d+)$", function() send("get all " .. matches[2] .. ".corpse", false) end)
  addAlias("^lc (\\w+)$", function() send("get all " .. matches[2], false) end)
  addAlias("^lcb$", function() send("get all corpse", false); send("put all " .. cont(), false) end)
  addAlias("^lcb (\\d+)$", function() send("get all " .. matches[2] .. ".corpse", false); send("put all " .. cont(), false) end)
  addAlias("^lic$", function() send("look in corpse", false) end)
  addAlias("^lic (\\d+)$", function() send("look in " .. matches[2] .. ".corpse", false) end)
  addAlias("^dc (.+)$", function() send("drag corpse " .. matches[2], false) end)
  for k, d in pairs({ nlc = "north", slc = "south", elc = "east", wlc = "west" }) do
    addAlias("^" .. k .. "$", function() send(d, false); send("get all corpse", false) end)
  end

  -- combat shortcuts
  addAlias("^kt$", function() if var("target") then send("kill " .. var("target"), false) end end)
  addAlias("^bsh (.+)$", function() setVar("target", matches[2]); send("bash " .. matches[2], false) end)
  addAlias("^bsht$", function() send("bash " .. (var("target") or ""), false) end)
  addAlias("^tr (.+)$", function() setVar("target", matches[2]); send("trample " .. matches[2], false) end)
  for k, race in pairs(raceBash) do
    addAlias("^" .. k .. "$", function() ArjAuto.vars.target = race; send("bash " .. race, false) end)
  end
  addAlias("^rbsh$", function()
    if ArjAuto.rebash.inLag then
      ArjAuto.rebash.generic = true
      note("<white:firebrick>[auto] Will bash when the lag ends.")
    else
      send("bash", false)
    end
  end)
  addAlias("^rbsht$", function()
    if ArjAuto.rebash.inLag then
      ArjAuto.rebash.target = true
      note("<white:firebrick>[auto] Will bash " .. (var("target") or "") .. " when the lag ends.")
    else
      send("bash " .. (var("target") or ""), false)
    end
  end)
  addAlias("^bof$", function()
    ArjAuto.rebash.generic, ArjAuto.rebash.target = false, false
    note("<white:firebrick>[auto] Rebash cancelled.")
  end)
  addAlias("^fls$", function()
    if not var("target") then note("<red>[auto] Set a target first: tt <name>") return end
    ArjAuto.fleeStabArmed = true
    send("flee", false)
  end)
  addAlias("^fls (.+)$", function()
    setVar("target", matches[2])
    ArjAuto.fleeStabArmed = true
    send("flee", false)
  end)
  addAlias("^bac$", function() if var("target") then send("backstab " .. var("target"), false) end end)
  addAlias("^bac (.+)$", function() setVar("target", matches[2]); send("backstab " .. matches[2], false) end)

  -- held items and wands: `uw <item> [target]` swaps what you hold and uses it
  addAlias("^uw (\\S+)(?: (.+))?$", function()
    local item, tgt = matches[2], matches[3]
    if var("held") ~= item then
      if var("held") then send("remove " .. var("held"), false) end
      send("get " .. item .. " " .. cont(), false)
      send("hold " .. item, false)
      ArjAuto.vars.held = item
      ArjAuto:save()
    end
    if tgt and tgt ~= "" then send("use " .. item .. " " .. tgt, false) else send("use " .. item, false) end
  end)
  addAlias("^uwt$", function()
    if var("held") then send("use " .. var("held") .. " " .. (var("target") or ""), false) end
  end)
  addAlias("^id (.+)$", function()
    if not var("idscroll") then note("<red>[auto] Set your identify scroll keyword first: idscroll <keyword>") return end
    send("get " .. var("idscroll") .. " " .. cont(), false)
    send("recite " .. var("idscroll") .. " " .. matches[2], false)
  end)

  -- rescue list
  addAlias("^rescue add (\\w+)$", function()
    ArjAuto.rescueList[matches[2]:lower()] = true
    ArjAuto:save()
    note("<cyan>[auto] " .. matches[2] .. " added to the rescue list.")
  end)
  addAlias("^rescue del (\\w+)$", function()
    ArjAuto.rescueList[matches[2]:lower()] = nil
    ArjAuto:save()
    note("<cyan>[auto] " .. matches[2] .. " removed from the rescue list.")
  end)
  addAlias("^rescue group$", function()
    local n = 0
    for _, m in ipairs(groupMembers()) do
      if (m.name or ""):lower() ~= myName():lower() then ArjAuto.rescueList[m.name:lower()] = true; n = n + 1 end
    end
    ArjAuto:save()
    note("<cyan>[auto] Added " .. n .. " group members to the rescue list.")
  end)
  addAlias("^rescue list$", function()
    local names = {}
    for n in pairs(ArjAuto.rescueList) do table.insert(names, n) end
    table.sort(names)
    note("<cyan>[auto] Rescue list: <white>" .. (#names > 0 and table.concat(names, ", ") or "(empty)") .. "<cyan>  autoRescue is " .. (on("autoRescue") and "on" or "off"))
  end)
  addAlias("^rescue clear$", function() ArjAuto.rescueList = {}; ArjAuto:save(); note("<cyan>[auto] Rescue list cleared.") end)

  -- group casting helpers: cast a spell on every player in the group, skipping yourself
  addAlias("^castall '?([^']+)'?$", function()
    local spell = matches[2]
    local n = 0
    for _, m in ipairs(groupMembers()) do
      if (m.name or ""):lower() ~= myName():lower() then send("cast '" .. spell .. "' " .. m.name, false); n = n + 1 end
    end
    note(string.format("<cyan>[auto] Cast '%s' on %d group members.", spell, n))
  end)
  addAlias("^vitall$", function() expandAlias("castall 'vitality'", false) end)
  addAlias("^virtueall$", function() expandAlias("castall 'virtue'", false) end)

  -- timers
  addAlias("^spam (.+)$", function() setVar("spam", matches[2]) end)
  addAlias("^spamon$", function()
    if not var("spam") then note("<red>[auto] Set the command first: spam <command>") return end
    ArjAuto:startTimer("spam", tonumber(var("spamInterval")) or 1, var("spam"), function() return not inCombat() and standing() end)
  end)
  addAlias("^spamoff$", function() ArjAuto:stopTimer("spam") end)
  addAlias("^spam interval ([\\d.]+)$", function() setVar("spamInterval", matches[2]) end)
  addAlias("^scan timer on$", function()
    ArjAuto:startTimer("scan", tonumber(var("scanInterval")) or 5, "scan", function() return not inCombat() and standing() end)
  end)
  addAlias("^scan timer off$", function() ArjAuto:stopTimer("scan") end)
  addAlias("^scan interval ([\\d.]+)$", function() setVar("scanInterval", matches[2]) end)

  -- login commands
  addAlias("^login add (.+)$", function()
    table.insert(ArjAuto.loginCommands, matches[2]); ArjAuto:save()
    note("<cyan>[auto] Will send '" .. matches[2] .. "' on login.")
  end)
  addAlias("^login clear$", function() ArjAuto.loginCommands = {}; ArjAuto:save(); note("<cyan>[auto] Login commands cleared.") end)
  addAlias("^login list$", function()
    note("<cyan>[auto] Login commands: <white>" .. (#ArjAuto.loginCommands > 0 and table.concat(ArjAuto.loginCommands, "; ") or "(none)"))
  end)

  -- ship
  addAlias("^oh (.+)$", function() send("order heading " .. matches[2], false) end)
  addAlias("^os (\\d+)$", function()
    local speed = tonumber(matches[2])
    local max = tonumber(ArjAuto:shipState().maxSpeed)
    if max and speed > max then
      note("<cyan>[auto] Capped at the ship's max speed " .. max)
      speed = max
    end
    send("order speed " .. speed, false)
  end)
  for k, side in pairs({ fff = "fore", ffp = "port", ffs = "starboard", ffr = "rear" }) do
    addAlias("^" .. k .. "$", function() send("fire " .. side, false) end)
  end
  addAlias("^ffall$", function() for _, s in ipairs({ "port", "starboard", "fore", "rear" }) do send("fire " .. s, false) end end)
  addAlias("^otf$", function() ArjAuto:orderHeadingRelative(0) end)
  addAlias("^otp$", function() ArjAuto:orderHeadingRelative(90) end)
  addAlias("^ots$", function() ArjAuto:orderHeadingRelative(-90) end)
  addAlias("^otr$", function() ArjAuto:orderHeadingRelative(180) end)
  addAlias("^oth$", function()
    local c = ArjAuto:targetContact()
    if c and c.heading then send("order heading " .. c.heading, false) else note("<cyan>[auto] No locked target heading.") end
  end)
  addAlias("^otsp$", function()
    local c = ArjAuto:targetContact()
    if c and c.speed then send("order speed " .. c.speed, false) else note("<cyan>[auto] No locked target speed.") end
  end)
  addAlias("^jet$", function() send("order jettison cargo all", false); send("order jettison contraband all", false) end)
  addAlias("^disem$", function() send("disembark", false); ArjAuto:stopTimer("lookout", true); ArjAuto:stopTimer("contacts", true) end)
  local farsee = { le = "75 50", ln = "50 70", lne = "70 70", lnw = "25 70", ls = "50 25", lse = "70 26", lsw = "30 30", lw = "20 50" }
  for k, xy in pairs(farsee) do addAlias("^" .. k .. "$", function() send("look t " .. xy, false) end) end
  addAlias("^ship poll on$", function()
    ArjAuto.contactsWanted = true
    ArjAuto:startTimer("contacts", tonumber(var("contactsInterval")) or 2, "look contacts")
  end)
  addAlias("^ship poll off$", function() ArjAuto.contactsWanted = false; ArjAuto:stopTimer("contacts") end)
  addAlias("^ship interval ([\\d.]+)$", function() setVar("contactsInterval", matches[2]) end)
  addAlias("^lout on$", function() ArjAuto:startTimer("lookout", 1.8, "look out", function() return not inCombat() end) end)
  addAlias("^lout off$", function() ArjAuto:stopTimer("lookout") end)
  addAlias("^shipf$", function() ArjAuto:startTimer("shipScan", 5, "scan") end)
  addAlias("^shipn$", function() ArjAuto:stopTimer("shipScan") end)
  addAlias("^qkcargo$", function()
    local captain = ArjAuto:shipState().captain
    for _, c in ipairs({ "s", "s", "disembark", "list cargo", "sell cargo", "buy cargo " .. (var("cargo") or "0"),
                          "sell contraband", "buy contraband " .. (var("contra") or "0"), "put all.coins " .. cont() }) do
      send(c, false)
    end
    if captain then send("enter " .. captain, false); send("n", false); send("n", false); send("order undock", false)
    else note("<cyan>[auto] Captain unknown, walk back aboard yourself.") end
  end)
  addAlias("^qkreload$", function()
    for _, c in ipairs({ "s", "s", "disembark", "list cargo", "sell cargo", "sell contraband", "repair all", "reload all", "put all.coins " .. cont() }) do
      send(c, false)
    end
  end)

  -- loot split
  addAlias("^split start$", function() ArjAuto:splitStart() end)
  addAlias("^split roll$", function() ArjAuto:splitRoll(false) end)
  addAlias("^split free$", function() ArjAuto:splitRoll(true) end)
  addAlias("^split scores$", function() ArjAuto:splitScores() end)
  addAlias("^split set (\\w+) (\\d+)$", function()
    ArjAuto.bidScores[matches[2]] = tonumber(matches[3]); ArjAuto:save()
    note("<cyan>[split] " .. matches[2] .. " = " .. ArjAuto:bidScore(matches[2]))
  end)
  addAlias("^split flush$", function() ArjAuto.bidScores = {}; ArjAuto:save(); note("<cyan>[split] Bidscores cleared.") end)

  -- epic zones
  addAlias("^epic report$", function() ArjAuto:epicReport() end)

  -- plane direction notes (from the archive, 2021)
  addAlias("^dirs(?: (\\w+))?$", function() ArjAuto:showDirs(matches[2]) end)
end

-- ============================================================
-- KEYS: ship controls
-- ============================================================

function ArjAuto:setupKeys()
  for _, id in ipairs(self.keys) do pcall(function() killKey(id) end) end
  self.keys = {}
  if not on("shipKeys") then return end
  local km = mudlet and mudlet.keymodifier or {}
  local ctrl = km.Control or 67108864
  local ctrlShift = (km.Control or 67108864) + (km.Shift or 33554432)
  local F10, F11, F12 = 16777273, 16777274, 16777275
  local binds = {
    { 0, F10, "order speed max" },
    { 0, F11, function() local m = tonumber(ArjAuto:shipState().maxSpeed) or 20; send("order speed " .. math.min(20, m), false) end },
    { 0, F12, "order speed 0" },
    { ctrl, 70, "fire fore" }, { ctrl, 82, "fire rear" }, { ctrl, 83, "fire starboard" }, { ctrl, 80, "fire port" },
    { ctrl, 79, "fire 0" }, { ctrl, F10, function() expandAlias("otsp", false) end },
    { ctrlShift, 80, function() expandAlias("otp", false) end }, { ctrlShift, 83, function() expandAlias("ots", false) end },
    { ctrlShift, 70, function() expandAlias("otf", false) end }, { ctrlShift, 82, function() expandAlias("otr", false) end },
    { ctrlShift, 72, function() expandAlias("oth", false) end },
    { ctrlShift, 78, "order heading n" }, { ctrlShift, 69, "order heading e" },
    { ctrlShift, 79, "order heading s" }, { ctrlShift, 87, "order heading w" },
    { ctrlShift, 77, "order ram" }, { ctrlShift, 66, "order ram off" },
  }
  for _, b in ipairs(binds) do
    local action = b[3]
    local fn = type(action) == "function" and action or function() send(action, false) end
    local ok, id = pcall(tempKey, b[1], b[2], fn)
    if ok and id then table.insert(self.keys, id) end
  end
end

-- ============================================================
-- HELP AND NOTES
-- ============================================================

function ArjAuto:showToggles()
  local desc = {
    autoStand = "stand after knockdown / mem done", autoGroup = "group whoever consents",
    autoRescue = "rescue names on the rescue list", autoAssist = "assist a group member who is attacked",
    autoRage = "re-rage when it abates in combat", autoWield = "re-wield 'wep' after a disarm",
    autoLoot = "coins and essence from corpse on kill", autoOre = "grab ore/gems when mining",
    autoFollow = "follow + consent on beckon", autoPlay = "bard: restart 'song' when it ends",
    trapKill = "order followers kill arrivals", scanReport = "scan summary to report channel",
    eventReport = "tracks/spell hits/scry/ship alerts to report channel", shipKeys = "Ctrl/Ctrl+Shift ship hotkeys",
    roller = "creation: reroll until rollThreshold",
  }
  local names = {}
  for k in pairs(self.toggleDefaults) do table.insert(names, k) end
  table.sort(names)
  note("<gold>══ Automation toggles (auto <name> on|off) ══")
  for _, k in ipairs(names) do
    local v = self.settings[k]
    note(string.format("%s%-12s<dim_gray> %s  %s", v and "<green>" or "<indian_red>", k, v and "on " or "off", desc[k] or ""))
  end
end

function ArjAuto:showVars()
  local names = {}
  for k in pairs(self.varDefaults) do table.insert(names, k) end
  table.sort(names)
  note("<gold>══ Variables ══")
  for _, k in ipairs(names) do
    note(string.format("<white>%-17s<dim_gray> %s", k, self.vars[k] ~= "" and self.vars[k] or "(unset)"))
  end
  note("<dim_gray>Set with: tt, ht, container, food, wep, held, dd, tank, song, cargo, contra, idscroll, spam, report channel, roller threshold")
end

function ArjAuto:help()
  note("<gold>══ ArjAuto ══")
  note("<white>auto set<dim_gray>                 list toggles;  <white>auto <name> on|off")
  note("<white>vars<dim_gray>                     list variables (tt target, container, food, wep, held, dd door, song ...)")
  note("<white>rescue add|del|group|list|clear<dim_gray>   who autoRescue protects")
  note("<white>kt bsht rbsh rbsht bof fls bac<dim_gray>   target kill, bash, rebash after lag, flee-stab, backstab")
  note("<white>bo bt bd bu bv b1 br bj b2 bk bm<dim_gray>  bash by evil race;  <white>bh bb bg bz bl bw be bc bf b3 b4<dim_gray> by goodie race")
  note("<white>pcb gcb pab gab lib pi gi grep rrep eat qf rq<dim_gray>   container, repair, food and potion helpers")
  note("<white>lc lc N lcb lic dc nlc slc elc wlc<dim_gray>   corpse looting")
  note("<white>od cd od dir cd dir uod ep epx egh emw ewh enl env sw lall sfle fc of rm abq aba locate")
  note("<white>uw <item> [target]  uwt  id <item>  idscroll<dim_gray>   hold-and-use, identify to one line")
  note("<white>castall <spell>  vitall  virtueall  weakest<dim_gray>   group casting helpers")
  note("<white>spam <cmd> spamon spamoff  scan timer on|off<dim_gray>   repeat timers (idle and standing only)")
  note("<white>oh os fff ffp ffs ffr ffall otf otp ots otr oth otsp jet disem le ln ... lw<dim_gray>   ship orders")
  note("<white>ship poll on|off  lout on|off  shipf shipn  qkcargo qkreload<dim_gray>   ship polling and dock runs")
  note("<white>split start|roll|free|scores|set|flush<dim_gray>   loot split by bidscore")
  note("<white>epic report<dim_gray>   completed epic zones seen this boot;  <white>login add|list|clear<dim_gray>   commands sent on login")
  note("<white>dirs [eth|astral|air|fire|water|neg]<dim_gray>   plane direction notes")
end

ArjAuto.dirNotes = {
  eth = {
    "From Dreggan Woods: Void in Time: e 2s w",
    "From Void in Time: Pocket of Antimatter (!magic): s 2e u | Dreggan Woods: e 2n w | Drifting Realms: 2w 3d",
    "From Pocket of Antimatter: Void in Time: d 2w n | Dreggan Woods: 3n d w",
    "Fortress of Dreams: s s e w (at wall) w n e u d d d",
  },
  astral = {
    "From New Githyanki Fortress: Old Fortress: e n w u | Tiamat: 2e 2n | Jot: e 2d 2s w",
    "From Old Githyanki Fortress: New Fortress: d s e w | Tiamat: d 2e n | Jot: 3d 2n",
    "From Tiamat: New Fortress: 2s 2w | Old Fortress: s 2w u | Jot: s 2d 2w 2n",
    "From Jot: New Fortress: e 2u 2n w | Old Fortress: 2s 3u | Tiamat: 2e 2u 2s n",
    "From Great Wormhole: New Fortress: 2d s 3w | Old Fortress: 2d 2e u | Tiamat: 2d w n | Jot: u 2e 2n",
    "From Edge of Sphere of Fire: New Fortress: 2d 2n 3w | Old Fortress: 2d 2e 2s u | Tiamat: 2d w 2s n | Jot: u 2e",
    "From Astral Rift in Space: New Fortress: 2n u 2w | Old Fortress: 3n 2w 2u | Tiamat: n u 3n | Jot: n d s 2w",
  },
  water = { "From Pocket of Lightning: Sea Kingdom: 3d" },
  fire = {
    "From Multicoloured Jet: Brass: u w 2n",
    "From Edge of Sphere: Charcoal Palace: n 2w",
    "From Smoke Portal: Jet: w s d",
  },
  air = {
    "From Jet Stream: Bahamut: u 3e | Pocket of Lightning: d 2w",
    "From Edge of a Sphere of Fire: Smoke Plane: w s | The Tempest Court: e 3n u | Jet Stream: u 2e",
  },
  neg = {
    "To Flat Expanse from: A Windy Portion of the Forest: 4w 3s | A Dusty Plot of Land: 4w 3n",
  },
}

function ArjAuto:showDirs(which)
  if not which or not self.dirNotes[which] then
    note("<gold>══ Plane direction notes (archive, 2021) ══ <dim_gray>dirs eth | astral | air | fire | water | neg")
    return
  end
  note("<dodger_blue>── " .. which .. " ──")
  for _, l in ipairs(self.dirNotes[which]) do note("<white>" .. l) end
end

-- ============================================================
-- BOOT
-- ============================================================

ArjAuto:init()
