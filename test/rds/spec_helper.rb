require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/hooks/default'
require 'backticks'
require 'docker'
require 'compose_wrapper'
require 'retry_until'

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir = 'reports')]