--[[
    Dev.DKHUB Dumper v2  (Roblox Studio, โหมด Edit)
    โครงสร้างผลลัพธ์ยึดตาม vita8it/Dumper:
        Explorer.txt   ต้นไม้ + properties (เฉพาะค่าที่ต่างจาก default)
        AGENT.md       คำอธิบายโครงสร้างสำหรับให้ AI อ่าน
        Remotes.txt    Remote / Bindable ทั้งหมด
        Scripts/       สคริปต์ทุกตัว แยกโฟลเดอร์ตาม path จริง
        Sources/       (ว่าง ไว้ใส่ไฟล์เพิ่มเอง)
    ส่งเข้า Discord Webhook เป็น zip หลายก้อน (Roblox จำกัด body ~1MB)
]]

local Http = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")

---------------- ตั้งค่า ----------------
local OWNER, REPO = "vita8it", "Dumper"
local CLASSES_URL = ("https://raw.githubusercontent.com/%s/%s/main/Utils/Classes.luau"):format(OWNER, REPO)
local LIMIT = 800000 -- ขนาดข้อมูลต่อ zip

local SERVICES = {
    "Workspace", "ReplicatedStorage", "ReplicatedFirst",
    "ServerScriptService", "ServerStorage", "StarterGui",
    "StarterPack", "StarterPlayer", "Lighting",
    "SoundService", "Teams",
} -- ไม่มี Players

---------------- UI ----------------
local function getParent()
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    local lp = game:GetService("Players").LocalPlayer
    return lp and lp:WaitForChild("PlayerGui")
end

local root = getParent()
local old = root:FindFirstChild("DKHUB_Dumper")
if old then old:Destroy() end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local gui = new("ScreenGui", {Name = "DKHUB_Dumper", ResetOnSpawn = false}, root)
local main = new("Frame", {
    Size = UDim2.fromOffset(380, 360), Position = UDim2.new(0.5, -190, 0.5, -180),
    BackgroundColor3 = Color3.fromRGB(20, 20, 28), BorderSizePixel = 0, Active = true,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, main)
new("UIStroke", {Color = Color3.fromRGB(110, 80, 255), Thickness = 1.5}, main)

local title = new("TextLabel", {
    Text = "Dev.DKHUB", Font = Enum.Font.GothamBold, TextSize = 22,
    TextColor3 = Color3.fromRGB(150, 120, 255), BackgroundTransparency = 1,
    Size = UDim2.new(1, -50, 0, 40), Position = UDim2.fromOffset(16, 6),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

-- ลากหน้าต่างได้
do
    local dragging, startPos, startInput
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startInput = true, main.Position, i.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
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
closeBtn.MouseButton1Click:Connect(function() stopped = true gui:Destroy() end)
stopBtn.MouseButton1Click:Connect(function() stopped = true end)

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
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bit32.bxor(crcT[bit32.band(bit32.bxor(c, string.byte(s, i)), 255)], bit32.rshift(c, 8))
    end
    return bit32.bxor(c, 0xFFFFFFFF)
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
        .. ("filename=\"workspace_part%d.zip\"\r\n"):format(idx)
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

---------------- Dump ----------------
local function clean(s) return (s:gsub('[<>:"/\\|?*%c]', "_")) end

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

local function propLines(inst, prefix)
    local def = Classes[inst.ClassName]
    local out = {}
    if def then
        local base = getDefault(inst.ClassName)
        local names = {}
        for name, info in pairs(def) do
            if not info.ReadOnly and name ~= "Name" and name ~= "Parent" then
                table.insert(names, name)
            end
        end
        table.sort(names)
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
    else
        local ok, v = pcall(function() return inst.Value end)
        if ok and inst:IsA("ValueBase") then table.insert(out, prefix .. "Value = " .. fmt(v)) end
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

local function splitText(name, ext, text, list)
    if #text <= LIMIT then
        table.insert(list, {name .. ext, text})
        return
    end
    local n, buf, size = 1, {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if size + #line + 1 > LIMIT then
            table.insert(list, {("%s_%d%s"):format(name, n, ext), table.concat(buf, "\n")})
            n += 1; buf, size = {}, 0
        end
        table.insert(buf, line); size += #line + 1
    end
    table.insert(list, {("%s_%d%s"):format(name, n, ext), table.concat(buf, "\n")})
end

local function run(url)
    stopped = false
    lines = {}
    progress(0, "กำลัง dump")

    local okC, errC = loadClasses()
    if okC then log("โหลด Classes จากรีโพสำเร็จ")
    else log(errC) log("ดัมป์แบบไม่มี properties (โครงสร้าง+สคริปต์ยังครบ)") end

    local tree, remotes, scripts, used = {}, {}, {}, {}
    local readOk, readFail, empty = 0, 0, 0

    local function uniquePath(p)
        if not used[p] then used[p] = 1 return p end
        used[p] += 1
        return (p:gsub("(%.lua)$", "_" .. used[p] .. "%1"))
    end

    local total, done = 0, 0
    for _, n in ipairs(SERVICES) do
        local ok, svc = pcall(function() return game:GetService(n) end)
        if ok then total += #svc:GetDescendants() + 1 end
    end
    total = math.max(total, 1)
    log("พบ instance ทั้งหมด " .. total)

    local function walk(inst, prefix, isLast, dir)
        if stopped then return end
        done += 1
        if done % 150 == 0 then
            progress(done / total * 40, "กำลัง dump : สแกนเกม")
            task.wait()
        end
        if inst:IsA("Terrain") or inst:IsA("Camera") then return end

        local branch = isLast and "└── " or "├── "
        local childPrefix = prefix .. (isLast and "    " or "│   ")
        table.insert(tree, prefix .. branch .. inst.Name .. " [" .. inst.ClassName .. "]")
        for _, l in ipairs(propLines(inst, childPrefix .. "  · ")) do table.insert(tree, l) end

        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
            or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            table.insert(remotes, inst:GetFullName() .. " [" .. inst.ClassName .. "]")
        end

        local myDir = dir .. "/" .. clean(inst.Name)
        if inst:IsA("LuaSourceContainer") then
            local ok, src = pcall(function() return inst.Source end)
            local body
            if not ok then
                readFail += 1
                log("อ่านไม่ได้: " .. inst.Name .. " | " .. tostring(src))
                body = "-- อ่าน Source ไม่ได้: " .. tostring(src)
            else
                if src == "" then empty += 1 else readOk += 1 end
                body = src
            end
            local p = uniquePath(myDir .. ".lua")
            scripts["Scripts/" .. p] = ("-- Path : %s\n-- Class : %s\n%s"):format(inst:GetFullName(), inst.ClassName, body)
        end

        local kids = inst:GetChildren()
        for i, c in ipairs(kids) do
            walk(c, childPrefix, i == #kids, myDir)
        end
    end

    local svcs = {}
    for _, n in ipairs(SERVICES) do
        local ok, svc = pcall(function() return game:GetService(n) end)
        if ok then table.insert(svcs, {n, svc}) end
    end
    for i, s in ipairs(svcs) do
        if stopped then break end
        log("สแกน " .. s[1])
        walk(s[2], "", i == #svcs, clean(s[1]))
    end

    for _, d in pairs(defaults) do if d then d:Destroy() end end

    if stopped then
        progress(0, "หยุดแล้ว")
        log("ผู้ใช้สั่งหยุด")
        return
    end

    log(("สคริปต์: อ่านได้ %d | ว่าง %d | พลาด %d"):format(readOk, empty, readFail))
    if readOk == 0 and (readFail > 0 or empty > 0) then
        log("!! อ่าน Source ไม่ได้ ให้รันใน Studio โหมด Edit")
    end

    ---------------- AGENT.md ----------------
    local agent = {
        "# AGENT.md",
        "",
        "ชุดข้อมูลนี้ dump จากเกม `" .. game.Name .. "` ด้วย Dev.DKHUB Dumper",
        "",
        "## โครงสร้าง",
        "- `Explorer.txt` ต้นไม้ของเกม `Name [ClassName]` ใต้แต่ละ node คือ property ที่ต่างจากค่า default (`·`), Attributes (`@`) และ Tags",
        "- `Remotes.txt` Remote/Bindable ทั้งหมด ใช้ตรวจชื่อก่อนเขียนโค้ดเรียกข้ามฝั่ง",
        "- `Scripts/` สคริปต์ทุกตัว path ตรงกับ Explorer แต่ละไฟล์ขึ้นต้นด้วย `-- Path :` และ `-- Class :`",
        "- `Sources/` โฟลเดอร์ว่าง ไว้ใส่ข้อมูลเพิ่ม",
        "",
        "## กฎการเขียนโค้ด",
        "- ใช้ path จาก `-- Path :` อ้างอิง instance ไม่ใช้ `script.Parent` ในไฟล์ที่รวมแล้ว",
        "- ตรวจชื่อ Remote จาก `Remotes.txt` ก่อนเสมอ",
        "- แก้เฉพาะส่วนที่ขอ ไม่เปลี่ยนโครงสร้างที่ไม่เกี่ยวข้อง",
        "",
        ("## สถิติ\n- instance: %d\n- สคริปต์: %d\n- remotes: %d"):format(done, readOk + empty + readFail, #remotes),
    }

    ---------------- รวมไฟล์ ----------------
    local list = {}
    local root = "workspace/"
    splitText(root .. "Explorer", ".txt", table.concat(tree, "\n"), list)
    splitText(root .. "Remotes", ".txt", table.concat(remotes, "\n"), list)
    table.insert(list, {root .. "AGENT.md", table.concat(agent, "\n")})
    table.insert(list, {root .. "Sources/.keep", ""})
    local sorted = {}
    for p in pairs(scripts) do table.insert(sorted, p) end
    table.sort(sorted)
    for _, p in ipairs(sorted) do
        local base, ext = p:match("^(.*)(%.lua)$")
        local tmp = {}
        splitText(root .. (base or p), ext or "", scripts[p], tmp)
        for _, f in ipairs(tmp) do table.insert(list, f) end
    end

    ---------------- zip ----------------
    progress(40, "กำลัง dump : บีบ zip")
    local groups, cur, curSize = {}, {}, 0
    for _, f in ipairs(list) do
        if curSize + #f[2] > LIMIT and #cur > 0 then
            table.insert(groups, cur); cur, curSize = {}, 0
        end
        table.insert(cur, f); curSize += #f[2]
    end
    if #cur > 0 then table.insert(groups, cur) end

    local zips = {}
    for i, g in ipairs(groups) do
        if stopped then progress(0, "หยุดแล้ว") return end
        zips[i] = makeZip(g)
        progress(40 + i / #groups * 20, ("กำลัง dump : บีบ zip %d/%d"):format(i, #groups))
        task.wait()
    end
    log(("สร้าง zip %d ก้อน (%d ไฟล์)"):format(#zips, #list))

    ---------------- ส่ง ----------------
    local failed = 0
    for i, z in ipairs(zips) do
        if stopped then progress(0, "หยุดแล้ว") return end
        progress(60 + (i - 1) / #zips * 40, ("กำลังส่ง Webhook %d/%d"):format(i, #zips))
        local ok, err = sendPart(url, i, #zips, z, i == 1 and ("scripts " .. readOk) or nil)
        if ok then log(("ส่ง part %d/%d สำเร็จ"):format(i, #zips))
        else failed += 1 log(("part %d ล้มเหลว: %s"):format(i, tostring(err))) end
        task.wait(1)
    end

    progress(100, failed == 0 and "เสร็จแล้ว ✔" or ("เสร็จ (พลาด " .. failed .. " ก้อน)"))
end

local busy = false
startBtn.MouseButton1Click:Connect(function()
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
