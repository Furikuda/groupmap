# frozen_string_literal: true

require 'json'
require 'sinatra/base'
require 'slim'

require_relative 'db'
require_relative 'map_catalog'
require_relative 'marker_input'
require_relative 'store'
require_relative 'throttle'

module GroupMap
  # Sinatra application: serves the page, the JSON API and the tile fallback.
  class App < Sinatra::Base
    CSP = [
      "default-src 'self'",
      "img-src 'self' data:",
      "style-src 'self' 'unsafe-inline'", # Leaflet sets inline styles
      "object-src 'none'",
      "base-uri 'none'",
      "frame-ancestors 'none'"
    ].join('; ')

    ROOT = File.expand_path('../..', __dir__)

    set :root, ROOT
    set :public_folder, File.join(ROOT, 'public')
    set :views, File.join(ROOT, 'views')
    set :static_cache_control, [:public, { max_age: 3600 }]
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, false # 500s are logged in one line by the error handler

    set :store, Store.new(DB.connect)
    set :catalog, MapCatalog.new(File.join(ROOT, 'public', 'group_pics'))
    set :add_throttle, Throttle.new(min_interval: Float(ENV.fetch('GROUPMAP_ADD_INTERVAL', 3)),
                                    per_hour: Integer(ENV.fetch('GROUPMAP_ADD_PER_HOUR', 100)))

    helpers do
      def json(payload, status = 200)
        halt status, { 'content-type' => 'application/json' }, payload.to_json
      end

      def json_error(status, message, headers = {})
        response.headers.merge!(headers)
        json({ error: message }, status)
      end
    end

    before do
      headers 'content-security-policy' => CSP,
              'x-content-type-options' => 'nosniff',
              'referrer-policy' => 'strict-origin-when-cross-origin'
    end

    get '/' do
      slim :main
    end

    get '/list_maps' do
      json maps: settings.catalog.all
    end

    get '/all_fluffs' do
      json fluffs: settings.store.fluffs
    end

    get '/list_fluff' do
      map = params['map'].to_s
      json_error 404, 'unknown map' unless settings.catalog.include?(map)
      json fluffs: settings.store.markers(map)
    end

    post '/add_fluff' do
      input = MarkerInput.parse(params, settings.catalog)
      wait = settings.add_throttle.hit(request.ip)
      json_error 429, "Too fast, try again in #{wait}s", 'retry-after' => wait.to_s if wait

      settings.store.add_marker(**input)
      json msg: 'Data updated!'
    end

    # Existing tiles are served as static files; this only runs for missing
    # ones (outside the pyramid) and answers with the blank tile.
    get %r{/group_pics/([^/]+)/\d+/\d+/\d+\.(?:jpe?g|png)} do |folder|
      blank = settings.catalog.blank_tile(folder)
      halt 404 unless blank

      cache_control :public, max_age: 86_400
      send_file blank, type: :png
    end

    error MarkerInput::Invalid do
      json_error 400, env['sinatra.error'].message
    end

    error 500 do
      if (e = env['sinatra.error'])
        warn "groupmap: #{e.class}: #{e.message} (#{e.backtrace&.first})"
      end
      json_error 500, 'internal error'
    end
  end
end
