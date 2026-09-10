# VibezCraft 1.1.1

A bug-fix release. Everything here came from one very thorough bug report (issue #7) — thanks, Oelda. Worlds from 1.1.0 still work.

## Fixes

- **Beds.** Waking up no longer leaves you stuck in the floor. You stand up next to the bed, and respawning at a bed puts you on your feet too.
- **Nether portals.** The obsidian frame around the portal now shows up, and is solid, when you arrive in the Nether. It was there all along, but the chunk was drawn from an older copy.
- **Furnaces.** The front is only on the side you were facing when you placed it, and stays put when the furnace lights. Pumpkins and jack-o'-lanterns had the same problem and are fixed too. Furnaces placed before this update face north; break and replace them if you mind. The top and bottom now use the stone texture, as in Alpha.
- **Furnace screen.** Opening a fresh furnace no longer shows a stretched flame and arrow.
- **Cactus.** No longer see-through at the edges. It has the classic narrower shape and hitbox.
- **Ore in caves.** Coal and other ore no longer sits in mid-air inside caves. Caves are now carved before ore is placed, the way the original game does it.
- **Water.** Picking up or breaking a water source now drains all the water it was feeding, not just the nearest blocks.
- **Skeletons.** They aim at your body instead of your feet, so they hit far more often, especially when you are standing above them. Arrows also connect a little more generously, matching the original game.
- **Spiders.** No longer float above the ground.
- **Inventory.** Items move the moment you click, not when you let go. Holding a stack and dragging it across slots splits it as you go.
- **Animations.** Walking looks like walking again. Punching the air swings your arm. The view bobs as you walk in first person, the screen flinches and your character flashes red when hurt, and flying no longer freezes the arms and legs.
- **Character preview.** The head in the inventory screen sits on the neck instead of drifting off it.
- **Gaps between chunks.** Thin lines of sky showing between blocks on some graphics cards should be gone. We could not make it happen on a Mac, so if you still see it after updating, please say so.

## For bug reports

If the game slows down badly for more than a couple of seconds, it now writes a line to the log saying what was going on at the time. You can copy it from **Pause → Options → Unstuck / Debug**. Please include it if you report lag.
