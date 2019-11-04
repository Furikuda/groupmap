module DBUtils
    require "logger"
    require "sequel"

    if not Object.const_defined?(:DB)
        if not File.directory?('db')
          Dir.mkdir('db')
        end
        DB = Sequel.sqlite 'db/fluff.sqlite', :loggers => [Logger.new($stderr)]
    end

    unless DB.table_exists?(:fluff)
        DB.create_table :fluff do
            primary_key :id
            String  :name, :unique => false, :empty => false
            String  :info, :unique => false, :empty => true
        end
        DB.alter_table(:fluff) do
            add_unique_constraint [:name, :info]
        end
    end

    unless DB.table_exists?(:map)
        DB.create_table :map do
            primary_key :id
            Integer  :fluff_id, :unique => false, :empty => false
            String  :map, :unique => false, :empty => false
            Float   :lat, :unique => false, :empty => false
            Float 	:lng, :unique => false, :empty => false
        end
        DB.alter_table(:map) do
            add_unique_constraint [:fluff_id, :map, :lat, :lng]
        end
    end

    def DBUtils.add_fluff_to_map(map, fluff_id, lat, lng)
        DB[:map].insert(
            map: map,
            fluff_id: fluff_id,
            lat: lat,
            lng: lng,
        )
    end

    def DBUtils.add_fluff(name, info)
      fid = DBUtils.get_fluffid(name, info)
      if not fid
        fid = DB[:fluff].insert(
            name: name,
            info: info,
        )
      end
      return fid
    end

    def DBUtils.get_all_fluff_from_map(map)
        return DB[:map].where(map: map).all
    end

    def DBUtils.get_all_fluff()
        return DB[:fluff].all
    end

    def DBUtils.get_fluffid(name, info)
      fluff =  DB[:fluff].where(name: name, info: info).select(:id).first
      if fluff
        return fluff[:id]
      end
      return nil
    end
end
