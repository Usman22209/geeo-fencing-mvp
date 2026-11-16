/**
 * AMIGO Feasibility Test — React Native Hybrid
 *
 * Cross-platform UI that bridges into the native Android (and future iOS)
 * geofence → burst → decision engine pipeline.
 *
 * All geofencing, burst location acquisition, sliding-window decision logic,
 * and notification delivery remain fully native.  The JS layer only drives
 * configuration, monitors state, and renders the telemetry log feed.
 */

import React, {useCallback, useEffect, useRef, useState} from 'react';
import {
  Alert,
  FlatList,
  NativeEventEmitter,
  NativeModules,
  PermissionsAndroid,
  Platform,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

// ---------------------------------------------------------------------------
// Native bridge
// ---------------------------------------------------------------------------
const {AmigoProximity} = NativeModules;
const emitter = AmigoProximity
  ? new NativeEventEmitter(AmigoProximity)
  : null;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface Perms {
  fineLocation: boolean;
  backgroundLocation: boolean;
  postNotifications: boolean;
  batteryExempt: boolean;
}

interface LogEntry {
  id: string;
  raw: string;
  ts: number;
}

type MonState = 'IDLE' | 'ARMED' | 'BURST' | 'DECIDED';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const COLORS = {
  bg: '#0d1117',
  card: '#161b22',
  accent: '#58a6ff',
  green: '#3fb950',
  red: '#f85149',
  orange: '#d29922',
  text: '#c9d1d9',
  muted: '#8b949e',
  border: '#30363d',
};

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
export default function App(): React.JSX.Element {
  // State
  const [perms, setPerms] = useState<Perms | null>(null);
  const [state, setState] = useState<MonState>('IDLE');
  const [targetLat, setTargetLat] = useState('31.4758');
  const [targetLng, setTargetLng] = useState('74.4027');
  const [armRadius, setArmRadius] = useState<'ARM_50M' | 'ARM_150M'>('ARM_50M');
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [distance, setDistance] = useState<number | null>(null);
  const logIdRef = useRef(0);
  const flatListRef = useRef<FlatList>(null);

  // ------------------------------------------------------------------
  // Init
  // ------------------------------------------------------------------
  useEffect(() => {
    async function boot() {
      if (!AmigoProximity) {
        console.warn('AmigoProximity native module not available');
        return;
      }
      try {
        const cfg = await AmigoProximity.initConfig();
        setTargetLat(String(cfg.targetLat));
        setTargetLng(String(cfg.targetLng));
        setArmRadius(cfg.activeArm === 'ARM_150M' ? 'ARM_150M' : 'ARM_50M');
        if (cfg.isArmed) {
          setState('ARMED');
        }
      } catch (e) {
        console.error('Config init error', e);
      }
      refreshPerms();
    }
    boot();
  }, []);

  // ------------------------------------------------------------------
  // Event listeners
  // ------------------------------------------------------------------
  useEffect(() => {
    if (!emitter) return;

    const logSub = emitter.addListener('onLogAppended', (evt: {raw: string}) => {
      const id = String(++logIdRef.current);
      setLogs(prev => [...prev.slice(-200), {id, raw: evt.raw, ts: Date.now()}]);

      // Parse distance from log line if present
      try {
        const parsed = JSON.parse(evt.raw);
        if (parsed.distance_m != null) {
          setDistance(parsed.distance_m);
        }
        if (parsed.event === 'burst_fix' || parsed.event === 'decision') {
          setState('BURST');
        }
        if (parsed.event === 'decision' && parsed.verdict) {
          setState('DECIDED');
        }
      } catch {
        // not JSON, that's fine
      }
    });

    const stateSub = emitter.addListener(
      'onStateChanged',
      (evt: {state: string}) => {
        if (evt.state === 'ARMED') setState('ARMED');
        else if (evt.state === 'IDLE') setState('IDLE');
      },
    );

    return () => {
      logSub.remove();
      stateSub.remove();
    };
  }, []);

  // ------------------------------------------------------------------
  // Permissions
  // ------------------------------------------------------------------
  const refreshPerms = useCallback(async () => {
    if (!AmigoProximity) return;
    const p = await AmigoProximity.checkPermissions();
    setPerms(p);
  }, []);

  const requestPerms = useCallback(async () => {
    if (Platform.OS !== 'android') return;
    try {
      await PermissionsAndroid.requestMultiple([
        PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
        PermissionsAndroid.PERMISSIONS.ACCESS_COARSE_LOCATION,
      ]);
      // Background location must be requested separately after fine location
      const bgResult = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION,
      );
      if (Platform.Version >= 33) {
        await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS,
        );
      }
    } catch (e) {
      console.error('Permission request failed', e);
    }
    refreshPerms();
  }, [refreshPerms]);

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------
  const handleSetTarget = useCallback(async () => {
    if (!AmigoProximity) return;
    const lat = parseFloat(targetLat);
    const lng = parseFloat(targetLng);
    if (isNaN(lat) || isNaN(lng)) {
      Alert.alert('Invalid Coordinates', 'Enter valid latitude and longitude.');
      return;
    }
    await AmigoProximity.setTarget(lat, lng);
    addLocalLog(`✅ Target set → (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
  }, [targetLat, targetLng]);

  const handleSetArm = useCallback(
    async (arm: 'ARM_50M' | 'ARM_150M') => {
      if (!AmigoProximity) return;
      setArmRadius(arm);
      const r = await AmigoProximity.setArmRadius(arm);
      addLocalLog(`🎯 Arm radius → ${r}m`);
    },
    [],
  );

  const handleStart = useCallback(async () => {
    if (!AmigoProximity) return;
    try {
      await AmigoProximity.startMonitoring();
      addLocalLog('🟢 Monitoring ARMED — waiting for geofence trigger');
    } catch (e: any) {
      Alert.alert('Start Failed', e.message);
    }
  }, []);

  const handleStop = useCallback(async () => {
    if (!AmigoProximity) return;
    try {
      await AmigoProximity.stopMonitoring();
      addLocalLog('🔴 Monitoring STOPPED');
      setDistance(null);
    } catch (e: any) {
      Alert.alert('Stop Failed', e.message);
    }
  }, []);

  const handleManualBurst = useCallback(async () => {
    if (!AmigoProximity) return;
    try {
      await AmigoProximity.triggerManualBurst();
      addLocalLog('⚡ Manual burst triggered');
    } catch (e: any) {
      Alert.alert('Burst Failed', e.message);
    }
  }, []);

  const handlePreset = useCallback(
    async (label: string, latOffset: number, lngOffset: number) => {
      if (!AmigoProximity) return;
      // Use a rough "here" target — get distance from 0,0 to see if we can do better
      const lat = parseFloat(targetLat) + latOffset;
      const lng = parseFloat(targetLng) + lngOffset;
      setTargetLat(lat.toFixed(6));
      setTargetLng(lng.toFixed(6));
      await AmigoProximity.setTarget(lat, lng);
      addLocalLog(`📍 Preset "${label}" → (${lat.toFixed(6)}, ${lng.toFixed(6)})`);
    },
    [targetLat, targetLng],
  );

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------
  const addLocalLog = useCallback((msg: string) => {
    const id = String(++logIdRef.current);
    setLogs(prev => [
      ...prev.slice(-200),
      {id, raw: msg, ts: Date.now()},
    ]);
  }, []);

  const stateColor =
    state === 'ARMED'
      ? COLORS.green
      : state === 'BURST'
      ? COLORS.orange
      : state === 'DECIDED'
      ? COLORS.accent
      : COLORS.muted;

  // ------------------------------------------------------------------
  // Render
  // ------------------------------------------------------------------
  return (
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={COLORS.bg} />

      {/* ── Header ─────────────────────────────────────── */}
      <View style={styles.header}>
        <Text style={styles.title}>AMIGO</Text>
        <Text style={styles.subtitle}>Feasibility Test · React Native</Text>
        <View style={[styles.stateBadge, {backgroundColor: stateColor}]}>
          <Text style={styles.stateBadgeText}>{state}</Text>
        </View>
      </View>

      {/* ── Permission banner ──────────────────────────── */}
      {perms && (!perms.fineLocation || !perms.backgroundLocation) && (
        <TouchableOpacity style={styles.permBanner} onPress={requestPerms}>
          <Text style={styles.permText}>
            ⚠️ Location permissions required — tap to grant
          </Text>
        </TouchableOpacity>
      )}

      {/* ── Distance display ───────────────────────────── */}
      {distance != null && (
        <View style={styles.distCard}>
          <Text style={styles.distLabel}>Distance to Target</Text>
          <Text style={styles.distValue}>{distance.toFixed(1)} m</Text>
        </View>
      )}

      {/* ── Target inputs ──────────────────────────────── */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Target Location</Text>
        <View style={styles.row}>
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Lat</Text>
            <TextInput
              style={styles.input}
              value={targetLat}
              onChangeText={setTargetLat}
              keyboardType="numeric"
              placeholderTextColor={COLORS.muted}
            />
          </View>
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>Lng</Text>
            <TextInput
              style={styles.input}
              value={targetLng}
              onChangeText={setTargetLng}
              keyboardType="numeric"
              placeholderTextColor={COLORS.muted}
            />
          </View>
          <TouchableOpacity style={styles.btnSmall} onPress={handleSetTarget}>
            <Text style={styles.btnText}>Set</Text>
          </TouchableOpacity>
        </View>

        {/* Presets */}
        <View style={styles.row}>
          <TouchableOpacity
            style={styles.presetBtn}
            onPress={() => handlePreset('📍 Here', 0, 0)}>
            <Text style={styles.presetText}>📍 Here</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.presetBtn}
            onPress={() => handlePreset('🚶 60m', 0.00054, 0)}>
            <Text style={styles.presetText}>🚶 60m</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.presetBtn}
            onPress={() => handlePreset('🚶 100m', 0.0009, 0)}>
            <Text style={styles.presetText}>🚶 100m</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* ── Arm selector ───────────────────────────────── */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Geofence Arm</Text>
        <View style={styles.row}>
          <TouchableOpacity
            style={[
              styles.armBtn,
              armRadius === 'ARM_50M' && styles.armBtnActive,
            ]}
            onPress={() => handleSetArm('ARM_50M')}>
            <Text
              style={[
                styles.armText,
                armRadius === 'ARM_50M' && styles.armTextActive,
              ]}>
              50 m
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[
              styles.armBtn,
              armRadius === 'ARM_150M' && styles.armBtnActive,
            ]}
            onPress={() => handleSetArm('ARM_150M')}>
            <Text
              style={[
                styles.armText,
                armRadius === 'ARM_150M' && styles.armTextActive,
              ]}>
              150 m
            </Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* ── Control buttons ────────────────────────────── */}
      <View style={styles.controlRow}>
        {state === 'IDLE' || state === 'DECIDED' ? (
          <TouchableOpacity
            style={[styles.ctrlBtn, {backgroundColor: COLORS.green}]}
            onPress={handleStart}>
            <Text style={styles.ctrlText}>▶  Start Monitoring</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity
            style={[styles.ctrlBtn, {backgroundColor: COLORS.red}]}
            onPress={handleStop}>
            <Text style={styles.ctrlText}>■  Stop</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity
          style={[styles.ctrlBtn, {backgroundColor: COLORS.orange, flex: 0.5}]}
          onPress={handleManualBurst}>
          <Text style={styles.ctrlText}>⚡ Burst</Text>
        </TouchableOpacity>
      </View>

      {/* ── Telemetry log ──────────────────────────────── */}
      <View style={styles.logContainer}>
        <View style={styles.logHeader}>
          <Text style={styles.cardTitle}>Telemetry Log</Text>
          <TouchableOpacity onPress={() => setLogs([])}>
            <Text style={styles.clearBtn}>Clear</Text>
          </TouchableOpacity>
        </View>
        <FlatList
          ref={flatListRef}
          data={logs}
          keyExtractor={item => item.id}
          renderItem={({item}) => (
            <Text style={styles.logLine} numberOfLines={2}>
              {item.raw}
            </Text>
          )}
          onContentSizeChange={() =>
            flatListRef.current?.scrollToEnd({animated: false})
          }
          style={styles.logList}
          initialNumToRender={30}
          maxToRenderPerBatch={20}
        />
      </View>
    </SafeAreaView>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------
const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: COLORS.bg,
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
  },
  title: {
    color: COLORS.accent,
    fontSize: 22,
    fontWeight: '800',
    letterSpacing: 2,
  },
  subtitle: {
    color: COLORS.muted,
    fontSize: 12,
    marginLeft: 10,
    marginTop: 4,
  },
  stateBadge: {
    marginLeft: 'auto',
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 12,
  },
  stateBadgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  permBanner: {
    backgroundColor: '#3d1d00',
    marginHorizontal: 12,
    borderRadius: 8,
    padding: 10,
    marginBottom: 6,
  },
  permText: {
    color: COLORS.orange,
    fontSize: 13,
    textAlign: 'center',
  },
  distCard: {
    marginHorizontal: 12,
    marginBottom: 6,
    backgroundColor: COLORS.card,
    borderRadius: 10,
    padding: 14,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  distLabel: {
    color: COLORS.muted,
    fontSize: 12,
    marginBottom: 2,
  },
  distValue: {
    color: COLORS.accent,
    fontSize: 32,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  card: {
    marginHorizontal: 12,
    marginBottom: 6,
    backgroundColor: COLORS.card,
    borderRadius: 10,
    padding: 12,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  cardTitle: {
    color: COLORS.text,
    fontSize: 13,
    fontWeight: '700',
    marginBottom: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 6,
  },
  inputGroup: {
    flex: 1,
  },
  inputLabel: {
    color: COLORS.muted,
    fontSize: 11,
    marginBottom: 2,
  },
  input: {
    backgroundColor: COLORS.bg,
    color: COLORS.text,
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 6,
    fontSize: 13,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  btnSmall: {
    backgroundColor: COLORS.accent,
    borderRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 8,
    marginTop: 14,
  },
  btnText: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 13,
  },
  presetBtn: {
    flex: 1,
    backgroundColor: COLORS.bg,
    borderRadius: 6,
    paddingVertical: 7,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  presetText: {
    color: COLORS.text,
    fontSize: 13,
  },
  armBtn: {
    flex: 1,
    backgroundColor: COLORS.bg,
    borderRadius: 8,
    paddingVertical: 10,
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: COLORS.border,
  },
  armBtnActive: {
    borderColor: COLORS.accent,
    backgroundColor: '#0d2137',
  },
  armText: {
    color: COLORS.muted,
    fontSize: 15,
    fontWeight: '700',
  },
  armTextActive: {
    color: COLORS.accent,
  },
  controlRow: {
    flexDirection: 'row',
    marginHorizontal: 12,
    marginBottom: 6,
    gap: 8,
  },
  ctrlBtn: {
    flex: 1,
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: 'center',
  },
  ctrlText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  logContainer: {
    flex: 1,
    marginHorizontal: 12,
    marginBottom: 8,
    backgroundColor: COLORS.card,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: COLORS.border,
    overflow: 'hidden',
  },
  logHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  clearBtn: {
    color: COLORS.red,
    fontSize: 12,
    fontWeight: '600',
  },
  logList: {
    flex: 1,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  logLine: {
    color: COLORS.muted,
    fontSize: 10.5,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    lineHeight: 15,
    paddingVertical: 1,
  },
});
