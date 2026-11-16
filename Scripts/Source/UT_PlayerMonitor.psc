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

; Implemented by UntamedTomesSKSE.dll. Records that this tome addition has been handled.
; Observation only: a no-op unless the native ObserveLedger experiment is selected.
Function UT_AcknowledgeTomeAddition(Form akBaseItem, Int aiCount, String asOutcome) global native

; Debug-only trap prototype. Enabled only by the UntamedTomes.DebugTrap marker file.
Bool Function UT_IsDebugTrapEnabled() global native
Function UT_ReportDebugTrap(Form akBaseItem, Int aiCount, String asOutcome) global native
; Selected effect: "none", "notify" (UntamedTomes.DebugTrap) or "fire" (UntamedTomes.FireTrap).
String Function UT_GetDefenseEffect() global native
Function UT_ReportDefense(Int aiId, Form akTome, String asStage, String asDetail) global native

; World tome eligibility handshake (Investigation 19). Active only with the
; UntamedTomes.WorldTomeHandshake or UntamedTomes.WorldTomeHandshakeAllTomes marker.
Bool Function UT_WorldTomeHandshakeReady() global native
String Function UT_AnswerWorldTomeRequest(Int aiRequestId, Int aiGeneration, ObjectReference akTome, String asOutcome) global native
Function UT_ReportWorldTome(Int aiRequestId, ObjectReference akTome, String asStage, String asDetail) global native
; True only for an addition bound to a forwarded authorised activation (Inv. 20). akItemRef is
; passed so a persistent reference matches only its own grant.
Bool Function UT_ConsumeWorldTomeGrant(Form akBaseItem, Int aiCount, ObjectReference akItemRef) global native

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
    UT_RegisterWorldTomeHandshake()
EndEvent

; Registered on every init and load. The native side ignores requests until it hears from here.
Function UT_RegisterWorldTomeHandshake()
    RegisterForModEvent("UT_WorldTomeRequest", "OnUTWorldTomeRequest")
    UT_WorldTomeHandshakeReady()
EndFunction

; A world tome activation was vetoed before pickup. numArg is the request id, strArg the generation,
; sender the world reference. Evaluates without touching inventory and answers the native side.
Event OnUTWorldTomeRequest(String asEventName, String asGeneration, Float afRequestId, Form akSender)
    Float receivedAt = Utility.GetCurrentRealTime()
    Int requestId = afRequestId as Int
    Int generation = asGeneration as Int
    ObjectReference tomeRef = akSender as ObjectReference
    UT_ReportWorldTome(requestId, tomeRef, "received", "generation=" + generation)
    String outcome = UT_EvaluateWorldTome(tomeRef)
    Float decidedAt = Utility.GetCurrentRealTime()
    String status = UT_AnswerWorldTomeRequest(requestId, generation, tomeRef, outcome)
    String timing = " outcome=" + outcome + " status=" + status + " evaluate_ms=" + ((decidedAt - receivedAt) * 1000.0) as Int
    ; Feedback only for an answer the native side applied, and only while the tome is still loaded
    ; (a late answer after a cell change or reload shows nothing).
    Bool present = false
    if tomeRef != None
        present = tomeRef.Is3DLoaded()
    endif
    if status == "rejected" && present
        UT_WorldTomeRefusal(requestId, tomeRef, receivedAt, timing)
    elseif status == "authorized" && present
        Debug.Notification("[Untamed Tomes] " + tomeRef.GetBaseObject().GetName() + " yields. Take it again.")
        UT_ReportWorldTome(requestId, tomeRef, "feedback", "kind=authorized notification=1" + timing \
            + " papyrus_ms=" + ((Utility.GetCurrentRealTime() - receivedAt) * 1000.0) as Int)
    elseif status == "unavailable" && present
        Debug.Notification("[Untamed Tomes] The tome cannot judge you right now. Try again.")
        UT_ReportWorldTome(requestId, tomeRef, "feedback", "kind=unavailable notification=1" + timing \
            + " papyrus_ms=" + ((Utility.GetCurrentRealTime() - receivedAt) * 1000.0) as Int)
    else
        UT_ReportWorldTome(requestId, tomeRef, "no_feedback", timing + " present=" + present)
    endif
EndEvent

; Never adds or removes items. Undecidable cases return "unavailable-*", which never authorises.
String Function UT_EvaluateWorldTome(ObjectReference akTome)
    if akTome == None
        return "unavailable-no-reference"
    endif
    Form base = akTome.GetBaseObject()
    if base == None || MagicTomeKeyword == None
        return "unavailable-no-base"
    endif
    if !base.HasKeyword(MagicTomeKeyword)
        return "unavailable-not-a-tome"
    endif
    if UT_ModEnabled != None
        if UT_ModEnabled.GetValueInt() == 0
            return "disabled"
        endif
    endif
    Bool debugWorld = DebugOn()
    Float enteredAt = 0.0
    String tracePrefix
    if debugWorld
        enteredAt = Utility.GetCurrentRealTime()
        tracePrefix = "[UntamedTomes][WorldTome ref=" + akTome + " item=" + base + "] "
    endif
    return UT_EvaluateTomeEligibility(base, akTome, debugWorld, enteredAt, tracePrefix)
EndFunction

; Rejection feedback on the world tome itself: a short vanilla shader pulse (EnchShockFXShader,
; Skyrim.esm 00059EDA, Inv. 05) when its 3D is loaded, and a notification. No damage, no movement.
Function UT_WorldTomeRefusal(Int aiRequestId, ObjectReference akTome, Float afReceivedAt, String asTiming)
    String shader = "skipped"
    EffectShader flash = Game.GetFormFromFile(0x00059EDA, "Skyrim.esm") as EffectShader
    if flash != None && akTome != None
        if akTome.Is3DLoaded()
            flash.Play(akTome, 0.6)
            shader = "played"
        else
            shader = "skipped-no-3d"
        endif
    elseif flash == None
        shader = "skipped-no-record"
    endif
    String tomeName = "The tome"
    if akTome != None
        tomeName = akTome.GetBaseObject().GetName()
    endif
    Debug.Notification("[Untamed Tomes] " + tomeName + " refuses you.")
    UT_ReportWorldTome(aiRequestId, akTome, "feedback", "kind=refusal shader=" + shader + " notification=1" + asTiming \
        + " papyrus_ms=" + ((Utility.GetCurrentRealTime() - afReceivedAt) * 1000.0) as Int)
EndFunction


Event OnItemAdded(Form akBaseItem, int aiCount, ObjectReference akItemRef, ObjectReference akSourceContainer)
    Bool debugPickup = DebugOn()
    Float enteredAt = 0.0
    if debugPickup
        enteredAt = Utility.GetCurrentRealTime()
    endif

    if akBaseItem == None || MagicTomeKeyword == None
        return
    endif
    if !akBaseItem.HasKeyword(MagicTomeKeyword)
        return
    endif

    ; Every tome addition is acknowledged exactly once, after its decision and any removal.
    if UT_ModEnabled != None
        if UT_ModEnabled.GetValueInt() == 0
            UT_AcknowledgeTomeAddition(akBaseItem, aiCount, "disabled")
            return
        endif
    endif

    ; The world tome handshake already evaluated and authorised this pickup: no second decision, no trap.
    if UT_ConsumeWorldTomeGrant(akBaseItem, aiCount, akItemRef)
        if debugPickup
            Debug.Trace("[UntamedTomes][Pickup item=" + akBaseItem + "] decision=accept-preauthorized")
        endif
        UT_AcknowledgeTomeAddition(akBaseItem, aiCount, "accept-preauthorized")
        return
    endif

    String tracePrefix
    if debugPickup
        Float identifiedAt = Utility.GetCurrentRealTime()
        tracePrefix = "[UntamedTomes][Pickup entry=" + enteredAt + " item=" + akBaseItem + "] "
        Debug.Trace(tracePrefix + "identified at=" + identifiedAt + " elapsed=" + (identifiedAt - enteredAt) \
            + " count=" + aiCount + " ref=" + akItemRef + " source=" + akSourceContainer + UT_GetMenuSnapshot())
    endif

    String outcome = UT_HandleTomePickup(akBaseItem, akItemRef, debugPickup, enteredAt, tracePrefix)
    UT_AcknowledgeTomeAddition(akBaseItem, aiCount, outcome)

    ; At most once per acquisition event, after the unchanged rejection and removal.
    if outcome == "reject-removed" || outcome == "reject-skipped-empty-inventory"
        UT_TriggerDefense(akBaseItem, aiCount, outcome)
    endif

    if debugPickup
        Float probeStartedAt = Utility.GetCurrentRealTime()
        String probePrefix = tracePrefix + "metadata "
        Debug.Trace(probePrefix + "begin elapsed=" + (probeStartedAt - enteredAt))
        UT_InspectTome(akBaseItem, probePrefix)
        Debug.Trace(probePrefix + "end probeElapsed=" + (Utility.GetCurrentRealTime() - probeStartedAt))
    endif
EndEvent

; ==============================
; Defensive effects (debug-only, Investigations 16-17)
; The trigger (UT_TriggerDefense) decides WHEN, the effect (UT_ActivateDefenseEffect) decides WHAT.
; New effects only add a branch to UT_ActivateDefenseEffect.
; State uses scalar slots: script arrays added to an existing save fail at runtime
; ("Cannot cast from None to Form[]"), observed in the Task 08 run.
; ==============================

Int UT_DefenseNextId
; Four deferred-defense slots (tome None = free).
Form UT_DQ0Tome
Form UT_DQ1Tome
Form UT_DQ2Tome
Form UT_DQ3Tome
Int UT_DQ0Id
Int UT_DQ1Id
Int UT_DQ2Id
Int UT_DQ3Id
Float UT_DQ0At
Float UT_DQ1At
Float UT_DQ2At
Float UT_DQ3At
Cell UT_DQ0Cell
Cell UT_DQ1Cell
Cell UT_DQ2Cell
Cell UT_DQ3Cell
String UT_DQ0Effect
String UT_DQ1Effect
String UT_DQ2Effect
String UT_DQ3Effect
; Four temporary casting markers awaiting cleanup.
ObjectReference UT_DM0
ObjectReference UT_DM1
ObjectReference UT_DM2
ObjectReference UT_DM3
Float UT_DM0At
Float UT_DM1At
Float UT_DM2At
Float UT_DM3At
; Hit verification for the most recent activation.
Int UT_DefenseAwaitId
Float UT_DefenseAwaitAt
Float UT_DefenseAwaitHealth
Form UT_DefenseAwaitSourceA
Form UT_DefenseAwaitSourceB
String UT_DefenseAwaitEffect

Float Function UT_DefenseExpirySeconds()
    return 30.0  ; Real seconds a deferred defense may wait for gameplay to resume.
EndFunction

Form Function UT_DQTome(Int i)
    if i == 0
        return UT_DQ0Tome
    elseif i == 1
        return UT_DQ1Tome
    elseif i == 2
        return UT_DQ2Tome
    endif
    return UT_DQ3Tome
EndFunction

Function UT_DQSet(Int i, Form akTome, Int aiId, Float afAt, Cell akCell, String asEffect)
    if i == 0
        UT_DQ0Tome = akTome
        UT_DQ0Id = aiId
        UT_DQ0At = afAt
        UT_DQ0Cell = akCell
        UT_DQ0Effect = asEffect
    elseif i == 1
        UT_DQ1Tome = akTome
        UT_DQ1Id = aiId
        UT_DQ1At = afAt
        UT_DQ1Cell = akCell
        UT_DQ1Effect = asEffect
    elseif i == 2
        UT_DQ2Tome = akTome
        UT_DQ2Id = aiId
        UT_DQ2At = afAt
        UT_DQ2Cell = akCell
        UT_DQ2Effect = asEffect
    else
        UT_DQ3Tome = akTome
        UT_DQ3Id = aiId
        UT_DQ3At = afAt
        UT_DQ3Cell = akCell
        UT_DQ3Effect = asEffect
    endif
EndFunction

Int Function UT_DQId(Int i)
    if i == 0
        return UT_DQ0Id
    elseif i == 1
        return UT_DQ1Id
    elseif i == 2
        return UT_DQ2Id
    endif
    return UT_DQ3Id
EndFunction

Float Function UT_DQAt(Int i)
    if i == 0
        return UT_DQ0At
    elseif i == 1
        return UT_DQ1At
    elseif i == 2
        return UT_DQ2At
    endif
    return UT_DQ3At
EndFunction

Cell Function UT_DQCell(Int i)
    if i == 0
        return UT_DQ0Cell
    elseif i == 1
        return UT_DQ1Cell
    elseif i == 2
        return UT_DQ2Cell
    endif
    return UT_DQ3Cell
EndFunction

String Function UT_DQEffect(Int i)
    if i == 0
        return UT_DQ0Effect
    elseif i == 1
        return UT_DQ1Effect
    elseif i == 2
        return UT_DQ2Effect
    endif
    return UT_DQ3Effect
EndFunction

ObjectReference Function UT_DM(Int i)
    if i == 0
        return UT_DM0
    elseif i == 1
        return UT_DM1
    elseif i == 2
        return UT_DM2
    endif
    return UT_DM3
EndFunction

Float Function UT_DMAt(Int i)
    if i == 0
        return UT_DM0At
    elseif i == 1
        return UT_DM1At
    elseif i == 2
        return UT_DM2At
    endif
    return UT_DM3At
EndFunction

Function UT_DMSet(Int i, ObjectReference akMarker, Float afAt)
    if i == 0
        UT_DM0 = akMarker
        UT_DM0At = afAt
    elseif i == 1
        UT_DM1 = akMarker
        UT_DM1At = afAt
    elseif i == 2
        UT_DM2 = akMarker
        UT_DM2At = afAt
    else
        UT_DM3 = akMarker
        UT_DM3At = afAt
    endif
EndFunction

Function UT_TriggerDefense(Form akTome, Int aiCount, String asOutcome)
    String effect = UT_GetDefenseEffect()
    if effect == "none" || effect == ""
        return
    endif
    UT_DefenseNextId += 1
    Int id = UT_DefenseNextId
    UT_ReportDefense(id, akTome, "triggered", "outcome=" + asOutcome + " effect=" + effect + " count=" + aiCount + UT_GetMenuSnapshot())
    if !Utility.IsInMenuMode()
        UT_ActivateDefenseEffect(id, akTome, effect, "immediate")
        return
    endif
    Int slot = 0
    while slot < 4 && UT_DQTome(slot) != None
        slot += 1
    endwhile
    if slot >= 4
        UT_ReportDefense(id, akTome, "cancelled", "reason=queue_full")
        return
    endif
    UT_DQSet(slot, akTome, id, Utility.GetCurrentRealTime(), Game.GetPlayer().GetParentCell(), effect)
    UT_ReportDefense(id, akTome, "deferred", "reason=menu_open slot=" + slot + " expiry_s=" + UT_DefenseExpirySeconds())
    RegisterForSingleUpdate(0.25)
EndFunction

; Non-blocking poll: fires deferred defenses once no menu is open, otherwise re-registers.
Event OnUpdate()
    Bool again = false
    Float now = Utility.GetCurrentRealTime()
    Actor player = Game.GetPlayer()
    Int i = 0
    while i < 4
        Form tome = UT_DQTome(i)
        if tome != None
            Float age = now - UT_DQAt(i)
            if age > UT_DefenseExpirySeconds()
                UT_CancelDefenseSlot(i, "reason=expired age_s=" + age)
            elseif player.GetParentCell() != UT_DQCell(i)
                UT_CancelDefenseSlot(i, "reason=location_changed")
            elseif UT_GetDefenseEffect() == "none"
                UT_CancelDefenseSlot(i, "reason=effect_disabled")
            elseif Utility.IsInMenuMode()
                again = true
            else
                Int id = UT_DQId(i)
                String effect = UT_DQEffect(i)
                UT_DQSet(i, None, 0, 0.0, None, "")
                UT_ActivateDefenseEffect(id, tome, effect, "deferred age_s=" + age)
                again = true
            endif
        endif
        ObjectReference marker = UT_DM(i)
        if marker != None
            if now - UT_DMAt(i) > 3.0
                marker.Delete()
                UT_DMSet(i, None, 0.0)
            else
                again = true
            endif
        endif
        i += 1
    endwhile
    if UT_DefenseAwaitId > 0
        if now - UT_DefenseAwaitAt > 3.0
            UT_ReportDefense(UT_DefenseAwaitId, None, "hit_not_observed", "effect=" + UT_DefenseAwaitEffect \
                + " waited_s=" + (now - UT_DefenseAwaitAt) + " health_delta=" + (player.GetActorValue("Health") - UT_DefenseAwaitHealth))
            UT_DefenseAwaitId = 0
        else
            again = true
        endif
    endif
    if again
        RegisterForSingleUpdate(0.25)
    endif
EndEvent

Function UT_CancelDefenseSlot(Int aiSlot, String asReason)
    UT_ReportDefense(UT_DQId(aiSlot), UT_DQTome(aiSlot), "cancelled", asReason)
    UT_DQSet(aiSlot, None, 0, 0.0, None, "")
EndFunction

; Pending defenses never survive a load: cancel and log them, and remove casting markers.
Event OnPlayerLoadGame()
    Int i = 0
    while i < 4
        if UT_DQTome(i) != None
            UT_CancelDefenseSlot(i, "reason=load")
        endif
        ObjectReference marker = UT_DM(i)
        if marker != None
            marker.Delete()
            UT_DMSet(i, None, 0.0)
        endif
        i += 1
    endwhile
    UT_DefenseAwaitId = 0
    UT_RegisterWorldTomeHandshake()
EndEvent

Function UT_ActivateDefenseEffect(Int aiId, Form akTome, String asEffect, String asTiming)
    if asEffect == "fire"
        UT_DefenseFireBolt(aiId, akTome, asTiming)
    elseif asEffect == "fire_burst"
        UT_DefenseFireBurst(aiId, akTome, asTiming)
    else
        UT_DefenseNotify(aiId, akTome, asTiming)
    endif
EndFunction

; Effect "notify": the Task 07 prototype. Harmless, no item changes.
Function UT_DefenseNotify(Int aiId, Form akTome, String asTiming)
    Debug.Notification("[Untamed Tomes debug trap] " + akTome.GetName() + " lashes out!")
    Game.ShakeCamera(None, 0.6, 0.6)
    UT_ReportDefense(aiId, akTome, "activated", "effect=notify timing=" + asTiming)
EndFunction

; Places a temporary XMarker (Skyrim.esm 0000003B) relative to the player and tracks it for cleanup.
ObjectReference Function UT_PlaceDefenseMarker(Float afForward, Float afUp)
    Form markerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
    Actor player = Game.GetPlayer()
    if markerBase == None
        return None
    endif
    ObjectReference marker = player.PlaceAtMe(markerBase, 1, false, false)
    if marker == None
        return None
    endif
    Float heading = player.GetAngleZ()
    marker.MoveTo(player, afForward * Math.Sin(heading), afForward * Math.Cos(heading), afUp)
    Int slot = 0
    while slot < 4 && UT_DM(slot) != None
        slot += 1
    endwhile
    if slot >= 4
        slot = 0
        UT_DM(0).Delete()
    endif
    UT_DMSet(slot, marker, Utility.GetCurrentRealTime())
    return marker
EndFunction

String Function UT_DescribeGeometry(ObjectReference akMarker)
    Actor player = Game.GetPlayer()
    return " marker_xyz=" + akMarker.GetPositionX() + "," + akMarker.GetPositionY() + "," + akMarker.GetPositionZ() \
        + " marker_angle=" + akMarker.GetAngleX() + "," + akMarker.GetAngleZ() \
        + " player_xyz=" + player.GetPositionX() + "," + player.GetPositionY() + "," + player.GetPositionZ() \
        + " player_heading=" + player.GetAngleZ() + " distance=" + akMarker.GetDistance(player) \
        + " marker_3d=" + akMarker.Is3DLoaded() + " cell=" + player.GetParentCell() + " interior=" + player.IsInInterior()
EndFunction

Function UT_AwaitDefenseHit(Int aiId, String asEffect, Form akSourceA, Form akSourceB)
    UT_DefenseAwaitId = aiId
    UT_DefenseAwaitAt = Utility.GetCurrentRealTime()
    UT_DefenseAwaitHealth = Game.GetPlayer().GetActorValue("Health")
    UT_DefenseAwaitSourceA = akSourceA
    UT_DefenseAwaitSourceB = akSourceB
    UT_DefenseAwaitEffect = asEffect
    RegisterForSingleUpdate(0.25)
EndFunction

; Experiment A, effect "fire": vanilla TrapFirebolt01 (Skyrim.esm 0007E56D, 15 trap fire damage)
; cast by a temporary XMarker 220 units ahead at chest height. Task 08 copied the player's
; heading onto the marker, so a facing-dependent cast would fly away from the player; the
; marker is now turned to face the player before casting.
Function UT_DefenseFireBolt(Int aiId, Form akTome, String asTiming)
    Spell bolt = Game.GetFormFromFile(0x0007E56D, "Skyrim.esm") as Spell
    ObjectReference marker = UT_PlaceDefenseMarker(220.0, 90.0)
    if bolt == None || marker == None
        UT_ReportDefense(aiId, akTome, "cancelled", "reason=records_or_source_unavailable fallback=notify")
        UT_DefenseNotify(aiId, akTome, asTiming)
        return
    endif
    Actor player = Game.GetPlayer()
    marker.SetAngle(0.0, 0.0, player.GetAngleZ() + 180.0)
    Debug.Notification("[Untamed Tomes debug trap] " + akTome.GetName() + " lashes out with fire!")
    UT_AwaitDefenseHit(aiId, "fire", bolt, None)
    bolt.Cast(marker, player)
    UT_ReportDefense(aiId, akTome, "cast_attempted", "effect=fire timing=" + asTiming + " spell=" + bolt + " source=" + marker \
        + " target=" + player + " health_before=" + UT_DefenseAwaitHealth + UT_DescribeGeometry(marker) + UT_GetMenuSnapshot())
EndFunction

; Experiment B, effect "fire_burst": vanilla TrapDweFlamePillarExplosion01 (Skyrim.esm 000E605E:
; 8 damage plus trap fire enchantment 000E605F, radius 50, force 0) placed at the player's
; position by a temporary XMarker. No projectile travel, so walls and aim cannot cause a miss.
Function UT_DefenseFireBurst(Int aiId, Form akTome, String asTiming)
    Form burst = Game.GetFormFromFile(0x000E605E, "Skyrim.esm")
    Form burstEnchantment = Game.GetFormFromFile(0x000E605F, "Skyrim.esm")
    ObjectReference marker = UT_PlaceDefenseMarker(0.0, 40.0)
    if burst == None || marker == None
        UT_ReportDefense(aiId, akTome, "cancelled", "reason=records_or_source_unavailable fallback=notify")
        UT_DefenseNotify(aiId, akTome, asTiming)
        return
    endif
    Actor player = Game.GetPlayer()
    Debug.Notification("[Untamed Tomes debug trap] " + akTome.GetName() + " erupts in flame!")
    UT_AwaitDefenseHit(aiId, "fire_burst", burst, burstEnchantment)
    ObjectReference placed = marker.PlaceAtMe(burst, 1, false, false)
    UT_ReportDefense(aiId, akTome, "cast_attempted", "effect=fire_burst timing=" + asTiming + " explosion=" + burst \
        + " placed=" + placed + " source=" + marker + " target=" + player + " health_before=" + UT_DefenseAwaitHealth \
        + UT_DescribeGeometry(marker) + UT_GetMenuSnapshot())
EndFunction

; Confirms a hit separately from the cast attempt. akSource may be the spell, the explosion or
; its enchantment; any other source during the window is logged as a hit from something else.
Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
    if UT_DefenseAwaitId <= 0
        return
    endif
    if akSource != None && (akSource == UT_DefenseAwaitSourceA || akSource == UT_DefenseAwaitSourceB)
        Actor player = Game.GetPlayer()
        UT_ReportDefense(UT_DefenseAwaitId, None, "hit_confirmed", "effect=" + UT_DefenseAwaitEffect + " source=" + akSource \
            + " aggressor=" + akAggressor + " projectile=" + akProjectile + " blocked=" + abHitBlocked \
            + " after_s=" + (Utility.GetCurrentRealTime() - UT_DefenseAwaitAt) \
            + " health_delta=" + (player.GetActorValue("Health") - UT_DefenseAwaitHealth))
        UT_DefenseAwaitId = 0
    else
        UT_ReportDefense(UT_DefenseAwaitId, None, "hit_other", "source=" + akSource + " aggressor=" + akAggressor)
    endif
EndEvent

; Returns the outcome for the acknowledgement. The decision is the shared one; only this
; post-acquisition path observes progression and removes the item.
String Function UT_HandleTomePickup(Form akBaseItem, ObjectReference akItemRef, Bool debugPickup, Float enteredAt, String tracePrefix)
    String decision = UT_EvaluateTomeEligibility(akBaseItem, akItemRef, debugPickup, enteredAt, tracePrefix)
    if decision != "accept-eligible" && decision != "reject-ineligible"
        return decision
    endif

    ; Observe progression without using the result for tome eligibility (reached exactly when the
    ; Magicka comparison was, as before the split).
    Actor player = GetReference() as Actor
    if player == None
        player = Game.GetPlayer()
    endif
    UT_EnsureBaseline(player)
    UT_IsClearlyNonMage(player)

    if decision == "accept-eligible"
        return "accept-eligible"
    endif

    Int invCount = player.GetItemCount(akBaseItem)
    if invCount <= 0
        if debugPickup
            Debug.Trace(tracePrefix + "removal=skipped-empty-inventory elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
        endif
        return "reject-skipped-empty-inventory"
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
    return "reject-removed"
EndFunction

; Shared eligibility decision for the post-acquisition and world-activation paths. Changes no items
; and no saved state. Returns accept-safe-context, accept-safe-keyword, accept-exclusion,
; accept-quest-reference, accept-eligible, reject-ineligible or abort-no-player.
String Function UT_EvaluateTomeEligibility(Form akBaseItem, ObjectReference akItemRef, Bool debugPickup, Float enteredAt, String tracePrefix)
    String ctx = UT_GetPickupContext()
    Bool safe = UT_IsSafeTomeContext(ctx)
    if debugPickup
        Debug.Trace(tracePrefix + "context gate 1 elapsed=" + (Utility.GetCurrentRealTime() - enteredAt) + " context=" + ctx + " safe=" + safe)
    endif
    if safe
        if debugPickup
            Debug.Trace(tracePrefix + "decision=accept-safe-context")
        endif
        return "accept-safe-context"
    endif

    if UT_TomeSafe != None
        if akBaseItem.HasKeyword(UT_TomeSafe)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-safe-keyword elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return "accept-safe-keyword"
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
        return "accept-safe-context"
    endif

    if UT_TomeExclusions != None
        if UT_TomeExclusions.HasForm(akBaseItem)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-exclusion elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return "accept-exclusion"
        endif
    endif

    if akItemRef != None
        if PO3_SKSEFunctions.IsQuestItem(akItemRef)
            if debugPickup
                Debug.Trace(tracePrefix + "decision=accept-quest-reference elapsed=" + (Utility.GetCurrentRealTime() - enteredAt))
            endif
            return "accept-quest-reference"
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
        return "abort-no-player"
    endif

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
        return "accept-eligible"
    endif
    return "reject-ineligible"
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
