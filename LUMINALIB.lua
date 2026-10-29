--[[
    Lumina UI Library  -  v1.0.0
    Light-purple x deep-navy interface toolkit for Roblox (Luau)

    Quick start:
        local Lumina = loadstring(game:HttpGet("<raw url of this file>"))()
        local Window = Lumina:CreateWindow({ Title = "My Hub", Subtitle = "v1.0" })
        local Tab    = Window:Tab({ Title = "Main", Icon = "★" })
        Tab:Button({ Title = "Hello", Callback = function() print("hi") end })

    See the accompanying documentation for the complete API.
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G

-- Remove a previous copy of the library (re-execution safe)
if Env.__LuminaUnload then
    pcall(Env.__LuminaUnload)
end

local Lumina = {
    Version = "1.0.1",
    Flags = {},
    Windows = {},
    NotificationsEnabled = true,
    _listening = false,
}

------------------------------------------------------------------------
-- Core helpers
------------------------------------------------------------------------
local function Merge(base, extra)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    if extra then
        for k, v in pairs(extra) do out[k] = v end
    end
    return out
end

local function New(class, props, children)
    local inst = Instance.new(class)
    local parent
    if props then
        for k, v in pairs(props) do
            if k == "Parent" then parent = v else inst[k] = v end
        end
    end
    if children then
        for _, child in ipairs(children) do child.Parent = inst end
    end
    if parent then inst.Parent = parent end
    return inst
end

local function Tween(inst, props, time, style, dir)
    local tw = TweenService:Create(
        inst,
        TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function Apply(inst, props, instant, time, style, dir)
    if instant then
        for k, v in pairs(props) do inst[k] = v end
    else
        Tween(inst, props, time, style, dir)
    end
end

local function Fire(callback, ...)
    if type(callback) == "function" then
        task.spawn(callback, ...)
    end
end

-- Product of every UIScale from the instance upwards (used to convert pixels to local units)
local function GetScale(inst)
    local scale = 1
    local p = inst
    while p do
        local s = p:FindFirstChildOfClass("UIScale")
        if s then scale = scale * s.Scale end
        p = p.Parent
    end
    return scale
end

local function NewMaid()
    local maid = {_t = {}}
    function maid:Give(item)
        self._t[#self._t + 1] = item
        return item
    end
    function maid:Clean()
        local list = self._t
        self._t = {}
        for _, item in ipairs(list) do
            local ty = typeof(item)
            if ty == "RBXScriptConnection" then
                pcall(function() item:Disconnect() end)
            elseif ty == "Instance" then
                pcall(function() item:Destroy() end)
            elseif ty == "function" then
                pcall(item)
            end
        end
    end
    return maid
end

------------------------------------------------------------------------
-- Theme engine  (light purple x dark blue)
------------------------------------------------------------------------
local Theme = {}
local Registry = setmetatable({}, {__mode = "k"})
local Hooks, hookId = {}, 0

local function Themed(inst, map)
    local reg = Registry[inst]
    if not reg then
        reg = {}
        Registry[inst] = reg
    end
    for prop, key in pairs(map) do
        reg[prop] = key
        inst[prop] = Theme[key]
    end
    return inst
end

-- Register a function that re-paints a stateful element when the theme changes
local function OnTheme(fn)
    hookId = hookId + 1
    local id = hookId
    Hooks[id] = fn
    return function() Hooks[id] = nil end
end

local function ApplyTheme(newTheme, instant)
    for k, v in pairs(newTheme) do Theme[k] = v end
    for inst, map in pairs(Registry) do
        for prop, key in pairs(map) do
            pcall(Apply, inst, {[prop] = Theme[key]}, instant, 0.4)
        end
    end
    for _, fn in pairs(Hooks) do pcall(fn) end
end

local function BuildTheme(bg, accent)
    local ink = Color3.fromRGB(240, 236, 255)
    local tint = Color3.fromRGB(62, 78, 196):Lerp(accent, 0.15)
    return {
        Background   = bg,
        Sidebar      = bg:Lerp(tint, 0.06),
        Topbar       = bg:Lerp(tint, 0.09),
        Surface      = bg:Lerp(tint, 0.16),
        SurfaceHover = bg:Lerp(tint, 0.26),
        Elevated     = bg:Lerp(tint, 0.34),
        Stroke       = bg:Lerp(tint, 0.46),
        Accent       = accent,
        AccentDark   = accent:Lerp(Color3.fromRGB(26, 30, 110), 0.45),
        AccentSoft   = accent:Lerp(Color3.new(1, 1, 1), 0.4),
        OnAccent     = Color3.fromRGB(14, 12, 38),
        Text         = ink,
        SubText      = bg:Lerp(ink, 0.6),
        Muted        = bg:Lerp(ink, 0.36),
        Success      = Color3.fromRGB(110, 231, 183),
        Warning      = Color3.fromRGB(252, 211, 120),
        Danger       = Color3.fromRGB(255, 117, 140),
        Info         = accent,
    }
end

local Presets = {
    ["Violet Night"] = {Color3.fromRGB(8, 11, 28),  Color3.fromRGB(178, 152, 255)},
    ["Lilac Mist"]   = {Color3.fromRGB(14, 17, 46), Color3.fromRGB(206, 184, 255)},
    ["Deep Ocean"]   = {Color3.fromRGB(5, 13, 32),  Color3.fromRGB(146, 168, 255)},
}
local PresetOrder = {"Violet Night", "Lilac Mist", "Deep Ocean"}
local CurrentPreset = "Violet Night"
local CurrentBG, CurrentAccent = Presets["Violet Night"][1], Presets["Violet Night"][2]

local function SetPalette(bg, accent, instant)
    CurrentBG, CurrentAccent = bg, accent
    ApplyTheme(BuildTheme(bg, accent), instant)
end
SetPalette(CurrentBG, CurrentAccent, true)

function Lumina:SetTheme(nameOrTable, instant)
    if type(nameOrTable) == "string" and Presets[nameOrTable] then
        CurrentPreset = nameOrTable
        SetPalette(Presets[nameOrTable][1], Presets[nameOrTable][2], instant)
    elseif type(nameOrTable) == "table" then
        SetPalette(nameOrTable.Background or CurrentBG, nameOrTable.Accent or CurrentAccent, instant)
    end
end

function Lumina:SetAccent(color, instant)
    if typeof(color) == "Color3" then
        SetPalette(CurrentBG, color, instant)
    end
end

function Lumina:GetTheme() return Theme end
function Lumina:GetPresets() return PresetOrder end

------------------------------------------------------------------------
-- Gui mounting
------------------------------------------------------------------------
local Gui

local function Mount(gui)
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
    local ok = false
    if gethui then
        ok = pcall(function() gui.Parent = gethui() end)
    end
    if not ok or not gui.Parent then
        ok = pcall(function() gui.Parent = CoreGui end)
    end
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function GetGui()
    if Gui and Gui.Parent then return Gui end
    Gui = New("ScreenGui", {
        Name = "LuminaUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 1000,
    })
    Mount(Gui)
    Lumina.Gui = Gui
    return Gui
end

------------------------------------------------------------------------
-- Small component helpers
------------------------------------------------------------------------
local function Corner(parent, radius)
    return New("UICorner", {
        CornerRadius = (radius == "full") and UDim.new(1, 0) or UDim.new(0, radius or 8),
        Parent = parent,
    })
end

-- key == false -> plain (un-themed) stroke, for stateful elements that repaint via OnTheme
local function AddStroke(parent, key, thickness, transparency)
    local s = New("UIStroke", {
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = Theme.Stroke,
        Parent = parent,
    })
    if key ~= false then Themed(s, {Color = key or "Stroke"}) end
    return s
end

local function Pad(parent, t, r, b, l)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t or 0),
        PaddingRight = UDim.new(0, r or t or 0),
        PaddingBottom = UDim.new(0, b or t or 0),
        PaddingLeft = UDim.new(0, l or r or t or 0),
        Parent = parent,
    })
end

local function List(parent, padding, props)
    local p = Merge({
        Padding = UDim.new(0, padding or 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, props)
    p.Parent = parent
    return New("UIListLayout", p)
end

-- key: theme key (default "Text"); false -> not registered
local function Label(props, key)
    local l = New("TextLabel", Merge({
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        Text = "",
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 0, 16),
    }, props))
    if key ~= false then Themed(l, {TextColor3 = key or "Text"}) end
    return l
end

local function Asset(v)
    if type(v) == "number" then return "rbxassetid://" .. v end
    if type(v) == "string" then
        if v:match("^%d+$") then return "rbxassetid://" .. v end
        if v:match("^rbx") then return v end
    end
    return nil
end

-- Icon: an asset id / rbxassetid string becomes an ImageLabel, any other string a text glyph
local function Icon(parent, icon, size, key, color)
    if icon == nil or icon == false or icon == "" then return nil end
    local img = Asset(icon)
    local inst
    if img then
        inst = New("ImageLabel", {
            Name = "Icon", BackgroundTransparency = 1, Image = img,
            Size = UDim2.fromOffset(size, size), ImageColor3 = color or Theme.Text,
        })
        if key ~= false then Themed(inst, {ImageColor3 = key or "Text"}) end
    else
        inst = New("TextLabel", {
            Name = "Icon", BackgroundTransparency = 1, Text = tostring(icon),
            Font = Enum.Font.GothamBold, TextSize = size,
            Size = UDim2.fromOffset(size, size), TextColor3 = color or Theme.Text,
        })
        if key ~= false then Themed(inst, {TextColor3 = key or "Text"}) end
    end
    inst.Parent = parent
    return inst
end

-- Drawn icons (no font needed): the Roblox fonts lack many dingbat glyphs (they showed up as boxes).
-- kind: "chevron" (points down), "cross", "check". Returns the container Frame (rotatable) and an api.
local function DrawIcon(parent, kind, size, key)
    local box = New("Frame", {Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent})
    local bars = {}
    local thick = math.max(2, math.floor(size / 7))
    local function bar(cx, cy, len, rot)
        local b = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy),
            Size = UDim2.fromOffset(len, thick), Rotation = rot, BorderSizePixel = 0, Parent = box,
        })
        Themed(b, {BackgroundColor3 = key or "Text"})
        Corner(b, "full")
        bars[#bars + 1] = b
    end
    if kind == "cross" then
        bar(0.5, 0.5, size * 0.8, 45)
        bar(0.5, 0.5, size * 0.8, -45)
    elseif kind == "check" then
        bar(0.36, 0.62, size * 0.38, 45)
        bar(0.6, 0.5, size * 0.72, -52)
    else
        bar(0.33, 0.45, size * 0.55, 45)
        bar(0.67, 0.45, size * 0.55, -45)
    end
    local api = {Frame = box}
    function api.SetColor(c, animate)
        for _, b in ipairs(bars) do
            if animate then Tween(b, {BackgroundColor3 = c}, 0.15) else b.BackgroundColor3 = c end
        end
    end
    return box, api
end

local function Hitbox(parent, z)
    return New("TextButton", {
        Name = "Hitbox", Text = "", AutoButtonColor = false,
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = z or 5, Parent = parent,
    })
end

-- The ripple lives in its own clipped holder. Adding it straight to an AutomaticSize card made the
-- card grow with the expanding circle (the "button turns huge for a second" bug).
local function GetRippleHolder(target)
    local h = target:FindFirstChild("RippleHolder")
    if h then return h end
    h = New("Frame", {
        Name = "RippleHolder", BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 0, Parent = target,
    })
    local c = target:FindFirstChildOfClass("UICorner")
    if c then New("UICorner", {CornerRadius = c.CornerRadius, Parent = h}) end
    return h
end

local function Ripple(target, bright)
    pcall(function()
        local m = UserInputService:GetMouseLocation()
        local ap, as = target.AbsolutePosition, target.AbsoluteSize
        if as.X < 1 or as.Y < 1 then return end
        local rx, ry = (m.X - ap.X) / as.X, (m.Y - ap.Y) / as.Y
        if rx < 0 or rx > 1 or ry < 0 or ry > 1 then rx, ry = 0.5, 0.5 end
        local d = math.max(as.X, as.Y) * 2.4 / GetScale(target)
        local dot = New("Frame", {
            Name = "Ripple", AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(rx, ry), Size = UDim2.fromOffset(0, 0),
            BackgroundColor3 = bright and Color3.new(1, 1, 1) or Theme.Accent,
            BackgroundTransparency = 0.78, BorderSizePixel = 0, Parent = GetRippleHolder(target),
        })
        Corner(dot, "full")
        Tween(dot, {Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1}, 0.6, Enum.EasingStyle.Quad)
        task.delay(0.65, function() dot:Destroy() end)
    end)
end

local function Shake(obj)
    local base = obj.Position
    task.spawn(function()
        for _, dx in ipairs({10, -10, 6, -6, 0}) do
            Tween(obj, {Position = UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset)}, 0.05, Enum.EasingStyle.Sine)
            task.wait(0.05)
        end
    end)
end

-- Pointer position in the same space as AbsolutePosition (the gui ignores the inset)
local function Pointer(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        local inset = GuiService:GetGuiInset()
        return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
    end
    return UserInputService:GetMouseLocation()
end

-- Button: variant = "Primary" | "Secondary" | "Danger"
local function MakeButton(parent, text, variant, callback, props)
    variant = variant or "Secondary"
    local bgKey, txtKey = "Elevated", "Text"
    if variant == "Primary" then
        bgKey, txtKey = "Accent", "OnAccent"
    elseif variant == "Danger" then
        bgKey, txtKey = "Danger", "OnAccent"
    end
    local btn = New("TextButton", Merge({
        AutoButtonColor = false, Text = "", BackgroundColor3 = Theme[bgKey],
        BorderSizePixel = 0, ClipsDescendants = true, Size = UDim2.fromOffset(96, 32),
    }, props))
    Themed(btn, {BackgroundColor3 = bgKey})
    Corner(btn, 8)
    if variant == "Secondary" then AddStroke(btn, "Stroke", 1, 0.3) end
    local lbl = Label({
        Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = btn,
    }, txtKey)
    btn.MouseEnter:Connect(function()
        Tween(btn, {BackgroundColor3 = Theme[bgKey]:Lerp(Color3.new(1, 1, 1), 0.12)}, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        Tween(btn, {BackgroundColor3 = Theme[bgKey]}, 0.15)
    end)
    btn.MouseButton1Click:Connect(function()
        Ripple(btn, variant ~= "Secondary")
        Fire(callback)
    end)
    return btn, lbl
end

local function MakeDraggable(handle, target, maid)
    local dragging, startPoint, startPos = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPoint = input.Position
            startPos = target.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    conn:Disconnect()
                end
            end)
        end
    end)
    local move = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - startPoint
            Tween(target, {
                Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
            }, 0.1, Enum.EasingStyle.Sine)
        end
    end)
    if maid then maid:Give(move) end
end

-- Animated open/close for sections. The resting "open" state is plain AutomaticSize (natural flow),
-- so nothing has to be measured up front: a section inside a tab that was never opened still lays
-- itself out correctly. Heights are only measured while animating.
local function Collapsible(clip, content, opened)
    local c = {Opened = opened and true or false, _tok = 0}
    clip.Size = UDim2.new(1, 0, 0, 0)
    clip.ClipsDescendants = false
    clip.AutomaticSize = c.Opened and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
    clip.Visible = c.Opened

    function c:Set(open)
        open = open and true or false
        if open == self.Opened then return end
        self.Opened = open
        self._tok = self._tok + 1
        local tok = self._tok
        if open then
            clip.Visible = true
            clip.ClipsDescendants = true
            clip.AutomaticSize = Enum.AutomaticSize.None
            clip.Size = UDim2.new(1, 0, 0, 0)
            task.spawn(function()
                task.wait() -- let the layout measure the content
                if tok ~= self._tok then return end
                local h = math.max(0, math.floor(content.AbsoluteSize.Y / GetScale(content) + 0.5))
                local tw = Tween(clip, {Size = UDim2.new(1, 0, 0, h)}, 0.32)
                tw.Completed:Connect(function()
                    if tok == self._tok and self.Opened then
                        clip.AutomaticSize = Enum.AutomaticSize.Y
                        clip.Size = UDim2.new(1, 0, 0, 0)
                        clip.ClipsDescendants = false
                    end
                end)
            end)
        else
            local h = math.max(0, math.floor(clip.AbsoluteSize.Y / GetScale(clip) + 0.5))
            clip.AutomaticSize = Enum.AutomaticSize.None
            clip.ClipsDescendants = true
            clip.Size = UDim2.new(1, 0, 0, h)
            local tw = Tween(clip, {Size = UDim2.new(1, 0, 0, 0)}, 0.3)
            tw.Completed:Connect(function()
                if tok == self._tok and not self.Opened then clip.Visible = false end
            end)
        end
    end
    return c
end

------------------------------------------------------------------------
-- Lua syntax highlighter for the Code element (RichText)
------------------------------------------------------------------------
local SynKeywords, SynBuiltins = {}, {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while continue"):gmatch("%a+") do
    SynKeywords[w] = true
end
for w in ("print warn error pcall xpcall game workspace script Instance Enum Vector2 Vector3 CFrame Color3 UDim UDim2 task require loadstring setmetatable getmetatable typeof type tostring tonumber ipairs pairs table string math os tick wait spawn delay self"):gmatch("%a+") do
    SynBuiltins[w] = true
end

local function Esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function Highlight(src)
    local cKey, cStr, cNum, cCom, cBuiltin = "#C79BFF", "#A6E3A1", "#FFB885", "#6E7AA8", "#8DB8FF"
    local out, i, n = {}, 1, #src
    local function push(color, text)
        if color then
            out[#out + 1] = '<font color="' .. color .. '">' .. Esc(text) .. "</font>"
        else
            out[#out + 1] = Esc(text)
        end
    end
    while i <= n do
        local c = src:sub(i, i)
        if src:sub(i, i + 1) == "--" then
            local e = src:find("\n", i, true) or (n + 1)
            push(cCom, src:sub(i, e - 1))
            i = e
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c or d == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            push(cStr, src:sub(i, j))
            i = j + 1
        elseif c:match("%d") then
            local s, e = src:find("^%d+%.?%d*", i)
            push(cNum, src:sub(s, e))
            i = e + 1
        elseif c:match("[%a_]") then
            local s, e = src:find("^[%w_]+", i)
            local word = src:sub(s, e)
            if SynKeywords[word] then
                push(cKey, word)
            elseif SynBuiltins[word] then
                push(cBuiltin, word)
            else
                push(nil, word)
            end
            i = e + 1
        else
            push(nil, c)
            i = i + 1
        end
    end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Notifications
------------------------------------------------------------------------
local NotifHolder, notifOrder = nil, 0

local function GetNotifHolder()
    if NotifHolder and NotifHolder.Parent then return NotifHolder end
    NotifHolder = New("Frame", {
        Name = "Notifications", AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20), Size = UDim2.new(0, 320, 1, -40),
        BackgroundTransparency = 1, Parent = GetGui(),
    })
    List(NotifHolder, 8, {VerticalAlignment = Enum.VerticalAlignment.Bottom})
    return NotifHolder
end

function Lumina:Notify(cfg)
    cfg = cfg or {}
    local handle = {Close = function() end}
    if not Lumina.NotificationsEnabled then return handle end

    local kind = cfg.Type or "Info"
    local colorKey = ({Info = "Accent", Success = "Success", Warning = "Warning", Error = "Danger"})[kind] or "Accent"
    local glyph = cfg.Icon or ({Info = "i", Warning = "!"})[kind]
    if not glyph and kind ~= "Success" and kind ~= "Error" then glyph = "i" end
    local duration = cfg.Duration or 4

    notifOrder = notifOrder + 1
    local wrap = New("Frame", {
        Name = "Notification", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = notifOrder, Parent = GetNotifHolder(),
    })
    local card = New("CanvasGroup", {
        Name = "Card", BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(1.2, 0, 0, 0), GroupTransparency = 1, Parent = wrap,
    })
    Themed(card, {BackgroundColor3 = "Surface"})
    Corner(card, 12)
    AddStroke(card, colorKey, 1, 0.65)

    local content = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
    })
    Pad(content, 13, 14, 17, 18)

    local bubble = New("Frame", {
        Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Theme[colorKey],
        BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = content,
    })
    Themed(bubble, {BackgroundColor3 = colorKey})
    Corner(bubble, "full")
    local gl
    if glyph then
        gl = Icon(bubble, glyph, 15, colorKey)
    else
        gl = DrawIcon(bubble, kind == "Error" and "cross" or "check", 14, colorKey)
    end
    gl.AnchorPoint = Vector2.new(0.5, 0.5)
    gl.Position = UDim2.fromScale(0.5, 0.5)

    local col = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0),
        Size = UDim2.new(1, -40, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = content,
    })
    List(col, 2)
    Label({
        Text = tostring(cfg.Title or "Notification"), Font = Enum.Font.GothamBold, TextSize = 14,
        TextWrapped = true, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = col,
    }, "Text")
    if cfg.Content and cfg.Content ~= "" then
        Label({
            Text = tostring(cfg.Content), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = col,
        }, "SubText")
    end

    local bar = New("Frame", {
        Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Theme[colorKey], BorderSizePixel = 0, Parent = card,
    })
    Themed(bar, {BackgroundColor3 = colorKey})
    local progress = New("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme[colorKey], BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = card,
    })
    Themed(progress, {BackgroundColor3 = colorKey})

    Tween(card, {Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0}, 0.45)
    if duration > 0 then
        Tween(progress, {Size = UDim2.new(0, 0, 0, 2)}, duration, Enum.EasingStyle.Linear)
    end

    local closed = false
    local function close()
        if closed then return end
        closed = true
        local h = wrap.AbsoluteSize.Y
        Tween(card, {Position = UDim2.new(1.2, 0, 0, 0), GroupTransparency = 1}, 0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.3, function()
            if not wrap.Parent then return end
            wrap.AutomaticSize = Enum.AutomaticSize.None
            wrap.Size = UDim2.new(1, 0, 0, h)
            Tween(wrap, {Size = UDim2.new(1, 0, 0, 0)}, 0.25)
            task.delay(0.28, function() wrap:Destroy() end)
        end)
    end
    card.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            close()
        end
    end)
    if duration > 0 then task.delay(duration, close) end

    handle.Close = close
    return handle
end

------------------------------------------------------------------------
-- Dialog / Popup (modal cards)
------------------------------------------------------------------------
local function BuildModal(parent, cfg, popup)
    cfg = cfg or {}
    local modal = {_closed = false}

    local overlay = New("TextButton", {
        Name = "LuminaModal", Text = "", AutoButtonColor = false,
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 200, Parent = parent,
    })
    local card = New("CanvasGroup", {
        Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, popup and 380 or 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, GroupTransparency = 1, Parent = overlay,
    })
    Themed(card, {BackgroundColor3 = "Surface"})
    Corner(card, 14)
    AddStroke(card, "Stroke", 1, 0.2)
    local scale = New("UIScale", {Scale = 0.9, Parent = card})

    local body = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
    })
    Pad(body, 20, 20, 18, 20)
    List(body, 10, {
        HorizontalAlignment = popup and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left,
    })

    if popup or cfg.Icon then
        local size = popup and 52 or 36
        local bubble = New("Frame", {
            Size = UDim2.fromOffset(size, size), BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.82, BorderSizePixel = 0, LayoutOrder = 1, Parent = body,
        })
        Themed(bubble, {BackgroundColor3 = "Accent"})
        Corner(bubble, "full")
        AddStroke(bubble, "Accent", 1, 0.55)
        local ic = Icon(bubble, cfg.Icon or "★", popup and 24 or 18, "Accent")
        ic.AnchorPoint = Vector2.new(0.5, 0.5)
        ic.Position = UDim2.fromScale(0.5, 0.5)
    end

    local align = popup and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
    Label({
        Text = tostring(cfg.Title or "Notice"), Font = Enum.Font.GothamBold, TextSize = 17, TextWrapped = true,
        TextXAlignment = align, Size = UDim2.new(1, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2, Parent = body,
    }, "Text")
    if cfg.Content and cfg.Content ~= "" then
        Label({
            Text = tostring(cfg.Content), TextSize = 13, TextWrapped = true, RichText = cfg.RichText == true,
            TextXAlignment = align, TextYAlignment = Enum.TextYAlignment.Top,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = body,
        }, "SubText")
    end

    local buttons = cfg.Buttons
    if type(buttons) ~= "table" or #buttons == 0 then
        buttons = {{Title = "Okay", Variant = "Primary"}}
    end
    local row = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 4, Parent = body,
    })
    List(row, 8, {FillDirection = Enum.FillDirection.Horizontal})
    local n = #buttons
    for i, bcfg in ipairs(buttons) do
        MakeButton(row, bcfg.Title or "Okay", bcfg.Variant or ((i == n) and "Primary" or "Secondary"), function()
            Fire(bcfg.Callback)
            if not bcfg.Keep then modal:Close() end
        end, {Size = UDim2.new(1 / n, -8 * (n - 1) / n, 1, 0), LayoutOrder = i})
    end

    Tween(overlay, {BackgroundTransparency = 0.45}, 0.25)
    Tween(card, {GroupTransparency = 0}, 0.25)
    Tween(scale, {Scale = 1}, 0.4, Enum.EasingStyle.Back)

    function modal:Close()
        if self._closed then return end
        self._closed = true
        Tween(overlay, {BackgroundTransparency = 1}, 0.2)
        Tween(card, {GroupTransparency = 1}, 0.18)
        Tween(scale, {Scale = 0.92}, 0.2)
        task.delay(0.26, function() overlay:Destroy() end)
    end
    if cfg.CloseOnOverlay then
        overlay.MouseButton1Click:Connect(function() modal:Close() end)
    end
    return modal
end

function Lumina:Popup(cfg) return BuildModal(GetGui(), cfg, true) end
function Lumina:Dialog(cfg) return BuildModal(GetGui(), cfg, false) end

------------------------------------------------------------------------
-- Key system
------------------------------------------------------------------------
function Lumina:KeySystem(cfg)
    cfg = cfg or {}
    local canFS = (writefile and readfile and isfile) and true or false
    local keyPath = "Lumina/" .. tostring(cfg.FileName or "LuminaKey") .. ".key"
    local saveKey = cfg.SaveKey ~= false

    local function trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end

    local function check(raw)
        local key = trim(raw)
        if key == "" then return false, "Please enter your key." end
        if type(cfg.Validate) == "function" then
            local ok, res, msg = pcall(cfg.Validate, key)
            if not ok then return false, "Validation failed. Please try again." end
            if res then return true end
            return false, (type(msg) == "string" and msg) or "That key is not valid."
        end
        if type(cfg.Keys) == "table" then
            for _, k in ipairs(cfg.Keys) do
                if tostring(k) == key then return true end
            end
        end
        return false, "That key is not valid."
    end

    -- A previously saved key skips the UI entirely
    if saveKey and canFS then
        local ok, saved = pcall(function()
            if isfile(keyPath) then return readfile(keyPath) end
            return nil
        end)
        if ok and saved and check(saved) then
            Fire(cfg.Callback, trim(saved))
            return true
        end
    end

    local gui = GetGui()
    local done, success, busy = false, false, false

    local overlay = New("Frame", {
        Name = "LuminaKeySystem", Active = true, BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 500, Parent = gui,
    })
    New("UIGradient", {
        Rotation = 120,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Background:Lerp(Theme.Accent, 0.22)),
            ColorSequenceKeypoint.new(0.5, Theme.Background),
            ColorSequenceKeypoint.new(1, Theme.Background:Lerp(Theme.Elevated, 0.6)),
        }),
        Parent = overlay,
    })

    local card = New("CanvasGroup", {
        Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 420, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background, BorderSizePixel = 0, GroupTransparency = 1, Parent = overlay,
    })
    Themed(card, {BackgroundColor3 = "Background"})
    Corner(card, 16)
    AddStroke(card, "Stroke", 1, 0.1)
    local cscale = New("UIScale", {Scale = 0.92, Parent = card})

    local topLine = New("Frame", {
        Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3, Parent = card,
    })
    local tlg = New("UIGradient", {Parent = topLine})
    tlg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentDark),
        ColorSequenceKeypoint.new(0.5, Theme.AccentSoft),
        ColorSequenceKeypoint.new(1, Theme.AccentDark),
    })

    local body = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
    })
    Pad(body, 26, 26, 24, 26)
    List(body, 14)

    -- header
    local head = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 1, Parent = body})
    local bubble = New("Frame", {
        Size = UDim2.fromOffset(48, 48), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.82,
        BorderSizePixel = 0, Parent = head,
    })
    Themed(bubble, {BackgroundColor3 = "Accent"})
    Corner(bubble, "full")
    AddStroke(bubble, "Accent", 1, 0.5)
    local bi = Icon(bubble, cfg.Icon or "★", 22, "Accent")
    bi.AnchorPoint = Vector2.new(0.5, 0.5)
    bi.Position = UDim2.fromScale(0.5, 0.5)
    Label({
        Text = tostring(cfg.Title or "Key System"), Font = Enum.Font.GothamBold, TextSize = 18,
        Position = UDim2.fromOffset(62, 4), Size = UDim2.new(1, -100, 0, 22), Parent = head,
    }, "Text")
    Label({
        Text = tostring(cfg.Subtitle or "Enter your key to continue"), TextSize = 12,
        Position = UDim2.fromOffset(62, 28), Size = UDim2.new(1, -100, 0, 18), Parent = head,
    }, "SubText")

    local closeBtn = New("TextButton", {
        Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Theme.Elevated, BackgroundTransparency = 1,
        BorderSizePixel = 0, Parent = head,
    })
    Corner(closeBtn, 8)
    local closeLbl = Label({
        Text = "×", Font = Enum.Font.GothamBold, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Parent = closeBtn,
    }, "SubText")
    closeBtn.MouseEnter:Connect(function()
        Tween(closeBtn, {BackgroundTransparency = 0}, 0.15)
        Tween(closeLbl, {TextColor3 = Theme.Danger}, 0.15)
    end)
    closeBtn.MouseLeave:Connect(function()
        Tween(closeBtn, {BackgroundTransparency = 1}, 0.15)
        Tween(closeLbl, {TextColor3 = Theme.SubText}, 0.15)
    end)

    local order = 1
    if cfg.Note and cfg.Note ~= "" then
        order = order + 1
        local noteBox = New("Frame", {
            BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = body,
        })
        Themed(noteBox, {BackgroundColor3 = "Surface"})
        Corner(noteBox, 10)
        Pad(noteBox, 10, 12)
        Label({
            Text = tostring(cfg.Note), TextSize = 12, TextWrapped = true, RichText = cfg.RichText == true,
            TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, Parent = noteBox,
        }, "SubText")
    end

    order = order + 1
    local inputBox = New("Frame", {
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44),
        LayoutOrder = order, Parent = body,
    })
    Themed(inputBox, {BackgroundColor3 = "Surface"})
    Corner(inputBox, 10)
    local inputStroke = AddStroke(inputBox, false, 1, 0.2)
    local box = New("TextBox", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0),
        Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Theme.Text, Text = "",
        PlaceholderText = tostring(cfg.Placeholder or "Paste your key here"), PlaceholderColor3 = Theme.Muted,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = inputBox,
    })
    Themed(box, {TextColor3 = "Text", PlaceholderColor3 = "Muted"})
    box.Focused:Connect(function()
        Tween(inputStroke, {Color = Theme.Accent, Transparency = 0}, 0.2)
    end)

    order = order + 1
    local status = Label({
        Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order, Parent = body,
    }, false)
    local function setStatus(text, key)
        status.Text = text
        Tween(status, {TextColor3 = Theme[key or "SubText"]}, 0.2)
    end

    local function finish(ok)
        if done then return end
        success = ok
        done = true
        Tween(overlay, {BackgroundTransparency = 1}, 0.3)
        Tween(card, {GroupTransparency = 1}, 0.25)
        Tween(cscale, {Scale = 0.92}, 0.25)
        task.delay(0.4, function() overlay:Destroy() end)
    end

    local verifyLbl
    local function submit()
        if busy or done then return end
        busy = true
        local key = trim(box.Text)
        setStatus("Verifying…", "SubText")
        if verifyLbl then verifyLbl.Text = "Verifying…" end
        task.spawn(function()
            local ok, msg = check(key)
            if verifyLbl then verifyLbl.Text = "Verify Key" end
            if ok then
                setStatus("Key accepted — welcome!", "Success")
                Tween(inputStroke, {Color = Theme.Success, Transparency = 0}, 0.2)
                if saveKey and canFS then
                    pcall(function()
                        if makefolder and isfolder and not isfolder("Lumina") then makefolder("Lumina") end
                        writefile(keyPath, key)
                    end)
                end
                Fire(cfg.Callback, key)
                task.wait(0.7)
                finish(true)
            else
                setStatus(msg or "That key is not valid.", "Danger")
                Tween(inputStroke, {Color = Theme.Danger, Transparency = 0}, 0.2)
                Shake(card)
                busy = false
            end
        end)
    end

    order = order + 1
    local verifyBtn
    verifyBtn, verifyLbl = MakeButton(body, "Verify Key", "Primary", submit, {
        Size = UDim2.new(1, 0, 0, 42), LayoutOrder = order,
    })

    if type(cfg.Links) == "table" and #cfg.Links > 0 then
        order = order + 1
        local linkRow = New("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, Parent = body,
        })
        List(linkRow, 8, {FillDirection = Enum.FillDirection.Horizontal})
        local n = #cfg.Links
        for i, link in ipairs(cfg.Links) do
            MakeButton(linkRow, link.Title or "Get Key", "Secondary", function()
                if type(link.Callback) == "function" then
                    Fire(link.Callback)
                    return
                end
                local clip = setclipboard or toclipboard or (syn and syn.write_clipboard)
                if clip and link.Url then
                    pcall(clip, link.Url)
                    setStatus("Link copied to your clipboard.", "Success")
                else
                    setStatus(tostring(link.Url or ""), "SubText")
                end
            end, {Size = UDim2.new(1 / n, -8 * (n - 1) / n, 1, 0), LayoutOrder = i})
        end
    end

    box.FocusLost:Connect(function(enter)
        Tween(inputStroke, {Color = Theme.Stroke, Transparency = 0.2}, 0.2)
        if enter then submit() end
    end)
    closeBtn.MouseButton1Click:Connect(function() finish(false) end)

    Tween(overlay, {BackgroundTransparency = 0.08}, 0.35)
    Tween(card, {GroupTransparency = 0}, 0.3)
    Tween(cscale, {Scale = 1}, 0.45, Enum.EasingStyle.Back)

    while not done do task.wait(0.1) end
    return success
end

------------------------------------------------------------------------
-- Image helper: rbxassetid / number, or an https URL (downloaded once via the executor)
------------------------------------------------------------------------
local function ResolveImage(src)
    if src == nil or src == false or src == "" then return nil end
    local a = Asset(src)
    if a then return a end
    if type(src) == "string" and src:match("^https?://") then
        local getAsset = getcustomasset or getsynasset
        if getAsset and writefile and isfile and readfile then
            local h = 5381
            for i = 1, #src do h = (h * 33 + src:byte(i)) % 4294967296 end
            local path = "Lumina/img_" .. h .. ".png"
            local ok, result = pcall(function()
                if makefolder and isfolder and not isfolder("Lumina") then makefolder("Lumina") end
                if not isfile(path) then writefile(path, game:HttpGet(src)) end
                return getAsset(path)
            end)
            if ok and result then return result end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Loader UI (shown before the window opens)
------------------------------------------------------------------------
function Lumina:Loader(cfg)
    if type(cfg) ~= "table" then cfg = {} end
    local gui = GetGui()
    local title = tostring(cfg.Title or "Lumina")
    local tagline = tostring(cfg.Subtitle or "Preparing your experience")

    local steps = {}
    local source = cfg.Steps or {
        "Initializing interface", "Loading theme", "Preparing components", "Checking environment", "Almost ready",
    }
    for _, s in ipairs(source) do
        if type(s) == "string" then steps[#steps + 1] = {Text = s} else steps[#steps + 1] = s end
    end
    local total = math.max(#steps, 1)
    local per = (tonumber(cfg.Duration) or 2.6) / total

    local stage = New("CanvasGroup", {
        Name = "LuminaLoader", Active = true, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, GroupTransparency = 1, ZIndex = 600, Parent = gui,
    })
    local bg = New("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = stage,
    })
    New("UIGradient", {
        Rotation = 135,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Background:Lerp(Theme.Accent, 0.16)),
            ColorSequenceKeypoint.new(0.5, Theme.Background),
            ColorSequenceKeypoint.new(1, Theme.Background:Lerp(Theme.Elevated, 0.7)),
        }),
        Parent = bg,
    })
    New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(780, 780),
        BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = Theme.Accent,
        ImageTransparency = 0.84, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450), Parent = stage,
    })

    local box = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = stage,
    })
    local boxScale = New("UIScale", {Scale = 0.92, Parent = box})
    List(box, 12, {HorizontalAlignment = Enum.HorizontalAlignment.Center})

    -- logo: faint track ring + spinning gradient ring + icon bubble
    local logo = New("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(96, 96), LayoutOrder = 1, Parent = box})
    local track = New("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = logo})
    Corner(track, "full")
    local trackStroke = New("UIStroke", {Color = Theme.Stroke, Thickness = 3, Transparency = 0.35, Parent = track})
    local ring = New("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = logo})
    Corner(ring, "full")
    local ringStroke = New("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 3, Parent = ring})
    local ringGrad = New("UIGradient", {
        Color = ColorSequence.new(Theme.AccentSoft, Theme.Accent),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0.1),
            NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = ringStroke,
    })
    local spin = TweenService:Create(ringGrad, TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 360})
    spin:Play()

    local bubble = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = logo,
    })
    Corner(bubble, "full")
    local bubbleScale = New("UIScale", {Scale = 1, Parent = bubble})
    local logoAsset = ResolveImage(cfg.Logo)
    local glyph, logoImg
    if logoAsset then
        bubble.BackgroundTransparency = 1
        logoImg = New("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(68, 68),
            BackgroundTransparency = 1, Image = logoAsset, ScaleType = Enum.ScaleType.Fit,
            ImageTransparency = 1, Parent = bubble,
        })
        if cfg.LogoRound ~= false then Corner(logoImg, "full") end
        Tween(logoImg, {ImageTransparency = 0}, 0.6)
    else
        glyph = Icon(bubble, cfg.Icon or "★", 30, false, Theme.Accent)
        glyph.AnchorPoint = Vector2.new(0.5, 0.5)
        glyph.Position = UDim2.fromScale(0.5, 0.5)
    end
    local badge = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 1, -8), Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.Success, BorderSizePixel = 0, ZIndex = 3, Parent = logo,
    })
    Corner(badge, "full")
    local checkBox = DrawIcon(badge, "check", 14, "OnAccent")
    checkBox.AnchorPoint = Vector2.new(0.5, 0.5)
    checkBox.Position = UDim2.fromScale(0.5, 0.5)
    checkBox.Visible = false

    local titleLbl = Label({
        Text = title, Font = Enum.Font.GothamBold, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, TextTransparency = 1, Parent = box,
    }, "Text")
    local tagLbl = Label({
        Text = tagline, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, TextTransparency = 1, Parent = box,
    }, "SubText")

    local barBlock = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -30, 0, 46), LayoutOrder = 4, Parent = box})
    local barTrack = New("Frame", {
        Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = Theme.Elevated,
        BorderSizePixel = 0, Parent = barBlock,
    })
    Corner(barTrack, "full")
    local fill = New("Frame", {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = barTrack,
    })
    Corner(fill, "full")
    local fillGrad = New("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.AccentDark), ColorSequenceKeypoint.new(0.5, Theme.AccentSoft),
            ColorSequenceKeypoint.new(1, Theme.AccentDark),
        }),
        Offset = Vector2.new(-1, 0), Parent = fill,
    })
    local shimmer = TweenService:Create(fillGrad, TweenInfo.new(1.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Offset = Vector2.new(1, 0)})
    shimmer:Play()

    local status = Label({
        Text = "", TextSize = 12, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -50, 0, 16), Parent = barBlock,
    }, "SubText")
    local pct = Label({
        Text = "0%", Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(1, -46, 0, 26), Size = UDim2.fromOffset(46, 16), Parent = barBlock,
    }, "Accent")
    fill:GetPropertyChangedSignal("Size"):Connect(function()
        pct.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
    end)

    Label({
        Text = "Welcome, " .. LocalPlayer.DisplayName .. "   ·   Lumina UI v" .. Lumina.Version, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, 0, 0, 14), Parent = stage,
    }, "Muted")

    -- intro
    Tween(stage, {GroupTransparency = 0}, 0.4)
    Tween(boxScale, {Scale = 1}, 0.7, Enum.EasingStyle.Back)
    task.delay(0.15, function() Tween(titleLbl, {TextTransparency = 0}, 0.6) end)
    task.delay(0.3, function() Tween(tagLbl, {TextTransparency = 0}, 0.6) end)
    task.wait(0.55)

    -- steps (each step may run real work in step.Run)
    for i, step in ipairs(steps) do
        status.TextTransparency = 1
        status.Text = tostring(step.Text or "")
        Tween(status, {TextTransparency = 0}, 0.25)
        local startFrac, endFrac = (i - 1) / total, i / total
        local dur = tonumber(step.Duration) or per
        local started = os.clock()
        Tween(fill, {Size = UDim2.fromScale(startFrac + (endFrac - startFrac) * 0.85, 1)}, math.max(dur, 0.2), Enum.EasingStyle.Quad)
        if type(step.Run) == "function" then pcall(step.Run) end
        local left = dur - (os.clock() - started)
        if left > 0 then task.wait(left) end
        Tween(fill, {Size = UDim2.fromScale(endFrac, 1)}, 0.2)
        task.wait(0.18)
    end

    -- done: ring becomes a success check
    status.Text = tostring(cfg.ReadyText or "Ready")
    Tween(ringStroke, {Transparency = 1}, 0.25)
    Tween(trackStroke, {Color = Theme.Success, Transparency = 0.1}, 0.3)
    if glyph then
        Tween(glyph, {TextColor3 = Theme.Success}, 0.25)
        Tween(bubble, {BackgroundColor3 = Theme.Success}, 0.25)
    end
    checkBox.Visible = true
    Tween(badge, {Size = UDim2.fromOffset(26, 26)}, 0.35, Enum.EasingStyle.Back)
    Tween(bubbleScale, {Scale = 1.18}, 0.25, Enum.EasingStyle.Back)
    task.delay(0.25, function() Tween(bubbleScale, {Scale = 1}, 0.3, Enum.EasingStyle.Quint) end)
    task.wait(0.6)

    Tween(stage, {GroupTransparency = 1}, 0.5)
    Tween(boxScale, {Scale = 1.08}, 0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    task.wait(0.5)
    spin:Cancel()
    shimmer:Cancel()
    stage:Destroy()
end

------------------------------------------------------------------------
-- Favorites (persisted to Lumina/favorites.json when the executor has a file system)
------------------------------------------------------------------------
local FAV_FILE = "Lumina/favorites.json"
local Favorites, FavListeners, favId = {}, {}, 0

local function FSAvailable()
    return (writefile and readfile and isfile and makefolder and isfolder) and true or false
end

local function SaveFavorites()
    if not FSAvailable() then return end
    pcall(function()
        if not isfolder("Lumina") then makefolder("Lumina") end
        writefile(FAV_FILE, HttpService:JSONEncode(Favorites))
    end)
end

if FSAvailable() then
    pcall(function()
        if isfile(FAV_FILE) then
            local data = HttpService:JSONDecode(readfile(FAV_FILE))
            if type(data) == "table" then Favorites = data end
        end
    end)
end

local function FavChanged()
    for _, fn in pairs(FavListeners) do pcall(fn) end
end

function Lumina:OnFavoritesChanged(fn)
    favId = favId + 1
    local id = favId
    FavListeners[id] = fn
    return function() FavListeners[id] = nil end
end

function Lumina:GetFavorites() return Favorites end

function Lumina:IsFavorite(placeId)
    for _, g in ipairs(Favorites) do
        if tonumber(g.PlaceId) == tonumber(placeId) then return true end
    end
    return false
end

function Lumina:AddFavorite(info)
    if not info or not info.PlaceId or self:IsFavorite(info.PlaceId) then return false end
    Favorites[#Favorites + 1] = {
        Name = info.Name, PlaceId = info.PlaceId, UniverseId = info.UniverseId, Creator = info.Creator,
        Players = info.Players, Up = info.Up, Down = info.Down,
    }
    SaveFavorites()
    FavChanged()
    return true
end

function Lumina:RemoveFavorite(placeId)
    for i, g in ipairs(Favorites) do
        if tonumber(g.PlaceId) == tonumber(placeId) then
            table.remove(Favorites, i)
            SaveFavorites()
            FavChanged()
            return true
        end
    end
    return false
end

-- returns the new favorite state
function Lumina:ToggleFavorite(info)
    if self:IsFavorite(info.PlaceId) then
        self:RemoveFavorite(info.PlaceId)
        return false
    end
    self:AddFavorite(info)
    return true
end

------------------------------------------------------------------------
-- Game search + teleport (needs an executor with HTTP support)
------------------------------------------------------------------------
local function HttpGetJson(url)
    local body
    local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    if req then
        local ok, res = pcall(req, {Url = url, Method = "GET"})
        if ok and type(res) == "table" and (res.Success or res.StatusCode == 200) then body = res.Body end
    end
    if not body then
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok then body = res end
    end
    if type(body) ~= "string" or body == "" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return data end
    return nil
end

local function ParseGames(data)
    local out, seen = {}, {}
    if type(data) ~= "table" then return out end
    local function add(c)
        local placeId = c.rootPlaceId or c.placeId
        if c.name and placeId and not seen[placeId] then
            seen[placeId] = true
            out[#out + 1] = {
                Name = c.name, UniverseId = c.universeId, PlaceId = placeId, Creator = c.creatorName,
                Players = c.playerCount, Up = c.totalUpVotes, Down = c.totalDownVotes,
            }
        end
    end
    if type(data.searchResults) == "table" then
        for _, group in ipairs(data.searchResults) do
            for _, c in ipairs(group.contents or {}) do
                if c.contentType == nil or c.contentType == "Game" then add(c) end
            end
        end
    end
    if type(data.games) == "table" then
        for _, c in ipairs(data.games) do add(c) end
    end
    return out
end

local function LookupGameById(id)
    local universeId = tonumber(id)
    local d = HttpGetJson("https://apis.roblox.com/universes/v1/places/" .. id .. "/universe")
    if d and d.universeId then universeId = d.universeId end
    local info = HttpGetJson("https://games.roblox.com/v1/games?universeIds=" .. tostring(universeId))
    if info == nil then return nil, true end
    local g = info.data and info.data[1]
    if not g then return nil, false end
    local votes = HttpGetJson("https://games.roblox.com/v1/games/votes?universeIds=" .. tostring(universeId))
    local v = votes and votes.data and votes.data[1]
    return {
        Name = g.name, UniverseId = g.id, PlaceId = g.rootPlaceId, Creator = g.creator and g.creator.name,
        Players = g.playing, Up = v and v.upVotes, Down = v and v.downVotes,
    }, false
end

-- returns list, errorMessage  (list is nil when Roblox could not be reached)
function Lumina:SearchGames(query)
    query = tostring(query or ""):match("^%s*(.-)%s*$")
    if query == "" then return {} end
    if query:match("^%d+$") then
        local g, failed = LookupGameById(query)
        if g then return {g} end
        if failed then return nil, "Could not reach Roblox. Your executor needs HTTP support." end
        return {}
    end
    local enc = HttpService:UrlEncode(query)
    local reached = false
    local data = HttpGetJson("https://apis.roblox.com/search-api/omni-search?searchQuery=" .. enc
        .. "&pageType=all&sessionId=" .. HttpService:GenerateGUID(false))
    if data ~= nil then reached = true end
    local list = ParseGames(data)
    if #list == 0 then
        data = HttpGetJson("https://games.roblox.com/v1/games/list?model.keyword=" .. enc .. "&model.maxRows=24")
        if data ~= nil then reached = true end
        list = ParseGames(data)
    end
    if not reached then return nil, "Could not reach Roblox. Your executor needs HTTP support." end
    return list
end

function Lumina:TeleportToGame(placeId, name)
    placeId = tonumber(placeId)
    if not placeId then return false end
    local TeleportService = game:GetService("TeleportService")
    Lumina:Notify({Title = "Teleporting…", Content = tostring(name or placeId), Type = "Info", Duration = 4})
    local failConn
    failConn = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
        if player == LocalPlayer then
            Lumina:Notify({Title = "Teleport failed", Content = tostring((message ~= nil and message ~= "") and message or result), Type = "Error"})
            failConn:Disconnect()
        end
    end)
    task.delay(20, function()
        if failConn.Connected then failConn:Disconnect() end
    end)
    local ok, err = pcall(function() TeleportService:Teleport(placeId, LocalPlayer) end)
    if not ok then
        failConn:Disconnect()
        Lumina:Notify({Title = "Teleport failed", Content = tostring(err), Type = "Error"})
    end
    return ok
end

local function FormatCount(n)
    n = tonumber(n)
    if not n then return "?" end
    if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

------------------------------------------------------------------------
-- Element framework
------------------------------------------------------------------------
local ContainerMethods = {}
local ContainerMeta = {__index = ContainerMethods}

local ElementBase = {}
ElementBase.__index = ElementBase

function ElementBase:SetTitle(text)
    if self._title then self._title.Text = tostring(text) end
end

function ElementBase:SetDesc(text)
    if self._desc then
        self._desc.Text = tostring(text or "")
        self._desc.Visible = text ~= nil and text ~= ""
    end
end

function ElementBase:SetVisible(visible)
    self.Frame.Visible = visible and true or false
end

function ElementBase:Lock()
    if not self._lock then
        self._lock = New("Frame", {
            Name = "Lock", BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.35,
            BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 30, Active = true, Parent = self.Frame,
        })
        Themed(self._lock, {BackgroundColor3 = "Background"})
        Corner(self._lock, 10)
    end
    self._lock.Visible = true
    self.Locked = true
end

function ElementBase:Unlock()
    if self._lock then self._lock.Visible = false end
    self.Locked = false
end

function ElementBase:Destroy()
    self._maid:Clean()
    if self.Flag and Lumina.Flags[self.Flag] == self then Lumina.Flags[self.Flag] = nil end
    if self.Frame then self.Frame:Destroy() end
end

local function NewContainer(window, content, scroller, extra)
    local c = setmetatable({_window = window, _content = content, _scroller = scroller, _order = 0}, ContainerMeta)
    if extra then
        for k, v in pairs(extra) do c[k] = v end
    end
    return c
end

-- Parent a finished frame into the container (and re-balance HStack rows)
function ContainerMethods:_attach(frame)
    self._order = (self._order or 0) + 1
    frame.LayoutOrder = self._order
    frame.Parent = self._content
    if self._stack == "H" then
        self._kids = self._kids or {}
        table.insert(self._kids, frame)
        local n, gap = #self._kids, self._gap or 8
        for _, f in ipairs(self._kids) do
            f.Size = UDim2.new(1 / n, -(gap * (n - 1)) / n, 0, f.Size.Y.Offset)
        end
    end
end

-- Standard card: rounded surface, title/description on the left, room for a control on the right
local function BuildCard(ctx, cfg, opts)
    opts = opts or {}
    local card = New("Frame", {
        Name = tostring(cfg.Title or "Element"), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ClipsDescendants = true,
    })
    Themed(card, {BackgroundColor3 = "Surface"})
    Corner(card, 10)
    local stroke = AddStroke(card, "Stroke", 1, 0.4)

    local inner = New("Frame", {
        Name = "Inner", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Parent = card,
    })
    Pad(inner, 11, 14)
    List(inner, 10)

    local header = New("Frame", {
        Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = inner,
    })
    local left, right = opts.LeftWidth or 0, opts.RightWidth or 0
    local textCol = New("Frame", {
        Name = "Text", BackgroundTransparency = 1, Position = UDim2.fromOffset(left, 0),
        Size = UDim2.new(1, -(left + right), 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = header,
    })
    List(textCol, 1)
    local title = Label({
        Name = "Title", Text = tostring(cfg.Title or ""), Font = Enum.Font.GothamMedium, TextSize = 14,
        TextWrapped = true, Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1, Parent = textCol,
    }, "Text")
    local hasDesc = cfg.Desc ~= nil and cfg.Desc ~= ""
    local desc = Label({
        Name = "Desc", Text = tostring(cfg.Desc or ""), TextSize = 12, TextWrapped = true,
        RichText = cfg.RichText == true, TextYAlignment = Enum.TextYAlignment.Top,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = hasDesc,
        LayoutOrder = 2, Parent = textCol,
    }, "SubText")

    return {Card = card, Inner = inner, Header = header, Stroke = stroke, TextCol = textCol, Title = title, Desc = desc}
end

local function NewElement(ctx, built, cfg, elType)
    local el = setmetatable({
        Frame = built.Card, Type = elType, Flag = cfg.Flag, Locked = false,
        _maid = NewMaid(), _title = built.Title, _desc = built.Desc, _ctx = ctx,
    }, ElementBase)
    ctx._window._maid:Give(function() el._maid:Clean() end)
    if cfg.Flag then Lumina.Flags[cfg.Flag] = el end
    ctx:_attach(el.Frame)
    if cfg.Locked then el:Lock() end
    if cfg.Visible == false then el.Frame.Visible = false end
    return el
end

local function CardHover(b, hit)
    hit.MouseEnter:Connect(function()
        Tween(b.Card, {BackgroundColor3 = Theme.SurfaceHover}, 0.18)
        Tween(b.Stroke, {Color = Theme.Accent, Transparency = 0.55}, 0.18)
    end)
    hit.MouseLeave:Connect(function()
        Tween(b.Card, {BackgroundColor3 = Theme.Surface}, 0.18)
        Tween(b.Stroke, {Color = Theme.Stroke, Transparency = 0.4}, 0.18)
    end)
end

-- Opens/closes a clipped sub-panel (dropdown list, colour panel)
local function PanelToggle(clip, height)
    local state = {Open = false}
    function state:Set(open)
        if open == self.Open then return end
        self.Open = open
        if open then clip.Visible = true end
        Tween(clip, {Size = UDim2.new(1, 0, 0, open and height() or 0)}, 0.3)
        task.delay(0.32, function()
            if not self.Open then clip.Visible = false end
        end)
    end
    return state
end

------------------------------------------------------------------------
-- Button
------------------------------------------------------------------------
function ContainerMethods:Button(cfg)
    cfg = cfg or {}
    local variant = cfg.Variant or "Default"
    local colored = variant == "Primary" or variant == "Danger"
    local baseKey = (variant == "Primary" and "Accent") or (variant == "Danger" and "Danger") or "Surface"

    local b = BuildCard(self, cfg, {RightWidth = 32})
    local el = NewElement(self, b, cfg, "Button")
    if colored then
        Themed(b.Card, {BackgroundColor3 = baseKey})
        Themed(b.Title, {TextColor3 = "OnAccent"})
        Themed(b.Desc, {TextColor3 = "OnAccent"})
        b.Desc.TextTransparency = 0.25
        b.Stroke.Transparency = 1
    end
    local arrow
    if cfg.Icon == nil then
        arrow = DrawIcon(b.Header, "chevron", 14, colored and "OnAccent" or "SubText")
        arrow.Rotation = -90
    else
        arrow = Icon(b.Header, cfg.Icon, 20, colored and "OnAccent" or "SubText")
    end
    if arrow then
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, 0, 0.5, 0)
    end

    local hit = Hitbox(b.Card)
    hit.MouseEnter:Connect(function()
        if colored then
            Tween(b.Card, {BackgroundColor3 = Theme[baseKey]:Lerp(Color3.new(1, 1, 1), 0.12)}, 0.18)
        else
            Tween(b.Card, {BackgroundColor3 = Theme.SurfaceHover}, 0.18)
            Tween(b.Stroke, {Color = Theme.Accent, Transparency = 0.55}, 0.18)
        end
        if arrow then Tween(arrow, {Position = UDim2.new(1, 4, 0.5, 0)}, 0.2) end
    end)
    hit.MouseLeave:Connect(function()
        if colored then
            Tween(b.Card, {BackgroundColor3 = Theme[baseKey]}, 0.18)
        else
            Tween(b.Card, {BackgroundColor3 = Theme.Surface}, 0.18)
            Tween(b.Stroke, {Color = Theme.Stroke, Transparency = 0.4}, 0.18)
        end
        if arrow then Tween(arrow, {Position = UDim2.new(1, 0, 0.5, 0)}, 0.2) end
    end)
    hit.MouseButton1Click:Connect(function()
        if el.Locked then return end
        Ripple(b.Card, colored)
        Fire(cfg.Callback)
    end)

    function el:SetCallback(fn) cfg.Callback = fn end
    return el
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function ContainerMethods:Toggle(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 56})
    local el = NewElement(self, b, cfg, "Toggle")
    local state = cfg.Default == true

    local track = New("Frame", {
        Name = "Track", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(44, 24), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Parent = b.Header,
    })
    Corner(track, "full")
    local tstroke = AddStroke(track, false, 1, 0.2)
    local knob = New("Frame", {
        Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Theme.SubText, BorderSizePixel = 0, Parent = track,
    })
    Corner(knob, "full")

    local function render(instant)
        Apply(track, {BackgroundColor3 = state and Theme.Accent or Theme.Elevated}, instant, 0.25)
        Apply(tstroke, {Color = state and Theme.Accent or Theme.Stroke}, instant, 0.25)
        Apply(knob, {
            Position = state and UDim2.new(0, 23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = state and Theme.OnAccent or Theme.SubText,
        }, instant, 0.3, Enum.EasingStyle.Back)
    end
    render(true)
    el._maid:Give(OnTheme(function() render(true) end))

    local function set(v, silent)
        v = v and true or false
        if v == state then return end
        state = v
        render(false)
        if not silent then Fire(cfg.Callback, state) end
    end

    local hit = Hitbox(b.Card)
    CardHover(b, hit)
    hit.MouseButton1Down:Connect(function()
        if not el.Locked then Tween(knob, {Size = UDim2.fromOffset(20, 18)}, 0.12) end
    end)
    hit.MouseButton1Up:Connect(function() Tween(knob, {Size = UDim2.fromOffset(18, 18)}, 0.15) end)
    hit.MouseLeave:Connect(function() Tween(knob, {Size = UDim2.fromOffset(18, 18)}, 0.15) end)
    hit.MouseButton1Click:Connect(function()
        if el.Locked then return end
        Ripple(b.Card)
        set(not state)
    end)

    function el:Set(v, silent) set(v, silent) end
    function el:Get() return state end
    function el:Serialize() return state end
    function el:Deserialize(v) set(v == true) end

    if cfg.CallOnInit ~= false then task.defer(Fire, cfg.Callback, state) end
    return el
end

------------------------------------------------------------------------
-- Slider
------------------------------------------------------------------------
function ContainerMethods:Slider(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 72})
    local el = NewElement(self, b, cfg, "Slider")

    local min, max = cfg.Min or 0, cfg.Max or 100
    local step = cfg.Step or cfg.Increment or 1
    local decimals = #((tostring(step):match("%.(%d+)")) or "")
    local suffix = cfg.Suffix or ""
    local value = math.clamp(cfg.Default or min, min, max)
    local dragging = false

    local valBox = New("TextBox", {
        Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(60, 24), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Theme.Accent, Text = "",
        ClearTextOnFocus = true, Parent = b.Header,
    })
    Themed(valBox, {BackgroundColor3 = "Elevated", TextColor3 = "Accent"})
    Corner(valBox, 7)

    local row = New("Frame", {Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, Parent = b.Inner})
    local track = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Parent = row,
    })
    Themed(track, {BackgroundColor3 = "Elevated"})
    Corner(track, "full")
    local fill = New("Frame", {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track,
    })
    Corner(fill, "full")
    local fillGrad = New("UIGradient", {Parent = fill})
    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = track,
    })
    Corner(knob, "full")
    AddStroke(knob, "Accent", 2, 0)

    local function paintFill() fillGrad.Color = ColorSequence.new(Theme.AccentDark, Theme.Accent) end
    paintFill()
    el._maid:Give(OnTheme(paintFill))

    local function render(instant)
        local r = (max > min) and (value - min) / (max - min) or 0
        Apply(fill, {Size = UDim2.fromScale(r, 1)}, instant, 0.1, Enum.EasingStyle.Sine)
        Apply(knob, {Position = UDim2.fromScale(r, 0.5)}, instant, 0.1, Enum.EasingStyle.Sine)
        valBox.Text = string.format("%." .. decimals .. "f", value) .. suffix
    end
    render(true)

    local function set(v, silent, force)
        v = math.clamp(v, min, max)
        v = math.floor((v - min) / step + 0.5) * step + min
        v = math.clamp(tonumber(string.format("%." .. decimals .. "f", v)) or min, min, max)
        if v == value and not force then
            render(false)
            return
        end
        value = v
        render(false)
        if not silent then Fire(cfg.Callback, value) end
    end

    local function fromInput(input)
        local ap, as = track.AbsolutePosition.X, track.AbsoluteSize.X
        if as <= 0 then return end
        local r = math.clamp((input.Position.X - ap) / as, 0, 1)
        set(min + (max - min) * r)
    end

    local function setScrolling(enabled)
        if self._scroller then self._scroller.ScrollingEnabled = enabled end
    end

    row.InputBegan:Connect(function(input)
        if el.Locked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setScrolling(false)
            Tween(knob, {Size = UDim2.fromOffset(18, 18)}, 0.12)
            fromInput(input)
        end
    end)
    el._maid:Give(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromInput(input)
        end
    end))
    el._maid:Give(UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            setScrolling(true)
            Tween(knob, {Size = UDim2.fromOffset(14, 14)}, 0.15)
        end
    end))
    valBox.FocusLost:Connect(function()
        local n = tonumber(valBox.Text:match("-?[%d%.]+"))
        if n then set(n) else render(true) end
    end)

    function el:Set(v, silent) set(tonumber(v) or value, silent, true) end
    function el:Get() return value end
    function el:Serialize() return value end
    function el:Deserialize(v) self:Set(v) end

    if cfg.CallOnInit ~= false then task.defer(Fire, cfg.Callback, value) end
    return el
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
function ContainerMethods:Input(cfg)
    cfg = cfg or {}
    local area = cfg.Type == "Textarea" or cfg.MultiLine == true
    local b = BuildCard(self, cfg, {})
    local el = NewElement(self, b, cfg, "Input")
    local value = cfg.Default ~= nil and tostring(cfg.Default) or ""

    local holder = New("Frame", {
        Name = "Box", BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, area and 88 or 34), LayoutOrder = 2, Parent = b.Inner,
    })
    Themed(holder, {BackgroundColor3 = "Elevated"})
    Corner(holder, 8)
    local st = AddStroke(holder, false, 1, 0.3)
    local box = New("TextBox", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, area and 8 or 0), Size = UDim2.new(1, -24, 1, area and -16 or 0),
        Font = Enum.Font.GothamMedium, TextSize = 13, Text = value, ClearTextOnFocus = false,
        PlaceholderText = tostring(cfg.Placeholder or "Type here…"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = area and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        MultiLine = area, TextWrapped = area, Parent = holder,
    })
    Themed(box, {TextColor3 = "Text", PlaceholderColor3 = "Muted"})

    box.Focused:Connect(function()
        Tween(st, {Color = Theme.Accent, Transparency = 0}, 0.2)
    end)
    box.FocusLost:Connect(function(enter)
        Tween(st, {Color = Theme.Stroke, Transparency = 0.3}, 0.2)
        local text = box.Text
        if cfg.Numeric then
            local n = tonumber(text)
            if n == nil then
                box.Text = value
                return
            end
            text = tostring(n)
            box.Text = text
        end
        if text ~= value then
            value = text
            Fire(cfg.Callback, value, enter)
        end
    end)
    if cfg.Live then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            if box:IsFocused() then
                value = box.Text
                Fire(cfg.Callback, value, false)
            end
        end)
    end

    function el:Set(v, silent)
        value = tostring(v == nil and "" or v)
        box.Text = value
        if not silent then Fire(cfg.Callback, value, false) end
    end
    function el:Get() return value end
    function el:Serialize() return value end
    function el:Deserialize(v) self:Set(v) end

    if cfg.CallOnInit == true then task.defer(Fire, cfg.Callback, value, false) end
    return el
end

------------------------------------------------------------------------
-- Dropdown
------------------------------------------------------------------------
function ContainerMethods:Dropdown(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 158})
    local el = NewElement(self, b, cfg, "Dropdown")

    local values = {}
    for _, v in ipairs(cfg.Values or {}) do values[#values + 1] = v end
    local multi = cfg.Multi == true
    local selected, single = {}, nil
    local ROW, MAXROWS = 28, 6

    local sel = New("TextButton", {
        Name = "Select", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(146, 28), Text = "", AutoButtonColor = false,
        BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Parent = b.Header,
    })
    Themed(sel, {BackgroundColor3 = "Elevated"})
    Corner(sel, 7)
    local sst = AddStroke(sel, false, 1, 0.3)
    local selLbl = Label({
        Text = "", TextSize = 12, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = sel,
    }, "Text")
    local chev = DrawIcon(sel, "chevron", 12, "SubText")
    chev.AnchorPoint = Vector2.new(1, 0.5)
    chev.Position = UDim2.new(1, -10, 0.5, 0)

    local clip = New("Frame", {
        Name = "Options", BackgroundTransparency = 1, ClipsDescendants = true, Visible = false,
        Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = b.Inner,
    })
    local listFrame = New("ScrollingFrame", {
        BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.2, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent, Parent = clip,
    })
    Themed(listFrame, {BackgroundColor3 = "Background", ScrollBarImageColor3 = "Accent"})
    Corner(listFrame, 8)
    AddStroke(listFrame, "Stroke", 1, 0.4)
    Pad(listFrame, 4)
    List(listFrame, 2)

    local panel = PanelToggle(clip, function()
        return math.max(math.min(#values, MAXROWS), 1) * (ROW + 2) + 8
    end)

    local painters = {}
    local function isSel(v)
        if multi then return selected[v] == true end
        return single == v
    end
    local function summary()
        if multi then
            local t = {}
            for _, v in ipairs(values) do
                if selected[v] then t[#t + 1] = tostring(v) end
            end
            return #t > 0 and table.concat(t, ", ") or tostring(cfg.Placeholder or "None")
        end
        return single ~= nil and tostring(single) or tostring(cfg.Placeholder or "Select…")
    end
    local function repaint()
        selLbl.Text = summary()
        for _, p in ipairs(painters) do p() end
    end

    local function getValue()
        if multi then
            local t = {}
            for _, v in ipairs(values) do
                if selected[v] then t[#t + 1] = v end
            end
            return t
        end
        return single
    end

    local function setOpen(open)
        panel:Set(open)
        Tween(chev, {Rotation = open and 180 or 0}, 0.25)
        Tween(sst, {Color = open and Theme.Accent or Theme.Stroke}, 0.2)
    end

    local function choose(v)
        if multi then
            selected[v] = (not selected[v]) or nil
            repaint()
            Fire(cfg.Callback, getValue())
        else
            single = v
            repaint()
            setOpen(false)
            Fire(cfg.Callback, v)
        end
    end

    local function build()
        for i = #painters, 1, -1 do painters[i] = nil end
        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for i, v in ipairs(values) do
            local opt = New("TextButton", {
                Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.SurfaceHover, BackgroundTransparency = 1,
                BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW), LayoutOrder = i, Parent = listFrame,
            })
            Corner(opt, 6)
            local lbl = Label({
                Text = tostring(v), TextSize = 13, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -40, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = opt,
            }, false)
            local chk = New("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -18, 0.5, 0), Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = opt,
            })
            Corner(chk, "full")
            local hover = false
            local function paint()
                local on = isSel(v)
                Tween(lbl, {TextColor3 = on and Theme.Accent or (hover and Theme.Text or Theme.SubText)}, 0.15)
                Tween(chk, {BackgroundTransparency = on and 0 or 1, BackgroundColor3 = Theme.Accent}, 0.15)
                Tween(opt, {BackgroundTransparency = on and 0.55 or (hover and 0.75 or 1)}, 0.15)
            end
            painters[#painters + 1] = paint
            opt.MouseEnter:Connect(function() hover = true paint() end)
            opt.MouseLeave:Connect(function() hover = false paint() end)
            opt.MouseButton1Click:Connect(function() choose(v) end)
            paint()
        end
    end

    local function apply(v)
        selected, single = {}, nil
        if multi then
            if type(v) == "table" then
                for _, item in ipairs(v) do selected[item] = true end
            elseif v ~= nil then
                selected[v] = true
            end
        else
            single = v
        end
    end

    apply(cfg.Default)
    build()
    repaint()
    el._maid:Give(OnTheme(repaint))

    sel.MouseButton1Click:Connect(function()
        if el.Locked then return end
        setOpen(not panel.Open)
    end)
    sel.MouseEnter:Connect(function() Tween(sel, {BackgroundColor3 = Theme.SurfaceHover}, 0.15) end)
    sel.MouseLeave:Connect(function() Tween(sel, {BackgroundColor3 = Theme.Elevated}, 0.15) end)

    function el:Set(v, silent)
        apply(v)
        repaint()
        if not silent then Fire(cfg.Callback, getValue()) end
    end
    function el:Get() return getValue() end
    function el:Refresh(newValues, keepSelection)
        values = {}
        for _, v in ipairs(newValues or {}) do values[#values + 1] = v end
        if not keepSelection then
            selected, single = {}, nil
        end
        build()
        repaint()
        if panel.Open then
            Tween(clip, {Size = UDim2.new(1, 0, 0, math.max(math.min(#values, MAXROWS), 1) * (ROW + 2) + 8)}, 0.25)
        end
    end
    function el:Open() setOpen(true) end
    function el:Close() setOpen(false) end
    function el:Serialize() return getValue() end
    function el:Deserialize(v) self:Set(v) end

    local hasDefault = (multi and type(cfg.Default) == "table" and #cfg.Default > 0) or (not multi and cfg.Default ~= nil)
    if hasDefault and cfg.CallOnInit ~= false then task.defer(Fire, cfg.Callback, getValue()) end
    return el
end

------------------------------------------------------------------------
-- Paragraph
------------------------------------------------------------------------
function ContainerMethods:Paragraph(cfg)
    cfg = cfg or {}
    local imgId = ResolveImage(cfg.Image)
    local hasLeft = imgId ~= nil or cfg.Icon ~= nil
    local b = BuildCard(self, cfg, {LeftWidth = hasLeft and 52 or 0})
    local el = NewElement(self, b, cfg, "Paragraph")

    if hasLeft then
        local pic = New("Frame", {
            Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Parent = b.Header,
        })
        Themed(pic, {BackgroundColor3 = "Elevated"})
        Corner(pic, 10)
        if imgId then
            New("ImageLabel", {
                BackgroundTransparency = 1, Image = imgId, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop,
                Parent = pic,
            })
        else
            local ic = Icon(pic, cfg.Icon, 20, "Accent")
            ic.AnchorPoint = Vector2.new(0.5, 0.5)
            ic.Position = UDim2.fromScale(0.5, 0.5)
        end
    end

    if type(cfg.Buttons) == "table" and #cfg.Buttons > 0 then
        local row = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2, Parent = b.Inner})
        List(row, 6, {FillDirection = Enum.FillDirection.Horizontal})
        for i, bc in ipairs(cfg.Buttons) do
            local w = math.max(70, #tostring(bc.Title or "Button") * 8 + 28)
            MakeButton(row, bc.Title or "Button", bc.Variant or "Secondary", bc.Callback, {
                Size = UDim2.fromOffset(w, 30), LayoutOrder = i,
            })
        end
    end
    return el
end

------------------------------------------------------------------------
-- Keybind
------------------------------------------------------------------------
function ContainerMethods:Keybind(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 112})
    local el = NewElement(self, b, cfg, "Keybind")

    local function toKey(v)
        if typeof(v) == "EnumItem" then return v end
        if type(v) == "string" and v ~= "" then
            local ok, k = pcall(function() return Enum.KeyCode[v] end)
            if ok and k then return k end
            ok, k = pcall(function() return Enum.UserInputType[v] end)
            if ok and k then return k end
        end
        return nil
    end

    local value = toKey(cfg.Default)
    local mode = cfg.Mode or "Press"
    local toggled, listening = false, false

    local box = New("TextButton", {
        Name = "Key", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(100, 26), Text = "", AutoButtonColor = false,
        BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Parent = b.Header,
    })
    Themed(box, {BackgroundColor3 = "Elevated"})
    Corner(box, 7)
    local bst = AddStroke(box, false, 1, 0.3)
    local lbl = Label({
        Text = "", TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Parent = box,
    }, false)

    local function render(instant)
        lbl.Text = listening and "..." or (value and value.Name or "None")
        Apply(lbl, {TextColor3 = listening and Theme.Accent or Theme.Text}, instant, 0.15)
        Apply(bst, {Color = listening and Theme.Accent or Theme.Stroke}, instant, 0.15)
    end
    render(true)
    el._maid:Give(OnTheme(function() render(true) end))

    box.MouseButton1Click:Connect(function()
        if el.Locked or listening then return end
        listening = true
        Lumina._listening = true
        render(false)
    end)

    el._maid:Give(UserInputService.InputBegan:Connect(function(input)
        if listening then
            local k = nil
            if input.UserInputType == Enum.UserInputType.Keyboard then
                k = input.KeyCode
                if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then
                    k = false
                elseif k == Enum.KeyCode.Unknown then
                    k = nil
                end
            elseif not cfg.KeyboardOnly and (input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3) then
                k = input.UserInputType
            end
            if k ~= nil then
                listening = false
                task.defer(function() Lumina._listening = false end)
                value = k or nil
                render(false)
                Fire(cfg.OnChange, value)
            end
            return
        end
        if not value or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == value or input.UserInputType == value then
            if mode == "Toggle" then
                toggled = not toggled
                Fire(cfg.Callback, toggled)
            elseif mode == "Hold" then
                Fire(cfg.Callback, true)
            else
                Fire(cfg.Callback, value)
            end
        end
    end))
    el._maid:Give(UserInputService.InputEnded:Connect(function(input)
        if mode == "Hold" and value and (input.KeyCode == value or input.UserInputType == value) then
            Fire(cfg.Callback, false)
        end
    end))

    function el:Set(v, silent)
        value = toKey(v)
        render(false)
        if not silent then Fire(cfg.OnChange, value) end
    end
    function el:Get() return value end
    function el:Serialize() return value and value.Name or "" end
    function el:Deserialize(v) self:Set(v) end
    return el
end

------------------------------------------------------------------------
-- Colorpicker
------------------------------------------------------------------------
function ContainerMethods:Colorpicker(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 64})
    local el = NewElement(self, b, cfg, "Colorpicker")

    local color = typeof(cfg.Default) == "Color3" and cfg.Default or Color3.fromRGB(178, 152, 255)
    local h, s, v = color:ToHSV()
    local svDrag, hueDrag = false, false
    local PANEL_H = 162

    local swatch = New("TextButton", {
        Name = "Swatch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(52, 24), Text = "", AutoButtonColor = false,
        BackgroundColor3 = color, BorderSizePixel = 0, Parent = b.Header,
    })
    Corner(swatch, 7)
    AddStroke(swatch, "Text", 1, 0.75)

    local clip = New("Frame", {
        Name = "Panel", BackgroundTransparency = 1, ClipsDescendants = true, Visible = false,
        Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = b.Inner,
    })
    local panelFrame = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, PANEL_H), Parent = clip})
    local panel = PanelToggle(clip, function() return PANEL_H end)

    local sv = New("Frame", {
        Name = "SV", Size = UDim2.new(1, -34, 0, 124), BackgroundColor3 = Color3.fromHSV(h, 1, 1),
        BorderSizePixel = 0, Parent = panelFrame,
    })
    Corner(sv, 8)
    local white = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sv})
    Corner(white, 8)
    New("UIGradient", {
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}),
        Parent = white,
    })
    local black = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv})
    Corner(black, 8)
    New("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}),
        Parent = black,
    })
    local cur = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1,
        ZIndex = 3, Parent = sv,
    })
    Corner(cur, "full")
    New("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 2, Parent = cur})

    local hue = New("Frame", {
        Name = "Hue", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(22, 124),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = panelFrame,
    })
    Corner(hue, 8)
    New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hue,
    })
    local hcur = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 6, 0, 6), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 3, Parent = hue,
    })
    Corner(hcur, 3)
    New("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5, Parent = hcur})

    local hexBox = New("TextBox", {
        Name = "Hex", Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12,
        Text = "", PlaceholderText = "#RRGGBB", ClearTextOnFocus = false, Parent = panelFrame,
    })
    Themed(hexBox, {BackgroundColor3 = "Elevated", TextColor3 = "Text", PlaceholderColor3 = "Muted"})
    Corner(hexBox, 7)

    local function toHex(c)
        return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    local function render()
        color = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = color
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        cur.Position = UDim2.fromScale(s, 1 - v)
        hcur.Position = UDim2.fromScale(0.5, h)
        hexBox.Text = toHex(color)
    end
    render()

    local function setScrolling(enabled)
        if self._scroller then self._scroller.ScrollingEnabled = enabled end
    end
    local function updateSV(input)
        local p = Pointer(input)
        local ap, as = sv.AbsolutePosition, sv.AbsoluteSize
        s = math.clamp((p.X - ap.X) / as.X, 0, 1)
        v = 1 - math.clamp((p.Y - ap.Y) / as.Y, 0, 1)
        render()
        Fire(cfg.Callback, color)
    end
    local function updateHue(input)
        local p = Pointer(input)
        local ap, as = hue.AbsolutePosition, hue.AbsoluteSize
        h = math.clamp((p.Y - ap.Y) / as.Y, 0, 0.999)
        render()
        Fire(cfg.Callback, color)
    end
    local function isPress(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end
    sv.InputBegan:Connect(function(input)
        if isPress(input) then svDrag = true setScrolling(false) updateSV(input) end
    end)
    hue.InputBegan:Connect(function(input)
        if isPress(input) then hueDrag = true setScrolling(false) updateHue(input) end
    end)
    el._maid:Give(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if svDrag then updateSV(input) elseif hueDrag then updateHue(input) end
        end
    end))
    el._maid:Give(UserInputService.InputEnded:Connect(function(input)
        if isPress(input) and (svDrag or hueDrag) then
            svDrag, hueDrag = false, false
            setScrolling(true)
        end
    end))

    hexBox.FocusLost:Connect(function()
        local r, g, bl = hexBox.Text:match("^#?(%x%x)(%x%x)(%x%x)$")
        if r then
            h, s, v = Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(bl, 16)):ToHSV()
            render()
            Fire(cfg.Callback, color)
        else
            render()
        end
    end)

    swatch.MouseButton1Click:Connect(function()
        if el.Locked then return end
        panel:Set(not panel.Open)
    end)

    function el:Set(c, silent)
        if type(c) == "string" then
            local r, g, bl = c:match("^#?(%x%x)(%x%x)(%x%x)$")
            if not r then return end
            c = Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(bl, 16))
        elseif type(c) == "table" then
            c = Color3.fromRGB(c[1] or 0, c[2] or 0, c[3] or 0)
        end
        if typeof(c) ~= "Color3" then return end
        h, s, v = c:ToHSV()
        render()
        if not silent then Fire(cfg.Callback, color) end
    end
    function el:Get() return color end
    function el:Serialize() return toHex(color) end
    function el:Deserialize(x) self:Set(x) end

    if cfg.CallOnInit ~= false then task.defer(Fire, cfg.Callback, color) end
    return el
end

------------------------------------------------------------------------
-- Code
------------------------------------------------------------------------
function ContainerMethods:Code(cfg)
    cfg = cfg or {}
    local src = tostring(cfg.Code or cfg.Text or "")

    local card = New("Frame", {
        Name = "Code", BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ClipsDescendants = true,
    })
    Themed(card, {BackgroundColor3 = "Background"})
    Corner(card, 10)
    AddStroke(card, "Stroke", 1, 0.35)
    List(card, 0)

    local head = New("Frame", {
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, Parent = card,
    })
    Themed(head, {BackgroundColor3 = "Surface"})
    local title = Label({
        Text = tostring(cfg.Title or "Lua"), Font = Enum.Font.GothamBold, TextSize = 12,
        Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -90, 1, 0), Parent = head,
    }, "SubText")
    MakeButton(head, "Copy", "Secondary", function()
        local clip = setclipboard or toclipboard or (syn and syn.write_clipboard)
        if clip then
            pcall(clip, src)
            Lumina:Notify({Title = "Copied", Content = "Code copied to your clipboard.", Type = "Success", Duration = 2})
        else
            Lumina:Notify({Title = "Clipboard unavailable", Content = "Your executor does not expose a clipboard function.", Type = "Warning", Duration = 3})
        end
    end, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(58, 24)})

    local lines = select(2, src:gsub("\n", "\n")) + 1
    local sc = New("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, math.clamp(lines * 16 + 22, 46, cfg.MaxHeight or 240)),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.XY, ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.XY, LayoutOrder = 2, Parent = card,
    })
    Themed(sc, {ScrollBarImageColor3 = "Accent"})
    Pad(sc, 10, 14)
    local txt = New("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
        Font = Enum.Font.Code, TextSize = 13, RichText = true, Text = Highlight(src),
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = sc,
    })
    Themed(txt, {TextColor3 = "Text"})

    local el = NewElement(self, {Card = card, Title = title}, cfg, "Code")
    function el:SetCode(text)
        src = tostring(text or "")
        txt.Text = Highlight(src)
    end
    function el:Get() return src end
    return el
end

------------------------------------------------------------------------
-- Divider / Space / Image / ProgressBar
------------------------------------------------------------------------
function ContainerMethods:Divider(cfg)
    cfg = cfg or {}
    local hasTitle = cfg.Title ~= nil and cfg.Title ~= ""
    local frame = New("Frame", {
        Name = "Divider", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasTitle and 28 or 10),
    })
    local title
    if hasTitle then
        title = Label({
            Text = string.upper(tostring(cfg.Title)), Font = Enum.Font.GothamBold, TextSize = 11,
            Size = UDim2.new(1, 0, 0, 14), Parent = frame,
        }, "Muted")
    end
    local line = New("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, hasTitle and 1 or 0.5),
        Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = frame,
    })
    if not hasTitle then line.AnchorPoint = Vector2.new(0, 0.5) end
    Themed(line, {BackgroundColor3 = "Stroke"})
    New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2),
            NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = line,
    })
    return NewElement(self, {Card = frame, Title = title}, cfg, "Divider")
end

function ContainerMethods:Space(cfg)
    cfg = cfg or {}
    local size = type(cfg) == "number" and cfg or cfg.Size or 12
    local frame = New("Frame", {Name = "Space", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, size)})
    return NewElement(self, {Card = frame}, type(cfg) == "table" and cfg or {}, "Space")
end

function ContainerMethods:Image(cfg)
    cfg = cfg or {}
    local frame = New("Frame", {
        Name = "Image", BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, cfg.Height or 140),
    })
    Themed(frame, {BackgroundColor3 = "Surface"})
    Corner(frame, cfg.Corner or 10)
    AddStroke(frame, "Stroke", 1, 0.4)
    local img = New("ImageLabel", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = ResolveImage(cfg.Image) or "",
        ScaleType = cfg.ScaleType or Enum.ScaleType.Crop, Parent = frame,
    })
    local caption
    if cfg.Title and cfg.Title ~= "" then
        local bar = New("Frame", {
            AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = frame,
        })
        caption = Label({
            Text = tostring(cfg.Title), Font = Enum.Font.GothamBold, TextSize = 12,
            Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Parent = bar,
        }, "Text")
    end
    local el = NewElement(self, {Card = frame, Title = caption}, cfg, "Image")
    function el:SetImage(id) img.Image = ResolveImage(id) or "" end
    return el
end

function ContainerMethods:ProgressBar(cfg)
    cfg = cfg or {}
    local b = BuildCard(self, cfg, {RightWidth = 56})
    local el = NewElement(self, b, cfg, "ProgressBar")
    local min, max = cfg.Min or 0, cfg.Max or 100
    local value = math.clamp(cfg.Default or cfg.Value or min, min, max)

    local pct = Label({
        Text = "0%", Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(48, 18),
        Parent = b.Header,
    }, "Accent")
    local track = New("Frame", {
        Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0, LayoutOrder = 2, Parent = b.Inner,
    })
    Themed(track, {BackgroundColor3 = "Elevated"})
    Corner(track, "full")
    local fill = New("Frame", {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track,
    })
    Corner(fill, "full")
    local grad = New("UIGradient", {Offset = Vector2.new(-1, 0), Parent = fill})
    local function paint()
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.AccentDark),
            ColorSequenceKeypoint.new(0.5, Theme.AccentSoft),
            ColorSequenceKeypoint.new(1, Theme.AccentDark),
        })
    end
    paint()
    el._maid:Give(OnTheme(paint))
    local shimmer = TweenService:Create(grad, TweenInfo.new(1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Offset = Vector2.new(1, 0)})
    shimmer:Play()
    el._maid:Give(function() shimmer:Cancel() end)

    local function render(instant)
        local r = (max > min) and (value - min) / (max - min) or 0
        Apply(fill, {Size = UDim2.fromScale(r, 1)}, instant, 0.45)
        pct.Text = type(cfg.Format) == "function" and tostring(cfg.Format(value)) or (math.floor(r * 100 + 0.5) .. "%")
    end
    render(true)

    function el:Set(v) value = math.clamp(tonumber(v) or value, min, max) render(false) end
    function el:Get() return value end
    return el
end

------------------------------------------------------------------------
-- Section (collapsible group), HStack / VStack, Group (deprecated)
------------------------------------------------------------------------
function ContainerMethods:Section(cfg)
    cfg = cfg or {}
    local frame = New("Frame", {
        Name = "Section_" .. tostring(cfg.Title or ""), BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    })
    List(frame, 8)

    local head = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28),
        LayoutOrder = 1, Parent = frame,
    })
    local mark = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 14),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = head,
    })
    Themed(mark, {BackgroundColor3 = "Accent"})
    Corner(mark, 2)
    local title = Label({
        Text = tostring(cfg.Title or "Section"), Font = Enum.Font.GothamBold, TextSize = 13,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -40, 1, 0), Parent = head,
    }, "Text")
    local chev = DrawIcon(head, "chevron", 14, "SubText")
    chev.AnchorPoint = Vector2.new(1, 0.5)
    chev.Position = UDim2.new(1, -6, 0.5, 0)

    local clip = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = frame})
    local content = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = clip,
    })
    List(content, 8)

    local opened = cfg.Opened ~= false
    local col = Collapsible(clip, content, opened)
    chev.Rotation = opened and 0 or -90
    head.MouseButton1Click:Connect(function()
        col:Set(not col.Opened)
        Tween(chev, {Rotation = col.Opened and 0 or -90}, 0.25)
    end)
    head.MouseEnter:Connect(function() Tween(mark, {Size = UDim2.fromOffset(3, 18)}, 0.15) end)
    head.MouseLeave:Connect(function() Tween(mark, {Size = UDim2.fromOffset(3, 14)}, 0.15) end)

    local section = NewContainer(self._window, content, self._scroller, {Frame = frame, Type = "Section"})
    function section:SetTitle(t) title.Text = tostring(t) end
    function section:Open() col:Set(true) Tween(chev, {Rotation = 0}, 0.25) end
    function section:Close() col:Set(false) Tween(chev, {Rotation = -90}, 0.25) end
    function section:Toggle() col:Set(not col.Opened) Tween(chev, {Rotation = col.Opened and 0 or -90}, 0.25) end
    function section:SetVisible(v) frame.Visible = v and true or false end
    function section:Destroy() frame:Destroy() end

    self:_attach(frame)
    return section
end

local function BuildStack(self, cfg, direction)
    cfg = cfg or {}
    local gap = cfg.Gap or 8
    local frame = New("Frame", {
        Name = direction == "H" and "HStack" or "VStack", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    })
    List(frame, gap, {
        FillDirection = direction == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    })
    self:_attach(frame)
    local stack = NewContainer(self._window, frame, self._scroller, {_stack = direction, _gap = gap, Frame = frame, Type = "Stack"})
    function stack:SetVisible(v) frame.Visible = v and true or false end
    function stack:Destroy() frame:Destroy() end
    return stack
end

function ContainerMethods:HStack(cfg) return BuildStack(self, cfg, "H") end
function ContainerMethods:VStack(cfg) return BuildStack(self, cfg, "V") end

function ContainerMethods:Group(cfg)
    if not Lumina._warnedGroup then
        Lumina._warnedGroup = true
        warn("[Lumina] Group is deprecated - use HStack / VStack instead.")
    end
    return BuildStack(self, cfg, "V")
end

-- Safety net: a failing element never takes the whole UI down. The error is printed, shown as a
-- notification, and a harmless stand-in is returned so the rest of your script keeps running.
local DummyElement = setmetatable({}, {
    __index = function(t) return function() return t end end,
})
for name, fn in pairs(ContainerMethods) do
    if type(fn) == "function" and name:sub(1, 1) ~= "_" then
        ContainerMethods[name] = function(self, ...)
            local ok, res = pcall(fn, self, ...)
            if ok then return res end
            warn("[Lumina] " .. name .. " failed: " .. tostring(res))
            Lumina:Notify({Title = name .. " failed", Content = tostring(res), Type = "Error", Duration = 0})
            return DummyElement
        end
    end
end

-- Tabs expose every container method plus their own (defined with the window below)
local TabMethods = {}
for k, fn in pairs(ContainerMethods) do TabMethods[k] = fn end
local TabMeta = {__index = TabMethods}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local WindowMethods = {}
WindowMethods.__index = WindowMethods

local CONFIG_DIR = "Lumina/Configs"

local function HasFS()
    return (writefile and readfile and isfile and makefolder and isfolder and listfiles) and true or false
end

function Lumina:CreateWindow(cfg)
    cfg = cfg or {}

    if cfg.Theme then Lumina:SetTheme(cfg.Theme, true) end
    if typeof(cfg.Accent) == "Color3" then Lumina:SetAccent(cfg.Accent, true) end

    local logoAsset = ResolveImage(cfg.Logo)

    -- Loader first (same theme as the UI), then the optional key screen, then the window
    if cfg.Loader ~= false then
        local lcfg = {Title = cfg.Title, Subtitle = cfg.Subtitle, Logo = logoAsset}
        if type(cfg.Loader) == "table" then lcfg = Merge(lcfg, cfg.Loader) end
        local ok, err = pcall(function() Lumina:Loader(lcfg) end)
        if not ok then
            warn("[Lumina] Loader failed: " .. tostring(err))
            local stuck = GetGui():FindFirstChild("LuminaLoader")
            if stuck then stuck:Destroy() end
        end
    end

    if cfg.KeySystem then
        if not Lumina:KeySystem(cfg.KeySystem) then return nil end
    end

    local gui = GetGui()
    local size = cfg.Size or UDim2.fromOffset(680, 460)
    local W, H = size.X.Offset, size.Y.Offset
    local view = gui.AbsoluteSize
    if view.X < 100 then view = Vector2.new(1280, 720) end
    local fit = math.min(1, (view.X - 30) / W, (view.Y - 30) / H)

    local self = setmetatable({
        Title = tostring(cfg.Title or "Lumina"), Tabs = {}, Visible = false,
        ToggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift,
        _maid = NewMaid(), _fit = fit, _mul = 1, _alpha = 0, _tok = 0, _seq = 0,
        _openEnabled = cfg.OpenButton ~= false, _pinnedCount = 0, _destroyed = false,
    }, WindowMethods)

    -- Holder (drag + scale target), glow, shadow and the main canvas ---------------------------
    local holder = New("Frame", {
        Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = size, BackgroundTransparency = 1, Visible = false, Parent = gui,
    })
    local scale = New("UIScale", {Scale = fit * 0.9, Parent = holder})
    local glow = New("ImageLabel", {
        Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 90, 1, 90), BackgroundTransparency = 1, Image = "rbxassetid://6014261993",
        ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450),
        ImageTransparency = 1, ZIndex = 0, Parent = holder,
    })
    Themed(glow, {ImageColor3 = "Accent"})
    local shadow = New("ImageLabel", {
        Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 50, 1, 50), BackgroundTransparency = 1, Image = "rbxassetid://6014261993",
        ImageColor3 = Color3.new(0, 0, 0), ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450), ImageTransparency = 1, ZIndex = 0, Parent = holder,
    })
    local main = New("CanvasGroup", {
        Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0, GroupTransparency = 1, Parent = holder,
    })
    Themed(main, {BackgroundColor3 = "Background"})
    Corner(main, 14)
    AddStroke(main, "Stroke", 1, 0.15)

    self._holder, self._scale, self._glow, self._shadow, self._main = holder, scale, glow, shadow, main

    local backdrop = New("Frame", {
        Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, Parent = main,
    })
    local bgGrad = New("UIGradient", {Rotation = 125, Parent = backdrop})
    local function paintBackdrop()
        bgGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Background:Lerp(Theme.Accent, 0.12)),
            ColorSequenceKeypoint.new(0.55, Theme.Background),
            ColorSequenceKeypoint.new(1, Theme.Background:Lerp(Theme.Elevated, 0.5)),
        })
    end
    paintBackdrop()
    self._maid:Give(OnTheme(paintBackdrop))

    -- Sidebar (user card, tabs, pinned tabs) --------------------------------------------------
    local sidebar = New("Frame", {
        Name = "Sidebar", Size = UDim2.new(0, 200, 1, 0), BackgroundColor3 = Theme.Sidebar,
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = main,
    })
    Themed(sidebar, {BackgroundColor3 = "Sidebar"})
    local sdiv = New("Frame", {
        Name = "Divider", Position = UDim2.fromOffset(200, 0), Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = main,
    })
    Themed(sdiv, {BackgroundColor3 = "Stroke"})

    local userCard = New("Frame", {
        Name = "User", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 56),
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = sidebar,
    })
    Themed(userCard, {BackgroundColor3 = "Surface"})
    Corner(userCard, 12)
    AddStroke(userCard, "Stroke", 1, 0.35)
    local avatar = New("ImageLabel", {
        Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0),
        Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", LocalPlayer.UserId),
        Parent = userCard,
    })
    Themed(avatar, {BackgroundColor3 = "Elevated"})
    Corner(avatar, "full")
    AddStroke(avatar, "Accent", 2, 0.1)
    local dot = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 44, 0.5, 14), Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Success, BorderSizePixel = 0, ZIndex = 2, Parent = userCard,
    })
    Themed(dot, {BackgroundColor3 = "Success"})
    Corner(dot, "full")
    AddStroke(dot, "Surface", 2, 0)
    Label({
        Text = LocalPlayer.DisplayName, Font = Enum.Font.GothamBold, TextSize = 13,
        Position = UDim2.fromOffset(56, 12), Size = UDim2.new(1, -64, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = userCard,
    }, "Text")
    Label({
        Text = "@" .. LocalPlayer.Name, TextSize = 11, Position = UDim2.fromOffset(56, 29),
        Size = UDim2.new(1, -64, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, Parent = userCard,
    }, "SubText")

    local tabList = New("ScrollingFrame", {
        Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 80),
        Size = UDim2.new(1, 0, 1, -80), ScrollBarThickness = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = sidebar,
    })
    Pad(tabList, 4, 10, 8, 10)
    List(tabList, 4)

    local pinned = New("Frame", {
        Name = "Pinned", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = sidebar,
    })
    Pad(pinned, 12, 10)
    List(pinned, 4)
    local pinLine = New("Frame", {
        Name = "PinLine", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 14, 1, 0), Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, Parent = sidebar,
    })
    Themed(pinLine, {BackgroundColor3 = "Stroke"})
    self._tabList, self._pinned, self._pinLine = tabList, pinned, pinLine

    -- Body: topbar + pages -----------------------------------------------------------------------
    local body = New("Frame", {
        Name = "Body", Position = UDim2.fromOffset(201, 0), Size = UDim2.new(1, -201, 1, 0),
        BackgroundTransparency = 1, Parent = main,
    })
    local topbar = New("Frame", {
        Name = "Topbar", Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = Theme.Topbar,
        BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = body,
    })
    Themed(topbar, {BackgroundColor3 = "Topbar"})
    local tline = New("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = topbar,
    })
    Themed(tline, {BackgroundColor3 = "Stroke"})

    local titleRow = New("Frame", {
        Name = "TitleRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 9),
        Size = UDim2.new(1, -120, 0, 22), Parent = topbar,
    })
    List(titleRow, 8, {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center})
    if logoAsset then
        local li = New("ImageLabel", {
            Name = "Logo", BackgroundTransparency = 1, Image = logoAsset, ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(22, 22), LayoutOrder = -1, Parent = titleRow,
        })
        Corner(li, 6)
    end
    local titleLbl = Label({
        Text = self.Title, Font = Enum.Font.GothamBold, TextSize = 16, Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 0, Parent = titleRow,
    }, "Text")
    local subLbl = Label({
        Text = tostring(cfg.Subtitle or ""), TextSize = 11, Position = UDim2.fromOffset(18, 32),
        Size = UDim2.new(1, -120, 0, 14), Parent = topbar,
    }, "SubText")
    self._titleRow, self._titleLbl, self._subLbl, self._tagSeq = titleRow, titleLbl, subLbl, 0

    local ctrl = New("Frame", {
        Name = "Controls", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(66, 28), BackgroundTransparency = 1, ZIndex = 10, Parent = topbar,
    })
    List(ctrl, 6, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right})
    local function ctrlButton(glyph, hoverKey, order, callback)
        local btn = New("TextButton", {
            Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Elevated, BackgroundTransparency = 1,
            BorderSizePixel = 0, Size = UDim2.fromOffset(28, 28), LayoutOrder = order, Parent = ctrl,
        })
        Themed(btn, {BackgroundColor3 = "Elevated"})
        Corner(btn, 8)
        local lbl = Label({
            Text = glyph, Font = Enum.Font.GothamBold, TextSize = (glyph == "×") and 22 or 14, TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1), Parent = btn,
        }, "SubText")
        btn.MouseEnter:Connect(function()
            Tween(btn, {BackgroundTransparency = 0}, 0.15)
            Tween(lbl, {TextColor3 = Theme[hoverKey]}, 0.15)
        end)
        btn.MouseLeave:Connect(function()
            Tween(btn, {BackgroundTransparency = 1}, 0.15)
            Tween(lbl, {TextColor3 = Theme.SubText}, 0.15)
        end)
        btn.MouseButton1Click:Connect(callback)
    end

    local pages = New("Frame", {
        Name = "Pages", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54),
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = body,
    })
    self._pages = pages

    -- Floating open button (shown while the window is hidden) --------------------------------
    local openBtn = New("TextButton", {
        Name = "LuminaOpen", Text = "★  " .. self.Title, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = Theme.Accent, AutoButtonColor = false, BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.05, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
        Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0,
        Visible = false, Parent = gui,
    })
    Themed(openBtn, {BackgroundColor3 = "Background", TextColor3 = "Accent"})
    Corner(openBtn, "full")
    AddStroke(openBtn, "Accent", 1, 0.45)
    Pad(openBtn, 0, 18)
    local openScale = New("UIScale", {Scale = 0.001, Parent = openBtn})
    self._openBtn, self._openScale = openBtn, openScale

    local downAt
    openBtn.MouseButton1Down:Connect(function() downAt = UserInputService:GetMouseLocation() end)
    openBtn.MouseButton1Click:Connect(function()
        if downAt and (UserInputService:GetMouseLocation() - downAt).Magnitude > 8 then return end
        self:Toggle(true)
    end)
    MakeDraggable(openBtn, openBtn, self._maid)

    -- Window controls ----------------------------------------------------------------------------
    ctrlButton("—", "Warning", 1, function()
        self:Toggle(false)
        Lumina:Notify({Title = "Interface hidden", Content = self:_reopenHint(), Duration = 3})
    end)
    ctrlButton("×", "Danger", 2, function()
        local function closeNow()
            Fire(cfg.OnClose)
            self:Destroy()
        end
        if cfg.ConfirmClose then
            local ok = pcall(function()
                self:Dialog({
                    Title = "Close the interface?",
                    Content = "This removes the window completely. Execute the script again to bring it back.",
                    Icon = "⚠",
                    Buttons = {
                        {Title = "Cancel"},
                        {Title = "Close UI", Variant = "Danger", Callback = closeNow},
                    },
                })
            end)
            if not ok then closeNow() end
        else
            closeNow()
        end
    end)

    MakeDraggable(topbar, holder, self._maid)
    MakeDraggable(userCard, holder, self._maid)

    self._maid:Give(UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if self.ToggleKey and input.KeyCode == self.ToggleKey and not Lumina._listening
            and not UserInputService:GetFocusedTextBox() then
            self:Toggle()
        end
    end))

    table.insert(Lumina.Windows, self)
    if cfg.GamesTab ~= false then self:_buildGames() end
    if cfg.SettingsTab ~= false then self:_buildSettings() end
    self:Toggle(true)
    return self
end

------------------------------------------------------------------------
-- Window methods
------------------------------------------------------------------------
function WindowMethods:_reopenHint()
    if self.ToggleKey then
        return "Press " .. self.ToggleKey.Name .. " to bring it back."
    end
    return "Use the floating button to bring it back."
end

function WindowMethods:_syncOpenButton()
    local show = (not self.Visible) and self._openEnabled and not self._destroyed
    local btn, sc = self._openBtn, self._openScale
    if show then
        btn.Visible = true
        Tween(sc, {Scale = 1}, 0.4, Enum.EasingStyle.Back)
    else
        Tween(sc, {Scale = 0.001}, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.22, function()
            if not ((not self.Visible) and self._openEnabled) then btn.Visible = false end
        end)
    end
end

function WindowMethods:Toggle(state)
    if self._destroyed then return end
    if state == nil then state = not self.Visible end
    state = state and true or false
    if state == self.Visible then return end
    self.Visible = state
    self._tok = self._tok + 1
    local tok = self._tok
    local s = self._fit * self._mul
    if state then
        self._holder.Visible = true
        Tween(self._scale, {Scale = s}, 0.45, Enum.EasingStyle.Back)
        Tween(self._main, {GroupTransparency = self._alpha}, 0.35)
        Tween(self._shadow, {ImageTransparency = 0.5}, 0.4)
        Tween(self._glow, {ImageTransparency = 0.86}, 0.4)
    else
        Tween(self._scale, {Scale = s * 0.9}, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        Tween(self._main, {GroupTransparency = 1}, 0.25)
        Tween(self._shadow, {ImageTransparency = 1}, 0.25)
        Tween(self._glow, {ImageTransparency = 1}, 0.25)
        task.delay(0.32, function()
            if self._tok == tok and not self.Visible then self._holder.Visible = false end
        end)
    end
    self:_syncOpenButton()
end

function WindowMethods:Show() self:Toggle(true) end
function WindowMethods:Hide() self:Toggle(false) end

function WindowMethods:SetToggleKey(key) self.ToggleKey = key end
function WindowMethods:SetTitle(text)
    self.Title = tostring(text)
    self._titleLbl.Text = self.Title
    self._openBtn.Text = "★  " .. self.Title
end
function WindowMethods:SetSubtitle(text) self._subLbl.Text = tostring(text) end

function WindowMethods:SetScale(mul)
    self._mul = math.clamp(tonumber(mul) or 1, 0.4, 2)
    if self.Visible then Tween(self._scale, {Scale = self._fit * self._mul}, 0.25) end
end

function WindowMethods:SetTransparency(alpha)
    self._alpha = math.clamp(tonumber(alpha) or 0, 0, 0.8)
    if self.Visible then Tween(self._main, {GroupTransparency = self._alpha}, 0.2) end
end

function WindowMethods:Notify(cfg) return Lumina:Notify(cfg) end
function WindowMethods:Dialog(cfg) return BuildModal(self._main, cfg, false) end
function WindowMethods:Popup(cfg) return BuildModal(GetGui(), cfg, true) end

function WindowMethods:Destroy()
    if self._destroyed then return end
    self._openEnabled = false
    pcall(function() self:Toggle(false) end)
    self._destroyed = true
    for i, w in ipairs(Lumina.Windows) do
        if w == self then
            table.remove(Lumina.Windows, i)
            break
        end
    end
    task.delay(0.45, function()
        pcall(function() self._maid:Clean() end)
        pcall(function() self._holder:Destroy() end)
        pcall(function() self._openBtn:Destroy() end)
    end)
end

------------------------------------------------------------------------
-- Tags
------------------------------------------------------------------------
function WindowMethods:Tag(cfg)
    cfg = cfg or {}
    local tag = {}
    local custom = typeof(cfg.Color) == "Color3" and cfg.Color or nil
    self._tagSeq = self._tagSeq + 1

    local pill = New("Frame", {
        Name = "Tag", Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.82, BorderSizePixel = 0,
        LayoutOrder = self._tagSeq, Parent = self._titleRow,
    })
    Corner(pill, "full")
    local st = AddStroke(pill, false, 1, 0.5)
    Pad(pill, 0, 9)
    local lbl = Label({
        Text = tostring(cfg.Title or "Tag"), Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, Parent = pill,
    }, false)

    local function paint()
        local c = custom or Theme.Accent
        pill.BackgroundColor3 = c
        lbl.TextColor3 = c
        st.Color = c
    end
    paint()
    local unhook = OnTheme(paint)
    self._maid:Give(unhook)

    function tag:SetTitle(t) lbl.Text = tostring(t) end
    function tag:SetColor(c) custom = c paint() end
    function tag:Destroy() unhook() pill:Destroy() end
    return tag
end

------------------------------------------------------------------------
-- Tab sections and tabs
------------------------------------------------------------------------
function WindowMethods:TabSection(cfg)
    cfg = cfg or {}
    local win = self
    self._seq = self._seq + 1

    local holder = New("Frame", {
        Name = "TabSection", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self._seq, Parent = self._tabList,
    })
    List(holder, 2)
    local head = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
        LayoutOrder = 1, Parent = holder,
    })
    Label({
        Text = string.upper(tostring(cfg.Title or "Section")), Font = Enum.Font.GothamBold, TextSize = 11,
        Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -30, 1, 0), Parent = head,
    }, "Muted")
    local chev = DrawIcon(head, "chevron", 14, "Muted")
    chev.AnchorPoint = Vector2.new(1, 0.5)
    chev.Position = UDim2.new(1, -6, 0.5, 0)
    local clip = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = holder})
    local content = New("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = clip,
    })
    List(content, 4)

    local opened = cfg.Opened ~= false
    local col = Collapsible(clip, content, opened)
    chev.Rotation = opened and 0 or -90
    head.MouseButton1Click:Connect(function()
        col:Set(not col.Opened)
        Tween(chev, {Rotation = col.Opened and 0 or -90}, 0.25)
    end)

    local section = {}
    function section:Tab(tabCfg) return win:_newTab(tabCfg or {}, content, false) end
    function section:Open() col:Set(true) Tween(chev, {Rotation = 0}, 0.25) end
    function section:Close() col:Set(false) Tween(chev, {Rotation = -90}, 0.25) end
    function section:Destroy() holder:Destroy() end
    return section
end

function WindowMethods:Tab(cfg)
    cfg = cfg or {}
    if cfg.Pinned then
        self._pinnedCount = self._pinnedCount + 1
        local n = self._pinnedCount
        local h = n * 36 + (n - 1) * 4 + 24
        self._pinned.Size = UDim2.new(1, 0, 0, h)
        self._tabList.Size = UDim2.new(1, 0, 1, -(80 + h))
        self._pinLine.Position = UDim2.new(0, 14, 1, -h)
        self._pinLine.Visible = true
        return self:_newTab(cfg, self._pinned, true)
    end
    return self:_newTab(cfg, self._tabList, false)
end

function WindowMethods:_newTab(cfg, listParent, pinned)
    local win = self
    self._seq = self._seq + 1
    local tab = setmetatable({
        _window = self, _order = 0, _active = false, Title = tostring(cfg.Title or "Tab"),
    }, TabMeta)

    local btn = New("TextButton", {
        Name = tab.Title, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, 36), LayoutOrder = self._seq, Parent = listParent,
    })
    Corner(btn, 9)
    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 0),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = btn,
    })
    Corner(bar, 2)
    local ic = Icon(btn, cfg.Icon, 18, false, Theme.SubText)
    if ic then
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, 13, 0.5, 0)
    end
    local icProp = (ic and ic:IsA("ImageLabel")) and "ImageColor3" or "TextColor3"
    local lbl = Label({
        Text = tab.Title, TextSize = 13, TextColor3 = Theme.SubText,
        Position = UDim2.fromOffset(ic and 40 or 16, 0), Size = UDim2.new(1, -(ic and 48 or 24), 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
    }, false)

    local function paint(instant)
        local on = tab._active
        Apply(btn, {BackgroundTransparency = on and 0 or 1, BackgroundColor3 = Theme.Surface}, instant, 0.25)
        Apply(bar, {Size = UDim2.fromOffset(3, on and 18 or 0), BackgroundColor3 = Theme.Accent}, instant, 0.3, Enum.EasingStyle.Back)
        Apply(lbl, {TextColor3 = on and Theme.Text or Theme.SubText}, instant, 0.2)
        if ic then Apply(ic, {[icProp] = on and Theme.Accent or Theme.SubText}, instant, 0.2) end
    end
    paint(true)
    tab._paint = paint
    tab._unhook = OnTheme(function() paint(true) end)
    self._maid:Give(tab._unhook)

    btn.MouseEnter:Connect(function()
        if not tab._active then Tween(btn, {BackgroundTransparency = 0.6}, 0.15) end
    end)
    btn.MouseLeave:Connect(function()
        if not tab._active then Tween(btn, {BackgroundTransparency = 1}, 0.15) end
    end)
    btn.MouseButton1Click:Connect(function()
        Ripple(btn)
        tab:Select()
    end)

    local page = New("CanvasGroup", {
        Name = "Page_" .. tab.Title, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        GroupTransparency = 1, Visible = false, Parent = self._pages,
    })
    local scroller = New("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = page,
    })
    Themed(scroller, {ScrollBarImageColor3 = "Accent"})
    Pad(scroller, 12, 16, 16, 16)
    List(scroller, 8)

    tab._btn, tab._page, tab._content, tab._scroller = btn, page, scroller, scroller
    table.insert(self.Tabs, tab)
    if not pinned and not self._current then tab:Select() end
    return tab
end

function TabMethods:_setActive(active)
    self._active = active
    self._paint(false)
    local pg = self._page
    if active then
        pg.Visible = true
        pg.Position = UDim2.fromOffset(0, 18)
        pg.GroupTransparency = 1
        Tween(pg, {Position = UDim2.fromOffset(0, 0), GroupTransparency = 0}, 0.4)
    else
        Tween(pg, {GroupTransparency = 1, Position = UDim2.fromOffset(0, -10)}, 0.18)
        task.delay(0.2, function()
            if not self._active and pg.Parent then pg.Visible = false end
        end)
    end
end

function TabMethods:Select()
    local win = self._window
    if win._current == self then return end
    local prev = win._current
    win._current = self
    if prev then prev:_setActive(false) end
    self:_setActive(true)
    win._subLbl.Text = self.Title
end

function TabMethods:SetTitle(text)
    self.Title = tostring(text)
    for _, child in ipairs(self._btn:GetChildren()) do
        if child:IsA("TextLabel") and child.Name ~= "Icon" then child.Text = self.Title end
    end
    if self._window._current == self then self._window._subLbl.Text = self.Title end
end

function TabMethods:Destroy()
    local win = self._window
    for i, t in ipairs(win.Tabs) do
        if t == self then
            table.remove(win.Tabs, i)
            break
        end
    end
    if self._unhook then self._unhook() end
    self._btn:Destroy()
    self._page:Destroy()
    if win._current == self then
        win._current = nil
        local nxt = win.Tabs[1]
        if nxt then nxt:Select() end
    end
end

function WindowMethods:SelectTab(tabOrIndex)
    local tab = type(tabOrIndex) == "number" and self.Tabs[tabOrIndex] or tabOrIndex
    if tab and tab.Select then tab:Select() end
end

------------------------------------------------------------------------
-- Configuration (save / load every element that has a Flag)
------------------------------------------------------------------------
function WindowMethods:SaveConfig(name)
    if not HasFS() then return false, "File system functions are unavailable in this environment." end
    name = (tostring(name or ""):gsub("[^%w%-_ ]", ""))
    if name == "" then return false, "Enter a config name first." end
    local data = {}
    for flag, el in pairs(Lumina.Flags) do
        if el.Serialize then
            local ok, val = pcall(el.Serialize, el)
            if ok then data[flag] = val end
        end
    end
    local ok, err = pcall(function()
        if not isfolder("Lumina") then makefolder("Lumina") end
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
    if not ok then return false, tostring(err) end
    return true
end

function WindowMethods:LoadConfig(name)
    if not HasFS() then return false, "File system functions are unavailable in this environment." end
    name = (tostring(name or ""):gsub("[^%w%-_ ]", ""))
    if name == "" then return false, "Enter a config name first." end
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    local ok, raw = pcall(function()
        if isfile(path) then return readfile(path) end
        return nil
    end)
    if not ok or not raw then return false, "Config not found." end
    local okd, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okd or type(data) ~= "table" then return false, "Config file is corrupted." end
    for flag, val in pairs(data) do
        local el = Lumina.Flags[flag]
        if el and el.Deserialize then pcall(el.Deserialize, el, val) end
    end
    return true
end

function WindowMethods:GetConfigs()
    local out = {}
    if not HasFS() then return out end
    pcall(function()
        if not isfolder(CONFIG_DIR) then return end
        for _, file in ipairs(listfiles(CONFIG_DIR)) do
            local n = tostring(file):match("([^/\\]+)%.json$")
            if n then out[#out + 1] = n end
        end
    end)
    table.sort(out)
    return out
end

------------------------------------------------------------------------
-- Games tab (search, favorites, teleport)
------------------------------------------------------------------------
local function EmptyState(container, text)
    local f = New("Frame", {Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52)})
    Label({
        Text = text, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Parent = f,
    }, "Muted")
    container:_attach(f)
    return f
end

local function BuildGameCard(win, container, info, painters)
    local card = New("Frame", {
        Name = "Game_" .. tostring(info.PlaceId), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 78), ClipsDescendants = true,
    })
    Themed(card, {BackgroundColor3 = "Surface"})
    Corner(card, 10)
    local stroke = AddStroke(card, "Stroke", 1, 0.4)

    local icon = New("ImageLabel", {
        Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = Theme.Elevated,
        BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop,
        Image = string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", tonumber(info.UniverseId) or 0),
        Parent = card,
    })
    Themed(icon, {BackgroundColor3 = "Elevated"})
    Corner(icon, 10)

    local actionsW = 132
    local textCol = New("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(78, 0),
        Size = UDim2.new(1, -(78 + actionsW + 18), 1, 0), Parent = card,
    })
    Label({
        Text = tostring(info.Name), Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.fromOffset(0, 13),
        Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, Parent = textCol,
    }, "Text")
    local up, down = tonumber(info.Up), tonumber(info.Down)
    local rating = "no votes"
    if up and down and up + down > 0 then
        rating = math.floor(up / (up + down) * 100 + 0.5) .. "% liked"
    end
    Label({
        Text = FormatCount(info.Players) .. " playing  ·  " .. rating, TextSize = 12,
        Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = textCol,
    }, "SubText")
    Label({
        Text = (info.Creator and ("by " .. tostring(info.Creator) .. "  ·  ") or "") .. "ID " .. tostring(info.PlaceId),
        TextSize = 11, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 14),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = textCol,
    }, "Muted")

    local actions = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(actionsW, 34),
        BackgroundTransparency = 1, Parent = card,
    })
    List(actions, 6, {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    })

    local star = New("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Size = UDim2.fromOffset(34, 34), LayoutOrder = 1, Parent = actions,
    })
    Themed(star, {BackgroundColor3 = "Elevated"})
    Corner(star, 9)
    local starLbl = Label({
        Text = "☆", Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Parent = star,
    }, false)
    local function paint(pop)
        local fav = Lumina:IsFavorite(info.PlaceId)
        starLbl.Text = fav and "★" or "☆"
        starLbl.TextColor3 = fav and Theme.Warning or Theme.SubText
        if pop then
            starLbl.TextSize = 27
            Tween(starLbl, {TextSize = 18}, 0.4, Enum.EasingStyle.Back)
        end
    end
    paint(false)
    painters[#painters + 1] = paint
    star.MouseButton1Click:Connect(function()
        local nowFav = Lumina:ToggleFavorite(info)
        Lumina:Notify({
            Title = nowFav and "Added to favorites" or "Removed from favorites", Content = tostring(info.Name),
            Type = nowFav and "Success" or "Info", Duration = 2,
        })
        paint(true)
    end)

    MakeButton(actions, "Teleport", "Primary", function()
        win:Dialog({
            Title = "Teleport to " .. tostring(info.Name) .. "?", Icon = "◎",
            Content = "You will leave your current game and join this experience.",
            Buttons = {
                {Title = "Cancel"},
                {Title = "Teleport", Variant = "Primary", Callback = function()
                    Lumina:TeleportToGame(info.PlaceId, info.Name)
                end},
            },
        })
    end, {Size = UDim2.fromOffset(86, 34), LayoutOrder = 2})

    card.MouseEnter:Connect(function()
        Tween(card, {BackgroundColor3 = Theme.SurfaceHover}, 0.18)
        Tween(stroke, {Color = Theme.Accent, Transparency = 0.55}, 0.18)
    end)
    card.MouseLeave:Connect(function()
        Tween(card, {BackgroundColor3 = Theme.Surface}, 0.18)
        Tween(stroke, {Color = Theme.Stroke, Transparency = 0.4}, 0.18)
    end)

    container:_attach(card)
    return card
end

function WindowMethods:_buildGames()
    local win = self
    local tab = self:Tab({Title = "Games", Icon = "◎", Pinned = true})
    self.GamesTab = tab

    local favFrames, resFrames, favPainters, resPainters = {}, {}, {}, {}
    local function clear(list)
        for i = #list, 1, -1 do
            list[i]:Destroy()
            list[i] = nil
        end
    end

    local searchSec = tab:Section({Title = "Find a Game"})
    local favSec = tab:Section({Title = "Favorites"})
    local resSec = tab:Section({Title = "Results"})

    local function renderFavs()
        clear(favFrames)
        for i = #favPainters, 1, -1 do favPainters[i] = nil end
        favSec._order = 0
        local favs = Lumina:GetFavorites()
        favSec:SetTitle("Favorites (" .. #favs .. ")")
        if #favs == 0 then
            favFrames[1] = EmptyState(favSec, "No favorites yet. Tap the ☆ on any game to save it here.")
        else
            for _, g in ipairs(favs) do
                favFrames[#favFrames + 1] = BuildGameCard(win, favSec, g, favPainters)
            end
        end
    end

    local function renderResults(list, emptyText)
        clear(resFrames)
        for i = #resPainters, 1, -1 do resPainters[i] = nil end
        resSec._order = 0
        resSec:SetTitle("Results (" .. #list .. ")")
        if #list == 0 then
            resFrames[1] = EmptyState(resSec, emptyText or "Search for a game above.")
        else
            for _, g in ipairs(list) do
                resFrames[#resFrames + 1] = BuildGameCard(win, resSec, g, resPainters)
            end
        end
    end

    local searching = false
    local searchInput
    local function runSearch()
        if searching then return end
        local q = tostring(searchInput:Get() or "")
        if q:match("^%s*$") then
            Lumina:Notify({Title = "Type something first", Content = "Enter a game name or ID to search.", Type = "Warning", Duration = 3})
            return
        end
        searching = true
        resSec:SetTitle("Results · searching…")
        local list, err = Lumina:SearchGames(q)
        searching = false
        if not list then
            renderResults({}, "Search failed.")
            Lumina:Notify({Title = "Search failed", Content = tostring(err), Type = "Error", Duration = 5})
            return
        end
        renderResults(list, "No games found for '" .. q .. "'.")
    end

    searchInput = searchSec:Input({
        Title = "Search", Desc = "Game name, or paste a Place / Universe ID.", Placeholder = "e.g. Retail Tycoon 2",
        Callback = function(text, enter)
            if enter then runSearch() end
        end,
    })
    local row = searchSec:HStack({Gap = 8})
    row:Button({Title = "Search", Variant = "Primary", Icon = false, Callback = runSearch})
    row:Button({Title = "Clear", Icon = false, Callback = function() renderResults({}) end})

    self._maid:Give(Lumina:OnFavoritesChanged(function()
        renderFavs()
        for _, p in ipairs(resPainters) do pcall(p, false) end
    end))
    renderFavs()
    renderResults({})
end

------------------------------------------------------------------------
-- Built-in Settings tab
------------------------------------------------------------------------
function WindowMethods:_buildSettings()
    local win = self
    local tab = self:Tab({Title = "Settings", Icon = "⚙", Pinned = true})
    self.SettingsTab = tab

    local ui = tab:Section({Title = "Interface"})
    ui:Keybind({
        Title = "Toggle UI Key", Desc = "Press this key to show or hide the interface.",
        Default = self.ToggleKey, KeyboardOnly = true,
        OnChange = function(key) win.ToggleKey = key end,
    })
    ui:Button({
        Title = "Hide UI", Desc = "Hides the window. Bring it back with the key above or the floating button.",
        Icon = "◎",
        Callback = function()
            win:Toggle(false)
            Lumina:Notify({Title = "Interface hidden", Content = win:_reopenHint(), Duration = 3})
        end,
    })
    ui:Toggle({
        Title = "Floating Button", Desc = "Show a draggable button while the UI is hidden. Handy on mobile.",
        Default = self._openEnabled, CallOnInit = false,
        Callback = function(v)
            win._openEnabled = v
            win:_syncOpenButton()
        end,
    })
    ui:Slider({
        Title = "UI Scale", Desc = "Make the whole window larger or smaller.",
        Min = 0.6, Max = 1.4, Step = 0.05, Default = 1, Suffix = "x", CallOnInit = false,
        Callback = function(v) win:SetScale(v) end,
    })
    ui:Slider({
        Title = "Window Transparency", Desc = "Fade the window to see the game behind it.",
        Min = 0, Max = 50, Step = 1, Default = 0, Suffix = "%", CallOnInit = false,
        Callback = function(v) win:SetTransparency(v / 100) end,
    })
    ui:Toggle({
        Title = "Notifications", Desc = "Allow pop-up notifications to appear.",
        Default = Lumina.NotificationsEnabled, CallOnInit = false,
        Callback = function(v) Lumina.NotificationsEnabled = v end,
    })

    local ap = tab:Section({Title = "Appearance"})
    local presetDD, accentPicker
    presetDD = ap:Dropdown({
        Title = "Theme Preset", Desc = "Switch between the built-in violet / navy palettes.",
        Values = Lumina:GetPresets(), Default = CurrentPreset, CallOnInit = false,
        Callback = function(v)
            Lumina:SetTheme(v)
            if accentPicker then accentPicker:Set(Theme.Accent, true) end
        end,
    })
    accentPicker = ap:Colorpicker({
        Title = "Accent Color", Desc = "Pick any accent colour - everything re-colours live.",
        Default = Theme.Accent, CallOnInit = false,
        Callback = function(c) Lumina:SetAccent(c, true) end,
    })
    ap:Button({
        Title = "Reset Theme", Desc = "Return to the default Violet Night palette.", Icon = "◉",
        Callback = function()
            Lumina:SetTheme("Violet Night")
            presetDD:Set("Violet Night", true)
            accentPicker:Set(Theme.Accent, true)
        end,
    })

    if HasFS() then
        local cf = tab:Section({Title = "Configuration", Opened = false})
        local nameInput = cf:Input({Title = "Config Name", Placeholder = "my-config"})
        local cfgDD
        local row = cf:HStack({Gap = 8})
        row:Button({
            Title = "Save", Variant = "Primary", Icon = false,
            Callback = function()
                local ok, err = win:SaveConfig(nameInput:Get())
                if ok then
                    Lumina:Notify({Title = "Config saved", Content = nameInput:Get(), Type = "Success"})
                    cfgDD:Refresh(win:GetConfigs(), true)
                else
                    Lumina:Notify({Title = "Could not save", Content = tostring(err), Type = "Error"})
                end
            end,
        })
        row:Button({
            Title = "Load", Icon = false,
            Callback = function()
                local ok, err = win:LoadConfig(nameInput:Get())
                if ok then
                    Lumina:Notify({Title = "Config loaded", Content = nameInput:Get(), Type = "Success"})
                else
                    Lumina:Notify({Title = "Could not load", Content = tostring(err), Type = "Error"})
                end
            end,
        })
        cfgDD = cf:Dropdown({
            Title = "Saved Configs", Values = win:GetConfigs(), Placeholder = "None",
            Callback = function(v) nameInput:Set(v or "", true) end,
        })
        cf:Button({
            Title = "Refresh List", Icon = "◉",
            Callback = function() cfgDD:Refresh(win:GetConfigs()) end,
        })
    end

    local dz = tab:Section({Title = "Danger Zone", Opened = false})
    local armed, unloadBtn = false, nil
    unloadBtn = dz:Button({
        Title = "Unload UI", Desc = "Completely removes the interface. Click twice to confirm.",
        Variant = "Danger", Icon = "×",
        Callback = function()
            if not armed then
                armed = true
                unloadBtn:SetTitle("Click again to confirm")
                task.delay(3, function()
                    armed = false
                    unloadBtn:SetTitle("Unload UI")
                end)
                return
            end
            Lumina:Unload()
        end,
    })

    tab:Paragraph({
        Title = "Lumina UI " .. Lumina.Version,
        Desc = "Light purple × deep navy interface toolkit.",
        Icon = "★",
    })
end

------------------------------------------------------------------------
-- Library-level API
------------------------------------------------------------------------
function Lumina:Unload()
    for i = #self.Windows, 1, -1 do
        local w = self.Windows[i]
        pcall(function() w:Destroy() end)
    end
    local gui = Gui
    Gui, NotifHolder = nil, nil
    task.delay(0.7, function()
        if gui then gui:Destroy() end
    end)
    Env.__LuminaUnload = nil
end

Env.__LuminaUnload = function() Lumina:Unload() end

return Lumina
