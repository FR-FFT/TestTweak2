#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h> // For UITouch properties if needed

// Menu Imports
#import "Menu.h"
#import "Page.h"
#import "MenuItem.h"
#import "ToggleItem.h"
#import "PageItem.h"
#import "SliderItem.h"
// #import "TextfieldItem.h" // Not used for coordinates in this example
// #import "InvokeItem.h" // Not used in this example
#import "Utils.h" // For showPopup if needed

// Overlay
#import "ControllerOverlayView.h"

// --- Globals ---
static Menu *controllerMenu;
static GCController *currentGameController = nil;
static UITouch *joystickTouch = nil; // Keep track of the joystick touch

// --- Preference Keys ---
#define PREF_ENABLED @"ControllerTweak_Enabled"

#define PREF_JOYSTICK_ENABLED @"ControllerTweak_Joystick_Enabled"
#define PREF_JOYSTICK_CENTER_X @"ControllerTweak_Joystick_CenterX"
#define PREF_JOYSTICK_CENTER_Y @"ControllerTweak_Joystick_CenterY"
#define PREF_JOYSTICK_RADIUS @"ControllerTweak_Joystick_Radius"

// Button Pref Keys (Example for Button A)
#define PREF_BUTTON_A_ENABLED @"ControllerTweak_ButtonA_Enabled"
#define PREF_BUTTON_A_X @"ControllerTweak_ButtonA_X"
#define PREF_BUTTON_A_Y @"ControllerTweak_ButtonA_Y"

#define PREF_BUTTON_B_ENABLED @"ControllerTweak_ButtonB_Enabled"
#define PREF_BUTTON_B_X @"ControllerTweak_ButtonB_X"
#define PREF_BUTTON_B_Y @"ControllerTweak_ButtonB_Y"

#define PREF_BUTTON_X_ENABLED @"ControllerTweak_ButtonX_Enabled"
#define PREF_BUTTON_X_X @"ControllerTweak_ButtonX_X"
#define PREF_BUTTON_X_Y @"ControllerTweak_ButtonX_Y"

#define PREF_BUTTON_Y_ENABLED @"ControllerTweak_ButtonY_Enabled"
#define PREF_BUTTON_Y_X @"ControllerTweak_ButtonY_X"
#define PREF_BUTTON_Y_Y @"ControllerTweak_ButtonY_Y"

// Add more for DPad, L1, R1, L2, R2, L3, R3 etc. as needed


// --- Forward Declarations ---
static void setupControllerObservation();
static void connectToController(GCController *controller);
static void disconnectController();
static void controllerValueChanged(GCExtendedGamepad *gamepad, GCControllerElement *element);
static void simulateTouchAtPoint(CGPoint point, UITouchPhase phase, UITouch *existingTouch);
static void simulateTapAtConfiguredPoint(NSString *baseKey);
static void updateJoystick(GCPoint2D *stickValue);
static void releaseJoystickTouch();


// --- Touch Simulation Helper ---
// This is a simplified version. Real touch injection can be complex.
// We'll try to use private APIs on UITouch and construct UIEvent manually.
// From: https://github.com/iolate/SimulateTouchID/blob/master/simulatetouch/simulatetouch.m (and other sources)
// And: https://github.com/JMהרצל/AAChipmunk/blob/master/AAChipmunk.m (for event structure)

@interface UIEvent (Private)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
- (void)_setTimestamp:(NSTimeInterval)timestamp;
@end

@interface UITouch (Private)
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)_setIsFirstTouchForView:(BOOL)firstTouch;
@end


static void sendTouchEvent(NSSet<UITouch *> *touches, UITouchPhase phase) {
    if (touches.count == 0) return;

    // Get the private _touchesEvent method
    SEL touchesEventSelector = NSSelectorFromString(@"_touchesEvent");
    if (![[UIApplication sharedApplication] respondsToSelector:touchesEventSelector]) {
        NSLog(@"[ControllerTweak] _touchesEvent not found on UIApplication");
        return;
    }
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    UIEvent *event = [[UIApplication sharedApplication] performSelector:touchesEventSelector];
    #pragma clang diagnostic pop

    if (!event) {
        NSLog(@"[ControllerTweak] Could not get touches event");
        return;
    }

    [event _clearTouches];
    [event _setTimestamp:[[NSDate date] timeIntervalSince1970]];

    for (UITouch *touch in touches) {
        [touch setTimestamp:[[NSDate date] timeIntervalSince1970]];
        [touch setPhase:phase];
        
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        if (!keyWindow) {
             for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
         if (!keyWindow && [[[UIApplication sharedApplication] windows] count] > 0) {
            keyWindow = [[[UIApplication sharedApplication] windows] firstObject];
        }

        if (keyWindow) {
            [touch setWindow:keyWindow];
            // For simplicity, let's assume the touch is on the window itself or a direct subview for now
            // A more robust solution would be to hit-test to find the actual view.
            UIView *targetView = keyWindow; 
            CGPoint locationInView = [targetView convertPoint:touch.locationInWindow fromView:nil];

            [touch setView:targetView];
            [touch _setLocationInWindow:touch.locationInWindow resetPrevious:(phase == UITouchPhaseBegan)];
            
            if (phase == UITouchPhaseBegan) {
                [touch _setIsFirstTouchForView:YES]; // Important for some gesture recognizers
            }
        } else {
            NSLog(@"[ControllerTweak] No key window for touch event");
            return;
        }
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    [[UIApplication sharedApplication] sendEvent:event];
}


static void simulateTapAtScreenPoint(CGPoint point) {
    if (![controllerMenu isItemOn:@"Enable Controller Tweak"]) return;

    [[ControllerOverlayView sharedInstance] flashTapAtPoint:point];

    UITouch *touch = [[UITouch alloc] init];
    [touch setTapCount:1];
    [touch _setLocationInWindow:point resetPrevious:YES];

    sendTouchEvent([NSSet setWithObject:touch], UITouchPhaseBegan);
    
    // Short delay for the "up" event
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Update location for ended phase, though it might not matter much for a tap
        [touch _setLocationInWindow:point resetPrevious:NO];
        sendTouchEvent([NSSet setWithObject:touch], UITouchPhaseEnded);
    });
}

static void updateJoystickTouch(CGPoint stickNormalizedPos) { // stickNormalizedPos: x, y from -1 to 1
    if (![controllerMenu isItemOn:@"Enable Controller Tweak"] || ![controllerMenu isItemOn:@"Enable Joystick"]) {
        if (joystickTouch) {
            releaseJoystickTouch();
        }
        [ControllerOverlayView sharedInstance].virtualJoystickThumbPosition = CGPointZero;
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
        return;
    }

    CGFloat joyCenterX = [controllerMenu getSliderValue:@"Joystick Center X"];
    CGFloat joyCenterY = [controllerMenu getSliderValue:@"Joystick Center Y"];
    CGFloat joyRadius = [controllerMenu getSliderValue:@"Joystick Radius"];

    CGPoint virtualJoystickScreenCenter = CGPointMake(joyCenterX, joyCenterY);
    
    // Calculate touch position based on stick input and virtual joystick params
    CGPoint touchPos = CGPointMake(
        virtualJoystickScreenCenter.x + stickNormalizedPos.x * joyRadius,
        virtualJoystickScreenCenter.y + stickNormalizedPos.y * joyRadius // iOS Y is inverted from typical joystick Y
    );

    // Update visualizer
    [ControllerOverlayView sharedInstance].virtualJoystickThumbPosition = stickNormalizedPos;
    [[ControllerOverlayView sharedInstance] updateJoystickVisuals];

    float deadZone = 0.15f; // Ignore small movements
    BOOL stickIsActive = (fabs(stickNormalizedPos.x) > deadZone || fabs(stickNormalizedPos.y) > deadZone);

    if (stickIsActive) {
        if (!joystickTouch) { // Begin touch
            joystickTouch = [[UITouch alloc] init];
            [joystickTouch setTapCount:0]; // It's not a tap
            
            // Start touch at the center of the virtual joystick for Agar.io style controls
            [joystickTouch _setLocationInWindow:virtualJoystickScreenCenter resetPrevious:YES];
            sendTouchEvent([NSSet setWithObject:joystickTouch], UITouchPhaseBegan);

            // Then immediately move to the stick position
            // Need a very small delay for the game to process Began before Moved
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (joystickTouch) { // Check if it wasn't released in that tiny interval
                     [joystickTouch _setLocationInWindow:touchPos resetPrevious:NO];
                     sendTouchEvent([NSSet setWithObject:joystickTouch], UITouchPhaseMoved);
                }
            });

        } else { // Move existing touch
            [joystickTouch _setLocationInWindow:touchPos resetPrevious:NO];
            sendTouchEvent([NSSet setWithObject:joystickTouch], UITouchPhaseMoved);
        }
    } else { // Stick is in deadzone (released)
        if (joystickTouch) {
            releaseJoystickTouch();
        }
    }
}

static void releaseJoystickTouch() {
    if (joystickTouch) {
        // End touch at its last known position or center
        CGPoint lastPos = joystickTouch.locationInWindow; // Use the actual last location
        [joystickTouch _setLocationInWindow:lastPos resetPrevious:NO];
        sendTouchEvent([NSSet setWithObject:joystickTouch], UITouchPhaseEnded);
        joystickTouch = nil;

        [ControllerOverlayView sharedInstance].virtualJoystickThumbPosition = CGPointZero;
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
    }
}

// --- Controller Logic ---
static void setupControllerObservation() {
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil]; // Necessary for some controllers

    [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        GCController *controller = note.object;
        NSLog(@"[ControllerTweak] Controller connected: %@", controller.vendorName);
        if (!currentGameController) { // Connect if we don't have one
            connectToController(controller);
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        GCController *controller = note.object;
        NSLog(@"[ControllerTweak] Controller disconnected: %@", controller.vendorName);
        if (currentGameController == controller) {
            disconnectController();
        }
    }];

    // Check for already connected controllers
    if ([GCController.controllers count] > 0) {
        connectToController(GCController.controllers.firstObject);
    }
}

static void connectToController(GCController *controller) {
    if (currentGameController) return; // Already connected to one

    currentGameController = controller;
    if (currentGameController.extendedGamepad) {
        currentGameController.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
            controllerValueChanged(gamepad, element);
        };
        showPopup(@"Controller Connected", currentGameController.vendorName ?: @"Unknown Controller");
    } else if (currentGameController.microGamepad) { // For basic remotes etc.
        // Handle microGamepad if needed, less common for gaming
        showPopup(@"Micro Controller Connected", currentGameController.vendorName ?: @"Unknown Controller");
    } else {
         showPopup(@"Gamepad Profile Not Recognized", currentGameController.vendorName ?: @"Unknown Controller");
    }
}

static void disconnectController() {
    if (currentGameController) {
        showPopup(@"Controller Disconnected", currentGameController.vendorName ?: @"Unknown Controller");
        if (currentGameController.extendedGamepad) {
            currentGameController.extendedGamepad.valueChangedHandler = nil;
        }
        currentGameController = nil;
        releaseJoystickTouch(); // Ensure joystick touch is released
    }
}

static void controllerValueChanged(GCExtendedGamepad *gamepad, GCControllerElement *element) {
    if (![controllerMenu isItemOn:@"Enable Controller Tweak"]) {
        // If joystick was active and tweak is disabled, release it
        if (joystickTouch) releaseJoystickTouch();
        return;
    }

    // Joystick (Left Thumbstick)
    if (element == gamepad.leftThumbstick) {
        CGPoint stickVal = CGPointMake(gamepad.leftThumbstick.xAxis.value, -gamepad.leftThumbstick.yAxis.value); // Invert Y
        updateJoystick(stickVal); // Pass normalized values
        return; // Important: return after handling an element if it's exclusive (like a joystick update)
    }
    
    // If stick is not active and was previously, release touch
    // This handles case where joystick goes to zero but no explicit "joystick element" event comes right after.
    // Check if the element is NOT the joystick and the joystick IS in deadzone
    BOOL stickInDeadzone = (fabs(gamepad.leftThumbstick.xAxis.value) < 0.15f && fabs(gamepad.leftThumbstick.yAxis.value) < 0.15f);
    if (element != gamepad.leftThumbstick && joystickTouch && stickInDeadzone) {
        releaseJoystickTouch();
    }


    // Button Taps (only on press)
    // Important: Check `isPressed` for buttons to avoid double actions on press & release for valueChangedHandler
    if (element == gamepad.buttonA && gamepad.buttonA.isPressed) {
        if ([controllerMenu isItemOn:@"Map Button A"]) {
            CGFloat x = [controllerMenu getSliderValue:@"Button A X"];
            CGFloat y = [controllerMenu getSliderValue:@"Button A Y"];
            simulateTapAtScreenPoint(CGPointMake(x, y));
        }
    } else if (element == gamepad.buttonB && gamepad.buttonB.isPressed) {
        if ([controllerMenu isItemOn:@"Map Button B"]) {
            CGFloat x = [controllerMenu getSliderValue:@"Button B X"];
            CGFloat y = [controllerMenu getSliderValue:@"Button B Y"];
            simulateTapAtScreenPoint(CGPointMake(x, y));
        }
    } else if (element == gamepad.buttonX && gamepad.buttonX.isPressed) {
        if ([controllerMenu isItemOn:@"Map Button X"]) {
            CGFloat x = [controllerMenu getSliderValue:@"Button X X"];
            CGFloat y = [controllerMenu getSliderValue:@"Button X Y"];
            simulateTapAtScreenPoint(CGPointMake(x, y));
        }
    } else if (element == gamepad.buttonY && gamepad.buttonY.isPressed) {
        if ([controllerMenu isItemOn:@"Map Button Y"]) {
            CGFloat x = [controllerMenu getSliderValue:@"Button Y X"];
            CGFloat y = [controllerMenu getSliderValue:@"Button Y Y"];
            simulateTapAtScreenPoint(CGPointMake(x, y));
        }
    }
    // Add more buttons: L1, R1, L2, R2, DPad up/down/left/right, etc.
    // Example for L1 (Left Shoulder)
    /*
    else if (element == gamepad.leftShoulder && gamepad.leftShoulder.isPressed) {
        if ([controllerMenu isItemOn:@"Map L1"]) { // Assuming you add "Map L1" toggle
            CGFloat x = [controllerMenu getSliderValue:@"L1 X"]; // And "L1 X", "L1 Y" sliders
            CGFloat y = [controllerMenu getSliderValue:@"L1 Y"];
            simulateTapAtScreenPoint(CGPointMake(x, y));
        }
    }
    */
}


// --- Menu Setup ---
static void initControllerMenu() {
    controllerMenu = [[Menu alloc] initMenu];

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    // --- Page 1: Main Settings ---
    Page *mainPage = [[Page alloc] initWithPageNumber:1 parentPage:1]; // Main page
    [controllerMenu addPage:mainPage];

    ToggleItem *enableTweak = [[ToggleItem alloc] initWithTitle:@"Enable Controller Tweak"
                                                   description:@"Master switch for all controller mappings."
                                                         prefsKey:PREF_ENABLED
                                                         defaultValue:NO];
    [enableTweak setCallback:^(BOOL isOn) {
        [ControllerOverlayView sharedInstance].hidden = !isOn;
        if (!isOn && joystickTouch) { // If disabling tweak, release joystick
            releaseJoystickTouch();
        }
        if (isOn) { // Re-check controller connection if enabling
            if (!currentGameController && [GCController.controllers count] > 0) {
                connectToController(GCController.controllers.firstObject);
            }
            [[ControllerOverlayView sharedInstance] updateJoystickVisuals]; // Show/hide joystick
        }
    }];
    [mainPage addItem:enableTweak];


    PageItem *buttonMappingPageLink = [[PageItem alloc] initWithTitle:@"Button Mapping" targetPage:2];
    [mainPage addItem:buttonMappingPageLink];

    PageItem *joystickMappingPageLink = [[PageItem alloc] initWithTitle:@"Joystick Mapping" targetPage:3];
    [mainPage addItem:joystickMappingPageLink];

    // --- Page 2: Button Mapping ---
    Page *buttonPage = [[Page alloc] initWithPageNumber:2 parentPage:1];
    [controllerMenu addPage:buttonPage];

    // Button A
    ToggleItem *mapA = [[ToggleItem alloc] initWithTitle:@"Map Button A" description:@"Enable mapping for Button A (Cross/X on PS)." prefsKey:PREF_BUTTON_A_ENABLED defaultValue:NO];
    SliderItem *sliderAX = [[SliderItem alloc] initWithTitle:@"Button A X" description:@"X coordinate for Button A tap." prefsKey:PREF_BUTTON_A_X defaultValue:screenWidth * 0.8f min:0 max:screenWidth floating:NO];
    SliderItem *sliderAY = [[SliderItem alloc] initWithTitle:@"Button A Y" description:@"Y coordinate for Button A tap." prefsKey:PREF_BUTTON_A_Y defaultValue:screenHeight * 0.8f min:0 max:screenHeight floating:NO];
    [buttonPage addItem:mapA];
    [buttonPage addItem:sliderAX];
    [buttonPage addItem:sliderAY];

    // Button B
    ToggleItem *mapB = [[ToggleItem alloc] initWithTitle:@"Map Button B" description:@"Enable mapping for Button B (Circle on PS)." prefsKey:PREF_BUTTON_B_ENABLED defaultValue:NO];
    SliderItem *sliderBX = [[SliderItem alloc] initWithTitle:@"Button B X" description:@"X coordinate for Button B tap." prefsKey:PREF_BUTTON_B_X defaultValue:screenWidth * 0.9f min:0 max:screenWidth floating:NO];
    SliderItem *sliderBY = [[SliderItem alloc] initWithTitle:@"Button B Y" description:@"Y coordinate for Button B tap." prefsKey:PREF_BUTTON_B_Y defaultValue:screenHeight * 0.7f min:0 max:screenHeight floating:NO];
    [buttonPage addItem:mapB];
    [buttonPage addItem:sliderBX];
    [buttonPage addItem:sliderBY];

    // Button X
    ToggleItem *mapX = [[ToggleItem alloc] initWithTitle:@"Map Button X" description:@"Enable mapping for Button X (Square on PS)." prefsKey:PREF_BUTTON_X_ENABLED defaultValue:NO];
    SliderItem *sliderXX = [[SliderItem alloc] initWithTitle:@"Button X X" description:@"X coordinate for Button X tap." prefsKey:PREF_BUTTON_X_X defaultValue:screenWidth * 0.8f min:0 max:screenWidth floating:NO];
    SliderItem *sliderXY = [[SliderItem alloc] initWithTitle:@"Button X Y" description:@"Y coordinate for Button X tap." prefsKey:PREF_BUTTON_X_Y defaultValue:screenHeight * 0.6f min:0 max:screenHeight floating:NO];
    [buttonPage addItem:mapX];
    [buttonPage addItem:sliderXX];
    [buttonPage addItem:sliderXY];

    // Button Y
    ToggleItem *mapY = [[ToggleItem alloc] initWithTitle:@"Map Button Y" description:@"Enable mapping for Button Y (Triangle on PS)." prefsKey:PREF_BUTTON_Y_ENABLED defaultValue:NO];
    SliderItem *sliderYX = [[SliderItem alloc] initWithTitle:@"Button Y X" description:@"X coordinate for Button Y tap." prefsKey:PREF_BUTTON_Y_X defaultValue:screenWidth * 0.7f min:0 max:screenWidth floating:NO];
    SliderItem *sliderYY = [[SliderItem alloc] initWithTitle:@"Button Y Y" description:@"Y coordinate for Button Y tap." prefsKey:PREF_BUTTON_Y_Y defaultValue:screenHeight * 0.7f min:0 max:screenHeight floating:NO];
    [buttonPage addItem:mapY];
    [buttonPage addItem:sliderYX];
    [buttonPage addItem:sliderYY];


    // --- Page 3: Joystick Mapping ---
    Page *joystickPage = [[Page alloc] initWithPageNumber:3 parentPage:1];
    [controllerMenu addPage:joystickPage];

    ToggleItem *enableJoystick = [[ToggleItem alloc] initWithTitle:@"Enable Joystick" description:@"Map left thumbstick to virtual on-screen joystick." prefsKey:PREF_JOYSTICK_ENABLED defaultValue:YES];
    [enableJoystick setCallback:^(BOOL isOn){
        [ControllerOverlayView sharedInstance].showVirtualJoystick = isOn;
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
        if (!isOn && joystickTouch) {
            releaseJoystickTouch();
        }
    }];
    [joystickPage addItem:enableJoystick];

    SliderItem *joyCenterX = [[SliderItem alloc] initWithTitle:@"Joystick Center X" description:@"X pos of virtual joystick." prefsKey:PREF_JOYSTICK_CENTER_X defaultValue:screenWidth / 4 min:0 max:screenWidth floating:NO];
    [joyCenterX setCallback:^(float val){ 
        [ControllerOverlayView sharedInstance].virtualJoystickCenter = CGPointMake(val, [ControllerOverlayView sharedInstance].virtualJoystickCenter.y);
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
    }];
    [joystickPage addItem:joyCenterX];
    
    SliderItem *joyCenterY = [[SliderItem alloc] initWithTitle:@"Joystick Center Y" description:@"Y pos of virtual joystick." prefsKey:PREF_JOYSTICK_CENTER_Y defaultValue:screenHeight * 3 / 4 min:0 max:screenHeight floating:NO];
    [joyCenterY setCallback:^(float val){
        [ControllerOverlayView sharedInstance].virtualJoystickCenter = CGPointMake([ControllerOverlayView sharedInstance].virtualJoystickCenter.x, val);
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
    }];
    [joystickPage addItem:joyCenterY];

    SliderItem *joyRadius = [[SliderItem alloc] initWithTitle:@"Joystick Radius" description:@"Size of virtual joystick." prefsKey:PREF_JOYSTICK_RADIUS defaultValue:60.0f min:20 max:200 floating:NO];
    [joyRadius setCallback:^(float val){
        [ControllerOverlayView sharedInstance].virtualJoystickRadius = val;
        [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
    }];
    [joystickPage addItem:joyRadius];


    // Load preferences and display
    [controllerMenu setUserDefaultsAndDict]; // Reads saved values
    
    // Initial setup for overlay based on loaded prefs
    BOOL tweakEnabled = [controllerMenu isItemOn:@"Enable Controller Tweak"];
    [ControllerOverlayView sharedInstance].hidden = !tweakEnabled;
    BOOL joyEnabled = [controllerMenu isItemOn:@"Enable Joystick"];
    [ControllerOverlayView sharedInstance].showVirtualJoystick = joyEnabled;
    [ControllerOverlayView sharedInstance].virtualJoystickCenter = CGPointMake([controllerMenu getSliderValue:@"Joystick Center X"], [controllerMenu getSliderValue:@"Joystick Center Y"]);
    [ControllerOverlayView sharedInstance].virtualJoystickRadius = [controllerMenu getSliderValue:@"Joystick Radius"];
    [[ControllerOverlayView sharedInstance] updateJoystickVisuals];
    
    [controllerMenu loadPage:1];
}

// --- Tweak Initialization ---
static void didFinishLaunching(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    // Wait a bit for the app to be fully ready, especially UIWindow
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Initialize overlay first so menu can use it if needed for default states
        [ControllerOverlayView sharedInstance]; 
        initControllerMenu();
        setupControllerObservation();
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
                                    NULL,
                                    &didFinishLaunching,
                                    (CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
