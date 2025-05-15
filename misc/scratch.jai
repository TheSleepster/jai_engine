            // Initialize the final grid
            dungeon_grid_width  = cast(u32)ceil(most_right_x - most_left_x);
            dungeon_grid_height = cast(u32)ceil(highest_y    - lowest_y);
            dungeon_grid := push_array(arena, []World_Gen_Grid_Square, dungeon_grid_width);
            for 0..dungeon_grid_width - 1
            {
                dungeon_grid[it] = push_array(arena, World_Gen_Grid_Square, dungeon_grid_height);
            }

            for x: 0..dungeon_grid_width - 1
            {
                for y: 0..dungeon_grid_height - 1
                {
                    square := *dungeon_grid[x][y];
                    square.occupied       = 0;
                    square.parent_room_id = U64_MAX;
                }
            }

            // place all rooms into the grid (main and non-main)
            for *room: generation_rooms
            {
                grid_x := cast(u32)floor(room.position.x - most_left_x);
                grid_y := cast(u32)floor(room.position.y - lowest_y);
                for delta_x: 0..cast(u32)room.size.x - 1
                {
                    for delta_y: 0..cast(u32)room.size.y - 1
                    {
                        new_x := grid_x + delta_x;
                        new_y := grid_y + delta_y;
                        assert(new_x < dungeon_grid_width);
                        assert(new_y < dungeon_grid_height);

                        square := *dungeon_grid[new_x][new_y];
                        square.occupied = 1;
                        square.parent_room_id = room.id;
                    }
                }
            }

            //   check hallways for room intersections
            for segment: hallway_segments
            {
                grid_start := (iVector2).{cast(s32)floor(segment.start.x - most_left_x), cast(s32)floor(segment.start.y - lowest_y)};
                grid_end   := (iVector2).{cast(s32)floor(segment.end.x   - most_left_x), cast(s32)floor(segment.end.y   - lowest_y)};
                
                is_horizontal := segment.type == .HORIZONTAL;
                fixed_value   := ifx is_horizontal then grid_start.y else grid_start.x;
                min_varying   := ifx is_horizontal then min(grid_start.x, grid_end.x) else min(grid_start.y, grid_end.y);
                max_varying   := ifx is_horizontal then max(grid_start.x, grid_end.x) else max(grid_start.y, grid_end.y);
                
                for i: 0..(max_varying - min_varying - 1)
                {
                    x := ifx is_horizontal then (min_varying + i) else fixed_value;
                    y := ifx is_horizontal then fixed_value else (min_varying + i);
                    cell := *dungeon_grid[x][y];
                    if cell.parent_room_id != U64_MAX
                    {
                        room := *generation_rooms[cell.parent_room_id];
                        if room.type != .MAIN
                        {
                            room.type = .LESSER;
                        }
                    }
                    // not yet
                    // cell.occupied = 1;
                    // cell.debug_hallway = true;

                }
            }

            // final pass to clear cells not belonging to main or lesser rooms
            for y: 0..dungeon_grid_height - 1
            {
                for x: 0..dungeon_grid_width - 1
                {
                    square := *dungeon_grid[x][y];
                    if square.parent_room_id != U64_MAX
                    {
                        room := *generation_rooms[square.parent_room_id];
                        if room.type != .MAIN && room.type != .LESSER
                        {
                            square.occupied = 0;
                            square.parent_room_id = U64_MAX;
                        }
                    }
                }
            }

            // copy main and lesser rooms to the final roomset
            new_room_count: u32;
            for room: generation_rooms
            {
                if room.type == .MAIN || room.type == .LESSER
                {
                    new_room_count += 1;
                }
            }

            rooms_copied: u32 = 1;
            final_room_set := push_array(arena, Generation_Room, new_room_count);
            for room: generation_rooms
            {
                if room.type == .MAIN || room.type == .LESSER
                {
                    memcpy(cast(*u8)final_room_set.data + (size_of(Generation_Room) * rooms_copied), *room, size_of(Generation_Room));
                    rooms_copied += 1;
                }
            }

            // override and have generation_rooms only contain the final set
            generation_rooms.data  = final_room_set.data;
            generation_rooms.count = final_room_set.count;

            new_hallways: [..]Generation_Hallway;
            defer free(new_hallways.data);

            // clip hallways to room boundaries, not go through them, create new hallways if needed
            to_remove: u32;
            new_hallway_count: u32;
            original_hallway_counter := hallway_segments.count;
            for hallway_index: 0..original_hallway_counter - 1
            {
                segment := *hallway_segments[hallway_index];
                if segment != null
                {
                    start_x := cast(s32)floor(segment.start.x - most_left_x);
                    start_y := cast(s32)floor(segment.start.y - lowest_y);

                    end_x   := cast(s32)floor(segment.end.x - most_left_x);
                    end_y   := cast(s32)floor(segment.end.y - lowest_y);

                    horizontal  := segment.start.y == segment.end.y;
                    length      := ifx horizontal then abs(end_x - start_x) else abs(end_y - start_y);

                    direction_x := end_x - start_x;
                    direction_y := end_y - start_y;
                    
                    dx := end_x - start_x;
                    dy := end_y - start_y;
                    advance_x := ifx (dx > 0) then 1 else ifx (dx < 0) then -1 else 0;
                    advance_y := ifx (dy > 0) then 1 else ifx (dy < 0) then -1 else 0;
                    advance: iVector2 = .{xx advance_x, xx advance_y};

                    current_x: s32 = start_x;
                    current_y: s32 = start_y;

                    // compute new start
                    for offset: 0..length - 1
                    {
                        grid_pos := (iVector2).{start_x + xx (advance.x * offset), start_y + xx (advance.y * offset)};
                        if grid_pos.x > xx dungeon_grid_width - 1 || grid_pos.y > xx dungeon_grid_height - 1 ||
                           grid_pos.x < 0                         || grid_pos.y < 0
                        {
                            break;
                        }

                        cell := *dungeon_grid[grid_pos.x][grid_pos.y];
                        if cell.parent_room_id == U64_MAX
                        {
                            break;
                        }

                        current_x += advance.x;
                        current_y += advance.y;
                    }

                    new_start: iVector2 = .{current_x, current_y};
                    segment.start       = .{(new_start.x + most_left_x), (new_start.y + lowest_y)};

                    // compute new end
                    current_x = end_x;
                    current_y = end_y;
                    negative_advance := (iVector2).{-advance.x, -advance.y};
                    for offset: 0..length - 1
                   { 
                        grid_pos := (iVector2).{end_x + xx (negative_advance.x * offset), end_y + xx (negative_advance.y * offset)};
                        if grid_pos.x > xx dungeon_grid_width - 1 || grid_pos.y > xx dungeon_grid_height - 1 ||
                           grid_pos.x < 0                         || grid_pos.y < 0
                        {
                            break;
                        }

                        cell := *dungeon_grid[grid_pos.x][grid_pos.y];
                        if cell.parent_room_id == U64_MAX
                        {
                            break;
                        }

                        current_x += negative_advance.x;
                        current_y += negative_advance.y;
                    }

                    new_end: iVector2 = .{current_x, current_y};
                    segment.end = .{(new_end.x + most_left_x), (new_end.y + lowest_y)};

                    // can a hallway fit?
                    is_valid: bool;
                    length = ifx horizontal then abs(end_x - start_x) else abs(end_y - start_y);
                    for offset: 0..length - 1
                    {
                        grid_pos := (iVector2).{start_x + xx (advance.x * offset), start_y + xx (advance.y * offset)};
                        if grid_pos.x > xx dungeon_grid_width - 1 || grid_pos.y > xx dungeon_grid_height - 1 ||
                           grid_pos.x < 0                         || grid_pos.y < 0
                        {
                            break;
                        }
                        
                        cell := *dungeon_grid[grid_pos.x][grid_pos.y];
                        if cell.parent_room_id == U64_MAX
                        {
                            is_valid = true;
                            break;
                        }
                    }
                    if !is_valid
                    {
                        segment.is_valid = false;
                        to_remove += 1;
                        continue;
                    }

                    // Properly split hallways into distinct room segments
                    if segment.is_valid
                    {
                        old_end: Vector2 = segment.end;
                        initial_grid_pos: iVector2 = .{cast(s32)floor(segment.start.x - most_left_x), cast(s32)floor(segment.start.y - lowest_y)};
                        segment_grid_end: iVector2 = .{cast(s32)floor(segment.end.x   - most_left_x), cast(s32)floor(segment.end.y   - lowest_y)};
                        current_grid_pos: iVector2 = initial_grid_pos;
                        next_grid_pos   : iVector2 = initial_grid_pos;
                        last_start      : Vector2  = segment.start;
                        last_end        : Vector2  = segment.end;

                        while current_grid_pos.x != segment_grid_end.x || current_grid_pos.y != segment_grid_end.y
                        {
                            is_inside_room : bool = false;
                            was_inside_room: bool = false;

                            next_grid_pos += advance;
                            if current_grid_pos.x > xx dungeon_grid_width - 1 || current_grid_pos.y > xx dungeon_grid_height - 1 ||
                               current_grid_pos.x < 0                         || current_grid_pos.y < 0
                            {
                                break;
                            }

                            intercepted_id: u64;
                            cell := *dungeon_grid[current_grid_pos.x][current_grid_pos.y];
                            if cell.parent_room_id != U64_MAX
                            {
                                new_grid_end  :=  current_grid_pos;
                                last_end       = .{(current_grid_pos.x - advance.x) + most_left_x, (current_grid_pos.y - advance.y) + lowest_y};
                                segment.end    =  last_end;
                                segment.debug_clipped = true;
                                //assert(segment.end != old_end);

                                intercepted_id = cell.parent_room_id;
                                
                                is_inside_room = true;
                                while is_inside_room
                                {
                                    next_grid_pos += advance;
                                    if next_grid_pos.x > xx dungeon_grid_width - 1 || next_grid_pos.y > xx dungeon_grid_height - 1 ||
                                       next_grid_pos.x < 0                         || next_grid_pos.y < 0
                                    {
                                        is_inside_room = false;
                                        break;
                                    }

                                    dungeon_cell := *dungeon_grid[next_grid_pos.x][next_grid_pos.y];
                                    if dungeon_cell.parent_room_id == U64_MAX
                                    {
                                        is_inside_room  = false;
                                        was_inside_room = true;
                                        break;
                                    }
                                }

                                if was_inside_room
                                {
                                    // create a new segment to make up for the fact that we clipped the old segment
                                    // replace the current working segment's end with the end we computed before
                                    new_cell  := *dungeon_grid[next_grid_pos.x][next_grid_pos.y];
                                    assert(new_cell.parent_room_id == U64_MAX);

                                    new_seg_start := (Vector2).{next_grid_pos.x + most_left_x, next_grid_pos.y + lowest_y};

                                    new_segment: Generation_Hallway;
                                    new_segment.id        = segment_count + new_hallway_count;
                                    new_segment.type      = ifx horizontal then .HORIZONTAL else .VERTICAL;
                                    new_segment.is_valid  = true;
                                    new_segment.room_a_id = intercepted_id;
                                    new_segment.room_b_id = segment.room_b_id;
                                    new_segment.L_pair_id = ifx segment.L_pair_id == -1 then -1 else segment.L_pair_id;
                                    new_segment.start     = new_seg_start;
                                    new_segment.end       = old_end;
                                    new_segment.debug_new_segment = true;

                                    array_add(*new_hallways, new_segment);
                                    new_hallway_count += 1;

                                    last_start = new_seg_start;
                                }
                            }

                            current_grid_pos = next_grid_pos;
                        }
                    }

                }
            }
            
            copied: u32 = 0;
            final_hallway_set := push_array(arena, Generation_Hallway, xx(hallway_segments.count + new_hallway_count));
            for *segment: hallway_segments
            {
                if segment && segment.is_valid == true
                {
                    memcpy(cast(*u8)final_hallway_set.data + (copied * size_of(Generation_Hallway)), segment, size_of(Generation_Hallway));
                    copied += 1;
                }
            }

            for *segment: new_hallways 
            {
                if segment && segment.is_valid == true
                {
                    memcpy(cast(*u8)final_hallway_set.data + (copied * size_of(Generation_Hallway)), segment, size_of(Generation_Hallway));
                    copied += 1;
                }
            }

            hallway_segments.data  = final_hallway_set.data;
            hallway_segments.count = final_hallway_set.count - to_remove;

            for segment: hallway_segments
            {
                grid_start := (iVector2).{cast(s32)floor(segment.start.x - most_left_x), cast(s32)floor(segment.start.y - lowest_y)};
                grid_end   := (iVector2).{cast(s32)floor(segment.end.x   - most_left_x), cast(s32)floor(segment.end.y   - lowest_y)};
                
                is_horizontal := segment.type == .HORIZONTAL;
                fixed_value   := ifx is_horizontal then grid_start.y else grid_start.x;
                min_varying   := ifx is_horizontal then min(grid_start.x, grid_end.x) else min(grid_start.y, grid_end.y);
                max_varying   := ifx is_horizontal then max(grid_start.x, grid_end.x) else max(grid_start.y, grid_end.y);
                
                for i: 0..(max_varying - min_varying - 1)
                {
                    x := ifx is_horizontal then (min_varying + i) else fixed_value;
                    y := ifx is_horizontal then fixed_value else (min_varying + i);
                    cell := *dungeon_grid[x][y];
                    if cell.parent_room_id == U64_MAX
                    {
                        cell.occupied = 1;
                        cell.debug_hallway = true;
                    }
                    else if cell.parent_room_id != U64_MAX
                    {
                        cell.occupied = 1;
                        cell.debug_hallway = true;
                    }
                    // not yet
                }
            }
