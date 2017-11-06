#!/usr/bin/ruby
# encoding: utf-8

Encoding.default_external = Encoding::UTF_8

require "cgi"
require "json"
require "sinatra"
require "slim"

require_relative "./db.rb"

$group_images_dir = File.join('public', 'group_pics')

def fix_name(n)
    name = CGI.escapeHTML(n)
    return name.strip()
end

get '/' do
    @liste = []
    Dir.glob(File.join($group_images_dir, "*")).each do |j|
        if File.directory?(j)
            @liste << File.basename(j)
        end
    end
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

    return unless (name && lat && lng && map)

    DBUtils.add_fluff(map, name, info, lat, lng)

    content_type 'application/json'
    {:msg => "Data updated!"}.to_json
end

get '/list_fluff' do
    map = params[:map]
    content_type 'application/json'
    p = DBUtils.get_all_fluff(map).map{|p| p.to_hash}
    {'fluff' => p}.to_json
end
