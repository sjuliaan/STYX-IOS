// ============================================================================
// STYX-iOS â€” mod menu (UIKit overlay)
// Floating draggable button -> panel with UISwitch rows + aim slider.
// Non-key window so game input is never stolen.
// ============================================================================
#import <UIKit/UIKit.h>
#import "StyxConfig.h"
#import "StyxAnogs.h"

// Hosts the panel and FAB and re-lays them out on every resize.
//
// layoutSubviews is driven by UIKit itself whenever the bounds change, so this
// survives a rotation without depending on a window-resize notification name
// (there is no public UIWindowDidResizeNotification).
@interface StyxMenuContainer : UIView
@property (nonatomic, weak) UIView *content;
@property (nonatomic, weak) UIButton *fab;
@end


@interface StyxMenuController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) StyxMenuContainer *container;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, assign) BOOL panelOpen;
@property (nonatomic, strong) UISwitch *swEsp, *swBox, *swDist, *swHp, *swAim, *swAc;
@property (nonatomic, strong) UISlider *slAim;
@property (nonatomic, strong) UILabel *lblAim;
@property (nonatomic, strong) UILabel *lblAimCap;
@property (nonatomic, strong) UILabel *lblAc;
@property (nonatomic, assign) BOOL aimSectionVisible;
@end

// Panel geometry. Rows are laid out top-down from these constants and the panel
// height is derived from the content, so nothing can overlap and adding a row
// does not require hand-tuning magic numbers.
static const CGFloat StyxPanelW       = 250.0;
static const CGFloat StyxPanelTitleY  = 10.0;
static const CGFloat StyxPanelRowsY   = 42.0;
static const CGFloat StyxRowH         = 32.0;
static const CGFloat StyxAimRowH      = 46.0;
static const CGFloat StyxPanelGap     = 6.0;    // rows -> diagnostics
static const CGFloat StyxDiagH        = 32.0;
static const CGFloat StyxPanelPad     = 8.0;
static const CGFloat StyxPadX         = 14.0;

@implementation StyxMenuContainer

- (void)layoutSubviews {
    [super layoutSubviews];

    UIView *p = self.content;
    if (p) {
        CGSize s = p.bounds.size;
        p.center = CGPointMake(CGRectGetMidX(self.bounds),
                               round((self.bounds.size.height - s.height) / 2));
    }

    // Keep the draggable button fully on-screen after a rotation.
    UIButton *f = self.fab;
    if (f) {
        CGFloat w = f.bounds.size.width;
        CGFloat h = f.bounds.size.height;
        CGFloat margin = 8.0;
        CGFloat cx = MIN(MAX(f.center.x, margin + w / 2), self.bounds.size.width  - margin - w / 2);
        CGFloat cy = MIN(MAX(f.center.y, margin + h / 2), self.bounds.size.height - margin - h / 2);
        f.center = CGPointMake(cx, cy);
    }
}

// Full-screen container. Returning nil for hits that miss both the panel and
// the FAB lets the window above us ignore the touch, so the game keeps it.
// The container itself is userInteractionEnabled == YES (it must be, to reach
// its subviews), so without this override it would swallow everything.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == nil) return nil;
    return hit;
}

@end

@implementation StyxMenuController

+ (instancetype)shared {
    static StyxMenuController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

+ (void)show { [[self shared] showMenu]; }
+ (void)hide { [[self shared] hideMenu]; }
+ (void)toggle { [[self shared] toggleMenu]; }

- (void)showMenu {
    if (self.window) { self.window.hidden = NO; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self build]; });
}

- (void)hideMenu {
    self.window.hidden = YES;
}

- (void)toggleMenu {
    if (!self.window) { [self showMenu]; return; }
    self.window.hidden = !self.window.hidden;
}

- (UIWindowScene *)activeScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)s;
        }
    }
    return nil;
}

- (void)build {
    UIWindowScene *scene = [self activeScene];
    if (!scene) {
        // Game UI not up yet; retry shortly.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self build]; });
        return;
    }

    self.window = [[StyxPassthroughWindow alloc] initWithWindowScene:scene];
    self.window.windowLevel = UIWindowLevelAlert + 1;   // above the ESP overlay
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [[StyxRootViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    // The root view itself ignores touches, but that alone does NOT let input
    // reach the game -- see StyxPassthroughWindow's hitTest for why.
    self.window.rootViewController.view.userInteractionEnabled = NO;
    self.window.hidden = NO;

    // Container owns layout: it centres the panel and keeps the FAB on-screen
    // whenever the window resizes (rotation), with no dependency on a
    // notification constant.
    self.container = [[StyxMenuContainer alloc] initWithFrame:self.window.bounds];
    self.container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.container.backgroundColor = UIColor.clearColor;
    [self.window addSubview:self.container];

    [self buildFab];
    [self buildPanel];
    self.panel.hidden = YES;
    self.panelOpen = NO;
    [self.container setNeedsLayout];
}

- (void)buildFab {
    CGFloat s = 46;
    // Anchor to the WINDOW, not the screen. [UIScreen mainScreen].bounds is
    // native-portrait (390x844) regardless of orientation, so a fixed y=140 put
    // the button at a different relative spot in landscape than in portrait.
    CGRect wb = (self.window ? self.window.bounds : [UIScreen mainScreen].bounds);
    CGFloat fx = 20;
    CGFloat fy = round(wb.size.height * 0.28f);

    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(fx, fy, s, s);
    self.fab.backgroundColor = [UIColor colorWithRed:0.10f green:0.10f blue:0.12f alpha:0.85f];
    self.fab.layer.cornerRadius = s / 2;
    self.fab.layer.borderWidth = 1.5f;
    self.fab.layer.borderColor = [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:1.0f].CGColor;
    [self.fab setTitle:@"S" forState:UIControlStateNormal];
    [self.fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [self.fab addGestureRecognizer:pan];

    [self.container addSubview:self.fab];
    self.container.fab = self.fab;
}

- (void)buildPanel {
    CGFloat w = StyxPanelW;
    self.panel = [[UIView alloc] initWithFrame:CGRectZero];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08f alpha:0.92f];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.25f alpha:1].CGColor;
    self.panel.clipsToBounds = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, StyxPanelTitleY, w, 24)];
    title.text = @"STYX";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:1];
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.panel addSubview:title];

    CGFloat ty = StyxPanelRowsY;
    self.swEsp  = [self switchRow:@"ESP"        y:&ty];
    self.swBox  = [self switchRow:@"Box"        y:&ty];
    self.swDist = [self switchRow:@"Distance"   y:&ty];
    self.swHp   = [self switchRow:@"Health"     y:&ty];
    self.swAim  = [self switchRow:@"Aim Assist" y:&ty];
    self.swAc   = [self switchRow:@"Anti-Cheat"  y:&ty];

    [self.swEsp  addTarget:self action:@selector(espChanged:)  forControlEvents:UIControlEventValueChanged];
    [self.swBox  addTarget:self action:@selector(boxChanged:)  forControlEvents:UIControlEventValueChanged];
    [self.swDist addTarget:self action:@selector(distChanged:) forControlEvents:UIControlEventValueChanged];
    [self.swHp   addTarget:self action:@selector(hpChanged:)    forControlEvents:UIControlEventValueChanged];
    [self.swAim  addTarget:self action:@selector(aimChanged:)  forControlEvents:UIControlEventValueChanged];
    [self.swAc   addTarget:self action:@selector(acChanged:)    forControlEvents:UIControlEventValueChanged];

    // --- Aim strength row (revealed only when Aim Assist is on) --------------
    // Label, slider and readout share one horizontal band so the slider never
    // sits on top of a row and the value never wraps under the panel edge.
    CGFloat ay = ty + 2;
    self.lblAimCap = [[UILabel alloc] initWithFrame:CGRectMake(StyxPadX, ay + 6, 56, 18)];
    self.lblAimCap.text = @"Strength";
    self.lblAimCap.textColor = [UIColor lightGrayColor];
    self.lblAimCap.font = [UIFont systemFontOfSize:12];
    [self.panel addSubview:self.lblAimCap];

    self.slAim = [[UISlider alloc] initWithFrame:CGRectMake(StyxPadX + 58, ay, w - StyxPadX * 2 - 58 - 34, 26)];
    self.slAim.minimumValue = 1.0f;
    self.slAim.maximumValue = 20.0f;
    self.slAim.value = StyxCfg.aimStrength;
    self.slAim.continuous = YES;
    [self.slAim addTarget:self action:@selector(aimSliderChanged:)
          forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.slAim];

    self.lblAim = [[UILabel alloc] initWithFrame:CGRectMake(w - StyxPadX - 32, ay + 6, 32, 18)];
    self.lblAim.textAlignment = NSTextAlignmentRight;
    self.lblAim.text = [NSString stringWithFormat:@"%.1f", StyxCfg.aimStrength];
    self.lblAim.textColor = [UIColor whiteColor];
    self.lblAim.font = [UIFont systemFontOfSize:11];
    [self.panel addSubview:self.lblAim];

    // --- Live anogs diagnostics ---------------------------------------------
    // Placed after the (optional) aim row, anchored to the panel bottom.
    self.lblAc = [[UILabel alloc] initWithFrame:CGRectZero];
    self.lblAc.textColor = [UIColor colorWithWhite:0.7f alpha:1];
    self.lblAc.font = [UIFont systemFontOfSize:10];
    self.lblAc.numberOfLines = 2;
    [self.panel addSubview:self.lblAc];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w - 42, 6, 32, 24);
    [close setTitle:@"X" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:close];

    [self.container addSubview:self.panel];
    self.container.content = self.panel;

    // Size the panel from its content. The aim row is collapsed by default
    // because Aim Assist ships off.
    [self updateAimSection:StyxCfg.aimOn];
    [self layoutPanel];
}

// Sizes the panel from its content height. The container view centres it in
// layoutSubviews, so this only has to set the height and position the internal
// rows -- x/y are owned by the container and re-applied on every resize.
- (void)layoutPanel {
    CGFloat h = StyxPanelRowsY + 6 * StyxRowH
             + (self.aimSectionVisible ? StyxAimRowH : 0)
             + StyxPanelGap + StyxDiagH + StyxPanelPad;

    self.panel.bounds = CGRectMake(0, 0, StyxPanelW, h);

    CGFloat dy = h - StyxDiagH - StyxPanelPad;
    self.lblAc.frame = CGRectMake(StyxPadX, dy, StyxPanelW - StyxPadX * 2, StyxDiagH);
}

// Named updateAimSection rather than setAimSectionVisible: the latter reads as
// the synthesized setter for the aimSectionVisible property, which trips
// -Wunused-property-ivar.
- (void)updateAimSection:(BOOL)visible {
    self.aimSectionVisible = visible;
    self.lblAimCap.hidden = !visible;
    self.slAim.hidden     = !visible;
    self.lblAim.hidden    = !visible;
    if (self.panel) [self layoutPanel];
}

- (UISwitch *)switchRow:(NSString *)label y:(CGFloat *)y {
    CGFloat w = StyxPanelW;
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - StyxPadX - 51, *y, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:1];

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(StyxPadX, *y + 4, w - StyxPadX * 2 - 60, 24)];
    l.text = label;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:14];
    [self.panel addSubview:l];
    [self.panel addSubview:sw];

    *y += StyxRowH;
    return sw;
}
- (void)togglePanel {
    self.panelOpen = !self.panelOpen;
    self.panel.hidden = !self.panelOpen;
    if (self.panelOpen) [self syncSwitches];
}

- (void)syncSwitches {
    self.swEsp.on  = StyxCfg.espOn;
    self.swBox.on  = StyxCfg.espBox;
    self.swDist.on = StyxCfg.espDistance;
    self.swHp.on   = StyxCfg.espHealth;
    self.swAim.on  = StyxCfg.aimOn;
    self.swAc.on   = StyxCfg.anogsBypassOn;
    self.slAim.value = StyxCfg.aimStrength;
    self.lblAim.text = [NSString stringWithFormat:@"%.1f", StyxCfg.aimStrength];
    [self updateAimSection:StyxCfg.aimOn];
    [self updateAcLabel];
}

// Shows whether the anogs pointer table was found and how much it has
// intercepted so far. Without this, a failed install looks identical to a
// working one (both are just "no kick").
//
// Only the two live counters are shown: the old path/module counters belong to
// interposers that were removed, and reporting zeros for them would imply
// coverage we no longer have.
- (void)updateAcLabel {
    if (!self.lblAc) return;
    if (!StyxAnogs.installed) {
        self.lblAc.text = @"anogs: not loaded / not hooked";
        return;
    }
    uint64_t total = StyxAnogs.hidImages + StyxAnogs.neuteredSysctl;
    self.lblAc.text = [NSString stringWithFormat:
        @"anogs: %d/%d slots | %llu hits (img %llu, dbg %llu)",
        StyxAnogs.hooksApplied,
        StyxAnogs.hooksWanted,
        (unsigned long long)total,
        (unsigned long long)StyxAnogs.hidImages,
        (unsigned long long)StyxAnogs.neuteredSysctl];
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

- (void)aimSliderChanged:(UISlider *)s {
    StyxCfg.aimStrength = s.value;
    self.lblAim.text = [NSString stringWithFormat:@"%.1f", s.value];
}

// ---- switch actions (bound in buildPanel) ----
- (void)espChanged:(UISwitch *)s  { StyxCfg.espOn = s.on; if (s.on) StyxStartOverlay(); }
- (void)boxChanged:(UISwitch *)s  { StyxCfg.espBox = s.on; }
- (void)distChanged:(UISwitch *)s { StyxCfg.espDistance = s.on; }
- (void)hpChanged:(UISwitch *)s    { StyxCfg.espHealth = s.on; }
- (void)aimChanged:(UISwitch *)s  {
    StyxCfg.aimOn = s.on;
    // Reveal the strength row only while the feature is actually usable.
    [self updateAimSection:s.on];
}
- (void)acChanged:(UISwitch *)s    { StyxCfg.anogsBypassOn = s.on; [self updateAcLabel]; }

@end
