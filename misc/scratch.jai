

//split hallways based on intersections so they can be made into room later
new_hallway_counter := 0;
new_hallways        := push_array(arena, Generation_Hallway, xx (edges_inserted * 10));
for hallway_index: 0..segment_count - 1 
{
    // FOR VERTICAL AND HORIZONTAL:
    // - advance down the line segment until we hit a room.
    // - if we hit a room, save the line segment's old end point, and make the new endpoint the tile before the room
    // - then create a new segment that starts at the border of the room, and extends to the old end point of the original segment
    segment := *hallway_segments[hallway_index];
    if segment != null
    {
        initial_b_room_id := segment.room_b_id;
        horizontal        := segment.type == .HORIZONTAL;

        grid_start     := (iVector2).{cast(s32)floor(segment.start.x - most_left_x), cast(s32)floor(segment.start.y - lowest_y)};
        grid_end       := (iVector2).{cast(s32)floor(segment.end.x   - most_left_x), cast(s32)floor(segment.end.y   - lowest_y)};
        initial_end    := grid_end;
        last_split_pos := grid_start;

        advance := ifx horizontal then (iVector2).{1, 0} else (iVector2).{0, 1};
        length  := ifx horizontal then abs(grid_end.x - grid_start.x + 1) else abs(grid_end.y - grid_start.y + 1);
        for offset: 0..length - 1
        {
            grid_pos := (iVector2).{grid_start.x + (advance.x * offset), grid_start.y + (advance.y * offset)};
            if grid_pos.x > xx dungeon_grid_width - 1 || grid_pos.y > xx dungeon_grid_height - 1 ||
                grid_pos.x < 0                         || grid_pos.y < 0
            {
                break;
            }

            cell := *dungeon_grid[grid_pos.x][grid_pos.y];
            if cell.parent_room_id != U64_MAX
            {
                segment_new_end  := grid_pos - advance;
                segment.end       = .{segment_new_end.x + most_left_x, segment_new_end.y + lowest_y};
                segment.room_b_id = cell.parent_room_id;

                while grid_pos.x < xx dungeon_grid_width - 1 && grid_pos.y < xx dungeon_grid_height - 1
                {
                    cell = *dungeon_grid[grid_pos.x][grid_pos.y];
                    if cell.parent_room_id == U64_MAX || cell.parent_room_id != segment.room_b_id
                    {
                        break;
                    }

                    grid_pos += advance;
                    offset   += 1;
                }

                if grid_pos.x < xx dungeon_grid_width - 1 && grid_pos.y < xx dungeon_grid_height - 1
                {
                    new_hallway: Generation_Hallway;
                    new_hallway.id        = segment_count;
                    new_hallway.type      = segment.type;
                    new_hallway.start     = .{grid_pos.x + most_left_x, grid_pos.y + lowest_y};
                    new_hallway.end       = .{initial_end.x + most_left_x, initial_end.y + lowest_y};
                    new_hallway.room_a_id = cell.parent_room_id;
                    new_hallway.room_b_id = initial_b_room_id;
                    new_hallway.L_pair_id = ifx segment.L_pair_id != -1 then segment.L_pair_id else -1;

                    new_hallways[new_hallway_counter] = new_hallway;
                    new_hallway_counter += 1;

                    segment.start     = new_hallway.start;
                    segment.room_a_id = cell.parent_room_id;
                    last_split_pos    = grid_pos;
                }
            }
        }
        if last_split_pos != grid_end
        {
            segment.end = .{grid_end.x + most_left_x, grid_end.y + lowest_y};
            segment.room_b_id = initial_b_room_id;
        }
    }
}

new_segment_array := push_size(arena, size_of(Generation_Hallway) * (segment_count + new_hallway_counter + 1));
memcpy(cast(*u8)new_segment_array,
       hallway_segments.data,
       segment_count * size_of(Generation_Hallway));

memcpy(cast(*u8)new_segment_array + (segment_count * size_of(Generation_Hallway)),
       new_hallways.data,
       new_hallway_counter * size_of(Generation_Hallway));

hallway_segments.data  = new_segment_array;
hallway_segments.count = new_hallway_counter + segment_count;
