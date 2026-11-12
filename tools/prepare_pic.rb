#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a tile pyramid + manifest.json for a group picture.
#
#   ruby tools/prepare_pic.rb input_pic.jpg destination_dir
#
# Requires libvips-tools (vips, vipsheader). Pictures narrower than MIN_WIDTH
# are upscaled first so there are enough zoom levels; the upscaled copy is
# temporary, only the original is kept next to the tiles ("Full image").

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

MIN_WIDTH = 20_000
TILE_SIZE = 256

def run!(*cmd)
  out, err, status = Open3.capture3(*cmd)
  abort "Command failed (exit #{status.exitstatus}): #{cmd.join(' ')}\n#{err}" unless status.success?
  out
rescue Errno::ENOENT
  abort "#{cmd.first} not found, please install the libvips-tools package"
end

def dimensions(file)
  %w[width height].map { |field| Integer(run!('vipsheader', '-f', field, file).strip) }
end

image, dest = ARGV
abort "Usage: #{$PROGRAM_NAME} input_pic.jpg destination_dir" unless image && dest
abort "No such file: #{image}" unless File.file?(image)
abort "#{dest} already exists" if File.exist?(dest)

width, height = dimensions(image)

Dir.mktmpdir('groupmap') do |tmp|
  tiled = image
  if width < MIN_WIDTH
    scale = MIN_WIDTH.fdiv(width)
    tiled = File.join(tmp, 'upscaled.v') # vips native format: fast, lossless
    puts format('Upscaling %<w>dx%<h>d by %<s>.2f', w: width, h: height, s: scale)
    run!('vips', 'resize', image, tiled, scale.to_s)
    width, height = dimensions(tiled)
  end

  puts "Building picture pyramid in '#{dest}'"
  run!('vips', 'dzsave', tiled, dest, '--layout', 'google', '--tile-size', TILE_SIZE.to_s, '--suffix', '.jpg')
end

FileUtils.cp(image, dest)

# Deepest zoom level = highest numeric folder written by vips.
max_zoom = Dir.children(dest).grep(/\A\d+\z/).map(&:to_i).max

manifest = {
  name: '',
  shortname: '',
  year: Time.now.year.to_s,
  url: '',
  source_pic: File.basename(image),
  source_photographer: '',
  max_zoom: max_zoom,
  width: width,
  height: height
}
manifest_path = File.join(dest, 'manifest.json')
File.write(manifest_path, "#{JSON.pretty_generate(manifest)}\n")
puts "Wrote #{manifest_path}:", File.read(manifest_path)
puts "Please fill in name/url/photographer in #{manifest_path}"
