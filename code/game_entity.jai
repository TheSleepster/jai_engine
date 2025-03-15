Entity_Manager :: struct
{
    active_entity_counter : u32;
    entities              : [MAX_ENTITIES]Entity;
};

using entity_flags :: enum u64
{
    IS_VALID             :: 1 << 0;
    IS_GRABBABLE         :: 1 << 1;
    CAN_BE_DAMAGED       :: 1 << 2;
    DROPS_ITEMS_ON_DEATH :: 1 << 3;
    IS_DEAD              :: 1 << 4;
    CAN_BE_PICKED_UP     :: 1 << 5;
    IS_ITEM              :: 1 << 6;
    CAN_PICKUP_ITEMS     :: 1 << 7;
};

entity_archetype :: enum 
{
    NIL;
    PLAYER;
    CRATE;
    STONE_NODE;
    COAL_NODE;
    TREE00;
    FURNACE;
    CRAFTING_STATION;

    ITEM_STONE_CHUNK;
    ITEM_COAL_CHUNK;
    ITEM_WOOD_CHUNK;
    ARCH_COUNT;
};

Entity_Drop :: struct
{
    dropped_entity : entity_archetype;
    amount_to_drop : u32;
};

Entity :: struct
{
    entity_id       :  u32;
    archetype       :  entity_archetype;
    flags           :  u64;

    prev_position   :  Vector2;
    position        :  Vector2;
    speed           :  float32;
    friction        :  float32;
    
    render_size     :  Vector2;
    draw_color      :  Vector4;
    sprite_data     : *Atlas_Sprite;

    attached_entity : *Entity;
    direction       :  Vector2;

    bounding_box    :  Range_V2;

    current_health  :  s32;
    max_health      :  s32;

    drop_list       : [..] Entity_Drop;
    max_drop_radius : float32;
};

create_entity :: (entity_manager: *Entity_Manager) -> *Entity
{
    result  : *Entity;
    success :  bool;
    for entity_index: 0..entity_manager.active_entity_counter
    {
        found := *entity_manager.entities[entity_index];
        if !(found.flags & xx IS_VALID)
        {
            result = found;
            result.flags |= xx IS_VALID;
            result.entity_id = entity_index;
            entity_manager.active_entity_counter += 1;

            success = true;
            break;
        }
    }
    assert(success);
    return result;
}

destroy_entity :: (entity: *$T)
{
    memset(entity, 0, size_of(T));
}

get_player :: (entity_manager: *Entity_Manager) -> *Entity
{
    player: *Entity;
    for entity_index: 0..entity_manager.active_entity_counter
    {
        found := *entity_manager.entities[entity_index];
        if (found.flags & xx IS_VALID) && found.archetype == xx entity_archetype.PLAYER
        {
            player = found;
            break;
        }
    }
    return player;
}

setup_entity_player :: (player: *Entity)
{
    player.sprite_data    = sprite_player;
    player.archetype      = xx entity_archetype.PLAYER;
    player.speed          = 10.0;
    player.friction       = 0.1;
    player.draw_color     = WHITE;
    player.render_size    = (Vector2).{xx sprite_player.atlas_size.x, xx sprite_player.atlas_size.y};
    player.flags         |= xx CAN_BE_DAMAGED|CAN_PICKUP_ITEMS;
    player.bounding_box   = range_v2_create(player.position, player.position + player.render_size);
    player.max_health     = 10;
    player.current_health = player.max_health;
}

setup_entity_build_crate :: (entity: *Entity)
{
    entity.sprite_data    = sprite_base_block;
    entity.archetype      = xx entity_archetype.CRATE;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_base_block.atlas_size.x, xx sprite_base_block.atlas_size.y};
    entity.flags         |= xx IS_GRABBABLE| xx CAN_BE_DAMAGED;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health     = 10;
    entity.current_health = entity.max_health;
}

setup_entity_furnace_block :: (entity: *Entity)
{
    entity.sprite_data    = sprite_furnace;
    entity.archetype      = xx entity_archetype.FURNACE;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_furnace.atlas_size.x, xx sprite_furnace.atlas_size.y};;
    entity.flags         |= xx IS_GRABBABLE| xx CAN_BE_DAMAGED;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health     = 30;
    entity.current_health = entity.max_health;
}

setup_entity_stone_node :: (entity: *Entity)
{
    entity.sprite_data     = sprite_stone_node;
    entity.archetype       = xx entity_archetype.STONE_NODE;
    entity.draw_color      = WHITE;
    entity.render_size    = (Vector2).{xx sprite_stone_node.atlas_size.x, xx sprite_stone_node.atlas_size.y};;
    entity.flags          |= xx CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH;
    entity.bounding_box    = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health      = 5;
    entity.current_health  = entity.max_health;
    entity.max_drop_radius = 5;

    item_drop: Entity_Drop;
    item_drop.dropped_entity = xx entity_archetype.ITEM_STONE_CHUNK;
    item_drop.amount_to_drop = 2;

    array_add(*entity.drop_list, item_drop);
}

setup_entity_coal_node :: (entity: *Entity)
{
    entity.sprite_data    = sprite_coal_node;
    entity.archetype      = xx entity_archetype.COAL_NODE;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_coal_node.atlas_size.x, xx sprite_coal_node.atlas_size.y};;
    entity.flags         |= xx CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health     = 5;
    entity.current_health = entity.max_health;
    entity.max_drop_radius = 5;

    item_drop: Entity_Drop;
    item_drop.dropped_entity = xx entity_archetype.ITEM_COAL_CHUNK;
    item_drop.amount_to_drop = 1;

    array_add(*entity.drop_list, item_drop);
}

setup_entity_tree_00 :: (entity: *Entity)
{
    entity.sprite_data    = sprite_tree_00;
    entity.archetype      = xx entity_archetype.TREE00;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_tree_00.atlas_size.x, xx sprite_tree_00.atlas_size.y};;
    entity.flags         |= xx CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health     = 5;
    entity.current_health = entity.max_health;
    entity.max_drop_radius = 5;

    item_drop: Entity_Drop;
    item_drop.dropped_entity = xx entity_archetype.ITEM_WOOD_CHUNK;
    item_drop.amount_to_drop = 1;

    array_add(*entity.drop_list, item_drop);
}

setup_entity_workbench :: (entity: *Entity)
{
    entity.sprite_data    = sprite_workbench;
    entity.archetype      = xx entity_archetype.CRAFTING_STATION;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_workbench.atlas_size.x, xx sprite_workbench.atlas_size.y};;
    entity.flags         |= xx IS_GRABBABLE;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
    entity.max_health     = 10;
    entity.current_health = entity.max_health;
}

setup_entity_item_stone_chunk :: (entity: *Entity)
{
    entity.sprite_data    = sprite_stone_chunk;
    entity.archetype      = xx entity_archetype.ITEM_STONE_CHUNK;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_stone_chunk.atlas_size.x, xx sprite_stone_chunk.atlas_size.y};;
    entity.flags         |= xx IS_ITEM;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
}

setup_entity_item_coal_chunk :: (entity: *Entity)
{
    entity.sprite_data    = sprite_coal_chunk;
    entity.archetype      = xx entity_archetype.ITEM_COAL_CHUNK;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_coal_chunk.atlas_size.x, xx sprite_coal_chunk.atlas_size.y};;
    entity.flags         |= xx IS_ITEM;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
}

setup_entity_item_wood_chunk :: (entity: *Entity)
{
    entity.sprite_data    = sprite_wood_chunk;
    entity.archetype      = xx entity_archetype.ITEM_WOOD_CHUNK;
    entity.draw_color     = WHITE;
    entity.render_size    = (Vector2).{xx sprite_wood_chunk.atlas_size.x, xx sprite_wood_chunk.atlas_size.y};;
    entity.flags         |= xx IS_ITEM;
    entity.bounding_box   = range_v2_create(entity.position, entity.position + entity.render_size);
}

// TODO(Sleepster): Keep an eye on performance with this... should be fine, but you never know 
spawn_entity :: inline (entity_manager: *Entity_Manager, kind: entity_archetype) -> *Entity
{
    entity := create_entity(entity_manager);
    setup_proc := entity_setup_table[kind];
    if setup_proc != null
    {
        setup_proc(entity);
    }

    return entity;
}

entity_check_direction :: (entity: *Entity, new_pos: Vector2)
{
    // NOTE(Sleepster): If you look here in the future and
    // go "what idiot made the x's flipped?" it's actually no
    // one's fault. This is just the way it works.

    // TODO(Sleepster): maybe replace atan2 
    direction := atan2(new_pos.y, new_pos.x);
    if direction == 0.0 then direction = -PI;

    half_pi := PI * 0.5;
    if abs(direction) == half_pi 
    {
        ifx direction == half_pi then entity.direction = .{0, 1} else entity.direction = .{0, -1};
    }
    else if abs(direction) == PI

    {
        ifx direction == PI then entity.direction = .{-1, 0} else entity.direction = .{1, 0};
    }
}
