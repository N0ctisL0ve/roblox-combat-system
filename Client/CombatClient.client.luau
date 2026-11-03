--!strict

local CombatFolder = script.Parent:WaitForChild("Combat")
local CombatController = require(CombatFolder:WaitForChild("CombatController"))

CombatController.Init()
