#!/bin/bash
# AMIGO Simulator Walk Test Script
# Simulates a device walking from 100m outside the geofence straight into the target location.

TARGET_LAT=31.475800
TARGET_LNG=74.402700

echo "=========================================================="
echo "🚶 AMIGO GPS Walk Simulation starting..."
echo "Target: ($TARGET_LAT, $TARGET_LNG)"
echo "Make sure AMIGO is running and 'START MONITORING' is tapped!"
echo "=========================================================="

# 1. Start 100m South (Outside 50m fence)
echo "📍 Step 1/6: At 100m South (Outside geofence)..."
xcrun simctl location booted set 31.474902,74.402700
sleep 2

# 2. Walk to 70m South (Still outside)
echo "📍 Step 2/6: Walking to 70m South..."
xcrun simctl location booted set 31.475171,74.402700
sleep 2

# 3. Enter 50m Fence at 45m (Should trigger didEnterRegion & wake!)
echo "📍 Step 3/6: Entering 50m fence at 45m South (WAKE + BURST TRIGGER)..."
xcrun simctl location booted set 31.475396,74.402700
sleep 2

# 4. Approach inside 40m proximity threshold (30m South)
echo "📍 Step 4/6: Inside 40m proximity at 30m South..."
xcrun simctl location booted set 31.475530,74.402700
sleep 1.5

# 5. Continuous approach step (20m South)
echo "📍 Step 5/6: Approaching at 20m South (decreasing distance)..."
xcrun simctl location booted set 31.475620,74.402700
sleep 1.5

# 6. Final approach step (10m South) -> CONFIRM EVENT!
echo "📍 Step 6/6: Approach confirmed at 10m South -> EVENT CONFIRMED & NOTIFICATION!"
xcrun simctl location booted set 31.475710,74.402700
sleep 2

echo "=========================================================="
echo "✅ Walk simulation finished! Check simulator screen/lock screen."
echo "=========================================================="
