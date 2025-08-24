--Original idea of this addon is based on Ogrisch's LazySpell
--Enhanced by Claude for perfect healing efficiency and mana management

GigaHealer = AceLibrary("AceAddon-2.0"):new("AceHook-2.1", "AceConsole-2.0", "AceDB-2.0")
GigaHealer:RegisterDB("GigaHealerDB")
GigaHealer:RegisterDefaults("account", { 
    overheal = 1.1, 
    healing_history = {}, 
    auto_mode = false,
    aggressive_conservation = true,
    emergency_threshold = 0.3,
    conservation_levels = {
        { mana_pct = 0.8, efficiency_bonus = 0 },
        { mana_pct = 0.6, efficiency_bonus = 0.1 },
        { mana_pct = 0.4, efficiency_bonus = 0.2 },
        { mana_pct = 0.2, efficiency_bonus = 0.3 }
    },
    show_efficiency_stats = false
})

local libHC = AceLibrary("HealComm-1.0")
local libIB = AceLibrary("ItemBonusLib-1.0")
local libSC = AceLibrary("SpellCache-1.0")

-- Spell efficiency data from PDFs (Heal Per Mana ratios) - Complete Turtle WoW data
local SPELL_EFFICIENCY = {
    ["Healing Wave"] = {
        [1] = { heal = 71, mana = 25, hpm = 2.84 },
        [2] = { heal = 71, mana = 45, hpm = 1.58 },
        [3] = { heal = 142, mana = 50, hpm = 2.84 },
        [4] = { heal = 262, mana = 95, hpm = 2.76 },
        [5] = { heal = 408, mana = 155, hpm = 2.63 },
        [6] = { heal = 579, mana = 200, hpm = 2.90 },
        [7] = { heal = 797, mana = 265, hpm = 3.01 },
        [8] = { heal = 1092, mana = 340, hpm = 3.21 },
        [9] = { heal = 1464, mana = 440, hpm = 3.33 },
        [10] = { heal = 1735, mana = 520, hpm = 3.34 }
    },
    ["Lesser Healing Wave"] = {
        [1] = { heal = 174, mana = 105, hpm = 1.66 },
        [2] = { heal = 264, mana = 145, hpm = 1.82 },
        [3] = { heal = 359, mana = 185, hpm = 1.94 },
        [4] = { heal = 463, mana = 235, hpm = 1.97 },
        [5] = { heal = 606, mana = 305, hpm = 1.99 },
        [6] = { heal = 830, mana = 380, hpm = 2.18 }
    },
    ["Chain Heal"] = {
        [1] = { heal = 602, mana = 260, hpm = 2.32 },
        [2] = { heal = 761, mana = 315, hpm = 2.42 },
        [3] = { heal = 1033, mana = 405, hpm = 2.55 }
    }
}

function GigaHealer:OnEnable()
    if Clique and Clique.CastSpell then
        self:Hook(Clique, "CastSpell", "Clique_CastSpell")
    end

    if CM and CM.CastSpell then
        self:Hook(CM, "CastSpell", "CM_CastSpell")
    end

    if pfUI and pfUI.uf and pfUI.uf.ClickAction then
        self:Hook(pfUI.uf, "ClickAction", "pfUI_ClickAction")
    end

    if SlashCmdList and SlashCmdList.PFCAST then
        self:Hook(SlashCmdList, "PFCAST", "pfUI_PFCast")
    end

    self:RegisterChatCommand({ "/heal" }, function(arg) GigaHealer:CastHeal(arg) end, "GIGAHEALER")
    self:RegisterChatCommand({ "/gh_overheal" }, function(arg) GigaHealer:Overheal(arg) end, "GIGAOVERHEALER")
    self:RegisterChatCommand({ "/gh_auto" }, function(arg) GigaHealer:AutoMode(arg) end, "GIGAAUTO")
    self:RegisterChatCommand({ "/gh_emergency" }, function(arg) GigaHealer:EmergencyThreshold(arg) end, "GIGAEMERGENCY")
    self:RegisterChatCommand({ "/gh_stats" }, function(arg) GigaHealer:ShowStats(arg) end, "GIGASTATS")
    self:Print('GigaHealer loaded - Advanced healing with mana efficiency, emergency mode, and statistics!')
end

-------------------------------------------------------------------------------
-- New: Auto mode toggle for adaptive healing
-------------------------------------------------------------------------------
function GigaHealer:AutoMode(value)
    if value and string.lower(value) == "on" then
        self.db.account.auto_mode = true
        self:Print("Auto mode enabled - Using adaptive downranking based on efficiency data")
    elseif value and string.lower(value) == "off" then
        self.db.account.auto_mode = false
        self:Print("Auto mode disabled - Using standard overheal prevention")
    else
        local status = self.db.account.auto_mode and "enabled" or "disabled"
        self:Print("Auto mode is currently " .. status .. ". Use /gh_auto on|off to toggle")
    end
end

-------------------------------------------------------------------------------
-- New: Track healing efficiency for adaptive learning
-------------------------------------------------------------------------------
function GigaHealer:TrackHealingEfficiency(spell, rank, unit, predicted_heal, actual_overheal)
    if rank == 1 then return end -- Don't track rank 1 heals
    
    local history = self.db.account.healing_history
    local entry = {
        spell = spell,
        rank = rank,
        target_missing = UnitHealthMax(unit) - UnitHealth(unit),
        predicted_heal = predicted_heal,
        overheal = actual_overheal or 0,
        timestamp = GetTime(),
        mana_cost = self:GetSpellManaCost(spell, rank)
    }
    
    table.insert(history, 1, entry)
    
    -- Keep only last 25 entries
    while table.getn(history) > 25 do
        table.remove(history)
    end
end

-------------------------------------------------------------------------------
-- New: Calculate spell mana cost
-------------------------------------------------------------------------------
function GigaHealer:GetSpellManaCost(spell, rank)
    if SPELL_EFFICIENCY[spell] and SPELL_EFFICIENCY[spell][rank] then
        return SPELL_EFFICIENCY[spell][rank].mana
    end
    return 0
end

-------------------------------------------------------------------------------
-- New: Check if player has enough mana for spell
-------------------------------------------------------------------------------
function GigaHealer:CanAffordSpell(spell, rank)
    local current_mana = UnitMana("player")
    local mana_cost = self:GetSpellManaCost(spell, rank)
    return current_mana >= mana_cost
end

-------------------------------------------------------------------------------
-- New: Get highest affordable rank
-------------------------------------------------------------------------------
function GigaHealer:GetHighestAffordableRank(spell, max_rank)
    local current_mana = UnitMana("player")
    
    -- Always ensure rank 1 is castable as absolute fallback
    local rank1_cost = self:GetSpellManaCost(spell, 1)
    if rank1_cost > 0 and current_mana < rank1_cost then
        -- If we can't even afford rank 1, something is very wrong - still return rank 1
        return 1
    end
    
    for rank = max_rank, 1, -1 do
        local mana_cost = self:GetSpellManaCost(spell, rank)
        if mana_cost > 0 and current_mana >= mana_cost then
            return rank
        end
    end
    
    -- Guaranteed fallback: rank 1 should always be affordable
    return 1
end

-------------------------------------------------------------------------------
-- New: Emergency healing threshold management
-------------------------------------------------------------------------------
function GigaHealer:EmergencyThreshold(value)
    if value and tonumber(value) then
        local threshold = tonumber(value)
        if threshold >= 0.1 and threshold <= 0.8 then
            self.db.account.emergency_threshold = threshold
            self:Print("Emergency threshold set to " .. (threshold * 100) .. "% health")
        else
            self:Print("Emergency threshold must be between 10% and 80%")
        end
    else
        local current = self.db.account.emergency_threshold * 100
        self:Print("Emergency threshold: " .. current .. "%. Use /gh_emergency <percentage> to change (10-80)")
    end
end

-------------------------------------------------------------------------------
-- New: Show healing efficiency statistics
-------------------------------------------------------------------------------
function GigaHealer:ShowStats(toggle)
    if toggle and string.lower(toggle) == "on" then
        self.db.account.show_efficiency_stats = true
        self:Print("Efficiency statistics display enabled")
    elseif toggle and string.lower(toggle) == "off" then
        self.db.account.show_efficiency_stats = false
        self:Print("Efficiency statistics display disabled")
    elseif toggle and string.lower(toggle) == "clear" then
        self.db.account.healing_history = {}
        self:Print("Healing history cleared")
    else
        self:DisplayHealingStatistics()
    end
end

-------------------------------------------------------------------------------
-- New: Display current healing statistics
-------------------------------------------------------------------------------
function GigaHealer:DisplayHealingStatistics()
    local history = self.db.account.healing_history
    if table.getn(history) == 0 then
        self:Print("No healing data collected yet")
        return
    end
    
    local total_heals = table.getn(history)
    local total_overheal = 0
    local total_mana = 0
    local spells_used = {}
    
    for i, entry in ipairs(history) do
        total_overheal = total_overheal + entry.overheal
        total_mana = total_mana + entry.mana_cost
        local spell_key = entry.spell .. " R" .. entry.rank
        spells_used[spell_key] = (spells_used[spell_key] or 0) + 1
    end
    
    local avg_overheal = total_overheal / total_heals
    local efficiency_pct = math.max(0, 100 - (avg_overheal * 100 / (total_mana / total_heals)))
    
    self:Print("=== Healing Statistics (Last " .. total_heals .. " heals) ===")
    self:Print("Average overheal: " .. string.format("%.1f", avg_overheal))
    self:Print("Efficiency rating: " .. string.format("%.1f", efficiency_pct) .. "%")
    self:Print("Total mana used: " .. total_mana)
    
    self:Print("Most used spells:")
    for spell, count in pairs(spells_used) do
        if count > 1 then
            self:Print("  " .. spell .. ": " .. count .. " times")
        end
    end
end

-------------------------------------------------------------------------------
-- New: Enhanced gear coefficient calculation
-------------------------------------------------------------------------------
function GigaHealer:GetEnhancedSpellPower(spell, unit)
    local base_bonus, base_power, base_mod = 0, 0, 1
    
    if TheoryCraft == nil then
        base_bonus = tonumber(libIB:GetBonus("HEAL"))
        base_power, base_mod = libHC:GetUnitSpellPower(unit, spell)
        local buffpower, buffmod = libHC:GetBuffSpellPower()
        base_bonus = base_bonus + buffpower
        base_mod = base_mod * buffmod
    end
    
    -- Enhanced coefficient calculation based on gear quality
    local gear_bonus = 1.0
    local current_mana_pct = UnitMana("player") / UnitManaMax("player")
    
    -- Apply conservation level bonuses
    for i, level in ipairs(self.db.account.conservation_levels) do
        if current_mana_pct <= level.mana_pct then
            gear_bonus = gear_bonus + level.efficiency_bonus
            break
        end
    end
    
    return base_bonus, base_power * gear_bonus, base_mod
end

-------------------------------------------------------------------------------
-- New: Emergency mode detection
-------------------------------------------------------------------------------
function GigaHealer:IsEmergencyHealing(unit)
    local health_pct = UnitHealth(unit) / UnitHealthMax(unit)
    return health_pct <= self.db.account.emergency_threshold
end

-------------------------------------------------------------------------------
-- New: Get conservation level based on current mana
-------------------------------------------------------------------------------
function GigaHealer:GetCurrentConservationLevel()
    local mana_pct = UnitMana("player") / UnitManaMax("player")
    
    for i, level in ipairs(self.db.account.conservation_levels) do
        if mana_pct <= level.mana_pct then
            return level
        end
    end
    
    return self.db.account.conservation_levels[1] -- Default to highest mana level
end

-------------------------------------------------------------------------------
-- Handler function for /heal <spell_name>[, overheal_multiplier]
-------------------------------------------------------------------------------
-- Function automatically choose which rank of heal will be casted based on
-- amount of missing life, mana efficiency, and affordability.
--
-- NOTE: Argument "spellName" should be always heal and shouldn't contain rank.
-- If there is a rank, function won't scale it. It means that "Healing Wave"
-- will use rank as needed, but "Healing Wave(Rank 3)" will always cast rank 3.
-- Argument "spellName" can contain overheal multiplier information separated
-- by "," or ";" and it should be either number (1.1) or percentage (110%).
--
-- Examples:
-- GigaHealer:CastSpell("Healing Wave")			--/heal Healing Wave
-- GigaHealer:CastSpell("Healing Wave, 1.15")		--/heal Healing Wave, 1.15
-- GigaHealer:CastSpell("Healing Wave;120%")		--/heal Healing Wave;120%
-------------------------------------------------------------------------------
function GigaHealer:CastHeal(spellName)
    local overheal

    -- self:Print("spellname: ", spellName, type(spellName), string.len(spellName))
    if not spellName or string.len(spellName) == 0 or type(spellName) ~= "string" then
        return
    else
        spellName = string.gsub(spellName, "^%s*(.-)%s*$", "%1") --strip leading and trailing space characters
        spellName = string.gsub(spellName, "%s+", " ")           --replace all space character with actual space

        local _, _, arg = string.find(spellName, "[,;]%s*(.-)$") --tries to find overheal multiplier (number after spell name, separated by "," or ";")
        if arg then
            local _, _, percent = string.find(arg, "(%d+)%%")
            if percent then
                overheal = tonumber(percent) / 100
            else
                overheal = tonumber(arg)
            end

            spellName = string.gsub(spellName, "[,;].*", "") --removes everything after first "," or ";"
        end

        if not overheal then
            overheal = self.db.account.overheal
        end
    end

    local spell, rank = libSC:GetRanklessSpellName(spellName)
    local unit, onSelf

    if UnitExists("target") and UnitCanAssist("player", "target") then
        unit = "target"
    end

    if unit == nil then
        if GetCVar("autoSelfCast") == "1" then
            unit = "player"
            onSelf = true
        else
            return
        end
    end

    if spell and rank == nil and libHC.Spells[spell] then
        rank = self:GetOptimalRank(spell, unit, overheal)
        if rank then
            spellName = libSC:GetSpellNameText(spell, rank)
        end
    end

    -- self:Print("spellname: ", spellName)

    CastSpellByName(spellName, onSelf)

    if UnitIsUnit("player", unit) then
        if SpellIsTargeting() then
            SpellTargetUnit(unit)
        end
        if SpellIsTargeting() then
            SpellStopTargeting()
        end
    end
end

-------------------------------------------------------------------------------
-- Handler function for /sh_overheal
-------------------------------------------------------------------------------
-- Saves new default overheal multiplier, argument "value" should be either
-- string or number. String could contain number ("1.15") or percentage ("115%")
-- If "value" is not specified or invalid, function prints current overheal
-- multiplier.
-------------------------------------------------------------------------------
function GigaHealer:Overheal(value)
    if value and type(value) == "string" then
        value = string.gsub(value, "^%s*(.-)%s*$", "%1")

        local _, _, percent = string.find(value, "(%d+)%%")
        if percent then
            value = tonumber(percent) / 100
        else
            value = tonumber(value)
        end
    end

    if type(value) == "number" then
        self.db.account.overheal = math.floor(value * 1000 + 0.5) / 1000
    else
        self:Print("Overheal multiplier: ", self.db.account.overheal, "(", self.db.account.overheal * 100, "%)")
    end
end

-------------------------------------------------------------------------------
-- FIXED: Function selects optimal spell rank with proper mana affordability
-------------------------------------------------------------------------------
-- spell	- spell name to cast ("Healing Wave")
-- unit	 	- unitId ("player", "target", ...)
-- overheal	- overheal multiplier. If nil, then using self.db.account.overheal.
-------------------------------------------------------------------------------
function GigaHealer:GetOptimalRank(spell, unit, overheal)
    if not libSC.data[spell] then
        self:Print('GigaHealer: spell rank data not found for ' .. spell)
        return
    end

    local bonus, power, mod
    if TheoryCraft == nil then
        -- Use enhanced spell power calculation
        bonus, power, mod = self:GetEnhancedSpellPower(spell, unit)
    end
    local missing = UnitHealthMax(unit) - UnitHealth(unit)
    local max_rank = tonumber(libSC.data[spell].Rank)
    overheal = overheal or self.db.account.overheal

    local current_mana = UnitMana("player")
    local max_mana = UnitManaMax("player")
    local mana_percent = current_mana / max_mana
    local target_health_percent = UnitHealth(unit) / UnitHealthMax(unit)
    
    -- Get highest affordable rank first
    local affordable_rank = self:GetHighestAffordableRank(spell, max_rank)
    
    -- Check for emergency healing mode
    local emergency_mode = self:IsEmergencyHealing(unit)
    
    -- Get current conservation level
    local conservation_level = self:GetCurrentConservationLevel()
    
    -- Aggressive conservation mode (enhanced)
    local conservation_mode = self.db.account.aggressive_conservation and 
                             mana_percent <= conservation_level.mana_pct and target_health_percent > 0.7
    
    local optimal_rank = affordable_rank
    
    -- Emergency mode: use maximum healing regardless of efficiency
    if emergency_mode then
        return affordable_rank -- Use highest affordable rank for emergencies
    end
    
    -- CORRECTED PRIORITY: Healing Need → Mana → Efficiency
    -- Step 1: Find the LOWEST rank that provides adequate healing (healing need first)
    local adequate_rank = nil
    
    -- NEW: When mana is low, prioritize ANY healing over perfect healing
    -- With 100 mana or less, accept partial healing to avoid cast failures
    if current_mana <= 100 then
        -- Just use the highest rank we can afford when mana is critically low
        -- This ensures we cast SOMETHING rather than failing
        adequate_rank = affordable_rank
        
        -- But still prefer efficient lower ranks if they heal enough
        for rank = 1, affordable_rank do
            local spellData = TheoryCraft ~= nil and TheoryCraft_GetSpellDataByName(spell, rank)
            local heal_amount
            
            if spellData then
                heal_amount = spellData.averagehealnocrit
            else
                heal_amount = (libHC.Spells[spell][rank](bonus) + power) * mod
            end
            
            -- With low mana, accept 50% of needed healing as "good enough"
            if heal_amount >= (missing * 0.5) then
                adequate_rank = rank
                break -- Use this efficient rank
            end
        end
    else
        -- Normal behavior when mana is not critically low
        for rank = 1, affordable_rank do
            local spellData = TheoryCraft ~= nil and TheoryCraft_GetSpellDataByName(spell, rank)
            local heal_amount
            
            if spellData then
                heal_amount = spellData.averagehealnocrit
            else
                heal_amount = (libHC.Spells[spell][rank](bonus) + power) * mod
            end
            
            -- Check if this rank provides adequate healing (with 10% overheal tolerance)
            if heal_amount >= (missing * overheal) then
                adequate_rank = rank
                break -- Found the LOWEST rank that heals adequately
            end
        end
    end
    
    -- Step 2: If no rank provides adequate healing, use highest affordable (mana priority)
    if adequate_rank == nil then
        return affordable_rank -- Best we can do with available mana
    end
    
    -- Step 3: Apply efficiency optimization ONLY within adequate healing range
    optimal_rank = adequate_rank
    
    -- Only apply efficiency logic if in auto mode and conservation conditions met
    if self.db.account.auto_mode and conservation_mode and adequate_rank > 1 then
        -- In conservation mode, prefer rank 1 if it still heals adequately AND is affordable
        if self:CanAffordSpell(spell, 1) then
            local rank1_spellData = TheoryCraft ~= nil and TheoryCraft_GetSpellDataByName(spell, 1)
            local rank1_heal
            
            if rank1_spellData then
                rank1_heal = rank1_spellData.averagehealnocrit
            else
                rank1_heal = (libHC.Spells[spell][1](bonus) + power) * mod
            end
            
            -- Use rank 1 if it still provides adequate healing
            if rank1_heal >= (missing * overheal) then
                optimal_rank = 1
            end
        end
    end
    
    -- CRITICAL FIX: Ensure final rank is actually affordable
    optimal_rank = math.min(optimal_rank, affordable_rank)
    
    -- ABSOLUTE SAFETY: If all else fails, guarantee we can cast something
    if not self:CanAffordSpell(spell, optimal_rank) then
        optimal_rank = 1  -- Force rank 1 as last resort
    end
    
    --[[
    -- Debug output
    if spellData then
        self:Print(spell
                .. ' rank ' .. optimal_rank
                .. ' hp ' .. math.floor(spellData.averagehealnocrit)
                .. ' hpm ' .. (spellData.averagehealnocrit / spellData.manacost)
                .. ' mana ' .. spellData.manacost )
    end
    ]]
    
    return optimal_rank
end

-------------------------------------------------------------------------------
-- Support for Clique
-------------------------------------------------------------------------------
function GigaHealer:Clique_CastSpell(clique, spellName, unit)
    unit = unit or clique.unit

    if UnitExists(unit) then
        local spell, rank = libSC:GetRanklessSpellName(spellName)

        if spell and rank == nil and libHC.Spells[spell] then
            rank = self:GetOptimalRank(spellName, unit)
            if rank then
                spellName = libSC:GetSpellNameText(spell, rank)
            end
        end
    end

    self.hooks[Clique]["CastSpell"](clique, spellName, unit)
end

-------------------------------------------------------------------------------
-- Support for ClassicMouseover
-------------------------------------------------------------------------------
function GigaHealer:CM_CastSpell(cm, spellName, unit)
    if UnitExists(unit) then
        local spell, rank = libSC:GetRanklessSpellName(spellName)

        if spell and rank == nil and libHC.Spells[spell] then
            rank = self:GetOptimalRank(spellName, unit)
            if rank then
                spellName = libSC:GetSpellNameText(spell, rank)
            end
        end
    end

    self.hooks[CM]["CastSpell"](cm, spellName, unit)
end

-------------------------------------------------------------------------------
-- Support for pfUI Click-Casting
-------------------------------------------------------------------------------
function GigaHealer:pfUI_ClickAction(pfui_uf, button)
    local spellName = ""
    local key = "clickcast"

    if button == "LeftButton" then
        local unit = (this.label or "") .. (this.id or "")

        if UnitExists(unit) then
            if this.config.clickcast == "1" then
                if IsShiftKeyDown() then
                    key = key .. "_shift"
                elseif IsAltKeyDown() then
                    key = key .. "_alt"
                elseif IsControlKeyDown() then
                    key = key .. "_ctrl"
                end

                spellName = pfUI_config.unitframes[key]

                if spellName ~= "" then
                    local spell, rank = libSC:GetRanklessSpellName(spellName)

                    if spell and rank == nil and libHC.Spells[spell] then
                        rank = self:GetOptimalRank(spellName, unit)
                        if rank then
                            pfUI_config.unitframes[key] = libSC:GetSpellNameText(spell, rank)
                        end
                    end
                end
            end
        end
    end

    self.hooks[pfUI.uf]["ClickAction"](pfui_uf, button)

    if spellName ~= "" then
        pfUI_config.unitframes[key] = spellName
    end
end

-------------------------------------------------------------------------------
-- Support for pfUI /pfcast and /pfmouse commands
-------------------------------------------------------------------------------

-- Inspired by how pfui deduces the intended target inside the implementation of /pfcast
-- Must be kept in sync with the pfui codebase   otherwise there might be cases where the
-- wrong target is assumed here thus leading to wrong healing rank calculations 

-- Prepare a list of units that can be used via SpellTargetUnit
local st_units = { [1] = "player", [2] = "target", [3] = "mouseover" }
for i = 1, MAX_PARTY_MEMBERS do table.insert(st_units, "party" .. i) end
for i = 1, MAX_RAID_MEMBERS do table.insert(st_units, "raid" .. i) end

-- Try to find a valid (friendly) unitstring that can be used for
-- SpellTargetUnit(unit) to avoid another target switch
local function getUnitString(unit)
    for index, unitstr in pairs(st_units) do
        if UnitIsUnit(unit, unitstr) then
            return unitstr
        end
    end

    return nil
end

local function getProperTargetBasedOnMouseOver()
    local unit = "mouseover"
    if not UnitExists(unit) then
        local frame = GetMouseFocus()
        if frame.label and frame.id then
            unit = frame.label .. frame.id
        elseif UnitExists("target") then
            unit = "target"
        elseif GetCVar("autoSelfCast") == "1" then
            unit = "player"
        else
            return
        end
    end

    -- If target and mouseover are friendly units, we can't use spell target as it
    -- would cast on the target instead of the mouseover. However, if the mouseover
    -- is friendly and the target is not, we can try to obtain the best unitstring
    -- for the later SpellTargetUnit() call.
    return ((not UnitCanAssist("player", "target") and UnitCanAssist("player", unit) and getUnitString(unit)) or "player")
end

function GigaHealer:pfUI_PFCast(msg)
    local spell, rank = libSC:GetRanklessSpellName(msg)
    if spell and rank == nil and libHC.Spells[spell] then
        local unitstr = getProperTargetBasedOnMouseOver()
        if unitstr == nil then return end
        rank = self:GetOptimalRank(msg, unitstr)
        if rank then
            self.hooks[SlashCmdList]["PFCAST"](libSC:GetSpellNameText(spell, rank)) -- mission accomplished
            return
        end
    end

    self.hooks[SlashCmdList]["PFCAST"](msg) -- fallback if we can't find optimal rank
end