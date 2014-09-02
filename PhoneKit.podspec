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
  s.version          = "0.2.0"
  s.summary          = "An extension of TwilioSDK for easily making & receiving VoIP calls from inside your iOS app!"
  s.homepage         = "https://github.com/jconst/PhoneKit"
  s.license          = 'MIT'
  s.author           = { "Joseph Constantakis" => "jcon5294@gmail.com" }
  s.source           = { :git => "https://github.com/jconst/PhoneKit.git", :tag => s.version.to_s }

  s.platform     = :ios, '6.0'
  s.requires_arc = true

  s.subspec "Core" do |ss|
    ss.dependency 'TwilioSDK'
    ss.dependency 'ReactiveCocoa'
    ss.source_files = 'Pod/Classes/Core/'
  end

  s.subspec "UI" do |ss|
    ss.dependency 'PhoneKit/Core'
    ss.dependency 'JCDialPad'
    ss.dependency 'FontasticIcons'
    ss.source_files = 'Pod/Classes/UI/'
  end
end
