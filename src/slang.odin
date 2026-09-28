package astro

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"

foreign import slang "system:slang"

// ---------------------------------------------------------------------------
// Basic Slang API types (see slang.h)
// ---------------------------------------------------------------------------

SlangResult :: c.int32_t
SlangInt :: c.int64_t // SLANG_PTR_IS_64 build

SlangProfileID :: distinct c.uint32_t
SlangCapabilityID :: distinct c.int32_t
SlangCompileTarget :: distinct c.int32_t
SlangSourceLanguage :: distinct c.int32_t
SlangPassThrough :: distinct c.int32_t
SlangArchiveType :: distinct c.int32_t
SlangStage :: distinct c.uint32_t
SlangMatrixLayoutMode :: distinct c.uint32_t
SlangFloatingPointMode :: distinct c.uint32_t
SlangLineDirectiveMode :: distinct c.uint32_t
SlangTargetFlags :: distinct c.uint32_t
SessionFlags :: distinct c.uint32_t

SLANG_OK :: SlangResult(0)

SLANG_TARGET_UNKNOWN :: SlangCompileTarget(0)
SLANG_GLSL :: SlangCompileTarget(2)
SLANG_HLSL :: SlangCompileTarget(5)
SLANG_SPIRV :: SlangCompileTarget(6)

SLANG_SOURCE_LANGUAGE_SLANG :: SlangSourceLanguage(1)
SLANG_SOURCE_LANGUAGE_HLSL :: SlangSourceLanguage(2)
SLANG_SOURCE_LANGUAGE_GLSL :: SlangSourceLanguage(3)

SLANG_STAGE_VERTEX :: SlangStage(1)
SLANG_STAGE_FRAGMENT :: SlangStage(5)
SLANG_STAGE_COMPUTE :: SlangStage(6)

SLANG_PROFILE_UNKNOWN :: SlangProfileID(0)

SLANG_MATRIX_LAYOUT_ROW_MAJOR :: SlangMatrixLayoutMode(1)
SLANG_MATRIX_LAYOUT_COLUMN_MAJOR :: SlangMatrixLayoutMode(2)

SLANG_FLOATING_POINT_MODE_DEFAULT :: SlangFloatingPointMode(0)
SLANG_LINE_DIRECTIVE_MODE_DEFAULT :: SlangLineDirectiveMode(0)
kDefaultTargetFlags :: SlangTargetFlags(1 << 10) // SLANG_TARGET_FLAG_GENERATE_SPIRV_DIRECTLY

Guid :: struct {
    data1: c.uint32_t,
    data2: c.uint16_t,
    data3: c.uint16_t,
    data4: [8]c.uint8_t,
}

SlangUInt :: c.uint64_t // SLANG_PTR_IS_64 build
SlangInt32 :: c.int32_t

// Opaque reflection handles (SlangProgramLayout doubles as the ShaderReflection/SlangReflection type).
SlangReflection :: struct {}
ProgramLayout :: SlangReflection
SlangReflectionEntryPoint :: struct {}

foreign slang {
    slang_createGlobalSession :: proc "c" (apiVersion: SlangInt, outGlobalSession: ^^IGlobalSession) -> SlangResult ---
    slang_shutdown :: proc "c" () ---

    spReflection_getEntryPointCount :: proc "c" (reflection: ^SlangReflection) -> SlangUInt ---
    spReflection_getEntryPointByIndex :: proc "c" (reflection: ^SlangReflection, index: SlangUInt) -> ^SlangReflectionEntryPoint ---
    spReflectionEntryPoint_getName :: proc "c" (entryPoint: ^SlangReflectionEntryPoint) -> cstring ---
    spReflectionEntryPoint_getStage :: proc "c" (entryPoint: ^SlangReflectionEntryPoint) -> SlangStage ---
}

// ---------------------------------------------------------------------------
// ISlangUnknown / ISlangBlob
// ---------------------------------------------------------------------------

ISlangUnknown_Vtbl :: struct {
    queryInterface: proc "c" (this: ^ISlangUnknown, uuid: ^Guid, outObject: ^rawptr) -> SlangResult,
    addRef:         proc "c" (this: ^ISlangUnknown) -> c.uint32_t,
    release:        proc "c" (this: ^ISlangUnknown) -> c.uint32_t,
}

ISlangUnknown :: struct {
    vtbl: ^ISlangUnknown_Vtbl,
}

ISlangBlob_Vtbl :: struct {
    using _unknown:   ISlangUnknown_Vtbl,
    getBufferPointer: proc "c" (this: ^ISlangBlob) -> rawptr,
    getBufferSize:    proc "c" (this: ^ISlangBlob) -> c.size_t,
}

ISlangBlob :: struct {
    vtbl: ^ISlangBlob_Vtbl,
}

// Release any Slang COM object (every interface starts with ISlangUnknown's vtbl layout).
slang_release :: proc(obj: ^$T) {
    if obj == nil do return
    unknown := cast(^ISlangUnknown)obj
    unknown.vtbl.release(unknown)
}

// Copies a blob's contents into an Odin-owned slice, then releases the blob.
slang_blob_to_bytes :: proc(blob: ^ISlangBlob, allocator := context.allocator) -> []byte {
    if blob == nil do return nil
    defer slang_release(blob)
    size := blob.vtbl.getBufferSize(blob)
    if size == 0 do return nil
    ptr := blob.vtbl.getBufferPointer(blob)
    out := make([]byte, int(size), allocator)
    copy(out, ([^]byte)(ptr)[:size])
    return out
}

// Logs the diagnostic text held in a blob (as produced by loadModule/link/etc), then releases it.
slang_log_diagnostics :: proc(blob: ^ISlangBlob) {
    if blob == nil do return
    defer slang_release(blob)
    size := blob.vtbl.getBufferSize(blob)
    if size == 0 do return
    ptr := blob.vtbl.getBufferPointer(blob)
    text := string(([^]byte)(ptr)[:size])
    log.warnf("slang: %s", text)
}

// ---------------------------------------------------------------------------
// IGlobalSession
// ---------------------------------------------------------------------------

IGlobalSession_Vtbl :: struct {
    using _unknown:                     ISlangUnknown_Vtbl,
    createSession:                      proc "c" (this: ^IGlobalSession, desc: ^SessionDesc, outSession: ^^ISession) -> SlangResult,
    findProfile:                        proc "c" (this: ^IGlobalSession, name: cstring) -> SlangProfileID,
    setDownstreamCompilerPath:          rawptr,
    setDownstreamCompilerPrelude:       rawptr,
    getDownstreamCompilerPrelude:       rawptr,
    getBuildTagString:                  proc "c" (this: ^IGlobalSession) -> cstring,
    setDefaultDownstreamCompiler:       rawptr,
    getDefaultDownstreamCompiler:       rawptr,
    setLanguagePrelude:                 rawptr,
    getLanguagePrelude:                 rawptr,
    createCompileRequest:               rawptr, // deprecated
    addBuiltins:                        rawptr, // deprecated
    setSharedLibraryLoader:             rawptr,
    getSharedLibraryLoader:             rawptr,
    checkCompileTargetSupport:          proc "c" (this: ^IGlobalSession, target: SlangCompileTarget) -> SlangResult,
    checkPassThroughSupport:            rawptr,
    compileCoreModule:                  rawptr,
    loadCoreModule:                     rawptr,
    saveCoreModule:                     rawptr,
    findCapability:                     rawptr,
    setDownstreamCompilerForTransition: rawptr,
    getDownstreamCompilerForTransition: rawptr,
    getCompilerElapsedTime:             rawptr,
    setSPIRVCoreGrammar:                rawptr,
    parseCommandLineArguments:          rawptr,
    getSessionDescDigest:               rawptr,
    compileBuiltinModule:               rawptr,
    loadBuiltinModule:                  rawptr,
    saveBuiltinModule:                  rawptr,
    getDownstreamCompilerPath:          rawptr,
}

IGlobalSession :: struct {
    vtbl: ^IGlobalSession_Vtbl,
}

// ---------------------------------------------------------------------------
// ISession
// ---------------------------------------------------------------------------

ISession_Vtbl :: struct {
    using _unknown:                        ISlangUnknown_Vtbl,
    getGlobalSession:                      proc "c" (this: ^ISession) -> ^IGlobalSession,
    loadModule:                            proc "c" (this: ^ISession, moduleName: cstring, outDiagnostics: ^^ISlangBlob) -> ^IModule,
    loadModuleFromSource:                  proc "c" (this: ^ISession, moduleName: cstring, path: cstring, source: ^ISlangBlob, outDiagnostics: ^^ISlangBlob) -> ^IModule,
    createCompositeComponentType:          proc "c" (this: ^ISession, componentTypes: [^]^IComponentType, componentTypeCount: SlangInt, outCompositeComponentType: ^^IComponentType, outDiagnostics: ^^ISlangBlob) -> SlangResult,
    specializeType:                        rawptr,
    getTypeLayout:                         rawptr,
    getContainerType:                      rawptr,
    getDynamicType:                        rawptr,
    getTypeRTTIMangledName:                rawptr,
    getTypeConformanceWitnessMangledName:  rawptr,
    getTypeConformanceWitnessSequentialID: rawptr,
    createCompileRequest:                  rawptr,
    createTypeConformanceComponentType:    rawptr,
    loadModuleFromIRBlob:                  rawptr,
    getLoadedModuleCount:                  rawptr,
    getLoadedModule:                       rawptr,
    isBinaryModuleUpToDate:                rawptr,
    loadModuleFromSourceString:            proc "c" (this: ^ISession, moduleName: cstring, path: cstring, source: cstring, outDiagnostics: ^^ISlangBlob) -> ^IModule,
    getDynamicObjectRTTIBytes:             rawptr,
    loadModuleInfoFromIRBlob:              rawptr,
    getDeclSourceLocation:                 rawptr,
}

ISession :: struct {
    vtbl: ^ISession_Vtbl,
}

// ---------------------------------------------------------------------------
// IComponentType (base of IModule, IEntryPoint, composite/linked programs)
// ---------------------------------------------------------------------------

IComponentType_Vtbl :: struct {
    using _unknown:              ISlangUnknown_Vtbl,
    getSession:                  rawptr,
    getLayout:                   proc "c" (this: ^IComponentType, targetIndex: SlangInt, outDiagnostics: ^^ISlangBlob) -> ^ProgramLayout,
    getSpecializationParamCount: rawptr,
    getEntryPointCode:           proc "c" (this: ^IComponentType, entryPointIndex: SlangInt, targetIndex: SlangInt, outCode: ^^ISlangBlob, outDiagnostics: ^^ISlangBlob) -> SlangResult,
    getResultAsFileSystem:       rawptr,
    getEntryPointHash:           rawptr,
    specialize:                  rawptr,
    link:                        proc "c" (this: ^IComponentType, outLinkedComponentType: ^^IComponentType, outDiagnostics: ^^ISlangBlob) -> SlangResult,
    getEntryPointHostCallable:   rawptr,
    renameEntryPoint:            rawptr,
    linkWithOptions:             rawptr,
    getTargetCode:               proc "c" (this: ^IComponentType, targetIndex: SlangInt, outCode: ^^ISlangBlob, outDiagnostics: ^^ISlangBlob) -> SlangResult,
    getTargetMetadata:           rawptr,
    getEntryPointMetadata:       rawptr,
}

IComponentType :: struct {
    vtbl: ^IComponentType_Vtbl,
}

// ---------------------------------------------------------------------------
// IModule : IComponentType
// ---------------------------------------------------------------------------

IModule_Vtbl :: struct {
    using _component:          IComponentType_Vtbl,
    findEntryPointByName:      proc "c" (this: ^IModule, name: cstring, outEntryPoint: ^^IComponentType) -> SlangResult,
    getDefinedEntryPointCount: proc "c" (this: ^IModule) -> SlangInt32,
    getDefinedEntryPoint:      proc "c" (this: ^IModule, index: SlangInt32, outEntryPoint: ^^IComponentType) -> SlangResult,
    serialize:                 rawptr,
    writeToFile:               rawptr,
    getName:                   rawptr,
    getFilePath:               rawptr,
    getUniqueIdentity:         rawptr,
    findAndCheckEntryPoint:    proc "c" (this: ^IModule, name: cstring, stage: SlangStage, outEntryPoint: ^^IComponentType, outDiagnostics: ^^ISlangBlob) -> SlangResult,
    getDependencyFileCount:    rawptr,
    getDependencyFilePath:     rawptr,
    getModuleReflection:       rawptr,
    disassemble:               rawptr,
}

IModule :: struct {
    vtbl: ^IModule_Vtbl,
}

module_as_component :: proc(m: ^IModule) -> ^IComponentType {
    return cast(^IComponentType)m
}

// ---------------------------------------------------------------------------
// Compiler options / session & target descriptors
// ---------------------------------------------------------------------------

CompilerOptionName :: distinct c.int32_t
// Forces row-major matrix layout regardless of session/target defaults, matching `-matrix-layout-row-major`.
SLANG_COMPILER_OPTION_NAME_MATRIX_LAYOUT_ROW :: CompilerOptionName(9)

CompilerOptionValueKind :: distinct c.int32_t
SLANG_COMPILER_OPTION_VALUE_KIND_INT :: CompilerOptionValueKind(0)

CompilerOptionValue :: struct {
    kind:         CompilerOptionValueKind,
    intValue0:    c.int32_t,
    intValue1:    c.int32_t,
    stringValue0: cstring,
    stringValue1: cstring,
}

CompilerOptionEntry :: struct {
    name:  CompilerOptionName,
    value: CompilerOptionValue,
}

PreprocessorMacroDesc :: struct {
    name:  cstring,
    value: cstring,
}

TargetDesc :: struct {
    structureSize:               c.size_t,
    format:                      SlangCompileTarget,
    profile:                     SlangProfileID,
    flags:                       SlangTargetFlags,
    floatingPointMode:           SlangFloatingPointMode,
    lineDirectiveMode:           SlangLineDirectiveMode,
    forceGLSLScalarBufferLayout: bool,
    compilerOptionEntries:       ^CompilerOptionEntry,
    compilerOptionEntryCount:    c.uint32_t,
}

SessionDesc :: struct {
    structureSize:            c.size_t,
    targets:                  ^TargetDesc,
    targetCount:              SlangInt,
    flags:                    SessionFlags,
    defaultMatrixLayoutMode:  SlangMatrixLayoutMode,
    searchPaths:              ^cstring,
    searchPathCount:          SlangInt,
    preprocessorMacros:       ^PreprocessorMacroDesc,
    preprocessorMacroCount:   SlangInt,
    fileSystem:               rawptr,
    enableEffectAnnotations:  bool,
    allowGLSLSyntax:          bool,
    compilerOptionEntries:    ^CompilerOptionEntry,
    compilerOptionEntryCount: c.uint32_t,
    skipSPIRVValidation:      bool,
}

target_desc_default :: proc(format: SlangCompileTarget, profile := SLANG_PROFILE_UNKNOWN) -> TargetDesc {
    desc := TargetDesc {
        structureSize = size_of(TargetDesc),
        format = format,
        profile = profile,
        flags = kDefaultTargetFlags,
        floatingPointMode = SLANG_FLOATING_POINT_MODE_DEFAULT,
        lineDirectiveMode = SLANG_LINE_DIRECTIVE_MODE_DEFAULT,
    }
    return desc
}

session_desc_default :: proc(targets: ^TargetDesc, target_count: int) -> SessionDesc {
    desc := SessionDesc {
        structureSize = size_of(SessionDesc),
        targets = targets,
        targetCount = SlangInt(target_count),
        // Matches compile.sh's implicit default (verified: slangc with no matrix-layout
        // flag, and with -matrix-layout-column-major, both emit ColMajor-flavored codegen).
        defaultMatrixLayoutMode = SLANG_MATRIX_LAYOUT_COLUMN_MAJOR,
    }
    return desc
}

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
    // Match compile.sh's `-profile glsl_450` so codegen (matrix majorness, SPIR-V version) matches the CLI reference.
    profile := self.global_session.vtbl.findProfile(self.global_session, "glsl_450")
    target := target_desc_default(SLANG_SPIRV, profile)
    session_desc := session_desc_default(&target, 1)
    session_desc_set_search_paths(&session_desc, search_paths, ta)

    session: ^ISession
    {
        result := self.global_session.vtbl.createSession(self.global_session, &session_desc, &session)
        if result != SLANG_OK || session == nil {
            log.errorf("Failed to create Slang session (result=%v)", result)
            return nil, false
        }
    }
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

Slang_Compiled_Shader :: struct {
    name:  string,
    stage: SlangStage,
    spirv: []byte,
}

// Composites `entry_point` with `module`, links, and reads back its SPIR-V code
// plus the entry point's real name/stage (via reflection on the linked layout).
@(private = "file")
slang_link_and_get_code :: proc(
    session: ^ISession,
    module: ^IModule,
    entry_point: ^IComponentType,
    allocator: runtime.Allocator,
) -> (
    result: Slang_Compiled_Shader,
    ok: bool,
) {
    components := [2]^IComponentType{module_as_component(module), entry_point}

    diagnostics: ^ISlangBlob
    program: ^IComponentType
    if r := session.vtbl.createCompositeComponentType(session, &components[0], 2, &program, &diagnostics); r != SLANG_OK || program == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to create Slang composite component type")
        return {}, false
    }
    slang_log_diagnostics(diagnostics)
    defer slang_release(program)

    diagnostics = nil
    linked: ^IComponentType
    if r := program.vtbl.link(program, &linked, &diagnostics); r != SLANG_OK || linked == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to link Slang program")
        return {}, false
    }
    slang_log_diagnostics(diagnostics)
    defer slang_release(linked)

    diagnostics = nil
    layout := linked.vtbl.getLayout(linked, 0, &diagnostics)
    slang_log_diagnostics(diagnostics)

    name := "main"
    stage := SlangStage(0)
    if layout != nil && spReflection_getEntryPointCount(layout) > 0 {
        if refl_ep := spReflection_getEntryPointByIndex(layout, 0); refl_ep != nil {
            name = string(spReflectionEntryPoint_getName(refl_ep))
            stage = spReflectionEntryPoint_getStage(refl_ep)
        }
    }

    diagnostics = nil
    code: ^ISlangBlob
    if r := linked.vtbl.getEntryPointCode(linked, 0, 0, &code, &diagnostics); r != SLANG_OK || code == nil {
        slang_log_diagnostics(diagnostics)
        log.errorf("Failed to get Slang entry point SPIR-V code")
        return {}, false
    }
    slang_log_diagnostics(diagnostics)

    return Slang_Compiled_Shader{
        name = strings.clone(name, allocator),
        stage = stage,
        spirv = slang_blob_to_bytes(code, allocator),
    }, true
}

// Compiles every `[shader(...)]`-tagged entry point found in `source`. If none are tagged,
// falls back to checking a single `main` function against each common stage in turn
// (compute, then vertex, then fragment) and compiles whichever one type-checks.
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
    shaders: []Slang_Compiled_Shader,
    ok: bool,
) {
    ensure(self.global_session != nil, "Slang_Compiler not initialized")

    ta := context.temp_allocator
    // Match compile.sh's `-profile glsl_450` so codegen (matrix majorness, SPIR-V version) matches the CLI reference.
    profile := self.global_session.vtbl.findProfile(self.global_session, "glsl_450")
    target := target_desc_default(SLANG_SPIRV, profile)
    session_desc := session_desc_default(&target, 1)
    session_desc_set_search_paths(&session_desc, search_paths, ta)

    session: ^ISession
    {
        result := self.global_session.vtbl.createSession(self.global_session, &session_desc, &session)
        if result != SLANG_OK || session == nil {
            log.errorf("Failed to create Slang session (result=%v)", result)
            return nil, false
        }
    }
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
    // `module` is owned by `session` (per slang.h: "modules ... remain resident until the
    // session is released"); it must NOT be released here.

    entry_points: [dynamic]^IComponentType
    entry_points.allocator = ta
    defer for ep in entry_points {
        slang_release(ep)
    }

    if defined_count := module.vtbl.getDefinedEntryPointCount(module); defined_count > 0 {
        for i in SlangInt32(0) ..< defined_count {
            ep: ^IComponentType
            if r := module.vtbl.getDefinedEntryPoint(module, i, &ep); r == SLANG_OK && ep != nil {
                append(&entry_points, ep)
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
        return nil, false
    }

    out := make([dynamic]Slang_Compiled_Shader, allocator)
    for ep in entry_points {
        compiled, cok := slang_link_and_get_code(session, module, ep, allocator)
        if !cok {
            for s in out {
                delete(s.spirv, allocator)
                delete(s.name, allocator)
            }
            delete(out)
            log.errorf("Failed to compile a Slang entry point in module %s", module_name)
            return nil, false
        }
        append(&out, compiled)
    }

    return out[:], true
}

