@import IOKit;
#import "AppDelegate.h"
#import "FingerStatusManager.h"
#import "KarabinerKit/KarabinerKit.h"
#import "MultitouchDeviceManager.h"
#import "MultitouchPrivate.h"
#import "NotificationKeys.h"
#import "PreferencesController.h"
#import "PreferencesKeys.h"
#import <pqrs/weakify.h>

static AppDelegate* global_self_ = nil;

@interface AppDelegate ()

@property(weak) IBOutlet PreferencesController* preferences;

@end

@implementation AppDelegate

// ------------------------------------------------------------
- (void)observer_NSWorkspaceDidWakeNotification:(NSNotification*)notification {
  @weakify(self);

  dispatch_async(dispatch_get_main_queue(), ^{
    @strongify(self);
    if (!self) {
      return;
    }

    NSLog(@"observer_NSWorkspaceDidWakeNotification");

    // sleep until devices are settled.
    [NSThread sleepForTimeInterval:1.0];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"relaunchAfterWakeUpFromSleep"]) {
      double wait = [[[NSUserDefaults standardUserDefaults] stringForKey:@"relaunchWait"] doubleValue];
      if (wait > 0) {
        [NSThread sleepForTimeInterval:wait];
      }

      [KarabinerKit relaunch];
    }

    [[MultitouchDeviceManager sharedMultitouchDeviceManager] setCallback:YES];
  });
}

- (void)registerWakeNotification {
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceDidWakeNotification:)
                                                             name:NSWorkspaceDidWakeNotification
                                                           object:nil];
}

- (void)unregisterWakeNotification {
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self
                                                                name:NSWorkspaceDidWakeNotification
                                                              object:nil];
}

void enable(void) {
  [[MultitouchDeviceManager sharedMultitouchDeviceManager] registerIONotification];
  [global_self_ registerWakeNotification];

  // sleep until devices are settled.
  [NSThread sleepForTimeInterval:1.0];

  [[MultitouchDeviceManager sharedMultitouchDeviceManager] setCallback:YES];
}

void disable(void) {
  [[MultitouchDeviceManager sharedMultitouchDeviceManager] unregisterIONotification];
  [global_self_ unregisterWakeNotification];

  [[MultitouchDeviceManager sharedMultitouchDeviceManager] setCallback:NO];
}

- (void)setVariables {
  //
  // Prepare variable names
  //

  NSMutableSet<NSString*>* enableVariableNames = [NSMutableSet new];
  NSMutableSet<NSString*>* discardVariableNames = [NSMutableSet new];

  FingerStatusManager* manager = [FingerStatusManager sharedFingerStatusManager];
  NSUInteger fingerCount = [manager getTouchedFixedFingerCount];

  for (NSUInteger i = 1; i <= MAX_FINGER_COUNT; ++i) {
    if (![PreferencesController isSettingEnabled:i]) {
      continue;
    }

    NSString* name = [PreferencesController getSettingIdentifier:i];
    if (!name) {
      continue;
    }

    if (i == fingerCount) {
      [enableVariableNames addObject:name];
    } else {
      [discardVariableNames addObject:name];
    }
  }

  //
  // Unset variables
  //

  for (NSString* name in discardVariableNames) {
    if ([enableVariableNames containsObject:name]) {
      continue;
    }

    libkrbn_grabber_client_async_set_variable([name UTF8String], 0);
  }

  //
  // Set variables
  //

  for (NSString* name in enableVariableNames) {
    libkrbn_grabber_client_async_set_variable([name UTF8String], 1);
  }
}

// ------------------------------------------------------------
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
  [KarabinerKit setup];
  [KarabinerKit exitIfAnotherProcessIsRunning:"multitouch_extension.pid"];
  [KarabinerKit observeConsoleUserServerIsDisabledNotification];

  [[NSApplication sharedApplication] disableRelaunchOnLogin];

  // ----------------------------------------
  if (![[NSUserDefaults standardUserDefaults] boolForKey:@"hideIconInDock"]) {
    ProcessSerialNumber psn = {0, kCurrentProcess};
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
  }

  @weakify(self);
  [[NSNotificationCenter defaultCenter] addObserverForName:kFixedFingerStateChanged
                                                    object:nil
                                                     queue:[NSOperationQueue mainQueue]
                                                usingBlock:^(NSNotification* note) {
                                                  @strongify(self);
                                                  if (!self) {
                                                    return;
                                                  }

                                                  [self setVariables];
                                                }];

  global_self_ = self;

  libkrbn_enable_grabber_client(enable,
                                disable,
                                disable);
}

- (void)dealloc {
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

// Note:
// We have to set NSSupportsSuddenTermination `NO` to use `applicationWillTerminate`.
- (void)applicationWillTerminate:(NSNotification*)aNotification {
  [[MultitouchDeviceManager sharedMultitouchDeviceManager] setCallback:NO];

  libkrbn_terminate();
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)flag {
  [self.preferences show];
  return YES;
}

@end
