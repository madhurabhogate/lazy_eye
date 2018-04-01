//
//  LazyEyeAppDelegate.m
//  LazyEye
//
//  Includes "Shady" code by Matt Gemmell.

//

#import "LazyEyeAppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "MGTransparentWindow.h"
#import "NSApplication+DockIcon.h"

#define OPACITY_UNIT                0.05; // "20 shades ought to be enough for _anybody_."
#define DEFAULT_OPACITY             0.4

#define STATE_MENU                    NSLocalizedString(@"Turn LazyEye Off", nil) // global status menu-item title when enabled
#define STATE_MENU_OFF                NSLocalizedString(@"Turn LazyEye On", nil) // global status menu-item title when disabled

#define HELP_TEXT                    NSLocalizedString(@"When LazyEye is frontmost:\rPress Up/Down to alter color,\ror press Q to Quit.", nil)
#define HELP_TEXT_OFF                NSLocalizedString(@"LazyEye is Off.\rPress S to turn LazyEye on,\ror press Q to Quit.", nil)

#define STATUS_MENU_ICON            [NSImage imageNamed:@"Lazy_Eye"]
#define STATUS_MENU_ICON_ALT        [NSImage imageNamed:@"Lazy_Eye"]
#define STATUS_MENU_ICON_OFF        [NSImage imageNamed:@"Lazy_Eye"]
#define STATUS_MENU_ICON_OFF_ALT    [NSImage imageNamed:@"Lazy_Eye"]

#define MAX_OPACITY                    0.90 // the darkest the screen can be, where 1.0 is pure black.
#define KEY_OPACITY                    @"LazyEyeSavedOpacityKey" // name of the saved opacity setting.
#define KEY_DOCKICON                   @"LazyEyeSavedDockIconKey" // name of the saved dock icon state setting.
#define KEY_ENABLED                    @"LazyEyeSavedEnabledKey" // name of the saved primary state setting.

#define H_PATTERN_SIZE 400
#define V_PATTERN_SIZE 100
#define SUBUNIT 100

@implementation LazyEyeAppDelegate

@synthesize opacity;
@synthesize statusMenu;
@synthesize opacitySlider;
@synthesize prefsWindow;
@synthesize dockIconCheckbox;
@synthesize stateMenuItemMainMenu;
@synthesize stateMenuItemStatusBar;


#pragma mark Setup and Tear-down


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Set the default opacity value and load any saved settings.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithFloat:DEFAULT_OPACITY], KEY_OPACITY,
                                [NSNumber numberWithBool:YES], KEY_DOCKICON,
                                [NSNumber numberWithBool:YES], KEY_ENABLED,
                                nil]];
    
    // Set up Dock icon.
    BOOL showsDockIcon = [defaults boolForKey:KEY_DOCKICON];
    [dockIconCheckbox setState:(showsDockIcon) ? NSOnState : NSOffState];
    if (showsDockIcon) {
        // Only set it here if it's YES, since we've just read a saved default and we always start with no Dock icon.
        [NSApp setShowsDockIcon:showsDockIcon];
    }
    
    
    // Activate statusItem.
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    statusItem = [bar statusItemWithLength:NSSquareStatusItemLength];
    [statusItem retain];
    
    NSImage* image = STATUS_MENU_ICON;
    [image setTemplate:YES];
    [statusItem setImage:image];
    
    NSImage* altImage = STATUS_MENU_ICON_ALT;
    [altImage setTemplate:YES];
    [statusItem setAlternateImage:altImage];
    [statusItem setHighlightMode:YES];
    [opacitySlider setFloatValue:(1.0 - opacity)];
    [statusItem setMenu:statusMenu];
    
    // Set appropriate initial display state.
    lazyEnabled = [defaults boolForKey:KEY_ENABLED];
    
    // Only show help text when activated _after_ we've launched and hidden ourselves.
    showsHelpWhenActive = NO;
    
    // Create transparent windows
    [self loadWindows];
    
    // Put this app into the background (the shade won't hide due to how its window is set up above).
    [NSApp hide:self];
    
}


- (void)dealloc
{
    if (statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        [statusItem release];
        statusItem = nil;
    }
    [helpWindow.parentWindow removeChildWindow:helpWindow];
    
    [helpWindow close];
    [windows makeObjectsPerformSelector:@selector(close)];
    
    windows = nil; // released when closed.
    helpWindow = nil; // released when closed.
    
    [super dealloc];
}

void myRedGreenPattern (void *info, CGContextRef myContext){
    float subunit = SUBUNIT; // the pattern cell itself is 16 by 18
    
    CGRect  myRect1 = {{0,0}, {subunit, subunit}},
    myRect2 = {{subunit, 0}, {subunit, subunit}},
    myRect3 = {{2*subunit,0}, {subunit, subunit}},
    myRect4 = {{3*subunit,0}, {subunit, subunit}};
    
    CGContextSetRGBFillColor (myContext, 1, 0, 0, 1);
    CGContextFillRect (myContext, myRect1);
    CGContextSetRGBFillColor (myContext, 1, 1, 1, 1);
    CGContextFillRect (myContext, myRect2);
    CGContextSetRGBFillColor (myContext, 10/255.0, 148/255.0, 45/255.0, 1);
    CGContextFillRect (myContext, myRect3);
    CGContextSetRGBFillColor (myContext, 1, 1, 1, 1);
    CGContextFillRect (myContext, myRect4);
}


- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)myContext
{
    CGPatternRef    pattern;
    CGColorSpaceRef patternSpace;
    CGFloat         alpha = 1;
    
    static const CGPatternCallbacks callbacks = {0, &myRedGreenPattern, NULL};
    CGContextSaveGState (myContext);
    patternSpace = CGColorSpaceCreatePattern (NULL);
    CGContextSetFillColorSpace (myContext, patternSpace);
    CGColorSpaceRelease (patternSpace);
    
    pattern = CGPatternCreate (NULL,
                               layer.bounds,
                               CGAffineTransformMake (1, 0, 0, 1, 0, 0),
                               H_PATTERN_SIZE,
                               V_PATTERN_SIZE,
                               kCGPatternTilingConstantSpacing,
                               true,
                               &callbacks);
    
    CGContextSetFillPattern (myContext, pattern, &alpha);
    CGPatternRelease (pattern);
    CGContextFillRect (myContext, layer.bounds);
    CGContextRestoreGState (myContext);
}


- (void)loadWindows
{
    NSMutableArray* array = [[NSMutableArray alloc] init];
    for( NSScreen* screen in [NSScreen screens] )
    {
        MGTransparentWindow* window;
        window = [[MGTransparentWindow windowWithFrame:screen.frame] retain];
        
        // Configure window.
        [window setReleasedWhenClosed:YES];
        [window setHidesOnDeactivate:NO];
        [window setCanHide:NO];
        if( NSFoundationVersionNumber10_6 <= NSFoundationVersionNumber )
            [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];
        else
            [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        [window setIgnoresMouseEvents:YES];
        [window setLevel:NSScreenSaverWindowLevel];
        [window setDelegate:self];
        
        //my changes
        NSView *contentView = [window contentView];
        [contentView setWantsLayer:YES];
        CALayer *layer = [contentView layer];
        layer.backgroundColor = [NSColor clearColor].CGColor;
        
        // screen variables
        CGFloat width = CGRectGetWidth(screen.frame);
        CGFloat height = CGRectGetWidth(screen.frame);
        
        //red green layer
        CALayer *redGreenColorLayer = [CALayer layer];
        redGreenColorLayer.delegate = self;
        redGreenColorLayer.frame = CGRectMake(0 ,0, width, height);
        [layer addSublayer:redGreenColorLayer];
        [redGreenColorLayer setNeedsDisplay];
        
        [window makeFirstResponder:contentView];
        [array addObject: window];
    }
    
    [windows release];
    windows = array;
    
    [self updateEnabledStatus];
    self.opacity = [[NSUserDefaults standardUserDefaults] floatForKey:KEY_OPACITY];
    
    // Put window on screen.
    [windows makeObjectsPerformSelector:@selector(makeKeyAndOrderFront:) withObject:self];
    
}

#pragma mark Notifications handlers


- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    [self applicationActiveStateChanged:aNotification];
}


- (void)applicationDidResignActive:(NSNotification *)aNotification
{
    [self applicationActiveStateChanged:aNotification];
}


- (void)applicationActiveStateChanged:(NSNotification *)aNotification
{
    BOOL appActive = [NSApp isActive];
    if (appActive) {
        // Give the window a kick into focus, so we still get key-presses.
        [windows makeObjectsPerformSelector:@selector(makeKeyAndOrderFront:) withObject:self];
    }
    
    if (!showsHelpWhenActive && !appActive) {
        // Enable help text display when active from now on.
        showsHelpWhenActive = YES;
        
    } else if (showsHelpWhenActive) {
        [self toggleHelpDisplay];
    }
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification
{
    [windows[0] removeChildWindow:helpWindow];
    
    [helpWindow close];
    [windows makeObjectsPerformSelector:@selector(close)];
    
    [windows release];
    windows = nil; // released when closed.
    helpWindow = nil; // released when closed.
    
    
    [self loadWindows];
}

#pragma mark IBActions


- (IBAction)showAbout:(id)sender
{
    // We wrap this for the statusItem to ensure LazyEye comes to the front first.
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:self];
}


- (IBAction)showPreferences:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [prefsWindow makeKeyAndOrderFront:self];
}


- (IBAction)increaseOpacity:(id)sender
{
    // i.e. make screen darker by making our mask less transparent.
    if (lazyEnabled) {
        self.opacity = opacity + OPACITY_UNIT;
    } else {
        NSBeep();
    }
}


- (IBAction)decreaseOpacity:(id)sender
{
    // i.e. make screen lighter by making our mask more transparent.
    if (lazyEnabled) {
        self.opacity = opacity - OPACITY_UNIT;
    } else {
        NSBeep();
    }
}


- (IBAction)opacitySliderChanged:(id)sender
{
    self.opacity = (1.0 - [sender floatValue]);
}


- (IBAction)toggleDockIcon:(id)sender
{
    BOOL showsDockIcon = ([sender state] != NSOffState);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:showsDockIcon forKey:KEY_DOCKICON];
    [defaults synchronize];
    [NSApp setShowsDockIcon:showsDockIcon];
}


- (IBAction)toggleEnabledStatus:(id)sender
{
    lazyEnabled = !lazyEnabled;
    [self updateEnabledStatus];
}


- (void)keyDown:(NSEvent *)event
{
    if ( [windows containsObject:[event window]]) {
        unsigned short keyCode = [event keyCode];
        if (keyCode == 12 || keyCode == 53) { // q || Esc
            [NSApp terminate:self];
            
        } else if (keyCode == 126) { // up-arrow
            [self decreaseOpacity:self];
            
        } else if (keyCode == 125) { // down-arrow
            [self increaseOpacity:self];
            
        } else if (keyCode == 1) { // s
            [self toggleEnabledStatus:self];
            
        } else if (keyCode == 43) { // ,
            [self showPreferences:self];
            
        } else {
            //NSLog(@"keyCode: %d", keyCode);
        }
    }
}


#pragma mark Helper methods


- (void)toggleHelpDisplay
{
    if( windows.count == 0 )    return; // Unknown error
    
    if (!helpWindow) {
        // Create helpWindow.
        NSRect mainFrame = [windows[0] frame];
        NSRect helpFrame = NSZeroRect;
        float width = 600;
        float height = 200;
        helpFrame.origin.x = (mainFrame.size.width - width) / 2.0;
        helpFrame.origin.y = 200.0;
        helpFrame.size.width = width;
        helpFrame.size.height = height;
        helpWindow = [[MGTransparentWindow windowWithFrame:helpFrame] retain];
        
        // Configure window.
        [helpWindow setReleasedWhenClosed:YES];
        [helpWindow setHidesOnDeactivate:NO];
        [helpWindow setCanHide:NO];
        [helpWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        [helpWindow setIgnoresMouseEvents:YES];
        
        // Configure contentView.
        NSView *contentView = [helpWindow contentView];
        [contentView setWantsLayer:YES];
        CATextLayer *layer = [CATextLayer layer];
        layer.opacity = 0;
        [contentView setLayer:layer];
        CGColorRef bgColor = CGColorCreateGenericGray(0.0, 0.6);
        layer.backgroundColor = bgColor;
        CGColorRelease(bgColor);
        layer.string = (lazyEnabled) ? HELP_TEXT : HELP_TEXT_OFF;
        layer.contentsRect = CGRectMake(0, 0, 1, 1.2);
        layer.fontSize = 40.0;
        layer.foregroundColor = CGColorGetConstantColor(kCGColorWhite);
        layer.borderColor = CGColorGetConstantColor(kCGColorWhite);
        layer.borderWidth = 4.0;
        layer.cornerRadius = 15.0;
        layer.alignmentMode = kCAAlignmentCenter;
        
        [windows[0] addChildWindow:helpWindow ordered:NSWindowAbove];
    }
    
    if (showsHelpWhenActive) {
        float helpOpacity = (([NSApp isActive] ? 1 : 0));
        [[[helpWindow contentView] layer] setOpacity:helpOpacity];
    }
}


- (void)updateEnabledStatus
{
    // Save state.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:lazyEnabled forKey:KEY_ENABLED];
    [defaults synchronize];
    
    // Show or hide the shade layer's view appropriately.
    for( NSWindow* window in windows )
        [[[window contentView] animator] setHidden:!lazyEnabled];
    
    // Modify help text shown when we're frontmost.
    if (helpWindow) {
        CATextLayer *helpLayer = (CATextLayer *)[[helpWindow contentView] layer];
        helpLayer.string = (lazyEnabled) ? HELP_TEXT : HELP_TEXT_OFF;
    }
    
    // Update both enable/disable menu-items (in the main menubar and in the NSStatusItem's menu).
    [stateMenuItemMainMenu setTitle:(lazyEnabled) ? STATE_MENU : STATE_MENU_OFF];
    [stateMenuItemStatusBar setTitle:(lazyEnabled) ? STATE_MENU : STATE_MENU_OFF];
    
    // Update status item's regular and alt/selected images.
    
    NSImage* image = (lazyEnabled) ? STATUS_MENU_ICON : STATUS_MENU_ICON_OFF;
    [image setTemplate:YES];
    
    NSImage* altImage = (lazyEnabled) ? STATUS_MENU_ICON_ALT : STATUS_MENU_ICON_OFF_ALT;
    [altImage setTemplate:YES];
    
    
    [statusItem setImage:image];
    [statusItem setAlternateImage:altImage];
    
    // Enable/disable slider.
    [opacitySlider setEnabled:lazyEnabled];
}


#pragma mark Accessors


- (void)setOpacity:(float)newOpacity
{
    float normalisedOpacity = MIN(MAX_OPACITY, MAX(newOpacity, 0.0));
    if (normalisedOpacity != opacity) {
        opacity = normalisedOpacity;
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setFloat:opacity forKey:KEY_OPACITY];
        [defaults synchronize];
        
    }
    
    for( NSWindow* window in windows )
        [[[window contentView] layer] setOpacity:opacity];
    
    [opacitySlider setFloatValue:(1.0 - opacity)];
    
}

-(float)opacity
{
    return opacity;
}


@end

