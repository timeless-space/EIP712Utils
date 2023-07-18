Pod::Spec.new do |spec|
  spec.name         = 'EIP712Utils'
  spec.homepage     = 'https://github.com/timeless-space/EIP712Utils'
  spec.authors      = { 'Toan Truong' => 'toan.truong@zien.vn' }
  spec.summary      = 'EIP712 utils for eth_signTypedData'
  spec.license      = { :type => 'MIT' }
  
  spec.swift_version          = '5.5'
  spec.ios.deployment_target  = '13.0'

  spec.version      = '1.0.0'
  spec.source       = { 
    :git => 'https://github.com/timeless-space/EIP712Utils.git', 
    :tag => spec.version.to_s 
  }

  spec.source_files  = "Sources/**/*.swift"

  spec.frameworks    = "Foundation"
  spec.dependency "web3swift"
  spec.dependency "BigInt"
end
