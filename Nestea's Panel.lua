-- Nestea Man's Panel (LocalScript)
-- Put in StarterPlayer > StarterPlayerScripts.
-- PC: RightShift = hide/show the menu (rebind it in the FLY tab).  Mobile: tap the round logo button at the top.
-- Features that have extra options show a black gear button on their right side: press it to open that feature's settings.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local IS_TOUCH = UserInputService.TouchEnabled

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local flyKey = Enum.KeyCode.F
local flySpeed = 50
local MIN_SPEED, MAX_SPEED = 1, 500
local flying = false
local espEnabled = false
local menuKey = Enum.KeyCode.RightShift -- key that hides / shows the menu (rebindable)
local aimKey = Enum.KeyCode.Q -- key that toggles / holds the aimbot (rebindable)
local resetKey = Enum.KeyCode.X -- key that resets your character (rebindable)
local listeningFor = nil -- "fly", "menu", "aim" or "reset" while waiting for a key press

local esp = {
	names = true,
	distance = true,
	health = true,
	tracers = false,
	teamColors = false,
	range = 2000,
	skeleton = false,
	-- extra options (changed from the gear settings of each ESP feature)
	fillT = 55,          -- highlight fill transparency in %
	outline = true,
	walls = true,        -- highlight through walls
	nameSize = 14,
	username = false,    -- show @username instead of display name
	meters = false,      -- distance in meters instead of studs
	distSize = 12,
	hpWidth = 70,        -- health bar width in %
	tracerThick = 2,
	tracerOrigin = 1,    -- 1 center, 2 bottom, 3 top
	hideTeam = false,
	skeletonThick = 2,
	box = false,
	boxThick = 2,
	boxFill = false,
	boxFillT = 70,       -- box fill transparency in %
	rgb = false,         -- RGB mode: every ESP element cycles through one color
	rgbSpeed = 30,
	-- colors (changed from the gear settings of each ESP feature)
	fillColor = Color3.fromRGB(255, 60, 60),
	outlineColor = Color3.fromRGB(255, 177, 177),
	nameColor = Color3.fromRGB(255, 157, 157),
	distColor = Color3.fromRGB(200, 200, 220),
	hpFull = Color3.fromRGB(60, 255, 120),
	hpLow = Color3.fromRGB(255, 70, 70),
	tracerColor = Color3.fromRGB(255, 60, 60),
	boxColor = Color3.fromRGB(255, 60, 60),
	boxFillColor = Color3.fromRGB(255, 60, 60),
	skeletonColor = Color3.fromRGB(255, 60, 60),
	customTeam = false,  -- use your own teammate / enemy colors instead of the game's team colors
	allyColor = Color3.fromRGB(60, 255, 120),
	enemyColor = Color3.fromRGB(255, 60, 60),
}

-- extra settings used by the gear panels (kept in one table to save local variables)
local Cfg = {
	boost = 3,
	accel = 10,
	bank = true,
	flyHold = false,
	jumpCd = 0,
	lastJump = 0,
	spinDir = 1,
	tpOffset = 3,
	fbBright = 2,
	lockTime = false,
	hideToast = true,
}
local SUI = {} -- settings panel API (gear button, open, close). Filled in below.

-- mobile fly buttons (read by the fly loop)
local mobUp, mobDown, mobBoost = false, false, false
local refreshMobile -- assigned in the mobile section

local minimized = false

------------------------------------------------------------
-- Theme / helpers
------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(14, 14, 20),
	panel = Color3.fromRGB(22, 22, 32),
	row = Color3.fromRGB(30, 30, 44),
	off = Color3.fromRGB(58, 58, 78),
	text = Color3.fromRGB(240, 240, 255),
	dim = Color3.fromRGB(150, 150, 175),
}
local WHITE = Color3.new(1, 1, 1)

local accentSet = {} -- [instance] = "PropertyName" (recolored with the theme accent, white by default)
local accentColor = WHITE

local currentTheme = { name = "Obsidian" } -- replaced when you pick a theme (WORLD tab)
local themed = setmetatable({}, { __mode = "k" }) -- [instance] = { {prop, colorKey}, ... }

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
		-- remember GUI colors that come from the C table so a theme can recolor them
		if (k == "BackgroundColor3" or k == "TextColor3" or k == "Color" or k == "ScrollBarImageColor3")
			and typeof(v) == "Color3" then
			for key, col in pairs(C) do
				if col == v then
					themed[i] = themed[i] or {}
					table.insert(themed[i], { k, key })
					break
				end
			end
		end
	end
	i.Parent = parent
	return i
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function tweenEx(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function tween(inst, t, props)
	return tweenEx(inst, t, props)
end

local playerGui = player:WaitForChild("PlayerGui")

local DEFAULT_POS = IS_TOUCH and UDim2.fromOffset(10, 10) or UDim2.fromOffset(20, 120)
local PANEL_SCALE = IS_TOUCH and math.clamp((camera.ViewportSize.Y - 24) / 430, 0.5, 1) or 1

------------------------------------------------------------
-- LOADING SCREEN (map camera, black banner + panel, arc gauge, PLAY button, SKIP button)
------------------------------------------------------------
local Loader = {}
do
	local rng = Random.new()

	-- easy tweaks -----------------------------------------------------------
	local BANNER_TOP = Color3.fromRGB(255, 117, 24)   -- banner color (top)  -> pumpkin orange
	local BANNER_BOT = Color3.fromRGB(58, 8, 74)      -- banner color (bottom) -> spooky purple
	local BANNER_TEXT = "🎃 NESTEA MAN'S PANEL 🧛"
	local WELCOME_TEXT = "HAPPY HALLOWEEN"
	local N_TICKS = 28                                -- segments of the loading arc
	local OVERLAY_TRANSPARENCY = 0.5                 -- higher = you see more of the map
	local CAM_SPEED = 0.1                             -- how fast the camera orbits the map
	local PANEL_LINES = {                             -- right side "updates" panel
		{ "🎃 UPDATES 🎃", 40, true },
		{ "🧛 Skybox Changer", 24, true },
		{ "🎃 Skin Changer (Visual)", 24, true },
		{ "🧛 FPS Display", 24, true },
		{ "🎃 Ping Display", 24, true },
		{ "🧛 Keystrokes", 24, true },
		{ "🎃 Keybinds", 24, true },
		{ "🧛 And MORE...", 24, true },
		{ "🎃 Features 🧛", 32, true },
		{ "Fly, ESP, Aim and Silent Aim\nNoclip, Click TP, Instant Prompts\nThemes, Fullbright, Anti-AFK", 13, false },
	}
	-------------------------------------------------------------------------

	local BLACK = Color3.new(0, 0, 0)
	local TICK_OFF = Color3.fromRGB(100, 100, 112)
	local ICE = Color3.fromRGB(255, 120, 0)
	local ORANGE = Color3.fromRGB(255, 120, 0)
	local PURPLE = Color3.fromRGB(25, 5, 35)

	local function randHex(n)
		local s = ""
		for _ = 1, n do s ..= string.format("%X", rng:NextInteger(0, 15)) end
		return s
	end

	------------------------------------------------------------
	-- Map camera (orbits the map while loading, no blur)
	------------------------------------------------------------
	local cam = { center = Vector3.new(0, 20, 0), radius = 120, t0 = os.clock() }

	function cam.scan()
		local chars = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then chars[p.Character] = true end
		end
		local lo, hi
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and not d:IsA("Terrain") and d.Size.Magnitude < 600 then
				local isChar, a = false, d.Parent
				while a and a ~= workspace do
					if chars[a] then isChar = true break end
					a = a.Parent
				end
				if not isChar then
					local p = d.Position
					lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
					hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
				end
			end
		end
		if lo and hi then
			cam.center = (lo + hi) / 2
			cam.radius = math.clamp((hi - lo).Magnitude * 0.5, 60, 400)
		else
			local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
			if spawn then cam.center = spawn.Position end
		end
	end

	function cam.start()
		pcall(cam.scan)
		cam.t0 = os.clock()
		task.delay(2.5, function() -- map may still be streaming in, scan again once
			if cam.on then pcall(cam.scan) end
		end)
		cam.on = true
		RunService:BindToRenderStep("NesteaLoadingCam", Enum.RenderPriority.Camera.Value + 2, function()
			camera.CameraType = Enum.CameraType.Scriptable
			local a = (os.clock() - cam.t0) * CAM_SPEED
			local pos = cam.center + Vector3.new(math.cos(a) * cam.radius, cam.radius * 0.45 + 15, math.sin(a) * cam.radius)
			camera.CFrame = CFrame.lookAt(pos, cam.center)
		end)
	end

	function cam.stop()
		if not cam.on then return end
		cam.on = false
		RunService:UnbindFromRenderStep("NesteaLoadingCam")
		camera.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
	end

	cam.start()

	------------------------------------------------------------
	-- UI
	------------------------------------------------------------
	local lg = new("ScreenGui", {
		Name = "NesteaLoading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- soft dark overlay (the map stays visible behind it, no blur)
	local root = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PURPLE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, lg)
	tweenEx(root, 0.8, { BackgroundTransparency = OVERLAY_TRANSPARENCY })

	-- floating dust particles
	local parts = {}
	local EMOJIS = { "🎃", "🧛" }
	for i = 1, 22 do
		local sz = rng:NextInteger(18, 34)
		local f = new("TextLabel", {
			Size = UDim2.fromOffset(sz + 10, sz + 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = EMOJIS[(i % #EMOJIS) + 1],
			TextSize = sz,
			TextTransparency = rng:NextNumber(0.35, 0.65),
			BorderSizePixel = 0,
		}, root)
		parts[i] = { f = f, x = rng:NextNumber(), y = rng:NextNumber(), v = rng:NextNumber(0.03, 0.08), w = rng:NextNumber(0.5, 2) }
	end

	-- animated elements: each fades / scales / slides in, and back out at the end
	local elems = {}
	local function elem(size, anchor, pos, startAt, slide, mult)
		local g = new("CanvasGroup", {
			Size = size,
			AnchorPoint = anchor,
			Position = pos,
			BackgroundTransparency = 1,
			GroupTransparency = 1,
		}, root)
		local u = new("UIScale", {}, g)
		local e = { g = g, u = u, pos = pos, startAt = startAt, slide = slide or Vector2.zero, mult = mult or 1, v = 0 }
		elems[#elems + 1] = e
		return e, g
	end

	-- white text with a black outline
	local function outlined(props, parent, thick)
		local l = new("TextLabel", props, parent)
		new("UIStroke", { Thickness = thick or 2.5, Color = BLACK, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
		return l
	end

	-- WELCOME TO
	local welcomeE, welcomeG = elem(UDim2.fromOffset(520, 64), Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.045), 0.35, Vector2.new(0, -30))
	outlined({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = WELCOME_TEXT,
		Font = Enum.Font.Creepster,
		TextSize = 52,
		TextColor3 = WHITE,
	}, welcomeG, 3)

	-- banner (black)
	local bannerE, bannerG = elem(UDim2.fromOffset(580, 112), Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.15), 0.55, Vector2.zero, 1)
	local shadow = new("Frame", {
		Size = UDim2.new(1, -4, 1, -10),
		Position = UDim2.fromOffset(2, 8),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, bannerG)
	corner(shadow, 16)
	local main = new("Frame", {
		Size = UDim2.new(1, -8, 1, -18),
		Position = UDim2.fromOffset(4, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, bannerG)
	corner(main, 14)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BANNER_TOP, BANNER_BOT) }, main)
	new("UIStroke", { Thickness = 3, Color = ORANGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, main)
	local gloss = new("Frame", {
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
	}, main)
	local sweep = new("Frame", {
		Size = UDim2.fromOffset(46, 220),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.2, 0, 0.5, 0),
		Rotation = 20,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
	}, main)
	outlined({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = BANNER_TEXT,
		Font = Enum.Font.Creepster,
		TextSize = 46,
		TextColor3 = WHITE,
	}, main, 3)

	-- updates panel (right side, black, white text + black outline)
	local panelE, panelG = elem(UDim2.fromOffset(310, 440), Vector2.new(1, 0.5), UDim2.new(1, -36, 0.5, 20), 0.75, Vector2.new(90, 0))
	local pbg = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(14, 0, 20),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, panelG)
	corner(pbg, 8)
	new("UIStroke", { Thickness = 2, Color = ORANGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pbg)
	local pcontent = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, panelG)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
	}, pcontent)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pcontent)
	for i, ln in ipairs(PANEL_LINES) do
		outlined({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = ln[1],
			Font = ln[3] and Enum.Font.Creepster or Enum.Font.GothamMedium,
			TextSize = ln[2],
			TextColor3 = ln[3] and Color3.fromRGB(255, 150, 40) or WHITE,
			TextWrapped = true,
			LayoutOrder = i,
		}, pcontent, ln[2] >= 28 and 2 or 1.2)
	end

	-- loading gauge (arc of segments), sits above the PLAY button
	local gaugeE, gaugeG = elem(UDim2.fromOffset(280, 190), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -110), 0.95, Vector2.new(0, 40))
	local CX, CY, R = 140, 130, 108
	local ticks = {}
	for i = 1, N_TICKS do
		local a = math.pi - (i - 1) / (N_TICKS - 1) * math.pi
		local f = new("Frame", {
			Size = UDim2.fromOffset(7, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CX + R * math.cos(a), CY - R * math.sin(a)),
			Rotation = 90 - math.deg(a),
			BackgroundColor3 = TICK_OFF,
			BorderSizePixel = 0,
		}, gaugeG)
		corner(f, 3)
		ticks[i] = f
	end
	local pct = outlined({
		Size = UDim2.fromOffset(120, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, CY - 40),
		BackgroundTransparency = 1,
		Text = "0%",
		Font = Enum.Font.Creepster,
		TextSize = 38,
		TextColor3 = WHITE,
	}, gaugeG, 2)
	local status = outlined({
		Size = UDim2.fromOffset(280, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(CX, CY - 12),
		BackgroundTransparency = 1,
		Text = "Awakening the darkness...",
		Font = Enum.Font.Creepster,
		TextSize = 20,
		TextColor3 = WHITE,
	}, gaugeG, 1.5)

	local tips = IS_TOUCH and {
		"🎃 Tap the round logo button to hide the panel",
		"🧛 UP / DOWN buttons control flying height",
		"🎃 Use the TP tab to visit other players",
		"🧛 3X boosts your fly speed",
	} or {
		"🎃 Press RightShift to hide the panel",
		"🧛 Hold Alt while flying for 3x speed",
		"🎃 Use the TP tab to visit other players",
		"🧛 Press the gear for spooky settings",
	}
	local tipLabel = outlined({
		Size = UDim2.fromOffset(280, 18),
		Position = UDim2.fromOffset(0, CY + 16),
		BackgroundTransparency = 1,
		Text = tips[1],
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 225),
	}, gaugeG, 1.2)

	-- PLAY button (bottom center, appears when loading reaches 100%)
	local ready, clicked = false, false
	local playE, playG = elem(UDim2.fromOffset(260, 72), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -26), math.huge, Vector2.new(0, 40))
	local playBtn = new("TextButton", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
	}, playG)
	corner(playBtn, 14)
	new("UIStroke", { Thickness = 3, Color = ORANGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, playBtn)
	outlined({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "🎃 PLAY 🧛",
		Font = Enum.Font.Creepster,
		TextSize = 40,
		TextColor3 = WHITE,
	}, playBtn, 3)
	playBtn.MouseEnter:Connect(function() tween(playBtn, 0.15, { BackgroundColor3 = Color3.fromRGB(70, 25, 90) }) end)
	playBtn.MouseLeave:Connect(function() tween(playBtn, 0.15, { BackgroundColor3 = BLACK }) end)
	playBtn.Activated:Connect(function()
		if ready then clicked = true end
	end)

	-- bottom-right small info
	local hudBR = new("TextLabel", {
		Size = UDim2.fromOffset(260, 16),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -14),
		BackgroundTransparency = 1,
		Text = "🧛 USER  " .. string.upper(player.DisplayName),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, root)

	local logLines = {}
	local function log(text)
		logLines[#logLines + 1] = text
		if #logLines > 20 then table.remove(logLines, 1) end
	end
	log("session " .. randHex(8))

	-- flash used for the finale
	local flash = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, root)

	------------------------------------------------------------
	-- Animation loop
	------------------------------------------------------------
	local shown, target = 0, 0
	local t0 = os.clock()
	local outro = false
	local tipIdx, nextTip = 1, t0 + 2.8
	local conn

	------------------------------------------------------------
	-- SKIP button (bottom-left): jumps the bar to 100% so PLAY appears right away
	------------------------------------------------------------
	local skipped = false
	local skipE, skipG = elem(UDim2.fromOffset(130, 44), Vector2.new(0, 1), UDim2.new(0, 24, 1, -24), 0.9, Vector2.new(-40, 0))
	local skipBtn = new("TextButton", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, skipG)
	corner(skipBtn, 12)
	new("UIStroke", { Thickness = 2, Color = ORANGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, skipBtn)
	outlined({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "SKIP >>",
		Font = Enum.Font.Creepster,
		TextSize = 24,
		TextColor3 = WHITE,
	}, skipBtn, 2)
	skipBtn.MouseEnter:Connect(function() tween(skipBtn, 0.15, { BackgroundColor3 = Color3.fromRGB(70, 25, 90) }) end)
	skipBtn.MouseLeave:Connect(function() tween(skipBtn, 0.15, { BackgroundColor3 = BLACK }) end)
	skipBtn.Activated:Connect(function()
		if skipped then return end
		skipped = true
		target = 1
		shown = 1
		status.Text = "Skipped!"
		skipBtn.Visible = false
	end)

	conn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local t = now - t0
		local vp = root.AbsoluteSize
		local base = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 1.25)

		-- progress easing
		shown += (target - shown) * (1 - math.exp(-dt * 2))
		if target - shown < 0.002 then shown = target end
		pct.Text = string.format("%d%%", math.floor(shown * 100 + 0.5))

		-- arc segments light up one by one
		local nOn = math.floor(shown * N_TICKS + 0.0001)
		for i, tk in ipairs(ticks) do
			if i <= nOn then
				local k = 0.5 + 0.5 * math.sin(t * 6 - i * 0.5)
				tk.BackgroundColor3 = ICE:Lerp(Color3.fromRGB(255, 225, 120), k * 0.7)
				tk.Size = UDim2.fromOffset(7, i == nOn and 26 or 22)
			else
				tk.BackgroundColor3 = TICK_OFF
				tk.Size = UDim2.fromOffset(7, 22)
			end
		end

		-- particles drift upward
		for _, p in ipairs(parts) do
			p.y -= p.v * dt
			if p.y < -0.05 then
				p.y = 1.05
				p.x = rng:NextNumber()
			end
			p.f.Position = UDim2.new(p.x + math.sin(t * p.w + p.x * 9) * 0.01, 0, p.y, 0)
		end

		-- banner shine sweep
		local ph = (t % 3.2) / 3.2
		sweep.Position = UDim2.new(-0.15 + ph * 1.4, 0, 0.5, 0)

		-- elements fade / scale / slide in (or out)
		for _, e in ipairs(elems) do
			local goal = (not outro and t >= e.startAt) and 1 or 0
			if outro then
				e.v += (goal - e.v) * (1 - math.exp(-dt * 7))
			elseif goal == 1 then
				e.v += (1 - e.v) * (1 - math.exp(-dt * 6))
			end
			e.g.GroupTransparency = 1 - e.v
			e.u.Scale = base * e.mult * (0.88 + 0.12 * e.v)
			e.g.Position = e.pos + UDim2.fromOffset(e.slide.X * (1 - e.v) * base, e.slide.Y * (1 - e.v) * base)
		end
		panelG.Visible = vp.X >= 760
		hudBR.Visible = vp.X >= 640 and not outro

		if now >= nextTip then
			tipIdx = tipIdx % #tips + 1
			tipLabel.Text = tips[tipIdx]
			nextTip = now + 2.8
		end
	end)

	------------------------------------------------------------
	-- API
	------------------------------------------------------------
	function Loader.log(text)
		log(text)
	end

	function Loader.setProgress(p, text)
		if skipped then return end
		target = math.max(target, math.clamp(p, 0, 1))
		if text and text ~= status.Text then
			status.Text = text
			log(text)
		end
	end

	-- like task.wait, but returns early when SKIP is pressed
	function Loader.wait(t)
		local e = os.clock() + t
		while not skipped and os.clock() < e do task.wait() end
	end

	-- waits for the PLAY button, then onReveal runs as everything fades out
	function Loader.finish(onReveal)
		target = 1
		local deadline = os.clock() + 6
		while shown < 0.999 and os.clock() < deadline do task.wait() end

		status.Text = "Press PLAY... if you dare"
		ready = true
		playBtn.Visible = true
		skipBtn.Visible = false
		playE.startAt = 0 -- the PLAY button fades in now
		while not clicked do task.wait() end
		playBtn.Active = false
		task.wait(0.1)

		tweenEx(flash, 0.12, { BackgroundTransparency = 0.7 })
		task.wait(0.12)
		cam.stop() -- camera goes back to your character (hidden behind the flash)
		tweenEx(flash, 0.5, { BackgroundTransparency = 1 })

		outro = true
		if onReveal then task.spawn(onReveal) end
		tweenEx(root, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		task.wait(0.9)
		conn:Disconnect()
		lg:Destroy()
	end
end

------------------------------------------------------------
-- GUI root (hidden until the loading screen finishes)
------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "NesteaMansPanel",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, playerGui)

-- Separate overlay for ESP tracers (ignores the top bar inset so coordinates line up)
local overlay = new("ScreenGui", {
	Name = "NesteaTracers",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -1,
}, playerGui)

local frame = new("Frame", {
	Size = UDim2.fromOffset(310, 420),
	Position = DEFAULT_POS,
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	Active = true,
	ClipsDescendants = true,
}, gui)
corner(frame, 14)

local scale = new("UIScale", { Scale = 0.6 }, frame)

-- White panel border (follows the theme accent)
local stroke = new("UIStroke", {
	Thickness = 2,
	Color = accentColor,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, frame)
accentSet[stroke] = "Color"

-- Subtle background gradient
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(24, 20, 38), Color3.fromRGB(10, 10, 16)),
}, frame)

-- Header
local header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 58),
	BackgroundTransparency = 1,
}, frame)

local title = new("TextLabel", {
	Size = UDim2.new(1, -90, 0, 28),
	Position = UDim2.fromOffset(16, 8),
	BackgroundTransparency = 1,
	Text = "NESTEA MAN'S PANEL 🎃",
	TextColor3 = WHITE,
	Font = Enum.Font.Creepster,
	TextSize = 23,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
new("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)

local subtitle = new("TextLabel", {
	Size = UDim2.new(1, -90, 0, 16),
	Position = UDim2.fromOffset(16, 34),
	BackgroundTransparency = 1,
	Text = "🧛 FLY  •  ESP  •  AIM  •  TOOLS",
	TextColor3 = C.dim,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local function headerButton(text, xFromRight)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -xFromRight, 0, 14),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		AutoButtonColor = false,
	}, header)
	corner(b, 8)
	b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.off }) end)
	b.MouseLeave:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.row }) end)
	return b
end
local minBtn = headerButton("–", 70)
local closeBtn = headerButton("×", 38)

-- Body (everything under the header, hidden when minimized)
local body = new("Frame", {
	Size = UDim2.new(1, 0, 1, -58),
	Position = UDim2.fromOffset(0, 58),
	BackgroundTransparency = 1,
}, frame)

-- Tabs
local tabBar = new("Frame", {
	Size = UDim2.new(1, -24, 0, 34),
	Position = UDim2.fromOffset(12, 0),
	BackgroundColor3 = C.panel,
	BorderSizePixel = 0,
}, body)
corner(tabBar, 10)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, tabBar)

local pages, tabButtons = {}, {}

local function makePage(name)
	local p = new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -52),
		Position = UDim2.fromOffset(12, 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.off,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, p)
	pages[name] = p
	return p
end

local function selectTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabButtons) do
		local active = n == name
		tween(b, 0.2, {
			BackgroundTransparency = active and 0 or 1,
			TextColor3 = active and WHITE or C.dim,
		})
	end
end

local function makeTab(name, label)
	local b = new("TextButton", {
		Size = UDim2.new(1 / 8, -4, 0, 26),
		BackgroundColor3 = C.off,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = label,
		TextColor3 = C.dim,
		Font = Enum.Font.GothamMedium,
		TextSize = 9,
		TextScaled = true,
		AutoButtonColor = false,
	}, tabBar)
	new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 9 }, b)
	corner(b, 8)
	b.MouseButton1Click:Connect(function() selectTab(name) end)
	tabButtons[name] = b
end

makeTab("main", "MAIN")
makeTab("fly", "FLY")
makeTab("esp", "ESP")
makeTab("aim", "AIM")
makeTab("me", "ME")
makeTab("world", "WORLD")
makeTab("tp", "TP")
makeTab("mob", "MOB")
local mainPage = makePage("main")
local flyPage = makePage("fly")
local espPage = makePage("esp")
local aimPage = makePage("aim")
local mePage = makePage("me")
local worldPage = makePage("world")
local tpPage = makePage("tp")
local mobPage = makePage("mob")
selectTab("main")

------------------------------------------------------------
-- Toast notifications
------------------------------------------------------------
local toast = new("TextLabel", {
	Size = UDim2.fromOffset(260, 34),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 40),
	BackgroundColor3 = C.bg,
	TextColor3 = C.text,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	Text = "",
	BorderSizePixel = 0,
}, gui)
corner(toast, 10)
local toastStroke = new("UIStroke", { Thickness = 1.5, Color = accentColor, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toast)
accentSet[toastStroke] = "Color"
local toastToken = 0

local function notify(text)
	toastToken += 1
	local t = toastToken
	toast.Text = text
	tween(toast, 0.35, { Position = UDim2.new(0.5, 0, 1, -30) })
	task.delay(1.8, function()
		if t == toastToken then
			tween(toast, 0.35, { Position = UDim2.new(0.5, 0, 1, 40) })
		end
	end)
end

------------------------------------------------------------
-- Gear button (BLACK button, white outlined gear)
------------------------------------------------------------
function SUI.gear(parent, spec, pos, anchor)
	local BLACK = Color3.new(0, 0, 0)
	local HOVER = Color3.fromRGB(38, 38, 46)
	local b = new("TextButton", {
		Name = "Gear",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = anchor,
		Position = pos,
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
	}, parent)
	corner(b, 8)
	new("UIStroke", { Thickness = 1, Color = Color3.fromRGB(70, 70, 85), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local pop = new("UIScale", {}, b)
	local icon = new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, b)

	local function part(w, h, rot, col, z, round)
		local f = new("Frame", {
			Size = UDim2.fromOffset(w, h),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rot,
			BackgroundColor3 = col,
			BorderSizePixel = 0,
			ZIndex = 4 + z,
		}, icon)
		new("UICorner", { CornerRadius = UDim.new(0, round) }, f)
	end
	-- white gear shape (8 teeth + body)
	for _, r in ipairs({ 0, 45, 90, 135 }) do part(6, 22, r, WHITE, 1, 1.5) end
	part(16, 16, 0, WHITE, 1, 8)
	-- black inside (leaves only a white outline, like the image)
	for _, r in ipairs({ 0, 45, 90, 135 }) do part(2.6, 18.6, r, BLACK, 2, 0.6) end
	part(12.4, 12.4, 0, BLACK, 2, 6.2)
	-- center ring
	part(10.4, 10.4, 0, WHITE, 3, 5.2)
	part(6.2, 6.2, 0, BLACK, 4, 3.1)

	b.MouseEnter:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = HOVER })
		tweenEx(icon, 0.35, { Rotation = 45 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = BLACK })
		icon.Rotation = icon.Rotation % 360
		tweenEx(icon, 0.3, { Rotation = 0 }, Enum.EasingStyle.Back)
	end)
	b.MouseButton1Click:Connect(function()
		pop.Scale = 0.8
		tweenEx(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		icon.Rotation = 0
		tweenEx(icon, 0.6, { Rotation = 360 }, Enum.EasingStyle.Back)
		if SUI.open then SUI.open(spec, b) end
	end)
	return b
end

------------------------------------------------------------
-- Widgets (every widget takes an optional "settings" spec -> adds the gear button
-- ONLY when that spec has a build function, i.e. the feature really has settings)
-- spec = { title, desc, build = function(parent, owner) end }
------------------------------------------------------------
local function makeToggle(parent, text, order, default, callback, settings)
	-- every top-level feature toggle gets a gear with a keybind (key + Toggle/Hold).
	-- toggles created inside a settings panel (SUI.collect is set) are sub-options and get none.
	if not SUI.collect and not (settings and settings.noBind) then
		settings = settings or {}
		local userBuild = settings.build
		settings.build = function(p, owner)
			if userBuild then userBuild(p, owner) end
			SUI.bindRows(p, owner, settings.title or text)
		end
	end
	if settings and not settings.build then settings = nil end -- no settings = no gear button
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 10)

	new("TextLabel", {
		Size = UDim2.new(1, settings and -104 or -70, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local track = new("Frame", {
		Size = UDim2.fromOffset(44, 22),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, settings and -42 or -12, 0.5, 0),
		BackgroundColor3 = C.off,
		BorderSizePixel = 0,
	}, row)
	corner(track, 11)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(knob, 8)

	-- click area covers the whole row (label + switch); the gear (ZIndex 3) sits on top of it
	local btn = new("TextButton", {
		Size = UDim2.new(1, settings and -40 or 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 2,
	}, row)

	local state = default
	local obj = { default = default }

	local function render()
		if state then
			accentSet[track] = "BackgroundColor3"
			tween(knob, 0.2, { Position = UDim2.new(1, -19, 0.5, 0), BackgroundColor3 = Color3.new(0, 0, 0) })
		else
			accentSet[track] = nil
			tween(track, 0.2, { BackgroundColor3 = C.off })
			tween(knob, 0.2, { Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = WHITE })
		end
	end

	function obj.set(v, silent)
		state = v
		render()
		if refreshMobile then refreshMobile() end
		if not silent and callback then callback(state) end
	end
	function obj.get() return state end

	btn.MouseButton1Click:Connect(function() obj.set(not state) end)
	render()

	if settings then
		settings.title = settings.title or text
		settings.owner = obj
		SUI.gear(row, settings, UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
	end
	if SUI.collect then SUI.collect[#SUI.collect + 1] = obj end
	return obj
end

local function makeSlider(parent, text, order, min, max, default, callback, settings)
	if settings and not settings.build then settings = nil end -- no settings = no gear button
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 10)

	new("TextLabel", {
		Size = UDim2.new(1, settings and -130 or -90, 0, 22),
		Position = UDim2.fromOffset(12, 6),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local valueBox = new("TextBox", {
		Size = UDim2.fromOffset(60, 22),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, settings and -42 or -12, 0, 6),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = tostring(default),
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		ClearTextOnFocus = false,
	}, row)
	corner(valueBox, 6)

	local bar = new("Frame", {
		Size = UDim2.new(1, -24, 0, 6),
		Position = UDim2.new(0, 12, 0, 40),
		BackgroundColor3 = C.off,
		BorderSizePixel = 0,
	}, row)
	corner(bar, 3)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
	}, bar)
	corner(fill, 3)
	accentSet[fill] = "BackgroundColor3"
	local knob = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, bar)
	corner(knob, 7)
	new("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, knob)

	local hit = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, -10),
		BackgroundTransparency = 1,
		Text = "",
	}, bar)

	local value = default
	local obj = { default = default }

	local function visual()
		local a = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valueBox.Text = tostring(value)
	end

	function obj.set(v, silent)
		v = tonumber(v)
		if not v then visual() return end
		value = math.clamp(math.floor(v + 0.5), min, max)
		visual()
		if not silent and callback then callback(value) end
	end
	function obj.get() return value end

	local dragging = false
	local function fromMouse(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		obj.set(min + a * (max - min))
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromMouse(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromMouse(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end)
	valueBox.FocusLost:Connect(function() obj.set(valueBox.Text) end)

	visual()

	if settings then
		settings.title = settings.title or text
		settings.owner = obj
		SUI.gear(row, settings, UDim2.new(1, -8, 0, 4), Vector2.new(1, 0))
	end
	if SUI.collect then SUI.collect[#SUI.collect + 1] = obj end
	return obj
end

local function makeButton(parent, text, order, callback, settings)
	if settings and not settings.build then settings = nil end -- no settings = no gear button
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		AutoButtonColor = false,
		LayoutOrder = order,
	}, parent)
	corner(b, 10)
	new("UIStroke", { Thickness = 1, Color = C.off, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.off }) end)
	b.MouseLeave:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.row }) end)
	b.MouseButton1Click:Connect(function()
		if callback then callback() end
	end)
	if settings then
		settings.title = settings.title or text
		SUI.gear(b, settings, UDim2.new(1, -6, 0.5, 0), Vector2.new(1, 0.5))
	end
	return b
end

local function makeHeading(parent, text, order)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = C.dim,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	}, parent)
end

------------------------------------------------------------
-- SETTINGS PANEL (opens over the page when a gear is pressed)
------------------------------------------------------------
do
	local cache = {} -- [spec] = ScrollingFrame with that feature's settings
	local current, busy = nil, false

	local panel = new("Frame", {
		Name = "SettingsPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 20,
	}, body)

	-- expanding circle that starts at the gear you pressed
	local ripple = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 21,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ripple)

	local bg = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 22,
	}, panel)

	local content = new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = 23,
	}, panel)

	local backBtn = new("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(12, 6),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "<",
		TextColor3 = Color3.new(0, 0, 0),
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		AutoButtonColor = false,
	}, content)
	corner(backBtn, 8)
	backBtn.MouseEnter:Connect(function() tween(backBtn, 0.15, { BackgroundColor3 = Color3.fromRGB(225, 225, 232) }) end)
	backBtn.MouseLeave:Connect(function() tween(backBtn, 0.15, { BackgroundColor3 = WHITE }) end)

	local ttl = new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 28),
		Position = UDim2.fromOffset(48, 6),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = accentColor,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, content)
	accentSet[ttl] = "TextColor3"

	local function buildScroll(spec)
		local sc = new("ScrollingFrame", {
			Size = UDim2.new(1, -24, 1, -50),
			Position = UDim2.fromOffset(12, 42),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = C.off,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
		}, content)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sc)
		if spec.desc then
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = spec.desc,
				TextColor3 = C.dim,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				LayoutOrder = 0,
			}, sc)
		end
		-- every toggle / slider created inside a settings panel is collected for "Reset all"
		SUI.collect = {}
		if spec.build then spec.build(sc, spec.owner) end
		local list = SUI.collect
		SUI.collect = nil
		if #list > 0 then
			makeButton(sc, "Reset all to default", 100, function()
				for _, o in ipairs(list) do o.set(o.default) end
				notify((spec.title or "Setting") .. ": reset")
			end)
		end
		return sc
	end

	function SUI.presets(p, owner, list, base)
		base = base or 0
		makeHeading(p, "PRESETS", base + 1)
		for i, e in ipairs(list) do
			makeButton(p, e[1] .. "  (" .. e[2] .. ")", base + 1 + i, function() owner.set(e[2]) end)
		end
	end

	function SUI.open(spec, gear)
		if busy or current then return end
		busy = true
		current = spec

		local sc = cache[spec]
		if not sc then
			sc = buildScroll(spec)
			cache[spec] = sc
		end
		for _, s in pairs(cache) do s.Visible = (s == sc) end

		local o = (gear.AbsolutePosition + gear.AbsoluteSize / 2 - body.AbsolutePosition) / math.max(scale.Scale, 0.01)

		ttl.Text = string.upper(spec.title or "SETTINGS") .. " SETTINGS"
		ttl.MaxVisibleGraphemes = 0
		content.GroupTransparency = 1
		content.Position = UDim2.fromOffset(0, 24)
		bg.BackgroundTransparency = 1
		ripple.BackgroundColor3 = accentColor
		ripple.BackgroundTransparency = 0
		ripple.Position = UDim2.fromOffset(o.X, o.Y)
		ripple.Size = UDim2.fromOffset(0, 0)
		ripple.Visible = true
		panel.Visible = true

		-- 1) circle bursts out of the gear
		tweenEx(ripple, 0.5, { Size = UDim2.fromOffset(1100, 1100) }, Enum.EasingStyle.Quart)
		-- 2) dark panel fades in over it
		task.delay(0.18, function()
			tweenEx(bg, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
		end)
		-- 3) content slides up + title types itself
		task.delay(0.3, function()
			if current ~= spec then return end
			tweenEx(content, 0.4, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
			task.spawn(function()
				local n = utf8.len(ttl.Text) or 0
				for i = 1, n do
					if current ~= spec then return end
					ttl.MaxVisibleGraphemes = i
					task.wait(0.018)
				end
				ttl.MaxVisibleGraphemes = -1
			end)
		end)
		task.delay(0.55, function()
			ripple.Visible = false
			busy = false
		end)
	end

	function SUI.close()
		if busy or not current then return end
		busy = true
		local spec = current
		-- panel fades away, revealing a circle that shrinks back into the page
		ripple.BackgroundColor3 = accentColor
		ripple.BackgroundTransparency = 0
		ripple.Size = UDim2.fromOffset(1100, 1100)
		ripple.Visible = true
		tweenEx(content, 0.22, { GroupTransparency = 1, Position = UDim2.fromOffset(40, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenEx(bg, 0.25, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		task.delay(0.2, function()
			tweenEx(ripple, 0.35, { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.3 }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		end)
		task.delay(0.58, function()
			panel.Visible = false
			ripple.Visible = false
			current = nil
			busy = false
		end)
	end

	backBtn.MouseButton1Click:Connect(function() SUI.close() end)
end

------------------------------------------------------------
-- Fly
------------------------------------------------------------
local bodyVel, bodyGyro
local curVel = Vector3.zero
local flyToggle, speedSlider, keyButton, menuKeyButton, aimKeyButton, resetKeyButton, aimToggle
local freezeToggle, setFreeze

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local function stopFly(silent)
	flying = false
	mobUp, mobDown = false, false
	if bodyVel then bodyVel:Destroy() bodyVel = nil end
	if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
	local _, hum = getRoot()
	if hum then hum.PlatformStand = false end
	curVel = Vector3.zero
	if flyToggle then flyToggle.set(false, true) end
	if refreshMobile then refreshMobile() end
	if not silent then notify("Fly: OFF") end
end

local function startFly()
	local root, hum = getRoot()
	if not root or not hum then
		if flyToggle then flyToggle.set(false, true) end
		return
	end
	flying = true
	curVel = Vector3.zero

	bodyVel = new("BodyVelocity", {
		MaxForce = Vector3.new(1e9, 1e9, 1e9),
		Velocity = Vector3.zero,
	}, root)
	bodyGyro = new("BodyGyro", {
		MaxTorque = Vector3.new(1e9, 1e9, 1e9),
		P = 9000,
		CFrame = camera.CFrame,
	}, root)
	hum.PlatformStand = true
	if setFreeze then setFreeze(false, true) end
	if flyToggle then flyToggle.set(true, true) end
	if refreshMobile then refreshMobile() end
	notify("Fly: ON")
end

local function toggleFly()
	if flying then stopFly() else startFly() end
end

-- Keybind rows (click, then press any key). They live inside the gear settings.
function SUI.keyRow(order, label, which, parent)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 10)
	new("TextLabel", {
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(100, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = (which == "fly" and flyKey or which == "aim" and aimKey or which == "reset" and resetKey or menuKey).Name,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = false,
	}, row)
	corner(btn, 6)
	btn.MouseButton1Click:Connect(function()
		-- clear any other button that was waiting for a key
		if keyButton then keyButton.Text = flyKey.Name end
		if menuKeyButton then menuKeyButton.Text = menuKey.Name end
		if aimKeyButton then aimKeyButton.Text = aimKey.Name end
		if resetKeyButton then resetKeyButton.Text = resetKey.Name end
		SUI.refreshBinds()
		listeningFor = which
		btn.Text = "press a key..."
	end)
	return btn
end

------------------------------------------------------------
-- Per-feature keybinds: every feature toggle gets a key + Toggle / Hold mode in its gear settings.
-- (Fly and Aimbot already have their own key + hold option, so they skip this.)
------------------------------------------------------------
SUI.feats = {} -- { obj, name, key, hold, btn } (filled the first time a feature's settings are opened)

function SUI.refreshBinds()
	if keyButton then keyButton.Text = flyKey.Name end
	if menuKeyButton then menuKeyButton.Text = menuKey.Name end
	if aimKeyButton then aimKeyButton.Text = aimKey.Name end
	if resetKeyButton then resetKeyButton.Text = resetKey.Name end
	for _, f in ipairs(SUI.feats) do
		if f.btn then f.btn.Text = f.key and f.key.Name or "None" end
	end
end

function SUI.assignFeatureKey(f, code)
	if code == Enum.KeyCode.Escape or code == Enum.KeyCode.Unknown then return end -- cancel
	if code == Enum.KeyCode.Backspace then
		f.key = nil
		notify(f.name .. ": key cleared")
		return
	end
	for _, k in ipairs({ { flyKey, "the fly key" }, { menuKey, "the hide menu key" }, { aimKey, "the aim key" }, { resetKey, "the reset key" } }) do
		if k[1] == code then
			notify(code.Name .. " is already " .. k[2])
			return
		end
	end
	for _, o in ipairs(SUI.feats) do
		if o ~= f and o.key == code then
			notify(code.Name .. " is already used by " .. o.name)
			return
		end
	end
	f.key = code
	notify(f.name .. " key: " .. code.Name .. " (" .. (f.hold and "hold" or "toggle") .. ")")
end

function SUI.bindRows(p, owner, name)
	local f = { obj = owner, name = name, key = nil, hold = false }
	SUI.feats[#SUI.feats + 1] = f

	makeHeading(p, "KEYBIND  (Backspace clears, Esc cancels)", 50)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = 51,
	}, p)
	corner(row, 10)
	new("TextLabel", {
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "Key",
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	f.btn = new("TextButton", {
		Size = UDim2.fromOffset(100, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = "None",
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = false,
	}, row)
	corner(f.btn, 6)
	f.btn.MouseButton1Click:Connect(function()
		SUI.refreshBinds() -- clear any other button that was waiting for a key
		listeningFor = f
		f.btn.Text = "press a key..."
	end)

	local mb
	mb = makeButton(p, "Key Mode: Toggle", 52, function()
		f.hold = not f.hold
		mb.Text = "Key Mode: " .. (f.hold and "Hold" or "Toggle")
		notify(name .. ": " .. (f.hold and "hold the key" or "press the key to toggle"))
	end)
	makeButton(p, "Clear Key", 53, function()
		f.key = nil
		SUI.refreshBinds()
		notify(name .. ": key cleared")
	end)
end

-- key released: Hold-mode features turn off again
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	for _, f in ipairs(SUI.feats) do
		if f.hold and f.key == input.KeyCode and f.obj.get() then
			f.obj.set(false)
		end
	end
end)

flyToggle = makeToggle(flyPage, "Fly", 1, false, function(on)
	if on then startFly() else stopFly() end
end, {
	noBind = true, -- has its own Fly Key + Hold To Fly
	desc = "Free flight. Speed, boost, key and feel are all here.",
	build = function(p)
		local sp = makeSlider(p, "Fly Speed", 1, MIN_SPEED, MAX_SPEED, flySpeed, function(v) flySpeed = v end)
		SUI.presets(p, sp, { { "Slow", 25 }, { "Normal", 50 }, { "Fast", 150 }, { "Insane", 400 } }, 1)
		makeSlider(p, "Boost Multiplier", 10, 1, 10, Cfg.boost, function(v) Cfg.boost = v end)
		makeSlider(p, "Acceleration", 11, 1, 30, Cfg.accel, function(v) Cfg.accel = v end)
		makeToggle(p, "Bank Tilt", 12, Cfg.bank, function(v) Cfg.bank = v end)
		makeToggle(p, "Hold To Fly", 13, Cfg.flyHold, function(v)
			Cfg.flyHold = v
			if not v and flying then stopFly(true) end
		end)
		keyButton = SUI.keyRow(14, "Fly Key", "fly", p)
		makeButton(p, "Reset Key To F", 15, function()
			flyKey = Enum.KeyCode.F
			keyButton.Text = flyKey.Name
			notify("Fly key: F")
		end)
	end,
})

makeButton(flyPage, "Hide Menu", 2, function()
	if Cfg.hideMenu then Cfg.hideMenu() end
end, {
	title = "Menu",
	desc = "Press the button to hide the panel. Change the key that hides / shows it here.",
	build = function(p)
		menuKeyButton = SUI.keyRow(1, "Hide Menu Key", "menu", p)
		makeToggle(p, "Toast When Hidden", 2, Cfg.hideToast, function(v) Cfg.hideToast = v end)
		makeButton(p, "Reset Key To RightShift", 3, function()
			menuKey = Enum.KeyCode.RightShift
			menuKeyButton.Text = menuKey.Name
			notify("Hide key: RightShift")
		end)
	end,
})

-- Discord: press the button to copy the invite link
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local DISCORD_LINK = "https://discord.gg/UN6P2GBdW9"

	-- fallback when the game can't write to the clipboard: a selectable box with the link
	local linkBox = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = DISCORD_LINK,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ClearTextOnFocus = false,
		TextEditable = false,
		Visible = false,
		LayoutOrder = 2,
	}, mainPage)
	corner(linkBox, 8)

	makeButton(mainPage, "Discord", 1, function()
		local copy = setclipboard or toclipboard
		local ok = false
		if copy then
			ok = pcall(copy, DISCORD_LINK)
		end
		if ok then
			notify("Discord link copied!")
		else
			-- Roblox doesn't allow normal scripts to touch the clipboard, so select the link for Ctrl+C
			linkBox.Visible = true
			linkBox:CaptureFocus()
			linkBox.CursorPosition = #DISCORD_LINK + 1
			linkBox.SelectionStart = 1
			notify(IS_TOUCH and "Hold the link to copy it" or "Link selected - press Ctrl+C")
		end
	end)
end

-- Skybox Changer (MAIN tab): swaps the sky for Space, Galaxy, Halloween and more. Only you see it.
-- Want your own pictures for Space / Galaxy? Upload the image to Roblox (create.roblox.com > Creations > Decals)
-- and paste its id between the quotes, like "rbxassetid://123456789". Left empty, a star + haze sky is used.
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local SKY_IMAGES = {
		Space = "",  -- the Milky Way picture
		Galaxy = "", -- the purple / pink lightning nebula picture
	}
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local sb = {
		on = false, idx = 1, stars = 5000, changeTime = true,
		sky = nil, atmo = nil, saved = nil, hiddenSkies = {}, hiddenAtmos = {},
	}
	-- tex = true uses Roblox's built-in sky pictures, false = pure black sky (stars only)
	-- atmo = { Density, Color, Decay, Glare, Haze }
	local PRESETS = {
		{ name = "Space", tex = false, clock = 0, sun = 0, moon = 0,
			atmo = { 0.18, rgb(95, 85, 120), rgb(70, 45, 40), 0, 1 } },
		{ name = "Galaxy", tex = false, clock = 0, sun = 0, moon = 0, shift = rgb(120, 60, 200),
			atmo = { 0.5, rgb(140, 70, 235), rgb(255, 60, 150), 0.1, 2.5 } },
		{ name = "Halloween Night", tex = false, clock = 0, sun = 0, moon = 20, shift = rgb(255, 120, 30),
			atmo = { 0.4, rgb(255, 120, 30), rgb(120, 40, 10), 0, 1.5 } },
		{ name = "Blood Moon", tex = false, clock = 0, sun = 0, moon = 20, shift = rgb(200, 20, 20),
			atmo = { 0.45, rgb(200, 20, 20), rgb(90, 0, 0), 0, 2 } },
		{ name = "Night", tex = true, clock = 0, sun = 21, moon = 11 },
		{ name = "Sunset", tex = true, clock = 17.8, sun = 21, moon = 11,
			atmo = { 0.3, rgb(255, 170, 110), rgb(255, 100, 60), 0.3, 1 } },
		{ name = "Dawn", tex = true, clock = 6, sun = 21, moon = 11,
			atmo = { 0.3, rgb(255, 190, 200), rgb(255, 130, 150), 0.2, 1 } },
		{ name = "Clear Day", tex = true, clock = 14, sun = 21, moon = 11 },
	}
	local FACES = { Bk = "bk", Dn = "dn", Ft = "ft", Lf = "lf", Rt = "rt", Up = "up" }
	local nextBtn

	function sb.label()
		if nextBtn then nextBtn.Text = "Next Skybox  (" .. PRESETS[sb.idx].name .. ")" end
	end

	function sb.apply()
		local P = PRESETS[sb.idx]
		if not sb.saved then
			sb.saved = { clock = Lighting.ClockTime, top = Lighting.ColorShift_Top, bottom = Lighting.ColorShift_Bottom }
			-- put the game's own sky / atmosphere aside until the feature is turned off
			for _, c in ipairs(Lighting:GetChildren()) do
				if c:IsA("Sky") then
					c.Parent = nil
					sb.hiddenSkies[#sb.hiddenSkies + 1] = c
				elseif c:IsA("Atmosphere") then
					c.Parent = nil
					sb.hiddenAtmos[#sb.hiddenAtmos + 1] = c
				end
			end
		end

		if not sb.sky then
			sb.sky = Instance.new("Sky")
			sb.sky.Name = "NesteaSky"
			sb.sky.Parent = Lighting
		end
		local sky = sb.sky
		local img = SKY_IMAGES[P.name] or ""
		for prop, face in pairs(FACES) do
			if img ~= "" then
				sky["Skybox" .. prop] = img -- your own picture on every side
			else
				sky["Skybox" .. prop] = P.tex and ("rbxasset://textures/sky/sky512_" .. face .. ".tex") or ""
			end
		end
		sky.CelestialBodiesShown = true
		sky.StarCount = sb.stars
		sky.SunAngularSize = P.sun
		sky.MoonAngularSize = P.moon

		if P.atmo then
			if not sb.atmo then
				sb.atmo = Instance.new("Atmosphere")
				sb.atmo.Name = "NesteaAtmosphere"
				sb.atmo.Parent = Lighting
			end
			local a = sb.atmo
			a.Density, a.Color, a.Decay, a.Glare, a.Haze = table.unpack(P.atmo)
			if img ~= "" then a.Density = 0 end -- a picture is shown clean, without haze
		elseif sb.atmo then
			sb.atmo:Destroy()
			sb.atmo = nil
		end

		if sb.changeTime then Lighting.ClockTime = P.clock end
		Lighting.ColorShift_Top = P.shift or sb.saved.top
		Lighting.ColorShift_Bottom = P.shift or sb.saved.bottom
	end

	function sb.restore()
		if not sb.saved then return end
		if sb.sky then
			sb.sky:Destroy()
			sb.sky = nil
		end
		if sb.atmo then
			sb.atmo:Destroy()
			sb.atmo = nil
		end
		for _, c in ipairs(sb.hiddenSkies) do c.Parent = Lighting end
		for _, c in ipairs(sb.hiddenAtmos) do c.Parent = Lighting end
		sb.hiddenSkies, sb.hiddenAtmos = {}, {}
		if sb.changeTime then Lighting.ClockTime = sb.saved.clock end
		Lighting.ColorShift_Top = sb.saved.top
		Lighting.ColorShift_Bottom = sb.saved.bottom
		sb.saved = nil
	end

	makeHeading(mainPage, "SKYBOX", 3)
	local tog
	tog = makeToggle(mainPage, "Skybox Changer", 4, false, function(v)
		sb.on = v
		if v then sb.apply() else sb.restore() end
		notify("Skybox: " .. (v and PRESETS[sb.idx].name or "OFF"))
	end, {
		desc = "Changes the sky (only you can see it). Pick a sky below or use the Next Skybox button on the main page.",
		build = function(p)
			makeHeading(p, "SKIES", 1)
			for i, P in ipairs(PRESETS) do
				makeButton(p, P.name, 1 + i, function()
					sb.idx = i
					sb.label()
					if tog.get() then
						sb.apply()
						notify("Skybox: " .. P.name)
					else
						tog.set(true)
					end
				end)
			end
			makeSlider(p, "Star Count", 20, 0, 5000, sb.stars, function(v)
				sb.stars = v
				if sb.on then sb.apply() end
			end)
			makeToggle(p, "Change Time Of Day Too", 21, sb.changeTime, function(v)
				sb.changeTime = v
				if sb.on then sb.apply() end
			end)
		end,
	})
	nextBtn = makeButton(mainPage, "Next Skybox", 5, function()
		sb.idx = sb.idx % #PRESETS + 1
		sb.label()
		if tog.get() then
			sb.apply()
			notify("Skybox: " .. PRESETS[sb.idx].name)
		else
			tog.set(true)
		end
	end)
	sb.label()
end

-- Skin Changer (MAIN tab, visual only): type a user ID (or a username) and your character wears their look.
-- Only you can see it (it is built on your own screen, other players still see your real skin).
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local sk = { userId = nil, keep = true, busy = false }

	-- puts one accessory (hair, hat...) on you and makes sure it is welded to the right body part
	function sk.addAcc(char, hum, acc)
		local clone = acc:Clone()
		if not pcall(function() hum:AddAccessory(clone) end) then
			clone.Parent = char
		end
		local handle = clone:FindFirstChild("Handle")
		if not handle then return end
		handle.Anchored = false
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.Massless = true

		local w = handle:FindFirstChild("AccessoryWeld")
		if w and w:IsA("Weld") and w.Part0 and w.Part0:IsDescendantOf(char) and w.Part1 == handle then
			return -- already attached correctly
		end
		-- build the weld ourselves: match the accessory's attachment (HairAttachment, HatAttachment...) to yours
		for _, d in ipairs(handle:GetChildren()) do
			if d:IsA("Weld") or d:IsA("WeldConstraint") then d:Destroy() end
		end
		local hatt = handle:FindFirstChildWhichIsA("Attachment")
		local target
		if hatt then
			for _, part in ipairs(char:GetChildren()) do
				if part:IsA("BasePart") then
					local a = part:FindFirstChild(hatt.Name)
					if a and a:IsA("Attachment") then
						target = a
						break
					end
				end
			end
		end
		local nw = Instance.new("Weld")
		nw.Name = "AccessoryWeld"
		nw.Part1 = handle
		if target then
			nw.Part0 = target.Parent
			nw.C0 = target.CFrame
			nw.C1 = hatt.CFrame
		else
			nw.Part0 = char:FindFirstChild("Head")
			nw.C0 = CFrame.new(0, 0.6, 0)
		end
		nw.Parent = handle
	end

	-- copies the look of a user onto your character (clothes, colors, accessories, face)
	function sk.put(userId)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			notify("Skin: no character yet")
			return false
		end

		-- method 1: download their appearance and copy it onto you by hand (works from a LocalScript)
		local ok, app = pcall(function() return Players:GetCharacterAppearanceAsync(userId) end)
		if ok and app then
			for _, c in ipairs(char:GetChildren()) do
				if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic")
					or c:IsA("BodyColors") or c:IsA("CharacterMesh") then
					c:Destroy()
				end
			end
			for _, c in ipairs(app:GetChildren()) do
				if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic")
					or c:IsA("BodyColors") or c:IsA("CharacterMesh") then
					c:Clone().Parent = char
				end
			end
			-- hair / hats / accessories
			local count = 0
			for _, d in ipairs(app:GetDescendants()) do
				if d:IsA("Accessory") then
					sk.addAcc(char, hum, d)
					count += 1
				end
			end
			-- nothing came with the appearance? build a model from their description and take the accessories from it
			if count == 0 then
				pcall(function()
					local desc = Players:GetHumanoidDescriptionFromUserId(userId)
					local dummy = Players:CreateHumanoidModelFromDescription(desc, hum.RigType)
					for _, d in ipairs(dummy:GetDescendants()) do
						if d:IsA("Accessory") then
							sk.addAcc(char, hum, d)
						end
					end
					dummy:Destroy()
				end)
			end
			-- face
			local faceSrc
			for _, d in ipairs(app:GetDescendants()) do
				if d:IsA("Decal") and d.Name:lower() == "face" then
					faceSrc = d
					break
				end
			end
			local head = char:FindFirstChild("Head")
			if faceSrc and head then
				local f = head:FindFirstChildOfClass("Decal")
				if f then
					f.Texture = faceSrc.Texture
				else
					faceSrc:Clone().Parent = head
				end
			end
			app:Destroy()
			return true
		end

		-- method 2 (backup): apply a HumanoidDescription
		local okD, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(userId) end)
		if okD and desc then
			local applied = pcall(function() hum:ApplyDescriptionReset(desc) end)
			if not applied then
				applied = pcall(function() hum:ApplyDescription(desc) end)
			end
			return applied
		end
		return false
	end

	-- input can be a user ID (numbers) or a username
	function sk.load(input)
		local text = (input or ""):match("^%s*@?(.-)%s*$")
		if text == "" then
			notify("Type a user ID first")
			return
		end
		if sk.busy then return end
		sk.busy = true
		notify("Skin: loading " .. text .. "...")
		task.spawn(function()
			local userId = text:match("^%d+$") and tonumber(text) or nil
			if not userId then
				local okId, id = pcall(function() return Players:GetUserIdFromNameAsync(text) end)
				userId = okId and id or nil
			end
			if not userId then
				notify("User not found: " .. text)
				sk.busy = false
				return
			end
			local okN, uname = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			if sk.put(userId) then
				sk.userId = userId
				notify("Skin: now wearing " .. (okN and uname or tostring(userId)))
			else
				notify("Couldn't load that skin (wrong ID?)")
			end
			sk.busy = false
		end)
	end

	function sk.reset()
		if sk.busy then return end
		sk.busy = true
		sk.userId = nil
		task.spawn(function()
			if sk.put(player.UserId) then
				notify("Skin: back to your own")
			else
				notify("Couldn't reset (respawn to get your skin back)")
			end
			sk.busy = false
		end)
	end

	makeHeading(mainPage, "SKIN CHANGER (VISUAL)", 7)

	-- user ID box
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = 8,
	}, mainPage)
	corner(row, 10)
	local box = new("TextBox", {
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Type a user ID (or username)...",
		PlaceholderColor3 = C.dim,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	corner(box, 8)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
	box.FocusLost:Connect(function(enter)
		if enter then sk.load(box.Text) end
	end)

	makeButton(mainPage, "Apply Skin", 9, function() sk.load(box.Text) end)
	makeButton(mainPage, "Reset To My Skin", 10, function() sk.reset() end)
	makeToggle(mainPage, "Keep Skin After Respawn", 11, sk.keep, function(v) sk.keep = v end, { noBind = true })

	-- re-apply the chosen skin when you respawn
	player.CharacterAdded:Connect(function(char)
		if not (sk.keep and sk.userId) then return end
		if not char:WaitForChild("Humanoid", 10) then return end
		task.wait(1.5) -- let the game finish dressing you first
		if sk.keep and sk.userId then sk.put(sk.userId) end
	end)
end

RunService.RenderStepped:Connect(function(dt)
	if not flying then return end
	local root, hum = getRoot()
	if not root or not bodyVel or not bodyGyro then return end

	local cf = camera.CFrame
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end

	-- Mobile / gamepad: thumbstick moves you along the camera direction
	if dir.Magnitude == 0 and hum and hum.MoveDirection.Magnitude > 0 then
		local md = hum.MoveDirection
		local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if flatLook.Magnitude > 0.001 then
			flatLook = flatLook.Unit
			local flatRight = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z).Unit
			dir += cf.LookVector * md:Dot(flatLook) + cf.RightVector * md:Dot(flatRight)
		else
			dir += md
		end
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) or mobUp then dir += Vector3.yAxis end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or mobDown then
		dir -= Vector3.yAxis
	end

	local boost = (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or mobBoost) and Cfg.boost or 1
	local target = dir.Magnitude > 0 and dir.Unit * flySpeed * boost or Vector3.zero
	-- Smooth acceleration / deceleration
	curVel = curVel:Lerp(target, 1 - math.exp(-dt * Cfg.accel))
	bodyVel.Velocity = curVel

	-- Slight bank into movement for style
	local bank = CFrame.Angles(0, 0, 0)
	if Cfg.bank and curVel.Magnitude > 1 then
		local side = curVel:Dot(cf.RightVector) / math.max(flySpeed, 1)
		bank = CFrame.Angles(0, 0, -side * 0.35)
	end
	bodyGyro.CFrame = cf * bank
end)

-- Hold-to-fly mode: releasing the fly key lands you
UserInputService.InputEnded:Connect(function(input)
	if Cfg.flyHold and flying and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == flyKey then
		stopFly()
	end
end)

player.CharacterAdded:Connect(function()
	bodyVel, bodyGyro = nil, nil
	flying = false
	mobUp, mobDown = false, false
	curVel = Vector3.zero
	flyToggle.set(false, true)
	if setFreeze then setFreeze(false, true) end
	if refreshMobile then refreshMobile() end
end)

------------------------------------------------------------
-- ESP
------------------------------------------------------------
local espObjects = {} -- [Player] = {highlight, billboard, nameLabel, distLabel, hpBar, hpFill, tracer, box, boxStroke, conn}

local function clearESP(plr)
	local d = espObjects[plr]
	if not d then return end
	if d.highlight then d.highlight:Destroy() end
	if d.billboard then d.billboard:Destroy() end
	if d.tracer then d.tracer:Destroy() end
	if d.box then d.box:Destroy() end
	if d.conn then d.conn:Disconnect() end
	espObjects[plr] = nil
end

local function applyESP(plr, char)
	local d = espObjects[plr]
	if not d then return end
	if d.highlight then d.highlight:Destroy() end
	if d.billboard then d.billboard:Destroy() end

	local head = char:WaitForChild("Head", 5)
	if not head or not espObjects[plr] then return end

	d.highlight = new("Highlight", {
		FillColor = Color3.fromRGB(255, 60, 60),
		OutlineColor = WHITE,
		FillTransparency = 0.55,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Adornee = char,
	}, char)

	d.billboard = new("BillboardGui", {
		Size = UDim2.fromOffset(160, 46),
		StudsOffset = Vector3.new(0, 2.8, 0),
		AlwaysOnTop = true,
		Adornee = head,
	}, head)

	d.nameLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.3,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Text = plr.DisplayName,
	}, d.billboard)

	d.hpBar = new("Frame", {
		Size = UDim2.new(0.7, 0, 0, 5),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 21),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BorderSizePixel = 0,
	}, d.billboard)
	corner(d.hpBar, 3)
	d.hpFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 255, 120),
		BorderSizePixel = 0,
	}, d.hpBar)
	corner(d.hpFill, 3)

	d.distLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 29),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		TextStrokeTransparency = 0.4,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		Text = "",
	}, d.billboard)
end

local function addESP(plr)
	if plr == player or espObjects[plr] then return end
	local d = {}
	espObjects[plr] = d
	d.tracer = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
	}, overlay)
	d.box = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, overlay)
	d.boxStroke = new("UIStroke", {
		Thickness = esp.boxThick,
		Color = WHITE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, d.box)
	d.conn = plr.CharacterAdded:Connect(function(char) applyESP(plr, char) end)
	if plr.Character then task.spawn(applyESP, plr, plr.Character) end
end

local espToggle
local function setESP(on, silent)
	espEnabled = on
	if espToggle then espToggle.set(on, true) end
	if refreshMobile then refreshMobile() end
	if on then
		for _, plr in ipairs(Players:GetPlayers()) do addESP(plr) end
	else
		for plr in pairs(espObjects) do clearESP(plr) end
	end
	if not silent then notify("ESP: " .. (on and "ON" or "OFF")) end
end

-- Color picker rows for a gear panel: preview + preset swatches + Red / Green / Blue sliders.
-- key = name of the Color3 field inside the esp table.
function SUI.colorRows(p, key, label, base)
	local function chan(v) return math.floor(v * 255 + 0.5) end
	local c0 = esp[key]
	makeHeading(p, label, base)

	local prev = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = base + 1,
	}, p)
	corner(prev, 10)
	new("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "Preview",
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, prev)
	local sw = new("Frame", {
		Size = UDim2.fromOffset(70, 20),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundColor3 = c0,
		BorderSizePixel = 0,
	}, prev)
	corner(sw, 6)
	new("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sw)

	local rowP = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = base + 2,
	}, p)
	corner(rowP, 10)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, rowP)

	local sr, sg, sbl
	local function upd()
		local c = Color3.fromRGB(sr.get(), sg.get(), sbl.get())
		esp[key] = c
		sw.BackgroundColor3 = c
	end
	local PRE = {
		{ 255, 60, 60 }, { 255, 140, 30 }, { 255, 230, 60 }, { 60, 255, 120 }, { 60, 220, 255},
		{ 70, 110, 255 }, { 170, 80, 255 }, { 255, 100, 200 }, { 255, 255, 255 },
	}
	for _, col in ipairs(PRE) do
		local b = new("TextButton", {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = Color3.fromRGB(col[1], col[2], col[3]),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		}, rowP)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			sr.set(col[1], true)
			sg.set(col[2], true)
			sbl.set(col[3], true)
			upd()
		end)
	end
	sr = makeSlider(p, "Red", base + 3, 0, 255, chan(c0.R), upd)
	sg = makeSlider(p, "Green", base + 4, 0, 255, chan(c0.G), upd)
	sbl = makeSlider(p, "Blue", base + 5, 0, 255, chan(c0.B), upd)
end

-- the color shared by every ESP part when RGB mode or team colors are on (nil = use each feature's own color)
function SUI.baseColor(plr, sameTeam)
	if esp.rgb then
		return Color3.fromHSV((os.clock() * esp.rgbSpeed / 100) % 1, 1, 1)
	elseif esp.teamColors and plr.Team then
		if esp.customTeam then
			return sameTeam and esp.allyColor or esp.enemyColor
		end
		return plr.TeamColor.Color
	end
	return nil
end

espToggle = makeToggle(espPage, "ESP", 1, false, function(on) setESP(on) end, {
	desc = "Highlights every player through walls. Highlight look, max range and RGB mode are here.",
	build = function(p)
		makeSlider(p, "Fill Transparency %", 1, 0, 100, esp.fillT, function(v) esp.fillT = v end)
		makeToggle(p, "Outline", 2, esp.outline, function(v) esp.outline = v end)
		makeToggle(p, "Through Walls", 3, esp.walls, function(v) esp.walls = v end)
		local rg = makeSlider(p, "Max Range", 10, 100, 5000, esp.range, function(v) esp.range = v end)
		SUI.presets(p, rg, { { "Close", 500 }, { "Medium", 1000 }, { "Far", 2000 }, { "Max", 5000 } }, 10)
		makeToggle(p, "RGB Mode (all ESP)", 20, esp.rgb, function(v) esp.rgb = v end)
		makeSlider(p, "RGB Speed", 21, 1, 200, esp.rgbSpeed, function(v) esp.rgbSpeed = v end)
		SUI.colorRows(p, "fillColor", "HIGHLIGHT FILL COLOR", 30)
		SUI.colorRows(p, "outlineColor", "HIGHLIGHT OUTLINE COLOR", 40)
	end,
})
makeToggle(espPage, "Names", 2, esp.names, function(v) esp.names = v end, {
	desc = "Shows the player name above their head.",
	build = function(p)
		makeSlider(p, "Text Size", 1, 8, 24, esp.nameSize, function(v) esp.nameSize = v end)
		makeToggle(p, "Use Username (not display name)", 2, esp.username, function(v) esp.username = v end)
		SUI.colorRows(p, "nameColor", "NAME COLOR", 30)
	end,
})
makeToggle(espPage, "Distance", 3, esp.distance, function(v) esp.distance = v end, {
	desc = "Shows how far each player is from you.",
	build = function(p)
		makeToggle(p, "Meters Instead Of Studs", 1, esp.meters, function(v) esp.meters = v end)
		makeSlider(p, "Text Size", 2, 8, 20, esp.distSize, function(v) esp.distSize = v end)
		SUI.colorRows(p, "distColor", "DISTANCE COLOR", 30)
	end,
})
makeToggle(espPage, "Health Bars", 4, esp.health, function(v) esp.health = v end, {
	desc = "Shows a health bar under the name.",
	build = function(p)
		makeSlider(p, "Bar Width %", 1, 30, 100, esp.hpWidth, function(v) esp.hpWidth = v end)
		SUI.colorRows(p, "hpFull", "FULL HEALTH COLOR", 30)
		SUI.colorRows(p, "hpLow", "LOW HEALTH COLOR", 40)
	end,
})
makeToggle(espPage, "Tracers", 5, esp.tracers, function(v) esp.tracers = v end, {
	desc = "Draws a line from the screen to every player.",
	build = function(p)
		makeSlider(p, "Line Thickness", 1, 1, 8, esp.tracerThick, function(v) esp.tracerThick = v end)
		local names = { "Center", "Bottom", "Top" }
		local ob
		ob = makeButton(p, "Start Point: " .. names[esp.tracerOrigin], 2, function()
			esp.tracerOrigin = esp.tracerOrigin % 3 + 1
			ob.Text = "Start Point: " .. names[esp.tracerOrigin]
		end)
		SUI.colorRows(p, "tracerColor", "TRACER COLOR", 30)
	end,
})
makeToggle(espPage, "Team Colors", 6, esp.teamColors, function(v) esp.teamColors = v end, {
	desc = "Colors players by their team.",
	build = function(p)
		makeToggle(p, "Hide Teammates", 1, esp.hideTeam, function(v) esp.hideTeam = v end)
		makeToggle(p, "Use My Own Colors Below", 2, esp.customTeam, function(v) esp.customTeam = v end)
		SUI.colorRows(p, "allyColor", "TEAMMATE COLOR", 30)
		SUI.colorRows(p, "enemyColor", "ENEMY COLOR", 40)
	end,
})
makeToggle(espPage, "Box", 8, esp.box, function(v) esp.box = v end, {
	desc = "Draws a 2D box around every player.",
	build = function(p)
		makeSlider(p, "Line Thickness", 1, 1, 8, esp.boxThick, function(v) esp.boxThick = v end)
		makeToggle(p, "Box Fill", 2, esp.boxFill, function(v) esp.boxFill = v end)
		makeSlider(p, "Fill Transparency %", 3, 0, 100, esp.boxFillT, function(v) esp.boxFillT = v end)
		SUI.colorRows(p, "boxColor", "BOX LINE COLOR", 30)
		SUI.colorRows(p, "boxFillColor", "BOX FILL COLOR", 40)
	end,
})
makeToggle(espPage, "Skeleton", 9, esp.skeleton, function(v) esp.skeleton = v end, {
	desc = "Draws the bones of every player.",
	build = function(p)
		makeSlider(p, "Line Thickness", 1, 1, 8, esp.skeletonThick, function(v) esp.skeletonThick = v end)
		SUI.colorRows(p, "skeletonColor", "SKELETON COLOR", 30)
	end,
})

Players.PlayerAdded:Connect(function(plr) if espEnabled then addESP(plr) end end)
Players.PlayerRemoving:Connect(clearESP)

-- Skeleton ESP: draws the bones of every player as 2D lines (R15 and R6 rigs)
do
	local R15 = {
		{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
		{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
		{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
		{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
		{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
	}
	local R6 = {
		{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
		{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
	}
	local pools = {} -- [Player] = { Frame, ... }
	local active = false

	local function getLine(plr, i)
		local pool = pools[plr]
		if not pool then
			pool = {}
			pools[plr] = pool
		end
		local l = pool[i]
		if not l then
			l = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Visible = false,
			}, overlay)
			pool[i] = l
		end
		return l
	end

	local function hidePool(plr, from)
		local pool = pools[plr]
		if not pool then return end
		for i = from, #pool do pool[i].Visible = false end
	end

	Players.PlayerRemoving:Connect(function(plr)
		local pool = pools[plr]
		if pool then
			for _, l in ipairs(pool) do l:Destroy() end
			pools[plr] = nil
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not (espEnabled and esp.skeleton) then
			if active then
				for plr in pairs(pools) do hidePool(plr, 1) end
				active = false
			end
			return
		end
		active = true

		local myRoot = getRoot()

		for plr in pairs(espObjects) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local dist = (root and myRoot) and (root.Position - myRoot.Position).Magnitude or math.huge
			local sameTeam = plr.Team ~= nil and plr.Team == player.Team

			if not root or not hum or hum.Health <= 0 or dist > esp.range or (esp.hideTeam and sameTeam) then
				hidePool(plr, 1)
			else
				local color = SUI.baseColor(plr, sameTeam) or esp.skeletonColor

				local bones = char:FindFirstChild("UpperTorso") and R15 or R6
				for i, bone in ipairs(bones) do
					local line = getLine(plr, i)
					local a = char:FindFirstChild(bone[1])
					local b = char:FindFirstChild(bone[2])
					local shown = false
					if a and b then
						local pa = camera:WorldToViewportPoint(a.Position)
						local pb = camera:WorldToViewportPoint(b.Position)
						if pa.Z > 0 and pb.Z > 0 then
							local A, B = Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y)
							local d = B - A
							line.Size = UDim2.fromOffset(d.Magnitude + 1, esp.skeletonThick)
							line.Position = UDim2.fromOffset((A.X + B.X) / 2, (A.Y + B.Y) / 2)
							line.Rotation = math.deg(math.atan2(d.Y, d.X))
							line.BackgroundColor3 = color
							shown = true
						end
					end
					line.Visible = shown
				end
				hidePool(plr, #bones + 1)
			end
		end
	end)
end

------------------------------------------------------------
-- Per-frame updates (ESP info + rainbow accent + border spin)
------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	-- theme accent (white by default)
	accentColor = currentTheme.accent or WHITE
	for inst, prop in pairs(accentSet) do
		inst[prop] = accentColor
	end
	subtitle.TextColor3 = accentColor:Lerp(C.dim, 0.35)

	if not espEnabled then return end
	local myRoot = getRoot()
	if not myRoot then return end

	local vp = camera.ViewportSize
	local origin = Vector2.new(vp.X / 2, esp.tracerOrigin == 1 and vp.Y / 2 or (esp.tracerOrigin == 2 and vp.Y or 0))

	for plr, d in pairs(espObjects) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		if not root or not d.billboard then
			if d.tracer then d.tracer.Visible = false end
			if d.box then d.box.Visible = false end
			continue
		end

		local dist = (root.Position - myRoot.Position).Magnitude
		local sameTeam = plr.Team ~= nil and plr.Team == player.Team
		local inRange = dist <= esp.range and not (esp.hideTeam and sameTeam)

		-- Color (RGB mode / team colors win; otherwise each feature uses its own color)
		local base = SUI.baseColor(plr, sameTeam)

		d.highlight.Enabled = inRange
		d.billboard.Enabled = inRange
		d.highlight.FillColor = base or esp.fillColor
		d.highlight.OutlineColor = base and base:Lerp(WHITE, 0.6) or esp.outlineColor
		d.highlight.FillTransparency = esp.fillT / 100
		d.highlight.OutlineTransparency = esp.outline and 0 or 1
		d.highlight.DepthMode = esp.walls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded

		if inRange then
			d.nameLabel.Visible = esp.names
			d.nameLabel.Text = esp.username and plr.Name or plr.DisplayName
			d.nameLabel.TextSize = esp.nameSize
			d.nameLabel.TextColor3 = base and base:Lerp(WHITE, 0.5) or esp.nameColor
			d.distLabel.Visible = esp.distance
			d.distLabel.TextSize = esp.distSize
			d.distLabel.TextColor3 = esp.distColor
			if esp.meters then
				d.distLabel.Text = string.format("[%dm]", math.floor(dist * 0.28))
			else
				d.distLabel.Text = string.format("[%d studs]", math.floor(dist))
			end

			d.hpBar.Visible = esp.health
			d.hpBar.Size = UDim2.new(esp.hpWidth / 100, 0, 0, 5)
			if hum and hum.MaxHealth > 0 then
				local r = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
				d.hpFill.Size = UDim2.fromScale(r, 1)
				d.hpFill.BackgroundColor3 = esp.hpLow:Lerp(esp.hpFull, r)
			end
		end

		-- Tracer
		local t = d.tracer
		if esp.tracers and inRange then
			local pos, onScreen = camera:WorldToViewportPoint(root.Position)
			if onScreen and pos.Z > 0 then
				local target = Vector2.new(pos.X, pos.Y)
				local delta = target - origin
				t.Size = UDim2.fromOffset(delta.Magnitude, esp.tracerThick)
				t.Position = UDim2.fromOffset((origin.X + target.X) / 2, (origin.Y + target.Y) / 2)
				t.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				t.BackgroundColor3 = base or esp.tracerColor
				t.Visible = true
			else
				t.Visible = false
			end
		else
			t.Visible = false
		end

		-- Box
		local bx = d.box
		if bx then
			local drawn = false
			if esp.box and inRange and char then
				local cf, size = char:GetBoundingBox()
				local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
				local allFront = true
				for ix = -1, 1, 2 do
					for iy = -1, 1, 2 do
						for iz = -1, 1, 2 do
							local wp = (cf * CFrame.new(size.X / 2 * ix, size.Y / 2 * iy, size.Z / 2 * iz)).Position
							local sp = camera:WorldToViewportPoint(wp)
							if sp.Z <= 0 then allFront = false end
							minX = math.min(minX, sp.X)
							minY = math.min(minY, sp.Y)
							maxX = math.max(maxX, sp.X)
							maxY = math.max(maxY, sp.Y)
						end
					end
				end
				if allFront then
					bx.Position = UDim2.fromOffset(minX, minY)
					bx.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
					d.boxStroke.Thickness = esp.boxThick
					d.boxStroke.Color = base or esp.boxColor
					bx.BackgroundColor3 = base or esp.boxFillColor
					bx.BackgroundTransparency = esp.boxFill and (esp.boxFillT / 100) or 1
					drawn = true
				end
			end
			bx.Visible = drawn
		end
	end
end)

------------------------------------------------------------
-- FPS / ping readout in the header
------------------------------------------------------------
local stats = new("TextLabel", {
	Size = UDim2.fromOffset(140, 14),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 43),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = C.dim,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
}, header)
do
	local Stats = game:GetService("Stats")
	local acc, frames = 0, 0

	-- real ping = the same "Data Ping" value Roblox shows in its own performance stats (round trip, in ms)
	local function getPing()
		local ok, value = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and type(value) == "number" then
			return math.floor(value + 0.5)
		end
		return math.floor(player:GetNetworkPing() * 2000) -- fallback estimate
	end

	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		frames += 1
		if acc >= 0.5 then
			stats.Text = string.format("%d FPS  •  Ping %d", math.floor(frames / acc + 0.5), getPing())
			acc, frames = 0, 0
		end
	end)
end

------------------------------------------------------------
-- ME tab
------------------------------------------------------------
local frozen = false
setFreeze = function(on, silent)
	local root = getRoot()
	if on and not root then
		if freezeToggle then freezeToggle.set(false, true) end
		return
	end
	frozen = on
	if on then
		if flying then stopFly(true) end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	elseif root then
		root.Anchored = false
	end
	if freezeToggle then freezeToggle.set(on, true) end
	if not silent then notify("Freeze: " .. (on and "ON" or "OFF")) end
end
freezeToggle = makeToggle(mePage, "Freeze Character", 1, false, function(on) setFreeze(on) end, {
	desc = "Anchors your character in place. Turning on Fly un-freezes you.",
})

local noclip = false
local noclipToggle = makeToggle(mePage, "Noclip", 2, false, function(v)
	noclip = v
	notify("Noclip: " .. (v and "ON" or "OFF"))
	if refreshMobile then refreshMobile() end
end, {
	desc = "Walk through walls and objects. Turn it off to collide again.",
})
RunService.Stepped:Connect(function()
	if not noclip then return end
	local char = player.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
		end
	end
end)

local infJump = false
local infJumpToggle = makeToggle(mePage, "Infinite Jump", 3, false, function(v)
	infJump = v
	notify("Infinite Jump: " .. (v and "ON" or "OFF"))
end, {
	desc = "Jump again in mid-air as many times as you want.",
	build = function(p)
		makeSlider(p, "Cooldown (ms)", 1, 0, 1000, Cfg.jumpCd, function(v) Cfg.jumpCd = v end)
	end,
})
UserInputService.JumpRequest:Connect(function()
	if not infJump then return end
	if os.clock() - Cfg.lastJump < Cfg.jumpCd / 1000 then return end
	Cfg.lastJump = os.clock()
	local _, hum = getRoot()
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local spin, spinSpeed = false, 10
makeToggle(mePage, "Spin", 4, false, function(v)
	spin = v
	notify("Spin: " .. (v and "ON" or "OFF"))
end, {
	desc = "Spins your character around. Speed and direction are here.",
	build = function(p)
		local s = makeSlider(p, "Spin Speed", 1, 1, 100, spinSpeed, function(v) spinSpeed = v end)
		SUI.presets(p, s, { { "Slow", 5 }, { "Normal", 10 }, { "Fast", 40 }, { "Insane", 100 } }, 1)
		makeToggle(p, "Reverse Direction", 10, Cfg.spinDir < 0, function(v) Cfg.spinDir = v and -1 or 1 end)
	end,
})
RunService.RenderStepped:Connect(function(dt)
	if not spin or flying or frozen then return end
	local root = getRoot()
	if root then
		root.CFrame *= CFrame.Angles(0, math.rad(spinSpeed * 36 * dt) * Cfg.spinDir, 0)
	end
end)

local wsOn, wsValue = false, 16
local jpOn, jpValue = false, 50
local wsToggle = makeToggle(mePage, "Custom WalkSpeed", 6, false, function(v)
	wsOn = v
	if not v then
		local _, hum = getRoot()
		if hum then hum.WalkSpeed = 16 end
	end
end, {
	desc = "Uses your own walk speed instead of the game's (default is 16). Set the speed here.",
	build = function(p)
		local s = makeSlider(p, "WalkSpeed", 1, 0, 300, 16, function(v) wsValue = v end)
		s.set(wsValue, true)
		Cfg.wsSlider = s
		SUI.presets(p, s, { { "Default", 16 }, { "Fast", 50 }, { "Very Fast", 100 }, { "Insane", 200 } }, 1)
	end,
})
makeToggle(mePage, "Custom JumpPower", 8, false, function(v)
	jpOn = v
	if not v then
		local _, hum = getRoot()
		if hum then hum.JumpPower = 50 end
	end
end, {
	desc = "Uses your own jump height instead of the game's (default is 50). Set the power here.",
	build = function(p)
		local s = makeSlider(p, "JumpPower", 1, 0, 300, 50, function(v) jpValue = v end)
		s.set(jpValue, true)
		SUI.presets(p, s, { { "Default", 50 }, { "High", 100 }, { "Very High", 200 }, { "Rocket", 300 } }, 1)
	end,
})
RunService.Heartbeat:Connect(function()
	local _, hum = getRoot()
	if not hum then return end
	if wsOn then hum.WalkSpeed = wsValue end
	if jpOn then
		hum.UseJumpPower = true
		hum.JumpPower = jpValue
	end
end)

local clickTp = false
local clickTpToggle = makeToggle(mePage, "Click TP (Ctrl+Click / Tap)", 10, false, function(v)
	clickTp = v
	notify("Click TP: " .. (v and "ON" or "OFF"))
end, {
	title = "Click TP",
	desc = "Ctrl+Click (PC) or tap (mobile) anywhere in the world to teleport there.",
	build = function(p)
		makeSlider(p, "Height Offset", 1, 0, 20, Cfg.tpOffset, function(v) Cfg.tpOffset = v end)
	end,
})
mouse.Button1Down:Connect(function()
	if not clickTp or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
	local root = getRoot()
	if root and mouse.Hit then
		root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, Cfg.tpOffset, 0))
	end
end)
-- Mobile: tap anywhere in the world to teleport there
UserInputService.TouchTapInWorld:Connect(function(pos, processed)
	if processed or not clickTp or Cfg.tapTp then return end
	local root = getRoot()
	if not root then return end
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if res then
		root.CFrame = CFrame.new(res.Position + Vector3.new(0, Cfg.tpOffset, 0))
	end
end)

-- Click TP (Mobile): tap anywhere in the world to teleport there.
-- A quick tap teleports; dragging the camera, pinching or tapping on buttons does not.
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local tap = { on = false, input = nil, active = {}, n = 0, start = Vector2.zero, t0 = 0, maxMove = 14, maxTime = 0.4 }

	local function go(pos)
		local root = getRoot()
		if not root then return end
		local ray = camera:ViewportPointToRay(pos.X, pos.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		if res then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(res.Position + Vector3.new(0, Cfg.tpOffset, 0))
		end
	end

	Cfg.tapToggle = makeToggle(mePage, "Click TP (Mobile Tap)", 10, false, function(v)
		tap.on = v
		Cfg.tapTp = v -- the normal Click TP then leaves taps to this one
		notify("Click TP (Mobile): " .. (v and "ON" or "OFF"))
		if refreshMobile then refreshMobile() end
	end, {
		title = "Click TP (Mobile)",
		desc = "Tap anywhere in the world to teleport there. A quick tap teleports, dragging the camera does not.",
		build = function(p)
			makeSlider(p, "Height Offset", 1, 0, 20, Cfg.tpOffset, function(v) Cfg.tpOffset = v end)
			makeSlider(p, "Tap Tolerance (px)", 2, 4, 40, tap.maxMove, function(v) tap.maxMove = v end)
			makeSlider(p, "Max Tap Time (x0.01s)", 3, 10, 100, math.floor(tap.maxTime * 100), function(v) tap.maxTime = v / 100 end)
		end,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Touch or processed then return end
		tap.active[input] = true
		tap.n += 1
		if tap.n > 1 then
			tap.input = nil -- two fingers (pinch / zoom): not a tap
		else
			tap.input = input
			tap.start = Vector2.new(input.Position.X, input.Position.Y)
			tap.t0 = os.clock()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or not tap.active[input] then return end
		tap.active[input] = nil
		tap.n = math.max(tap.n - 1, 0)
		if input ~= tap.input then return end
		tap.input = nil
		if not tap.on then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if (pos - tap.start).Magnitude <= tap.maxMove and os.clock() - tap.t0 <= tap.maxTime then
			go(pos)
		end
	end)
end

-- Instant Proximity Prompts: every ProximityPrompt in the world gets HoldDuration = 0
local instantPrompts = false
local promptOrig = {} -- [ProximityPrompt] = original HoldDuration
local promptConn = {} -- [ProximityPrompt] = { changed, destroying }

local function forgetPrompt(prompt)
	local c = promptConn[prompt]
	if c then
		c[1]:Disconnect()
		c[2]:Disconnect()
	end
	promptConn[prompt], promptOrig[prompt] = nil, nil
end

local function instantize(inst)
	if not inst:IsA("ProximityPrompt") or promptConn[inst] then return end
	promptOrig[inst] = inst.HoldDuration
	inst.HoldDuration = 0
	promptConn[inst] = {
		-- if the server changes it again, keep it instant (and remember the new original)
		inst:GetPropertyChangedSignal("HoldDuration"):Connect(function()
			if instantPrompts and inst.HoldDuration ~= 0 then
				promptOrig[inst] = inst.HoldDuration
				inst.HoldDuration = 0
			end
		end),
		inst.Destroying:Connect(function() forgetPrompt(inst) end),
	}
end

local function setInstantPrompts(on)
	instantPrompts = on
	if on then
		for _, d in ipairs(workspace:GetDescendants()) do instantize(d) end
	else
		local list = {}
		for prompt, hd in pairs(promptOrig) do list[#list + 1] = { prompt, hd } end
		for _, e in ipairs(list) do
			if e[1].Parent then e[1].HoldDuration = e[2] end
			forgetPrompt(e[1])
		end
	end
end
workspace.DescendantAdded:Connect(function(d)
	if instantPrompts then instantize(d) end
end)

local instantToggle = makeToggle(mePage, "Instant Prompts", 11, false, function(v)
	setInstantPrompts(v)
	notify("Instant Prompts: " .. (v and "ON" or "OFF"))
	if refreshMobile then refreshMobile() end
end, {
	desc = "Every hold-to-interact prompt in the world activates instantly. Turn it off to restore them.",
})

local function resetCharacter()
	local _, hum = getRoot()
	if hum then hum.Health = 0 end
end
makeButton(mePage, "Reset Character", 12, resetCharacter, {
	desc = "Respawns your character. Set the key that resets you here.",
	build = function(p)
		resetKeyButton = SUI.keyRow(1, "Reset Key", "reset", p)
		makeButton(p, "Reset Key To X", 2, function()
			resetKey = Enum.KeyCode.X
			resetKeyButton.Text = resetKey.Name
			notify("Reset key: X")
		end)
	end,
})

-- No Animations: disables the Animate script and stops every playing animation
local noAnim = false
local function applyNoAnim(char)
	if not char then return end
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LuaSourceContainer") then
		animate.Disabled = noAnim
	end
end

makeToggle(mePage, "No Animations", 14, false, function(v)
	noAnim = v
	applyNoAnim(player.Character)
	notify("No Animations: " .. (v and "ON" or "OFF"))
end, {
	desc = "Stops all character animations (walking, jumping, tools).",
})

RunService.RenderStepped:Connect(function()
	if not noAnim then return end
	local _, hum = getRoot()
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
			tr:Stop(0)
		end
	end
end)

-- stays active after respawn
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("Animate", 5)
	if noAnim then applyNoAnim(char) end
end)

-- No Ragdoll: keeps the character out of ragdoll states and repairs custom ragdolls
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local nr = { on = false, t = 0, interval = 150 }

	function nr.fix(char, scanJoints)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end

		-- stop the humanoid from entering ragdoll-type states
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Ragdoll
			or st == Enum.HumanoidStateType.FallingDown
			or st == Enum.HumanoidStateType.Physics then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		-- PlatformStand is how many games stun you, but Fly needs it, so leave it alone while flying
		if hum.PlatformStand and not flying then
			hum.PlatformStand = false
		end

		-- custom ragdolls: turn the joints back on and remove the ragdoll constraints
		if scanJoints then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("Motor6D") then
					if not d.Enabled then d.Enabled = true end
				elseif d:IsA("BallSocketConstraint") then
					d:Destroy()
				end
			end
		end
	end

	makeToggle(mePage, "No Ragdoll", 15, false, function(v)
		nr.on = v
		if not v then
			-- give the humanoid its normal states back
			local _, hum = getRoot()
			if hum then
				hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
				hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			end
		end
		notify("No Ragdoll: " .. (v and "ON" or "OFF"))
	end, {
		desc = "Keeps you out of ragdoll and stun states.",
		build = function(p)
			makeSlider(p, "Joint Scan Interval (ms)", 1, 50, 1000, nr.interval, function(v) nr.interval = v end)
		end,
	})

	RunService.Heartbeat:Connect(function(dt)
		if not nr.on then return end
		-- states are checked every frame, joints only every "interval" ms
		nr.t += dt
		local scan = nr.t >= nr.interval / 1000
		if scan then nr.t = 0 end
		nr.fix(player.Character, scan)
	end)
end

-- Anti Void: when you fall into the void you are teleported back to where you were before falling
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local av = {
		on = false,
		margin = 100,      -- studs above the destroy height that trigger the teleport
		spawnOnly = false, -- true = always go to spawn instead of your last position
		back = 10,         -- how far back (x0.1s) from your last grounded moment to return to
		hist = {},         -- recent safe positions { pos, t }
		lastT = 0,
		busy = false,
	}

	-- pick a safe spot from a little before you left the ground
	function av.safeSpot()
		local h = av.hist
		if #h == 0 then return nil end
		local cutoff = h[#h].t - av.back / 10
		for i = #h, 1, -1 do
			if h[i].t <= cutoff then return h[i].pos end
		end
		return h[1].pos -- not enough history yet: use the oldest spot
	end

	-- spawn position (used when "spawn only" is on, or there is no safe spot yet)
	function av.spawnPos()
		local sp = player.RespawnLocation
		if not (sp and sp.Parent) then
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("SpawnLocation") and d.Enabled then
					if not (d.Neutral == false and player.Team and d.TeamColor ~= player.TeamColor) then
						sp = d
						break
					end
					sp = sp or d
				end
			end
		end
		if sp then return sp.Position + Vector3.new(0, sp.Size.Y / 2 + 5, 0) end
		return nil
	end

	makeToggle(mePage, "Anti Void", 16, false, function(v)
		av.on = v
		notify("Anti Void: " .. (v and "ON" or "OFF"))
	end, {
		desc = "When you fall into the void, teleports you back to where you were before you fell (or to spawn if you prefer).",
		build = function(p)
			makeSlider(p, "Trigger Margin (studs)", 1, 20, 300, av.margin, function(v) av.margin = v end)
			makeSlider(p, "Go Back (x0.1s)", 2, 0, 50, av.back, function(v) av.back = v end)
			makeToggle(p, "Go To Spawn Instead", 3, av.spawnOnly, function(v) av.spawnOnly = v end)
		end,
	})

	-- a new character starts with a fresh history
	player.CharacterAdded:Connect(function()
		av.hist = {}
		av.busy = false
	end)

	RunService.Heartbeat:Connect(function()
		if not av.on then return end
		local root, hum = getRoot()
		if not root or not hum then return end

		local voidY = workspace.FallenPartsDestroyHeight + av.margin
		local now = os.clock()

		-- remember places where you stood on solid ground
		if root.Position.Y > voidY + 20 and hum.FloorMaterial ~= Enum.Material.Air
			and now - av.lastT > 0.1 then
			av.lastT = now
			av.hist[#av.hist + 1] = { pos = root.Position + Vector3.new(0, 3, 0), t = now }
			if #av.hist > 120 then table.remove(av.hist, 1) end
		end

		if root.Position.Y < voidY and not av.busy then
			local pos = (not av.spawnOnly and av.safeSpot()) or av.spawnPos() or av.safeSpot()
			if pos then
				av.busy = true
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.CFrame = CFrame.new(pos)
				notify("Anti Void: saved you")
				task.delay(0.5, function() av.busy = false end)
			end
		end
	end)
end

------------------------------------------------------------
-- WORLD tab
------------------------------------------------------------
local orig = {
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	FogEnd = Lighting.FogEnd,
	GlobalShadows = Lighting.GlobalShadows,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Gravity = workspace.Gravity,
	FOV = camera.FieldOfView,
}

local fullbrightToggle = makeToggle(worldPage, "Fullbright", 1, false, function(v)
	if v then
		Lighting.Brightness = Cfg.fbBright
		Lighting.FogEnd = 1e6
		Lighting.GlobalShadows = false
		Lighting.Ambient = WHITE
		Lighting.OutdoorAmbient = WHITE
	else
		Lighting.Brightness = orig.Brightness
		Lighting.FogEnd = orig.FogEnd
		Lighting.GlobalShadows = orig.GlobalShadows
		Lighting.Ambient = orig.Ambient
		Lighting.OutdoorAmbient = orig.OutdoorAmbient
	end
end, {
	desc = "Removes darkness, fog and shadows.",
	build = function(p, owner)
		makeSlider(p, "Brightness", 1, 1, 5, Cfg.fbBright, function(v)
			Cfg.fbBright = v
			if owner.get() then Lighting.Brightness = v end
		end)
	end,
})

local startTime = math.clamp(math.floor(orig.ClockTime), 0, 24)
local startGrav = math.clamp(math.floor(orig.Gravity + 0.5), 0, 400)
local startFov = math.clamp(math.floor(orig.FOV), 30, 120)
local timeTouched, gravTouched, fovTouched = false, false, false
local fovValue = startFov
Cfg.timeValue, Cfg.gravValue = startTime, startGrav

local timeToggle, gravToggle, fovToggle
timeToggle = makeToggle(worldPage, "Custom Time of Day", 2, false, function(v)
	timeTouched = v
	Lighting.ClockTime = v and Cfg.timeValue or orig.ClockTime
end, {
	title = "Time of Day",
	desc = "Sets the time of day (0-24). Moving the slider turns it on.",
	build = function(p)
		local s = makeSlider(p, "Time of Day", 1, 0, 24, startTime, function(v)
			Cfg.timeValue = v
			if timeTouched then Lighting.ClockTime = v else timeToggle.set(true) end
		end)
		s.set(Cfg.timeValue, true)
		SUI.presets(p, s, { { "Midnight", 0 }, { "Sunrise", 6 }, { "Noon", 12 }, { "Sunset", 18 } }, 1)
		makeToggle(p, "Lock Time (game can't change it)", 10, Cfg.lockTime, function(v) Cfg.lockTime = v end)
	end,
})
gravToggle = makeToggle(worldPage, "Custom Gravity", 3, false, function(v)
	gravTouched = v
	workspace.Gravity = v and Cfg.gravValue or orig.Gravity
end, {
	title = "Gravity",
	desc = "World gravity (normal is about 196). Moving the slider turns it on.",
	build = function(p)
		local s = makeSlider(p, "Gravity", 1, 0, 400, startGrav, function(v)
			Cfg.gravValue = v
			if gravTouched then workspace.Gravity = v else gravToggle.set(true) end
		end)
		s.set(Cfg.gravValue, true)
		SUI.presets(p, s, { { "Zero", 0 }, { "Moon", 32 }, { "Normal", 196 }, { "Heavy", 400 } }, 1)
	end,
})
fovToggle = makeToggle(worldPage, "Custom Field of View", 4, false, function(v)
	fovTouched = v
	if not v then camera.FieldOfView = orig.FOV end
end, {
	title = "Field of View",
	desc = "Camera field of view. Moving the slider turns it on.",
	build = function(p)
		local s = makeSlider(p, "Field of View", 1, 30, 120, startFov, function(v)
			fovValue = v
			if not fovTouched then fovToggle.set(true) end
		end)
		s.set(fovValue, true)
		SUI.presets(p, s, { { "Narrow", 50 }, { "Default", 70 }, { "Wide", 100 }, { "Max", 120 } }, 1)
	end,
})
RunService.RenderStepped:Connect(function()
	if fovTouched then camera.FieldOfView = fovValue end
	if timeTouched and Cfg.lockTime then Lighting.ClockTime = Cfg.timeValue end
end)

local function resetWorldValues()
	timeToggle.set(false, true)
	gravToggle.set(false, true)
	fovToggle.set(false, true)
	Lighting.ClockTime = orig.ClockTime
	workspace.Gravity = orig.Gravity
	camera.FieldOfView = orig.FOV
	timeTouched, gravTouched, fovTouched = false, false, false
	fovValue = startFov
	Cfg.timeValue, Cfg.gravValue = startTime, startGrav
	Cfg.lockTime = false
end

local antiAfk = false
local afkToggle = makeToggle(worldPage, "Anti-AFK", 5, false, function(v)
	antiAfk = v
	notify("Anti-AFK: " .. (v and "ON" or "OFF"))
end, {
	desc = "Stops Roblox from kicking you for being idle.",
})
player.Idled:Connect(function()
	if not antiAfk then return end
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

makeButton(worldPage, "Reset World Settings", 6, function()
	fullbrightToggle.set(false)
	resetWorldValues()
	notify("World settings reset")
end, {
	desc = "Puts lighting, gravity and field of view back to how the game had them.",
})

-- REJOIN AUTO-EXECUTE
-- If the panel is in StarterPlayerScripts it already starts by itself every time you join, so nothing is needed.
-- If you run it with an executor, paste the line you normally execute between the quotes, for example:
--   loadstring(game:HttpGet("https://your-link/panel.lua"))()
-- It gets queued with queue_on_teleport so the panel starts again after rejoining.
Cfg.autoExec = ""
makeButton(worldPage, "Rejoin Server", 7, function()
	local queue = queue_on_teleport or (syn and syn.queue_on_teleport)
	if queue and Cfg.autoExec ~= "" then
		pcall(queue, Cfg.autoExec)
		notify("Rejoining... panel will auto-start")
	else
		notify("Rejoining...")
	end
	pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
end, {
	desc = "Leaves and joins this game again. The panel starts again by itself after rejoining (see the AUTO-EXECUTE note in the script if you use an executor).",
})

------------------------------------------------------------
-- WORLD tab extras: GUI theme + Unlock Camera (infinite zoom)
------------------------------------------------------------
do
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local function theme(name, bg, panel, row, off, text, dim, accent, gradTop, gradBot)
		return { name = name, bg = bg, panel = panel, row = row, off = off, text = text, dim = dim,
			accent = accent, gradTop = gradTop, gradBot = gradBot }
	end

	-- dark, realistic palettes (white / soft tinted accents, no neon)
	local THEMES = {
		theme("Halloween", rgb(16, 8, 22), rgb(28, 14, 38), rgb(42, 21, 54), rgb(88, 46, 104),
			rgb(255, 238, 216), rgb(184, 142, 156), rgb(255, 140, 30), rgb(46, 16, 58), rgb(12, 5, 18)),
		theme("Obsidian", rgb(12, 12, 14), rgb(20, 20, 23), rgb(28, 28, 32), rgb(58, 58, 64),
			rgb(245, 245, 245), rgb(150, 150, 158), rgb(255, 255, 255), rgb(22, 22, 26), rgb(8, 8, 10)),
		theme("Graphite", rgb(24, 26, 29), rgb(33, 36, 40), rgb(43, 47, 52), rgb(76, 81, 88),
			rgb(235, 238, 242), rgb(146, 152, 160), rgb(225, 229, 235), rgb(36, 39, 44), rgb(18, 19, 22)),
		theme("Midnight", rgb(10, 14, 24), rgb(16, 22, 36), rgb(23, 31, 50), rgb(52, 66, 96),
			rgb(226, 234, 248), rgb(128, 144, 175), rgb(190, 210, 245), rgb(16, 24, 42), rgb(7, 10, 18)),
		theme("Steel", rgb(18, 22, 26), rgb(26, 32, 38), rgb(35, 43, 51), rgb(65, 78, 90),
			rgb(232, 238, 243), rgb(140, 152, 163), rgb(175, 195, 210), rgb(28, 35, 42), rgb(13, 16, 19)),
		theme("Forest", rgb(11, 18, 15), rgb(17, 27, 22), rgb(24, 38, 31), rgb(52, 74, 63),
			rgb(228, 240, 232), rgb(130, 155, 140), rgb(185, 215, 195), rgb(18, 32, 25), rgb(8, 13, 10)),
		theme("Burgundy", rgb(20, 11, 14), rgb(30, 17, 21), rgb(41, 24, 29), rgb(82, 48, 56),
			rgb(245, 232, 235), rgb(168, 135, 142), rgb(225, 185, 195), rgb(38, 19, 25), rgb(15, 8, 10)),
		theme("Sand", rgb(24, 21, 17), rgb(34, 30, 24), rgb(45, 40, 32), rgb(84, 76, 62),
			rgb(244, 238, 228), rgb(163, 153, 136), rgb(224, 208, 180), rgb(38, 33, 26), rgb(16, 14, 11)),
	}
	local idx = 1
	local themeBtn

	local function applyTheme(i)
		local T = THEMES[i]
		idx = i
		currentTheme = T
		for _, k in ipairs({ "bg", "panel", "row", "off", "text", "dim" }) do
			C[k] = T[k]
		end
		for inst, list in pairs(themed) do
			if inst.Parent then
				for _, e in ipairs(list) do
					inst[e[1]] = C[e[2]]
				end
			end
		end
		local g = frame:FindFirstChildOfClass("UIGradient")
		if g then g.Color = ColorSequence.new(T.gradTop, T.gradBot) end
		-- re-select the open tab so its highlight uses the new colors
		for n, b in pairs(tabButtons) do
			if b.BackgroundTransparency < 0.5 then
				selectTab(n)
				break
			end
		end
		themeBtn.Text = "GUI Theme: " .. T.name
	end

	makeHeading(worldPage, "GUI & CAMERA", 8)
	themeBtn = makeButton(worldPage, "GUI Theme: Halloween", 9, function()
		applyTheme(idx % #THEMES + 1)
		notify("Theme: " .. THEMES[idx].name)
	end, {
		title = "GUI Theme",
		desc = "Press the button to cycle themes, or pick one directly here.",
		build = function(p)
			for i, T in ipairs(THEMES) do
				makeButton(p, T.name, i, function()
					applyTheme(i)
					notify("Theme: " .. T.name)
				end)
			end
		end,
	})

	applyTheme(1) -- Halloween is the default theme

	-- Unlock Camera: infinite zoom (also lets you zoom all the way into first person)
	local unlocked = false
	local orig = {
		max = player.CameraMaxZoomDistance,
		min = player.CameraMinZoomDistance,
		mode = player.CameraMode,
	}
	makeToggle(worldPage, "Unlock Camera (Inf. Zoom)", 10, false, function(v)
		unlocked = v
		if v then
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMinZoomDistance = 0
			player.CameraMaxZoomDistance = 1e6
		else
			player.CameraMaxZoomDistance = orig.max
			player.CameraMinZoomDistance = orig.min
			player.CameraMode = orig.mode
		end
		notify("Unlock Camera: " .. (v and "ON" or "OFF"))
	end, {
		title = "Unlock Camera",
		desc = "Zoom out as far as you want, or all the way into first person.",
	})
	-- keep it unlocked even if the game tries to put the limits back
	RunService.RenderStepped:Connect(function()
		if not unlocked then return end
		if player.CameraMaxZoomDistance < 1e6 then player.CameraMaxZoomDistance = 1e6 end
		if player.CameraMinZoomDistance > 0 then player.CameraMinZoomDistance = 0 end
	end)
end

------------------------------------------------------------
-- TP tab
------------------------------------------------------------
local waypoint
makeButton(tpPage, "Save Waypoint", 1, function()
	local root = getRoot()
	if root then
		waypoint = root.CFrame
		notify("Waypoint saved")
	end
end, {
	desc = "Remembers your current position so you can come back to it.",
})
makeButton(tpPage, "Go To Waypoint", 2, function()
	local root = getRoot()
	if root and waypoint then
		root.CFrame = waypoint
		notify("Teleported to waypoint")
	else
		notify("No waypoint saved yet")
	end
end, {
	desc = "Teleports you back to the saved waypoint.",
	build = function(p)
		makeButton(p, "Clear Waypoint", 1, function()
			waypoint = nil
			notify("Waypoint cleared")
		end)
	end,
})

local spectating
local function stopSpectate()
	spectating = nil
	local _, hum = getRoot()
	if hum then camera.CameraSubject = hum end
end
makeButton(tpPage, "Stop Spectating", 3, function()
	stopSpectate()
	notify("Camera reset")
end, {
	desc = "Puts the camera back on your own character after pressing VIEW on a player.",
})
makeHeading(tpPage, "PLAYERS", 4)

local tpRows = {}
local function addPlayerRow(plr)
	if plr == player or tpRows[plr] then return end
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = 10,
	}, tpPage)
	corner(row, 10)
	new("TextLabel", {
		Size = UDim2.new(1, -130, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = plr.DisplayName,
		TextColor3 = C.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local function small(text, xOff)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(48, 24),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, xOff, 0.5, 0),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			Text = text,
			TextColor3 = C.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			AutoButtonColor = false,
		}, row)
		corner(b, 6)
		b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.off }) end)
		b.MouseLeave:Connect(function() tween(b, 0.15, { BackgroundColor3 = C.panel }) end)
		return b
	end

	small("TP", -10).MouseButton1Click:Connect(function()
		local root = getRoot()
		local c = plr.Character
		local tr = c and c:FindFirstChild("HumanoidRootPart")
		if root and tr then
			root.CFrame = tr.CFrame * CFrame.new(0, 0, 3)
			notify("Teleported to " .. plr.DisplayName)
		end
	end)
	small("VIEW", -62).MouseButton1Click:Connect(function()
		local c = plr.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
			spectating = plr
			notify("Viewing " .. plr.DisplayName)
		end
	end)

	tpRows[plr] = row
end

local function removePlayerRow(plr)
	if spectating == plr then stopSpectate() end
	if tpRows[plr] then
		tpRows[plr]:Destroy()
		tpRows[plr] = nil
	end
end

for _, plr in ipairs(Players:GetPlayers()) do addPlayerRow(plr) end
Players.PlayerAdded:Connect(addPlayerRow)
Players.PlayerRemoving:Connect(removePlayerRow)

------------------------------------------------------------
-- AIM tab (Aimbot + Smooth + FOV)
------------------------------------------------------------
local aim = {
	enabled = false,
	fov = 150,        -- circle radius in pixels
	smooth = 5,       -- 1 = instant, higher = slower
	partIndex = 1,
	teamCheck = false,
	wallCheck = true,
	showFov = true,
	holdRMB = not IS_TOUCH, -- PC: only aim while right mouse is held
	holdKey = false,  -- true: aimbot is ON only while the aim key is held
	-- extra options (gear settings)
	maxDist = 5000,
	holdBtn = Enum.UserInputType.MouseButton2,
	fovThick = 2,
	fovRainbow = true,
}
local AIM_PARTS = { "Head", "UpperTorso", "HumanoidRootPart" }

local fovCircle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(aim.fov * 2, aim.fov * 2),
	Visible = false,
}, overlay)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fovCircle)
local fovStroke = new("UIStroke", {
	Thickness = 1.5,
	Color = WHITE,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, fovCircle)

aimToggle = makeToggle(aimPage, "Aimbot", 1, false, function(v)
	aim.enabled = v
	if not aim.holdKey then notify("Aimbot: " .. (v and "ON" or "OFF")) end
end, {
	noBind = true, -- has its own Aim Key + Hold Key Mode
	desc = "Smoothly pulls your camera toward the closest player inside the FOV circle. All aimbot options are here.",
	build = function(p)
		local sm = makeSlider(p, "Smoothness (1 = instant)", 1, 1, 50, aim.smooth, function(v) aim.smooth = v end)
		SUI.presets(p, sm, { { "Instant", 1 }, { "Fast", 3 }, { "Smooth", 10 }, { "Legit", 25 } }, 1)
		local fv = makeSlider(p, "FOV (radius)", 10, 20, 600, aim.fov, function(v)
			aim.fov = v
			fovCircle.Size = UDim2.fromOffset(v * 2, v * 2)
		end)
		SUI.presets(p, fv, { { "Tiny", 50 }, { "Small", 100 }, { "Medium", 150 }, { "Large", 300 } }, 10)
		makeSlider(p, "Max Distance (studs)", 20, 50, 5000, aim.maxDist, function(v) aim.maxDist = v end)
		makeToggle(p, "Show FOV Circle", 21, aim.showFov, function(v) aim.showFov = v end)
		makeSlider(p, "Circle Thickness", 22, 1, 6, aim.fovThick, function(v) aim.fovThick = v end)
		makeToggle(p, "Theme Colored Circle", 23, aim.fovRainbow, function(v) aim.fovRainbow = v end)
		makeToggle(p, "Hold Mouse Button To Aim", 24, aim.holdRMB, function(v) aim.holdRMB = v end)
		makeToggle(p, "Use Left Mouse Instead", 25, aim.holdBtn == Enum.UserInputType.MouseButton1, function(v)
			aim.holdBtn = v and Enum.UserInputType.MouseButton1 or Enum.UserInputType.MouseButton2
		end)
		makeToggle(p, "Wall Check", 26, aim.wallCheck, function(v) aim.wallCheck = v end)
		makeToggle(p, "Team Check", 27, aim.teamCheck, function(v) aim.teamCheck = v end)
		makeToggle(p, "Hold Key Mode", 28, aim.holdKey, function(v)
			aim.holdKey = v
			aimToggle.set(false) -- start clean when switching between toggle / hold
			notify(v and ("Hold " .. aimKey.Name .. " to aim") or ("Press " .. aimKey.Name .. " to toggle aimbot"))
		end)
		aimKeyButton = SUI.keyRow(29, "Aim Key", "aim", p)
		makeButton(p, "Reset Key To Q", 30, function()
			aimKey = Enum.KeyCode.Q
			aimKeyButton.Text = aimKey.Name
			notify("Aim key: Q")
		end)
		local partBtn
		partBtn = makeButton(p, "Target: " .. AIM_PARTS[aim.partIndex], 31, function()
			aim.partIndex = aim.partIndex % #AIM_PARTS + 1
			partBtn.Text = "Target: " .. AIM_PARTS[aim.partIndex]
		end)
	end,
})
-- hold mode: releasing the aim key turns the aimbot off again
UserInputService.InputEnded:Connect(function(input)
	if aim.holdKey and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == aimKey then
		aimToggle.set(false)
	end
end)

-- Silent aim: picks a target inside its own FOV without moving your camera.
-- It hands the target to YOUR game's weapon scripts through NesteaSilentAim
-- (a BindableFunction under the player, also available as _G.NesteaSilentAim).
-- "Redirect Clicks To Target" is OFF by default so the camera never moves:
-- your own weapon script reads the target instead (see WeaponClient.lua).
local silent = { enabled = false, fov = 100, showFov = true, debug = false, target = nil,
	hitChance = 100, thick = 2, beamTime = 15, redirect = false }
do
	silent.circle = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(silent.fov * 2, silent.fov * 2),
		Visible = false,
	}, overlay)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, silent.circle)
	silent.stroke = new("UIStroke", {
		Thickness = 1.5,
		Color = Color3.fromRGB(255, 80, 80),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, silent.circle)

	-- marker used by Silent Test (shows which player is locked)
	silent.marker = new("Highlight", {
		FillColor = Color3.fromRGB(255, 60, 60),
		OutlineColor = WHITE,
		FillTransparency = 0.6,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	}, workspace)

	makeHeading(aimPage, "SILENT AIM", 11)
	makeToggle(aimPage, "Silent Aim", 12, false, function(v)
		silent.enabled = v
		if not v then silent.target = nil end
		notify("Silent Aim: " .. (v and "ON" or "OFF"))
	end, {
		desc = "Picks a target without moving your camera. Your game's weapon scripts read it through NesteaSilentAim. FOV circle and test mode are here.",
		build = function(p)
			makeSlider(p, "Hit Chance %", 1, 1, 100, silent.hitChance, function(v) silent.hitChance = v end)
			local fv = makeSlider(p, "Silent FOV (radius)", 2, 20, 600, silent.fov, function(v)
				silent.fov = v
				silent.circle.Size = UDim2.fromOffset(v * 2, v * 2)
			end)
			SUI.presets(p, fv, { { "Tiny", 50 }, { "Small", 100 }, { "Medium", 200 }, { "Large", 400 } }, 2)
			makeToggle(p, "Redirect Clicks To Target", 9, silent.redirect, function(v) silent.redirect = v end)
			makeToggle(p, "Show Silent FOV", 10, silent.showFov, function(v) silent.showFov = v end)
			makeSlider(p, "Circle Thickness", 11, 1, 6, silent.thick, function(v)
				silent.thick = v
				silent.stroke.Thickness = v
			end)
			-- Test mode: client-side only (nobody else sees it, no damage)
			makeToggle(p, "Silent Test (marker + beam)", 12, false, function(v)
				silent.debug = v
				notify("Silent Test: " .. (v and "ON" or "OFF"))
			end)
			makeSlider(p, "Beam Duration (x0.01s)", 13, 5, 100, silent.beamTime, function(v) silent.beamTime = v end)
		end,
	})
	local Debris = game:GetService("Debris")
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not silent.debug or not silent.enabled then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local t = silent.target
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if not (t and t.Parent and head) then return end
		local a, b = head.Position, t.Position
		local beam = Instance.new("Part")
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(255, 60, 60)
		beam.Size = Vector3.new(0.2, 0.2, (b - a).Magnitude)
		beam.CFrame = CFrame.lookAt((a + b) / 2, b)
		beam.Parent = workspace
		Debris:AddItem(beam, silent.beamTime / 100)
	end)

	local function result()
		local t = silent.target
		if silent.enabled and t and t.Parent then
			if silent.hitChance < 100 and math.random(1, 100) > silent.hitChance then
				return nil
			end
			return t.Position, t
		end
		return nil
	end
	local fn = new("BindableFunction", { Name = "NesteaSilentAim" }, player)
	fn.OnInvoke = result
	_G.NesteaSilentAim = result
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimTarget(center, radius)
	local best, bestDist = nil, radius
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local part = char and (char:FindFirstChild(AIM_PARTS[aim.partIndex])
				or char:FindFirstChild("HumanoidRootPart"))
			local sameTeam = plr.Team ~= nil and plr.Team == player.Team
			if part and hum and hum.Health > 0 and not (aim.teamCheck and sameTeam)
				and (part.Position - camera.CFrame.Position).Magnitude <= aim.maxDist then
				local pos, onScreen = camera:WorldToViewportPoint(part.Position)
				if onScreen and pos.Z > 0 then
					local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
					if d < bestDist then
						local visible = true
						if aim.wallCheck then
							aimParams.FilterDescendantsInstances = { player.Character, char }
							local origin = camera.CFrame.Position
							visible = workspace:Raycast(origin, part.Position - origin, aimParams) == nil
						end
						if visible then best, bestDist = part, d end
					end
				end
			end
		end
	end
	return best
end

RunService:BindToRenderStep("NesteaAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local vp = camera.ViewportSize
	local center = IS_TOUCH and Vector2.new(vp.X / 2, vp.Y / 2) or UserInputService:GetMouseLocation()

	fovCircle.Visible = aim.enabled and aim.showFov
	fovCircle.Position = UDim2.fromOffset(center.X, center.Y)
	fovStroke.Color = aim.fovRainbow and accentColor or WHITE
	fovStroke.Thickness = aim.fovThick

	-- silent aim only computes a target (camera untouched here)
	silent.circle.Visible = silent.enabled and silent.showFov
	silent.circle.Position = UDim2.fromOffset(center.X, center.Y)
	silent.target = silent.enabled and getAimTarget(center, silent.fov) or nil
	local showMark = silent.debug and silent.target ~= nil
	silent.marker.Enabled = showMark
	silent.marker.Adornee = showMark and silent.target.Parent or nil

	if not aim.enabled then return end
	if aim.holdRMB and not UserInputService:IsMouseButtonPressed(aim.holdBtn) then return end

	local target = getAimTarget(center, aim.fov)
	if not target then return end

	local camPos = camera.CFrame.Position
	local goal = CFrame.lookAt(camPos, target.Position)
	-- FPS-independent smoothing: smooth = 1 -> instant snap
	local alpha = 1 - (1 - 1 / aim.smooth) ^ (dt * 60)
	camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end)

------------------------------------------------------------
-- SILENT AIM click redirect (OFF by default, see "Redirect Clicks To Target").
-- When on, a click briefly points the camera so mouse.Hit / camera rays land on the target.
-- Leave it off if your weapon script reads NesteaSilentAim, then the camera never moves.
------------------------------------------------------------
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	local flick = { frames = 0, target = nil }

	local function cursorPos()
		local vp = camera.ViewportSize
		return IS_TOUCH and Vector2.new(vp.X / 2, vp.Y / 2) or UserInputService:GetMouseLocation()
	end

	-- camera CFrame that makes the ray under the cursor pass through the target
	local function redirected(targetPos)
		local cf = camera.CFrame
		local cur = cursorPos()
		local ray = camera:ViewportPointToRay(cur.X, cur.Y)
		local dLocal = cf:VectorToObjectSpace(ray.Direction)
		local fwd = Vector3.new(0, 0, -1)
		local base = CFrame.lookAt(cf.Position, targetPos)
		local axis = dLocal:Cross(fwd)
		if axis.Magnitude > 1e-4 then
			base = base * CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(dLocal:Dot(fwd), -1, 1)))
		end
		return base
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not silent.enabled or not silent.redirect then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local t = silent.target
		if not (t and t.Parent) then return end
		if silent.hitChance < 100 and math.random(1, 100) > silent.hitChance then return end
		flick.target = t
		flick.frames = 3
		camera.CFrame = redirected(t.Position) -- applies right away for scripts that read on click
	end)

	RunService:BindToRenderStep("NesteaSilentRedirect", Enum.RenderPriority.Camera.Value + 2, function()
		if flick.frames <= 0 then return end
		flick.frames -= 1
		local t = flick.target
		if t and t.Parent then
			camera.CFrame = redirected(t.Position)
		end
	end)
end

------------------------------------------------------------
-- Menu behavior: drag, minimize, close, hide key, rebinding
------------------------------------------------------------
do
	local dragging, dragStart, startPos
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end)
end

local function setMinimized(v, instant)
	minimized = v
	body.Visible = not v
	local size = v and UDim2.fromOffset(310, 58) or UDim2.fromOffset(310, 420)
	if instant then
		frame.Size = size
	else
		tween(frame, 0.3, { Size = size })
	end
end
minBtn.MouseButton1Click:Connect(function()
	setMinimized(not minimized)
end)

local menuOpen = true
local menuToken = 0 -- bumps every time the menu is toggled so old animations cancel themselves

-- White / colored flash layer that sits on top of the panel during the animation
local flashOverlay = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 100,
	Visible = false,
}, frame)
corner(flashOverlay, 14)

-- The panel is anchored top-left normally. During the animation we anchor it at its center
-- so it collapses / expands around the middle, then we put the anchor back.
local centered = false
local function fullSize()
	return Vector2.new(310, minimized and 58 or 420) * PANEL_SCALE
end
local function centerAnchor()
	if centered then return end
	local s = fullSize()
	frame.Position += UDim2.fromOffset(s.X / 2, s.Y / 2)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	centered = true
end
local function cornerAnchor()
	if not centered then return end
	local s = fullSize()
	frame.Position -= UDim2.fromOffset(s.X / 2, s.Y / 2)
	frame.AnchorPoint = Vector2.zero
	centered = false
end

-- Burst of colored shards flying out from the panel's center
local function burst(center, count)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.5
		local dist = math.random(70, 190)
		local sz = math.random(4, 9)
		local p = new("Frame", {
			Size = UDim2.fromOffset(sz, sz),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			BackgroundColor3 = (i % 2 == 0) and WHITE or Color3.fromRGB(150, 150, 150),
			BorderSizePixel = 0,
			Rotation = math.random(0, 90),
			ZIndex = 10,
		}, gui)
		corner(p, 2)
		local dur = 0.45 + math.random() * 0.25
		tweenEx(p, dur, {
			Position = UDim2.fromOffset(center.X + math.cos(a) * dist, center.Y + math.sin(a) * dist),
			BackgroundTransparency = 1,
			Rotation = p.Rotation + 220,
			Size = UDim2.fromOffset(0, 0),
		}, Enum.EasingStyle.Quad)
		task.delay(dur + 0.1, function() p:Destroy() end)
	end
end

local function playHide(token)
	centerAnchor()
	flashOverlay.Visible = true
	frame.Rotation = 0
	local base = frame.Position

	-- 1) glitch: pop up, shake, chromatic flicker
	tweenEx(scale, 0.15, { Scale = PANEL_SCALE * 1.06 }, Enum.EasingStyle.Back)
	for i = 1, 6 do
		if token ~= menuToken then frame.Position = base return end
		frame.Position = base + UDim2.fromOffset(math.random(-8, 8), math.random(-3, 3))
		stroke.Thickness = (i % 2 == 0) and 2 or 5
		flashOverlay.BackgroundColor3 = (i % 2 == 0) and WHITE or Color3.new(0, 0, 0)
		flashOverlay.BackgroundTransparency = 0.75
		task.wait(0.03)
	end
	frame.Position = base
	if token ~= menuToken then return end

	-- 2) CRT shutdown: squash into a bright white line
	body.Visible = false
	flashOverlay.BackgroundColor3 = WHITE
	tweenEx(scale, 0.2, { Scale = PANEL_SCALE })
	tweenEx(frame, 0.24, { Size = UDim2.fromOffset(350, 4) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	tweenEx(flashOverlay, 0.24, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
	task.wait(0.24)
	if token ~= menuToken then return end

	-- 3) line spins down to a dot and bursts into shards
	local center = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
	burst(center, 16)
	tweenEx(frame, 0.22, { Size = UDim2.fromOffset(8, 8), Rotation = 180 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(0.22)
	if token ~= menuToken then return end

	frame.Visible = false
	flashOverlay.Visible = false
	flashOverlay.BackgroundTransparency = 1
	stroke.Thickness = 2
end

local function playShow(token)
	centerAnchor()
	scale.Scale = PANEL_SCALE
	body.Visible = false
	stroke.Thickness = 2
	frame.Rotation = 180
	frame.Size = UDim2.fromOffset(8, 8)
	flashOverlay.BackgroundColor3 = WHITE
	flashOverlay.BackgroundTransparency = 0
	flashOverlay.Visible = true
	frame.Visible = true

	-- 1) dot spins open into a bright line
	tweenEx(frame, 0.2, { Size = UDim2.fromOffset(350, 4), Rotation = 0 }, Enum.EasingStyle.Quart)
	task.wait(0.2)
	if token ~= menuToken then return end

	-- 2) line expands into the full panel while the flash fades out
	local fullH = minimized and 58 or 420
	tweenEx(frame, 0.34, { Size = UDim2.fromOffset(310, fullH) }, Enum.EasingStyle.Back)
	tweenEx(flashOverlay, 0.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	burst(Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset), 10)
	task.wait(0.34)
	if token ~= menuToken then return end

	body.Visible = not minimized
	flashOverlay.Visible = false
	frame.Size = UDim2.fromOffset(310, fullH)
	cornerAnchor()
end

local function setMenu(open)
	if open == menuOpen then return end
	menuOpen = open
	menuToken += 1
	local token = menuToken
	task.spawn(open and playShow or playHide, token)
end
function Cfg.hideMenu()
	setMenu(false)
	if Cfg.hideToast then
		notify(IS_TOUCH and "Menu hidden - tap the logo button to reopen" or ("Menu hidden - press " .. menuKey.Name .. " to reopen"))
	end
end
closeBtn.MouseButton1Click:Connect(function() Cfg.hideMenu() end)

------------------------------------------------------------
-- LOGO BUTTON: floating round button that hides / shows the panel (drag it to move it)
------------------------------------------------------------
do -- scoped, so it adds no locals to the main chunk (200-local limit)
	-- To use your real picture: upload Design_fara_titlu_1.png as an image on the Roblox website
	-- (create.roblox.com > Creations > Decals), then paste its id here, like "rbxassetid://123456789".
	-- Left empty, the logo is drawn with UI shapes so it works without any upload.
	local LOGO_IMAGE = ""
	local SIZE = IS_TOUCH and 54 or 48
	local BLACK = Color3.new(0, 0, 0)

	local btn = new("TextButton", {
		Name = "LogoButton",
		Size = UDim2.fromOffset(SIZE, SIZE),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
	}, gui)
	corner(btn, SIZE / 2)
	new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(70, 70, 80), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
	local pop = new("UIScale", {}, btn)

	if LOGO_IMAGE ~= "" then
		new("ImageLabel", {
			Size = UDim2.fromScale(0.86, 0.86),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = LOGO_IMAGE,
			ZIndex = 51,
		}, btn)
	else
		-- the logo drawn from shapes: ring + two vertical bars + diagonal band (the "N")
		local logo = new("CanvasGroup", {
			Size = UDim2.fromScale(0.86, 0.86),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 51,
		}, btn)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, logo)

		local function box(parent, x, y, w, h, color, z)
			return new("Frame", {
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromScale(w, h),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z,
			}, parent)
		end

		-- ring
		local ring = box(logo, 0, 0, 1, 1, WHITE, 51)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
		local inner = box(logo, 0.049, 0.049, 0.902, 0.902, BLACK, 52)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, inner)

		-- vertical bars
		box(logo, 0.326, 0, 0.092, 1, WHITE, 53)
		box(logo, 0.583, 0, 0.084, 1, WHITE, 53)

		-- diagonal band, clipped to the space between the bars
		local clip = box(logo, 0.397, 0, 0.209, 1, BLACK, 54)
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		local band = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(2.87, 0.074),
			Rotation = 58,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 54,
		}, clip)
		new("UIStroke", { Thickness = 1, Color = BLACK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, band)

		-- thin black separator lines
		for _, x in ipairs({ 0.326, 0.397, 0.606, 0.667 }) do
			box(logo, x - 0.003, 0, 0.006, 1, BLACK, 55)
		end
	end

	-- click toggles the panel, dragging moves the button
	local dragging, moved, dragStart, startPos = false, false, nil, nil
	local function isPress(i)
		return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
	end
	btn.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, moved = true, false
			dragStart = input.Position
			startPos = btn.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if moved or d.Magnitude > 6 then
				moved = true
				btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and isPress(input) then
			dragging = false
			if not moved then
				pop.Scale = 0.85
				tweenEx(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				setMenu(not menuOpen)
			end
		end
	end)
	btn.MouseEnter:Connect(function() tween(pop, 0.15, { Scale = 1.08 }) end)
	btn.MouseLeave:Connect(function() tween(pop, 0.15, { Scale = 1 }) end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if listeningFor then
		local which = listeningFor
		listeningFor = nil
		local code = input.KeyCode
		if type(which) == "table" then -- a feature keybind
			SUI.assignFeatureKey(which, code)
			SUI.refreshBinds()
			return
		end
		-- Escape cancels; the two actions can't share a key
		if code ~= Enum.KeyCode.Escape and code ~= Enum.KeyCode.Unknown then
			local keys = { fly = flyKey, menu = menuKey, aim = aimKey, reset = resetKey }
			local labels = { fly = "the fly key", menu = "the hide menu key", aim = "the aim key", reset = "the reset key" }
			local clash
			for k, v in pairs(keys) do
				if k ~= which and v == code then clash = k end
			end
			local featClash
			for _, f in ipairs(SUI.feats) do
				if f.key == code then featClash = f.name end
			end
			if clash then
				notify(code.Name .. " is already " .. labels[clash])
			elseif featClash then
				notify(code.Name .. " is already used by " .. featClash)
			elseif which == "fly" then
				flyKey = code
				notify("Fly key: " .. code.Name)
			elseif which == "aim" then
				aimKey = code
				notify("Aim key: " .. code.Name)
			elseif which == "reset" then
				resetKey = code
				notify("Reset key: " .. code.Name)
			else
				menuKey = code
				notify("Hide key: " .. code.Name)
			end
		end
		if keyButton then keyButton.Text = flyKey.Name end
		if menuKeyButton then menuKeyButton.Text = menuKey.Name end
		if aimKeyButton then aimKeyButton.Text = aimKey.Name end
		SUI.refreshBinds()
		return
	end

	if gameProcessed then return end

	if input.KeyCode == flyKey then
		if Cfg.flyHold then startFly() else toggleFly() end
	elseif input.KeyCode == menuKey then
		setMenu(not menuOpen)
	elseif input.KeyCode == resetKey then
		resetCharacter()
	elseif input.KeyCode == aimKey then
		if aim.holdKey then
			aimToggle.set(true)
		else
			aimToggle.set(not aimToggle.get())
		end
	end

	-- per-feature keybinds: Hold turns it on while pressed, Toggle flips it
	for _, f in ipairs(SUI.feats) do
		if f.key == input.KeyCode then
			if f.hold then f.obj.set(true) else f.obj.set(not f.obj.get()) end
		end
	end
end)

------------------------------------------------------------
-- MOBILE BUTTONS
------------------------------------------------------------
local mobileGui = new("ScreenGui", {
	Name = "NesteaMobile",
	ResetOnSpawn = false,
	Enabled = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

;(function() -- own function = own 200-local limit (fixes "Out of local registers")
local mobileButtonsOn = IS_TOUCH
local dockPage = 1 -- 1 = MAIN, 2 = TOOLS
local dock = new("Frame", {
	Size = UDim2.fromOffset(120, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	BackgroundTransparency = 1,
	Visible = mobileButtonsOn,
}, mobileGui)
local dockScale = new("UIScale", {}, dock)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(56, 56),
	CellPadding = UDim2.fromOffset(8, 8),
	FillDirection = Enum.FillDirection.Horizontal,
	FillDirectionMaxCells = 2,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, dock)

-- shrink the dock on short screens so 6 rows always fit
local dockUserScale = 1
local function fitDock()
	dockScale.Scale = math.clamp((camera.ViewportSize.Y - 20) / 380, 0.55, 1) * dockUserScale
end
fitDock()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitDock)

local mobItems = {} -- { btn, page (nil = always), onlyFly }
local function mobBtn(text, order, page, onlyFly)
	local b = new("TextButton", {
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextScaled = true,
		AutoButtonColor = false,
		LayoutOrder = order,
	}, dock)
	corner(b, 28)
	-- keeps the text readable: scales to fit the circle, never gets too big or too small
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 15 }, b)
	-- Border mode: the ring goes around the button only (the default also outlined the text and blurred it)
	local st = new("UIStroke", { Thickness = 2, Color = accentColor, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	accentSet[st] = "Color"
	mobItems[#mobItems + 1] = { btn = b, page = page, onlyFly = onlyFly }
	return b
end

local function setActive(b, on)
	if on then
		accentSet[b] = "BackgroundColor3"
		b.TextColor3 = Color3.fromRGB(10, 10, 16)
	else
		accentSet[b] = nil
		b.BackgroundColor3 = C.bg
		b.TextColor3 = WHITE
	end
end

-- always visible
local flyBtn = mobBtn("FLY", 2)
local pageBtn = mobBtn("TOOLS", 3)
-- page 1 (MAIN)
local upBtn = mobBtn("UP", 4, 1, true)
local downBtn = mobBtn("DOWN", 5, 1, true)
local boostBtn = mobBtn("3X", 6, 1, true)
local espBtn = mobBtn("ESP", 7, 1)
local clipBtn = mobBtn("CLIP", 8, 1)
local instaBtn = mobBtn("INSTA", 9, 1)
-- page 2 (TOOLS)
local jumpBtn = mobBtn("JUMP", 10, 2)
local speedBtn = mobBtn("SPEED", 11, 2)
local tapBtn = mobBtn("TAP TP", 12, 2)
local freezeBtn = mobBtn("FREEZE", 13, 2)
local saveBtn = mobBtn("SAVE", 14, 2)
local goBtn = mobBtn("GO", 15, 2)
local lightBtn = mobBtn("LIGHT", 16, 2)
local afkBtn = mobBtn("AFK", 17, 2)

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1
end
local function holdButton(btn, setter)
	btn.InputBegan:Connect(function(i)
		if isPress(i) then setter(true) end
	end)
	btn.InputEnded:Connect(function(i)
		if isPress(i) then setter(false) end
	end)
end

refreshMobile = function()
	setActive(flyBtn, flying)
	setActive(boostBtn, mobBoost)
	setActive(upBtn, mobUp)
	setActive(downBtn, mobDown)
	setActive(espBtn, espEnabled)
	setActive(clipBtn, noclip)
	setActive(instaBtn, instantPrompts)
	setActive(jumpBtn, infJumpToggle.get())
	setActive(speedBtn, wsToggle.get())
	setActive(tapBtn, Cfg.tapToggle.get())
	setActive(freezeBtn, freezeToggle.get())
	setActive(lightBtn, fullbrightToggle.get())
	setActive(afkBtn, afkToggle.get())
	pageBtn.Text = dockPage == 1 and "TOOLS" or "MAIN"
	for _, it in ipairs(mobItems) do
		it.btn.Visible = (it.page == nil or it.page == dockPage) and (not it.onlyFly or flying)
	end
end

flyBtn.MouseButton1Click:Connect(toggleFly)
pageBtn.MouseButton1Click:Connect(function()
	dockPage = dockPage == 1 and 2 or 1
	refreshMobile()
end)
boostBtn.MouseButton1Click:Connect(function()
	mobBoost = not mobBoost
	refreshMobile()
end)
holdButton(upBtn, function(v)
	mobUp = v
	refreshMobile()
end)
holdButton(downBtn, function(v)
	mobDown = v
	refreshMobile()
end)

espBtn.MouseButton1Click:Connect(function() espToggle.set(not espEnabled) end)
clipBtn.MouseButton1Click:Connect(function() noclipToggle.set(not noclip) end)
instaBtn.MouseButton1Click:Connect(function() instantToggle.set(not instantPrompts) end)

jumpBtn.MouseButton1Click:Connect(function() infJumpToggle.set(not infJumpToggle.get()) end)
speedBtn.MouseButton1Click:Connect(function()
	-- 16 is the default speed, so bump it the first time or the toggle would do nothing
	if not wsToggle.get() and wsValue <= 16 then
		wsValue = 60
		if Cfg.wsSlider then Cfg.wsSlider.set(60, true) end
	end
	wsToggle.set(not wsToggle.get())
end)
tapBtn.MouseButton1Click:Connect(function() Cfg.tapToggle.set(not Cfg.tapToggle.get()) end)
freezeBtn.MouseButton1Click:Connect(function() freezeToggle.set(not freezeToggle.get()) end)
lightBtn.MouseButton1Click:Connect(function() fullbrightToggle.set(not fullbrightToggle.get()) end)
afkBtn.MouseButton1Click:Connect(function() afkToggle.set(not afkToggle.get()) end)

saveBtn.MouseButton1Click:Connect(function()
	local root = getRoot()
	if root then
		waypoint = root.CFrame
		notify("Waypoint saved")
	end
end)
goBtn.MouseButton1Click:Connect(function()
	local root = getRoot()
	if root and waypoint then
		root.CFrame = waypoint
		notify("Teleported to waypoint")
	else
		notify("No waypoint saved yet")
	end
end)

------------------------------------------------------------
-- MOB tab: everything about the on-screen buttons
------------------------------------------------------------
makeHeading(mobPage, "ON-SCREEN BUTTONS", 1)
makeToggle(mobPage, "Show Mobile Buttons", 2, mobileButtonsOn, function(v)
	mobileButtonsOn = v
	dock.Visible = v
	notify("Mobile buttons: " .. (v and "ON" or "OFF"))
end, {
	desc = "Shows the round buttons on the right side of the screen. Button size is here.",
	build = function(p)
		local s = makeSlider(p, "Button Size %", 1, 50, 150, 100, function(v)
			dockUserScale = v / 100
			fitDock()
		end)
		SUI.presets(p, s, { { "Small", 70 }, { "Normal", 100 }, { "Large", 130 }, { "Huge", 150 } }, 1)
	end,
})
makeButton(mobPage, "Switch Button Page", 4, function()
	dockPage = dockPage == 1 and 2 or 1
	refreshMobile()
	notify("Buttons: " .. (dockPage == 1 and "MAIN" or "TOOLS") .. " page")
end, {
	desc = "Switches the on-screen buttons between the MAIN and TOOLS page.",
})
makeHeading(mobPage, "WHAT EACH BUTTON DOES", 5)
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 150),
	BackgroundTransparency = 1,
	Text = "MAIN page\n"
		.. "FLY - toggle flight   UP / DOWN - height   3X - boost\n"
		.. "ESP - toggle ESP   CLIP - noclip   INSTA - instant prompts\n\n"
		.. "TOOLS page\n"
		.. "JUMP - infinite jump   SPEED - custom walk speed\n"
		.. "TAP TP - tap the world to teleport   FREEZE - freeze character\n"
		.. "SAVE / GO - set and return to a waypoint\n"
		.. "LIGHT - fullbright   AFK - anti-AFK",
	TextColor3 = C.dim,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	LayoutOrder = 6,
}, mobPage)

refreshMobile()
end)()

------------------------------------------------------------
-- HUD DISPLAYS (MAIN tab): FPS, Ping, Keystrokes, Keybinds + Move GUI
------------------------------------------------------------
;(function() -- own function = own 200-local limit
	local Stats = game:GetService("Stats")
	local hud = { move = false, snap = 0, els = {}, drag = nil }
	local GREEN, YELLOW, RED = Color3.fromRGB(60, 255, 120), Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 70, 70)

	local hudGui = new("ScreenGui", {
		Name = "NesteaHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local function isPress(i)
		return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
	end

	local function textColor(e, valueColor)
		local s = e.s
		if s.rgb then return Color3.fromHSV((os.clock() * 0.3) % 1, 1, 1) end
		if s.theme then return accentColor end
		if s.auto and valueColor then return valueColor end
		return esp[e.key .. "Text"]
	end

	-- creates one draggable HUD element
	local function newEl(key, pos, auto, noBg)
		local e = {
			key = key, defPos = pos, on = false, noBg = noBg,
			s = { scale = 100, corner = 8, outline = false, theme = false, rgb = false,
				bgT = 40, txtT = 0, size = 16, label = true, auto = false, interval = 500 },
		}
		esp[key .. "Text"] = WHITE
		esp[key .. "Bg"] = Color3.new(0, 0, 0)
		e.frame = new("Frame", {
			Name = key,
			Size = UDim2.new(),
			Position = pos,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Visible = false,
			AutomaticSize = auto and Enum.AutomaticSize.XY or Enum.AutomaticSize.None,
		}, hudGui)
		e.corner = corner(e.frame, 8)
		e.stroke = new("UIStroke", { Thickness = 1.5, Color = WHITE, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, e.frame)
		e.scaleObj = new("UIScale", {}, e.frame)
		e.frame.InputBegan:Connect(function(input)
			if hud.move and isPress(input) then
				hud.drag = { e = e, start = input.Position, pos = e.frame.Position }
			end
		end)
		hud.els[#hud.els + 1] = e
		return e
	end

	local function newText(e, font)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		}, e.frame)
		e.label = new("TextLabel", {
			Size = UDim2.new(),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Font = font or Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = WHITE,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
		}, e.frame)
		return e.label
	end

	-- dragging (Move GUI)
	local function snapTo(v)
		if hud.snap > 1 then return math.floor(v / hud.snap + 0.5) * hud.snap end
		return v
	end
	UserInputService.InputChanged:Connect(function(input)
		if hud.drag and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - hud.drag.start
			local p = hud.drag.pos
			hud.drag.e.frame.Position = UDim2.new(
				p.X.Scale, snapTo(p.X.Offset + d.X),
				p.Y.Scale, snapTo(p.Y.Offset + d.Y)
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if hud.drag and isPress(input) then hud.drag = nil end
	end)

	------------------------------------------------------------
	-- Elements
	------------------------------------------------------------
	local fps = newEl("hudFps", UDim2.fromOffset(12, 12), true)
	newText(fps)
	local png = newEl("hudPing", UDim2.fromOffset(12, 52), true)
	newText(png)
	local kb = newEl("hudBinds", UDim2.fromOffset(12, 92), true)
	newText(kb, Enum.Font.Code)
	kb.label.RichText = true
	kb.s.size = 14
	kb.s.title, kb.s.main, kb.s.state, kb.s.mode = true, true, true, true

	local ks = newEl("hudKeys", UDim2.new(0, 12, 1, -170), false, true)
	ks.frame.Size = UDim2.fromOffset(128, 154)
	ks.s.size, ks.s.bgT, ks.s.pressT = 14, 35, 0
	ks.s.space, ks.s.mouse, ks.s.cps = true, true, true
	esp.hudKeysDown = Color3.fromRGB(255, 140, 30)

	-- keystroke boxes
	local function keyBox(label, code, mouse, x, y, w, h)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, ks.frame)
		corner(f, 6)
		local t = new("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = label,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = WHITE,
		}, f)
		return { f = f, t = t, code = code, mouse = mouse, a = 0, label = label }
	end
	local keysMain = {
		keyBox("W", Enum.KeyCode.W, nil, 44, 0, 40, 40),
		keyBox("A", Enum.KeyCode.A, nil, 0, 44, 40, 40),
		keyBox("S", Enum.KeyCode.S, nil, 44, 44, 40, 40),
		keyBox("D", Enum.KeyCode.D, nil, 88, 44, 40, 40),
	}
	local spaceKey = keyBox("SPACE", Enum.KeyCode.Space, nil, 0, 88, 128, 28)
	local lmbKey = keyBox("LMB", nil, Enum.UserInputType.MouseButton1, 0, 120, 62, 34)
	local rmbKey = keyBox("RMB", nil, Enum.UserInputType.MouseButton2, 66, 120, 62, 34)
	local allKeys = { keysMain[1], keysMain[2], keysMain[3], keysMain[4], spaceKey, lmbKey, rmbKey }

	-- clicks per second
	local clicks = { {}, {} }
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			table.insert(clicks[1], os.clock())
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			table.insert(clicks[2], os.clock())
		end
	end)
	local function cpsOf(list)
		local n, now = 0, os.clock()
		for i = #list, 1, -1 do
			if now - list[i] <= 1 then n += 1 else table.remove(list, i) end
		end
		return n
	end

	-- ping (same "Data Ping" value Roblox shows in its own stats)
	local function pingNow()
		local ok, value = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and type(value) == "number" then return math.floor(value + 0.5) end
		return math.floor(player:GetNetworkPing() * 2000)
	end

	-- keybinds list text
	local function fmt(name, key, mode, on)
		local t = string.format("%-15s %-10s", name:sub(1, 15), key)
		if kb.s.mode and mode then t ..= mode end
		if kb.s.state and on ~= nil then
			t ..= on and ' <font color="#3CFF78">ON</font>' or ' <font color="#FF4646">OFF</font>'
		end
		return t
	end
	local function refreshBinds()
		local lines = {}
		if kb.s.title then lines[1] = "KEYBINDS" end
		if kb.s.main then
			lines[#lines + 1] = fmt("Fly", flyKey.Name, Cfg.flyHold and " [hold]" or " [toggle]", flying)
			lines[#lines + 1] = fmt("Hide Menu", menuKey.Name)
			lines[#lines + 1] = fmt("Aimbot", aimKey.Name, aim.holdKey and " [hold]" or " [toggle]", aim.enabled)
			lines[#lines + 1] = fmt("Reset", resetKey.Name)
		end
		for _, f in ipairs(SUI.feats) do
			if f.key then
				lines[#lines + 1] = fmt(f.name, f.key.Name, f.hold and " [hold]" or " [toggle]", f.obj.get())
			end
		end
		if #lines == (kb.s.title and 1 or 0) then lines[#lines + 1] = "(no keybinds set)" end
		kb.label.Text = table.concat(lines, "\n")
	end

	------------------------------------------------------------
	-- Update loop
	------------------------------------------------------------
	local fpsAcc, fpsFrames, pingAcc, bindAcc = 0, 0, 0, 1
	RunService.RenderStepped:Connect(function(dt)
		-- FPS / ping values
		fpsAcc += dt
		fpsFrames += 1
		if fpsAcc >= fps.s.interval / 1000 then
			fps.value = math.floor(fpsFrames / fpsAcc + 0.5)
			fpsAcc, fpsFrames = 0, 0
		end
		pingAcc += dt
		if pingAcc >= png.s.interval / 1000 or not png.value then
			pingAcc = 0
			png.value = pingNow()
		end
		local fv, pv = fps.value or 0, png.value or 0
		fps.label.Text = (fps.s.label and "FPS: " or "") .. fv
		png.label.Text = (png.s.label and "Ping: " or "") .. pv .. " ms"
		fps.vcol = fv >= 50 and GREEN or (fv >= 30 and YELLOW or RED)
		png.vcol = pv <= 80 and GREEN or (pv <= 150 and YELLOW or RED)

		-- keybinds text
		bindAcc += dt
		if kb.frame.Visible and bindAcc >= 0.25 then
			bindAcc = 0
			refreshBinds()
		end

		-- look of every element
		for _, e in ipairs(hud.els) do
			local s = e.s
			local vis = e.on or hud.move -- Move GUI shows everything so you can place it
			e.frame.Visible = vis
			if vis then
				e.frame.Active = hud.move
				e.corner.CornerRadius = UDim.new(0, s.corner)
				e.scaleObj.Scale = s.scale / 100
				e.frame.BackgroundColor3 = esp[e.key .. "Bg"]
				e.frame.BackgroundTransparency = e.noBg and 1 or s.bgT / 100
				local col = (e == ks) and esp.hudKeysText or textColor(e, e.vcol)
				e.stroke.Color = hud.move and Color3.fromRGB(255, 200, 40) or col
				e.stroke.Transparency = (hud.move or s.outline) and 0 or 1
				if e.label then
					e.label.TextSize = s.size
					e.label.TextColor3 = col
					e.label.TextTransparency = s.txtT / 100
				end
			end
		end

		-- keystrokes
		if ks.frame.Visible then
			local s = ks.s
			local y = 84
			spaceKey.f.Visible = s.space
			if s.space then
				spaceKey.f.Position = UDim2.fromOffset(0, y + 4)
				y += 32
			end
			lmbKey.f.Visible, rmbKey.f.Visible = s.mouse, s.mouse
			if s.mouse then
				lmbKey.f.Position = UDim2.fromOffset(0, y + 4)
				rmbKey.f.Position = UDim2.fromOffset(66, y + 4)
				y += 38
			end
			ks.frame.Size = UDim2.fromOffset(128, y)

			local pcol = esp.hudKeysDown
			if s.rgb then pcol = Color3.fromHSV((os.clock() * 0.3) % 1, 1, 1)
			elseif s.theme then pcol = accentColor end

			for _, k in ipairs(allKeys) do
				if k.f.Visible then
					local down
					if k.mouse then
						down = UserInputService:IsMouseButtonPressed(k.mouse)
					else
						down = UserInputService:IsKeyDown(k.code)
					end
					k.a += ((down and 1 or 0) - k.a) * math.min(1, dt * 18)
					k.f.BackgroundColor3 = esp.hudKeysBg:Lerp(pcol, k.a)
					k.f.BackgroundTransparency = (s.bgT + (s.pressT - s.bgT) * k.a) / 100
					k.t.TextColor3 = esp.hudKeysText
					k.t.TextTransparency = s.txtT / 100
					if k.mouse and s.cps then
						k.t.TextSize = math.max(8, s.size - 3)
						k.t.Text = k.label .. "\n" .. cpsOf(clicks[k.mouse == Enum.UserInputType.MouseButton1 and 1 or 2])
					else
						k.t.TextSize = s.size
						k.t.Text = k.label
					end
				end
			end
		end
	end)

	------------------------------------------------------------
	-- Settings (gear buttons)
	------------------------------------------------------------
	local function common(p, e, themeLbl, bgLbl)
		local s = e.s
		makeSlider(p, "Scale %", 1, 40, 250, s.scale, function(v) s.scale = v end)
		makeSlider(p, "Text Size", 2, 8, 40, s.size, function(v) s.size = v end)
		makeSlider(p, "Text Transparency %", 3, 0, 100, s.txtT, function(v) s.txtT = v end)
		makeSlider(p, bgLbl, 4, 0, 100, s.bgT, function(v) s.bgT = v end)
		makeSlider(p, "Corner Roundness", 5, 0, 20, s.corner, function(v) s.corner = v end)
		makeToggle(p, "Outline", 6, s.outline, function(v) s.outline = v end)
		makeToggle(p, themeLbl, 7, s.theme, function(v) s.theme = v end)
		makeToggle(p, "RGB Mode", 8, s.rgb, function(v) s.rgb = v end)
	end

	local function valueSettings(p, e)
		common(p, e, "Theme Colored Text", "Background Transparency %")
		makeToggle(p, "Show Label", 9, e.s.label, function(v) e.s.label = v end)
		makeToggle(p, "Color By Value (green/yellow/red)", 10, e.s.auto, function(v) e.s.auto = v end)
		makeSlider(p, "Update Interval (ms)", 11, 100, 2000, e.s.interval, function(v) e.s.interval = v end)
		SUI.colorRows(p, e.key .. "Text", "TEXT COLOR", 20)
		SUI.colorRows(p, e.key .. "Bg", "BACKGROUND COLOR", 30)
	end

	makeHeading(mainPage, "HUD DISPLAYS", 12)

	makeToggle(mainPage, "FPS Display", 13, false, function(v) fps.on = v end, {
		desc = "Shows your FPS on screen. Color, transparency, size and more are here. Use Move GUI to place it.",
		build = function(p) valueSettings(p, fps) end,
	})
	makeToggle(mainPage, "Ping Display", 14, false, function(v) png.on = v end, {
		desc = "Shows your ping on screen. Color, transparency, size and more are here. Use Move GUI to place it.",
		build = function(p) valueSettings(p, png) end,
	})
	makeToggle(mainPage, "Keystrokes", 15, false, function(v) ks.on = v end, {
		desc = "Shows W A S D, Space and the mouse buttons (with clicks per second) lighting up as you press them.",
		build = function(p)
			common(p, ks, "Theme Colored Pressed Keys", "Key Transparency %")
			makeSlider(p, "Pressed Transparency %", 9, 0, 100, ks.s.pressT, function(v) ks.s.pressT = v end)
			makeToggle(p, "Show Space Bar", 10, ks.s.space, function(v) ks.s.space = v end)
			makeToggle(p, "Show Mouse Buttons", 11, ks.s.mouse, function(v) ks.s.mouse = v end)
			makeToggle(p, "Show Clicks Per Second", 12, ks.s.cps, function(v) ks.s.cps = v end)
			SUI.colorRows(p, "hudKeysText", "TEXT COLOR", 20)
			SUI.colorRows(p, "hudKeysBg", "KEY COLOR", 30)
			SUI.colorRows(p, "hudKeysDown", "PRESSED KEY COLOR", 40)
		end,
	})
	makeToggle(mainPage, "Keybinds", 16, false, function(v) kb.on = v end, {
		desc = "Shows the keys you set on features (Fly, Aimbot, Reset, Hide Menu and every feature you gave a key).",
		build = function(p)
			common(p, kb, "Theme Colored Text", "Background Transparency %")
			makeToggle(p, "Show Title", 9, kb.s.title, function(v) kb.s.title = v end)
			makeToggle(p, "Show Main Keys (Fly, Aim...)", 10, kb.s.main, function(v) kb.s.main = v end)
			makeToggle(p, "Show ON / OFF State", 11, kb.s.state, function(v) kb.s.state = v end)
			makeToggle(p, "Show Hold / Toggle Mode", 12, kb.s.mode, function(v) kb.s.mode = v end)
			SUI.colorRows(p, "hudBindsText", "TEXT COLOR", 20)
			SUI.colorRows(p, "hudBindsBg", "BACKGROUND COLOR", 30)
		end,
	})

	makeToggle(mainPage, "Move GUI", 17, false, function(v)
		hud.move = v
		notify(v and "Move GUI: drag the HUD elements" or "Move GUI: OFF")
	end, {
		desc = "Turn it on and drag the FPS, Ping, Keystrokes and Keybinds displays anywhere. Every display is shown while it is on, so you can place the ones that are off too.",
		build = function(p)
			makeSlider(p, "Snap To Grid (px, 0 = off)", 1, 0, 100, hud.snap, function(v) hud.snap = v end)
			makeButton(p, "Reset All HUD Positions", 2, function()
				for _, e in ipairs(hud.els) do e.frame.Position = e.defPos end
				notify("HUD positions reset")
			end)
		end,
	})
end)()

------------------------------------------------------------
-- Boot sequence: loading screen -> PLAY button -> panel reveal
-- (Loader.wait returns early when you press SKIP)
------------------------------------------------------------
task.spawn(function()
	local steps = {
		{ 0.16, "Summoning the interface..." },
		{ 0.34, "Awakening the fly engine..." },
		{ 0.52, "Hunting for spirits..." },
		{ 0.68, "Brewing the tools..." },
	}
	for _, s in ipairs(steps) do
		Loader.setProgress(s[1], s[2])
		Loader.wait(0.9)
	end

	Loader.setProgress(0.86, "Carving the pumpkin...")
	Loader.wait(0.9)
	Loader.setProgress(0.94, "Ready... if you dare")
	Loader.wait(0.8)

	Loader.finish(function()
		gui.Enabled = true
		mobileGui.Enabled = true
		tween(scale, 0.5, { Scale = PANEL_SCALE })
		task.delay(0.5, function() notify("Nestea Man's Panel loaded") end)
	end)
end)
