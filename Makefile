.PHONY: bootstrap project test clean

bootstrap:
	./Scripts/fetch-libxray.sh
	command -v xcodegen >/dev/null || { echo "请先执行: brew install xcodegen"; exit 1; }
	xcodegen generate

project:
	command -v xcodegen >/dev/null || { echo "请先执行: brew install xcodegen"; exit 1; }
	xcodegen generate

test: bootstrap
	xcodebuild -project V2BoxKit.xcodeproj -scheme V2BoxKit -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf V2BoxKit.xcodeproj DerivedData Vendor
