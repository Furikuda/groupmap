# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  VALID = { 'map' => 'con1', 'name' => 'Foo', 'info' => 'https://x.y', 'lat' => '-10', 'lng' => '20' }.freeze

  def app
    GroupMap::App
  end

  def setup
    @db = fresh_db
    pics = make_pics({ 'con1' => { 'name' => 'Con 1', 'year' => '2024' },
                       'con2' => { 'name' => 'Con 2', 'year' => '2020' } }, ['con1'])
    app.set :store, GroupMap::Store.new(@db)
    app.set :catalog, GroupMap::MapCatalog.new(pics)
    no_throttle!
  end

  def no_throttle!
    app.set :add_throttle, GroupMap::Throttle.new(min_interval: 0, per_hour: 1_000_000)
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def add(params = {}, ip = '10.0.0.1')
    post '/add_fluff', VALID.merge(params), 'REMOTE_ADDR' => ip
  end

  # ---- page & headers ----

  def test_index_page_and_security_headers
    get '/'

    assert_predicate last_response, :ok?
    assert_includes last_response.body, 'id="map"'
    assert_includes last_response.body, '/vendor/leaflet-1.9.4/leaflet.js'
    assert_match(/default-src 'self'/, last_response.headers['content-security-policy'])
    assert_match(/frame-ancestors 'none'/, last_response.headers['content-security-policy'])
    assert_equal 'nosniff', last_response.headers['x-content-type-options']
  end

  def test_static_assets_are_served
    get '/groupmap.js'

    assert_predicate last_response, :ok?
    assert_match(/javascript/, last_response.content_type)
  end

  # ---- read API ----

  def test_list_maps
    get '/list_maps'

    assert_equal 'application/json', last_response.content_type
    assert_equal(%w[con1 con2], json_body['maps'].map { |m| m['folder'] })
  end

  def test_list_fluff_requires_a_known_map
    get '/list_fluff', 'map' => 'nope'

    assert_equal 404, last_response.status
    assert_equal({ 'error' => 'unknown map' }, json_body)

    get '/list_fluff'

    assert_equal 404, last_response.status
  end

  def test_empty_lists
    get '/all_fluffs'

    assert_equal({ 'fluffs' => [] }, json_body)

    get '/list_fluff', 'map' => 'con1'

    assert_equal({ 'fluffs' => [] }, json_body)
  end

  # ---- adding markers ----

  def test_add_fluff_then_read_back
    add

    assert_predicate last_response, :ok?
    assert_equal({ 'msg' => 'Data updated!' }, json_body)

    get '/all_fluffs'
    fluff = json_body['fluffs'].first

    assert_equal %w[Foo https://x.y], fluff.values_at('name', 'info')

    get '/list_fluff', 'map' => 'con1'

    assert_equal([[fluff['id'], 'con1', -10.0, 20.0]],
                 json_body['fluffs'].map { |m| m.values_at('fluff_id', 'map', 'lat', 'lng') })

    get '/list_fluff', 'map' => 'con2'

    assert_empty json_body['fluffs']
  end

  def test_html_is_stored_raw_and_returned_as_json_string
    payload = '<img src=x onerror=alert(1)>'
    add('name' => "Foo & #{payload}", 'info' => payload)
    get '/all_fluffs'
    fluff = json_body['fluffs'].first

    assert_equal "Foo & #{payload}", fluff['name'], 'no HTML escaping on input any more'
    assert_equal payload, fluff['info']
    assert_equal 'application/json', last_response.content_type
  end

  def test_duplicate_submit_is_idempotent
    2.times { add }

    assert_predicate last_response, :ok?
    assert_equal 1, @db[:map].count
  end

  def test_validation_errors_are_400_json
    {
      { 'name' => '' } => 'name is required',
      { 'map' => 'nope' } => 'unknown map',
      { 'lat' => 'abc' } => 'lat must be a number',
      { 'lng' => '999' } => 'lng is outside the picture',
      { 'name' => 'x' * 101 } => 'name is too long (max 100)'
    }.each do |params, message|
      add(params)

      assert_equal 400, last_response.status, params.inspect
      assert_equal({ 'error' => message }, json_body)
    end
    assert_equal 0, @db[:map].count
  end

  def test_empty_post_is_a_client_error
    post '/add_fluff'

    assert_equal 400, last_response.status
  end

  def test_validation_errors_are_not_logged
    _, err = capture_io { add('name' => '') }

    assert_empty err
  end

  # ---- throttling ----

  def test_throttles_per_ip
    app.set :add_throttle, GroupMap::Throttle.new(min_interval: 60, per_hour: 100)
    add

    assert_predicate last_response, :ok?

    add('lat' => '-11')

    assert_equal 429, last_response.status
    assert_match(/\AToo fast, try again in \d+s\z/, json_body['error'])
    assert_operator last_response.headers['retry-after'].to_i, :>=, 59

    add({ 'lat' => '-12' }, '10.0.0.2')

    assert_predicate last_response, :ok?, 'other IPs are not affected'
    assert_equal 2, @db[:map].count
  end

  def test_invalid_requests_do_not_use_up_the_budget
    app.set :add_throttle, GroupMap::Throttle.new(min_interval: 60, per_hour: 100)
    3.times { add('name' => '') }
    add

    assert_predicate last_response, :ok?
  end

  # ---- tiles ----

  def test_missing_tile_falls_back_to_blank
    get '/group_pics/con1/7/1/2.jpg'

    assert_predicate last_response, :ok?
    assert_equal 'image/png', last_response.content_type
    assert_equal "\x89PNG fake".b, last_response.body.b
    assert_match(/max-age=86400/, last_response.headers['cache-control'])
  end

  def test_tile_fallback_404s
    get '/group_pics/con2/7/1/2.jpg' # known map without blank.png

    assert_equal 404, last_response.status

    get '/group_pics/unknown/7/1/2.jpg'

    assert_equal 404, last_response.status

    get '/group_pics/con1/7/1/2.exe'

    assert_equal 404, last_response.status
  end

  # ---- logging ----

  def test_requests_are_access_logged
    get '/list_maps'

    assert_match %r{"GET /list_maps HTTP/1\.[01]" 200}, last_request.env['rack.errors'].string
  end

  # Behind a proxy that does not forward Host, the browser's Referer host differs
  # from the Host the app sees and JsonCsrf answers 403. That must show up in the log.
  def test_rack_protection_denials_are_logged
    get '/list_maps', {}, 'HTTP_HOST' => '127.0.0.1:4567', 'HTTP_REFERER' => 'https://groupmap.example/'

    assert_equal 403, last_response.status
    assert_match(/attack prevented by Rack::Protection::JsonCsrf/, last_request.env['rack.errors'].string)
  end

  def test_same_host_referer_is_allowed
    get '/list_maps', {}, 'HTTP_HOST' => 'groupmap.example', 'HTTP_REFERER' => 'https://groupmap.example/'

    assert_predicate last_response, :ok?
  end

  # ---- errors ----

  def test_internal_errors_are_json_and_logged_in_one_line
    broken = Object.new
    def broken.fluffs = raise(Sequel::DatabaseError, 'disk on fire')
    app.set :store, broken

    _, err = capture_io { get '/all_fluffs' }

    assert_equal 500, last_response.status
    assert_equal({ 'error' => 'internal error' }, json_body)
    assert_equal 1, err.lines.size
    assert_match(/Sequel::DatabaseError: disk on fire/, err)
  end
end
