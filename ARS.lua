--[[
Transport Rings Control Program
v1.2.0
Created By: Augur ShicKla

System Requirements:
Tier 2 GPU
Tier 2 Screen
]]--

local AdminList = {
"ShicKla",
}

local component = require("component")
local unicode = require("unicode")
local event = require("event")
local term = require("term")
local computer = require("computer")
local serialization = require("serialization")
local gpu = component.gpu
local screen = component.screen
local rings = {}
local AunisVersion = ""

-- Checking System Requirements are Met --------------------------------------------
if gpu.maxResolution() < 80 then
  io.stderr:write("Tier 2 GPU and Screen Required")
  os.exit(1)
end
if not component.isAvailable("transportrings") then
  io.stderr:write("No Transport Rings Connected.")
  os.exit(1)
else
  rings = component.transportrings
end
-- End of Checking System Requirements ---------------------------------------------

local ActiveButtons = {}
local RingsType = ""
local symbolType = {GOAULD=0, ORI=1}
local ringName = ""
local MainLoop = true
local OriginalResolution = {gpu.getResolution()}
local OrignalColorDepth = gpu.getDepth()
local DestinationButtons = {}
local TransportInterlock = false
local User = ""
local resultMessages = {
OK = "OK", 
BUSY = "BUSY", 
BUSY_TARGET = "Target Ring Platform is Busy", 
OBSTRUCTED = "Ring Platform is Obstructed", 
OBSTRUCTED_TARGET = "Target Ring Platform is Obstructed",
NOT_ENOUGH_POWER = "Ring Platform Has No Power"}

-- Button Object -------------------------------------------------------------------
local Button = {}
Button.__index = Button
function Button.new(xPos, yPos, width, height, label, func, border)
  local self = setmetatable({}, Button)
  if xPos < 1 or xPos > term.window.width then xPos = 1 end
  if yPos < 1 or yPos > term.window.height then yPos = 1 end
  if (width-2) < unicode.len(label) then width = unicode.len(label)+2 end
  if height < 3 then height = 3 end
  if border == nil then
    self.border = true
  else
    self.border = border
  end
  self.xPos = xPos
  self.yPos = yPos
  self.width = width
  self.height = height
  self.label = label
  self.func = func
  self.visible = false
  self.disabled = false
  return self
end

function Button.display(self, x, y)
  table.insert(ActiveButtons, 1, self)
  if (self.width-2) < unicode.len(self.label) then self.width = unicode.len(self.label)+2 end
  if x ~= nil and y ~= nil then
    self.xPos = x
    self.yPos = y
  end
  if self.border then
    gpu.fill(self.xPos+1, self.yPos, self.width-2, 1, "─")
    gpu.fill(self.xPos+1, self.yPos+self.height-1, self.width-2, 1, "─")
    gpu.fill(self.xPos, self.yPos+1, 1, self.height-2, "│")
    gpu.fill(self.xPos+self.width-1, self.yPos+1, 1, self.height-2, "│")
    gpu.set(self.xPos, self.yPos, "┌")
    gpu.set(self.xPos+self.width-1, self.yPos, "┐")
    gpu.set(self.xPos, self.yPos+self.height-1, "└")
    gpu.set(self.xPos+self.width-1, self.yPos+self.height-1, "┘")
  end
  -- gpu.set(self.xPos+1, self.yPos+1, self.label)
  gpu.set(self.xPos+(math.ceil((self.width)/2)-math.ceil(unicode.len(self.label)/2)), self.yPos+1, self.label)
  self.visible = true
end

function Button.hide(self)
  self.visible = false
  for i,v in ipairs(ActiveButtons) do
    if v == self then table.remove(ActiveButtons, i) end
  end
  if self.border then
    gpu.fill(self.xPos, self.yPos, self.width, self.height, " ")
  else
    gpu.fill(self.xPos+1, self.yPos+1, self.width-2, 1, " ")
  end
end

function Button.disable(self, bool)
  if bool == nil then
    self.disabled = false
  else
    self.disabled = bool
  end
  if self.disabled then gpu.setForeground(0x3C3C3C) end
  if self.visible then self:display() end
  gpu.setForeground(0xFFFFFF)
end

function Button.touch(self, x, y)
  local wasTouched = false
  if self.visible and not self.disabled then  
    if self.border then
      if x >= self.xPos and x <= (self.xPos+self.width-1) and y >= self.yPos and y <= (self.yPos+self.height-1) then wasTouched = true end
    else
      if x >= self.xPos+1 and x <= (self.xPos+self.width-2) and y >= self.yPos+1 and y <= (self.yPos+self.height-2) then wasTouched = true end
    end
  end
  if wasTouched then
    gpu.setBackground(0x3C3C3C)
    gpu.fill(self.xPos+1, self.yPos+1, self.width-2, self.height-2, " ")
    gpu.set(self.xPos+(math.ceil((self.width)/2)-math.ceil(unicode.len(self.label)/2)), self.yPos+1, self.label)
    gpu.setBackground(0x000000)
    local success, msg = pcall(self.func)
    if self.visible then
      gpu.fill(self.xPos+1, self.yPos+1, self.width-2, self.height-2, " ")
      gpu.set(self.xPos+(math.ceil((self.width)/2)-math.ceil(unicode.len(self.label)/2)), self.yPos+1, self.label)
    end
    if not success then
      HadNoError = false
      ErrorMessage = debug.traceback(msg)
    end
  end
  return wasTouched
end
-- End of Button Object ------------------------------------------------------------

-- Event Handlers ------------------------------------------------------------------
local Events = {}

Events.transportrings_teleport_start = event.listen("transportrings_teleport_start", function(_, address, caller, initiating)
  TransportInterlock = true
  for i,v in ipairs(DestinationButtons) do
    v:disable(true)
  end
  gpu.setBackground(0xFF9200)
  gpu.fill(1,1,36,3," ")
  gpu.set(19-math.ceil(unicode.len(ringName)/2), 2, ringName)
  gpu.setBackground(0x000000)
end)

Events.transportrings_teleport_finished = event.listen("transportrings_teleport_finished", function(_, address, caller, initiating)
  TransportInterlock = false
  for i,v in ipairs(DestinationButtons) do
    v:disable(false)
  end
  gpu.setBackground(0x4B4B4B)
  gpu.fill(1,1,36,3," ")
  gpu.set(19-math.ceil(unicode.len(ringName)/2), 2, ringName)
  gpu.setBackground(0x000000)
end)

Events.touch = event.listen("touch", function(_, screenAddress, x, y, button, playerName)
  if button == 0 then
    for i,v in ipairs(ActiveButtons) do
      if v:touch(x,y) then break end
    end
  end
end)

Events.key_down = event.listen("key_down", function(_, keyboardAddress, chr, code, playerName)
  User = playerName
end)

Events.interrupted = event.listen("interrupted", function()
  local shouldExit = false
  for i,v in ipairs(AdminList) do
    if v == User then shouldExit = true end
  end
  if shouldExit then MainLoop = false end
end)
-- End of Event Handlers -----------------------------------------------------------

local function AunisVersionCheck()
  local success, result = pcall(rings.getJSGVersion)
  if not success then
    success, result = pcall(rings.getAunisVersion)
  end
  if not success then
    AunisVersion = "legacy"
  else
    AunisVersion = result
  end
end

local function ringTypeSelection()
  if AunisVersion == "legacy" then
    return
  end
  gpu.set(2, 2, "Select the type of transport rings")
  gpu.set(11, 3, "you are using.")
  local GOAULD_Button = Button.new(1, 5, 36, 0, "Goa'uld", function()
    RingsType = "GOAULD"
    event.push("selectionMade")
  end)
  local ORI_Button = Button.new(1, 9, 36, 0, "Ori", function()
    RingsType = "ORI"
    event.push("selectionMade")
  end)
  GOAULD_Button:display()
  ORI_Button:display()
  event.pull("selectionMade")
  GOAULD_Button:hide()
  ORI_Button:hide()
  GOAULD_Button = nil
  ORI_Button = nil
  print(RingsType)
end

local function messagePopUp(msg)
  computer.beep()
  if msg ~= "OK" and msg ~= "ACTIVATED" then
    local msgString = resultMessages[msg]
    if msgString == nil then msgString = msg end
    gpu.setBackground(0xFF0000)
    gpu.fill(1,1,36,3," ")
    gpu.set(19-math.ceil(unicode.len(msgString)/2), 2, msgString)
    gpu.setBackground(0x000000)
    os.sleep(3)
    gpu.setBackground(0x4B4B4B)
    gpu.fill(1,1,36,3," ")
    gpu.set(19-math.ceil(unicode.len(ringName)/2), 2, ringName)
    gpu.setBackground(0x000000)
  end
end

local function dialRing(addressString)
  local address = {}
  for symbol in addressString:gmatch('[^,%s]+') do
    table.insert(address, symbol)
  end
  for _,v in ipairs(address) do
    local msg = rings.addSymbolToAddress(symbolType[RingsType], v)
  end
  local result = rings.addSymbolToAddress(symbolType[RingsType], 5)
  messagePopUp(result)
end

local function updateButtons()
  local buttonCount = 1
  local ringEntries = {}
  if AunisVersion == "legacy" then
    for k,v in pairs(rings.getAvailableRings()) do
      DestinationButtons[buttonCount] = Button.new(1, (buttonCount-1)*3+4, 36, 0, v, function()
        local result = rings.attemptTransportTo(k)
        messagePopUp(result)
      end)
      if buttonCount == 5 then break end
      buttonCount = buttonCount + 1
    end
  else
    for _,v in ipairs(rings.getAvailableRingsAddresses()) do
      ringEntries[v[RingsType]] = rings.getAvailableRings()[v[RingsType]]
    end
    for k,v in pairs(ringEntries) do
      -- print(v.."\n"..k) -- for debug
      DestinationButtons[buttonCount] = Button.new(1, (buttonCount-1)*3+4, 36, 0, v, function() 
        dialRing(k)
      end)
      if buttonCount == 5 then break end
      buttonCount = buttonCount + 1
    end
  end

  for i,v in ipairs(DestinationButtons) do
    v:display()
  end
end

-- Main Procedures -----------------------------------------------------------------
ringName = rings.getName()
if ringName == "NOT_IN_GRID" then
  error("Transport Rings Missing Address and Name", 0)
end
AunisVersionCheck()
gpu.setResolution(36,18)
gpu.setDepth(4)
term.clear()
screen.setTouchModeInverted(true)
-- ringTypeSelection()
RingsType = "GOAULD"
term.clear()
gpu.setBackground(0x4B4B4B)
gpu.fill(1,1,36,3," ")
gpu.set(19-math.ceil(unicode.len(ringName)/2), 2, ringName)
gpu.setBackground(0x000000)

updateButtons()

while MainLoop do
  os.sleep(0.05)
end
-- event.pull("interrupted")
-- End Main Procedures -------------------------------------------------------------

-- Closing Procedures --------------------------------------------------------------
for k,v in pairs(Events) do
  event.cancel(v)
end
screen.setTouchModeInverted(false)
gpu.setResolution(table.unpack(OriginalResolution))
gpu.setDepth(OrignalColorDepth)
term.clear()