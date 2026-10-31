#!/bin/bash
# Kimu Chat - Android call audio fix (update 4):
#  speaker button now really switches between earpiece and loudspeaker,
#  audio calls start on the earpiece (screen turns off at the ear), video calls on the speaker,
#  headsets are used automatically. Run ONCE (bumps versionCode by 1).
set -e
ROOT="${1:-/Users/debbie/Desktop/kimuchat-app}"
A="$ROOT/android"; J="$A/app/src/main/java/app/kimuchat"; M="$A/app/src/main/AndroidManifest.xml"; G="$A/app/build.gradle"
if [ ! -f "$J/KimuNativePlugin.java" ] || [ ! -f "$M" ] || [ ! -f "$G" ]; then
  echo "ERROR: call-screen files not found in $ROOT (run the earlier call-screen updates first)"; exit 1
fi
BK="$ROOT/.backup-callaudio-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp "$J/KimuNativePlugin.java" "$M" "$G" "$BK/"; echo "Backup: $BK"

cat > "$J/KimuNativePlugin.java" <<'KIMU_PLUGIN_EOF'
package app.kimuchat;

import android.app.AppOpsManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.util.Log;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.lang.reflect.Method;
import java.util.List;
import java.util.Locale;

/**
 * window.Capacitor.Plugins.KimuNative
 *  - call setup checks (full-screen calls, battery, autostart, Xiaomi permissions)
 *  - call audio routing: earpiece / loudspeaker / headset (the WebView alone always uses the loudspeaker)
 */
@CapacitorPlugin(name = "KimuNative")
public class KimuNativePlugin extends Plugin {

    private static final String TAG = "KimuAudio";

    private static final String[][] AUTOSTART_SCREENS = {
        { "com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity" },
        { "com.transsion.phonemaster", "com.cyin.himgr.autostart.AutoStartActivity" },
        { "com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity" },
        { "com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity" },
        { "com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity" },
        { "com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity" },
        { "com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity" },
        { "com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity" },
        { "com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity" },
        { "com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity" },
    };

    private static String manufacturer() {
        return Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
    }

    private static boolean isAggressiveOem() {
        String m = manufacturer();
        return m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") || m.contains("tecno")
            || m.contains("infinix") || m.contains("itel") || m.contains("oppo") || m.contains("realme")
            || m.contains("oneplus") || m.contains("vivo") || m.contains("huawei") || m.contains("honor");
    }

    private static boolean isXiaomi() {
        String m = manufacturer();
        return m.contains("xiaomi") || m.contains("redmi") || m.contains("poco");
    }

    // =====================================================================
    // Call setup status + settings screens
    // =====================================================================

    @PluginMethod
    public void getCallSetupStatus(PluginCall call) {
        Context ctx = getContext();
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);

        boolean fullScreen = true;
        if (Build.VERSION.SDK_INT >= 34 && nm != null) {
            fullScreen = nm.canUseFullScreenIntent();
        }

        boolean ignoringBattery = true;
        PowerManager pm = (PowerManager) ctx.getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            ignoringBattery = pm.isIgnoringBatteryOptimizations(ctx.getPackageName());
        }

        boolean callChannelEnabled = true;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
            CallNotifier.ensureChannel(ctx);
            NotificationChannel ch = nm.getNotificationChannel(CallNotifier.CHANNEL_ID);
            callChannelEnabled = ch == null || ch.getImportance() != NotificationManager.IMPORTANCE_NONE;
        }

        JSObject r = new JSObject();
        r.put("canUseFullScreenIntent", fullScreen);
        r.put("ignoringBatteryOptimizations", ignoringBattery);
        r.put("notificationsEnabled", nm == null || nm.areNotificationsEnabled());
        r.put("callChannelEnabled", callChannelEnabled);
        r.put("manufacturer", manufacturer());
        r.put("needsAutostart", isAggressiveOem());
        r.put("isXiaomi", isXiaomi());
        if (isXiaomi()) {
            Boolean lock = miuiOpAllowed(ctx, 10020);  // "Show on lock screen"
            Boolean popup = miuiOpAllowed(ctx, 10021); // "Display pop-up windows while running in background"
            if (lock != null) r.put("xiaomiShowOnLockScreen", lock.booleanValue());
            if (popup != null) r.put("xiaomiBackgroundPopups", popup.booleanValue());
        }
        call.resolve(r);
    }

    private static Boolean miuiOpAllowed(Context ctx, int op) {
        try {
            AppOpsManager ops = (AppOpsManager) ctx.getSystemService(Context.APP_OPS_SERVICE);
            Method m = AppOpsManager.class.getMethod("checkOpNoThrow", int.class, int.class, String.class);
            Object res = m.invoke(ops, op, android.os.Process.myUid(), ctx.getPackageName());
            return (res instanceof Integer) && ((Integer) res) == AppOpsManager.MODE_ALLOWED;
        } catch (Throwable t) {
            return null;
        }
    }

    @PluginMethod
    public void openFullScreenIntentSettings(PluginCall call) {
        String pkg = getContext().getPackageName();
        Intent i;
        if (Build.VERSION.SDK_INT >= 34) {
            i = new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:" + pkg));
        } else {
            i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg);
        }
        open(call, i);
    }

    @PluginMethod
    public void openBatteryOptimizationSettings(PluginCall call) {
        Intent i = isAggressiveOem() ? appDetails() : new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
        open(call, i);
    }

    @PluginMethod
    public void openAutostartSettings(PluginCall call) {
        for (String[] screen : AUTOSTART_SCREENS) {
            Intent i = new Intent().setComponent(new ComponentName(screen[0], screen[1]));
            if (tryStart(i)) {
                JSObject r = new JSObject();
                r.put("opened", true);
                r.put("screen", screen[1]);
                call.resolve(r);
                return;
            }
        }
        open(call, appDetails());
    }

    /** Xiaomi: opens "Other permissions" (Show on lock screen, Pop-up windows in background). */
    @PluginMethod
    public void openXiaomiPermissions(PluginCall call) {
        String pkg = getContext().getPackageName();
        String[] screens = {
            "com.miui.permcenter.permissions.PermissionsEditorActivity",
            "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
        };
        for (String cls : screens) {
            Intent i = new Intent("miui.intent.action.APP_PERM_EDITOR");
            i.setClassName("com.miui.securitycenter", cls);
            i.putExtra("extra_pkgname", pkg);
            if (tryStart(i)) {
                JSObject r = new JSObject();
                r.put("opened", true);
                call.resolve(r);
                return;
            }
        }
        Intent generic = new Intent("miui.intent.action.APP_PERM_EDITOR");
        generic.putExtra("extra_pkgname", pkg);
        if (tryStart(generic)) {
            JSObject r = new JSObject();
            r.put("opened", true);
            call.resolve(r);
            return;
        }
        open(call, appDetails());
    }

    /** Opens the "Eingehende Anrufe" notification channel (sound, lock screen, pop-up/floating). */
    @PluginMethod
    public void openCallNotificationSettings(PluginCall call) {
        String pkg = getContext().getPackageName();
        Intent i;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            CallNotifier.ensureChannel(getContext());
            i = new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                .putExtra(Settings.EXTRA_CHANNEL_ID, CallNotifier.CHANNEL_ID);
        } else {
            i = appDetails();
        }
        open(call, i);
    }

    @PluginMethod
    public void openAppSettings(PluginCall call) {
        open(call, appDetails());
    }

    private Intent appDetails() {
        return new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getContext().getPackageName()));
    }

    private boolean tryStart(Intent i) {
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(i);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private void open(PluginCall call, Intent i) {
        boolean ok = tryStart(i) || tryStart(appDetails());
        JSObject r = new JSObject();
        r.put("opened", ok);
        call.resolve(r);
    }

    // =====================================================================
    // Call audio routing
    //   startCallAudio({ speaker })  – when a call connects
    //   setSpeaker({ on })           – speaker button
    //   stopCallAudio()              – when the call ends
    // Without this, Android's WebView always plays call audio on the loudspeaker.
    // =====================================================================

    private boolean callAudioActive = false;
    private int savedMode = AudioManager.MODE_NORMAL;
    private boolean speakerOn = false;
    private Object focusRequest; // AudioFocusRequest on Android 8+
    private PowerManager.WakeLock proximityLock;

    private AudioManager audio() {
        return (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
    }

    @PluginMethod
    public void startCallAudio(PluginCall call) {
        boolean speaker = Boolean.TRUE.equals(call.getBoolean("speaker", false));
        AudioManager am = audio();
        if (am == null) {
            call.reject("No audio service");
            return;
        }
        if (!callAudioActive) {
            savedMode = am.getMode();
            callAudioActive = true;
            requestFocus(am);
        }
        am.setMode(AudioManager.MODE_IN_COMMUNICATION);
        call.resolve(applyRoute(am, speaker));
    }

    @PluginMethod
    public void setSpeaker(PluginCall call) {
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        AudioManager am = audio();
        if (am == null) {
            call.reject("No audio service");
            return;
        }
        if (am.getMode() != AudioManager.MODE_IN_COMMUNICATION) {
            am.setMode(AudioManager.MODE_IN_COMMUNICATION);
        }
        call.resolve(applyRoute(am, on));
    }

    @PluginMethod
    public void getAudioRoute(PluginCall call) {
        JSObject r = new JSObject();
        r.put("speaker", speakerOn);
        r.put("active", callAudioActive);
        call.resolve(r);
    }

    @PluginMethod
    public void stopCallAudio(PluginCall call) {
        resetAudio();
        call.resolve();
    }

    @Override
    protected void handleOnDestroy() {
        resetAudio();
        super.handleOnDestroy();
    }

    @SuppressWarnings("deprecation")
    private JSObject applyRoute(AudioManager am, boolean speaker) {
        speakerOn = speaker;
        String output = speaker ? "speaker" : "earpiece";
        if (Build.VERSION.SDK_INT >= 31) {
            AudioDeviceInfo target = null;
            List<AudioDeviceInfo> devices = am.getAvailableCommunicationDevices();
            if (speaker) {
                target = find(devices, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER);
            } else {
                // a connected headset wins over the earpiece, like a normal phone call
                target = find(devices,
                    AudioDeviceInfo.TYPE_BLE_HEADSET,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE);
            }
            if (target != null) {
                boolean ok = am.setCommunicationDevice(target);
                output = deviceName(target.getType());
                Log.i(TAG, "Call audio -> " + output + (ok ? "" : " (refused)"));
            } else {
                Log.w(TAG, "No matching audio device for speaker=" + speaker);
            }
        } else {
            am.setSpeakerphoneOn(speaker);
            if (!speaker && (am.isWiredHeadsetOn() || am.isBluetoothScoOn())) output = "headset";
            Log.i(TAG, "Call audio -> " + output);
        }
        updateProximity("earpiece".equals(output));

        JSObject r = new JSObject();
        r.put("speaker", speaker);
        r.put("output", output);
        return r;
    }

    private static AudioDeviceInfo find(List<AudioDeviceInfo> devices, int... typesInOrder) {
        if (devices == null) return null;
        for (int type : typesInOrder) {
            for (AudioDeviceInfo d : devices) {
                if (d.getType() == type) return d;
            }
        }
        return null;
    }

    private static String deviceName(int type) {
        switch (type) {
            case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER: return "speaker";
            case AudioDeviceInfo.TYPE_BUILTIN_EARPIECE: return "earpiece";
            case AudioDeviceInfo.TYPE_BLUETOOTH_SCO:
            case AudioDeviceInfo.TYPE_BLE_HEADSET: return "bluetooth";
            default: return "headset";
        }
    }

    @SuppressWarnings("deprecation")
    private void requestFocus(AudioManager am) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                AudioFocusRequest req = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build())
                    .build();
                am.requestAudioFocus(req);
                focusRequest = req;
            } else {
                am.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
            }
        } catch (Exception e) {
            Log.w(TAG, "Audio focus request failed", e);
        }
    }

    @SuppressWarnings("deprecation")
    private void resetAudio() {
        updateProximity(false);
        if (!callAudioActive) return;
        callAudioActive = false;
        AudioManager am = audio();
        if (am == null) return;
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                am.clearCommunicationDevice();
            } else {
                am.setSpeakerphoneOn(false);
            }
            am.setMode(savedMode == AudioManager.MODE_IN_COMMUNICATION ? AudioManager.MODE_NORMAL : savedMode);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && focusRequest instanceof AudioFocusRequest) {
                am.abandonAudioFocusRequest((AudioFocusRequest) focusRequest);
            } else {
                am.abandonAudioFocus(null);
            }
        } catch (Exception e) {
            Log.w(TAG, "Audio reset failed", e);
        }
        focusRequest = null;
        speakerOn = false;
        Log.i(TAG, "Call audio reset");
    }

    /** Turns the screen off when the phone is held to the ear (earpiece only), like a normal call. */
    private void updateProximity(boolean on) {
        try {
            PowerManager pm = (PowerManager) getContext().getSystemService(Context.POWER_SERVICE);
            if (pm == null) return;
            if (on) {
                if (proximityLock == null && pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                    proximityLock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "kimu:call-proximity");
                }
                if (proximityLock != null && !proximityLock.isHeld()) {
                    proximityLock.acquire(2 * 60 * 60 * 1000L);
                }
            } else if (proximityLock != null && proximityLock.isHeld()) {
                proximityLock.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY);
            }
        } catch (Exception e) {
            Log.w(TAG, "Proximity lock failed", e);
        }
    }
}
KIMU_PLUGIN_EOF
echo "  wrote KimuNativePlugin.java (call audio routing)"

if ! grep -q "android.permission.WAKE_LOCK" "$M"; then
  perl -0pi -e 's|</manifest>|    <uses-permission android:name="android.permission.WAKE_LOCK" />\n</manifest>|' "$M"
  echo "  added WAKE_LOCK permission (screen off at the ear)"
fi

OLD=$(grep -Eo 'versionCode[[:space:]]+[0-9]+' "$G" | head -1 | grep -Eo '[0-9]+')
if [ -n "$OLD" ]; then NEW=$((OLD + 1)); perl -0pi -e "s/versionCode\\s+$OLD/versionCode $NEW/" "$G"; echo "  versionCode $OLD -> $NEW"; fi
echo ""; echo "Done. Next: ./gradlew clean assembleRelease"
