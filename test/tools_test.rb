# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'rbconfig'

# The tools are standalone scripts, so they are run as subprocesses.
class ToolsTest < Minitest::Test
  TOOLS = File.join(TestHelpers::ROOT, 'tools')

  def run_tool(name, *, env: {})
    Open3.capture2e(env, RbConfig.ruby, File.join(TOOLS, name), *)
  end

  def path(name) = File.join(tmpdir, name)

  # ---- convert_db_to_v2.rb ----

  def old_db_current_layout
    db = Sequel.sqlite(path('v1.sqlite'))
    db.create_table(:fluff) do
      primary_key :id
      String :name
      String :info
    end
    db.create_table(:map) do
      primary_key :id
      Integer :fluff_id
      String :map
      Float :lat
      Float :lng
    end
    db[:fluff].import(%i[id name info], [[1, 'Foo &amp; Bar', 'https://t.co/foo'], [2, 'Foo & Bar ', 'https://t.co/foo'],
                                         [3, '', nil], [4, 'Evil', '<script>x</script>'], [5, 'NoInfo', nil]])
    db[:map].import(%i[fluff_id map lat lng], [[1, 'con1', -10, 20], [2, 'con1', -10, 20], [3, 'con1', -1, 1],
                                               [4, 'con1', -2, 2], [5, 'con2', -3, 3], [99, 'con1', -4, 4],
                                               [5, nil, -5, 5]])
    db.disconnect
    path('v1.sqlite')
  end

  def old_db_legacy_layout
    db = Sequel.sqlite(path('legacy.sqlite'))
    db.create_table(:fluff) do
      primary_key :id
      String :name
      String :map
      Float :lng
      Float :lat
      String :info
    end
    db[:fluff].import(%i[name map lng lat info], [['Old &lt;3', 'nfc', 10, -5, 'x'], ['Old &lt;3', 'nfc', 11, -6, 'x']])
    db.disconnect
    path('legacy.sqlite')
  end

  def test_convert_current_layout
    out, status = run_tool('convert_db_to_v2.rb', old_db_current_layout, path('v2.sqlite'))

    assert_predicate status, :success?, out
    assert_match(/fluff \+ map tables/, out)
    assert_match(/fluff_blank_skipped\s+1/, out)
    assert_match(/marker_duplicate_skipped\s+1/, out)
    assert_match(/marker_invalid_skipped\s+3/, out)
    assert_match(/1 fluff\(s\) contain HTML/, out)

    db = Sequel.sqlite(path('v2.sqlite'))

    assert_equal [['Evil', '<script>x</script>'], ['Foo & Bar', 'https://t.co/foo'], ['NoInfo', '']],
                 db[:fluff].order(:name).select_map(%i[name info])
    assert_equal [['con1', -10.0, 20.0, 'Foo & Bar'], ['con1', -2.0, 2.0, 'Evil'], ['con2', -3.0, 3.0, 'NoInfo']],
                 db[:map].join(:fluff, id: :fluff_id).order(Sequel[:map][:id])
                         .select_map([Sequel[:map][:map], :lat, :lng, :name])
  end

  def test_convert_legacy_layout
    out, status = run_tool('convert_db_to_v2.rb', old_db_legacy_layout, path('legacy_v2.sqlite'))

    assert_predicate status, :success?, out
    assert_match(/pre-2019/, out)

    db = Sequel.sqlite(path('legacy_v2.sqlite'))

    assert_equal [['Old <3', 'x']], db[:fluff].select_map(%i[name info])
    assert_equal [['nfc', -5.0, 10.0], ['nfc', -6.0, 11.0]], db[:map].order(:id).select_map(%i[map lat lng])
  end

  def test_convert_does_not_touch_the_old_file
    old = old_db_current_layout
    before = File.binread(old)
    run_tool('convert_db_to_v2.rb', old, path('v2.sqlite'))

    assert_equal before, File.binread(old)
  end

  def test_convert_refuses_to_overwrite_and_needs_an_input
    File.write(path('exists.sqlite'), '')
    out, status = run_tool('convert_db_to_v2.rb', old_db_current_layout, path('exists.sqlite'))

    refute_predicate status, :success?
    assert_match(/already exists/, out)

    out, status = run_tool('convert_db_to_v2.rb', path('missing.sqlite'), path('new.sqlite'))

    refute_predicate status, :success?
    assert_match(/No old database/, out)
  end

  # ---- transform.rb ----

  def transform_fixture
    db = GroupMap::DB.connect(path('t.sqlite'))
    store = GroupMap::Store.new(db)
    store.add_marker(map: 'con1', name: 'A', info: '', lat: -10.0, lng: 20.0)
    store.add_marker(map: 'con1', name: 'B', info: '', lat: -2.0, lng: 2.0)
    store.add_marker(map: 'con2', name: 'C', info: '', lat: -3.0, lng: 3.0)
    db.disconnect
    # new = 2 * old + (1, -1): an exact affine map
    pts = { 'old' => [[-10, 20], [-2, 2], [-3, 3], [-50, 100]] }
    pts['new'] = pts['old'].map { |lat, lng| [(2 * lat) + 1, (2 * lng) - 1] }
    File.write(path('pts.json'), JSON.generate(pts))
    [path('pts.json'), { 'GROUPMAP_DB' => path('t.sqlite') }]
  end

  def coords(map)
    db = Sequel.sqlite(path('t.sqlite'))
    db[:map].where(map: map).order(:id).select_map(%i[lat lng]).map { |c| c.map { |v| v.round(6) } }
  ensure
    db&.disconnect
  end

  def test_transform_dry_run_changes_nothing
    pts, env = transform_fixture
    out, status = run_tool('transform.rb', pts, 'con1', env: env)

    assert_predicate status, :success?, out
    assert_match(/Dry run: 2 markers would move/, out)
    assert_equal [[-10.0, 20.0], [-2.0, 2.0]], coords('con1')
  end

  def test_transform_apply_moves_only_that_map
    pts, env = transform_fixture
    out, status = run_tool('transform.rb', pts, 'con1', '--apply', env: env)

    assert_predicate status, :success?, out
    assert_match(/off by 0\.0000/, out)
    assert_equal [[-19.0, 39.0], [-3.0, 3.0]], coords('con1')
    assert_equal [[-3.0, 3.0]], coords('con2')
  end

  def test_transform_rejects_bad_control_points
    _, env = transform_fixture
    {
      { 'old' => [[0, 0], [1, 1]], 'new' => [[0, 0], [1, 1]] } => /at least 3/,
      { 'old' => [[0, 0], [1, 1], [2, 2]], 'new' => [[0, 0], [1, 1]] } => /same number/,
      { 'old' => [[0, 0], [1, 1], [2, 2]], 'new' => [[0, 0], [1, 1], [2, 2]] } => /collinear/
    }.each do |pts, message|
      File.write(path('bad.json'), JSON.generate(pts))
      out, status = run_tool('transform.rb', path('bad.json'), 'con1', env: env)

      refute_predicate status, :success?
      assert_match message, out
    end
  end

  def test_transform_unknown_map
    pts, env = transform_fixture
    out, status = run_tool('transform.rb', pts, 'nope', env: env)

    refute_predicate status, :success?
    assert_match(/No markers for map "nope"/, out)
  end

  # ---- prepare_pic.rb (argument checks only; tiling needs libvips) ----

  def test_prepare_pic_argument_checks
    out, status = run_tool('prepare_pic.rb')

    refute_predicate status, :success?
    assert_match(/Usage/, out)

    out, = run_tool('prepare_pic.rb', path('missing.jpg'), path('dest'))

    assert_match(/No such file/, out)

    File.write(path('pic.jpg'), 'x')
    FileUtils.mkdir_p(path('dest'))
    out, = run_tool('prepare_pic.rb', path('pic.jpg'), path('dest'))

    assert_match(/already exists/, out)
  end
end
