// Tweak.mm - MLBB MOD STANDALONE (PRO EDITION)
// UPDATED WITH DUMP.CS OFFSETS & SECURITY FEATURES

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

typedef struct {
    float x, y, z;
} Vector3;

// ============================================
// LOG SYSTEM
// ============================================
static NSMutableArray *g_logs = nil;
void add_log(NSString *msg) {
    if (!g_logs) g_logs = [[NSMutableArray alloc] init];
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    [g_logs addObject:[NSString stringWithFormat:@"[%@] %@", timestamp, msg]];
    if (g_logs.count > 50) [g_logs removeObjectAtIndex:0];
    NSLog(@"[Antigravity] %@", msg);
}
#define LOG(fmt, ...) add_log([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ============================================
// OFFSETS (FROM DUMP.CS)
// ============================================
#define OFF_BATTLE_MANAGER_INST 0xADC8A0   
#define OFF_SHOW_PLAYERS        0x78        
#define OFF_LOCAL_PLAYER        0x50        
#define OFF_ENTITY_POS          0x30        
#define OFF_ENTITY_CAMP         0xD8        
#define OFF_ENTITY_HP           0x1AC       
#define OFF_ENTITY_HP_MAX       0x1B0       
#define OFF_ENTITY_SHIELD       0x1B8       
#define OFF_PLAYER_HERO_NAME    0x918       
#define RVA_WORLD_TO_SCREEN     0x89FE040   
#define RVA_CAMERA_MAIN         0x89FF130   

#define RVA_SDK_REPORT_LOG      0x4CEB580
#define RVA_SDK_REPORT_ERR      0x4CEB690
#define RVA_SDK_SEND_STEP       0x4CEB7A0

#define OFF_DRONE_SET_FOV       0x89FB2B8
#define OFF_RADAR_VISIBLE       0x5023FF0

// ============================================
// GLOBAL TOGGLES
// ============================================
static BOOL espEnabled = YES;
static BOOL lineEnabled = YES;
static BOOL hpBarEnabled = YES;
static BOOL distEnabled = YES;
static BOOL antiReport = YES;
static BOOL autoDelete = YES;
static BOOL radarEnabled = YES;
static BOOL droneEnabled = NO;
static float droneFov = 70.0;

// ============================================
// SECURITY & HOOKS
// ============================================
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
static MSHookFunction_t MSHookFunction_ptr = NULL;
static uintptr_t g_unityBase = 0;

void self_destruct() {
    LOG(@"[CRITICAL] Ban Detection! Self-destructing...");
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "mlbb_m.dylib") || strstr(name, "edgymlbb.dylib"))) {
            unlink(name);
            break;
        }
    }
    exit(0);
}

static void (*old_ReportLog)(void* msg);
static void hooked_ReportLog(void* msg) { if (antiReport) return; if (old_ReportLog) old_ReportLog(msg); }

static void (*old_set_fieldOfView)(void* instance, float value);
static void hooked_set_fieldOfView(void* instance, float value) {
    if (droneEnabled) value = droneFov;
    if (old_set_fieldOfView) old_set_fieldOfView(instance, value);
}

static void (*old_SetVisible)(void* instance, bool visible);
static void hooked_SetVisible(void* instance, bool visible) {
    if (radarEnabled) visible = true;
    if (old_SetVisible) old_SetVisible(instance, visible);
}

static void (*old_GMBan)(unsigned long uid);
static void hooked_GMBan(unsigned long uid) {
    if (autoDelete) self_destruct();
    if (old_GMBan) old_GMBan(uid);
}

// ============================================
// ESP OVERLAY
// ============================================

@interface ESPOverlay : UIView
@property (nonatomic, strong) CADisplayLink *displayLink;
@end

@implementation ESPOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}
- (void)redraw { if (espEnabled) [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!espEnabled || !g_unityBase) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    uintptr_t bmPtr = *(uintptr_t*)(g_unityBase + OFF_BATTLE_MANAGER_INST);
    if (!bmPtr) return;
    uintptr_t playerList = *(uintptr_t*)(bmPtr + OFF_SHOW_PLAYERS);
    if (!playerList) return;
    
    void* items = *(void**)(playerList + 0x10);
    int size = *(int*)(playerList + 0x18);
    if (!items || size <= 0) return;
    
    void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
    void* mainCam = get_main();
    if (!mainCam) return;
    
    Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
    uintptr_t localPlayer = *(uintptr_t*)(bmPtr + OFF_LOCAL_PLAYER);
    int myTeam = localPlayer ? *(int*)(localPlayer + OFF_ENTITY_CAMP) : 0;
    
    for (int i = 0; i < size; i++) {
        uintptr_t player = *(uintptr_t*)((uintptr_t)items + 0x20 + (i * 8));
        if (!player) continue;
        
        Vector3 pos = *(Vector3*)(player + OFF_ENTITY_POS);
        Vector3 screenPos = w2s(mainCam, pos);
        
        if (screenPos.z > 0) {
            int team = *(int*)(player + OFF_ENTITY_CAMP);
            if (team == myTeam && !radarEnabled) continue;
            
            float scale = [UIScreen mainScreen].scale;
            float x = screenPos.x / scale;
            float y = rect.size.height - (screenPos.y / scale);
            float boxWidth = (500.0f / screenPos.z) / scale;
            float boxHeight = boxWidth * 1.3f;
            
            UIColor *color = (team == myTeam) ? [UIColor greenColor] : [UIColor redColor];
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 1.5);

            CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
            
            if (lineEnabled) {
                CGContextSetStrokeColorWithColor(ctx, [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor);
                CGContextMoveToPoint(ctx, rect.size.width/2, rect.size.height/2);
                CGContextAddLineToPoint(ctx, x, y);
                CGContextStrokePath(ctx);
            }

            if (hpBarEnabled) {
                int hp = *(int*)(player + OFF_ENTITY_HP);
                int maxHp = *(int*)(player + OFF_ENTITY_HP_MAX);
                int shield = *(int*)(player + OFF_ENTITY_SHIELD);
                float hpPct = (float)hp / (float)maxHp;
                float shPct = (float)shield / (float)maxHp;

                CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
                CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 10, boxWidth, 4));
                CGContextSetFillColorWithColor(ctx, (hpPct > 0.3) ? [UIColor greenColor].CGColor : [UIColor redColor].CGColor);
                CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 10, boxWidth * hpPct, 4));
                if (shield > 0) {
                    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.9 alpha:0.7].CGColor);
                    CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 10, boxWidth * MIN(shPct, 1.0), 4));
                }
            }

            if (distEnabled) {
                NSString *distStr = [NSString stringWithFormat:@"%.0fm", screenPos.z];
                [distStr drawAtPoint:CGPointMake(x + boxWidth/2 + 3, y - boxHeight) withAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:10]}];
            }
        }
    }
}
@end

@interface CustomToggle : UIView
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, copy) void (^onToggle)(BOOL isOn);
- (void)animateToState:(BOOL)isOn;
@end

@implementation CustomToggle { UIView *track; UIView *thumb; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        track = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 46, 22)];
        track.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        track.layer.cornerRadius = 11;
        [self addSubview:track];
        thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 6, 18, 18)];
        thumb.backgroundColor = [UIColor whiteColor];
        thumb.layer.cornerRadius = 9;
        [self addSubview:thumb];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    }
    return self;
}
- (void)tapped { self.isOn = !self.isOn; [self animateToState:self.isOn]; if (self.onToggle) self.onToggle(self.isOn); }
- (void)animateToState:(BOOL)isOn {
    [UIView animateWithDuration:0.3 animations:^{
        self->thumb.frame = CGRectMake(isOn ? 26 : 2, 6, 18, 18);
        self->track.backgroundColor = isOn ? [UIColor cyanColor] : [UIColor colorWithWhite:0.2 alpha:1.0];
    }];
}
@end

@interface ModernMenu : UIView
- (void)show; - (void)hide;
@end

@implementation ModernMenu { UIView *content; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
        bg.frame = self.bounds;
        bg.layer.cornerRadius = 20;
        bg.clipsToBounds = YES;
        bg.layer.borderWidth = 1.5;
        bg.layer.borderColor = [UIColor cyanColor].CGColor;
        [self addSubview:bg];
        
        content = [[UIView alloc] initWithFrame:self.bounds];
        [bg.contentView addSubview:content];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, self.frame.size.width, 30)];
    title.text = @"pH-1 PRO GANG";
    title.textColor = [UIColor cyanColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont fontWithName:@"AvenirNext-Bold" size:18];
    [content addSubview:title];
    
    float y = 60;
    y = [self addToggle:@"Enable ESP" y:y state:espEnabled action:^(BOOL isOn) { espEnabled = isOn; }];
    y = [self addToggle:@"Snaplines" y:y state:lineEnabled action:^(BOOL isOn) { lineEnabled = isOn; }];
    y = [self addToggle:@"HP & Shield" y:y state:hpBarEnabled action:^(BOOL isOn) { hpBarEnabled = isOn; }];
    y = [self addToggle:@"Distance" y:y state:distEnabled action:^(BOOL isOn) { distEnabled = isOn; }];
    y = [self addToggle:@"Anti-Report" y:y state:antiReport action:^(BOOL isOn) { antiReport = isOn; }];
    y = [self addToggle:@"Auto Delete" y:y state:autoDelete action:^(BOOL isOn) { autoDelete = isOn; }];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, self.frame.size.height - 50, self.frame.size.width - 40, 35);
    close.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.6];
    [close setTitle:@"HIDE MENU" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.layer.cornerRadius = 10;
    [close addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];
}

- (float)addToggle:(NSString *)text y:(float)y state:(BOOL)state action:(void (^)(BOOL))action {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    lbl.text = text; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:14];
    [content addSubview:lbl];
    CustomToggle *t = [[CustomToggle alloc] initWithFrame:CGRectMake(self.frame.size.width - 66, y, 46, 30)];
    t.isOn = state; [t animateToState:state]; t.onToggle = action;
    [content addSubview:t];
    return y + 40;
}

- (void)show { self.hidden = NO; self.alpha = 0; [UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }]; }
- (void)hide { [UIView animateWithDuration:0.3 animations:^{ self.alpha = 0; } completion:^(BOOL f){ self.hidden = YES; }]; }
@end

@interface FloatingFab : UIButton
@property (nonatomic, strong) ModernMenu *menu;
@end
@implementation FloatingFab
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor cyanColor];
        self.layer.cornerRadius = frame.size.width/2;
        [self setTitle:@"P" forState:UIControlStateNormal];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)tapped { if (self.menu.hidden) [self.menu show]; else [self.menu hide]; }
- (void)pan:(UIPanGestureRecognizer *)p { self.center = [p locationInView:self.superview]; }
@end

// ============================================
// INITIALIZATION
// ============================================
uintptr_t get_base(const char* name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* img_name = _dyld_get_image_name(i);
        if (img_name && strstr(img_name, name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void safe_hook(uintptr_t address, void* new_func, void** old_func) {
    if (MSHookFunction_ptr && address > 0x1000) {
        MSHookFunction_ptr((void*)address, new_func, old_func);
    }
}

__attribute__((constructor))
static void initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_unityBase = get_base("UnityFramework");
        MSHookFunction_ptr = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
        
        safe_hook(g_unityBase + OFF_DRONE_SET_FOV, (void*)&hooked_set_fieldOfView, (void**)&old_set_fieldOfView);
        safe_hook(g_unityBase + OFF_RADAR_VISIBLE, (void*)&hooked_SetVisible, (void**)&old_SetVisible);
        safe_hook(g_unityBase + RVA_SDK_REPORT_LOG, (void*)&hooked_ReportLog, (void**)&old_ReportLog);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *win = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        win = scene.windows.firstObject;
                        break;
                    }
                }
            }
            if (!win) win = [UIApplication sharedApplication].keyWindow;
            if (!win) win = [UIApplication sharedApplication].windows.firstObject;
            
            if (win) {
                [win addSubview:[[ESPOverlay alloc] initWithFrame:win.bounds]];
                ModernMenu *menu = [[ModernMenu alloc] initWithFrame:CGRectMake(win.bounds.size.width/2-110, win.bounds.size.height/2-175, 220, 350)];
                menu.hidden = YES;
                [win addSubview:menu];
                FloatingFab *fab = [[FloatingFab alloc] initWithFrame:CGRectMake(50, 150, 50, 50)];
                fab.menu = menu;
                [win addSubview:fab];
            }
        });
    });
}
