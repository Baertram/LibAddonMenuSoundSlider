--[[soundSliderData = {
    type = "soundslider",
    name = "My sound slider", -- or string id or function returning a string
    getFunc = function() return db.var end,
    setFunc = function(value) db.var = value doStuff() end,
    autoSelect = false, -- boolean, automatically select everything in the text input field when it gains focus (optional)
    inputLocation = "below", -- or "right", determines where the input field is shown. This should not be used within the addon menu and is for custom sliders (optional)
    showSoundName = true, -- or function returning a boolean (optional) If set to true (default) the selected sound name will be shown at the label of the slider
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

local em = EVENT_MANAGER
local wm = WINDOW_MANAGER
local cm = CALLBACK_MANAGER
local strformat = string.format
local tins = table.insert
local tsort = table.sort

--The sounds table of the game
local soundsRef = SOUNDS
--The number of possible sounds in the game
local numSounds = NonContiguousCount(soundsRef)
--The sound names table, sorted by name
local soundNames = {}
for soundName, soundInternalName in pairs(soundsRef) do
    if soundName ~= "NONE" then
        tins(soundNames, soundName)
    end
end
tsort(soundNames)
if #soundNames <= 0 then
    d("[LibAddonMenuSoundSlider] ERROR No sounds could be found - Widget won't work properly!")
    return
end
--Insert "none" as first sound
tins(soundNames, 1, "NONE")


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
    if control.data.playSound and value > 1 and soundsRef[soundName] ~= nil then
        PlaySound(soundsRef[soundName])
    end
    cm:FireCallbacks("LibAddonMenuSoundSlider_UpdateValue", panel or LAM.currentAddonPanel, control, value, soundName)
end

local function updateSoundSliderLabel(control, value)
    local data = control.data
    if data.showSoundName == true then
        --Show the sound name at the slider's label
        local soundName = soundNames[value] or "n/a"
        control.slidervalue:SetText(soundName)
    else
        --Only show the slider's value at the label
        control.slidervalue:SetText(value)
    end
end

local function UpdateValue(control, forceDefault, value)
    if forceDefault then --if we are forcing defaults
        value = util.GetDefaultValue(control.data.default)
        control.data.setFunc(value)
    elseif value then
        control.data.setFunc(value)
        --after setting this value, let's refresh the others to see if any should be disabled or have their settings changed
        util.RequestRefreshIfNeeded(control)
    else
        value = control.data.getFunc()
    end

    control.slider:SetValue(value)

    updateSoundSliderLabel(control, value)
    --Play the sound now and raise the callback function
    raiseSoundChangedCallback(nil, control, value)
end

local index = 1
function LAMCreateControl.soundslider(parent, sliderData, controlName)
    local control = util.CreateLabelAndContainerControl(parent, sliderData, controlName)
    local isInputOnRight = sliderData.inputLocation == "right"

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
        --slidervalue:SetText(value)
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
