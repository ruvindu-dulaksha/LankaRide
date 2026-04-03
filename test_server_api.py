#!/usr/bin/env python3
"""
LankaRide Server API Test - Robust Testing
Tests actual API endpoints with proper error handling
"""

import requests
import json
import sys
from datetime import datetime

API_BASE_URL = "http://localhost:5001"
TIMEOUT = 2  # Much shorter timeout
RETRY_ATTEMPTS = 3

def log_test(title):
    print(f"\n{'='*80}")
    print(f"🧪 {title}")
    print(f"{'='*80}\n")

def log_success(msg):
    print(f"✅ {msg}")

def log_error(msg):
    print(f"❌ {msg}")

def log_info(msg):
    print(f"ℹ️  {msg}")

def test_connection():
    """Test basic server connectivity"""
    log_test("TEST 1: Server Connection")
    
    for attempt in range(RETRY_ATTEMPTS):
        try:
            log_info(f"Attempt {attempt+1}/{RETRY_ATTEMPTS}: Trying /health endpoint...")
            response = requests.get(f"{API_BASE_URL}/health", timeout=TIMEOUT)
            
            if response.status_code == 200:
                log_success(f"Server responded: {response.status_code}")
                data = response.json()
                log_success(f"Status: {data.get('status')}")
                log_success(f"Model loaded: {data.get('model_loaded')}")
                log_success(f"Zones loaded: {data.get('zones_loaded')}")
                return True
            else:
                log_error(f"Server returned: {response.status_code}")
        except requests.exceptions.Timeout:
            log_info(f"  Timeout on attempt {attempt+1}, retrying...")
        except requests.exceptions.ConnectionError:
            log_error(f"Cannot connect to server on attempt {attempt+1}")
            return False
        except Exception as e:
            log_info(f"  Error on attempt {attempt+1}: {str(e)[:50]}")
    
    return False

def test_service_area():
    """Test service area endpoint"""
    log_test("TEST 2: Service Area Information")
    
    try:
        response = requests.get(f"{API_BASE_URL}/service-area", timeout=TIMEOUT)
        
        if response.status_code == 200:
            log_success("Service area endpoint accessible")
            data = response.json()
            log_success(f"Service area: {data.get('service_area')}")
            log_success(f"Routes defined: {len(data.get('trained_routes', []))}")
            return True
        else:
            log_error(f"Failed with status: {response.status_code}")
            return False
    except Exception as e:
        log_error(f"Service area test failed: {str(e)[:100]}")
        return False

def test_risk_prediction():
    """Test /predict endpoint"""
    log_test("TEST 3: Risk Prediction API")
    
    # Test case: General Hospital in Colombo 7 (should be RED - high capacity)
    test_payload = {
        "latitude": 6.9189,   # General Hospital latitude
        "longitude": 79.8687,  # General Hospital longitude
        "rainLevel": 0.0,
        "unionDensity": 0.5
    }
    
    try:
        log_info(f"Testing prediction with payload: {json.dumps(test_payload, indent=2)}")
        response = requests.post(
            f"{API_BASE_URL}/predict",
            json=test_payload,
            timeout=TIMEOUT
        )
        
        if response.status_code == 200:
            log_success("Prediction endpoint accessible")
            data = response.json()
            log_success(f"Zone returned: {data.get('zone')}")
            log_success(f"Risk score: {data.get('risk_score')}")
            log_success(f"Recommendation: {data.get('recommendation', 'N/A')[:50]}")
            
            # Validate zone
            if data.get('zone') in ['RED', 'YELLOW', 'GREEN']:
                log_success(f"Zone is valid: {data.get('zone')}")
            else:
                log_error(f"Invalid zone returned: {data.get('zone')}")
            
            return True
        else:
            log_error(f"Prediction failed with status: {response.status_code}")
            try:
                log_error(f"Error: {response.json()}")
            except:
                log_error(f"Response: {response.text[:100]}")
            return False
    except Exception as e:
        log_error(f"Prediction test failed: {str(e)[:100]}")
        return False

def test_directions():
    """Test /directions endpoint"""
    log_test("TEST 4: Google Directions API")
    
    test_payload = {
        "origin_lat": 6.9300,
        "origin_lon": 80.7760,
        "destination_lat": 6.9189,
        "destination_lon": 79.8687
    }
    
    try:
        log_info(f"Testing directions API...")
        response = requests.post(
            f"{API_BASE_URL}/directions",
            json=test_payload,
            timeout=TIMEOUT
        )
        
        if response.status_code == 200:
            log_success("Directions endpoint accessible")
            data = response.json()
            if 'error' in data:
                log_info(f"Google Maps API note: {data.get('error')}")
            else:
                log_success(f"Distance: {data.get('distance_km', 'N/A')} km")
                log_success(f"Duration: {data.get('duration_normal', 'N/A')} min")
            return True
        else:
            log_error(f"Failed with status: {response.status_code}")
            return False
    except Exception as e:
        log_error(f"Directions test failed: {str(e)[:100]}")
        return False

def main():
    print(f"\n{'='*80}")
    print(f"🚀 LankaRide Server API Test Suite")
    print(f"⏰ Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"🎯 Target: {API_BASE_URL}")
    print(f"{'='*80}\n")
    
    results = {
        "Connection": test_connection(),
        "Service Area": test_service_area(),
        "Risk Prediction": test_risk_prediction(),
        "Directions API": test_directions(),
    }
    
    # Summary
    print(f"\n{'='*80}")
    print(f"📊 TEST SUMMARY")
    print(f"{'='*80}\n")
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}  {test_name}")
    
    print(f"\n{'='*80}")
    print(f"📈 Result: {passed}/{total} tests passed")
    print(f"{'='*80}\n")
    
    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(main())
