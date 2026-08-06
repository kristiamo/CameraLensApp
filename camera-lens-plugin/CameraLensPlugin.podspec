require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'CameraLensPlugin'
  s.version        = package['version']
  s.summary        = package['description']
  s.license        = package['license']
  s.homepage       = 'https://github.com/example/camera-lens-plugin'
  s.author         = package['author']
  s.source         = { :git => 'https://github.com/example/camera-lens-plugin', :tag => s.version.to_s }
  s.source_files   = 'ios/Sources/CameraLensPlugin/**/*.{swift,h,m,c}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version  = '5.9'
end