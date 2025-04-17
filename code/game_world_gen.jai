/*
TODO:
  - [x] Make a LIST of the tiles with the lowest entropy, instead of
        picking just the first one we see. Then select randomly from that
        list.

  - [x] Propogate collapses to all nearby tiles within a 3x3
        intersection of our tile.

  - [ ] Improve the way we supply rules and options

  - [ ] Bitset, we need more than 64 options for modules

  - [ ] Compress the options so that they also store a rotation??

  - [ ] Create a queue for the propagation code rather than what we're doing now. (slow) 

  - [ ] A* path finding to tie the rooms together

  - [ ] Path contraints?
*/

////////////////
// BITSET DATA
////////////////

MAX_BITSET :: 10;

Bitset :: struct
{
    bits      : [MAX_BITSET]u64;
    bit_count : s64;
}#no_padding;

bitset_create :: (arena: *Memory_Arena, bit_count: s64) -> Bitset #must
{
    // NOTE(Sleepster): assert you're not stupid...
    assert(bit_count > 0);
    
    result: Bitset;
    result.bit_count = bit_count;

    return result;
};

bitset_destroy :: (bitset: *Bitset)
{
    free(bitset.bits.data);
}

bitset_set_bit :: (bitset: *Bitset, index: s64)
{
    assert(index < bitset.bit_count);
    bitset.bits[index >> 6] |= (cast(u64)(1 << (index & 63)));
}

bitset_clear_bit :: (bitset: *Bitset, index: s64)
{
    assert(index < bitset.bit_count);
    bitset.bits[index >> 6] &= ~(cast(u64)(1 << (index & 63)));
}

bitset_toggle_bit :: (bitset: *Bitset, index: s64)
{
    assert(index < bitset.bit_count);
    bitset.bits[index >> 6] ^= (cast(u64)(1 << (index & 63)));
}

bitset_check_bit :: (bitset: *Bitset, index: s64) -> bool
{
    return (((bitset.bits[index >> 6]) & (xx(1 << (index & 63)))) != 0);
}

bitset_clear :: (bitset: *Bitset)
{
    for 0..bitset.bits.count - 1
    {
        bitset.bits[it] = 0;
    }
}

bitset_popcount :: (bitset: *Bitset) -> s32 
{
    result: s32;
    for element: bitset.bits
    {
        result += popcount(element);
    }

    return result;
}

bitset_combine :: (A: Bitset, B: Bitset) -> Bitset
{
    result: Bitset;
    result.bit_count = A.bit_count;
    assert(A.bit_count == B.bit_count);
    for index: 0..A.bits.count - 1
    {
        result.bits[index] = (A.bits[index] & B.bits[index]);
    }

    return result;
}

operator != :: (A: Bitset, B: Bitset) -> bool
{
    if A.bit_count != B.bit_count return true;
    for index: 0..A.bits.count - 1
    {
        if A.bits[index] != B.bits[index] return true;
    }

    return false;
}

////////////////////////
// WFC MAP GENERATION
////////////////////////

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

    cell_x       : s32;
    cell_y       : s32;

    cell_mask    : Bitset;
    cell_value   : u32;
};

WFC_Module :: struct
{
    sprite      : Atlas_Sprite;
    constraints : [Directions.COUNT]Bitset;
    weight      : float32;
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
            cell.cell_mask    = bitset_create(arena, modules.count);

            cell.cell_x       = x;
            cell.cell_y       = y;

            for module_index: 0..modules.count - 1
            {
                bitset_set_bit(*cell.cell_mask, module_index);
            }
        }
    }

    return new_chunk;
}

//////////////////////////
// AC-1 WORLD GENERATION
//////////////////////////


WFC_propagate_AC1 :: (chunk_data    : *WFC_Gen_Chunk,
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
            if bitset_check_bit(*primary_cell.cell_mask, module_index)
            {
                supported: bool;
                for rule_index: 0..chunk_modules.count - 1
                {
                    if bitset_check_bit(*neighbor_cell.cell_mask, rule_index)
                    {
                        if bitset_check_bit(*chunk_modules[module_index].constraints[neighbor_dir], rule_index)
                        {
                            supported = true;
                            break;
                        }
                    }
                }

                if !supported
                {
                    bitset_clear_bit(*primary_cell.cell_mask, module_index);
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
        new_mask := bitset_combine(*primary_cell.cell_mask, *allowed_mask);
        if new_mask != original_mask
        {
            primary_cell.cell_mask = new_mask;
            result = true;
        }
    }

    return result;
}

WFC_generate_AC1 :: (arena: *Memory_Arena, gen_chunk: *WFC_Gen_Chunk)
{
    DEBUG_profile_and_report();
    using gen_chunk;

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
            if bitset_check_bit(*cell.cell_mask, bit_index)
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
                            propagated = WFC_propagate_AC1(gen_chunk, cell, east_neighbor, EAST, WEST);
                        }

                        //check west
                        if x_index - 1 >= 0
                        {
                            west_neighbor := *chunk_grid[x_index - 1][y_index];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, west_neighbor, WEST, EAST);
                        }

                        //check north
                        if y_index + 1 < chunk_size.y
                        {
                            north_neighbor := *chunk_grid[x_index][y_index + 1];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, north_neighbor, NORTH, SOUTH);
                        }

                        //check south
                        if y_index - 1 >= 0
                        {
                            south_neighbor := *chunk_grid[x_index][y_index - 1];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, south_neighbor, SOUTH, NORTH);
                        }

                        cell.entropy = cast(u32)(bitset_popcount(*cell.cell_mask));
                        if cell.entropy == 0
                        {
                            // failure
                            log("[ERROR]: Generation has failed... Resetting...");

                            // NOTE(Sleepster): Resetting in place.
                            for x: 0..chunk_size.x - 1
                            {
                                for y: 0..chunk_size.y - 1
                                {
                                    cell := *gen_chunk.chunk_grid[x][y];
                                    
                                    cell.is_collapsed = false;
                                    cell.cell_value   = 0;
                                    cell.entropy      = xx chunk_modules.count;

                                    bitset_clear(*cell.cell_mask);
                                    for module_index: 0..chunk_modules.count - 1
                                    {
                                        bitset_set_bit(*cell.cell_mask, module_index);
                                    }
                                }
                            }
                            end_temporary_block(*scratch_arena);
                            WFC_generate_AC1(arena, gen_chunk);
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

//////////////////////////
// AC-3 WORLD GENERATION
//////////////////////////

WFC_Arc :: struct
{
    domain_A : *WFC_Cell;
    domain_B : *WFC_Cell;

    // NOTE(Sleepster): A to B
    arc_dir  : iVector2;
};

WFC_Arc_Queue :: struct
{
    arc_list    : []WFC_Arc;
    queue_count : u32;
};

get_direction_from_vector :: inline (vector: iVector2) -> Directions
{
    result: Directions;
    if vector.x != 0
    {
        result = ifx vector.x == 1 then EAST else WEST;
    }
    if vector.y != 0
    {
        result = ifx vector.y == 1 then NORTH else SOUTH;
    }

    return result;
}

get_opposite_vector :: inline (vector: iVector2) -> iVector2
{
    result: iVector2;
    result.x = vector.x * -1;
    result.y = vector.y * -1;

    return result;
}

WFC_enqueue_arc :: inline (using arc_queue       : *WFC_Arc_Queue,
                                 cell            : *WFC_Cell,
                                 neighbor        : *WFC_Cell,
                                 neighbor_vector :  iVector2)
{
    main_arc             := cast(WFC_Arc).{cell, neighbor, neighbor_vector};
    arc_list[queue_count] = main_arc;

    queue_count += 1;
}

WFC_revise_domain :: (chunk_data     : *WFC_Gen_Chunk,
                      collapsed_cell : *WFC_Cell,
                      neighbor_cell  : *WFC_Cell,
                      arc_dir        :  Directions) -> bool
{
    if neighbor_cell.is_collapsed return false;

    changes_made := false;
    for module: 0..chunk_data.chunk_modules.count - 1
    {
        if bitset_check_bit(*neighbor_cell.cell_mask, module)
        {
            supported := false;
            for bit_index: 0..chunk_data.chunk_modules.count - 1
            {
                if bitset_check_bit(*collapsed_cell.cell_mask, bit_index)
                {
                    if bitset_check_bit(*chunk_data.chunk_modules[module].constraints[arc_dir], bit_index)
                    {
                        supported = true;
                        break;
                    }
                }
            }
            if !supported
            {
                bitset_clear_bit(*neighbor_cell.cell_mask, module);
                changes_made = true;
            }
        }
    }

    return changes_made;
}

WFC_generate_AC3 :: (arena: *Memory_Arena, gen_chunk: *WFC_Gen_Chunk)
{
    DEBUG_profile_and_report();
    using gen_chunk;

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
            if bitset_check_bit(*cell.cell_mask, bit_index)
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
        bitset_clear(*cell.cell_mask);
        bitset_set_bit(*cell.cell_mask, selected_module);

        // build the arc queue
        arc_queue: WFC_Arc_Queue;
        arc_queue.arc_list = push_array(arena, WFC_Arc, xx (chunk_size.x * chunk_size.y));

        cell_vectors: [4]iVector2;
        cell_vectors[NORTH] = .{ 0,  1};
        cell_vectors[SOUTH] = .{ 0, -1};
        cell_vectors[EAST]  = .{ 1,  0};
        cell_vectors[WEST]  = .{-1,  0};
        for 0..4 - 1
        {
            neighbor_x := cell.cell_x + cell_vectors[it].x;
            neighbor_y := cell.cell_y + cell_vectors[it].y;

            neighbor_vector := get_opposite_vector(cell_vectors[it]);
            if neighbor_x >= 0 && neighbor_x < gen_chunk.chunk_size.x &&
               neighbor_y >= 0 && neighbor_y < gen_chunk.chunk_size.y
            {
                neighbor_cell := *chunk_grid[neighbor_x][neighbor_y];
                WFC_enqueue_arc(*arc_queue, neighbor_cell, cell, neighbor_vector);
            }
        }

        // propagate the collapse
        while arc_queue.queue_count != 0 
        {
            // remove an item from the queue
            arc := arc_queue.arc_list[arc_queue.queue_count - 1];
            arc_queue.queue_count -= 1;

            if !arc.domain_A.is_collapsed
            {
                dir          := get_direction_from_vector(arc.arc_dir);
                opposite_dir := get_direction_from_vector(get_opposite_vector(arc.arc_dir));  

                // Module A is the neighbor, Module B is the collapsed cell
                changed := WFC_revise_domain(gen_chunk, arc.domain_B, arc.domain_A, dir);
                arc.domain_A.entropy = cast(u32)(bitset_popcount(*arc.domain_A.cell_mask));
                if arc.domain_A.entropy == 0
                {
                    // failure
                    log("\n\n\n[=================== ERROR ====================\n");
                    log("[ERROR]: Generation has failed... Resetting...\n");
                    log("[=================== ERROR ====================\n\n\n");

                    // NOTE(Sleepster): Resetting in place.
                    for x: 0..chunk_size.x - 1
                    {
                        for y: 0..chunk_size.y - 1
                        {
                            cell := *gen_chunk.chunk_grid[x][y];
                            
                            cell.is_collapsed = false;
                            cell.cell_value   = 0;
                            cell.entropy      = xx chunk_modules.count;

                            bitset_clear(*cell.cell_mask);
                            for module_index: 0..chunk_modules.count - 1
                            {
                                bitset_set_bit(*cell.cell_mask, module_index);
                            }
                        }
                    }

                    end_temporary_block(*scratch_arena);
                    WFC_generate_AC3(arena, gen_chunk);
                }

                if changed
                {
                    for 0..4 - 1
                    {
                        neighbor_x := arc.domain_A.cell_x + cell_vectors[it].x;
                        neighbor_y := arc.domain_A.cell_y + cell_vectors[it].y;

                        neighbor_vector := get_opposite_vector(cell_vectors[it]);
                        if neighbor_x  >= 0 && neighbor_x < gen_chunk.chunk_size.x &&
                            neighbor_y >= 0 && neighbor_y < gen_chunk.chunk_size.y
                        {
                            neighbor_cell := *chunk_grid[neighbor_x][neighbor_y];
                            WFC_enqueue_arc(*arc_queue, neighbor_cell, arc.domain_A, neighbor_vector);
                        }
                    }
                }
            }
        }
    }

    end_temporary_block(*scratch_arena);
}


////////////////
// RENDERERING
////////////////

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
}

/////////////////////////////////////
// AUTOMATIC STM MODULE GENERATION
/////////////////////////////////////

WFC_Module_Neighbor_Data :: struct
{
    hash_indices : []u32;
    count        : u32;
};

WFC_Generator_Module :: struct
{
    neighbors  : [COUNT]WFC_Module_Neighbor_Data;
    weight     : float32;
    hash_value : s64 = -1;
};

WFC_Generator :: struct
{
    module_hash         : []WFC_Generator_Module;
    unique_module_count : u32;
};

add_module_to_neighbor_list :: (primary: *WFC_Generator_Module, neighbor: *WFC_Generator_Module, dir: Directions)
{
    neighbor_data := *primary.neighbors[dir];

    neighbor_data.hash_indices[neighbor_data.count] = xx neighbor.hash_value;
    neighbor_data.count += 1;
}

WFC_analyze :: (arena: *Memory_Arena)
{
    texture := asset_load_texture_from_path(example_image_filepath);
    scratch := begin_temporary_block(arena);

    // setup
    grid_width  := texture.width  / tile_size.x;
    grid_height := texture.height / tile_size.y;

    WFC_gen_data: WFC_Generator;
    WFC_gen_data.module_hash = push_array(arena, WFC_Generator_Module, xx (grid_width * grid_height));
    for *module: WFC_gen_data.module_hash
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
    WFC_gen_data.unique_module_count = 0;
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

            hash_index    := (hash_value % xx WFC_gen_data.module_hash.count);
            log("HASH INDEX: '%', grid pos: {%, %}\n", hash_index, grid_x, grid_y);
            
            hashed_module := *WFC_gen_data.module_hash[hash_index];
            hashed_module.weight += 0.01;
            if hashed_module.hash_value == -1 
            {
                hashed_module.hash_value = xx hash_index;
                WFC_gen_data.unique_module_count += 1;
            }

            module_grid[grid_x][grid_y] = xx hash_index;
        }
    }

    // init neighbor list
    for *module: WFC_gen_data.module_hash
    {
        if module.hash_value != -1
        {
            module.neighbors[NORTH].hash_indices = push_array(arena, u32, WFC_gen_data.unique_module_count);
            module.neighbors[SOUTH].hash_indices = push_array(arena, u32, WFC_gen_data.unique_module_count);
            module.neighbors[EAST].hash_indices  = push_array(arena, u32, WFC_gen_data.unique_module_count);
            module.neighbors[WEST].hash_indices  = push_array(arena, u32, WFC_gen_data.unique_module_count);
        }
    }
    
    // analysis
    for x: 0..grid_width - 1
    {
        for y: 0..grid_height - 1
        {
            grid_value     := module_grid[x][y];
            primary_module := *WFC_gen_data.module_hash[grid_value];
            
            //check east
            if x + 1 < grid_width
            {
                east_neighbor   := module_grid[x + 1][y];
                neighbor_module := *WFC_gen_data.module_hash[east_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, EAST);
            }

            //check west
            if x - 1 >= 0
            {
                west_neighbor := module_grid[x - 1][y];
                neighbor_module := *WFC_gen_data.module_hash[west_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, WEST);
            }

            //check north
            if y + 1 < grid_height
            { 
                north_neighbor := module_grid[x][y + 1];
                neighbor_module := *WFC_gen_data.module_hash[north_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, NORTH);
            }

            //check south
            if y - 1 >= 0
            {
                south_neighbor := module_grid[x][y - 1];
                neighbor_module := *WFC_gen_data.module_hash[south_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, SOUTH);
            }
        }
    }

    for *module: WFC_gen_data.module_hash
    {
        if module.hash_value != -1
        {
            for neighbor_list: module.neighbors
            {
                if neighbor_list.count > 0
                {
                    log("Module '%' has the following neighbors: ", module.hash_value);
                    for index: 0..neighbor_list.count - 1
                    {
                        log("%", neighbor_list.hash_indices[index]);
                    }
                    log("\n\n");
                }
            }
        }
    }

    resulting_modules := push_array(arena, WFC_Module, WFC_gen_data.unique_module_count);
    for *module: resulting_modules
    {
    }
    
    end_temporary_block(*scratch);
}

#scope_file
example_image_filepath : string   = "../data/res/textures/OLM_test_input.png";
tile_size              : iVector2 = .{64, 64};

