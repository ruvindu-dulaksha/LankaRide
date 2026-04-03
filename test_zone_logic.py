#!/usr/bin/env python3
"""
Test the zone decision logic for each hotspot
Shows which hotspots SHOULD be RED vs GREEN based on current rules
"""

import pandas as pd

# Load the database
route_db = pd.read_csv('routes_db.csv')

print("\n" + "="*80)
print("ZONE DECISION TEST - CHECKING LOGIC")
print("="*80 + "\n")

print("Zone Rule:")
print("  🔴 RED: capacity >= 15 (union stronghold)")
print("  🟢 GREEN: capacity < 15 (safe area)")
print("  🟡 YELLOW: Exceptions (gridlock, demand overflow)")
print("\n" + "-"*80 + "\n")

for _, row in route_db.iterrows():
    name = row['name']
    capacity = row['park_capacity']
    poi = row['poi_density']
    
    # Determine zone based on capacity
    if capacity >= 15:
        zone = "🔴 RED"
        reason = f"High union risk (capacity={capacity})"
    else:
        zone = "🟢 GREEN"
        reason = f"Low union risk (capacity={capacity})"
    
    # Calculate expected profit
    profit_score = (poi / 91) * 100 * (1.5 if poi > 75 else 1.0)  # Estimate
    
    print(f"{zone} {name:30s} | Cap: {capacity:2d} | POI: {poi:2d} | Profit: {profit_score:6.1f}%")
    print(f"       {reason}\n")

print("\n" + "="*80)
print("WHAT THIS MEANS:")
print("="*80)
print("\n🔴 RED hotspots should show RED zone circles (high union, risky)")
print("🟢 GREEN hotspots should show GREEN zone circles (safe, but lower demand)")
print("\n✅ If your app is showing all GREEN, the zone logic might not be triggering correctly.")
print("   Check: Is the backend reading capacity values correctly?")
print("          Is traffic_intensity being calculated correctly?")
