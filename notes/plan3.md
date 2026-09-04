I want to refactor the script at ./reframework/autorun/FreeCam.lua. Much of the script utilizes the REFramework API which is outlined here: https://refdocs.praydog.com/. I want to make the imgui node tree so that its easier to read at a glance. For instance if you could instantly see all of the elements at a particular branch level and all of their children. Then with all of that displayed you could point to a function that created the logic for each part of the node tree that is displayed.

So imagine a tree that goes like this:

```yaml
Lua FreeCam v1.9.0:
  Enable FreeCam:
  Hide UI:
  2x Quality:
  Freeze Time & Scene:
  Orthographic Cam:
  Enable Cam Light:
  Cam Light Settings:
  Quick Zoom:
  Hotkeys:
  Visual Settings:
  Camera:
  LightProbes:

SF6 Tools:
  P1:
    CMD File:
    Children:
      esf012v00_01:
        Materials:
          esf_body
          esf_face
          esf_eye
      esf012v00_02:
        Materials:
          esf_body
          esf_face

  P2:
    CMD File:
    Children:
      esf001v00_01:
        Materials:
          esf_body
          esf_face
```

Indentation naturally represents parent child relationships and its easier to see

---

The YAML/string defines **only the structure**.

```yaml
SF6 Tools:
  P1:
    CMD File:
    Children:
      Character:
        Materials:

  P2:
    CMD File:
    Children:
      Character:
        Materials:
```

Then have a registry

```lua
local callbacks = {
    ["SF6 Tools"] = draw_sf6_root,
    ["P1"] = draw_p1,
    ["P2"] = draw_p2,
    ["CMD File"] = draw_cmd_dropdown,
    ["Children"] = draw_children,
    ["Character"] = draw_character,
    ["Materials"] = draw_materials,
}
```

Your renderer becomes

```lua
draw_tree(node)

↓

imgui.tree_node(node.name)

↓

callbacks[node.name](...)

↓

draw children
```


I really just want to perform this refactor with this function:

```lua
function display_freecam()
```

I want the yaml string to be in same file for now.
