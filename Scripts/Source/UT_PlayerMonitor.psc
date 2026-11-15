Scriptname UT_PlayerMonitor extends ReferenceAlias

; ==============================
; Untamed Tomes - Player Monitor
; v1: basic magicka check + vanish
; ==============================

GlobalVariable Property UT_ModEnabled       Auto
GlobalVariable Property UT_DebugEnabled     Auto
GlobalVariable Property UT_MagickaThreshold Auto

Keyword       Property MagicTomeKeyword     Auto ; vanilla keyword on spell tomes
Keyword       Property VendorChestKeyword   Auto ; keyword on vendor chests
Keyword       Property UT_TomeSafe          Auto ; our custom "safe tome" keyword

Keyword Property LocTypeCity    Auto
Keyword Property LocTypeTown    Auto
Keyword Property LocTypeInn     Auto
Keyword Property LocTypeStore   Auto
Keyword Property LocTypeDungeon Auto

FormList      Property UT_TomeExclusions    Auto ; manual exclusion list

; Saved with the player alias script instance.
Int UT_BaselineLevel
Float UT_BaselineMagicSum
Bool UT_BaselineInitialized

Bool Function DebugOn()
    if UT_DebugEnabled == None
        return false
    endif
    return UT_DebugEnabled.GetValueInt() != 0
EndFunction

Float Function UT_GetMagicSkillSum(Actor player)
    Float magicSum = player.GetBaseActorValue("Destruction")
    magicSum += player.GetBaseActorValue("Conjuration")
    magicSum += player.GetBaseActorValue("Restoration")
    magicSum += player.GetBaseActorValue("Illusion")
    magicSum += player.GetBaseActorValue("Alteration")
    magicSum += player.GetBaseActorValue("Enchanting")
    return magicSum
EndFunction

Function UT_EnsureBaseline(Actor player)
    if player == None || UT_BaselineInitialized
        return
    endif

    UT_BaselineLevel = player.GetLevel()
    UT_BaselineMagicSum = UT_GetMagicSkillSum(player)
    UT_BaselineInitialized = true
EndFunction

Bool Function UT_IsClearlyNonMage(Actor player)
    if player == None || !UT_BaselineInitialized
        return false
    endif

    Int currentLevel = player.GetLevel()
    Float currentMagicSum = UT_GetMagicSkillSum(player)
    Int levelDelta = currentLevel - UT_BaselineLevel
    Float magicDelta = currentMagicSum - UT_BaselineMagicSum
    Bool isNonMage = levelDelta >= 3 && magicDelta <= 10.0

    if DebugOn()
        String msg = "Baseline level=" + UT_BaselineLevel + " magic sum=" + UT_BaselineMagicSum
        msg += " | Current level=" + currentLevel + " magic sum=" + currentMagicSum
        msg += " | Level delta=" + levelDelta + " Magic delta=" + magicDelta
        Debug.Trace("[UntamedTomes] Progression | " + msg + " | Non-mage=" + isNonMage)
    endif
    return isNonMage
EndFunction

Bool Function UT_IsBarterMenuOpen()
    ; Uses the built-in UI script: IsMenuOpen("BarterMenu")
    return UI.IsMenuOpen("BarterMenu")
EndFunction

Function Log(string msg)
    if DebugOn()
        Debug.Trace("[UntamedTomes] " + msg)
    endif
EndFunction

String Function UT_GetMenuSnapshot()
    return " menuMode=" + Utility.IsInMenuMode() + " inventory=" + UI.IsMenuOpen("InventoryMenu") \
        + " container=" + UI.IsMenuOpen("ContainerMenu") + " barter=" + UI.IsMenuOpen("BarterMenu")
EndFunction

String Function UT_GetTomeLocationContext()
    Actor player = GetReference() as Actor
    if player == None
        player = Game.GetPlayer()
    endif
    if player == None
        return "no-player"
    endif

    Location loc = player.GetCurrentLocation()
    if loc == None
        return "no-location" ; wilderness or unlinked cell
    endif

    ; Dungeon
    if LocTypeDungeon != None
        if loc.HasKeyword(LocTypeDungeon)
            return "dungeon"
        endif
    endif

    ; City / Town
    Bool isTownOrCity = false
    if LocTypeCity != None
        if loc.HasKeyword(LocTypeCity)
            isTownOrCity = true
        endif
    endif
    if !isTownOrCity && LocTypeTown != None
        if loc.HasKeyword(LocTypeTown)
            isTownOrCity = true
        endif
    endif
    if isTownOrCity
        return "town"
    endif

    ; Inn
    if LocTypeInn != None
        if loc.HasKeyword(LocTypeInn)
            return "inn"
        endif
    endif

    ; Store / shop
    if LocTypeStore != None
        if loc.HasKeyword(LocTypeStore)
            return "store"
        endif
    endif

    ; Fallback
    return "other"
EndFunction

String Function UT_GetPickupContext()
    ; 0) Trading menu open? Treat as safe, regardless of location.
    if UT_IsBarterMenuOpen()
        return "barter"
    endif

    return UT_GetTomeLocationContext()
EndFunction

Bool Function UT_IsSafeTomeContext(String ctx)
    return ctx == "barter" || ctx == "town" || ctx == "inn" || ctx == "store"
EndFunction


Event OnInit()
    Log("Player monitor initialized.")
EndEvent


Event OnItemAdded(Form akBaseItem, int aiCount, ObjectReference akItemRef, ObjectReference akSourceContainer)
    Bool debugPickup = DebugOn()
    Float enteredAt = 0.0
    if debugPickup
        enteredAt = Utility.GetCurrentRealTime()
    endif

    if UT_ModEnabled != None
        if UT_ModEnabled.GetValueInt() == 0
            return
        endif
    endif

    if akBaseItem == None || MagicTomeKeyword == None
        return
    endif
    if !akBaseItem.HasKeyword(MagicTomeKeyword)
        return
    endif

    String tracePrefix
    if debugPickup
        Float identifiedAt = Utility.GetCurrentRealTime()
        tracePrefix = "[UntamedTomes][Pickup entry=" + enteredAt + " item=" + akBaseItem + "] "
        Debug.Trace(tracePrefix + "identified at=" + identifiedAt + " elapsed=" + (identifiedAt - enteredAt) \
            + " count=" + aiCount + " ref=" + akItemRef + " source=" + akSourceContainer + UT_GetMenuSnapshot())
    endif

    UT_HandleTomePickup(akBaseItem, akItemRef, debugPickup, enteredAt, tracePrefix)

    if debugPickup
        Float probeStartedAt = Utility.GetCurrentRealTime()
        String probePrefix = tracePrefix + "metadata "
        Debug.Trace(probePrefix + "begin elapsed=" + (probeStartedAt - enteredAt))
        UT_InspectTome(akBaseItem, probePrefix)
        Debug.Trace(probePrefix + "end probeElapsed=" + (Utility.GetCurrentRealTime() - probeStartedAt))
    endif
EndEvent

Function UT_HandleTomePickup(Form akBaseItem, ObjectReference akItemRef, Bool debugPickup, Float enteredAt, String tracePrefix)
    String ctx = UT_GetPickupContext()
    Bool safe = UT_IsSafeTomeContext(ctx)
    if debugPickup
        Debug.Trace(tracePrefix + "context gate 1 elapsed=" + (Utility.GetCurrentRealTime() - enteredAt) + " context=" + ctx + " safe=" + safe)
    endif
    if safe
        if debugPickup
            Debug.Trace(tracePrefix + "decision=accept-safe-context")
        endif
        return
    endif

    if UT_TomeSafe != None
        if akBaseItem.HasKeyword(UT_TomeSafe)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-safe-keyword elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return
        endif
    endif

    ; Keep the second safety gate while measuring the existing pipeline.
    ctx = UT_GetPickupContext()
    safe = UT_IsSafeTomeContext(ctx)
    if debugPickup
        Debug.Trace(tracePrefix + "context gate 2 elapsed=" + (Utility.GetCurrentRealTime() - enteredAt) + " context=" + ctx + " safe=" + safe)
    endif
    if safe
        if debugPickup
            Debug.Trace(tracePrefix + "decision=accept-safe-context")
        endif
        return
    endif

    if UT_TomeExclusions != None
        if UT_TomeExclusions.HasForm(akBaseItem)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-exclusion elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return
        endif
    endif

    if akItemRef != None
        if PO3_SKSEFunctions.IsQuestItem(akItemRef)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-quest-reference elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return
        endif
    endif

    Actor player = GetReference() as Actor
    if player == None
        player = Game.GetPlayer()
    endif
    if player == None
        if debugPickup
            Debug.Trace(tracePrefix + "decision=abort-no-player elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
        endif
        return
    endif

    ; Observe progression without using the result for tome eligibility.
    UT_EnsureBaseline(player)
    UT_IsClearlyNonMage(player)

    Float threshold = 0.0
    if UT_MagickaThreshold != None
        threshold = UT_MagickaThreshold.GetValue()
    endif
    Float magicka = player.GetBaseActorValue("Magicka")
    Bool eligible = magicka >= threshold
    if debugPickup
        Debug.Trace(tracePrefix + "decision elapsed=" + (Utility.GetCurrentRealTime() - enteredAt) \
            + " eligible=" + eligible + " baseMagicka=" + magicka + " threshold=" + threshold)
    endif
    if eligible
        return
    endif

    Int invCount = player.GetItemCount(akBaseItem)
    if invCount <= 0
        if debugPickup
            Debug.Trace(tracePrefix + "removal=skipped-empty-inventory elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
        endif
        return
    endif

    String removalMenus
    Float beforeRemoval = 0.0
    if debugPickup
        removalMenus = UT_GetMenuSnapshot()
        beforeRemoval = Utility.GetCurrentRealTime()
    endif

    player.RemoveItem(akBaseItem, 1, true)

    if debugPickup
        Float afterRemoval = Utility.GetCurrentRealTime()
        Debug.Trace(tracePrefix + "before RemoveItem elapsed=" + (beforeRemoval - enteredAt) + " baseCount=" + invCount + removalMenus)
        Debug.Trace(tracePrefix + "after RemoveItem elapsed=" + (afterRemoval - enteredAt) \
            + " callElapsed=" + (afterRemoval - beforeRemoval) + UT_GetMenuSnapshot())
    endif
EndFunction

Int Function UT_GetTierIndex(Int minimumSkill)
    ; Only canonical effect minimum-skill values are supported.
    if minimumSkill < 0 || minimumSkill > 100 || minimumSkill % 25 != 0
        return -1
    endif
    return minimumSkill / 25
EndFunction

String Function UT_GetTierName(Int tier)
    if tier == 0
        return "Novice"
    elseif tier == 1
        return "Apprentice"
    elseif tier == 2
        return "Adept"
    elseif tier == 3
        return "Expert"
    elseif tier == 4
        return "Master"
    endif
    return "unresolved"
EndFunction

Bool Function UT_IsMagicSchool(String school)
    return school == "Alteration" || school == "Conjuration" || school == "Destruction" \
        || school == "Illusion" || school == "Restoration"
EndFunction

Float Function UT_Clamp(Float value, Float lower, Float upper)
    if value < lower
        return lower
    elseif value > upper
        return upper
    endif
    return value
EndFunction

Function UT_LogCompetence(Actor player, String school, Int tier, String prefix)
    if player == None
        Debug.Trace(prefix + "competence=unresolved reason=no-player")
        return
    endif

    Float magicka = player.GetBaseActorValue("Magicka")
    Float skill = player.GetBaseActorValue(school)
    Float contribution = UT_Clamp((magicka - 100.0) / 5.0, -10.0, 30.0)
    Float competence = UT_Clamp(skill, 0.0, 100.0) + contribution
    Float target = 15.0 + 20.0 * tier
    Float margin = competence - target
    String outcome = "safe"
    if margin < 0.0
        outcome = "unsafe"
    endif

    Debug.Trace(prefix + "baseMagicka=" + magicka + " baseSchoolSkill=" + skill + " magickaContribution=" + contribution \
        + " competence=" + competence + " target=" + target + " margin=" + margin + " predicted=" + outcome)
    if margin < 0.0
        Debug.Trace(prefix + "predictedSeverity=" + UT_Clamp(-margin / 40.0, 0.0, 1.0))
    endif
EndFunction

Function UT_InspectTome(Form baseItem, String prefix)
    Debug.Trace(prefix + "bookFormID=" + baseItem.GetFormID())
    Book tome = baseItem as Book
    if tome == None
        Debug.Trace(prefix + "status=unresolved reason=tagged-form-is-not-a-book")
        return
    endif

    Spell taughtSpell = tome.GetSpell()
    if taughtSpell == None
        Debug.Trace(prefix + "status=unresolved reason=no-taught-spell")
        return
    endif

    Int spellType = PO3_SKSEFunctions.GetSpellType(taughtSpell)
    Int effectCount = taughtSpell.GetNumEffects()
    Int baseCost = taughtSpell.GetMagickaCost()
    Perk halfCostPerk = taughtSpell.GetPerk()
    Debug.Trace(prefix + "spellFormID=" + taughtSpell.GetFormID() + " spellType=" + spellType \
        + " effectCount=" + effectCount + " baseCostRaw=" + baseCost)
    if halfCostPerk != None
        Debug.Trace(prefix + "halfCostPerkFormID=" + halfCostPerk.GetFormID())
    else
        Debug.Trace(prefix + "halfCostPerk=none")
    endif
    if baseCost < 0
        Debug.Trace(prefix + "baseCostStatus=invalid-or-unset")
    endif

    Int primaryIndex = -1
    if effectCount > 0
        primaryIndex = taughtSpell.GetCostliestEffectIndex()
        Debug.Trace(prefix + "costliestEffectIndex=" + primaryIndex)
        if primaryIndex == 0
            Debug.Trace(prefix + "costliestIndexNote=SKSE-also-returns-zero-when-no-costliest-effect-is-found")
        endif
    else
        Debug.Trace(prefix + "costliestEffectIndex=unavailable")
    endif

    String primarySchool
    Int primaryTier = -1
    Int primaryMinimumSkill
    Bool missingEffect = false
    Bool conflictingEffects = false
    String firstSchool
    Int firstMinimumSkill
    Bool foundEffect = false
    Int index = 0
    while index < effectCount
        MagicEffect effect = taughtSpell.GetNthEffectMagicEffect(index)
        if effect == None
            missingEffect = true
            Debug.Trace(prefix + "effectIndex=" + index + " status=missing-effect")
        else
            String school = effect.GetAssociatedSkill()
            Int minimumSkill = effect.GetSkillLevel()
            Debug.Trace(prefix + "effectIndex=" + index + " effectFormID=" + effect.GetFormID() \
                + " school=[" + school + "] minimumSkill=" + minimumSkill)
            if !foundEffect
                firstSchool = school
                firstMinimumSkill = minimumSkill
                foundEffect = true
            elseif school != firstSchool || minimumSkill != firstMinimumSkill
                conflictingEffects = true
            endif
            if index == primaryIndex
                primarySchool = school
                primaryMinimumSkill = minimumSkill
                primaryTier = UT_GetTierIndex(minimumSkill)
            endif
        endif
        index += 1
    endwhile

    Actor player = GetReference() as Actor
    if player == None
        player = Game.GetPlayer()
    endif
    if player != None && spellType == 0 && foundEffect && !missingEffect
        Int effectiveCost = taughtSpell.GetEffectiveMagickaCost(player)
        Debug.Trace(prefix + "effectiveCostRaw=" + effectiveCost)
        if effectiveCost < 0
            Debug.Trace(prefix + "effectiveCostStatus=invalid-or-unset")
        endif
    else
        Debug.Trace(prefix + "effectiveCost=unavailable reason=no-player-or-unsupported-spell-data")
    endif

    if spellType != 0
        Debug.Trace(prefix + "status=unresolved reason=unsupported-spell-type")
    elseif effectCount <= 0
        Debug.Trace(prefix + "status=unresolved reason=no-effects")
    elseif primaryIndex < 0 || primaryIndex >= effectCount
        Debug.Trace(prefix + "status=unresolved reason=invalid-costliest-index")
    elseif missingEffect
        Debug.Trace(prefix + "status=unresolved reason=missing-effect")
    elseif conflictingEffects
        Debug.Trace(prefix + "status=ambiguous reason=effects-disagree candidateSchool=[" + primarySchool \
            + "] candidateMinimumSkill=" + primaryMinimumSkill + " candidateTier=" + UT_GetTierName(primaryTier))
    elseif !UT_IsMagicSchool(primarySchool)
        Debug.Trace(prefix + "status=unresolved reason=unsupported-school school=[" + primarySchool + "]")
    elseif primaryTier < 0
        Debug.Trace(prefix + "status=unresolved reason=noncanonical-minimum-skill minimumSkill=" + primaryMinimumSkill)
    else
        Debug.Trace(prefix + "status=resolved school=" + primarySchool + " tier=" + UT_GetTierName(primaryTier))
        UT_LogCompetence(player, primarySchool, primaryTier, prefix)
    endif
EndFunction
