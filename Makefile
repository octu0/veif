.PHONY: wasm
wasm:
	swift package --swift-sdk swift-6.2.3-RELEASE_wasm plugin --allow-writing-to-package-directory js --use-cdn --output ./docs/swiftwasm/ --product wasm
	#swift build --swift-sdk swift-6.2.3-RELEASE_wasm -c release --product wasm
	
