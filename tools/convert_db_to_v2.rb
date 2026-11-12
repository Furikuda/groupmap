#!/usr/bin/env ruby
# frozen_string_literal: true

# ONE-OFF: converts the old db/fluff.sqlite into db/fluff_v2.sqlite.
# Run once, check the output, then delete this script.
#
#   bundle exec ruby tools/convert_db_to_v2.rb [old.sqlite] [new.sqlite]
#
# - Handles both old layouts: the current one (fluff + map tables) and the
#   pre-Nov-2019 one (fluff rows holding map/lat/lng directly).
# - Names were stored HTML-escaped (CGI.escapeHTML); they are stored raw now.
# - Rows that are blank or duplicates after cleaning are merged/skipped.
# - The old file is opened read-only and never modified.

require 'cgi'
require 'sequel'
require_relative '../lib/groupmap/db'

old_path = ARGV[0] || File.expand_path('../db/fluff.sqlite', __dir__)
new_path = ARGV[1] || GroupMap::DB::DEFAULT_PATH

abort "No old database at #{old_path}" unless File.file?(old_path)
abort "#{new_path} already exists; remove it first to convert again" if File.exist?(new_path)

old = Sequel.sqlite(old_path, readonly: true)
new = GroupMap::DB.connect(new_path)
stats = Hash.new(0)
suspicious = []

clean = ->(s) { s.to_s.strip }
fluff_columns = old.schema(:fluff).map(&:first)
legacy = fluff_columns.include?(:lat)
puts "Old layout: #{legacy ? 'pre-2019 (markers inside fluff table)' : 'fluff + map tables'}"

new.transaction do
  id_map = {} # old fluff id -> new fluff id

  old[:fluff].order(:id).each do |row|
    name = clean.call(CGI.unescapeHTML(row[:name].to_s))
    info = clean.call(row[:info])
    if name.empty?
      stats[:fluff_blank_skipped] += 1
      next
    end
    suspicious << [row[:id], name, info] if "#{name} #{info}".match?(/<|javascript:/i)

    new[:fluff].insert_conflict.insert(name: name, info: info)
    id_map[row[:id]] = new[:fluff].where(name: name, info: info).get(:id)
    stats[:fluff_read] += 1
  end

  markers = if legacy
              old[:fluff].select(Sequel.as(:id, :fluff_id), :map, :lat, :lng)
            else
              old[:map].select(:fluff_id, :map, :lat, :lng)
            end

  markers.each do |row|
    fluff_id = id_map[row[:fluff_id]]
    map = clean.call(row[:map])
    if fluff_id.nil? || map.empty? || row[:lat].nil? || row[:lng].nil?
      stats[:marker_invalid_skipped] += 1
      next
    end

    marker = { fluff_id: fluff_id, map: map, lat: Float(row[:lat]), lng: Float(row[:lng]) }
    if new[:map].where(marker).empty?
      new[:map].insert(marker)
      stats[:marker_copied] += 1
    else
      stats[:marker_duplicate_skipped] += 1
    end
  end
end

stats[:fluff_written] = new[:fluff].count
stats[:marker_written] = new[:map].count
puts "Wrote #{new_path}"
stats.sort.each { |k, v| puts format('  %-26<k>s %<v>d', k: k, v: v) }

unless suspicious.empty?
  puts "\n#{suspicious.size} fluff(s) contain HTML/JS-looking text (now shown as plain text, review anyway):"
  suspicious.each { |id, name, info| puts "  old id #{id}: #{name.inspect} #{info.inspect}" }
end
