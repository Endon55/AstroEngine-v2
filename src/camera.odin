package astro

import la "core:math/linalg"
import "core:math"

Camera_Type :: enum {
    Perspective,
    Orthographic,
}

// World/camera convention used by gameplay code is right=+X, forward=+Y, up=+Z.
// The renderer's projection matrix expects the standard right=+X, up=+Y, forward=-Z space,
// so this fixed rotation (about X by -90deg) converts into it once per frame, at no extra per-vertex cost.
AXIS_REMAP_ROTATION := la.quaternion_angle_axis_f32(la.to_radians(f32(-90)), la.Vector3f32{1, 0, 0})

Camera :: struct {
    type: Camera_Type,
    transform: la.Matrix4f32, // camera-to-world matrix
    view: la.Matrix4f32, // world-to-camera matrix (inverse of transform)
    position: la.Vector3f32,
    rotation: la.Quaternionf32,
    axis_locked: bool, // when true, rotation is restricted to yaw (world +Z) and pitch (local +X), no roll
    yaw: f32, // radians, about world +Z, only used while axis_locked
    pitch: f32, // radians, about local +X, only used while axis_locked
    pitch_min: f32,
    pitch_max: f32,
}


camera_init :: proc(camera: ^Camera, camera_type: Camera_Type = .Perspective, axis_locked: bool = false,) {
    
    camera.type = camera_type
    camera.transform = la.MATRIX4F32_IDENTITY
    camera.view = la.MATRIX4F32_IDENTITY
    camera.rotation = la.QUATERNIONF32_IDENTITY
    camera.axis_locked = axis_locked
    camera.yaw = 0
    camera.pitch = 0
    camera.pitch_min = la.to_radians(f32(-89))
    camera.pitch_max = la.to_radians(f32(89))

}

// Enables/disables the 2-axis (yaw/pitch) rotation lock. When enabling, the current
// orientation's yaw/pitch are extracted (roll is dropped) so the view doesn't snap.
camera_set_axis_lock :: proc(self: ^Camera, locked: bool) {
    if locked && !self.axis_locked {
        forward := camera_forward(self)
        self.pitch = math.asin(clamp(forward.z, -1, 1))
        self.yaw = math.atan2(-forward.x, forward.y)
        camera_clamp_pitch(self)
        camera_apply_yaw_pitch(self)
    }
    self.axis_locked = locked
}

// Sets the min/max pitch (up/down) angles allowed while axis_locked, in degrees.
camera_set_pitch_limits :: proc(self: ^Camera, min_degrees: f32, max_degrees: f32) {
    self.pitch_min = la.to_radians(min_degrees)
    self.pitch_max = la.to_radians(max_degrees)
    if self.axis_locked {
        camera_clamp_pitch(self)
        camera_apply_yaw_pitch(self)
    }
}

@(private)
camera_clamp_pitch :: proc(self: ^Camera) {
    self.pitch = clamp(self.pitch, self.pitch_min, self.pitch_max)
}

@(private)
camera_apply_yaw_pitch :: proc(self: ^Camera) {
    yaw_quat := la.quaternion_angle_axis_f32(self.yaw, la.Vector3f32{0, 0, 1})
    pitch_quat := la.quaternion_angle_axis_f32(self.pitch, la.Vector3f32{1, 0, 0})
    self.rotation = la.quaternion_normalize(la.quaternion_mul_quaternion(yaw_quat, pitch_quat))
}

camera_update_transform :: proc(self: ^Camera) {
    //Do some check to see if the position/rotation has changed before recalculating.

    rotation := la.matrix4_from_quaternion(self.rotation)
    translate := la.matrix4_translate_f32(self.position)
    self.transform = la.matrix_mul(translate, rotation)

    inv_rotation := la.matrix4_from_quaternion(la.quaternion_mul_quaternion(AXIS_REMAP_ROTATION, la.quaternion_inverse(self.rotation)))
    inv_translate := la.matrix4_translate_f32(-self.position)
    self.view = la.matrix_mul(inv_rotation, inv_translate)
}

camera_forward :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 1, 0})
}

camera_right :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{1, 0, 0})
}

camera_up :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 0, 1})
}

// local_movement is in camera space (x: right, y: forward, z: up), rotated into world space before being applied
camera_move :: proc(self: ^Camera, local_movement: la.Vector3f32) {
    world_movement := la.quaternion_mul_vector3(self.rotation, local_movement)
    self.position += world_movement
}

camera_move_forward :: proc(self: ^Camera, distance: f32) {
    self.position += camera_forward(self) * distance
}
camera_move_backward :: proc(self: ^Camera, distance: f32) {
    self.position += (camera_forward(self) * distance * -1)
}
camera_move_right :: proc(self: ^Camera, distance: f32) {
    self.position += camera_right(self)* distance
}
camera_move_left :: proc(self: ^Camera, distance: f32) {
    self.position += (camera_right(self) * distance * -1)
}
camera_move_up :: proc(self: ^Camera, distance: f32) {
    self.position += camera_up(self)* distance
}
camera_move_down :: proc(self: ^Camera, distance: f32) {
    self.position += (camera_up(self) * distance * -1)
}
// euler.x: pitch about local right (+X), euler.y: yaw about local up (+Z), euler.z: roll about local forward (+Y)
// When self.axis_locked, roll (euler.z) is ignored and pitch is clamped to [pitch_min, pitch_max].
camera_add_rotation :: proc(self: ^Camera, euler: la.Vector3f32) {
    if self.axis_locked {
        self.yaw += euler.y
        self.pitch += euler.x
        camera_clamp_pitch(self)
        camera_apply_yaw_pitch(self)
        return
    }

    pitch := la.quaternion_angle_axis_f32(euler.x, la.Vector3f32{1, 0, 0})
    yaw := la.quaternion_angle_axis_f32(euler.y, la.Vector3f32{0, 0, 1})
    roll := la.quaternion_angle_axis_f32(euler.z, la.Vector3f32{0, 1, 0})
    delta := la.quaternion_mul_quaternion(la.quaternion_mul_quaternion(yaw, pitch), roll)
    self.rotation = la.quaternion_normalize(la.quaternion_mul_quaternion(self.rotation, delta))
}


