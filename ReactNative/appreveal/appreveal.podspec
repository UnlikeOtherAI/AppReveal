Pod::Spec.new do |s|
  s.name             = 'AppReveal'
  s.version          = '0.4.0'
  s.summary          = 'Debug-only in-app MCP framework for React Native'
  s.description      = <<-DESC
    AppReveal embeds an MCP server inside your React Native app in debug builds,
    giving LLM agents native app control via standard MCP protocol.
  DESC

  s.homepage         = 'https://github.com/UnlikeOtherAI/AppReveal'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AppReveal' => 'hello@appreveal.dev' }
  s.source           = { :git => 'https://github.com/UnlikeOtherAI/AppReveal.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version = '5.9'

  s.source_files = 'ios/**/*.{h,m,mm,swift}'

  s.frameworks = 'Network'
  s.weak_frameworks = 'WebKit'

  s.dependency 'React-Core'
end
