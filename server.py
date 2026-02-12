import os
import requests
import pandas as pd
import numpy as np
import xgboost as xgb
from flask import Flask, request, jsonify, render_template_string, session, redirect, url_for
from flask_cors import CORS
from datetime import datetime, timedelta
from haversine import haversine, Unit # pip install haversine
from dotenv import load_dotenv

# Load environment variables
load_dotenv('.env.python')

app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY')
if not app.secret_key:
    raise ValueError('FLASK_SECRET_KEY must be set in .env.python file')
CORS(app)

# ==========================================
# ADMIN CREDENTIALS (Load from .env.python)
# ==========================================
ADMIN_EMAIL = os.getenv('ADMIN_EMAIL')
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD')

if not ADMIN_EMAIL or not ADMIN_PASSWORD:
    raise ValueError('ADMIN_EMAIL and ADMIN_PASSWORD must be set in .env.python file')

# ==========================================
# GLOBAL STATE FOR TESTING
# ==========================================
test_rain_level = 0.0
test_union_density = 0.0
test_logs = []

def log_test(message):
    """Log test activities"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_entry = f"[{timestamp}] {message}"
    test_logs.append(log_entry)
    if len(test_logs) > 100:  # Keep last 100 logs
        test_logs.pop(0)
    print(log_entry)

# ==========================================
# AUTHENTICATION
# ==========================================
@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    """Admin login page"""
    if request.method == 'POST':
        email = request.form.get('email')
        password = request.form.get('password')
        
        if email == ADMIN_EMAIL and password == ADMIN_PASSWORD:
            session['admin_logged_in'] = True
            session.permanent = True
            app.permanent_session_lifetime = timedelta(hours=24)
            log_test(f"✅ Admin logged in: {email}")
            return redirect(url_for('admin_dashboard'))
        else:
            error = "❌ Invalid credentials"
            log_test(f"⚠️ Failed login attempt: {email}")
            return render_template_string(LOGIN_HTML, error=error)
    
    return render_template_string(LOGIN_HTML)

@app.route('/admin/logout')
def admin_logout():
    """Admin logout"""
    session.clear()
    log_test("👋 Admin logged out")
    return redirect(url_for('admin_login'))

def admin_required(f):
    """Decorator to require admin authentication"""
    from functools import wraps
    
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('admin_logged_in'):
            return redirect(url_for('admin_login'))
        return f(*args, **kwargs)
    
    return decorated_function

# ==========================================
# ADMIN DASHBOARD
# ==========================================
@app.route('/admin')
@app.route('/admin/dashboard')
@admin_required
def admin_dashboard():
    """Admin dashboard page"""
    return render_template_string(DASHBOARD_HTML, 
                                 rain_level=test_rain_level,
                                 union_density=test_union_density,
                                 logs=test_logs[-20:])  # Last 20 logs

# ==========================================
# WEATHER TEST ENDPOINT (For Verification)
# ==========================================
@app.route('/test-weather', methods=['GET'])
def test_weather():
    """Test endpoint to verify weather API is working"""
    lat = request.args.get('lat', 6.9271, type=float)  # Colombo default
    lng = request.args.get('lng', 79.8612, type=float)
    
    print(f"\n🧪 Testing Weather API for ({lat}, {lng})...")
    rain = get_real_weather(lat, lng)
    
    return jsonify({
        'status': 'success',
        'latitude': lat,
        'longitude': lng,
        'rain_mm': rain,
        'api_key_active': OPENWEATHER_API_KEY is not None,
        'message': f'✅ Real rain data fetched: {rain}mm'
    })

# ==========================================
# ADMIN API ENDPOINTS
# ==========================================
@app.route('/admin/api/set-parameters', methods=['POST'])
@admin_required
def admin_set_parameters():
    """Set test parameters"""
    global test_rain_level, test_union_density
    
    data = request.json
    test_rain_level = float(data.get('rain_level', 0))
    test_union_density = float(data.get('union_density', 0))
    
    log_test(f"⚙️ Parameters updated: Rain={test_rain_level}, Density={test_union_density}")
    
    return jsonify({
        'status': 'success',
        'rain_level': test_rain_level,
        'union_density': test_union_density
    })

@app.route('/admin/api/test-predict', methods=['POST'])
@admin_required
def admin_test_predict():
    """Test prediction with admin parameters"""
    data = request.json
    lat = float(data.get('latitude', 6.9271))
    lng = float(data.get('longitude', 79.8612))
    
    log_test(f"🧪 Test prediction: Lat={lat}, Lng={lng}, Rain={test_rain_level}, Density={test_union_density}")
    
    # Simulate prediction (will call the same logic)
    try:
        response = requests.post(
            'http://localhost:5001/predict',
            json={
                'latitude': lat,
                'longitude': lng,
                'rain_level': test_rain_level,
                'union_density': test_union_density
            },
            timeout=5
        )
        result = response.json()
        log_test(f"✅ Prediction result: {result['zone']}")
        return jsonify(result)
    except Exception as e:
        log_test(f"❌ Prediction error: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/api/logs')
@admin_required
def admin_get_logs():
    """Get test logs"""
    return jsonify({'logs': test_logs})

@app.route('/admin/api/clear-logs', methods=['POST'])
@admin_required
def admin_clear_logs():
    """Clear test logs"""
    global test_logs
    test_logs = []
    log_test("🗑️ Logs cleared")
    return jsonify({'status': 'success', 'message': 'Logs cleared'})

# ==========================================
# DRIVER TRACKING ENDPOINTS (For real driver data)
# ==========================================
@app.route('/drivers/nearby', methods=['GET'])
def get_nearby_drivers():
    """
    Get nearby active drivers
    Query params: latitude, longitude, radius_km (default 5)
    Returns list of active drivers within radius
    """
    try:
        user_lat = float(request.args.get('latitude', 0))
        user_lng = float(request.args.get('longitude', 0))
        radius_km = float(request.args.get('radius_km', 5))
        
        if user_lat == 0 or user_lng == 0:
            return jsonify({'error': 'Missing latitude/longitude'}), 400
        
        log_test(f"🚗 Query nearby drivers: Lat={user_lat}, Lng={user_lng}, Radius={radius_km}km")
        
        # This endpoint connects to Firebase via Flutter
        # The actual driver data is fetched directly from Firebase Firestore in the app
        # This is just a reference endpoint for backend integration
        
        return jsonify({
            'status': 'success',
            'message': 'Use Firebase Firestore for real-time driver data',
            'drivers': [],
            'note': 'Driver tracking is handled by Firebase Firestore with real-time updates'
        })
        
    except Exception as e:
        log_test(f"❌ Error fetching nearby drivers: {str(e)}")
        return jsonify({'error': str(e)}), 500

# ==========================================
# HTML TEMPLATES
# ==========================================
LOGIN_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lanka Ride - Admin Login</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .login-container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            width: 100%;
            max-width: 400px;
        }
        
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .login-header h1 {
            color: #333;
            font-size: 28px;
            margin-bottom: 10px;
        }
        
        .login-header p {
            color: #666;
            font-size: 14px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            color: #333;
            font-weight: 500;
        }
        
        .form-group input {
            width: 100%;
            padding: 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .login-btn {
            width: 100%;
            padding: 12px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s;
        }
        
        .login-btn:hover {
            transform: translateY(-2px);
        }
        
        .error {
            background: #fee;
            color: #c33;
            padding: 12px;
            border-radius: 5px;
            margin-bottom: 20px;
            text-align: center;
            font-size: 14px;
        }
        
        .credentials-hint {
            background: #f0f8ff;
            border-left: 4px solid #667eea;
            padding: 12px;
            margin-top: 20px;
            font-size: 12px;
            color: #666;
        }
        
        .credentials-hint strong {
            display: block;
            margin-bottom: 5px;
            color: #333;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-header">
            <h1>🛡️ Admin Panel</h1>
            <p>Lanka Ride Developer Console</p>
        </div>
        
        {% if error %}
        <div class="error">{{ error }}</div>
        {% endif %}
        
        <form method="POST">
            <div class="form-group">
                <label for="email">Email/Username</label>
                <input type="text" id="email" name="email" required autofocus>
            </div>
            
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" id="password" name="password" required>
            </div>
            
            <button type="submit" class="login-btn">🔓 Login to Admin Panel</button>
        </form>
        
        <div class="credentials-hint">
            <strong>Access Required:</strong>
            Please use your admin credentials provided by the system administrator.
        </div>
    </div>
</body>
</html>
'''

DASHBOARD_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Lanka Ride - Admin Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            color: #333;
        }
        
        .navbar {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .navbar h1 {
            font-size: 24px;
        }
        
        .navbar a {
            color: white;
            text-decoration: none;
            padding: 8px 16px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 5px;
            transition: background 0.3s;
        }
        
        .navbar a:hover {
            background: rgba(255, 255, 255, 0.3);
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 30px 20px;
        }
        
        .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
        }
        
        .card h2 {
            margin-bottom: 20px;
            color: #667eea;
            font-size: 18px;
        }
        
        .slider-group {
            margin-bottom: 25px;
        }
        
        .slider-label {
            display: flex;
            justify-content: space-between;
            margin-bottom: 8px;
            font-weight: 500;
        }
        
        .slider-label span:last-child {
            color: #667eea;
            font-weight: 700;
        }
        
        input[type="range"] {
            width: 100%;
            height: 6px;
            border-radius: 3px;
            background: #ddd;
            outline: none;
            -webkit-appearance: none;
        }
        
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #667eea;
            cursor: pointer;
            box-shadow: 0 2px 6px rgba(102, 126, 234, 0.4);
        }
        
        input[type="range"]::-moz-range-thumb {
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #667eea;
            cursor: pointer;
            border: none;
            box-shadow: 0 2px 6px rgba(102, 126, 234, 0.4);
        }
        
        .button-group {
            display: flex;
            gap: 12px;
            margin-top: 20px;
        }
        
        .btn {
            flex: 1;
            padding: 12px;
            border: none;
            border-radius: 5px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 16px rgba(102, 126, 234, 0.4);
        }
        
        .btn-secondary {
            background: #f0f0f0;
            color: #333;
        }
        
        .btn-secondary:hover {
            background: #e0e0e0;
        }
        
        .logs-container {
            background: #1e1e1e;
            color: #0f0;
            padding: 15px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 400px;
            overflow-y: auto;
            margin-bottom: 15px;
        }
        
        .log-entry {
            margin-bottom: 8px;
            line-height: 1.4;
        }
        
        .status {
            display: inline-block;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 15px;
            text-align: center;
        }
        
        .status.success {
            background: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
        }
        
        .status.error {
            background: #f8d7da;
            border: 1px solid #f5c6cb;
            color: #721c24;
        }
        
        .test-input {
            width: 100%;
            padding: 10px;
            margin-bottom: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        
        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }
            
            .button-group {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
    <div class="navbar">
        <h1>🛡️ Lanka Ride - Admin Panel</h1>
        <a href="/admin/logout">🔓 Logout</a>
    </div>
    
    <div class="container">
        <div class="grid">
            <!-- Parameters Control -->
            <div class="card">
                <h2>⚙️ Test Parameters</h2>
                
                <div class="slider-group">
                    <div class="slider-label">
                        <span>☔ Rain Level (mm)</span>
                        <span id="rainValue">{{ rain_level }}</span>
                    </div>
                    <input type="range" id="rainLevel" min="0" max="10" step="0.1" value="{{ rain_level }}">
                </div>
                
                <div class="slider-group">
                    <div class="slider-label">
                        <span>🚗 Union Density</span>
                        <span id="densityValue">{{ union_density }}</span>
                    </div>
                    <input type="range" id="unionDensity" min="0" max="30" step="0.1" value="{{ union_density }}">
                </div>
                
                <div class="button-group">
                    <button class="btn btn-primary" onclick="updateParameters()">💾 Save Parameters</button>
                </div>
            </div>
            
            <!-- Test Prediction -->
            <div class="card">
                <h2>🧪 Test Prediction</h2>
                
                <input type="text" class="test-input" id="testLat" placeholder="Latitude (default: 6.9271)" value="6.9271">
                <input type="text" class="test-input" id="testLng" placeholder="Longitude (default: 79.8612)" value="79.8612">
                
                <div id="testStatus"></div>
                
                <div class="button-group">
                    <button class="btn btn-primary" onclick="testPredict()">🚀 Send Test Request</button>
                </div>
            </div>
        </div>
        
        <!-- Test Logs -->
        <div class="card">
            <h2>📋 Activity Logs</h2>
            <div class="logs-container">
                {% for log in logs %}
                <div class="log-entry">{{ log }}</div>
                {% endfor %}
            </div>
            <div class="button-group">
                <button class="btn btn-secondary" onclick="clearLogs()">🗑️ Clear Logs</button>
                <button class="btn btn-secondary" onclick="refreshLogs()">🔄 Refresh</button>
            </div>
        </div>
    </div>
    
    <script>
        // Update slider values
        document.getElementById('rainLevel').addEventListener('input', (e) => {
            document.getElementById('rainValue').textContent = e.target.value;
        });
        
        document.getElementById('unionDensity').addEventListener('input', (e) => {
            document.getElementById('densityValue').textContent = e.target.value;
        });
        
        // Update parameters
        async function updateParameters() {
            const rainLevel = parseFloat(document.getElementById('rainLevel').value);
            const unionDensity = parseFloat(document.getElementById('unionDensity').value);
            
            try {
                const response = await fetch('/admin/api/set-parameters', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({rain_level: rainLevel, union_density: unionDensity})
                });
                
                const data = await response.json();
                if (data.status === 'success') {
                    showStatus('✅ Parameters saved successfully!', 'success');
                }
            } catch (error) {
                showStatus('❌ Error saving parameters: ' + error.message, 'error');
            }
        }
        
        // Test prediction
        async function testPredict() {
            const lat = parseFloat(document.getElementById('testLat').value) || 6.9271;
            const lng = parseFloat(document.getElementById('testLng').value) || 79.8612;
            
            showStatus('🔄 Testing...', 'success');
            
            try {
                const response = await fetch('/admin/api/test-predict', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({latitude: lat, longitude: lng})
                });
                
                const data = await response.json();
                
                if (data.zone) {
                    const statusHtml = `
                        <div class="status success">
                            <strong>✅ Prediction Successful</strong><br>
                            Zone: <strong>${data.zone}</strong> | 
                            Risk Score: <strong>${data.risk_score.toFixed(2)}</strong><br>
                            Message: ${data.message}
                        </div>
                    `;
                    document.getElementById('testStatus').innerHTML = statusHtml;
                } else {
                    showStatus('❌ ' + (data.error || 'Prediction failed'), 'error');
                }
            } catch (error) {
                showStatus('❌ Error: ' + error.message, 'error');
            }
        }
        
        // Clear logs
        async function clearLogs() {
            if (confirm('Are you sure you want to clear all logs?')) {
                try {
                    await fetch('/admin/api/clear-logs', {method: 'POST'});
                    refreshLogs();
                } catch (error) {
                    showStatus('❌ Error clearing logs', 'error');
                }
            }
        }
        
        // Refresh logs
        function refreshLogs() {
            location.reload();
        }
        
        // Show status message
        function showStatus(message, type) {
            const statusDiv = document.getElementById('testStatus');
            statusDiv.innerHTML = `<div class="status ${type}">${message}</div>`;
        }
    </script>
</body>
</html>
'''


# ==========================================
# 1. CONFIGURATION
# ==========================================
# Load API key from environment variables
OPENWEATHER_API_KEY = os.getenv('OPENWEATHER_API_KEY')
if not OPENWEATHER_API_KEY:
    raise ValueError('OPENWEATHER_API_KEY must be set in .env.python file')

MODEL_PATH = "/Users/dulaboy/Learn/LankaRide/lanka_ride/traffic_model.json"
DATABASE_FILE = "/Users/dulaboy/Learn/LankaRide/lanka_ride/routes_db.csv"

# ==========================================
# 2. LOAD RESOURCES
# ==========================================

# A. Load XGBoost Model (The Brain)
model = None
try:
    if os.path.exists(MODEL_PATH):
        model = xgb.XGBRegressor()
        model.load_model(MODEL_PATH)
        print("✅ Traffic Model Loaded Successfully!")
    else:
        print("⚠️ Model file not found! Server will rely on logic rules.")
except Exception as e:
    print(f"❌ Model Loading Error: {e}")

# B. Load Route Database (The Map Layer)
route_db = pd.DataFrame()
try:
    if os.path.exists(DATABASE_FILE):
        route_db = pd.read_csv(DATABASE_FILE)
        print(f"✅ Real-Time Database Loaded ({len(route_db)} zones).")
    else:
        print("❌ 'routes_db.csv' not found! Please create the file.")
except Exception as e:
    print(f"❌ Database Error: {e}")

# ==========================================
# 3. REAL-TIME FEATURE ENGINEERING
# ==========================================

def get_real_weather(lat, lon):
    """
    Connects to OpenWeatherMap API to get LIVE rain data.
    """
    try:
        url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={OPENWEATHER_API_KEY}"
        response = requests.get(url, timeout=3)
        if response.status_code == 200:
            data = response.json()
            # 1. Check direct rain volume (mm)
            if 'rain' in data and '1h' in data['rain']:
                return float(data['rain']['1h'])
            
            # 2. Check weather condition codes if volume missing
            # (Codes 200-531 mean Thunderstorm/Drizzle/Rain)
            weather_id = data['weather'][0]['id']
            if 200 <= weather_id <= 531:
                return 5.0 # Assume moderate rain
            
            return 0.0 # Clear sky
    except Exception as e:
        print(f"⚠️ Weather API unavailable: {e}")
        return 0.0 # Default to clear

def perform_geo_lookup(lat, lon):
    """
    Performs a Spatial Search in the CSV Database.
    Finds the zone attributes (Capacity, POI) based on Driver's GPS.
    """
    if route_db.empty:
        return "Unknown Area", 5, 50 # Default values if DB missing
    
    nearest_name = "General Road"
    nearest_cap = 5  # Default low risk
    nearest_poi = 40 # Default low density
    min_dist = float('inf')

    # Iterate through all zones in DB to find the closest one
    for index, row in route_db.iterrows():
        zone_loc = (row['lat'], row['lon'])
        driver_loc = (lat, lon)
        # Calculate real-world distance
        dist = haversine(driver_loc, zone_loc, unit=Unit.METERS)

        if dist < min_dist:
            min_dist = dist
            nearest_name = row['name']
            nearest_cap = row['park_capacity']
            nearest_poi = row['poi_density']

    # If driver is > 400m away from any known Union Stand, it's a "Safe Area"
    if min_dist > 400:
        return f"Near {nearest_name}", 5, 40 # Force low capacity for generic roads
    
    return nearest_name, nearest_cap, nearest_poi

def get_time_features():
    """Extracts Hour, Weekend, Holiday status from System Time"""
    now = datetime.now()
    hour = now.hour
    is_weekend = 1 if now.weekday() >= 5 else 0
    is_holiday = 0 # In a full system, you would call a Calendar API here
    return hour, is_weekend, is_holiday

def decide_zone_color(capacity, rain, poi, predicted_traffic):
    """
    Applies the Thesis Logic (Smart Hustle)
    """
    # 1. UNION RULE (Safety)
    if capacity >= 15:
        # NOVELTY: If Rain is High OR Area is Super Busy -> Union is Overflowed
        if rain > 2.0 or poi > 85:
            return "YELLOW", "High Demand Detected! Safe to operate (Maintain 500m gap)."
        else:
            return "RED", "High Risk Zone! Strong Union Presence."
            
    # 2. TRAFFIC RULE (Efficiency)
    # If traffic for 500m takes more than 5 mins (300s), it's bad.
    if predicted_traffic > 300: 
        return "ORANGE", "Traffic Congestion. Low Profitability."
        
    # 3. GREEN ZONE
    return "GREEN", "Safe Zone. High Opportunity."

# ==========================================
# 4. API ENDPOINT
# ==========================================

@app.route('/predict', methods=['POST'])
def predict():
    try:
        # 1. RECEIVE INPUT (Real GPS)
        data = request.json
        # Accept both Flutter format (latitude/longitude) and internal format (lat/lng)
        lat = data.get('latitude') or data.get('lat')
        lng = data.get('longitude') or data.get('lng')
        rain_level = data.get('rain_level', 0)
        union_density = data.get('union_density', 0)
        use_test_mode = data.get('use_test_mode', False)  # NEW: Test mode flag

        if not lat or not lng:
            return jsonify({"error": "GPS data missing (need latitude and longitude)"}), 400

        print(f"\n📍 Driver at: {lat}, {lng}")
        print(f"☔ Rain: {rain_level}mm | 🚗 Union Density: {union_density} | Test Mode: {use_test_mode}")

        # 2. FETCH DYNAMIC DATA (Live Weather)
        # FIXED: Always fetch real weather, use test values only if test_mode=True
        if use_test_mode and rain_level > 0:
            rain_1h = rain_level  # Use admin test value
            print(f"🧪 TEST MODE: Using admin rain value {rain_level}mm")
        else:
            rain_1h = get_real_weather(lat, lng)  # Always fetch real weather
            print(f"🌐 REAL WEATHER: Fetched {rain_1h}mm from OpenWeatherMap")

        # 3. FETCH STATIC DATA (Database Lookup)
        # This replaces "Hardcoding". We query the DB.
        loc_name, park_capacity, poi_density = perform_geo_lookup(lat, lng)
        if union_density > 0:
            park_capacity = union_density  # Use provided union_density if given

        # 4. FETCH TIME FEATURES
        hour, is_weekend, is_holiday = get_time_features()

        print(f"📊 Analysis: {loc_name} | Union: {park_capacity} | Rain: {rain_1h}mm")

        # 5. MODEL PREDICTION
        predicted_duration = 0
        if model:
            # Construct the exact Feature Vector used in training
            features = pd.DataFrame([[
                park_capacity,
                poi_density,
                rain_1h,
                hour,
                is_weekend,
                500, # We simulate a standardized 500m trip to gauge traffic intensity
                is_holiday
            ]], columns=['nearby_park_capacity', 'poi_density', 'rain_1h', 'hour', 'is_weekend', 'distance_m', 'is_public_holiday'])
            
            # Predict
            predicted_duration = float(model.predict(features)[0])
        else:
            # Fallback Logic (Only if model file is missing/corrupt)
            predicted_duration = (park_capacity * 10) + (rain_1h * 5)

        # 6. DECISION LOGIC
        color, msg = decide_zone_color(park_capacity, rain_1h, poi_density, predicted_duration)

        # Calculate risk score (0-1)
        risk_score = min(1.0, (park_capacity / 30.0) + (rain_1h / 50.0))

        # 7. SEND RESPONSE (Flutter app format)
        return jsonify({
            "zone": color,
            "message": msg,
            "risk_score": risk_score,
            "metadata": {
                "location": loc_name,
                "union_capacity": int(park_capacity),
                "rain_mm": rain_1h,
                "predicted_traffic_time": round(predicted_duration, 1),
                "model_used": model is not None
            }
        })

    except Exception as e:
        print(f"❌ Server Error: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Running on 0.0.0.0 allows the Emulator/Phone to connect
    print("🚀 TukGuard Real-Time Server Running...")
    app.run(host='0.0.0.0', port=5001, debug=True)