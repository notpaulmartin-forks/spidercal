//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsGeneralVC.h"
#import "Itsycal.h"
#import "MoLoginItem.h"
#import "MoVFLHelper.h"
#import "MASShortcut/Shortcut.h"

@implementation PrefsGeneralVC
{
    NSButton *_login;
}

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];

    // Convenience function for making labels.
    NSTextField* (^label)(NSString*) = ^NSTextField* (NSString *stringValue) {
        NSTextField *txt = [NSTextField labelWithString:stringValue];
        [v addSubview:txt];
        return txt;
    };

    // Convenience function for making checkboxes.
    NSButton* (^chkbx)(NSString *) = ^NSButton* (NSString *title) {
        NSButton *chkbx = [NSButton checkboxWithTitle:title target:self action:nil];
        [v addSubview:chkbx];
        return chkbx;
    };

    // Checkboxes
    _login = chkbx(NSLocalizedString(@"Launch at login", @""));
    _login.action = @selector(launchAtLogin:);
    NSButton *beepBeep = chkbx(NSLocalizedString(@"Beep beep on the hour", @""));

    // Shortcut label
    NSTextField *shortcutLabel = label(NSLocalizedString(@"Keyboard shortcut", @""));

    // Shortcut view
    MASShortcutView *shortcutView = [MASShortcutView new];
    [shortcutView setAssociatedUserDefaultsKey:kKeyboardShortcut withTransformerName:MASDictionaryTransformerName];
    [v addSubview:shortcutView];

    // Window position label
    NSTextField *positionLabel = label(NSLocalizedString(@"Window position:", @""));

    // Window position popup
    NSPopUpButton *positionPopup = [NSPopUpButton new];
    [positionPopup addItemsWithTitles:@[NSLocalizedString(@"Below menu bar icon", @""),
                                        NSLocalizedString(@"Top right of screen", @"")]];
    // The tags will be used to bind the selected window
    // position preference to NSUserDefaults.
    [positionPopup itemAtIndex:0].tag = WindowPositionBelowMenuBarIcon;
    [positionPopup itemAtIndex:1].tag = WindowPositionTopRightOfScreen;
    [positionPopup.cell setAccessibilityTitleUIElement:positionLabel.cell];
    [v addSubview:positionPopup];

    // Typed dates: how the numbers in a date like 6/11, typed in quick
    // add or in an event's details, are read.
    NSTextField *dateOrderLabel = label(NSLocalizedString(@"Typed dates:", @"Settings label: how dates typed as numbers, like 6/11, are read"));
    NSPopUpButton *dateOrderPopup = [NSPopUpButton new];
    [dateOrderPopup addItemsWithTitles:@[NSLocalizedString(@"Day/Month (31/12)", @"Settings: typed dates like 6/11 are read day first"),
                                         NSLocalizedString(@"Month/Day (12/31)", @"Settings: typed dates like 6/11 are read month first")]];
    [dateOrderPopup itemAtIndex:0].tag = TypedDateOrderDayMonth;
    [dateOrderPopup itemAtIndex:1].tag = TypedDateOrderMonthDay;
    [dateOrderPopup.cell setAccessibilityTitleUIElement:dateOrderLabel.cell];
    [v addSubview:dateOrderPopup];

    // Spidercal: quitting is here rather than in a menu under the
    // window's gear button, which now opens Settings. (⌘Q works too.)
    NSButton *quit = [NSButton buttonWithTitle:NSLocalizedString(@"Quit Spidercal", @"") target:NSApp action:@selector(terminate:)];
    [v addSubview:quit];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @20} views:NSDictionaryOfVariableBindings(_login, beepBeep, shortcutLabel, shortcutView, positionLabel, positionPopup, dateOrderLabel, dateOrderPopup, quit)];
    [vfl :@"V:|-m-[_login]-[beepBeep]-m-[shortcutLabel]-3-[shortcutView(25)]-30-[positionPopup]-[dateOrderPopup]-30-[quit]-m-|"];
    [vfl :@"H:|-m-[quit]-(>=m)-|"];
    [vfl :@"H:|-m-[_login]-(>=m)-|"];
    [vfl :@"H:|-m-[beepBeep]-(>=m)-|"];
    [vfl :@"H:|-(>=m)-[shortcutLabel]-(>=m)-|"];
    [vfl :@"H:|-m-[shortcutView(>=220)]-m-|"];
    [vfl :@"H:|-(>=m)-[positionLabel]-[positionPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-(>=m)-[dateOrderLabel]-[dateOrderPopup]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];
    // The labels end, and the popups start, at the same place, and
    // the longer label starts at the margin.
    [v addConstraint:[positionLabel.trailingAnchor constraintEqualToAnchor:dateOrderLabel.trailingAnchor]];
    for (NSTextField *label in @[positionLabel, dateOrderLabel]) {
        NSLayoutConstraint *atMargin = [label.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20];
        atMargin.priority = 200;
        atMargin.active = YES;
    }

    // Center shortcutLabel
    [v addConstraint:[NSLayoutConstraint constraintWithItem:shortcutLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:v attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];


    // Binding for hourly beep
    [beepBeep bind:@"value" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kBeepBeepOnTheHour] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // Bindings for window position
    [positionPopup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWindowPosition] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [dateOrderPopup bind:@"selectedTag" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kTypedDateOrder] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    // The API used to check the login item's state (LSSharedFileList) causes
    // errors for users who have network drives but are not connected to their
    // network (github.com/sfsam/Itsycal/issues/15). Give them an option to
    // disable this check.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDoNotCheckLoginItemStatus] == NO) {
        _login.hidden = NO;
        _login.state = MOIsLoginItemEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    }
    else {
        _login.hidden = YES;
    }
}

#pragma mark -
#pragma mark Login item

- (void)launchAtLogin:(NSButton *)login
{
    MOEnableLoginItem(login.state == NSControlStateValueOn);
}

@end
