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

// static inline vec4 mat4Transform(mat4 Matrix, vec4 Vector)
// {
//     return mat4MakeTransform(Vector, Matrix);
// }

// static inline vec4 mat4MakeTransform(vec4 Left, mat4 Right)
// {
    
//     vec4 Result;
//
//     Result.X = Left.Elements[0] * Right.Columns[0].X;
//     Result.Y = Left.Elements[0] * Right.Columns[0].Y;
//     Result.Z = Left.Elements[0] * Right.Columns[0].Z;
//     Result.W = Left.Elements[0] * Right.Columns[0].W;
    
//     Result.X += Left.Elements[1] * Right.Columns[1].X;
//     Result.Y += Left.Elements[1] * Right.Columns[1].Y;
//     Result.Z += Left.Elements[1] * Right.Columns[1].Z;
//     Result.W += Left.Elements[1] * Right.Columns[1].W;
    
//     Result.X += Left.Elements[2] * Right.Columns[2].X;
//     Result.Y += Left.Elements[2] * Right.Columns[2].Y;
//     Result.Z += Left.Elements[2] * Right.Columns[2].Z;
//     Result.W += Left.Elements[2] * Right.Columns[2].W;
    
//     Result.X += Left.Elements[3] * Right.Columns[3].X;
//     Result.Y += Left.Elements[3] * Right.Columns[3].Y;
//     Result.Z += Left.Elements[3] * Right.Columns[3].Z;
//     Result.W += Left.Elements[3] * Right.Columns[3].W;
// #endif
    
//     return Result;
// }

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
