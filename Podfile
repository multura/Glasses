platform :ios, '15.0'

target 'Glasses' do
  use_frameworks!
  pod 'libopus', :podspec => 'libopus.podspec'
  pod 'AIBudsSDK/ABMate',
      :git => 'https://github.com/topstepsmart/AIBuds-SDK-iOS.git',
      :tag => '1.0.0'
end

dynamic_frameworks = ['AFNetworking', 'WCDB.swift', 'WCDBOptimizedSQLCipher', 'SocketRocket']
static_frameworks = ['zipzap']
pre_install do |installer|
  installer.pod_targets.each do |pod|
    if dynamic_frameworks.include?(pod.name)
      def pod.static_framework?; false; end
      def pod.build_type; Pod::BuildType.dynamic_framework; end
    elsif static_frameworks.include?(pod.name)
      def pod.static_framework?; true; end
      def pod.build_type; Pod::BuildType.static_framework; end
    end
  end
end

def patch_private_header(installer, pod_subdir_pairs)
  pod_subdir_pairs.each do |pod_name, sub_dir|
    target_dir = sub_dir ? File.join(installer.sandbox.pod_dir(pod_name), sub_dir) : installer.sandbox.pod_dir(pod_name)
    next unless Dir.exist?(target_dir)

    Dir.glob(File.join(target_dir, '**', '*.{h,m}')).each do |file_path|
      file_content = File.read(file_path)
      next unless file_content.include?('#import <netinet6/in6.h>')
      original_mode = File.stat(file_path).mode
      File.chmod(original_mode | 0o200, file_path)
      File.write(file_path, file_content.gsub('#import <netinet6/in6.h>', ''))
      File.chmod(original_mode, file_path)
    end
  end
end

post_install do |installer|
  patch_private_header(installer, {'AFNetworking' => 'AFNetworking', 'Reachability' => nil})
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_project.native_targets.each do |target|
      next unless target.name == 'Glasses'

      target.build_configurations.each do |config|
        config.build_settings['OTHER_LDFLAGS'] = [
          '$(inherited)',
          '-framework',
          'MobileCoreServices'
        ]
      end
    end
    aggregate_target.user_project.save
  end
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
