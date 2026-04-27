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

#import "PreferencesController.h"
#import "ShortcutRecorder/SRRecorderControl.h"
#import "PTHotKeyCenter.h"
#import "PTHotKey.h"
#import "NSFileManager+DirectoryLocations.h"
#import <ServiceManagement/SMAppService.h>

@implementation PreferencesController

@synthesize toggleHotKey = _toggleHotKey;
@synthesize switchMethodHotKey = _switchMethodHotKey;
@synthesize versionString;
@synthesize shortcuts;

-(id)init {
    if (![super initWithWindowNibName:@"Preferences"])
        return nil;
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    NSString *buildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    
    self.versionString = [NSString stringWithFormat:@"Version %@ (build %@)", version, buildNumber];
    
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.toggleHotKey setKeyCombo: [AppData sharedAppData].toggleCombo];
    [self.switchMethodHotKey setKeyCombo: [AppData sharedAppData].switchMethodCombo];

    [self.shortcuts setContent:[AppData sharedAppData].shortcuts];

    // Sync the Cocoa-bound `startAtLogin` user-defaults key with system reality.
    // The checkbox is bound to values.startAtLogin (see Preferences.xib); without
    // this seeding it would show whatever was last persisted, not what SMAppService
    // actually reports.
    BOOL enabled = ([SMAppService mainAppService].status == SMAppServiceStatusEnabled);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"startAtLogin"];
}

- (void)windowWillClose :(NSNotification *)notification
{
    [self saveSetting];
}

- (BOOL)shortcutRecorder:(SRRecorderControl *)aRecorder isKeyCode:(NSInteger)keyCode andFlagsTaken:(NSUInteger)flags reason:(NSString **)aReason
{
    return NO;
}

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
    PTKeyCombo *keyCombo = [[PTKeyCombo alloc] initWithKeyCode:newKeyCombo.code modifiers:newKeyCombo.flags];
    if (aRecorder == self.toggleHotKey) {
        [[AppData sharedAppData].userPrefs setObject:[keyCombo plistRepresentation] forKey:NAKL_TOGGLE_HOTKEY];
        [AppData sharedAppData].toggleCombo = newKeyCombo;
    } else {
        [[AppData sharedAppData].userPrefs setObject:[keyCombo plistRepresentation] forKey:NAKL_SWITCH_METHOD_HOTKEY];
        [AppData sharedAppData].switchMethodCombo = newKeyCombo;
    }
}

- (IBAction) startupOptionClick:(id)sender
{
    NSButton *button = (NSButton *)sender;
    BOOL wantEnabled = (button.state == NSControlStateValueOn);
    SMAppService *service = [SMAppService mainAppService];
    NSError *err = nil;
    BOOL ok = wantEnabled
        ? [service registerAndReturnError:&err]
        : [service unregisterAndReturnError:&err];

    if (ok) return;

    // Failure path: revert the bound user-defaults value (the binding flips
    // the checkbox back) and tell the user why. Common failure: user denied
    // the macOS background-item prompt.
    [[NSUserDefaults standardUserDefaults] setBool:!wantEnabled forKey:@"startAtLogin"];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = wantEnabled
        ? NSLocalizedString(@"Could not enable Load at Login", nil)
        : NSLocalizedString(@"Could not disable Load at Login", nil);
    alert.informativeText = err.localizedDescription ?: @"Unknown error";
    [alert runModal];
}

- (void) saveSetting
{
    NSString *filePath = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"shortcuts.setting"];

    // Preserve the historical nested-archive wire format that AppData.loadShortcuts
    // expects: outer archive whose root is an NSData containing an inner archive
    // of the shortcuts NSMutableArray. requiringSecureCoding:NO matches the load
    // side; promoting to YES would force ShortcutSetting to adopt NSSecureCoding.
    NSError *err = nil;
    NSData *innerData = [NSKeyedArchiver archivedDataWithRootObject:[AppData sharedAppData].shortcuts
                                              requiringSecureCoding:NO
                                                              error:&err];
    NSData *outerData = innerData ? [NSKeyedArchiver archivedDataWithRootObject:innerData
                                                          requiringSecureCoding:NO
                                                                          error:&err] : nil;
    if (outerData) {
        [outerData writeToURL:[NSURL fileURLWithPath:filePath]
                      options:NSDataWritingAtomic
                        error:&err];
    }
    if (err) {
        NSLog(@"NAKL: failed to save shortcuts.setting: %@", err);
    }

    [[AppData sharedAppData].shortcutDictionary removeAllObjects];
    for (ShortcutSetting *s in [AppData sharedAppData].shortcuts) {
        [[AppData sharedAppData].shortcutDictionary setObject:s.text forKey:s.shortcut];
    }
}

@end