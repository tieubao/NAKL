/*******************************************************************************
 * Copyright (c) 2012 Huy Phan <dachuy@gmail.com>
 * This file is part of NAKL project.
 *
 * NAKL is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * NAKL is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NAKL.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

#import <Security/Security.h>
#import "AppDelegate.h"

@implementation AppDelegate

@synthesize window = _window;
@synthesize preferencesController;
@synthesize eventTap;

uint64_t controlKeys = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskHelp;

static char *separators[] = {
    "",                                     // VKM_OFF
    "!@#$%&)|\\-{}[]:\";<>,/'`~?.^*(+=",    // VKM_VNI
    "!@#$%&)|\\-:\";<>,/'`~?.^*(+="         // VKM_TELEX
};

KeyboardHandler *kbHandler;

static char rk = 0;
bool dirty;

#pragma mark Initialization

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *appDefs = [NSMutableDictionary dictionary];
    [appDefs setObject:[NSNumber numberWithInt:1] forKey:NAKL_KEYBOARD_METHOD];
    [defaults registerDefaults:appDefs];

    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @NO});

    if (!accessibilityEnabled) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"NAKL";
        alert.informativeText =
            @"NAKL không thể hoạt động nếu chưa được cấp quyền điều khiển bàn phím. "
            @"Bạn cần phải kích hoạt bằng cách mở System Settings > Privacy & Security > "
            @"Accessibility và đánh dấu vào NAKL.\n\n"
            @"Sau khi kích hoạt, bạn cần phải tắt và mở lại NAKL.";
        [alert runModal];

        [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    }
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    preferencesController = [[PreferencesController alloc] init];
    
    [AppData loadUserPrefs];
    [AppData loadHotKeys];
    [AppData loadShortcuts];
    [AppData loadExcludedApps];
    
    int method = (int)[[AppData sharedAppData].userPrefs integerForKey:NAKL_KEYBOARD_METHOD];
    for (id object in [statusMenu itemArray]) {
        [(NSMenuItem*) object setState:((NSMenuItem*) object).tag == method];
    }
    
    kbHandler = [[KeyboardHandler alloc] init];
    kbHandler.kbMethod = method;
    [self performSelectorInBackground:@selector(eventLoop) withObject:nil];
    
    [self updateStatusItem];
}

-(void)awakeFromNib {
    [super awakeFromNib];
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    statusItem.button.action = @selector(menuItemClicked);
    
    
    viStatusImage = [NSImage imageNamed:@"StatusBarVI"];
    enStatusImage = [NSImage imageNamed:@"StatusBarEN"];
}

#pragma mark Keyboard Handler

CGEventRef KeyHandler(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    UniCharCount actualStringLength;
    UniCharCount maxStringLength = 1;
    UniChar chars[3];
    NSString *activeAppBundleId = [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier;

    uint64_t flag = CGEventGetFlags(event);
    
    if (flag & NAKL_MAGIC_NUMBER) {
        return event;
    }
    
    if ([[AppData sharedAppData].excludedApps objectForKey:activeAppBundleId]) {
        return event;
    }
    
    CGEventKeyboardGetUnicodeString(event, maxStringLength, &actualStringLength, chars);
    UniChar key = chars[0];
    
    switch (type) {
        case kCGEventKeyUp:
            if (rk == key) {
                chars[0] = XK_BackSpace;
                CGEventKeyboardSetUnicodeString(event, actualStringLength, chars);
                rk = 0;
            }
            break;
            
        case kCGEventTapDisabledByTimeout:
            CGEventTapEnable(((__bridge AppDelegate *) refcon).eventTap , TRUE);
            break;
            
        case kCGEventKeyDown:
        {
            ushort keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            
            if (flag & (controlKeys)) {
                bool validShortcut = false;
                if (((flag & controlKeys) == [AppData sharedAppData].toggleCombo.flags) && (keycode == [AppData sharedAppData].toggleCombo.code) )
                {
                    if (kbHandler.kbMethod == VKM_OFF) {
                        kbHandler.kbMethod = (int)[[AppData sharedAppData].userPrefs integerForKey:NAKL_KEYBOARD_METHOD];
                    } else {
                        kbHandler.kbMethod = VKM_OFF;
                    }
                    
                    AppDelegate *appDelegate = (__bridge AppDelegate *) refcon;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [appDelegate updateCheckedItem];
                        [appDelegate updateStatusItem];
                    });
                    validShortcut = true;
                }

                if (((flag & controlKeys) == [AppData sharedAppData].switchMethodCombo.flags) && (keycode == [AppData sharedAppData].switchMethodCombo.code) ){
                    if (kbHandler.kbMethod == VKM_VNI) {
                        kbHandler.kbMethod = VKM_TELEX;
                    } else if (kbHandler.kbMethod == VKM_TELEX) {
                        kbHandler.kbMethod = VKM_VNI;
                    }
                    
                    if (kbHandler.kbMethod != VKM_OFF) {
                        [[AppData sharedAppData].userPrefs setValue:[NSNumber numberWithInt:kbHandler.kbMethod] forKey:NAKL_KEYBOARD_METHOD];
                        AppDelegate *appDelegate = (__bridge AppDelegate *) refcon;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [appDelegate updateCheckedItem];
                            [appDelegate updateStatusItem];
                        });
                    }
                    validShortcut = true;
                }
                
                [kbHandler clearBuffer];
                
                if (validShortcut) return NULL;
                
                break;
            }
            
            /* TODO: Use keycode instead of value of character */
            switch (keycode) {
                case KC_Return:
                case KC_Return_Num:
                case KC_Home:
                case KC_Left:
                case KC_Up:
                case KC_Right:
                case KC_Down:
                case KC_End:
                case KC_Tab:
                case KC_BackSpace:
                case KC_Delete:
                case KC_Page_Up:
                case KC_Page_Down:
                    [kbHandler clearBuffer];
                    break;
                    
                default:
                    
                    if (kbHandler.kbMethod == VKM_OFF) {
                        break;
                    }
                    
                    char *sp = strchr(separators[kbHandler.kbMethod], key);
                    if (sp) {
                        [kbHandler clearBuffer];
                        break;
                    }
                    
                    {
                        int n = [kbHandler addKey:key];
                        if (n <= 0) {
                            break;
                        }
                        const UniChar *buf = [kbHandler replayBuffer];
                        for (int k = 0; k < n; k++) {
                            UniChar ch = buf[k];
                            CGEventRef keyEventDown = CGEventCreateKeyboardEvent(NULL, 1, true);
                            CGEventRef keyEventUp   = CGEventCreateKeyboardEvent(NULL, 1, false);

                            int eflag = (int)CGEventGetFlags(keyEventDown);
                            CGEventSetFlags(keyEventDown, NAKL_MAGIC_NUMBER | eflag);
                            eflag = (int)CGEventGetFlags(keyEventUp);
                            CGEventSetFlags(keyEventUp,   NAKL_MAGIC_NUMBER | eflag);

                            if (ch == '\b') {
                                CGEventSetIntegerValueField(keyEventDown, kCGKeyboardEventKeycode, 0x33);
                                CGEventSetIntegerValueField(keyEventUp,   kCGKeyboardEventKeycode, 0x33);
                            } else {
                                CGEventKeyboardSetUnicodeString(keyEventDown, 1, &ch);
                                CGEventKeyboardSetUnicodeString(keyEventUp,   1, &ch);
                            }

                            CGEventTapPostEvent(proxy, keyEventDown);
                            CGEventTapPostEvent(proxy, keyEventUp);

                            CFRelease(keyEventDown);
                            CFRelease(keyEventUp);
                        }
                        return NULL;
                    }
            }
            break;
        }
            
        case kCGEventLeftMouseDown:
        case kCGEventRightMouseDown:
        case kCGEventOtherMouseDown:
            [kbHandler clearBuffer];
            break;
            
        default:
            break;
    }
    
    return event;
}

- (void) eventLoop {
    CGEventMask        eventMask;
    CFRunLoopSourceRef runLoopSource;
    
    eventMask = ((1 << kCGEventKeyDown) | (1 << kCGEventKeyUp) |
                 (1 << kCGEventLeftMouseDown) |
                 (1 << kCGEventRightMouseDown) |
                 (1 << kCGEventOtherMouseDown)
                 );
    
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0,
                                eventMask, KeyHandler, (__bridge void *)self);
    if (!eventTap) {
        fprintf(stderr, "failed to create event tap\n");
        exit(1);
    }
    
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    CFRunLoopRun();
}

#pragma mark GUI

- (void) updateCheckedItem {
    int method = kbHandler.kbMethod;
    for (id object in [statusMenu itemArray]) {
        [(NSMenuItem*) object setState:((NSMenuItem*) object).tag == method];
    }
}

- (void) updateStatusItem {
    int method = kbHandler.kbMethod;
    switch (method) {
        case VKM_VNI:
        case VKM_TELEX:
            statusItem.button.image = viStatusImage;
            break;

        default:
            statusItem.button.image = enStatusImage;
            break;
    }
}

-(IBAction)showPreferences:(id)sender{
    if(!self.preferencesController)
        self.preferencesController = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    
    [NSApp activateIgnoringOtherApps:YES];
    [self.preferencesController showWindow:self];
    [self.preferencesController.window center];
}

- (IBAction) methodSelected:(id)sender {
    for (id object in [statusMenu itemArray]) {
        [(NSMenuItem*) object setState:NSControlStateValueOff];
    }

    [(NSMenuItem*) sender setState:NSControlStateValueOn];
    
    int method;
    
    if ([[(NSMenuItem*) sender title] compare:@"VNI"] == 0)
    {
        method = VKM_VNI;
    }
    else if ([[(NSMenuItem*) sender title] compare:@"Telex"] == 0)
    {
        method = VKM_TELEX;
    }
    else
    {
        method = VKM_OFF;
    }
    
    kbHandler.kbMethod = method;
    if (method != VKM_OFF)
    {
        [[AppData sharedAppData].userPrefs setValue:[NSNumber numberWithInt:method] forKey:NAKL_KEYBOARD_METHOD];
    }
    
    [self updateStatusItem];
}

#pragma mark -

- (IBAction) quit:(id)sender 
{
    CFRunLoopRef rl = (CFRunLoopRef)CFRunLoopGetCurrent();
    CFRunLoopStop(rl);
    [NSApp terminate:self];
}

@end
