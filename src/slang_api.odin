package astro

// Hand-written bindings for Slang's C++ API (slang.h).
//
// Slang's public headers are C++-only: the compiler API is exposed through COM-style
// virtual interfaces (IGlobalSession, ISession, IComponentType, ...), so a C binding
// generator such as odin-c-bindgen cannot produce these. The vtable structs below must
// mirror the declaration order in slang.h exactly -- reordering them silently changes
// which function gets called.
//
// Verified against Vulkan SDK 1.4.357.1 (x86_64/include/slang/slang.h). Treat the vtable
// layout as pinned to that SDK version: when updating Slang, re-check each interface in
// slang.h and extend/rename the trailing `rawptr` placeholders as needed.
//
// The plain C API (slang_createGlobalSession, slang_shutdown, spReflection_*) is declared
// in the same foreign block below.

import "core:c"
import "core:log"

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
    getDownstreamCompilerVersion:       rawptr,
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
