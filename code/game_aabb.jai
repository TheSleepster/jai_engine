Range_V2 :: struct
{
    min : Vector2;
    max : Vector2;
}

range_v2_create :: inline (min: Vector2, max: Vector2) -> Range_V2
{
    result: Range_V2 = ---;
    result.min = min;
    result.max = max;

    return result;
}

range_v2_shift :: inline (range: Range_V2, shift: Vector2) -> Range_V2
{
    new_range: Range_V2 = ---;
    
    new_range.min = range.min + shift;
    new_range.max = range.max + shift;

    return new_range;
}

range_v2_make_centered :: inline (position: Vector2, area: Vector2) -> Vector2
{
    center: Vector2 = ---;
    center.x = position.x + (area.x * 0.5);
    center.y = position.y + (area.y * 0.5);

    return center;
}

range_v2_get_area :: inline (range: Range_V2) -> Vector2
{
    area: Vector2 = ---;
    area = abs(range.min - range.max);

    return area;
}

range_v2_is_within :: inline (position: Vector2, range: Range_V2) -> bool
{
    return (position.x >= range.min.x) && (position.x <= range.max.x) &&
           (position.y >= range.min.y) && (position.y <= range.max.y);
}


