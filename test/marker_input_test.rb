# frozen_string_literal: true

require_relative 'test_helper'

class MarkerInputTest < Minitest::Test
  Catalog = Struct.new(:folders) do
    def include?(folder) = folders.include?(folder)
  end

  CATALOG = Catalog.new(['con1'])
  VALID = { 'map' => 'con1', 'name' => 'Foo', 'info' => 'https://x.y', 'lat' => '-10.5', 'lng' => '20' }.freeze

  def parse(overrides = {})
    GroupMap::MarkerInput.parse(VALID.merge(overrides), CATALOG)
  end

  def assert_invalid(message, overrides)
    error = assert_raises(GroupMap::MarkerInput::Invalid) { parse(overrides) }
    assert_equal message, error.message
  end

  def test_valid_input
    assert_equal({ map: 'con1', name: 'Foo', info: 'https://x.y', lat: -10.5, lng: 20.0 }, parse)
  end

  def test_html_is_kept_verbatim
    result = parse('name' => '<b>Foo</b> & co', 'info' => '"><script>alert(1)</script>')

    assert_equal '<b>Foo</b> & co', result[:name]
    assert_equal '"><script>alert(1)</script>', result[:info]
  end

  def test_text_is_stripped_normalised_and_control_chars_removed
    result = parse('name' => "  Café\tFox\n ", 'info' => "a\u0000b")

    assert_equal 'Café Fox', result[:name]
    assert_equal 'a b', result[:info]
  end

  def test_invalid_utf8_is_scrubbed
    assert_equal 'Foo', parse('name' => (+"Fo\xFFo").force_encoding('BINARY'))[:name]
  end

  def test_info_is_optional
    assert_equal '', parse('info' => nil)[:info]
  end

  def test_name_is_required
    assert_invalid 'name is required', 'name' => nil
    assert_invalid 'name is required', 'name' => "  \t "
  end

  def test_length_limits
    assert_equal 100, parse('name' => 'a' * 100)[:name].length
    assert_invalid 'name is too long (max 100)', 'name' => 'a' * 101
    assert_invalid 'info is too long (max 500)', 'info' => 'a' * 501
  end

  def test_unknown_or_missing_map
    assert_invalid 'unknown map', 'map' => 'nope'
    assert_invalid 'unknown map', 'map' => '../con1'
    assert_invalid 'unknown map', 'map' => nil
  end

  def test_coordinates_must_be_numbers
    assert_invalid 'lat must be a number', 'lat' => 'abc'
    assert_invalid 'lat must be a number', 'lat' => ''
    assert_invalid 'lng must be a number', 'lng' => nil
    assert_invalid 'lng must be a number', 'lng' => '1,5'
  end

  def test_coordinates_must_be_inside_the_picture
    assert_invalid 'lat is outside the picture', 'lat' => '0.1'
    assert_invalid 'lat is outside the picture', 'lat' => '-256.1'
    assert_invalid 'lng is outside the picture', 'lng' => '-1'
    assert_invalid 'lng is outside the picture', 'lng' => '257'
    assert_invalid 'lat must be a number', 'lat' => 'NaN'
    assert_invalid 'lat must be a number', 'lat' => '-Infinity'
  end

  def test_range_edges_are_allowed
    result = parse('lat' => '-256', 'lng' => '256')

    assert_equal [-256.0, 256.0], result.values_at(:lat, :lng)
    assert_equal [0.0, 0.0], parse('lat' => '0', 'lng' => '0').values_at(:lat, :lng)
  end
end
