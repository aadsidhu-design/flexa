# Uncomment the next line to define a global platform for your project
platform :ios, '16.0'

target 'FlexaSwiftUI' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # MediaPipe Tasks Vision for BlazePose pose detection
  pod 'MediaPipeTasksVision', '~> 0.10.14'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
