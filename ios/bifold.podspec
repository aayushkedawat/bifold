#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint bifold.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'bifold'
  s.version          = '1.0.0'
  s.summary          = 'Fold awareness for iPhone Duo and Android foldables.'
  s.description      = <<-DESC
Hinge angle, pose, fold regions, device capabilities, rear display and
fold-aware layout widgets, behind one API on iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/aayushkedawat/bifold'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Aayush Kedawat' => 'aayushkedawat@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'bifold/Sources/bifold/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'bifold_privacy' => ['bifold/Sources/bifold/PrivacyInfo.xcprivacy']}
end
