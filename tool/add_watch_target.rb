#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds (or repairs) the watchOS companion target in ios/Runner.xcodeproj.
#
# Kept as a script rather than a one-off hand edit of project.pbxproj: the repo
# is checked out as several worktrees, and a merge conflict in a hand-written
# pbxproj diff is far harder to resolve than re-running an idempotent script.
#
#   ruby tool/add_watch_target.rb
#
# Safe to run repeatedly. Existing targets are updated in place.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../ios/Runner.xcodeproj', __dir__)
WATCH_TARGET_NAME = 'CavernoWatch Watch App'
WATCH_SOURCE_DIR = 'CavernoWatch Watch App'
WIDGET_TARGET_NAME = 'CavernoWatchWidgetExtension'
WIDGET_SOURCE_DIR = 'CavernoWatchWidget'
APP_BUNDLE_ID = 'com.noguwo.apps.caverno'
WATCH_BUNDLE_ID = "#{APP_BUNDLE_ID}.watchkitapp"
WIDGET_BUNDLE_ID = "#{WATCH_BUNDLE_ID}.widget"
APP_GROUP_ID = "group.#{APP_BUNDLE_ID}"
WATCHOS_DEPLOYMENT_TARGET = '10.0'
DEVELOPMENT_TEAM = '89UG59TBNX'
EMBED_PHASE_NAME = 'Embed Watch Content'
WIDGET_EMBED_PHASE_NAME = 'Embed Foundation Extensions'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target not found' unless runner

watch = project.targets.find { |target| target.name == WATCH_TARGET_NAME }
if watch.nil?
  watch = project.new_target(
    :application,
    WATCH_TARGET_NAME,
    :watchos,
    WATCHOS_DEPLOYMENT_TARGET
  )
  puts "Created target #{WATCH_TARGET_NAME}"
else
  puts "Updating existing target #{WATCH_TARGET_NAME}"
end

# Build settings. Written on every run so a stale value cannot survive.
watch.build_configurations.each do |config|
  settings = config.build_settings
  settings['SDKROOT'] = 'watchos'
  # Required, not redundant with SDKROOT: archiving with
  # `-destination generic/platform=iOS` resolves each dependency's platform from
  # the destination, and without this the watch target is built against the iOS
  # SDK, where WatchKit does not exist.
  settings['SUPPORTED_PLATFORMS'] = 'watchsimulator watchos'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['WATCHOS_DEPLOYMENT_TARGET'] = WATCHOS_DEPLOYMENT_TARGET
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = WATCH_BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM[sdk=watchos*]'] = DEVELOPMENT_TEAM
  settings['DEVELOPMENT_TEAM[sdk=watchsimulator*]'] = DEVELOPMENT_TEAM
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_ENTITLEMENTS'] =
    "#{WATCH_SOURCE_DIR}/CavernoWatch.entitlements"

  # Single-target watch app layout (Xcode 14+): no separate WatchKit extension,
  # and the Info.plist is generated from these keys instead of a checked-in
  # file, which keeps the plist from drifting out of sync with the settings.
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_WKApplication'] = 'YES'
  settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = APP_BUNDLE_ID
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Caverno'
  settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] =
    'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown'

  # Version stamps follow the Flutter build so the watch app cannot be
  # submitted with a version that disagrees with its host app.
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
end

# Source group and files.
group = project.main_group.find_subpath(WATCH_SOURCE_DIR, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(WATCH_SOURCE_DIR)

source_root = File.join(File.dirname(PROJECT_PATH), WATCH_SOURCE_DIR)
swift_files = Dir.glob(File.join(source_root, '*.swift')).sort
raise "No Swift sources under #{source_root}" if swift_files.empty?

existing_paths = group.files.map(&:path)
swift_files.each do |path|
  name = File.basename(path)
  file = group.files.find { |f| f.path == name } ||
         group.new_reference(name)
  watch.add_file_references([file]) unless watch.source_build_phase.files_references.include?(file)
end

asset_dir = File.join(source_root, 'Assets.xcassets')
if Dir.exist?(asset_dir)
  assets = group.files.find { |f| f.path == 'Assets.xcassets' } ||
           group.new_reference('Assets.xcassets')
  unless watch.resources_build_phase.files_references.include?(assets)
    watch.add_resources([assets])
  end
end

# Drop references to sources that no longer exist, so a deleted view does not
# fail the build with a missing-file error on the next checkout.
stale = group.files.reject do |file|
  file.path == 'Assets.xcassets' || File.exist?(File.join(source_root, file.path))
end
stale.each do |file|
  puts "Removing stale reference #{file.path}"
  file.remove_from_project
end
puts "Sources: #{swift_files.map { |f| File.basename(f) }.join(', ')}" if existing_paths.empty?

# Runner embeds the watch app and depends on it.
runner.add_dependency(watch) unless runner.dependencies.any? { |d| d.target == watch }

embed = runner.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
    phase.name == EMBED_PHASE_NAME
end
if embed.nil?
  embed = runner.new_copy_files_build_phase(EMBED_PHASE_NAME)
  embed.dst_subfolder_spec = '16' # Products directory
  embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
end

unless embed.files_references.include?(watch.product_reference)
  build_file = embed.add_file_reference(watch.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Order matters, and getting it wrong fails the build rather than degrading:
# appended at the end, the copy lands after the Flutter and CocoaPods script
# phases and Xcode reports "Cycle inside Runner". Xcode's own template puts
# Embed Watch Content immediately after Resources, before anything that embeds
# frameworks or rewrites the binary, so place it there on every run.
resources_index = runner.build_phases.index do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
end
if resources_index
  desired_index = resources_index + 1
  current_index = runner.build_phases.index(embed)
  if current_index != desired_index
    runner.build_phases.delete_at(current_index)
    runner.build_phases.insert(desired_index, embed)
    puts "Moved #{EMBED_PHASE_NAME} to index #{desired_index} (was #{current_index})"
  end
end

# ---------------------------------------------------------------------------
# Smart Stack widget extension.
#
# Lives on the watch beside the app and reads its glance from the shared App
# Group. App Group containers are per-device, which is what makes this work:
# both processes run on the same watch. Nothing here crosses to the phone.
# ---------------------------------------------------------------------------

widget = project.targets.find { |target| target.name == WIDGET_TARGET_NAME }
if widget.nil?
  widget = project.new_target(
    :app_extension,
    WIDGET_TARGET_NAME,
    :watchos,
    WATCHOS_DEPLOYMENT_TARGET
  )
  puts "Created target #{WIDGET_TARGET_NAME}"
else
  puts "Updating existing target #{WIDGET_TARGET_NAME}"
end

widget.build_configurations.each do |config|
  settings = config.build_settings
  settings['SDKROOT'] = 'watchos'
  settings['SUPPORTED_PLATFORMS'] = 'watchsimulator watchos'
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['WATCHOS_DEPLOYMENT_TARGET'] = WATCHOS_DEPLOYMENT_TARGET
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM[sdk=watchos*]'] = DEVELOPMENT_TEAM
  settings['DEVELOPMENT_TEAM[sdk=watchsimulator*]'] = DEVELOPMENT_TEAM
  settings['CODE_SIGN_ENTITLEMENTS'] =
    "#{WIDGET_SOURCE_DIR}/CavernoWatchWidget.entitlements"
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Caverno'
  settings['INFOPLIST_KEY_NSExtensionPointIdentifier'] =
    'com.apple.widgetkit-extension'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
end

widget_group = project.main_group.find_subpath(WIDGET_SOURCE_DIR, true)
widget_group.set_source_tree('SOURCE_ROOT')
widget_group.set_path(WIDGET_SOURCE_DIR)

widget_root = File.join(File.dirname(PROJECT_PATH), WIDGET_SOURCE_DIR)
widget_sources = Dir.glob(File.join(widget_root, '*.swift')).sort
raise "No Swift sources under #{widget_root}" if widget_sources.empty?

widget_sources.each do |path|
  name = File.basename(path)
  file = widget_group.files.find { |f| f.path == name } ||
         widget_group.new_reference(name)
  unless widget.source_build_phase.files_references.include?(file)
    widget.add_file_references([file])
  end
  # The glance store is the contract between the two processes, so the watch
  # app compiles the same file rather than keeping a copy that can drift.
  next unless name == 'WatchGlanceStore.swift'
  unless watch.source_build_phase.files_references.include?(file)
    watch.add_file_references([file])
  end
end

watch.add_dependency(widget) unless watch.dependencies.any? { |d| d.target == widget }

widget_embed = watch.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
    phase.name == WIDGET_EMBED_PHASE_NAME
end
if widget_embed.nil?
  widget_embed = watch.new_copy_files_build_phase(WIDGET_EMBED_PHASE_NAME)
  widget_embed.dst_subfolder_spec = '13' # PlugIns directory
  widget_embed.dst_path = ''
end
unless widget_embed.files_references.include?(widget.product_reference)
  build_file = widget_embed.add_file_reference(widget.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Same ordering rule as Embed Watch Content: an embed phase appended after the
# phases that rewrite the binary produces a dependency cycle.
watch_resources_index = watch.build_phases.index do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
end
if watch_resources_index
  desired = watch_resources_index + 1
  current = watch.build_phases.index(widget_embed)
  if current != desired
    watch.build_phases.delete_at(current)
    watch.build_phases.insert(desired, widget_embed)
    puts "Moved #{WIDGET_EMBED_PHASE_NAME} to index #{desired} (was #{current})"
  end
end

project.save
puts "Saved #{PROJECT_PATH}"
