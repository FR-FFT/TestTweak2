#import "ControllerOverlayView.h"

@implementation ControllerOverlayView {
    CAShapeLayer *_joystickBaseLayer;
    CAShapeLayer *_joystickThumbLayer;
}

static ControllerOverlayView *_sharedInstance = nil;

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Ensure it's full screen and on top
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        if (!keyWindow) { // Fallback for early calls
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
            _sharedInstance = [[self alloc] initWithFrame:keyWindow.bounds];
            _sharedInstance.userInteractionEnabled = NO;
            _sharedInstance.backgroundColor = [UIColor clearColor];
            _sharedInstance.hidden = YES; // Initially hidden
            [keyWindow addSubview:_sharedInstance];
            [keyWindow bringSubviewToFront:_sharedInstance];
        } else {
            NSLog(@"[ControllerTweak] Could not get keyWindow to add overlay!");
        }
    });
    return _sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _showVirtualJoystick = NO;
        _virtualJoystickCenter = CGPointMake(frame.size.width / 4, frame.size.height * 3 / 4);
        _virtualJoystickRadius = 50.0;
        _virtualJoystickThumbPosition = CGPointZero;

        _joystickBaseLayer = [CAShapeLayer layer];
        _joystickBaseLayer.fillColor = [UIColor colorWithWhite:0.5 alpha:0.3].CGColor;
        _joystickBaseLayer.strokeColor = [UIColor colorWithWhite:0.8 alpha:0.5].CGColor;
        _joystickBaseLayer.lineWidth = 2.0;
        [self.layer addSublayer:_joystickBaseLayer];

        _joystickThumbLayer = [CAShapeLayer layer];
        _joystickThumbLayer.fillColor = [UIColor colorWithWhite:0.8 alpha:0.7].CGColor;
        _joystickThumbLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
        _joystickThumbLayer.lineWidth = 1.0;
        [self.layer addSublayer:_joystickThumbLayer];
        
        [self updateJoystickVisuals]; // Initial draw
    }
    return self;
}

- (void)flashTapAtPoint:(CGPoint)point {
    if (self.hidden) return;
    CAShapeLayer *tapCircle = [CAShapeLayer layer];
    tapCircle.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - 15, point.y - 15, 30, 30)].CGPath;
    tapCircle.fillColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.7].CGColor;
    [self.layer addSublayer:tapCircle];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.3];
        tapCircle.opacity = 0.0;
        [CATransaction setCompletionBlock:^{
            [tapCircle removeFromSuperlayer];
        }];
        [CATransaction commit];
    });
}

- (void)updateJoystickVisuals {
    if (self.hidden || !_showVirtualJoystick) {
        _joystickBaseLayer.hidden = YES;
        _joystickThumbLayer.hidden = YES;
        return;
    }
    _joystickBaseLayer.hidden = NO;
    _joystickThumbLayer.hidden = NO;

    _joystickBaseLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(
        self.virtualJoystickCenter.x - self.virtualJoystickRadius,
        self.virtualJoystickCenter.y - self.virtualJoystickRadius,
        self.virtualJoystickRadius * 2,
        self.virtualJoystickRadius * 2
    )].CGPath;

    CGFloat thumbRadius = self.virtualJoystickRadius * 0.4;
    CGPoint thumbActualPos = CGPointMake(
        self.virtualJoystickCenter.x + self.virtualJoystickThumbPosition.x * self.virtualJoystickRadius,
        self.virtualJoystickCenter.y + self.virtualJoystickThumbPosition.y * self.virtualJoystickRadius
    );

    _joystickThumbLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(
        thumbActualPos.x - thumbRadius,
        thumbActualPos.y - thumbRadius,
        thumbRadius * 2,
        thumbRadius * 2
    )].CGPath;
    
    [self setNeedsDisplay]; // May not be needed with CAShapeLayers but good practice
}

// Ensure overlay stays on top if view hierarchy changes
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self.window bringSubviewToFront:self];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // If screen rotates or bounds change, ensure it's still full screen.
    // This is important if the keyWindow reference becomes stale or changes.
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
     if (!keyWindow) { // Fallback for early calls
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

    if (keyWindow && !CGRectEqualToRect(self.frame, keyWindow.bounds)) {
        self.frame = keyWindow.bounds;
    }
    [self updateJoystickVisuals];
}


@end
