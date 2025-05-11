
old_end: Vector2 = segment.end;
initial_pos     := (iVector2).{xx(segment.start.x - most_left_x), xx(segment.start.y - lowest_y)};
current_pos     := (iVector2).{initial_pos.x, initial_pos.y};

segment_start := new_start;
last_segment: Generation_Hallway = segment.*;
while segment.start != segment.end
{
    grid_pos      := current_pos;
    next_grid_pos := current_pos + advance;
    horizontal    := segment.start.y == segment.end.y;
    if grid_pos.x > xx dungeon_grid_width - 1 || grid_pos.y > xx dungeon_grid_height - 1 ||
        grid_pos.x < 0                         || grid_pos.y < 0
    {
        break;
    }

    collision: bool;
    cell := *dungeon_grid[grid_pos.x][grid_pos.y];
    if cell.parent_room_id != U64_MAX
    {
        last_segment.end = .{current_pos.x + most_left_x, current_pos.y + lowest_y};

        new_hallway: Generation_Hallway;
        new_hallway.id        = segment_count;
        new_hallway.type      = ifx horizontal then .HORIZONTAL else .VERTICAL; 
        new_hallway.is_valid  = true;
        new_hallway.start     = .{segment.start.x, segment.start.y};
        new_hallway.end       = .{current_pos.x + most_left_x, current_pos.y + lowest_y};
        new_hallway.room_a_id = segment.room_a_id;
        new_hallway.room_b_id = cell.parent_room_id;
        new_hallway.L_pair_id = -1;

        array_add(*new_hallways, new_hallway);
        new_hallway_count += 1;
        last_segment = new_hallway;

        collision = true;
        while collision
        {
            next_grid_pos += advance;
            if next_grid_pos.x > xx dungeon_grid_width - 1 || next_grid_pos.y > xx dungeon_grid_height - 1 ||
                next_grid_pos.x < 0                         || next_grid_pos.y < 0
            {
                collision = false;
                break;
            }

            cell := *dungeon_grid[next_grid_pos.x][next_grid_pos.y];
            if cell.parent_room_id == U64_MAX then collision = false;
        }
        segment.start = (Vector2).{next_grid_pos.x + most_left_x, next_grid_pos.y + lowest_y};
    }
    current_pos = next_grid_pos;
}

// Add final segment
if segment_start.x != new_end.x || segment_start.y != new_end.y
{
    new_segment: Generation_Hallway;
    new_segment.start = .{(segment_start.x + most_left_x), (segment_start.y + lowest_y)};
    new_segment.end   = .{(new_end.x + most_left_x), (new_end.y + lowest_y)};
    new_segment.is_valid = true;

    array_add(*new_hallways, new_segment);
    new_hallway_count += 1;
}








// Properly split hallways into distinct room-like segments
old_end: Vector2 = segment.end;
initial_grid_pos: iVector2 = .{xx(segment.start.x - most_left_x), xx(segment.start.y - lowest_y)};
current_grid_pos: iVector2 = initial_grid_pos;
segment_grid_end: iVector2 = .{xx(segment.end.x - most_left_x), xx(segment.end.y - lowest_y)};

last_start: Vector2 = segment.start;
is_inside_room: bool = false;
segment_count += 1; 

while current_grid_pos.x != segment_grid_end.x || current_grid_pos.y != segment_grid_end.y
{
    next_grid_pos: iVector2 = current_grid_pos + advance;

    if next_grid_pos.x >= xx(dungeon_grid_width) || next_grid_pos.y >= xx(dungeon_grid_height) ||
        next_grid_pos.x < 0 || next_grid_pos.y < 0
    {
        break;
    }

    cell := *dungeon_grid[next_grid_pos.x][next_grid_pos.y];

    if !is_inside_room && cell.parent_room_id != U64_MAX
    {
        if last_start.x != current_grid_pos.x + most_left_x || last_start.y != current_grid_pos.y + lowest_y
        {
            new_hallway: Generation_Hallway;
            new_hallway.id        = segment_count;
            new_hallway.type      = ifx (segment.start.y == segment.end.y) then .HORIZONTAL else .VERTICAL;
            new_hallway.is_valid  = true;
            new_hallway.start     = last_start;
            new_hallway.end       = .{current_grid_pos.x + most_left_x, current_grid_pos.y + lowest_y};
            new_hallway.room_a_id = segment.room_a_id;
            new_hallway.room_b_id = cell.parent_room_id;

            // TODO(Sleepster): L Pair ids need to remain intact
            new_hallway.L_pair_id = -1;

            array_add(*new_hallways, new_hallway);
            new_hallway_count += 1;
        }
        is_inside_room = true;
    }
    else if is_inside_room && cell.parent_room_id == U64_MAX
    {
        last_start = .{next_grid_pos.x + most_left_x, next_grid_pos.y + lowest_y};
        is_inside_room = false;
    }

    current_grid_pos = next_grid_pos;
}

if !is_inside_room && (last_start.x != segment.end.x || last_start.y != segment.end.y)
{
    new_hallway: Generation_Hallway;
    new_hallway.id        = segment_count;
    new_hallway.type      = ifx (segment.start.y == segment.end.y) then .HORIZONTAL else .VERTICAL;
    new_hallway.is_valid  = true;
    new_hallway.start     = last_start;
    new_hallway.end       = segment.end;
    new_hallway.room_a_id = segment.room_a_id;
    new_hallway.room_b_id = segment.room_b_id;

    // TODO(Sleepster): L Pair ids need to remain intact
    new_hallway.L_pair_id = -1;

    array_add(*new_hallways, new_hallway);
    new_hallway_count += 1;
}
