# frozen_string_literal: true

module GroupMap
  # Validates and normalises the fields of a new marker (POST /add_fluff).
  # Text is stored raw; it is only ever rendered as text by the front-end.
  module MarkerInput
    NAME_MAX = 100
    INFO_MAX = 500
    # CRS.Simple: a whole tile pyramid fits in the 256x256 square at zoom 0,
    # top-left anchored, so valid points have lat in [-256, 0] and lng in [0, 256].
    LAT_RANGE = (-256.0..0.0)
    LNG_RANGE = (0.0..256.0)
    CONTROL_CHARS = /[\u0000-\u001f\u007f]/

    # Raised for invalid client input; becomes a 400 JSON response.
    class Invalid < StandardError; end

    module_function

    # Returns keyword arguments for Store#add_marker or raises Invalid.
    def parse(params, catalog)
      map = params['map'].to_s
      raise Invalid, 'unknown map' unless catalog.include?(map)

      {
        map: map,
        name: clean_text(params['name'], 'name', max: NAME_MAX, required: true),
        info: clean_text(params['info'], 'info', max: INFO_MAX),
        lat: coordinate(params['lat'], 'lat', LAT_RANGE),
        lng: coordinate(params['lng'], 'lng', LNG_RANGE)
      }
    end

    def clean_text(value, field, max:, required: false)
      text = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub('')
                  .unicode_normalize(:nfc).gsub(CONTROL_CHARS, ' ').strip
      raise Invalid, "#{field} is required" if required && text.empty?
      raise Invalid, "#{field} is too long (max #{max})" if text.length > max

      text
    end

    def coordinate(value, field, range)
      number = Float(value.to_s)
      raise Invalid, "#{field} is outside the picture" unless number.finite? && range.cover?(number)

      number
    rescue ArgumentError
      raise Invalid, "#{field} must be a number"
    end
  end
end
