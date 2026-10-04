-- Nestea Man's Panel (LocalScript)
-- Put in StarterPlayer > StarterPlayerScripts.
-- PC: RightShift = hide/show the menu (rebind it in the FLY tab).  Mobile: MENU button on the right side.

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
local listeningFor = nil -- "fly" or "menu" while waiting for a key press

local esp = {
	names = true,
	distance = true,
	health = true,
	tracers = false,
	teamColors = false,
	rainbow = true,
	range = 2000,
}

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

local BRAND = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(0, 220, 255)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(170, 80, 255)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 70, 160)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 220, 255)),
})

local accentSet = {} -- [instance] = "PropertyName" (recolored every frame with the rainbow accent)
local accentColor = Color3.fromHSV(0.55, 0.7, 1)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
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
-- LOADING SCREEN
------------------------------------------------------------
local Loader = {}
do
	local rng = Random.new()
	local OFFC = Color3.fromRGB(48, 48, 70)
	local GREEN = Color3.fromRGB(90, 255, 160)

	local function randHex(n)
		local s = ""
		for _ = 1, n do
			s ..= string.format("%X", rng:NextInteger(0, 15))
		end
		return s
	end

	local lg = new("ScreenGui", {
		Name = "NesteaLoading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- CanvasGroup = whole screen fades / transforms as one piece
	local root = new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, lg)
	local bgGrad = new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(40, 10, 60), Color3.fromRGB(10, 5, 20)),
	}, root)

	-- Aurora bands
	local bands = {}
	for i = 1, 2 do
		local b = new("Frame", {
			Size = UDim2.fromOffset(2800, 240),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Rotation = -20 + i * 22,
		}, root)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.78),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, b)
		bands[i] = b
	end

	------------------------------------------------------------
	-- HYPERSPACE STARFIELD (streaks fly out from the center, speed rises with progress)
	------------------------------------------------------------
	local STAR_N = 90
	local stars = {}
	local starLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
	for i = 1, STAR_N do
		local f = new("Frame", {
			Size = UDim2.fromOffset(4, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, starLayer)
		stars[i] = {
			f = f,
			a = rng:NextNumber() * math.pi * 2,
			r = rng:NextNumber(),
			v = rng:NextNumber(0.25, 0.9),
			h = rng:NextNumber(),
		}
	end

	------------------------------------------------------------
	-- DIGITAL RAIN on the screen edges
	------------------------------------------------------------
	local RAIN_PER_SIDE, RAIN_LINES = 7, 44
	local RAIN_CHARS = "0123456789ABCDEF<>/|=+*#"
	local function rainText()
		local out = table.create(RAIN_LINES)
		for i = 1, RAIN_LINES do
			local k = rng:NextInteger(1, #RAIN_CHARS)
			out[i] = RAIN_CHARS:sub(k, k)
		end
		return table.concat(out, "\n")
	end
	local rain = {}
	for side = 0, 1 do
		for i = 1, RAIN_PER_SIDE do
			local lab = new("TextLabel", {
				Size = UDim2.new(0, 14, 1, 0),
				AnchorPoint = Vector2.new(side, 0),
				Position = UDim2.new(side, side == 0 and (8 + (i - 1) * 18) or -(8 + (i - 1) * 18), 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.Code,
				TextSize = 13,
				TextColor3 = WHITE,
				Text = rainText(),
				TextYAlignment = Enum.TextYAlignment.Top,
			}, root)
			local g = new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.42, 0.85),
					NumberSequenceKeypoint.new(0.5, 0.05),
					NumberSequenceKeypoint.new(0.58, 0.85),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}, lab)
			rain[#rain + 1] = { lab = lab, g = g, speed = rng:NextNumber(0.25, 0.7), phase = rng:NextNumber() * 2, idx = i }
		end
	end

	-- Scanline sweep
	local scan = new("Frame", {
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, root)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.97, 0.94),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
	}, scan)

	-- Vignette bars
	for _, top in ipairs({ true, false }) do
		local v = new("Frame", {
			Size = UDim2.new(1, 0, 0.28, 0),
			AnchorPoint = Vector2.new(0, top and 0 or 1),
			Position = UDim2.fromScale(0, top and 0 or 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, root)
		new("UIGradient", {
			Rotation = top and 90 or 270,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, v)
	end

	------------------------------------------------------------
	-- HUD: corner brackets, header texts, boot terminal
	------------------------------------------------------------
	local hudParts = {}
	local function bracket(ax, ay)
		local hold = new("Frame", {
			Size = UDim2.fromOffset(34, 34),
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.new(ax, ax == 0 and 18 or -18, ay, ay == 0 and 18 or -18),
			BackgroundTransparency = 1,
		}, root)
		hudParts[#hudParts + 1] = new("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			AnchorPoint = Vector2.new(0, ay),
			Position = UDim2.fromScale(0, ay),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, hold)
		hudParts[#hudParts + 1] = new("Frame", {
			Size = UDim2.new(0, 2, 1, 0),
			AnchorPoint = Vector2.new(ax, 0),
			Position = UDim2.fromScale(ax, 0),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, hold)
	end
	bracket(0, 0)
	bracket(1, 0)
	bracket(0, 1)
	bracket(1, 1)

	local hudTL = new("TextLabel", {
		Size = UDim2.fromOffset(260, 16),
		Position = UDim2.fromOffset(62, 22),
		BackgroundTransparency = 1,
		Text = "NESTEA//PANEL  •  BOOT SEQUENCE",
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, root)
	local hudTR = new("TextLabel", {
		Size = UDim2.fromOffset(260, 16),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -62, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, root)
	local hudBR = new("TextLabel", {
		Size = UDim2.fromOffset(260, 16),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -62, 1, -22),
		BackgroundTransparency = 1,
		Text = "SECURE LINK  " .. string.upper(player.DisplayName),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, root)

	local term = new("TextLabel", {
		Size = UDim2.fromOffset(300, 120),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -52),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(120, 255, 190),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = "",
		TextTransparency = 0.15,
	}, root)

	local logLines = {}
	local function log(text)
		logLines[#logLines + 1] = "> " .. text
		if #logLines > 8 then table.remove(logLines, 1) end
	end
	log("nestea panel boot v2.0")
	log("session " .. randHex(8))

	local fillers = {
		function() return "alloc 0x" .. randHex(8) .. " ok" end,
		function() return "hash " .. randHex(12) end,
		function() return "link " .. ({ "fly", "esp", "tp", "world", "ui" })[rng:NextInteger(1, 5)] .. " -> 0x" .. randHex(4) end,
		function() return "sync " .. randHex(6) .. " ... ok" end,
	}

	------------------------------------------------------------
	-- CENTER STACK
	------------------------------------------------------------
	-- System check list (right side, wide screens only)
	local checks = {
		{ "UI RENDER", 0.16 }, { "FLY ENGINE", 0.34 }, { "ESP CORE", 0.52 },
		{ "TOOLS", 0.68 }, { "NETWORK", 0.9 }, { "ACCESS", 1 },
	}
	local checkHolder = new("Frame", {
		Size = UDim2.fromOffset(190, 22 + 18 * #checks),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -150, 0.5, 0),
		BackgroundTransparency = 1,
	}, root)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "SYSTEM CHECK",
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, checkHolder)
	for i, c in ipairs(checks) do
		c.lab = new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 22 + (i - 1) * 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			TextColor3 = WHITE,
		}, checkHolder)
	end

	-- Equalizer bars along the bottom
	local EQ_N = 56
	local eq = new("Frame", {
		Size = UDim2.new(0.46, 0, 0, 50),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		BackgroundTransparency = 1,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, eq)
	local eqBars = {}
	for i = 1, EQ_N do
		eqBars[i] = new("Frame", {
			Size = UDim2.new(1 / EQ_N, -2, 0, 4),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, eq)
	end

	local center = new("Frame", {
		Size = UDim2.fromOffset(520, 410),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
	}, root)
	local cScale = new("UIScale", {}, center)

	-- Emblem
	local emblem = new("Frame", {
		Size = UDim2.fromOffset(130, 130),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
	}, center)

	local function ring(size, thick)
		local r = new("Frame", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
		}, emblem)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		local s = new("UIStroke", {
			Thickness = thick,
			Color = WHITE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, r)
		return new("UIGradient", {
			Color = BRAND,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, s)
	end
	local ringA = ring(130, 4)
	local ringB = ring(98, 3)
	local ringD = ring(160, 2)

	local ringC = new("Frame", {
		Size = UDim2.fromOffset(150, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
	}, emblem)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ringC)
	new("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ringC)

	-- Rotating 4D hypercube (tesseract) inside the rings
	local TV, TE, TLines = {}, {}, {}
	for i = 0, 15 do
		TV[i + 1] = {
			(i % 2 == 0) and -1 or 1,
			(math.floor(i / 2) % 2 == 0) and -1 or 1,
			(math.floor(i / 4) % 2 == 0) and -1 or 1,
			(math.floor(i / 8) % 2 == 0) and -1 or 1,
		}
	end
	for i = 0, 15 do
		for b = 0, 3 do
			local j = bit32.bxor(i, bit32.lshift(1, b))
			if j > i then TE[#TE + 1] = { i + 1, j + 1 } end
		end
	end
	for e = 1, #TE do
		TLines[e] = new("Frame", {
			Size = UDim2.fromOffset(2, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, emblem)
	end
	local TP = table.create(16)
	local function drawTesseract(t, hue)
		local c1, s1 = math.cos(t * 0.9), math.sin(t * 0.9)
		local c2, s2 = math.cos(t * 0.6), math.sin(t * 0.6)
		local c3, s3 = math.cos(t * 0.4), math.sin(t * 0.4)
		for i, v in ipairs(TV) do
			local x, y, z, w = v[1], v[2], v[3], v[4]
			x, w = x * c1 - w * s1, x * s1 + w * c1
			y, z = y * c2 - z * s2, y * s2 + z * c2
			x, z = x * c3 - z * s3, x * s3 + z * c3
			local k = 1 / (3.0 - w)
			x, y, z = x * k, y * k, z * k
			local k2 = 130 / (3.6 - z)
			TP[i] = Vector2.new(65 + x * k2, 65 + y * k2)
		end
		for e, ed in ipairs(TE) do
			local a, b = TP[ed[1]], TP[ed[2]]
			local d = b - a
			local ln = TLines[e]
			ln.Size = UDim2.fromOffset(d.Magnitude + 1, 2)
			ln.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			ln.Rotation = math.deg(math.atan2(d.Y, d.X))
			ln.BackgroundColor3 = Color3.fromHSV((hue + e / #TE) % 1, 0.9, 1)
		end
	end

	local dots = {}
	for i = 1, 4 do
		local d = new("Frame", {
			Size = UDim2.fromOffset(8, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, emblem)
		corner(d, 4)
		dots[i] = d
	end

	-- Title ghosts (chromatic split, only visible during glitch)
	local TITLE = "NESTEA MAN'S"
	local SCRAMBLE = "#%&@$*?<>01ABCDEFXYZ"
	local function ghost(color)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 56),
			Position = UDim2.fromOffset(0, 160),
			BackgroundTransparency = 1,
			Text = TITLE,
			Font = Enum.Font.GothamBlack,
			TextSize = 48,
			TextColor3 = color,
			TextTransparency = 1,
		}, center)
	end
	local ghostC = ghost(Color3.fromRGB(0, 255, 255))
	local ghostM = ghost(Color3.fromRGB(255, 0, 200))

	-- Title letters
	local titleRow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 160),
		BackgroundTransparency = 1,
	}, center)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, titleRow)

	local letters = {}
	for i = 1, #TITLE do
		local ch = TITLE:sub(i, i)
		local isSpace = ch == " "
		local holder = new("Frame", {
			Size = isSpace and UDim2.fromOffset(16, 56) or UDim2.fromOffset(0, 56),
			AutomaticSize = isSpace and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, titleRow)
		if not isSpace then
			local lab = new("TextLabel", {
				Size = UDim2.fromOffset(0, 56),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(0, -50),
				BackgroundTransparency = 1,
				Text = ch,
				Font = Enum.Font.GothamBlack,
				TextSize = 48,
				TextColor3 = WHITE,
				TextTransparency = 1,
			}, holder)
			letters[#letters + 1] = { lab = lab, i = i, ch = ch }
		end
	end

	-- Subtitle + side lines
	local sub = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 222),
		BackgroundTransparency = 1,
		Text = "P  A  N  E  L",
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = WHITE,
		TextTransparency = 1,
	}, center)

	local function sideLine(left)
		local l = new("Frame", {
			Size = UDim2.fromOffset(0, 2),
			AnchorPoint = Vector2.new(left and 1 or 0, 0.5),
			Position = UDim2.new(0.5, left and -105 or 105, 0, 235),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, center)
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, left and 1 or 0),
				NumberSequenceKeypoint.new(1, left and 0 or 1),
			}),
		}, l)
		return l
	end
	local lineL, lineR = sideLine(true), sideLine(false)

	-- Typewriter tagline
	local TAG = "FLY  •  ESP  •  AIM  •  TOOLS  •  WORLD"
	local tag = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 258),
		BackgroundTransparency = 1,
		Text = TAG,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		MaxVisibleGraphemes = 0,
	}, center)

	-- Status / percent
	local status = new("TextLabel", {
		Size = UDim2.fromOffset(300, 18),
		Position = UDim2.new(0.5, -200, 0, 312),
		BackgroundTransparency = 1,
		Text = "Starting...",
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(215, 215, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, center)
	local pct = new("TextLabel", {
		Size = UDim2.fromOffset(80, 18),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, 200, 0, 312),
		BackgroundTransparency = 1,
		Text = "0%",
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, center)

	-- Segmented progress bar
	local SEG_N = 36
	local segBar = new("Frame", {
		Size = UDim2.fromOffset(400, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 336),
		BackgroundTransparency = 1,
	}, center)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, segBar)
	local segs = {}
	for i = 1, SEG_N do
		local f = new("Frame", {
			Size = UDim2.new(1 / SEG_N, -3, 1, 0),
			BackgroundColor3 = OFFC,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, segBar)
		corner(f, 2)
		segs[i] = { f = f, lit = false }
	end

	-- Tips
	local tips = IS_TOUCH and {
		"Tip: tap MENU to open or hide the panel",
		"Tip: UP / DOWN buttons control flying height",
		"Tip: use the TP tab to jump to other players",
		"Tip: 3X boosts your fly speed",
	} or {
		"Tip: press RightShift to hide the panel",
		"Tip: hold Alt while flying for 3x speed",
		"Tip: use the TP tab to jump to other players",
		"Tip: rebind the fly key in the FLY tab",
	}
	local tipLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 372),
		BackgroundTransparency = 1,
		Text = tips[1],
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(175, 175, 200),
	}, center)

	-- Finale layers
	local flash = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, root)
	local shock = new("Frame", {
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shock)
	local shockStroke = new("UIStroke", { Thickness = 6, Color = WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shock)

	------------------------------------------------------------
	-- Animation loop
	------------------------------------------------------------
	local shown, target = 0, 0
	local warp, warpBoost = 0.3, false
	local t0 = os.clock()
	local outro, outroT = false, 0
	local glitchUntil, nextGlitch = 0, t0 + 2.4
	local tipIdx, nextTip = 1, t0 + 2.6
	local nextFill, nextRain, nextHud = t0 + 0.6, t0 + 0.1, 0
	local finishing = false
	local fpsAvg = 60
	local pcx, pcy = 0, 0
	local shakeAmp = 0
	local conn

	conn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local t = now - t0
		local hue = (t * 0.25) % 1
		local col = Color3.fromHSV(hue, 0.9, 1)
		local vp = root.AbsoluteSize
		bgGrad.Rotation = (t * 15) % 360
		bgGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, 0.85, 0.28)),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV((hue + 0.33) % 1, 0.85, 0.14)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV((hue + 0.66) % 1, 0.85, 0.28)),
		})
		fpsAvg += (1 / math.max(dt, 1e-3) - fpsAvg) * 0.05

		-- progress easing
		shown += (target - shown) * (1 - math.exp(-dt * 2))
		if target - shown < 0.002 then shown = target end
		pct.Text = string.format("%d%%", math.floor(shown * 100 + 0.5))

		-- warp speed follows progress; jumps at the end
		local warpTarget = warpBoost and 10 or (0.3 + shown * 1.1)
		warp += (warpTarget - warp) * (1 - math.exp(-dt * 3))

		-- segmented bar
		local nOn = math.floor(shown * SEG_N + 0.0001)
		for i, sg in ipairs(segs) do
			if i <= nOn then
				local c = Color3.fromHSV((hue + i / SEG_N) % 1, 1, 1)
				c = c:Lerp(WHITE, 0.4 * math.max(0, math.sin(t * 7 - i * 0.55)))
				if i == nOn then c = c:Lerp(WHITE, 0.5 + 0.5 * math.sin(t * 12)) end
				sg.f.BackgroundColor3 = c
				sg.lit = true
			elseif sg.lit then
				sg.lit = false
				sg.f.BackgroundColor3 = OFFC
			end
		end

		-- starfield
		local tx, ty = vp.X / 2, vp.Y / 2
		if not IS_TOUCH then
			local ml = UserInputService:GetMouseLocation()
			tx += (ml.X - tx) * 0.15
			ty += (ml.Y - ty) * 0.15
		end
		if t < 0.1 then
			pcx, pcy = tx, ty
		else
			pcx += (tx - pcx) * (1 - math.exp(-dt * 4))
			pcy += (ty - pcy) * (1 - math.exp(-dt * 4))
		end
		local cx, cy = pcx, pcy
		local maxR = math.sqrt(vp.X * vp.X + vp.Y * vp.Y)
		for _, s in ipairs(stars) do
			s.r += s.v * dt * warp * (0.2 + s.r * 1.5)
			if s.r > 1 then
				s.r = rng:NextNumber(0.01, 0.08)
				s.a = rng:NextNumber() * math.pi * 2
			end
			local rad = s.r * maxR
			local len = 2 + s.r * s.r * warp * 38
			s.f.Size = UDim2.fromOffset(len, 1 + s.r * 2)
			s.f.Position = UDim2.fromOffset(cx + math.cos(s.a) * rad, cy + math.sin(s.a) * rad)
			s.f.Rotation = math.deg(s.a)
			s.f.BackgroundTransparency = 1 - math.clamp(s.r * 4, 0, 1) * 0.9
			s.f.BackgroundColor3 = Color3.fromHSV((hue + s.h) % 1, 0.9, 1)
		end

		-- digital rain
		local allow = vp.X < 700 and 1 or (vp.X < 1000 and 3 or RAIN_PER_SIDE)
		for _, r in ipairs(rain) do
			r.lab.Visible = r.idx <= allow
			if r.lab.Visible then
				local v = ((t * r.speed + r.phase) % 2) - 1
				r.g.Offset = Vector2.new(v, v)
				r.lab.TextColor3 = Color3.fromHSV((hue + r.idx * 0.07) % 1, 0.9, 1)
			end
		end
		if now >= nextRain then
			rain[rng:NextInteger(1, #rain)].lab.Text = rainText()
			nextRain = now + 0.09
		end

		-- emblem
		ringA.Rotation = (t * 220) % 360
		ringB.Rotation = 360 - ((t * 300) % 360)
		ringD.Rotation = (t * 90) % 360
		local pulse = math.sin(t * 2)
		ringC.Size = UDim2.fromOffset(150 + 8 * pulse, 150 + 8 * pulse)
		drawTesseract(t, hue)
		for i, d in ipairs(dots) do
			local a = t * 2.4 + i * (math.pi / 2)
			d.Position = UDim2.fromOffset(65 + 74 * math.cos(a), 65 + 74 * math.sin(a))
			d.BackgroundColor3 = Color3.fromHSV((hue + i * 0.25) % 1, 1, 1)
		end

		-- title wave + glitch with chromatic split
		for _, L in ipairs(letters) do
			L.lab.TextColor3 = Color3.fromHSV((t * 0.35 + L.i * 0.08) % 1, 0.95, 1)
		end
		if now >= nextGlitch then
			glitchUntil = now + 0.16
			nextGlitch = now + rng:NextNumber(1.6, 3.2)
		end
		if now < glitchUntil then
			titleRow.Position = UDim2.fromOffset(rng:NextInteger(-7, 7), 160 + rng:NextInteger(-3, 3))
			ghostC.Position = UDim2.fromOffset(-rng:NextInteger(4, 10), 160 + rng:NextInteger(-2, 2))
			ghostM.Position = UDim2.fromOffset(rng:NextInteger(4, 10), 160 + rng:NextInteger(-2, 2))
			ghostC.TextTransparency, ghostM.TextTransparency = 0.35, 0.35
			for _, L in ipairs(letters) do
				if rng:NextNumber() < 0.35 then
					L.lab.TextColor3 = rng:NextNumber() < 0.5 and Color3.fromRGB(0, 255, 255) or Color3.fromRGB(255, 0, 200)
				end
			end
		else
			titleRow.Position = UDim2.fromOffset(0, 160)
			ghostC.TextTransparency, ghostM.TextTransparency = 1, 1
		end
		sub.TextColor3 = col
		lineL.BackgroundColor3 = col
		lineR.BackgroundColor3 = col

		-- background
		for i, b in ipairs(bands) do
			b.Position = UDim2.fromScale(0.5 + 0.15 * math.sin(t * 0.3 + i * 2), 0.25 + 0.4 * (i - 1) + 0.06 * math.sin(t * 0.5 + i))
			b.BackgroundColor3 = Color3.fromHSV((hue + i * 0.3) % 1, 1, 1)
		end
		scan.Position = UDim2.new(0, 0, ((t / 3.2) % 1) * 1.25 - 0.15, 0)
		scan.BackgroundColor3 = col

		-- HUD
		for _, p in ipairs(hudParts) do p.BackgroundColor3 = col end
		if now >= nextHud then
			hudTR.Text = string.format("%d FPS  •  %s", math.floor(fpsAvg + 0.5), os.date("%H:%M:%S"))
			nextHud = now + 0.25
		end
		term.Visible = vp.X >= 640

		-- system check rows
		checkHolder.Visible = vp.X >= 1000
		if checkHolder.Visible then
			local spin = ({ "|", "/", "-", "+" })[math.floor(t * 10) % 4 + 1]
			for _, c in ipairs(checks) do
				if shown >= c[2] - 0.003 then
					c.lab.Text = "[ OK ] " .. c[1]
					c.lab.TextColor3 = GREEN
				else
					c.lab.Text = "[ " .. spin .. "  ] " .. c[1]
					c.lab.TextColor3 = Color3.fromRGB(150, 150, 175)
				end
			end
		end

		-- equalizer
		eq.Visible = vp.X >= 500
		if eq.Visible then
			local amp = 0.35 + math.min(shown, 1) * 0.4 + (warpBoost and 0.25 or 0)
			for i, bar in ipairs(eqBars) do
				local n = math.clamp(math.noise(i * 0.22 + 0.13, t * 1.6) + 0.5, 0.05, 1)
				local envelope = 0.55 + 0.45 * math.sin(i / EQ_N * math.pi)
				bar.Size = UDim2.new(1 / EQ_N, -2, 0, 4 + 44 * n * amp * envelope)
				bar.BackgroundColor3 = Color3.fromHSV((hue + i / EQ_N) % 1, 0.9, 1)
			end
		end
		hudBR.Visible = vp.X >= 640
		if now >= nextFill and not finishing then
			log(fillers[rng:NextInteger(1, #fillers)]())
			nextFill = now + 0.28
		end
		term.Text = table.concat(logLines, "\n") .. (math.floor(t * 2.5) % 2 == 0 and "_" or " ")

		-- tips
		if now >= nextTip then
			tipIdx = tipIdx % #tips + 1
			tipLabel.Text = tips[tipIdx]
			nextTip = now + 2.6
		end

		-- screen shake
		if shakeAmp > 0 then
			root.Position = UDim2.fromOffset(rng:NextInteger(-shakeAmp, shakeAmp), rng:NextInteger(-shakeAmp, shakeAmp))
		else
			root.Position = UDim2.new()
		end

		-- responsive scale (+ outro zoom)
		local base = math.clamp(math.min(vp.Y / 720, vp.X / 560), 0.55, 1.35)
		if outro then
			outroT = math.min(outroT + dt / 0.7, 1)
			cScale.Scale = base * (1 + 0.5 * outroT * outroT)
		else
			cScale.Scale = base
		end
	end)

	------------------------------------------------------------
	-- Intro animation
	------------------------------------------------------------
	tweenEx(root, 0.6, { GroupTransparency = 0 })
	task.spawn(function()
		task.wait(0.35)
		for _, L in ipairs(letters) do
			tweenEx(L.lab, 0.55, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 }, Enum.EasingStyle.Back)
			task.spawn(function()
				for _ = 1, 9 do
					local k = rng:NextInteger(1, #SCRAMBLE)
					L.lab.Text = SCRAMBLE:sub(k, k)
					task.wait(0.045)
				end
				L.lab.Text = L.ch
			end)
			task.wait(0.075)
		end
		task.wait(0.15)
		tweenEx(sub, 0.5, { TextTransparency = 0 })
		tweenEx(lineL, 0.6, { Size = UDim2.fromOffset(70, 2) })
		tweenEx(lineR, 0.6, { Size = UDim2.fromOffset(70, 2) })
		local n = utf8.len(TAG)
		for i = 1, n do
			tag.MaxVisibleGraphemes = i
			task.wait(0.03)
		end
	end)

	------------------------------------------------------------
	-- API
	------------------------------------------------------------
	function Loader.log(text)
		log(text)
	end

	function Loader.setProgress(p, text)
		target = math.max(target, math.clamp(p, 0, 1))
		if text and text ~= status.Text then
			status.Text = text
			log("[ OK ] " .. text)
		end
	end

	-- onReveal runs as the warp jump hits, so the panel appears underneath the fading loader
	function Loader.finish(onReveal)
		target = 1
		local deadline = os.clock() + 6
		while shown < 0.999 and os.clock() < deadline do task.wait() end

		finishing = true
		status.Text = "ACCESS GRANTED"
		status.TextColor3 = GREEN
		log("ACCESS GRANTED")
		for i = 1, 5 do
			status.TextTransparency = (i % 2 == 0) and 0 or 0.7
			task.wait(0.06)
		end
		status.TextTransparency = 0
		task.wait(0.3)

		-- WARP JUMP
		warpBoost = true
		log("engaging warp...")
		for i = 1, 10 do
			shakeAmp = i
			task.wait(0.1)
		end

		shock.Visible = true
		shakeAmp = 16
		task.spawn(function()
			for a = 16, 0, -2 do
				shakeAmp = a
				task.wait(0.05)
			end
		end)
		tweenEx(shock, 0.9, { Size = UDim2.fromOffset(3400, 3400) }, Enum.EasingStyle.Quad)
		tweenEx(shockStroke, 0.9, { Transparency = 1 })
		tweenEx(flash, 0.1, { BackgroundTransparency = 0.15 })
		task.wait(0.1)
		tweenEx(flash, 0.6, { BackgroundTransparency = 1 })

		outro = true
		if onReveal then task.spawn(onReveal) end
		tweenEx(root, 0.7, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.85)
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

-- Animated rainbow border
local stroke = new("UIStroke", {
	Thickness = 2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, frame)
local strokeGrad = new("UIGradient", { Color = BRAND }, stroke)

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
	Text = "NESTEA MAN'S PANEL",
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBlack,
	TextSize = 19,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local titleGrad = new("UIGradient", { Color = BRAND }, title)

local subtitle = new("TextLabel", {
	Size = UDim2.new(1, -90, 0, 16),
	Position = UDim2.fromOffset(16, 34),
	BackgroundTransparency = 1,
	Text = "FLY  •  ESP  •  AIM  •  TOOLS",
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
		Size = UDim2.new(1, -24, 1, -78),
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
		Size = UDim2.new(1 / 7, -4, 0, 26),
		BackgroundColor3 = C.off,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = label,
		TextColor3 = C.dim,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		AutoButtonColor = false,
	}, tabBar)
	corner(b, 8)
	b.MouseButton1Click:Connect(function() selectTab(name) end)
	tabButtons[name] = b
end

makeTab("fly", "FLY")
makeTab("esp", "ESP")
makeTab("aim", "AIM")
makeTab("me", "ME")
makeTab("world", "WORLD")
makeTab("tp", "TP")
makeTab("mob", "MOB")
local flyPage = makePage("fly")
local espPage = makePage("esp")
local aimPage = makePage("aim")
local mePage = makePage("me")
local worldPage = makePage("world")
local tpPage = makePage("tp")
local mobPage = makePage("mob")
selectTab("fly")

-- Footer hint
local function footerText()
	return IS_TOUCH and "Joystick = move • UP/DOWN = height • 3X = boost • MENU hides"
		or ("WASD • Space/Shift = up/down • Alt = 3x • " .. menuKey.Name .. " hides")
end
local footerLabel = new("TextLabel", {
	Size = UDim2.new(1, -24, 0, 26),
	Position = UDim2.new(0, 12, 1, -30),
	BackgroundTransparency = 1,
	Text = footerText(),
	TextColor3 = C.dim,
	Font = Enum.Font.Gotham,
	TextSize = 10,
}, body)
local function updateFooter()
	footerLabel.Text = footerText()
end

------------------------------------------------------------
-- Toast notifications
------------------------------------------------------------
local toast = new("TextLabel", {
	Size = UDim2.fromOffset(260, 34),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 40),
	BackgroundColor3 = C.bg,
	TextColor3 = C.text,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	Text = "",
	BorderSizePixel = 0,
}, gui)
corner(toast, 10)
local toastStroke = new("UIStroke", { Thickness = 1.5, Color = accentColor }, toast)
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
-- Widgets
------------------------------------------------------------
local function makeToggle(parent, text, order, default, callback)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 10)

	new("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
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
		Position = UDim2.new(1, -12, 0.5, 0),
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

	local btn = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
	}, row)

	local state = default
	local obj = { default = default }

	local function render()
		if state then
			accentSet[track] = "BackgroundColor3"
			tween(knob, 0.2, { Position = UDim2.new(1, -19, 0.5, 0) })
		else
			accentSet[track] = nil
			tween(track, 0.2, { BackgroundColor3 = C.off })
			tween(knob, 0.2, { Position = UDim2.new(0, 3, 0.5, 0) })
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
	return obj
end

local function makeSlider(parent, text, order, min, max, default, callback)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(row, 10)

	new("TextLabel", {
		Size = UDim2.new(1, -90, 0, 22),
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
		Position = UDim2.new(1, -12, 0, 6),
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
	return obj
end

local function makeButton(parent, text, order, callback)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = C.text,
		Font = Enum.Font.GothamBold,
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
-- Fly
------------------------------------------------------------
local bodyVel, bodyGyro
local curVel = Vector3.zero
local flyToggle, speedSlider, keyButton, menuKeyButton
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

flyToggle = makeToggle(flyPage, "Fly", 1, false, function(on)
	if on then startFly() else stopFly() end
end)

speedSlider = makeSlider(flyPage, "Fly Speed", 2, MIN_SPEED, MAX_SPEED, flySpeed, function(v)
	flySpeed = v
end)

-- Keybind rows (click, then press any key)
local function makeKeyRow(order, label, which)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, flyPage)
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
		Text = (which == "fly" and flyKey or menuKey).Name,
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
		listeningFor = which
		btn.Text = "press a key..."
	end)
	return btn
end
keyButton = makeKeyRow(3, "Fly Key", "fly")
menuKeyButton = makeKeyRow(4, "Hide Menu Key", "menu")

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

	local boost = (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or mobBoost) and 3 or 1
	local target = dir.Magnitude > 0 and dir.Unit * flySpeed * boost or Vector3.zero
	-- Smooth acceleration / deceleration
	curVel = curVel:Lerp(target, 1 - math.exp(-dt * 10))
	bodyVel.Velocity = curVel

	-- Slight bank into movement for style
	local bank = CFrame.Angles(0, 0, 0)
	if curVel.Magnitude > 1 then
		local side = curVel:Dot(cf.RightVector) / math.max(flySpeed, 1)
		bank = CFrame.Angles(0, 0, -side * 0.35)
	end
	bodyGyro.CFrame = cf * bank
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
local espObjects = {} -- [Player] = {highlight, billboard, nameLabel, distLabel, hpBar, hpFill, tracer, conn}

local function clearESP(plr)
	local d = espObjects[plr]
	if not d then return end
	if d.highlight then d.highlight:Destroy() end
	if d.billboard then d.billboard:Destroy() end
	if d.tracer then d.tracer:Destroy() end
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

espToggle = makeToggle(espPage, "ESP", 1, false, function(on) setESP(on) end)
makeToggle(espPage, "Names", 2, esp.names, function(v) esp.names = v end)
makeToggle(espPage, "Distance", 3, esp.distance, function(v) esp.distance = v end)
makeToggle(espPage, "Health Bars", 4, esp.health, function(v) esp.health = v end)
makeToggle(espPage, "Tracers", 5, esp.tracers, function(v) esp.tracers = v end)
makeToggle(espPage, "Team Colors", 6, esp.teamColors, function(v) esp.teamColors = v end)
makeToggle(espPage, "Rainbow ESP", 7, esp.rainbow, function(v) esp.rainbow = v end)
makeSlider(espPage, "Max Range", 8, 100, 5000, esp.range, function(v) esp.range = v end)

Players.PlayerAdded:Connect(function(plr) if espEnabled then addESP(plr) end end)
Players.PlayerRemoving:Connect(clearESP)

------------------------------------------------------------
-- Per-frame updates (ESP info + rainbow accent + border spin)
------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	-- Rainbow accent + spinning border
	local hue = (os.clock() * 0.12) % 1
	accentColor = Color3.fromHSV(hue, 0.65, 1)
	for inst, prop in pairs(accentSet) do
		inst[prop] = accentColor
	end
	strokeGrad.Rotation = (strokeGrad.Rotation + dt * 90) % 360
	titleGrad.Rotation = (titleGrad.Rotation + dt * 40) % 360
	subtitle.TextColor3 = accentColor:Lerp(C.dim, 0.35)

	if not espEnabled then return end
	local myRoot = getRoot()
	if not myRoot then return end

	local vp = camera.ViewportSize
	local origin = Vector2.new(vp.X / 2, vp.Y)

	for plr, d in pairs(espObjects) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")

		if not root or not d.billboard then
			if d.tracer then d.tracer.Visible = false end
			continue
		end

		local dist = (root.Position - myRoot.Position).Magnitude
		local inRange = dist <= esp.range

		-- Color
		local color = Color3.fromRGB(255, 60, 60)
		if esp.teamColors and plr.Team then
			color = plr.TeamColor.Color
		elseif esp.rainbow then
			color = Color3.fromHSV((hue + dist / 400) % 1, 0.8, 1)
		end

		d.highlight.Enabled = inRange
		d.billboard.Enabled = inRange
		d.highlight.FillColor = color
		d.highlight.OutlineColor = color:Lerp(WHITE, 0.6)

		if inRange then
			d.nameLabel.Visible = esp.names
			d.nameLabel.TextColor3 = color:Lerp(WHITE, 0.5)
			d.distLabel.Visible = esp.distance
			d.distLabel.Text = string.format("[%d studs]", dist)

			d.hpBar.Visible = esp.health
			if hum and hum.MaxHealth > 0 then
				local r = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
				d.hpFill.Size = UDim2.fromScale(r, 1)
				d.hpFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(60, 255, 120), r)
			end
		end

		-- Tracer
		local t = d.tracer
		if esp.tracers and inRange then
			local pos, onScreen = camera:WorldToViewportPoint(root.Position)
			if onScreen and pos.Z > 0 then
				local target = Vector2.new(pos.X, pos.Y)
				local delta = target - origin
				t.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
				t.Position = UDim2.fromOffset((origin.X + target.X) / 2, (origin.Y + target.Y) / 2)
				t.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				t.BackgroundColor3 = color
				t.Visible = true
			else
				t.Visible = false
			end
		else
			t.Visible = false
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
	local acc, frames = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		frames += 1
		if acc >= 0.5 then
			local ping = math.floor(player:GetNetworkPing() * 2000)
			stats.Text = string.format("%d FPS  •  %d ms", math.floor(frames / acc + 0.5), ping)
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
freezeToggle = makeToggle(mePage, "Freeze Character", 1, false, function(on) setFreeze(on) end)

local noclip = false
local noclipToggle = makeToggle(mePage, "Noclip", 2, false, function(v)
	noclip = v
	notify("Noclip: " .. (v and "ON" or "OFF"))
	if refreshMobile then refreshMobile() end
end)
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
end)
UserInputService.JumpRequest:Connect(function()
	if not infJump then return end
	local _, hum = getRoot()
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local spin, spinSpeed = false, 10
makeToggle(mePage, "Spin", 4, false, function(v)
	spin = v
	notify("Spin: " .. (v and "ON" or "OFF"))
end)
makeSlider(mePage, "Spin Speed", 5, 1, 100, spinSpeed, function(v) spinSpeed = v end)
RunService.RenderStepped:Connect(function(dt)
	if not spin or flying or frozen then return end
	local root = getRoot()
	if root then
		root.CFrame *= CFrame.Angles(0, math.rad(spinSpeed * 36 * dt), 0)
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
end)
local wsSlider = makeSlider(mePage, "WalkSpeed", 7, 0, 300, wsValue, function(v) wsValue = v end)
makeToggle(mePage, "Custom JumpPower", 8, false, function(v)
	jpOn = v
	if not v then
		local _, hum = getRoot()
		if hum then hum.JumpPower = 50 end
	end
end)
makeSlider(mePage, "JumpPower", 9, 0, 300, jpValue, function(v) jpValue = v end)
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
end)
mouse.Button1Down:Connect(function()
	if not clickTp or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
	local root = getRoot()
	if root and mouse.Hit then
		root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
	end
end)
-- Mobile: tap anywhere in the world to teleport there
UserInputService.TouchTapInWorld:Connect(function(pos, processed)
	if processed or not clickTp then return end
	local root = getRoot()
	if not root then return end
	local ray = camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if res then
		root.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0))
	end
end)

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
end)

makeButton(mePage, "Reset Character", 12, function()
	local _, hum = getRoot()
	if hum then hum.Health = 0 end
end)

-- No Animations: disables the Animate script and stops every playing animation
local noAnim = false
local function applyNoAnim(char)
	if not char then return end
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LuaSourceContainer") then
		animate.Disabled = noAnim
	end
end

makeToggle(mePage, "No Animations", 13, false, function(v)
	noAnim = v
	applyNoAnim(player.Character)
	notify("No Animations: " .. (v and "ON" or "OFF"))
end)

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
		Lighting.Brightness = 2
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
end)

local startTime = math.clamp(math.floor(orig.ClockTime), 0, 24)
local startGrav = math.clamp(math.floor(orig.Gravity + 0.5), 0, 400)
local startFov = math.clamp(math.floor(orig.FOV), 30, 120)
local timeTouched, gravTouched, fovTouched = false, false, false
local fovValue = startFov

local timeSlider = makeSlider(worldPage, "Time of Day", 2, 0, 24, startTime, function(v)
	timeTouched = true
	Lighting.ClockTime = v
end)
local gravSlider = makeSlider(worldPage, "Gravity", 3, 0, 400, startGrav, function(v)
	gravTouched = true
	workspace.Gravity = v
end)
local fovSlider = makeSlider(worldPage, "Field of View", 4, 30, 120, startFov, function(v)
	fovTouched = true
	fovValue = v
end)
RunService.RenderStepped:Connect(function()
	if fovTouched then camera.FieldOfView = fovValue end
end)

local function resetWorldValues()
	Lighting.ClockTime = orig.ClockTime
	workspace.Gravity = orig.Gravity
	camera.FieldOfView = orig.FOV
	timeTouched, gravTouched, fovTouched = false, false, false
	fovValue = startFov
	timeSlider.set(startTime, true)
	gravSlider.set(startGrav, true)
	fovSlider.set(startFov, true)
end

local antiAfk = false
local afkToggle = makeToggle(worldPage, "Anti-AFK", 5, false, function(v)
	antiAfk = v
	notify("Anti-AFK: " .. (v and "ON" or "OFF"))
end)
player.Idled:Connect(function()
	if not antiAfk then return end
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

makeButton(worldPage, "Reset World Settings", 6, function()
	fullbrightToggle.set(false)
	resetWorldValues()
	notify("World settings reset")
end)

makeButton(worldPage, "Rejoin Server", 7, function()
	notify("Rejoining...")
	pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
end)

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
end)
makeButton(tpPage, "Go To Waypoint", 2, function()
	local root = getRoot()
	if root and waypoint then
		root.CFrame = waypoint
		notify("Teleported to waypoint")
	else
		notify("No waypoint saved yet")
	end
end)

local spectating
local function stopSpectate()
	spectating = nil
	local _, hum = getRoot()
	if hum then camera.CameraSubject = hum end
end
makeButton(tpPage, "Stop Spectating", 3, function()
	stopSpectate()
	notify("Camera reset")
end)
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
			Font = Enum.Font.GothamBold,
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

makeToggle(aimPage, "Aimbot", 1, false, function(v)
	aim.enabled = v
	notify("Aimbot: " .. (v and "ON" or "OFF"))
end)
makeSlider(aimPage, "Smoothness (1 = instant)", 2, 1, 50, aim.smooth, function(v)
	aim.smooth = v
end)
makeSlider(aimPage, "FOV (radius)", 3, 20, 600, aim.fov, function(v)
	aim.fov = v
	fovCircle.Size = UDim2.fromOffset(v * 2, v * 2)
end)
makeToggle(aimPage, "Show FOV Circle", 4, aim.showFov, function(v) aim.showFov = v end)
makeToggle(aimPage, "Hold Right Mouse", 5, aim.holdRMB, function(v) aim.holdRMB = v end)
makeToggle(aimPage, "Wall Check", 6, aim.wallCheck, function(v) aim.wallCheck = v end)
makeToggle(aimPage, "Team Check", 7, aim.teamCheck, function(v) aim.teamCheck = v end)
local partBtn
partBtn = makeButton(aimPage, "Target: Head", 8, function()
	aim.partIndex = aim.partIndex % #AIM_PARTS + 1
	partBtn.Text = "Target: " .. AIM_PARTS[aim.partIndex]
end)

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimTarget(center)
	local best, bestDist = nil, aim.fov
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local part = char and (char:FindFirstChild(AIM_PARTS[aim.partIndex])
				or char:FindFirstChild("HumanoidRootPart"))
			local sameTeam = plr.Team ~= nil and plr.Team == player.Team
			if part and hum and hum.Health > 0 and not (aim.teamCheck and sameTeam) then
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
	fovStroke.Color = accentColor

	if not aim.enabled then return end
	if aim.holdRMB and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end

	local target = getAimTarget(center)
	if not target then return end

	local camPos = camera.CFrame.Position
	local goal = CFrame.lookAt(camPos, target.Position)
	-- FPS-independent smoothing: smooth = 1 -> instant snap
	local alpha = 1 - (1 - 1 / aim.smooth) ^ (dt * 60)
	camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end)

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
	local hue0 = os.clock() * 0.12
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.5
		local dist = math.random(70, 190)
		local sz = math.random(4, 9)
		local p = new("Frame", {
			Size = UDim2.fromOffset(sz, sz),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			BackgroundColor3 = Color3.fromHSV((hue0 + i / count) % 1, 0.75, 1),
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
		flashOverlay.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(0, 255, 255) or Color3.fromRGB(255, 0, 200)
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
closeBtn.MouseButton1Click:Connect(function()
	setMenu(false)
	notify(IS_TOUCH and "Menu hidden - tap MENU to reopen" or ("Menu hidden - press " .. menuKey.Name .. " to reopen"))
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if listeningFor then
		local which = listeningFor
		listeningFor = nil
		local code = input.KeyCode
		-- Escape cancels; the two actions can't share a key
		if code ~= Enum.KeyCode.Escape and code ~= Enum.KeyCode.Unknown then
			if which == "fly" and code == menuKey then
				notify(code.Name .. " already hides the menu")
			elseif which == "menu" and code == flyKey then
				notify(code.Name .. " is already the fly key")
			elseif which == "fly" then
				flyKey = code
				notify("Fly key: " .. code.Name)
			else
				menuKey = code
				updateFooter()
				notify("Hide key: " .. code.Name)
			end
		end
		keyButton.Text = flyKey.Name
		menuKeyButton.Text = menuKey.Name
		return
	end

	if gameProcessed then return end

	if input.KeyCode == flyKey then
		toggleFly()
	elseif input.KeyCode == menuKey then
		setMenu(not menuOpen)
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
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		AutoButtonColor = false,
		LayoutOrder = order,
	}, dock)
	corner(b, 28)
	local st = new("UIStroke", { Thickness = 2, Color = accentColor }, b)
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
local menuBtn = mobBtn("MENU", 1)
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
	setActive(tapBtn, clickTpToggle.get())
	setActive(freezeBtn, freezeToggle.get())
	setActive(lightBtn, fullbrightToggle.get())
	setActive(afkBtn, afkToggle.get())
	pageBtn.Text = dockPage == 1 and "TOOLS" or "MAIN"
	for _, it in ipairs(mobItems) do
		it.btn.Visible = (it.page == nil or it.page == dockPage) and (not it.onlyFly or flying)
	end
end

menuBtn.MouseButton1Click:Connect(function() setMenu(not menuOpen) end)
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
	if not wsToggle.get() and wsSlider.get() <= 16 then wsSlider.set(60) end
	wsToggle.set(not wsToggle.get())
end)
tapBtn.MouseButton1Click:Connect(function() clickTpToggle.set(not clickTpToggle.get()) end)
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
end)
makeSlider(mobPage, "Button Size %", 3, 50, 150, 100, function(v)
	dockUserScale = v / 100
	fitDock()
end)
makeButton(mobPage, "Switch Button Page (MAIN / TOOLS)", 4, function()
	dockPage = dockPage == 1 and 2 or 1
	refreshMobile()
	notify("Buttons: " .. (dockPage == 1 and "MAIN" or "TOOLS") .. " page")
end)
makeHeading(mobPage, "WHAT EACH BUTTON DOES", 5)
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 150),
	BackgroundTransparency = 1,
	Text = "MAIN page\n"
		.. "MENU - show / hide this panel\n"
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

------------------------------------------------------------
-- Boot sequence: loading screen -> panel reveal
------------------------------------------------------------
task.spawn(function()
	local steps = {
		{ 0.16, "Building interface..." },
		{ 0.34, "Loading fly engine..." },
		{ 0.52, "Calibrating ESP..." },
		{ 0.68, "Mounting tools..." },
	}
	for _, s in ipairs(steps) do
		Loader.setProgress(s[1], s[2])
		task.wait(0.9)
	end

	Loader.setProgress(0.86, "Finishing up...")
	task.wait(0.9)
	Loader.setProgress(0.94, "Ready")
	task.wait(0.8)

	Loader.finish(function()
		gui.Enabled = true
		mobileGui.Enabled = true
		tween(scale, 0.5, { Scale = PANEL_SCALE })
		task.delay(0.5, function() notify("Nestea Man's Panel loaded") end)
	end)
end)
