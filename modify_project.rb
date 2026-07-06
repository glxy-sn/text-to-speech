require 'xcodeproj'

project_path = '/Users/vio/XCodeProjects/C1_P4_Fix/tts_coach.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# 1. Remove swift-qwen3-tts package dependency
project.root_object.package_references.each do |pkg|
  if pkg.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    if pkg.repositoryURL && pkg.repositoryURL.include?('swift-qwen3-tts')
      pkg.remove_from_project
    end
  elsif pkg.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    if pkg.relative_path && pkg.relative_path.include?('swift-qwen3-tts')
      pkg.remove_from_project
    end
  end
end

target.package_product_dependencies.each do |dep|
  if dep.product_name == 'Qwen3TTS'
    dep.remove_from_project
  end
end

target.frameworks_build_phase.files.each do |file|
  if file.display_name && file.display_name.include?('Qwen3TTS')
    file.remove_from_project
  end
end

# 2. Add mlx-audio-swift package dependency
pkg_ref = project.root_object.package_references.find do |p| 
  p.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference) && p.repositoryURL && p.repositoryURL.include?('mlx-audio-swift') 
end
unless pkg_ref
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = 'https://github.com/Blaizzy/mlx-audio-swift'
  project.root_object.package_references << pkg_ref
end
pkg_ref.requirement = {
  'kind' => 'branch',
  'branch' => 'main'
}

# Add the modules from mlx-audio-swift
['MLXAudioCore', 'MLXAudioTTS', 'MLXAudioSTT'].each do |module_name|
  unless target.package_product_dependencies.any? { |d| d.product_name == module_name }
    product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product_dep.product_name = module_name
    product_dep.package = pkg_ref
    target.package_product_dependencies << product_dep
    
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = product_dep
    target.frameworks_build_phase.files << build_file
  end
end

project.save
puts "Successfully updated project dependencies."
