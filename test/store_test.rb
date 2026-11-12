# frozen_string_literal: true

require_relative 'test_helper'

class StoreTest < Minitest::Test
  def setup
    @db = fresh_db
    @store = GroupMap::Store.new(@db)
  end

  def add(name: 'Foo', info: '', map: 'con1', lat: -1.0, lng: 1.0)
    @store.add_marker(name: name, info: info, map: map, lat: lat, lng: lng)
  end

  def test_add_marker_creates_fluff_and_marker
    fluff_id = add(name: 'Foo', info: 'https://x')

    assert_equal [{ id: fluff_id, name: 'Foo', info: 'https://x' }], @store.fluffs
    assert_equal [{ id: 1, fluff_id: fluff_id, map: 'con1', lat: -1.0, lng: 1.0 }], @store.markers('con1')
  end

  def test_same_marker_twice_is_a_no_op
    2.times { add }

    assert_equal 1, @db[:fluff].count
    assert_equal 1, @db[:map].count
  end

  def test_same_fluff_in_two_places_reuses_the_fluff
    a = add(lat: -1.0)
    b = add(lat: -2.0)
    c = add(map: 'con2')

    assert_equal [a], [b, c].uniq
    assert_equal 1, @db[:fluff].count
    assert_equal 2, @store.markers('con1').size
    assert_equal 1, @store.markers('con2').size
  end

  def test_same_name_with_different_info_is_a_different_fluff
    refute_equal add(info: 'a'), add(info: 'b')
  end

  def test_fluffs_sorted_by_name
    %w[Zed Amy Moe].each_with_index { |n, i| add(name: n, lat: -i.to_f) }

    assert_equal(%w[Amy Moe Zed], @store.fluffs.map { |f| f[:name] })
  end

  def test_markers_of_unknown_map_is_empty
    add

    assert_empty @store.markers('other')
  end

  def test_schema_rejects_nulls
    assert_raises(Sequel::NotNullConstraintViolation) { @db[:fluff].insert(name: nil) }
    fid = @db[:fluff].insert(name: 'x')

    assert_equal '', @db[:fluff].where(id: fid).get(:info), 'info defaults to empty string'
    assert_raises(Sequel::NotNullConstraintViolation) { @db[:map].insert(fluff_id: fid, map: 'm', lat: nil, lng: 1) }
  end

  def test_schema_enforces_foreign_key_and_cascades
    assert_raises(Sequel::ForeignKeyConstraintViolation) { @db[:map].insert(fluff_id: 999, map: 'm', lat: 0, lng: 0) }

    fid = add
    @db[:fluff].where(id: fid).delete

    assert_equal 0, @db[:map].count
  end

  def test_map_column_is_indexed
    assert(@db.indexes(:map).values.any? { |i| i[:columns] == [:map] })
  end
end
