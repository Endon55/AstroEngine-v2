package astro

import la "core:math/linalg"

Camera_Type :: enum {
    Perspective,
    Orthographic,
}

Camera :: struct {
    type: Camera_Type,
    transform: la.Matrix4f32, // camera-to-world matrix
    view: la.Matrix4f32, // world-to-camera matrix (inverse of transform)
    position: la.Vector3f32,
    rotation: la.Quaternionf32
}


camera_init :: proc(camera: ^Camera, camera_type: Camera_Type = .Perspective) {
    
    camera.type = camera_type
    camera.transform = la.MATRIX4F32_IDENTITY
    camera.view = la.MATRIX4F32_IDENTITY
    camera.rotation = la.QUATERNIONF32_IDENTITY

}

camera_update_transform :: proc(self: ^Camera) {
    //Do some check to see if the position/rotation has changed before recalculating.

    rotation := la.matrix4_from_quaternion(self.rotation)
    translate := la.matrix4_translate_f32(self.position)
    self.transform = la.matrix_mul(translate, rotation)

    inv_rotation := la.matrix4_from_quaternion(la.quaternion_inverse(self.rotation))
    inv_translate := la.matrix4_translate_f32(-self.position)
    self.view = la.matrix_mul(inv_rotation, inv_translate)
}

camera_forward :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 0, -1})
}

camera_right :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{1, 0, 0})
}

camera_up :: proc(self: ^Camera) -> la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 1, 0})
}

// local_movement is in camera space (x: right, y: up, z: backward), rotated into world space before being applied
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
// euler: pitch (x), yaw (y), roll (z) in radians, applied as a delta to the current rotation
camera_add_rotation :: proc(self: ^Camera, euler: la.Vector3f32) {
    delta := la.quaternion_from_pitch_yaw_roll_f32(euler.x, euler.y, euler.z)
    self.rotation = la.quaternion_normalize(la.quaternion_mul_quaternion(self.rotation, delta))
}


