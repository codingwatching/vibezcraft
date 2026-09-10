shader_type spatial;
// `unshaded` skips Godot's PBR pipeline so ALBEDO writes directly to the
// framebuffer. Vanilla Alpha bakes ALL illumination into per-vertex color
// (sky + block light, run through the brightness LUT) and writes that with
// GL_LIGHTING disabled — there's no environmental ambient or sun term on
// terrain. This shader does the same: the LUT + Notch face shade below
// produce the final color, no Godot lift on top. Without `unshaded`, an
// `ambient_light_energy = 0` Environment would gate every face to black
// (ALBEDO × 0 = 0); with `unshaded`, caves drop to the proper Alpha 5% floor.
//
// World-terrain variant: `cull_back` is correct because the camera never
// ends up inside a solid chunk cell (player collides with terrain). Entity
// cubes (falling blocks, dropped items, TP-held block) use the cull_disabled
// sibling at shaders/chunk_entity.gdshader — see that file for why.
//
// `world_vertex_coords`: every chunk is its own mesh instance, translated
// by (cx·16, 0, cz·16), and two chunks share the vertices along their
// border. Godot's default vertex path multiplies each instance's
// modelview (view × model, formed per vertex) into the LOCAL vertex, so
// the two instances reach a shared border vertex through different
// intermediate roundings — a ULP apart on some drivers, which leaves a
// hairline no triangle covers and the sky shows through ("slight gaps
// between blocks showing the skybox", issue #7; seen on Windows, not
// reproducible on Metal). In world mode the model transform is applied
// first — an exact integer add — and the SAME view transform then runs on
// identical inputs, so border vertices are bit-identical by construction.
// Chunk transforms are pure translations, so NORMAL is unchanged by this.
// The entity/overlay siblings keep local coords: they rotate.
render_mode cull_back, unshaded, world_vertex_coords;

#include "res://shaders/chunk_common.gdshaderinc"
