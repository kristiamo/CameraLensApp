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
)
