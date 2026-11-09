--===========================================================================
-- EzWoW - Druid Forms
-- UI/OptionsWindow.lua : Settings window (key capture), Blizzard launcher, slash
--===========================================================================
local _, ns = ...
local type, ipairs, pairs, tostring, pcall = type, ipairs, pairs, tostring, pcall

local UIKit = ns.UIKit
local configFrame, optionsPanel, donateBox, capture

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local function S() return ns.Style end

local FORM_ORDER = { "bear", "aquatic", "cat", "travel", "moonkin" }
local COMBAT_CHOICES = { "bear", "cat", "caster", "moonkin" }
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

-----------------------------------------------------------------------------
-- Key capture
-----------------------------------------------------------------------------
local function finishCapture(key)
    capture:Hide()
    if key then
        local action = type(GetBindingAction) == "function" and GetBindingAction(key) or ""
        if action ~= "" and action ~= ns.BindingName() then
            ns.Print(string.format(ns:L("keyReplaced"), key, action))
        end
        -- Shift/Ctrl + this key bound elsewhere: those presses never reach this button
        if ns.db and ns.db.useModifiers and not key:find("%-") and type(GetBindingAction) == "function" then
            local taken = {}
            for _, mod in ipairs({ "SHIFT", "CTRL" }) do
                local combo = mod .. "-" .. key
                local other = GetBindingAction(combo) or ""
                if other ~= "" and other ~= ns.BindingName() then
                    taken[#taken + 1] = combo .. " (" .. (_G["BINDING_NAME_" .. other] or other) .. ")"
                end
            end
            if #taken > 0 then
                ns.Print(string.format(ns:L("keyModTaken"), table.concat(taken, ", ")))
            end
        end
        ns.SetKey(key)
    end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function startCapture()
    if ns.InCombat() then
        ns.Print(ns:L("combatLater"))
        return
    end
    if not capture then
        capture = CreateFrame("Frame", nil, configFrame)
        capture:SetAllPoints(configFrame)
        capture:SetFrameLevel(configFrame:GetFrameLevel() + 50)
        capture:EnableMouse(true)
        capture:EnableKeyboard(true)
        capture:SetPropagateKeyboardInput(false)
        local shade = capture:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints()
        shade:SetColorTexture(0, 0, 0, 0.75)
        capture.text = capture:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        capture.text:SetPoint("CENTER")
        capture.text:SetWidth(380)
        capture.text:SetTextColor(rgba(S().accent))
        capture:SetScript("OnKeyDown", function(_, key)
            if MODIFIER_KEYS[key] then return end
            if key == "ESCAPE" then finishCapture(nil) return end
            local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
            finishCapture(combo)
        end)
        capture:SetScript("OnMouseDown", function(_, mouse)
            local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
            if map[mouse] then finishCapture(map[mouse]) end
        end)
        capture:SetScript("OnMouseWheel", function(_, delta)
            finishCapture(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        end)
        capture:EnableMouseWheel(true)
    end
    capture.text:SetText(ns:L("pressKey"))
    capture:Show()
end

-- opens the settings window (never closes it)
function ns:OpenOptions()
    if configFrame and configFrame:IsShown() then
        configFrame:Raise()
        return
    end
    self:ToggleOptions()
end

-- opened from the quick menu
function ns.StartKeyCapture()
    if configFrame and configFrame:IsShown() then startCapture() end
end

-----------------------------------------------------------------------------
-- Donate popup
-----------------------------------------------------------------------------
local function showDonatePopup()
    if not donateBox then
        donateBox = CreateFrame("Frame", "EzWoWDruidFormsDonate", UIParent, "BackdropTemplate")
        donateBox:SetSize(390, 116)
        donateBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        UIKit:ApplyBackdrop(donateBox)
        donateBox:SetBackdropColor(S().bgPrimary[1], S().bgPrimary[2], S().bgPrimary[3], 0.98)
        donateBox:SetBackdropBorderColor(rgba(S().accent))
        donateBox.label = donateBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        donateBox.label:SetPoint("TOP", 0, -14)
        donateBox.label:SetTextColor(rgba(S().accent))
        local box, edit = UIKit:CreateEditBox(donateBox, 346, 27)
        box:SetPoint("TOP", 0, -43)
        box:SetFrameLevel(donateBox:GetFrameLevel() + 5)
        edit:SetText(ns.DONATE_URL)
        edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
        edit:SetScript("OnEscapePressed", function() donateBox:Hide() end)
        edit:SetScript("OnEnterPressed", function() donateBox:Hide() end)
        edit:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(ns.DONATE_URL) self:HighlightText() end end)
        donateBox.edit = edit
        local close = UIKit:CreateCloseButton(donateBox, function() donateBox:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    donateBox.label:SetText(ns:L("copy"))
    UIKit:ElevateModal(donateBox, 260)
    donateBox:Show()
    donateBox.edit:SetFocus()
    donateBox.edit:HighlightText()
end

-----------------------------------------------------------------------------
-- Settings window
-----------------------------------------------------------------------------
function ns:ToggleOptions()
    if not self.db then return end
    if configFrame then
        configFrame:SetShown(not configFrame:IsShown())
        if configFrame:IsShown() then configFrame:Raise() end
        return
    end
    local db = self.db
    configFrame = CreateFrame("Frame", "EzWoWDruidFormsConfig", UIParent, "BackdropTemplate")
    configFrame:SetSize(440, 676)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetToplevel(true)
    configFrame:SetClampedToScreen(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWDruidFormsConfig") end
    UIKit:ApplyBackdrop(configFrame, 1, 1)
    configFrame:SetBackdropColor(rgba(S().bgPrimary))
    configFrame:SetBackdropBorderColor(rgba(S().border))
    configFrame:SetScript("OnHide", function() if capture then capture:Hide() end end)

    local top = UIKit:CreateHeader(configFrame, ns.TITLE)
    top.subtitle:SetWidth(320)
    local close = UIKit:CreateCloseButton(top, function() configFrame:Hide() end)
    close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)

    local headings = {}
    local function section(key, y)
        local t = UIKit:CreateSectionLabel(configFrame, 20, y)
        local line = configFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(S().border[1], S().border[2], S().border[3], 0.85)
        line:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, y - 20)
        line:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -20, y - 20)
        line:SetHeight(1)
        headings[#headings + 1] = { fs = t, key = key }
    end

    -- learned forms
    local learned = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    learned:SetPoint("TOPLEFT", 22, -68)
    learned:SetWidth(396)
    learned:SetJustifyH("LEFT")
    learned:SetTextColor(rgba(S().textMuted))

    -- 1. Key
    section("secKey", -104)
    local keyBtn = UIKit:CreateButton(configFrame, 290, 34, "", true, "GameFontNormal")
    keyBtn:SetPoint("TOPLEFT", 20, -130)
    keyBtn:SetScript("OnClick", startCapture)
    local clearKey = UIKit:CreateButton(configFrame, 104, 34, "", false, "GameFontHighlightSmall")
    clearKey:SetPoint("LEFT", keyBtn, "RIGHT", 6, 0)
    clearKey:SetScript("OnClick", function() ns.SetKey(nil) end)

    -- 2. In combat
    section("secCombat", -182)
    local combatBtns = {}
    for i, kind in ipairs(COMBAT_CHOICES) do
        local b = UIKit:CreateButton(configFrame, 97, 28, "", false, "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 20 + (i - 1) * 101, -208)
        b.kind = kind
        b:SetScript("OnClick", function(self)
            db.combatForm = self.kind
            ns.ApplyButton()
            ns.RefreshOptions()
        end)
        combatBtns[#combatBtns + 1] = b
    end

    -- 3. Out of combat & modifiers
    section("secPlace", -254)
    local checks = {}
    local function option(x, y, key, after)
        local c, t = UIKit:CreateCheck(configFrame, function(value)
            db[key] = value
            if after then after(value) end
            ns.ApplyButton()
            ns.RefreshOptions()
        end)
        c:SetPoint("TOPLEFT", x, y)
        checks[#checks + 1] = { check = c, label = t, key = key }
    end
    option(20, -278, "useAquatic")
    option(20, -304, "useTravel")
    option(20, -330, "indoorCat")
    option(20, -356, "useModifiers")

    -- 4. Button
    section("secButton", -394)
    option(20, -418, "showButton")
    local moveHint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moveHint:SetPoint("TOPLEFT", 24, -450)
    moveHint:SetWidth(392)
    moveHint:SetJustifyH("LEFT")
    moveHint:SetTextColor(rgba(S().textMuted))
    local sizeLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", 24, -480)
    local minus = UIKit:CreateButton(configFrame, 27, 27, "-", false, "GameFontNormalLarge")
    minus:SetPoint("TOPLEFT", 150, -473)
    local sizeValue = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValue:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    sizeValue:SetWidth(40)
    local plus = UIKit:CreateButton(configFrame, 27, 27, "+", false, "GameFontNormalLarge")
    plus:SetPoint("LEFT", minus, "RIGHT", 48, 0)
    local function changeSize(delta)
        db.buttonSize = math.max(24, math.min(64, db.buttonSize + delta))
        ns.ApplyButton()
        ns.RefreshOptions()
    end
    minus:SetScript("OnClick", function() changeSize(-4) end)
    plus:SetScript("OnClick", function() changeSize(4) end)
    local resetBtn = UIKit:CreateButton(configFrame, 150, 27, "", false, "GameFontHighlightSmall")
    resetBtn:SetPoint("TOPLEFT", 270, -473)
    resetBtn:SetScript("OnClick", function()
        db.buttonPos = nil
        ns.ApplyButton()
    end)

    -- macro preview
    section("secMacro", -516)
    local macroText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    macroText:SetPoint("TOPLEFT", 22, -542)
    macroText:SetWidth(396)
    macroText:SetJustifyH("LEFT")
    macroText:SetJustifyV("TOP")
    macroText:SetTextColor(rgba(S().textMuted))

    local langBtn = UIKit:CreateButton(configFrame, 197, 28, "")
    langBtn:SetPoint("BOTTOMLEFT", 20, 32)
    local langItems = {}
    for i, v in ipairs(ns.LANGUAGE_OPTIONS) do langItems[i] = { value = v[1], text = v[2] } end
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { accent = ns.Style.accent },
        get = function() return db.language end,
        set = function(code) db.language = code ns.RefreshOptions() end,
    })
    local donateBtn = UIKit:CreateButton(configFrame, 197, 28, "", true)
    donateBtn:SetPoint("BOTTOMRIGHT", -20, 32)
    donateBtn:SetScript("OnClick", showDonatePopup)
    local foot = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 12)

    function ns.RefreshOptions()
        if not configFrame then return end
        ns.FitText(top.subtitle, ns:L("settingsSub"), 320, 10, 8)
        for _, h in ipairs(headings) do ns.FitText(h.fs, ns:L(h.key), 395, 13, 10) end

        local isDruid = ns.IsDruid()
        if not isDruid then
            learned:SetText(ns:L("notDruid"))
        else
            local names = {}
            for _, kind in ipairs(FORM_ORDER) do
                if ns.forms[kind] then names[#names + 1] = ns.forms[kind].name end
            end
            learned:SetText(#names > 0 and (ns:L("learned") .. " " .. table.concat(names, ", ")) or ns:L("noForms"))
        end

        local key = ns.GetBoundKey()
        keyBtn:SetLabel(key and string.format(ns:L("keyIs"), key) or ns:L("keyNone"))
        keyBtn:SetEnabledState(isDruid)
        clearKey:SetLabel(ns:L("keyClear"))
        clearKey:SetEnabledState(isDruid and key ~= nil)

        local combatKind = isDruid and ns.CombatKind() or db.combatForm
        for _, b in ipairs(combatBtns) do
            b:SetLabel(isDruid and ns.FormLabel(ns:L("form_" .. b.kind), b.kind) or ns:L("form_" .. b.kind))
            local available = b.kind == "caster" or (ns.forms[b.kind] ~= nil)
            b:SetEnabledState(isDruid and available)
            b:SetActive(isDruid and combatKind == b.kind)
        end
        for _, item in ipairs(checks) do
            item.check:SetChecked(db[item.key] and true or false)
            local text = ns:L("opt_" .. item.key)
            if isDruid then text = ns.FormLabel(text, ns.OPTION_FORM[item.key]) end
            ns.FitText(item.label, text, 370, 12, 9)
        end
        ns.FitText(sizeLabel, ns:L("buttonSize"), 120, 12, 9)
        sizeValue:SetText(tostring(db.buttonSize))
        resetBtn:SetLabel(ns:L("resetPos"))
        moveHint:SetText(ns:L("moveHint"))
        macroText:SetText(isDruid and ns.BuildMacro() or "")
        -- grow the window so the macro never runs into the buttons below it
        local macroHeight = macroText:GetStringHeight() or 0
        configFrame:SetHeight(math.max(600, math.ceil(542 + macroHeight + 84)))
        langBtn:SetLabel(ns:L("language") .. ": " .. ns:GetLanguageDisplayLabel() .. " ▼")
        donateBtn:SetLabel(ns:L("donate"))
        local ver = ns.GetVersion()
        foot:SetText(ns.TITLE .. (ver ~= "" and (" v" .. ver) or "") .. "  ·  /ezdf")
        if optionsPanel and optionsPanel.refreshText then optionsPanel.refreshText() end
    end
    configFrame:SetScript("OnShow", ns.RefreshOptions)
    ns.RefreshOptions()
end

-----------------------------------------------------------------------------
-- Blizzard settings launcher & slash
-----------------------------------------------------------------------------
function ns:RegisterBlizzardOptions()
    if optionsPanel then return end
    optionsPanel = CreateFrame("Frame", "EzWoWDruidFormsOptionsPanel", UIParent)
    optionsPanel.name = ns.TITLE
    local icon = optionsPanel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 18, -18)
    icon:SetTexture(ns.MEDIA_PATH .. "Icon")
    local heading = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    heading:SetText(ns.TITLE)
    heading:SetTextColor(rgba(S().accent))
    local desc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    local open = UIKit:CreateButton(optionsPanel, 220, 28, "", true)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    open:SetScript("OnClick", function() ns:ToggleOptions() end)
    optionsPanel.refreshText = function()
        desc:SetText(ns:L("panelDesc"))
        open:SetLabel(ns:L("panelOpen"))
    end
    optionsPanel:SetScript("OnShow", optionsPanel.refreshText)
    -- fill the texts now: the settings window does not always fire OnShow
    optionsPanel.refreshText()
    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, optionsPanel, ns.TITLE)
        if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
    end
end

SLASH_EZWOWDRUIDFORMS1 = "/ezdf"
SLASH_EZWOWDRUIDFORMS2 = "/드루이드"
SLASH_EZWOWDRUIDFORMS3 = "/ezwowdruidforms"
SlashCmdList.EZWOWDRUIDFORMS = function()
    if not ns.db then return end
    ns:ToggleOptions()
end
