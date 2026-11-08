Pod::Spec.new do |s|
  s.name             = 'custom_cursor'
  s.version          = '0.1.0'
  s.summary          = 'Custom cursor decoding and platform cursor management.'
  s.description      = <<-DESC
Custom cursor decoding and display for Flutter desktop apps.
                       DESC
  s.homepage         = 'https://git.hadak.org/dart/custom_cursor'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Hans Kokx' => 'hans.d.kokx@gmail.com' }
  s.source           = { :git => 'https://git.hadak.org/dart/custom_cursor.git', :tag => s.version.to_s }
  s.source_files     = 'custom_cursor/Sources/custom_cursor/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.swift_version    = '5.9'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end