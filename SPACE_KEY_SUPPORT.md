# SPACE Key Support for Keybinds

## Summary
Added support for SPACE and other special keys in hyprwhspr keybind configuration.

## Problem
The `ALT+SPACE` keybind was not working because the global shortcuts parser in `/opt/hyprwhspr/lib/src/global_shortcuts.py` only supported:
- Function keys (F1-F12)
- Modifier keys (CTRL, ALT, SHIFT, SUPER)
- Letter keys (A-Z)

The SPACE key was not mapped, so `ALT+SPACE` would only register ALT.

## Solution
Extended the `_string_to_keycode()` function in `global_shortcuts.py` to add a `special_key_map` dictionary.

### Changes Made

**File:** `/opt/hyprwhspr/lib/src/global_shortcuts.py`

**Added (around line 165):**
```python
# Special keys
special_key_map = {
    'space': ecodes.KEY_SPACE,
    'enter': ecodes.KEY_ENTER,
    'return': ecodes.KEY_ENTER,
    'tab': ecodes.KEY_TAB,
    'esc': ecodes.KEY_ESC,
    'escape': ecodes.KEY_ESC,
    'backspace': ecodes.KEY_BACKSPACE
}

# Check special keys (added after char_key_map check)
if key_string in special_key_map:
    return special_key_map[key_string]
```

### Config Format
**File:** `~/.config/hyprwhspr/config.json`

```json
{
  "primary_shortcut": "ALT+SPACE"
}
```

**Format:** Use `+` separator (not comma), e.g.:
- `"ALT+SPACE"` ✅
- `"SUPER+ALT+D"` ✅
- `"ALT, SPACE"` ❌ (comma not supported)

## Testing
✅ `ALT+SPACE` now triggers dictation correctly  
✅ Service restarts and picks up the new keybind  
✅ No longer triggers on just ALT alone  

## Additional Keys Supported
- `SPACE`
- `ENTER` / `RETURN`
- `TAB`
- `ESC` / `ESCAPE`
- `BACKSPACE`

## Note
The modified file is in `/opt/hyprwhspr/` (system-wide installation), not in this repository. A backup was created at `/opt/hyprwhspr/lib/src/global_shortcuts.py.backup`.
