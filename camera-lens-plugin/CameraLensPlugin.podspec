
Pod::Spec.new do |s|
  s.name           = 'CameraLensPlugin'
  s.version        = '1.0.0'
  s.summary        = 'description'
  s.license        = 'license'
  s.homepage       = 'https://github.com/example/camera-lens-plugin'
  s.author         = 'author'
  s.source         = { :git => 'https://github.com/example/camera-lens-plugin', :tag => s.version.to_s }
  s.source_files   = 'ios/Sources/CameraLensPlugin/**/*.{swift,h,m,c}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version  = '5.9'
end