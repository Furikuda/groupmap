# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

class CacheHeadersTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GroupMap::App
  end

  def setup
    app.set :catalog, GroupMap::MapCatalog.new(make_pics({ 'con1' => {} }, ['con1']))
  end

  def cache_control_for(path)
    get path
    last_response.headers['cache-control']
  end

  def test_app_code_is_always_revalidated
    assert_equal 'no-cache', cache_control_for('/groupmap.js')
    assert_equal 'no-cache', cache_control_for('/autofill.js')
    assert_equal 'no-cache', cache_control_for('/groupmap.css')
    assert_equal 'no-cache', cache_control_for('/')
    assert_equal 'no-cache', cache_control_for('/list_maps')
  end

  def test_versioned_vendor_files_are_cached_long
    assert_equal 'public, max-age=31536000, immutable', cache_control_for('/vendor/leaflet-1.9.4/leaflet.js')
  end

  def test_tiles_keep_their_day_long_cache
    assert_match(/max-age=86400/, cache_control_for('/group_pics/con1/7/1/2.jpg'))
  end

  def test_unchanged_static_file_revalidates_as_not_modified
    get '/groupmap.js'
    last_modified = last_response.headers['last-modified']

    refute_nil last_modified
    get '/groupmap.js', {}, 'HTTP_IF_MODIFIED_SINCE' => last_modified

    assert_equal 304, last_response.status
  end
end
