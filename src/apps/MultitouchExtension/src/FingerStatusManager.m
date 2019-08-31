#import "FingerStatusManager.h"
#import "NotificationKeys.h"
#import "PreferencesKeys.h"
#import <pqrs/weakify.h>

@interface FingerStatusEntry : NSObject

//
// unique keys
//

@property MTDeviceRef device;
@property int identifier;

//
// variables
//

@property int frame;
@property NSPoint point;
@property BOOL touchedPhysically;
@property BOOL touchedFixed;
@property NSTimer* delayTimer;

@end

@implementation FingerStatusEntry

- (instancetype)init:(MTDeviceRef)device
          identifier:(int)identifier {
  self = [super init];

  if (self) {
    _device = device;
    _identifier = identifier;
    _frame = 0;
    _point = NSMakePoint(0, 0);
    _touchedPhysically = NO;
    _touchedFixed = NO;
    _delayTimer = nil;
  }

  return self;
}

@end

@interface FingerStatusManager ()

@property NSMutableArray<FingerStatusEntry*>* entries;
@end

@implementation FingerStatusManager

- (instancetype)init {
  self = [super init];

  if (self) {
    _entries = [NSMutableArray new];
  }

  return self;
}

- (FingerStatusEntry*)findEntry:(MTDeviceRef)device
                     identifier:(int)identifier {
  for (FingerStatusEntry* e in self.entries) {
    if (e.device == device &&
        e.identifier == identifier) {
      return e;
    }
  }

  return nil;
}

- (void)update:(MTDeviceRef)device
          data:(Finger*)data
       fingers:(int)fingers
     timestamp:(double)timestamp
         frame:(int)frame {
  BOOL physicalFingerStateChanged = NO;

  @synchronized(self) {
    for (int i = 0; i < fingers; ++i) {
      int identifier = data[i].identifier;

      FingerStatusEntry* e = [self findEntry:device identifier:identifier];
      if (!e) {
        e = [[FingerStatusEntry alloc] init:device identifier:identifier];
        [self.entries addObject:e];
      }

      e.frame = frame;
      e.point = NSMakePoint(data[i].normalized.position.x, data[i].normalized.position.y);

      // state values:
      //   4: touched
      //   1-3,5-7: near
      BOOL touched = NO;
      if (data[i].state == 4) {
        touched = YES;
      } else {
        touched = NO;
      }

      if (e.touchedPhysically != touched) {
        e.touchedPhysically = touched;
        physicalFingerStateChanged = YES;

        if (e.touchedFixed == touched) {
          [e.delayTimer invalidate];
        } else {
          NSInteger delay = 0;
          if (e.touchedPhysically) {
            delay = [[NSUserDefaults standardUserDefaults] integerForKey:kDelayBeforeTurnOn];
          } else {
            delay = [[NSUserDefaults standardUserDefaults] integerForKey:kDelayBeforeTurnOff];
          }

          @weakify(self);
          e.delayTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 * delay / 1000.0)
                                                         repeats:NO
                                                           block:^(NSTimer* timer) {
                                                             @strongify(self);
                                                             if (!self) {
                                                               return;
                                                             }

                                                             @synchronized(self) {
                                                               e.touchedFixed = touched;
                                                             }

                                                             [[NSNotificationCenter defaultCenter] postNotificationName:kFixedFingerStateChanged
                                                                                                                 object:self];
                                                           }];
        }
      }
    }

    [self.entries filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary* bindings) {
                    FingerStatusEntry* e = (FingerStatusEntry*)(evaluatedObject);

                    // Keep other devices entries
                    if (e.device != device) {
                      return YES;
                    }

                    // Discard old entries
                    if (e.frame != frame &&
                        !e.touchedFixed) {
                      return NO;
                    }

                    // Discard untouched entries
                    if (!e.touchedPhysically &&
                        !e.touchedFixed) {
                      return NO;
                    }

                    // Keep entries
                    return YES;
                  }]];

    printf("update %d\n", (int)(self.entries.count));
  }

  if (physicalFingerStateChanged) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPhysicalFingerStateChanged
                                                        object:self];
  }
}

- (void)debugDump {
  @synchronized(self) {
    for (FingerStatusEntry* e in self.entries) {
      printf("%d %d %d %dx%d\n",
             e.identifier,
             e.touchedPhysically,
             e.touchedFixed,
             (int)(e.point.x),
             (int)(e.point.y));
    }
  }
}

@end
