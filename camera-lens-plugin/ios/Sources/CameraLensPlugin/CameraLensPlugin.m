#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Register the plugin class with Capacitor
CAP_PLUGIN(CameraLensPlugin, "CameraLensPlugin",
           CAP_PLUGIN_METHOD(deviceAction, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(configureLens, CAPPluginReturnPromise);
)
