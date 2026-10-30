--!strict

local CombatFolder = script.Parent:WaitForChild("Combat")
local CombatService = require(CombatFolder:WaitForChild("CombatService"))

CombatService.Init()
