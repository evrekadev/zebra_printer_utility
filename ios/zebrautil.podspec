#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zebrautil.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zebrautil'
  s.version          = '0.0.1'
  s.summary          = 'A flutter plugin for working with zebra printers'
  s.description      = <<-DESC
A flutter plugin for working with zebra printers
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.static_framework = true
  s.frameworks = 'ExternalAccessory', 'QuartzCore'

  # libZSDK_API.a has no arm64 simulator slice, so it is linked for the device SDK only
  # (not through vendored_libraries, which would also link it into simulator builds).
  # The Swift code that uses it is compiled out on the simulator.
  s.preserve_paths = 'libZSDK_API.a'
  zsdk_search_paths = '"${PODS_ROOT}/../.symlinks/plugins/zebrautil/ios" "${PODS_ROOT}/zebrautil"'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -l"ZSDK_API"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => "$(inherited) #{zsdk_search_paths}"
  }
end
