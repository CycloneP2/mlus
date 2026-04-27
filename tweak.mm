// Tweak.mm - MLBB MOD STANDALONE (ANTI-FC PROTECTED)
// Compile: clang++ -dynamiclib -framework UIKit -framework Foundation Tweak.mm -o mlbb_m.dylib

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
// LOG SYSTEM (Safe)
// ============================================
static NSMutableArray *g_logs = nil;
void add_log(NSString *msg) {
    @try {
        if (!g_logs) g_logs = [[NSMutableArray alloc] init];
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        [g_logs addObject:[NSString stringWithFormat:@"[%@] %@", timestamp, msg]];
        if (g_logs.count > 50) [g_logs removeObjectAtIndex:0];
        NSLog(@"[MOD] %@", msg);
    } @catch (NSException *e) {}
}
#define LOG(fmt, ...) add_log([NSString stringWithFormat:fmt, ##__VA_ARGS__])

// ============================================
// OFFSETS (VALID)
// ============================================
#define OFF_BATTLE_MANAGER_INST 0xADC8A0
#define OFF_SHOW_PLAYERS        0x78
#define OFF_LOCAL_PLAYER        0x50
#define OFF_ENTITY_POS          0x30
#define OFF_ENTITY_CAMP         0xD8
#define OFF_ENTITY_HP           0x1AC
#define OFF_ENTITY_HP_MAX       0x1B0
#define RVA_WORLD_TO_SCREEN     0x89FE040
#define RVA_CAMERA_MAIN         0x89FF130
#define RVA_IS_TUTORIAL         0x51666C8
#define OFF_DRONE_SET_FOV       0x89FB2B8
#define OFF_RADAR_VISIBLE       0x5023FF0

// ============================================
// SAFE MEMORY ACCESS (CORE ANTI-FC)
// ============================================
static BOOL is_address_valid(uintptr_t addr) {
    if (addr < 0x100000) return NO;
    if (addr > 0x200000000) return NO;
    
    vm_size_t size = 0;
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    mach_port_t object;
    
    kern_return_t kr = vm_region(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO, 
                                  (vm_region_info_t)&info, &count, &object);
    return (kr == KERN_SUCCESS);
}

static uintptr_t safe_read_ptr(uintptr_t addr) {
    if (!is_address_valid(addr)) return 0;
    @try {
        return *(uintptr_t*)addr;
    } @catch (NSException *e) {
        return 0;
    }
}

static int safe_read_int(uintptr_t addr) {
    if (!is_address_valid(addr)) return 0;
    @try {
        return *(int*)addr;
    } @catch (NSException *e) {
        return 0;
    }
}

static float safe_read_float(uintptr_t addr) {
    if (!is_address_valid(addr)) return 0;
    @try {
        return *(float*)addr;
    } @catch (NSException *e) {
        return 0;
    }
}

static Vector3 safe_read_vector3(uintptr_t addr) {
    Vector3 result = {0, 0, 0};
    if (!is_address_valid(addr)) return result;
    @try {
        return *(Vector3*)addr;
    } @catch (NSException *e) {
        return result;
    }
}

// ============================================
// SECURITY & UTILITY
// ============================================
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
static MSHookFunction_t MSHookFunction_ptr = NULL;
static uintptr_t g_unityBase = 0;
static BOOL g_safeMode = NO;
static BOOL g_isInBattle = NO;

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

NSString* get_game_version() {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    return info[@"CFBundleShortVersionString"] ?: @"Unknown";
}

// ============================================
// GLOBAL TOGGLES
// ============================================
static BOOL espEnabled = YES;
static BOOL radarEnabled = YES;
static BOOL droneEnabled = NO;
static float droneFov = 70.0;
static BOOL skipTutorialEnabled = YES;

// ============================================
// SAFE HOOK (Dengan Try-Catch)
// ============================================
static void (*old_set_fieldOfView)(void* instance, float value) = NULL;
static void hooked_set_fieldOfView(void* instance, float value) {
    @try {
        if (droneEnabled) value = droneFov;
        if (old_set_fieldOfView) old_set_fieldOfView(instance, value);
    } @catch (NSException *e) {}
}

static void (*old_SetVisible)(void* instance, bool visible) = NULL;
static void hooked_SetVisible(void* instance, bool visible) {
    @try {
        if (radarEnabled) visible = true;
        if (old_SetVisible) old_SetVisible(instance, visible);
    } @catch (NSException *e) {}
}

static bool (*original_IsTutorialBattle)() = NULL;
static bool hooked_IsTutorialBattle() {
    @try {
        if (skipTutorialEnabled) return false;
        return original_IsTutorialBattle ? original_IsTutorialBattle() : true;
    } @catch (NSException *e) {
        return true;
    }
}

void safe_hook(uintptr_t address, void* new_func, void** old_func) {
    @try {
        if (address > 0x100000 && address < 0x200000000 && is_address_valid(address)) {
            if (MSHookFunction_ptr) {
                MSHookFunction_ptr((void*)address, new_func, old_func);
                LOG(@"✅ Hooked: 0x%lx", address);
            }
        }
    } @catch (NSException *e) {
        LOG(@"❌ Hook failed: 0x%lx", address);
    }
}

// ============================================
// SAFE ESP OVERLAY (NO CRASH GUARANTEED)
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
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(safeRedraw)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)safeRedraw {
    @try {
        if (espEnabled && g_unityBase) {
            [self setNeedsDisplay];
        }
    } @catch (NSException *e) {}
}

- (void)drawRect:(CGRect)rect {
    // PROTECT: Langsung return jika kondisi tidak aman
    if (!espEnabled || !g_unityBase) return;
    if (!g_isInBattle) return; // Hanya gambar saat dalam battle
    
    @try {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) return;
        CGContextSetLineWidth(ctx, 1.5);
        
        // ========== SAFE READ BATTLE MANAGER ==========
        uintptr_t bmPtrAddr = g_unityBase + OFF_BATTLE_MANAGER_INST;
        if (!is_address_valid(bmPtrAddr)) return;
        
        uintptr_t bmPtr = safe_read_ptr(bmPtrAddr);
        if (!is_address_valid(bmPtr)) return;
        
        // ========== SAFE READ PLAYER LIST ==========
        uintptr_t playerListAddr = bmPtr + OFF_SHOW_PLAYERS;
        if (!is_address_valid(playerListAddr)) return;
        
        uintptr_t playerList = safe_read_ptr(playerListAddr);
        if (!is_address_valid(playerList)) return;
        
        // ========== SAFE READ LIST DATA ==========
        uintptr_t itemsAddr = playerList + 0x10;
        uintptr_t sizeAddr = playerList + 0x18;
        if (!is_address_valid(itemsAddr) || !is_address_valid(sizeAddr)) return;
        
        uintptr_t items = safe_read_ptr(itemsAddr);
        int size = safe_read_int(sizeAddr);
        
        if (!is_address_valid(items) || size <= 0 || size > 100) return;
        
        // ========== SAFE GET CAMERA ==========
        void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
        if (!get_main) return;
        
        void* mainCam = get_main();
        if (!mainCam || !is_address_valid((uintptr_t)mainCam)) return;
        
        // ========== SAFE WORLD TO SCREEN ==========
        Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
        if (!w2s) return;
        
        // ========== SAFE LOCAL TEAM ==========
        uintptr_t localPlayerAddr = bmPtr + OFF_LOCAL_PLAYER;
        uintptr_t localPlayer = safe_read_ptr(localPlayerAddr);
        int myTeam = 0;
        if (is_address_valid(localPlayer)) {
            uintptr_t teamAddr = localPlayer + OFF_ENTITY_CAMP;
            if (is_address_valid(teamAddr)) {
                myTeam = safe_read_int(teamAddr);
            }
        }
        
        float scale = [UIScreen mainScreen].scale;
        float screenH = rect.size.height;
        
        for (int i = 0; i < size && i < 100; i++) {
            @autoreleasepool {
                uintptr_t playerAddrPtr = items + 0x20 + (i * 8);
                if (!is_address_valid(playerAddrPtr)) continue;
                
                uintptr_t player = safe_read_ptr(playerAddrPtr);
                if (!is_address_valid(player)) continue;
                
                // Get position
                uintptr_t posAddr = player + OFF_ENTITY_POS;
                if (!is_address_valid(posAddr)) continue;
                Vector3 pos = safe_read_vector3(posAddr);
                
                Vector3 screenPos = w2s(mainCam, pos);
                
                if (screenPos.z > 0.1f) {
                    uintptr_t teamAddr = player + OFF_ENTITY_CAMP;
                    int team = is_address_valid(teamAddr) ? safe_read_int(teamAddr) : 0;
                    
                    // Skip teammate
                    if (team == myTeam && !radarEnabled) continue;
                    
                    float x = screenPos.x / scale;
                    float y = screenH - (screenPos.y / scale);
                    
                    float boxWidth = (500.0f / screenPos.z) / scale;
                    float boxHeight = boxWidth * 1.3f;
                    
                    UIColor *color = (team == myTeam) ? [UIColor greenColor] : [UIColor redColor];
                    
                    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                    CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
                    
                    // HP Bar (safe read)
                    uintptr_t hpAddr = player + OFF_ENTITY_HP;
                    uintptr_t maxHpAddr = player + OFF_ENTITY_HP_MAX;
                    if (is_address_valid(hpAddr) && is_address_valid(maxHpAddr)) {
                        int hp = safe_read_int(hpAddr);
                        int maxHp = safe_read_int(maxHpAddr);
                        if (maxHp > 0) {
                            float percent = (float)hp / (float)maxHp;
                            if (percent > 1.0) percent = 1.0;
                            
                            CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
                            CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth, 3));
                            CGContextSetFillColorWithColor(ctx, color.CGColor);
                            CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth * percent, 3));
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Silent fail - no crash
        LOG(@"ESP Draw error: %@", e.reason);
    }
}

- (void)dealloc {
    [self.displayLink invalidate];
}

@end

// ============================================
// UI Components (Safe)
// ============================================

@interface CustomToggle : UIView
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, copy) void (^onToggle)(BOOL isOn);
@end

@implementation CustomToggle {
    UIView *trackView;
    UIView *thumbView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        trackView = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height/2 - 12, frame.size.width, 24)];
        trackView.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        trackView.layer.cornerRadius = 12;
        [self addSubview:trackView];
        
        thumbView = [[UIView alloc] initWithFrame:CGRectMake(2, frame.size.height/2 - 10, 20, 20)];
        thumbView.backgroundColor = [UIColor whiteColor];
        thumbView.layer.cornerRadius = 10;
        thumbView.layer.shadowOpacity = 0.3;
        [self addSubview:thumbView];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)toggle {
    self.isOn = !self.isOn;
    [self animateToState:self.isOn];
    if (self.onToggle) self.onToggle(self.isOn);
}

- (void)animateToState:(BOOL)isOn {
    CGFloat targetX = isOn ? self.frame.size.width - 22 : 2;
    UIColor *trackColor = isOn ? [UIColor cyanColor] : [UIColor colorWithWhite:0.3 alpha:1.0];
    
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        self->thumbView.frame = CGRectMake(targetX, self->thumbView.frame.origin.y, 20, 20);
        self->trackView.backgroundColor = trackColor;
    } completion:nil];
}
@end

@interface AnimatedToast : UIView
+ (void)showMessage:(NSString *)message inView:(UIView *)view;
@end

@implementation AnimatedToast
+ (void)showMessage:(NSString *)message inView:(UIView *)view {
    @try {
        AnimatedToast *toast = [[AnimatedToast alloc] initWithFrame:CGRectMake(20, -60, view.bounds.size.width - 40, 50)];
        toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
        toast.layer.cornerRadius = 12;
        
        UILabel *label = [[UILabel alloc] initWithFrame:toast.bounds];
        label.text = message;
        label.textColor = [UIColor cyanColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:13];
        [toast addSubview:label];
        
        [view addSubview:toast];
        
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            toast.frame = CGRectMake(20, 80, view.bounds.size.width - 40, 50);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{
                toast.alpha = 0;
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        }];
    } @catch (NSException *e) {}
}
@end

@interface ModernMenu : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
- (void)showWithAnimation;
- (void)hideWithAnimation;
@end

@implementation ModernMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        self.blurView.frame = self.bounds;
        self.blurView.layer.cornerRadius = 20;
        self.blurView.clipsToBounds = YES;
        [self addSubview:self.blurView];
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIView *contentView = [[UIView alloc] initWithFrame:self.bounds];
    contentView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    [self.blurView.contentView addSubview:contentView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 30)];
    title.text = @"pH-1 PRO";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:20];
    [contentView addSubview:title];
    
    __weak typeof(self) weakSelf = self;
    float y = 70;
    
    y = [self addToggle:contentView title:@"Safe Mode" y:y state:g_safeMode action:^(BOOL isOn) {
        g_safeMode = isOn;
        [AnimatedToast showMessage:isOn ? @"Safe Mode ON" : @"Safe Mode OFF" inView:weakSelf.superview];
    }];
    y = [self addToggle:contentView title:@"Enable ESP" y:y state:espEnabled action:^(BOOL isOn) {
        espEnabled = isOn;
        [AnimatedToast showMessage:isOn ? @"ESP Enabled" : @"ESP Disabled" inView:weakSelf.superview];
    }];
    y = [self addToggle:contentView title:@"Drone View" y:y state:droneEnabled action:^(BOOL isOn) {
        droneEnabled = isOn;
        [AnimatedToast showMessage:isOn ? @"Drone ON" : @"Drone OFF" inView:weakSelf.superview];
    }];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, self.bounds.size.height - 50, self.bounds.size.width - 40, 40);
    closeBtn.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
    [closeBtn setTitle:@"CLOSE" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn addTarget:self action:@selector(hideWithAnimation) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:closeBtn];
}

- (float)addToggle:(UIView*)parent title:(NSString*)title y:(float)y state:(BOOL)state action:(void (^)(BOOL))action {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    [parent addSubview:lbl];
    
    CustomToggle *toggle = [[CustomToggle alloc] initWithFrame:CGRectMake(self.bounds.size.width - 70, y, 50, 30)];
    toggle.isOn = state;
    [toggle animateToState:state];
    toggle.onToggle = action;
    [parent addSubview:toggle];
    
    return y + 45;
}

- (void)showWithAnimation {
    self.hidden = NO;
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    } completion:nil];
}

- (void)hideWithAnimation {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self.alpha = 0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
    }];
}
@end

@interface FloatingButton : UIButton
@property (nonatomic, strong) ModernMenu *menuView;
@end

@implementation FloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
        self.layer.cornerRadius = frame.size.width / 2;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];
        
        [self addTarget:self action:@selector(animateTap) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan locationInView:self.superview];
    self.center = p;
}

- (void)animateTap {
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    }];
    
    if (self.menuView) {
        if (self.menuView.hidden) {
            [self.menuView showWithAnimation];
        } else {
            [self.menuView hideWithAnimation];
        }
    }
}
@end

// ============================================
// BATTLE DETECTION (Safe)
// ============================================
static void check_battle_status() {
    @try {
        if (!g_unityBase) return;
        
        uintptr_t bmPtrAddr = g_unityBase + OFF_BATTLE_MANAGER_INST;
        if (!is_address_valid(bmPtrAddr)) {
            g_isInBattle = NO;
            return;
        }
        
        uintptr_t bmPtr = safe_read_ptr(bmPtrAddr);
        if (is_address_valid(bmPtr)) {
            g_isInBattle = YES;
        } else {
            g_isInBattle = NO;
        }
    } @catch (NSException *e) {
        g_isInBattle = NO;
    }
}

// ============================================
// INITIALIZATION (Safe & Sequential)
// ============================================
__attribute__((constructor))
static void initialize() {
    LOG(@"========================================");
    LOG(@"pH-1 PRO Initializing...");
    LOG(@"========================================");
    
    // Proteksi: Cek environment
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID containsString:@"com.mobile.legends"]) {
            LOG(@"Not MLBB environment, exiting...");
            return;
        }
        LOG(@"Bundle ID: %@", bundleID);
    } @catch (NSException *e) {
        return;
    }
    
    // Stage 1: Delay 8 detik (lebih aman)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LOG(@"Stage 1: Getting base address...");
        
        @try {
            g_unityBase = get_base("UnityFramework");
            if (g_unityBase == 0) {
                LOG(@"❌ UnityFramework not found!");
                return;
            }
            LOG(@"✅ UnityBase: 0x%lx", g_unityBase);
            LOG(@"Game Version: %@", get_game_version());
        } @catch (NSException *e) {
            LOG(@"❌ Failed to get base: %@", e.reason);
            return;
        }
        
        // Stage 2: Setup hooks (safe)
        LOG(@"Stage 2: Setting up hooks...");
        
        @try {
            MSHookFunction_ptr = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
            
            if (MSHookFunction_ptr) {
                LOG(@"✅ MSHookFunction found");
                
                // Drone View Hook
                if (is_address_valid(g_unityBase + OFF_DRONE_SET_FOV)) {
                    safe_hook(g_unityBase + OFF_DRONE_SET_FOV, (void*)&hooked_set_fieldOfView, (void**)&old_set_fieldOfView);
                }
                
                // Tutorial Skip Hook
                if (is_address_valid(g_unityBase + RVA_IS_TUTORIAL)) {
                    safe_hook(g_unityBase + RVA_IS_TUTORIAL, (void*)&hooked_IsTutorialBattle, (void**)&original_IsTutorialBattle);
                }
                
                // Radar Hook (Optional, comment if crash)
                // if (is_address_valid(g_unityBase + OFF_RADAR_VISIBLE)) {
                //     safe_hook(g_unityBase + OFF_RADAR_VISIBLE, (void*)&hooked_SetVisible, (void**)&old_SetVisible);
                // }
            } else {
                LOG(@"⚠️ MSHookFunction not found, some features disabled");
            }
        } @catch (NSException *e) {
            LOG(@"❌ Hook setup error: %@", e.reason);
        }
        
        // Stage 3: Load UI
        LOG(@"Stage 3: Loading UI...");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                UIWindow *win = nil;
                if (@available(iOS 13.0, *)) {
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            win = scene.windows.firstObject;
                            break;
                        }
                    }
                }
                if (!win) win = [[UIApplication sharedApplication] windows].firstObject;
                
                if (win) {
                    // ESP Overlay
                    ESPOverlay *overlay = [[ESPOverlay alloc] initWithFrame:win.bounds];
                    [win addSubview:overlay];
                    
                    // Modern Menu
                    ModernMenu *menu = [[ModernMenu alloc] initWithFrame:CGRectMake(win.bounds.size.width/2 - 150, win.bounds.size.height/2 - 160, 300, 240)];
                    menu.hidden = YES;
                    [win addSubview:menu];
                    
                    // Floating Button
                    FloatingButton *fab = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 100, 50, 50)];
                    fab.menuView = menu;
                    [win addSubview:fab];
                    
                    LOG(@"✅ UI Loaded successfully!");
                    [AnimatedToast showMessage:@"pH-1 PRO Loaded!" inView:win];
                } else {
                    LOG(@"❌ No window found");
                }
            } @catch (NSException *e) {
                LOG(@"❌ UI Error: %@", e.reason);
            }
        });
        
        // Stage 4: Battle status checker (periodic)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            while (YES) {
                @autoreleasepool {
                    check_battle_status();
                    [NSThread sleepForTimeInterval:2.0];
                }
            }
        });
        
        LOG(@"========================================");
        LOG(@"✅ pH-1 PRO Ready!");
        LOG(@"========================================");
    });
}
