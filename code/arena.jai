#if OS == .WINDOWS
{
    W :: #import "Windows";
    my_alloc :: inline (size: u64) -> *void
    {
        data := W.VirtualAlloc(null, xx size, W.MEM_COMMIT|W.MEM_RESERVE, W.PAGE_READWRITE);
        return data;
    }
}

// NOTE(Sleepster): Helpers
/////////////////////////////////////////
KB :: (value : u64) -> u64 #expand
{
    return value * 1000;
}

MB :: (value : u64) -> u64 #expand
{
    return KB(value) * 1000;
}

GB :: (value : u64) -> u64 #expand
{
    return MB(value) * 1000;
}
/////////////////////////////////////////

Memory_Block :: struct
{
    block_data   : *void;
    block_offset : *u8;
    block_size   :  u64;
};

Memory_Arena :: struct
{
    capacity      :  s64;
    used          :  s64;
    base          : *u8;
    parent_block  : *Memory_Block;

    scratch_count : s32;
};

Scratch_Arena :: struct
{
    parent_arena : *Memory_Arena;
    memory_used  :  s64;
};

init_memory_block :: (size: u64) -> Memory_Block
{
    result: Memory_Block;
    result.block_size   = size;
    result.block_data   = my_alloc(xx size);
    result.block_offset = cast(*u8)result.block_data;
    return result;
}

init_arena :: (block: *Memory_Block, size: s64) -> Memory_Arena
{
    arena: Memory_Arena;
    assert(size <= xx block.block_size);
    assert(block.block_offset + size <= block.block_offset + block.block_size);

    arena.capacity     = size;
    arena.base         = cast(*u8)block.block_offset;
    arena.used         = 0;
    arena.parent_block = block;

    block.block_offset += arena.capacity;
    return arena;
}

get_alignment_offset :: (arena: *Memory_Arena, alignment: u32 = 4) -> u64
{
    offset: u32 = cast(u32)(arena.base + arena.used);
    alignment_mask := alignment - 1;

    alignment_offset: u64 = 0;
    if offset & alignment_mask
    {
        alignment_offset = alignment - (offset & alignment_mask);
    }
    return alignment_offset;
}

push_size :: (arena: *Memory_Arena, size: s64, alignment: u32 = 4) -> *void
{
    alignment_offset := get_alignment_offset(arena, alignment);
    size += xx alignment_offset;
    assert((arena.used + size) <= arena.capacity);

    result: *void = (arena.base + arena.used + alignment_offset);
    arena.used += size;

    return result;
}

push_element :: inline (arena: *Memory_Arena, $T: Type, alignment: u32 = 4) -> *T
{
    result := push_size(arena, size_of(T), alignment);
    return result;
}

push_array :: inline (arena: *Memory_Arena, $T : Type, count: int, alignment: u32 = 4) -> []T
{
    result: []T;
    result.data  = push_size(arena, size_of(T) * count, alignment);
    result.count = count;

    return result;
}

get_scratch_memory :: (arena : *Memory_Arena) -> Scratch_Arena
{
    result: Scratch_Arena;
    result.parent_arena   = arena;
    result.memory_used    = arena.used;

    arena.scratch_count += 1;
    return result;
}

restore_from_scratch :: (scratch: *Scratch_Arena)
{
    arena := scratch.parent_arena;
    assert(arena.used >= scratch.memory_used);
    assert(arena.scratch_count > 0);

    arena.used = scratch.memory_used;
    arena -= 1;
}

init_child_arena :: inline (arena: *Memory_Arena, child_capacity: s64, alignment: u32 = 4) -> Memory_Arena
{
    result: Memory_Arena;
    result.capacity = child_capacity;
    result.base     = push_size(arena, child_capacity, alignment);

    return result;
}

reset_arena :: (arena: *Memory_Arena)
{
    arena.used = 0;
}


