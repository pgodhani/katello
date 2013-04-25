#
# Copyright 2013 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

# encoding: UTF-8

unless ENV['RAILS_ENV'] == 'build' # ok
  require_relative 'minitest_helper'
else
  # if we are in build environment of RPM we have only the bare minimum
  warn 'loading minimal test environment'
  require 'minitest/autorun'
  require 'rails'
  require 'minitest/rails'
end

class SourceCodeTest < MiniTest::Rails::ActiveSupport::TestCase

  class SourceCode
    include MiniTest::Assertions
    attr_reader :files

    # @param [Array<Regexp>] ignores
    def initialize(pattern, *ignores)
      @pattern = pattern || raise
      root     = File.expand_path File.join(File.dirname(__FILE__), '..')
      @files   = Dir.glob("#{root}/#{pattern}").select { |path| ignores.all? { |i| path !~ i } }
    end

    def each_file(&it)
      return to_enum :each_file unless it
      files.each { |file_path| it[File.read(file_path), file_path] }
    end

    def each_line(&it)
      return to_enum :each_line unless it
      each_file do |content, file_path|
        content.each_line.each_with_index { |line, line_number| it[line, line_number+1, file_path] }
      end
    end

    def check_lines(message = nil, &condition)
      bad_lines = each_line.map do |line, line_number, file_path|
        [line, line_number, file_path] unless condition.call line
      end.compact

      assert bad_lines.empty?,
             "#{message + "\n" if message}check lines:\n" + bad_lines.
                 map { |line, line_number, file_path| ' - %s:%d: %s' % [file_path, line_number, line.strip] }.
                 join("\n")
    end
  end

  describe 'formatting' do
    it 'does not have trailing whitespaces' do
      SourceCode.
          new('**/*.{rb,js,scss,haml}').
          check_lines { |line| line !~ / +$/ }
    end

    it 'does use soft-tabs' do
      SourceCode.
          new('**/*.{rb,js,scss,haml}',
              %r'(public|vendor)/assets/.*\.js').# tab is ok in minified files, its shorter than space
          check_lines { |line| line !~ /\t/ }
    end
  end

  describe 'best practices' do
    it 'does not use rescue Exception => e' do # ok
      SourceCode.
          new('**/*.rb').
          check_lines(<<-DOC) { |line| (line !~ /rescue +Exception/) ? true : line =~ /#\s?ok/ }
always rescue specific exception or at least `rescue => e` which equals to `rescue StandardError => e`
see http://stackoverflow.com/questions/10048173/why-is-it-bad-style-to-rescue-exception-e-in-ruby
      DOC
    end

    it 'does not use ENV variables' do
      SourceCode.
          new('**/*.rb',
              %r'config/(application|boot)\.rb',
              %r'test/minitest_helper\.rb', # TODO clean up minitest_helper
              %r'lib/util/puppet\.rb').
          check_lines(<<-DOC) { |line| (line !~ /ENV\[[^\]]+\]/) ? true : line =~ /#\s?ok/ }
Katello.config or Katello.early_config should be always used instead of ENV variables, Katello.config is
the single entry point to configuration. ENV variables are processed there.
      DOC
    end

    it 'does not use general rescue => e' do
      skip 'to be enabled'
    end
  end

  describe 'gettext' do
    it 'does not use interpolation or multiple anonymous placeholders' do
      doc = <<-DOC

Interpolation example:
  _("This is a malformed string with \#{interpolated_variable} within")
  # should be _("This is a malformed string with %s within") % interpolated_variable
Multiple anonymous placeholders:
  _("This is a malformed string with %s, and another %s") % [var1, var2]
  # should be _("This is a malformed string with %{var1}, and another %{var2}") %
  #              {:var1 => var1, :var2 => var2}
      DOC
      SourceCode.
          new('**/*.{rb,js,scss,haml}',
              %r'script/check-gettext\.rb',
              %r'test/source_code_test\.rb').
          check_lines doc do |line|
        line.scan(/_\((".*?"|'.*?')\)/).all? do |match|
          gettext_str = match.first
          gettext_str !~ /#\{.*?\}/ and gettext_str.scan(/%[a-z]/).size <= 1
        end
      end
    end
  end
end
