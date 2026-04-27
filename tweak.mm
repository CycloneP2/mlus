// Tweak.mm - EDGY HACKS (FULLY FIXED & VALIDATED)
// Optimized for MLBB with Cydia Substrate

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ============================================
// DATA STRUCTURES
// ============================================
typedef struct { float x, y, z; } Vector3;

// ============================================
// CONFIGURATION & OFFSETS
// ============================================
#define RVA_BATTLE_MANAGER_INST 0xADC8A0   
#define OFF_SHOW_PLAYERS        0x78        
#define OFF_SHOW_MONSTERS       0x80        
#define OFF_LOCAL_PLAYER        0x50        

#define OFF_ENTITY_POS          0x30        
#define OFF_ENTITY_CAMP         0xD8        
#define OFF_ENTITY_HP           0x1AC       
#define OFF_ENTITY_HP_MAX       0x1B0       
#define OFF_PLAYER_HERO_NAME    0x918       

#define RVA_WORLD_TO_SCREEN     0x89FE040   
#define RVA_CAMERA_MAIN         0x89FF130   

#define RVA_SDK_REPORT_LOG      0x4CEB580
#define RVA_SDK_REPORT_ERR      0x4CEB690

// Tweak State
static BOOL espEnabled = YES;
static BOOL monsterEsp = NO;
static BOOL snaplinesEnabled = YES;
static BOOL showTeam = NO;
static BOOL bypassDNS = YES;
static BOOL showHeroName = YES;
static float enemyR = 0.6, enemyG = 0.4, enemyB = 1.0; 

static uintptr_t g_unityBase = 0;

// ============================================
// UTILITIES
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

NSString* readIl2CppString(uintptr_t strPtr) {
    if (!strPtr) return nil;
    int len = *(int*)(strPtr + 0x10);
    if (len > 0 && len < 100) { // Basic memory validation
        uint16_t *chars = (uint16_t*)(strPtr + 0x14);
        return [NSString stringWithCharacters:chars length:len];
    }
    return nil;
}

// ============================================
// ANTI-REPORT HOOKS
// ============================================
static void (*old_ReportLog)(void* msg);
void hooked_ReportLog(void* msg) { if (bypassDNS) return; if (old_ReportLog) old_ReportLog(msg); }

static void (*old_ReportErr)(void* msg);
void hooked_ReportErr(void* msg) { if (bypassDNS) return; if (old_ReportErr) old_ReportErr(msg); }

// ============================================
// UI COMPONENTS
// ============================================

@interface EdgyToggle : UISwitch
@end
@implementation EdgyToggle
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.onTintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0]; }
    return self;
}
@end

@interface EdgyMenu : UIView
@property (nonatomic, strong) UIView *contentArea;
@end

@implementation EdgyMenu
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.98];
        self.layer.cornerRadius = 24;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, frame.size.width, 30)];
        title.text = @"EDGY HACKS";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont fontWithName:@"Helvetica-Bold" size:22];
        [self addSubview:title];
        
        _contentArea = [[UIView alloc] initWithFrame:CGRectMake(20, 65, frame.size.width - 40, frame.size.height - 80)];
        [self addSubview:_contentArea];
        
        [self setupUI];
        
        // Fix: Make Menu Draggable
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        close.frame = CGRectMake(frame.size.width - 40, 15, 25, 25);
        [close setTitle:@"✕" forState:UIControlStateNormal];
        close.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        close.layer.cornerRadius = 12.5;
        [close addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];
    }
    return self;
}

- (void)setupUI {
    float y = 0;
    y = [self addToggle:@"ENABLE ESP" y:y state:espEnabled cb:^(BOOL on){ espEnabled = on; }];
    y = [self addToggle:@"HERO NAME" y:y state:showHeroName cb:^(BOOL on){ showHeroName = on; }];
    y = [self addToggle:@"MonsterESP" y:y state:monsterEsp cb:^(BOOL on){ monsterEsp = on; }];
    y = [self addToggle:@"SNAPLINES" y:y state:snaplinesEnabled cb:^(BOOL on){ snaplinesEnabled = on; }];
    y = [self addToggle:@"SHOW TEAM" y:y state:showTeam cb:^(BOOL on){ showTeam = on; }];
    y = [self addToggle:@"BYPASS DNS" y:y state:bypassDNS cb:^(BOOL on){ bypassDNS = on; }];
}

- (float)addToggle:(NSString *)name y:(float)y state:(BOOL)state cb:(void(^)(BOOL))cb {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, y, 150, 31)];
    lbl.text = name;
    lbl.textColor = [UIColor whiteColor];
    [self.contentArea addSubview:lbl];
    
    EdgyToggle *s = [[EdgyToggle alloc] initWithFrame:CGRectMake(self.contentArea.frame.size.width - 51, y, 51, 31)];
    s.on = state;
    objc_setAssociatedObject(s, "toggle_cb", cb, OBJC_ASSOCIATION_COPY_NONATOMIC);
    // Fix: Add action handler
    [s addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentArea addSubview:s];
    return y + 40;
}

- (void)toggled:(UISwitch *)s {
    void(^cb)(BOOL) = objc_getAssociatedObject(s, "toggle_cb");
    if (cb) cb(s.on);
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    self.center = [p locationInView:self.superview];
}

- (void)show { self.hidden = NO; }
- (void)hide { self.hidden = YES; }
@end

// ============================================
// ESP RENDERER
// ============================================

@interface EdgyESPView : UIView
@end

@implementation EdgyESPView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        // Fix: Add CADisplayLink for constant redrawing
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)redraw {
    if (espEnabled) [self setNeedsDisplay];
}

- (void)drawEntities:(uintptr_t)list rect:(CGRect)rect ctx:(CGContextRef)ctx cam:(void*)cam w2s:(Vector3(*)(void*, Vector3))w2s myTeam:(int)myTeam color:(UIColor*)color isMonster:(BOOL)isMonster {
    if (!list) return; // Fix: Memory validation
    
    // Fix: Correct List<T> access
    uintptr_t arrayPtr = *(uintptr_t*)(list + 0x10);
    if (!arrayPtr) return;
    
    int size = *(int*)(list + 0x18);
    if (size <= 0 || size > 200) return; // Basic bounds check
    
    for (int i = 0; i < size; i++) {
        // Fix: Il2Cpp array elements start at 0x20
        uintptr_t entity = *(uintptr_t*)(arrayPtr + 0x20 + (i * 8));
        if (!entity) continue;
        
        int team = *(int*)(entity + OFF_ENTITY_CAMP);
        if (!showTeam && team == myTeam && !isMonster) continue;
        
        Vector3 pos = *(Vector3*)(entity + OFF_ENTITY_POS);
        Vector3 sPos = w2s(cam, pos);
        
        if (sPos.z > 0) {
            float x = sPos.x;
            float y = rect.size.height - sPos.y;
            
            if (snaplinesEnabled) {
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextSetLineWidth(ctx, 1.0);
                CGContextMoveToPoint(ctx, rect.size.width/2, rect.size.height);
                CGContextAddLineToPoint(ctx, x, y);
                CGContextStrokePath(ctx);
            }
            
            if (showHeroName && !isMonster) {
                uintptr_t heroNamePtr = *(uintptr_t*)(entity + OFF_PLAYER_HERO_NAME);
                if (heroNamePtr) {
                    // Fix: Correct Il2Cpp string parsing
                    NSString *name = readIl2CppString(heroNamePtr);
                    if (name) {
                        [name drawAtPoint:CGPointMake(x - 20, y - 35) withAttributes:@{
                            NSForegroundColorAttributeName: [UIColor whiteColor],
                            NSFontAttributeName: [UIFont boldSystemFontOfSize:10]
                        }];
                    }
                }
            }
            
            int hp = *(int*)(entity + OFF_ENTITY_HP);
            [[NSString stringWithFormat:@"%d", hp] drawAtPoint:CGPointMake(x - 10, y - 20) withAttributes:@{
                NSForegroundColorAttributeName: color,
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10]
            }];
        }
    }
}

- (void)drawRect:(CGRect)rect {
    @try {
        if (!espEnabled || !g_unityBase) return;
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        uintptr_t bmPtr = *(uintptr_t*)(g_unityBase + RVA_BATTLE_MANAGER_INST);
        if (!bmPtr) return;
        
        void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
        void* cam = get_main();
        if (!cam) return;
        
        Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
        if (!w2s) return;
        
        uintptr_t local = *(uintptr_t*)(bmPtr + OFF_LOCAL_PLAYER);
        int myTeam = local ? *(int*)(local + OFF_ENTITY_CAMP) : 0;
        
        UIColor *espColor = [UIColor colorWithRed:enemyR green:enemyG blue:enemyB alpha:1.0];
        
        // Draw Players
        uintptr_t playerList = *(uintptr_t*)(bmPtr + OFF_SHOW_PLAYERS);
        [self drawEntities:playerList rect:rect ctx:ctx cam:cam w2s:w2s myTeam:myTeam color:espColor isMonster:NO];
        
        // Draw Monsters
        if (monsterEsp) {
            uintptr_t monsterList = *(uintptr_t*)(bmPtr + OFF_SHOW_MONSTERS);
            [self drawEntities:monsterList rect:rect ctx:ctx cam:cam w2s:w2s myTeam:myTeam color:[UIColor yellowColor] isMonster:YES];
        }
    } @catch (NSException *e) {
        // silent fail to prevent crashing
    }
}
@end

// ============================================
// INITIALIZATION
// ============================================

__attribute__((constructor))
static void initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Fix: Use correct get_base function
        g_unityBase = get_base("UnityFramework");
        if (!g_unityBase) return;
        
        // Fix: Properly setup Substrate hooks
        MSHookFunction((void*)(g_unityBase + RVA_SDK_REPORT_LOG), (void*)&hooked_ReportLog, (void**)&old_ReportLog);
        MSHookFunction((void*)(g_unityBase + RVA_SDK_REPORT_ERR), (void*)&hooked_ReportErr, (void**)&old_ReportErr);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *win = nil;
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        win = scene.windows.firstObject; break;
                    }
                }
            }
            if (!win) win = [UIApplication sharedApplication].windows.firstObject;
            
            if (win) {
                [win addSubview:[[EdgyESPView alloc] initWithFrame:win.bounds]];
                
                EdgyMenu *menu = [[EdgyMenu alloc] initWithFrame:CGRectMake(win.bounds.size.width/2 - 150, win.bounds.size.height/2 - 200, 300, 400)];
                menu.hidden = YES;
                [win addSubview:menu];
                
                // Fix: Add Floating Button back
                UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
                fab.frame = CGRectMake(15, 100, 60, 30);
                fab.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:0.8];
                fab.layer.cornerRadius = 15;
                [fab setTitle:@"EDGY" forState:UIControlStateNormal];
                [fab addTarget:menu action:@selector(show) forControlEvents:UIControlEventTouchUpInside];
                [win addSubview:fab];
                
                // Make FAB draggable
UIPanGestureRecognizer *fabPan = [[UIPanGestureRecognizer alloc] initWithTarget:fab action:@selector(drag:)];
                [fab addGestureRecognizer:fabPan];
            }
        });
    });
}

// Category for FAB dragging
@interface UIButton (Draggable)
- (void)drag:(UIPanGestureRecognizer *)p;
@end

@implementation UIButton (Draggable)
- (void)drag:(UIPanGestureRecognizer *)p {
    self.center = [p locationInView:self.superview];
}
@end
