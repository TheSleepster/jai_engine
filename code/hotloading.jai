// TODO(Sleepster): This is horrible awful stupid and angering. Too bad! 
hotload_assets :: (using asset_manager: *Asset_Manager) -> bool
{
    for *path_data: data_paths
    {
        files := file_list(path_data.path, true);
        new_file_count := xx files.count;
        if path_data.file_count != new_file_count
        {
            for file: files
            {
                path, basename, ext := path_decomp(file);
                file_data: Visit_File_Data;
                file_data.transient_state = asset_manager.transient_state;
                if ext == "png"
                {
                    visit_files(path_data.path, true, cast(*void)*file_data, init_asset_image_metadata_from_disk);
                }
                else if ext == "wav"
                {
                    visit_files(path_data.path, true, cast(*void)*file_data, init_asset_sound_metadata_from_disk);
                }
                else if ext == "ttf"
                {
                    visit_files(path_data.path, true, cast(*void)*file_data, init_asset_font_metadata_from_disk);
                }

                log("New File: % detected in path %\n", basename, path);
                path_data.file_count = xx new_file_count;
            }
        }

        for file: files
        {
            path, basename, ext := path_decomp(file);
            asset: *Asset_Slot;
            if ext == "png"
            {
                asset = cast(*Asset_Slot)hash_get_value(*asset_manager.textures, basename);
            }
            else if ext == "wav"
            {
                asset = cast(*Asset_Slot)hash_get_value(*asset_manager.soundfx, basename);
            }
            else if ext == "ttf"
            {
                asset = cast(*Asset_Slot)hash_get_value(*asset_manager.fonts, basename);
            }

            if asset
            {
                new_mod_time, new_mod_size := file_modtime_and_size(file);
                if new_mod_time != asset.mod_time || new_mod_size != asset.mod_size
                {
                    asset.mod_time = new_mod_time;
                    asset.mod_size = new_mod_size;
                    asset.modified = true;
                    if ext == "png"
                    {
                        sprite := asset_get_sprite(asset_manager, basename);
                        if sprite
                        {
                            atlas := sprite.atlas_texture;
                            load_textures_into_atlas(asset_manager, basename);
                        }
                    }
                }
            }
            else
            {
                log("[ERROR]: hotloading failed to find asset '%'...\n", file);
            }
        }
    }
    return true;
}
