module DBUtils
    require "logger"
    require "sequel"

    Sequel::Model.plugin(:schema) 
    if not Object.const_defined?(:DB)
        DB = Sequel.sqlite 'db/fluff.sqlite', :loggers => [Logger.new($stderr)]
    end

    class Fluff < Sequel::Model(:fluff)
        set_schema do
            primary_key :id
            String  :name, :unique => false, :empty => false
            String  :map, :unique => false, :empty => false
            Float   :lat, :unique => false, :empty => false
            Float 	:lng, :unique => false, :empty => false
            String  :info, :unique => false, :empty => true
        end
        create_table unless table_exists?
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
