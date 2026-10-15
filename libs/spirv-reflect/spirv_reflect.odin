/*
 Copyright 2017-2022 Google Inc.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

/*

VERSION HISTORY

  1.0   (2018-03-27) Initial public release

*/

// clang-format off
/*!

 @file spirv_reflect.h

*/
package spirv

import "core:c"

foreign import lib "libspirv-reflect.a"
_ :: lib

/*! @enum SpvReflectResult

*/
SpvReflectResult :: enum u32 {
	SUCCESS                                    = 0,
	NOT_READY                                  = 1,
	ERROR_PARSE_FAILED                         = 2,
	ERROR_ALLOC_FAILED                         = 3,
	ERROR_RANGE_EXCEEDED                       = 4,
	ERROR_NULL_POINTER                         = 5,
	ERROR_INTERNAL_ERROR                       = 6,
	ERROR_COUNT_MISMATCH                       = 7,
	ERROR_ELEMENT_NOT_FOUND                    = 8,
	ERROR_SPIRV_INVALID_CODE_SIZE              = 9,
	ERROR_SPIRV_INVALID_MAGIC_NUMBER           = 10,
	ERROR_SPIRV_UNEXPECTED_EOF                 = 11,
	ERROR_SPIRV_INVALID_ID_REFERENCE           = 12,
	ERROR_SPIRV_SET_NUMBER_OVERFLOW            = 13,
	ERROR_SPIRV_INVALID_STORAGE_CLASS          = 14,
	ERROR_SPIRV_RECURSION                      = 15,
	ERROR_SPIRV_INVALID_INSTRUCTION            = 16,
	ERROR_SPIRV_UNEXPECTED_BLOCK_DATA          = 17,
	ERROR_SPIRV_INVALID_BLOCK_MEMBER_REFERENCE = 18,
	ERROR_SPIRV_INVALID_ENTRY_POINT            = 19,
	ERROR_SPIRV_INVALID_EXECUTION_MODE         = 20,
	ERROR_SPIRV_MAX_RECURSIVE_EXCEEDED         = 21,
}

/*! @enum SpvReflectModuleFlagBits

SPV_REFLECT_MODULE_FLAG_NO_COPY - Disables copying of SPIR-V code
when a SPIRV-Reflect shader module is created. It is the
responsibility of the calling program to ensure that the pointer
remains valid and the memory it's pointing to is not freed while
SPIRV-Reflect operations are taking place. Freeing the backing
memory will cause undefined behavior or most likely a crash.
This is flag is intended for cases where the memory overhead of
storing the copied SPIR-V is undesirable.

*/
SpvReflectModuleFlagBits :: enum u32 {
	NE    = 0,
	_COPY = 1,
}

SpvReflectModuleFlags :: u32

/*! @enum SpvReflectTypeFlagBits

*/
SpvReflectTypeFlagBits :: enum u32 {
	UNDEFINED                       = 0,
	VOID                            = 1,
	BOOL                            = 2,
	INT                             = 4,
	FLOAT                           = 8,
	VECTOR                          = 256,
	MATRIX                          = 512,
	EXTERNAL_IMAGE                  = 65536,
	EXTERNAL_SAMPLER                = 131072,
	EXTERNAL_SAMPLED_IMAGE          = 262144,
	EXTERNAL_BLOCK                  = 524288,
	EXTERNAL_ACCELERATION_STRUCTURE = 1048576,
	EXTERNAL_TENSOR_ARM             = 2097152,
	EXTERNAL_MASK                   = 16711680,
	STRUCT                          = 268435456,
	ARRAY                           = 536870912,
	REF                             = 1073741824,
}

SpvReflectTypeFlags :: u32

/*! @enum SpvReflectDecorationBits

NOTE: HLSL row_major and column_major decorations are reversed
in SPIR-V. Meaning that matrices declrations with row_major
will get reflected as column_major and vice versa. The
row and column decorations get appied during the compilation.
SPIRV-Reflect reads the data as is and does not make any
attempt to correct it to match what's in the source.

The Patch, PerVertex, and PerTask are used for Interface
variables that can have array

*/
SpvReflectDecorationFlagBits :: enum u32 {
	NONE                = 0,
	BLOCK               = 1,
	BUFFER_BLOCK        = 2,
	ROW_MAJOR           = 4,
	COLUMN_MAJOR        = 8,
	BUILT_IN            = 16,
	NOPERSPECTIVE       = 32,
	FLAT                = 64,
	NON_WRITABLE        = 128,
	RELAXED_PRECISION   = 256,
	NON_READABLE        = 512,
	PATCH               = 1024,
	PER_VERTEX          = 2048,
	PER_TASK            = 4096,
	WEIGHT_TEXTURE      = 8192,
	BLOCK_MATCH_TEXTURE = 16384,
}

SpvReflectDecorationFlags :: u32

// Based of SPV_GOOGLE_user_type
SpvReflectUserType :: enum u32 {
	INVALID                                = 0,
	CBUFFER                                = 1,
	TBUFFER                                = 2,
	APPEND_STRUCTURED_BUFFER               = 3,
	BUFFER                                 = 4,
	BYTE_ADDRESS_BUFFER                    = 5,
	CONSTANT_BUFFER                        = 6,
	CONSUME_STRUCTURED_BUFFER              = 7,
	INPUT_PATCH                            = 8,
	OUTPUT_PATCH                           = 9,
	RASTERIZER_ORDERED_BUFFER              = 10,
	RASTERIZER_ORDERED_BYTE_ADDRESS_BUFFER = 11,
	RASTERIZER_ORDERED_STRUCTURED_BUFFER   = 12,
	RASTERIZER_ORDERED_TEXTURE_1D          = 13,
	RASTERIZER_ORDERED_TEXTURE_1D_ARRAY    = 14,
	RASTERIZER_ORDERED_TEXTURE_2D          = 15,
	RASTERIZER_ORDERED_TEXTURE_2D_ARRAY    = 16,
	RASTERIZER_ORDERED_TEXTURE_3D          = 17,
	RAYTRACING_ACCELERATION_STRUCTURE      = 18,
	RW_BUFFER                              = 19,
	RW_BYTE_ADDRESS_BUFFER                 = 20,
	RW_STRUCTURED_BUFFER                   = 21,
	RW_TEXTURE_1D                          = 22,
	RW_TEXTURE_1D_ARRAY                    = 23,
	RW_TEXTURE_2D                          = 24,
	RW_TEXTURE_2D_ARRAY                    = 25,
	RW_TEXTURE_3D                          = 26,
	STRUCTURED_BUFFER                      = 27,
	SUBPASS_INPUT                          = 28,
	SUBPASS_INPUT_MS                       = 29,
	TEXTURE_1D                             = 30,
	TEXTURE_1D_ARRAY                       = 31,
	TEXTURE_2D                             = 32,
	TEXTURE_2D_ARRAY                       = 33,
	TEXTURE_2DMS                           = 34,
	TEXTURE_2DMS_ARRAY                     = 35,
	TEXTURE_3D                             = 36,
	TEXTURE_BUFFER                         = 37,
	TEXTURE_CUBE                           = 38,
	TEXTURE_CUBE_ARRAY                     = 39,
}

/*! @enum SpvReflectResourceType

*/
SpvReflectResourceType :: enum u32 {
	UNDEFINED = 0,
	SAMPLER   = 1,
	CBV       = 2,
	SRV       = 4,
	UAV       = 8,
}

/*! @enum SpvReflectFormat

*/
SpvReflectFormat :: enum u32 {
	UNDEFINED           = 0,   // = VK_FORMAT_UNDEFINED
	R16_UINT            = 74,  // = VK_FORMAT_R16_UINT
	R16_SINT            = 75,  // = VK_FORMAT_R16_SINT
	R16_SFLOAT          = 76,  // = VK_FORMAT_R16_SFLOAT
	R16G16_UINT         = 81,  // = VK_FORMAT_R16G16_UINT
	R16G16_SINT         = 82,  // = VK_FORMAT_R16G16_SINT
	R16G16_SFLOAT       = 83,  // = VK_FORMAT_R16G16_SFLOAT
	R16G16B16_UINT      = 88,  // = VK_FORMAT_R16G16B16_UINT
	R16G16B16_SINT      = 89,  // = VK_FORMAT_R16G16B16_SINT
	R16G16B16_SFLOAT    = 90,  // = VK_FORMAT_R16G16B16_SFLOAT
	R16G16B16A16_UINT   = 95,  // = VK_FORMAT_R16G16B16A16_UINT
	R16G16B16A16_SINT   = 96,  // = VK_FORMAT_R16G16B16A16_SINT
	R16G16B16A16_SFLOAT = 97,  // = VK_FORMAT_R16G16B16A16_SFLOAT
	R32_UINT            = 98,  // = VK_FORMAT_R32_UINT
	R32_SINT            = 99,  // = VK_FORMAT_R32_SINT
	R32_SFLOAT          = 100, // = VK_FORMAT_R32_SFLOAT
	R32G32_UINT         = 101, // = VK_FORMAT_R32G32_UINT
	R32G32_SINT         = 102, // = VK_FORMAT_R32G32_SINT
	R32G32_SFLOAT       = 103, // = VK_FORMAT_R32G32_SFLOAT
	R32G32B32_UINT      = 104, // = VK_FORMAT_R32G32B32_UINT
	R32G32B32_SINT      = 105, // = VK_FORMAT_R32G32B32_SINT
	R32G32B32_SFLOAT    = 106, // = VK_FORMAT_R32G32B32_SFLOAT
	R32G32B32A32_UINT   = 107, // = VK_FORMAT_R32G32B32A32_UINT
	R32G32B32A32_SINT   = 108, // = VK_FORMAT_R32G32B32A32_SINT
	R32G32B32A32_SFLOAT = 109, // = VK_FORMAT_R32G32B32A32_SFLOAT
	R64_UINT            = 110, // = VK_FORMAT_R64_UINT
	R64_SINT            = 111, // = VK_FORMAT_R64_SINT
	R64_SFLOAT          = 112, // = VK_FORMAT_R64_SFLOAT
	R64G64_UINT         = 113, // = VK_FORMAT_R64G64_UINT
	R64G64_SINT         = 114, // = VK_FORMAT_R64G64_SINT
	R64G64_SFLOAT       = 115, // = VK_FORMAT_R64G64_SFLOAT
	R64G64B64_UINT      = 116, // = VK_FORMAT_R64G64B64_UINT
	R64G64B64_SINT      = 117, // = VK_FORMAT_R64G64B64_SINT
	R64G64B64_SFLOAT    = 118, // = VK_FORMAT_R64G64B64_SFLOAT
	R64G64B64A64_UINT   = 119, // = VK_FORMAT_R64G64B64A64_UINT
	R64G64B64A64_SINT   = 120, // = VK_FORMAT_R64G64B64A64_SINT
	R64G64B64A64_SFLOAT = 121, // = VK_FORMAT_R64G64B64A64_SFLOAT
}

/*! @enum SpvReflectVariableFlagBits

*/
SpvReflectVariableFlagBits :: enum u32 {
	NONE                  = 0,
	UNUSED                = 1,

	// If variable points to a copy of the PhysicalStorageBuffer struct
	PHYSICAL_POINTER_COPY = 2,
}

SpvReflectVariableFlags :: u32

/*! @enum SpvReflectDescriptorType

*/
SpvReflectDescriptorType :: enum u32 {
	SAMPLER                    = 0,          // = VK_DESCRIPTOR_TYPE_SAMPLER
	COMBINED_IMAGE_SAMPLER     = 1,          // = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
	SAMPLED_IMAGE              = 2,          // = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
	STORAGE_IMAGE              = 3,          // = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
	UNIFORM_TEXEL_BUFFER       = 4,          // = VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
	STORAGE_TEXEL_BUFFER       = 5,          // = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
	UNIFORM_BUFFER             = 6,          // = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
	STORAGE_BUFFER             = 7,          // = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
	UNIFORM_BUFFER_DYNAMIC     = 8,          // = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
	STORAGE_BUFFER_DYNAMIC     = 9,          // = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC
	INPUT_ATTACHMENT           = 10,         // = VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT
	ACCELERATION_STRUCTURE_KHR = 1000150000, // = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR
	TENSOR_ARM                 = 1000460000, // = VK_DESCRIPTOR_TYPE_TENSOR_ARM
}

/*! @enum SpvReflectShaderStageFlagBits

*/
SpvReflectShaderStageFlagBits :: enum u32 {
	VERTEX_BIT                  = 1,    // = VK_SHADER_STAGE_VERTEX_BIT
	TESSELLATION_CONTROL_BIT    = 2,    // = VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT
	TESSELLATION_EVALUATION_BIT = 4,    // = VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT
	GEOMETRY_BIT                = 8,    // = VK_SHADER_STAGE_GEOMETRY_BIT
	FRAGMENT_BIT                = 16,   // = VK_SHADER_STAGE_FRAGMENT_BIT
	COMPUTE_BIT                 = 32,   // = VK_SHADER_STAGE_COMPUTE_BIT
	TASK_BIT_NV                 = 64,   // = VK_SHADER_STAGE_TASK_BIT_NV
	TASK_BIT_EXT                = 64,   // = VK_SHADER_STAGE_CALLABLE_BIT_EXT
	MESH_BIT_NV                 = 128,  // = VK_SHADER_STAGE_MESH_BIT_NV
	MESH_BIT_EXT                = 128,  // = VK_SHADER_STAGE_CALLABLE_BIT_EXT
	RAYGEN_BIT_KHR              = 256,  // = VK_SHADER_STAGE_RAYGEN_BIT_KHR
	ANY_HIT_BIT_KHR             = 512,  // = VK_SHADER_STAGE_ANY_HIT_BIT_KHR
	CLOSEST_HIT_BIT_KHR         = 1024, // = VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR
	MISS_BIT_KHR                = 2048, // = VK_SHADER_STAGE_MISS_BIT_KHR
	INTERSECTION_BIT_KHR        = 4096, // = VK_SHADER_STAGE_INTERSECTION_BIT_KHR
	CALLABLE_BIT_KHR            = 8192, // = VK_SHADER_STAGE_CALLABLE_BIT_KHR
}

/*! @enum SpvReflectGenerator

*/
SpvReflectGenerator :: enum u32 {
	KHRONOS_LLVM_SPIRV_TRANSLATOR         = 6,
	KHRONOS_SPIRV_TOOLS_ASSEMBLER         = 7,
	KHRONOS_GLSLANG_REFERENCE_FRONT_END   = 8,
	GOOGLE_SHADERC_OVER_GLSLANG           = 13,
	GOOGLE_SPIREGG                        = 14,
	GOOGLE_RSPIRV                         = 15,
	X_LEGEND_MESA_MESAIR_SPIRV_TRANSLATOR = 16,
	KHRONOS_SPIRV_TOOLS_LINKER            = 17,
	WINE_VKD3D_SHADER_COMPILER            = 18,
	CLAY_CLAY_SHADER_COMPILER             = 19,
	SLANG_SHADER_COMPILER                 = 40,
}

SPV_REFLECT_MAX_ARRAY_DIMS             :: 32
SPV_REFLECT_MAX_DESCRIPTOR_SETS        :: 64
SPV_REFLECT_BINDING_NUMBER_DONT_CHANGE :: -1
SPV_REFLECT_SET_NUMBER_DONT_CHANGE     :: -1

SpvReflectNumericTraits :: struct {
	scalar:  Scalar,
	vector:  Vector,
	_matrix: Matrix,
}

Scalar :: struct {
	width:      u32,
	signedness: u32,
}

Vector :: struct {
	component_count: u32,
}

Matrix :: struct {
	column_count: u32,
	row_count:    u32,
	stride:       u32, // Measured in bytes
}

SpvReflectImageTraits :: struct {
	dim:          SpvDim,
	depth:        u32,
	arrayed:      u32,
	ms:           u32, // 0: single-sampled; 1: multisampled
	sampled:      u32,
	image_format: SpvImageFormat,
}

SpvReflectArrayDimType :: enum u32 {
	SPV_REFLECT_ARRAY_DIM_RUNTIME = 0, // OpTypeRuntimeArray
}

SpvReflectArrayTraits :: struct {
	dims_count: u32,

	// Each entry is either:
	// - specialization constant dimension
	// - OpTypeRuntimeArray
	// - the array length otherwise
	dims: [32]u32,

	// Stores Ids for dimensions that are specialization constants
	spec_constant_op_ids: [32]u32,
	stride:               u32, // Measured in bytes
}

SpvReflectBindingArrayTraits :: struct {
	dims_count: u32,
	dims:       [32]u32,
}

SpvReflectTensorTraits :: struct {
	// 0 if the tensor is unranked, ~0 if the rank is not an OpConstant
	rank: u32,

	// All 0 if the tensor is not shaped, ~0 for a dimension that is not an OpConstant
	dims: [32]u32,
}

/*! @struct SpvReflectTypeDescription
@brief Information about an OpType* instruction
*/
SpvReflectTypeDescription :: struct {
	id:        u32,
	op:        SpvOp,
	type_name: cstring,

	// Non-NULL if type is member of a struct
	struct_member_name: cstring,

	// The storage class (SpvStorageClass) if the type, and -1 if it does not have a storage class.
	storage_class:    i32,
	type_flags:       SpvReflectTypeFlags,
	decoration_flags: SpvReflectDecorationFlags,
	traits:           Traits,

	// If underlying type is a struct (ex. array of structs)
	// this gives access to the OpTypeStruct
	struct_type_description: ^SpvReflectTypeDescription,

	// Some pointers to SpvReflectTypeDescription are really
	// just copies of another reference to the same OpType
	copied: u32,

	// @deprecated use struct_type_description instead
	member_count: u32,

	// @deprecated use struct_type_description instead
	members: ^SpvReflectTypeDescription,
}

Traits :: struct {
	numeric: SpvReflectNumericTraits,
	image:   SpvReflectImageTraits,
	array:   SpvReflectArrayTraits,
	tensor:  SpvReflectTensorTraits,
}

/*! @struct SpvReflectInterfaceVariable
@brief The OpVariable that is either an Input or Output to the module
*/
SpvReflectInterfaceVariable :: struct {
	spirv_id:         u32,
	name:             cstring,
	location:         u32,
	component:        u32,
	storage_class:    SpvStorageClass,
	semantic:         cstring,
	decoration_flags: SpvReflectDecorationFlags,

	// The builtin id (SpvBuiltIn) if the variable is a builtin, and -1 otherwise.
	built_in:     i32,
	numeric:      SpvReflectNumericTraits,
	array:        SpvReflectArrayTraits,
	member_count: u32,
	members:      ^SpvReflectInterfaceVariable,
	format:       SpvReflectFormat,

	// NOTE: SPIR-V shares type references for variables
	//       that have the same underlying type. This means
	//       that the same type name will appear for multiple
	//       variables.
	type_description: ^SpvReflectTypeDescription,

	word_offset: struct {
		location: u32,
	},
}

/*! @struct SpvReflectBlockVariable

*/
SpvReflectBlockVariable :: struct {
	spirv_id: u32,
	name:     cstring,

	// For Push Constants, this is the lowest offset of all memebers
	offset:           u32, // Measured in bytes
	absolute_offset:  u32, // Measured in bytes
	size:             u32, // Measured in bytes
	padded_size:      u32, // Measured in bytes
	decoration_flags: SpvReflectDecorationFlags,
	numeric:          SpvReflectNumericTraits,
	array:            SpvReflectArrayTraits,
	flags:            SpvReflectVariableFlags,
	member_count:     u32,
	members:          ^SpvReflectBlockVariable,
	type_description: ^SpvReflectTypeDescription,

	word_offset: struct {
		offset: u32,
	},
}

/*! @struct SpvReflectDescriptorBinding

*/
SpvReflectDescriptorBinding :: struct {
	spirv_id:                         u32,
	name:                             cstring,
	binding:                          u32,
	input_attachment_index:           u32,
	set:                              u32,
	descriptor_type:                  SpvReflectDescriptorType,
	resource_type:                    SpvReflectResourceType,
	image:                            SpvReflectImageTraits,
	block:                            SpvReflectBlockVariable,
	array:                            SpvReflectBindingArrayTraits,
	count:                            u32,
	accessed:                         u32,
	uav_counter_id:                   u32,
	uav_counter_binding:              ^SpvReflectDescriptorBinding,
	byte_address_buffer_offset_count: u32,
	byte_address_buffer_offsets:      ^u32,
	type_description:                 ^SpvReflectTypeDescription,

	word_offset: struct {
		binding: u32,
		set:     u32,
	},

	decoration_flags: SpvReflectDecorationFlags,

	// Requires SPV_GOOGLE_user_type
	user_type: SpvReflectUserType,
}

/*! @struct SpvReflectDescriptorSet

*/
SpvReflectDescriptorSet :: struct {
	set:           u32,
	binding_count: u32,
	bindings:      ^^SpvReflectDescriptorBinding,
}

SpvReflectExecutionModeValue :: enum i32 {
	SPV_REFLECT_EXECUTION_MODE_SPEC_CONSTANT = -1, // specialization constant
}

/*! @struct SpvReflectEntryPointResourceHeapAccess
@brief One distinct resource-heap access pattern (OpUntypedAccessChainKHR
element type + stride) reachable from this entry point.
*/
SpvReflectEntryPointResourceHeapAccess :: struct {
	heap_name:             cstring,
	runtime_array_type_id: u32,
	stride:                u32, // UINT32_MAX when not specified by shader (e.g. ArrayStride from OpConstantSizeOfEXT) or could not be resolved
	descriptor_type:       SpvReflectDescriptorType,
	type_description:      ^SpvReflectTypeDescription,
}

/*! @struct SpvReflectEntryPointSamplerHeapAccess
@brief One distinct sampler-heap access pattern reachable from this entry
point (usually at most one).
*/
SpvReflectEntryPointSamplerHeapAccess :: struct {
	heap_name:             cstring,
	runtime_array_type_id: u32,
	stride:                u32, // UINT32_MAX when not specified by shader (e.g. ArrayStride from OpConstantSizeOfEXT) or could not be resolved
	type_description:      ^SpvReflectTypeDescription,
}

/*! @struct SpvReflectEntryPoint

*/
SpvReflectEntryPoint :: struct {
	name:                     cstring,
	id:                       u32,
	spirv_execution_model:    SpvExecutionModel,
	shader_stage:             SpvReflectShaderStageFlagBits,
	input_variable_count:     u32,
	input_variables:          ^^SpvReflectInterfaceVariable,
	output_variable_count:    u32,
	output_variables:         ^^SpvReflectInterfaceVariable,
	interface_variable_count: u32,
	interface_variables:      ^SpvReflectInterfaceVariable,
	descriptor_set_count:     u32,
	descriptor_sets:          ^SpvReflectDescriptorSet,
	used_uniform_count:       u32,
	used_uniforms:            ^u32,
	used_push_constant_count: u32,
	used_push_constants:      ^u32,
	execution_mode_count:     u32,
	execution_modes:          ^SpvExecutionMode,
	local_size:               LocalSize,
	invocations:              u32, // valid for geometry
	output_vertices:          u32, // valid for geometry, tesselation

	// SPV_EXT_descriptor_heap: distinct heap access patterns reachable from this
	// entry point's static call graph. Each entry corresponds to a unique
	// (heap variable, OpUntypedAccessChainKHR Data Type) pair.
	resource_heap_access_count: u32,
	resource_heap_accesses:     ^SpvReflectEntryPointResourceHeapAccess,
	sampler_heap_access_count:  u32,
	sampler_heap_accesses:      ^SpvReflectEntryPointSamplerHeapAccess,
}

LocalSize :: struct {
	x: u32,
	y: u32,
	z: u32,
}

/*! @struct SpvReflectGraphEntryPoint
@brief An OpGraphEntryPointARM (SPV_ARM_graph)
*/
SpvReflectGraphEntryPoint :: struct {
	name:         cstring,
	id:           u32, // OpGraphARM
	input_count:  u32,
	inputs:       ^^SpvReflectDescriptorBinding,
	output_count: u32,
	outputs:      ^^SpvReflectDescriptorBinding,
}

/*! @struct SpvReflectCapability

*/
SpvReflectCapability :: struct {
	value:       SpvCapability,
	word_offset: u32,
}

/*! @struct SpvReflectSpecId

*/
SpvReflectSpecializationConstant :: struct {
	spirv_id:         u32,
	constant_id:      u32,
	name:             cstring,
	type_description: ^SpvReflectTypeDescription,

	// Size of the default value in bytes (always a multiple of 4).
	// Will be 4 for 8/16/32-bit constants and 8 for 64-bit constants.
	default_value_size: u32,

	// Pointer to the raw default value data.
	// The interpretation of this data depends on type_description->op:
	// - SpvOpSpecConstantTrue:  size = 4, data = uint32_t(1)
	// - SpvOpSpecConstantFalse: size = 4, data = uint32_t(0)
	// - SpvOpSpecConstant:      data contains the bit pattern of the default value
	//   * The type will be a scalar integer or float.
	//   * Types 32 bits wide or smaller take one word.
	//   * Larger types take multiple words, with low-order words appearing first.
	default_value: rawptr,
}

/*! @struct SpvReflectShaderModule

*/
SpvReflectShaderModule :: struct {
	generator:                 SpvReflectGenerator,
	entry_point_name:          cstring,
	entry_point_id:            u32,
	entry_point_count:         u32,
	entry_points:              ^SpvReflectEntryPoint,
	source_language:           SpvSourceLanguage,
	source_language_version:   u32,
	source_file:               cstring,
	source_source:             cstring,
	capability_count:          u32,
	capabilities:              ^SpvReflectCapability,
	spirv_execution_model:     SpvExecutionModel,                 // Uses value(s) from first entry point
	shader_stage:              SpvReflectShaderStageFlagBits,     // Uses value(s) from first entry point
	descriptor_binding_count:  u32,                               // Uses value(s) from first entry point
	descriptor_bindings:       ^SpvReflectDescriptorBinding,      // Uses value(s) from first entry point
	descriptor_set_count:      u32,                               // Uses value(s) from first entry point
	descriptor_sets:           [64]SpvReflectDescriptorSet,       // Uses value(s) from first entry point
	input_variable_count:      u32,                               // Uses value(s) from first entry point
	input_variables:           ^^SpvReflectInterfaceVariable,     // Uses value(s) from first entry point
	output_variable_count:     u32,                               // Uses value(s) from first entry point
	output_variables:          ^^SpvReflectInterfaceVariable,     // Uses value(s) from first entry point
	interface_variable_count:  u32,                               // Uses value(s) from first entry point
	interface_variables:       ^SpvReflectInterfaceVariable,      // Uses value(s) from first entry point
	push_constant_block_count: u32,                               // Uses value(s) from first entry point
	push_constant_blocks:      ^SpvReflectBlockVariable,          // Uses value(s) from first entry point
	spec_constant_count:       u32,                               // Uses value(s) from first entry point
	spec_constants:            ^SpvReflectSpecializationConstant, // Uses value(s) from first entry point
	graph_entry_point_count:   u32,
	graph_entry_points:        ^SpvReflectGraphEntryPoint,
	_internal:                 ^Internal,
}

Internal :: struct {
	module_flags:           SpvReflectModuleFlags,
	spirv_size:             c.size_t,
	spirv_code:             ^u32,
	spirv_word_count:       u32,
	type_description_count: c.size_t,
	type_descriptions:      ^SpvReflectTypeDescription,
}

@(default_calling_convention="c")
foreign lib {
	/*! @fn spvReflectCreateShaderModule
	
	@param  size      Size in bytes of SPIR-V code.
	@param  p_code    Pointer to SPIR-V code.
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@return           SPV_REFLECT_RESULT_SUCCESS on success.
	
	*/
	spvReflectCreateShaderModule :: proc(size: c.size_t, p_code: rawptr, p_module: ^SpvReflectShaderModule) -> SpvReflectResult ---

	/*! @fn spvReflectCreateShaderModule2
	
	@param  flags     Flags for module creations.
	@param  size      Size in bytes of SPIR-V code.
	@param  p_code    Pointer to SPIR-V code.
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@return           SPV_REFLECT_RESULT_SUCCESS on success.
	
	*/
	spvReflectCreateShaderModule2 :: proc(flags: SpvReflectModuleFlags, size: c.size_t, p_code: rawptr, p_module: ^SpvReflectShaderModule) -> SpvReflectResult ---
	spvReflectGetShaderModule     :: proc(size: c.size_t, p_code: rawptr, p_module: ^SpvReflectShaderModule) -> SpvReflectResult ---

	/*! @fn spvReflectDestroyShaderModule
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	
	*/
	spvReflectDestroyShaderModule :: proc(p_module: ^SpvReflectShaderModule) ---

	/*! @fn spvReflectGetCodeSize
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@return           Returns the size of the SPIR-V in bytes
	
	*/
	spvReflectGetCodeSize :: proc(p_module: ^SpvReflectShaderModule) -> u32 ---

	/*! @fn spvReflectGetCode
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@return           Returns a const pointer to the compiled SPIR-V bytecode.
	
	*/
	spvReflectGetCode :: proc(p_module: ^SpvReflectShaderModule) -> ^u32 ---

	/*! @fn spvReflectGetEntryPoint
	
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  Name of the requested entry point.
	@return              Returns a const pointer to the requested entry point,
	or NULL if it's not found.
	*/
	spvReflectGetEntryPoint :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring) -> ^SpvReflectEntryPoint ---

	/*! @fn spvReflectGetGraphEntryPoint
	
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  Name of the requested graph entry point.
	@return              Returns a const pointer to the requested graph entry point,
	or NULL if it's not found.
	*/
	spvReflectGetGraphEntryPoint :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring) -> ^SpvReflectGraphEntryPoint ---

	/*! @fn spvReflectEnumerateDescriptorBindings
	
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  p_count      If pp_bindings is NULL, the module's descriptor binding
	count (across all descriptor sets) will be stored here.
	If pp_bindings is not NULL, *p_count must contain the
	module's descriptor binding count.
	@param  pp_bindings  If NULL, the module's total descriptor binding count
	will be written to *p_count.
	If non-NULL, pp_bindings must point to an array with
	*p_count entries, where pointers to the module's
	descriptor bindings will be written. The caller must not
	free the binding pointers written to this array.
	@return              If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateDescriptorBindings :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_bindings: ^^SpvReflectDescriptorBinding) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointDescriptorBindings
	@brief  Creates a listing of all descriptor bindings that are used in the
	static call tree of the given entry point.
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  The name of the entry point to get the descriptor bindings for.
	@param  p_count      If pp_bindings is NULL, the entry point's descriptor binding
	count (across all descriptor sets) will be stored here.
	If pp_bindings is not NULL, *p_count must contain the
	entry points's descriptor binding count.
	@param  pp_bindings  If NULL, the entry point's total descriptor binding count
	will be written to *p_count.
	If non-NULL, pp_bindings must point to an array with
	*p_count entries, where pointers to the entry point's
	descriptor bindings will be written. The caller must not
	free the binding pointers written to this array.
	@return              If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointDescriptorBindings :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_bindings: ^^SpvReflectDescriptorBinding) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateDescriptorSets
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  p_count   If pp_sets is NULL, the module's descriptor set
	count will be stored here.
	If pp_sets is not NULL, *p_count must contain the
	module's descriptor set count.
	@param  pp_sets   If NULL, the module's total descriptor set count
	will be written to *p_count.
	If non-NULL, pp_sets must point to an array with
	*p_count entries, where pointers to the module's
	descriptor sets will be written. The caller must not
	free the descriptor set pointers written to this array.
	@return           If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateDescriptorSets :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_sets: ^^SpvReflectDescriptorSet) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointDescriptorSets
	@brief  Creates a listing of all descriptor sets and their bindings that are
	used in the static call tree of a given entry point.
	@param  p_module    Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point The name of the entry point to get the descriptor bindings for.
	@param  p_count     If pp_sets is NULL, the module's descriptor set
	count will be stored here.
	If pp_sets is not NULL, *p_count must contain the
	module's descriptor set count.
	@param  pp_sets     If NULL, the module's total descriptor set count
	will be written to *p_count.
	If non-NULL, pp_sets must point to an array with
	*p_count entries, where pointers to the module's
	descriptor sets will be written. The caller must not
	free the descriptor set pointers written to this array.
	@return             If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointDescriptorSets :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_sets: ^^SpvReflectDescriptorSet) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateInterfaceVariables
	@brief  If the module contains multiple entry points, this will only get
	the interface variables for the first one.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_variables is NULL, the module's interface variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the module's interface variable count.
	@param  pp_variables  If NULL, the module's interface variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the module's
	interface variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateInterfaceVariables :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointInterfaceVariables
	@brief  Enumerate the interface variables for a given entry point.
	@param  entry_point The name of the entry point to get the interface variables for.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_variables is NULL, the entry point's interface variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the entry point's interface variable count.
	@param  pp_variables  If NULL, the entry point's interface variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the entry point's
	interface variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointInterfaceVariables :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateInputVariables
	@brief  If the module contains multiple entry points, this will only get
	the input variables for the first one.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_variables is NULL, the module's input variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the module's input variable count.
	@param  pp_variables  If NULL, the module's input variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the module's
	input variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateInputVariables :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointInputVariables
	@brief  Enumerate the input variables for a given entry point.
	@param  entry_point The name of the entry point to get the input variables for.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_variables is NULL, the entry point's input variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the entry point's input variable count.
	@param  pp_variables  If NULL, the entry point's input variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the entry point's
	input variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointInputVariables :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateOutputVariables
	@brief  Note: If the module contains multiple entry points, this will only get
	the output variables for the first one.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_variables is NULL, the module's output variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the module's output variable count.
	@param  pp_variables  If NULL, the module's output variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the module's
	output variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateOutputVariables :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointOutputVariables
	@brief  Enumerate the output variables for a given entry point.
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point   The name of the entry point to get the output variables for.
	@param  p_count       If pp_variables is NULL, the entry point's output variable
	count will be stored here.
	If pp_variables is not NULL, *p_count must contain
	the entry point's output variable count.
	@param  pp_variables  If NULL, the entry point's output variable count will be
	written to *p_count.
	If non-NULL, pp_variables must point to an array with
	*p_count entries, where pointers to the entry point's
	output variables will be written. The caller must not
	free the interface variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointOutputVariables :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_variables: ^^SpvReflectInterfaceVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumeratePushConstantBlocks
	@brief  Note: If the module contains multiple entry points, this will only get
	the push constant blocks for the first one.
	@param  p_module   Pointer to an instance of SpvReflectShaderModule.
	@param  p_count    If pp_blocks is NULL, the module's push constant
	block count will be stored here.
	If pp_blocks is not NULL, *p_count must
	contain the module's push constant block count.
	@param  pp_blocks  If NULL, the module's push constant block count
	will be written to *p_count.
	If non-NULL, pp_blocks must point to an
	array with *p_count entries, where pointers to
	the module's push constant blocks will be written.
	The caller must not free the block variables written
	to this array.
	@return            If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumeratePushConstantBlocks :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_blocks: ^^SpvReflectBlockVariable) -> SpvReflectResult ---
	spvReflectEnumeratePushConstants      :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_blocks: ^^SpvReflectBlockVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateEntryPointPushConstantBlocks
	@brief  Enumerate the push constant blocks used in the static call tree of a
	given entry point.
	@param  p_module   Pointer to an instance of SpvReflectShaderModule.
	@param  p_count    If pp_blocks is NULL, the entry point's push constant
	block count will be stored here.
	If pp_blocks is not NULL, *p_count must
	contain the entry point's push constant block count.
	@param  pp_blocks  If NULL, the entry point's push constant block count
	will be written to *p_count.
	If non-NULL, pp_blocks must point to an
	array with *p_count entries, where pointers to
	the entry point's push constant blocks will be written.
	The caller must not free the block variables written
	to this array.
	@return            If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the
	failure.
	
	*/
	spvReflectEnumerateEntryPointPushConstantBlocks :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_count: ^u32, pp_blocks: ^^SpvReflectBlockVariable) -> SpvReflectResult ---

	/*! @fn spvReflectEnumerateSpecializationConstants
	@param  p_module      Pointer to an instance of SpvReflectShaderModule.
	@param  p_count       If pp_blocks is NULL, the module's specialization constant
	count will be stored here. If pp_blocks is not NULL, *p_count
	must contain the module's specialization constant count.
	@param  pp_constants  If NULL, the module's specialization constant count
	will be written to *p_count. If non-NULL, pp_blocks must
	point to an array with *p_count entries, where pointers to
	the module's specialization constant blocks will be written.
	The caller must not free the  variables written to this array.
	@return               If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of the failure.
	*/
	spvReflectEnumerateSpecializationConstants :: proc(p_module: ^SpvReflectShaderModule, p_count: ^u32, pp_constants: ^^SpvReflectSpecializationConstant) -> SpvReflectResult ---

	/*! @fn spvReflectGetDescriptorBinding
	
	@param  p_module        Pointer to an instance of SpvReflectShaderModule.
	@param  binding_number  The "binding" value of the requested descriptor
	binding.
	@param  set_number      The "set" value of the requested descriptor binding.
	@param  p_result        If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return                 If the module contains a descriptor binding that
	matches the provided [binding_number, set_number]
	values, a pointer to that binding is returned. The
	caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note                    If the module contains multiple desriptor bindings
	with the same set and binding numbers, there are
	no guarantees about which binding will be returned.
	
	*/
	spvReflectGetDescriptorBinding :: proc(p_module: ^SpvReflectShaderModule, binding_number: u32, set_number: u32, p_result: ^SpvReflectResult) -> ^SpvReflectDescriptorBinding ---

	/*! @fn spvReflectGetEntryPointDescriptorBinding
	@brief  Get the descriptor binding with the given binding number and set
	number that is used in the static call tree of a certain entry
	point.
	@param  p_module        Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point     The entry point to get the binding from.
	@param  binding_number  The "binding" value of the requested descriptor
	binding.
	@param  set_number      The "set" value of the requested descriptor binding.
	@param  p_result        If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return                 If the entry point contains a descriptor binding that
	matches the provided [binding_number, set_number]
	values, a pointer to that binding is returned. The
	caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note                    If the entry point contains multiple desriptor bindings
	with the same set and binding numbers, there are
	no guarantees about which binding will be returned.
	
	*/
	spvReflectGetEntryPointDescriptorBinding :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, binding_number: u32, set_number: u32, p_result: ^SpvReflectResult) -> ^SpvReflectDescriptorBinding ---

	/*! @fn spvReflectGetDescriptorSet
	
	@param  p_module    Pointer to an instance of SpvReflectShaderModule.
	@param  set_number  The "set" value of the requested descriptor set.
	@param  p_result    If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return             If the module contains a descriptor set with the
	provided set_number, a pointer to that set is
	returned. The caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	
	*/
	spvReflectGetDescriptorSet :: proc(p_module: ^SpvReflectShaderModule, set_number: u32, p_result: ^SpvReflectResult) -> ^SpvReflectDescriptorSet ---

	/*! @fn spvReflectGetEntryPointDescriptorSet
	
	@param  p_module    Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point The entry point to get the descriptor set from.
	@param  set_number  The "set" value of the requested descriptor set.
	@param  p_result    If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return             If the entry point contains a descriptor set with the
	provided set_number, a pointer to that set is
	returned. The caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	
	*/
	spvReflectGetEntryPointDescriptorSet :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, set_number: u32, p_result: ^SpvReflectResult) -> ^SpvReflectDescriptorSet ---

	/* @fn spvReflectGetInputVariableByLocation
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  location  The "location" value of the requested input variable.
	A location of 0xFFFFFFFF will always return NULL
	with *p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the module contains an input interface variable
	with the provided location value, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetInputVariableByLocation :: proc(p_module: ^SpvReflectShaderModule, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---
	spvReflectGetInputVariable           :: proc(p_module: ^SpvReflectShaderModule, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetEntryPointInputVariableByLocation
	
	@param  p_module    Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point The entry point to get the input variable from.
	@param  location    The "location" value of the requested input variable.
	A location of 0xFFFFFFFF will always return NULL
	with *p_result == ELEMENT_NOT_FOUND.
	@param  p_result    If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return             If the entry point contains an input interface variable
	with the provided location value, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetEntryPointInputVariableByLocation :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetInputVariableBySemantic
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  semantic  The "semantic" value of the requested input variable.
	A semantic of NULL will return NULL.
	A semantic of "" will always return NULL with
	*p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the module contains an input interface variable
	with the provided semantic, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetInputVariableBySemantic :: proc(p_module: ^SpvReflectShaderModule, semantic: cstring, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetEntryPointInputVariableBySemantic
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point The entry point to get the input variable from.
	@param  semantic  The "semantic" value of the requested input variable.
	A semantic of NULL will return NULL.
	A semantic of "" will always return NULL with
	*p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the entry point contains an input interface variable
	with the provided semantic, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetEntryPointInputVariableBySemantic :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, semantic: cstring, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetOutputVariableByLocation
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  location  The "location" value of the requested output variable.
	A location of 0xFFFFFFFF will always return NULL
	with *p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the module contains an output interface variable
	with the provided location value, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetOutputVariableByLocation :: proc(p_module: ^SpvReflectShaderModule, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---
	spvReflectGetOutputVariable           :: proc(p_module: ^SpvReflectShaderModule, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetEntryPointOutputVariableByLocation
	
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  The entry point to get the output variable from.
	@param  location     The "location" value of the requested output variable.
	A location of 0xFFFFFFFF will always return NULL
	with *p_result == ELEMENT_NOT_FOUND.
	@param  p_result     If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return              If the entry point contains an output interface variable
	with the provided location value, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetEntryPointOutputVariableByLocation :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, location: u32, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetOutputVariableBySemantic
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  semantic  The "semantic" value of the requested output variable.
	A semantic of NULL will return NULL.
	A semantic of "" will always return NULL with
	*p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the module contains an output interface variable
	with the provided semantic, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetOutputVariableBySemantic :: proc(p_module: ^SpvReflectShaderModule, semantic: cstring, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/* @fn spvReflectGetEntryPointOutputVariableBySemantic
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  The entry point to get the output variable from.
	@param  semantic  The "semantic" value of the requested output variable.
	A semantic of NULL will return NULL.
	A semantic of "" will always return NULL with
	*p_result == ELEMENT_NOT_FOUND.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the entry point contains an output interface variable
	with the provided semantic, a pointer to that
	variable is returned. The caller must not free this
	pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	@note
	
	*/
	spvReflectGetEntryPointOutputVariableBySemantic :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, semantic: cstring, p_result: ^SpvReflectResult) -> ^SpvReflectInterfaceVariable ---

	/*! @fn spvReflectGetPushConstantBlock
	
	@param  p_module  Pointer to an instance of SpvReflectShaderModule.
	@param  index     The index of the desired block within the module's
	array of push constant blocks.
	@param  p_result  If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return           If the provided index is within range, a pointer to
	the corresponding push constant block is returned.
	The caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	
	*/
	spvReflectGetPushConstantBlock :: proc(p_module: ^SpvReflectShaderModule, index: u32, p_result: ^SpvReflectResult) -> ^SpvReflectBlockVariable ---
	spvReflectGetPushConstant      :: proc(p_module: ^SpvReflectShaderModule, index: u32, p_result: ^SpvReflectResult) -> ^SpvReflectBlockVariable ---

	/*! @fn spvReflectGetEntryPointPushConstantBlock
	@brief  Get the push constant block corresponding to the given entry point.
	As by the Vulkan specification there can be no more than one push
	constant block used by a given entry point, so if there is one it will
	be returned, otherwise NULL will be returned.
	@param  p_module     Pointer to an instance of SpvReflectShaderModule.
	@param  entry_point  The entry point to get the push constant block from.
	@param  p_result     If successful, SPV_REFLECT_RESULT_SUCCESS will be
	written to *p_result. Otherwise, a error code
	indicating the cause of the failure will be stored
	here.
	@return              If the provided index is within range, a pointer to
	the corresponding push constant block is returned.
	The caller must not free this pointer.
	If no match can be found, or if an unrelated error
	occurs, the return value will be NULL. Detailed
	error results are written to *pResult.
	
	*/
	spvReflectGetEntryPointPushConstantBlock :: proc(p_module: ^SpvReflectShaderModule, entry_point: cstring, p_result: ^SpvReflectResult) -> ^SpvReflectBlockVariable ---

	/*! @fn spvReflectChangeDescriptorBindingNumbers
	@brief  Assign new set and/or binding numbers to a descriptor binding.
	In addition to updating the reflection data, this function modifies
	the underlying SPIR-V bytecode. The updated code can be retrieved
	with spvReflectGetCode().  If the binding is used in multiple
	entry points within the module, it will be changed in all of them.
	@param  p_module            Pointer to an instance of SpvReflectShaderModule.
	@param  p_binding           Pointer to the descriptor binding to modify.
	@param  new_binding_number  The new binding number to assign to the
	provided descriptor binding.
	To leave the binding number unchanged, pass
	SPV_REFLECT_BINDING_NUMBER_DONT_CHANGE.
	@param  new_set_number      The new set number to assign to the
	provided descriptor binding. Successfully changing
	a descriptor binding's set number invalidates all
	existing SpvReflectDescriptorBinding and
	SpvReflectDescriptorSet pointers from this module.
	To leave the set number unchanged, pass
	SPV_REFLECT_SET_NUMBER_DONT_CHANGE.
	@return                     If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of
	the failure.
	*/
	spvReflectChangeDescriptorBindingNumbers :: proc(p_module: ^SpvReflectShaderModule, p_binding: ^SpvReflectDescriptorBinding, new_binding_number: u32, new_set_number: u32) -> SpvReflectResult ---
	spvReflectChangeDescriptorBindingNumber  :: proc(p_module: ^SpvReflectShaderModule, p_descriptor_binding: ^SpvReflectDescriptorBinding, new_binding_number: u32, optional_new_set_number: u32) -> SpvReflectResult ---

	/*! @fn spvReflectChangeDescriptorSetNumber
	@brief  Assign a new set number to an entire descriptor set (including
	all descriptor bindings in that set).
	In addition to updating the reflection data, this function modifies
	the underlying SPIR-V bytecode. The updated code can be retrieved
	with spvReflectGetCode().  If the descriptor set is used in
	multiple entry points within the module, it will be modified in all
	of them.
	@param  p_module        Pointer to an instance of SpvReflectShaderModule.
	@param  p_set           Pointer to the descriptor binding to modify.
	@param  new_set_number  The new set number to assign to the
	provided descriptor set, and all its descriptor
	bindings. Successfully changing a descriptor
	binding's set number invalidates all existing
	SpvReflectDescriptorBinding and
	SpvReflectDescriptorSet pointers from this module.
	To leave the set number unchanged, pass
	SPV_REFLECT_SET_NUMBER_DONT_CHANGE.
	@return                 If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of
	the failure.
	*/
	spvReflectChangeDescriptorSetNumber :: proc(p_module: ^SpvReflectShaderModule, p_set: ^SpvReflectDescriptorSet, new_set_number: u32) -> SpvReflectResult ---

	/*! @fn spvReflectChangeInputVariableLocation
	@brief  Assign a new location to an input interface variable.
	In addition to updating the reflection data, this function modifies
	the underlying SPIR-V bytecode. The updated code can be retrieved
	with spvReflectGetCode().
	It is the caller's responsibility to avoid assigning the same
	location to multiple input variables.  If the input variable is used
	by multiple entry points in the module, it will be changed in all of
	them.
	@param  p_module          Pointer to an instance of SpvReflectShaderModule.
	@param  p_input_variable  Pointer to the input variable to update.
	@param  new_location      The new location to assign to p_input_variable.
	@return                   If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of
	the failure.
	
	*/
	spvReflectChangeInputVariableLocation :: proc(p_module: ^SpvReflectShaderModule, p_input_variable: ^SpvReflectInterfaceVariable, new_location: u32) -> SpvReflectResult ---

	/*! @fn spvReflectChangeOutputVariableLocation
	@brief  Assign a new location to an output interface variable.
	In addition to updating the reflection data, this function modifies
	the underlying SPIR-V bytecode. The updated code can be retrieved
	with spvReflectGetCode().
	It is the caller's responsibility to avoid assigning the same
	location to multiple output variables.  If the output variable is used
	by multiple entry points in the module, it will be changed in all of
	them.
	@param  p_module          Pointer to an instance of SpvReflectShaderModule.
	@param  p_output_variable Pointer to the output variable to update.
	@param  new_location      The new location to assign to p_output_variable.
	@return                   If successful, returns SPV_REFLECT_RESULT_SUCCESS.
	Otherwise, the error code indicates the cause of
	the failure.
	
	*/
	spvReflectChangeOutputVariableLocation :: proc(p_module: ^SpvReflectShaderModule, p_output_variable: ^SpvReflectInterfaceVariable, new_location: u32) -> SpvReflectResult ---

	/*! @fn spvReflectSourceLanguage
	
	@param  source_lang  The source language code.
	@return Returns string of source language specified in \a source_lang.
	The caller must not free the memory associated with this string.
	*/
	spvReflectSourceLanguage :: proc(source_lang: SpvSourceLanguage) -> cstring ---

	/*! @fn spvReflectBlockVariableTypeName
	
	@param  p_var Pointer to block variable.
	@return Returns string of block variable's type description type name
	or NULL if p_var is NULL.
	*/
	spvReflectBlockVariableTypeName :: proc(p_var: ^SpvReflectBlockVariable) -> cstring ---
}

