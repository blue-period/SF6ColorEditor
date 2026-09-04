---

### Refactor Goal

Remove the `freecam_callback_scope_anchor` + `debug.getupvalue` mechanism entirely and replace it with an explicit shared context object.

The current implementation relies on Lua's debug API to inspect and mutate locals from another module. This makes dependencies implicit, difficult to understand, and tightly couples `callbacks.lua` to the internal implementation details of `FreeCam.lua`.  

The new design should expose dependencies explicitly through a `context` table.

---

## Desired Architecture

Instead of this:

```lua
install_freecam_callbacks(callbacks, freecam_callback_scope_anchor)
```

the API should become

```lua
local context = {
    state = state,
    camera = camera,
    lighting = lighting,
    ui = ui,
    sf6 = sf6,
    functions = {
        tooltip = tooltip,
        attach_detach = attach_detach,
        create_new_cam_light = create_new_cam_light,
        ...
    }
}

install_freecam_callbacks(callbacks, context)
```

---

## Refactor Requirements

### 1. Remove all debug API usage

Delete:

* `freecam_callback_scope_anchor`
* `debug.getupvalue`
* `debug.setupvalue`
* the `bindings` table
* the custom `_ENV` implementation

`callbacks.lua` should never inspect another module's locals.

---

### 2. Introduce a context object

Build a single context table in `FreeCam.lua`.

Example (structure, not exact contents):

```lua
local context = {
    state = {
        changed = changed,
        was_changed = was_changed,
        freecam_on = freecam_on,
        freecam_changed = freecam_changed,
        frozen_scene = frozen_scene,
        ...
    },

    camera = {
        cam = cam,
        cam_light = cam_light,
        cam_lights = cam_lights,
        cam_attached = cam_attached,
        cam_gameobj = cam_gameobj,
        cam_xform = cam_xform,
        ...
    },

    sf6 = {
        players = players,
        data = sf6_data,
    },

    settings = {
        freecam_settings = freecam_settings,
        default_settings = default_settings,
        defaults = defaults,
    },

    ui = {
        imgui_data = imgui_data,
        filter_options = filter_options,
        lightconfig_names = lightconfig_names,
        ...
    },

    functions = {
        tooltip = tooltip,
        change_quality = change_quality,
        create_new_cam_light = create_new_cam_light,
        create_or_toggle_cam_light = create_or_toggle_cam_light,
        attach_detach = attach_detach,
        move_to_light = move_to_light,
        apply_shadow_bias = apply_shadow_bias,
        ...
    }
}
```

The exact grouping is flexible, but related values should be grouped logically.

---

### 3. Preserve mutability

Some callback code intentionally mutates state.

Instead of

```lua
freecam_on = true
```

callbacks should become

```lua
context.state.freecam_on = true
```

Likewise,

```lua
cam_light = light
```

becomes

```lua
context.camera.cam_light = light
```

Callbacks should never depend on module-local variables directly.

---

### 4. Functions should live under `context.functions`

Instead of

```lua
tooltip(...)
```

callbacks should call

```lua
context.functions.tooltip(...)
```

Likewise,

```lua
create_new_cam_light()
```

becomes

```lua
context.functions.create_new_cam_light()
```

---

### 5. Update callbacks.lua

Change

```lua
local function install_callbacks(callbacks, scope_anchor)
```

to

```lua
local function install_callbacks(callbacks, context)
```

Remove the entire block that builds `_ENV`:

```lua
bindings = {}
...
_ENV = scope
```

and instead begin each callback with

```lua
local state = context.state
local camera = context.camera
local sf6 = context.sf6
local ui = context.ui
local settings = context.settings
local fn = context.functions
```

or simply reference `context` directly.

---

### 6. Keep module boundaries explicit

`callbacks.lua` should only depend on what is present in `context`.

If a callback requires a new variable or helper function, add it to `context` explicitly.

Do **not** recreate any hidden dependency mechanism.

---

## Design Goals

The finished architecture should have these properties:

* No use of `debug.getupvalue`
* No use of `debug.setupvalue`
* No custom `_ENV`
* No "scope anchor" function
* All dependencies explicitly declared
* Clear ownership of state
* Easy to see what `callbacks.lua` needs from `FreeCam.lua`
* Easier future refactoring because dependencies are visible rather than inferred

The goal is to replace implicit runtime introspection with an explicit API between the two modules. This makes the code significantly easier to understand, maintain, and extend while preserving existing behavior.

