"""
Google Maps API Key Setup Helper

This script helps you set up Google Maps API keys for both Android and iOS.
Run this after getting your API key from Google Cloud Console.

Usage:
    python setup_maps_key.py YOUR_API_KEY_HERE
"""

import sys
import os
import re

def update_android_manifest(api_key):
    """Update Android AndroidManifest.xml with API key"""
    manifest_path = 'android/app/src/main/AndroidManifest.xml'
    
    try:
        with open(manifest_path, 'r') as file:
            content = file.read()
        
        # Replace placeholder with actual key
        updated_content = content.replace(
            'YOUR_GOOGLE_MAPS_API_KEY_HERE',
            api_key
        )
        
        with open(manifest_path, 'w') as file:
            file.write(updated_content)
        
        print(f"✅ Android: Updated {manifest_path}")
        return True
    except Exception as e:
        print(f"❌ Android: Error updating manifest - {e}")
        return False

def update_ios_appdelegate(api_key):
    """Update iOS AppDelegate.swift with API key"""
    appdelegate_path = 'ios/Runner/AppDelegate.swift'
    
    try:
        with open(appdelegate_path, 'r') as file:
            content = file.read()
        
        # Check if import already exists
        if 'import GoogleMaps' not in content:
            # Add import after UIKit import
            content = content.replace(
                'import UIKit',
                'import UIKit\nimport GoogleMaps'
            )
        
        # Check if GMSServices call already exists
        if 'GMSServices.provideAPIKey' not in content:
            # Add API key setup before return in application method
            content = content.replace(
                'GeneratedPluginRegistrant.register(with: self)',
                f'GeneratedPluginRegistrant.register(with: self)\n    GMSServices.provideAPIKey("{api_key}")'
            )
        else:
            # Replace existing key
            content = re.sub(
                r'GMSServices\.provideAPIKey\(".*?"\)',
                f'GMSServices.provideAPIKey("{api_key}")',
                content
            )
        
        with open(appdelegate_path, 'w') as file:
            file.write(content)
        
        print(f"✅ iOS: Updated {appdelegate_path}")
        return True
    except Exception as e:
        print(f"❌ iOS: Error updating AppDelegate - {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python setup_maps_key.py YOUR_API_KEY_HERE")
        print("\nGet your API key from:")
        print("https://console.cloud.google.com/google/maps-apis/credentials")
        sys.exit(1)
    
    api_key = sys.argv[1]
    
    if not api_key or api_key.startswith('-'):
        print("❌ Error: Please provide a valid API key")
        sys.exit(1)
    
    print("🔧 Setting up Google Maps API key...\n")
    
    android_success = update_android_manifest(api_key)
    ios_success = update_ios_appdelegate(api_key)
    
    print("\n" + "="*60)
    
    if android_success and ios_success:
        print("✅ Success! Google Maps API key configured for both platforms")
        print("\nNext steps:")
        print("1. Enable Maps SDK for both Android and iOS in Google Cloud Console")
        print("2. Run: flutter pub get")
        print("3. Run: flutter run")
    else:
        print("⚠️  Some configurations failed. Please check the errors above.")
        print("\nYou may need to configure the keys manually:")
        print("\nAndroid: android/app/src/main/AndroidManifest.xml")
        print("iOS: ios/Runner/AppDelegate.swift")
    
    print("="*60)

if __name__ == "__main__":
    main()
