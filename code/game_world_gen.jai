/*
TODO:
  - [x] Make a LIST of the tiles with the lowest entropy, instead of
        picking just the first one we see. Then select randomly from that
        list.

  - [x] Propogate collapses to all nearby tiles within a 3x3
        intersection of our tile.

  - [ ] Improve the way we supply rules and options

  - [ ] Path contraints?
*/

using Directions :: enum u8
{
    NORTH;
    SOUTH;
    WEST;
    EAST;
    COUNT;
};

WFC_Cell :: struct
{
    is_collapsed : bool;
    entropy      : u32;
    union
    {
        cell_value : u32;
        cell_mask  : u32;
    };
};

WFC_Module :: struct
{
    sprite      : Atlas_Sprite;
    constraints : [Directions.COUNT]u32;
    weight      : float32;

    // NOTE(Sleepster): This is used for access on module generation.
    hash_value  : s64 = -1;
};

WFC_Gen_Chunk :: struct
{
    chunk_size    : iVector2;
    chunk_modules : []WFC_Module;
    chunk_grid    : [][]WFC_Cell;
};

// TODO(Sleepster): This might be painfully slow 
WFC_new_chunk :: (arena: *Memory_Arena, chunk_size: iVector2, modules: []WFC_Module) -> WFC_Gen_Chunk
{
    new_chunk: WFC_Gen_Chunk;
    new_chunk.chunk_size    = chunk_size;
    new_chunk.chunk_modules = modules;

    new_chunk.chunk_grid = push_array(arena, []WFC_Cell, xx chunk_size.x);
    for x: 0..chunk_size.x - 1
    {
        new_chunk.chunk_grid[x] = push_array(arena, WFC_Cell, xx chunk_size.y);
    }

    for x: 0..chunk_size.x - 1
    {
        for y: 0..chunk_size.y - 1
        {
            cell := *new_chunk.chunk_grid[x][y];
            
            cell.is_collapsed = false;
            cell.cell_value   = 0;
            cell.entropy      = xx modules.count;

            for module_index: 0..modules.count - 1
            {
                cell.cell_mask  |= BIT(xx module_index);
            }
        }
    }

    return new_chunk;
}

WFC_propagate :: (chunk_data    : *WFC_Gen_Chunk,
                  primary_cell  : *WFC_Cell,
                  neighbor_cell : *WFC_Cell,
                  neighbor_dir  : Directions,
                  opposite_dir  : Directions) -> bool
{
    using chunk_data;
    result: bool;
    
    if !neighbor_cell.is_collapsed
    {
        // check if each module is supported in the neighbor cell's domain
        for module_index: 0..chunk_modules.count - 1
        {
            if (primary_cell.cell_mask & (1 << module_index))
            {
                supported: bool;
                for rule_index: 0..chunk_modules.count - 1
                {
                    if neighbor_cell.cell_mask & (1 << rule_index)
                    {
                        if chunk_modules[module_index].constraints[neighbor_dir] & (1 << rule_index)
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
        allowed_mask           := chunk_modules[module].constraints[opposite_dir];
        original_mask          := primary_cell.cell_mask;
        primary_cell.cell_mask &= allowed_mask;

        if primary_cell.cell_mask != original_mask
        {
            result = true;
        }
    }

    return result;
}

WFC_generate :: (arena: *Memory_Arena, gen_chunk: *WFC_Gen_Chunk)
{
    using gen_chunk;
    fail_chunk: WFC_Gen_Chunk;
    fail_chunk = gen_chunk.*;
    
    scratch_arena := begin_temporary_block(arena);
    while true
    {
        to_collapse: []*WFC_Cell;
        to_collapse.count = (chunk_size.x * chunk_size.y);
        to_collapse.data  = push_size(arena, size_of(*WFC_Cell) * (chunk_size.x * chunk_size.y));
        cell_count : u32;

        // builds list of tiles to collapse
        lowest_entropy := chunk_modules.count + 1;
        for x_index: 0..chunk_size.x - 1
        {
            for y_index: 0..chunk_size.y - 1
            {
                current_cell := *chunk_grid[x_index][y_index];
                if !current_cell.is_collapsed
                {
                    if current_cell.entropy < lowest_entropy
                    {
                        lowest_entropy = current_cell.entropy;
                        cell_count = 0;
                        for index: 0..to_collapse.count - 1
                        {
                            cell := *to_collapse[index];
                            if cell.* != null
                            {
                                cell.* = null;
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
        if lowest_entropy == chunk_modules.count + 1
        {
            log("[INFO]: WFC GENERATION COMPLETED...\n");
            break;
        }

        // picks cell from list
        random_seed(*context.random_state, rdtsc());
        index_to_pick := cast(u32)random_get_within_range(*context.random_state, 0, cast(float32)(cell_count - 1));

        // collapse the cell
        cell := to_collapse[index_to_pick];
        cell_modules: []u32;

        cell_modules.data  = push_size(arena, xx (size_of(u32) * chunk_modules.count));
        cell_modules.count = chunk_modules.count;

        cell_module_counter: u32 = 0;
        for bit_index: 0..chunk_modules.count - 1
        {
            if cell.cell_mask & (1 << bit_index)
            {
                cell_modules[cell_module_counter] = cast(u32)bit_index;
                cell_module_counter += 1;
            }
        }

        total_weight: float32;
        if cell_module_counter != 0
        {
            for index: 0..cell_module_counter - 1
            {
                total_weight += chunk_modules[cell_modules[index]].weight;
            }
        }
        else
        {
            total_weight += chunk_modules[cell_modules[0]].weight;
        }

        collapsed_value   := random_get_within_range(*context.random_state, 0.0, total_weight);
        cumulative_weight : float32;
        selected_module   : u32;
        for index: 0..cell_module_counter - 1
        {
            cumulative_weight += chunk_modules[cell_modules[index]].weight;
            if collapsed_value <= cumulative_weight 
            {
                selected_module = cell_modules[index];
                break;
            }
        }
        
        cell.is_collapsed = true;
        cell.cell_value   = selected_module;
        cell.entropy      = 1;

        // propagate the collapse
        propagated: bool = true;
        while propagated
        {
            propagated = false;

            // loop over every cell
            for x_index: 0..chunk_size.x- 1
            {
                for y_index: 0..chunk_size.y - 1
                {
                    cell := *chunk_grid[x_index][y_index];
                    if !cell.is_collapsed
                    {
                        //check east
                        if x_index + 1 < chunk_size.x
                        {
                            east_neighbor := *chunk_grid[x_index + 1][y_index];
                            propagated = WFC_propagate(gen_chunk, cell, east_neighbor, EAST, WEST);
                        }

                        //check west
                        if x_index - 1 >= 0
                        {
                            west_neighbor := *chunk_grid[x_index - 1][y_index];
                            propagated = WFC_propagate(gen_chunk, cell, west_neighbor, WEST, EAST);
                        }

                        //check north
                        if y_index + 1 < chunk_size.y
                        {
                            north_neighbor := *chunk_grid[x_index][y_index + 1];
                            propagated = WFC_propagate(gen_chunk, cell, north_neighbor, NORTH, SOUTH);
                        }

                        //check south
                        if y_index - 1 >= 0
                        {
                            south_neighbor := *chunk_grid[x_index][y_index - 1];
                            propagated = WFC_propagate(gen_chunk, cell, south_neighbor, SOUTH, NORTH);
                        }
                        cell.entropy = cast(u32)(popcount(cell.cell_mask));

                        // TODO(Sleepster): we have failed... 
                        if cell.entropy == 0
                        {
                            log("[ERROR]: Generation has failed... Retrying...");

                            gen_chunk.* = fail_chunk;
                            WFC_generate(arena, gen_chunk);
                        }
                    }
                    else
                    {
                        continue;
                    }
                }
            }
        }
    }
    end_temporary_block(*scratch_arena);
}

WFC_render :: (chunk: *WFC_Gen_Chunk, draw_frame: *Draw_Frame_Data)
{
    push_render_layer(draw_frame, 15);
    initial_pos := (Vector2).{-482, -240};

    for x: 0..chunk.chunk_size.x -1
    {
        for y: 0..chunk.chunk_size.y - 1
        {
            cell := chunk.chunk_grid[x][y];

            new_pos := (Vector2).{initial_pos.x + (x * 16), initial_pos.y + (y * 16)};
            draw_texture(draw_frame, new_pos, .{16, 16}, *chunk.chunk_modules[cell.cell_value].sprite, WHITE);
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

/////////////////////////////////////
// AUTOMATIC STM MODULE GENERATION
/////////////////////////////////////

WFC_analyze :: (arena: *Memory_Arena)
{
    texture := asset_load_texture_from_path(example_image_filepath);

    // setup
    grid_width := texture.width  / tile_size.x;
    grid_height := texture.height / tile_size.y;

    scratch := begin_temporary_block(arena);
    module_hash := push_array(arena, WFC_Module, xx (grid_width * grid_height));
    for *module: module_hash
    {
        module.hash_value = -1;
    }

    module_grid: [][]s64;
    module_grid = push_array(arena, []s64, xx grid_width);
    for grid_y: 0..grid_height - 1
    {
        module_grid[grid_y] = push_array(arena, s64, xx grid_height);
    }

    // hash
    for grid_x: 0..grid_width - 1
    {
        for grid_y: 0..grid_height - 1
        {
            hash_value: u64 = 14695981039346656037;
            for x: 0..tile_size.x 
            {
                for y: 0..tile_size.y 
                {
                    pixel_x := grid_x * tile_size.x + x;
                    pixel_y := grid_y * tile_size.y + y;

                    pixel_index := (pixel_y * texture.width + pixel_x) * texture.channels;
                    for channel: 0..texture.channels - 1
                    {
                        hash_value = hash_value ^ texture.data[pixel_index + channel];
                        hash_value = hash_value * 1099511628211;
                    }
                }
            }

            hash_index    := (hash_value % xx module_hash.count);
            log("HASH INDEX: '%', grid pos: {%, %}\n", hash_index, grid_x, grid_y);
            
            hashed_module := *module_hash[hash_index];
            if hashed_module.hash_value == -1 
            {
                hashed_module.hash_value = xx hash_index;
            }

            module_grid[grid_x][grid_y] = xx hash_index;
        }
    }

    // analysis
    for x: 0..grid_width - 1
    {
        for y: 0..grid_height - 1
        {
            grid_value := module_grid[x][y];
            //check east
            if x + 1 < grid_width
            {
                east_neighbor := module_grid[x + 1][y];
                module := *module_hash[east_neighbor];
            }

            //check west
            if x - 1 >= 0
            {
                west_neighbor := module_grid[x - 1][y];
                module := *module_hash[west_neighbor];
            }

            //check north
            if y + 1 < grid_height
            { 
                north_neighbor := module_grid[x][y + 1];
                module := *module_hash[north_neighbor];
            }

            //check south
            if y - 1 >= 0
            {
                south_neighbor := module_grid[x][y - 1];
                module := *module_hash[south_neighbor];
            }
        }
    }

    end_temporary_block(*scratch);
}

#scope_file
example_image_filepath : string = "../data/res/textures/OLM_test_input.png";
tile_size              : iVector2 = .{16, 16};

