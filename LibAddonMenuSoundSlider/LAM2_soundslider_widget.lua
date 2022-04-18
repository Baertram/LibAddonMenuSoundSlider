--[[soundSliderData = {
    type = "soundslider",
    name = "My sound slider", -- or string id or function returning a string
    getFunc = function() return db.var end,
    setFunc = function(value) db.var = value doStuff() end,
    autoSelect = false, -- boolean, automatically select everything in the text input field when it gains focus (optional)
    inputLocation = "below", -- or "right", determines where the input field is shown. This should not be used within the addon menu and is for custom sliders (optional)
    saveSoundIndex = false, -- or function returning a boolean (optional) If set to false (default) the internal soundName will be saved. If set to true the selected sound's index will be saved to the SavedVariables (the index might change if sounds get inserted later!).
    showSoundName = true, -- or function returning a boolean (optional) If set to true (default) the selected sound name will be shown at the label of the slider, and at the tooltip too
    playSound = true, -- or function returning a boolean (optional) If set to true (default) the selected sound name will be played via function PlaySound
    readOnly = true, -- boolean, you can use the slider, but you can't insert a value manually (optional)
    tooltip = "Sound slider's tooltip text.", -- or string id or function returning a string (optional)
    width = "full", -- or "half" (optional)
    disabled = function() return db.someBooleanSetting end, --or boolean (optional)
    warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
    requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
    default = defaults.var, -- default value or function that returns the default value (optional)
    helpUrl = "https://www.esoui.com/portal.php?id=218&a=faq", -- a string URL or a function that returns the string URL (optional)
    reference = "MyAddonSoundSlider" -- unique global reference to control (optional)
} ]]

local widgetVersion = 1
local widgetName = "LibAddonMenuSoundSlider"

local LAM = LibAddonMenu2
local util = LAM.util
local getDefaultValue = util.GetDefaultValue

local em = EVENT_MANAGER
local wm = WINDOW_MANAGER
local cm = CALLBACK_MANAGER

local tins = table.insert
local tsort = table.sort

local defaultTooltip

--The sounds table of the game
local soundsRef = SOUNDS
local conNone= "NONE"

--The sound names table, sorted by name. Only create once and cache at LibAddonMenu2 table!
local soundNames = {}
local soundLookup = {}
local soundIndexLookup = {}
local idx = 0
for soundName, soundInternalName in pairs(soundsRef) do
    if soundName ~= conNone then
        tins(soundNames, soundName)
        idx = idx +1
        soundLookup[idx] = soundInternalName
        soundIndexLookup[soundInternalName] = idx + 1 --+1 as later the "None" sound will be at index 1
    end
end
tsort(soundNames)
if #soundNames <= 0 then
    d("[LibAddonMenuSoundSlider] ERROR No sounds could be found - Widget won't work properly!")
    return
end
--Insert "NONE" as first sound
tins(soundNames, 1, conNone)
local nonSoundInternalName = soundsRef[conNone]
tins(soundLookup, 1, nonSoundInternalName)
soundIndexLookup[nonSoundInternalName] = 1

--The number of possible sounds in the game
local numSounds = #soundNames

LAM.soundData = {
    origSounds = soundsRef,
    soundNames = soundNames,
    soundLookup = soundLookup,
    soundIndexLookup = soundIndexLookup,
}

local SLIDER_HANDLER_NAMESPACE = "LAM2_SoundSlider"


local function UpdateDisabled(control)
    local disable
    if type(control.data.disabled) == "function" then
        disable = control.data.disabled()
    else
        disable = control.data.disabled
    end

    control.slider:SetEnabled(not disable)
    control.slidervalue:SetEditEnabled(not (control.data.readOnly or disable))
    if disable then
        control.label:SetColor(ZO_DEFAULT_DISABLED_COLOR:UnpackRGBA())
        control.minText:SetColor(ZO_DEFAULT_DISABLED_COLOR:UnpackRGBA())
        control.maxText:SetColor(ZO_DEFAULT_DISABLED_COLOR:UnpackRGBA())
        control.slidervalue:SetColor(ZO_DEFAULT_DISABLED_MOUSEOVER_COLOR:UnpackRGBA())
    else
        control.label:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
        control.minText:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
        control.maxText:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
        control.slidervalue:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
    end
end

local function raiseSoundChangedCallback(panel, control, value)
    local soundName = soundNames[value] or "n/a"
    local playSoundData = control.data.playSound
    local playSound = (playSoundData ~= nil and getDefaultValue(playSoundData)) or false
    if playSound == true and value > 1 and soundsRef[soundName] ~= nil then
        PlaySound(soundsRef[soundName])
    end
    cm:FireCallbacks("LibAddonMenuSoundSlider_UpdateValue", panel or LAM.currentAddonPanel, control, value, soundName)
end

local function updateSoundSliderLabel(control, value)
    local data = control.data
    local showSoundNameData = data.showSoundName
    local showSoundName = (showSoundNameData ~= nil and getDefaultValue(showSoundNameData)) or false
    if showSoundName == true then
        --Show the sound name at the slider's label too
        local soundName = soundNames[value]
        if soundName and soundName ~= "" then
            control.label:SetText(data.name .. " " .. soundName)
            data.tooltipText = defaultTooltip ..  "\n" .. soundName
        end
    else
        --Only show the slider's name at the label
        control.label:SetText(data.name)
        data.tooltipText = defaultTooltip
    end
end

local function UpdateValue(control, forceDefault, value)
    local doNotPlaySound = true
    local data = control.data
    local defaultVar = data.default ~= nil and getDefaultValue(data.default)

    local valueOfSlider --the number variable to use to update the slider's selected index, as the internal sound name string cannot be used to update the slider's position!
    local saveSoundIndex = (data.saveSoundIndex ~= nil and getDefaultValue(data.saveSoundIndex)) or false
    local soundNameInternal, soundIndex
    --Save the internal sound name string?
    if not saveSoundIndex then
        if value ~= nil then
            soundNameInternal = soundLookup[value]
            soundIndex = soundIndexLookup[value]
            valueOfSlider = value
        else
            soundNameInternal = soundLookup[defaultVar]
            soundIndex = soundIndexLookup[defaultVar]
            valueOfSlider = soundIndex
        end
    else
        --Save the sound index number
        if value ~= nil then
            valueOfSlider = value
        else
            valueOfSlider = defaultVar
        end
    end


    if forceDefault then --if we are forcing defaults
        --Save/Load the internal soundName of the index seleced at the slider?
        value = (saveSoundIndex == true and defaultVar) or soundNameInternal
        data.setFunc(value)
    elseif value ~= nil then
        doNotPlaySound = false
        data.setFunc((saveSoundIndex == true and valueOfSlider) or soundNameInternal)
        --after setting this value, let's refresh the others to see if any should be disabled or have their settings changed
        util.RequestRefreshIfNeeded(control)
    else
        value = data.getFunc()
        --> getfunc changes value to the "internal_sound_name" but the slider needs the value as number! Get index via mapping table for internal_sound_name to number
        if not saveSoundIndex and value ~= nil then
            valueOfSlider = soundIndexLookup[value]
        elseif value == nil then
            valueOfSlider = 1 --fallback value = index 1 "NONE"
        end
    end

    control.slider:SetValue(valueOfSlider)
    control.slidervalue:SetText(valueOfSlider)

    updateSoundSliderLabel(control, valueOfSlider)
    --Play the sound now and raise the callback function
    if not doNotPlaySound then
        raiseSoundChangedCallback(nil, control, value)
    end
end

local index = 1
function LAMCreateControl.soundslider(parent, sliderData, controlName)
    local control = util.CreateLabelAndContainerControl(parent, sliderData, controlName)
    local isInputOnRight = sliderData.inputLocation == "right"

    --Cache the default tooltip
    defaultTooltip = sliderData.tooltip or sliderData.name
    --Default values: Show sound name / Play sound
    sliderData.saveSoundIndex = sliderData.saveSoundIndex or false
    if sliderData.showSoundName == nil then sliderData.showSoundName = true end
    if sliderData.playSound == nil then sliderData.playSound = true end

    --skipping creating the backdrop...  Is this the actual slider texture?
    control.slider = wm:CreateControl(nil, control.container, CT_SLIDER)
    local slider = control.slider
    slider:SetAnchor(TOPLEFT)
    slider:SetHeight(14)
    if(isInputOnRight) then
        slider:SetAnchor(TOPRIGHT, nil, nil, -60)
    else
        slider:SetAnchor(TOPRIGHT)
    end
    slider:SetMouseEnabled(true)
    slider:SetOrientation(ORIENTATION_HORIZONTAL)
    --put nil for highlighted texture file path, and what look to be texture coords
    slider:SetThumbTexture("EsoUI\\Art\\Miscellaneous\\scrollbox_elevator.dds", "EsoUI\\Art\\Miscellaneous\\scrollbox_elevator_disabled.dds", nil, 8, 16)
    local minValue = 1
    local maxValue = numSounds
    slider:SetMinMax(minValue, maxValue)
    slider:SetHandler("OnMouseEnter", function() ZO_Options_OnMouseEnter(control) end)
    slider:SetHandler("OnMouseExit", function() ZO_Options_OnMouseExit(control) end)

    slider.bg = wm:CreateControl(nil, slider, CT_BACKDROP)
    local bg = slider.bg
    bg:SetCenterColor(0, 0, 0)
    bg:SetAnchor(TOPLEFT, slider, TOPLEFT, 0, 4)
    bg:SetAnchor(BOTTOMRIGHT, slider, BOTTOMRIGHT, 0, -4)
    bg:SetEdgeTexture("EsoUI\\Art\\Tooltips\\UI-SliderBackdrop.dds", 32, 4)

    control.minText = wm:CreateControl(nil, slider, CT_LABEL)
    local minText = control.minText
    minText:SetFont("ZoFontGameSmall")
    minText:SetAnchor(TOPLEFT, slider, BOTTOMLEFT)
    minText:SetText(sliderData.min)

    control.maxText = wm:CreateControl(nil, slider, CT_LABEL)
    local maxText = control.maxText
    maxText:SetFont("ZoFontGameSmall")
    maxText:SetAnchor(TOPRIGHT, slider, BOTTOMRIGHT)
    maxText:SetText(sliderData.max)

    control.slidervalueBG = wm:CreateControlFromVirtual(nil, slider, "ZO_EditBackdrop")
    if(isInputOnRight) then
        control.slidervalueBG:SetDimensions(60, 26)
        control.slidervalueBG:SetAnchor(LEFT, slider, RIGHT, 5, 0)
    else
        control.slidervalueBG:SetDimensions(50, 16)
        control.slidervalueBG:SetAnchor(TOP, slider, BOTTOM, 0, 0)
    end
    control.slidervalue = wm:CreateControlFromVirtual(nil, control.slidervalueBG, "ZO_DefaultEditForBackdrop")
    local slidervalue = control.slidervalue
    slidervalue:ClearAnchors()
    slidervalue:SetAnchor(TOPLEFT, control.slidervalueBG, TOPLEFT, 3, 1)
    slidervalue:SetAnchor(BOTTOMRIGHT, control.slidervalueBG, BOTTOMRIGHT, -3, -1)
    slidervalue:SetTextType(TEXT_TYPE_NUMERIC)
    if(isInputOnRight) then
        slidervalue:SetFont("ZoFontGameLarge")
    else
        slidervalue:SetFont("ZoFontGameSmall")
    end

    local isHandlingChange = false
    local function HandleValueChanged(value)
        if isHandlingChange then return end
        isHandlingChange = true
        slider:SetValue(value)
        slidervalue:SetText(value)

        updateSoundSliderLabel(control, value)
        isHandlingChange = false
    end

    slidervalue:SetHandler("OnEscape", function(self)
        HandleValueChanged(sliderData.getFunc())
        self:LoseFocus()
    end)
    slidervalue:SetHandler("OnEnter", function(self)
        self:LoseFocus()
    end)
    slidervalue:SetHandler("OnFocusLost", function(self)
        local value = tonumber(self:GetText())
        control:UpdateValue(false, value)
    end)
    slidervalue:SetHandler("OnTextChanged", function(self)
        local input = self:GetText()
        if(#input > 1 and not input:sub(-1):match("[0-9]")) then return end
        local value = tonumber(input)
        if(value) then
            HandleValueChanged(value)
        end
    end)
    if(sliderData.autoSelect) then
        ZO_PreHookHandler(slidervalue, "OnFocusGained", function(self)
            self:SelectAll()
        end)
    end

    --local range = maxValue - minValue
    slider:SetValueStep(sliderData.step or 1)
    slider:SetHandler("OnValueChanged", function(self, value, eventReason)
        if eventReason == EVENT_REASON_SOFTWARE then return end
        HandleValueChanged(value)
    end)
    slider:SetHandler("OnSliderReleased", function(self, value)
        if self:GetEnabled() then
            control:UpdateValue(false, value)
        end
    end)

    local function OnMouseWheel(self, value)
        if(not self:GetEnabled()) then return end
        local new_value = (tonumber(slidervalue:GetText()) or sliderData.min or 0) + ((sliderData.step or 1) * value)
        control:UpdateValue(false, new_value)
    end

    local sliderHasFocus = false
    local scrollEventInstalled = false
    local function UpdateScrollEventHandler()
        local needsScrollEvent = sliderHasFocus or slidervalue:HasFocus()
        if needsScrollEvent ~= scrollEventInstalled then
            local callback = needsScrollEvent and OnMouseWheel or nil
            slider:SetHandler("OnMouseWheel", callback, SLIDER_HANDLER_NAMESPACE)
            scrollEventInstalled = needsScrollEvent
        end
    end

    EVENT_MANAGER:RegisterForEvent(widgetName .. "_OnGlobalMouseUp_" .. index, EVENT_GLOBAL_MOUSE_UP, function()
        sliderHasFocus = (wm:GetMouseOverControl() == slider)
        UpdateScrollEventHandler()
    end)
    slidervalue:SetHandler("OnFocusGained", UpdateScrollEventHandler, SLIDER_HANDLER_NAMESPACE)
    slidervalue:SetHandler("OnFocusLost", UpdateScrollEventHandler, SLIDER_HANDLER_NAMESPACE)
    index = index + 1

    if sliderData.warning ~= nil or sliderData.requiresReload then
        control.warning = wm:CreateControlFromVirtual(nil, control, "ZO_Options_WarningIcon")
        control.warning:SetAnchor(RIGHT, slider, LEFT, -5, 0)
        control.UpdateWarning = util.UpdateWarning
        control:UpdateWarning()
    end

    control.UpdateValue = UpdateValue
    control:UpdateValue()

    if sliderData.disabled ~= nil then
        control.UpdateDisabled = UpdateDisabled
        control:UpdateDisabled()
    end

    util.RegisterForRefreshIfNeeded(control)
    util.RegisterForReloadIfNeeded(control)

    return control
end


--Load the widget into LAM
local eventAddOnLoadedForWidgetName = widgetName .. "_EVENT_ADD_ON_LOADED"
local function registerWidget(eventId, addonName)
    if addonName ~= widgetName then return end
    em:UnregisterForEvent(eventAddOnLoadedForWidgetName, EVENT_ADD_ON_LOADED)

    if not LAM:RegisterWidget("soundslider", widgetVersion) then return end
end
em:RegisterForEvent(eventAddOnLoadedForWidgetName, EVENT_ADD_ON_LOADED, registerWidget)
