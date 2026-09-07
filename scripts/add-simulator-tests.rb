# Adds test targets to xtool's disposable generated project, never to product
# sources or the IPA configuration. Run after xtool dev generate-xcode-project.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
path = File.join(root, 'xtool/.xtool-tmp/JibunKit.xcodeproj')
project = Xcodeproj::Project.open(path)
app = project.targets.find { |target| target.name == 'JibunKit-App' }
abort 'Generated app target not found' unless app
abort 'Simulator tests already added' if project.targets.any? { |target| target.name == 'MigrationUITests' }

tests = project.new_target(:ui_test_bundle, 'MigrationUITests', :ios, '26.0')
tests.add_dependency(app)
tests.add_file_references(Dir[File.join(root, 'UITests/*.swift')].sort.map { |file| project.new_file(file) })
tests.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jibunkit.migration-tests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_TARGET_NAME'] = app.name
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][tests.uuid] = { 'TestTargetID' => app.uuid }
project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(path, 'MigrationUITests', true)
puts "Added MigrationUITests to #{path}"
