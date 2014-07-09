#
# Be sure to run `pod lib lint NAME.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "PhoneKit"
  s.version          = "0.1.0"
  s.summary          = "An extension of TwilioSDK for easily making/receiving VoIP calls from inside your iOS app!"
  s.homepage         = "https://github.com/jconst/PhoneKit"
  s.license          = 'MIT'
  s.author           = { "Joseph Constantakis" => "jcon5294@gmail.com" }
  s.source           = { :git => "https://github.com/jconst/PhoneKit.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.subspec "Core" do |ss|
    s.dependency 'TwilioSDK', '1.1.5-ce0a13e'
    s.dependency 'ReactiveCocoa'
    s.source_files = 'Pod/Classes/Core/'
  end

  s.subspec "UI" do |ss|
    s.dependency 'PhoneKit/Core'
    s.dependency 'JCDialPad'
    s.dependency 'FontasticIcons'
    s.source_files = 'Pod/Classes/UI/'
  end
end
