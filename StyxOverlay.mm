// ============================================================================
// STYX-iOS — ESP overlay renderer
// Reads game memory via the verified iOS offset table and draws boxes,
// distances and health bars into a single full-screen overlay UIView.
//
// Names are intentionally not drawn: PlayerInfo.m_NickName could not be
// resolved from the 1.6.58 dump (il2cpp reports the sentinel 0x7FFFFFFF),
// so reading it would produce garbage. Bots vs players are distinguished by
// box colour instead (green = bot, red = player).
// ============================================================================
#import <UIKit/UIKit.h>
#import "StyxConfig.h"
#import "StyxOffsets.h"
#import "StyxTypes.h"

// Native il2cpp function pointer typedefs (all instance/static methods)
typedef void   *(*T_Gameplay_get_MatchGame)(void);
typedef void   *(*T_Gameplay_get_LocalPawn)(void);
typedef void   *(*T_Camera_get_main)(void);
typedef Styxi_Vector3 (*T_Camera_W2S)(void *cam, Styxi_Vector3 world, bool sr);
typedef Styxi_Vector3 (*T_Transform_get_position)(void *t);

static T_Gameplay_get_MatchGame   fnMatchGame   = NULL;
static T_Gameplay_get_LocalPawn   fnLocalPawn   = NULL;
static T_Camera_get_main          fnCameraMain  = NULL;
static T_Camera_W2S               fnW2S         = NULL;
static T_Transform_get_position   fnGetPos       = NULL;

// Live counters, surfaced in the menu so "is ESP reading anything?" is visible.
StyxEspStats_t StyxEspStats;

// Small validity gate: refuse to read if the pointer looks non-canonical.
static inline BOOL StyxPtrOK(uintptr_t p) {
    return p > 0x1000 && p < 0x7FFFFFFFFFFFULL;
}

// NOTE: player names were removed. PlayerInfo.m_NickName is not resolvable
// from the 1.6.58 dump (il2cpp emits the sentinel 0x7FFFFFFF for it), so any
// read of that field yields garbage rather than a name.

typedef struct {
    BOOL valid;
    CGPoint head;
    CGPoint root;
    float  health, maxHealth;
    BOOL   isBot;
    BOOL   alive;
    BOOL   visible;
} StyxEntity;

static void StyxEntityFromPawn(uintptr_t pawn, void *cam, CGSize viewSize,
                               CGPoint *headOut, CGPoint *rootOut,
                               float *hpOut, float *maxHpOut,
                               BOOL *botOut, BOOL *aliveOut, BOOL *visOut) {
    StyxEntity e = {0};
    if (!StyxPtrOK(pawn)) { *visOut = NO; return; }

    BOOL alive = *(BOOL *)(pawn + IOS_Pawn__m_IsAlive);
    uintptr_t headT = *(uintptr_t *)(pawn + IOS_Pawn__m_HeadBone);
    uintptr_t rootT = *(uintptr_t *)(pawn + IOS_Pawn__m_Mesh);
    if (!StyxPtrOK(headT) || !StyxPtrOK(rootT)) { *visOut = NO; return; }

    Styxi_Vector3 wh = fnGetPos((void *)headT);
    Styxi_Vector3 rw = fnGetPos((void *)rootT);
    if (wh.z == 0 && rw.z == 0) { *visOut = NO; return; }

    Styxi_Vector3 hsc = fnW2S(cam, wh, NO);
    Styxi_Vector3 rsc = fnW2S(cam, rw, NO);
    if (hsc.z <= 0.0f || rsc.z <= 0.0f) { *visOut = NO; return; }

    e.valid = YES; e.alive = alive;
    e.isBot = *(BOOL *)(pawn + IOS_Pawn__m_IsBot);
    float hp  = *(float *)(pawn + IOS_Pawn__m_Health);
    float mx  = *(float *)(pawn + IOS_Pawn__m_MaxHealth);
    e.health = hp; e.maxHealth = mx;
    // Unity is bottom-left origin; UIKit is top-left. Flip against the VIEW's
    // height, not [UIScreen mainScreen].bounds: on modern iOS the latter reports
    // the native portrait height (844) even in landscape, which would push
    // every box off the bottom of the screen.
    CGFloat viewH = viewSize.height;
    e.head = CGPointMake(hsc.x, viewH - hsc.y);
    e.root = CGPointMake(rsc.x, viewH - rsc.y);
    e.visible = YES;
    *visOut = YES;
    if (headOut) *headOut = e.head;
    if (rootOut) *rootOut = e.root;
    if (hpOut) *hpOut = hp;
    if (maxHpOut) *maxHpOut = mx;
    if (botOut) *botOut = e.isBot;
    if (aliveOut) *aliveOut = alive;
}

static void StyxInitFnPointers(void) {
    if (fnMatchGame) return;
    uintptr_t b = StyxBase();
    fnMatchGame  = (T_Gameplay_get_MatchGame)(b + IOS_Gameplay__get_MatchGame);
    fnLocalPawn  = (T_Gameplay_get_LocalPawn)(b + IOS_Gameplay__get_LocalPawn);
    fnCameraMain = (T_Camera_get_main)(b + IOS_Camera__get_main);
    fnW2S        = (T_Camera_W2S)(b + IOS_Camera__WorldToScreenPoint);
    fnGetPos     = (T_Transform_get_position)(b + IOS_Transform__get_position);
}

// Full-screen transparent view that draws the ESP each frame.
@interface StyxOverlayView : UIView
@end

@implementation StyxOverlayView {
    CADisplayLink *_link;
}

- (instancetype)init {
    // Zero-sized on purpose: +[StyxOverlayWindow shared] sets the real frame from
    // the window bounds. Using [UIScreen mainScreen].bounds here would bake in
    // the native portrait size before we know the orientation.
    self = [super initWithFrame:CGRectZero];
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.contentScaleFactor = [UIScreen mainScreen].scale;
    return self;
}

- (void)start {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFramesPerSecond = 30;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)l {
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (!StyxCfg.espOn) return;
    // Reset per-frame counters so the menu shows the CURRENT frame's numbers.
    StyxEspStats.enemiesSeen = 0;
    StyxEspStats.enemiesDrawn = 0;
    StyxEspStats.frames++;
    StyxInitFnPointers();
    if (!fnMatchGame || !fnW2S) return;

    void *mg = fnMatchGame();
    if (!StyxPtrOK((uintptr_t)mg)) return;

    uintptr_t list = *(uintptr_t *)((uintptr_t)mg + IOS_BaseGame__EnemyPawns);
    if (!StyxPtrOK(list)) return;

    uintptr_t items = *(uintptr_t *)(list + IL2CPP_LIST_ITEMS_OFF);
    int32_t size     = *(int32_t  *)(list + IL2CPP_LIST_SIZE_OFF);
    if (!StyxPtrOK(items) || size <= 0 || size > 512) return;

    uintptr_t *arr = (uintptr_t *)(items + IL2CPP_ARRAY_DATA_OFF);
    // View bounds, not UIScreen.bounds -- see the note on StyxEntityFromPawn.
    CGFloat sw = self.bounds.size.width;

    // Resolve the camera ONCE per frame. This used to be called twice per
    // entity inside the loop, i.e. ~40 cross-language calls per frame at 10
    // enemies, for a value that is constant across the whole frame.
    void *cam = fnCameraMain();
    if (!StyxPtrOK((uintptr_t)cam)) return;

    for (int i = 0; i < size; i++) {
        uintptr_t pawn = arr[i];
        if (!StyxPtrOK(pawn)) continue;
        StyxEspStats.enemiesSeen++;

        CGPoint head, root; float hp, mx; BOOL bot, alive, vis;
        StyxEntityFromPawn(pawn, cam, self.bounds.size, &head, &root, &hp, &mx, &bot, &alive, &vis);
        if (!vis || !alive) continue;
        if (head.x < -50 || head.x > sw + 50) continue;

        CGFloat boxH = fabs(root.y - head.y);
        if (boxH < 20) continue;
        StyxEspStats.enemiesDrawn++;
        CGFloat boxW = boxH * 0.32f;
        CGRect box = CGRectMake(head.x - boxW * 0.5f, head.y, boxW, boxH);

        UIColor *stroke = bot ? [UIColor colorWithRed:0.0f green:1.0f blue:0.4f alpha:0.9f]
                              : [UIColor colorWithRed:1.0f green:0.15f blue:0.2f alpha:0.9f];

        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (StyxCfg.espBox) {
            CGContextSetStrokeColorWithColor(ctx, stroke.CGColor);
            CGContextSetLineWidth(ctx, 1.5f);
            CGContextStrokeRect(ctx, box);
        }
        if (StyxCfg.espHealth && mx > 0) {
            float pct = hp / mx;
            if (pct < 0) pct = 0; if (pct > 1) pct = 1;
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.55f].CGColor);
            CGContextFillRect(ctx, CGRectMake(box.origin.x - 5, box.origin.y, 3, boxH));
            CGContextSetFillColorWithColor(ctx, (pct > 0.5f ? [UIColor greenColor] : (pct > 0.25f ? [UIColor orangeColor] : [UIColor redColor])).CGColor);
            CGContextFillRect(ctx, CGRectMake(box.origin.x - 5, box.origin.y + boxH * (1 - pct), 3, boxH * pct));
        }
        if (StyxCfg.espDistance) {
            void *lp = fnLocalPawn();
            if (StyxPtrOK((uintptr_t)lp)) {
                Styxi_Vector3 lv = *(Styxi_Vector3 *)((uintptr_t)lp + IOS_Pawn__m_LastPawnPos);
                Styxi_Vector3 hv = *(Styxi_Vector3 *)((uintptr_t)pawn + IOS_Pawn__m_LastPawnPos);
                float d = sqrtf((lv.x-hv.x)*(lv.x-hv.x) + (lv.y-hv.y)*(lv.y-hv.y) + (lv.z-hv.z)*(lv.z-hv.z));
                NSString *line = [NSString stringWithFormat:@"%.0fm", d];
                [stroke set];
                [line drawAtPoint:CGPointMake(box.origin.x, box.origin.y - 12) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:9]}];
            }
        }
    }
}
@end

// The overlay window hosting StyxOverlayView. Created with the game's
// UIWindowScene so it attaches properly. It is a StyxPassthroughWindow, so
// touches that miss the overlay fall through to the game rather than being
// swallowed -- the overlay is purely visual.
@interface StyxOverlayWindow ()
@property (nonatomic, strong) StyxOverlayView *overlayView;
@end

@implementation StyxOverlayWindow

// Creates the overlay, or returns nil if the game window is not ready yet.
//
// NOT dispatch_once. The previous version wrapped this in dispatch_once and
// returned nil when no window was available. dispatch_once is consumed even on
// that early return, so the singleton stayed permanently nil and ESP never drew
// again -- no error, no retry. That is why "ESP does nothing".
//
// Creation is now simply retried until it succeeds.
+ (instancetype)shared {
    static StyxOverlayWindow *s = nil;
    if (s) return s;

    // UIKit view creation must happen on the main thread.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ (void)[StyxOverlayWindow shared]; });
        return nil;
    }

    // The overlay lives in the GAME's window, not one of ours: our own window
    // has a fixed portrait-shaped coordinate space, which misplaces every
    // coordinate. The game's window tracks the interface orientation.
    UIWindow *host = StyxHostWindow();
    if (!host) return nil;              // retryable: a later call can succeed

    StyxOverlayWindow *w = [[StyxOverlayWindow alloc] initWithFrame:host.bounds];
    w.backgroundColor = UIColor.clearColor;
    w.userInteractionEnabled = NO;      // purely visual
    w.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:w];

    StyxOverlayView *ov = [[StyxOverlayView alloc] init];
    ov.frame = w.bounds;
    ov.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    ov.backgroundColor = UIColor.clearColor;
    ov.userInteractionEnabled = NO;
    [w addSubview:ov];
    w.overlayView = ov;

    s = w;
    StyxEspStats.alive = YES;
    NSLog(@"[STYX] ESP overlay created in host window (%dx%d)",
          (int)ov.bounds.size.width, (int)ov.bounds.size.height);
    return s;
}

- (void)startDrawing {
    [_overlayView start];
    StyxEspStats.alive = YES;
}
@end

// Retries while the scene is unavailable, so ESP survives being switched on
// before the game UI exists.
static int g_espRetries = 0;

void StyxStartOverlay(void) {
    StyxInitFnPointers();

    StyxOverlayWindow *w = [StyxOverlayWindow shared];
    if (w) {
        [w startDrawing];
        g_espRetries = 0;
        return;
    }

    if (g_espRetries < 30) {
        g_espRetries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ StyxStartOverlay(); });
    } else {
        NSLog(@"[STYX] ESP overlay never obtained a scene after %d retries", g_espRetries);
    }
}
