#!/usr/bin/env ruby
# frozen_string_literal: true

# Entry point. Prefer `bundle exec rackup` (config.ru); this also works with
# `bundle exec ruby index.rb` for quick local runs.
require_relative 'lib/groupmap/app'

GroupMap::App.run! if $PROGRAM_NAME == __FILE__
