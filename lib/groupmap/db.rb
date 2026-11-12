# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'sequel'

module GroupMap
  # Database connection and schema. Tables are created if missing; there is no
  # migration framework (tools/convert_db_to_v2.rb is a one-off upgrade).
  module DB
    DEFAULT_PATH = File.expand_path('../../db/fluff_v2.sqlite', __dir__)

    def self.path
      ENV.fetch('GROUPMAP_DB', DEFAULT_PATH)
    end

    def self.connect(path = self.path)
      FileUtils.mkdir_p(File.dirname(path))
      db = Sequel.sqlite(path) # Sequel enables PRAGMA foreign_keys by default
      db.loggers << Logger.new($stderr) if ENV['GROUPMAP_SQL_LOG']
      create_schema(db)
      db
    end

    def self.create_schema(db)
      db.create_table?(:fluff) do
        primary_key :id
        String :name, null: false
        String :info, null: false, default: ''
        unique %i[name info]
      end

      db.create_table?(:map) do
        primary_key :id
        foreign_key :fluff_id, :fluff, null: false, on_delete: :cascade
        String :map, null: false
        Float :lat, null: false
        Float :lng, null: false
        unique %i[fluff_id map lat lng]
        index :map
      end
    end
  end
end
