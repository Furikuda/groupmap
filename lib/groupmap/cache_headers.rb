# frozen_string_literal: true

module GroupMap
  # Sets Cache-Control by path, including for static files (which Sinatra
  # serves before any `after` filter runs). Keeps a header a route set itself.
  #
  # - tiles and pictures: cached for a day
  # - /vendor/<lib>-<version>/: versioned path, cached for a year
  # - everything else (app JS/CSS, page, API): `no-cache`, i.e. the browser
  #   revalidates with Last-Modified each time, so a deploy is seen immediately.
  class CacheHeaders
    RULES = [
      [%r{\A/group_pics/}, 'public, max-age=86400'],
      [%r{\A/vendor/}, 'public, max-age=31536000, immutable']
    ].freeze
    DEFAULT = 'no-cache'

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      unless headers.key?('cache-control')
        path = env['PATH_INFO'].to_s
        headers['cache-control'] = RULES.find { |pattern, _| pattern.match?(path) }&.last || DEFAULT
      end
      [status, headers, body]
    end
  end
end
