#!/usr/bin/env ruby
# Programmatic Xcode project configuration for oh-my-just-open.
#
# Replaces the manual Xcode UI steps (Add Package, wire xcconfigs, set
# entitlements path, flip App Sandbox, share scheme) with a single idempotent
# Ruby pass over project.pbxproj.
#
# Prereqs: Xcode CLOSED, `gem install --user-install xcodeproj` (already on
# this machine at 1.27.0).
#
# Usage: ruby scripts/configure-project.rb
#
# Safe to re-run; checks state before mutating.

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH   = File.expand_path('../oh-my-just-open.xcodeproj', __dir__)
TARGET_NAME    = 'oh-my-just-open'
SPARKLE_URL    = 'https://github.com/sparkle-project/Sparkle'
ENTITLEMENTS   = 'Config/oh-my-just-open.entitlements'

abort "Project not found: #{PROJECT_PATH}" unless Dir.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

app_target   = project.targets.find { |t| t.name == TARGET_NAME }
tests_target = project.targets.find { |t| t.name == "#{TARGET_NAME}Tests" }
ui_target    = project.targets.find { |t| t.name == "#{TARGET_NAME}UITests" }
abort "App target #{TARGET_NAME} not found" unless app_target

puts "==> Configuring #{TARGET_NAME}"

# ---------------------------------------------------------------------------
# 1. File references for xcconfigs + entitlements (group: Config)
# ---------------------------------------------------------------------------
config_group = project.main_group['Config'] || project.main_group.new_group('Config', 'Config')

def find_or_add(group, filename)
  existing = group.files.find { |f| f.path == filename || f.display_name == filename }
  return existing if existing
  group.new_reference(filename)
end

version_xc   = find_or_add(config_group, 'Version.xcconfig')
dist_xc      = find_or_add(config_group, 'Distribution.xcconfig')
entitlements = find_or_add(config_group, 'oh-my-just-open.entitlements')

puts "    Added/found xcconfig + entitlements file refs in Config group"

# ---------------------------------------------------------------------------
# 2. Wire baseConfigurationReference on PROJECT level and APP TARGET level
#    Debug → Version.xcconfig, Release → Distribution.xcconfig
# ---------------------------------------------------------------------------
wire_configs = lambda do |configurations|
  configurations.each do |config|
    config.base_configuration_reference = (config.name == 'Debug' ? version_xc : dist_xc)
  end
end

wire_configs.call(project.build_configurations)
wire_configs.call(app_target.build_configurations)
puts "    Wired baseConfigurationReference on project + app target"

# ---------------------------------------------------------------------------
# 3. Clean target build settings: remove values that should flow from xcconfig
#    + flip App Sandbox ON + set entitlements path
# ---------------------------------------------------------------------------
SHADOWS = %w[MARKETING_VERSION CURRENT_PROJECT_VERSION DEVELOPMENT_TEAM MACOSX_DEPLOYMENT_TARGET].freeze

app_target.build_configurations.each do |config|
  SHADOWS.each { |k| config.build_settings.delete(k) }
  config.build_settings['ENABLE_APP_SANDBOX']     = 'YES'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ENTITLEMENTS
end
puts "    Cleaned shadowing target settings; flipped ENABLE_APP_SANDBOX = YES; set CODE_SIGN_ENTITLEMENTS"

# Strip MARKETING_VERSION/CURRENT_PROJECT_VERSION from project-level too if duplicated
project.build_configurations.each do |config|
  SHADOWS.each { |k| config.build_settings.delete(k) }
end

# ---------------------------------------------------------------------------
# 4. Link Sparkle product to the app target
# ---------------------------------------------------------------------------
sparkle_pkg = project.root_object.package_references.find do |r|
  r.respond_to?(:repositoryURL) && r.repositoryURL == SPARKLE_URL
end
abort "Sparkle package reference not found in project — expected at #{SPARKLE_URL}" unless sparkle_pkg

unless app_target.package_product_dependencies.any? { |d| d.product_name == 'Sparkle' }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package      = sparkle_pkg
  dep.product_name = 'Sparkle'
  app_target.package_product_dependencies << dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  app_target.frameworks_build_phase.files << build_file

  puts "    Linked Sparkle product to #{TARGET_NAME} target (packageProductDependencies + Frameworks phase)"
else
  puts "    Sparkle already linked to #{TARGET_NAME} (skipping)"
end

# ---------------------------------------------------------------------------
# 5. Save pbxproj
# ---------------------------------------------------------------------------
project.save
puts "==> Saved #{PROJECT_PATH}"

# ---------------------------------------------------------------------------
# 6. Create a SHARED scheme for the app target
# ---------------------------------------------------------------------------
shared_dir = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
FileUtils.mkdir_p(shared_dir)

scheme_path = File.join(shared_dir, "#{TARGET_NAME}.xcscheme")
if File.exist?(scheme_path)
  puts "==> Shared scheme already exists: #{scheme_path}"
else
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(app_target)
  scheme.add_test_target(tests_target) if tests_target
  scheme.add_test_target(ui_target) if ui_target
  scheme.set_launch_target(app_target)
  scheme.save_as(PROJECT_PATH, TARGET_NAME, true) # shared = true
  puts "==> Created shared scheme: #{scheme_path}"
end

puts ""
puts "Done. Next:"
puts "  - Generate Sparkle EdDSA key:  ./scripts/generate-sparkle-key.sh"
puts "  - Build verify:                xcodebuild -project oh-my-just-open.xcodeproj -scheme #{TARGET_NAME} -configuration Debug build"
