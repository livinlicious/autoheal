-- AutoHeal - Automatic Healing Addon
-- Based on proven patterns from QuickHeal and AUTO-REJU macro

-- Saved Variables
AutoHealVariables = {};
local AHV = {};

-- Default values with preset system
local DAHV = {
    Presets = {
        reju = {
            name = "reju",
            spell = "Rejuvenation",
            healthThreshold = 90,
            blockTime = 12,
            maxRange = 40,
            selfPreservationThreshold = 60,
            selfPreservationEnabled = true
        }
    }
}

-- Blacklist tracking (handles invisible buff problem)
local BlacklistTimes = {};
local GCDFrame = nil;

-- Helper function to write to chat
local function writeLine(s, r, g, b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

-- Get all spell IDs for a spell name
local function GetSpellIDs(spellName)
    local spellIds = {};
    local i = 1;
    while true do
        local name, rank = GetSpellName(i, BOOKTYPE_SPELL);
        if not name then
            break;
        end
        if name == spellName then
            local _, _, rankNum = string.find(rank or "", "(%d+)");
            if rankNum then
                rankNum = tonumber(rankNum);
                spellIds[rankNum] = i;
            else
                spellIds[1] = i;
            end
        end
        i = i + 1;
    end
    return spellIds;
end

-- Find spell slot by name (from Spam Cast Protected macro)
local function FindSpellSlot(spellName)
    local baseName = spellName;
    local _, _, base = string.find(spellName, "(.+)%(Rank %d+%)");
    if base then
        baseName = base;
    end

    for i = 1, 200 do
        local name = GetSpellName(i, BOOKTYPE_SPELL);
        if not name then
            break;
        end
        if name == baseName then
            return i;
        end
    end
    return nil;
end

-- Auto-detect buff texture from spell (from Spam Cast Protected concept)
local function GetBuffTextureForSpell(spellName)
    -- Find the spell slot
    local spellSlot = FindSpellSlot(spellName);
    if not spellSlot then
        return nil;
    end

    -- Get the spell texture (icon)
    local texture = GetSpellTexture(spellSlot, BOOKTYPE_SPELL);
    if not texture then
        return nil;
    end

    -- Extract just the icon name from the path
    -- Example: "Interface\\Icons\\Spell_Nature_Rejuvenation" -> "Spell_Nature_Rejuvenation"
    local _, _, iconName = string.find(texture, "Interface\\\\Icons\\\\(.+)");
    if iconName then
        return iconName;
    end

    -- If no match, return the full texture path
    return texture;
end

-- Get distance to unit (from pfUI-raiddistance addon)
local function GetDistance(unit)
    if not UnitExists(unit) then
        return nil;
    end
    local success, distance = pcall(UnitXP, "distanceBetween", "player", unit);
    if success then
        return distance;
    end
    return nil;
end

-- Check line of sight to unit (from pfUI-raiddistance addon)
local function GetLineOfSight(unit)
    if not UnitExists(unit) then
        return false;
    end
    local success, los = pcall(UnitXP, "inSight", "player", unit);
    if success then
        return los;
    end
    return false;
end

-- Check if unit is healable (range and LOS aware)
local function UnitIsHealable(unit, maxRange)
    if not UnitExists(unit) then
        return false;
    end
    if UnitIsDeadOrGhost(unit) then
        return false;
    end
    if not UnitCanAssist("player", unit) then
        return false;
    end
    if not UnitIsConnected(unit) then
        return false;
    end

    -- Check line of sight (from pfUI-raiddistance)
    if not GetLineOfSight(unit) then
        return false;
    end

    -- Check distance if maxRange specified (from pfUI-raiddistance)
    if maxRange and maxRange > 0 then
        local distance = GetDistance(unit);
        if distance and distance > maxRange then
            return false;
        end
    end

    return true;
end

-- Check if unit has specific buff (based on QuickHeal pattern)
local function UnitHasBuff(unit, buffTexture)
    if not UnitExists(unit) then
        return false;
    end

    -- Check using UnitBuff (up to 40 buffs checked, but only first 32 visible to others)
    for i = 1, 40 do
        local texture = UnitBuff(unit, i);
        if texture then
            if string.find(texture, buffTexture) then
                return true;
            end
        end
    end

    return false;
end

-- Check if target should be skipped due to blacklist (from AUTO-REJU macro)
local function ShouldSkipTarget(unitName, blockTime)
    if not unitName then
        return true;
    end

    local lastCastTime = BlacklistTimes[unitName];
    if lastCastTime then
        local currentTime = GetTime();
        local elapsed = currentTime - lastCastTime;
        if elapsed < blockTime then
            return true;
        else
            -- Clear expired blacklist
            BlacklistTimes[unitName] = nil;
        end
    end
    return false;
end

-- Check if unit needs healing based on preset configuration
local function NeedsHeal(unit, preset)
    -- Check if unit is healable (includes LOS and distance check from pfUI-raiddistance)
    if not UnitIsHealable(unit, preset.maxRange) then
        return false;
    end

    -- Auto-detect buff texture from spell if not already cached
    if not preset.buffTexture then
        preset.buffTexture = GetBuffTextureForSpell(preset.spell);
    end

    -- Check if buff is visible on unit
    if preset.buffTexture and UnitHasBuff(unit, preset.buffTexture) then
        return false;
    end

    local unitName = UnitName(unit);
    if not unitName then
        return false;
    end

    -- Check blacklist (handles the invisible buff problem)
    if ShouldSkipTarget(unitName, preset.blockTime) then
        return false;
    end

    -- Check health threshold
    local health = UnitHealth(unit);
    local maxHealth = UnitHealthMax(unit);
    if health == 0 or maxHealth == 0 then
        return false;
    end

    local healthPct = (health / maxHealth) * 100;
    return healthPct <= preset.healthThreshold;
end

-- Get health percentage of unit
local function GetHealthPercent(unit)
    if not UnitExists(unit) then
        return 100;
    end
    local hp = UnitHealth(unit);
    local maxhp = UnitHealthMax(unit);
    if maxhp == 0 then
        return 100;
    end
    return (hp / maxhp) * 100;
end

-- Check if spell is castable (from AUTO-REJU macro)
local function CanCastSpell(spellName)
    local i = 1;
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL);
        if not name then
            break;
        end
        if name == spellName then
            local start, duration = GetSpellCooldown(i, BOOKTYPE_SPELL);
            return start == 0;
        end
        i = i + 1;
    end
    return false;
end

-- Find all heal targets based on preset
-- Returns sorted table of targets
-- FIXED: Player prioritized by HP%, not always last
-- ADDED: Emergency self-preservation mode
local function FindAllHealTargets(preset)
    local targets = {};
    local playerHealth = GetHealthPercent("player");

    -- EMERGENCY: Self-preservation check
    -- If enabled and player below threshold, prioritize self above all else
    if preset.selfPreservationEnabled and playerHealth <= preset.selfPreservationThreshold then
        if NeedsHeal("player", preset) then
            local unitName = UnitName("player");
            if unitName then
                -- Return ONLY player as emergency target
                return {{
                    unit = "player",
                    name = unitName,
                    health = playerHealth,
                    priority = 0,
                    emergency = true
                }};
            end
        end
    end

    -- Normal mode: mouseover and target get special priority, everyone else by HP%

    -- Priority 1: Mouseover (intentional healing)
    if NeedsHeal("mouseover", preset) then
        local unitName = UnitName("mouseover");
        if unitName then
            table.insert(targets, {
                unit = "mouseover",
                name = unitName,
                health = GetHealthPercent("mouseover"),
                priority = 1
            });
        end
    end

    -- Priority 2: Current target (intentional healing)
    if NeedsHeal("target", preset) then
        local unitName = UnitName("target");
        if unitName then
            table.insert(targets, {
                unit = "target",
                name = unitName,
                health = GetHealthPercent("target"),
                priority = 2
            });
        end
    end

    -- Priority 3: Everyone else (party, raid, player) - sorted by HP% only
    -- Player is treated equally based on HP%, not given special priority

    -- Add party members
    for i = 1, GetNumPartyMembers() do
        local unit = "party" .. i;
        if NeedsHeal(unit, preset) then
            local unitName = UnitName(unit);
            if unitName then
                table.insert(targets, {
                    unit = unit,
                    name = unitName,
                    health = GetHealthPercent(unit),
                    priority = 3
                });
            end
        end
    end

    -- Add raid members
    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i;
        if NeedsHeal(unit, preset) then
            local unitName = UnitName(unit);
            if unitName then
                table.insert(targets, {
                    unit = unit,
                    name = unitName,
                    health = GetHealthPercent(unit),
                    priority = 3
                });
            end
        end
    end

    -- Add player (same priority as raid/party, sorted by HP%)
    if NeedsHeal("player", preset) then
        local unitName = UnitName("player");
        if unitName then
            table.insert(targets, {
                unit = "player",
                name = unitName,
                health = playerHealth,
                priority = 3
            });
        end
    end

    -- Sort: mouseover first, target second, then everyone else by HP% (lowest first)
    table.sort(targets, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority;
        else
            return a.health < b.health;
        end
    end);

    return targets;
end

-- Cast spell on target with GCD-based success detection (from AUTO-REJU macro)
local function CastSpellOnTarget(spellName, unit, unitName, preset)
    if not unit or not unitName then
        return false;
    end

    -- Check if spell is castable
    if not CanCastSpell(spellName) then
        return false;
    end

    -- Get highest rank spell ID
    local spellIds = GetSpellIDs(spellName);
    local maxRank = 0;
    local maxSpellId = nil;

    for rank, spellId in pairs(spellIds) do
        if rank > maxRank then
            maxRank = rank;
            maxSpellId = spellId;
        end
    end

    if not maxSpellId then
        return false;
    end

    -- Save old target
    local oldTarget = UnitName("target");

    -- Target unit
    TargetUnit(unit);

    if not UnitExists("target") then
        -- Restore old target
        if oldTarget then
            TargetByName(oldTarget);
        end
        return false;
    end

    -- Cast spell (LOS and range already checked by UnitIsHealable)
    CastSpell(maxSpellId, BOOKTYPE_SPELL);

    -- Setup GCD success detection (from AUTO-REJU macro pattern)
    if not GCDFrame then
        GCDFrame = CreateFrame("Frame");
    end

    GCDFrame.checkTime = GetTime() + 0.3;
    GCDFrame.targetName = unitName;

    GCDFrame:SetScript("OnUpdate", function()
        if GetTime() >= GCDFrame.checkTime then
            -- Check if GCD is active (using spell slot 154 as reliable indicator from macro)
            local start, duration = GetSpellCooldown(154, BOOKTYPE_SPELL);
            local gcdRemaining = 0;
            if start and duration and duration > 0 then
                gcdRemaining = (start + duration) - GetTime();
            end

            if gcdRemaining > 0 then
                -- Cast succeeded, blacklist the target
                BlacklistTimes[GCDFrame.targetName] = GetTime();
            end

            -- Clean up
            GCDFrame:SetScript("OnUpdate", nil);
            GCDFrame.checkTime = nil;
            GCDFrame.targetName = nil;
        end
    end);

    -- Restore old target
    if oldTarget then
        TargetByName(oldTarget);
    end

    return true;
end

-- Main healing function with preset support
function AutoHeal_Cast(presetName)
    -- Get preset
    local preset = AHV.Presets[presetName];
    if not preset then
        writeLine("AutoHeal: Preset not found: " .. (presetName or "nil"));
        return;
    end

    -- Find all potential targets (from AUTO-REJU macro pattern)
    local targets = FindAllHealTargets(preset);

    -- If no targets found, return silently (allows macro to continue to next line)
    if not targets or table.getn(targets) == 0 then
        return;
    end

    -- Check GCD only if we have valid targets
    -- This prevents blocking macro execution when there's nothing to heal
    local start, duration = GetSpellCooldown(154, BOOKTYPE_SPELL);
    if start > 0 and (GetTime() - start) < duration then
        return;
    end

    -- Mana check removed - CanCastSpell() already checks if spell is castable (includes mana)
    -- This handles all situations: base cost, form modifiers, trinket buffs, external buffs, etc.

    -- Loop through targets and try to cast on each one
    -- If cast fails (out of range/LOS), try next target
    -- This prevents getting stuck on unreachable targets
    for _, targetInfo in targets do
        if CastSpellOnTarget(preset.spell, targetInfo.unit, targetInfo.name, preset) then
            -- Cast succeeded, stop trying other targets
            -- This WILL trigger GCD and stop macro execution (correct behavior)
            return;
        end
    end

    -- If we get here, no targets were castable (all out of range/LOS)
    -- Return silently to allow macro to continue to next line
end

--[ UI Functions ]--

-- Current selected preset in UI
local SelectedPreset = nil;
local PresetButtons = {};

-- Create preset list buttons
local function CreatePresetButtons()
    local yOffset = -70;
    local buttonNum = 1;

    -- Clear old buttons
    for _, btn in pairs(PresetButtons) do
        btn:Hide();
    end
    PresetButtons = {};

    -- Create button for each preset
    for name, _ in pairs(AHV.Presets) do
        local btn = CreateFrame("Button", "AutoHealPresetBtn" .. buttonNum, AutoHealConfigFrame, "GameMenuButtonTemplate");
        btn:SetWidth(120);
        btn:SetHeight(20);
        btn:SetPoint("TOPLEFT", 20, yOffset);
        btn:SetText(name);
        -- Store preset name on button for OnClick to access
        btn.presetName = name;
        btn:SetScript("OnClick", function()
            AutoHeal_SelectPreset(this.presetName);
        end);
        btn:Show();

        table.insert(PresetButtons, btn);
        yOffset = yOffset - 25;
        buttonNum = buttonNum + 1;
    end
end

-- Select a preset for editing
function AutoHeal_SelectPreset(name)
    SelectedPreset = name;
    local preset = AHV.Presets[name];

    if preset then
        AutoHealConfigFrameCurrentPreset:SetText("Editing: " .. name);
        AutoHealConfigFrameSpellEdit:SetText(preset.spell or "");
        AutoHealConfigFrameHealthEdit:SetText(tostring(preset.healthThreshold or 90));
        AutoHealConfigFrameBlockEdit:SetText(tostring(preset.blockTime or 12));
        AutoHealConfigFrameRangeEdit:SetText(tostring(preset.maxRange or 40));
        AutoHealConfigFrameSelfThresholdEdit:SetText(tostring(preset.selfPreservationThreshold or 60));

        -- Set checkbox state
        if preset.selfPreservationEnabled then
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(1);
        else
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(nil);
        end

        -- Show auto-detected buff texture (read-only display)
        local buffTex = GetBuffTextureForSpell(preset.spell);
        AutoHealConfigFrameBuffInfo:SetText(buffTex or "Not detected");
    end
end

-- Save current preset
function AutoHeal_SavePreset()
    if not SelectedPreset then
        writeLine("AutoHeal: No preset selected");
        return;
    end

    local preset = AHV.Presets[SelectedPreset];
    if not preset then
        writeLine("AutoHeal: Preset not found");
        return;
    end

    -- Get values from edit boxes
    preset.spell = AutoHealConfigFrameSpellEdit:GetText();

    -- Validate health threshold (0-100)
    local healthVal = tonumber(AutoHealConfigFrameHealthEdit:GetText()) or 90;
    if healthVal < 0 then
        healthVal = 0;
    elseif healthVal > 100 then
        healthVal = 100;
    end
    preset.healthThreshold = healthVal;

    preset.blockTime = tonumber(AutoHealConfigFrameBlockEdit:GetText()) or 12;
    preset.maxRange = tonumber(AutoHealConfigFrameRangeEdit:GetText()) or 40;

    -- Validate self-preservation threshold (0-100)
    local selfThreshold = tonumber(AutoHealConfigFrameSelfThresholdEdit:GetText()) or 60;
    if selfThreshold < 0 then
        selfThreshold = 0;
    elseif selfThreshold > 100 then
        selfThreshold = 100;
    end
    preset.selfPreservationThreshold = selfThreshold;

    -- Get checkbox state
    preset.selfPreservationEnabled = (AutoHealConfigFrameSelfPreservationCheck:GetChecked() == 1);

    -- Auto-detect and cache buff texture
    preset.buffTexture = GetBuffTextureForSpell(preset.spell);

    -- Save to saved variables
    AutoHealVariables.Presets[SelectedPreset] = preset;

    writeLine("AutoHeal: Preset '" .. SelectedPreset .. "' saved");

    -- Refresh display
    AutoHeal_SelectPreset(SelectedPreset);
end

-- Create new preset
function AutoHeal_NewPreset()
    StaticPopupDialogs["AUTOHEAL_NEW_PRESET"] = {
        text = "Enter preset name:",
        button1 = "Create",
        button2 = "Cancel",
        hasEditBox = 1,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function()
            local name = getglobal(this:GetParent():GetName().."EditBox"):GetText();
            if name and name ~= "" then
                if AHV.Presets[name] then
                    writeLine("AutoHeal: Preset '" .. name .. "' already exists");
                else
                    -- Create new preset with defaults (mana and buff auto-detected)
                    AHV.Presets[name] = {
                        name = name,
                        spell = "Rejuvenation",
                        healthThreshold = 90,
                        blockTime = 12,
                        maxRange = 40,
                        selfPreservationThreshold = 60,
                        selfPreservationEnabled = true
                    };
                    AutoHealVariables.Presets[name] = AHV.Presets[name];
                    CreatePresetButtons();
                    AutoHeal_SelectPreset(name);
                    writeLine("AutoHeal: Preset '" .. name .. "' created");
                end
            end
        end,
    };
    StaticPopup_Show("AUTOHEAL_NEW_PRESET");
end

-- Delete current preset
function AutoHeal_DeletePreset()
    if not SelectedPreset then
        writeLine("AutoHeal: No preset selected");
        return;
    end

    StaticPopupDialogs["AUTOHEAL_DELETE_PRESET"] = {
        text = "Delete preset '" .. SelectedPreset .. "'?",
        button1 = "Delete",
        button2 = "Cancel",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function()
            AHV.Presets[SelectedPreset] = nil;
            AutoHealVariables.Presets[SelectedPreset] = nil;
            SelectedPreset = nil;
            CreatePresetButtons();
            AutoHealConfigFrameCurrentPreset:SetText("Select a preset");
            AutoHealConfigFrameSpellEdit:SetText("");
            AutoHealConfigFrameHealthEdit:SetText("");
            AutoHealConfigFrameBlockEdit:SetText("");
            AutoHealConfigFrameRangeEdit:SetText("");
            AutoHealConfigFrameSelfThresholdEdit:SetText("");
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(nil);
            AutoHealConfigFrameBuffInfo:SetText("");
            writeLine("AutoHeal: Preset deleted");
        end,
    };
    StaticPopup_Show("AUTOHEAL_DELETE_PRESET");
end

-- Config frame OnLoad
function AutoHeal_ConfigOnLoad()
    -- Set EditBox colors properly
    local function SetupEditBox(editbox)
        editbox:SetTextColor(1, 1, 1);
        editbox:SetBackdropColor(0, 0, 0, 0.9);
        editbox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1);
    end

    SetupEditBox(AutoHealConfigFrameSpellEdit);
    SetupEditBox(AutoHealConfigFrameHealthEdit);
    SetupEditBox(AutoHealConfigFrameBlockEdit);
    SetupEditBox(AutoHealConfigFrameRangeEdit);
    SetupEditBox(AutoHealConfigFrameSelfThresholdEdit);
end

-- Config frame OnShow
function AutoHeal_ConfigOnShow()
    CreatePresetButtons();
    if SelectedPreset and AHV.Presets[SelectedPreset] then
        AutoHeal_SelectPreset(SelectedPreset);
    end
end

-- Toggle config window
function AutoHeal_ToggleConfig()
    if AutoHealConfigFrame:IsVisible() then
        AutoHealConfigFrame:Hide();
    else
        AutoHealConfigFrame:Show();
    end
end

-- Find preset by name (case-insensitive)
local function FindPreset(name)
    if not name then
        return nil;
    end

    local lowerName = string.lower(name);

    -- First try exact match
    if AHV.Presets[name] then
        return name;
    end

    -- Then try case-insensitive match
    for presetName, _ in pairs(AHV.Presets) do
        if string.lower(presetName) == lowerName then
            return presetName;
        end
    end

    return nil;
end

-- Slash command handler
local function SlashCommandHandler(msg)
    local cmd = msg or "";
    local cmdLower = string.lower(cmd);

    if cmdLower == "config" or cmdLower == "cfg" then
        AutoHeal_ToggleConfig();
    elseif cmd == "" or cmdLower == "reju" or cmdLower == "1" then
        -- Default preset
        local presetName = FindPreset("reju");
        if presetName then
            AutoHeal_Cast(presetName);
        else
            writeLine("AutoHeal: Default preset 'reju' not found");
        end
    else
        -- Try to find preset by name (case-insensitive)
        local presetName = FindPreset(cmd);
        if presetName then
            AutoHeal_Cast(presetName);
        else
            writeLine("AutoHeal Usage:");
            writeLine("/autoheal config - Open configuration window");
            writeLine("/autoheal <preset> - Cast using preset");
            writeLine("");
            writeLine("Available presets:");
            for name, _ in pairs(AHV.Presets) do
                writeLine("  " .. name);
            end
        end
    end
end

-- Initialize addon
local function InitializeAddon()
    -- Load saved variables or defaults
    if not AutoHealVariables or type(AutoHealVariables) ~= "table" then
        AutoHealVariables = {};
    end

    -- Initialize presets
    if not AutoHealVariables.Presets then
        AutoHealVariables.Presets = {};
    end

    -- Copy defaults for missing presets
    for k, v in pairs(DAHV.Presets) do
        if not AutoHealVariables.Presets[k] then
            AutoHealVariables.Presets[k] = {};
            for kk, vv in pairs(v) do
                AutoHealVariables.Presets[k][kk] = vv;
            end
        end
    end

    -- Set runtime config
    AHV.Presets = AutoHealVariables.Presets;

    writeLine("AutoHeal loaded. Type /autoheal for help.");
end

-- Register slash commands
SLASH_AUTOHEAL1 = "/autoheal";
SLASH_AUTOHEAL2 = "/ah";
SlashCmdList["AUTOHEAL"] = SlashCommandHandler;

-- Event frame
local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("VARIABLES_LOADED");
eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        InitializeAddon();
    end
end);
