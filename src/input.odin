package astro

import la "core:math/linalg"
import "vendor:glfw"
import "core:c"

KEY_COUNT :: 512
MOUSE_BUTTON_COUNT :: 8

Input :: struct {
    window_handle: glfw.WindowHandle,

    mouse_moved: bool,
    mouse_pos: la.Vector2f32,
    mouse_prev_pos: la.Vector2f32,
    mouse_delta: la.Vector2f32,
    key_state: [KEY_COUNT]bool,
    key_state_repeating: [KEY_COUNT]bool,
    mouse_button_state: [MOUSE_BUTTON_COUNT]bool,
    mouse_button_state_repeating: [MOUSE_BUTTON_COUNT]bool,
}

input_init :: proc(self: ^Input, window_handle: glfw.WindowHandle) {
    self.window_handle = window_handle
    input_update(self)
}

input_update :: proc(self: ^Input) {
    self.mouse_prev_pos = self.mouse_pos
    x, y := glfw.GetCursorPos(self.window_handle)
    self.mouse_pos.x = f32(x)
    self.mouse_pos.y = f32(y)
    self.mouse_moved = self.mouse_pos != self.mouse_prev_pos

    if self.mouse_moved {
        self.mouse_delta.x = self.mouse_pos.x - self.mouse_prev_pos.x
        self.mouse_delta.y = self.mouse_pos.y - self.mouse_prev_pos.y
    } else {
        self.mouse_delta.x = 0.0
        self.mouse_delta.y = 0.0
    }
    for key in Key {
        k := int(key)
        self.key_state_repeating[k] = self.key_state[k]
        self.key_state[k] = glfw.GetKey(self.window_handle, i32(key)) == glfw.PRESS
        self.key_state_repeating[k] &= self.key_state[k]
    }
    for i in 0..< MOUSE_BUTTON_COUNT {
        self.mouse_button_state[i] = glfw.GetMouseButton(self.window_handle, i32(i)) == glfw.PRESS
    }
}

is_mouse_pressed :: proc(button: Mouse_Button) -> bool {
    return GLOBALS.input.mouse_button_state[int(button)]
}

//Allows repeated key presses
is_key_pressed :: proc(key: Key) -> bool {
    return GLOBALS.input.key_state[int(key)]
}
//Doesn't Allow repeated key presses
is_key_hit :: proc(key: Key) -> bool {

    pressed := GLOBALS.input.key_state[int(key)] 
    if pressed {
        return !GLOBALS.input.key_state_repeating[int(key)]
    }
    return false
}

is_key_not_pressed :: proc(key: Key) -> bool {
    return !GLOBALS.input.key_state[int(key)]
}

Input_State :: enum i32 {
    RELEASED = 0,
    PRESSED = 1,
    REPEATING = 2,
}

/* Joystick hat states. */
HAT_CENTERED   :: 0
HAT_UP         :: 1
HAT_RIGHT      :: 2
HAT_DOWN       :: 4
HAT_LEFT       :: 8
HAT_RIGHT_UP   :: (HAT_RIGHT | HAT_UP)
HAT_RIGHT_DOWN :: (HAT_RIGHT | HAT_DOWN)
HAT_LEFT_UP    :: (HAT_LEFT  | HAT_UP)
HAT_LEFT_DOWN  :: (HAT_LEFT  | HAT_DOWN)

/* The unknown key */

/* Joystick buttons */
JOYSTICK_1  :: 0
JOYSTICK_2  :: 1
JOYSTICK_3  :: 2
JOYSTICK_4  :: 3
JOYSTICK_5  :: 4
JOYSTICK_6  :: 5
JOYSTICK_7  :: 6
JOYSTICK_8  :: 7
JOYSTICK_9  :: 8
JOYSTICK_10 :: 9
JOYSTICK_11 :: 10
JOYSTICK_12 :: 11
JOYSTICK_13 :: 12
JOYSTICK_14 :: 13
JOYSTICK_15 :: 14
JOYSTICK_16 :: 15

JOYSTICK_LAST :: JOYSTICK_16

/* Gamepad buttons */
GAMEPAD_BUTTON_A            :: 0
GAMEPAD_BUTTON_B            :: 1
GAMEPAD_BUTTON_X            :: 2
GAMEPAD_BUTTON_Y            :: 3
GAMEPAD_BUTTON_LEFT_BUMPER  :: 4
GAMEPAD_BUTTON_RIGHT_BUMPER :: 5
GAMEPAD_BUTTON_BACK         :: 6
GAMEPAD_BUTTON_START        :: 7
GAMEPAD_BUTTON_GUIDE        :: 8
GAMEPAD_BUTTON_LEFT_THUMB   :: 9
GAMEPAD_BUTTON_RIGHT_THUMB  :: 10
GAMEPAD_BUTTON_DPAD_UP      :: 11
GAMEPAD_BUTTON_DPAD_RIGHT   :: 12
GAMEPAD_BUTTON_DPAD_DOWN    :: 13
GAMEPAD_BUTTON_DPAD_LEFT    :: 14
GAMEPAD_BUTTON_LAST         :: GAMEPAD_BUTTON_DPAD_LEFT

GAMEPAD_BUTTON_CROSS    :: GAMEPAD_BUTTON_A
GAMEPAD_BUTTON_CIRCLE   :: GAMEPAD_BUTTON_B
GAMEPAD_BUTTON_SQUARE   :: GAMEPAD_BUTTON_X
GAMEPAD_BUTTON_TRIANGLE :: GAMEPAD_BUTTON_Y

/* Gamepad axes */
GAMEPAD_AXIS_LEFT_X        :: 0
GAMEPAD_AXIS_LEFT_Y        :: 1
GAMEPAD_AXIS_RIGHT_X       :: 2
GAMEPAD_AXIS_RIGHT_Y       :: 3
GAMEPAD_AXIS_LEFT_TRIGGER  :: 4
GAMEPAD_AXIS_RIGHT_TRIGGER :: 5
GAMEPAD_AXIS_LAST          :: GAMEPAD_AXIS_RIGHT_TRIGGER

/* Bitmask for modifier keys */
MOD_SHIFT     :: 0x0001
MOD_CONTROL   :: 0x0002
MOD_ALT       :: 0x0004
MOD_SUPER     :: 0x0008
MOD_CAPS_LOCK :: 0x0010
MOD_NUM_LOCK  :: 0x0020

Mouse_Button :: enum i32 {
/* Mouse buttons */
B1 = 0,
B2 = 1,
B3 = 2,
B4 = 3,
B5 = 4,
B6 = 5,
B7 = 6,
B8 = 7,

/* Mousebutton aliases */
LAST   = B8,
LEFT   = B1,
RIGHT  = B2,
MIDDLE = B3,

}

Key :: enum i32 {

SPACE         = 32,
APOSTROPHE    = 39,  /* ' */
COMMA         = 44,  /* , */
MINUS         = 45,  /* - */
PERIOD        = 46,  /* . */
SLASH         = 47,  /* / */
SEMICOLON     = 59,  /* ; */
EQUAL         = 61,  /* :: */
LEFT_BRACKET  = 91,  /* [ */
BACKSLASH     = 92,  /* \ */
RIGHT_BRACKET = 93,  /* ] */
GRAVE_ACCENT  = 96,  /* ` */
WORLD_1       = 161, /* non-US #1 */
WORLD_2       = 162, /* non-US #2 */

N0 = 48,
N1 = 49,
N2 = 50,
N3 = 51,
N4 = 52,
N5 = 53,
N6 = 54,
N7 = 55,
N8 = 56,
N9 = 57,

A = 65,
B = 66,
C = 67,
D = 68,
E = 69,
F = 70,
G = 71,
H = 72,
I = 73,
J = 74,
K = 75,
L = 76,
M = 77,
N = 78,
O = 79,
P = 80,
Q = 81,
R = 82,
S = 83,
T = 84,
U = 85,
V = 86,
W = 87,
X = 88,
Y = 89,
Z = 90,

ESCAPE       = 256,
ENTER        = 257,
TAB          = 258,
BACKSPACE    = 259,
INSERT       = 260,
DELETE       = 261,
RIGHT        = 262,
LEFT         = 263,
DOWN         = 264,
UP           = 265,
PAGE_UP      = 266,
PAGE_DOWN    = 267,
HOME         = 268,
END          = 269,
CAPS_LOCK    = 280,
SCROLL_LOCK  = 281,
NUM_LOCK     = 282,
PRINT_SCREEN = 283,
PAUSE        = 284,

F1  = 290,
F2  = 291,
F3  = 292,
F4  = 293,
F5  = 294,
F6  = 295,
F7  = 296,
F8  = 297,
F9  = 298,
F10 = 299,
F11 = 300,
F12 = 301,
F13 = 302,
F14 = 303,
F15 = 304,
F16 = 305,
F17 = 306,
F18 = 307,
F19 = 308,
F20 = 309,
F21 = 310,
F22 = 311,
F23 = 312,
F24 = 313,
F25 = 314,

/* Keypad numbers */
KP_0 = 320,
KP_1 = 321,
KP_2 = 322,
KP_3 = 323,
KP_4 = 324,
KP_5 = 325,
KP_6 = 326,
KP_7 = 327,
KP_8 = 328,
KP_9 = 329,

/* Keypad named function keys */
KP_DECIMAL  = 330,
KP_DIVIDE   = 331,
KP_MULTIPLY = 332,
KP_SUBTRACT = 333,
KP_ADD      = 334,
KP_ENTER    = 335,
KP_EQUAL    = 336,

/* Modifier keys */
LEFT_SHIFT    = 340,
LEFT_CONTROL  = 341,
LEFT_ALT      = 342,
LEFT_SUPER    = 343,
RIGHT_SHIFT   = 344,
RIGHT_CONTROL = 345,
RIGHT_ALT     = 346,
RIGHT_SUPER   = 347,
MENU          = 348,

LAST = MENU,
}
