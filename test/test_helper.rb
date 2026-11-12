# frozen_string_literal: true

# The app connects to GROUPMAP_DB when it is loaded, so point it at a
# throwaway file before requiring anything from lib/.
require 'fileutils'
require 'json'
require 'tmpdir'

ENV['RACK_ENV'] = 'test'
TEST_TMP = Dir.mktmpdir('groupmap-test')
ENV['GROUPMAP_DB'] = File.join(TEST_TMP, 'app.sqlite')

require 'minitest/autorun'
Minitest.after_run { FileUtils.rm_rf(TEST_TMP) }

require_relative '../lib/groupmap/app'

# Shared fixtures: temp map folders and fresh databases.
module TestHelpers
  ROOT = File.expand_path('..', __dir__)

  def tmpdir
    @tmpdir ||= Dir.mktmpdir('t', TEST_TMP)
  end

  # maps: { folder => manifest Hash, or a raw String written as-is }
  def make_pics(maps, blank = [])
    dir = File.join(tmpdir, 'pics')
    maps.each do |folder, manifest|
      FileUtils.mkdir_p(File.join(dir, folder))
      body = manifest.is_a?(String) ? manifest : JSON.generate(manifest)
      File.write(File.join(dir, folder, 'manifest.json'), body)
    end
    blank.each { |folder| File.binwrite(File.join(dir, folder, 'blank.png'), "\x89PNG fake") }
    dir
  end

  def fresh_db
    GroupMap::DB.connect(File.join(tmpdir, "db-#{rand(1 << 30)}.sqlite"))
  end
end

module Minitest
  class Test
    include TestHelpers
  end
end
