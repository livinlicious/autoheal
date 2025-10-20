-- AutoHeal - Automatic Healing Addon
-- Based on proven patterns from QuickHeal and AUTO-REJU macro

-- Saved Variables
AutoHealVariables = {};
local AHV = {};

-- Default values for new presets
local DAHV = {
    PresetDefaults = {
        spell = "Rejuvenation",
        spellRank = 0,  -- 0 = use highest rank
        healthThreshold = 90,
        blockTime = 12,
        cooldown = 0,  -- spell cooldown in seconds (0 = no cooldown)
        maxRange = 40,
        selfPreservationThreshold = 60,
        selfPreservationEnabled = true,
        requiresBuff = ""  -- empty = normal buff spell, filled = consume spell that requires this buff
    }
}

-- Enhanced target state tracking (handles invisible buff problem)
-- Tracks by spell name, not preset name
local TargetStates = {};  -- [targetName][spellName] = { lastCast, duration }
local SpellCooldowns = {};  -- [spellName] = { lastCast, cooldown }
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

-- Get or create target state for a spell
local function GetSpellState(unitName, spellName)
    if not unitName or not spellName then
        return nil;
    end

    if not TargetStates[unitName] then
        TargetStates[unitName] = {};
    end

    if not TargetStates[unitName][spellName] then
        TargetStates[unitName][spellName] = {
            lastCast = 0,
            duration = 0
        };
    end

    return TargetStates[unitName][spellName];
end

-- Check if spell is on cooldown
local function IsSpellOnCooldown(spellName, cooldown)
    if not spellName or cooldown == 0 then
        return false;
    end

    if not SpellCooldowns[spellName] then
        return false;
    end

    local elapsed = GetTime() - SpellCooldowns[spellName].lastCast;
    return elapsed < cooldown;
end

-- Update spell cooldown
local function UpdateSpellCooldown(spellName, cooldown)
    if not spellName or cooldown == 0 then
        return;
    end

    SpellCooldowns[spellName] = {
        lastCast = GetTime(),
        cooldown = cooldown
    };
end

-- Check if target is blacklisted for a spell
local function IsTargetBlacklisted(unitName, spellName, duration)
    if not unitName or not spellName or duration == 0 then
        return false;
    end

    local state = GetSpellState(unitName, spellName);
    if not state then
        return false;
    end

    local elapsed = GetTime() - state.lastCast;
    return elapsed < duration;
end

-- Update target blacklist after casting
local function UpdateTargetBlacklist(unitName, spellName, duration)
    if not unitName or not spellName then
        return;
    end

    local state = GetSpellState(unitName, spellName);
    if state then
        state.lastCast = GetTime();
        state.duration = duration;
    end
end

-- Clear target blacklist for a spell (after buff consumed)
local function ClearTargetBlacklist(unitName, spellName)
    if not unitName or not spellName then
        return;
    end

    local state = GetSpellState(unitName, spellName);
    if state then
        state.lastCast = 0;
        state.duration = 0;
    end
end

-- Check if unit needs healing based on preset configuration
-- Returns: needsHeal (bool), visibleBuffs (table of spell names that were visible)
local function NeedsHeal(unit, preset)
    -- Check if unit is healable (includes LOS and distance check from pfUI-raiddistance)
    if not UnitIsHealable(unit, preset.maxRange) then
        return false, nil;
    end

    local unitName = UnitName(unit);
    if not unitName then
        return false, nil;
    end

    -- Check health threshold first
    local health = UnitHealth(unit);
    local maxHealth = UnitHealthMax(unit);
    if health == 0 or maxHealth == 0 then
        return false, nil;
    end

    local healthPct = (health / maxHealth) * 100;
    if healthPct > preset.healthThreshold then
        return false, nil;
    end

    -- Auto-detect buff texture from spell if not already cached
    if not preset.buffTexture then
        preset.buffTexture = GetBuffTextureForSpell(preset.spell);
    end

    -- Check if this is a consume spell (has requiresBuff set)
    if preset.requiresBuff and preset.requiresBuff ~= "" then
        -- CONSUME SPELL (e.g., Swiftmend) - needs at least one required buff present

        -- Parse required buffs (comma-separated)
        local requiredBuffs = {};
        for buffName in string.gfind(preset.requiresBuff, "[^,]+") do
            local trimmed = string.gsub(buffName, "^%s*(.-)%s*$", "%1");
            table.insert(requiredBuffs, trimmed);
        end

        -- Check each required buff
        local visibleBuffs = {};
        local hasVisibleBuff = false;
        local hasBlacklistedBuff = false;

        for _, buffName in ipairs(requiredBuffs) do
            local buffTexture = GetBuffTextureForSpell(buffName);
            if buffTexture then
                local isVisible = UnitHasBuff(unit, buffTexture);
                if isVisible then
                    table.insert(visibleBuffs, buffName);
                    hasVisibleBuff = true;
                else
                    -- Check if blacklisted (invisible but likely present)
                    if IsTargetBlacklisted(unitName, buffName, preset.blockTime) then
                        hasBlacklistedBuff = true;
                    end
                end
            end
        end

        -- Eligible if ANY buff visible OR ANY buff blacklisted (optimistic)
        if hasVisibleBuff or hasBlacklistedBuff then
            return true, visibleBuffs;
        end

        return false, nil;
    else
        -- NORMAL BUFF SPELL (e.g., Rejuvenation) - don't cast if buff already visible
        local hasBuff = preset.buffTexture and UnitHasBuff(unit, preset.buffTexture);
        if hasBuff then
            -- Buff visible, clear blacklist (buff is real)
            ClearTargetBlacklist(unitName, preset.spell);
            return false, nil;
        end

        -- Check blacklist (handles the invisible buff problem)
        if IsTargetBlacklisted(unitName, preset.spell, preset.blockTime) then
            return false, nil;
        end

        return true, nil;
    end
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
        local needsHeal, visibleBuffs = NeedsHeal("player", preset);
        if needsHeal then
            local unitName = UnitName("player");
            if unitName then
                -- Return ONLY player as emergency target
                return {{
                    unit = "player",
                    name = unitName,
                    health = playerHealth,
                    priority = 0,
                    emergency = true,
                    visibleBuffs = visibleBuffs
                }};
            end
        end
    end

    -- Normal mode: mouseover and target get special priority, everyone else by HP%

    -- Priority 1: Mouseover (intentional healing)
    local needsHeal, visibleBuffs = NeedsHeal("mouseover", preset);
    if needsHeal then
        local unitName = UnitName("mouseover");
        if unitName then
            table.insert(targets, {
                unit = "mouseover",
                name = unitName,
                health = GetHealthPercent("mouseover"),
                priority = 1,
                visibleBuffs = visibleBuffs
            });
        end
    end

    -- Priority 2: Current target (intentional healing)
    needsHeal, visibleBuffs = NeedsHeal("target", preset);
    if needsHeal then
        local unitName = UnitName("target");
        if unitName then
            table.insert(targets, {
                unit = "target",
                name = unitName,
                health = GetHealthPercent("target"),
                priority = 2,
                visibleBuffs = visibleBuffs
            });
        end
    end

    -- Priority 3: Everyone else (party, raid, player) - sorted by HP% only
    -- Player is treated equally based on HP%, not given special priority

    -- Add party members
    for i = 1, GetNumPartyMembers() do
        local unit = "party" .. i;
        needsHeal, visibleBuffs = NeedsHeal(unit, preset);
        if needsHeal then
            local unitName = UnitName(unit);
            if unitName then
                table.insert(targets, {
                    unit = unit,
                    name = unitName,
                    health = GetHealthPercent(unit),
                    priority = 3,
                    visibleBuffs = visibleBuffs
                });
            end
        end
    end

    -- Add raid members
    for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i;
        needsHeal, visibleBuffs = NeedsHeal(unit, preset);
        if needsHeal then
            local unitName = UnitName(unit);
            if unitName then
                table.insert(targets, {
                    unit = unit,
                    name = unitName,
                    health = GetHealthPercent(unit),
                    priority = 3,
                    visibleBuffs = visibleBuffs
                });
            end
        end
    end

    -- Add player (same priority as raid/party, sorted by HP%)
    needsHeal, visibleBuffs = NeedsHeal("player", preset);
    if needsHeal then
        local unitName = UnitName("player");
        if unitName then
            table.insert(targets, {
                unit = "player",
                name = unitName,
                health = playerHealth,
                priority = 3,
                visibleBuffs = visibleBuffs
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
local function CastSpellOnTarget(spellName, unit, unitName, preset, visibleBuffs)
    if not unit or not unitName then
        return false;
    end

    -- Check if spell is castable
    if not CanCastSpell(spellName) then
        return false;
    end

    -- Get spell ID based on rank setting
    local spellIds = GetSpellIDs(spellName);
    local targetSpellId = nil;
    local targetRank = preset.spellRank or 0;

    if targetRank == 0 then
        -- Use highest rank
        local maxRank = 0;
        for rank, spellId in pairs(spellIds) do
            if rank > maxRank then
                maxRank = rank;
                targetSpellId = spellId;
            end
        end
    else
        -- Use specific rank
        targetSpellId = spellIds[targetRank];
    end

    if not targetSpellId then
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
    CastSpell(targetSpellId, BOOKTYPE_SPELL);

    -- Setup GCD success detection (from AUTO-REJU macro pattern)
    if not GCDFrame then
        GCDFrame = CreateFrame("Frame");
    end

    GCDFrame.checkTime = GetTime() + 0.3;
    GCDFrame.targetName = unitName;
    GCDFrame.spellName = spellName;
    GCDFrame.blockTime = preset.blockTime or 0;
    GCDFrame.cooldown = preset.cooldown or 0;
    GCDFrame.visibleBuffs = visibleBuffs or {};
    GCDFrame.requiresBuff = preset.requiresBuff or "";

    GCDFrame:SetScript("OnUpdate", function()
        if GetTime() >= GCDFrame.checkTime then
            -- Check if GCD is active (using spell slot 154 as reliable indicator from macro)
            local start, duration = GetSpellCooldown(154, BOOKTYPE_SPELL);
            local gcdRemaining = 0;
            if start and duration and duration > 0 then
                gcdRemaining = (start + duration) - GetTime();
            end

            if gcdRemaining > 0 then
                -- Cast succeeded!

                -- Check if this is a consume spell (has requiresBuff)
                if GCDFrame.requiresBuff and GCDFrame.requiresBuff ~= "" then
                    -- CONSUME SPELL - handle blacklist clearing

                    -- Update cooldown for this spell
                    UpdateSpellCooldown(GCDFrame.spellName, GCDFrame.cooldown);

                    -- Determine which buffs to clear
                    if table.getn(GCDFrame.visibleBuffs) == 0 then
                        -- No buffs were visible (optimistic cast succeeded)
                        -- Clear ALL required buff blacklists
                        for buffName in string.gfind(GCDFrame.requiresBuff, "[^,]+") do
                            local trimmed = string.gsub(buffName, "^%s*(.-)%s*$", "%1");
                            ClearTargetBlacklist(GCDFrame.targetName, trimmed);
                        end
                    else
                        -- Some buffs were visible - clear only those
                        for _, buffName in ipairs(GCDFrame.visibleBuffs) do
                            ClearTargetBlacklist(GCDFrame.targetName, buffName);
                        end
                    end
                else
                    -- NORMAL BUFF SPELL - update blacklist for this spell
                    UpdateTargetBlacklist(GCDFrame.targetName, GCDFrame.spellName, GCDFrame.blockTime);
                end
            end

            -- Clean up
            GCDFrame:SetScript("OnUpdate", nil);
            GCDFrame.checkTime = nil;
            GCDFrame.targetName = nil;
            GCDFrame.spellName = nil;
            GCDFrame.blockTime = nil;
            GCDFrame.cooldown = nil;
            GCDFrame.visibleBuffs = nil;
            GCDFrame.requiresBuff = nil;
        end
    end);

    -- Restore old target
    if oldTarget then
        TargetByName(oldTarget);
    end

    return true;
end

-- Main healing function with chained preset support
function AutoHeal_Cast(...)
    -- Handle both old style (single preset) and new style (multiple presets)
    local presetNames = {};

    if arg.n == 0 then
        -- No arguments, show help
        writeLine("AutoHeal: No preset specified. Use /autoheal <preset1> [preset2] ...");
        return;
    else
        -- Collect all preset names from arguments
        for i = 1, arg.n do
            if arg[i] and arg[i] ~= "" then
                table.insert(presetNames, arg[i]);
            end
        end
    end

    -- Check GCD first - if on cooldown, don't try anything
    local start, duration = GetSpellCooldown(154, BOOKTYPE_SPELL);
    if start > 0 and (GetTime() - start) < duration then
        return;
    end

    -- Try each preset in order (priority chain)
    for _, presetName in ipairs(presetNames) do
        local preset = AHV.Presets[presetName];

        if not preset then
            writeLine("AutoHeal: Preset not found: " .. presetName);
        else
            -- Check if spell is on cooldown
            if IsSpellOnCooldown(preset.spell, preset.cooldown or 0) then
                -- Skip this preset, try next one
            else
                -- Find all potential targets for this preset
                local targets = FindAllHealTargets(preset);

                -- If targets found, try to cast
                if targets and table.getn(targets) > 0 then
                    -- Loop through targets and try to cast on each one
                    for _, targetInfo in targets do
                        if CastSpellOnTarget(preset.spell, targetInfo.unit, targetInfo.name, preset, targetInfo.visibleBuffs) then
                            -- Cast succeeded! Stop trying other presets
                            return;
                        end
                    end
                end

                -- No valid targets for this preset, continue to next preset
            end
        end
    end

    -- If we get here, no presets had valid targets
    -- Return silently to allow macro to continue
end

--[ UI Functions ]--

-- Current selected preset in UI
local SelectedPreset = nil;
local PresetListItems = {};

-- Create preset list items (text-based, not buttons)
local function CreatePresetList()
    local yOffset = 8;
    local itemNum = 1;

    -- Clear old items
    for _, itemData in pairs(PresetListItems) do
        if itemData.fontString then
            itemData.fontString:Hide();
        end
        if itemData.button then
            itemData.button:Hide();
        end
    end
    PresetListItems = {};

    -- Create text item for each preset
    for name, _ in pairs(AHV.Presets) do
        local item = AutoHealConfigFramePresetListFrame:CreateFontString("AutoHealPresetItem" .. itemNum, "OVERLAY", "GameFontNormal");
        item:SetPoint("TOPLEFT", 10, -yOffset);
        item:SetText(name);
        item:SetJustifyH("LEFT");
        item:SetWidth(140);

        -- Make it clickable
        local button = CreateFrame("Button", nil, AutoHealConfigFramePresetListFrame);
        button:SetAllPoints(item);
        button.presetName = name;
        button.fontString = item;
        button:SetScript("OnClick", function()
            AutoHeal_SelectPreset(this.presetName);
        end);
        button:SetScript("OnEnter", function()
            this.fontString:SetTextColor(1, 1, 0);
        end);
        button:SetScript("OnLeave", function()
            if SelectedPreset == this.presetName then
                this.fontString:SetTextColor(0, 1, 0);
            else
                this.fontString:SetTextColor(1, 1, 1);
            end
        end);

        -- Highlight if selected
        if SelectedPreset == name then
            item:SetTextColor(0, 1, 0);
        else
            item:SetTextColor(1, 1, 1);
        end

        table.insert(PresetListItems, {fontString = item, button = button});
        yOffset = yOffset + 18;
        itemNum = itemNum + 1;
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
        AutoHealConfigFrameCooldownEdit:SetText(tostring(preset.cooldown or 0));
        AutoHealConfigFrameSelfThresholdEdit:SetText(tostring(preset.selfPreservationThreshold or 60));
        AutoHealConfigFrameSpellRankEdit:SetText(tostring(preset.spellRank or 0));
        AutoHealConfigFrameRequiresBuffEdit:SetText(preset.requiresBuff or "");

        -- Set checkbox state
        if preset.selfPreservationEnabled then
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(1);
        else
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(nil);
        end

        -- Update list highlighting
        for _, listItem in pairs(PresetListItems) do
            if listItem.button.presetName == name then
                listItem.fontString:SetTextColor(0, 1, 0);  -- Green for selected
            else
                listItem.fontString:SetTextColor(1, 1, 1);  -- White for others
            end
        end
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
    preset.cooldown = tonumber(AutoHealConfigFrameCooldownEdit:GetText()) or 0;
    preset.spellRank = tonumber(AutoHealConfigFrameSpellRankEdit:GetText()) or 0;

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

    -- Get requires buff field
    local requiresBuffText = AutoHealConfigFrameRequiresBuffEdit:GetText();
    preset.requiresBuff = (requiresBuffText and requiresBuffText ~= "") and requiresBuffText or "";

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
                    -- Create new preset with defaults
                    AHV.Presets[name] = {
                        name = name,
                        spell = DAHV.PresetDefaults.spell,
                        spellRank = DAHV.PresetDefaults.spellRank,
                        healthThreshold = DAHV.PresetDefaults.healthThreshold,
                        blockTime = DAHV.PresetDefaults.blockTime,
                        cooldown = DAHV.PresetDefaults.cooldown,
                        maxRange = DAHV.PresetDefaults.maxRange,
                        selfPreservationThreshold = DAHV.PresetDefaults.selfPreservationThreshold,
                        selfPreservationEnabled = DAHV.PresetDefaults.selfPreservationEnabled,
                        requiresBuff = DAHV.PresetDefaults.requiresBuff
                    };
                    AutoHealVariables.Presets[name] = AHV.Presets[name];
                    CreatePresetList();
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
            CreatePresetList();
            AutoHealConfigFrameCurrentPreset:SetText("Select a preset");
            AutoHealConfigFrameSpellEdit:SetText("");
            AutoHealConfigFrameHealthEdit:SetText("");
            AutoHealConfigFrameBlockEdit:SetText("");
            AutoHealConfigFrameRangeEdit:SetText("");
            AutoHealConfigFrameCooldownEdit:SetText("");
            AutoHealConfigFrameSelfThresholdEdit:SetText("");
            AutoHealConfigFrameSpellRankEdit:SetText("");
            AutoHealConfigFrameSelfPreservationCheck:SetChecked(nil);
            AutoHealConfigFrameRequiresBuffEdit:SetText("");
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
    SetupEditBox(AutoHealConfigFrameCooldownEdit);
    SetupEditBox(AutoHealConfigFrameSelfThresholdEdit);
    SetupEditBox(AutoHealConfigFrameSpellRankEdit);
    SetupEditBox(AutoHealConfigFrameRequiresBuffEdit);
end

-- Config frame OnShow
function AutoHeal_ConfigOnShow()
    CreatePresetList();
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
        return;
    end

    if cmdLower == "delete all" then
        StaticPopupDialogs["AUTOHEAL_DELETE_ALL"] = {
            text = "Delete ALL presets and reset AutoHeal to clean state?",
            button1 = "Delete All",
            button2 = "Cancel",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                AHV.Presets = {};
                AutoHealVariables.Presets = {};
                SelectedPreset = nil;
                TargetStates = {};
                SpellCooldowns = {};
                if AutoHealConfigFrame and AutoHealConfigFrame:IsVisible() then
                    CreatePresetList();
                    AutoHealConfigFrameCurrentPreset:SetText("Select a preset");
                    AutoHealConfigFrameSpellEdit:SetText("");
                    AutoHealConfigFrameHealthEdit:SetText("");
                    AutoHealConfigFrameBlockEdit:SetText("");
                    AutoHealConfigFrameRangeEdit:SetText("");
                    AutoHealConfigFrameCooldownEdit:SetText("");
                    AutoHealConfigFrameSelfThresholdEdit:SetText("");
                    AutoHealConfigFrameSpellRankEdit:SetText("");
                    AutoHealConfigFrameSelfPreservationCheck:SetChecked(nil);
                    AutoHealConfigFrameRequiresBuffEdit:SetText("");
                end
                writeLine("AutoHeal: All configuration deleted. Fresh start!");
            end,
        };
        StaticPopup_Show("AUTOHEAL_DELETE_ALL");
        return;
    end

    -- Parse multiple preset names from command
    local presetNames = {};
    local words = {};

    -- Split by spaces
    for word in string.gfind(cmd, "%S+") do
        table.insert(words, word);
    end

    if table.getn(words) == 0 then
        -- No arguments - show help
        writeLine("AutoHeal Usage:");
        writeLine("/autoheal config - Open configuration window");
        writeLine("/autoheal <preset1> [preset2] ... - Cast using preset chain");
        writeLine("/autoheal delete all - Delete all presets and reset");
        writeLine("Example: /autoheal swift reju");
        if next(AHV.Presets) then
            writeLine("");
            writeLine("Available presets:");
            for name, _ in pairs(AHV.Presets) do
                writeLine("  " .. name);
            end
        else
            writeLine("");
            writeLine("No presets created yet. Use /autoheal config to create.");
        end
        return;
    end

    -- Try to find each word as a preset (case-insensitive)
    local foundAny = false;
    for _, word in ipairs(words) do
        local presetName = FindPreset(word);
        if presetName then
            table.insert(presetNames, presetName);
            foundAny = true;
        else
            writeLine("AutoHeal: Preset not found: " .. word);
        end
    end

    if foundAny then
        -- Call with all found presets
        AutoHeal_Cast(unpack(presetNames));
    else
        -- Show help
        writeLine("AutoHeal Usage:");
        writeLine("/autoheal config - Open configuration window");
        writeLine("/autoheal <preset1> [preset2] ... - Cast using preset chain");
        writeLine("/autoheal delete all - Delete all presets and reset");
        writeLine("Example: /autoheal swift reju");
        writeLine("");
        writeLine("Available presets:");
        for name, _ in pairs(AHV.Presets) do
            writeLine("  " .. name);
        end
    end
end

-- Initialize addon
local function InitializeAddon()
    -- Load saved variables or defaults
    if not AutoHealVariables or type(AutoHealVariables) ~= "table" then
        AutoHealVariables = {};
    end

    -- Initialize presets (empty by default)
    if not AutoHealVariables.Presets then
        AutoHealVariables.Presets = {};
    end

    -- Migrate old presets to new format (add missing fields)
    for k, preset in pairs(AutoHealVariables.Presets) do
        -- Remove old spellType field (no longer used)
        preset.spellType = nil;

        if preset.requiresBuff == nil then
            preset.requiresBuff = "";
        end
        if preset.cooldown == nil then
            preset.cooldown = 0;
        end
        if preset.spellRank == nil then
            preset.spellRank = 0;
        end
    end

    -- Set runtime config
    AHV.Presets = AutoHealVariables.Presets;

    writeLine("AutoHeal loaded. Type /autoheal config to create presets.");
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
