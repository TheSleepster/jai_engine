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

mat4_make_scale :: (scale: Vector3) -> Matrix4
{
    result := Matrix4_Identity;
    result._11 = scale.x;
    result._22 = scale.y;
    result._33 = scale.z;

    return result;
}

mat4_scale :: (m: Matrix4, scale: Vector3) -> Matrix4
{
    return multiply(m, mat4_make_scale(scale));
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

