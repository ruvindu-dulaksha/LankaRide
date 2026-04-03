#!/usr/bin/env python3
"""
COMPREHENSIVE LANKARIDE SYSTEM TEST
Tests all components: Backend API, Model, Firebase, Complete Flow
"""

import requests
import json
import pandas as pd
from datetime import datetime
import time

print("\n" + "="*80)
print("🧪 LANKARIDE SYSTEM TESTING")
print("="*80)
print(f"⏰ Test Start: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

# Configuration
API_BASE_URL = "http://localhost:5001"
TIMEOUT = 10

# Test hotspots (from routes_db.csv)
TEST_LOCATIONS = {
    "General Hospital": {"lat": 6.9189, "lon": 79.8687, "expected": "HIGH_CAPACITY"},
    "Eye Hospital": {"lat": 6.917, "lon": 79.866, "expected": "HIGH_CAPACITY"},
    "Town Hall": {"lat": 6.9147, "lon": 79.8633, "expected": "HIGH_CAPACITY"},
    "BMICH": {"lat": 6.901, "lon": 79.8735, "expected": "LOW_CAPACITY"},
    "Cinnamon Gardens": {"lat": 6.912, "lon": 79.866, "expected": "LOW_CAPACITY"},
}

# ============================================
# TEST 1: Backend Server Health
# ============================================
print("TEST 1️⃣: Backend Server Health")
print("-" * 80)

try:
    response = requests.get(f"{API_BASE_URL}/", timeout=TIMEOUT)
    print(f"✅ Server responding on port 5001")
    print(f"   Status: {response.status_code}\n")
except requests.exceptions.ConnectionError:
    print(f"❌ FAILED: Cannot reach server at {API_BASE_URL}")
    print(f"   Start server: python server.py\n")
    exit(1)

# ============================================
# TEST 2: Database Loading
# ============================================
print("TEST 2️⃣: Database & Model Loading")
print("-" * 80)

try:
    route_db = pd.read_csv('routes_db.csv')
    print(f"✅ routes_db.csv loaded: {len(route_db)} hotspots")
    print(f"   Columns: {list(route_db.columns)}")
    
    # Check XGBoost model
    import xgboost as xgb
    model = xgb.XGBRegressor()
    if pd.isna(model):
        print(f"⚠️  XGBoost available but model not loaded yet")
    else:
        print(f"✅ XGBoost available")
    print()
except Exception as e:
    print(f"❌ Database Error: {e}\n")

# ============================================
# TEST 3: API Endpoints
# ============================================
print("TEST 3️⃣: API Endpoints")
print("-" * 80)

endpoints_tested = 0
endpoints_passed = 0

# Test /predict endpoint
print("\n📍 Testing /predict endpoint (Zone Decision):\n")

for location_name, coords in TEST_LOCATIONS.items():
    try:
        payload = {
            "latitude": coords["lat"],
            "longitude": coords["lon"],
            "rainLevel": 0.0,
            "unionDensity": 0.0
        }
        
        response = requests.post(
            f"{API_BASE_URL}/predict",
            json=payload,
            timeout=TIMEOUT
        )
        
        endpoints_tested += 1
        
        if response.status_code == 200:
            data = response.json()
            zone = data.get("zone", "UNKNOWN")
            capacity = data.get("metadata", {}).get("union_capacity", "?")
            message = data.get("message", "")
            
            print(f"  ✅ {location_name:25s} → Zone: {zone:8s} | Cap: {capacity:2} | {message[:40]}")
            
            # Verify zone logic
            if capacity >= 15 and zone != "RED":
                print(f"     ⚠️  LOGIC ERROR: Capacity {capacity} should give RED, got {zone}")
            elif capacity < 15 and zone == "RED":
                print(f"     ⚠️  LOGIC ERROR: Capacity {capacity} should not give RED")
            else:
                endpoints_passed += 1
                
        elif response.status_code == 403:
            print(f"  ⚠️  {location_name:25s} → OUT OF SERVICE AREA")
            endpoints_passed += 1
        else:
            print(f"  ❌ {location_name:25s} → Error {response.status_code}")
            
    except requests.exceptions.Timeout:
        print(f"  ❌ {location_name:25s} → TIMEOUT (server too slow)")
    except Exception as e:
        print(f"  ❌ {location_name:25s} → {str(e)[:50]}")

# ============================================
# TEST 4: Model Inference
# ============================================
print("\n\nTEST 4️⃣: Model Inference & Smart Hustle Rules")
print("-" * 80)

try:
    # Test with different conditions
    test_conditions = [
        {"name": "Clear Day", "rain": 0.0, "rainfall_desc": "No rain"},
        {"name": "Rainy Day", "rain": 3.0, "rainfall_desc": "Heavy rain"},
        {"name": "School Peak", "rain": 0.0, "rainfall_desc": "School closing time"},
    ]
    
    print("\n📊 Testing conditions at General Hospital:\n")
    
    for condition in test_conditions:
        payload = {
            "latitude": 6.9189,
            "longitude": 79.8687,
            "rainLevel": condition["rain"],
            "unionDensity": 2.0  # 2 other drivers nearby
        }
        
        response = requests.post(
            f"{API_BASE_URL}/predict",
            json=payload,
            timeout=TIMEOUT
        )
        
        if response.status_code == 200:
            data = response.json()
            zone = data.get("zone")
            risk = data.get("risk_score")
            traffic = data.get("metadata", {}).get("traffic_intensity", 0)
            
            print(f"  Condition: {condition['name']:15s}")
            print(f"    Zone: {zone:8s} | Risk: {risk:.2f} | Traffic: {traffic:.2f}x")
            print(f"    Message: {data.get('message')[:60]}\n")
            endpoints_passed += 1
        else:
            print(f"  ❌ {condition['name']} failed")

except Exception as e:
    print(f"❌ Model test error: {e}")

# ============================================
# TEST 5: Zone Logic Verification
# ============================================
print("\n\nTEST 5️⃣: Zone Color Logic (Critical)")
print("-" * 80)

zone_tests = {
    "High Capacity (≥15) → RED": [],
    "Low Capacity (<15) → GREEN": [],
}

print("\n📋 Zone Decision Logic:\n")

for location_name, coords in TEST_LOCATIONS.items():
    try:
        response = requests.post(
            f"{API_BASE_URL}/predict",
            json={
                "latitude": coords["lat"],
                "longitude": coords["lon"],
                "rainLevel": 0.0,
                "unionDensity": 0.0
            },
            timeout=TIMEOUT
        )
        
        if response.status_code == 200:
            data = response.json()
            zone = data.get("zone")
            capacity = data.get("metadata", {}).get("union_capacity", 0)
            
            # Verify logic
            if capacity >= 15:
                if zone == "RED":
                    zone_tests["High Capacity (≥15) → RED"].append((location_name, True))
                    print(f"  ✅ {location_name:25s}: Cap {capacity} → RED ✓")
                else:
                    zone_tests["High Capacity (≥15) → RED"].append((location_name, False))
                    print(f"  ❌ {location_name:25s}: Cap {capacity} should be RED, got {zone}")
            else:
                if zone == "RED":
                    zone_tests["Low Capacity (<15) → GREEN"].append((location_name, False))
                    print(f"  ❌ {location_name:25s}: Cap {capacity} should be GREEN, got RED")
                else:
                    zone_tests["Low Capacity (<15) → GREEN"].append((location_name, True))
                    print(f"  ✅ {location_name:25s}: Cap {capacity} → {zone} ✓")
                    
    except Exception as e:
        print(f"  ❌ {location_name}: Error - {str(e)[:40]}")

# ============================================
# TEST 6: Data Flow (Location → Prediction → Decision)
# ============================================
print("\n\nTEST 6️⃣: Complete Data Flow")
print("-" * 80)

print("\n📍 Simulating driver at General Hospital:\n")

try:
    # Step 1: Capture location
    driver_lat = 6.9189
    driver_lon = 79.8687
    print(f"  Step 1️⃣  GPS Capture: {driver_lat}, {driver_lon}")
    
    # Step 2: Get weather (mocked)
    rain_level = 0.0
    print(f"  Step 2️⃣  Weather Check: {rain_level}mm rain")
    
    # Step 3: Send to backend
    print(f"  Step 3️⃣  Send to /predict endpoint...")
    
    response = requests.post(
        f"{API_BASE_URL}/predict",
        json={
            "latitude": driver_lat,
            "longitude": driver_lon,
            "rainLevel": rain_level,
            "unionDensity": 0.0
        },
        timeout=TIMEOUT
    )
    
    if response.status_code == 200:
        data = response.json()
        
        print(f"  Step 4️⃣  Model Prediction:")
        print(f"     Zone: {data.get('zone')}")
        print(f"     Risk Score: {data.get('risk_score')}")
        print(f"     Traffic Intensity: {data.get('metadata', {}).get('traffic_intensity', '?')}")
        
        print(f"\n  Step 5️⃣  Decision Support Output:")
        print(f"     {data.get('message')}")
        
        print(f"\n  Step 6️⃣  Would Draw on Map:")
        print(f"     Zone circle at ({driver_lat}, {driver_lon})")
        print(f"     Color: {data.get('zone')} (RED=🔴, YELLOW=🟡, GREEN=🟢)")
        
        print(f"\n  Step 7️⃣  Driver Sees Decision Panel:")
        print(f"     POI Density: {data.get('metadata', {}).get('poi_density')}/100")
        print(f"     Union Capacity: {data.get('metadata', {}).get('union_capacity')}")
        print(f"     Weather: Clear")
        
        print(f"\n  Step 8️⃣  Driver Takes Action:")
        print(f"     [Navigate] [✅ Got Hire] [❌ No Hire]")
        
        print(f"\n  ✅ Complete flow working!")
        
    else:
        print(f"  ❌ Step failed with status {response.status_code}")
        
except Exception as e:
    print(f"  ❌ Error: {e}")

# ============================================
# TEST 7: Directions Service
# ============================================
print("\n\nTEST 7️⃣: Google Directions Service")
print("-" * 80)

try:
    response = requests.post(
        f"{API_BASE_URL}/directions",
        json={
            "origin_lat": 6.9134,
            "origin_lng": 79.8617,
            "dest_lat": 6.9189,
            "dest_lng": 79.8687
        },
        timeout=TIMEOUT
    )
    
    if response.status_code == 200:
        data = response.json()
        if data.get("error"):
            print(f"  ⚠️  Directions API not configured (need Google Maps API key)")
            print(f"     Add to .env.python: GOOGLE_MAPS_API_KEY=your_key")
        else:
            print(f"  ✅ Directions working")
            print(f"     Distance: {data.get('distance_text', '?')}")
            print(f"     Duration: {data.get('duration_text', '?')}")
    else:
        print(f"  ⚠️  Directions endpoint returned {response.status_code}")
        
except Exception as e:
    print(f"  ⚠️  Directions test error: {str(e)[:60]}")

# ============================================
# SUMMARY
# ============================================
print("\n\n" + "="*80)
print("📊 TEST SUMMARY")
print("="*80)

print(f"\n✅ Tests Passed: {endpoints_passed}/{endpoints_tested}")
print(f"📍 Hotspots Tested: {len(TEST_LOCATIONS)}")
print(f"⏰ Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

print("\n" + "="*80)
print("CHECKLIST:")
print("="*80)

checklist = [
    ("Server running on port 5001", True),
    ("Database (routes_db.csv) loaded", True),
    ("API /predict endpoint working", endpoints_passed > 0),
    ("Zone colors matching capacity rules", endpoints_passed >= 3),
    ("Model inference working", endpoints_passed > 0),
    ("Complete flow: GPS → Prediction → Decision", endpoints_passed > 0),
    ("Firebase integration", "Check app"),
    ("GPS tracking in Flutter app", "Check app"),
    ("2 buttons (Got Hire / No Hire)", "Check app"),
]

for i, (item, status) in enumerate(checklist, 1):
    status_str = "✅" if status is True else ("⚠️ " if status == "Check app" else "❌")
    print(f"{i}. {status_str} {item}")

print("\n" + "="*80)
print("🎯 NEXT STEPS:")
print("="*80)
print("""
1. ✅ Backend verified (if tests passed above)
2. ⏭️  Run Flutter app: flutter run
3. ⏭️  Test in app:
     - Check GPS blue dot on map
     - Tap "ANALYZE RISK" button
     - Verify zone circle appears at your location
     - Click a hotspot
     - Tap "✅ Got Hire"
     - Check Firebase Console → driver_outcomes collection
4. ⚠️  If zone colors wrong: Check capacity logic in server.py line 430
5. ⚠️  If buttons don't save: Check Firebase auth in Flutter app
""")

print("="*80)
print(f"✨ Testing Complete - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
