local env = (getgenv and getgenv()) or _G
local FUEL_TRIPS = { 2, 5 }
local BACKPACK_CAPACITY = 10
local LOOP_FOREVER = false
local POWER_WAIT = 300
local FUEL_WAIT = 40
local WALK_SPEED = 32
local NOCLIP = true
local DEBUG_LEVEL = 2
local SHOW_PATH = true
local SHOW_THREATS = true
local SHOW_HUD = true
local myToken = {}
env.__FuelHaulerToken = myToken
local function alive() return env.__FuelHaulerToken == myToken end
print("[FuelHauler] started")
local function safeRef(s)
	if cloneref then
		local ok, r = pcall(cloneref, s)
		if ok and r then return r end
	end
	return s
end
local Players = safeRef(game:GetService("Players"))
local PathfindingService = safeRef(game:GetService("PathfindingService"))
local ReplicatedStorage = safeRef(game:GetService("ReplicatedStorage"))
local player = Players.LocalPlayer
local rand = Random.new()
local running = true
local dotFolder
local dots = {}
local function makeDot(list, pos, color, size, transparency)
	if not dotFolder or not dotFolder.Parent then
		dotFolder = Instance.new("Folder")
		dotFolder.Name = tostring(rand:NextInteger(100000, 999999))
		dotFolder.Parent = workspace
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.15
	p.Position = pos + Vector3.new(0, 0.6, 0)
	p.Parent = dotFolder
	table.insert(list, p)
	return p
end
local function dot(pos, color, size)
	if SHOW_PATH then makeDot(dots, pos, color, size or 0.7) end
end
local function clearDots()
	for _, d in ipairs(dots) do d:Destroy() end
	table.clear(dots)
end
local function showPath(wps, target)
	clearDots()
	if not SHOW_PATH then return end
	for _, wp in ipairs(wps) do
		dot(wp.Position, wp.Action == Enum.PathWaypointAction.Jump and Color3.fromRGB(255, 220, 0) or Color3.fromRGB(0, 255, 120), 0.7)
	end
	dot(target, Color3.fromRGB(255, 60, 60), 1.4)
end
local function fmt(v)
	return "(" .. math.floor(v.X) .. ", " .. math.floor(v.Y) .. ", " .. math.floor(v.Z) .. ")"
end
local hudLines = {}
local hudLabel
local status = "starting"
local function refreshHud()
	if hudLabel then hudLabel.Text = "status: " .. status .. "\n" .. table.concat(hudLines, "\n") end
end
local function emit(...)
	local p = table.pack(...)
	for i = 1, p.n do p[i] = tostring(p[i]) end
	local line = table.concat(p, " ")
	print("[FuelHauler] " .. line)
	table.insert(hudLines, line)
	if #hudLines > 7 then table.remove(hudLines, 1) end
	refreshHud()
end
local function log(...)
	if DEBUG_LEVEL >= 1 then emit(...) end
end
local function dlog(...)
	if DEBUG_LEVEL >= 2 then emit(...) end
end
local function tlog(...)
	if DEBUG_LEVEL >= 3 then emit(...) end
end
local function setStatus(t)
	status = t
	refreshHud()
end
if SHOW_HUD then
	pcall(function()
		if env.__FuelHaulerHud then pcall(function() env.__FuelHaulerHud:Destroy() end) end
		local gui = Instance.new("ScreenGui")
		gui.Name = tostring(rand:NextInteger(100000, 999999))
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 20000
		local label = Instance.new("TextLabel")
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.45
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Font = Enum.Font.Code
		label.TextSize = 12
		label.TextWrapped = true
		label.Position = UDim2.new(0, 6, 0, 40)
		label.Size = UDim2.new(0, 300, 0, 120)
		label.Parent = gui
		local function button(x, text, onClick)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, 96, 0, 26)
			b.Position = UDim2.new(0, x, 0, 164)
			b.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			b.TextColor3 = Color3.new(1, 1, 1)
			b.Font = Enum.Font.Code
			b.TextSize = 12
			b.Text = text()
			b.Parent = gui
			b.Activated:Connect(function()
				onClick()
				b.Text = text()
			end)
		end
		button(6, function() return "Dots: " .. (SHOW_PATH and "on" or "off") end, function()
			SHOW_PATH = not SHOW_PATH
			SHOW_THREATS = SHOW_PATH
			if not SHOW_PATH then clearDots() end
		end)
		button(106, function() return "Debug: " .. DEBUG_LEVEL end, function()
			DEBUG_LEVEL = (DEBUG_LEVEL + 1) % 4
		end)
		button(206, function() return "Stop" end, function()
			env.__FuelHaulerToken = nil
		end)
		local okHui, hui = pcall(function() return gethui and gethui() end)
		gui.Parent = (okHui and hui) or player:WaitForChild("PlayerGui")
		hudLabel = label
		env.__FuelHaulerHud = gui
	end)
end
local noclipOn = false
local noclipParts = {}
local noclipConns = {}
local rsRaw = game:GetService("RunService")
local function stopNoclip()
	for _, c in ipairs(noclipConns) do c:Disconnect() end
	table.clear(noclipConns)
end
local function restoreNoclip()
	for part in pairs(noclipParts) do
		if part.Parent then part.CanCollide = true end
	end
	table.clear(noclipParts)
end
local function applyNoclip()
	if not alive() or not running then
		stopNoclip()
		restoreNoclip()
		return
	end
	if not noclipOn then return end
	local char = player.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			noclipParts[part] = true
			part.CanCollide = false
		end
	end
end
local function setNoclip(want)
	if want == noclipOn then return end
	noclipOn = want
	if want then
		for _, name in ipairs({ "Stepped", "PreSimulation", "Heartbeat" }) do
			local okSig, sig = pcall(function() return rsRaw[name] end)
			if okSig and sig then table.insert(noclipConns, sig:Connect(applyNoclip)) end
		end
		applyNoclip()
		log("noclip on (" .. #noclipConns .. " loops)")
	else
		stopNoclip()
		restoreNoclip()
		log("noclip off")
	end
end
local function getChar()
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid")
	local hrp = char:WaitForChild("HumanoidRootPart")
	return char, hum, hrp
end
local function pressButton(btn)
	if not btn then return false end
	local fired = false
	if firesignal then
		for _, name in ipairs({ "MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up" }) do
			local ok = pcall(firesignal, btn[name])
			fired = fired or ok
		end
	end
	if not fired and getconnections then
		for _, name in ipairs({ "MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up" }) do
			local ok, conns = pcall(getconnections, btn[name])
			if ok and conns then
				for _, c in ipairs(conns) do
					pcall(function() c:Fire() end)
					fired = true
				end
			end
		end
	end
	return fired
end
local avoidOn = true
local deathEpoch = 0
local intentionalDeath = false
local flee
local function charPos(m)
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	return r and r.Position
end
local function isDead(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health <= 0
end
local function threatsWithin(range, origin)
	local list = {}
	local folder = workspace:FindFirstChild("Characters")
	local mine = player.Character
	local root = mine and mine:FindFirstChild("HumanoidRootPart")
	local o = origin or (root and root.Position)
	if not folder or not o then return list end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m ~= mine and not isDead(m) then
			local p = charPos(m)
			if p and (p - o).Magnitude <= range then table.insert(list, p) end
		end
	end
	return list
end
local function zonePosition()
	local st = workspace:FindFirstChild("Structures")
	local gen = st and st:FindFirstChild("Generator")
	local z = gen and gen:FindFirstChild("FuelZone")
	if not z then return nil end
	return z:IsA("BasePart") and z.Position or z:GetPivot().Position
end
local mapOk = false
local function rayTile(pos, tiles)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { tiles }
	return workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -100, 0), rp) ~= nil
end
local function onMap(pos)
	local map = workspace:FindFirstChild("Map")
	local tiles = map and map:FindFirstChild("Tiles")
	if not tiles then return true end
	if not mapOk then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and rayTile(root.Position, tiles) then mapOk = true else return true end
	end
	return rayTile(pos, tiles)
end
local blockers = {}
local function purgeBlockers(all)
	for i = #blockers, 1, -1 do
		local b = blockers[i]
		if all or os.clock() > b.expires then
			b.part:Destroy()
			table.remove(blockers, i)
		end
	end
end
local function addBlocker(pos)
	local part = Instance.new("Part")
	part.Name = tostring(rand:NextInteger(100000, 999999))
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(6, 12, 6)
	part.CFrame = CFrame.new(pos)
	local mod = Instance.new("PathfindingModifier")
	mod.Label = "Blocked"
	mod.Parent = part
	part.Parent = workspace
	table.insert(blockers, { part = part, expires = os.clock() + 90 })
end
local function walkCore(targetPos, stopDist, stopCheck, timeout, noAvoid)
	local _, hum, hrp = getChar()
	stopDist = stopDist or 4
	timeout = timeout or 45
	local startT = os.clock()
	local epoch0 = deathEpoch
	local stuckCount = 0
	local stuckSpots = {}
	local repeats = 0
	local agentRadius = 2
	local dodge = false
	local lastScan = 0
	purgeBlockers(false)
	local function flat(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function done()
		if (hrp.Position - targetPos).Magnitude <= stopDist then return true end
		return stopCheck and stopCheck() or false
	end
	local function timedOut()
		return os.clock() - startT > timeout or not alive() or deathEpoch ~= epoch0
	end
	while not done() and not timedOut() do
		if not noAvoid and avoidOn and #threatsWithin(10) > 0 then flee() end
		local path = PathfindingService:CreatePath({
			AgentRadius = agentRadius,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = { Blocked = math.huge },
		})
		local ok = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
		if ok and path.Status == Enum.PathStatus.Success then
			local stuck = false
			local stuckDir = Vector3.new(0, 0, 1)
			local wps = path:GetWaypoints()
			showPath(wps, targetPos)
			dlog("path ok:", #wps, "waypoints")
			if #wps > 0 and (wps[#wps].Position - targetPos).Magnitude > math.max(12, stopDist + 6) then
				log("no real route to the target, giving up")
				hum:MoveTo(hrp.Position)
				return false
			end
			for i, wp in ipairs(wps) do
				if i > 1 then
					if done() or timedOut() or stuck or dodge then break end
					if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
					local prevDot = dots[i - 1]
					if prevDot then prevDot.Transparency = 0.85 end
					local curDot = dots[i]
					if curDot then curDot.Color = Color3.fromRGB(0, 200, 255) end
					tlog("waypoint " .. i .. "/" .. #wps)
					hum:MoveTo(wp.Position)
					local best = flat(hrp.Position, wp.Position)
					local bestAt = os.clock()
					local wpStart = os.clock()
					local checkAt
					while not done() and not timedOut() do
						task.wait(0.05)
						if not noAvoid and avoidOn and os.clock() - lastScan > 0.25 then
							lastScan = os.clock()
							if #threatsWithin(10) > 0 then
								dodge = true
								break
							end
						end
						local d = flat(hrp.Position, wp.Position)
						if d < 2 then
							stuckCount = 0
							break
						end
						if d < best - 1 then
							best, bestAt = d, os.clock()
							checkAt = nil
						end
						local idle = os.clock() - bestAt
						if idle > 1.5 then hum.Jump = true end
						if idle > 0.5 and not checkAt then
							checkAt = os.clock() + 0.2
							log("not making progress, rechecking in 0.2s")
						end
						if (checkAt and os.clock() >= checkAt) or os.clock() - wpStart > 12 then
							stuck = true
							local v = wp.Position - hrp.Position
							v = Vector3.new(v.X, 0, v.Z)
							if v.Magnitude > 0.1 then stuckDir = v.Unit end
							break
						end
					end
				end
			end
			if dodge then
				dodge = false
				flee()
			elseif stuck then
				stuckCount += 1
				local here = hrp.Position
				for _, sp in ipairs(stuckSpots) do
					if (sp - here).Magnitude < 6 then
						repeats += 1
						break
					end
				end
				table.insert(stuckSpots, here)
				if repeats >= 2 or #stuckSpots >= 4 then
					log("blocked by a wall, giving up on this target")
					hum:MoveTo(hrp.Position)
					return false
				end
				addBlocker(here + stuckDir * 5)
				agentRadius = math.min(agentRadius + 0.5, 4)
				log("still stuck after 0.2s, rerouting around the obstacle (" .. stuckCount .. ")")
				hum.Jump = true
				hum:MoveTo(here - stuckDir * 6)
				task.wait(0.5)
			elseif not done() then
				hum:MoveTo(targetPos)
				local t = os.clock()
				while not done() and os.clock() - t < 2 do task.wait(0.05) end
				return done()
			end
		else
			stuckCount += 1
			dlog("path failed, status:", tostring(ok and path.Status or "error"))
			task.wait(0.5)
			if stuckCount >= 3 then
				log("no path to the target, giving up")
				return done()
			end
		end
	end
	return done()
end
local function walkTo(targetPos, stopDist, stopCheck, timeout, noAvoid)
	dlog("walkTo", fmt(targetPos), "stop", stopDist or 4, "timeout", timeout or 45)
	local r = walkCore(targetPos, stopDist, stopCheck, timeout, noAvoid)
	clearDots()
	dlog("walkTo finished:", r)
	return r
end
flee = function()
	if #threatsWithin(10) == 0 then return false end
	setStatus("avoiding a character")
	log("character within 10 studs, walking away")
	local _, _, hrp = getChar()
	local zonePos = zonePosition()
	local start = os.clock()
	while alive() and os.clock() - start < 20 do
		local near = threatsWithin(15)
		if #near == 0 then break end
		local best, bestScore
		for i = 0, 11 do
			local ang = i * math.pi / 6
			for _, dist in ipairs({ 14, 22 }) do
				local c = hrp.Position + Vector3.new(math.cos(ang), 0, math.sin(ang)) * dist
				if onMap(c) then
					local minD = math.huge
					for _, p in ipairs(near) do minD = math.min(minD, (p - c).Magnitude) end
					local score = minD - (zonePos and (c - zonePos).Magnitude * 0.05 or 0)
					if not bestScore or score > bestScore then best, bestScore = c, score end
				end
			end
		end
		if not best then
			log("no safe spot on the map to run to")
			break
		end
		dlog("fleeing to", fmt(best))
		walkTo(best, 3, function() return #threatsWithin(15) == 0 end, 8, true)
	end
	return true
end
local failed = {}
local function modelPos(m)
	local u = m:FindFirstChild("Union1")
	if u and u:IsA("BasePart") then return u.Position end
	return m:GetPivot().Position
end
local function isRealFuel(m)
	if m.Name ~= "Fuel" or not m:IsA("Model") then return false end
	local itemType = m:GetAttribute("ItemType")
	if itemType ~= nil and itemType ~= "Fuel" then return false end
	return m:FindFirstChildWhichIsA("BasePart", true) ~= nil
end
local function closestFuel()
	local _, _, hrp = getChar()
	local folder = workspace:FindFirstChild("DroppedItems")
	if not folder then return nil end
	local zonePos = zonePosition()
	local best, bestScore
	for _, m in ipairs(folder:GetChildren()) do
		local f = failed[m]
		if isRealFuel(m) and (not f or os.clock() - f > 30) then
			local p = modelPos(m)
			if onMap(p) and #threatsWithin(10, p) == 0 then
				local score = (p - hrp.Position).Magnitude + (zonePos and (p - zonePos).Magnitude or 0)
				if not bestScore or score < bestScore then
					best, bestScore = m, score
				end
			end
		end
	end
	return best
end
local function equipBackpack()
	local char, hum = getChar()
	if char:FindFirstChild("Backpack") then return true end
	local tool = player.Backpack:FindFirstChild("Backpack")
	if tool then
		hum:EquipTool(tool)
		return true
	end
	return false
end
local function getAdjust()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
	local tools = remotes and remotes:WaitForChild("Tools", 5)
	return tools and tools:WaitForChild("AdjustBackpack", 5)
end
local function storeFuel(item)
	local adjust = getAdjust()
	if not adjust then
		print("[FuelHauler] AdjustBackpack remote NOT found")
		return false
	end
	adjust:FireServer(item)
	return true
end
local function dropFuel()
	local _, _, hrp = getChar()
	local adjust = getAdjust()
	if adjust then
		adjust:FireServer(nil, hrp.CFrame * CFrame.new(0, 0, -3))
	end
end
local function pickViaClick(fuel, union)
	for _, d in ipairs(fuel:GetDescendants()) do
		if d:IsA("ClickDetector") then
			log("firing ClickDetector:", d:GetFullName())
			pcall(fireclickdetector, d)
		elseif d:IsA("ProximityPrompt") then
			log("firing ProximityPrompt:", d:GetFullName())
			pcall(fireproximityprompt, d)
		end
	end
	task.wait(0.2)
	local char = getChar()
	local ds = char:FindFirstChild("DragSystem")
	local remote = ds and ds:FindFirstChild("DragItem")
	if remote then
		pcall(function() remote:FireServer(fuel, union or fuel) end)
		log("DragItem fired")
	end
	task.wait(0.4)
	return true, function() end
end
local function grabOne(target)
	local fuel = target or closestFuel()
	if not fuel then log("no Fuel left in DroppedItems") return false end
	local char, _, hrp = getChar()
	local union = fuel:FindFirstChild("Union1")
	setStatus("walking to fuel")
	log("target:", fuel:GetFullName(), "ItemType:", tostring(fuel:GetAttribute("ItemType")),
		"dist:", math.floor((modelPos(fuel) - hrp.Position).Magnitude))
	walkTo(modelPos(fuel), 3, function() return not fuel.Parent end)
	if not fuel.Parent then log("fuel disappeared while walking") return false end
	local function dist() return (modelPos(fuel) - hrp.Position).Magnitude end
	if not fuel.Parent then log("fuel disappeared while walking") return false end
	log("dist after walk:", math.floor(dist()))
	if dist() > 10 then
		log("could not get close enough, skipping this one")
		failed[fuel] = os.clock()
		return false
	end
	setStatus("storing fuel")
	equipBackpack()
	local t = os.clock()
	while not char:FindFirstChild("Backpack") and os.clock() - t < 2 do task.wait(0.05) end
	log("backpack equipped:", char:FindFirstChild("Backpack") ~= nil)
	task.wait(0.2)
	local function gone() return fuel.Parent ~= workspace:FindFirstChild("DroppedItems") end
	local function waitGone(t)
		local st = os.clock()
		while os.clock() - st < t do
			if gone() then return true end
			task.wait(0.1)
		end
		return gone()
	end
	local dragging = player:FindFirstChild("CurrentlyDragging")
	storeFuel(fuel)
	if waitGone(2) then log("SUCCESS (direct store)") return true end
	log("attempt 1 failed; CurrentlyDragging =", dragging and tostring(dragging.Value) or "n/a")
	pickViaClick(fuel, union)
	log("CurrentlyDragging after DragItem =", dragging and tostring(dragging.Value) or "n/a")
	storeFuel(fuel)
	if waitGone(2) then log("SUCCESS (DragItem + store)") return true end
	local det = fuel:FindFirstChild("ItemDrag")
	local reqOwn = det and det:FindFirstChild("RequestNetworkOwnership")
	if reqOwn then
		pcall(function() reqOwn:FireServer() end)
		log("RequestNetworkOwnership fired")
		task.wait(0.3)
		pickViaClick(fuel, union)
		storeFuel(fuel)
		if waitGone(2) then log("SUCCESS (ownership + DragItem + store)") return true end
	end
	log("all attempts failed for this fuel, skipping it")
	failed[fuel] = os.clock()
	return false
end
local function insideZone(zone, pos)
	if not zone:IsA("BasePart") then
		return (zone:GetPivot().Position - pos).Magnitude < 6
	end
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local s = zone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end
local function zoneTargets(zone, fromPos)
	local pts = {}
	if zone:IsA("BasePart") then
		local sx, sz = zone.Size.X * 0.35, zone.Size.Z * 0.35
		for _, o in ipairs({ {0, 0}, {sx, 0}, {-sx, 0}, {0, sz}, {0, -sz}, {sx, sz}, {-sx, sz}, {sx, -sz}, {-sx, -sz} }) do
			table.insert(pts, (zone.CFrame * CFrame.new(o[1], 0, o[2])).Position)
		end
	else
		table.insert(pts, zone:GetPivot().Position)
	end
	table.sort(pts, function(a, b) return (a - fromPos).Magnitude < (b - fromPos).Magnitude end)
	return pts
end
local function goToZoneAndDrop(count)
	setStatus("going to the FuelZone")
	local zone = workspace:WaitForChild("Structures"):WaitForChild("Generator"):WaitForChild("FuelZone")
	local _, hum, hrp = getChar()
	local function inside() return insideZone(zone, hrp.Position) end
	local startT = os.clock()
	while not inside() and os.clock() - startT < 90 do
		for _, target in ipairs(zoneTargets(zone, hrp.Position)) do
			if inside() then break end
			walkTo(target, 1.5, inside, 15)
		end
	end
	if not inside() then
		warn("[FuelHauler] could not reach FuelZone; NOT dropping")
		return false
	end
	setStatus("dropping fuel")
	log("inside FuelZone, dropping", count)
	hum:MoveTo(hrp.Position)
	equipBackpack()
	local t = os.clock()
	while not (getChar()):FindFirstChild("Backpack") and os.clock() - t < 2 do task.wait(0.05) end
	for _ = 1, count do
		dropFuel()
	end
	return true
end
local function truthy(v) return v ~= nil and v ~= false end
local function getCutsceneUI()
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	return pg and pg:FindFirstChild("CutsceneUI")
end
local function cutsceneBusy()
	local ui = getCutsceneUI()
	return truthy(player:GetAttribute("RoundIntroPending"))
		or truthy(player:GetAttribute("RoundIntroClientActive"))
		or (ui ~= nil and ui.Enabled)
end
task.spawn(function()
	while alive() and running do
		local ui = getCutsceneUI()
		local skip = ui and ui:FindFirstChild("Skip")
		if ui and ui.Enabled and skip and skip.Visible then
			pressButton(skip)
			task.wait(0.15)
		else
			task.wait(0.25)
		end
	end
end)
local function waitForCutscenes(maxWait)
	local start = os.clock()
	local quietSince
	local announced = false
	while alive() and os.clock() - start < maxWait do
		if cutsceneBusy() then
			quietSince = nil
			if not announced then
				setStatus("skipping cutscene")
				log("cutscene detected, skipping...")
				announced = true
			end
		else
			quietSince = quietSince or os.clock()
			if os.clock() - quietSince > 1 then
				if announced then
					log("cutscene skipped after " .. string.format("%.1f", os.clock() - start) .. "s")
				end
				return true
			end
		end
		task.wait(0.1)
	end
	warn("[FuelHauler] cutscene still busy after " .. maxWait .. "s, continuing anyway")
	return false
end
local speedActive = true
local baseSpeed = 16
task.spawn(function()
	local seen
	while alive() and speedActive do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			if hum ~= seen then
				seen = hum
				if hum.WalkSpeed ~= WALK_SPEED then baseSpeed = hum.WalkSpeed end
			end
			if hum.WalkSpeed ~= WALK_SPEED then hum.WalkSpeed = WALK_SPEED end
		end
		task.wait(0.1)
	end
	if alive() and not speedActive then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = baseSpeed end
	end
end)
local function fuelStatus()
	local folder = workspace:FindFirstChild("DroppedItems")
	if not folder then return "workspace.DroppedItems does not exist yet" end
	local total, skipped, offMap, nearChar, others = 0, 0, 0, 0, 0
	for _, m in ipairs(folder:GetChildren()) do
		if m.Name == "Fuel" then
			total += 1
			local f = failed[m]
			local p = modelPos(m)
			if f and os.clock() - f <= 30 then
				skipped += 1
			elseif not onMap(p) then
				offMap += 1
			elseif #threatsWithin(10, p) > 0 then
				nearChar += 1
			end
		else
			others += 1
		end
	end
	return total .. " Fuel (" .. skipped .. " skipped, " .. offMap .. " off the map, " .. nearChar
		.. " near characters) / " .. others .. " other items"
end
local function beelineCore(target, stopDist, timeout, stopCheck)
	local _, hum, hrp = getChar()
	local start = os.clock()
	local epoch0 = deathEpoch
	local best = (hrp.Position - target).Magnitude
	local bestAt = os.clock()
	local side = 1
	while alive() and deathEpoch == epoch0 and os.clock() - start < timeout do
		local d = (hrp.Position - target).Magnitude
		if d <= stopDist or (stopCheck and stopCheck()) then return true end
		hum:MoveTo(target)
		if d < best - 1 then best, bestAt = d, os.clock() end
		local idle = os.clock() - bestAt
		if idle > 1 then hum.Jump = true end
		if idle > 2.5 then
			local dir = target - hrp.Position
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 0.1 then
				local perp = Vector3.new(-dir.Z, 0, dir.X).Unit * side
				hum:MoveTo(hrp.Position + perp * 10)
				task.wait(0.8)
				side = -side
			end
			best = (hrp.Position - target).Magnitude
			bestAt = os.clock()
		end
		task.wait(0.1)
	end
	return false
end
local function beeline(target, stopDist, timeout, stopCheck)
	local _, _, hrp = getChar()
	clearDots()
	local from = hrp.Position
	local n = math.floor((target - from).Magnitude / 8)
	for i = 1, n do dot(from:Lerp(target, i / (n + 1)), Color3.fromRGB(80, 160, 255), 0.6) end
	dot(target, Color3.fromRGB(255, 60, 60), 1.4)
	dlog("beeline to", fmt(target))
	local r = beelineCore(target, stopDist, timeout, stopCheck)
	clearDots()
	dlog("beeline finished:", r)
	return r
end
local powerCooldown = 0
local powerDone = false
local powerTarget
local phase = 1
local function promptPos(p)
	local par = p.Parent
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("Model") then return par:GetPivot().Position end
	return nil
end
local lastDeep, deepFound = -100, {}
local function deepPrompts(tiles)
	if os.clock() - lastDeep > 5 then
		lastDeep = os.clock()
		deepFound = {}
		for _, d in ipairs(tiles:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d:FindFirstAncestor("Power Box") then
				table.insert(deepFound, d)
			end
		end
	end
	return deepFound
end
local function powerPlants()
	local list = {}
	local map = workspace:FindFirstChild("Map")
	local tiles = map and map:FindFirstChild("Tiles")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not tiles or not root then return list end
	local function add(p, name)
		local pos = promptPos(p)
		if pos then
			table.insert(list, { prompt = p, name = name, pos = pos, dist = (pos - root.Position).Magnitude })
		end
	end
	for _, plant in ipairs(tiles:GetChildren()) do
		if plant.Name:lower():find("power plant") then
			local box = plant:FindFirstChild("Power Box")
			local p = box and box:FindFirstChild("Prompt")
			if p and p:IsA("ProximityPrompt") then add(p, plant.Name) end
		end
	end
	if #list == 0 then
		for _, p in ipairs(deepPrompts(tiles)) do
			if p.Parent then
				local box = p:FindFirstAncestor("Power Box")
				add(p, box and box.Parent and box.Parent.Name or "?")
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end
local function pickPowerTarget()
	if powerTarget and powerTarget.prompt.Parent then return powerTarget end
	local list = powerPlants()
	if #list == 0 then return nil end
	local idx = math.min(2, #list)
	powerTarget = list[idx]
	log("power plants found: " .. #list .. ", going to #" .. idx .. " by distance (" .. powerTarget.name
		.. ", " .. math.floor(powerTarget.dist) .. " studs)")
	return powerTarget
end
local function doPowerBox(target)
	if os.clock() < powerCooldown then return false end
	local prompt, pos = target.prompt, target.pos
	setStatus("going to the Power Box")
	log("going to the Power Box in", target.name)
	avoidOn = false
	if NOCLIP then setNoclip(true) end
	local fired = false
	local ok, err = pcall(function()
		local _, _, hrp = getChar()
		local range = prompt.MaxActivationDistance
		local function inRange() return not prompt.Parent or (hrp.Position - pos).Magnitude <= range - 1 end
		purgeBlockers(true)
		pcall(function() player:RequestStreamAroundAsync(pos, 3) end)
		log("walking straight to the Power Box")
		beeline(pos, range - 1, 60, inRange)
		if not prompt.Parent or not inRange() then
			powerCooldown = os.clock() + 0.2
			log("could not get in range of the Power Box prompt")
			return
		end
		local t = os.clock()
		setStatus("firing the Power Box prompt")
		while prompt.Parent and not prompt.Enabled and os.clock() - t < 15 do task.wait(0.2) end
		pcall(function() prompt.HoldDuration = 0 end)
		local shots = 0
		for _ = 1, 5 do
			if not prompt.Parent or not prompt.Enabled then break end
			pcall(fireproximityprompt, prompt)
			shots += 1
			task.wait(0.3)
		end
		fired = shots > 0
		powerCooldown = os.clock() + (fired and ((prompt.Parent and prompt.Enabled) and 30 or 0) or 10)
		log(fired and "Power Box prompt fired" or "Power Box prompt never became enabled")
	end)
	avoidOn = true
	if fired then setNoclip(false) end
	if not ok then
		warn("[FuelHauler] power box error: " .. tostring(err))
		powerCooldown = os.clock() + 15
	end
	return ok and fired
end
local function powerStatus()
	local list = powerPlants()
	if #list > 0 then return #list .. " power plants found" end
	local map = workspace:FindFirstChild("Map")
	local tiles = map and map:FindFirstChild("Tiles")
	if not tiles then return "workspace.Map.Tiles not found" end
	local names = {}
	for _, c in ipairs(tiles:GetChildren()) do
		if c.Name:lower():find("power") then table.insert(names, c.Name) end
	end
	return "no Power Box prompt found; Tiles children with 'power' in the name: "
		.. (#names > 0 and table.concat(names, ", ") or "none")
end
local function restartRound()
	local _, hum = getChar()
	setStatus("resetting, then PlayAgain")
	log("resetting the character")
	intentionalDeath = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
	local misc = remotes and remotes:WaitForChild("Misc", 5)
	local reset = misc and misc:WaitForChild("Reset", 5)
	if reset then
		pcall(function() reset:FireServer() end)
	else
		log("Reset remote not found, setting health to 0 instead")
		pcall(function() hum.Health = 0 end)
	end
	local start = os.clock()
	local presses = 0
	while alive() and os.clock() - start < 90 do
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local ui = pg and pg:FindFirstChild("DownedUI")
		local lost = ui and ui:FindFirstChild("Lost")
		local btn = lost and lost:FindFirstChild("PlayAgain")
		local shown = btn and ui.Enabled and lost.Visible and btn.Visible
		if shown and presses < 10 then
			presses += 1
			log("pressing PlayAgain (" .. presses .. ")")
			pressButton(btn)
			task.wait(1)
		elseif presses > 0 and not shown then
			break
		else
			task.wait(0.2)
		end
	end
	intentionalDeath = false
	log(presses > 0 and "PlayAgain pressed" or "PlayAgain button never appeared")
end
local stored = 0
local function collect(target, epoch)
	local lastNotice = -100
	local noFuelSince
	while stored < target and alive() and deathEpoch == epoch do
		flee()
		setStatus("collecting fuel " .. stored .. "/" .. target)
		local fuel
		local okF, resF = pcall(closestFuel)
		if okF then fuel = resF end
		if not fuel then
			noFuelSince = noFuelSince or os.clock()
			if os.clock() - noFuelSince > FUEL_WAIT and (phase > 1 or stored > 0) then
				log("no more fuel available, moving on with " .. stored .. " stored")
				return
			end
			if os.clock() - lastNotice > 10 then
				setStatus("waiting for fuel")
				log("waiting for fuel (" .. stored .. "/" .. target .. " stored) - " .. fuelStatus())
				lastNotice = os.clock()
			end
			task.wait(0.75)
		else
			noFuelSince = nil
			local t = os.clock()
			while fuel.Parent and fuel:GetAttribute("JustSpawned") == true and os.clock() - t < 5 do
				task.wait(0.2)
			end
			if grabOne(fuel) then
				stored += 1
				log("stored " .. stored .. "/" .. target)
			end
		end
	end
end
local function trip()
	local epoch = deathEpoch
	while phase <= #FUEL_TRIPS and alive() and deathEpoch == epoch do
		collect(math.min(FUEL_TRIPS[phase], BACKPACK_CAPACITY), epoch)
		while stored > 0 and alive() and deathEpoch == epoch do
			if goToZoneAndDrop(stored) then
				stored = 0
			else
				task.wait(2)
			end
		end
		if not alive() or deathEpoch ~= epoch then return end
		log("dropped batch " .. phase .. "/" .. #FUEL_TRIPS)
		phase += 1
	end
	if deathEpoch ~= epoch then return end
	local waitStart = os.clock()
	local lastPowerNotice = -100
	while alive() and deathEpoch == epoch and not powerDone and os.clock() - waitStart < POWER_WAIT do
		local target = pickPowerTarget()
		if target and doPowerBox(target) then
			powerDone = true
			break
		end
		flee()
		if os.clock() - lastPowerNotice > 10 then
			setStatus("waiting for the Power Box")
			log("waiting for the Power Box - " .. powerStatus())
			lastPowerNotice = os.clock()
		end
		task.wait(1)
	end
	if powerDone and alive() and deathEpoch == epoch then restartRound() end
end
local deathWatch = true
local function votePlayAgain()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local misc = remotes and remotes:FindFirstChild("Misc")
	local vote = misc and misc:FindFirstChild("VotePlayAgain")
	if not vote then
		log("VotePlayAgain remote not found")
		return
	end
	pcall(function() vote:FireServer() end)
	log("player is dead, VotePlayAgain fired")
end
local function anyVisibleChild(ui)
	for _, c in ipairs(ui:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then return true end
	end
	return false
end
local function isDeadNow()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead) then return true end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local ui = pg and pg:FindFirstChild("DownedUI")
	return ui ~= nil and ui.Enabled and anyVisibleChild(ui)
end
task.spawn(function()
	local fired = false
	local seen = false
	while alive() and deathWatch do
		local char = player.Character
		if char then seen = true end
		local dead = (seen and (not char or not char.Parent)) or isDeadNow()
		if dead and not fired then
			fired = true
			votePlayAgain()
			if not intentionalDeath then
				deathEpoch += 1
				stored = 0
				phase = 1
				powerDone = false
				powerTarget = nil
				powerCooldown = 0
				table.clear(failed)
				purgeBlockers(true)
				setNoclip(false)
				setStatus("died, starting over")
				log("died mid-way, starting over after respawn")
			end
		elseif not dead then
			fired = false
		end
		task.wait(0.25)
	end
end)
local threatMarks = {}
task.spawn(function()
	while alive() and running do
		for _, m in ipairs(threatMarks) do m:Destroy() end
		table.clear(threatMarks)
		if SHOW_THREATS then
			for _, p in ipairs(threatsWithin(15)) do
				makeDot(threatMarks, p, Color3.fromRGB(255, 40, 40), 2.5, 0.5)
			end
		end
		task.wait(0.3)
	end
	for _, m in ipairs(threatMarks) do m:Destroy() end
end)
log("scanning for fuel... " .. fuelStatus())
while alive() do
	local epoch = deathEpoch
	local ok, err = pcall(function()
		getChar()
		waitForCutscenes(90)
		trip()
	end)
	if not ok then
		warn("[FuelHauler] error (will retry): " .. tostring(err))
		task.wait(2)
	elseif deathEpoch ~= epoch then
		task.wait(1)
	elseif not LOOP_FOREVER then
		break
	else
		powerDone = false
		powerTarget = nil
		phase = 1
	end
end
deathWatch = false
setNoclip(false)
purgeBlockers(true)
speedActive = false
running = false
setStatus("finished")
clearDots()
if dotFolder then dotFolder:Destroy() end
print("[FuelHauler] finished")
