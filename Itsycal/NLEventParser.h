//
//  NLEventParser.h
//  Spidercal
//
//  Turns a line of natural language, e.g.
//  "Flight to Tokyo on 12 Nov at 4pm, New York time",
//  into the details of a new event.
//

#import <Foundation/Foundation.h>

// A time zone's short name on date, like "EST" or "CET". macOS only
// has these in some regions (and says "GMT-5" elsewhere), so this looks
// beyond the user's region before settling for an offset.
NSString *ShortTimeZoneName(NSTimeZone *timeZone, NSDate *date);

@interface NLEventDraft : NSObject
// What is left of the text once dates, times, time zones and the
// location are taken out.
@property (nonatomic, copy) NSString *title;
// nil if the text has no date or time.
@property (nonatomic) NSDate *startDate;
@property (nonatomic) NSDate *endDate;
// The text has a date but no time.
@property (nonatomic) BOOL allDay;
// nil if the text doesn't name a time zone.
@property (nonatomic) NSTimeZone *timeZone;
// nil if the text has no "at <place>".
@property (nonatomic, copy) NSString *location;
// Where the place's name is in the text ({NSNotFound, 0} if none).
@property (nonatomic) NSRange locationRange;
// The parts of the text that were understood (NSRange values).
@property (nonatomic) NSArray<NSValue *> *tokenRanges;
@end

@interface NLEventParser : NSObject
+ (NLEventDraft *)parse:(NSString *)text
               calendar:(NSCalendar *)calendar
                    now:(NSDate *)now
 defaultDurationMinutes:(NSInteger)defaultDurationMinutes;
// The time zone a word or phrase names ("JP", "PST", "Tokyo",
// "Japan"), or nil.
+ (NSTimeZone *)timeZoneForName:(NSString *)name;
// A day typed on its own: "9 Nov", "Nov 9", "9.11.", "9/11", "9-11"
// or "2026-11-09", with or without a year, or "today" or "tomorrow".
// Numbers are read day first or month first as set in Settings
// (kTypedDateOrder). Without a year, it's the date nearest to near.
// Returns the start of that day in calendar, or nil if text isn't
// a date.
+ (NSDate *)dateFromTypedString:(NSString *)text near:(NSDate *)near calendar:(NSCalendar *)calendar;
@end
