# frozen_string_literal: true

require_relative 'test_helper'

class MapCatalogTest < Minitest::Test
  def catalog(dir)
    GroupMap::MapCatalog.new(dir)
  end

  def test_lists_maps_with_folder_newest_year_first
    dir = make_pics('old' => { 'name' => 'Old', 'year' => '2017' },
                    'new' => { 'name' => 'New', 'year' => '2024' },
                    'noyear' => { 'name' => 'No year' })

    assert_equal(%w[new old noyear], catalog(dir).all.map { |m| m['folder'] })
    assert_equal 'New', catalog(dir).all.first['name']
  end

  def test_skips_broken_manifests_with_a_warning
    dir = make_pics('ok' => { 'name' => 'OK' }, 'bad' => '{nope', 'array' => '[1, 2]')
    maps = nil
    _, err = capture_io { maps = catalog(dir).all }

    assert_equal(['ok'], maps.map { |m| m['folder'] })
    assert_match(%r{skipping .*bad/manifest\.json}, err)
    assert_match(/not a JSON object/, err)
  end

  def test_missing_directory_means_no_maps
    assert_empty catalog(File.join(tmpdir, 'nowhere')).all
  end

  def test_picks_up_new_and_changed_manifests_without_restart
    dir = make_pics('a' => { 'name' => 'A' })
    cat = catalog(dir)

    assert_equal(['A'], cat.all.map { |m| m['name'] })

    make_pics('b' => { 'name' => 'B', 'year' => '2030' })

    assert_equal(%w[B A], cat.all.map { |m| m['name'] })

    path = File.join(dir, 'a', 'manifest.json')
    File.write(path, JSON.generate('name' => 'A2'))
    File.utime(Time.now + 10, Time.now + 10, path)

    assert_includes cat.all.map { |m| m['name'] }, 'A2'
  end

  def test_include
    cat = catalog(make_pics('con1' => {}))

    assert cat.include?('con1')
    refute cat.include?('con2')
    refute cat.include?('')
  end

  def test_blank_tile
    dir = make_pics({ 'with' => {}, 'without' => {} }, ['with'])
    cat = catalog(dir)

    assert_equal File.join(dir, 'with', 'blank.png'), cat.blank_tile('with')
    assert_nil cat.blank_tile('without')
    assert_nil cat.blank_tile('unknown')
  end
end
