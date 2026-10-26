--[[
    Dev.DKHUB Dumper v3  (main_v3.lua | Roblox Studio, โหมด Edit)
    โครงสร้างผลลัพธ์ (แตกทุก zip ลงโฟลเดอร์เดียวกัน):
        workspace/AGENT.md                 คำอธิบายโครงสร้างให้ AI อ่าน (สร้างจากข้อมูลจริง)
        workspace/Remotes.txt              Remote / Bindable ทั้งหมด
        workspace/Services/<ชื่อ>.lua       ต้นไม้ + properties ของแต่ละ service (คอมเมนต์ล้วน)
        workspace/Scripts/<หมวด>/*.lua     สคริปต์ 1 ตัว = 1 ไฟล์ ไม่ซ้ำกัน (หมวด Monster / Area / General)
        workspace/EmptyScripts.txt         รายชื่อสคริปต์ที่ Source ว่าง
    แบ่ง zip ตามขนาดจริง แล้วส่งเข้า Discord Webhook ทีละก้อน (Roblox จำกัด body ~1MB)
    ไฟล์ที่เล็กกว่า MIN_BYTES จะไม่ถูกสร้าง (กันไฟล์ขยะขนาด 15B)
]]

local Http = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")

---------------- ตั้งค่า ----------------
local OWNER, REPO = "vita8it", "Dumper"
local CLASSES_URL = ("https://raw.githubusercontent.com/%s/%s/main/Utils/Classes.luau"):format(OWNER, REPO)

local ZIP_LIMIT = 700000   -- ขนาดข้อมูลรวมต่อ zip 1 ก้อน (รวมค่า header โดยประมาณ)
local FILE_LIMIT = 600000  -- ไฟล์เดี่ยวที่ใหญ่กว่านี้จะถูกแบ่งเป็น _1, _2 (ต้อง <= ZIP_LIMIT)
local MIN_BYTES = 16       -- ไฟล์ที่เล็กกว่านี้ (เช่น 15B) จะไม่ถูกใส่ใน zip

local SERVICES = {
    "ReplicatedStorage",
    "ReplicatedFirst",
    "Workspace",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPlayer",
    "StarterPack",
} -- ไม่มี Players (ใน Studio โหมด Edit ไม่มี LocalPlayer)

-- ใช้แปลเฉพาะชื่อที่แสดงใน UI/Log และชื่อไฟล์ใน Services/
-- ชื่อ Service จริงใน game:GetService() และใน Source ยังเป็นภาษาอังกฤษเหมือนเดิม
local SERVICE_LABELS = {
    ReplicatedStorage = "ที่เก็บข้อมูลร่วม",
    ReplicatedFirst = "เริ่มต้นร่วม",
    Workspace = "พื้นที่เกม",
    ServerScriptService = "สคริปต์เซิร์ฟเวอร์",
    ServerStorage = "ที่เก็บเซิร์ฟเวอร์",
    StarterGui = "ส่วนติดต่อผู้เล่น",
    StarterPlayer = "ผู้เล่นเริ่มต้น",
    StarterPack = "กระเป๋าเริ่มต้น",
}

local function serviceLabel(name)
    return SERVICE_LABELS[name] or name
end

-- ตัวกรอง
-- ExcludePlayerBranches / HideModelNodes ซ่อนเฉพาะ "ต้นไม้+properties"
-- Source ของ Script ยังถูกเก็บครบเสมอ
local FILTER = {
    ExcludePlayerBranches = true,
    HideModelNodes = true,
}

-- จัดหมวดสคริปต์ตามลำดับ (ตรงหมวดแรกก็หยุด สคริปต์ 1 ตัวอยู่ได้แค่ 1 หมวด)
local CATEGORIES = {
    {name = "Monster", patterns = {"monster", "monter", "enemy", "mob"}},
    {name = "Area", patterns = {"area", "พื้นที่", "zone", "region"}},
}
local DEFAULT_CATEGORY = "General"

---------------- UI ----------------
local function getParent()
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    local lp = game:GetService("Players").LocalPlayer
    return lp and lp:WaitForChild("PlayerGui")
end

local guiRoot = getParent()
local old = guiRoot:FindFirstChild("DKHUB_Dumper")
if old then old:Destroy() end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local gui = new("ScreenGui", {Name = "DKHUB_Dumper", ResetOnSpawn = false}, guiRoot)
local main = new("Frame", {
    Size = UDim2.fromOffset(380, 360), Position = UDim2.new(0.5, -190, 0.5, -180),
    BackgroundColor3 = Color3.fromRGB(20, 20, 28), BorderSizePixel = 0, Active = true,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, main)
new("UIStroke", {Color = Color3.fromRGB(110, 80, 255), Thickness = 1.5}, main)

local title = new("TextLabel", {
    Text = "Dev.DKHUB v3", Font = Enum.Font.GothamBold, TextSize = 22,
    TextColor3 = Color3.fromRGB(150, 120, 255), BackgroundTransparency = 1,
    Size = UDim2.new(1, -50, 0, 40), Position = UDim2.fromOffset(16, 6),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local connections = {} -- เก็บไว้ disconnect ตอนปิด GUI
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

-- ลากหน้าต่างได้
do
    local dragging, startPos, startInput
    connect(title.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startInput = true, main.Position, i.Position
        end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    connect(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local closeBtn = new("TextButton", {
    Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(200, 60, 60), Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -38, 0, 10),
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, closeBtn)

local status = new("TextLabel", {
    Text = "พร้อมใช้งาน", Font = Enum.Font.GothamMedium, TextSize = 15,
    TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
    Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 52),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local barBg = new("Frame", {
    Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 80),
    BackgroundColor3 = Color3.fromRGB(40, 40, 55), BorderSizePixel = 0,
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, barBg)
local bar = new("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(110, 80, 255), BorderSizePixel = 0,
}, barBg)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, bar)
local pct = new("TextLabel", {
    Text = "0%", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2,
}, barBg)

local logBox = new("TextLabel", {
    Text = "", Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(170, 230, 170),
    BackgroundColor3 = Color3.fromRGB(12, 12, 18), BorderSizePixel = 0,
    Size = UDim2.new(1, -32, 0, 130), Position = UDim2.fromOffset(16, 112),
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, logBox)
new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6)}, logBox)

local urlBox = new("TextBox", {
    Text = "", PlaceholderText = "ใส่ URL Webhook", ClearTextOnFocus = false,
    Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
    PlaceholderColor3 = Color3.fromRGB(130, 130, 150),
    BackgroundColor3 = Color3.fromRGB(40, 40, 55), BorderSizePixel = 0,
    Size = UDim2.new(1, -32, 0, 32), Position = UDim2.fromOffset(16, 254),
    TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, urlBox)
new("UIPadding", {PaddingLeft = UDim.new(0, 8)}, urlBox)

local startBtn = new("TextButton", {
    Text = "เริ่ม Dump", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(110, 80, 255), BorderSizePixel = 0,
    Size = UDim2.new(0.6, -20, 0, 36), Position = UDim2.fromOffset(16, 304),
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, startBtn)

local stopBtn = new("TextButton", {
    Text = "หยุด", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(70, 70, 90), BorderSizePixel = 0,
    Size = UDim2.new(0.4, -20, 0, 36), Position = UDim2.new(0.6, 4, 0, 304),
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, stopBtn)

local lines = {}
local function log(s)
    table.insert(lines, s)
    if #lines > 8 then table.remove(lines, 1) end
    logBox.Text = table.concat(lines, "\n")
end
local function progress(p, text)
    p = math.clamp(p, 0, 100)
    bar.Size = UDim2.fromScale(p / 100, 1)
    pct.Text = math.floor(p) .. "%"
    if text then status.Text = text end
end

local stopped = false
connect(closeBtn.MouseButton1Click, function()
    stopped = true
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    gui:Destroy()
end)
connect(stopBtn.MouseButton1Click, function() stopped = true end)

---------------- ZIP (store, ไม่บีบ) ----------------
local crcT = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if bit32.band(c, 1) == 1 then c = bit32.bxor(bit32.rshift(c, 1), 0xEDB88320)
        else c = bit32.rshift(c, 1) end
    end
    crcT[i] = c
end

local function crc32(s)
    local band, bxor, rshift, byte = bit32.band, bit32.bxor, bit32.rshift, string.byte
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bxor(crcT[band(bxor(c, byte(s, i)), 255)], rshift(c, 8))
        if i % 200000 == 0 then task.wait() end -- กัน script timeout กับข้อมูลก้อนใหญ่
    end
    return bxor(c, 0xFFFFFFFF)
end

local DOSDATE = 23873
local function makeZip(list)
    local out, cd, offset = {}, {}, 0
    for _, f in ipairs(list) do
        local name, data = f[1], f[2]
        local crc, size = crc32(data), #data
        local lh = string.pack("<I4I2I2I2I2I2I4I4I4I2I2",
            0x04034b50, 20, 0x0800, 0, 0, DOSDATE, crc, size, size, #name, 0) .. name
        table.insert(out, lh)
        table.insert(out, data)
        table.insert(cd, string.pack("<I4I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4",
            0x02014b50, 20, 20, 0x0800, 0, 0, DOSDATE, crc, size, size,
            #name, 0, 0, 0, 0, 0, offset) .. name)
        offset += #lh + size
    end
    local cdStr = table.concat(cd)
    table.insert(out, cdStr)
    table.insert(out, string.pack("<I4I2I2I2I2I4I4I2",
        0x06054b50, 0, 0, #list, #list, #cdStr, offset, 0))
    return table.concat(out)
end

---------------- ส่ง Webhook ----------------
local function sendPart(url, idx, total, zipData, note)
    local b = "----DKHUB" .. tostring(math.random(1e8, 9e8))
    local payload = Http:JSONEncode({
        content = ("Dev.DKHUB | %s | part %d/%d%s"):format(game.Name, idx, total, note and (" | " .. note) or ""),
    })
    local body = "--" .. b .. "\r\nContent-Disposition: form-data; name=\"payload_json\"\r\n"
        .. "Content-Type: application/json\r\n\r\n" .. payload .. "\r\n"
        .. "--" .. b .. "\r\nContent-Disposition: form-data; name=\"files[0]\"; "
        .. ("filename=\"dkhub_part%d_of_%d.zip\"\r\n"):format(idx, total)
        .. "Content-Type: application/zip\r\n\r\n" .. zipData .. "\r\n--" .. b .. "--\r\n"
    local lastErr = "unknown"
    for attempt = 1, 4 do
        local ok, res = pcall(function()
            return Http:RequestAsync({
                Url = url, Method = "POST",
                Headers = {["Content-Type"] = "multipart/form-data; boundary=" .. b},
                Body = body,
            })
        end)
        if ok and res.Success then return true end
        if not ok then
            lastErr = tostring(res)
            task.wait(2 * attempt)
        elseif res.StatusCode == 429 then
            local wait = 3
            local okj, j = pcall(function() return Http:JSONDecode(res.Body) end)
            if okj and type(j) == "table" and tonumber(j.retry_after) then wait = math.ceil(j.retry_after) + 1 end
            lastErr = "rate limit"
            task.wait(wait)
        else
            return false, "HTTP " .. res.StatusCode
        end
    end
    return false, lastErr
end

---------------- Classes (รายการ property จากรีโพของคุณ) ----------------
local Classes = {}
local function loadClasses()
    local ok, src = pcall(function() return Http:GetAsync(CLASSES_URL) end)
    if not ok then return false, "โหลด Classes ไม่ได้: " .. tostring(src) end
    local fn, err = loadstring(src)
    if not fn then return false, "loadstring ไม่ได้ (เปิด ServerScriptService.LoadStringEnabled): " .. tostring(err) end
    local ok2, res = pcall(fn)
    if ok2 and type(res) == "table" then Classes = res return true end
    return false, "Classes.luau ผิดรูปแบบ"
end

---------------- ตัวช่วย ----------------
local function clean(s) return (s:gsub('[<>:"/\\|?*%c]', "_")) end

local function lower(s) return tostring(s):lower() end

-- ชื่อ node ที่ถือว่าเป็นกิ่งของผู้เล่น (เช็คเฉพาะตัวเอง ส่งต่อให้ลูกผ่านพารามิเตอร์)
local function isPlayerNode(inst)
    if not FILTER.ExcludePlayerBranches then return false end
    local n = lower(inst.Name)
    return inst:IsA("Player") or n == "players" or n == "player"
        or n == "characters" or n == "character"
end

local function categoryFor(path)
    local p = lower(path):gsub("mobile", ""):gsub("mobility", "")
    for _, cat in ipairs(CATEGORIES) do
        for _, needle in ipairs(cat.patterns) do
            if p:find(lower(needle), 1, true) then return cat.name end
        end
    end
    return DEFAULT_CATEGORY
end

local function fileStem(path)
    local s = path:gsub("%[", "_"):gsub("%]", "_")
    s = s:gsub("[^%w%._%-]+", "_")
    s = s:gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    if #s > 150 then s = s:sub(-150) end
    if s == "" then s = "unnamed" end
    return s
end

local function fmt(v)
    local t = typeof(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "Instance" then return v:GetFullName()
    elseif t == "Color3" then return ("Color3(%.3f, %.3f, %.3f)"):format(v.R, v.G, v.B)
    elseif t == "UDim2" then return ("UDim2(%g, %g, %g, %g)"):format(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "CFrame" then return "CFrame(" .. table.concat({v:GetComponents()}, ", ") .. ")"
    elseif t == "Vector3" then return ("Vector3(%g, %g, %g)"):format(v.X, v.Y, v.Z)
    elseif t == "Vector2" then return ("Vector2(%g, %g)"):format(v.X, v.Y)
    end
    return tostring(v)
end

local function same(a, b)
    if a == b then return true end
    if typeof(a) == "Instance" or typeof(b) == "Instance" then return false end
    return tostring(a) == tostring(b)
end

local defaults = {} -- cache instance default ต่อ class (false = สร้างไม่ได้)
local function getDefault(className)
    local d = defaults[className]
    if d == nil then
        local ok, inst = pcall(Instance.new, className)
        d = ok and inst or false
        defaults[className] = d
    end
    return d
end

-- รวม property ของ class นั้น + class แม่ทุกชั้น (ไม่พึ่งว่า Classes.luau flatten มาแล้วหรือไม่)
local propCache = {}
local function propNamesFor(inst)
    local cn = inst.ClassName
    local cached = propCache[cn]
    if cached then return cached end
    local set, names = {}, {}
    for className, def in pairs(Classes) do
        if type(def) == "table" then
            local okIs, isA = pcall(inst.IsA, inst, className)
            if okIs and isA then
                for name, info in pairs(def) do
                    if type(info) == "table" and not info.ReadOnly
                        and name ~= "Name" and name ~= "Parent" and not set[name] then
                        set[name] = true
                        table.insert(names, name)
                    end
                end
            end
        end
    end
    table.sort(names)
    propCache[cn] = names
    return names
end

local function propLines(inst, prefix)
    local out = {}
    local names = propNamesFor(inst)
    if #names > 0 then
        local base = getDefault(inst.ClassName)
        for _, name in ipairs(names) do
            local ok, v = pcall(function() return inst[name] end)
            if ok and v ~= nil then
                local skip = false
                if base then
                    local okb, bv = pcall(function() return base[name] end)
                    if okb and same(v, bv) then skip = true end
                end
                if not skip then table.insert(out, prefix .. name .. " = " .. fmt(v)) end
            end
        end
    elseif inst:IsA("ValueBase") then
        local ok, v = pcall(function() return inst.Value end)
        if ok then table.insert(out, prefix .. "Value = " .. fmt(v)) end
    end
    local attrs = inst:GetAttributes()
    local an = {}
    for k in pairs(attrs) do table.insert(an, k) end
    table.sort(an)
    for _, k in ipairs(an) do table.insert(out, prefix .. "@" .. k .. " = " .. fmt(attrs[k])) end
    local tags = CS:GetTags(inst)
    if #tags > 0 then table.insert(out, prefix .. "Tags = " .. table.concat(tags, ",")) end
    return out
end

-- แบ่งข้อความเป็นก้อนไม่เกิน FILE_LIMIT (แบ่งตามบรรทัด บรรทัดที่ยาวเกินจะตัดตามไบต์)
local function chunkText(text)
    local chunks, buf, size = {}, {}, 0
    local function flush()
        if #buf > 0 then
            table.insert(chunks, table.concat(buf, "\n"))
            buf, size = {}, 0
        end
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if #line > FILE_LIMIT then
            flush()
            for i = 1, #line, FILE_LIMIT do
                table.insert(chunks, line:sub(i, i + FILE_LIMIT - 1))
            end
        else
            if size + #line + 1 > FILE_LIMIT then flush() end
            table.insert(buf, line)
            size += #line + 1
        end
    end
    flush()
    return chunks
end

---------------- Dump ----------------
local function run(url)
    stopped = false
    lines = {}
    progress(0, "กำลัง dump")

    local okC, errC = loadClasses()
    if okC then log("โหลด Classes จากรีโพสำเร็จ")
    else log(errC) log("ดัมป์แบบไม่มี properties (โครงสร้าง+สคริปต์ยังครบ)") end

    local svcs = {}
    for _, n in ipairs(SERVICES) do
        local ok, svc = pcall(game.GetService, game, n)
        if ok and svc then table.insert(svcs, {n, svc}) end
    end

    local total, done = 0, 0
    for _, s in ipairs(svcs) do total += #s[2]:GetDescendants() + 1 end
    total = math.max(total, 1)
    log("พบ instance ทั้งหมด " .. total)

    local tree = {}
    local svcTree = {}   -- [service] = {บรรทัดของต้นไม้}
    local scripts = {}   -- {path, class, body, cat}
    local remotes = {}
    local emptyList = {}
    local readOk, readFail = 0, 0

    local function walk(inst, prefix, isLast, parentHidden)
        if stopped then return end
        done += 1
        if done % 150 == 0 then
            progress(done / total * 40, "กำลัง dump : สแกนเกม")
            task.wait()
        end
        if inst:IsA("Terrain") or inst:IsA("Camera") then return end

        -- กิ่งผู้เล่น/Model: ซ่อนแค่ต้นไม้ ไม่ตัดการอ่านสคริปต์และ Remote
        local hidden = parentHidden or isPlayerNode(inst)
        local branch = isLast and "└── " or "├── "
        local childPrefix = prefix .. (isLast and "    " or "│   ")
        local hideNode = hidden or (FILTER.HideModelNodes and inst:IsA("Model"))
        if not hideNode then
            table.insert(tree, prefix .. branch .. inst.Name .. " [" .. inst.ClassName .. "]")
            for _, l in ipairs(propLines(inst, childPrefix .. "  · ")) do table.insert(tree, l) end
        end

        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
            or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            table.insert(remotes, inst:GetFullName() .. " [" .. inst.ClassName .. "]")
        end

        if inst:IsA("LuaSourceContainer") then
            local fullPath = inst:GetFullName()
            local ok, src = pcall(function() return inst.Source end)
            if not ok then
                readFail += 1
                log("อ่านไม่ได้: " .. inst.Name .. " | " .. tostring(src))
                table.insert(scripts, {
                    path = fullPath, class = inst.ClassName,
                    body = "-- อ่าน Source ไม่ได้: " .. tostring(src),
                    cat = categoryFor(fullPath),
                })
            elseif src == "" then
                table.insert(emptyList, fullPath .. " [" .. inst.ClassName .. "]")
            else
                readOk += 1
                table.insert(scripts, {
                    path = fullPath, class = inst.ClassName, body = src,
                    cat = categoryFor(fullPath),
                })
            end
        end

        local kids = inst:GetChildren()
        for i, c in ipairs(kids) do
            walk(c, childPrefix, i == #kids, hidden)
        end
    end

    for _, s in ipairs(svcs) do
        if stopped then break end
        log("สแกน " .. serviceLabel(s[1]) .. " (" .. s[1] .. ")")
        tree = {}
        walk(s[2], "", true, false)
        svcTree[s[1]] = tree
    end

    for _, d in pairs(defaults) do if d then d:Destroy() end end

    if stopped then
        progress(0, "หยุดแล้ว")
        log("ผู้ใช้สั่งหยุด")
        return
    end

    local empty = #emptyList
    log(("สคริปต์: อ่านได้ %d | ว่าง %d | พลาด %d"):format(readOk, empty, readFail))
    if readOk == 0 and (readFail > 0 or empty > 0) then
        log("!! อ่าน Source ไม่ได้ ให้รันใน Studio โหมด Edit")
    end

    ---------------- รวมไฟล์ ----------------
    local BASE = "workspace/"
    local entries = {}
    local tinySkipped = 0

    -- ไฟล์เล็กกว่า MIN_BYTES ไม่ถูกสร้าง
    local function addFile(name, data)
        if #data < MIN_BYTES then
            tinySkipped += 1
            return
        end
        table.insert(entries, {name, data})
    end
    -- ไฟล์ใหญ่เกิน FILE_LIMIT แบ่งเป็น name_1.ext, name_2.ext (ชิ้นส่วนไม่ถูกตัดทิ้งแม้เล็ก)
    local function addText(name, text)
        if #text <= FILE_LIMIT then
            addFile(name, text)
            return
        end
        local stem, ext = name:match("^(.*)(%.[^./]+)$")
        for i, chunk in ipairs(chunkText(text)) do
            table.insert(entries, {("%s_%d%s"):format(stem, i, ext), chunk})
        end
    end

    -- นับหมวดสำหรับ AGENT.md
    local catCount = {}
    for _, sc in ipairs(scripts) do catCount[sc.cat] = (catCount[sc.cat] or 0) + 1 end
    local catNames = {}
    for _, cat in ipairs(CATEGORIES) do table.insert(catNames, cat.name) end
    table.insert(catNames, DEFAULT_CATEGORY)

    -- AGENT.md (อธิบายตามโครงสร้างที่สร้างจริง) ใส่เป็นไฟล์แรก จะได้อยู่ zip ก้อนแรก
    local agent = {
        "# AGENT.md",
        "",
        "ชุดข้อมูลนี้ dump จากเกม `" .. game.Name .. "` ด้วย Dev.DKHUB Dumper v3",
        "ข้อมูลถูกแบ่งเป็นหลาย zip ให้แตกทุกก้อนลงโฟลเดอร์เดียวกัน",
        "",
        "## โครงสร้าง",
        "- `workspace/Services/<ชื่อ>.lua` ต้นไม้ `Name [ClassName]` ของแต่ละ service เป็นคอมเมนต์ (`-- `) ทั้งไฟล์ **ไม่มีโค้ดสคริปต์**",
        "  ใต้แต่ละ node คือ property ที่ต่างจาก default (`·`), Attributes (`@`) และ Tags",
        "  โหนด Model และกิ่ง Player/Character ถูกซ่อนจากต้นไม้ แต่สคริปต์ข้างในยังถูกเก็บ",
        "- `workspace/Scripts/<หมวด>/<path>.lua` สคริปต์ 1 ตัวต่อ 1 ไฟล์ ไม่ซ้ำกัน หัวไฟล์คือ `-- ===== Path : ... | Class : ... =====`",
        "  ชื่อไฟล์ได้จาก full path (จุดคงไว้ อักขระอื่นเป็น `_`) ตัวที่ชื่อชนกันจะมี `_2`, `_3` ต่อท้าย",
        "- `workspace/Remotes.txt` Remote/Bindable ทั้งหมด ใช้ตรวจชื่อก่อนเขียนโค้ดเรียกข้ามฝั่ง",
        "- `workspace/EmptyScripts.txt` สคริปต์ที่ Source ว่าง (ไม่มีไฟล์ใน Scripts/)",
        "- ไฟล์ใหญ่เกินจะถูกแบ่งเป็น `Name_1.ext`, `Name_2.ext`",
        "- ไฟล์ที่เล็กกว่า " .. MIN_BYTES .. " ไบต์ไม่ถูกสร้าง",
        "- ไฟล์ในชุดนี้อ่านเพื่อดูโค้ด ไม่ใช่รันตรงๆ",
        "",
        "## ชื่อไฟล์ใน Services/ (ชื่อไทย = service จริง)",
    }
    for _, s in ipairs(svcs) do
        table.insert(agent, ("- `%s.lua` = `%s`"):format(clean(serviceLabel(s[1])), s[1]))
    end
    table.insert(agent, "")
    table.insert(agent, "## หมวดใน Scripts/ (จัดตามคำในชื่อ path ตามลำดับ ตรงหมวดแรกก็หยุด)")
    for _, cat in ipairs(CATEGORIES) do
        table.insert(agent, ("- `%s` คำที่ใช้: %s"):format(cat.name, table.concat(cat.patterns, ", ")))
    end
    table.insert(agent, ("- `%s` ที่เหลือทั้งหมด"):format(DEFAULT_CATEGORY))
    table.insert(agent, "")
    table.insert(agent, "## กฎการเขียนโค้ด")
    table.insert(agent, "- ใช้ path จาก `-- Path :` อ้างอิง instance ไม่เดาจากชื่อไฟล์")
    table.insert(agent, "- ตรวจชื่อ Remote จาก `Remotes.txt` ก่อนเสมอ")
    table.insert(agent, "- แก้เฉพาะส่วนที่ขอ ไม่เปลี่ยนโครงสร้างที่ไม่เกี่ยวข้อง")
    table.insert(agent, "")
    table.insert(agent, "## สถิติ")
    table.insert(agent, "- instance ที่สแกน: " .. done)
    table.insert(agent, ("- สคริปต์: มี Source %d | ว่าง %d | อ่านไม่ได้ %d"):format(readOk, empty, readFail))
    for _, name in ipairs(catNames) do
        table.insert(agent, ("- Scripts/%s: %d ไฟล์"):format(name, catCount[name] or 0))
    end
    table.insert(agent, "- remotes: " .. #remotes)
    addText(BASE .. "AGENT.md", table.concat(agent, "\n"))

    if #remotes > 0 then addText(BASE .. "Remotes.txt", table.concat(remotes, "\n")) end
    if empty > 0 then addText(BASE .. "EmptyScripts.txt", table.concat(emptyList, "\n")) end

    for _, s in ipairs(svcs) do
        local name = s[1]
        local t = svcTree[name]
        if t and #t > 0 then
            local parts = {
                ("-- Dev.DKHUB | %s | service: %s"):format(serviceLabel(name), name),
                "",
                "-- ===== EXPLORER (models/players hidden) =====",
            }
            for _, l in ipairs(t) do table.insert(parts, "-- " .. l) end
            addText(BASE .. "Services/" .. clean(serviceLabel(name)) .. ".lua", table.concat(parts, "\n"))
        end
    end

    -- สคริปต์ 1 ตัว = 1 ไฟล์ ลงหมวดเดียว ไม่เขียนซ้ำ
    local usedNames = {}
    for _, sc in ipairs(scripts) do
        local stem = fileStem(sc.path)
        local key = (sc.cat .. "/" .. stem):lower()
        local n = (usedNames[key] or 0) + 1
        usedNames[key] = n
        local fname = n == 1 and stem or (stem .. "_" .. n)
        local block = ("-- ===== Path : %s | Class : %s =====\n%s"):format(sc.path, sc.class, sc.body)
        addText(BASE .. "Scripts/" .. sc.cat .. "/" .. fname .. ".lua", block)
    end
    scripts = nil

    if tinySkipped > 0 then log(("ข้ามไฟล์เล็กกว่า %d ไบต์ %d ไฟล์"):format(MIN_BYTES, tinySkipped)) end

    ---------------- แบ่ง zip ตามขนาด ----------------
    progress(40, "กำลัง dump : แบ่งไฟล์")
    local groups, cur, curSize = {}, {}, 0
    for _, f in ipairs(entries) do
        local cost = #f[2] + #f[1] * 2 + 120 -- ข้อมูล + ชื่อ (local+central header) + header
        if curSize + cost > ZIP_LIMIT and #cur > 0 then
            table.insert(groups, cur)
            cur, curSize = {}, 0
        end
        table.insert(cur, f)
        curSize += cost
    end
    if #cur > 0 then table.insert(groups, cur) end

    if #groups == 0 then
        progress(0, "ไม่มีข้อมูลให้ส่ง")
        log("ไม่พบไฟล์ที่จะ dump")
        return
    end

    local zips = {}
    for i, g in ipairs(groups) do
        if stopped then progress(0, "หยุดแล้ว") return end
        progress(40 + (i - 1) / #groups * 20, ("กำลัง dump : บีบ zip %d/%d"):format(i, #groups))
        local data = makeZip(g)
        table.insert(zips, {files = #g, data = data})
        log(("zip %d/%d : %d ไฟล์ | %d bytes"):format(i, #groups, #g, #data))
        task.wait()
    end
    groups, entries = nil, nil

    ---------------- ส่ง ----------------
    local failed = 0
    for i, z in ipairs(zips) do
        if stopped then progress(0, "หยุดแล้ว") return end
        progress(60 + (i - 1) / #zips * 40, ("กำลังส่ง Webhook %d/%d"):format(i, #zips))
        local note = ("%d ไฟล์%s"):format(z.files, i == 1 and (" | scripts " .. readOk) or "")
        local ok, err = sendPart(url, i, #zips, z.data, note)
        if ok then log(("ส่ง part %d/%d สำเร็จ"):format(i, #zips))
        else failed += 1 log(("part %d ล้มเหลว: %s"):format(i, tostring(err))) end
        task.wait(1)
    end

    progress(100, failed == 0 and "เสร็จแล้ว ✔" or ("เสร็จ (พลาด " .. failed .. " ก้อน)"))
end

local busy = false
connect(startBtn.MouseButton1Click, function()
    if busy then return end
    local url = urlBox.Text:gsub("%s", "")
    if not url:match("^https://[%w%.%-]+/api/webhooks/") then
        log("URL Webhook ไม่ถูกต้อง")
        return
    end
    busy = true
    startBtn.Text = "กำลังทำงาน..."
    local ok, err = pcall(run, url)
    if not ok then log("error: " .. tostring(err)) progress(0, "เกิดข้อผิดพลาด") end
    startBtn.Text = "เริ่ม Dump"
    busy = false
end)
