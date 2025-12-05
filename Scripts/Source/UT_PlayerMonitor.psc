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


Bool Function DebugOn()
    if UT_DebugEnabled == None
        return false
    endif
    return UT_DebugEnabled.GetValueInt() != 0
EndFunction

Bool Function UT_IsBarterMenuOpen()
    ; Uses the built-in UI script: IsMenuOpen("BarterMenu")
    return UI.IsMenuOpen("BarterMenu")
EndFunction

Function Log(string msg)
    if DebugOn()
        Debug.Trace("[UntamedTomes] " + msg)
        Debug.Notification("[Untamed Tomes] " + msg)
    endif
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

Bool Function UT_IsSafeTomeContext()
    ; 0) Trading menu open? Treat as safe, regardless of location.
    if UT_IsBarterMenuOpen()
        return true
    endif

    String ctx = UT_GetTomeLocationContext()

    if ctx == "town"
        return true
    endif
    if ctx == "inn"
        return true
    endif
    if ctx == "store"
        return true
    endif

    ; Everything else (dungeon / other / no-location) is unsafe for now
    return false
EndFunction


Event OnInit()
    Log("Player monitor initialized.")
EndEvent


Event OnItemAdded(Form akBaseItem, int aiCount, ObjectReference akItemRef, ObjectReference akSourceContainer)
    ; 0) Mod enabled?
    if UT_ModEnabled != None
        if UT_ModEnabled.GetValueInt() == 0
            return
        endif
    endif

    if akBaseItem == None
        return
    endif

    ; 1) Only care about spell tomes
    if MagicTomeKeyword == None
        ; Misconfigured, fail safe
        return
    endif

    if !akBaseItem.HasKeyword(MagicTomeKeyword)
        return
    endif

    ; --- Debug: context probe for this tome pickup ---
    if DebugOn()
        String ctx = UT_GetTomeLocationContext()
        String msg = "Untamed Tomes: this tome is in " + ctx
        Debug.Notification(msg)
        Debug.Trace("[UntamedTomes] Tome context = " + ctx)
    endif

        ; --- Debug: detect bartering context ---
    if DebugOn()
        if UT_IsBarterMenuOpen()
            Debug.Trace("[UntamedTomes] BarterMenu is open when tome was added.")
        endif
    endif

      ; --- Debug: mark context as SAFE / UNSAFE ---
    if DebugOn()
        Bool safe = UT_IsSafeTomeContext()

        String label = "Unsafe"
        if safe
            label = "Safe"
        endif

        Debug.Notification("Untamed Tomes: context is " + label)
        Debug.Trace("[UntamedTomes] Tome context is " + label)
    endif

         ; --- Context-based safety gate (shops / inns / towns) ---
    if UT_IsSafeTomeContext()
        if DebugOn()
            Log("Safe context detected (" + UT_GetTomeLocationContext() + "), skipping Untamed logic.")
        endif
        return
    endif

    ; 2) Exclusions

    ; 2a) Marked safe via keyword (quest tomes, neutralized tomes, etc.)
    if UT_TomeSafe != None
        if akBaseItem.HasKeyword(UT_TomeSafe)
            Log("Tome marked safe via UT_TomeSafe keyword, skipping.")
            return
        endif
    endif

    ; --- Context-based safety gate (shops / inns / towns) ---
    if UT_IsSafeTomeContext()
        if DebugOn()
            Log("Safe context detected, skipping Untamed logic.")
        endif
        return
    endif

    ; 2b) In explicit exclusion list
    if UT_TomeExclusions != None
        if UT_TomeExclusions.HasForm(akBaseItem)
            Log("Tome found in UT_TomeExclusions, skipping.")
            return
        endif
    endif

        ; 2c) Quest item instance – don't nuke main quest stuff
    ; Uses powerofthree's Papyrus Extender: PO3_SKSEFunctions.IsQuestItem(ObjectReference)
    if akItemRef != None
        if PO3_SKSEFunctions.IsQuestItem(akItemRef)
            Log("Tome instance is quest item (PO3), skipping.")
            return
        endif
    endif

    ; 2d) Vendor tomes – purchased, already neutralized - vendor container do not have keywords?!
    ; if akSourceContainer != None && VendorChestKeyword != None
    ;     if akSourceContainer.HasKeyword(VendorChestKeyword)
    ;         Log("Tome came from vendor chest, skipping.")
    ;         return
    ;     endif
    ; endif

    ; 3) Get player & magicka
    Actor player = GetReference() as Actor
    if player == None
        player = Game.GetPlayer()
    endif
    if player == None
        return
    endif

    float threshold = 0.0
    if UT_MagickaThreshold != None
        threshold = UT_MagickaThreshold.GetValue()
    endif

    float magicka = player.GetBaseActorValue("Magicka")

    if DebugOn()
        Log("Picked up tome " + akBaseItem + " | Magicka=" + magicka + " Threshold=" + threshold)
    endif

    ; 4) If magicka is high enough, accept the tome
    if magicka >= threshold
        return
    endif

    ; 5) Not enough magicka -> tome rejects you and vanishes

    ; For now: always remove exactly 1 tome.
    ; (Later you can decide how to handle stacks / Take All behavior.)
    int countToRemove = 1

    ; Safety: if somehow the player doesn't actually have it, don't crash logic.
    int invCount = player.GetItemCount(akBaseItem)
    if invCount <= 0
        Log("Player has no copies of tome to remove; aborting.")
        return
    endif

    player.RemoveItem(akBaseItem, countToRemove, true) ; silent removal

    if DebugOn()
        Debug.Notification("The untamed tome rejects you.")
        Log("Removed one copy of tome due to insufficient magicka.")
    endif
EndEvent
