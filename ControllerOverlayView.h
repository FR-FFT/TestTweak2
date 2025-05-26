#import <UIKit/UIKit.h>

@interface ControllerOverlayView : UIView

@property (nonatomic, assign) BOOL showVirtualJoystick;
@property (nonatomic, assign) CGPoint virtualJoystickCenter;
@property (nonatomic, assign) CGFloat virtualJoystickRadius;
@property (nonatomic, assign) CGPoint virtualJoystickThumbPosition; // Relative to center, normalized -1 to 1

+ (instancetype)sharedInstance;
- (void)flashTapAtPoint:(CGPoint)point;
- (void)updateJoystickVisuals;

@end
