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
            String  :map, :unique => false, :empty => false
            Float   :lat, :unique => false, :empty => false
            Float 	:lng, :unique => false, :empty => false
            String  :info, :unique => false, :empty => true
        end
    end

    class Fluff < Sequel::Model(:fluff)
    end

    def DBUtils.add_fluff(map, name, info, lat, lng)
        Fluff.insert(
            :map => map,
            :name => name,
            :info => info,
            :lat => lat,
            :lng => lng,
        )
    end

    def DBUtils.get_all_fluff(map)
        return Fluff.where(map: map).all
    end
end
