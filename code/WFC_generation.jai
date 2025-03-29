/*
// NOTE(Sleepster): the idea for the bitmask on the states_left and
the cell_rules is that each bit in the bitset indicates whether the
item at the index of the bit (bit 0, bit 1, bit 2, etc...) is a valid
option for the next cell. If the bit is 0, then it is NOT a valid
option and should be removed from the array of options in the
states_left array. If it's 1, then it's still a valid option and we
should keep it.
*/

WFC_Cell_Ruleset :: struct
{
    left  : u32;
    right : u32;
    up    : u32;
    down  : u32;
};

WFC_Chunk_Cell :: struct
{
    is_collapsed      : bool;
    cell_sprite_index : s32;

    // bitset of remaining options, they are indices into the parent sprites[] array
    remaining_options : u32;
};

WFC_Chunk_Data :: struct
{
    chunk_size : u32;
    atlas      : Atlas_Sprite;
    sprites    : []Atlas_Sprite;

    // bitset array for describing the rules of each sprite
    chunk_rules: []WFC_Cell_Ruleset;
    cells      : []WFC_Chunk_Cell;

    chunk_arena : Memory_Arena;
};

WFC_init :: (arena: *Memory_Arena, chunk_dim: u32, tile_sprites: []Atlas_Sprite, rule_bitsets: []WFC_Cell_Ruleset) -> WFC_Chunk_Data
{
    chunk: WFC_Chunk_Data;
    chunk.chunk_size  = chunk_dim;
    chunk.chunk_rules = rule_bitsets;
    chunk.sprites     = tile_sprites;
    chunk.cells       = push_array(arena, WFC_Chunk_Cell, (chunk_dim * chunk_dim));

    for cell_index: 0..(chunk_dim * chunk_dim) - 1
    {
        cell := *chunk.cells[cell_index];
        cell.cell_sprite_index = -1;
        cell.remaining_options = cast(u32)((1 << tile_sprites.count) - 1);
    }

    return chunk;
}

WFC_generate :: (chunk: *WFC_Chunk_Data)
{
}
