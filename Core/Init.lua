--===========================================================================
-- EzWoW - Druid Forms
-- Core/Init.lua : Namespace, EzWoW Style Palette, Helpers & SavedVariables
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, tostring, pcall = type, pairs, tostring, pcall

_G.EzWoW_DruidForms = ns

ns.ADDON_NAME = ADDON_NAME or "EzWoW-DruidForms"
ns.TITLE = "EzWoW - Druid Forms"
ns.MEDIA_PATH = "Interface\\AddOns\\EzWoW-DruidForms\\Media\\"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"
ns.BUTTON_NAME = "EzWoWDruidFormsButton"

-----------------------------------------------------------------------------
-- EzWoW Style v1.0 Palette (Brand Accent: Druid Orange #F59A4A)
-----------------------------------------------------------------------------
ns.Style = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.97 },
    bgSecondary = { 0.114, 0.157, 0.192, 0.96 },
    bgInput     = { 0.047, 0.067, 0.086, 0.96 },
    bgHover     = { 0.160, 0.210, 0.260, 1.00 },
    bgAccent    = { 0.230, 0.150, 0.080, 0.96 },
    bgAccentHot = { 0.300, 0.190, 0.100, 1.00 },
    border      = { 0.204, 0.298, 0.357, 1.00 },
    textBody    = { 0.929, 0.957, 0.969, 1.00 },
    textMuted   = { 0.655, 0.725, 0.773, 1.00 },
    accent      = { 0.961, 0.604, 0.290, 1.00 }, -- #F59A4A
    accentHex   = "F59A4A",
    warning     = { 0.906, 0.486, 0.439, 1.00 },
    disabled    = { 0.388, 0.447, 0.482, 1.00 },
}

ns.DEFAULTS = {
    language     = "auto",
    combatForm   = "bear",   -- "bear" | "cat" | "caster" | "moonkin"
    useAquatic   = true,
    useTravel    = true,
    indoorCat    = true,
    useModifiers = true,
    showButton   = true,
    buttonSize   = 40,
    buttonPos    = nil,
}

function ns.IsSecret(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret and true or false
end

function ns.InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- Protected changes (macro text, binding, button position) wait until combat ends.
local afterCombat = {}
function ns.RunAfterCombat(key, fn)
    if not ns.InCombat() then
        fn()
        return
    end
    afterCombat[key] = fn
end

function ns.Print(msg)
    print("|cff" .. ns.Style.accentHex .. "EzWoW - Druid Forms:|r " .. tostring(msg or ""))
end

function ns.GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getter) == "function" then
        local ok, ver = pcall(getter, ns.ADDON_NAME, "Version")
        if ok and type(ver) == "string" and ver ~= "" and not ver:find("^@") then
            return ver
        end
    end
    return ""
end

function ns.IsDruid()
    local ok, _, classFile = pcall(UnitClass, "player")
    return ok and classFile == "DRUID"
end

function ns.FitText(fs, text, maxWidth, baseSize, minSize)
    if not fs then return end
    text = text or ""
    fs:SetWordWrap(false)
    if fs.SetTextScale then fs:SetTextScale(1) end
    local font, rawSize, flags = fs:GetFont()
    if not font then
        fs:SetText(text)
        return
    end
    local function applySize(size)
        if fs.SetTextScale and rawSize and rawSize > 0 then
            fs:SetTextScale(size / rawSize)
        else
            fs:SetFont(font, size, flags)
        end
    end
    applySize(baseSize)
    fs:SetText(text)
    local size = baseSize
    while fs:GetStringWidth() > maxWidth and size > minSize do
        size = size - 0.5
        applySize(size)
    end
    if fs:GetStringWidth() > maxWidth then
        local original = text
        while #text > 0 and fs:GetStringWidth() > maxWidth do
            local cut = #text
            while cut > 1 and string.byte(text, cut) >= 128 and string.byte(text, cut) < 192 do
                cut = cut - 1
            end
            text = text:sub(1, cut - 1)
            fs:SetText(text .. "...")
            if text == original then break end
        end
    end
end

function ns:InitDB()
    if type(_G.EzWoW_DruidFormsDB) ~= "table" then _G.EzWoW_DruidFormsDB = {} end
    local db = _G.EzWoW_DruidFormsDB
    for key, value in pairs(self.DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    db.buttonSize = math.max(24, math.min(64, tonumber(db.buttonSize) or 40))
    self.db = db
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ns.ADDON_NAME then ns:InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns:InitDB() end
        if ns.Start then ns.Start() end
        if ns.RegisterBlizzardOptions then ns:RegisterBlizzardOptions() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for key, fn in pairs(afterCombat) do
            afterCombat[key] = nil
            pcall(fn)
        end
    end
end)
