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

#import "AppData.h"
#import <AppKit/AppKit.h>
#import "PTHotKey.h"
#import "NSFileManager+DirectoryLocations.h"
#import "ShortcutSetting.h"

static NSString * const kNAKLMigrationFromZepvnCompleteKey = @"NAKLMigrationFromZepvnComplete";
static NSString * const kLegacyDefaultsSuite = @"com.zepvn.NAKL";
static NSString * const kLegacyAppSupportDir = @"Library/Application Support/NAKL";

@implementation AppData

+ (instancetype)sharedAppData
{
    static AppData *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (void) loadUserPrefs
{
    [AppData sharedAppData].userPrefs = [NSUserDefaults standardUserDefaults];
}

+ (void) loadHotKeys
{
    NSDictionary *dictionary = [[AppData sharedAppData].userPrefs dictionaryForKey:NAKL_TOGGLE_HOTKEY];
    PTKeyCombo *keyCombo = [[PTKeyCombo alloc] initWithPlistRepresentation:dictionary];
    [AppData sharedAppData].toggleCombo = SRMakeKeyCombo([keyCombo keyCode], [keyCombo modifiers]);

    dictionary = [[AppData sharedAppData].userPrefs dictionaryForKey:NAKL_SWITCH_METHOD_HOTKEY];
    keyCombo = [[PTKeyCombo alloc] initWithPlistRepresentation:dictionary];
    [AppData sharedAppData].switchMethodCombo = SRMakeKeyCombo([keyCombo keyCode], [keyCombo modifiers]);
}

+ (void) loadShortcuts
{
    NSString *filePath = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"shortcuts.setting"];
    [AppData sharedAppData].shortcuts = [[NSMutableArray alloc] init];
    [AppData sharedAppData].shortcutDictionary = [[NSMutableDictionary alloc] init];

    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (fileData != nil) {
        NSError *err = nil;
        NSKeyedUnarchiver *outer = [[NSKeyedUnarchiver alloc] initForReadingFromData:fileData error:&err];
        outer.requiresSecureCoding = NO;
        NSData *innerData = [outer decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        [outer finishDecoding];

        if (innerData != nil) {
            NSKeyedUnarchiver *inner = [[NSKeyedUnarchiver alloc] initForReadingFromData:innerData error:&err];
            inner.requiresSecureCoding = NO;
            NSArray *savedArray = [inner decodeObjectForKey:NSKeyedArchiveRootObjectKey];
            [inner finishDecoding];

            if (savedArray != nil) {
                [[AppData sharedAppData].shortcuts setArray:savedArray];
            }
        }
    }

    for (ShortcutSetting *s in [AppData sharedAppData].shortcuts) {
        [[AppData sharedAppData].shortcutDictionary setObject:s.text forKey:s.shortcut];
    }
}

+ (void) loadExcludedApps
{
    [AppData sharedAppData].excludedApps = [[NSMutableDictionary alloc] init];
    NSDictionary *excludedApps = [[AppData sharedAppData].userPrefs dictionaryForKey:NAKL_EXCLUDED_APPS];
    if (excludedApps != nil) {
        [[AppData sharedAppData].excludedApps setDictionary:excludedApps];
    }
}

+ (void) migrateLegacyDataIfNeeded
{
    NSUserDefaults *current = [NSUserDefaults standardUserDefaults];
    if ([current boolForKey:kNAKLMigrationFromZepvnCompleteKey]) return;

    NSUserDefaults *legacy = [[NSUserDefaults alloc]
                              initWithSuiteName:kLegacyDefaultsSuite];

    BOOL legacyHasData = ([legacy objectForKey:NAKL_KEYBOARD_METHOD] != nil);
    BOOL currentIsEmpty = ([current objectForKey:NAKL_KEYBOARD_METHOD] == nil);

    if (legacyHasData && currentIsEmpty) {
        NSArray<NSString *> *keys = @[NAKL_KEYBOARD_METHOD,
                                      NAKL_LOAD_AT_LOGIN,
                                      NAKL_TOGGLE_HOTKEY,
                                      NAKL_SWITCH_METHOD_HOTKEY,
                                      NAKL_EXCLUDED_APPS];
        for (NSString *key in keys) {
            id value = [legacy objectForKey:key];
            if (value != nil) {
                [current setObject:value forKey:key];
            }
        }

        if ([legacy boolForKey:NAKL_LOAD_AT_LOGIN]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(
                    @"Re-enable Load at Login",
                    @"Migration prompt title shown after rebrand from NAKL to Monke when the user previously had load-at-login enabled.");
                alert.informativeText = NSLocalizedString(
                    @"Monke was previously installed under a different identity. macOS treats the renamed app as a separate background item, so open Preferences and toggle Load at Login once more to keep it starting at boot.",
                    @"Migration prompt body explaining why load-at-login does not transfer across bundle-ID renames.");
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
            });
        }
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *legacyPath = [NSHomeDirectory()
        stringByAppendingPathComponent:
            [kLegacyAppSupportDir stringByAppendingPathComponent:@"shortcuts.setting"]];
    NSString *newDir = [fm applicationSupportDirectory];
    NSString *newPath = [newDir stringByAppendingPathComponent:@"shortcuts.setting"];
    if ([fm fileExistsAtPath:legacyPath] && ![fm fileExistsAtPath:newPath]) {
        NSError *copyError = nil;
        [fm copyItemAtPath:legacyPath toPath:newPath error:&copyError];
        if (copyError) {
            NSLog(@"[Monke] shortcut migration failed: %@", copyError);
        }
    }

    [current setBool:YES forKey:kNAKLMigrationFromZepvnCompleteKey];
}

@end
