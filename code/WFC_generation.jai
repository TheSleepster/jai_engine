/*
TODO:
  - [x] Make a LIST of the tiles with the lowest entropy, instead of
        picking just the first one we see. Then select randomly from that
        list.

  - [ ] Instead of JUST collapsing the tile, we should check our
        neighbors and their possiblities first. Have the neighbors
        directly influence the collapsing tiles possibilities

  - [ ] Propogate collapses to all nearby tiles within a 3x3
        intersection of our tile.

  - [ ] Improve the way we supply rules and options
*/

WFC_Cell :: struct
{
    is_collapsed : bool;
    entropy      : u32;

    grid_x : u32;
    grid_y : u32;
    union
    {
        cell_value : u32;
        cell_mask  : u32;
    };
};

WFC_Init :: ()
{
    // BLACK BACKGROUND
    options[0]      = subsprite(sprite_WFC_input, .{32, 32}, .{-32, -32});
    rules[0][UP]    = BIT(0) | BIT(4) | BIT(2) | BIT(3);  
    rules[0][DOWN]  = BIT(0) | BIT(1) | BIT(2) | BIT(3); 
    rules[0][LEFT]  = BIT(0) | BIT(2) | BIT(4);
    rules[0][RIGHT] = BIT(0) | BIT(3) | BIT(4);

    // WALL TOP
    options[1]      = subsprite(sprite_WFC_input, .{16, 32}, .{-32, -32});
    rules[1][UP]    = BIT(0);  
    rules[1][DOWN]  = BIT(5); 
    rules[1][LEFT]  = BIT(1) | BIT(3);
    rules[1][RIGHT] = BIT(1) | BIT(2);

    // WALL RIGHT SIDE 
    options[2]      = subsprite(sprite_WFC_input, .{32, 16}, .{-32, -32});
    rules[2][UP]    = BIT(0) | BIT(2);  
    rules[2][DOWN]  = BIT(0) | BIT(2); 
    rules[2][LEFT]  = BIT(5) | BIT(1) | BIT(4);
    rules[2][RIGHT] = BIT(0);

    // WALL LEFT SIDE
    options[3]      = subsprite(sprite_WFC_input, .{ 0, 16}, .{-32, -32});
    rules[3][UP]    = BIT(0) | BIT(3);  
    rules[3][DOWN]  = BIT(0) | BIT(3); 
    rules[3][LEFT]  = BIT(0);
    rules[3][RIGHT] = BIT(5) | BIT(1) | BIT(4);

    // WALL BOTTOM SIDE
    options[4]      = subsprite(sprite_WFC_input, .{16,  0}, .{-32, -32});
    rules[4][UP]    = BIT(5);
    rules[4][DOWN]  = BIT(0) | BIT(1); 
    rules[4][LEFT]  = BIT(0) | BIT(3) | BIT(4);
    rules[4][RIGHT] = BIT(0) | BIT(2) | BIT(4);

    // FLOOR 
    options[5]      = subsprite(sprite_WFC_input, .{16, 16}, .{-32, -32});
    rules[5][UP]    = BIT(5) | BIT(1);
    rules[5][DOWN]  = BIT(5) | BIT(4); 
    rules[5][LEFT]  = BIT(5) | BIT(3);
    rules[5][RIGHT] = BIT(5) | BIT(2);

    for x: 0..N - 1
    {
        for y: 0..N - 1
        {
            cell := *grid[x][y];
            
            cell.is_collapsed  = false;
            cell.cell_value = 0;
            cell.cell_mask  = BIT(0) | BIT(1) | BIT(2) | BIT(3) | BIT(4) | BIT(5);
            cell.entropy    = 6;

            cell.grid_x = cast(u32)x;
            cell.grid_y = cast(u32)y;
        }
    }
}

WFC_propagate :: (primary_cell: *WFC_Cell,
                  neighbor_cell: *WFC_Cell,
                  neighbor_dir: Directions,
                  opposite_dir: Directions) -> bool
{
    result: bool;
    
    if !neighbor_cell.is_collapsed
    {
        // check if each module is supported in the neighbor cell's domain
        for module_index: 0..rule_count - 1
        {
            if (primary_cell.cell_mask & (1 << module_index))
            {
                supported: bool;
                for rule_index: 0..rule_count - 1
                {
                    if neighbor_cell.cell_mask & (1 << rule_index)
                    {
                        if rules[module_index][neighbor_dir] & (1 << rule_index)
                        {
                            supported = true;
                            break;
                        }
                    }
                }

                if !supported
                {
                    primary_cell.cell_mask &= ~(cast(u32)(1 << module_index));
                    result = true;
                }
            }
        }
    }
    else
    {
        module                 := neighbor_cell.cell_value;
        allowed_mask           := rules[module][opposite_dir];
        original_mask          := primary_cell.cell_mask;
        primary_cell.cell_mask &= allowed_mask;

        if primary_cell.cell_mask != original_mask
        {
            result = true;
        }
    }

    return result;
}

WFC_generate :: (draw_frame: *Draw_Frame_Data)
{
    while true
    {
        to_collapse: [N*N]*WFC_Cell;
        cell_count : u32;

        // builds list of tiles to collapse
        lowest_entropy := rule_count + 1;
        for x_index: 0..N - 1
        {
            for y_index: 0..N - 1
            {
                current_cell := *grid[x_index][y_index];
                if !current_cell.is_collapsed
                {
                    if current_cell.entropy < lowest_entropy
                    {
                        lowest_entropy = current_cell.entropy;
                        cell_count = 0;
                        for cell: to_collapse
                        {
                            if cell != null
                            {
                                cell = null;
                            }
                        }
                    }

                    if current_cell.entropy == lowest_entropy
                    {
                        to_collapse[cell_count] = current_cell;
                        cell_count += 1;
                    }
                }
            }
        }

        // all cells have been collapsed
        if lowest_entropy == rule_count + 1
        {
            log("[INFO]: WFC GENERATION COMPLETED...\n");
            break;
        }

        // picks cell from list
        random_seed(*context.random_state, rdtsc());
        index_to_pick := cast(u32)random_get_within_range(*context.random_state, 0, cast(float32)(cell_count - 1));

        // collapse the cell
        cell := to_collapse[index_to_pick];
        cell_modules: [rule_count]u32;
        cell_module_counter: u32 = 0;
        for bit_index: 0.. rule_count - 1
        {
            if cell.cell_mask & (1 << bit_index)
            {
                cell_modules[cell_module_counter] = cast(u32)bit_index;
                cell_module_counter += 1;
            }
        }

        collapsed_value := cast(u32)random_get_within_range(*context.random_state, 0, cast(float32)(cell_module_counter - 1));
        cell.is_collapsed = true;
        cell.cell_value   = cell_modules[collapsed_value];
        cell.entropy      = 1;

        // initial_pos := (Vector2).{-100, -120};
        // new_pos := (Vector2).{initial_pos.x + (cell.grid_x * 16), initial_pos.y + (cell.grid_y * 16)};
        // draw_texture(draw_frame, new_pos, .{16, 16}, *options[cell.cell_value], WHITE);

        // propagate the collapse
        propagated: bool = true;
        while propagated
        {
            propagated = false;

            // loop over every cell
            for x_index: 0..N - 1
            {
                for y_index: 0..N - 1
                {
                    cell := *grid[x_index][y_index];
                    if !cell.is_collapsed
                    {

                        //propagated = WFC_propagate(cell, east_neighbor, RIGHT, LEFT);
                        //check right
                        if x_index + 1 < N
                        {
                            east_neighbor := *grid[x_index + 1][y_index];
                            if !east_neighbor.is_collapsed
                            {
                                 // check if each module is supported in the neighbor cell's domain
                                for module_index: 0..rule_count - 1
                                {
                                    if (cell.cell_mask & (1 << module_index))
                                    {
                                        supported: bool;
                                        for rule_index: 0..rule_count - 1
                                        {
                                            if east_neighbor.cell_mask & (1 << rule_index)
                                            {
                                                if rules[module_index][RIGHT] & (1 << rule_index)
                                                {
                                                    supported = true;
                                                    break;
                                                }
                                            }
                                        }

                                        if !supported
                                        {
                                            cell.cell_mask &= ~(cast(u32)(1 << module_index));
                                            propagated = true;
                                        }
                                    }
                                }
                            }
                            else
                            {
                                module := east_neighbor.cell_value;
                                allowed_mask := rules[module][LEFT];
                                original_mask := cell.cell_mask;
                                cell.cell_mask &= allowed_mask;
                                if cell.cell_mask != original_mask
                                {
                                    propagated = true;
                                }
                            }
                        }

                        //check left
                        if x_index - 1 >= 0
                        {
                            west_neighbor := *grid[x_index - 1][y_index];
                            if !west_neighbor.is_collapsed
                            {
                                 // check if each module is supported in the neighbor cell's domain
                                for module_index: 0..rule_count - 1
                                {
                                    if (cell.cell_mask & (1 << module_index))
                                    {
                                        supported: bool;
                                        for rule_index: 0..rule_count - 1
                                        {
                                            if west_neighbor.cell_mask & (1 << rule_index)
                                            {
                                                if rules[module_index][LEFT] & (1 << rule_index)
                                                {
                                                    supported = true;
                                                    break;
                                                }
                                            }
                                        }

                                        if !supported
                                        {
                                            cell.cell_mask &= ~(cast(u32)(1 << module_index));
                                            propagated = true;
                                        }
                                    }
                                }
                            }
                            else
                            {
                                module := west_neighbor.cell_value;
                                allowed_mask := rules[module][RIGHT];
                                original_mask := cell.cell_mask;
                                cell.cell_mask &= allowed_mask;
                                if cell.cell_mask != original_mask
                                {
                                    propagated = true;
                                }
                            }
                        }

                        //check up
                        if y_index + 1 < N
                        {
                            north_neighbor := *grid[x_index][y_index + 1];
                            if !north_neighbor.is_collapsed
                            {
                                 // check if each module is supported in the neighbor cell's domain
                                for module_index: 0..rule_count - 1
                                {
                                    if (cell.cell_mask & (1 << module_index))
                                    {
                                        supported: bool;
                                        for rule_index: 0..rule_count - 1
                                        {
                                            if north_neighbor.cell_mask & (1 << rule_index)
                                            {
                                                if rules[module_index][UP] & (1 << rule_index)
                                                {
                                                    supported = true;
                                                    break;
                                                }
                                            }
                                        }

                                        if !supported
                                        {
                                            cell.cell_mask &= ~(cast(u32)(1 << module_index));
                                            propagated = true;
                                        }
                                    }
                                }
                            }
                            else
                            {
                                module := north_neighbor.cell_value;
                                allowed_mask := rules[module][DOWN];
                                original_mask := cell.cell_mask;
                                cell.cell_mask &= allowed_mask;
                                if cell.cell_mask != original_mask
                                {
                                    propagated = true;
                                }
                            }
                        }

                        //check down
                        if y_index - 1 >= 0
                        {
                            south_neighbor := *grid[x_index][y_index - 1];
                            if !south_neighbor.is_collapsed
                            {
                                 // check if each module is supported in the neighbor cell's domain
                                for module_index: 0..rule_count - 1
                                {
                                    if (cell.cell_mask & (1 << module_index)) != 0
                                    {
                                        supported: bool;
                                        for rule_index: 0..rule_count - 1
                                        {
                                            if south_neighbor.cell_mask & (1 << rule_index)
                                            {
                                                if rules[module_index][DOWN] & (1 << rule_index)
                                                {
                                                    supported = true;
                                                    break;
                                                }
                                            }
                                        }

                                        if !supported
                                        {
                                            cell.cell_mask &= ~(cast(u32)(1 << module_index));
                                            propagated = true;
                                        }
                                    }
                                }
                            }
                            else
                            {
                                module := south_neighbor.cell_value;
                                allowed_mask := rules[module][UP];
                                original_mask := cell.cell_mask;
                                cell.cell_mask &= allowed_mask;
                                if cell.cell_mask != original_mask
                                {
                                    propagated = true;
                                }
                            }
                        }
                        cell.entropy = cast(u32)(popcount(cell.cell_mask));
                        assert(cell.entropy != 0);
                    }
                    else
                    {
                        continue;
                    }
                }
            }
        }
    }
}

WFC_render :: (draw_frame: *Draw_Frame_Data)
{
    push_render_layer(draw_frame, 15);

    initial_pos := (Vector2).{-100, -120};

    for x: 0..N -1
    {
        for y: 0..N -1
        {
            cell := grid[x][y];

            new_pos := (Vector2).{initial_pos.x + (x * 16), initial_pos.y + (y * 16)};
            draw_texture(draw_frame, new_pos, .{16, 16}, *options[cell.cell_value], WHITE);
        }
    }

    // Palette rendering
    // draw_texture(draw_frame, .{-50,  32}, .{16, 16}, *options[0], WHITE);
    // draw_texture(draw_frame, .{-50,  16}, .{16, 16}, *options[1], WHITE);
    // draw_texture(draw_frame, .{-50,   0}, .{16, 16}, *options[2], WHITE);
    // draw_texture(draw_frame, .{-50, -16}, .{16, 16}, *options[3], WHITE);
    // draw_texture(draw_frame, .{-50, -32}, .{16, 16}, *options[4], WHITE);
    // draw_texture(draw_frame, .{-50, -48}, .{16, 16}, *options[5], WHITE);
    
}

#scope_file
using Directions :: enum u32
{
    UP;
    DOWN;
    LEFT;
    RIGHT;
};

N          :: 15;
rule_count :: 6;

grid    : [N][N]WFC_Cell;
options : [rule_count]Atlas_Sprite;
rules   : [rule_count][rule_count]u32;
