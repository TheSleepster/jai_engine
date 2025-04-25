/*
TODO:
  - [ ] Test the idea of layered room generation. (First generate the floor, then the walls, etc.) 
  - [ ] Implment a function that can place a room of certain dimensions, allow precollapsed tiles during this to "seed" the room
  - [ ] Create a higher level structure for storing these generated rooms and their layout in the world
  - [ ] Create a "generator" that can control HOW the rooms are placed and what their sizes should be
  - [ ] Create a method of connecting the rooms together and cull the unconnected rooms

BACKBURNER:
  - [ ] A* path finding to tie the rooms together
  - [ ] Compress the generated options so that they also store a rotation??
  - [ ] Backtracking on AC-3?
  - [ ] Path contraints?

DONE:
  - [x] Create a queue for the propagation code rather than what we're doing now. (slow) 
  - [x] Bitset, we need more than 64 options for modules
  - [x] Make a LIST of the tiles with the lowest entropy, instead of
        picking just the first one we see. Then select randomly from that
        list.
  - [x] Propogate collapses to all nearby tiles
  - [x] Improve the way we supply rules and options
  - [x] Add the ability to precollapse tiles before generation, "seeding" the generation
*/

////////////////
// BITSET DATA
////////////////

MAX_BITSET :: 10;

Bitset :: struct
{
    bits      : [MAX_BITSET]u64;
    bit_count :             s64;
}#no_padding;

bitset_create :: (arena: *Memory_Arena, bit_count: s64) -> Bitset #must
{
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

bitset_reset :: (bitset: *Bitset)
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


/*
FUTURE IDEA:

WFC_Tile_Chunk :: struct
{
    generation_grid : [][]WFC_Cell;
    initial_grid    : [][]WFC_Cell;
}

WFC_Gen_Chunk :: struct
{
    chunk_size    :   iVector2;
    chunk_modules : []WFC_Module;

    floor_chunk   : []WFC_Tile_Chunk;
    wall_chunk    : []WFC_Tile_Chunk;
    decor_chunk   : []WFC_Tile_Chunk;

    arc_queue     :   WFC_Arc_Queue;
};
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
    chunk_size      :     iVector2;
    chunk_modules   :   []WFC_Module;
    generation_grid : [][]WFC_Cell;
    initial_grid    : [][]WFC_Cell;

    arc_queue       : WFC_Arc_Queue;
};

// TODO(Sleepster): This might be painfully slow 
WFC_new_chunk :: (arena: *Memory_Arena, chunk_size: iVector2, modules: []WFC_Module) -> WFC_Gen_Chunk
{
    new_chunk: WFC_Gen_Chunk;
    new_chunk.chunk_size    = chunk_size;
    new_chunk.chunk_modules = modules;

    new_chunk.generation_grid = push_array(arena, []WFC_Cell, xx chunk_size.x);
    for x: 0..chunk_size.x - 1
    {
        new_chunk.generation_grid[x] = push_array(arena, WFC_Cell, xx chunk_size.y);
    }

    new_chunk.initial_grid = push_array(arena, []WFC_Cell, xx chunk_size.x);
    for x: 0..chunk_size.x - 1
    {
        new_chunk.initial_grid[x] = push_array(arena, WFC_Cell, xx chunk_size.y);
    }

    for x: 0..chunk_size.x - 1
    {
        for y: 0..chunk_size.y - 1
        {
            cell         := *new_chunk.generation_grid[x][y];
            initial_cell := *new_chunk.initial_grid[x][y];
            
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

            initial_cell.* = cell.*;
        }
    }

    return new_chunk;
}

// TODO(Sleepster): It might be a better / more efficient idea to have
// this function add to a list of cells to update. Just so we could
// perform all of the updating at the same time rather than *here* every
// single time someone asks us to collapse a cell.
WFC_collapse_single_cell :: (chunk: *WFC_Gen_Chunk, value: u32, grid_pos: iVector2)
{
    initial_cell := *chunk.initial_grid[grid_pos.x][grid_pos.y];
    initial_cell.is_collapsed = true;
    initial_cell.cell_value   = value;
    initial_cell.entropy      = 1;

    bitset_reset(*initial_cell.cell_mask);
    bitset_set_bit(*initial_cell.cell_mask, initial_cell.cell_value);

    cell_vectors: [4]iVector2;
    cell_vectors[NORTH] = .{ 0,  1};
    cell_vectors[SOUTH] = .{ 0, -1};
    cell_vectors[EAST]  = .{ 1,  0};
    cell_vectors[WEST]  = .{-1,  0};
    for 0..4 - 1
    {
        neighbor_x := initial_cell.cell_x + cell_vectors[it].x;
        neighbor_y := initial_cell.cell_y + cell_vectors[it].y;

        neighbor_vector := get_opposite_vector(cell_vectors[it]);
        if neighbor_x >= 0 && neighbor_x < chunk.chunk_size.x &&
            neighbor_y >= 0 && neighbor_y < chunk.chunk_size.y
        {
            neighbor_cell := *chunk.initial_grid[neighbor_x][neighbor_y];
            WFC_enqueue_arc(*chunk.arc_queue, neighbor_cell, initial_cell, neighbor_vector);
        }
    }

    // propagate the collapse
    while chunk.arc_queue.queue_count != 0
    {
        // remove an item from the queue
        arc := chunk.arc_queue.arc_list[chunk.arc_queue.queue_count - 1];
        chunk.arc_queue.queue_count -= 1;

        if !arc.domain_A.is_collapsed
        {
            dir          := get_direction_from_vector(arc.arc_dir);
            opposite_dir := get_direction_from_vector(get_opposite_vector(arc.arc_dir));  

            // Module A is the neighbor, Module B is the collapsed cell
            changed := WFC_revise_domain(chunk, arc.domain_B, arc.domain_A, dir);
            arc.domain_A.entropy = cast(u32)(bitset_popcount(*arc.domain_A.cell_mask));
            if arc.domain_A.entropy == 0
            {
                log("[ERROR]: Seeding has failed...\n");
                break;
            }

            if changed
            {
                for 0..4 - 1
                {
                    neighbor_x := arc.domain_A.cell_x + cell_vectors[it].x;
                    neighbor_y := arc.domain_A.cell_y + cell_vectors[it].y;

                    neighbor_vector := get_opposite_vector(cell_vectors[it]);
                    if neighbor_x  >= 0 && neighbor_x < chunk.chunk_size.x &&
                        neighbor_y >= 0 && neighbor_y < chunk.chunk_size.y
                    {
                        neighbor_cell := *chunk.initial_grid[neighbor_x][neighbor_y];
                        WFC_enqueue_arc(*chunk.arc_queue, neighbor_cell, arc.domain_A, neighbor_vector);
                    }
                }
            }
        }

        cell  := *chunk.generation_grid[arc.domain_A.cell_x][arc.domain_A.cell_y];
        cell.* = arc.domain_A.*;
    }

    chunk.arc_queue.queue_count = 0;
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

WFC_generate_AC1 :: (arena: *Memory_Arena, gen_chunk: *WFC_Gen_Chunk) -> bool
{
    result: bool;
    should_break: bool;
    
    DEBUG_profile_and_report();
    using gen_chunk;

    scratch_arena := begin_temporary_block(arena);
    while !should_break 
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
                current_cell := *generation_grid[x_index][y_index];
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
            result = true;
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
                    cell := *generation_grid[x_index][y_index];
                    if !cell.is_collapsed
                    {
                        // check east
                        if x_index + 1 < chunk_size.x
                        {
                            east_neighbor := *generation_grid[x_index + 1][y_index];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, east_neighbor, EAST, WEST);
                        }

                        // check west
                        if x_index - 1 >= 0
                        {
                            west_neighbor := *generation_grid[x_index - 1][y_index];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, west_neighbor, WEST, EAST);
                        }

                        // check north
                        if y_index + 1 < chunk_size.y
                        {
                            north_neighbor := *generation_grid[x_index][y_index + 1];
                            propagated = WFC_propagate_AC1(gen_chunk, cell, north_neighbor, NORTH, SOUTH);
                        }

                        // check south
                        if y_index - 1 >= 0
                        {
                            south_neighbor := *generation_grid[x_index][y_index - 1];
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
                                    cell := *gen_chunk.generation_grid[x][y];
                                    
                                    cell.is_collapsed = false;
                                    cell.cell_value   = 0;
                                    cell.entropy      = xx chunk_modules.count;

                                    bitset_reset(*cell.cell_mask);
                                    for module_index: 0..chunk_modules.count - 1
                                    {
                                        bitset_set_bit(*cell.cell_mask, module_index);
                                    }
                                }
                            }

                            result = false;
                            should_break = true;
                            break;
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
    return result;
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

// NOTE(Sleepster): growing... must be freed.
WFC_Arc_Queue :: struct
{
    arc_list    : [..]WFC_Arc;
    queue_count :   u32;
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

WFC_enqueue_arc :: (using arc_queue       : *WFC_Arc_Queue,
                          cell            : *WFC_Cell,
                          neighbor        : *WFC_Cell,
                          neighbor_vector :  iVector2)
{
    main_arc := cast(WFC_Arc).{cell, neighbor, neighbor_vector};
    array_insert_at(*arc_list, main_arc, queue_count);

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

WFC_generate_AC3 :: (arena: *Memory_Arena, gen_chunk: *WFC_Gen_Chunk) -> bool
{
    //DEBUG_profile_and_report();
    result: bool;

    should_break: bool;
    scratch_arena := begin_temporary_block(arena);
    while !should_break
    {
        to_collapse: []*WFC_Cell;
        to_collapse.count = (gen_chunk.chunk_size.x * gen_chunk.chunk_size.y);
        to_collapse.data  = push_size(arena, size_of(*WFC_Cell) * (gen_chunk.chunk_size.x * gen_chunk.chunk_size.y));
        cell_count : u32;

        // builds list of tiles to collapse
        lowest_entropy := gen_chunk.chunk_modules.count + 1;
        for x_index: 0..gen_chunk.chunk_size.x - 1
        {
            for y_index: 0..gen_chunk.chunk_size.y - 1
            {
                current_cell := *gen_chunk.generation_grid[x_index][y_index];
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
        if lowest_entropy == gen_chunk.chunk_modules.count + 1
        {
            log("[INFO]: WFC GENERATION COMPLETED...\n");
            array_free(gen_chunk.arc_queue.arc_list);

            result = true;
            break;
        }

        // picks cell from list
        random_seed(*context.random_state, rdtsc());
        index_to_pick := cast(u32)random_get_within_range(*context.random_state, 0, cast(float32)(cell_count - 1));

        // collapse the cell
        cell := to_collapse[index_to_pick];
        cell_modules: []u32;

        cell_modules.data  = push_size(arena, xx (size_of(u32) * gen_chunk.chunk_modules.count));
        cell_modules.count = gen_chunk.chunk_modules.count;

        cell_module_counter: u32 = 0;
        for bit_index: 0..gen_chunk.chunk_modules.count - 1
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
                total_weight += gen_chunk.chunk_modules[cell_modules[index]].weight;
            }
        }
        else
        {
            total_weight += gen_chunk.chunk_modules[cell_modules[0]].weight;
        }

        collapsed_value   := random_get_within_range(*context.random_state, 0.0, total_weight);
        cumulative_weight : float32;
        selected_module   : u32;
        for index: 0..cell_module_counter - 1
        {
            cumulative_weight += gen_chunk.chunk_modules[cell_modules[index]].weight;
            if collapsed_value <= cumulative_weight 
            {
                selected_module = cell_modules[index];
                break;
            }
        }
        
        cell.is_collapsed = true;
        cell.cell_value   = selected_module;
        cell.entropy      = 1;
        bitset_reset(*cell.cell_mask);
        bitset_set_bit(*cell.cell_mask, selected_module);

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
                neighbor_cell := *gen_chunk.generation_grid[neighbor_x][neighbor_y];
                WFC_enqueue_arc(*gen_chunk.arc_queue, neighbor_cell, cell, neighbor_vector);
            }
        }

        // propagate the collapse
        while gen_chunk.arc_queue.queue_count != 0 
        {
            // remove an item from the queue
            arc := gen_chunk.arc_queue.arc_list[gen_chunk.arc_queue.queue_count - 1];
            gen_chunk.arc_queue.queue_count -= 1;

            if !arc.domain_A.is_collapsed
            {
                dir          := get_direction_from_vector(arc.arc_dir);
                opposite_dir := get_direction_from_vector(get_opposite_vector(arc.arc_dir));  

                // NOTE(Sleepster): Module A is the neighbor, Module B is the collapsed cell
                changed := WFC_revise_domain(gen_chunk, arc.domain_B, arc.domain_A, dir);
                arc.domain_A.entropy = cast(u32)(bitset_popcount(*arc.domain_A.cell_mask));
                if arc.domain_A.entropy == 0
                {
                    // failure
                    log("[ERROR]: Generation has failed... Resetting...\n");

                    // NOTE(Sleepster): Resetting in place.
                    for x: 0..gen_chunk.chunk_size.x - 1
                    {
                        for y: 0..gen_chunk.chunk_size.y - 1
                        {
                            cell         := *gen_chunk.generation_grid[x][y];
                            initial_cell :=  gen_chunk.initial_grid[x][y];

                            cell.* = initial_cell;
                        }
                    }
                    gen_chunk.arc_queue.queue_count = 0;

                    result = false;
                    should_break = true;
                    break;
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
                            neighbor_cell := *gen_chunk.generation_grid[neighbor_x][neighbor_y];
                            WFC_enqueue_arc(*gen_chunk.arc_queue, neighbor_cell, arc.domain_A, neighbor_vector);
                        }
                    }
                }
            }
        }
    }

    end_temporary_block(*scratch_arena);
    return result;
}


////////////////
// RENDERERING
////////////////

WFC_render :: (chunk: *WFC_Gen_Chunk, draw_frame: *Draw_Frame_Data)
{
    push_render_layer(draw_frame, 15);
    initial_pos := (Vector2).{-100, -100};
    for x: 0..chunk.chunk_size.x -1
    {
        for y: 0..chunk.chunk_size.y - 1
        {
            cell := chunk.generation_grid[x][y];

            new_pos := (Vector2).{initial_pos.x + (x * 8), initial_pos.y + (y * 8)};
            draw_texture(draw_frame, new_pos, .{8, 8}, *chunk.chunk_modules[cell.cell_value].sprite, WHITE);
        }
    }
}


/////////////////////////////////////
// AUTOMATIC STM MODULE GENERATION
/////////////////////////////////////

WFC_Generator_Neighbor_Data :: struct
{
    neighbor_hash_values : [..]u64;
    neighbor_count       :   u32;
};

WFC_Generator_Module :: struct
{
    hash_value          : u64;
    unique_module_index : u32;
    is_valid            : bool;

    constraint_data     : [4]WFC_Generator_Neighbor_Data;
    sprite_data         :    Atlas_Sprite;
    module_frequency    :    float32;
};

WFC_Generator :: struct
{
    module_hash         : []WFC_Generator_Module;
    unique_module_count :   u32;
};

add_module_to_neighbor_list :: inline (parent    : *WFC_Generator_Module,
                                       neighbor  : *WFC_Generator_Module,
                                       direction :  Directions)
{
    parent_data := *parent.constraint_data[direction];

    array_insert_at(*parent_data.neighbor_hash_values, neighbor.hash_value, parent_data.neighbor_count);
    parent_data.neighbor_count += 1;
}

WFC_analyze :: (arena: *Memory_Arena, asset_manager: *Asset_Manager, filepath: string) -> []WFC_Module
{
    result: []WFC_Module;
    
    path, basename, ext     := path_decomp(filepath);
    atlas_sprite            := asset_get_sprite(asset_manager,  basename);
    texture_data, allocated := asset_load_texture_from_path(asset_manager, filepath); 

    grid_width  := texture_data.width  / tile_size.x;
    grid_height := texture_data.height / tile_size.y;
    hash_size   := ((grid_width * grid_height) * 2);

    generator: WFC_Generator;
    generator.module_hash = push_temp_array(WFC_Generator_Module, xx hash_size);
    generator.unique_module_count = 0;
    for *module: generator.module_hash
    {
        module.is_valid = false; 
    }

    module_grid: [][]u64;
    module_grid = push_array(arena, []u64, xx grid_width);
    for grid_y: 0..grid_width - 1
    {
        module_grid[grid_y] = push_array(arena, u64, xx grid_height);
    }

    valid_hashes: []u64;
    valid_hashes.data  = alloc(xx((grid_width * grid_height) * size_of(u64)));
    defer free(valid_hashes.data);

    valid_hashes.count = (grid_width * grid_height);
    for grid_x: 0..grid_width - 1
    {
        for grid_y: 0..grid_height - 1
        {
            sprite_data := subsprite(atlas_sprite, .{xx(grid_x * tile_size.x), xx(grid_y * tile_size.y)}, .{xx tile_size.x, xx tile_size.y});

            hash_value: u64 = 14695981039346656037;
            for x: 0..tile_size.x - 1 
            {
                for y: 0..tile_size.y - 1 
                {

                    pixel_x := grid_x * tile_size.x + x;
                    pixel_y := grid_y * tile_size.y + y;

                    pixel_index := (pixel_y * atlas_sprite.atlas_size.x + pixel_x) * texture_data.channels;
                    for channel: 0..texture_data.channels - 1
                    {
                        hash_value = hash_value ^ texture_data.data[pixel_index + channel];
                        hash_value = hash_value * 1099511628211;
                    }
                }
            }

            hash_index    := hash_value % xx generator.module_hash.count;
            hashed_module := *generator.module_hash[hash_index];
            // we know this is a new module
            if !hashed_module.is_valid
            {
                hashed_module.hash_value          = hash_index;
                hashed_module.unique_module_index = generator.unique_module_count;
                hashed_module.is_valid            = true;
                hashed_module.sprite_data         = sprite_data;
                // TODO(Sleepster): maybe we want to pass a file with metadata about how to increase weights? 
                
                valid_hashes[generator.unique_module_count] = hash_index;
                generator.unique_module_count              += 1;
            }
            else
            {
                assert(hashed_module.is_valid);
            }

            hashed_module.module_frequency += 1;
            module_grid[grid_x][grid_y]     = hash_index;
        }
    }

    // analysis
    for x: 0..grid_width - 1
    {
        for y: 0..grid_height - 1
        {
            grid_value     := module_grid[x][y];
            primary_module := *generator.module_hash[grid_value];

            //check north
            if y + 1 < grid_height
            { 
                north_neighbor  := module_grid[x][y + 1];
                neighbor_module := *generator.module_hash[north_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, NORTH);
            }

            //check south
            if y - 1 >= 0
            {
                south_neighbor  := module_grid[x][y - 1];
                neighbor_module := *generator.module_hash[south_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, SOUTH);
            }
            
            //check east
            if x + 1 < grid_width
            {
                east_neighbor   := module_grid[x + 1][y];
                neighbor_module := *generator.module_hash[east_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, EAST);
            }

            //check west
            if x - 1 >= 0
            {
                west_neighbor   := module_grid[x - 1][y];
                neighbor_module := *generator.module_hash[west_neighbor];
                add_module_to_neighbor_list(primary_module, neighbor_module, WEST);
            }
        }
    }

    // for *module: generator.module_hash
    // {
    //     if module.is_valid 
    //     {
    //         for *neighbor_list: module.constraint_data
    //         {
    //             if neighbor_list.neighbor_count > 0
    //             {
    //                 log("Module '%' has the following neighbors: ", module.hash_value);
    //                 for index: 0..neighbor_list.neighbor_count - 1
    //                 {
    //                     hash_index := neighbor_list.neighbor_hash_values[index];
    //                     log("%, module_index: %", hash_index, generator.module_hash[hash_index].unique_module_index);
    //                 }
    //                 log("\n\n");
    //             }
    //         }
    //     }
    // }

    result = push_array(arena, WFC_Module, generator.unique_module_count);
    for gen_module_index: 0..generator.unique_module_count - 1
    {
        hash_index  := valid_hashes[gen_module_index];
        module_data := generator.module_hash[hash_index];

        new_module: WFC_Module;
        new_module.sprite = module_data.sprite_data;
        new_module.weight = 1 + log(module_data.module_frequency - 1);
        for constraint_index: 0..4 - 1
        {
            gen_constraint_data := *module_data.constraint_data[constraint_index];
            new_module.constraints[constraint_index] = bitset_create(arena, generator.unique_module_count);
            if gen_constraint_data.neighbor_count > 0
            {
                for bitset_index: 0..gen_constraint_data.neighbor_count - 1
                {
                    neighbor_index  := gen_constraint_data.neighbor_hash_values[bitset_index];
                    neighbor_module := generator.module_hash[neighbor_index];
                    bitset_set_bit(*new_module.constraints[constraint_index], neighbor_module.unique_module_index);
                }
            }
        }
        result[gen_module_index] = new_module;
    }

    for valid_hash: 0..generator.unique_module_count - 1 
    {
        hash_index := valid_hashes[valid_hash];
        module     := *generator.module_hash[hash_index];
        assert(module.is_valid);

        array_free(module.constraint_data[NORTH].neighbor_hash_values);
        array_free(module.constraint_data[SOUTH].neighbor_hash_values);
        array_free(module.constraint_data[EAST].neighbor_hash_values);
        array_free(module.constraint_data[WEST].neighbor_hash_values);
    }

    if allocated then asset_release_texture(texture_data);
    return result;
}

#scope_file
tile_size: iVector2 = .{16, 16};

