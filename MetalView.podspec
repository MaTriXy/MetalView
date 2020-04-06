Pod::Spec.new do |s|
  s.name = "MetalView"
  s.version = "1.0.1"

  s.summary = "A view with custom core animation metal layer"
  s.homepage = "https://github.com/eugenebokhan/MetalView"

  s.author = {
    "Eugene Bokhan" => "eugenebokhan@protonmail.com"
  }

  s.ios.deployment_target = "13.0"

  s.source = {
    :git => "https://github.com/eugenebokhan/MetalView.git",
    :tag => "#{s.version}"
  }
  s.source_files = "Sources/**/*.{swift,metal}"

  s.swift_version = "5.2"

  s.dependency "Alloy", "~> 0.14.1"
  s.dependency "SwiftMath", "~> 3.2.1"
end
