#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Register the plugin class with Capacitor
CAP_PLUGIN(CameraLensPlugin, "CameraLensPlugin",
           CAP_PLUGIN_METHOD(deviceAction, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(configureLens, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(startSession, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(stopSession, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setEncoderSettings, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getEncoderStats, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(connectWebSocket, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(disconnectWebSocket, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getWebSocketStatus, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getDeviceCapabilities, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setISO, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setShutterSpeed, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setFocusDistance, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setZoomFactor, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setLensType, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setWhiteBalance, CAPPluginReturnPromise);
)
