#!/usr/bin/ruby
# encoding: utf-8

Encoding.default_external = Encoding::UTF_8

require "cgi"
require "json"
require "sinatra"
require "slim"

require_relative "./db.rb"

$group_images_dirname = 'group_pics'

def fix_name(n)
    name = CGI.escapeHTML(n)
    return name.strip()
end

def get_map_list()
    liste = []
    Dir.glob(File.join('public', $group_images_dirname, "*", "manifest.json")).each do |j|
        metadata = JSON.parse(File.read(j))
        metadata['folder'] = File.basename(File.dirname(j))
        liste << metadata
    end
    liste.sort_by{|x| x['year']}.reverse
end

$map_list = get_map_list()

get '/' do
    @liste = $map_list
    slim :main
end

post '/add_fluff' do
    $stderr.puts params.to_s
    name = params[:name]
    info = params[:info]
    name = fix_name(name)

    lat = params[:lat].to_f
    lng = params[:lng].to_f
    map = params[:map]

    unless (name && lat && lng && map)
        $stderr.puts("missing info")
        return {:msg => "missing info"}
    end

    DBUtils.add_fluff(map, name, info, lat, lng)

    content_type 'application/json'
    return {:msg => "Data updated!"}.to_json
end

get '/list_fluff' do
    map = params[:map]
    p = DBUtils.get_all_fluff(map).map{|p| p.to_hash}
    content_type 'application/json'
    {'fluff' => p}.to_json
end

get '/list_maps' do
    content_type 'application/json'
    {'maps' => $map_list}.to_json
end

get "/#{$group_images_dirname}/:folder/:z/:x/:y.*" do |folder, z, x, y, ext|
    case ext
    when "jpg"
        content_type 'image/jpeg'
    when "png"
        content_type 'image/png'
    end

    begin
        tile_path = File.join('public', $group_images_dirname, folder, z, x, "#{y}.#{ext}")
        content = File.open(tile_path, 'rb').read()
    rescue Errno::ENOENT
        content_type 'image/png'
        blank_path = File.join('public', $group_images_dirname, folder, "blank.png")
        content = File.open(blank_path, 'rb').read()
    end

    content
end
