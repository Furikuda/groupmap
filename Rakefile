# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

namespace :test do
  desc 'Front-end logic tests (QuickJS)'
  task :js do
    qjs = ENV.fetch('QJS', 'qjs')
    FileList['test/js/**/*_test.js'].each { |f| sh qjs, '-m', f }
  end
end

task default: %i[test test:js]
