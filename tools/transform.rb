#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves all markers of one map with an affine transform, e.g. after the tile
# pyramid was regenerated from a differently sized/cropped picture.
#
#   bundle exec ruby tools/transform.rb points.json MAP_FOLDER          # dry run
#   bundle exec ruby tools/transform.rb points.json MAP_FOLDER --apply  # write
#
# points.json holds at least 3 (better 4+) matching control points, as
# [lat, lng] pairs read from the map (old position -> new position):
#
#   { "old": [[-72.19, 158.62], [-69.50, 16.56], [-32.75, 122.93]],
#     "new": [[-62.88, 138.88], [-60.86, 14.82], [-28.60, 107.69]] }
#
# Uses GROUPMAP_DB or db/fluff_v2.sqlite.

require 'json'
require 'matrix'
require_relative '../lib/groupmap/db'

points_file, map_folder, flag = ARGV
abort "Usage: #{$PROGRAM_NAME} points.json MAP_FOLDER [--apply]" unless points_file && map_folder

points = JSON.parse(File.read(points_file))
old_pts = points.fetch('old')
new_pts = points.fetch('new')
abort 'Need the same number of old and new points' unless old_pts.size == new_pts.size
abort 'Need at least 3 control points for an affine fit' if old_pts.size < 3

# Least squares fit of [lat', lng'] = [lat, lng, 1] * M, where M is 3x2.
design = Matrix.rows(old_pts.map { |lat, lng| [Float(lat), Float(lng), 1.0] })
target = Matrix.rows(new_pts.map { |lat, lng| [Float(lat), Float(lng)] })
normal = design.transpose * design
abort 'Control points are collinear, pick points spread over the picture' if normal.det.abs < 1e-9
transform = normal.inverse * design.transpose * target

apply = ->(lat, lng) { (Matrix[[lat, lng, 1.0]] * transform).row(0).to_a }

puts 'Control point residuals (map units):'
old_pts.zip(new_pts).each do |(lat, lng), expected|
  got = apply.call(Float(lat), Float(lng))
  error = Math.hypot(got[0] - expected[0], got[1] - expected[1])
  puts format('  [%<lat>.3f, %<lng>.3f] -> off by %<err>.4f', lat: lat, lng: lng, err: error)
end

db = GroupMap::DB.connect
markers = db[:map].where(map: map_folder)
abort "No markers for map #{map_folder.inspect}" if markers.empty?

updates = markers.select(:id, :lat, :lng).map { |r| [r[:id], *apply.call(r[:lat], r[:lng])] }
updates.first(5).each do |id, lat, lng|
  puts format('  marker %<id>d -> [%<lat>.4f, %<lng>.4f]', id: id, lat: lat, lng: lng)
end

if flag == '--apply'
  db.transaction { updates.each { |id, lat, lng| db[:map].where(id: id).update(lat: lat, lng: lng) } }
  puts "Updated #{updates.size} markers of #{map_folder}."
else
  puts "Dry run: #{updates.size} markers would move. Re-run with --apply to write."
end
