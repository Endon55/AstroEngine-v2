# Shader manager

Put Slang shaders under a registered `shaders/source/` directory, using
`<name>.<stage>.slang`. For example, `source/ocean/debug.geom.slang` is available
as `game/ocean/debug.geom` in the game shader directory. Names may contain dots.
Unstaged files such as `common.slang` are treated as includes.

| Stage | Filename suffixes |
| --- | --- |
| Vertex | `vert`, `vertex` |
| Tessellation control | `tesc`, `tesscontrol`, `tess_control`, `tessellation_control`, `hull` |
| Tessellation evaluation | `tese`, `tesseval`, `tess_eval`, `tessellation_evaluation`, `domain` |
| Geometry | `geom`, `geometry` |
| Fragment | `frag`, `fragment`, `pixel` |
| Compute | `comp`, `compute` |
| Ray generation | `rgen`, `raygen`, `raygeneration`, `ray_generation` |
| Intersection | `rint`, `intersection` |
| Any hit | `rahit`, `anyhit`, `any_hit` |
| Closest hit | `rchit`, `closesthit`, `closest_hit` |
| Miss | `rmiss`, `miss` |
| Callable | `rcall`, `callable` |
| Task | `task`, `amplification` |
| Mesh | `mesh` |

Use `[shader("geometry")]` (or the corresponding Slang stage attribute) for a
named entry point. An untagged `main` is checked against the filename stage.
Task shaders must use `[shader("amplification")]`: Slang otherwise infers a
`[numthreads]` entry point as compute. All entry points in a file must match its
stage. Entry-point names are preserved in SPIR-V. Compute modules can contain
multiple entry points; the graphics builder uses the first SPIR-V entry point.

The manager compiles and caches these stages as SPIR-V 1.4. Shader compilation
errors, stage mismatches, and failures in nested directories report a failed
build; a failed hot reload keeps the previously loaded shader. Cached modules
are checked for their entry-point stages before use.

The current graphics builder supports vertex, tessellation, geometry, and
fragment stages; the compute builder supports compute. Ray-tracing and mesh/task
shaders can be compiled and loaded by the manager, but using them requires
separate pipeline support and Vulkan device extensions/features that the engine
does not currently set up. Geometry and tessellation also require corresponding
device features. A tessellation pipeline needs both control and evaluation
shaders, `PATCH_LIST` topology, and a nonzero count set with
`graphics_pipeline_builder_set_patch_control_points`.

Geometry entry points that emit with a stream return `void`. Fragment-only
semantics such as `SV_IsFrontFace` should be declared in the fragment shader,
not in the geometry shader's output.

## Tests

With `VULKAN_SDK` set, run:

```sh
odin test src -collection:libs=libs -define:GLFW_SHARED=false \
  -extra-linker-flags:"-L$VULKAN_SDK/lib -Wl,-rpath,$VULKAN_SDK/lib"
```
