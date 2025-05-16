/*
TODO:
  - [ ] Create a higher level structure for storing these generated rooms and their layout in the world
  - [ ] Create a "generator" that can control HOW the rooms are placed and what their sizes should be
  - [ ] Stop using globals and dynamic arrays in this file.
  - [ ] Create a method of connecting the rooms together and cull the unconnected rooms
  - [ ] Test the idea of layered room generation. (First generate the floor, then the walls, etc.) 
  - [ ] Add a field called "tile_types" to the WFC_Modules. 
        Use a seperate image with different colors to denote the type of the tile (RED is hazard, GREEN is wall, BLUE is floor, etc.)

BACKBURNER:
  - [ ] A* path finding to tie the rooms together
  - [ ] Compress the generated options so that they also store a rotation??
  - [ ] Backtracking on AC-3?
  - [ ] Path contraints?
  - [ ] Map file format
  - [ ] There's a bug with the world generation, specifically with the handling of hallways. Sometimes a main room becomes disconnected from the rest. Fix this eventually

DONE:
  - [x] Create a queue for the propagation code rather than what we're doing now. (slow) 
  - [x] Bitset, we need more than 64 options for modules
  - [x] Make a LIST of the tiles with the lowest entropy, instead of
        picking just the first one we see. Then select randomly from that
        list.
  - [x] Propogate collapses to all nearby tiles
  - [x] Improve the way we supply rules and options
  - [x] Add the ability to precollapse tiles before generation, "seeding" the generation
  - [x] Implment a function that can place a room of certain dimensions, allow precollapsed tiles during this to "seed" the room
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

WFC_Tile_Type :: enum
{
    FLOOR;
    WALL; 
    DECOR;
};

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
        index_to_pick := cast(u32)random_get_within_range(0, cast(float32)(cell_count - 1));

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

        collapsed_value   := random_get_within_range(0.0, total_weight);
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
        index_to_pick := cast(u32)random_get_within_range(0, cast(float32)(cell_count - 1));

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

        collapsed_value   := random_get_within_range(0.0, total_weight);
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

// TODO(Sleepster): DEBUG, get rid of this 
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


////////////////////
// ROOM GENERATION
////////////////////

generate_enclosed_room :: (game_state: *Game_State, modules: []WFC_Module, generation_size: iVector2)
{
    new_chunk = WFC_new_chunk(*game_state.game_arena, generation_size, modules);

    // WALL LEFT
    WFC_collapse_single_cell(*new_chunk, 0, .{0, xx((generation_size.y * 0.5) - 1.0)});
    // WALL BOTTOM
    WFC_collapse_single_cell(*new_chunk, 1, .{xx((generation_size.x * 0.5) - 1.0), 0});
    // WALL TOP
    WFC_collapse_single_cell(*new_chunk, 4, .{xx((generation_size.x * 0.5) - 1.0), xx(generation_size.y - 1.0)});
    // WALL RIGHT
    WFC_collapse_single_cell(*new_chunk, 5, .{xx(generation_size.x - 1.0), xx(generation_size.y * 0.5)});

    generated: bool;
    while !generated
    {
        //generated = WFC_generate_AC1(*game_state.game_arena, *new_chunk);
        generated = WFC_generate_AC3(*game_state.game_arena, *new_chunk);
    }
}

/////////////////////
// WORLD GENERATION
/////////////////////

world_to_tile_pos :: inline (world_pos: Vector2) -> iVector2
{
    result: iVector2 = ---;
    result.x = cast(s32)floor(world_pos.x / tile_size.x);
    result.y = cast(s32)floor(world_pos.y / tile_size.y);

    return result;
}

tile_to_world_pos :: inline (tile_pos: iVector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = cast(float32)tile_pos.x * cast(float32)tile_size.x;
    result.y = cast(float32)tile_pos.y * cast(float32)tile_size.y;

    return result;
}

round_to_tile_pos :: inline (position: Vector2) -> Vector2
{
    result: Vector2 = ---;
    result = tile_to_world_pos(world_to_tile_pos(position));

    return result;
}

get_random_vec2 :: (minimum: Vector2, maximum: Vector2) -> Vector2
{
    return cast(Vector2).{random_get_within_range(minimum.x, maximum.x),
                          random_get_within_range(minimum.y, maximum.y)};
}

get_random_within_radius :: (radius: float32) -> Vector2 
{
    result: Vector2 = ---;
    
    TAU      := 2 * PI;
    theta    := TAU * random_get_zero_to_one();

    uniform  := random_get_zero_to_one();
    u_radius := radius * sqrt(uniform);

    result.x  = u_radius * cos(theta);
    result.y  = u_radius * sin(theta);

    return result;
}

get_random_within_ellipse :: (elipse_width: float32, elipse_height: float32) -> Vector2 
{
    result: Vector2 = ---;
    
    TAU      := 2.0 * PI;
    theta    := TAU * random_get_zero_to_one();

    uniform  := random_get_zero_to_one();
    u_radius := ifx uniform > 1 then 2 - uniform else uniform;

    result.x  = (elipse_width  * u_radius * cos(theta));
    result.y  = (elipse_height * u_radius * sin(theta));

    return result;
}

room_type :: enum 
{
    NIL;
    MAIN;
    LESSER;
    HALLWAY;
};

hallway_type :: enum
{
    NIL;
    VERTICAL;
    HORIZONTAL;
};

Generation_Room :: struct
{
    id             : u64;
    idx            : u64;
    
    position       : Vector2;
    size           : Vector2;
    velocity       : Vector2;

    type           : room_type;
    bounding_box   : AABB;

    solve_collision: bool;
};

Generation_Hallway :: struct
{
    id        : u32;
    type      : hallway_type;
    is_valid  : bool;

    start     : Vector2;
    end       : Vector2;

    // NOTE(Sleepster): These are the rooms the hallway connects 
    room_a_id : u64;
    room_b_id : u64;
    L_pair_id : s64;
};

reset_generation :: ()
{
    for *room: generation_rooms
    {
        room.* = cast(Generation_Room).{};
    }

    for *point: super_triangle.points
    {
        point.* = .{0, 0};
    }
}

init_generation :: (arena: *Memory_Arena)
{
    radius     := 5.0;
    added       = false;
    MST_index   = 0;
    main_room_counter = 0;

    array_reset(*triangulations);

    point_list.data  = null;
    point_list.count = 0;

    generation_rooms.data  = null;
    generation_rooms.count = 0;

    hallway_segments.data  = null;
    hallway_segments.count = 0;

    // max_room_x : float32 = 35.0 * v2_cast(tile_size).x;
    // max_room_y : float32 = 40.0 * v2_cast(tile_size).x;

    // min_room_x : float32 = 5.0 * v2_cast(tile_size).y;
    // min_room_y : float32 = 5.0 * v2_cast(tile_size).y;

    max_room_x : float32 = 35.0;
    max_room_y : float32 = 40.0;

    min_room_x : float32 = 5.0;
    min_room_y : float32 = 5.0;

    generation_rooms = push_array(arena, Generation_Room, xx room_count);
    for room_index: 0..room_count - 1
    {
        room := *generation_rooms[room_index];
        //room_position := round_to_tile_pos(get_random_within_radius(radius));
        //room_position := round_to_tile_pos(get_random_within_ellipse(150.0 * tile_size.x, 200.0 * tile_size.y));
        room_position := round_to_tile_pos(get_random_within_ellipse(150.0, 250.0));
        // 150 200

        // TODO(Sleepster): Do we want to try a normal random distribution for better rooms? 
        room_size     := v2_floor(get_random_v2_normal_in_range(.{min_room_x, min_room_y}, .{max_room_x, max_room_y}));

        room.position        = room_position;
        room.size            = room_size;
        room.id              = xx room_index;
        room.idx             = xx room_index;
        room.type            = .NIL;
        room.bounding_box    = AABB_create(room.position, room.position + room.size); 
        room.solve_collision = true;
    }
}

update_generation :: (draw_frame: *Draw_Frame_Data, time: Time_Data) -> bool
{
    finished: bool = true;
    
    repulsion_strength := 1.0;
    for *A: generation_rooms
    {
        disperse_vector: Vector2;
        for *B: generation_rooms
        {
            if A == B continue;
            if A.solve_collision && B.solve_collision
            {
                if AABB_collision(A.bounding_box, B.bounding_box)
                {
                    finished   = false;
                    direction := (Vector2).{(A.position.x + (A.size.x * 0.5)) - (B.position.x + (B.size.x * 0.5)),
                                            (A.position.y + (A.size.y * 0.5)) - (B.position.y + (B.size.y * 0.5))};

                    direction       *= repulsion_strength * tick_rate;
                    disperse_vector += direction;

                    A.bounding_box.min = A.position;
                    A.bounding_box.max = A.position + A.size;

                    B.bounding_box.min = B.position;
                    B.bounding_box.max = B.position + B.size;
                }
            }
        }

        A.position += disperse_vector;
    }

    return finished;
}

Delaunay_Triangle_Edge :: struct
{
    first_point  : Vector2;
    second_point : Vector2;

    edge_weight  : float32;
};

Delaunay_Triangle :: struct
{
    is_valid : bool = true;
    
    points   : [3]Vector2;
    edges    : [3]Delaunay_Triangle_Edge;
};

World_Gen_Grid_Square :: struct
{
    parent_room_id : u64;
    occupied       : u64;
    debug_hallway  : bool;
};

is_point_within_circumcircle :: (point: Vector2, triangle: *Delaunay_Triangle) -> bool
{
    result: bool = false;
    A := triangle.points[0];
    B := triangle.points[1];
    C := triangle.points[2];

    denominator := 2.0 * (A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y));

    // NOTE(Sleepster): No circumcircle exists, so point can't be inside
    if denominator == 0.0 {
        return result;
    }

    // NOTE(Sleepster): Compute circumcenter coordinates (Ox, Oy)
    Ox := ((A.x*A.x + A.y*A.y) * (B.y - C.y) + 
           (B.x*B.x + B.y*B.y) * (C.y - A.y) + 
           (C.x*C.x + C.y*C.y) * (A.y - B.y)) / denominator;

    Oy := ((A.x*A.x + A.y*A.y) * (C.x - B.x) + 
           (B.x*B.x + B.y*B.y) * (A.x - C.x) + 
           (C.x*C.x + C.y*C.y) * (B.x - A.x)) / denominator;

    // NOTE(Sleepster): Compute radius (distance from circumcenter to vertex A)
    r_squared    := (A.x - Ox) * (A.x - Ox) + (A.y - Oy) * (A.y - Oy);
    dist_squared := (point.x - Ox) * (point.x - Ox) + (point.y - Oy) * (point.y - Oy);

    result = dist_squared < r_squared;
    return result;
}

is_edge_shared :: (edge: Delaunay_Triangle_Edge, working_triangle: *Delaunay_Triangle, triangle_set: *[..]*Delaunay_Triangle) -> bool
{
    result: bool;
    for triangle: triangle_set.*
        {
            if triangle == working_triangle continue;

            for new_edge: triangle.edges
            {
                if(new_edge.first_point == edge.first_point  && new_edge.second_point == edge.second_point) ||
                  (new_edge.first_point == edge.second_point && new_edge.second_point == edge.first_point)
                {
                    result = true;
                    break;
                }
            }
            if result break;
        }
    
    return result;
}

contains_point_from_super_triangle :: (triangle: Delaunay_Triangle, super_triangle: Delaunay_Triangle) -> bool
{
    result: bool;
    for point: triangle.points
    {
        for super_point: super_triangle.points
        {
            if point == super_point
            {
                result = true;
                break;
            }
        }
        if result break;
    }

    return result;
}

// NOTE(Sleepster): is_valid is initialized to true 
world_gen_triangulate :: ()
{
    // insert the point
    for point_index: 0..point_list.count - 1
    {
        // TODO(Sleepster): I'm lazy 
        violations: [..]*Delaunay_Triangle;
        defer free(violations.data);

        // find the triangles the insertion violates the Delaunay Optimal of
        point := point_list[point_index];
        for triangle_index: 0..triangulations.count - 1
        {
            triangle := *triangulations[triangle_index];
            if triangle
            {
                if is_point_within_circumcircle(point, triangle)
                {
                    array_add(*violations, triangle);
                }
            }
        }

        // TODO(Sleepster): again, lazy 
        polygonal_hole: [..]Delaunay_Triangle_Edge;
        defer free(polygonal_hole.data);

        // find the edges of the violated triangles that are not shared by any other triangles
        for triangle_index: 0..violations.count - 1
        {
            working_triangle := violations[triangle_index];
            if working_triangle
            {
                for edge: working_triangle.edges
                {
                    if !is_edge_shared(edge, working_triangle, *violations)
                    {
                        // add the edge to the new polygonal hole
                        array_add(*polygonal_hole, edge);
                    }
                }
            }
        }

        // mark for removal
        for triangle: violations
        {
            if triangle
            {
                triangle.is_valid = false;
            }
        }

        // remove the old triangle 
        for triangle: triangulations
        {
            if !triangle.is_valid
            {
                remove triangle; // removes from the array
            }
        }

        // add the new triangle
        for edge: polygonal_hole
        {
            new_triangle: Delaunay_Triangle;

            new_triangle.points[0] = point;
            new_triangle.points[1] = edge.first_point;
            new_triangle.points[2] = edge.second_point;

            new_triangle.edges[0] = .{edge.first_point, edge.second_point, 0.0};
            new_triangle.edges[1] = .{edge.second_point, point, 0.0};
            new_triangle.edges[2] = .{point, edge.first_point, 0.0};

            new_triangle.is_valid = true;
            array_add(*triangulations, new_triangle);
        }
    }

    // remove the vertices associated with the super triangle
    new_triangulations: [..]Delaunay_Triangle;
    for triangle: triangulations
    {
        if !contains_point_from_super_triangle(triangle, super_triangle)
        {
            array_add(*new_triangulations, triangle);
        }
    }

    free(triangulations.data);
    triangulations.count = 0;
    triangulations.data  = new_triangulations.data;
    triangulations.count = new_triangulations.count;
}

MST_union_set :: (union_find: []u32, first_index: u32, second_index: u32)
{
    root1 := MST_find(union_find, first_index);
    root2 := MST_find(union_find, second_index);
    if root1 != root2
    {
        union_find[root1] = root2;
    }
}

MST_find :: (union_find: []u32, ID: u32) -> u32
{
    if union_find.data[ID] != ID
    {
        union_find.data[ID] = MST_find(union_find, union_find.data[ID]);
    }

    return union_find[ID];
}

world_gen_segment_hallways :: (hallway           : *Generation_Hallway,
                               room_array        :   []Generation_Room,
                               new_hallways      :  *[..]Generation_Hallway,
                               segment_count     :  u32,
                               new_hallway_count : *u32)
{
    // DDA
    hallway_dir_x := hallway.end.x - hallway.start.x;
    hallway_dir_y := hallway.end.y - hallway.start.y;

    step_count: u32;
    if abs(hallway_dir_x) >= abs(hallway_dir_y)
    {
        step_count = xx ceil(abs(hallway_dir_x));
    }
    else
    {
        step_count = xx ceil(abs(hallway_dir_y));
    }

    delta_x := hallway_dir_x / step_count;
    delta_y := hallway_dir_y / step_count;

    x_value := hallway.start.x;
    y_value := hallway.start.y;

    idx: u32;
    old_id: u64;
    original_end := hallway.end;

    intersected_room: *Generation_Room;
    while idx <= step_count
    {
        last_working_hallway: *Generation_Hallway = hallway;
        new_hallway_end := (Vector2).{x_value, y_value};

        for *room: room_array
        {
            if AABB_is_point_within(new_hallway_end, room.bounding_box)
            {
                intersected_room = room;
                break;
            }
        }

        if intersected_room
        {
            //hallway.end = new_hallway_end - .{delta_x, delta_y};
            hallway.end = new_hallway_end;

            old_id := hallway.room_b_id;

            hallway.room_b_id = intersected_room.id;
            while idx <= step_count
            {
                new_hallway_end = .{x_value, y_value};
                if !AABB_is_point_within(new_hallway_end, intersected_room.bounding_box)
                {
                    break;
                }

                x_value += delta_x;
                y_value += delta_y;
                idx     += 1;
            }

            if idx > step_count
            {
                return;
            }

            // Create a new segment starting after the room
            new_segment: Generation_Hallway;
            new_segment.id        = segment_count + new_hallway_count.*;
            new_segment.type      = hallway.type;
            new_segment.is_valid  = true;
            new_segment.room_a_id = old_id;
            new_segment.room_b_id = intersected_room.id;
            new_segment.L_pair_id = hallway.L_pair_id;
            new_segment.start     = new_hallway_end;
            new_segment.end       = original_end;

            // Add to new_hallways
            array_add(new_hallways, new_segment);
            new_hallway_count.* += 1;

            // Recursively split the new segment
            new_hallway := *new_hallways.data[new_hallway_count.* - 1];
            world_gen_segment_hallways(new_hallway,
                                       room_array,
                                       new_hallways,
                                       segment_count,
                                       new_hallway_count);
            return;
        }

        x_value += delta_x;
        y_value += delta_y;
        idx     += 1;
    }
}

process_generation :: (arena: *Memory_Arena, draw_frame: *Draw_Frame_Data, time: Time_Data) -> bool
{
    finished := update_generation(draw_frame, time);
    if finished && !added
    {
        for *room: generation_rooms
        {
            room.solve_collision = false;
        }
        
        // NOTE(Sleepster): Calculate the mean room size 
        total_width: float32;
        total_height: float32;
        for *room: generation_rooms
        {
            room.position = v2_floor(room.position);
            
            total_width  += room.size.x;
            total_height += room.size.y;
        }

        mean_room_width  = total_width  / room_count;
        mean_room_height = total_height / room_count;

        // NOTE(Sleepster): Which rooms are main rooms?
        for *room: generation_rooms
        {
            if room.size.x > (mean_room_width * 1.25) && room.size.y > (mean_room_height * 1.25)
            {
                room.type          = .MAIN;
                main_room_counter += 1;
            }
        }

        // NOTE(Sleepster): Build the point list of the delaunay triangulation 
        inserted: u32;
        point_list = push_array(arena, Vector2, main_room_counter);
        for *room: generation_rooms
        {
            if room.type == .MAIN
            {
                point_list[inserted] = .{room.position.x + (room.size.x * 0.5), room.position.y + (room.size.y * 0.5)};
                inserted += 1;
            }
        }

        most_left_x  : float32;
        most_right_x : float32;
        highest_y    : float32;
        lowest_y     : float32;
        for *room: generation_rooms
        {
            most_left_x  = min(most_left_x,  room.position.x);
            most_right_x = max(most_right_x, room.position.x + room.size.x);
            lowest_y     = min(lowest_y,     room.position.y);
            highest_y    = max(highest_y,    room.position.y + room.size.y);
        }

        padding_x := most_right_x - most_left_x;
        padding_y := highest_y    - lowest_y;
        delta     := max(padding_x, padding_y) * 10;

        super_triangle.points[0]  = .{most_left_x   - delta,              lowest_y  - delta};
        super_triangle.points[1]  = .{most_right_x  + delta,              lowest_y  - delta};
        super_triangle.points[2]  = .{(most_right_x + most_left_x), highest_y + delta};

        super_triangle.edges[0] = cast(Delaunay_Triangle_Edge).{super_triangle.points[0], super_triangle.points[1], 0.0};
        super_triangle.edges[1] = cast(Delaunay_Triangle_Edge).{super_triangle.points[1], super_triangle.points[2], 0.0};
        super_triangle.edges[2] = cast(Delaunay_Triangle_Edge).{super_triangle.points[2], super_triangle.points[0], 0.0};

        // TODO(Sleepster): This is just here for debug, I want to see the algorithm work in real time. 
        if !added
        {
            for *triangle: triangulations
            {
                if triangle
                {
                    remove triangle;
                }
            }
            
            array_add(*triangulations, super_triangle);
            // TODO(Sleepster): return a triangle list 
            world_gen_triangulate();

            // take all of the points in each of the edges, remove duplicates.
            edges := push_array(arena, Delaunay_Triangle_Edge, xx (triangulations.count * 3));
            edges_inserted := 0;
            for *triangle: triangulations
            {
                for edge: triangle.edges
                {
                    broken := false;
                    for index: 0..edges_inserted - 1
                    {
                        array_edge := *edges[index];
                        if(edge.first_point == array_edge.first_point  && edge.second_point == array_edge.second_point) ||
                          (edge.first_point == array_edge.second_point && edge.second_point == array_edge.first_point)
                        {
                            broken = true;
                            break;
                        }
                    }
                    if !broken
                    {
                        edges[edges_inserted] = edge;
                        edges_inserted += 1;
                    }
                }
            }

            // Calculate the weight by taking the length of each edge
            for edge_index: 0..edges_inserted - 1
            {
                edge := *edges[edge_index];
                edge.edge_weight = sqrt(square(edge.second_point.x - edge.first_point.x) +
                                        square(edge.second_point.y - edge.first_point.y));
            }

            ////////////////////////
            // KRUSKAL'S ALGORITHM
            ////////////////////////
            
            // construct a list of shortest vectors.
            sorted_edges := push_array(arena, Delaunay_Triangle_Edge, xx(edges_inserted));
            edge_MST      = push_array(arena, Delaunay_Triangle_Edge, xx(edges_inserted));

            vertex_count: u32 = 0;
            unique_vertices := push_array(arena, *Vector2, xx(edges_inserted * 4));

            // NOTE(Sleepster): This is a terrible way of doing this, first_point and second point should just be an array... TOO BAD! 
            for edge_index: 0..edges_inserted - 1
            {
                edge := *edges[edge_index];

                first_point_unique  := true;
                second_point_unique := true;
                for vertex_index: 0..vertex_count - 1
                {
                    vertex := unique_vertices[vertex_index];
                    if vertex == *edge.first_point
                    {
                        first_point_unique = false;
                    }
                    else if vertex == *edge.second_point
                    {
                        second_point_unique = false;
                    }

                    if vertex_count == 0 break;
                }
                
                if first_point_unique
                {
                    unique_vertices[vertex_count] = *edge.first_point;
                    vertex_count += 1;
                }
                if second_point_unique
                {
                    unique_vertices[vertex_count] = *edge.second_point;
                    vertex_count += 1;
                }
            }

            memcpy(sorted_edges.data, edges.data, size_of(Delaunay_Triangle_Edge) * edges_inserted);
            quick_sort(sorted_edges, (A, B) => compare(B.edge_weight, A.edge_weight));

            union_find := push_array(arena, u32, vertex_count);
            for 0..vertex_count - 1
            {
                union_find[it] = it;
            }

            MST_index = 0;
            for edge_index: 0..edges_inserted - 1
            {
                edge := *sorted_edges[edge_index];
                first_index: u32;
                second_index: u32;
                for vertex_index: 0..vertex_count - 1
                {
                    if unique_vertices[vertex_index] == edge.first_point then  first_index  = vertex_index;
                    if unique_vertices[vertex_index] == edge.second_point then second_index = vertex_index;
                }

                if MST_find(union_find, first_index) != MST_find(union_find, second_index)
                {
                    edge_MST[MST_index] = edge;
                    MST_index += 1;

                    MST_union_set(union_find, first_index, second_index);
                }

                // NOTE(Sleepster): overflow 
                if MST_index == vertex_count - 1 break;
            }

            // remaining sorted edges that are not part of the MST are added back to the options
            remaining_edges := push_array(arena, Delaunay_Triangle_Edge, xx edges_inserted);
            remaining_edge_counter: u32;
            for edge: sorted_edges
            {
                is_unique: bool = true;
                for MST_edge: edge_MST
                {
                    if ((edge.first_point == MST_edge.first_point)  && (edge.second_point == MST_edge.second_point)) ||
                       ((edge.first_point == MST_edge.second_point) && (edge.second_point == MST_edge.first_point))
                    {
                        is_unique = false;
                    }
                }

                if is_unique
                {
                    remaining_edges[remaining_edge_counter] = edge;
                    remaining_edge_counter += 1;
                }
            }

            // add addtional leaves to the main tree by random chance
            added_rooms: u32;
            for index: 0..remaining_edge_counter - 1
            {
                if added_rooms < leaf_edges
                {
                    edge_to_check := remaining_edges[index];
                    chance := random_get_zero_to_one(); 
                    if chance > leaf_room_add_chance
                    {
                        edge_MST[MST_index] = edge_to_check;
                        MST_index   += 1;
                        added_rooms += 1;
                    }
                }
            }

            // MST_Nodes are the room centers
            // add rooms to new room set.

            // pick a pair of rooms that are connected via the MST
            // determine the TYPE of hallwall (vertical, horizontal, L)
            // widen the corridors by adding parrellel lines along the initial "hallway"
            // any rooms that overlap with the hallways are added to the room list
            // create a tile grid and fill in the empty spaces

            // TODO(Sleepster): Maybe we can make the segment count multiples of 1-3-5-7-etc 
            hallway_segments = push_array(arena, Generation_Hallway, xx (edges_inserted * 10));
            segment_count: u32 = 0;
            for *MST_edge: edge_MST
            {
                room_A: *Generation_Room;
                room_B: *Generation_Room;
                for *room: generation_rooms
                {
                    center_pos := (Vector2).{room.position.x + (room.size.x * 0.5), room.position.y + (room.size.y * 0.5)};
                    
                    if center_pos == MST_edge.first_point
                    {
                        room_A = room;
                    }

                    if center_pos == MST_edge.second_point
                    {
                        room_B = room;
                    } 
                }

                if room_A && room_B
                {
                    A_real_position := room_A.position + (room_A.size * 0.5);
                    B_real_position := room_B.position + (room_B.size * 0.5);
                    room_midpoint := (Vector2).{(A_real_position.x + B_real_position.x) * 0.5,
                                                (A_real_position.y + B_real_position.y) * 0.5};

                    room_A_ymin := room_A.position.y;
                    room_A_ymax := room_A.position.y + room_A.size.y;
                    room_B_ymin := room_B.position.y;
                    room_B_ymax := room_B.position.y + room_B.size.y;

                    y_overlap := (room_midpoint.y >= room_A_ymin && room_midpoint.y <= room_A_ymax) &&
                                 (room_midpoint.y >= room_B_ymin && room_midpoint.y <= room_B_ymax);

                    room_A_xmin := room_A.position.x;
                    room_A_xmax := room_A.position.x + room_A.size.x;
                    room_B_xmin := room_B.position.x;
                    room_B_xmax := room_B.position.x + room_B.size.x;

                    x_overlap := (room_midpoint.x >= room_A_xmin && room_midpoint.x <= room_A_xmax) &&
                                 (room_midpoint.x >= room_B_xmin && room_midpoint.x <= room_B_xmax);
                    if y_overlap
                    {
                        // horizontal hallway
                        xstart := min(A_real_position.x, B_real_position.x);
                        xend   := max(A_real_position.x, B_real_position.x);

                        new_segment := (Generation_Hallway).{segment_count,
                                                             .HORIZONTAL,
                                                             true,
                                                             (Vector2).{xstart, room_midpoint.y},
                                                             (Vector2).{xend, room_midpoint.y},
                                                             room_A.id,
                                                             room_B.id,
                                                             -1};
                        hallway_segments[segment_count] = new_segment;
                        segment_count += 1;

                    }
                    else if x_overlap
                    {
                        // vertical hallway
                        ystart := min(A_real_position.y, B_real_position.y);
                        yend   := max(A_real_position.y, B_real_position.y);

                        new_segment := (Generation_Hallway).{segment_count,
                                                             .VERTICAL,
                                                             true,
                                                             (Vector2).{room_midpoint.x, ystart},
                                                             (Vector2).{room_midpoint.x, yend},
                                                              room_A.id,
                                                             room_B.id,
                                                             -1};
                        hallway_segments[segment_count];
                        segment_count += 1;
                    }
                    else
                    {
                        // L-shaped hallway
                        corner_pos := (Vector2).{A_real_position.x, B_real_position.y};

                        // Vertical segment
                        vertical_hallway := (Generation_Hallway).{segment_count,
                                                                  .VERTICAL,
                                                                  true,
                                                                  (Vector2).{A_real_position.x, A_real_position.y},
                                                                  (Vector2).{A_real_position.x, B_real_position.y},
                                                                  room_A.id,
                                                                  room_B.id,
                                                                  -1};

                        horizontal_hallway := (Generation_Hallway).{segment_count + 1,
                                                                    .HORIZONTAL,
                                                                    true,
                                                                    (Vector2).{A_real_position.x, B_real_position.y},
                                                                    (Vector2).{B_real_position.x, B_real_position.y},
                                                                    room_A.id,
                                                                    room_B.id,
                                                                    -1};

                        vertical_hallway.L_pair_id          = segment_count + 1;
                        horizontal_hallway.L_pair_id        = segment_count;
                        hallway_segments[segment_count]     = vertical_hallway;
                        hallway_segments[segment_count + 1] = horizontal_hallway;

                        segment_count += 2;
                    }
                }
                else
                {
                    continue;
                }
            }
            hallway_segments.count = segment_count;


            //////////////////////////////
            // ROOM AND HALLWAY HANDLING
            //////////////////////////////

            for room_idx: 0..generation_rooms.count - 1
            {
                room := *generation_rooms[room_idx];
                if room.type == .NIL
                {
                    for hallway_idx: 0..hallway_segments.count - 1
                    {
                        // DDA
                        hallway := *hallway_segments[hallway_idx];

                        hallway_dir_x := hallway.end.x - hallway.start.x;
                        hallway_dir_y := hallway.end.y - hallway.start.y;

                        step_count: u32;
                        if abs(hallway_dir_x) >= abs(hallway_dir_y)
                        {
                            step_count = xx ceil(abs(hallway_dir_x));
                        }
                        else
                        {
                            step_count = xx ceil(abs(hallway_dir_y));
                        }

                        delta_x := hallway_dir_x / step_count;
                        delta_y := hallway_dir_y / step_count;

                        x_value := hallway.start.x;
                        y_value := hallway.start.y;

                        idx: u32;
                        while idx <= step_count
                        {
                            if AABB_is_point_within(.{x_value, y_value}, room.bounding_box)
                            {
                                room.type = .LESSER;
                            }
                            
                            x_value += delta_x;
                            y_value += delta_y;
                            idx     += 1;
                        }
                    }
                }
            }

            // copy the valid rooms to the new array
            valid_room_count: u32;
            for *room: generation_rooms
            {
                if room.type == .LESSER || room.type == .MAIN
                {
                    valid_room_count += 1;
                }
            }

            rooms_copied: u32;
            new_rooms := push_array(arena, Generation_Room, valid_room_count);
            for *room: generation_rooms
            {
                if room.type == .LESSER || room.type == .MAIN
                {
                    room.idx = rooms_copied;
                    memcpy(cast(*u8)new_rooms.data + (size_of(Generation_Room) * rooms_copied), room, size_of(Generation_Room));
                    rooms_copied += 1;
                }
            }

            generation_rooms.data  = new_rooms.data;
            generation_rooms.count = valid_room_count;

            // clipping start to just outside the rooms
            for room_idx: 0..generation_rooms.count - 1
            {
                room := *generation_rooms[room_idx];
                for hallway_idx: 0..hallway_segments.count - 1
                {
                    // DDA
                    hallway       := *hallway_segments[hallway_idx];
                    hallway_dir_x := hallway.end.x - hallway.start.x;
                    hallway_dir_y := hallway.end.y - hallway.start.y;

                    step_count: u32;
                    if abs(hallway_dir_x) >= abs(hallway_dir_y)
                    {
                        step_count = xx ceil(abs(hallway_dir_x));
                    }
                    else
                    {
                        step_count = xx ceil(abs(hallway_dir_y));
                    }

                    delta_x := hallway_dir_x / step_count;
                    delta_y := hallway_dir_y / step_count;

                    x_value := hallway.start.x;
                    y_value := hallway.start.y;

                    idx: u32;
                    while idx <= step_count
                    {
                        new_hallway_vector := (Vector2).{x_value, y_value};
                        if !AABB_is_point_within(new_hallway_vector, room.bounding_box)
                        {
                            hallway.start = new_hallway_vector;
                            break;
                        }
                        
                        x_value += delta_x;
                        y_value += delta_y;
                        idx     += 1;
                    }
                }
            }

            // clipping end to just outside the rooms
            for room_idx: 0..generation_rooms.count - 1
            {
                room := *generation_rooms[room_idx];
                for hallway_idx: 0..hallway_segments.count - 1
                {
                    // DDA
                    hallway       := *hallway_segments[hallway_idx];
                    hallway_dir_x := hallway.end.x - hallway.start.x;
                    hallway_dir_y := hallway.end.y - hallway.start.y;

                    step_count: u32;
                    if abs(hallway_dir_x) >= abs(hallway_dir_y)
                    {
                        step_count = xx ceil(abs(hallway_dir_x));
                    }
                    else
                    {
                        step_count = xx ceil(abs(hallway_dir_y));
                    }

                    delta_x := (hallway_dir_x / step_count) * -1;
                    delta_y := (hallway_dir_y / step_count) * -1;

                    x_value := hallway.end.x;
                    y_value := hallway.end.y;

                    idx: u32;
                    while idx <= step_count
                    {
                        new_hallway_vector := (Vector2).{x_value, y_value};
                        if !AABB_is_point_within(new_hallway_vector, room.bounding_box)
                        {
                            hallway.end = new_hallway_vector;
                            break;
                        }
                        
                        x_value += delta_x;
                        y_value += delta_y;
                        idx     += 1;
                    }
                }
            }

            // traverse the segment, clipping it to the first intercepted room. Then creating another segment to continue the rest of the way
            new_hallways: [..]Generation_Hallway;
            new_hallway_counter: u32;
            defer array_free(new_hallways);
            for *hallway: hallway_segments 
            {
                world_gen_segment_hallways(hallway, generation_rooms, *new_hallways, segment_count, *new_hallway_counter);
            }

            //validate
            {
                for *hallway: hallway_segments
                {
                    length := sqrt(square(hallway.end.x - hallway.start.x) + square(hallway.end.y - hallway.start.y));
                    if length < HALLWAY_DIST_EPSILON
                    {
                        hallway.is_valid = false;
                    }
                }

                for *hallway: new_hallways
                {
                    is_horizontal := hallway.start.y == hallway.end.y;

                    length := sqrt(square(hallway.end.x - hallway.start.x) + square(hallway.end.y - hallway.start.y));
                    if length < HALLWAY_DIST_EPSILON
                    {
                        hallway.is_valid = false;
                    }
                }
            }

            // Copy valid segments to final set
            to_remove: u32;
            copied: u32 = 0;
            final_hallway_set := push_array(arena, Generation_Hallway, xx(hallway_segments.count + new_hallway_counter));
            for *segment: hallway_segments
            {
                if segment
                {
                    if segment.is_valid
                    {
                        memcpy(cast(*u8)final_hallway_set.data + (copied * size_of(Generation_Hallway)),
                               segment,
                               size_of(Generation_Hallway));
                        copied += 1;
                    }
                    else
                    {
                        to_remove += 1;
                    }
                }
            }

            for *segment: new_hallways 
            {
                if segment
                {
                    if segment.is_valid
                    {
                        memcpy(cast(*u8)final_hallway_set.data + (copied * size_of(Generation_Hallway)),
                               segment,
                               size_of(Generation_Hallway));
                        copied += 1;
                    }
                    else
                    {
                        to_remove += 1;
                    }
                }
            }

            hallway_segments.data = final_hallway_set.data;
            hallway_segments.count = final_hallway_set.count - to_remove;

            // floor to turn the hallways into generation rooms
            {
                for *room: generation_rooms
                {
                    room.position = v2_round(room.position);
                    room.bounding_box.min = room.position;
                    room.bounding_box.max = room.position + room.size;

                    x := 0;
                }

                for *hallway: hallway_segments
                {
                    hallway.start = v2_round(hallway.start);
                    hallway.end = v2_round(hallway.end);

                    x := 0;
                }
            }

            // // FINALLY turn them into rooms.
            hallway_rooms := push_array(arena, Generation_Room, xx hallway_segments.count);
            new_room_counter: u64;
            for *hallway: hallway_segments
            {
                new_room: Generation_Room;
                new_room.type = .HALLWAY;
                new_room.id = xx generation_rooms.count + new_room_counter;
                new_room.idx = new_room.id;
                new_room.solve_collision = false;

                dx := hallway.end.x - hallway.start.x;
                dy := hallway.end.y - hallway.start.y;
                length := sqrt(square(dx) + square(dy));

                hallway_width := 5.0;

                new_room.size = ifx abs(dx) >= abs(dy) then
                                (Vector2).{length, hallway_width} else
                                (Vector2).{hallway_width, length};

                if dx < 0 || dy < 0
                {
                    new_room.position = ifx dx < 0 then hallway.end else hallway.start;
                    new_room.position.y = ifx dy < 0 then hallway.end.y else hallway.start.y;
                }
                else
                {
                    new_room.position = hallway.start;
                }

                new_room.bounding_box.min = new_room.position;
                new_room.bounding_box.max = new_room.position + new_room.size;

                hallway_rooms[new_room_counter] = new_room;
                new_room_counter += 1;
            }

            // merge the hallway rooms and the main rooms into one array
            last_room_array := push_array(arena, Generation_Room, xx(generation_rooms.count + hallway_segments.count));
            {
                copied: u32;
                for *room: generation_rooms
                {
                    memcpy(cast(*u8)last_room_array.data + (copied * size_of(Generation_Room)),
                           room,
                           size_of(Generation_Room));
                    copied += 1;
                }

                for *hallway: hallway_rooms
                {
                    memcpy(cast(*u8)last_room_array.data + (copied * size_of(Generation_Room)),
                           hallway,
                           size_of(Generation_Room));
                    copied += 1;
                }
            }

            generation_rooms.data  = last_room_array.data;
            generation_rooms.count = last_room_array.count;

            // TODO(Sleepster): bugged???? 
            // for *room: generation_rooms
            // {
            //     parent_hallway: *Generation_Hallway;
            //     for *hallway: hallway_segments
            //     {
            //         if hallway.room_a_id == room.id && hallway.room_b_id != room.id
            //         {
            //             parent_hallway = hallway;
            //         }
            //     }

            //     if parent_hallway == null
            //     {
            //         print("[ERROR]: room '%' does is not claimed by any segment...\n", room.id);
            //     }
            // }

            /*
            // TODO(Sleepster):  
                - [x] Modify the segments so that they are able to store the rooms that they are connecting
                - [x] Cull the hallways so that the grid cells that their segments travel through are instead left to the room they intersect with, not the hallway
                - [x] Turn the hallways into their own generation rooms 
                - [x] add the hallways to the generation room list with a random size from a table of widths (3, 5, 7, 9, 11)
                - [ ] (stretch goal 1) have the rooms feed through the WFC algorithm
                - [ ] (stretch goal 2) think of a way to make the rooms have precollapsed cells based on their neighboring rooms
            */

            added = true;
        }
    }
    return finished;
}

draw_generation :: (draw_frame: *Draw_Frame_Data)
{
    // for segment_index: 0..hallway_segments.count - 1
    // {
    //     segment := *hallway_segments[segment_index];
    //     if segment && segment.is_valid
    //     {
    //         direction := segment.end - segment.start;
    //         length    := sqrt(direction.x * direction.x + direction.y * direction.y);
    //         thickness := (iVector2).{cast(s32)(tile_size.x * 0.25), cast(s32)(tile_size.y * 0.25)};
            
    //         step_count  := cast(s32)length + 1;
    //         step_vector := direction / length;
            
    //         for step_index: 0..step_count - 1
    //         {
    //             color: Vector4 = ORANGE;
    //             position    := segment.start + step_vector * cast(float32)step_index;
    //             render_size := (iVector2).{thickness.x, thickness.y}; 
    //             if position == segment.start && step_index == 0
    //             {
    //                 color = CYAN;
    //             }
    //             else if position == segment.end
    //             {
    //                 color = PURPLE;
    //             }
                
    //             draw_texture(draw_frame, position - (Vector2).{cast(float32)thickness.x / 2, cast(float32)thickness.y / 2}, render_size, sprite_textureless, color);
    //         }
    //     }
    // }

    // for index: 0..MST_index - 1
    // {
    //     if MST_index == 0 break;

    //     edge := edge_MST[index];
    //     draw_texture(draw_frame, v2_floor(edge.first_point) - .{1, 1}, .{5, 5}, sprite_outline, ORANGE);
    //     draw_texture(draw_frame, v2_floor(edge.second_point) - .{1, 1}, .{3, 3}, sprite_outline, BLUE);
    // }

    for *A: generation_rooms
    {
        if A != null
        {
            color: Vector4;
            if A.type == .MAIN
            {
                color = RED;
            }
            else if A.type == .LESSER
            {
                color = BLUE;
            }
            else
            {
                color = WHITE;
            }
            
            draw_texture(draw_frame, v2_floor(A.position), iv2_cast(A.size), sprite_outline, color);
        }
    }
}

#scope_file
tile_size: iVector2 = .{16, 16};
generation_rooms: []Generation_Room;

update_radius := 20.0;
epsilon       := 0.1;

room_count    := 150;
leaf_edges    := 40;
leaf_room_add_chance := 0.32;

mean_room_width : float32;
mean_room_height: float32;

point_list: []Vector2;
main_room_counter: u32;

// TODO(Sleepster): I'm Lazy... 
super_triangle: Delaunay_Triangle; 
triangulations: [..]Delaunay_Triangle;

edge_MST      : []Delaunay_Triangle_Edge; 
MST_index     : u32;

hallway_segments: []Generation_Hallway;

dungeon_grid: [][]World_Gen_Grid_Square;
dungeon_grid_width  : u32;
dungeon_grid_height : u32;

HALLWAY_DIST_EPSILON :: 0.04;

added: bool;
