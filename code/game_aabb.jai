AABB :: struct
{
    min : Vector2;
    max : Vector2;
}

AABB_create :: inline (min: Vector2, max: Vector2) -> AABB
{
    result: AABB = ---;
    result.min = min;
    result.max = max;

    return result;
}

AABB_shift :: inline (range: AABB, shift: Vector2) -> AABB
{
    new_range: AABB = ---;
    
    new_range.min = range.min + shift;
    new_range.max = range.max + shift;

    return new_range;
}

AABB_make_centered :: inline (position: Vector2, area: Vector2) -> Vector2
{
    center: Vector2 = ---;
    center.x = position.x + (area.x * 0.5);
    center.y = position.y + (area.y * 0.5);

    return center;
}

AABB_get_area :: inline (range: AABB) -> Vector2
{
    area: Vector2 = ---;
    area = abs(range.min - range.max);

    return area;
}

AABB_is_within :: inline (position: Vector2, range: AABB) -> bool
{
    return (position.x >= range.min.x) && (position.x <= range.max.x) &&
           (position.y >= range.min.y) && (position.y <= range.max.y);
}
