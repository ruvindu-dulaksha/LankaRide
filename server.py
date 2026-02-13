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
# HELPER FUNCTIONS
# ==========================================

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

def perform_geo_lookup(lat, lon):
    """Find nearest union stand & POI density"""
    if route_db.empty:
        return "Unknown Area", 5, 40

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

    if min_dist > 400:
        return f"Near {nearest_name}", 5, 40

    return nearest_name, nearest_cap, nearest_poi

def get_active_union_capacity(base_capacity):
    """Drivers reduce at night"""
    hour = datetime.now().hour
    if hour >= 22 or hour < 6:
        return int(base_capacity * 0.2)
    return base_capacity


# ==========================================
# DEMAND ENGINE (Final Unified Version)
# ==========================================

def calculate_passenger_demand(poi_density, hour, is_weekend, traffic_intensity):
    """
    DEMAND ENGINE V4
    Traffic = People
    Empty Road = No People
    """

    demand_score = poi_density

    # 1) EVENT DETECTION (Traffic Spike)
    if traffic_intensity > 2.0:
        demand_score += 50
        return demand_score, "High (Active Crowd Detected)"

    # 2) GHOST TOWN DETECTION (Too Fast = Nobody There)
    if traffic_intensity < 1.2:
        demand_score *= 0.3
        return demand_score, "Low (Empty Road / Inactive)"

    # 3) TIME-BASED LOGIC
    if hour >= 22 or hour < 6:
        if is_weekend and hour < 2:
            return demand_score * 0.5, "Moderate (Night Life)"
        return 0, "Very Low (Sleeping Hours)"
    elif 7 <= hour < 9:
        return demand_score * 1.2, "High (Morning Rush)"
    elif 9 <= hour < 17:
        return demand_score * 1.0, "Moderate (Business Hours)"
    elif 17 <= hour < 21:
        return demand_score * 1.3, "High (Evening Activity)"

    return demand_score, "Moderate (Standard)"


# ==========================================
# DECISION ENGINE
# ==========================================

def decide_smart_zone(capacity, rain, demand_score, demand_desc, traffic_time):
    traffic_intensity = traffic_time / 60.0

    # 1) UNION RISK
    if capacity >= 15:
        if rain > 2.0 or demand_score > 100:
            return "YELLOW", f"High Demand! ({demand_desc})"
        return "RED", "High Union Risk. Avoid."

    # 2) GRIDLOCK (Too Slow = Bad Earnings)
    if traffic_intensity > 5.0:
        return "YELLOW", f"Heavy Traffic Area. ({demand_desc})"

    # 3) BUSY BUT PROFITABLE
    if traffic_intensity > 2.0:
        return "GREEN", f"Busy Area. {demand_desc}"

    # 4) NORMAL AREA
    if demand_score > 60:
        return "GREEN", f"Prime Spot. {demand_desc}"

    return "GREEN", "Safe but Low Activity."

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

        loc_name, base_cap, poi = perform_geo_lookup(lat, lng)

        now = datetime.now()
        hour = now.hour
        is_weekend = 1 if now.weekday() >= 5 else 0

        active_cap = get_active_union_capacity(base_cap)
        # Boost effective capacity if app detects many drivers nearby via Firebase
        if nearby_drivers > 0:
            active_cap = max(active_cap, int(nearby_drivers))

        # 2) MODEL PREDICTION
        if model:
            features = pd.DataFrame([[
                active_cap,
                poi,
                rain,
                hour,
                is_weekend,
                500,
                0
            ]], columns=[
                'nearby_park_capacity',
                'poi_density',
                'rain_1h',
                'hour',
                'is_weekend',
                'distance_m',
                'is_public_holiday'
            ])

            pred_time = float(model.predict(features)[0])
        else:
            pred_time = (active_cap * 5) + (rain * 10)

        traffic_intensity = pred_time / 60.0

        # 3) DEMAND
        demand_score, demand_desc = calculate_passenger_demand(
            poi, hour, is_weekend, traffic_intensity
        )

        # 4) DECISION
        zone_color, message = decide_smart_zone(
            active_cap, rain, demand_score, demand_desc, pred_time
        )

        risk_score = min(1.0, active_cap / 25.0)

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
                "model_used": model is not None
            }
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "running",
        "model_loaded": model is not None,
        "zones_loaded": len(route_db)
    })

if __name__ == '__main__':
    print("🚀 LankaRide Smart Prediction Server Running...")
    app.run(host='0.0.0.0', port=5001, debug=True)
