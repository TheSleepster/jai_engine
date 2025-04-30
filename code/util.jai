offset_of :: ($T: Type, ident: Code) -> s64 #expand
{
    t: T = ---;
    return cast(*void) (*t.#insert ident) - cast(*void) *t;
}

// NOTE(Sleepster): Helpers
/////////////////////////////////////////
KB :: (value: u64) -> u64 #expand
{
    return value * 1000;
}

MB :: (value: u64) -> u64 #expand
{
    return KB(value) * 1000;
}

GB :: (value: u64) -> u64 #expand
{
    return MB(value) * 1000;
}
/////////////////////////////////////////

BIT :: inline (index: u32) -> u32 #expand
{
    return cast(u32)(1 << index);
}

compare_s32 :: (a: s32, b: s32) -> int
{
    return ifx a > b then -1 else 1; 
}

is_equals :: (a: float32, b: float32, threshhold: float32) -> bool
{
    return abs(a - b) <= threshhold;
}

f32_approach :: (value: *float32, target: float32, rate: float32, delta_time: float32)
{
    <<value += cast(float32)((target - <<value) * (1.0 - pow(2.0, -rate * delta_time)));
    if is_equals(<<value, target, 0.001)
    {
        <<value = target;
    }
}

v2_approach :: (value: *Vector2, target: Vector2, rate: float32, delta_time: float32)
{
    f32_approach(*value.x, target.x, rate, delta_time);
    f32_approach(*value.y, target.y, rate, delta_time);
}

find_character_from_left :: (s: string, c: int) -> string, bool
{
    cursor := 0;
    while cursor < s.count
    {
        if s[cursor] == c return slice(s, 0, cursor), true;
    }

    return "", false; 
}

is_equal :: (A: float32, B: float32, epsilon: float32) -> bool
{
    return abs(A - B) <= epsilon;
}

approach_target :: (value: *float32, target_value: float32, rate: float32, delta: float32)
{
    <<value += cast(float32)(target_value - <<value) * (1.0 - pow(2.0, -rate * delta));
    if is_equal(<<value, target_value, 0.001)
    {
        <<value = target_value;
    }
}

approach_target_v2 :: (value: *Vector2, target_value: Vector2, rate: Vector2, delta: float32)
{
    approach_target(*value.x, target_value.x, rate.x, delta);
    approach_target(*value.y, target_value.y, rate.y, delta);
}

hex_to_rgba :: (hex: u32) -> Vector4
{
    color: Vector4;
    color.x = ((hex >> 24) & 0xFF) / 255.0;
    color.y = ((hex >> 16) & 0xFF) / 255.0;
    color.z = ((hex >> 8)  & 0xFF) / 255.0;
    color.w = ( hex        & 0xFF) / 255.0;

    return color;
}

v2_floor :: inline (A: Vector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = floor(A.x);
    result.y = floor(A.y);

    return result;
}

v2_expand :: inline (A: Vector2, B: float32) -> Vector3
{
    result: Vector3;
    result.x = A.x;
    result.y = A.y;
    result.z = B;

    return result;
}

v2_expand :: inline (A: Vector2, B: float32, C: float32) -> Vector4
{
    result: Vector4;
    result.x = A.x;
    result.y = A.y;
    result.z = B;
    result.w = C;

    return result;
}

////////////////////
// VECTOR OPERATORS
////////////////////
operator + :: (A: Vector2, B: iVector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = A.x + cast(float32)B.x;
    result.y = A.y + cast(float32)B.y;

    return result;
}

operator + :: (A: iVector2, B: Vector2) -> iVector2
{
    result: iVector2 = ---;
    result.x = A.x + cast(s32)B.x;
    result.y = A.y + cast(s32)B.y;

    return result;
}

v2_cast :: inline (vector: iVector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = xx vector.x;
    result.y = xx vector.y;

    return result;
}

iv2_cast :: inline (vector: Vector2) -> iVector2
{
    result: iVector2 = ---;
    result.x = xx vector.x;
    result.y = xx vector.y;

    return result;
}

////////////////
// MATRIX STUFF
////////////////
mat4_identity :: () -> Matrix4
{
    return Matrix4_Identity;
}

mat4_scale :: (m: Matrix4, scale: Vector3) -> Matrix4
{
    return multiply(m, mat4_make_scale(scale));
}

mat4_make_scale :: (scale: Vector3) -> Matrix4
{
    result := mat4_identity();
    result._11 = scale.x;
    result._22 = scale.y;
    result._33 = scale.z;
    result._44 = 1.0;

    return result;
}

mat4_make_translation :: (translation: Vector3) -> Matrix4
{
    result := mat4_identity();
    result._41 = translation.x;
    result._42 = translation.y;
    result._43 = translation.z;
    result._44 = 1.0;

    return result;
}

mat4_translate :: (matrix: Matrix4, translation: Vector3) -> Matrix4
{
    return multiply(matrix, mat4_make_translation(translation));
}

mat4_rotate :: (rotation: float32, axis: Vector3) -> Matrix4
{
    result: Matrix4 = mat4_identity();
    axis_norm := normalize(axis);
    
    sin_theta := sin(rotation);
    cos_theta := cos(rotation);
    cos_value := 1.0 - cos_theta;

    result._11 = (axis.x * axis.x * cos_value) + cos_theta;
    result._21 = (axis.x * axis.y * cos_value) + (axis.z * sin_theta);
    result._31 = (axis.x * axis.z * cos_value) - (axis.y * sin_theta);
    
    result._12 = (axis.y * axis.x * cos_value) - (axis.z * sin_theta);
    result._22 = (axis.y * axis.y * cos_value) + cos_theta;
    result._32 = (axis.y * axis.z * cos_value) + (axis.x * sin_theta);
    
    result._13 = (axis.z * axis.x * cos_value) + (axis.y * sin_theta);
    result._23 = (axis.z * axis.y * cos_value) - (axis.x * sin_theta);
    result._33 = (axis.z * axis.z * cos_value) + cos_theta;

    return result;
}

print_matrix :: (m: Matrix4)
{
    for 0..3
    {
        print("VECTOR %: %\n", it, m.v[it]);
    }
}

mat4_transform :: (matrix: Matrix4, vector: Vector4) -> Vector4
{
    result: Vector4 = ---;

    result.x  = vector.x * matrix._11;
    result.y  = vector.x * matrix._12;
    result.z  = vector.x * matrix._13;
    result.w  = vector.x * matrix._14;

    result.x += vector.y * matrix._21;
    result.y += vector.y * matrix._22;
    result.z += vector.y * matrix._23;
    result.w += vector.y * matrix._24;

    result.x += vector.z * matrix._31;
    result.y += vector.z * matrix._32;
    result.z += vector.z * matrix._33;
    result.w += vector.z * matrix._34;

    result.x += vector.w * matrix._41;
    result.y += vector.w * matrix._42;
    result.z += vector.w * matrix._43;
    result.w += vector.w * matrix._44;

    return result;
}

sin_breathe_normalized :: (time: float32, modifier: float32, min: float32, max: float32) -> float32
{
    sin_value := (sin(modifier * 2 * PI * time) + 1.0) / 2.0;
    return(min + (max - min) * sin_value);
}

sin_breathe :: (time: float32, modifier: float32) -> float32
{
    return(sin((time * PI) / modifier));
}

///////////////////////////////
// NORMAL RANDOM DISTRIBUTION
///////////////////////////////

get_random_normal :: () -> float64
{
    if has_cached
    {
        has_cached = false;
        return cached_value;
    }
    
    u1 := random_get_zero_to_one_new();
    u2 := random_get_zero_to_one_new();

    if u1 <= 0 then u1 = random_get_zero_to_one_new();

    radius := sqrt(-2.0 * log(u1));
    angle  := (2 * PI) * u2;

    z1 := radius * cos(angle);
    z2 := radius * sin(angle);

    has_cached   = true;
    cached_value = z2;

    return z1;
}

// 0.5, / 4.0

get_random_normal_range :: (min: float32, max: float32) -> float32
{
    mean := min + 0.5 * (min + max); 
    sigma := (max - min) / 4.0;
    
    z := get_random_normal();  
    x := mean + sigma * z;     
    
    if x < min then x = min;
    if x > max then x = max;
    
    return cast(float32)x;
}

get_random_v2_normal_in_range :: (min: Vector2, max: Vector2) -> Vector2
{
    width        := get_random_normal_range(min.x, max.x);
    aspect_ratio := random_get_within_range(0.5, 2.0);
    height       := width * aspect_ratio;

    if height < min.y then height = min.y;
    if height > max.y then height = max.y;

    return .{width, height};
}

#scope_file
has_cached: bool;
cached_value: float64;

RANDRANGE : u32 : 1 << 24;  // Not using all the bits for stuff like float divides, because we start losing accuracy due to the max representable integer. Maybe could be smarter than this. Must be a power of two for MASK to work. The highest exactly-representable integer in float32 is 2**24.
MASK :: RANDRANGE - 1;
