Entity_Manager :: struct
{
    active_entity_counter : u32;
    entities              : []Entity;
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
    INVENTORY_FULL       :: 1 << 8;
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
    WORKBENCH;

    ITEM_STONE_CHUNK;
    ITEM_COAL_CHUNK;
    ITEM_WOOD_CHUNK;
    ARCH_COUNT;
};

Entity_Drop :: struct
{
    dropped_item   : Item_ID; 
    amount_to_drop : u32;
};

Entity_Inventory_Slot :: struct
{
    item_in_slot : Item_ID;
    quantity     : u32;
};

Entity :: struct
{
    entity_id       :  u32;
    archetype       :  entity_archetype;
    flags           :  u64;

    position        :  Vector2;
    target_position :  Vector2;
    speed           :  float32;
    friction        :  float32;
    
    render_size     :  iVector2;
    draw_color      :  Vector4;
    sprite_data     : *Sprite2D;

    attached_entity : *Entity;
    direction       :  Vector2;

    bounding_box    :  AABB;

    current_health  :  s32;
    max_health      :  s32;

    drop_list       :  []Entity_Drop;
    max_drop_radius :  float32;
    pickup_delay    :  float32;
    pickup_timer    :  float32;

    inventory       :  [20]Entity_Inventory_Slot;
    used_slots      :  u32;
    max_slots       :  u32 = 20;

    drop_id         :  Item_ID;
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

add_to_entity_inventory :: (game_state: *Game_State, entity: *Entity, item_id: Item_ID, count: u32) -> bool
{
    result: bool;
    if entity.used_slots + 1 > entity.max_slots
    {
        return result;
    }
    
    if !(entity.flags & xx INVENTORY_FULL)
    {
        active_slot: *Entity_Inventory_Slot;
        item_data  := *game_state.game_data.item_data[item_id];
        
        for *slot: entity.inventory
        {
            if slot.item_in_slot == item_id &&
                slot.quantity     <= item_data.max_stack
            {
                active_slot = slot;
                break;
            }
        }

        if active_slot
        {
            active_slot.quantity += count;
            result = true;
        }

        if !active_slot && entity.used_slots + 1 <= entity.max_slots
        {
            active_slot = *entity.inventory[entity.used_slots];
            active_slot.item_in_slot = item_id;
            active_slot.quantity     = count;
            result = true;

            entity.used_slots += 1;
        }
    }

    return result;
}
