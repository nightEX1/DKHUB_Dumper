local Http = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local LIMIT = 800000 -- ขนาดต่อ zip (Roblox จำกัด body ~1MB)
local SERVICES = {
    "Workspace", "ReplicatedStorage", "ReplicatedFirst",
    "ServerScriptService", "ServerStorage", "StarterGui",
    "StarterPack", "StarterPlayer", "Lighting",
    "SoundService", "Teams",
}

---------------- UI ----------------
local old = CoreGui:FindFirstChild("DKHUB_Dumper")
if old then old:Destroy() end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local gui = new("ScreenGui", {Name = "DKHUB_Dumper", ResetOnSpawn = false}, CoreGui)
local main = new("Frame", {
    Size = UDim2.fromOffset(380, 330), Position = UDim2.new(0.5, -190, 0.5, -165),
    BackgroundColor3 = Color3.fromRGB(20, 20, 28), BorderSizePixel = 0, Active = true,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 12)}, main)
new("UIStroke", {Color = Color3.fromRGB(110, 80, 255), Thickness = 1.5}, main)

new("TextLabel", {
    Text = "Dev.DKHUB", Font = Enum.Font.GothamBold, TextSize = 22,
    TextColor3 = Color3.fromRGB(150, 120, 255), BackgroundTransparency = 1,
    Size = UDim2.new(1, -50, 0, 40), Position = UDim2.fromOffset(16, 6),
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local closeBtn = new("TextButton", {
    Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(200, 60, 60), Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -38, 0, 10),
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, closeBtn)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

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
    Size = UDim2.new(1, -32, 0, 110), Position = UDim2.fromOffset(16, 112),
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
    Size = UDim2.new(1, -32, 0, 32), Position = UDim2.fromOffset(16, 234),
    TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, urlBox)
new("UIPadding", {PaddingLeft = UDim.new(0, 8)}, urlBox)

local startBtn = new("TextButton", {
    Text = "เริ่ม Dump", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(110, 80, 255), BorderSizePixel = 0,
    Size = UDim2.new(1, -32, 0, 36), Position = UDim2.fromOffset(16, 278),
}, main)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, startBtn)

local lines = {}
local function log(s)
    table.insert(lines, s)
    if #lines > 7 then table.remove(lines, 1) end
    logBox.Text = table.concat(lines, "\n")
end
local function progress(p, text)
    p = math.clamp(p, 0, 100)
    bar.Size = UDim2.fromScale(p / 100, 1)
    pct.Text = math.floor(p) .. "%"
    if text then status.Text = text end
end

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
local function sendPart(url, idx, total, zipData)
    local b = "----DKHUB" .. tostring(math.random(1e8, 9e8))
    local payload = Http:JSONEncode({
        content = ("Dev.DKHUB | %s | part %d/%d"):format(game.Name, idx, total),
    })
    local body = "--" .. b .. "\r\nContent-Disposition: form-data; name=\"payload_json\"\r\n"
        .. "Content-Type: application/json\r\n\r\n" .. payload .. "\r\n"
        .. "--" .. b .. "\r\nContent-Disposition: form-data; name=\"files[0]\"; "
        .. ("filename=\"workspace_part%d.zip\"\r\n"):format(idx)
        .. "Content-Type: application/zip\r\n\r\n" .. zipData .. "\r\n--" .. b .. "--\r\n"
    for _ = 1, 3 do
        local ok, res = pcall(function()
            return Http:RequestAsync({
                Url = url, Method = "POST",
                Headers = {["Content-Type"] = "multipart/form-data; boundary=" .. b},
                Body = body,
            })
        end)
        if ok and res.Success then return true end
        if ok and res.StatusCode == 429 then task.wait(3)
        else return false, ok and ("HTTP " .. res.StatusCode) or tostring(res) end
    end
    return false, "rate limit"
end

---------------- Dump ----------------
local function clean(s) return (s:gsub('[<>:"/\\|?*]', "_")) end

local function run(url)
    lines = {}
    local files, tree, remotes, used = {}, {}, {}, {}

    local function uniquePath(p)
        if not used[p] then used[p] = 1 return p end
        used[p] += 1
        return (p:gsub("(%.lua)$", "_" .. used[p] .. "%1"))
    end
    local function info(inst)
        local e = {}
        if inst:IsA("BasePart") then
            table.insert(e, "pos=" .. tostring(inst.Position))
            table.insert(e, "size=" .. tostring(inst.Size))
            table.insert(e, "anchored=" .. tostring(inst.Anchored))
        end
        if inst:IsA("ValueBase") then table.insert(e, "value=" .. tostring(inst.Value)) end
        for k, v in pairs(inst:GetAttributes()) do table.insert(e, "@" .. k .. "=" .. tostring(v)) end
        local tags = CS:GetTags(inst)
        if #tags > 0 then table.insert(e, "tags=" .. table.concat(tags, ",")) end
        return table.concat(e, " ")
    end

    -- นับทั้งหมดก่อน เพื่อคำนวณ %
    progress(0, "กำลัง dump")
    local total, done = 0, 0
    for _, n in ipairs(SERVICES) do
        local ok, svc = pcall(function() return game:GetService(n) end)
        if ok then total += #svc:GetDescendants() + 1 end
    end
    log("พบ instance ทั้งหมด " .. total)

    local function walk(inst, depth, dir)
        done += 1
        if done % 150 == 0 then
            progress(done / total * 40, "กำลัง dump : สแกนเกม")
            task.wait()
        end
        if inst:IsA("Terrain") or inst:IsA("Camera") then return end
        table.insert(tree, string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "] " .. info(inst))
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
            or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            table.insert(remotes, inst:GetFullName() .. " [" .. inst.ClassName .. "]")
        end
        local childDir = dir .. "/" .. clean(inst.Name)
        if inst:IsA("LuaSourceContainer") then
            local ok, src = pcall(function() return inst.Source end)
            files[uniquePath(childDir .. ".lua")] = "-- " .. inst.ClassName .. "\n" .. (ok and src or "-- อ่าน Source ไม่ได้")
        end
        for _, c in ipairs(inst:GetChildren()) do walk(c, depth + 1, childDir) end
    end

    for _, n in ipairs(SERVICES) do
        local ok, svc = pcall(function() return game:GetService(n) end)
        if ok then
            log("สแกน " .. n)
            walk(svc, 0, clean(n))
        end
    end

    -- รวมเป็นรายการไฟล์
    local list, scripts = {}, 0
    for p, c in pairs(files) do table.insert(list, {"workspace/" .. p, c}) scripts += 1 end
    log("สคริปต์ " .. scripts .. " ไฟล์ | remotes " .. #remotes)

    local function addText(name, text)
        if #text <= LIMIT then
            table.insert(list, {"workspace/" .. name .. ".txt", text})
            return
        end
        local n, buf = 1, {}
        local size = 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if size + #line + 1 > LIMIT then
                table.insert(list, {("workspace/%s_%d.txt"):format(name, n), table.concat(buf, "\n")})
                n += 1; buf, size = {}, 0
            end
            table.insert(buf, line); size += #line + 1
        end
        table.insert(list, {("workspace/%s_%d.txt"):format(name, n), table.concat(buf, "\n")})
    end
    addText("_tree", table.concat(tree, "\n"))
    addText("_remotes", table.concat(remotes, "\n"))

    -- แบ่งเป็นกลุ่ม ≤ LIMIT
    progress(40, "กำลัง dump : บีบ zip")
    local groups, cur, curSize = {}, {}, 0
    for _, f in ipairs(list) do
        if #f[2] > LIMIT then
            log("ข้าม (ใหญ่เกิน): " .. f[1])
        else
            if curSize + #f[2] > LIMIT and #cur > 0 then
                table.insert(groups, cur); cur, curSize = {}, 0
            end
            table.insert(cur, f); curSize += #f[2]
        end
    end
    if #cur > 0 then table.insert(groups, cur) end

    local zips = {}
    for i, g in ipairs(groups) do
        zips[i] = makeZip(g)
        progress(40 + i / #groups * 20, "กำลัง dump : บีบ zip " .. i .. "/" .. #groups)
        task.wait()
    end
    log("สร้าง zip " .. #zips .. " ก้อน")

    -- ส่ง
    local failed = 0
    for i, z in ipairs(zips) do
        progress(60 + (i - 1) / #zips * 40, ("กำลังส่ง Webhook %d/%d"):format(i, #zips))
        local ok, err = sendPart(url, i, #zips, z)
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
    if not url:match("^https://[%w%.]*discord%.com/api/webhooks/") then
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