module InventoryCommands
  def normal_get_inventory(steam_id: @steam_id, app_id: 753)
    raise "No logged-in and no SteamId specified" unless steam_id

    app_id = app_id.to_s
    context = 6

    # Verify given another game
    context = 2 if app_id.to_s != '753'

    # verify trade link
    steam_id, token = verify_profileid_or_trade_link_or_steamid(steam_id)
    raise "Invalid SteamId : #{steam_id}, length of received :: #{steam_id.to_s.length}, normal is 17" if steam_id.to_s.length != 17

    verify_app_id app_id

    if @inventory_cache
      verdict = verify_inventory_cache('normal', steam_id, app_id)
      if verdict != false
        return verdict
      end
    end

    items = []
    last_id = 0
    until last_id == false
      received = get_inventory_chunk_normal_way(app_id, context, steam_id, last_id)
      last_id = received['new_last_id']
      items = items + received['assets']
      output "loaded #{items.length}"
    end

    output "total loaded #{items.length} asset"
    if @inventory_cache
      File.open("./normal_#{steam_id}_#{app_id}.inventory", 'w') { |f| f.write items.to_json }
    end

    items
  end

  def raw_get_inventory(steam_id: @steam_id, app_id: '753', trim: true)
    app_id = app_id.to_s
    context = 6

    steam_id, token = verify_profileid_or_trade_link_or_steamid(steam_id)

    verify_app_id app_id

    context = 2 if app_id != "753"

    if @inventory_cache
      verdict = verify_inventory_cache('raw', steam_id, app_id)
      return verdict if verdict != false
    end

    last_id = 0
    hash = { "assets" => [], "descriptions" => [] }
    until last_id == false
      received = get_inventory_chunk_raw_way(app_id, context, steam_id, last_id, trim)
      last_id = received['new_last_id']
      hash["assets"] = hash["assets"] + received['assets']
      hash["descriptions"] = hash["descriptions"] + received["descriptions"]
      output "Loaded #{hash["assets"].length}"
    end

    output "Total loaded #{hash["assets"].length} asset"

    if @inventory_cache
      File.open(cache_file_name('raw', steam_id, app_id), 'w') { |f| f.write hash.to_json }
    end

    hash
  end

  private

  def cache_file_name(type, steam_id, app_id)
    "./#{type}_#{steam_id}_#{app_id}.inventory"
  end

  def verify_app_id(app_id)
    unless %w[753 730 570 440].include?(app_id.to_s)
      all_games = JSON.parse(File.read("#{@lib_dir}blueprints/game_inv_list.json"))
      raise "Invalid AppId: #{app_id}" unless all_games.include?(app_id.to_s)
    end
  end

  def get_inventory_chunk_normal_way(appid, context, steamid, last_id)
    html = ''
    tries = 1

    until html != ''
      begin
        html = @session.get("https://steamcommunity.com/inventory/#{steamid}/#{appid}/#{context}?start_assetid=#{last_id}&l=english&count=5000").content
      rescue
        raise "Cannot get inventory, tried 3 times" if tries == 3
        tries = tries + 1
        sleep(0.5)
      end
    end

    get = JSON.parse(html)
    raise "Something totally unexpected happened while getting inventory with appid #{appid} of steamid #{steamid} with contextid #{context}" if get.key?("error") == true
    if get["total_inventory_count"] == 0
      output "EMPTY::inventory with app_id #{appid} of steamid #{steamid} with contextid #{context}"
      return { 'assets' => [], 'new_last_id' => false }
    end
    if get.keys[3].to_s == "last_assetid"
      new_last_id = get.values[3].to_s
    else
      new_last_id = false
    end

    assets = get["assets"]
    descriptions = get["descriptions"]

    descriptions_classids = {} ###sorting descriptions by key value || key is classid of the item's description
    descriptions.each { |description|
      classidxinstance = description["classid"] + '_' + description["instanceid"] # some items has the same classid but different instane id
      descriptions_classids[classidxinstance] = description
    }

    assets.each { |asset| ## merging assets with names
      classidxinstance = asset["classid"] + '_' + asset["instanceid"]
      asset.replace(asset.merge(descriptions_classids[classidxinstance]))
    }

    return { 'assets' => assets, 'new_last_id' => new_last_id }

  end

  def get_inventory_chunk_raw_way(appid, context, steamid, last_id, trim)

    html = ''
    tries = 1

    until html != ''
      begin
        html = @session.get("https://steamcommunity.com/inventory/#{steamid}/#{appid}/#{context}?start_assetid=#{last_id}&count=5000").content
      rescue
        raise "Cannot get inventory, tried 3 times" if tries == 3
        tries = tries + 1
        sleep(0.5)
      end
    end

    get = JSON.parse(html)
    raise "something totally unexpected happened while getting inventory with appid #{appid} of steamid #{steamid} with contextid #{context}" if get.key?("error") == true
    if get["total_inventory_count"] == 0
      output "EMPTY :: inventory with appid #{appid} of steamid #{steamid} with contextid #{context}"
      return { 'assets' => [], "descriptions" => [], 'new_last_id' => false }
    end
    if get.keys[3].to_s == "last_assetid"
      new_last_id = get.values[3].to_s
    else
      new_last_id = false
    end

    assets = get["assets"]
    descriptions = get["descriptions"]
    if trim == true
      descriptions.each { |desc|
        desc.delete_if { |key, value| key != "appid" && key != "classid" && key != "instanceid" && key != "tags" && key != "type" && key != "market_fee_app" && key != "marketable" && key != "name" }
        desc["tags"].delete_at(0)
        desc["tags"].delete_at(0)
      }
    end

    { 'assets' => get["assets"], "descriptions" => get["descriptions"], 'new_last_id' => new_last_id }

  end

  def verify_inventory_cache(type, steam_id, app_id)
    file_name = cache_file_name type, steam_id, app_id
    return false unless File.exists?(file_name)

    file_last_time = Time.parse(File.mtime(file_name).to_s)
    current_time = Time.parse(Time.now.to_s)
    diff = current_time - file_last_time
    if diff.to_i > @inventory_validity
      File.delete(file_name)
      false
    else
      output "Gonna use cached inventory which is #{diff} seconds old"
      begin
        JSON.parse(File.read(file_name, external_encoding: 'utf-8', internal_encoding: 'utf-8'))
      rescue
        File.delete(file_name)
        false
      end
    end
  end

  # def self.included(base)
  #   base.extend(Inventory_ClassMethods)
  # end

  # module Inventory_ClassMethods
  #   @@libdir = Util.gem_libdir
  #   @@session = Mechanize.new
  #
  #   def normal_get_inventory(steam_id, app_id = 753)
  #     app_id = app_id.to_s
  #     context = 6
  #
  #     context = 2 unless app_id.to_s != "753"
  #
  #     steam_id, token = verify_profileid_or_trade_link_or_steamid(steam_id)
  #     raise "Invalid SteamId: #{steam_id}, length of received :: #{steam_id.to_s.length}, normal is 17" if steam_id.to_s.length != 17
  #
  #     if ["753", "730", '570', '440'].include?(app_id.to_s) == false
  #       allgames = JSON.parse(File.read("#{@@libdir}blueprints/game_inv_list.json"))
  #       raise "invalid appid: #{app_id}" if allgames.include?(app_id.to_s) == false
  #     end
  #     ## end verify appid
  #
  #     items = []
  #     last_id = 0
  #     until last_id == false
  #       received = get_inventory_chunk_normal_way(app_id, context, steam_id, last_id)
  #       last_id = received['new_last_id']
  #       items = items + received['assets']
  #       output "loaded #{items.length}"
  #     end
  #
  #     output "total loaded #{items.length} asset"
  #
  #     return items
  #   end
  #
  #   def get_inventory_chunk_normal_way(appid, context, steamid, last_id)
  #     html = ''
  #     tries = 1
  #
  #     until html != ''
  #       begin
  #         html = @@session.get("https://steamcommunity.com/inventory/#{steamid}/#{appid}/#{context}?start_assetid=#{last_id}&l=english&count=5000").content
  #       rescue
  #         raise "Cannot get inventory, tried 3 times" if tries == 3
  #         tries = tries + 1
  #         sleep(0.5)
  #       end
  #     end
  #
  #     get = JSON.parse(html)
  #     raise "something totally unexpected happened while getting inventory with appid #{appid} of steamid #{steamid} with contextid #{context}" if get.key?("error") == true
  #     if get["total_inventory_count"] == 0
  #       output "EMPTY :: inventory with appid #{appid} of steamid #{steamid} with contextid #{context}"
  #       return { 'assets' => [], 'new_last_id' => false }
  #     end
  #     if get.keys[3].to_s == "last_assetid"
  #       new_last_id = get.values[3].to_s
  #     else
  #       new_last_id = false
  #     end
  #
  #     assets = get["assets"]
  #     descriptions = get["descriptions"]
  #
  #     descriptions_classids = {} ###sorting descriptions by key value || key is classid of the item's description
  #     descriptions.each { |description|
  #       classidxinstance = description["classid"] + '_' + description["instanceid"] # some items has the same classid but different instane id
  #       descriptions_classids[classidxinstance] = description
  #     }
  #
  #     assets.each { |asset| ## merging assets with names
  #       classidxinstance = asset["classid"] + '_' + asset["instanceid"]
  #       asset.replace(asset.merge(descriptions_classids[classidxinstance]))
  #     }
  #
  #     return { 'assets' => assets, 'new_last_id' => new_last_id }
  #
  #   end
  #
  #   # def raw_get_inventory(steam_id, app_id = 753)
  #   #   trim = true
  #   #   context = 6
  #   #
  #   #   steam_id, token = verify_profileid_or_trade_link_or_steamid(steam_id)
  #   #   raise "invalid steamid : #{steam_id}, length of received :: #{steam_id.to_s.length}, normal is 17" if steam_id.to_s.length != 17
  #   #   ## verify appid
  #   #
  #   #   if ["753", "730", '570', '440'].include?(app_id.to_s) == false
  #   #     allgames = JSON.parse(File.read("#{@lib_dir}blueprints/game_inv_list.json"))
  #   #     raise "invalid appid: #{app_id}" if allgames.include?(app_id.to_s) == false
  #   #   end
  #   #   ## end verify appid
  #   #
  #   #   if app_id.to_s != "753"
  #   #     context = 2
  #   #   end
  #   #
  #   #   last_id = 0
  #   #   hash = { "assets" => [], "descriptions" => [] }
  #   #   until last_id == false
  #   #     received = get_inventory_chunk_raw_way(app_id, context, steam_id, last_id, trim)
  #   #     last_id = received['new_last_id']
  #   #     hash["assets"] = hash["assets"] + received['assets']
  #   #     hash["descriptions"] = hash["descriptions"] + received["descriptions"]
  #   #     output "loaded #{hash["assets"].length}"
  #   #   end
  #   #
  #   #   output "total loaded #{hash["assets"].length} asset"
  #   #
  #   #   return hash
  #   # end
  #
  #   def get_inventory_chunk_raw_way(appid, context, steamid, last_id, trim)
  #
  #     html = ''
  #     tries = 1
  #
  #     until html != ''
  #       begin
  #         html = @@session.get("https://steamcommunity.com/inventory/#{steamid}/#{appid}/#{context}?start_assetid=#{last_id}&count=5000").content
  #       rescue
  #         raise "Cannot get inventory, tried 3 times" if tries == 3
  #         tries = tries + 1
  #         sleep(0.5)
  #       end
  #     end
  #     get = JSON.parse(html)
  #     raise "something totally unexpected happened while getting inventory with appid #{appid} of steamid #{steamid} with contextid #{context}" if get.key?("error") == true
  #     if get["total_inventory_count"] == 0
  #       output "EMPTY :: inventory with appid #{appid} of steamid #{steamid} with contextid #{context}"
  #       return { 'assets' => [], "descriptions" => [], 'new_last_id' => false }
  #     end
  #     if get.keys[3].to_s == "last_assetid"
  #
  #       new_last_id = get.values[3].to_s
  #
  #     else
  #       new_last_id = false
  #
  #     end
  #
  #     assets = get["assets"]
  #     descriptions = get["descriptions"]
  #     if trim == true
  #       descriptions.each { |desc|
  #         desc.delete_if { |key, value| key != "appid" && key != "classid" && key != "instanceid" && key != "tags" && key != "type" && key != "market_fee_app" && key != "marketable" && key != "name" }
  #         desc["tags"].delete_at(0)
  #         desc["tags"].delete_at(0)
  #       }
  #     end
  #
  #     return { 'assets' => get["assets"], "descriptions" => get["descriptions"], 'new_last_id' => new_last_id }
  #
  #   end
  #
  # end

end
