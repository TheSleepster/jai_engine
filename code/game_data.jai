using Item_ID :: enum
{
    item_null;
    item_stone_chunk;
    item_coal_chunk;
    item_wood_chunk;
    item_count;
};

using Entity_ID :: enum
{
    entity_null;
    entity_player;
    entity_build_crate;
    entity_stone_node;
    entity_coal_node;
    entity_tree00;
    entity_furnace;
    entity_workbench;
    entity_count;
};

Entity_Data_Entry :: struct
{
    ID              :  Entity_ID;
    entity_arch     :  entity_archetype;
    flags           :  u64;
    sprite          :  Atlas_Sprite;
    speed           :  float32;
    friction        :  float32;
    max_health      :  s32;
    drop_list       :  []Entity_Drop;
    drop_count      :  s32;
    max_drop_radius :  float32;
    pickup_delay    :  float32;
    drop_id         :  Item_ID;
};

Item_Data_Entry :: struct
{
    ID                 :  Item_ID;
    entity_arch        :  entity_archetype;
    name               :  string;
    description        :  string;
    sprite             :  Atlas_Sprite;
    flags_when_dropped :  u64;

    pickup_delay       :  float32;
    max_stack          :  u32;
};

Game_Data :: struct
{
    item_data   : [Item_ID.item_count]    Item_Data_Entry;
    entity_data : [Entity_ID.entity_count]Entity_Data_Entry;
};

/*
Entity_Drop :: struct
{
    dropped_item   : Item_ID; 
    amount_to_drop : u32;
};
*/

add_to_drop_list :: (list: *[..]Entity_Drop, item_id: Item_ID, count: u32)
{
    result: Entity_Drop;
    result.dropped_item   = item_id;
    result.amount_to_drop = count;

    array_add(list, result);
}

create_item_and_add_to_catalog :: (game_data    : *Game_Data,
                                   item_id      :  Item_ID, 
                                   entity_arch  :  entity_archetype,
                                   name         :  string,
                                   description  :  string,
                                   sprite       : *Atlas_Sprite,
                                   flags        :  u64,
                                   pickup_delay :  float32,
                                   max_stack    :  u32)
{
    result := *game_data.item_data[item_id];
    result.ID                  = item_id;
    result.entity_arch         = entity_arch;
    result.name                = name;
    result.description         = description;
    result.sprite              = sprite;
    result.flags_when_dropped |= flags;
    result.pickup_delay        = pickup_delay;
    result.max_stack           = max_stack;
}

create_entity_and_add_to_catalog :: (game_data     : *Game_Data,
                                     entity_id     :  Entity_ID,
                                     entity_arch   :  entity_archetype,
                                     item_on_drop  :  Item_ID,
                                     flags         :  u64,
                                     sprite        : *Atlas_Sprite,
                                     move_speed    :  float32,
                                     friction      :  float32,
                                     max_health    :  s32,
                                     drops         :  []Entity_Drop,
                                     max_drop_dist :  float32)
{
    result := *game_data.entity_data[entity_id];
    result.ID              = entity_id;
    result.entity_arch     = entity_arch;
    result.flags           |= flags;
    result.sprite          = sprite;
    result.speed           = move_speed;
    result.friction        = friction;
    result.max_health      = max_health;
    result.drop_list       = drops;
    result.drop_count      = xx drops.count;
    result.max_drop_radius = max_drop_dist;
    result.drop_id         = item_on_drop;
}

init_game_data :: (game_data: *Game_Data)
{
    // TODO(Sleepster): Make this stuff load from a file/some files
    no_drops: []Entity_Drop;
    
    create_item_and_add_to_catalog(game_data, Item_ID.item_stone_chunk, entity_archetype.ITEM_STONE_CHUNK, "stone chunk", "This is a stone chunk... You can use it to craft stuff!", sprite_stone_chunk, xx IS_ITEM, .3, 32);
    create_item_and_add_to_catalog(game_data, Item_ID.item_coal_chunk,  entity_archetype.ITEM_COAL_CHUNK,  "stone chunk", "This is a stone chunk... You can use it to craft stuff!", sprite_coal_chunk,  xx IS_ITEM, .3, 32);
    create_item_and_add_to_catalog(game_data, Item_ID.item_wood_chunk,  entity_archetype.ITEM_WOOD_CHUNK,  "wood chunk",  "This is a wood chunk... You can use it to craft stuff!", sprite_wood_chunk,  xx IS_ITEM, .3, 32);

    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_player,      entity_archetype.PLAYER,    0, xx (CAN_PICKUP_ITEMS|CAN_BE_DAMAGED), sprite_player, 10.0, 0.1, 10, no_drops, 0);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_build_crate, entity_archetype.CRATE,     0, xx (IS_GRABBABLE|CAN_BE_DAMAGED), sprite_base_block, 0.0,  0.0, 10, no_drops, 0);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_furnace,     entity_archetype.FURNACE,   0, xx (IS_GRABBABLE|CAN_BE_DAMAGED), sprite_furnace,    0.0,  0.0, 30, no_drops, 0);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_workbench,   entity_archetype.WORKBENCH, 0, xx (IS_GRABBABLE),              sprite_workbench,  0.0,  0.0, 10, no_drops, 0);

    stone_node_drop_list: [..]Entity_Drop;
    add_to_drop_list(*stone_node_drop_list, Item_ID.item_stone_chunk, 3);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_stone_node, entity_archetype.STONE_NODE, item_stone_chunk, xx (CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH), sprite_stone_node, 0.0, 0.0, 5, stone_node_drop_list, 0);

    coal_node_drop_list: [..]Entity_Drop;
    add_to_drop_list(*coal_node_drop_list, Item_ID.item_coal_chunk, 1);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_coal_node, entity_archetype.COAL_NODE, item_coal_chunk, xx (CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH), sprite_coal_node, 0.0, 0.0, 5, coal_node_drop_list, 0);

    tree_00_drop_list: [..]Entity_Drop;
    add_to_drop_list(*tree_00_drop_list, Item_ID.item_wood_chunk, 1);
    create_entity_and_add_to_catalog(game_data, Entity_ID.entity_tree00, entity_archetype.TREE00, item_wood_chunk, xx (CAN_BE_DAMAGED|DROPS_ITEMS_ON_DEATH), sprite_tree_00, 0.0, 0.0, 5, tree_00_drop_list, 0);
}

spawn_item :: (game_state: *Game_State, item_id: Item_ID) -> *Entity
{
    item_data := *game_state.game_data.item_data[item_id];

    entity := create_entity(game_state.entity_manager);
    entity.sprite_data  = *item_data.sprite;
    entity.archetype    = item_data.entity_arch;
    entity.draw_color   = WHITE;
    entity.flags       |= item_data.flags_when_dropped;
    entity.render_size  = entity.sprite_data.atlas_size;
    entity.bounding_box = AABB_create(entity.position, entity.position + entity.render_size);
    entity.pickup_delay = item_data.pickup_delay;
    entity.pickup_timer = item_data.pickup_delay;

    return entity;
}

spawn_entity :: (game_state: *Game_State, entity_id: Entity_ID) -> *Entity
{
    entity_data := *game_state.game_data.entity_data[entity_id];

    using entity_data;
    entity := create_entity(game_state.entity_manager);
    entity.entity_id       = xx entity_id;
    entity.archetype       = entity_arch;
    entity.flags          |= flags;
    entity.sprite_data     = *sprite;
    entity.draw_color      = WHITE;
    entity.speed           = speed;
    entity.friction        = friction;
    entity.render_size     = entity.sprite_data.atlas_size;
    entity.max_health      = max_health;
    entity.current_health  = max_health;
    entity.drop_list       = drop_list;
    entity.max_drop_radius = max_drop_radius;
    entity.pickup_timer    = pickup_delay;
    entity.pickup_delay    = pickup_delay;

    return entity;
}

get_item_data :: (game_data: *Game_Data, item_name: string) -> *Item_Data_Entry
{
    result: *Item_Data_Entry;
    for item_data: game_data.item_data
    {
        if compare_strings(item_name, item_data.name)
        {
            result = *item_data;
        }
    }

    if result == null
    {
        result = *game_data.item_data[Item_ID.item_null]; 
    }
    
    return result;
}

get_item_data_id :: (game_data: *Game_Data, item_id: Item_ID) -> *Item_Data_Entry
{
    if item_id > Item_ID.item_count
    {
        log("Accessing the item array at index '%', this is beyond the max of '%'", item_id, Item_ID.item_count);
        return null;
    }
    return(*game_data.item_data[item_id]);
}
