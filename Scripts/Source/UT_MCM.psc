Scriptname UT_MCM extends SKI_ConfigBase

GlobalVariable Property UT_ModEnabled        Auto
GlobalVariable Property UT_DebugEnabled      Auto
GlobalVariable Property UT_MagickaThreshold  Auto

; SkyUI assigns these handles each time it builds the page.
Int enableOption
Int thresholdOption
Int debugOption

Bool Function IsEnabled()
    if UT_ModEnabled == None
        return true
    endif
    return UT_ModEnabled.GetValueInt() != 0
EndFunction

Bool Function IsDebug()
    if UT_DebugEnabled == None
        return false
    endif
    return UT_DebugEnabled.GetValueInt() != 0
EndFunction

Float Function GetMagickaThreshold()
    if UT_MagickaThreshold == None
        return 0.0
    endif
    return UT_MagickaThreshold.GetValue()
EndFunction

Int Function SettingFlags(GlobalVariable setting, String propertyName)
    if setting == None
        Debug.Trace("[UntamedTomes][MCM] Missing global binding: " + propertyName)
        return OPTION_FLAG_DISABLED
    endif
    return OPTION_FLAG_NONE
EndFunction

Event OnConfigInit()
    ; This name appears in the MCM list
    ModName = "Untamed Tomes"
EndEvent

Event OnPageReset(string page)
    ; Single-page menu; SkyUI passes empty string for the only page
    if page != ""
        return
    endif

    SetCursorFillMode(TOP_TO_BOTTOM)

    enableOption = AddToggleOption("Enable Untamed Tomes", IsEnabled(), SettingFlags(UT_ModEnabled, "UT_ModEnabled"))
    thresholdOption = AddSliderOption("Required Magicka", GetMagickaThreshold(), "{0}", SettingFlags(UT_MagickaThreshold, "UT_MagickaThreshold"))
    debugOption = AddToggleOption("Debug logging", IsDebug(), SettingFlags(UT_DebugEnabled, "UT_DebugEnabled"))
EndEvent

Event OnOptionSelect(int option)
    if option == enableOption && UT_ModEnabled != None
        Bool enabled = !IsEnabled()
        UT_ModEnabled.SetValueInt(enabled as Int)
        SetToggleOptionValue(option, enabled)
    elseif option == debugOption && UT_DebugEnabled != None
        Bool debugEnabled = !IsDebug()
        UT_DebugEnabled.SetValueInt(debugEnabled as Int)
        SetToggleOptionValue(option, debugEnabled)
    endif
EndEvent

Event OnOptionSliderOpen(int option)
    if option == thresholdOption && UT_MagickaThreshold != None
        SetSliderDialogStartValue(GetMagickaThreshold())
        SetSliderDialogRange(0.0, 500.0)
        SetSliderDialogInterval(10.0)
        SetSliderDialogDefaultValue(100.0)
    endif
EndEvent

Event OnOptionSliderAccept(int option, float value)
    if option == thresholdOption && UT_MagickaThreshold != None
        UT_MagickaThreshold.SetValue(value)
        SetSliderOptionValue(option, value, "{0}")
    endif
EndEvent
