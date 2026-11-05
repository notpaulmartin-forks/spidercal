//
//  AppDelegate.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/4/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "Itsycal.h"
#import "ItsycalWindow.h"
#import "ViewController.h"
#import "Themer.h"
#import "Sizer.h"
#import "MoUtils.h"
#import "MASShortcut/Shortcut.h"

@implementation AppDelegate
{
    NSWindowController *_wc;
    ViewController *_vc;
}

+ (void)initialize
{
    // Get the default firstWeekday for user's locale.
    // User can change this in preferences.
    NSCalendar *cal = [NSCalendar autoupdatingCurrentCalendar];
    NSInteger weekStartDOW = MIN(MAX(cal.firstWeekday - 1, 0), 6);
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        kPinItsycal:           @(NO),
        @"FocusNewEventOnOpen": @(YES), // Spidercal; see ViewController.m
        kShowWeeks:            @(NO),
        kHighlightedDOWs:      @0,
        kShowEventDays:        @7,
        kWeekStartDOW:         @(weekStartDOW), // Sun=0, Mon=1,... (MoCalendar.h)
        kShowMonthInIcon:      @(NO),
        kShowDayOfWeekInIcon:  @(NO),
        kShowEventDots:        @(YES),
        kUseColoredDots:       @(YES),
        kThemePreference:      @0, // System=0, Light=1, Dark=2
        kHideIcon:             @(NO),
        kShowLocation:         @(NO),
        kSizePreference:       @0, // Small=0, Medium=1, Large=2
        kShowDaysWithNoEventsInAgenda: @(NO),
        kShowCompletedReminders: @(YES), // Calendar's default
        kShowOverdueReminders: @(YES),
        kOverdueSectionExpanded: @(NO),
        kDoNotDrawOutlineAroundCurrentMonth: @(NO),
        kShowMeetingIndicator: @(NO),
        kBaselineOffset:       @0,  // Clamped to -2.0...2.0
        kEnableMeetingButtonIndefinitely: @(NO),
        kShowEventPopoverOnHover: @(NO),
        kAllowOutsideApplicationsFolder: @(NO),
        kDoNotCheckLoginItemStatus: @(NO),
        kWindowPosition:       @(WindowPositionBelowMenuBarIcon),
        // Disable AppKit's scroll edge effect (macOS 27), which draws a
        // hairline under the floating date header in the agenda.
        @"NSScrollPocketEnabled": @(NO),
    }];
    
    // Constrain kShowEventDays to values 0...9 in (unlikely) case it is invalid.
    // Only write if invalid: a value passed as a launch argument
    // must not end up saved as the user's setting.
    NSInteger showEventDays = [defaults integerForKey:kShowEventDays];
    NSInteger validDays = MIN(MAX(showEventDays, 0), 9);
    if (validDays != showEventDays) {
        [defaults setInteger:validDays forKey:kShowEventDays];
    }
    
    // Set kThemePreference to system in the unlikely case it's invalid.
    NSInteger themePref = [defaults integerForKey:kThemePreference];
    if (themePref < ThemePreferenceSystem || themePref > ThemePreferenceDark) {
        [defaults setInteger:ThemePreferenceSystem forKey:kThemePreference];
    }

    // Set kSizePreference to small in the unlikely case it's invalid.
    NSInteger sizePref = [defaults integerForKey:kSizePreference];
    if (sizePref < SizePreferenceSmall || sizePref > SizePreferenceLarge) {
        [defaults setInteger:SizePreferenceSmall forKey:kSizePreference];
    }

    // Set kWindowPosition to below menu bar icon in the unlikely case it's invalid.
    NSInteger windowPosition = [defaults integerForKey:kWindowPosition];
    if (windowPosition != WindowPositionBelowMenuBarIcon && windowPosition != WindowPositionTopRightOfScreen) {
        [defaults setInteger:WindowPositionBelowMenuBarIcon forKey:kWindowPosition];
    }
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    NSApp.mainMenu = [self mainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Ensure the user has moved Itsycal to the /Applications folder.
    // Having the user manually move Itsycal to /Applications turns off
    // Gatekeeper Path Randomization (introduced in 10.12).
#ifndef DEBUG
    [self checkIfRunFromApplicationsFolder];
#endif

    // Initialize the 'Theme' global variable which can be
    // used throught the app instead of '[Themer shared]'.
    [Themer shared];

    // Initialize the 'SizePref' global variable which can be
    // used throught the app instead of '[Sizer shared]'.
    [Sizer shared];

    // Create our Application Support folder if it doesn't exist.
    // ~/Library/Application Support/com.mowglii.ItsycalApp/
    NSURL *url = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    if (url) {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        url = [url URLByAppendingPathComponent:bundleID isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    // Register keyboard shortcut.
    [[MASShortcutBinder sharedBinder] setBindingOptions:@{NSValueTransformerNameBindingOption: MASDictionaryTransformerName}];
    [[MASShortcutBinder sharedBinder] bindShortcutWithDefaultsKey:kKeyboardShortcut toAction:^{
         [self->_vc keyboardShortcutActivated];
     }];

    // Establish the binding to NSUserDefaultsController. This call
    // must be made BEFORE the window is created because sizes are
    // used when initializing views.
    [SizePref bind:@"sizePreference" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kSizePreference] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // The window's contentView draws the window, so put the view
    // controller's view inside it rather than setting the window's
    // contentViewController (which would replace the contentView).
    _vc = [ViewController new];
    _wc = [[NSWindowController alloc] initWithWindow:[ItsycalWindow  new]];
    NSView *contentView = _wc.window.contentView;
    NSLayoutGuide *safeArea = contentView.safeAreaLayoutGuide;
    [contentView addSubview:_vc.view];
    [NSLayoutConstraint activateConstraints:@[
        [_vc.view.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [_vc.view.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [_vc.view.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [_vc.view.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
    ]];
    _wc.window.delegate = _vc;
    
    // Establish the binding to NSUserDefaultsController. On macOS
    // 10.14+, it is crucial for this call to be made AFTER the window
    // is created because Theme instantiation relies on checking a
    // property on the window to determine its appearance.
    [Theme bind:@"themePreference" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kThemePreference] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

#ifdef DEBUG
    [self snapshotForTestingIfRequested];
#endif
}

#ifdef DEBUG
// Development aid, Debug builds only. Run with the environment
// variable SPIDERCAL_SNAPSHOT=/path/to.png to open the window,
// optionally type SPIDERCAL_TYPE into the New Event field (and
// show the details if SPIDERCAL_EXPAND is set, and type
// SPIDERCAL_LOCATION into its location field) or SPIDERCAL_SEARCH
// into the Search field, save a picture of the window and quit.
// SPIDERCAL_FIXTURE=1 uses sample events (see EventCenter.m).
// Theme and size: pass -ThemePreference 0|1|2 -SizePreference 0|1|2.
- (void)snapshotForTestingIfRequested
{
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *path = env[@"SPIDERCAL_SNAPSHOT"];
    if (!path) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_vc keyboardShortcutActivated];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSWindow *window = self->_wc.window;
            id quick = [self->_vc valueForKey:@"_quickVC"];
            if (env[@"SPIDERCAL_SEARCH"]) {
                [quick performSelector:@selector(focusSearch)];
                [(NSText *)[window fieldEditor:YES forObject:nil] insertText:env[@"SPIDERCAL_SEARCH"]];
            }
            else if (env[@"SPIDERCAL_TYPE"]) {
                [quick performSelector:@selector(focusEntry)];
                id responder = window.firstResponder;
                if ([responder isKindOfClass:[NSTextView class]]) {
                    [(NSTextView *)responder insertText:env[@"SPIDERCAL_TYPE"] replacementRange:NSMakeRange(NSNotFound, 0)];
                }
                if (env[@"SPIDERCAL_EXPAND"]) {
                    [quick performSelector:NSSelectorFromString(@"toggleExpanded:") withObject:nil];
                }
                if (env[@"SPIDERCAL_LOCATION"]) {
                    // Type into the details form's location field.
                    NSTextField *location = [[quick valueForKey:@"_eventVC"] valueForKey:@"_location"];
                    [window makeFirstResponder:location];
                    NSTextView *editor = (NSTextView *)location.currentEditor;
                    [editor insertText:env[@"SPIDERCAL_LOCATION"] replacementRange:NSMakeRange(NSNotFound, 0)];
                }
            }
            if (env[@"SPIDERCAL_DRAG"] || env[@"SPIDERCAL_DOUBLECLICK"]) {
                // Drive the agenda's handle with real mouse events.
                NSView *handle = [self->_vc valueForKey:@"_agendaHandle"];
                NSPoint start = [handle convertPoint:NSMakePoint(NSMidX(handle.bounds), 2) toView:nil];
                NSView *hit = [window.contentView.superview hitTest:start];
                NSLog(@"edge strip height=%.0f, click 2pt above the window's bottom edge lands on: %@", NSHeight(handle.frame), hit.className);
                NSEvent* (^mouse)(NSEventType, NSPoint, NSInteger) = ^NSEvent* (NSEventType type, NSPoint point, NSInteger clicks) {
                    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:clicks pressure:1];
                };
                if (env[@"SPIDERCAL_DOUBLECLICK"]) {
                    [handle mouseDown:mouse(NSEventTypeLeftMouseDown, start, 2)];
                    [handle mouseUp:mouse(NSEventTypeLeftMouseUp, start, 2)];
                }
                else {
                    CGFloat dy = [env[@"SPIDERCAL_DRAG"] doubleValue]; // positive is down
                    NSPoint end = NSMakePoint(start.x, start.y - dy);
                    [handle mouseDown:mouse(NSEventTypeLeftMouseDown, start, 1)];
                    [handle mouseDragged:mouse(NSEventTypeLeftMouseDragged, end, 1)];
                    [handle mouseUp:mouse(NSEventTypeLeftMouseUp, end, 1)];
                }
            }
            if (env[@"SPIDERCAL_PREFS"]) {
                [self->_vc performSelector:@selector(showPrefs:) withObject:nil];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSView *contentView = window.contentView;
                // The pin only kept the window open for the snapshot.
                ((NSButton *)[self->_vc valueForKey:@"_btnPin"]).state = NSControlStateValueOff;
                if (env[@"SPIDERCAL_NOFOCUS"]) [window makeFirstResponder:nil];
                [contentView displayIfNeeded];
                // Render the layers, as the window shows them, on a
                // transparent background to keep the window's shape.
                CGFloat scale = window.backingScaleFactor;
                NSSize size = contentView.bounds.size;
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size.width * scale pixelsHigh:size.height * scale bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                CGContextRef context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep].CGContext;
                CGContextScaleCTM(context, scale, scale);
                [contentView.layer renderInContext:context];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
                NSLog(@"snapshot %@ window=%@ firstResponder=%@", path, NSStringFromRect(window.frame), window.firstResponder.className);
                exit(0);
            });
        });
    });
}
#endif

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [_vc removeStatusItem];
    [[MASShortcutMonitor sharedMonitor] unregisterAllShortcuts];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count >= 1) {
        // We can only handle showing one date at a time, so we pick the first one
        NSURL *url = urls[0];
        if ([url.host isEqualToString:@"date"] && url.pathComponents.count == 2) {
            NSString *dateString = url.pathComponents[1];
            
            if ([dateString isEqualToString:@"now"]) {
                [_vc dateURLReceived:[NSDate new]];
            } else {
                NSDateFormatter *format = [NSDateFormatter new];
                format.dateFormat = @"yyyy-MM-dd";
                NSDate *date = [format dateFromString:dateString];
                
                if (date) {
                    [_vc dateURLReceived:date];
                }
            }
        }
    }
}

#pragma mark -
#pragma mark Applications folder check

- (void)checkIfRunFromApplicationsFolder
{
    // This check can be short-circuited.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAllowOutsideApplicationsFolder]) {
        return;
    }
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSArray *applicationDirs = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask | NSUserDomainMask, YES);
    for (NSString *appDir in applicationDirs) {
        if ([bundlePath hasPrefix:appDir]) {
            return; // Ok, Itsycal is being run from /Applications.
        }
    }
    // Itsycal is not being run from /Applications.
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Move Spidercal to the Applications folder", nil);
    alert.informativeText = [NSLocalizedString(@"Spidercal must be run from the Applications folder in order to work properly.\n\nPlease quit Spidercal, move it to the Applications folder, and relaunch.", nil) stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", bundlePath]];
    alert.icon = [NSImage imageNamed:@"move"];
    alert.showsHelp = YES;
    alert.delegate = self;
    [alert addButtonWithTitle:NSLocalizedString(@"Quit Spidercal", @"")];
    [alert runModal];
    [NSApp terminate:nil];
}

#pragma mark -
#pragma mark Main menu

// Itsycal is a menu bar app, so its main menu is never shown. But
// AppKit uses the main menu to handle standard keyboard shortcuts
// like ⌘C, ⌘V, ⌘Z, ⌘A, ⌘W, and ⌘Q. Since it's never shown, all the
// items go in a single submenu, and the titles aren't localized.
- (NSMenu *)mainMenu
{
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Quit Spidercal" action:@selector(terminate:) keyEquivalent:@"q"];
    [menu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    // AppKit implements undo: and redo: (in NSWindow and NSTextView),
    // but no public header declares them, so look them up by name.
    [menu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
    [menu addItemWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"Z"];
    [menu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [menu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [menu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    NSMenuItem *pasteAsPlainText = [menu addItemWithTitle:@"Paste and Match Style" action:@selector(pasteAsPlainText:) keyEquivalent:@"v"];
    pasteAsPlainText.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand;
    [menu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    NSMenu *mainMenu = [NSMenu new];
    [mainMenu addItemWithTitle:@"" action:NULL keyEquivalent:@""].submenu = menu;
    return mainMenu;
}

- (BOOL)alertShowHelp:(NSAlert *)alert
{
    NSURL *url = [NSURL URLWithString:@"https://mowglii.com/itsycal/appfolder.html"];
    [[NSWorkspace sharedWorkspace] openURL:url];
    return YES;
}

@end
