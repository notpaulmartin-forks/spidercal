//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsAboutVC.h"
#import "Itsycal.h"
#import "MoTextField.h"
#import "MoVFLHelper.h"

@implementation PrefsAboutVC

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    NSView *v = [NSView new];

    // The content goes in a box that hugs it. The box is centered
    // so the content stays centered when the Settings window is
    // wider than the content (see PrefsVC).
    NSView *box = [NSView new];
    [v addSubview:box];

    // Convenience function for making labels.
    MoTextField* (^label)(NSString*, BOOL) = ^MoTextField* (NSString *stringValue, BOOL isLink) {
        MoTextField *txt = [MoTextField labelWithString:stringValue];
        if (isLink) {
            txt.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            txt.linkEnabled = YES;
        }
        [box addSubview:txt];
        return txt;
    };

    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSTextField *appName = label(@"Spidercal", NO);
    appName.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];

    NSTextField *version = label([NSString stringWithFormat:@"%@ (%@)", infoDict[@"CFBundleShortVersionString"], infoDict[@"CFBundleVersion"]], NO);
    version.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    version.textColor = [NSColor secondaryLabelColor];

    // Spidercal is a fork, not Mowglii's app: say so, and link to
    // both projects. The Help, Follow and Donate links were Mowglii's.
    NSTextField *fork = label(NSLocalizedString(@"An unofficial fork of Itsycal", @"Under the app's name in Settings › About"), NO);
    fork.textColor = [NSColor secondaryLabelColor];

    MoTextField *github = label(NSLocalizedString(@"Spidercal on GitHub", @"Link in Settings › About"), YES);
    github.urlString = @"https://github.com/notpaulmartin-forks/spidercal";

    MoTextField *itsycal = label(NSLocalizedString(@"Itsycal by Mowglii", @"Link to the original app's website in Settings › About"), YES);
    itsycal.urlString = @"https://www.mowglii.com/itsycal/";

    MoTextField *donate = label(NSLocalizedString(@"Donate to Itsycal's developer", @"Link in Settings › About"), YES);
    donate.urlString = @"https://mowglii.com/donate/";

    NSTextField *emojiGitHub  = label(@"🐙", NO);
    NSTextField *emojiItsycal = label(@"📅", NO);
    NSTextField *emojiDonate  = label(@"♥️", NO);

    // The emoji are decorative, so VoiceOver skips them.
    [emojiGitHub.cell setAccessibilityElement:NO];
    [emojiItsycal.cell setAccessibilityElement:NO];
    [emojiDonate.cell setAccessibilityElement:NO];

    // Itsycal's copyright, as in its licence (LICENSE.txt).
    NSTextField *copyright = label(@"Itsycal © 2012—2026 Sanjay Madan", NO);
    copyright.textColor = [NSColor secondaryLabelColor];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:box metrics:@{@"m": @25} views:NSDictionaryOfVariableBindings(appName, version, fork, github, emojiGitHub, itsycal, emojiItsycal, donate, emojiDonate, copyright)];
    [vfl :@"V:|[appName]-4-[fork]-m-[github]-10-[itsycal]-10-[donate]-m-[copyright]|"];
    [vfl :@"H:|[appName]-4-[version]-(>=0)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|[fork]-(>=0)-|"];
    [vfl :@"H:|[emojiGitHub]-6-[github]-(>=0)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|[emojiItsycal]-6-[itsycal]-(>=0)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|[emojiDonate]-6-[donate]-(>=0)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|[copyright]-(>=0)-|"];

    MoVFLHelper *outer = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @25} views:NSDictionaryOfVariableBindings(box)];
    [outer :@"V:|-m-[box]-m-|"];
    [outer :@"H:|-(>=m)-[box]-(>=m)-|"];
    [box.centerXAnchor constraintEqualToAnchor:v.centerXAnchor].active = YES;

    // Make the box as narrow as its content allows.
    NSLayoutConstraint *hug = [box.widthAnchor constraintEqualToConstant:0];
    hug.priority = 1;
    hug.active = YES;

    self.view = v;
}

@end
