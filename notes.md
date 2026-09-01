After reading the script, the good news is that **Steps 1–3 are almost entirely UI refactoring**. Very little of the underlying SF6 functionality has to change. Most of what you're doing is moving or removing `imgui` code while leaving the helper functions intact. 

---

# Step 1

> Move the "SF6 Tools" dropdown so that it is on the same level as "Lua FreeCam v1.9.0"

## What currently happens

The UI is built inside `display_freecam()`.

The root of the UI is

```lua
if imgui.tree_node("Lua FreeCam v1.9.0") then
```

around line **674**. 

Everything that appears in the menu—including SF6 Tools—is drawn inside this tree.

Near line **1557** you find

```lua
if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then
```

This entire section is nested inside the FreeCam tree. 

The current hierarchy is

```
Lua FreeCam v1.9.0
    FreeCam
    Camera
    Hotkeys
    Visual Settings
    SF6 Tools
```

You want

```
Lua FreeCam v1.9.0

SF6 Tools
```

---

## What you'll need to change

### 1. Find the entire SF6 Tools block

It starts here

```lua
if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then
```

and ends here

```lua
imgui.tree_pop()
```

just before the code returns to the rest of `display_freecam()`. 

---

### 2. Cut that block

Remove the whole section from inside the FreeCam tree.

---

### 3. Paste it outside

Immediately after

```lua
imgui.tree_pop()
```

that closes

```
Lua FreeCam v1.9.0
```

create another top-level tree:

```lua
if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then
        ...
    end
end
```

Because it is no longer inside the first tree, imgui will render it as another top-level item.

---

### Nothing else changes

None of these need modification:

* `sf6_data`
* `players`
* callbacks
* rendering logic
* hotkeys
* helper functions

Only where the UI is drawn changes.

---

# Step 2

> Under every child, remove everything except Materials.

Current hierarchy is

```
P1

    Position
    Rotation
    Scale
    Third Person
    Facial Animation
    Animation Viewer
    Children
        esf012v00_01
            Materials
```

You want

```
P1

    Children
        esf012v00_01
            Materials
```

---

## Where this code lives

Inside the SF6 Tools section.

Look for

```lua
for i=2,1,-1 do
```

around line **1678**. 

This loop builds both

```
P1
```

and

```
P2
```

---

Inside you'll see

```lua
if imgui.tree_node(name) then
```

Everything inside this block builds the player UI.

---

### The current contents

Inside that tree are things like

```
Position
Rotation
Scale
Third Person
Facial Animation
Animation Viewer
```

These are all separate UI sections.

---

### What you need to identify

Find every section that looks like

```lua
imgui.button(...)
```

or

```lua
imgui.drag_float(...)
```

or

```lua
imgui.tree_node(...)
```

that is **not**

```
Children
```

Delete those.

Leave only the code that creates

```
Children
```

and everything beneath it.

---

### Do NOT delete

The helper functions that manipulate players.

For example:

```
find_player_meshes()

change_player_mat_params()

lua_get_system_array()
```

These are still needed because Materials depends on them. 

Only remove UI drawing code.

---

### Expected result

Current:

```
P1

    Position

    Rotation

    Scale

    Third Person

    Facial Animation

    Children

        esf012v00_01

            Materials
```

Desired:

```
P1

    Children

        esf012v00_01

            Materials
```

Repeat for P2.

---

# Step 3

Remove everything unrelated to Materials.

Your comment lists

```
Graphics

2D Distortion Effect

Overlapping Fighters

Frame Rate

Set Battle Damage

Set Sweat

Slow Motion

Show Character Gizmos

Show Character Lights Gizmos

Move Stage

Move Lights

Stage Display
```

These are all at the beginning of the SF6 Tools UI.

---

## Exactly where they are

They begin immediately after

```lua
imgui.begin_rect()
```

around line **1559**. 

---

### Graphics

```lua
if graphics_settings_mgr and imgui.tree_node("Graphics") then
```

Delete the entire block.

---

### Distortion

```lua
changed, sf6_data.distortion_idx =
```

Delete.

---

### Overlapping Fighters

```lua
changed, sf6_data.overlap_idx =
```

Delete.

---

### Frame Rate

```lua
changed, sf6_data.fps_idx =
```

Delete.

---

### Battle Damage

```lua
changed, sf6_data.battle_damage_percent =
```

Delete.

---

### Sweat

```lua
changed, sf6_data.sweat_percent =
```

Delete.

---

### Slow Motion

```lua
changed, sf6_data.slow_motion_speed =
```

Delete.

---

### Show Character Gizmos

```lua
changed, movechars_on =
```

Delete.

---

### Character Lights Gizmos

```lua
changed, movelights_on =
```

Delete.

---

### Move Stage / Move Lights

Delete the entire

```lua
if EMV then
```

block.

---

### Stage Display

Delete

```lua
if battleflow and imgui.tree_node("Stage Display") then
```

entirely.

---

# What should remain

After Steps 1–3, your SF6 Tools UI should look approximately like this:

```
SF6 Tools

    P1

        Children

            esf012v00_01

                Materials

                    esf_*

            esf012v00_02

                Materials

                    esf_*

    P2

        Children

            esf001v00_01

                Materials

                    esf_*
```

Everything else in the SF6 Tools menu is gone.

---

# What should *not* be deleted

A common mistake would be to remove the helper functions because their UI is gone. Many of them are still used by the Materials system or may be needed for your future Step 4 (adding the CMD dropdown).

Keep:

* `sf6_data` table (even if some fields become unused initially) 
* `find_player_meshes()` 
* `change_player_mat_params()` 
* the code that populates `players`
* the code that builds the `Children` → `Materials` tree
* any callbacks or hooks that the Materials editor depends on

Only remove the **imgui controls** for the features you no longer want. This keeps the refactor low-risk and makes Step 4 (adding the CMD dropdown above `Children`) much easier.

