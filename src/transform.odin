package astro

import  "core:math"
import la "core:math/linalg"

AXIS_FORMAT : la.Euler_Angle_Order = .XYZ

Transform :: struct {
    scale: la.Vector3f32,
    position: la.Vector3f32,
    rotation: la.Quaternionf32,
}


transform_init :: proc(self:^ Transform) {
    self.scale = 1 
    self.position = 0 
    
}

transform_get_matrix :: proc(self: ^Transform) -> (m: la.Matrix4f32,) {
    self.rotation = la.quaternion_normalize(self.rotation)
    //Do some check to see if the position/rotation has changed before recalculating. 
    // rotation := la.matrix4_from_quaternion(self.rotation)
    // scale := la.matrix4_scale(self.scale)
    // translate := la.matrix4_translate_f32(self.position)
    // m = la.matrix_mul(rotation, scale)
    // m = la.matrix_mul(translate, m)
    // return m
    return la.matrix4_from_trs(self.position, self.rotation, self.scale)

}

transform_add_position :: proc(self: ^Transform, pos: la.Vector3f32) {
    self.position += pos 
}

transform_set_position :: proc(self: ^Transform, pos: la.Vector3f32) {
    self.position = pos 
}

transform_set_rotation_degrees :: proc(self:^ Transform, rot: la.Vector3f32) {
    self.rotation = la.quaternion_from_euler_angles(math.to_radians(rot.x), math.to_radians(rot.y), math.to_radians(rot.z), AXIS_FORMAT)
}

transform_set_rotation_radians :: proc(self:^ Transform, rot: la.Vector3f32) {
    self.rotation = la.quaternion_from_euler_angles(rot.x, rot.y, rot.z, AXIS_FORMAT)
}

transform_add_rotation_degrees :: proc(self:^ Transform, rot: la.Vector3f32) {
    x,y,z := la.euler_angles_from_quaternion(self.rotation, AXIS_FORMAT)
    x += la.to_radians(rot.x)
    y += la.to_radians(rot.y)
    z += la.to_radians(rot.z)
    self.rotation = la.quaternion_from_euler_angles(x, y, z, AXIS_FORMAT)
}

transform_add_rotation_radians :: proc(self:^ Transform, rot: la.Vector3f32) {
    x,y,z := la.euler_angles_from_quaternion(self.rotation, AXIS_FORMAT)

    self.rotation = la.quaternion_from_euler_angles(rot.x + x, rot.y + y, rot.z + z, AXIS_FORMAT)
}

transform_set_scale :: proc(self:^ Transform, scale: la.Vector3f32) {

    self.scale = scale 
}

transform_add_scale :: proc(self:^ Transform, scale: la.Vector3f32) {

    self.scale += scale 
}

transform_add_relative_x :: proc(self:^ Transform, distance: f32) {
    self.position += transform_get_relative_x(self^) * distance
}

transform_add_relative_y :: proc(self:^ Transform, distance: f32) {
    self.position += transform_get_relative_y(self^) * distance
}

transform_add_relative_z :: proc(self:^ Transform, distance: f32) {
    self.position += transform_get_relative_z(self^) * distance
}

transform_get_relative_x :: proc(self:Transform) ->la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{1, 0, 0})
}

transform_get_relative_y :: proc(self:Transform) ->la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 1, 0})
}

transform_get_relative_z :: proc(self:Transform) ->la.Vector3f32 {
    return la.quaternion_mul_vector3(self.rotation, la.Vector3f32{0, 0, 1})
}

transform_get_pitch :: proc(self:Transform) -> f32 {
    return la.pitch_from_quaternion(self.rotation)
}

transform_get_yaw:: proc(self:Transform) -> f32 {

    return la.yaw_from_quaternion(self.rotation)
}

transform_get_roll :: proc(self:Transform) -> f32 {
    return la.roll_from_quaternion(self.rotation)
}

quaternion_get_euler_x :: proc(self:la.Quaternionf32) -> f32 {
    x, y, z := la.euler_angles_from_quaternion(self, AXIS_FORMAT)
    return x
}
quaternion_get_euler_y :: proc(self:la.Quaternionf32) -> f32 {
    x, y, z := la.euler_angles_from_quaternion(self, AXIS_FORMAT)
    return y 
}
quaternion_get_euler_z :: proc(self:la.Quaternionf32) -> f32 {
    x, y, z := la.euler_angles_from_quaternion(self, AXIS_FORMAT)
    return z
}
