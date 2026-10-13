#import "StyxConfig.h"

// Single definition shared across all translation units.
StyxConfig_t StyxCfg = {
    .espOn        = NO,
    .espBox       = YES,
    .espDistance  = YES,
    .espHealth    = YES,
    .aimOn        = NO,
    .aimStrength  = 6.0f,

    .anogsBypassOn = YES,
};

// ---------------------------------------------------------------------------
// StyxRootViewController
//
// Declares the same interface orientations codm's Info.plist does. Without
// this, our windows tell the scene they support any orientation and the game
// boots rotated the wrong way (portrait device + landscape game).
// ---------------------------------------------------------------------------
@implementation StyxRootViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

// ---------------------------------------------------------------------------
// StyxPassthroughWindow
//
// Returning nil when the hit lands on the window itself (or on the disabled
// root view) lets UIKit fall through to the game's window underneath, while
// taps that genuinely land on the FAB or panel are still handled here.
// ---------------------------------------------------------------------------
@implementation StyxPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];

    // nil == pass the touch through to the next window.
    if (hit == self || hit == self.rootViewController.view) return nil;

    return hit;
}

// Never take key status from the game window. Unity relies on it for input.
- (BOOL)canBecomeKeyWindow {
    return NO;
}

@end