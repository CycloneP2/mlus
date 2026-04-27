// Tweak.mm - MLBB MOD STANDALONE (PRO EDITION)
// UPDATED WITH DUMP.CS OFFSETS & SECURITY FEATURES
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

// PROMPT 1: ESP / WALLHACK
#define OFF_BATTLE_MANAGER_INST 0xADC8A0   // Static Field
#define OFF_SHOW_PLAYERS        0x78        // List<ShowEntity>
#define OFF_LOCAL_PLAYER        0x50        // ShowPlayer
#define OFF_ENTITY_POS          0x30        // Vector3 (m_vPosition)
#define OFF_ENTITY_CAMP         0xD8        // int (m_EntityCampType)
#define OFF_ENTITY_HP           0x1AC       // int (m_Hp)
#define OFF_ENTITY_HP_MAX       0x1B0       // int (m_HpMax)
#define OFF_ENTITY_STATE        0x428       // EntityStates (m_States)
#define OFF_PLAYER_HERO_NAME    0x918       // UnityString (m_HeroName)
#define OFF_PLAYER_RANK         0x954       // uint (m_uiRankLevel)
#define OFF_SUMMON_SKILL        0x9A4       // int (m_iSummonSkillId)
#define RVA_WORLD_TO_SCREEN     0x89FE040   // Camera.WorldToScreenPoint
#define RVA_CAMERA_MAIN         0x89FF130   // Camera.get_main

// PROMPT 2: SKILL / COMBAT
#define OFF_SKILL_LIST          0x48        // List<OwnSkillData> (m_NormalSkill)
#define RVA_GET_CUR_CD          0x67BD63C   // ShowCoolDownComp.GetCurCD
#define OFF_OWN_SKILL_COMP      0x110       // ShowOwnSkillComp
#define OFF_CD_COMP             0x100       // ShowCoolDownComp
#define OFF_SKILL_CD_TIME       0x60        // uint (m_startStageTime)
#define OFF_SKILL_ID            0x10        // int (m_iSpellID)

// PROMPT 3: DAMAGE & ATTACK
#define OFF_ATTACK_DIST         0x338       // float (m_AtkDis)
#define RVA_TAKE_DAMAGE         0x530508C   // OnOwnerTakeDamage
#define RVA_DEAL_DAMAGE         0x5304EAC   // OnOwnerDealDamage

// PROMPT 4: ANTI-CHEAT & SECURITY
#define RVA_IS_TUTORIAL         0x51666C8   // IsTutorialBattle
#define RVA_IS_DEBUG            0x8A06220   // get_isDebugBuild
#define OFF_REPORT_ENABLED      0x1053889   // m_isReportEnabled (Static)

// Existing legacy offsets
#define OFF_DRONE_SET_FOV       0x89FB2B8
#define OFF_RADAR_VISIBLE       0x5023FF0

// ============================================
// SECURITY & UTILITY
// ============================================

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
static MSHookFunction_t MSHookFunction_ptr = NULL;
static uintptr_t g_unityBase = 0;
static BOOL g_safeMode = NO;

BOOL validate_offset(uintptr_t base, uintptr_t offset, const char* name) {
    uintptr_t addr = base + offset;
    vm_size_t size = 0;
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT;
    mach_port_t object;
    kern_return_t kr = vm_region(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &count, &object);
    if (kr != KERN_SUCCESS) {
        LOG(@"[ERROR] Offset %s (0x%lx) invalid!", name, offset);
        return NO;
    }
    return YES;
}

bool patch_memory(uintptr_t address, const void* data, size_t size) {
    kern_return_t kr;
    mach_port_t self = mach_task_self();
    kr = vm_protect(self, (vm_address_t)address, size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return false;
    kr = vm_write(self, (vm_address_t)address, (vm_offset_t)data, (mach_msg_type_number_t)size);
    if (kr != KERN_SUCCESS) {
        memcpy((void*)address, data, size);
    }
    vm_protect(self, (vm_address_t)address, size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return true;
}

void safe_hook(uintptr_t address, void* new_func, void** old_func) {
    @try {
        if (address > 0x100000 && address < 0x200000000) {
            if (MSHookFunction_ptr) {
                MSHookFunction_ptr((void*)address, new_func, old_func);
                LOG(@"Hooked successfully: 0x%lx", address);
            } else {
                LOG(@"Hook failed: MSHookFunction not found");
            }
        } else {
            LOG(@"Invalid address for hook: 0x%lx", address);
        }
    } @catch (NSException *e) {
        LOG(@"Hook exception: %@", e.reason);
    }
}

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
static float damageMulti = 1.0;

// ============================================
// HOOKED FUNCTIONS
// ============================================

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

static bool (*original_IsTutorialBattle)() = NULL;
static bool hooked_IsTutorialBattle() {
    if (skipTutorialEnabled) return false;
    return original_IsTutorialBattle ? original_IsTutorialBattle() : true;
}

static bool (*original_isDebugBuild)() = NULL;
static bool hooked_isDebugBuild() {
    if (g_safeMode) return false;
    return original_isDebugBuild ? original_isDebugBuild() : true;
}

// ============================================
// UI & OVERLAY
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

- (void)redraw { 
    if (espEnabled) [self setNeedsDisplay]; 
}

- (void)drawRect:(CGRect)rect {
    if (!espEnabled || !g_unityBase) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.5);
    
    // Get BattleManager Instance
    uintptr_t bmPtr = *(uintptr_t*)(g_unityBase + OFF_BATTLE_MANAGER_INST);
    if (!bmPtr) return;
    
    // Get ShowPlayers list
    uintptr_t playerList = *(uintptr_t*)(bmPtr + OFF_SHOW_PLAYERS);
    if (!playerList) return;
    
    void* items = *(void**)(playerList + 0x10);
    int size = *(int*)(playerList + 0x18);
    if (!items || size <= 0) return;
    
    // Get Camera
    void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
    void* mainCam = get_main();
    if (!mainCam) return;
    
    // World to Screen function
    Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
    
    // Get local player team
    uintptr_t localPlayer = *(uintptr_t*)(bmPtr + OFF_LOCAL_PLAYER);
    int myTeam = localPlayer ? *(int*)(localPlayer + OFF_ENTITY_CAMP) : 0;
    
    for (int i = 0; i < size; i++) {
        uintptr_t player = *(uintptr_t*)((uintptr_t)items + 0x20 + (i * 8));
        if (!player) continue;
        
        // Get position
        Vector3 pos = *(Vector3*)(player + OFF_ENTITY_POS);
        Vector3 screenPos = w2s(mainCam, pos);
        
        if (screenPos.z > 0) {
            int team = *(int*)(player + OFF_ENTITY_CAMP);
            
            // Skip teammates if not map hack
            if (team == myTeam && !radarEnabled) continue;
            
            float scale = [UIScreen mainScreen].scale;
            float x = screenPos.x / scale;
            float y = rect.size.height - (screenPos.y / scale);
            
            float boxWidth = (500.0f / screenPos.z) / scale;
            float boxHeight = boxWidth * 1.3f;
            
            // Choose color
            UIColor *color = (team == myTeam) ? [UIColor greenColor] : [UIColor redColor];
            
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
            
            // HP Bar
            int hp = *(int*)(player + OFF_ENTITY_HP);
            int maxHp = *(int*)(player + OFF_ENTITY_HP_MAX);
            float percent = (float)hp / (float)maxHp;
            
            CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
            CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth, 3));
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth * percent, 3));
        }
    }
}

- (void)dealloc {
    [self.displayLink invalidate];
}

@end

@interface CustomToggle : UIView
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, copy) void (^onToggle)(BOOL isOn);
- (void)animateToState:(BOOL)isOn;
@end

@implementation CustomToggle {
    UIView *trackView;
    UIView *thumbView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        // Track
        trackView = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height/2 - 12, frame.size.width, 24)];
        trackView.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        trackView.layer.cornerRadius = 12;
        trackView.clipsToBounds = YES;
        [self addSubview:trackView];
        
        // Thumb
        thumbView = [[UIView alloc] initWithFrame:CGRectMake(2, frame.size.height/2 - 10, 20, 20)];
        thumbView.backgroundColor = [UIColor whiteColor];
        thumbView.layer.cornerRadius = 10;
        thumbView.layer.shadowColor = [UIColor blackColor].CGColor;
        thumbView.layer.shadowOffset = CGSizeMake(0, 2);
        thumbView.layer.shadowRadius = 3;
        thumbView.layer.shadowOpacity = 0.3;
        [self addSubview:thumbView];
        
        // Tap gesture
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
    
    // Slide down animation
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        toast.frame = CGRectMake(20, 80, view.bounds.size.width - 40, 50);
    } completion:^(BOOL finished) {
        // Auto hide after 2 seconds
        [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{
            toast.alpha = 0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    }];
}
@end

@interface ModernMenu : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *contentView;
- (void)showWithAnimation;
- (void)hideWithAnimation;
@end

@implementation ModernMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Glassmorphism Background
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        self.blurView.frame = self.bounds;
        self.blurView.layer.cornerRadius = 20;
        self.blurView.clipsToBounds = YES;
        [self addSubview:self.blurView];
        
        // Gradient border
        CAGradientLayer *borderLayer = [CAGradientLayer layer];
        borderLayer.frame = self.bounds;
        borderLayer.colors = @[(id)[UIColor cyanColor].CGColor, (id)[UIColor purpleColor].CGColor];
        borderLayer.startPoint = CGPointMake(0, 0);
        borderLayer.endPoint = CGPointMake(1, 1);
        borderLayer.cornerRadius = 20;
        [self.layer insertSublayer:borderLayer atIndex:0];

        // Content
        self.contentView = [[UIView alloc] initWithFrame:self.bounds];
        self.contentView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
        self.contentView.layer.cornerRadius = 20;
        self.contentView.clipsToBounds = YES;
        [self.blurView.contentView addSubview:self.contentView];
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Title dengan gradient
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, 0, self.bounds.size.width, 50);
    gradient.colors = @[(id)[UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor,
                         (id)[UIColor colorWithRed:0.5 green:0.0 blue:1.0 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 0);
    [self.contentView.layer addSublayer:gradient];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 30)];
    title.text = @"pH-1 PRO";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont fontWithName:@"AvenirNext-Bold" size:20];
    [self.contentView addSubview:title];
    
    // Animated indicator dot
    UIView *statusDot = [[UIView alloc] initWithFrame:CGRectMake(self.bounds.size.width - 30, 20, 10, 10)];
    statusDot.backgroundColor = [UIColor greenColor];
    statusDot.layer.cornerRadius = 5;
    statusDot.alpha = 0.8;
    [self.contentView addSubview:statusDot];
    
    // Pulsing animation
    [UIView animateWithDuration:1.0 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
        statusDot.alpha = 0.3;
    } completion:nil];
    
    // Add Toggles dengan __weak
    __weak typeof(self) weakSelf = self;
    
    float y = 70;
    y = [self addMenuToggle:@"Safe Mode" y:y state:g_safeMode action:^(BOOL isOn) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        g_safeMode = isOn;
        [AnimatedToast showMessage:isOn ? @"Safe Mode ON" : @"Safe Mode OFF" inView:strongSelf.superview];
    }];
    y = [self addMenuToggle:@"Enable ESP" y:y state:espEnabled action:^(BOOL isOn) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        espEnabled = isOn;
        [AnimatedToast showMessage:isOn ? @"ESP Enabled" : @"ESP Disabled" inView:strongSelf.superview];
    }];
    y = [self addMenuToggle:@"Drone View" y:y state:droneEnabled action:^(BOOL isOn) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        droneEnabled = isOn;
        [AnimatedToast showMessage:isOn ? @"Drone View ON" : @"Drone View OFF" inView:strongSelf.superview];
    }];
    y = [self addMenuToggle:@"Skip Tutorial" y:y state:skipTutorialEnabled action:^(BOOL isOn) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        skipTutorialEnabled = isOn;
        [AnimatedToast showMessage:isOn ? @"Skip Tutorial ON" : @"Skip Tutorial OFF" inView:strongSelf.superview];
    }];

    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, self.bounds.size.height - 50, self.bounds.size.width - 40, 40);
    closeBtn.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
    [closeBtn setTitle:@"CLOSE" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn addTarget:self action:@selector(hideWithAnimation) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];
}

- (float)addMenuToggle:(NSString *)title y:(float)y state:(BOOL)state action:(void (^)(BOOL))action {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 150, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.contentView addSubview:lbl];
    
    CustomToggle *toggle = [[CustomToggle alloc] initWithFrame:CGRectMake(self.bounds.size.width - 70, y, 50, 30)];
    toggle.isOn = state;
    [toggle animateToState:state];
    toggle.onToggle = action;
    [self.contentView addSubview:toggle];
    
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
        self.layer.shadowColor = [UIColor cyanColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 12;
        self.layer.shadowOpacity = 0.5;
        
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];
        
        // Rotate animation on tap
        [self addTarget:self action:@selector(animateTap) forControlEvents:UIControlEventTouchUpInside];
        
        // Drag
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
    // Rotate animation
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        self.transform = CGAffineTransformRotate(self.transform, M_PI / 4);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    }];
    
    // Pulse animation
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
// INITIALIZATION
// ============================================
__attribute__((constructor))
static void initialize() {
    LOG(@"Initializing Anti-cheat Bypass & Hooks...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_unityBase = get_base("UnityFramework");
        if (g_unityBase == 0) {
            LOG(@"[FATAL] UnityFramework not found!");
            return;
        }
        
        NSString *version = get_game_version();
        LOG(@"Game Version Detected: %@", version);
        
        MSHookFunction_ptr = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
        
        // Validation & Hooking
        if (validate_offset(g_unityBase, RVA_IS_TUTORIAL, "IsTutorial")) {
            safe_hook(g_unityBase + RVA_IS_TUTORIAL, (void*)&hooked_IsTutorialBattle, (void**)&original_IsTutorialBattle);
        }
        
        if (validate_offset(g_unityBase, RVA_IS_DEBUG, "IsDebug")) {
            safe_hook(g_unityBase + RVA_IS_DEBUG, (void*)&hooked_isDebugBuild, (void**)&original_isDebugBuild);
        }
        
        if (validate_offset(g_unityBase, OFF_DRONE_SET_FOV, "DroneFOV")) {
            safe_hook(g_unityBase + OFF_DRONE_SET_FOV, (void*)&hooked_set_fieldOfView, (void**)&old_set_fieldOfView);
        }
        
        if (validate_offset(g_unityBase, OFF_RADAR_VISIBLE, "RadarHack")) {
            safe_hook(g_unityBase + OFF_RADAR_VISIBLE, (void*)&hooked_SetVisible, (void**)&old_SetVisible);
        }

        // Fallback Patching
        if (!MSHookFunction_ptr) {
            LOG(@"Using Fallback Memory Patching...");
            uint32_t patch_false[] = { 0x52800000, 0xD65F03C0 }; // mov w0, #0; ret
            patch_memory(g_unityBase + RVA_IS_TUTORIAL, patch_false, 8);
            patch_memory(g_unityBase + RVA_IS_DEBUG, patch_false, 8);
        }

        LOG(@"Mod menu loading in main queue...");
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
            if (!win) win = [[UIApplication sharedApplication] windows].firstObject;
            
            if (win) {
                ESPOverlay *overlay = [[ESPOverlay alloc] initWithFrame:win.bounds];
                [win addSubview:overlay];
                
                ModernMenu *menu = [[ModernMenu alloc] initWithFrame:CGRectMake(win.bounds.size.width/2 - 150, win.bounds.size.height/2 - 160, 300, 320)];
                menu.hidden = YES;
                [win addSubview:menu];
                
                FloatingButton *fab = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 100, 50, 50)];
                fab.menuView = menu;
                [win addSubview:fab];
            }
        });
        
        LOG(@"[OK] All systems initialized!");
    });
}
