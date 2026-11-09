# Gamepad support — research

Research into whether and how to make AltArmy usable with a gamepad on WoW: Forever (interface 16001) and TBC Anniversary (20506). Done 2026-11-09 by reading Blizzard's UI source, ConsolePort and other addons, and AltArmy's own code. **Nothing here has been tested in game.** Every claim cites a file and line or a URL; anything inferred or unverified is marked as such. Section 6 lists the in-game checks that would settle the open points.

Sources used:

- Blizzard UI source mirrors ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)): branches `forever` (1.60.1.70862), `classic_anniversary` (2.5.6) and `live` (12.1.5), for comparison. Paths below are relative to the branch, written `forever: Interface/AddOns/...`. "API docs" means `Interface/AddOns/Blizzard_APIDocumentationGenerated/` in that branch.
- [ConsolePort](https://github.com/seblindfors/ConsolePort) (commit 18bd2055, v3.3.13) and its node scanner [ConsolePortNode](https://github.com/seblindfors/ConsolePortNode) (b86ed651), which ConsolePort pulls in through `.pkgmeta`.
- Other addons: [YUI-Dialogue / DialogueUI](https://github.com/Peterodox/YUI-Dialogue), [Immersion](https://github.com/seblindfors/Immersion), [WhatsTraining](https://github.com/fusionpit/WhatsTraining), [Improved Forever](https://github.com/markgravity/ImprovedForever), [Plumber](https://github.com/Peterodox/Plumber), [BetterBags](https://github.com/Cidan/BetterBags), [Dominos](https://github.com/tullamods/Dominos), [Azeroth Pilot Reloaded](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded), [salty-max/addon-kit](https://github.com/salty-max/addon-kit), Questie's `AddonDialog`, [WoWXIV](https://github.com/vaxherd/WoWXIV).
- AltArmy paths are relative to `addon/AltArmy_TBC/`.

---

## 1. Summary and recommendation

### What the clients offer

- **All three clients** (forever, classic_anniversary, live) have the engine layer: the `C_GamePad` namespace, the `GAME_PAD_*` events, `Frame:EnableGamePadButton` / `OnGamePadButtonDown`, the `PAD*` binding names and glyph strings, override bindings, and the game's own **virtual mouse cursor** (`SetGamePadCursorControl`).
- **Only Forever** ships Blizzard's console-style gamepad UI: `Blizzard_GamepadSmartNavigation` (a D-pad focus cursor over UI panels), `Blizzard_GamepadSharedUtility` (frame focus manager, binding stack, button-prompt templates), `C_InputInterfaceStyle`, and so on. It is active only when the player turns on Settings → Gamepad → "Enable Gamepad UI". Neither classic_anniversary nor live has any of it (both ship only `Blizzard_MovePad`, a mouse/touch movement pad).
- **ConsolePort**, the best-known controller addon, lists both target clients and live in its TOC (`## Interface: 120100, 50504, 38010, 20506, 16001, 11509`, `ConsolePort/ConsolePort.toc:1`). It already finds AltArmy's main window by scanning `UISpecialFrames`.

### Where AltArmy stands

AltArmy was built for the mouse. With a pad today:

- There is **no key binding** to open the window (no `Bindings.xml`); it opens from `/alta` or the minimap button.
- Opening it with `:Show()` does **not** free the game's virtual cursor (only `ShowUIPanel` and bags do), so a pad player has to press Esc/PADBACK first, which clears the target, then frees the cursor, and only a further press closes the window.
- **Forever's smart navigation does not reach the window** at all: it only drives frames passed through `ShowUIPanel` or `GamepadMode.FrameControlsManager:FrameShown`.
- Under ConsolePort the window is reachable, and most buttons, rows and tooltips should work. What fails is a predictable set of shared widgets: sliders, drag-only scrollbars, custom dropdown popups, hover-only `Frame`s, wheel-only lists, and modifier-click item actions.
- **The export string can't leave the game** with only a pad: it relies on Ctrl+C, and `CopyToClipboard` is restricted for addons on every client.

### Demand

One request in 10 CurseForge comments ("It would be great if you could add gamepad support", 2026-11-09, out of 13,787 downloads), nothing on GitHub. On Forever, Blizzard pushes controller play officially (as a beta, [Blizzard news](https://news.blizzard.com/article/24316974/wow)), and a Questie fix for the Gamepad UI drew about 20k downloads in a month ([CurseForge](https://www.curseforge.com/wow/addons/questie-forever-gamepad)), so Forever pad players exist and install fixes. Nobody publishes how many there are.

### Recommendation

Do the routes in this order; each one is useful by itself.

| Phase | What | Clients | Effort | Risk |
|---|---|---|---|---|
| **0. Hygiene** | `Bindings.xml` toggle; free the virtual cursor on show; `CloseButton` fields; ConsolePort registration and node attributes; a D-pad → `SimulateMouseWheel` shim for lists | both | ~1–2 days, ~200–300 lines | low |
| **1. Shared widgets** | Fix the dozen `Theme.lua` factories that a pad can't operate (sliders, dropdown popups, labelled checkbox rows, help icons, horizontal scroll, hover-only frames), plus a modifier-free item action menu | both | ~3–5 days, mostly `UI/Theme.lua` | low |
| **2. Forever native** | Register the main window and dialogs with `FrameControlsManager` (out of combat, gated on the Gamepad UI style), mark frames focusable/ignored, add jump overrides and button prompts | Forever | ~1 week | **taint** — try only after the taint test in §6 |
| **3. Own focus model** | A DialogueUI/Immersion-style navigator using `OnGamePadButtonDown`, so a pad works without ConsolePort or Forever's UI | both | 2–4 weeks + upkeep per tab | combat/input capture |

Concretely: **do phases 0 and 1 now** (they serve ConsolePort users on both clients and native-cursor users everywhere, and they cost little). **Treat phase 2 as an experiment** behind a test with `/console taintLog 1`. **Hold phase 3** until more players ask; it is the only route that works with nothing but a pad on TBC Anniversary, but it is a lasting cost on every tab.

Per client:

- **Forever:** phase 0 + 1, then phase 2 if the taint test is clean. With the Gamepad UI on, ConsolePort steps aside for frames Blizzard's smart navigation drives (`ConsolePort_Cursor/Controller/Stack.lua:52-55`), so phase 2 is what Gamepad UI players will actually see.
- **TBC Anniversary:** phase 0 + 1. There is no native navigation to join; players use the virtual cursor or ConsolePort.

---

## 2. Gamepad APIs

### 2.1 Availability per client

"Docs" = the branch's API docs; "calls" = only evidenced by Blizzard or addon call sites (undocumented).

| API | forever | classic_anniversary | live | Notes |
|---|---|---|---|---|
| `C_GamePad` (23 core functions: `IsEnabled`, `GetActiveDeviceID`, `GetDeviceMappedState`, `GetDeviceRawState`, `ButtonIndexToBinding`, `SetVibration`, `Get/SetConfig`, …) | ✅ docs | ✅ docs | ✅ docs | `GamePadDocumentation.lua`. `AddSDLMapping`, `ApplyConfigs`, `DeleteConfig`, `SetConfig` are `HasRestrictions` (forever :13, :30, :99, :243). Forever adds `SecretArguments` annotations. |
| `C_GamePad.Get/SetAllowHoverEventsWithFreeLook` | ✅ | ❌ | ❌ | forever `GamePadDocumentation.lua:135, :231`. **Not useful to AltArmy:** it is a world-unit hover switch, and Blizzard turns it off while a menu has focus (forever `Blizzard_GamepadSharedUtility/FrameControlsManager.lua:897-901`). |
| Events `GAME_PAD_ACTIVE_CHANGED`, `GAME_PAD_CONNECTED`, `GAME_PAD_DISCONNECTED`, `GAME_PAD_CONFIGS_CHANGED`, `GAME_PAD_POWER_CHANGED` | ✅ | ✅ | ✅ | forever `GamePadDocumentation.lua:296-343`. Blizzard action buttons use `GAME_PAD_ACTIVE_CHANGED` to swap hotkey text (anniversary `Blizzard_ActionBar/Shared/ActionButton.lua:208`). |
| `Frame:EnableGamePadButton` / `EnableGamePadStick` | ✅ | ✅ | ✅ | `SimpleFrameAPIDocumentation.lua` forever :225/:236, anniversary :185/:195, live :225/:236. **`IsProtectedFunction = true`** on every client, like `EnableKeyboard`. |
| Script handlers `OnGamePadButtonDown/Up(self, button)`, `OnGamePadStick(self, stick, x, y, len)` | ✅ | ✅ | ✅ | `Blizzard_SharedXML/UI.xsd` forever :444-446, anniversary :366-368. Buttons arrive as `PAD*` strings; sticks as `"Left"`, `"Right"`, `"Movement"` (forever `Blizzard_SharedXML/Blizzard_RadialWheel.lua:566`). |
| `Frame:SetPropagateKeyboardInput` | ✅ | ✅ | ✅ | `HasRestrictions` (forever `SimpleFrameAPIDocumentation.lua:1428`, anniversary :1235). [Wiki](https://warcraft.wiki.gg/wiki/API_Frame_SetPropagateKeyboardInput): insecure code can't call it in combat. Gamepad buttons follow the same flag (ConsolePort `ConsolePort/Widget/Helpers.lua:47-57`). |
| `PAD*` binding names and `KEY_PAD*` / `KEY_ABBR_PAD*` glyph strings | ✅ | ✅ | ✅ | `Blizzard_SharedXML/SharedConstants.lua:55-128` in each branch; the atlases are `Gamepad_<style>_<name>_64` / `_32`. Forever also has `Shared/GamepadConstants.lua:3-47` (`GAMEPAD_FACE_BOTTOM = "PAD1"`, …). |
| `SetOverrideBinding`, `SetOverrideBindingClick`, `ClearOverrideBindings`, `SetBinding` | ✅ | ✅ | ✅ | No-combat ([wiki SetOverrideBinding](https://warcraft.wiki.gg/wiki/API_SetOverrideBinding), [wiki SetBinding](https://warcraft.wiki.gg/wiki/API_SetBinding)). |
| `SetGamePadCursorControl`, `CanAutoSetGamePadCursorControl`, `IsGamePadCursorControlEnabled`, `SetGamePadFreeLook`, `IsGamePadFreelookEnabled` | ✅ calls | ✅ calls | ✅ calls | Not in any API docs. Blizzard calls: forever `Blizzard_Game/Shared/Game.lua:16-43`, anniversary `Blizzard_UIParent/TBC/UIParent.lua:1212-1218`, `Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua:134`. ConsolePort calls them from insecure code (`ConsolePort/Controller/Mouse.lua:86-87, 275-276`), so probably not protected. Listed as 2.5.1 additions on the [wiki](https://warcraft.wiki.gg/wiki/Patch_2.5.1/API_changes). |
| `SetCursorPosition`, `SimulateMouseClick/Down/Up`, `SimulateMouseWheel`, `GetCursorPosition`, `GetMouseFoci` | ✅ | ✅ | ✅ | `InputDocumentation.lua` forever :272-337, anniversary :62-118, live :253-310. `RequiresLimitedInput`: insecure code may call each "only once in response to gamepad input hardware events"; the mouse focus must not be protected. |
| `IsUsingGamepad`, `IsUsingMouse` | ✅ docs | ❌ not in docs | ✅ docs | forever `InputDocumentation.lua:245, :254`. Unverified on 20506; guard with `if IsUsingGamepad then`. |
| `GetCursorCenterPosition`, `IsCursorVisible` | ✅ | ❌ | ❌ | forever `InputDocumentation.lua:10, :106`. |
| `C_InputInterfaceStyle.GetCurrentStyle`, `Enum.InputDeviceInterfaceType` (Mkb=0, Gamepad=1), `INPUT_DEVICE_INTERFACE_TRANSITION`, CVar `InputDeviceInterfaceStyle` | ✅ | ❌ | ❌ | forever `InputInterfaceStyleDocumentation.lua:5`, `InputConstantsDocumentation.lua:20-28`, `InputDocumentation.lua:341-350`. The Settings checkbox writes the CVar (forever `Blizzard_SettingsDefinitions_Shared/Gamepad.lua:276-291`); its default is `PlatformIsHandheld()` (:288), a Forever-only API. |
| `InputUtil.IsGamepadUIEnabled`, `RegisterGamepadInit/Uninit` | ✅ | ❌ | ❌ | forever `Blizzard_SharedXML/Mainline/InputUtil.lua:11-13`; `Blizzard_SharedXML/InputUtil.lua:100-166`. **The `InputUtil` table itself exists on all three** (cursor helpers), so test `InputUtil.IsGamepadUIEnabled`, not `InputUtil`. |
| `C_KeyBindings.ActivateBindingContext` | ✅ | ✅ | ✅ | `KeyBindingsDocumentation.lua:11` in each, `HasRestrictions`. Only `Enum.BindingContext.GamepadModeInGameCore` (forever :201) is Forever-only; it is Blizzard's, not addon-usable. |
| `C_GamepadUI`, `C_GamepadTargeting`, `SetPreferredGamepadInteractTarget` | ✅ | ❌ | ❌ | Action-bar storage and targeting; not relevant to windows. `SetPreferredGamepadInteractTarget` is `HasRestrictions` (forever `TargetScriptDocumentation.lua:59`) and is the function that taint shows up on (§2.4). |
| ScriptRegion `FocusEnter`, `FocusExit`, `MouseDown`, `MouseUp` | ✅ | ❌ | ❌ | forever `SimpleScriptRegionAPIDocumentation.lua:106-128, 596-617`, all `IsProtectedFunction`. Smart navigation calls them; addons can't. |
| Restricted environment `IsGamePadEnabled()`, `GetGamePadState()` | ✅ | ✅ | ✅ | `Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua:176-182`, for secure snippets. Not needed by AltArmy. |
| `IsBindingForGamePad(key)` | ✅ calls | ✅ calls | ✅ calls | forever `Blizzard_ActionBar/Shared/ActionButton.lua:507`, anniversary :497. |
| Blizzard gamepad framework (`Blizzard_Gamepad`, `…SmartNavigation`, `…SharedUtility`, `…SoftCursor`, `…Targeting`, `…ActionBars`) | ✅ | ❌ | ❌ | `ls Interface/AddOns` in each branch. |
| `CopyToClipboard` | restricted | restricted | restricted | `OsDocumentation.lua:10` in each, `HasRestrictions`; forever adds `SecretArguments = "AllowedWhenUntainted"`. See §2.7. |
| Blizzard on-screen keyboard | ❌ | ❌ | ❌ | No hits for virtual/on-screen keyboard API names in any branch. See §2.7. |

GamePad CVars (`GamePadEnable`, `GamePadEmulateShift/Ctrl/Alt/Esc`, `GamePadCursorLeftClick/RightClick`, `GamePadCursorAutoEnable`, `GamePadCursorSpeed*`, …) are engine CVars; the [wiki](https://warcraft.wiki.gg/wiki/Game_Pad_buttons) lists them and their defaults. Forever's settings panel binds some of them (forever `Blizzard_SettingsDefinitions_Shared/Gamepad.lua:34-132`). On 20506 their existence is inferred from ConsolePort setting them there (`ConsolePort/Model/Data/Console.lua:18-66`). Defaults per the wiki: Shift = PADLTRIGGER, Ctrl = PADLSHOULDER, Esc = PADBACK, left click = PADRTRIGGER, right click = PADRSHOULDER. **AltArmy should read these, never write them**, and should not count on the triggers or shoulders being free.

Detecting a pad on both clients: `C_GamePad.IsEnabled()` plus `GAME_PAD_ACTIVE_CHANGED(isActive)`. On Forever also `IsUsingGamepad()` and `InputUtil.IsGamepadUIEnabled()` / `INPUT_DEVICE_INTERFACE_TRANSITION`.

### 2.2 The game's virtual cursor (both clients)

With a pad the player normally moves in free-look: the camera is on a stick and there is no cursor. "Cursor control" frees an on-screen mouse cursor moved by a stick, which clicks with PADRTRIGGER/PADRSHOULDER (wiki defaults). The game turns it on by itself (CVar `GamePadCursorAutoEnable`, default 1) when `ShowUIPanel` opens a panel (forever `Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:878-880`, anniversary :828-830), when bags open (anniversary `ContainerFrame_Shared.lua:134`), and from Esc when there is nothing to cancel.

AltArmy opens with `main:Show()` (`Core.lua:442, 471`) and is only in `UISpecialFrames` (`Core.lua:87-88`), so **the cursor is not freed today**. Esc first tries `ClearTarget()` (and on anniversary `SpellStopCasting`, `SpellStopTargeting`), then frees the cursor, and only a further press closes the window (forever `Blizzard_Game/Shared/Game.lua:15-24`; anniversary `TBC/UIParent.lua:1207-1267`).

What should work under the virtual cursor (inferred; see §6 for tests):

- Clicks are real mouse clicks with `LeftButton`/`RightButton` ([wiki CVar_GamePadCursorLeftClick](https://warcraft.wiki.gg/wiki/CVar_GamePadCursorLeftClick)); Blizzard depends on this for bag slots.
- `GetCursorPosition` follows the cursor (Forever's loot frame relies on it: forever `Blizzard_UIPanels_Game/Mainline/LootFrame.lua:255-261`).
- `OnEnter`/`OnLeave`, tooltips and `IsMouseOver` should behave as with a mouse.
- Shift/Ctrl clicks work while an emulated modifier is held.
- **No mouse wheel.** No GamePad CVar maps a wheel. `SimulateMouseWheel(delta)` can supply one tick per hardware press from an `OnGamePadButtonDown` handler. No reference addon uses it, so it is untested.
- Unverified: whether `IsMouseButtonDown(1)` is true while the click trigger is held (AltArmy's horizontal scrollbar and graph zoom poll it), and whether `OnMouseUp` arrives if the cursor turns off mid-drag (on jump: `GamePadCursorAutoDisableJump`).

Blizzard's pattern to copy: `if CanAutoSetGamePadCursorControl(true) then SetGamePadCursorControl(true) end` on show; `CloseAllWindows` already turns it off when it closes a `UISpecialFrames` window (forever `UIParentPanelManager.lua:1170-1180`). **Skip it when ConsolePort is loaded**: ConsolePort sets `GamePadCursorAutoEnable` to 0 and manages cursor control itself (`ConsolePort/Controller/Mouse.lua:267-289, 373`).

### 2.3 Forever's gamepad framework, and how an addon frame takes part

Forever's "Gamepad UI" has two pieces every Blizzard panel uses:

- **`GamepadMode.FrameControlsManager`** (forever `Blizzard_GamepadSharedUtility/FrameControlsManager.lua`): keeps the list of shown, focusable windows sorted left to right, tracks which has focus, pages between them with LT/RT (:181-185), and turns UI focus on and off with the TOGGLEUIFOCUS binding (`Blizzard_Gamepad/Bindings.xml`; :629-706).
- **`SmartNavigation`** (forever `Blizzard_GamepadSmartNavigation/SmartNavigation.lua`): the D-pad focus cursor inside the focused window.

The load gating: `Blizzard_Gamepad`, `…ActionBars`, `…Targeting` are `## AllowLoadGameType: camelot` (Forever's internal game type: forever `Blizzard_GlueParent/Mainline/GlueParent.lua:193-194`). `SmartNavigation` and `SharedUtility` are `## AllowLoad: Both`, ungated. `Blizzard_GamepadSoftCursor` is gated to `mainline`; Forever also loads other `mainline`-gated addons (Mail, Friends, Professions), so it probably loads, but this is unverified. AltArmy doesn't need it.

**How a frame joins.** The manager's own header comment: "A frame can subscribe to this by either being a part of ShowUIPanel or by manually calling FrameShown on their OnShow event" (FrameControlsManager.lua:3-11). `FrameShown` returns immediately unless `InputUtil.IsGamepadUIEnabled()` (:384-387). Blizzard's non-panel frames do exactly this: `Blizzard_Channels/Mainline/CreateChannelPopup.lua:68-81` (paired `FrameShown`/`FrameHidden`), `Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.lua:75-80`, `SpellFlyout.lua:455-468`, and the `GamepadBaseDialogTemplate` (`Blizzard_GamepadSharedUtility/Templates/BaseDialog.lua:10-16`).

For a non-popup frame, `FrameShown` turns UI focus on itself when the player is in character control (:416-422, :441-445), so the window gets focus as soon as it opens. When UI focus is toggled off and back on, it returns to the same window (:643-652, :683-690).

**What smart navigation does once a frame is focused:**

- **Discovery** (`Blizzard_GamepadSmartNavigation/Utility.lua:263-334`): walks the frame's children; a stop is any Button or EditBox, any frame with an `OnMouseUp`/`OnMouseDown` script, or any frame marked focusable. It does **not** check `EnableMouse`, and `OnEnter` alone does **not** count. A `ScrollFrame`, or anything with `.ScrollTarget` (a ScrollBox), starts a scroll group; every button below goes into its **innermost** scroll group only. A `CreateFrame` hook rescans when new children appear inside the panel (SmartNavigation.lua:255-265).
- **Movement**: nearest valid stop within a 45° cone (:9, :1472-1582), or a logical grid if `SetUseGridNavigation` is on (:1332-1470). Valid means visible and, inside a scroll group, centred within that group's rect (:1207-1248).
- **Focus**: locks the button's highlight, calls the protected `FocusEnter()` (:747-751; presumably this fires `OnEnter`, so tooltips should show; inferred), then calls the optional Lua methods `OnSmartNavSelect`/`OnSmartNavDeselect` on the button and `SmartNavigationOnSelect` on the panel (:674-710).
- **A** (PAD1): calls the button's `OnSmartNavClick` if it has one, otherwise `MouseDown()` + `MouseUp()` with no button argument (:1639-1653). The API docs give the argument `Default = "LeftButton"` (forever `SimpleScriptRegionAPIDocumentation.lua:596-617`), and Blizzard's own gamepad tab switching relies on omitted arguments acting as `LeftButton` with `upInside` (forever `Blizzard_GamepadSharedUtility/Tab/TabIndicators.lua:101-111` driving `LargeSideTabButtonTemplate` tabs whose `OnMouseUp` checks `button == "LeftButton" and upInside`, e.g. `Blizzard_InspectUI/Camelot/Blizzard_InspectUI.lua:260-264`). So **AltArmy's `button == "LeftButton"` checks should pass** (strongly inferred).
- **B** (PAD2): calls the frame's `SmartNavigationCloseHandler` (return `true` as the handled flag), else clicks `frame.CloseButton`, else any visible button whose name contains `CloseButton` (:1661-1694).
- **Right click**: `SmartNavigation:RightClick()` passes `"RightButton"` (:1655-1659), but Blizzard binds it only per panel (bags, merchant), so a right-click action needs AltArmy's own binding.
- **Scrolling**: when focus moves onto a button in a scroll group, the group is scrolled vertically (`SetVerticalScroll` or a ScrollBox percentage, :1087-1179). Nothing scrolls horizontally. The right stick scrolls only a scroll frame set with `SetScrollFrameForFrame` (:1017-1030, :486-566), vertically.

**What an addon may call.** Calls from insecure code go through `SecureHelper` (`Blizzard_GamepadSmartNavigation/SecureHelper.lua`). A wrapped function called insecurely is passed through `SetAttribute("invoke")` and run securely by an attribute handler if `issecure() or not IsAddOnRestrictionActive(Combat)` (:26-28, :79-126, :162-191); in combat it shows "Interface action failed because of an AddOn" and does nothing.

- **Wrapped (callable out of combat):** `FrameControlsManager:FrameShown` (:464), **`FrameHidden` (:561)**, `HandlePopupShown` (:583), `HandlePopupHide` (:589); `SmartNavigation:HandlePanelOpen` (:1771), `RefreshButtonGroups` (:1797), `SetTargetButtonForFrame` (:1015), `SetScrollFrameForFrame` (:1030), `SetWrapping` (:1063), `SetUseGridNavigation` (:1085), `SelectFirstButton` (:966), `ShowCursor`/`HideCursor` (:394/:411), `RemovePanelInfo` (:902). (One verifier's report said `FrameHidden` is unwrapped; the source shows it is wrapped.)
- **Secure-only (refused, "action blocked"):** `SelectButton` (:649), `Navigate` (:1472), `EnterFocusGroup`/`LeaveFocusGroup` (:1881, :1916), `ActivateBinding` (:276) and others behind `EnsureIsSecure` (:74-88). Blizzard's comment at :650 says to use `SetTargetButtonForFrame` instead of `SelectButton`. So the Settings-panel pattern of a sub-section focus group can't be copied.
- **Key setters** (Utility.lua:14-43: "may be set without causing taint (only while out of combat)"): `SmartNavigation_MarkFrameIgnored`, `_MarkFrameFocusable`, `_MarkFrameIgnoredContainerFrame`, `_MarkFrameSubSection`, `_SetButtonFrame`, `_AddJumpNavigationOverride`, `_AddBidirectionalJumpNavigationOverride`, `_AddIgnoreInputNavigationOverride`, `_RegisterOutgoingDirNavCallback`, `_SetCustomCursorAnchorPointForFrame`, `_MarkScrollFrameMaintainPreviousButtonOnScroll` (Utility.lua:46-602). They write through `SecureHelper:SetSecureValue`. Don't assign the keys directly.
- **Methods Blizzard calls on our frames** through `securecallfunction`, so our handlers run but their taint is contained: `FocusGamepad`, `UnfocusGamepad`, `StartFocus`, `EndFocus` (FrameControlsManager.lua:47-48, :106-107), `OnSmartNavClick`, `OnSmartNavSelect`, `OnSmartNavDeselect`, `SmartNavigationOnSelect`, `SmartNavigationCloseHandler`.
- **Unwrapped, avoid:** every other `FrameControlsManager` method (`FocusFrame`, `FocusNextFrame`, `SetUIFocusState`, `ToggleUIFocus`, `SuspendFrame`, `UnsuspendFrame`, `HideActiveFrames`, the flag setters :842-887). Called from addon code they write the manager's shared state tainted.

Templates usable on Forever only (inherit or `CreateFrame` behind a feature check): `InputIconTextureFrameTemplate` (`SetInputKey("PAD1")`, follows the controller's label style; forever `Blizzard_SharedXML/Shared/InputIcons/InputIconTexture.xml:3`), the `InputPrompt*Template` family (`Blizzard_GamepadSharedUtility/InputPrompts/InputPrompts.xml`), `InputPromptLegends.CreateInputLegend` (used by WhatsTraining), `GamepadBaseDialogTemplate`, `GamepadTabIndicatorsTemplate` (LB/RB tab paging; it reads `PanelTemplates_GetSelectedTab`, which does not match AltArmy's Forever top tabs, see §4.1), `GamepadScrollBarHint`, `SmartNavigationPointerTemplate`. Display-only templates (icons, prompts without bindings) carry no taint risk. Footers and tab indicators with function bindings push groups onto Blizzard's shared binding stack (`GamepadMode.CreateBindingGroup`, which binds with `SetOverrideBindingClick(UIParent, true, …)`: `InputBindingStack/InputFunctionBinding.lua:49`). That stack has no security wrapper and is shared with Blizzard; using it from an addon is a taint risk (inferred). For extra keys, prefer AltArmy's own override bindings on an AltArmy-owned frame.

### 2.4 Restrictions: combat, protected functions, taint

- **Combat.** Everything that changes input routing must be set up out of combat: `SetOverrideBinding*`, `SetBinding`, `SetPropagateKeyboardInput`, `EnableGamePadButton`/`EnableGamePadStick`/`EnableKeyboard` (protected), the wrapped SmartNavigation/FrameControlsManager calls, and the `SmartNavigation_*` key setters. Every surveyed addon drops pad capture in combat: DialogueUI swaps to a frame whose propagation is fixed in XML (`Code/Dialogue/KeyboardControl.lua`; `API.xml:13`), Questie stops taking keys (`Modules/Libs/AddonDialog/Dialog.lua:347-360`), WhatsTraining and Improved Forever release capture; ConsolePort hides its cursor on `PLAYER_REGEN_DISABLED` (`ConsolePort_Cursor/View/Cursor.lua:28-60`). AltArmy is an out-of-combat tool, so the rule is simple: **pad support is set up out of combat, released on `PLAYER_REGEN_DISABLED`, and nothing is rebound in combat.**
- **Taint on Forever.** Improved Forever documents traps from driving Forever's frame manager from addon code (`ImprovedForever/CLAUDE.md:23-46, 124-128, 174-194`): calling the unwrapped `Focus*` methods, calling `ShowUIPanel`, `StaticPopup_Show` (its handler writes `GamepadPopupHandler.visiblePopups` tainted: forever `Blizzard_StaticPopup/StaticPopupGamepad.lua:208-222`), `AddManagedFrame`, and taking or binding the game's own pad buttons. The reported symptom is `ADDON_ACTION_BLOCKED` on `SetPreferredGamepadInteractTarget`, which is reached from binding-group changes through `MainActionBarFrame.lua:57, 355-374, 672-673` (path partly inferred). Note that `UISpecialFrames` closing via Esc is itself listed as a trap there (`ImprovedForever/Focus.lua:117-122`); AltArmy already uses it, so this needs checking in the taint test. ImprovedForever also stubs out `FrameHidden` calls from its tracker's close handler after a forbidden-action error (`tools/fork_objective_tracker.py:71`; CHANGELOG QuestTracker 0.6.2), unverified whether `FrameHidden` itself was the cause.
- **Verdict on joining Forever's navigation:** calling `FrameShown`/`FrameHidden` from AltArmy's `OnShow`/`OnHide`, out of combat, gated on `InputUtil.IsGamepadUIEnabled()`, passing only the frame, **is probably safe (medium confidence)**. Conditions: never call the unwrapped manager methods, `ShowUIPanel` or `StaticPopup_Show`; never set the manager's flag fields (`skipGamepadAutoFocus`, `useCustomNavigation`, `returnToPlayerControl`, `dismissOnUnfocus`, …) or `smartNavigation*` keys by plain assignment (secure code reads them raw: FrameControlsManager.lua:17, 91, 118, 419, 520, 665, 672); never pass a function as `shouldFocusFrame` (:428-429, "Intentionally missing taint barrier"). Two addons do this in the field: APR (`APR-Core/integrations/Gamepad.lua:195-265`, hides its windows on `PLAYER_REGEN_DISABLED`) and salty-max's addon-kit (`Kit.lua:3423-3500`, defers in combat and settles on `PLAYER_REGEN_ENABLED`). APR's only related issue ([#591](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/issues/591)) shows the manager's fields still secure, weak evidence since it doesn't say whether the Gamepad UI was on. Nobody has published a clean `taint.log` for this exact pattern.

### 2.5 Detecting gamepad use

- Both clients: `C_GamePad.IsEnabled()` (pad input switched on) and `GAME_PAD_ACTIVE_CHANGED(isActive)` (last input came from the pad or not). `GAME_PAD_CONNECTED`/`DISCONNECTED` for hot-plug.
- Forever: `IsUsingGamepad()`, `InputUtil.IsGamepadUIEnabled()`, `INPUT_DEVICE_INTERFACE_TRANSITION(newMode, oldMode)`. Avoid `InputUtil.RegisterGamepadInit` etc.; they put AltArmy callbacks into Blizzard's tables (run via `secureexecuterange`, `Blizzard_SharedXML/InputUtil.lua:76-81`). Register the event on AltArmy's own frame instead.
- Brand for glyphs: `C_GamePad.GetDeviceMappedState(id).labelStyle` (forever `Shared/InputIcons/InputDeviceIconSetManager.lua:1-60`), or DialogueUI's approach of matching `GetDeviceRawState(id).name` against XBOX/PLAYSTATION (`Code/Utility/DeviceUtil.lua:157-178`).
- Improved Forever and WoWXIV switch between "pad mode" and "mouse mode" on the input used last (`GAME_PAD_ACTIVE_CHANGED` plus mouse movement, `ImprovedForever/Input.lua:1-60`); DialogueUI has an explicit setting. Note from Improved Forever: setting a gamepad script turns gamepad input on for that frame, so call `EnableGamePadButton(false)` until it is wanted (`ImprovedForever_Auction/AuctionBuyClassic.lua:2262-2264`).

### 2.6 Tooltips

- **ConsolePort** runs a node's `OnEnter`/`OnLeave` when its cursor lands and leaves (`ConsolePort_Cursor/View/Cursor.lua:534-550`), re-anchors `ANCHOR_CURSOR` tooltips (`Controller/Hooks.lua:371-380`; AltArmy has no `ANCHOR_CURSOR` uses), and skips `OnEnter` on disabled buttons (Cursor.lua:534), so tooltips explaining a disabled control won't show there.
- **Smart navigation** calls `FocusEnter()` (presumably fires `OnEnter`; inferred). Frames with only `OnEnter` are never focused, so their tooltips are unreachable unless marked focusable.
- **The virtual cursor** behaves like a mouse.
- Code that polls the real mouse (`MouseIsOver`, `GetMouseFocus`, `IsMouseOver`, `GetCursorPosition`) sees nothing under ConsolePort's or smart navigation's cursors. Plumber adds an `or ConsolePort:GetCursorNode() == f` branch for this (`Plumber/API.lua:4733-4752`).

### 2.7 Text entry and the export string

- **No on-screen keyboard** in Blizzard's UI on any client (no API or template hits in any branch). Smart navigation treats EditBoxes as stops (Utility.lua:264), and Forever's chat gives its own edit box focus explicitly (forever `Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua:196`), but characters still need a physical keyboard or an OS/Steam keyboard. Steam Deck players open Steam's keyboard by hand (Steam+X); a Blizzard forum thread reports Deck players buying keyboards ([thread](https://us.forums.blizzard.com/en/wow/t/steamdeck-forever/2356531), fetched as a search summary only).
- **ConsolePort_Keyboard** (a separate module, `LoadOnDemand`, `## DefaultState: disabled`, TOC lists 16001 and 20506) opens a radial keyboard for any focused EditBox by watching `GetCurrentKeyBoardFocus()` (`ConsolePort_Keyboard/Core/Observer.lua:1-40`), unless the box has the `hidekeyboard` attribute (`ConsolePort_Keyboard/Database.lua:8`). AltArmy's EditBoxes work with it as they are. Keep live `OnTextChanged` filtering cheap; the keyboard inserts one character at a time.
- None of the surveyed native-controller addons offers pad text entry. Improved Forever replaces number fields with steppers and leaves search to keyboard/mouse (`ImprovedForever_Auction/AuctionBuyClassic.lua:180-190`). The lesson for AltArmy: steppers, toggles and pick-lists instead of typed values; keep search optional.
- **`CopyToClipboard` is restricted for addons** on every client (`OsDocumentation.lua:10`, `HasRestrictions`; the [wiki](https://warcraft.wiki.gg/wiki/API_CopyToClipboard) says secure code only). WoWXIV notes that taint even blocks Blizzard's own path (`logwindow.lua:948-949`). ConsolePort doesn't call it. A Copy button is almost certainly not possible (untested; `/run CopyToClipboard("x")` would confirm).
- **QR code** is how ConsolePort shares a link: a popup with a QR code plus a highlighted EditBox carrying `hidekeyboard` (`ConsolePort_Config/View/About/About.lua:175-206`), via LibWoWQRCode, which wraps [speedata/luaqrcode](https://github.com/speedata/luaqrcode) (BSD-3; LibWoWQRCode has no licence file of its own, so use luaqrcode directly). Byte mode tops out at 2,953 bytes (version 40-L). Estimates from the export format (raw DEFLATE + 8/6 printable overhead, not the addon's real output): the golden fixture is 308 chars (version 11), a 4-character Forever account with 237 recipes about 1,225 chars (version 25, 117×117 modules), a 15-character TBC account with 1,652 recipes about 3,080 chars, which **does not fit** one code. Options: several numbered codes, or Base45 in alphanumeric mode (needs a new decoder on the site). A scanned code also lands in the phone's session, so the site would need a `/paste#AAX1…` route opened while signed in. Version-40 density on screen is untested.
- **Alt Army Sync** uploads the SavedVariables file with no copy step, but it is Windows-only and looks only under `C:\Program Files*` (`site/src/altarmy_site/wowfiles.py:11-12`); under SteamOS/Proton it is unverified.

---

## 3. How other addons do it

### 3.1 ConsolePort's interface cursor

How AltArmy is found: the cursor scans `UIPanelWindows`, `UISpecialFrames` and `UIMenus`, and hooks `ShowUIPanel`, `StaticPopupSpecial_Show`, `HelpTipTemplateMixin.Init` and the modern `Menu` manager (`ConsolePort_Cursor/Database.lua:161-175`; `Controller/Stack.lua:252-338`). The Menu manager exists on all three clients (anniversary `Blizzard_Menu/DropdownButton.lua:124`). Frames found are tracked while visible and get `nodepass` (the frame itself is not a node, its children are scanned: Stack.lua:111-131). Anonymous frames are rejected (Stack.lua:30-42). Discovery is lazy, on the next stack update, so a dialog created on first open may not get the cursor until its next show.

AltArmy is already in `UISpecialFrames`: `AltArmyTBC_MainFrame` (`Core.lua:87-88`) and seven dialogs (`UI/BankAltSuggestDialog.lua:37-38`, `LinkAccountDialog.lua:22-23`, `GuildShareOnboarding.lua:264-265`, `LinkAccountsOnboarding.lua:121-122`, `ProfitExportDialog.lua:31-32`, `RestedXpQuestRewardConflictDialog.lua:62-63`). Not registered: the alert frames (`Data/Cooldowns/CooldownAlerts.lua:19`, `Data/Gear/GearUpgradeAlerts.lua:1068`, `Data/MailAlerts.lua:16`) and the Gear drop box.

**Node rules** (`ConsolePortNode.lua`): recursion through `GetChildren` only, so FontStrings, textures and hyperlinks are never nodes (:339-356). A node is visible, not forbidden, mouse-enabled, not a `ScrollFrame`, without `nodepass`, and either a Button, CheckButton, EditBox or Slider, or **mouse-motion enabled** (any `EnableMouse(true)` frame) (:117-122, :241-257). It must be on screen and intersect its innermost scroll/clip ancestor (:263-334). Mouse-enabled frames that are not nodes become "rects" that hide nodes beneath them at a lower level (:372-387). Movement picks the best candidate in the pressed direction, first among the current node's siblings, then across the stack (`ConsolePort_Cursor/View/Cursor.lua:382-431`), so grouping related controls under one parent helps.

**Clicks**: a Button/CheckButton with `OnClick` (or with no `OnMouseDown/Up`) gets a real secure click with `LeftButton` or `RightButton` through an override binding (Cursor.lua:555-564, :624-641; `ConsolePort/Controller/Input.lua:112-122, 245-280`). Other nodes get `OnMouseDown`/`OnMouseUp` emulated with an explicit button name (Cursor.lua:336-361; the comment says "may be unsafe"). Modifier clicks work because ConsolePort assigns pad buttons to `GamePadEmulateShift/Ctrl/Alt` (`Console.lua:18-44`). Holding A and pressing a direction calls `OnDragStart` (:643-657). B clicks the nearest ancestor's `.CloseButton` or `_G[name.."CloseButton"]` (:659-693) unless the node has `OnCancelClick`. Y calls `node.OnSpecialClick` and toggles EditBox focus (`Controller/Hooks.lua:19-37`). **Sliders can't be changed** (Cursor.lua:590-592 is a TODO).

**Scrolling**: when the selected node's scroll ancestor is unchanged, a plain `ScrollFrame` is scrolled vertically to centre it; a ScrollBox scrolls with `ScrollToElementDataIndex` using the row's `GetElementDataIndex`, which Blizzard's `ScrollBoxListView` sets on both clients (`ScrollBoxListView.lua:94`) (`Controller/Scroll.lua:17-95`). Vertical only. Shift+D-pad paging works for ScrollBoxes and for wheel-enabled frames with a named Slider child (Scroll.lua:112-167; ConsolePortNode.lua:285-305; Cursor.lua:609-612 needs named step buttons).

**Addon-facing API** (`ConsolePort/API.lua`, all safe to call from insecure code, guard with `if ConsolePort then`):

- `ConsolePort:AddInterfaceCursorFrame(frameOrName)` / `RemoveInterfaceCursorFrame` (:143-165): registers a named frame, waiting for the cursor module to load. It is filed under ConsolePort's own key, not the calling addon; the frame must exist when called.
- `ConsolePort:SetCursorNode(node)`, `SetCursorNodeIfActive(node)`, `GetCursorNode()`, `IsCursorNode(node)`, `IsCursorActive()`, `SetCursorObstructor(key, bool)` (:181-228).
- `ConsolePort:ForceKeyboardFocus`, `ToggleHintFocus`, `GetFormattedButtonCombination` (:85-127).
- Node attributes set with `frame:SetAttribute(name, value)` (`ConsolePort_Cursor/Database.lua:200-211`; `ConsolePortNode.lua:30-35`): `nodeignore` (skip the frame and its subtree), `nodepass`, `nodesingleton`, `nodepriority` (first pick), `nodeignoredrag`, `nodeignorescroll`, `nodeignoremime`, `nodespecialclick`, `nodecancelclick`, `nohooks`; `hidekeyboard` for the keyboard.

ConsolePort is GPL-family licensed (ConsolePortNode GPLv2, `ConsolePortNode.lua:7`; ConsolePort `LICENSE.md`): integrate through the API and attributes, don't copy code. No `OptionalDeps` entry is needed.

### 3.2 Addons with their own controller support

| Addon | Clients (TOC) | Technique | Lesson for AltArmy |
|---|---|---|---|
| DialogueUI / YUI-Dialogue | 16001, 20506, live, … | One hidden frame with `OnKeyDown`/`OnGamePadButtonDown`, `EnableGamePadButton(true)`, `SetPropagateKeyboardInput(not handled)` so unused buttons reach the game (`Code/Dialogue/KeyboardControl.lua:252, 275-277, 306-326`). Pad buttons are mapped onto keyboard actions (PAD2/PADBACK → ESCAPE). Its own linear focus list (`IndexGamePadObject`, `FocusObjectByDelta`, `DialogueUI.lua:3270-3351`) reuses each button's `OnEnter`/`OnLeave`; scrolls near edges; D-pad repeat 0.375 s then 0.125 s. LB/RB switch tabs, right stick scrolls (`BookUI.lua:1731-1778`), Y toggles tooltip compare info. | The most portable model: no secure code, works on both clients. |
| Immersion | 16001, 20506, live, … | `OnGamePadButtonDown = OnKeyDown`, propagation on by default, off only when handled and out of combat (`Logic/Frame.lua:425-473`); focus via `LockHighlight` + `OnEnter` (`Logic/Controller.lua:290-350`); optional ConsolePort hint bar (:11-146). | Share one handler for keyboard and pad. |
| WhatsTraining | 16001, 20506, 11509 | Forever-only layer loaded by TOC line `Forever\Forever.xml [AllowLoadGameType camelot][ExcludeLoadGameType classic]` (`WhatsTraining.toc:58`). Uses Blizzard's `InputIconTextureFrameTemplate`, `SmartNavigationPointerTemplate`, `InputPromptLegends.CreateInputLegend`, reads `SmartNavigation:GetCurrentButton()`, but runs its **own** focus logic and captures the pad only while open and out of combat (`Forever/Controller.lua:15-86, 517-648`). Own menu with `HandleButton(D-pad/A/B)` (`Forever/Menu.lua:319-340`). | The packaging precedent for a two-client addon with Forever-only polish. |
| Improved Forever | Forever only | Hidden 1×1 buttons bound with `SetOverrideBindingClick` per pad key while the window is open, cleared on close, out of combat (`ImprovedForever/Menu.lua:266-380`); pad/mouse mode by last input; game glyph atlases (`Pad.lua`); steppers for numbers. Coexists with Forever's manager (L2/R2 switch between its window and the game's) and documents its taint traps (§2.4). | Override bindings beat the game's pad bindings, but can't change in combat. Read its taint notes before phase 2. |
| Questie `AddonDialog` | — | `EnableGamePadButton(true)`; PAD2 closes, other buttons propagate (`Dialog.lua:206-208, 347-360`). | The minimum: B closes. |
| WoWXIV | live only | A `SecureActionButtonTemplate` menu cursor with a focus stack and modal stack, driven by override bindings (`gamepad/menucursor/menucursor.lua`). | Heavier than AltArmy needs; the modal-stack idea fits AltArmy's popups. |
| Dominos | all | Uses Forever's `C_GamepadUI` for bar paging and disables itself when the Gamepad UI style is on (`Dominos/Dominos.lua:43, 69`). | Feature-test Forever-only APIs. |
| Bartender4 | all | No gamepad code. | — |

The return value of `OnGamePadButtonDown` (Questie and WhatsTraining return true/false as a "propagate" signal) is not documented by Blizzard; rely on `SetPropagateKeyboardInput`.

### 3.3 Light-weight compatibility patterns

| Pattern | Who | Notes |
|---|---|---|
| Rely on `UISpecialFrames`/`UIPanelWindows` discovery | ConsolePort itself | AltArmy already does this. |
| `if ConsolePort and ConsolePort.AddInterfaceCursorFrame then ConsolePort:AddInterfaceCursorFrame(f) end` | BetterBags (`integrations/consoleport.lua:14-49`), Plumber (`Modules/Timerunning/LegionRemix_UI.lua:1531-1535`), EllesmereUI | For named windows no manager catches. Nameless overlays must be parented to a named root. |
| `nodeignore` on scrollbars and decoration, `nodepriority = 1` on the default control | BetterBags (`frames/grid.lua:163, 185`), Plumber (:1528-1537) | Costs nothing without ConsolePort. |
| Invisible Buttons over cards as cursor-snapping targets | Plumber (:1806-1855) | For hover-only areas. |
| `ConsolePort:SetCursorNode(firstItem)` when a menu opens | BetterBags | ConsolePort does this itself only for StaticPopups and Blizzard Menus (`Controller/Mods.lua:12-49`, `Stack.lua:317-322`). |
| `GamepadMode.FrameControlsManager:FrameShown/FrameHidden` in `OnShow`/`OnHide`, gated on `IsGamepadUIEnabled`, deferred out of combat | APR, salty-max addon-kit | The Forever-native counterpart; see §2.4. |
| `SmartNavigation_*` helpers for ignored/focusable frames and jump overrides | APR, ExtraStats (`forever/Controller.lua`) | Forever only, out of combat. |

---

## 4. AltArmy UI changes

### 4.1 Shared widgets to change first

Most problems come from a handful of factories in `UI/Theme.lua`; fixing them fixes their ~60 call sites. Call counts are from grep over `AltArmy_TBC`.

| Widget | Calls | Problem with a pad | Change |
|---|---|---|---|
| `Theme.CreateLabeledCheckbox` (`UI/Theme.lua:2513`) | 27 | Each row is a CheckButton **plus** a full-width `hoverRegion` Frame with `OnMouseUp` (:2529-2572): two stops per row for both smart navigation and ConsolePort, overlapping. 18 px box. | Make the whole row one CheckButton (stretch the hit rect over the label) or `EnableMouse(false)` on the hover region and drive the tint from the check's `OnEnter`. |
| `Theme.CreateOptionsSlider` (:2595) | 2 (Window Scale; Font size hidden) | A plain `Slider`: smart navigation never focuses it; ConsolePort focuses it but can't change it. **Blocker.** | Add `-`/`+` step Buttons, or use Blizzard's `MinimalSliderWithSteppersTemplate`. |
| `Theme.CreateRangeSlider` (:2716; the Level filter) | 1 (`UI/CharacterFilterControls.lua:120`, every settings panel) | A plain Frame; `OnMouseDown` sets the value from `GetCursorPosition` (:2812-2856). Not a ConsolePort node (no motion script); under smart navigation a press jumps to wherever the hardware cursor is. Under the virtual cursor it probably works, but the `OnUpdate` has no `IsMouseButtonDown` check, so it can stick to the cursor if the button-up is lost. **Blocker.** | Two pairs of `-`/`+` Buttons (low, high), or two stepper Buttons; add an `IsMouseButtonDown` guard; mark the bar ignored for navigation. |
| `Theme.CreateSingleSelectDropdown` (:3330), `CreateMultiSelectCheckboxDropdown` (:3590), `CreateDropdownMenuItem` (:3165), ScoreSortRow's provider popup | 8 + 3 | Custom popups (a `BackdropTemplate` Frame, :3367), not Blizzard menus: focus isn't moved in, B closes the whole window, long lists scroll by wheel. | Move them onto Blizzard_Menu (`MenuUtil`, `WowStyle1DropdownTemplate`, present on all three clients), as `Theme.CreateFilterDropdown` already does on the native path (:3945-3967). Both ConsolePort (Cursor.lua:363-379) and smart navigation (FrameControlsManager.lua:250-265) handle those. Otherwise: focus the selected row on open (`SetCursorNodeIfActive`), close on B via `OnCancelClick` / `SmartNavigationCloseHandler`, reuse the existing open-popup registries `Theme._openSingleSelectDropdowns` and `_openMultiSelectCheckboxDropdowns` (:3242, :3578) as the popup stack. Replace the 3-item scan-mode list with radio buttons. |
| `Theme.AttachLabelHelpIcon` (:3007) | 2 (`UI/GearUpgradeOptions.lua`) | The icon has mouse off; an `OnEnter`-only hit Frame carries the tooltip (:3018-3033). Unreachable under smart navigation. | Show the text inline, or make the icon a Button whose click toggles the tooltip. |
| `Theme.AttachSettingsHelpIcon` (:2988) | 6 | The text already shows when the row's checkbox is focused (hooked at ~:2975-2984). The scan-mode icon sits beside a dropdown, so there the icon is the only way in. | Show help on focus of the owning control; ignore the icon for navigation. |
| `Theme.CreateHorizontalScrollBar` (:1924) and `HorizontalListScroll` | 6 | A custom Slider dragged with `GetCursorPosition` while `IsMouseButtonDown(1)` (:1963-1991). Neither smart navigation nor ConsolePort scrolls horizontally. Off-screen columns are unreachable. | Scroll horizontally to the focused cell (hook focus/`OnEnter`), add page-left/right Buttons or shoulder bindings, keep the bar for the mouse. |
| `Theme.CreateVirtualScrollBinding` (:2070; the Summary list) | 1 | A fixed row pool with its own offset; the nested ScrollFrame has no real range (`Tabs/TabSummary.lua:257-269`). Focus-follow scrolling can't work. The native `MinimalScrollBar` steppers are reachable, so it is slow, not impossible. | Move to `WowScrollBoxList` (as Search already is), or scroll one row when focus reaches an edge row. |
| `Theme.CreateVerticalScrollBinding`/`Viewport` (:2185, :2360) | ~18 | Real ScrollFrames, so focus-follow scrolling works; wheel-only otherwise. The binding owns `OnVerticalScroll`; an outside `SetVerticalScroll` may leave the bar stale (inferred). | Re-sync the bar from an `OnVerticalScroll` hook; expose `ScrollToFrame`. |
| `Theme.BindInteractableHover` (:718), `InstallRowHoverHighlight` (:746), `SkinButton` (:506), `InstallHoverTint` (:631) | ~19 / ~48 | Focus feedback is only the hover tint from `OnEnter`; `BindInteractableHover` mouse-enables child frames, which become extra ConsolePort nodes. | One `Theme.SetFocused(target, on)` used by `OnEnter` and by `OnSmartNavSelect`; don't make children separate nodes. |
| `UI/ItemActions.lua` `GetClickAction` (:26-31) with `UI/ItemSlotButton.lua` | Gear, Search, Inventory | Preview = Ctrl+click, link = Shift+click; a plain click does nothing; right-click registered but unused. | A plain/right click opens a small Blizzard_Menu: Link to chat, Preview, Search across characters, Upgrade check. Keep the modifier shortcuts. |
| `UI/TopTabs.lua`, `UI/SideTabs.lua` | all tabs | On Forever top tabs are `TabSystemTemplate` (TopTabs.lua:63-66), not PanelTemplates, so `GamepadTabIndicatorsTemplate` can't track them; side tabs are `LargeSideTabButtonTemplate` Frames found through `OnMouseUp` (SideTabs.lua:34; forever `SharedUIPanelTemplates.xml:1008`). Icon-only on Forever, names in tooltips. | Add `SelectNext`/`SelectPrev` and bind LB/RB (top) and another pair (side) on an AltArmy-owned frame while the window is open, out of combat. LT/RT are taken by FrameControlsManager window paging. |
| Dialog shells (5 dialogs × `buildDialog`, plus `ProfitExportDialog`) | 7 | Unnamed `UIPanelCloseButton` (e.g. `LinkAccountDialog.lua:41`), or a "Close" text button (`ProfitExportDialog.lua:104-109`): neither ConsolePort nor smart navigation finds it, so B can't close. Drag-only headers become ConsolePort nodes. | One `Theme.CreateDialog`: `dialog.CloseButton = closeBtn`, `nodeignore` on the header, a default focus button (on the safe choice), and Forever registration (phase 2). |
| Main window (`Core.lua`) | — | On Forever it is `PortraitFrameTemplate` (`Core.lua:61-63`), which has `.CloseButton`, so B works. The `BackdropTemplate` fallback's button is published only as `_G.AltArmyTBC_HeaderCloseButton` (:363-368). Resize grip is a Button with `StartSizing` on `OnMouseDown` (:228-249). | Set `main.CloseButton` on the fallback; `nodeignore` / ignore the grip; size presets and a Reset size button in Options. |
| Real-mouse checks | — | `MouseIsOver`/`GetMouseFocus`/`IsMouseOver` in `Tabs/TabGuild.lua:3024-3043, 3369, 3410, 3458, 3487`, `TabCooldowns.lua:1659, 2837-2856`, `TabEconomy.lua:624-632`, `TabReputation.lua:665-666`; `GetCursorPosition` in `TabGraph.lua:353, 438`. The Theme stepper checks (:962, :983) are fallbacks; their state is already set from `OnEnter`. | Add `or (ConsolePort and ConsolePort:IsCursorNode(f))`, or drive state from `OnEnter`/`OnLeave`/`OnSmartNavSelect`. |

### 4.2 Per tab and area

Severity: **blocker** = can't be done with a pad on any route; **major** = hard or loses information; **minor** = awkward. "SN" = Forever smart navigation (phase 2), "CP" = ConsolePort, "VC" = virtual cursor.

#### Window shell and toolbar

| Element (file:line) | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Opening (`UI/Options.lua:2308`; no `Bindings.xml`) | `/alta`, minimap button | No bindable action; slash needs typing; minimap reachable only with VC/CP unlimited mode. | major | `Bindings.xml` with "Toggle Alt Army" (and per-tab if wanted). |
| Window on show (`Core.lua:442, 471`) | `:Show()`, `UISpecialFrames` | VC not freed; SN not active. | major | Free the VC on show (unless ConsolePort); phase 2 `FrameShown`. |
| Title drag (`Core.lua:93-106`) | `StartMoving` | Drag only; harmless (window is centred and clamped). | minor | `nodeignore`; position presets optional. |
| Resize grip (`Core.lua:228-249`) | Drag; tooltip "Drag to resize" | SN/CP press = down+up at once, nothing happens. Window Scale slider (the alternative) is also unusable. | major | Width/height presets and a Reset size button calling `AltArmy.ResetWindowSize`. |
| Header search box (`Core.lua:383-399, 912-943`; `Theme.lua:1640-1688`) | Typing enters Search mode | The only way into Search; 14 px clear button. | **blocker** without a keyboard | "Search for this" from item slots and rows; recent queries list; B clears text (as `TabInventory.lua:229-231` does). |
| Settings gear (`Core.lua:475-501, 629-637`) | Toggles the side panel | Icon-only; focus not moved into the panel. | minor | Move focus to the panel's first control on open (`SetTargetButtonForFrame` / `nodepriority`), back on close. |
| Slide transition (`UI/SlideTransition.lua:116-193`) | 0.2 s slide | Focus may stay on the outgoing page (inferred). | minor | Re-target in `onFinish`. |

#### Summary (`Tabs/TabSummary.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Character list scroll (243-279, 1014-1030) | Faux pool, wheel, MinimalScrollBar | No native range; neither SN nor CP scrolls it; only the bar's steppers. | major | ScrollBox, or edge-row scrolling. |
| Warning "!" (684-704, 1067-1086) | 20 px Frame, `OnEnter` only, mouse-enabled on every row | Instructions are hover-only; SN can't focus it; CP stops on empty cells. | major | One row Button whose focus shows all row tooltips; disable mouse when nothing is missing. |
| Rest XP hit (731-766) | `OnEnter`-only Frame | Same. | major | Fold into the row tooltip. |
| Name overlay (770-786) | Mouse-enabled on every row | Extra CP stop. | minor | Fold into the row. |
| Main star, bank-alt icon (788-848) | 16 px Frames, `OnMouseUp` (LeftButton) | Tiny; action discoverable only on hover. (SN's click passes as `LeftButton`, so the click works.) | major | Larger hit rect, or "Set as main"/"Character options" in a row action menu. |
| Sort headers, section headers (281-345, 603-665) | Buttons with `OnClick` | Work. Headers past the right edge need horizontal scroll. | minor | — |
| Horizontal bar (381-447) | Custom Slider drag | See §4.1. | major | Shared fix; or reflow columns when the settings panel opens. |
| Settings panel (449-501) | Shared filter controls | Range slider, popups, double checkbox stops. | major | Shared fixes. |

#### Reputation (`Tabs/TabReputation.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Grid cells (469-521, 842-930) | Frames with `OnEnter` only; exact progress only in tooltip | SN can't focus them. CP can, but cells sit in a full-height inner horizontal ScrollFrame (382-385), so auto-scroll targets that frame (range ~0) and neither axis follows. Columns are created only when scrolled into view (932-981). | major | Make cells Buttons or one moving cell cursor; scroll both axes to the focused cell; show exact progress inline. |
| Character headers (155-177, 392-455) | Buttons; sort in `OnMouseUp` | Work. Full name on hover. | minor | Move the handler to `OnClick` (`RegisterForClicks` already set, 412-414). |
| Score "!" (`scoreHover`, 430-450) | Frame inside the header | Hover-only, overlapping node. | major | Put its text in the header's own tooltip. |
| Faction rows (585-674, 707-786) | Button with `OnMouseUp`; Zygor button tested with `IsMouseOver()` (662-670) | Under CP/SN the `IsMouseOver` check reads the real mouse, so the wrong branch may run. Zygor button 16 px wide, icon-only. | major | Use `OnClick`, drop the `IsMouseOver` check (the child button owns its click). |
| Faction filter EditBox (290-312) | Typing | Needs a keyboard. | major | Non-text filters (category toggles, "with progress only"). |
| Vertical scroll | Real ScrollFrame | Works for faction rows (SN and CP). | — | — |

#### Gear (`Tabs/TabGear.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Grid cells (3527-3600; 1221-1233) | Frames with `OnMouseUp`/`OnEnter`; Ctrl/Shift clicks | Reachable, but cells' scroll group is the full-height inner horizontal ScrollFrame (1647-1656), so **vertical auto-scroll fails** in SN and CP and hidden rows still count as valid; horizontal never scrolls. Modifier actions. | **blocker** (scroll) | Scroll both axes from the focused cell; LB/RB to page columns; row-major focus; item action menu. |
| Column headers (1764-1845) | Frames, `OnMouseUp` (selects for compare) | Full name hover-only; stop even in grid mode. | major | Button enabled only in compare mode; show full name in the compare header. |
| Score "!" (1789-1803) | `OnEnter`-only | Hover-only. | major | Visible Button opening the explanation. |
| Upgrade Check drop zone (1909-2028; 3416-3446) | `OnReceiveDrag` or click with item on cursor; right-click clears | Item must be picked up from bags (VC: clumsy but possible; SN clears cursor items when it closes, SmartNavigation.lua:330-353). Clear is right-click only. | **blocker** | "Choose item…" Button listing equippable items from bags/bank/quest rewards; visible Clear. |
| Compare focused slot, equipped icons (2043-2195) | Frames; equipped icons `OnEnter` only | Item details and the comparison target are hover-only; right-click clears. | major | Buttons; print item names in the panel; Change…/Clear Buttons. |
| "?" hints (2137-2170, 2967-2984) | 12–14 px Buttons, `OnEnter` | Tiny. | major | Larger hit rect or footer text on row focus. |
| Compare stat list (2433-2470) | Wheel viewport, no focusable rows | SN won't scroll it. | major | Right-stick/shoulder scroll, or focusable rows. |
| Score sort button, provider dropdown (1478-1625) | Small Button; custom popup | See §4.1. | minor/major | Shared fixes. |
| Options EditBoxes (`UI/GearUpgradeOptions.lua:161-216`) | Numeric typing (44×20) | Needs a keyboard. | major | `-`/`+` steppers. |
| Quest reward badge (`UI/QuestRewardIndicators.lua:131-158`) | 22 px Button over Blizzard's reward button | Overlaps the reward button; A may hit the wrong one (inferred). | major | Visual-only badge; offer "view details" elsewhere. |
| Upgrade alert chat link (`Data/Gear/GearUpgradeAlerts.lua:108-112`) | Custom hyperlink in chat | Chat links are FontString text, not reachable. | major | A toast with a "View details" Button, or a binding "Open last upgrade". |

#### Search (`Tabs/TabSearch.lua`) and Inventory (`Tabs/TabInventory*.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Item result rows (696-736, 920-955) | Frames, `OnMouseUp`; actions only with Ctrl/Shift | A plain press does nothing. | major | Button rows, action menu on press. |
| Recipe rows and Character overlay (739-918, 957-981) | Shift-link, click toggles groups; overlay Button whispers | Two overlapping stops per row; last-online and grouped names hover-only; dead buttons. | major | One stop per row; whisper in the action menu; expand chevron. |
| Sticky section headers (381-440) | Mouse-enabled header Frames with sort Buttons | Float over rows; header Frames are empty CP nodes. | major | Ignore the header Frames; sort via a cycle binding or dropdown. |
| List scrolling (208-305) | WowScrollBoxList inside a horizontal ScrollFrame | **Vertical works** in SN and CP (the ScrollBox is the rows' innermost group). Horizontal fails. | major (horizontal) | Drop the horizontal layer, or let the settings panel overlay the list. |
| Filter dropdown (`Core.lua:804-837`) | Appears only once the box has text | Unreachable without typing. | major | Keep it visible in Search mode. |
| Recipe level Min/Max (`TabSearchSettings.lua:99-185`) | Numeric EditBoxes | Typing only. | **blocker** | Range slider replacement (steppers). |
| Professions/Difficulty/Source filters (`TabSearchSettings.lua:295-499`) | Custom multi-select popups | See §4.1. | major | Shared fix. |
| Inventory search (`TabInventory.lua:196-232`) | Typing | Convenience only. | major | "Highlight this item" from a slot. |
| Character picker, layout dropdown (234-279) | Custom single-select | See §4.1; long alt lists by wheel. | major | Shoulder bindings to cycle characters and layouts. |
| Item slots (`UI/ItemSlotButton.lua:91-217`) | Buttons; Ctrl/Shift; right-click registered but unused | Good targets; actions need modifiers. | major | Action menu (§4.1). |
| Bag headers (`TabInventoryBags.lua:141-162`) | `OnEnter`-only Frames | SN can't focus; scan-estimate note hover-only. | minor | Show note inline or mark focusable. |
| Scroll viewports (Bags 325-347) | Real ScrollFrame; slots rebuilt on every Refresh (290-297) | Focus may jump on refresh. | minor | Keep focus by bag/slot key. |
| Mail rows (`TabInventoryMail.lua:222-334`) | Button rows with child attachment Buttons | Nested stops. | minor | Navigate by attachment; details pane. |

#### Guild (`Tabs/TabGuild.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Group row gear (3305-3332, 3354-3373, 3466-3506) | 18 px gear, **hidden until hovered**; the only way into group edit; hover from `GetMouseFocus`/`MouseIsOver`, re-synced on every roster refresh (4527) | SN skips hidden frames (`IsButtonValid` requires `IsVisible`, SmartNavigation.lua:1212); focus can't keep it shown. | **blocker** | Show the gear always (dimmed), or put Edit in the expanded group; drive hover from focus. |
| Add character with autocomplete (1502-1620, 2725-2797) | Typing; suggestions close 0.15 s after focus is lost (2749-2752) | Moving focus to a suggestion closes the list; needs typing. | **blocker** | A pick-from-roster list; keep suggestions open while focus is in the popup. |
| "M" and "!" marks (3376-3459, 3593-3617) | "M" `OnEnter`-only Frame; "!" 14 px Button | Hover-only information. | major | Status in the row tooltip or a visible line. |
| Recipe rows (3917-3963) | Frames; only Shift-click links | A plain press does nothing. | major | Buttons; plain press links (when chat is open) or opens an action menu. |
| Searches, override name, display name (698-726, 4659-4689, 1214-1322) | EditBoxes | Typing. | major | Optional; presets for the override name. |
| Rows, footer, wizard buttons | Buttons | Work; focus lost after relayout or slide. | minor | Default focus after each `slideSwap`. |

#### Cooldowns (`Tabs/TabCooldowns.lua`, `TabCooldownsRaids.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Compose-mode rows (1541-1754, 1205-1245) | Row Button + `catBtn` + `matSlot` Frame + 16 px CheckButton; send preview hover-only; tint by `MouseIsOver`; refresh deferred while `IsMouseButtonDown` | Four overlapping stops; allocation hover-only; a refresh can recycle the focused row. | **blocker** | One row Button that toggles; show "send N / will have M" as a column; ignore the inner controls. |
| Recipe cell and picker (1454-1503, 529-786) | Tooltip with reagent counts; picker auto-focuses its search box (736) | Reagent counts hover-only; focus lands in an EditBox. | major | Details strip; don't auto-focus; B closes. |
| Send bar (858-909) | 24×20 steppers; `sendHit` `OnEnter`-only overlay over Send | Overlay hides the reason under SN and steals CP focus. | major | Inline reason text; D-pad/triggers for the stepper. |
| Dungeons rows (`TabCooldownsRaids.lua:268-299`) | Frames with mouse disabled; rebuilt every second (337-338) | Nothing focusable, so the list can't be scrolled by focus; "*" unexplained. | **blocker** | Focusable rows; don't rebuild unchanged rows. |
| Crafting list rebuilds | Rows kept unless the row set changes (3133) | Focus lost only on changes. | minor | Refocus by key. |

#### Economy (Forever only; `Tabs/TabEconomy*.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Currency cells (`TabEconomyCurrency.lua:392-451, 595-633`) | `OnEnter`-only Frames | SN can't focus; CP can but cells are inside a full-height inner horizontal ScrollFrame (no vertical follow). | **blocker** | Details strip per focused row/column, or focusable cells. |
| Currency columns (635-703) | Windowed: off-screen columns hidden | Unreachable sideways. | **blocker** | `<`/`>` Buttons and shoulder bindings; scroll on outgoing focus. |
| Character headers (344-390) | `OnEnter`-only | Full name and missing data hover-only. | major | Focusable Buttons. |
| Waylaid / Writs rows (`TabEconomy.lua:517-663`; `TabEconomyWrits.lua:264-375`) | Buttons; long tooltip; "?" guess note via `cell:IsMouseOver()` in `OnUpdate` (626-638) | Tooltip can't be scrolled; guess note never appears under SN/CP. | major | Details pane rendering the tooltip lines; separate "Search AH" action. |
| Scan footer, filter dropdowns | Mixed | Shared issues. | minor | Shared fixes. |
| Supply Chain URL box (`TabEconomySupplyChain.lua:63-87`) | Read-only EditBox for Ctrl+C | Can't copy. | minor | Large plain text; `hidekeyboard`. |

#### Graph (`Tabs/TabGraph.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Drag-to-zoom (431-519) | `OnMouseDown` + `GetCursorPosition` until `IsMouseButtonDown` is false | SN/CP: zero-width drag, nothing zooms. VC: works if `IsMouseButtonDown` reports the trigger (unverified). | **blocker** (SN/CP) | LB/RB zoom around a cursor level, triggers to pan, Y to reset; maths in `GraphLogic` (reuse `NormalizeZoomRange`, `GraphLogic.lua:747`). |
| Data point markers (1021-1112) | 18 px `OnEnter`-only Frames, pooled per rebuild | Exact values hover-only; far too dense to navigate. | **blocker** | One focusable plot frame (`OnSmartNavClick` hook on Forever); D-pad steps level and series; fixed readout panel. |
| Option rows, Compare rows (586-648, 753-907) | Frame + CheckButton + label Button; hover preview runs `RebuildGraph` | Two stops per row; preview fires on every focus pass under CP. | major | One Button per row; preview on mouse hover only. |

#### Options and dialogs (`UI/Options.lua`, `UI/*Dialog.lua`)

| Element | Today | Gamepad problem | Severity | Change |
|---|---|---|---|---|
| Export (`UI/ProfitExportDialog.lua:76-77, 153-154, 171-172`; opened only by `/altarmy export`, `Options.lua:2312-2314`) | One-line EditBox, focused and highlighted for Ctrl+C | No way to copy; no button to open it; ConsolePort's keyboard pops over it. | **blocker** | An Export button in the UI; `hidekeyboard`; a QR code (§2.7); point pad players at Alt Army Sync. |
| Slash-only actions (`Options.lua:2308-2682`: export, resetsize, debug) | Typing | Unreachable. | **blocker** | Buttons for the user-facing ones. |
| Window Scale slider (`Options.lua:1557-1593`) | Slider | See §4.1. | **blocker** | Steppers. |
| "Turn on guild sharing" overlays (`Options.lua:820-858`) | `OnEnter`-only overlay Frames over disabled controls | SN focuses the disabled control underneath (no tooltip); CP sees two nodes. | major | Inline reason text; `SetMotionScriptsWhileDisabled` on the control. |
| Link accounts request (`UI/LinkAccountDialog.lua:63-123`) | Link / Not now | A stray A could link accounts. | major | Default focus on "Not now"; code shown on the Link button. |
| Two-press confirms (`Options.lua:2086-2101, 368-524`; `UI/LinkedAccountsOptions.lua:167-176`) | Same button relabels | A double tap commits. | minor | Confirm on a separate button. |
| Linked account rows (`UI/LinkedAccountsOptions.lua:47-64`) | Status text cut off (`SetWordWrap(false)`) | Unreadable on any input. | minor | Wrap or tooltip on focus. |
| AH scan button (`UI/AuctionScanButton.lua:70-112`) | Above the AH frame; scan kind in tooltip; settings icon has no tooltip | Outside the AH frame's rect; kind hover-only. | minor | Kind in the label; tooltip on the icon. |
| Onboarding queue (`UI/OnboardingDialogQueue.lua:44-89`) | One dialog per login | Doesn't take pad focus; marked shown anyway. | minor | Phase 2 registration; default focus. |

### 4.3 Cross-cutting issues

- **Hover-only information** is the biggest single theme: missing-data and rest XP in Summary, reputation progress, currency amounts and caps, gear comparison targets, reagent counts, Waylaid/Writs breakdowns, guildmate last-online, help icons, disabled-control reasons. Rule: anything a tooltip says must be reachable from a focusable control (Button, or `OnMouseUp` Frame, or a frame marked with `SmartNavigation_MarkFrameFocusable`), and the important parts should be visible text or a details pane.
- **Modifier clicks** (Shift link, Ctrl preview; `ItemActions.lua:26-31`, `TabGuild.lua:3952`, `TabSearch.lua:770, 891`, `TabGear.lua:1225, 1839, 3558`): work under CP and the VC (emulated modifiers) but are undiscoverable, and SN passes none. Add a modifier-free action menu.
- **Right-click** (clear drop zones, item slots): CP and the VC have it; SN only through an AltArmy binding.
- **Mouse wheel** (21 `OnMouseWheel` handlers): no pad route except focus-follow scrolling on real vertical ScrollFrames/ScrollBoxes, scroll-bar steppers, or a `SimulateMouseWheel` shim.
- **Horizontal scrolling**: supported by nothing; every horizontally scrolled grid (Summary, Gear, Reputation, Search, Currency, Cooldowns) needs AltArmy's own scroll-to-focus or paging, or a layout that doesn't scroll sideways.
- **Nested scroll frames** (Gear, Reputation, Currency put a full-height horizontal ScrollFrame inside the vertical one): cells belong to the inner frame in both SN (Utility.lua:278-325) and CP (ConsolePortNode.lua:263-334), so vertical follow fails too. Restructure so each scroll axis has its own container whose children are the rows, or scroll manually.
- **Drag**: window move, resize, horizontal bar, range slider, graph zoom, item drops. All need a non-drag alternative.
- **Resize**: presets instead of the grip.
- **Text entry**: search, filters, numbers, names. Steppers and pick-lists first; ConsolePort_Keyboard then works for free.
- **Pooled rows rebuilt under focus**: keep stable frames per key and refocus by key after a rebuild.
- **The export string**: §2.7.

---

## 5. Suggested phased plan

1. **Phase 0 — hygiene (both clients, ~1–2 days).**
   - Add `Bindings.xml` with a "Toggle Alt Army" binding (and list it in the TOC).
   - In the main frame's `OnShow`, unless ConsolePort is loaded: `if CanAutoSetGamePadCursorControl and CanAutoSetGamePadCursorControl(true) then SetGamePadCursorControl(true) end`.
   - Set `.CloseButton` on the fallback main frame and every dialog.
   - ConsolePort: `AddInterfaceCursorFrame` for the alert frames and any other named root outside `UISpecialFrames`; `nodeignore` on the resize grip, title drag strip, scrollbar parts and invisible hit frames; `nodepriority = 1` on each tab's default control; `hidekeyboard` on the export and URL boxes; `SetCursorNodeIfActive` on dialog/popup open.
   - Optional: a small frame that, while the window is shown and out of combat, takes D-pad up/down with `EnableGamePadButton` and calls `SimulateMouseWheel` (test first, §6).
   - An Export button and a Reset size button in the UI.
2. **Phase 1 — shared widgets (both clients, ~3–5 days).** The §4.1 table, in this order: sliders → labelled checkbox rows → dropdown popups onto Blizzard_Menu → help icons → item action menu → horizontal scroll-to-focus and paging → Summary list onto ScrollBox → replace real-mouse checks. Then the per-tab blockers that remain: Guild group gear, Guild roster picker, Cooldowns compose rows, Dungeons rows, Gear "Choose item…", Currency columns, Graph readout and zoom.
3. **Phase 2 — Forever native (Forever only, ~1 week, after a clean taint test).** In `OnShow`/`OnHide` of the main window and dialogs: if `InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()` and not in combat, call `GamepadMode.FrameControlsManager:FrameShown(frame)` / `FrameHidden(frame)`; on `PLAYER_REGEN_DISABLED` call `FrameHidden` (APR's approach), and settle deferred calls on `PLAYER_REGEN_ENABLED`. Add `SmartNavigationCloseHandler` (close the top popup first, return `true`), `SmartNavigation_MarkFrameFocusable` for hover-only frames that stay, `SmartNavigation_MarkFrameIgnored` for decoration and duplicate stops, jump overrides between side tabs/top tabs and content, `SetScrollFrameForFrame` per tab, and button prompts with `InputIconTextureFrameTemplate` / legends. Load this from a Forever-only file (`[AllowLoadGameType camelot]`, as WhatsTraining does) or feature-test every call.
4. **Phase 3 — own focus model (both clients, 2–4 weeks; only if demand grows).** A DialogueUI/Immersion-style navigator: per-tab ordered focus lists reusing `OnEnter`/`OnLeave`, `SetPropagateKeyboardInput` for unhandled buttons, LB/RB tabs, right stick to scroll, released in combat and when ConsolePort's cursor (`ConsolePort:IsCursorActive()`) or Forever's Gamepad UI is active.

---

## 6. Open questions needing in-game checks

Run on both clients unless marked Forever. Use `/console taintLog 1` (not 2, which can flood: `ImprovedForever/CLAUDE.md:181`), `/reload`, then read `Logs/taint.log` after `/console taintLog 0`.

| Question | Test |
|---|---|
| Does the virtual cursor's click trigger hold a real button? | Hold PADRTRIGGER over AltArmy with an `OnUpdate` printing `IsMouseButtonDown(1)`. |
| Does `OnMouseUp` arrive if the cursor turns off mid-drag? | Start the range slider drag, jump; see whether the handle stays stuck. |
| Is `SetGamePadCursorControl(true)` allowed from AltArmy's `OnShow`, in and out of combat? | `/run SetGamePadCursorControl(true)`; open the window by binding in combat. |
| Does `SimulateMouseWheel(-1)` from an `OnGamePadButtonDown` handler scroll a hovered AltArmy list? | Temporary handler on a frame with `EnableGamePadButton(true)`. |
| Do `OnGamePadButtonDown` events fire with `GamePadEnable` 0 and no ConsolePort? | `/dump C_GamePad.IsEnabled()`, `/dump GetCVar("GamePadEnable")`; register a handler. |
| Which GamePad CVars exist on 20506, and does `IsUsingGamepad` exist there? | `/dump GetCVar("GamePadEmulateShift")`, `/dump IsUsingGamepad`. |
| Is `CopyToClipboard` blocked for addons? | `/run CopyToClipboard("x")`; watch for ADDON_ACTION_BLOCKED/FORBIDDEN. |
| (Forever) Does `FrameShown` from AltArmy's `OnShow` focus the window with no taint? | With the Gamepad UI on: open AltArmy by binding; `/dump GamepadMode.FrameControlsManager.isUIFocused`; `/dump issecurevariable(GamepadMode.FrameControlsManager,"focusedFrame"), issecurevariable(GamepadMode.FrameControlsManager,"isUIFocused"), issecurevariable(GamepadMode.FrameControlsManager,"shownFrames")`; `/dump issecurevariable(SmartNavigation,"activeInfo"), issecurevariable(SmartNavigation,"currentButton")` (all should be `true`). Then navigate, LT/RT to bags, TOGGLEUIFOCUS out and in, close with B and with X, interact with an NPC and loot (watch for `SetPreferredGamepadInteractTarget` errors). Repeat 3+ times and once with registration off as a control. |
| (Forever) Is the window left in `shownFrames` after a combat close? | Open, enter combat, close, leave combat; `/dump #GamepadMode.FrameControlsManager.shownFrames`. |
| (Forever) Does `UISpecialFrames` Esc-closing taint the frame manager? | Same taint run with the window closed by Esc. |
| (Forever) Does SN's A press reach `OnMouseUp` as `"LeftButton"` with `upInside`? | AltArmy's dev dump (`AltArmy.Debug.Dump`) inside a row's `OnMouseUp`. |
| (Forever) Does `FocusEnter` fire `OnEnter`, and does `GetMouseFocus()` then return the focused frame? | Print from an AltArmy `OnEnter` while moving SN focus. |
| (Forever) Is the Gamepad UI on by default anywhere, and does `Blizzard_GamepadSoftCursor` load? | `/dump C_InputInterfaceStyle.GetCurrentStyle()`, `/dump PlatformIsHandheld()`, `/dump C_AddOns.IsAddOnLoaded("Blizzard_GamepadSoftCursor")`. |
| ConsolePort: is the main window picked up from `UISpecialFrames`, and do rows, tooltips, right-click and B work? | Install ConsolePort, open AltArmy, walk every tab and dialog. |
| ConsolePort on Forever with the Gamepad UI on: which cursor wins? | Toggle the Gamepad UI with ConsolePort loaded. |
| Does a QR code of a real export scan from the screen? | Render the golden fixture and a large account at versions 25 and 40. |

### Testing without a gamepad

The developer has no gamepad. Much of the plan can still be built and tested with a mouse and keyboard; some of it needs the client to see a controller.

**Testable without a pad:**

- **Most of phase 1.** Sliders with +/- buttons, labelled checkbox rows, dropdowns that close, a modifier-free item action menu and hover-only information moved into the window are ordinary UI changes. They help mouse users too and can be checked by clicking.
- **The `Bindings.xml` toggle and `.CloseButton` fields.** Bind the toggle to a keyboard key.
- **Pad handlers, in part.** A frame's `OnGamePadButtonDown` script can be called by hand to check its logic: `/run local f = <frame>; f:GetScript("OnGamePadButtonDown")(f, "PADDDOWN")`.
- **Navigation logic in specs.** A focus model (phase 3) or the D-pad scroll shim can keep its "which control next" logic pure and be covered by busted specs with fake button names, as the other specs stub the game's API.

**Probably needs a controller the client sees:**

- The virtual cursor (`SetGamePadCursorControl`, the `GamePadCursor*` CVars).
- Forever's smart navigation: it runs only with Settings → Gamepad → "Enable Gamepad UI" on.
- ConsolePort's interface cursor.
- The `SimulateMouseWheel` shim: insecure code may call it only in response to a gamepad hardware event (§2.1, `RequiresLimitedInput`), so `/run` can't stand in.
- Most of the in-game checks in the table above.

**Ways to get one:**

- **A virtual controller.** Free tools built on the ViGEmBus driver make Windows see a virtual Xbox 360 controller, driven from the keyboard or a phone app. *Unverified* that WoW accepts it; it likely does, since the client reads controllers through SDL's mappings (`C_GamePad.AddSDLMapping`), and a ViGEm device presents as a standard XInput pad. Good for checking that things work; poor for judging how navigation feels.
- **A cheap used Xbox or PlayStation controller** (about $20–30): the only way to judge the experience.
- **The player who asked on CurseForge** (§1, Demand) as a tester of a test build once phases 0 and 1 exist.

Suggested order: build phase 1 on the mouse; get a virtual or real controller before phase 0's cursor work, phase 2 and the checks above.

---

## 7. Sources

Blizzard UI source ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)), branches `forever`, `classic_anniversary`, `live`:

- API docs: `GamePadDocumentation.lua`, `GamePadConstDocumentation.lua`, `InputDocumentation.lua`, `InputInterfaceStyleDocumentation.lua`, `InputConstantsDocumentation.lua`, `SimpleFrameAPIDocumentation.lua`, `SimpleScriptRegionAPIDocumentation.lua`, `KeyBindingsDocumentation.lua`, `OsDocumentation.lua`, `TargetScriptDocumentation.lua`, `GamepadUIDocumentation.lua`, `ClientDocumentation.lua`, `RestrictedActionsDocumentation.lua`.
- forever: `Blizzard_GamepadSmartNavigation/` (`SmartNavigation.lua`, `Utility.lua`, `SecureHelper.lua`, `SmartNavigation.xml`), `Blizzard_GamepadSharedUtility/` (`FrameControlsManager.lua`, `InputBindingStack/`, `InputPrompts/`, `PromptedBindings/`, `Tab/TabIndicators.lua`, `Templates/BaseDialog.lua`), `Blizzard_Gamepad/` (`Core.lua`, `Bindings.xml`), `Blizzard_GamepadSoftCursor/`, `Blizzard_SharedXML/Mainline/InputUtil.lua`, `Blizzard_SharedXML/InputUtil.lua`, `Blizzard_SharedXML/Shared/GamepadConstants.lua`, `Blizzard_SharedXML/Shared/InputIcons/`, `Blizzard_SettingsDefinitions_Shared/Gamepad.lua`, `Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua`, `Blizzard_Game/Shared/Game.lua`, `Blizzard_StaticPopup/StaticPopupGamepad.lua`, `Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua`, `Blizzard_UIPanels_Game/Mainline/LootFrame.lua`.
- classic_anniversary: `Blizzard_UIParent/TBC/UIParent.lua`, `Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua`, `Blizzard_SharedXML/SharedConstants.lua`, `Blizzard_Menu/`.

Addons:

- ConsolePort: <https://github.com/seblindfors/ConsolePort> (`ConsolePort/API.lua`, `ConsolePort_Cursor/`, `ConsolePort_Keyboard/`, `ConsolePort_Config/View/About/About.lua`); ConsolePortNode: <https://github.com/seblindfors/ConsolePortNode>; LibWoWQRCode: <https://github.com/seblindfors/LibWoWQRCode>; luaqrcode: <https://github.com/speedata/luaqrcode>.
- YUI-Dialogue: <https://github.com/Peterodox/YUI-Dialogue>; Immersion: <https://github.com/seblindfors/Immersion>; WhatsTraining: <https://github.com/fusionpit/WhatsTraining>; Improved Forever: <https://github.com/markgravity/ImprovedForever>; Plumber: <https://github.com/Peterodox/Plumber>; BetterBags: <https://github.com/Cidan/BetterBags>; Dominos: <https://github.com/tullamods/Dominos>; APR: <https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded>; addon-kit: <https://github.com/salty-max/addon-kit>; WoWXIV: <https://github.com/vaxherd/WoWXIV>; Questie: <https://github.com/Questie/Questie> (`Modules/Libs/AddonDialog/Dialog.lua`).

Wiki and web:

- <https://warcraft.wiki.gg/wiki/Category:API_systems/GamePad>, <https://warcraft.wiki.gg/wiki/Game_Pad_buttons>, <https://warcraft.wiki.gg/wiki/API_Frame_EnableGamePadButton>, <https://warcraft.wiki.gg/wiki/API_Frame_SetPropagateKeyboardInput>, <https://warcraft.wiki.gg/wiki/API_SetOverrideBinding>, <https://warcraft.wiki.gg/wiki/API_SetBinding>, <https://warcraft.wiki.gg/wiki/API_CopyToClipboard>, <https://warcraft.wiki.gg/wiki/API_SimulateMouseWheel>, <https://warcraft.wiki.gg/wiki/CVar_GamePadCursorLeftClick>, <https://warcraft.wiki.gg/wiki/Patch_2.5.1/API_changes>.
- Blizzard, "Explore WoW: Forever with a Gamepad": <https://news.blizzard.com/article/24316974/wow>; Warcraft Tavern controller guide: <https://www.warcrafttavern.com/forever/guides/controller/>; Steam Deck: <https://www.notebookcheck.net/Fancy-questing-on-Steam-Deck-WoW-Forever-runs-amazing-here-s-how.1444087.0.html>; Blizzard forum thread (search summary only): <https://us.forums.blizzard.com/en/wow/t/steamdeck-forever/2356531>.
- CurseForge: Alt Army <https://www.curseforge.com/wow/addons/alt-army> (comments via the page's comments endpoint for mod 1464073), ConsolePort <https://www.curseforge.com/wow/addons/console-port>, Questie Forever Gamepad fix <https://www.curseforge.com/wow/addons/questie-forever-gamepad>.
- APR issue #591: <https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/issues/591>; Improved Forever issue #15: <https://github.com/markgravity/ImprovedForever/issues/15>.
