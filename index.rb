#!/usr/bin/ruby
# encoding: utf-8

Encoding.default_external = Encoding::UTF_8

require "cgi"
require "json"
require "logger"
require "pp"
require "sinatra"
require "slim"

require_relative "./db.rb"

$group_images_dir = File.join('public', 'group_pics')

$logger = Logger.new(STDOUT)

# $BLACK = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00:~\x9bU\x00\x00\x00\x01sRGB\x00\xae\xce\x1c\xe9\x00\x00\x00\tpHYs\x00\x00\x0b\x13\x00\x00\x0b\x13\x01\x00\x9a\x9c\x18\x00\x00\x00\x07tIME\x07\xdc\t\x14\x03\x15\x1e\xb4\xbf\xb1c\x00\x00\x00\x19tEXtComment\x00Created with GIMPW\x81\x0e\x17\x00\x00\x00\nIDAT\x08\xd7c`\x00\x00\x00\x02\x00\x01\xe2!\xbc3\x00\x00\x00\x00IEND\xaeB`\x82"
# $WHITE = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x00\x00\x00\x00:~\x9bU\x00\x00\x00\x01sRGB\x00\xae\xce\x1c\xe9\x00\x00\x00\tpHYs\x00\x00\x0b\x13\x00\x00\x0b\x13\x01\x00\x9a\x9c\x18\x00\x00\x00\x07tIME\x07\xdc\t\x13\x0c\x12\x1emuX \x00\x00\x00\x19tEXtComment\x00Created with GIMPW\x81\x0e\x17\x00\x00\x00\nIDAT\x08\xd7c\xf8\x0f\x00\x01\x01\x01\x00\x1b\xb6\xeeV\x00\x00\x00\x00IEND\xaeB`\x82"

begin
    $CONF = JSON.parse(File.read("config.json"))
rescue JSON::ParserError => e
    $stderr.puts "Your config file is not correct JSON"
    raise e
end

def fix_name(n)
    name = CGI.escapeHTML(n)
    return name.strip()
end

get '/' do
    #@available_things=$CONF["omniauth"].keys
    @signed_in=false
    @liste = []
    Dir.glob(File.join($group_images_dir, "*")).each do |j|
        @liste << File.basename(j)
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

get '/tiles/:map/:zoom/:x/:y' do
    map = params[:map]
    zoom = params[:zoom].to_i
    x = params[:x].to_i
    y = params[:y].to_i
    filename = File.join($group_images_dir, 'lol', zoom.to_s, y.to_s, "#{x}.jpg")
    $stderr.puts filename
    body = nil
    if File.exist?(filename)
        body = File.read(filename)
    else
        $stderr.puts "can't find #{filename}"
        if y >= 2 ** (zoom-1)
            body = $BLACK
        else
            body = $WHITE
        end
    end

    content_type 'image/png'
    body
end
