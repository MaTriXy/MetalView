Pod::Spec.new do |s|
  s.name = "MetalView"
  s.version = "1.0.0"

  s.summary = "A view with custom core animation metal layer"
  s.homepage = "https://github.com/eugenebokhan/MetalView"

  s.author = {
    "Eugene Bokhan" => "eugenebokhan@protonmail.com"
  }

  s.ios.deployment_target = "12.3"

  s.source = {
    :git => "https://github.com/eugenebokhan/MTLVideoTextureView.git",
    :tag => "#{s.version}"
  }
  s.source_files = "Sources/**/*.{swift,metal}"

  s.swift_version = "5.1"

  s.dependency "Alloy", "~> 0.13.2"
  s.dependency "SwiftMath", "~> 3.2.1"
end
