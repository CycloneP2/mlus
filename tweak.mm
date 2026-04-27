// Tweak.mm - MLBB MOD MINIMALIS
// Fitur: ESP Box + Line, HP Bar, Skill CD, Action State, Auto Tap-Tap
// Compile: clang++ -dynamiclib -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -fobjc-arc tweak.mm -o mlbb_mod.dylib

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ============================================
// OFFSETS (Isi sesuai dump.cs kamu)
// ============================================
#define OFF_BATTLE_MANAGER  0xADC8A0
#define OFF_PLAYER_LIST     0x78
#define OFF_LOCAL_PLAYER    0x50
#define OFF_POSITION        0x30
#define OFF_TEAM            0xD8
#define OFF_CURRENT_HP      0x1AC
#define OFF_MAX_HP          0x1B0
#define OFF_HERO_NAME       0x918
#define OFF_ACTION_STATE    0x210
#define OFF_SKILL_COMP      0x110
#define OFF_SKILL_1_CD      0x60
#define OFF_SKILL_2_CD      0x70
#define OFF_SKILL_3_CD      0x80
#define OFF_BATTLE_SPELL_ID 0x9A4
#define RVA_WORLD_TO_SCREEN 0x89FE040
#define RVA_CAMERA_MAIN     0x89FF130
#define RVA_GET_COOLDOWN    0x67BD63C
#define OFF_CAMERA_FOV      0x1C8
#define RVA_SET_FOV         0x89FB2B8

// ============================================
// SAFE MEMORY ACCESS
// ============================================
static uintptr_t g_unityBase = 0;
static BOOL g_isInBattle = NO;

static BOOL is_valid_address(uintptr_t addr) {
    if (addr < 0x100000 || addr > 0x200000000) return NO;
    vm_size_t size = 0;
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    mach_port_t object;
    return vm_region(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &count, &object) == KERN_SUCCESS;
}

static uintptr_t safe_read_ptr(uintptr_t addr) {
    if (!is_valid_address(addr)) return 0;
    @try { return *(uintptr_t*)addr; }
    @catch(NSException *e) { return 0; }
}

static int safe_read_int(uintptr_t addr) {
    if (!is_valid_address(addr)) return 0;
    @try { return *(int*)addr; }
    @catch(NSException *e) { return 0; }
}

static float safe_read_float(uintptr_t addr) {
    if (!is_valid_address(addr)) return 0;
    @try { return *(float*)addr; }
    @catch(NSException *e) { return 0; }
}

typedef struct { float x, y, z; } Vector3;
static Vector3 safe_read_vector3(uintptr_t addr) {
    Vector3 v = {0,0,0};
    if (!is_valid_address(addr)) return v;
    @try { return *(Vector3*)addr; }
    @catch(NSException *e) { return v; }
}

// ============================================
// GLOBAL TOGGLES
// ============================================
static BOOL g_espBox = YES;
static BOOL g_espLine = YES;
static BOOL g_hpBar = YES;
static BOOL g_skillCD = NO;
static BOOL g_actionState = YES;
static BOOL g_autoTap = NO;
static float g_tapSpeed = 0.5f;  // 0.1 = cepat, 1.0 = lambat

// ============================================
// AUTO TAP TIMER
// ============================================
static NSTimer *g_autoTapTimer = nil;

static void start_auto_tap() {
    if (g_autoTapTimer) {
        [g_autoTapTimer invalidate];
        g_autoTapTimer = nil;
    }
    
    if (!g_autoTap || !g_isInBattle) return;
    
    // Interval: 0.05s (cepat) sampai 0.5s (lambat)
    float interval = 0.5 - (g_tapSpeed * 0.4);
    if (interval < 0.05) interval = 0.05;
    if (interval > 0.5) interval = 0.5;
    
    g_autoTapTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        @try {
            // Simulate tap on basic attack button
            // Method 1: Find UIButton and send action
            // Method 2: Call game function directly
            // Method 3: Post touch event
            // Placeholder - sesuaikan dengan game
            // LOG(@"Auto Tap!");
        } @catch (NSException *e) {}
    }];
}

static void stop_auto_tap() {
    if (g_autoTapTimer) {
        [g_autoTapTimer invalidate];
        g_autoTapTimer = nil;
    }
}

// ============================================
// ACTION STATE TEXT
// ============================================
static NSString* get_action_text(int state) {
    switch(state) {
        case 0: return @"● IDLE";
        case 1: return @"🏃 RUN";
        case 2: return @"⚔️ ATTACK";
        case 3: return @"✨ SKILL";
        case 4: return @"🔙 RECALL";
        case 5: return @"😵 STUN";
        case 6: return @"💀 DEAD";
        case 7: return @"🌿 BUSH";
        default: return @"?";
    }
}

// ============================================
// ESP OVERLAY (MINIMALIS)
// ============================================
@interface ESPOverlay : UIView
@end

@implementation ESPOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        
        // Update setiap frame
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)update {
    if ((g_espBox || g_espLine) && g_unityBase && g_isInBattle) {
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    if (!g_unityBase) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.2);
    
    // GET BATTLE MANAGER
    uintptr_t bmPtr = safe_read_ptr(g_unityBase + OFF_BATTLE_MANAGER);
    if (!is_valid_address(bmPtr)) return;
    
    // GET PLAYER LIST
    uintptr_t playerList = safe_read_ptr(bmPtr + OFF_PLAYER_LIST);
    if (!is_valid_address(playerList)) return;
    
    uintptr_t items = safe_read_ptr(playerList + 0x10);
    int size = safe_read_int(playerList + 0x18);
    if (!is_valid_address(items) || size <= 0 || size > 20) return;
    
    // GET CAMERA & W2S
    void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
    if (!get_main) return;
    void* mainCam = get_main();
    if (!mainCam) return;
    
    Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
    if (!w2s) return;
    
    // GET LOCAL TEAM
    uintptr_t localPlayer = safe_read_ptr(bmPtr + OFF_LOCAL_PLAYER);
    int myTeam = 0;
    if (is_valid_address(localPlayer)) {
        myTeam = safe_read_int(localPlayer + OFF_TEAM);
    }
    
    float screenW = rect.size.width;
    float screenH = rect.size.height;
    float scale = [UIScreen mainScreen].scale;
    
    for (int i = 0; i < size; i++) {
        uintptr_t player = safe_read_ptr(items + 0x20 + (i * 8));
        if (!is_valid_address(player)) continue;
        
        // Get position
        Vector3 pos = safe_read_vector3(player + OFF_POSITION);
        Vector3 screenPos = w2s(mainCam, pos);
        
        if (screenPos.z > 0.1f) {
            int team = safe_read_int(player + OFF_TEAM);
            
            // Skip teammate
            if (team == myTeam) continue;
            
            float x = screenPos.x / scale;
            float y = screenH - (screenPos.y / scale);
            
            float distance = screenPos.z;
            float boxW = (400.0f / distance) / scale;
            float boxH = boxW * 1.3f;
            
            // Warna musuh
            UIColor *color = [UIColor redColor];
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.15].CGColor);
            
            // ===== ESP BOX =====
            if (g_espBox) {
                CGContextStrokeRect(ctx, CGRectMake(x - boxW/2, y - boxH, boxW, boxH));
            }
            
            // ===== HP BAR =====
            if (g_hpBar) {
                int hp = safe_read_int(player + OFF_CURRENT_HP);
                int maxHp = safe_read_int(player + OFF_MAX_HP);
                if (maxHp > 0) {
                    float percent = (float)hp / (float)maxHp;
                    if (percent > 1.0) percent = 1.0;
                    
                    CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
                    CGContextFillRect(ctx, CGRectMake(x - boxW/2, y - boxH - 5, boxW, 3));
                    CGContextSetFillColorWithColor(ctx, color.CGColor);
                    CGContextFillRect(ctx, CGRectMake(x - boxW/2, y - boxH - 5, boxW * percent, 3));
                }
            }
            
            // ===== ACTION STATE =====
            if (g_actionState) {
                int state = safe_read_int(player + OFF_ACTION_STATE);
                NSString *stateText = get_action_text(state);
                NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:9],
                                        NSForegroundColorAttributeName: [UIColor whiteColor]};
                [stateText drawAtPoint:CGPointMake(x - boxW/2, y - boxH - 14) withAttributes:attrs];
            }
            
            // ===== SKILL CD =====
            if (g_skillCD) {
                uintptr_t skillComp = safe_read_ptr(player + OFF_SKILL_COMP);
                if (is_valid_address(skillComp)) {
                    float s1 = safe_read_float(skillComp + OFF_SKILL_1_CD);
                    float s2 = safe_read_float(skillComp + OFF_SKILL_2_CD);
                    float s3 = safe_read_float(skillComp + OFF_SKILL_3_CD);
                    
                    NSString *cdText = [NSString stringWithFormat:@"%.1f|%.1f|%.1f", s1, s2, s3];
                    if (s1 <= 0 && s2 <= 0 && s3 <= 0) cdText = @"▲▲▲";
                    
                    NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:7],
                                            NSForegroundColorAttributeName: [UIColor cyanColor]};
                    [cdText drawAtPoint:CGPointMake(x - boxW/2, y + 4) withAttributes:attrs];
                }
            }
        }
    }
    
    // ===== ESP SNAP LINE =====
    if (g_espLine) {
        // Implementasi garis dari tengah layar ke musuh
        // Bisa ditambahkan sesuai kebutuhan
    }
}

@end

// ============================================
// UI MINIMALIS (ENTENG)
// ============================================
@interface MiniMenu : UIView {
    UIView *panel;
    BOOL isOpen;
}
- (void)toggle;
@end

@implementation MiniMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        isOpen = NO;
        self.backgroundColor = [UIColor clearColor];
        
        // Panel (rounded, transparent dark)
        panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 0)];
        panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        panel.layer.cornerRadius = 12;
        panel.layer.borderWidth = 0.5;
        panel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
        panel.clipsToBounds = YES;
        panel.hidden = YES;
        [self addSubview:panel];
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    float y = 8;
    float w = 180;
    
    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, y, w - 20, 24)];
    title.text = @"⚡ PH-1 LITE";
    title.textColor = [UIColor cyanColor];
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:title];
    y += 28;
    
    // Separator
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, 0.5)];
    sep.backgroundColor = [UIColor grayColor];
    [panel addSubview:sep];
    y += 8;
    
    // ===== ESP BOX =====
    y = [self addToggle:panel title:@"ESP BOX" y:y state:&g_espBox action:^(BOOL on) {
        g_espBox = on;
    }];
    
    // ===== HP BAR =====
    y = [self addToggle:panel title:@"HP BAR" y:y state:&g_hpBar action:^(BOOL on) {
        g_hpBar = on;
    }];
    
    // ===== ACTION STATE =====
    y = [self addToggle:panel title:@"ACTION STATE" y:y state:&g_actionState action:^(BOOL on) {
        g_actionState = on;
    }];
    
    // ===== SKILL CD =====
    y = [self addToggle:panel title:@"SKILL CD" y:y state:&g_skillCD action:^(BOOL on) {
        g_skillCD = on;
    }];
    
    // Separator
    sep = [[UIView alloc] initWithFrame:CGRectMake(8, y, w - 16, 0.5)];
    sep.backgroundColor = [UIColor grayColor];
    [panel addSubview:sep];
    y += 8;
    
    // ===== AUTO TAP =====
    y = [self addToggle:panel title:@"AUTO TAP" y:y state:&g_autoTap action:^(BOOL on) {
        g_autoTap = on;
        if (on) {
            start_auto_tap();
        } else {
            stop_auto_tap();
        }
    }];
    
    // ===== TAP SPEED SLIDER =====
    UILabel *speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, y, 100, 18)];
    speedLabel.text = @"⚡ TAP SPEED";
    speedLabel.textColor = [UIColor lightGrayColor];
    speedLabel.font = [UIFont systemFontOfSize:9];
    [panel addSubview:speedLabel];
    
    UISlider *speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(10, y + 16, w - 20, 24)];
    speedSlider.minimumValue = 0.1;
    speedSlider.maximumValue = 1.0;
    speedSlider.value = g_tapSpeed;
    speedSlider.minimumTrackTintColor = [UIColor cyanColor];
    speedSlider.continuous = YES;
    [speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:speedSlider];
    
    UILabel *speedValue = [[UILabel alloc] initWithFrame:CGRectMake(10, y + 36, w - 20, 14)];
    speedValue.text = [NSString stringWithFormat:@"%.0f%%", g_tapSpeed * 100];
    speedValue.textColor = [UIColor cyanColor];
    speedValue.font = [UIFont systemFontOfSize:8];
    speedValue.textAlignment = NSTextAlignmentCenter;
    speedValue.tag = 123;
    [panel addSubview:speedValue];
    y += 54;
    
    // Panel height
    CGRect frame = panel.frame;
    frame.size.height = y + 8;
    panel.frame = frame;
}

- (float)addToggle:(UIView*)parent title:(NSString*)title y:(float)y state:(BOOL*)state action:(void(^)(BOOL))action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, y, 120, 26)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:11];
    [parent addSubview:label];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(130, y, 0, 0)];
    sw.transform = CGAffineTransformMakeScale(0.7, 0.7);
    sw.on = *state;
    sw.onTintColor = [UIColor cyanColor];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(sw, "action", [action copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(sw, "statePtr", [NSValue valueWithPointer:state], OBJC_ASSOCIATION_ASSIGN);
    [parent addSubview:sw];
    
    return y + 32;
}

- (void)switchChanged:(UISwitch*)sw {
    NSValue *ptrVal = objc_getAssociatedObject(sw, "statePtr");
    if (ptrVal) {
        BOOL *state = [ptrVal pointerValue];
        *state = sw.isOn;
        
        void(^action)(BOOL) = objc_getAssociatedObject(sw, "action");
        if (action) action(sw.isOn);
    }
}

- (void)speedChanged:(UISlider*)slider {
    g_tapSpeed = slider.value;
    UILabel *speedValue = [panel viewWithTag:123];
    if (speedValue) {
        speedValue.text = [NSString stringWithFormat:@"%.0f%%", g_tapSpeed * 100];
    }
    
    // Restart auto tap with new speed
    if (g_autoTap) {
        stop_auto_tap();
        start_auto_tap();
    }
}

- (void)toggle {
    isOpen = !isOpen;
    
    if (isOpen) {
        panel.hidden = NO;
        panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
        panel.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{
            panel.transform = CGAffineTransformIdentity;
            panel.alpha = 1;
        }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{
            panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
            panel.alpha = 0;
        } completion:^(BOOL finished) {
            panel.hidden = YES;
            panel.transform = CGAffineTransformIdentity;
        }];
    }
}

@end

// ============================================
// FLOATING BUTTON (MINIMALIS)
// ============================================
@interface MiniFloatingButton : UIButton
@property (nonatomic, strong) MiniMenu *menu;
@end

@implementation MiniFloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:0.9];
        self.layer.cornerRadius = 20;
        self.layer.shadowColor = [UIColor cyanColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.5;
        
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)tapped {
    if (self.menu) [self.menu toggle];
}

- (void)drag:(UIPanGestureRecognizer*)pan {
    CGPoint p = [pan locationInView:self.superview];
    self.center = p;
}

@end

// ============================================
// BATTLE DETECTION
// ============================================
static void check_battle_status() {
    @try {
        if (!g_unityBase) {
            g_isInBattle = NO;
            return;
        }
        uintptr_t bmPtr = safe_read_ptr(g_unityBase + OFF_BATTLE_MANAGER);
        g_isInBattle = is_valid_address(bmPtr);
        
        if (!g_isInBattle) {
            stop_auto_tap();
        } else if (g_autoTap) {
            start_auto_tap();
        }
    } @catch (NSException *e) {
        g_isInBattle = NO;
    }
}

// ============================================
// INITIALIZATION
// ============================================
__attribute__((constructor))
static void initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_unityBase = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && strstr(name, "UnityFramework")) {
                g_unityBase = (uintptr_t)_dyld_get_image_header(i);
                break;
            }
        }
        
        if (!g_unityBase) return;
        
        UIWindow *win = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    win = scene.windows.firstObject;
                    break;
                }
            }
        }
        if (!win) win = [UIApplication sharedApplication].windows.firstObject;
        
        if (win) {
            ESPOverlay *esp = [[ESPOverlay alloc] initWithFrame:win.bounds];
            [win addSubview:esp];
            
            MiniFloatingButton *btn = [[MiniFloatingButton alloc] initWithFrame:CGRectMake(15, 120, 40, 40)];
            MiniMenu *menu = [[MiniMenu alloc] initWithFrame:CGRectMake(0, 0, 200, 0)];
            btn.menu = menu;
            [win addSubview:btn];
            [win addSubview:menu];
        }
        
        // Battle checker
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            check_battle_status();
        }];
    });
}
