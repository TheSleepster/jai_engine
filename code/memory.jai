#if OS == .WINDOWS
{
    W :: #import "Windows";
    platform_allocate_memory :: inline (size: u64) -> *void
    {
        data := W.VirtualAlloc(null, xx size, W.MEM_COMMIT|W.MEM_RESERVE, W.PAGE_READWRITE);
        //log("[INFO]: Virtual alloc called with a size of: %mb\n", cast(float32)(size / 1048576.0));
        return data;
    }

    platform_deallocate_memory :: (data: *void, size: u64)
    {
        W.VirtualFree(data, 0, W.MEM_RELEASE);
    }
}
#if OS == .LINUX
{
    P :: #import "POSIX";

    platform_allocate_memory :: inline (size: u64) -> *void
    {
        data := P.mmap(null, size, P.PROT_READ|P.PROT_WRITE, P.MAP_PRIVATE|P.MAP_ANONYMOUS, -1, 0);
        log("[INFO]: mmap called with a size of: %mb\n", cast(float32)(size / 1048576.0));
        return data;
    }

    platform_deallocate_memory :: inline (data: *void, size: u64)
    {
        P.munmap(data, size);
    }
}

Memory_Arena_Footer :: struct
{
    last_used      :  u64;
    last_capacity  :  u64;
    last_base      : *u8;
};

Scratch_Arena :: struct
{
    parent_arena : *Memory_Arena;
    parent_base  : *u8;
    memory_used  :  u64;
};

Memory_Arena :: struct
{
    base               : *u8;
    used               :  u64;
    capacity           :  u64;

    minimum_block_size :  u32;
    block_count        :  u32;
    scratch_count      :  s32;
};

init_arena :: (minimum_block_size: u64) -> Memory_Arena
{
    result: Memory_Arena = ---;
    result.base          = null;
    result.used          = 0;
    result.capacity      = 0;
    result.scratch_count = 0;
    result.block_count   = 0;
    result.minimum_block_size = xx minimum_block_size;

    return result;
}

init_arena :: (base: *void, capacity: u64) -> Memory_Arena
{
    result: Memory_Arena;
    result.base     = cast(*u8)base;
    result.capacity = capacity;
    result.used     = 0;

    return result;
}

bootstrap_allocate_struct :: inline ($bootstrap: Type, offset: s64, minimum_block_size: u32 = 0) -> *bootstrap
{
    bootstrap_arena: Memory_Arena;
    bootstrap_arena.minimum_block_size = minimum_block_size;
    bootstrap_struct := push_struct(*bootstrap_arena, bootstrap);

    (cast(*Memory_Arena)(bootstrap_struct + offset)).* = bootstrap_arena;

    return bootstrap_struct;
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

get_effective_allocation_size :: (arena: *Memory_Arena, allocation_size: u32, alignment_offset: u32 = 4) -> u32
{
    result := allocation_size;
    offset := get_alignment_offset(arena, alignment_offset);
    
    result += xx offset;
    return result;
}

get_footer :: inline (arena: *Memory_Arena) -> *Memory_Arena_Footer
{
    result := cast(*Memory_Arena_Footer)(arena.base + arena.capacity);
    return result;
}

push_size :: (arena: *Memory_Arena, size_init: s64, alignment: u32 = 4) -> *void
{
    result: *void;
    
    size := get_effective_allocation_size(arena, xx size_init, alignment);
    if (arena.used + size) > arena.capacity
    {
        if !arena.minimum_block_size
        {
            arena.minimum_block_size = cast(u32)MB(1);
        }

        save: Memory_Arena_Footer;
        save.last_base     = arena.base;
        save.last_capacity = arena.capacity;
        save.last_used     = arena.used;
        
        size = xx size_init;
        new_block_size := ifx size > (arena.minimum_block_size + size_of(Memory_Arena_Footer)) then size else arena.minimum_block_size; 

        arena.capacity     = new_block_size - size_of(Memory_Arena_Footer);
        arena.base         = platform_allocate_memory(new_block_size);
        arena.used         = 0;
        arena.block_count += 1;

        footer  := get_footer(arena);
        footer.* = save;
    }
    assert((arena.used + size) <= arena.capacity);
    assert(size >= size_init);

    alignment_offset := get_alignment_offset(arena, alignment);
    result      = (arena.base + arena.used + alignment_offset);
    arena.used += size;
    return result;
}

push_struct :: inline (arena: *Memory_Arena, $T: Type, alignment: u32 = 4) -> *T
{
    result := push_size(arena, size_of(T), alignment);
    return result;
}

push_array :: inline (arena: *Memory_Arena, $T: Type, count: u32, alignment: u32 = 4) -> []T
{
    result: []T;
    result.data  = push_size(arena, size_of(T) * count, alignment);
    result.count = count;

    return result;
}

begin_temporary_block :: (arena : *Memory_Arena) -> Scratch_Arena
{
    result: Scratch_Arena;
    result.parent_arena   = arena;
    result.parent_base    = arena.base;
    result.memory_used    = arena.used;

    arena.scratch_count += 1;
    return result;
}

free_last_block :: inline (arena: *Memory_Arena)
{
    free          := cast(*void)arena.base; 
    old_capacity  := arena.capacity;

    memory_footer     := get_footer(arena);
    arena.base         = memory_footer.last_base;
    arena.used         = memory_footer.last_used;
    arena.capacity     = memory_footer.last_capacity;

    platform_deallocate_memory(free, old_capacity);
    arena.block_count -= 1;
}

end_temporary_block :: (scratch: *Scratch_Arena)
{
    arena := scratch.parent_arena;
    while arena.base != scratch.parent_base
    {
        free_last_block(arena);
        log("[INFO]: [end_temporary_block]: Block freed...\n");
    }

    assert(arena.used >= scratch.memory_used);

    arena.used = scratch.memory_used;
    arena.base = scratch.parent_base;
    arena.scratch_count -= 1;
}

reset_arena :: (arena: *Memory_Arena)
{
    while arena.block_count > 0
    {
        free_last_block(arena);
        log("[INFO]: [reset_arena]: Block freed...\n");
    }
    arena.used          = 0;
    arena.scratch_count = 0;
}

push_temp_array :: ($T: Type, count: u32) -> []T
{
    result: []T;
    result.data  = talloc(size_of(T) * count);
    result.count = count;

    return result;
}

