Yes. After going through the script, here are the **exact line ranges** you should modify for **Step 1**.

---

# Step 1.1: Find the root FreeCam tree

Starts here:

**Line 674**

```lua
if imgui.tree_node("Lua FreeCam v1.9.0") then
```

This entire block runs until

**Line 1857**

```lua
imgui.tree_pop()
```

which closes the `"Lua FreeCam v1.9.0"` tree.  

---

# Step 1.2: Find the SF6 Tools block

Starts at

**Line 1557**

```lua
if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then
```

Ends at

**Line 1843**

```lua
imgui.end_rect(2)
imgui.tree_pop()
```

These two `tree_pop()` calls close

* `SF6 Tools`
* the surrounding `if`

This entire section should be cut. 

---

# Step 1.3: Remove it

Delete (or cut) everything from

```
1557
```

through

```
1843
```

Do **not** delete the following block:

```lua
else
    imgui.text()
    imgui.spacing()
end
```

around **1844–1847** because that belongs to the parent logic. 

---

# Step 1.4: Find where Lua FreeCam closes

Near the bottom of `display_freecam()` you'll see

```lua
imgui.end_rect(3)
imgui.text("                                   By alphaZomega")
imgui.tree_pop()
```

This is approximately

**Lines 1855–1857**

The final

```lua
imgui.tree_pop()
```

is what closes

```lua
imgui.tree_node("Lua FreeCam v1.9.0")
```



---

# Step 1.5: Insert the new top-level tree

Immediately **after**

```lua
imgui.tree_pop()
```

on line **1857**

and **before**

```lua
imgui.spacing()
```

on line **1859**

insert

```lua
if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then

        -- Paste the old SF6 Tools contents here

    end
end
```

The new layout becomes

```text
display_freecam()

Lua FreeCam
    ...

(end Lua FreeCam)

SF6 Tools
    ...
```

instead of

```text
Lua FreeCam
    ...
    SF6 Tools
```

---

# Summary

| Action                  |                     Lines |
| ----------------------- | ------------------------: |
| Find `Lua FreeCam` root |                   **674** |
| SF6 Tools begins        |                  **1557** |
| SF6 Tools ends          |                  **1843** |
| Lua FreeCam closes      |                  **1857** |
| Insert new SF6 Tools    | **between 1857 and 1859** |

---

One suggestion: rather than moving the code immediately, I'd recommend first extracting the entire SF6 Tools section into its own function, for example:

```lua
local function draw_sf6_tools()
    ...
end
```

Then inside `display_freecam()` you would simply call:

```lua
if imgui.tree_node("Lua FreeCam v1.9.0") then
    ...
end

if isSF6 and players[2] then
    if imgui.tree_node("SF6 Tools") then
        draw_sf6_tools()
        imgui.tree_pop()
    end
end
```

This makes the file much easier to maintain, and it will simplify your later refactor when you eventually split the SF6-specific code into `SF6Tools.lua`.

