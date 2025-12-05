Scriptname UT_MCM extends SKI_ConfigBase

; ============================
; Untamed Tomes - MCM v1
; ============================

GlobalVariable Property UT_ModEnabled        Auto
GlobalVariable Property UT_DebugEnabled      Auto
GlobalVariable Property UT_MagickaThreshold  Auto

; Option handles
int Property O_Enable       Auto
int Property O_Threshold    Auto
int Property O_Debug        Auto

Bool Function IsEnabled()
    if UT_ModEnabled == None
        return true ; fail-safe: treat as enabled
    endif
    return UT_ModEnabled.GetValueInt() != 0
EndFunction

Bool Function IsDebug()
    if UT_DebugEnabled == None
        return false
    endif
    return UT_DebugEnabled.GetValueInt() != 0
EndFunction

Event OnConfigInit()
    ; This name appears in the MCM list
    ModName = "Untamed Tomes"
    Debug.Trace("[UntamedTomes][MCM] OnConfigInit called")
EndEvent

Event OnPageReset(string page)
    ; Single-page menu; SkyUI passes empty string for the only page
    if page != ""
        return
    endif

    SetCursorFillMode(TOP_TO_BOTTOM)

    ; --- Enable toggle ---
    O_Enable = AddToggleOption("Enable Untamed Tomes", IsEnabled())

    ; --- Magicka threshold slider ---
    float threshold = 0.0
    if UT_MagickaThreshold != None
        threshold = UT_MagickaThreshold.GetValue()
    endif
    O_Threshold = AddSliderOption("Required Magicka", threshold, "{0}")

    ; --- Debug toggle ---
    O_Debug = AddToggleOption("Debug logging", IsDebug())
EndEvent

Event OnOptionSelect(int option)
    ; Handle toggle options
    if option == O_Enable
        Bool cur = IsEnabled()
        Bool newVal = !cur

        if UT_ModEnabled != None
            if newVal
                UT_ModEnabled.SetValueInt(1)
            else
                UT_ModEnabled.SetValueInt(0)
            endif
        endif

        SetToggleOptionValue(option, newVal)

    elseif option == O_Debug
        Bool curD = IsDebug()
        Bool newD = !curD

        if UT_DebugEnabled != None
            if newD
                UT_DebugEnabled.SetValueInt(1)
            else
                UT_DebugEnabled.SetValueInt(0)
            endif
        endif

        SetToggleOptionValue(option, newD)
    endif
EndEvent

Event OnOptionSliderOpen(int option)
    if option == O_Threshold
        float cur = 0.0
        if UT_MagickaThreshold != None
            cur = UT_MagickaThreshold.GetValue()
        endif

        ; Configure the slider dialog
        ; start value
        SetSliderDialogStartValue(cur)
        ; min/max
        SetSliderDialogRange(0.0, 500.0)
        ; step
        SetSliderDialogInterval(10.0)
        ; default
        SetSliderDialogDefaultValue(100.0)
    endif
EndEvent

Event OnOptionSliderAccept(int option, float value)
    if option == O_Threshold
        if UT_MagickaThreshold != None
            UT_MagickaThreshold.SetValue(value)
        endif
        SetSliderOptionValue(option, value, "{0}")
    endif
EndEvent
