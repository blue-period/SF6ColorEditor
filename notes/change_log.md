Thu Sep  3 21:38:12 EDT 2026:

Implemented the plan3.md refactor scaffold in reframework/autorun/FreeCam.lua:651.

  Changes made:

  - Added an in-file YAML-like freecam_ui_tree_yaml structure.
  - Added a small parser and recursive renderer for that tree.
  - Routed display_freecam() through a callback registry.
  - Extracted the first top-level FreeCam controls into named callbacks: Enable FreeCam, Hide UI, 2x Quality,
    Freeze Time & Scene, Orthographic Cam, and Enable Cam Light.

  Verification note: luac/lua are not installed here, and npx luaparse hung twice while fetching, so I could not
  run a real Lua syntax parser. I inspected the changed block and confirmed no parser process was left running.
