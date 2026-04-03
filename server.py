import os
import requests
import pandas as pd
import xgboost as xgb
from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
from haversine import haversine, Unit
from dotenv import load_dotenv

# ==========================================
# INITIAL SETUP
# ==========================================

load_dotenv('.env.python')

app = Flask(__name__)
CORS(app)

OPENWEATHER_API_KEY = os.getenv('OPENWEATHER_API_KEY')
GOOGLE_MAPS_API_KEY = os.getenv('GOOGLE_MAPS_API_KEY')
MODEL_PATH = "traffic_model.json"
DATABASE_FILE = "routes_db.csv"

# ==========================================
# LOAD MODEL
# ==========================================

model = None
if os.path.exists(MODEL_PATH):
    try:
        model = xgb.XGBRegressor()
        model.load_model(MODEL_PATH)
        print("✅ Traffic Model Loaded")
    except Exception as e:
        print(f"❌ Model Load Error: {e}")
else:
    print("⚠️ Model file not found. Using fallback logic.")

# ==========================================
# LOAD DATABASE
# ==========================================

route_db = pd.DataFrame()
if os.path.exists(DATABASE_FILE):
    try:
        route_db = pd.read_csv(DATABASE_FILE)
        print(f"✅ Route Database Loaded ({len(route_db)} zones)")
    except Exception as e:
        print(f"❌ Database Error: {e}")
else:
    print("⚠️ routes_db.csv not found.")

# ==========================================
# LOAD SCHOOLS DATABASE (Location-Based)
# ==========================================

schools_db = pd.DataFrame()
schools_data = [
    # Colombo Schools (sample - add your actual schools)
    {"name": "Royal College", "lat": 6.9271, "lon": 80.7789, "type": "high"},
    {"name": "Colombo International School", "lat": 6.9180, "lon": 80.7850, "type": "high"},
    {"name": "Hindu College", "lat": 6.8920, "lon": 80.7650, "type": "high"},
    {"name": "Aquinas", "lat": 6.9305, "lon": 80.7770, "type": "high"},
    {"name": "Anna Wijesinhe Maha Vidyalaya", "lat": 6.8950, "lon": 80.7700, "type": "primary"},
    {"name": "Wesley College", "lat": 6.9160, "lon": 80.7600, "type": "high"},
    {"name": "St Joseph's College", "lat": 6.8850, "lon": 80.7800, "type": "high"},
    {"name": "Colombo North Primary School", "lat": 6.9450, "lon": 80.7900, "type": "primary"},
]

if len(schools_data) > 0:
    schools_db = pd.DataFrame(schools_data)
    print(f"✅ Schools Database Loaded ({len(schools_db)} schools)")
else:
    print("⚠️ Schools database not found.")

# ==========================================
# HELPER FUNCTIONS
# ==========================================

def debug_log(message):
    """Log messages with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")

def find_nearby_schools(lat, lon, radius_m=1000):
    """
    Find schools within specified radius (default 1km)
    Returns list of nearby schools and distance to nearest school
    
    Args:
        lat: User latitude
        lon: User longitude
        radius_m: Search radius in meters (default 1000m = 1km)
    
    Returns:
        nearby_schools: List of schools within radius
        nearest_school_dist: Distance to nearest school in meters
        has_schools_nearby: Boolean indicating if schools exist nearby
    """
    if schools_db.empty:
        return [], float('inf'), False
    
    nearby_schools = []
    min_dist = float('inf')
    
    for _, school in schools_db.iterrows():
        dist = haversine(
            (lat, lon), 
            (school['lat'], school['lon']), 
            unit=Unit.METERS
        )
        
        if dist < min_dist:
            min_dist = dist
        
        if dist <= radius_m:
            nearby_schools.append({
                "name": school['name'],
                "type": school['type'],
                "distance_m": round(dist, 0)
            })
    
    has_schools = len(nearby_schools) > 0
    
    debug_log(f"🏫 School Search: Found {len(nearby_schools)} schools within {radius_m}m | Nearest: {min_dist:.0f}m")
    
    return nearby_schools, min_dist, has_schools

def get_real_weather(lat, lon):
    """Fetch rain data (mm)"""
    try:
        if not OPENWEATHER_API_KEY:
            return 0.0

        url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={OPENWEATHER_API_KEY}"
        response = requests.get(url, timeout=3)

        if response.status_code == 200:
            data = response.json()

            if 'rain' in data and '1h' in data['rain']:
                return float(data['rain']['1h'])

            weather_id = data['weather'][0]['id']
            if 200 <= weather_id <= 531:
                return 5.0

        return 0.0
    except Exception:
        return 0.0

def get_colombo7_bounds():
    """
    Define geographic boundaries for Colombo 7 service area
    Based on trained routes_db coordinates
    
    Returns: dict with min/max lat/lon for bounding box
    """
    if route_db.empty:
        return None
    
    min_lat = route_db['lat'].min()
    max_lat = route_db['lat'].max()
    min_lon = route_db['lon'].min()
    max_lon = route_db['lon'].max()
    
    # Add 500m buffer (approximately 0.005 degrees) to account for nearby areas
    buffer = 0.005
    
    return {
        'min_lat': min_lat - buffer,
        'max_lat': max_lat + buffer,
        'min_lon': min_lon - buffer,
        'max_lon': max_lon + buffer
    }

def is_within_service_area(lat, lon):
    """
    Check if coordinates are within Colombo 7 service area
    
    Returns: (is_within: bool, distance_to_area_m: float)
    """
    bounds = get_colombo7_bounds()
    if bounds is None:
        return False, float('inf')
    
    # Check if within bounding box
    if (bounds['min_lat'] <= lat <= bounds['max_lat'] and 
        bounds['min_lon'] <= lon <= bounds['max_lon']):
        return True, 0
    
    # Calculate distance to nearest point in Colombo 7
    # Find closest route and return distance
    if route_db.empty:
        return False, float('inf')
    
    min_dist = float('inf')
    for _, row in route_db.iterrows():
        dist = haversine((lat, lon), (row['lat'], row['lon']), unit=Unit.METERS)
        min_dist = min(min_dist, dist)
    
    return False, min_dist

def perform_geo_lookup(lat, lon):
    """
    Find nearest union stand & POI density
    Returns: (location_name, capacity, poi_density, is_within_bounds)
    """
    if route_db.empty:
        return "Unknown Area", 5, 40, False

    # Check if user is within service area
    within_bounds, dist_to_area = is_within_service_area(lat, lon)
    
    nearest_name = "General Road"
    nearest_cap = 5
    nearest_poi = 40
    min_dist = float('inf')

    for _, row in route_db.iterrows():
        dist = haversine((lat, lon), (row['lat'], row['lon']), unit=Unit.METERS)

        if dist < min_dist:
            min_dist = dist
            nearest_name = row['name']
            nearest_cap = row['park_capacity']
            nearest_poi = row['poi_density']

    # STRICT BOUNDARY CHECK: Only serve locations close to trained routes (< 400m)
    # This ensures predictions are only made for areas where model was trained (Chapter 5: 400m influence zone)
    if min_dist > 400:
        debug_log(f"⚠️ OUT OF BOUNDS: Nearest route is {min_dist:.0f}m away (> 400m threshold)")
        return "Outside Service Area", 0, 0, False

    return nearest_name, nearest_cap, nearest_poi, within_bounds

def get_active_union_capacity(base_capacity):
    """Drivers reduce at night"""
    hour = datetime.now().hour
    if hour >= 22 or hour < 6:
        return int(base_capacity * 0.2)
    return base_capacity

def is_school_closed(hour, is_weekend, is_public_holiday):
    """
    Determine if school is closed.
    Children being at home/traveling affects traffic patterns.
    
    School Hours (Operating):
    - Primary School: 6 AM - 12 PM
    - High School: 6 AM - 1:30 PM
    
    School Closed When:
    - Weekend (Saturday/Sunday): always closed
    - Public Holiday: always closed  
    - Before 6 AM: closed (night time)
    - After 1:30 PM: closed (after high school)
    """
    
    # Weekends (Saturday=5, Sunday=6) are always school closed
    if is_weekend:
        return 1  # School closed
    
    # Public holidays = school closed
    if is_public_holiday:
        return 1  # School closed
    
    # Weekday hours check
    # School opens at 6 AM, closes after 1:30 PM (13:30)
    if hour < 6 or hour >= 14:  # Before 6 AM or after 2 PM (accounting for high school until 1:30 PM)
        return 1  # School closed
    else:
        return 0  # School is open (6 AM - 2 PM)

def is_school_closing_peak(hour):
    """
    PEAK DEMAND WINDOW: 12 PM - 1:30 PM (School Closing Time)
    
    During this window:
    - Primary school children getting picked up (12:00 PM)
    - High school children getting picked up (1:00 - 1:30 PM)
    - Parents commuting for pickup
    - School vehicles + Personal vehicles = massive traffic surge
    - High passenger demand LIKELY but not guaranteed
    
    NOTE: We observe traffic patterns and location context.
    Actual passenger availability must be verified in real-time.
    """
    return 12 <= hour < 14  # 12 PM to 1:59 PM (covers 12:00 - 1:30)


# ==========================================
# DEMAND ENGINE (Enhanced with School Closure Logic)
# ==========================================

def calculate_passenger_demand(poi_density, hour, is_weekend, traffic_intensity, school_closed, has_schools_nearby):
    """
    DEMAND ENGINE V8 - Location-Based + Traffic-Driven (NOT Time-Generic)
    
    CORE PRINCIPLE: Demand is driven by LOCATION (POI density) + ACTUAL TRAFFIC.
    Time and school status modify demand logically, NOT generically.
    
    ✅ NOVELTY - School Closing Peak (12 PM - 1:30 PM):
    - ONLY applies when BOTH conditions are true:
      1. Time is exactly 12 PM - 1:30 PM
      2. Schools are ACTUALLY nearby (location-based)
    - This is inelastic demand: parents MUST pick up children
    - +70% multiplier ONLY with this condition
    
    ❌ DO NOT: Say "school closed = high demand" globally
    - At 3 PM, schools are CLOSED (students already home)
    - This does NOT mean high demand everywhere
    - Demand at 3 PM depends on LOCATION (markets? offices? parks?)
    
    Traffic intensity is the PRIMARY demand indicator (independent of time).
    """

    base_demand = poi_density
    
    # ============================================================
    # SCHOOL CLOSING PEAK: 12 PM - 1:30 PM WITH schools nearby
    # This is THE location-aware research novelty
    # ============================================================
    if is_school_closing_peak(hour) and has_schools_nearby:
        peak_demand = poi_density * 1.7
        debug_log(f"🎓 SCHOOL PICKUP PEAK (12-1:30 PM near schools): Demand {peak_demand:.0f}")
        return peak_demand, "PEAK - School Pickup Surge"
    
    # ============================================================
    # TRAFFIC INTENSITY (Primary driver - location-aware)
    # ============================================================
    
    # Extreme congestion: high demand but gridlocked
    if traffic_intensity > 3.0:
        debug_log(f"🚗 HEAVY GRIDLOCK: High demand but slow")
        return base_demand * 1.5, "High - Heavy Traffic (Gridlock)"
    
    # Busy traffic: good throughput and demand
    if traffic_intensity > 2.0:
        debug_log(f"🚗 BUSY AREA: Normal demand with traffic")
        return base_demand * 1.2, "High - Busy Traffic Area"
    
    # Ghost town: fast but empty
    if traffic_intensity < 1.2:
        debug_log(f"👻 EMPTY ROAD: Fast but no demand")
        return base_demand * 0.3, "Low - Empty Road (No Demand)"
    
    # ============================================================
    # TIME-BASED CONTEXT (Secondary - only after traffic)
    # ============================================================
    
    # Night hours (always low regardless of traffic)
    if hour >= 22 or hour < 6:
        if is_weekend and hour < 2:
            return base_demand * 0.3, "Low - Late Night Weekend"
        return 0, "Closed - Night Hours"
    
    # Morning school hours (6 AM - 9 AM)
    if 6 <= hour < 9:
        return base_demand * 1.1, "High - Morning Rush"
    
    # Mid morning (9 AM - 11 AM): School drop-off continues
    if 9 <= hour < 11:
        return base_demand * 0.95, "Moderate - Mid Morning"
    
    # Late morning (11 AM - 12 PM): Before lunch rush
    if 11 <= hour < 12:
        return base_demand * 0.85, "Moderate - Late Morning"
    
    # Afternoon/Evening (12 PM onwards): Demand based on location, not school status
    if hour >= 12:
        if base_demand > 80:  # Busy area
            return base_demand * 1.1, "High - Busy Commercial Area"
        else:
            return base_demand * 0.95, "Moderate - Standard Area"
    
    # Default fallback
    return base_demand, "Moderate - Standard"


# ==========================================
# DECISION ENGINE (Improved Algorithm V2)
# ==========================================

def decide_smart_zone(capacity, rain, demand_score, demand_desc, traffic_time, school_closed, hour, has_schools_nearby, nearby_schools):
    """
    SMART ZONE DECISION ENGINE V4
    
    NOVELTY: Location-Based School Detection
    - Checks if user is near schools (within 1km)
    - Only applies school peak logic when schools actually nearby
    - Provides location-specific suggestions
    
    Improved Logic:
    - Considers school closure for better demand assessment
    - Recognizes peak school closing window (12-1:30 PM) when near schools
    - When school is closed: Families out = higher demand despite union risk
    - When school is open: School zones have different traffic patterns
    """
    
    traffic_intensity = traffic_time / 60.0
    
    # PEAK SCHOOL CLOSING CHECK (12 PM - 1:30 PM) - LOCATION-BASED
    school_closing_peak = is_school_closing_peak(hour)
    
    if school_closing_peak and has_schools_nearby:
        debug_log(f"🎓 LOCATION-BASED SCHOOL PEAK (12-1:30 PM): Near {len(nearby_schools)} schools")
        
        # During school closing near schools, even RED zones become YELLOW
        # because school pickup creates inelastic demand (parents MUST pick up children)
        if capacity >= 20:
            debug_log("🟡 YELLOW: Union territory BUT school closing peak near schools - consider this area")
            school_names = ", ".join([s['name'] for s in nearby_schools[:2]])
            return "YELLOW", f"School Closing Peak. Near: {school_names}. {demand_desc}"
        elif capacity >= 15:
            debug_log("🟢 GREEN: Moderate union BUT school closing peak near schools")
            return "GREEN", f"School Closing Peak Time. Near schools. {demand_desc}"
        else:
            debug_log("🟢 GREEN: Low union + school closing peak + nearby schools")
            return "GREEN", f"School Closing Peak Time. {demand_desc}"
    
    # LOG DECISION PROCESS
    debug_log(f"🎯 Decision Logic: cap={capacity}, rain={rain:.1f}mm, demand={demand_score:.0f}, traffic={traffic_intensity:.2f}x, school={'CLOSED' if school_closed else 'OPEN'}, schools_nearby={has_schools_nearby}")

    # 1) EXTREME UNION RISK (Stronghold territory - Capacity >= 15 per Chapter 5)
    if capacity >= 15:
        # Exception: High traffic + rain = worth considering despite union risk (Demand Overflow)
        if rain > 2.0 or demand_score > 100:
            debug_log("⚠️ YELLOW: High union risk BUT demand overflow (rain > 2.0mm or high demand)")
            return "YELLOW", f"Opportunity Override - High Demand in Risky Area. {demand_desc}"
        
        # Gridlock condition: traffic too heavy
        if traffic_intensity > 5.0:
            debug_log("🟡 YELLOW: High union + gridlock")
            return "YELLOW", f"High Risk Area with Gridlock. {demand_desc}"
        
        # Regular union territory
        debug_log("🔴 RED: High union capacity = restricted zone")
        return "RED", "High Union Risk. Stay Clear."
    
    # (Capacity < 15 = low union risk)
    # Proceed to traffic-based decision below

    # 2) GRIDLOCK (Very slow traffic = low earnings despite traffic)
    if traffic_intensity > 5.0:
        debug_log("🟡 YELLOW: Severe gridlock - slow movement")
        return "YELLOW", f"Severe Gridlock - Very Slow Traffic. {demand_desc}"

    # 3) GREEN ZONE - Prime Spot (High Traffic Intensity 2.0 < I <= 5.0)
    if traffic_intensity > 2.0:
        debug_log("🟢 GREEN - PRIME SPOT: Busy area with high traffic")
        return "GREEN", f"Prime Spot. High Activity. {demand_desc}"
    
    # 4) GREEN ZONE - Ghost Town (Low Traffic Intensity I < 1.2)
    if traffic_intensity < 1.2:
        debug_log("🟢 GREEN - GHOST TOWN: Empty road but safe")
        return "GREEN", f"Ghost Town. Safe but Low Activity. {demand_desc}"
    
    # 5) Default GREEN ZONE (Normal traffic 1.2 <= I <= 2.0)
    debug_log("🟢 GREEN: Standard area with normal traffic")
    return "GREEN", f"Safe Zone. {demand_desc}"

# ==========================================
# API ENDPOINTS
# ==========================================

@app.route('/predict', methods=['POST'])
def predict():
    """Main prediction endpoint"""
    try:
        data = request.json
        lat = data.get('latitude') or data.get('lat')
        lng = data.get('longitude') or data.get('lng')

        if lat is None or lng is None:
            return jsonify({"error": "GPS missing"}), 400

        # Client-side context (optional overrides from app)
        client_rain = data.get('rain_level', 0.0)
        nearby_drivers = data.get('union_density', 0.0)

        # 1) CONTEXT
        rain = get_real_weather(lat, lng)
        # Use client rain as fallback if weather API returned 0 but app detected rain
        if rain == 0.0 and client_rain > 0:
            rain = float(client_rain)

        # GEOGRAPHIC BOUNDARY CHECK (CRITICAL FOR RESEARCH CREDIBILITY)
        loc_name, base_cap, poi, is_within_bounds = perform_geo_lookup(lat, lng)
        
        # ⚠️ OUT-OF-BOUNDS CHECK
        if not is_within_bounds and base_cap == 0:
            debug_log(f"🚫 OUT OF SERVICE AREA: lat={lat}, lon={lng}")
            return jsonify({
                "error": "OUT_OF_SERVICE_AREA",
                "zone": "UNAVAILABLE",
                "message": "LankaRide Decision Support System is currently trained only for Colombo 7 area. Your location is outside the service area.",
                "metadata": {
                    "location": "Outside Service Area",
                    "service_area": "Colombo 7 (Colombo Central Business District)",
                    "limitation": "Model trained exclusively on Colombo 7 routes. Geographic restrictions implemented to maintain research integrity.",
                    "user_location": f"({lat:.4f}, {lng:.4f})",
                    "available_in": "Colombo 7 district (Colombo, Sri Lanka)"
                }
            }), 403

        now = datetime.now()
        hour = now.hour
        is_weekend = 1 if now.weekday() >= 5 else 0

        active_cap = get_active_union_capacity(base_cap)
        # Boost effective capacity if app detects many drivers nearby via Firebase
        if nearby_drivers > 0:
            active_cap = max(active_cap, int(nearby_drivers))

        # 2) SCHOOL CLOSURE CHECK
        # Extract is_public_holiday from data or default to 0
        is_public_holiday = data.get('is_public_holiday', 0)
        school_closed = is_school_closed(hour, is_weekend, is_public_holiday)
        
        debug_log(f"🏫 School Status: {'CLOSED' if school_closed else 'OPEN'} | Hour: {hour} | Weekend: {is_weekend} | Holiday: {is_public_holiday}")
        
        # 3) LOCATION-BASED SCHOOL DETECTION (500m - 1km radius)
        nearby_schools, nearest_school_dist, has_schools_nearby = find_nearby_schools(lat, lng, radius_m=1000)
        
        if has_schools_nearby:
            school_list = ", ".join([f"{s['name']} ({s['distance_m']:.0f}m)" for s in nearby_schools])
            debug_log(f"🎓 SCHOOLS DETECTED NEARBY: {school_list}")
        else:
            debug_log(f"🎓 No schools nearby (nearest: {nearest_school_dist:.0f}m away)")

        # 4) MODEL PREDICTION (with school closure context)
        if model:
            features = pd.DataFrame([[
                active_cap,
                poi,
                rain,
                hour,
                is_weekend,
                500,
                is_public_holiday,
                school_closed
            ]], columns=[
                'nearby_park_capacity',
                'poi_density',
                'rain_1h',
                'hour',
                'is_weekend',
                'distance_m',
                'is_public_holiday',
                'school_closed'
            ])

            pred_time = float(model.predict(features)[0])
            debug_log(f"✅ Model Prediction: {pred_time:.1f}s | Features: cap={active_cap}, poi={poi}, rain={rain}, school_closed={school_closed}, schools_nearby={has_schools_nearby}")
        else:
            pred_time = (active_cap * 5) + (rain * 10)
            debug_log(f"⚠️ Fallback Prediction: {pred_time:.1f}s (model not loaded)")

        traffic_intensity = pred_time / 60.0

        # 5) DEMAND (with school closure context + location-based school detection)
        demand_score, demand_desc = calculate_passenger_demand(
            poi, hour, is_weekend, traffic_intensity, school_closed, has_schools_nearby
        )

        # 6) DECISION (with school closure context, peak window detection, and location-based schools)
        zone_color, message = decide_smart_zone(
            active_cap, rain, demand_score, demand_desc, pred_time, school_closed, hour, has_schools_nearby, nearby_schools
        )

        risk_score = min(1.0, active_cap / 25.0)
        
        # Add school peak flag for mobile app to display
        school_peak = is_school_closing_peak(hour)

        return jsonify({
            "zone": zone_color,
            "message": message,
            "risk_score": round(risk_score, 2),
            "metadata": {
                "location": loc_name,
                "union_capacity": active_cap,
                "rain_mm": rain,
                "poi_density": poi,
                "predicted_traffic_sec": round(pred_time, 1),
                "predicted_traffic_time": round(pred_time, 1),
                "traffic_intensity": round(traffic_intensity, 2),
                "demand_level": demand_desc,
                "school_closed": bool(school_closed),
                "school_closing_peak": school_peak,
                "has_schools_nearby": has_schools_nearby,
                "nearby_schools": nearby_schools,
                "nearest_school_distance_m": round(nearest_school_dist, 1) if nearest_school_dist != float('inf') else None,
                "is_weekend": bool(is_weekend),
                "time_of_day": f"{hour:02d}:00",
                "model_used": model is not None,
                "service_area": "Colombo 7 (Colombo CBD)",
                "within_bounds": is_within_bounds,
                "coordinates": {"lat": lat, "lon": lng}
            }
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ==========================================
# GOOGLE DIRECTIONS (LIVE TRAFFIC ROUTES)
# ==========================================

@app.route('/directions', methods=['POST'])
def get_directions():
    """Get live traffic-aware route from Google Directions API"""
    try:
        data = request.json
        origin_lat = data.get('origin_lat')
        origin_lng = data.get('origin_lng')
        dest_lat = data.get('dest_lat')
        dest_lng = data.get('dest_lng')

        if not all([origin_lat, origin_lng, dest_lat, dest_lng]):
            return jsonify({"error": "Missing coordinates"}), 400

        if not GOOGLE_MAPS_API_KEY:
            print("⚠️ Google Maps API key not configured")
            # Return fallback response if API key not available
            return jsonify({
                "polyline": "",
                "distance_m": 0,
                "duration_sec": 0,
                "duration_traffic_sec": 0,
                "error": "API not configured"
            }), 200

        # Call Google Directions API with live traffic
        directions_url = (
            f"https://maps.googleapis.com/maps/api/directions/json?"
            f"origin={origin_lat},{origin_lng}&"
            f"destination={dest_lat},{dest_lng}&"
            f"key={GOOGLE_MAPS_API_KEY}&"
            f"departure_time=now&"
            f"traffic_model=best_guess"
        )

        response = requests.get(directions_url, timeout=10)

        if response.status_code == 200:
            data = response.json()
            
            if data['status'] != 'OK' or not data['routes']:
                return jsonify({"error": data.get('status', 'No route found')}), 400

            route = data['routes'][0]
            leg = route['legs'][0]

            return jsonify({
                "polyline": route['overview_polyline']['points'],
                "distance_m": leg['distance']['value'],
                "duration_sec": leg['duration']['value'],
                "duration_traffic_sec": leg.get('duration_in_traffic', {}).get('value', leg['duration']['value']),
                "distance_text": leg['distance']['text'],
                "duration_text": leg['duration']['text'],
                "duration_traffic_text": leg.get('duration_in_traffic', {}).get('text', leg['duration']['text']),
                "status": "OK"
            })
        else:
            print(f"❌ Google Directions error: {response.status_code}")
            return jsonify({"error": f"API error: {response.status_code}"}), 500

    except Exception as e:
        print(f"❌ Directions endpoint error: {e}")
        return jsonify({"error": str(e)}), 500

# ==========================================
# ROUTE CORRIDOR ANALYSIS (NEW FEATURE!)
# ==========================================

def predict_traffic_duration(lat, lon, capacity, poi_density, rain, hour, is_weekend, is_public_holiday, school_closed):
    """
    Predict traffic duration at a specific location
    Uses XGBoost model if available, fallback calculation otherwise
    """
    if model is not None:
        try:
            # Calculate distance from city center (simple approximation)
            city_center_lat, city_center_lon = 6.9271, 80.7744
            distance = haversine((lat, lon), (city_center_lat, city_center_lon), unit=Unit.METERS)
            
            features = pd.DataFrame([{
                'capacity': capacity,
                'poi_density': poi_density,
                'rain_1h': rain,
                'hour': hour,
                'is_weekend': is_weekend,
                'distance_m': distance,
                'is_public_holiday': is_public_holiday,
                'school_closed': school_closed
            }])
            
            pred_time = float(model.predict(features)[0])
            return pred_time
        except:
            pass
    
    # Fallback calculation
    return (capacity * 5) + (rain * 10) + (hour % 2 * 5)

def interpolate_route_points(start_lat, start_lon, end_lat, end_lon, num_points=7):
    """
    Create waypoints along the entire route from start to destination
    This allows analysis of the entire corridor, not just the starting point
    
    Example: Borella (start) to B'mich (destination)
    Returns 7 points along this route for comprehensive analysis
    """
    points = []
    for i in range(num_points):
        t = i / (num_points - 1)
        lat = start_lat + (end_lat - start_lat) * t
        lon = start_lon + (end_lon - end_lon) * t
        points.append({
            'lat': lat,
            'lon': lon,
            'segment': f"{i+1}/{num_points}",
            't': t
        })
    return points

@app.route('/predict-route', methods=['POST'])
def predict_route():
    """
    ROUTE CORRIDOR ANALYSIS - Analyzes entire path from start to destination
    
    This is what you asked for:
    - Driver in Borella (start) → B'mich (destination)
    - Analyzes EVERY segment of the route
    - Returns safety assessment for entire corridor
    - Gives better predictive accuracy
    
    USAGE:
    POST /predict-route
    {
        "start_lat": 6.927,
        "start_lon": 80.771,
        "end_lat": 6.932,
        "end_lon": 80.777,
        "vehicle_type": "tuk_tuk"  (optional)
    }
    """
    try:
        data = request.json
        start_lat = data.get('start_lat') or data.get('start_latitude')
        start_lon = data.get('start_lon') or data.get('start_longitude')
        end_lat = data.get('end_lat') or data.get('end_latitude')
        end_lon = data.get('end_lon') or data.get('end_longitude')
        
        if None in [start_lat, start_lon, end_lat, end_lon]:
            return jsonify({"error": "Missing coordinates. Need: start_lat, start_lon, end_lat, end_lon"}), 400
        
        # Get client context
        client_rain = data.get('rain_level', 0.0)
        is_public_holiday = data.get('is_public_holiday', 0)
        
        # Get real weather
        rain = get_real_weather(start_lat, start_lon)
        if rain == 0.0 and client_rain > 0:
            rain = float(client_rain)
        
        # Get time context
        now = datetime.now()
        hour = now.hour
        is_weekend = 1 if now.weekday() >= 5 else 0
        school_closed = is_school_closed(hour, is_weekend, is_public_holiday)
        
        # Get route corridor (7 waypoints along the path)
        waypoints = interpolate_route_points(start_lat, start_lon, end_lat, end_lon, num_points=7)
        
        segment_analyses = []
        zones = []
        capacities = []
        risks = []
        
        debug_log(f"📍 ANALYZING ROUTE CORRIDOR: ({start_lat:.4f},{start_lon:.4f}) → ({end_lat:.4f},{end_lon:.4f})")
        debug_log(f"🧭 Total waypoints: {len(waypoints)}")
        
        # Analyze each segment
        for waypoint in waypoints:
            wp_lat = waypoint['lat']
            wp_lon = waypoint['lon']
            
            # Get location analysis for this waypoint
            loc_name, base_cap, poi, is_within = perform_geo_lookup(wp_lat, wp_lon)
            
            # Skip if outside service area
            if not is_within and base_cap == 0:
                debug_log(f"⚠️ Waypoint {waypoint['segment']} outside service area")
                continue
            
            # Get real-time data at this point
            traffic_pred = predict_traffic_duration(
                lat=wp_lat,
                lon=wp_lon,
                capacity=base_cap,
                poi_density=poi,
                rain=rain,
                hour=hour,
                is_weekend=is_weekend,
                is_public_holiday=is_public_holiday,
                school_closed=school_closed
            )
            
            # Calculate demand
            demand, demand_desc = calculate_passenger_demand(
                poi_density=poi,
                hour=hour,
                is_weekend=is_weekend,
                traffic_intensity=traffic_pred / 60.0,
                school_closed=school_closed,
                has_schools_nearby=False  # Would need separate school lookup for each waypoint
            )
            
            # Get zone decision
            active_cap = get_active_union_capacity(base_cap)
            zone, msg = decide_smart_zone(
                capacity=active_cap,
                rain=rain,
                demand_score=demand,
                demand_desc=demand_desc,
                traffic_time=traffic_pred,
                school_closed=school_closed,
                hour=hour,
                has_schools_nearby=False,
                nearby_schools=[]
            )
            
            zones.append(zone)
            capacities.append(active_cap)
            risks.append(zone_to_risk_score(zone))
            
            segment_analyses.append({
                'segment': waypoint['segment'],
                'location': loc_name,
                'coordinates': {'lat': wp_lat, 'lon': wp_lon},
                'zone': zone,
                'message': msg,
                'metrics': {
                    'union_capacity': active_cap,
                    'poi_density': poi,
                    'traffic_duration_sec': traffic_pred,
                    'demand_score': demand,
                    'demand_type': demand_desc,
                    'rainfall_mm': rain
                }
            })
        
        # AGGREGATE ROUTE ANALYSIS
        def zone_to_risk_score(zone):
            return {'RED': 3, 'YELLOW': 2, 'GREEN': 1}.get(zone, 0)
        
        avg_risk = sum(risks) / len(risks) if risks else 0
        max_zone = max(zones, key=lambda z: zone_to_risk_score(z)) if zones else 'UNKNOWN'
        avg_capacity = sum(capacities) / len(capacities) if capacities else 0
        
        # Determine overall corridor safety
        if max_zone == 'RED':
            overall_zone = 'RED'
            overall_msg = "⚠️ HIGH RISK CORRIDOR: This route passes through high-risk union areas"
        elif 'RED' in zones or max_zone == 'YELLOW':
            overall_zone = 'YELLOW'
            overall_msg = "⚠️ CAUTION: Parts of this route have union risk or gridlock"
        else:
            overall_zone = 'GREEN'
            overall_msg = "✅ SAFE CORRIDOR: Route is generally safe with good opportunities"
        
        return jsonify({
            "route_analysis": {
                "overall_zone": overall_zone,
                "overall_message": overall_msg,
                "risk_level": f"{avg_risk:.1f}/3.0",
                "corridor_capacity_avg": f"{avg_capacity:.0f}",
                "corridor_segments": len(segment_analyses)
            },
            "segment_details": segment_analyses,
            "route_summary": {
                "start": {"lat": start_lat, "lon": start_lon},
                "end": {"lat": end_lat, "lon": end_lon},
                "zones_encountered": list(set(zones)),
                "highest_risk": max_zone,
                "context": {
                    "time": hour,
                    "is_weekend": bool(is_weekend),
                    "school_closed": bool(school_closed),
                    "rainfall_mm": rain,
                    "timestamp": now.isoformat()
                }
            }
        })
    
    except Exception as e:
        debug_log(f"❌ Route analysis error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    bounds = get_colombo7_bounds()
    return jsonify({
        "status": "running",
        "model_loaded": model is not None,
        "zones_loaded": len(route_db),
        "service_area": "Colombo 7",
        "geographic_bounds": bounds if bounds else None,
        "research_note": "LankaRide Smart Hustle Algorithm - Trained for Colombo 7 only. Out-of-bounds requests are rejected for research integrity."
    })

@app.route('/service-area', methods=['GET'])
def service_area():
    """Get service area information and bounds for map visualization"""
    bounds = get_colombo7_bounds()
    routes_list = []
    
    if not route_db.empty:
        routes_list = route_db[['name', 'lat', 'lon', 'park_capacity', 'poi_density']].to_dict('records')
    
    return jsonify({
        "service_area": "Colombo 7",
        "geographic_bounds": bounds,
        "trained_routes": routes_list,
        "coverage": "Colombo Central Business District - Colombo 7",
        "limitation": "Model trained exclusively on 14 strategic routes in Colombo 7. Predictions outside this area are not supported.",
        "research_integrity": "Geographic boundary enforcement ensures research credibility by preventing out-of-scope predictions."
    })

if __name__ == '__main__':
    print("=" * 80)
    print("🚀 LankaRide Smart Hustle Prediction Server Starting...")
    print("=" * 80)
    
    # Show service area information
    bounds = get_colombo7_bounds()
    if bounds:
        print("\n📍 SERVICE AREA CONFIGURATION:")
        print(f"   Region: Colombo 7 (Colombo CBD)")
        print(f"   Latitude Range: {bounds['min_lat']:.5f} to {bounds['max_lat']:.5f}")
        print(f"   Longitude Range: {bounds['min_lon']:.5f} to {bounds['max_lon']:.5f}")
        print(f"   ✅ Geographic boundary check: ENABLED")
        print(f"   ✅ Out-of-bounds rejection: ENABLED")
    
    print("\n📊 RESEARCH INTEGRITY:")
    print("   ✅ Model trained on: 14 routes in Colombo 7")
    print("   ✅ Geographic restrictions: ACTIVE")
    print("   ✅ Out-of-scope predictions: BLOCKED")
    print("   ✅ Service area enforcement: ACTIVE")
    
    print("\n" + "=" * 80)
    print("🚀 Server Running on http://0.0.0.0:5001")
    print("=" * 80)
    
    app.run(host='0.0.0.0', port=5001, debug=False)
