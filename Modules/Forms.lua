--===========================================================================
-- EzWoW - Druid Forms
-- Modules/Forms.lua : Learned forms, the one-key macro, the button & key binding
--===========================================================================
-- The choice happens inside the game's macro conditions ([swimming], [outdoors],
-- [combat], [form:n], [mod:shift] ...), so it also works in combat, where an
-- addon may not change what a secure button does.
local _, ns = ...
local type, ipairs, pairs, pcall, tostring = type, ipairs, pairs, pcall, tostring

ns.forms = {}       -- kind -> { index, name, icon, spellID }
local button, keyButton
local iconOnUpdate  -- the visible button's icon prediction (runs only while it is shown)

local CASTER_ICON = "Interface\\Icons\\ClassIcon_Druid"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Spell IDs of the classic forms, plus words of the localized names (checked when the
-- IDs differ on this realm). Order matters: bear is matched before the others.
local KINDS = {
    { key = "bear", ids = { [5487] = true, [9634] = true },
      words = { "곰", "bear", "bär", "ours", "oso", "медвед", "熊" } },
    { key = "aquatic", ids = { [1066] = true },
      words = { "수중", "aquatic", "wasser", "aquatique", "acuática", "водн", "水栖", "水棲" } },
    { key = "cat", ids = { [768] = true },
      words = { "표범", "cat", "katze", "félin", "felina", "кош", "猎豹", "獵豹" } },
    { key = "travel", ids = { [783] = true },
      words = { "여행", "치타", "날쌘", "travel", "reise", "voyage", "viaje", "поход", "旅行" } },
    { key = "moonkin", ids = { [24858] = true },
      words = { "달빛야수", "moonkin", "mondkin", "sélénien", "lechúcico", "лунного", "枭兽", "梟獸" } },
}

local function spellName(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

local function classify(spellID, name)
    for _, kind in ipairs(KINDS) do
        if kind.ids[spellID] then return kind.key end
    end
    local lower = (name or ""):lower()
    for _, kind in ipairs(KINDS) do
        for _, word in ipairs(kind.words) do
            if lower:find(word, 1, true) then return kind.key end
        end
    end
    return nil
end

-- Reads the stance bar (only learned forms are on it).
function ns.ScanForms()
    wipe(ns.forms)
    if type(GetNumShapeshiftForms) ~= "function" then return end
    local okCount, count = pcall(GetNumShapeshiftForms)
    count = okCount and tonumber(count) or 0
    for index = 1, count do
        local ok, icon, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
        if ok and type(spellID) == "number" then
            local name = spellName(spellID)
            local kind = name and classify(spellID, name)
            if kind and not ns.forms[kind] then
                ns.forms[kind] = { index = index, name = name, icon = icon, spellID = spellID }
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Macro
-----------------------------------------------------------------------------
-- The form the combat press goes to ("caster" = no form).
function ns.CombatKind()
    local kind = ns.db.combatForm
    if kind ~= "caster" and not ns.forms[kind] then
        kind = ns.forms.bear and "bear" or (ns.forms.cat and "cat" or "caster")
    end
    return kind
end

-- Out of combat: the form for the current place, or nil to stay as you are.
local function placeKinds()
    local f, db = ns.forms, ns.db
    local outdoor = (db.useTravel and f.travel and "travel") or (f.cat and "cat") or (f.bear and "bear")
    local indoor = db.indoorCat and ((f.cat and "cat") or (f.bear and "bear")) or nil
    local water = (db.useAquatic and f.aquatic and "aquatic") or outdoor
    return water, outdoor, indoor
end

function ns.BuildMacro()
    local f, db = ns.forms, ns.db
    local lines = {}
    local function add(line) lines[#lines + 1] = line end

    if db.useModifiers then
        add("/cancelform [mod:alt]")
        add("/stopmacro [mod:alt]")
        local guard, cast = {}, {}
        if f.bear then
            guard[#guard + 1] = "[mod:shift,form:" .. f.bear.index .. "]"
            cast[#cast + 1] = "[mod:shift] " .. f.bear.name
        end
        if f.cat then
            guard[#guard + 1] = "[mod:ctrl,form:" .. f.cat.index .. "]"
            cast[#cast + 1] = "[mod:ctrl] " .. f.cat.name
        end
        -- already in that form: stay (a second cast would leave it)
        if #guard > 0 then add("/stopmacro " .. table.concat(guard)) end
        if #cast > 0 then add("/cast " .. table.concat(cast, "; ")) end
        add("/stopmacro [mod:shift][mod:ctrl]")
    end

    -- in combat while swimming: aquatic form (already in it: stay)
    if db.useAquatic and f.aquatic then
        add("/stopmacro [combat,swimming,form:" .. f.aquatic.index .. "]")
        add("/cast [combat,swimming] " .. f.aquatic.name)
        add("/stopmacro [combat,swimming]")
    end

    local combatKind = ns.CombatKind()
    if combatKind == "caster" then
        add("/cancelform [combat]")
    else
        local form = f[combatKind]
        add("/stopmacro [combat,form:" .. form.index .. "]")
        add("/cast [combat] " .. form.name)
    end
    add("/stopmacro [combat]")

    -- out of combat a second press in the same form turns it off (the game's own toggle)
    local water, outdoor, indoor = placeKinds()
    local cast = {}
    if water then cast[#cast + 1] = "[swimming] " .. f[water].name end
    if outdoor then cast[#cast + 1] = "[outdoors] " .. f[outdoor].name end
    if indoor then cast[#cast + 1] = "[indoors] " .. f[indoor].name end
    if #cast > 0 then add("/cast " .. table.concat(cast, "; ")) end
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------------
-- Button
-----------------------------------------------------------------------------
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local function keyDownMode()
    if C_CVar and type(C_CVar.GetCVarBool) == "function" then
        local ok, value = pcall(C_CVar.GetCVarBool, "ActionButtonUseKeyDown")
        if ok then return value and true or false end
    end
    return type(GetCVarBool) == "function" and GetCVarBool("ActionButtonUseKeyDown") and true or false
end

function ns.BindingName()
    return "CLICK " .. ns.BUTTON_NAME .. ":LeftButton"
end

function ns.GetBoundKey()
    if type(GetBindingKey) ~= "function" then return nil end
    return (GetBindingKey(ns.BindingName()))
end

local function shortKey(key)
    if not key then return "" end
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
    key = key:gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD"):gsub("BUTTON", "M")
    key = key:gsub("NUMPAD", "N")
    return key
end

-- Applies the macro to both buttons, plus the visible button's look and place.
-- Protected: out of combat.
function ns.ApplyButton()
    if not button then return end
    ns.RunAfterCombat("button", function()
        local db = ns.db
        local macro = ns.BuildMacro()
        -- key button: follows the "cast on key down" setting
        keyButton:RegisterForClicks(keyDownMode() and "AnyDown" or "AnyUp")
        keyButton:SetAttribute("type", "macro")
        keyButton:SetAttribute("macrotext", macro)
        -- visible button: left = macro, right = quick menu (no secure action)
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", macro)
        button:SetSize(db.buttonSize, db.buttonSize)
        button:ClearAllPoints()
        local pos = db.buttonPos
        if type(pos) == "table" and pos[1] then
            button:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            button:SetPoint("CENTER", UIParent, "CENTER", 0, -230)
        end
        button:SetAlpha(db.showButton and 1 or 0)
        button:EnableMouse(db.showButton and true or false)
        -- no icon prediction while the button is hidden
        button:SetScript("OnUpdate", db.showButton and iconOnUpdate or nil)
        if db.showButton and iconOnUpdate then iconOnUpdate(button, 1) end
        button.hotkey:SetText(shortKey(ns.GetBoundKey()))
        button.combat:SetText(ns:L("short_" .. ns.CombatKind()))
        if ns.RefreshQuickMenu then ns.RefreshQuickMenu() end
    end)
end

-- Icon of what the next press will do (shown only; the macro decides).
local function predictIcon()
    local f, db = ns.forms, ns.db
    if not next(f) then return FALLBACK_ICON end
    local current = (type(GetShapeshiftForm) == "function" and GetShapeshiftForm()) or 0
    local function iconOf(kind)
        if kind == "caster" or not f[kind] then return CASTER_ICON end
        return f[kind].icon or FALLBACK_ICON
    end
    if db.useModifiers then
        if IsAltKeyDown() then return CASTER_ICON end
        if IsShiftKeyDown() and f.bear then return iconOf("bear") end
        if IsControlKeyDown() and f.cat then return iconOf("cat") end
    end
    if ns.InCombat() or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if db.useAquatic and f.aquatic and IsSwimming and IsSwimming() then
            return iconOf("aquatic")
        end
        return iconOf(ns.CombatKind())
    end
    local water, outdoor, indoor = placeKinds()
    local kind
    if IsSwimming and IsSwimming() then kind = water
    elseif IsOutdoors and IsOutdoors() then kind = outdoor
    else kind = indoor end
    if not kind then return CASTER_ICON end
    if f[kind].index == current then return CASTER_ICON end -- second press leaves the form
    return iconOf(kind)
end

local function createButtons()
    -- hidden button the key binding clicks
    keyButton = CreateFrame("Button", ns.BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    keyButton:SetSize(1, 1)
    keyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)

    button = CreateFrame("Button", "EzWoWDruidFormsBar", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    ns.UIKit:ApplyBackdrop(button, 1, 0)
    button:SetBackdropColor(rgba(ns.Style.bgSecondary))
    button:SetBackdropBorderColor(rgba(ns.Style.border))
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(button.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    button.hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    button.hotkey:SetPoint("TOPRIGHT", -3, -3)
    -- combat choice in the corner (bear / cat ...), handy for feral druids
    button.combat = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.combat:SetPoint("BOTTOMLEFT", 3, 3)
    local path, size = button.combat:GetFont()
    if path then button.combat:SetFont(path, size, "OUTLINE") end
    button.combat:SetTextColor(rgba(ns.Style.accent))

    -- Ctrl + drag moves it; the click that ends a drag does nothing
    button:SetScript("OnDragStart", function(self)
        if ns.InCombat() or not IsControlKeyDown() then return end
        self.moving = true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self:StopMovingOrSizing()
        self.moving = false
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.db.buttonPos = { point, relPoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
        self.justMoved = true
        C_Timer.After(0.2, function() self.justMoved = false end)
    end)
    button:SetScript("PreClick", function(self)
        if self.justMoved and not ns.InCombat() then self:SetAttribute("type1", nil) end
    end)
    button:SetScript("PostClick", function(self, mouse)
        if self.justMoved and not ns.InCombat() then self:SetAttribute("type1", "macro") end
        if mouse == "RightButton" and ns.ToggleQuickMenu then ns.ToggleQuickMenu(self) end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.TITLE, rgba(ns.Style.accent))
        local key = ns.GetBoundKey()
        GameTooltip:AddLine(key and string.format(ns:L("tipKey"), key) or ns:L("tipNoKey"), rgba(ns.Style.textBody))
        GameTooltip:AddLine(string.format(ns:L("tipCombat"), ns:L("form_" .. ns.CombatKind())), rgba(ns.Style.textBody))
        GameTooltip:AddLine(ns:L("tipRules"), 0.75, 0.8, 0.85, true)
        GameTooltip:AddLine(ns:L("tipMouse"), rgba(ns.Style.accent))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local elapsed = 0
    iconOnUpdate = function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.15 then return end
        elapsed = 0
        self.icon:SetTexture(predictIcon())
    end
    button:SetScript("OnUpdate", iconOnUpdate)
end

-----------------------------------------------------------------------------
-- Quick menu (right-click): combat form, place rules, modifiers
-----------------------------------------------------------------------------
local menu
local ROW_H = 20

local function menuRows()
    local rows = { { header = "secCombat" } }
    for _, kind in ipairs({ "bear", "cat", "caster", "moonkin" }) do
        rows[#rows + 1] = { radio = kind, available = kind == "caster" or ns.forms[kind] ~= nil }
    end
    rows[#rows + 1] = { header = "secPlace" }
    rows[#rows + 1] = { check = "useAquatic", available = ns.forms.aquatic ~= nil }
    rows[#rows + 1] = { check = "useTravel", available = ns.forms.travel ~= nil }
    rows[#rows + 1] = { check = "indoorCat", available = true }
    rows[#rows + 1] = { check = "useModifiers", available = true }
    rows[#rows + 1] = { header = "secMore" }
    rows[#rows + 1] = { action = "setKey", available = true }
    rows[#rows + 1] = { action = "options", available = true }
    return rows
end

local function buildMenu()
    menu = CreateFrame("Frame", "EzWoWDruidFormsMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    ns.UIKit:ApplyBackdrop(menu, 1, 1)
    menu:SetBackdropColor(ns.Style.bgPrimary[1], ns.Style.bgPrimary[2], ns.Style.bgPrimary[3], 0.98)
    menu:SetBackdropBorderColor(rgba(ns.Style.accent))
    menu:SetWidth(240)
    menu.rows = {}
    menu.note = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menu.note:SetPoint("BOTTOMLEFT", 8, 6)
    menu.note:SetWidth(224)
    menu.note:SetJustifyH("LEFT")
    menu.note:SetTextColor(rgba(ns.Style.warning))
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWDruidFormsMenu") end
    menu:Hide()
    menu:SetScript("OnUpdate", function(self)
        -- close when the mouse is pressed somewhere else
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and not self:IsMouseOver()
            and not (button and button:IsMouseOver()) then
            self:Hide()
        end
    end)
end

local function onRowClick(row)
    local db = ns.db
    local item = row.item
    if not item or item.header or not item.available then return end
    if item.radio then
        db.combatForm = item.radio
    elseif item.check then
        db[item.check] = not db[item.check]
    elseif item.action == "setKey" then
        menu:Hide()
        ns:OpenOptions()
        if ns.StartKeyCapture then ns.StartKeyCapture() end
        return
    elseif item.action == "options" then
        menu:Hide()
        ns:OpenOptions()
        return
    end
    ns.ApplyButton()
    if ns.RefreshOptions then ns.RefreshOptions() end
    ns.RefreshQuickMenu()
end

function ns.RefreshQuickMenu()
    if not menu or not menu:IsShown() then return end
    local rows = menuRows()
    local db = ns.db
    local combatKind = ns.CombatKind()
    for i, item in ipairs(rows) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(ROW_H)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(ns.Style.accent[1], ns.Style.accent[2], ns.Style.accent[3], 0.16)
            row.hl:Hide()
            row.mark = row:CreateTexture(nil, "OVERLAY")
            row.mark:SetSize(10, 10)
            row.mark:SetPoint("LEFT", 10, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) if self.item and not self.item.header then self.hl:Show() end end)
            row:SetScript("OnLeave", function(self) self.hl:Hide() end)
            row:SetScript("OnClick", onRowClick)
            menu.rows[i] = row
        end
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 3, -4 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -3, -4 - (i - 1) * ROW_H)
        row.text:ClearAllPoints()
        row.mark:Hide()
        if item.header then
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetText(ns:L(item.header))
            row.text:SetTextColor(rgba(ns.Style.accent))
        else
            row.text:SetPoint("LEFT", 28, 0)
            row.text:SetPoint("RIGHT", -6, 0)
            local on
            if item.radio then
                row.text:SetText(ns:L("form_" .. item.radio))
                on = combatKind == item.radio
            elseif item.check then
                row.text:SetText(ns:L("opt_" .. item.check))
                on = db[item.check] and true or false
            else
                row.text:SetText(ns:L("menu_" .. item.action))
            end
            local color = item.available and (on and ns.Style.accent or ns.Style.textBody) or ns.Style.disabled
            row.text:SetTextColor(rgba(color))
            if item.radio or item.check then
                -- filled square = on, outline only = off
                row.mark:SetColorTexture(color[1], color[2], color[3], on and 1 or 0.25)
                row.mark:Show()
            end
        end
        row:Show()
    end
    for i = #rows + 1, #menu.rows do menu.rows[i]:Hide() end
    local inCombat = ns.InCombat()
    menu.note:SetText(inCombat and ns:L("menuCombat") or "")
    menu:SetHeight(#rows * ROW_H + 8 + (inCombat and 18 or 0))
end

function ns.ToggleQuickMenu(anchor)
    if not menu then buildMenu() end
    if menu:IsShown() then menu:Hide() return end
    menu:ClearAllPoints()
    local _, y = anchor:GetCenter()
    local uiH = UIParent:GetHeight() or 768
    if y and y < uiH / 2 then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    end
    menu:Show()
    ns.RefreshQuickMenu()
end

-----------------------------------------------------------------------------
-- Key binding
-----------------------------------------------------------------------------
function ns.SetKey(key)
    ns.RunAfterCombat("binding", function()
        local name = ns.BindingName()
        local old = { GetBindingKey(name) }
        for _, oldKey in ipairs(old) do SetBinding(oldKey) end
        if key then SetBindingClick(key, ns.BUTTON_NAME, "LeftButton") end
        local set = type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet() or 2
        pcall(SaveBindings, set)
        ns.ApplyButton()
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
end

-----------------------------------------------------------------------------
-- Start
-----------------------------------------------------------------------------
function ns.Refresh()
    if not ns.IsDruid() then return end
    ns.RunAfterCombat("scan", function()
        ns.ScanForms()
        ns.ApplyButton()
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
end

function ns.Start()
    _G.BINDING_HEADER_EZWOWDRUIDFORMS = ns.TITLE
    _G["BINDING_NAME_" .. ns.BindingName()] = ns:L("bindingName")
    if not ns.IsDruid() then return end
    createButtons()
    ns.Refresh()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "LEARNED_SPELL_IN_TAB",
        "PLAYER_LEVEL_UP", "UPDATE_BINDINGS", "CVAR_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_BINDINGS" or event == "CVAR_UPDATE" then
            ns.ApplyButton()
        else
            ns.Refresh()
        end
    end)
end
