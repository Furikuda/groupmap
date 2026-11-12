# frozen_string_literal: true

module GroupMap
  # Data access for fluffs (people) and their markers on group pictures.
  class Store
    def initialize(db)
      @db = db
    end

    def fluffs
      @db[:fluff].select(:id, :name, :info).order(:name, :id).all
    end

    def markers(map)
      @db[:map].where(map: map).select(:id, :fluff_id, :map, :lat, :lng).all
    end

    # Adds a marker, creating the fluff if needed. Re-sending the exact same
    # marker is a no-op instead of a unique-constraint error.
    def add_marker(map:, name:, info:, lat:, lng:)
      @db.transaction do
        @db[:fluff].insert_conflict.insert(name: name, info: info)
        fluff_id = @db[:fluff].where(name: name, info: info).get(:id)
        @db[:map].insert_conflict.insert(fluff_id: fluff_id, map: map, lat: lat, lng: lng)
        fluff_id
      end
    end
  end
end
