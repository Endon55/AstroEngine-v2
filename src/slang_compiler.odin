package astro

// High-level wrapper around the Slang compiler bindings in slang_api.odin.

import "base:runtime"
import "core:log"
import "core:strings"

// ---------------------------------------------------------------------------
// Session setup
// ---------------------------------------------------------------------------

// Converts `paths` to a temp-allocated cstring array and wires it into `desc` as
// `#include`/`import` search directories. `desc` must not outlive `allocator`'s scope.
@(private = "file")
session_desc_set_search_paths :: proc(desc: ^SessionDesc, paths: []string, allocator: runtime.Allocator) {
    if len(paths) == 0 do return
    paths_c := make([]cstring, len(paths), allocator)
    for path, i in paths {
        paths_c[i] = strings.clone_to_cstring(path, allocator)
    }
    desc.searchPaths = &paths_c[0]
    desc.searchPathCount = SlangInt(len(paths_c))
}

// Creates a Slang session that emits SPIR-V, mirroring compile.sh's `-profile glsl_450`
// so codegen (matrix majorness, SPIR-V version) matches the CLI reference.
@(private = "file")
slang_session_create :: proc(
    self: ^Slang_Compiler,
    search_paths: []string,
    allocator: runtime.Allocator,
) -> (
    session: ^ISession,
    ok: bool,
) {
    profile := self.global_session.vtbl.findProfile(self.global_session, "glsl_450")
    target := target_desc_default(SLANG_SPIRV, profile)
    session_desc := session_desc_default(&target, 1)
    session_desc_set_search_paths(&session_desc, search_paths, allocator)

    result := self.global_session.vtbl.createSession(self.global_session, &session_desc, &session)
    if result != SLANG_OK || session == nil {
        log.errorf("Failed to create Slang session (result=%v)", result)
        return nil, false
    }
    return session, true
}

// ---------------------------------------------------------------------------
// High level compiler wrapper
// ---------------------------------------------------------------------------

Slang_Compiler :: struct {
    global_session: ^IGlobalSession,
}

slang_compiler_init :: proc(self: ^Slang_Compiler) -> (ok: bool) {
    result := slang_createGlobalSession(0, &self.global_session)
    if result != SLANG_OK || self.global_session == nil {
        log.errorf("Failed to create Slang global session (result=%v)", result)
        return false
    }
    return true
}

slang_compiler_deinit :: proc(self: ^Slang_Compiler) {
    if self.global_session != nil {
        slang_release(self.global_session)
        self.global_session = nil
    }
}

// Compiles Slang/HLSL/GLSL source held as a string into SPIR-V bytecode.
// entry_point_name identifies the function to compile, stage is its shader stage.
// `file_path` (defaults to `module_name`) and `search_paths` let Slang's preprocessor
// resolve `#include`/`import` directives in `source` on its own.
// The returned bytes are allocated with `allocator` and owned by the caller.
slang_compile_to_spirv :: proc(
    self: ^Slang_Compiler,
    source: string,
    module_name: string,
    entry_point_name: string,
    stage: SlangStage,
    file_path := "",
    search_paths: []string = nil,
    allocator := context.allocator,
) -> (
    spirv: []byte,
    ok: bool,
) {
    ensure(self.global_session != nil, "Slang_Compiler not initialized")

    ta := context.temp_allocator
    session, session_ok := slang_session_create(self, search_paths, ta)
    if !session_ok do return nil, false
    defer slang_release(session)

    module_name_c := strings.clone_to_cstring(module_name, ta)
    path_c := strings.clone_to_cstring(file_path if file_path != "" else module_name, ta)
    source_c := strings.clone_to_cstring(source, ta)

    diagnostics: ^ISlangBlob
    module := session.vtbl.loadModuleFromSourceString(session, module_name_c, path_c, source_c, &diagnostics)
    slang_log_diagnostics(diagnostics)
    if module == nil {
        log.errorf("Failed to load Slang module: %s", module_name)
        return nil, false
    }

    entry_point_name_c := strings.clone_to_cstring(entry_point_name, ta)
    entry_point: ^IComponentType
    {
        diagnostics = nil
        result := module.vtbl.findAndCheckEntryPoint(module, entry_point_name_c, stage, &entry_point, &diagnostics)
        slang_log_diagnostics(diagnostics)
        if result != SLANG_OK || entry_point == nil {
            log.errorf("Failed to find Slang entry point: %s", entry_point_name)
            return nil, false
        }
    }
    defer slang_release(entry_point)

    components := [2]^IComponentType{module_as_component(module), entry_point}

    program: ^IComponentType
    {
        diagnostics = nil
        result := session.vtbl.createCompositeComponentType(session, &components[0], 2, &program, &diagnostics)
        slang_log_diagnostics(diagnostics)
        if result != SLANG_OK || program == nil {
            log.errorf("Failed to create Slang composite component type")
            return nil, false
        }
    }
    defer slang_release(program)

    linked: ^IComponentType
    {
        diagnostics = nil
        result := program.vtbl.link(program, &linked, &diagnostics)
        slang_log_diagnostics(diagnostics)
        if result != SLANG_OK || linked == nil {
            log.errorf("Failed to link Slang program")
            return nil, false
        }
    }
    defer slang_release(linked)

    code: ^ISlangBlob
    {
        diagnostics = nil
        result := linked.vtbl.getEntryPointCode(linked, 0, 0, &code, &diagnostics)
        slang_log_diagnostics(diagnostics)
        if result != SLANG_OK || code == nil {
            log.errorf("Failed to get Slang entry point SPIR-V code")
            return nil, false
        }
    }

    return slang_blob_to_bytes(code, allocator), true
}

// ---------------------------------------------------------------------------
// Auto-detecting compilation (no explicit module/entry point/stage required)
// ---------------------------------------------------------------------------

// One entry point in a compiled module, as reported by Slang's reflection.
Slang_Entry_Point :: struct {
    name:  string,
    stage: SlangStage,
}

// A single SPIR-V module containing every compiled entry point. The entry point names
// are also embedded in the SPIR-V (OpEntryPoint), so callers can create one shader
// module and then one pipeline per entry point.
Slang_Compiled_Module :: struct {
    spirv:        []byte,
    entry_points: []Slang_Entry_Point,
}

slang_compiled_module_destroy :: proc(self: ^Slang_Compiled_Module, allocator := context.allocator) {
    if self.spirv != nil {
        delete(self.spirv, allocator)
    }
    for entry_point in self.entry_points {
        delete(entry_point.name, allocator)
    }
    if self.entry_points != nil {
        delete(self.entry_points, allocator)
    }
    self^ = {}
}

// Compiles every `[shader(...)]`-tagged entry point found in `source` into one SPIR-V
// module. If none are tagged, falls back to checking a single `main` function against
// each common stage in turn (compute, then vertex, then fragment) and compiles whichever
// one type-checks.
//
// Linking all entry points into one module lets reflection report the union of their
// descriptor bindings, which is exactly what a shared pipeline layout needs: an entry
// point that doesn't use a binding is still compatible with the union layout.
//
// `file_path` (defaults to `module_name`) and `search_paths` let Slang's preprocessor
// resolve `#include`/`import` directives in `source` on its own.
slang_compile_module :: proc(
    self: ^Slang_Compiler,
    source: string,
    module_name := "shader",
    file_path := "",
    search_paths: []string = nil,
    allocator := context.allocator,
) -> (
    compiled: Slang_Compiled_Module,
    ok: bool,
) {
    ensure(self.global_session != nil, "Slang_Compiler not initialized")

    ta := context.temp_allocator
    session, session_ok := slang_session_create(self, search_paths, ta)
    if !session_ok do return {}, false
    defer slang_release(session)

    module_name_c := strings.clone_to_cstring(module_name, ta)
    path_c := strings.clone_to_cstring(file_path if file_path != "" else module_name, ta)
    source_c := strings.clone_to_cstring(source, ta)

    diagnostics: ^ISlangBlob
    module := session.vtbl.loadModuleFromSourceString(session, module_name_c, path_c, source_c, &diagnostics)
    slang_log_diagnostics(diagnostics)
    if module == nil {
        log.errorf("Failed to load Slang module: %s", module_name)
        return {}, false
    }
    // `module` is owned by `session` (per slang.h: "modules ... remain resident until the
    // session is released"); it must NOT be released here.

    entry_points: [dynamic]^IComponentType
    entry_points.allocator = ta
    defer for ep in entry_points {
        slang_release(ep)
    }

    if defined_count := module.vtbl.getDefinedEntryPointCount(module); defined_count > 0 {
        // A module may define any number of `[shader(...)]` entry points. Gather them all
        // and link them together below.
        for i in SlangInt32(0) ..< defined_count {
            ep: ^IComponentType
            if r := module.vtbl.getDefinedEntryPoint(module, i, &ep); r == SLANG_OK && ep != nil {
                append(&entry_points, ep)
            } else {
                log.errorf("Failed to get Slang entry point %i in module %s", i, module_name)
            }
        }
    } else {
        // No `[shader(...)]` tags: probe a plain `main` against each common stage and
        // keep whichever one Slang accepts.
        main_c := strings.clone_to_cstring("main", ta)
        for stage in ([]SlangStage{SLANG_STAGE_COMPUTE, SLANG_STAGE_VERTEX, SLANG_STAGE_FRAGMENT}) {
            ep: ^IComponentType
            stage_diagnostics: ^ISlangBlob
            r := module.vtbl.findAndCheckEntryPoint(module, main_c, stage, &ep, &stage_diagnostics)
            slang_release(stage_diagnostics) // mismatched stages are expected to fail; don't log noise
            if r == SLANG_OK && ep != nil {
                append(&entry_points, ep)
                break
            }
        }
    }

    if len(entry_points) == 0 {
        log.errorf("Slang module %s has no usable entry points", module_name)
        return {}, false
    }

    components := make([]^IComponentType, len(entry_points) + 1, ta)
    components[0] = module_as_component(module)
    copy(components[1:], entry_points[:])

    diagnostics = nil
    program: ^IComponentType
    if r := session.vtbl.createCompositeComponentType(session, raw_data(components), SlangInt(len(components)), &program, &diagnostics); r != SLANG_OK || program == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to create Slang composite component type for module %s", module_name)
        return {}, false
    }
    slang_log_diagnostics(diagnostics)
    defer slang_release(program)

    diagnostics = nil
    linked: ^IComponentType
    if r := program.vtbl.link(program, &linked, &diagnostics); r != SLANG_OK || linked == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to link Slang program for module %s", module_name)
        return {}, false
    }
    slang_log_diagnostics(diagnostics)
    defer slang_release(linked)

    diagnostics = nil
    layout := linked.vtbl.getLayout(linked, 0, &diagnostics)
    slang_log_diagnostics(diagnostics)
    if layout == nil {
        log.errorf("Failed to get Slang reflection layout for module %s", module_name)
        return {}, false
    }

    entry_point_count := int(spReflection_getEntryPointCount(layout))
    if entry_point_count == 0 {
        log.errorf("Slang module %s has no reflected entry points", module_name)
        return {}, false
    }

    compiled.entry_points = make([]Slang_Entry_Point, entry_point_count, allocator)
    for i in 0 ..< entry_point_count {
        refl_ep := spReflection_getEntryPointByIndex(layout, SlangUInt(i))
        if refl_ep == nil {
            log.errorf("Failed to reflect Slang entry point %i in module %s", i, module_name)
            slang_compiled_module_destroy(&compiled, allocator)
            return {}, false
        }
        compiled.entry_points[i] = {
            name = strings.clone(string(spReflectionEntryPoint_getName(refl_ep)), allocator),
            stage = spReflectionEntryPoint_getStage(refl_ep),
        }
    }

    diagnostics = nil
    code: ^ISlangBlob
    if r := linked.vtbl.getTargetCode(linked, 0, &code, &diagnostics); r != SLANG_OK || code == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to get Slang target code for module %s", module_name)
        slang_compiled_module_destroy(&compiled, allocator)
        return {}, false
    }
    slang_log_diagnostics(diagnostics)

    compiled.spirv = slang_blob_to_bytes(code, allocator)
    return compiled, true
}
