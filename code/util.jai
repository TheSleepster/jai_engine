compare_s32 :: (a : s32, b : s32) -> int
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

v2_approach :: (value : *Vector2, target: Vector2, rate: float32, delta_time: float32)
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

////////////////
// MATRIX STUFF
////////////////
mat4_identity :: (diagonal: float32) -> Matrix4
{
    matrix: Matrix4;
    matrix._11 = diagonal;
    matrix._22 = diagonal;
    matrix._33 = diagonal;
    matrix._44 = diagonal;

    return matrix;
}

mat4_scale :: (m: Matrix4, scale: Vector3) -> Matrix4
{
    return multiply(m, mat4_make_scale(scale));
}

mat4_make_scale :: (scale: Vector3) -> Matrix4
{
    result := mat4_identity(1.0);
    result._11 = scale.x;
    result._22 = scale.y;
    result._33 = scale.z;

    return result;
}

mat4_make_translation :: (translation: Vector3) -> Matrix4
{
    result := mat4_identity(1.0);
    result._41 = translation.x;
    result._42 = translation.y;
    result._43 = translation.z;

    return result;
}

mat4_translate :: (matrix: Matrix4, translation: Vector3) -> Matrix4
{
    return multiply(matrix, mat4_make_translation(translation));
}

print_matrix :: (m: Matrix4)
{
    for 0..3
    {
        print("VECTOR %: %\n", it, m.v[it]);
    }
}
