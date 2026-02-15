# 🛺 Lanka Ride - Real-Time Tuk-Tuk Tracking & Zone Safety Analysis

A production-ready Flutter mobile application that provides real-time traffic zone analysis and driver safety features for tuk-tuk (auto-rickshaw) drivers in Sri Lanka.

## 📋 Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Key Features](#key-features)
- [API Documentation](#api-documentation)
- [Firebase Setup](#firebase-setup)
- [Building for Android](#building-for-android)
- [Troubleshooting](#troubleshooting)

---

## ✨ Features

### Core Functionality
- **Real-Time Driver Tracking** - Live location updates and driver markers on Google Maps
- **Traffic Zone Analysis** - AI-powered risk assessment based on union capacity, weather, and traffic patterns
- **Dynamic Zone Classification**:
  - 🔴 **Red Zone** - High Risk (Union strongholds)
  - 🟡 **Yellow Zone** - Medium Risk (Smart hustle opportunities)
  - 🟢 **Green Zone** - Safe (Prime spots or empty roads)
  
- **Online Driver Count** - Real-time display of active drivers in the area
- **Weather Integration** - Real-time rain detection via OpenWeather API
- **Smart Zone Recommendations** - ML-based predictions for safer driving zones

### User Features
- **User Authentication** - Firebase Auth with email/password
- **Driver Profiles** - Customizable vehicle color, license plate, and photo
- **Account Statistics** - Member since, vehicle info, online driver count
- **Dark/Light Theme Support** - System-aware theme switching

---

## 🏗 Tech Stack

### Frontend
- **Flutter** (3.10.8+) - Cross-platform mobile framework
- **Dart** - Programming language
- **Google Maps Flutter** - Real-time map integration
- **Flutter Riverpod** - State management

### Backend
- **Firebase**:
  - Authentication (Email/Password)
  - Firestore (Real-time database)
  - Storage (User photos)
  
- **Flask Server** (Python):
  - Traffic prediction endpoint
  - XGBoost ML model
  - Weather API integration

### Third-Party APIs
- **Google Maps Platform** - Map tiles and directions
- **OpenWeather API** - Real-time weather data
- **Geolocator** - GPS location services

### Build & Deployment
- **Android**: minSdk 26, targetSdk 34, compileSdk 36
- **iOS**: Supported (iOS 12+)

---

## 📦 Requirements

### System Requirements
- **Flutter**: 3.10.8 or higher
- **Dart**: 3.10.8 or higher
- **Android SDK**: API 26+ (minSdk), API 34 (targetSdk)
- **Java**: JDK 17+

### Development Setup
```bash
# Check versions
flutter --version
dart --version

# Get dependencies
flutter pub get

# Run analysis
flutter analyze
```

---

## 🚀 Installation

### 1. Clone Repository
```bash
git clone https://github.com/ruvindu-dulaksha/LankaRide.git
cd LankaRide/lanka_ride
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Setup Environment Variables
Create `.env` file in project root:
```env
# Firebase
FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY
FIREBASE_APP_ID_ANDROID=YOUR_ANDROID_APP_ID
FIREBASE_APP_ID_IOS=YOUR_IOS_APP_ID
FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID
FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
FIREBASE_STORAGE_BUCKET=YOUR_STORAGE_BUCKET
FIREBASE_IOS_BUNDLE_ID=com.example.lankaRide

# Google Maps
GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY

# Weather API
OPENWEATHER_API_KEY=YOUR_OPENWEATHER_API_KEY
```

---

## 🔧 Configuration

### Firebase Setup
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create new project "Lanka Ride"
3. Enable:
   - Authentication (Email/Password)
   - Firestore Database (Production mode)
   - Storage
4. Download `google-services.json` → `android/app/`
5. Download `GoogleService-Info.plist` → `ios/Runner/`

### Firestore Collections
```
users/
├── {userId}
│   ├── name: string
│   ├── email: string
│   ├── phone: string
│   ├── latitude: number
│   ├── longitude: number
│   ├── is_live: boolean
│   ├── vehicle_color: string
│   ├── license_plate: string
│   ├── rating: number
│   ├── total_trips: number
│   ├── created_at: timestamp
│   ├── last_updated: timestamp
│   └── photo_path: string
```

---

## 📂 Project Structure

```
lib/
├── main.dart                              # App entry point
├── core/
│   ├── api/
│   │   └── api_service.dart              # API clients
│   ├── constants/
│   │   └── app_constants.dart            # App configuration
│   ├── theme/
│   │   ├── app_theme.dart                # Colors & typography
│   │   └── theme_provider.dart           # Theme management
│   └── utils/
│       └── user_document_helper.dart
├── features/
│   ├── auth/
│   │   ├── providers/
│   │   │   └── auth_provider.dart              # Auth state management
│   │   └── screens/
│   │       ├── login_screen.dart
│   │       └── signup_screen.dart
│   ├── drivers/
│   │   ├── models/
│   │   │   └── driver_model.dart               # Driver data model
│   │   └── providers/
│   │       └── driver_provider.dart            # Driver queries & state
│   ├── map/
│   │   ├── screens/
│   │   │   └── map_screen.dart                # Main map & tracking
│   │   └── widgets/
│   │       ├── scanner_panel.dart             # Zone analysis UI
│   │       └── risk_dialog.dart               # Risk display
│   ├── profile/
│   │   └── screens/
│   │       └── profile_screen.dart            # User profile & settings
│   └── settings/
│       └── screens/
│           └── settings_screen.dart           # App settings
├── pubspec.yaml                           # Dependencies
└── README.md                              # This file
```

---

## 🎯 Key Features in Detail

### 1. Real-Time Driver Tracking
- Listens to Firestore `users` collection for `is_live: true`
- Updates driver markers every 5 seconds
- Filters drivers within 5km radius
- Excludes current user from nearby list

**Files**: [lib/features/drivers/providers/driver_provider.dart](lib/features/drivers/providers/driver_provider.dart), [lib/features/map/screens/map_screen.dart](lib/features/map/screens/map_screen.dart)

### 2. Traffic Zone Analysis
- Queries backend API with:
  - Current location (lat/lng)
  - Real-time weather data
  - Nearby driver count
  - Historical traffic data
  
- Returns zone classification with risk score

**Files**: [lib/core/api/api_service.dart](lib/core/api/api_service.dart), [server.py](server.py)

### 3. User Profile Management
- Editable fields: Name, Phone, Vehicle Color, License Plate
- Profile photo upload (local storage)
- Account stats: Member since, vehicle info
- Real-time online driver count

**Files**: [lib/features/profile/screens/profile_screen.dart](lib/features/profile/screens/profile_screen.dart)

---

## 📡 API Documentation

### Backend Prediction Endpoint
```
POST /predict

Request:
{
  "latitude": 6.9271,
  "longitude": 79.8612,
  "rain_level": 0.0,
  "union_density": 5
}

Response:
{
  "zone": "green|yellow|red",
  "message": "Zone description",
  "risk_score": 0.5,
  "metadata": {
    "location": "Near Town Hall",
    "union_capacity": 20,
    "rain_mm": 0.0,
    "poi_density": 45,
    "traffic_intensity": 1.2,
    "demand_level": "High (Evening Activity)"
  }
}
```

### Firestore Real-Time Listeners
```dart
// Online drivers count
db.collection('users')
  .where('is_live', isEqualTo: true)
  .snapshots()

// Nearby drivers (within 5km)
db.collection('users')
  .where('is_live', isEqualTo: true)
  .snapshots()
  // Then filter by distance
```

---

## 🔐 Firebase Setup

### Step 1: Create Firebase Project
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Create project
firebase projects create lanka-ride
```

### Step 2: Initialize Firestore
- Collection: `users` (auto-generated from user signup)
- No special rules needed (uses default auth)

### Step 3: Security Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own document
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
  }
}
```

---

## 📱 Building for Android

### Debug APK
```bash
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Configuration
- **API Level**: 26 (minSdk) → 34 (targetSdk)
- **Compile SDK**: 36
- **Key Store**: Debug keys (for release, generate signing key)

### Test on Device
```bash
flutter install
flutter run
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. Google Maps Not Showing
**Solution:** Verify API key in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml):
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ACTUAL_API_KEY"/>
```

#### 2. Firebase Connection Issues
**Solution:** Check `.env` file has correct credentials:
```bash
# Verify Firebase is initialized
flutter logs | grep "firebase"
```

#### 3. Location Permissions Not Working
**Solution:** Ensure permissions in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
```

#### 4. Tuk-Tuk Markers Not Appearing
**Solution:** Check console logs:
```
🚗 Firestore update: X live users total
✅ Added driver: name at Xkm
🎯 Final: X drivers within 5km radius
```

---

## 🔄 Real-Time Updates Flow

```
User changes is_live in Firebase
        ↓
Firestore listener triggers
        ↓
Driver queries execute:
  - activeDriversProvider (nearby drivers)
  - onlineDriversCountProvider (total count)
        ↓
Map updates with new markers
Scanner panel updates online count
```

---

## 📊 Data Models

### DriverModel
```dart
class DriverModel {
  final String id;
  final String name;
  final String email;
  final double? latitude;
  final double? longitude;
  final bool isLive;
  final String? licensePlate;
  final String? vehicleColor;
  final double rating;
  final int totalTrips;
  final DateTime? lastUpdated;
  final String? photoPath;
}
```

### PredictionResponse
```dart
class PredictionResponse {
  final String zone;
  final String message;
  final double riskScore;
  final Map<String, dynamic> metadata;
}
```

---

## 💻 Technology Stack Summary

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Frontend | Flutter + Dart | Cross-platform mobile app |
| State Mgmt | Riverpod v2 | Reactive state & side effects |
| Database | Firestore | Real-time user & driver data |
| Auth | Firebase Auth | User authentication |
| Maps | Google Maps Flutter | Map rendering & markers |
| Location | Geolocator | GPS positioning |
| Backend | Python Flask | ML zone prediction |
| ML Model | XGBoost | Traffic risk classification |

---

## 🎓 Learning Resources

- [Flutter Docs](https://flutter.dev/docs)
- [Riverpod Docs](https://riverpod.dev)
- [Firebase for Flutter](https://firebase.flutter.dev)
- [Google Maps API](https://developers.google.com/maps)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)

---

## 📞 Support

For issues and questions:
- Create GitHub Issue: [LankaRide Issues](https://github.com/ruvindu-dulaksha/LankaRide/issues)
- Project Documentation: [ARCHITECTURE_GUIDE.md](./ARCHITECTURE_GUIDE.md)

---

## 📄 License

This project is proprietary. All rights reserved.

---

## 🎉 Changelog

### v1.0.0 (February 15, 2026)
- ✅ Real-time driver tracking with Firestore
- ✅ AI-powered zone classification  
- ✅ User authentication & profiles
- ✅ Android 14 (API 34) support
- ✅ Online driver count tracking
- ✅ Weather-aware zone analysis
- ✅ Profile photo upload & storage
- ✅ Vehicle color & license plate customization

---

**Created by**: Ruvindu Dulaksha  
**Last Updated**: February 15, 2026

# API
dio: ^5.4.0

# Maps
google_maps_flutter: ^2.5.0
geolocator: ^10.1.0

# UI
google_fonts: ^6.1.0
flutter_animate: ^4.3.0
glassmorphism_ui: ^0.2.0

# Auth (optional)
firebase_core: ^2.24.2
firebase_auth: ^4.16.0
```

## 🎓 Academic Context

This is a university thesis project demonstrating:
- Real-world problem solving (union territory conflicts)
- Mobile app development best practices
- Clean architecture implementation
- AI integration (predictive modeling)
- User-centered design

## 📄 License

This project is for educational purposes.

---

**Note**: Replace `YOUR_API_KEY_HERE` with actual Google Maps API keys before deployment.
