# frozen_string_literal: true

require 'json'

module GroupMap
  # The group pictures available under public/group_pics/<folder>/manifest.json.
  # Manifests are re-read when a folder is added or a manifest changes, so a
  # restart is no longer needed after adding a picture.
  class MapCatalog
    def initialize(dir)
      @dir = dir
      @signature = nil
      @maps = []
      @mutex = Mutex.new
    end

    def all
      refresh
      @maps
    end

    def include?(folder)
      all.any? { |m| m['folder'] == folder }
    end

    # Path of the blank tile vips writes for the google layout, if present.
    def blank_tile(folder)
      return unless include?(folder)

      path = File.join(@dir, folder, 'blank.png')
      path if File.file?(path)
    end

    private

    def refresh
      paths = Dir.glob(File.join(@dir, '*', 'manifest.json'))
      signature = paths.map { |p| [p, File.mtime(p)] }.sort
      return if signature == @signature

      @mutex.synchronize do
        @maps = paths.filter_map { |p| load_manifest(p) }
                     .sort_by { |m| [m['year'].to_s, m['folder']] }
                     .reverse
        @signature = signature
      end
    end

    def load_manifest(path)
      data = JSON.parse(File.read(path))
      raise JSON::ParserError, 'manifest is not a JSON object' unless data.is_a?(Hash)

      data.merge('folder' => File.basename(File.dirname(path)))
    rescue JSON::ParserError, SystemCallError => e
      warn "groupmap: skipping #{path}: #{e.message}"
      nil
    end
  end
end
